// Sync backend: a Cloudflare Worker over D1.
//
// The server is a relay with a total order, not a second application. It stores
// rows opaquely, decides staleness by `version` alone, and never interprets a
// name, a colour or a timestamp. Everything that reasons about the data lives in
// the client, which already holds an authoritative offline-first copy — so a
// server that "helpfully" merged fields could only disagree with it.
//
// Endpoints:
//   POST /sync        push + pull in one round trip
//   GET  /export.csv  the whole timeline as CSV, for a spreadsheet or a script
//
// Auth is a single bearer token in SYNC_TOKEN. This is one person's own devices,
// so there are no accounts to model; the token is the whole security boundary,
// which is why it is compared in constant time and why there is nothing else.

const MAX_PAGE = 500;

const API_PATHS = new Set(['/sync', '/export.csv']);

export default {
  async fetch(request, env) {
    const url = new URL(request.url);

    // Anything that is not an API route is the PWA. Serving it from this same
    // Worker is what keeps the app and the API on one origin — a separately
    // hosted app would be cross-origin, so every sync would need a CORS
    // preflight and this Worker would have to grow origin handling.
    //
    // Note the order: the token gates the *API*, not the app. Authorising first
    // would 401 every static file, which is how the first deploy served nothing
    // but "unauthorized".
    if (!API_PATHS.has(url.pathname)) {
      if (env.ASSETS) return env.ASSETS.fetch(request);
      return json({ error: 'not found' }, 404);
    }

    if (!authorized(request, url, env)) {
      return json({ error: 'unauthorized' }, 401);
    }

    try {
      if (url.pathname === '/sync' && request.method === 'POST') {
        return await handleSync(request, env);
      }
      if (url.pathname === '/export.csv' && request.method === 'GET') {
        return await handleExport(env);
      }
      return json({ error: 'not found' }, 404);
    } catch (e) {
      return json({ error: String(e && e.message ? e.message : e) }, 500);
    }
  },
};

/**
 * Bearer token, or `?token=` for the export URL — a spreadsheet fetching a CSV
 * cannot set headers. Compared in constant time: a timing oracle on a
 * single-token system would be the whole security boundary.
 */
function authorized(request, url, env) {
  const expected = env.SYNC_TOKEN;
  if (!expected) return false;

  const header = request.headers.get('authorization') || '';
  const bearer = header.startsWith('Bearer ') ? header.slice(7) : '';
  const supplied = bearer || url.searchParams.get('token') || '';
  return timingSafeEqual(supplied, expected);
}

function timingSafeEqual(a, b) {
  const ab = new TextEncoder().encode(a);
  const bb = new TextEncoder().encode(b);
  // Length alone is not secret enough to be worth hiding, but the comparison
  // still runs over a fixed length so a partial match reveals nothing.
  if (ab.length !== bb.length) return false;
  let diff = 0;
  for (let i = 0; i < ab.length; i++) diff |= ab[i] ^ bb[i];
  return diff === 0;
}

async function handleSync(request, env) {
  const body = await request.json();
  const cursor = Number.parseInt(body.cursor ?? '0', 10) || 0;
  const activities = Array.isArray(body.activities) ? body.activities : [];
  const changes = Array.isArray(body.changes) ? body.changes : [];

  const rejected = [];
  let seq = await nextSeq(env, activities.length + changes.length);

  for (const dto of activities) {
    if (!validActivity(dto)) continue;
    const stored = await env.DB.prepare('SELECT version FROM activities WHERE sync_id = ?')
      .bind(dto.syncId)
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
         (sync_id, parent_id, name, color, bookmarked, last_used_at, external_id, version, deleted_at, seq)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
       ON CONFLICT(sync_id) DO UPDATE SET
         parent_id = excluded.parent_id,
         name = excluded.name,
         color = excluded.color,
         bookmarked = excluded.bookmarked,
         last_used_at = excluded.last_used_at,
         external_id = excluded.external_id,
         version = excluded.version,
         deleted_at = excluded.deleted_at,
         seq = excluded.seq`,
    )
      .bind(
        dto.syncId,
        dto.parentId ?? null,
        dto.name,
        dto.color,
        dto.bookmarked ? 1 : 0,
        dto.lastUsedAt ?? null,
        dto.externalId ?? null,
        dto.version,
        dto.deletedAt ?? null,
        seq++,
      )
      .run();
  }

  for (const dto of changes) {
    if (!validChange(dto)) continue;
    const stored = await env.DB.prepare('SELECT version FROM changes WHERE sync_id = ?')
      .bind(dto.syncId)
      .first();
    if (stored && dto.version < stored.version) {
      rejected.push(dto.syncId);
      continue;
    }
    await env.DB.prepare(
      `INSERT INTO changes
         (sync_id, changed_at, comment, version, deleted_at, activity_ids, seq)
       VALUES (?, ?, ?, ?, ?, ?, ?)
       ON CONFLICT(sync_id) DO UPDATE SET
         changed_at = excluded.changed_at,
         comment = excluded.comment,
         version = excluded.version,
         deleted_at = excluded.deleted_at,
         activity_ids = excluded.activity_ids,
         seq = excluded.seq`,
    )
      .bind(
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
    'SELECT * FROM activities WHERE seq > ? ORDER BY seq LIMIT ?',
  )
    .bind(cursor, MAX_PAGE)
    .all();
  const outChanges = await env.DB.prepare(
    'SELECT * FROM changes WHERE seq > ? ORDER BY seq LIMIT ?',
  )
    .bind(cursor, MAX_PAGE)
    .all();

  const rows = [...(outActivities.results ?? []), ...(outChanges.results ?? [])];
  // The new cursor is the highest seq actually *sent*. Advancing past a row that
  // was truncated by the page limit would skip it permanently; leaving the
  // cursor short only costs a re-delivery.
  const nextCursor = rows.length
    ? Math.max(...rows.map((r) => r.seq))
    : cursor;

  return json({
    cursor: String(nextCursor),
    activities: (outActivities.results ?? []).map(activityToDto),
    changes: (outChanges.results ?? []).map(changeToDto),
    rejected,
  });
}

/** Reserve [count] positions in the shared order in one write. */
async function nextSeq(env, count) {
  const row = await env.DB.prepare('SELECT next FROM sync_seq WHERE id = 1').first();
  const start = row ? row.next : 1;
  await env.DB.prepare('UPDATE sync_seq SET next = ? WHERE id = 1')
    .bind(start + Math.max(count, 0))
    .run();
  return start;
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
async function handleExport(env) {
  const changes = await env.DB.prepare(
    'SELECT * FROM changes WHERE deleted_at IS NULL ORDER BY changed_at',
  ).all();
  const activities = await env.DB.prepare(
    'SELECT * FROM activities WHERE deleted_at IS NULL',
  ).all();

  const byId = new Map((activities.results ?? []).map((a) => [a.sync_id, a]));
  const rows = changes.results ?? [];

  const lines = ['start,end,duration_minutes,activity,comment'];
  for (let i = 0; i < rows.length; i++) {
    const row = rows[i];
    const next = rows[i + 1];
    // The open block has no end. Exporting "now" would make the file's meaning
    // depend on when it was fetched, so it is left out entirely.
    if (!next) break;

    const ids = changeToDto(row).activityIds;
    for (const id of ids) {
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
