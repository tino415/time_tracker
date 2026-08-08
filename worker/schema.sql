-- D1 schema for the sync backend.
--
-- The server is a relay with a total order, not a second application. It stores
-- rows opaquely, decides staleness by `version` alone, and never interprets a
-- name, a colour or a timestamp. Everything that reasons about the data lives in
-- the client, which is where the offline-first copy already is.
--
-- `seq` is the server's own monotonic counter and the only thing a cursor means:
-- "I have seen everything up to here". It is assigned on write, so a row edited
-- twice moves to the end of the order and is re-delivered — clients adopt
-- idempotently, so re-delivery is cheap and missing a row is not.

-- One account per sync token. The token itself is never stored, only its hash,
-- so a dump of this table does not hand over anyone's data. There is no
-- username: the token *is* the identity, generated on the first device and
-- entered on the others to join the same account.
--
-- `seq` is per account, so one account's writes cannot advance another's cursor.
CREATE TABLE IF NOT EXISTS accounts (
  id         TEXT PRIMARY KEY,
  token_hash TEXT NOT NULL UNIQUE,
  created_at INTEGER NOT NULL,
  next_seq   INTEGER NOT NULL DEFAULT 1
);

CREATE TABLE IF NOT EXISTS activities (
  account_id   TEXT NOT NULL,
  sync_id      TEXT NOT NULL,
  parent_id    TEXT,
  name         TEXT NOT NULL,
  color        TEXT NOT NULL,
  bookmarked   INTEGER NOT NULL DEFAULT 0,
  last_used_at INTEGER,
  external_id  TEXT,
  version      INTEGER NOT NULL,
  deleted_at   INTEGER,
  seq          INTEGER NOT NULL,
  PRIMARY KEY (account_id, sync_id)
);

CREATE TABLE IF NOT EXISTS changes (
  account_id   TEXT NOT NULL,
  sync_id      TEXT NOT NULL,
  changed_at   INTEGER NOT NULL,
  comment      TEXT,
  version      INTEGER NOT NULL,
  deleted_at   INTEGER,
  -- The activity set travels inside its change and has no identity of its own,
  -- so it is stored as a JSON array rather than a join table. Nothing on the
  -- server ever queries by activity.
  activity_ids TEXT NOT NULL DEFAULT '[]',
  seq          INTEGER NOT NULL,
  PRIMARY KEY (account_id, sync_id)
);

-- Every pull is "this account's rows with seq > cursor, oldest first".
CREATE INDEX IF NOT EXISTS activities_seq ON activities (account_id, seq);
CREATE INDEX IF NOT EXISTS changes_seq ON changes (account_id, seq);
