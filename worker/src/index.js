// Sync backend: a Cloudflare Worker over D1, serving the PWA from the same
// origin so the app and the API never need CORS.
//
// The server is a relay with a total order, not a second application. It stores
// rows opaquely, decides staleness by `version` alone, and never interprets a
// name, a colour or a timestamp. Everything that reasons about the data lives in
// the client, which already holds an authoritative offline-first copy — so a
// server that "helpfully" merged fields could only disagree with it.
//
// Endpoints:
//   POST /account     claim an account for a sync token
//   POST /sync        push + pull in one round trip
//   GET  /export.csv  the whole timeline as CSV, for a spreadsheet or a script
//   *                 the PWA, served from static assets
//
// ## Accounts
//
// A sync token *is* an account: generated on the first device, entered on the
// others to join. No usernames, no reset flow, no third party — which suits a
// handful of people who know each other, and is the whole security boundary.
//
// Only the token's hash is stored, so a database dump does not hand over
// anyone's data. It is a plain SHA-256 rather than a slow password hash on
// purpose: a generated token has far more entropy than a password, so there is
// nothing to brute force, and this runs on every request.

const MAX_PAGE = 500;

const API_PATHS = new Set(['/sync', '/export.csv', '/account']);

export default {
  async fetch(request, env) {
    const url = new URL(request.url);

    // Anything that is not an API route is the PWA. Note the order: the token
    // gates the *API*, not the app. Authorising first would 401 every static
    // file, which is how the first deploy served nothing but "unauthorized".
    if (!API_PATHS.has(url.pathname)) {
      if (env.ASSETS) return env.ASSETS.fetch(request);
      return json({ error: 'not found' }, 404);
    }

    try {
      const token = presentedToken(request, url);
      if (!token) return json({ error: 'unauthorized' }, 401);

      if (url.pathname === '/account' && request.method === 'POST') {
        return await handleClaimAccount(token, env);
      }

      const account = await accountFor(token, env);
      // An unknown token is indistinguishable from a wrong one, deliberately:
      // "no such account" would confirm which tokens exist.
      if (!account) return json({ error: 'unauthorized' }, 401);

      if (url.pathname === '/sync' && request.method === 'POST') {
        return await handleSync(request, env, account);
      }
      if (url.pathname === '/export.csv' && request.method === 'GET') {
        return await handleExport(env, account);
      }
      return json({ error: 'not found' }, 404);
    } catch (e) {
      return json({ error: String(e && e.message ? e.message : e) }, 500);
    }
  },
};

/**
 * Bearer token, or `?token=` for the export URL — a spreadsheet fetching a CSV
 * cannot set headers.
 */
function presentedToken(request, url) {
  const header = request.headers.get('authorization') || '';
  const bearer = header.startsWith('Bearer ') ? header.slice(7) : '';
  const token = bearer || url.searchParams.get('token') || '';
  // A short token is not a token. This is also what stops an empty string
  // matching an empty hash somewhere downstream.
  return token.length >= 16 ? token : '';
}

async function hashToken(token) {
  const digest = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(token));
  return [...new Uint8Array(digest)].map((b) => b.toString(16).padStart(2, '0')).join('');
}

async function accountFor(token, env) {
  const hash = await hashToken(token);
  return env.DB.prepare('SELECT id, next_seq FROM accounts WHERE token_hash = ?').bind(hash).first();
}

/**
 * Claim an account for a token, or confirm it is already claimed.
 *
 * Idempotent so a client that generated a token and lost the response can retry,
 * and so entering an existing token on a second device succeeds rather than
 * colliding. Anyone can create an account — there is nothing to gate it with,
 * and an account is worth nothing without its token.
 */
async function handleClaimAccount(token, env) {
  const existing = await accountFor(token, env);
  if (existing) return json({ accountId: existing.id, created: false });

  const id = crypto.randomUUID();
  await env.DB.prepare('INSERT INTO accounts (id, token_hash, created_at, next_seq) VALUES (?, ?, ?, 1)')
    .bind(id, await hashToken(token), Date.now())
    .run();
  return json({ accountId: id, created: true });
}

