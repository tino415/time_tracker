// Exercises the real sync Worker against a local D1, via `wrangler dev`.
//
// The Dart tests prove the client's half — the conflict rule, convergence
// between two databases — but they run against a FakeServer written to mirror
// this Worker. If the Worker diverges from that model, nothing in the Dart suite
// notices. This is what catches that: same properties, asserted against workerd
// and SQLite rather than against a stand-in.
//
// Local only: no Cloudflare account, no deploy, no network.

import { spawn, spawnSync } from 'node:child_process';
import { rmSync } from 'node:fs';

const PORT = process.argv[2] ?? '4243';
const ORIGIN = `http://127.0.0.1:${PORT}`;
// Long enough to be accepted: the Worker rejects anything under 16 characters,
// since a short token is not a token.
const TOKEN = 'smoke-test-token-aaaaaaaaaaaa';
const OTHER_TOKEN = 'smoke-test-token-bbbbbbbbbbbb';

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

const checks = [];
function check(name, ok, detail = '') {
  checks.push({ name, ok });
  console.log(`${ok ? 'ok  ' : 'FAIL'}  ${name}${detail ? `  — ${detail}` : ''}`);
}

const sync = (body, token = TOKEN) =>
  fetch(`${ORIGIN}/sync`, {
    method: 'POST',
    headers: { 'content-type': 'application/json', authorization: `Bearer ${token}` },
    body: JSON.stringify(body),
  });

const activity = (syncId, name, version, extra = {}) => ({
  syncId,
  name,
  color: '#4F8FEE',
  version,
  ...extra,
});

// A fresh D1 per run, so `seq` and the cursor assertions start from a known
// place. The state directory and the schema have to use the *same*
// --persist-to as the dev server, or the Worker runs against an empty database
// and every query fails with "no such table".
const STATE = '.wrangler/smoke-state';
rmSync(`worker/${STATE}`, { recursive: true, force: true });

const applySchema = spawnSync(
  'npx',
  ['wrangler', 'd1', 'execute', 'track-sync', '--local', '--persist-to', STATE, '--file', 'schema.sql'],
  { cwd: 'worker', encoding: 'utf8' },
);
if (applySchema.status !== 0) {
  console.error(applySchema.stderr || applySchema.stdout);
  process.exit(1);
}
console.log('schema applied to a fresh local D1');

// Refuse to run against someone else's server. If the port is already taken —
// a `just worker-dev` left running, most likely — wrangler cannot bind, every
// request goes to *that* worker instead, and the whole suite fails against a
// database and a token it does not own. It looks exactly like a broken Worker.
const inUse = await fetch(`${ORIGIN}/`).then(() => true).catch(() => false);
if (inUse) {
  console.error(`port ${PORT} is already serving something — stop it, or pass a free port.`);
  process.exit(1);
}

const server = spawn(
  'npx',
  ['wrangler', 'dev', '--port', PORT, '--var', `SYNC_TOKEN:${TOKEN}`, '--persist-to', STATE],
  { cwd: 'worker', stdio: ['ignore', 'pipe', 'pipe'] },
);
server.stdout.on('data', (d) => process.stdout.write(`[wrangler] ${d}`));
server.stderr.on('data', (d) => process.stderr.write(`[wrangler] ${d}`));

