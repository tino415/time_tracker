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
```

Then `just worker-deploy`, which builds the PWA and uploads it with the Worker —
the app is served from this same origin, so the two never need CORS.

There is no server-side secret to set. Clients take only the URL at build time:

```bash
SYNC_URL=https://track-sync.<subdomain>.workers.dev/ just worker-deploy
SYNC_URL=https://track-sync.<subdomain>.workers.dev/ just deploy <serial>
```

Without it the app runs exactly as before, with sync hidden entirely. With it,
sync is offered but *opt-in*: the app contacts nothing until someone creates or
joins an account.

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

## Accounts

**A sync token is an account.** It is generated on the first device and entered
on the others to join. There are no usernames, no password reset and no third
party — which suits a handful of people who know each other, and keeps the whole
thing to one secret a user can copy between their devices.

- `POST /account` claims an account for the presented token, creating it if the
  token is unknown. Idempotent, so retrying is safe and entering an existing
  token on a second device joins rather than collides. Anyone may create one:
  there is nothing to gate it with, and an account is worth nothing without its
  token.
- Only the token's **hash** is stored, so a database dump does not hand over
  anyone's data. A plain SHA-256 rather than a slow password hash, deliberately:
  a generated token has far more entropy than a password, so there is nothing to
  brute force, and this runs on every request.
- Tokens shorter than 16 characters are refused outright.
- An unknown token and a wrong one both return 401. "No such account" would
  confirm which tokens exist.
- Every row carries `account_id`, and `seq` is per account — so one account's
  writes cannot advance another's cursor, and the same `syncId` in two accounts
  does not collide.

The token is **not** compiled into clients. A token baked into a web build is
served to everyone who loads the page, and it could only ever be one account's;
clients take `SYNC_URL` at build time and get their token from the user.

There is no way to recover a lost token, and no way to change one without
re-entering it everywhere. That is the cost of having no accounts to manage.
Anyone holding a token has that account's data.