async function handleSync(request, env, account) {
  const body = await request.json();
  const cursor = Number.parseInt(body.cursor ?? '0', 10) || 0;
  const activities = Array.isArray(body.activities) ? body.activities : [];
  const changes = Array.isArray(body.changes) ? body.changes : [];

  const rejected = [];
  let seq = await nextSeq(env, account, activities.length + changes.length);

  for (const dto of activities) {
    if (!validActivity(dto)) continue;
    const stored = await env.DB.prepare(
      'SELECT version FROM activities WHERE account_id = ? AND sync_id = ?',
    )
      .bind(account.id, dto.syncId)
      .first();
    // Accepting the *equal* case is what makes concurrent edits converge: two
    // devices that both edited version 3 both arrive with 4, and whoever gets
    // here last wins. Deterministic, and the loser learns about it on its pull.
    if (stored && dto.version < stored.version) {
      rejected.push(dto.syncId);
      continue;
    }
    await env.DB.prepare(
      `INSERT INTO activities
         (account_id, sync_id, parent_id, name, color, bookmarked, last_used_at, external_id, aliases, version, deleted_at, seq)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
       ON CONFLICT(account_id, sync_id) DO UPDATE SET
         parent_id = excluded.parent_id,
         name = excluded.name,
         color = excluded.color,
         bookmarked = excluded.bookmarked,
         last_used_at = excluded.last_used_at,
         external_id = excluded.external_id,
         aliases = COALESCE(excluded.aliases, activities.aliases),
         version = excluded.version,
         deleted_at = excluded.deleted_at,
         seq = excluded.seq`,
    )
      .bind(
        account.id,
        dto.syncId,
        dto.parentId ?? null,
        dto.name,
        dto.color,
        dto.bookmarked ? 1 : 0,
        dto.lastUsedAt ?? null,
        dto.externalId ?? null,
        Array.isArray(dto.aliases) ? JSON.stringify(dto.aliases) : null,
        dto.version,
        dto.deletedAt ?? null,
        seq++,
      )
      .run();
  }

  for (const dto of changes) {
    if (!validChange(dto)) continue;
    const stored = await env.DB.prepare(
      'SELECT version FROM changes WHERE account_id = ? AND sync_id = ?',
    )
      .bind(account.id, dto.syncId)
      .first();
    if (stored && dto.version < stored.version) {
      rejected.push(dto.syncId);
      continue;
    }
    await env.DB.prepare(
      `INSERT INTO changes
         (account_id, sync_id, changed_at, comment, version, deleted_at, activity_ids, seq)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?)
       ON CONFLICT(account_id, sync_id) DO UPDATE SET
         changed_at = excluded.changed_at,
         comment = excluded.comment,
         version = excluded.version,
         deleted_at = excluded.deleted_at,
         activity_ids = excluded.activity_ids,
         seq = excluded.seq`,
    )
      .bind(
        account.id,
        dto.syncId,
        dto.changedAt,
        dto.comment ?? null,
        dto.version,
        dto.deletedAt ?? null,
        JSON.stringify(Array.isArray(dto.activityIds) ? dto.activityIds : []),
        seq++,
      )
      .run();
  }

  // Pull everything past the client's cursor — including what it just pushed.
  // Echoing a push back costs one adopt (idempotent) and is what tells a client
  // whose row was rejected which version actually won.
  const outActivities = await env.DB.prepare(
    'SELECT * FROM activities WHERE account_id = ? AND seq > ? ORDER BY seq LIMIT ?',
  )
    .bind(account.id, cursor, MAX_PAGE)
    .all();
  const outChanges = await env.DB.prepare(
    'SELECT * FROM changes WHERE account_id = ? AND seq > ? ORDER BY seq LIMIT ?',
  )
    .bind(account.id, cursor, MAX_PAGE)
    .all();

  const rows = [...(outActivities.results ?? []), ...(outChanges.results ?? [])];
  // The cursor may only advance to where *both* lists are complete. They page
  // independently, so the highest seq sent can belong to the list that fitted
  // while the other was cut off at the limit — and moving past a row that was
  // truncated away skips it permanently, because the cursor only goes forward.
  // Stopping short of one costs a re-delivery, which clients adopt idempotently.
  const lastSeqIfTruncated = ({ results }) =>
    (results ?? []).length === MAX_PAGE ? results[results.length - 1].seq : Infinity;
  const complete = Math.min(lastSeqIfTruncated(outActivities), lastSeqIfTruncated(outChanges));
  const highest = rows.length ? Math.max(...rows.map((r) => r.seq)) : cursor;
  const nextCursor = Math.min(highest, complete);

  return json({
    cursor: String(nextCursor),
    activities: (outActivities.results ?? []).map(activityToDto),
    changes: (outChanges.results ?? []).map(changeToDto),
    rejected,
    hasMore: complete !== Infinity,
  });
}

