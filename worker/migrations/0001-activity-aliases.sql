-- For a database created before activities had aliases. Run once; not re-runnable.
ALTER TABLE activities ADD COLUMN aliases TEXT;
