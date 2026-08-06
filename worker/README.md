# track — sync backend

A Cloudflare Worker over D1. Optional: the app is fully usable without it, and
every client keeps an authoritative offline-first copy of the data. This exists
so a user's *own* devices agree, not so the app can work.

## What the server is

A relay with a total order. It stores rows opaquely, decides staleness by
`version` alone, and never interprets a name, a colour or a timestamp. A server
that "helpfully" merged fields could only disagree with the clients, which
already hold the real logic.

`seq` is the server's monotonic counter and the only thing a cursor means: *I
have seen everything up to here*. It is assigned on write, so an edited row moves
to the end of the order and is re-delivered. Clients adopt idempotently, so
re-delivery is cheap while missing a row is not.

## Conflicts

Version-LWW, with the server as the serialization point:

- A push is accepted when `incoming.version >= stored.version`, rejected as stale
  otherwise.
- Accepting the **equal** case is what makes concurrent edits converge. Two
  devices that both edited a row at version 3 both arrive with version 4, and
  whoever reaches the server last wins.

That does lose one of the two edits. It is a deliberate trade: the alternative is
vector clocks or per-field causality, which cost far more than this app's
conflict surface — one person, a handful of devices, mostly disjoint edits — is
worth. What matters is that every device converges on the same row, and rejected
pushes come back in the same response so the loser finds out immediately.

## Setup

```bash
npm install -g wrangler          # or: npx wrangler
wrangler d1 create track-sync    # put the returned id in wrangler.toml
wrangler d1 execute track-sync --remote --file=schema.sql
wrangler secret put SYNC_TOKEN   # generate something long and random
wrangler deploy
```

Point the app at it at build time, so no credentials enter the repository:

```bash
flutter build web \
  --dart-define=SYNC_URL=https://track-sync.<subdomain>.workers.dev/ \
  --dart-define=SYNC_TOKEN=<the same token>
```

Without both defines the app runs exactly as before, with the sync action hidden.

## Endpoints

### `POST /sync`

Push and pull in one round trip — a separate pull would need its own trip and
could interleave with a push, which is exactly when "did my edit survive?" gets
hard to answer.

```jsonc
// request
{ "cursor": "0", "activities": [ /* ActivityDto */ ], "changes": [ /* ChangeDto */ ] }

// response
{ "cursor": "42", "activities": [...], "changes": [...], "rejected": ["sync-id"] }
```

Responses are capped at 500 rows per table; the cursor only advances as far as
what was actually sent, so a truncated page is re-delivered rather than skipped.
A client that is far behind converges over several syncs.

### `GET /export.csv`

The whole timeline as CSV, derived the way the app derives blocks — a change runs
until the next one. Server-side because the point is reaching it from something
that is *not* the app: a spreadsheet's "import from URL", a cron job, a script.
Accepts `?token=` as well as the bearer header, since a spreadsheet cannot set
headers.

The open block is omitted: it has no end, and exporting "now" would make the
file's meaning depend on when it was fetched.

## Auth

One bearer token in `SYNC_TOKEN`. This is one person's own devices, so there are
no accounts to model — which also means the token is the *entire* security
boundary. It is compared in constant time, and it is the only thing standing
between the internet and the data. Rotate it with `wrangler secret put` and
rebuild the clients.