/**
 * Reserve [count] positions in this account's order in one write.
 *
 * Zero reservations write nothing. Every device polls /sync with an empty push
 * far more often than it edits, and D1 bills by rows written — a poll that
 * cost a row write would turn the write budget into a request counter.
 */
async function nextSeq(env, account, count) {
  if (count <= 0) return account.next_seq ?? 1;
  // Reserved in the database, not computed from the row `accountFor` read: two
  // devices syncing the same account at once would otherwise both start from
  // the same value, hand out duplicate seqs, and a pull cursor — which is
  // max(seq) and only moves forward — would skip the clobbered rows forever.
  const row = await env.DB.prepare(
    'UPDATE accounts SET next_seq = next_seq + ? WHERE id = ? RETURNING next_seq',
  )
    .bind(count, account.id)
    .first();
  return row.next_seq - count;
}

function validActivity(dto) {
  return (
    dto &&
    typeof dto.syncId === 'string' &&
    dto.syncId.length > 0 &&
    typeof dto.name === 'string' &&
    typeof dto.color === 'string' &&
    Number.isInteger(dto.version)
  );
}

function validChange(dto) {
  return (
    dto &&
    typeof dto.syncId === 'string' &&
    dto.syncId.length > 0 &&
    Number.isInteger(dto.changedAt) &&
    Number.isInteger(dto.version)
  );
}

function activityToDto(row) {
  return {
    syncId: row.sync_id,
    parentId: row.parent_id,
    name: row.name,
    color: row.color,
    bookmarked: row.bookmarked === 1,
    lastUsedAt: row.last_used_at,
    externalId: row.external_id,
    aliases: parseAliases(row.aliases),
    version: row.version,
    deletedAt: row.deleted_at,
  };
}

function changeToDto(row) {
  let activityIds = [];
  try {
    const parsed = JSON.parse(row.activity_ids || '[]');
    if (Array.isArray(parsed)) activityIds = parsed;
  } catch {
    // A corrupt set is better than a failed sync: the owning change still
    // arrives, and the next push from a client repairs it.
  }
  return {
    syncId: row.sync_id,
    changedAt: row.changed_at,
    comment: row.comment,
    version: row.version,
    deletedAt: row.deleted_at,
    activityIds,
  };
}

/**
 * The optional export API: the whole timeline as CSV, derived the same way the
 * app derives blocks — a change runs until the next one.
 *
 * Server-side because the point is reaching it from something that is not the
 * app: a spreadsheet's "import from URL", a cron job, a script.
 */
async function handleExport(env, account) {
  const changes = await env.DB.prepare(
    'SELECT * FROM changes WHERE account_id = ? AND deleted_at IS NULL ORDER BY changed_at',
  )
    .bind(account.id)
    .all();
  const activities = await env.DB.prepare(
    'SELECT * FROM activities WHERE account_id = ? AND deleted_at IS NULL',
  )
    .bind(account.id)
    .all();

  const byId = new Map((activities.results ?? []).map((a) => [a.sync_id, a]));
  const rows = changes.results ?? [];

  const lines = ['start,end,duration_minutes,activity,comment'];
  for (let i = 0; i < rows.length; i++) {
    const row = rows[i];
    const next = rows[i + 1];
    // The open block has no end. Exporting "now" would make the file's meaning
    // depend on when it was fetched, so it is left out entirely.
    if (!next) break;

    for (const id of changeToDto(row).activityIds) {
      const activity = byId.get(id);
      if (!activity) continue;
      lines.push(
        [
          new Date(row.changed_at).toISOString(),
          new Date(next.changed_at).toISOString(),
          Math.round((next.changed_at - row.changed_at) / 60000),
          csvField(activity.name),
          csvField(row.comment ?? ''),
        ].join(','),
      );
    }
  }

  return new Response(lines.join('\n'), {
    headers: {
      'content-type': 'text/csv; charset=utf-8',
      'content-disposition': 'attachment; filename="track-export.csv"',
    },
  });
}

function csvField(value) {
  const s = String(value ?? '');
  return /[",\n]/.test(s) ? `"${s.replace(/"/g, '""')}"` : s;
}

function json(body, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'content-type': 'application/json; charset=utf-8' },
  });
}

function parseAliases(stored) {
  try {
    const parsed = JSON.parse(stored || '[]');
    return Array.isArray(parsed) ? parsed.filter((a) => typeof a === 'string') : [];
  } catch {
    return [];
  }
}
