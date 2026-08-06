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

CREATE TABLE IF NOT EXISTS activities (
  sync_id      TEXT PRIMARY KEY,
  parent_id    TEXT,
  name         TEXT NOT NULL,
  color        TEXT NOT NULL,
  bookmarked   INTEGER NOT NULL DEFAULT 0,
  last_used_at INTEGER,
  external_id  TEXT,
  version      INTEGER NOT NULL,
  deleted_at   INTEGER,
  seq          INTEGER NOT NULL
);

CREATE TABLE IF NOT EXISTS changes (
  sync_id      TEXT PRIMARY KEY,
  changed_at   INTEGER NOT NULL,
  comment      TEXT,
  version      INTEGER NOT NULL,
  deleted_at   INTEGER,
  -- The activity set travels inside its change and has no identity of its own,
  -- so it is stored as a JSON array rather than a join table. Nothing on the
  -- server ever queries by activity.
  activity_ids TEXT NOT NULL DEFAULT '[]',
  seq          INTEGER NOT NULL
);

-- Every pull is "rows with seq > cursor, oldest first".
CREATE INDEX IF NOT EXISTS activities_seq ON activities (seq);
CREATE INDEX IF NOT EXISTS changes_seq ON changes (seq);

-- Single-row counter. D1 has no sequences, and AUTOINCREMENT would not give a
-- shared order across two tables — a cursor has to advance over both.
CREATE TABLE IF NOT EXISTS sync_seq (
  id      INTEGER PRIMARY KEY CHECK (id = 1),
  next    INTEGER NOT NULL
);
INSERT OR IGNORE INTO sync_seq (id, next) VALUES (1, 1);