try {
  // Boot can take a while: workerd downloads nothing but does compile.
  let up = false;
  for (let i = 0; i < 120; i++) {
    try {
      const res = await fetch(`${ORIGIN}/sync`, { method: 'POST' });
      if (res.status) { up = true; break; }
    } catch {}
    await sleep(500);
  }
  check('worker boots', up);
  if (!up) throw new Error('wrangler dev never came up');

  // --- auth and accounts ----------------------------------------------------
  check('rejects a missing token', (await fetch(`${ORIGIN}/sync`, { method: 'POST' })).status === 401);
  check(
    'rejects a token that has no account',
    (await sync({ cursor: null }, 'unclaimed-token-aaaaaaaaaaaa')).status === 401,
  );
  check(
    'rejects a token too short to be one',
    (await fetch(`${ORIGIN}/account`, {
      method: 'POST',
      headers: { authorization: 'Bearer short' },
    })).status === 401,
  );

  const claim = async (token) =>
    fetch(`${ORIGIN}/account`, {
      method: 'POST',
      headers: { authorization: `Bearer ${token}` },
    });

  let res = await claim(TOKEN);
  let body = await res.json();
  check('claims an account for a new token', res.status === 200 && body.created === true, JSON.stringify(body));

  body = await (await claim(TOKEN)).json();
  // Idempotent so a client that lost the response can retry, and so entering an
  // existing token on a second device joins rather than colliding.
  check('claiming again joins the same account', body.created === false && !!body.accountId);

  // --- push and pull -------------------------------------------------------
  res = await sync({ cursor: null, activities: [activity('a', 'Deep work', 1)], changes: [] });
  check('accepts an authorised push', res.status === 200, `http ${res.status}`);
  body = await res.json();
  check('echoes the push back', body.activities?.length === 1, JSON.stringify(body.activities));
  check('nothing rejected', (body.rejected ?? []).length === 0);
  check('returns a cursor', typeof body.cursor === 'string' && body.cursor !== '0', body.cursor);

  const cursorAfterFirst = body.cursor;

  // --- the cursor actually means something ---------------------------------
  body = await (await sync({ cursor: cursorAfterFirst })).json();
  check('a cursor at the head pulls nothing', (body.activities ?? []).length === 0);
  body = await (await sync({ cursor: null })).json();
  check('a null cursor pulls everything', (body.activities ?? []).length === 1);

  // --- the conflict rule, which is the whole design ------------------------
  // Get the stored row ahead first: `a` is still at v1, and v1 over v1 is the
  // *equal* case, which is accepted by design.
  body = await (await sync({ cursor: null, activities: [activity('a', 'Third', 3)] })).json();
  check('accepts a newer version', (body.rejected ?? []).length === 0);

  body = await (await sync({ cursor: null, activities: [activity('a', 'Stale', 2)] })).json();
  check('rejects a stale push', (body.rejected ?? []).includes('a'), JSON.stringify(body.rejected));
  check(
    'the rejected row comes back at the winning version',
    body.activities?.find((x) => x.syncId === 'a')?.name === 'Third',
    body.activities?.find((x) => x.syncId === 'a')?.name,
  );

  // Accepting an equal version is what makes concurrent edits converge: two
  // devices that both edited v2 arrive with v3, and whoever lands last wins.
  body = await (await sync({ cursor: null, activities: [activity('a', 'Same version wins', 3)] })).json();
  check('accepts an equal version', (body.rejected ?? []).length === 0);
  body = await (await sync({ cursor: null })).json();
  check(
    'the equal-version write took effect',
    body.activities?.find((x) => x.syncId === 'a')?.name === 'Same version wins',
  );

  // --- changes carry their activity set ------------------------------------
  const start = 1770000000000;
  body = await (
    await sync({
      cursor: null,
      changes: [
        { syncId: 'c1', changedAt: start, version: 1, activityIds: ['a'], comment: 'first' },
        { syncId: 'c2', changedAt: start + 3600000, version: 1, activityIds: ['a'] },
      ],
    })
  ).json();
  check('accepts changes', (body.rejected ?? []).length === 0);
  const c1 = (body.changes ?? []).find((c) => c.syncId === 'c1');
  check('the activity set survives the round trip', JSON.stringify(c1?.activityIds) === '["a"]', JSON.stringify(c1?.activityIds));
  check('millisecond precision survives', c1?.changedAt === start, String(c1?.changedAt));
  check('the comment survives', c1?.comment === 'first', c1?.comment);

  // --- tombstones ----------------------------------------------------------
  body = await (await sync({ cursor: null, activities: [activity('gone', 'Gone', 2, { deletedAt: start })] })).json();
  const tombstone = (body.activities ?? []).find((a) => a.syncId === 'gone');
  check('a tombstone round-trips', tombstone?.deletedAt === start, String(tombstone?.deletedAt));

  // --- export --------------------------------------------------------------
  const csv = await fetch(`${ORIGIN}/export.csv?token=${TOKEN}`);
  check('export.csv is authorised by query token', csv.status === 200, `http ${csv.status}`);
  const text = await csv.text();
  const lines = text.trim().split('\n');
  check('export has a header', lines[0] === 'start,end,duration_minutes,activity,comment', lines[0]);
  // c1 -> c2 is one closed hour; c2 is open and must be omitted, or the file's
  // meaning would depend on when it was fetched.
  check('export has the closed block only', lines.length === 2, `${lines.length - 1} row(s)`);
  check('export computes the duration', lines[1]?.includes(',60,'), lines[1]);
  check('export.csv rejects a bad token', (await fetch(`${ORIGIN}/export.csv?token=nope`)).status === 401);

  // --- accounts are isolated ------------------------------------------------
  // The whole point of accounts: another token must not see this data, and must
  // not be able to advance or read this account's sequence.
  await claim(OTHER_TOKEN);
  body = await (await sync({ cursor: null }, OTHER_TOKEN)).json();
  check('a second account starts empty', (body.activities ?? []).length === 0, JSON.stringify(body.activities));
  check('and sees none of the first account\'s changes', (body.changes ?? []).length === 0);

  await sync({ cursor: null, activities: [activity('a', 'Their own row', 1)] }, OTHER_TOKEN);
  body = await (await sync({ cursor: null })).json();
  const mine = (body.activities ?? []).find((x) => x.syncId === 'a');
  // Same syncId in both accounts — they must not collide.
  check('a colliding syncId in another account does not overwrite', mine?.name !== 'Their own row', mine?.name);

  const otherCsv = await fetch(`${ORIGIN}/export.csv?token=${OTHER_TOKEN}`);
  check('export is scoped to its account', (await otherCsv.text()).trim().split('\n').length === 1);

  // --- unknown routes ------------------------------------------------------
  check('unknown route is 404', (await fetch(`${ORIGIN}/nope`, {
    headers: { authorization: `Bearer ${TOKEN}` },
  })).status === 404);
} finally {
  server.kill('SIGTERM');
}

const failed = checks.filter((c) => !c.ok);
console.log(`\n${checks.length - failed.length}/${checks.length} checks passed`);
process.exit(failed.length === 0 ? 0 : 1);
