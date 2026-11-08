-- A cursor keeps the id of the last run that read its kind, in place of
-- synced_at, a time from the clock of this machine. The time of the run is
-- in syncs. A cursor from before this migration has no sync id, until the
-- next run reads its kind.

ALTER TABLE cursors DROP COLUMN synced_at;
ALTER TABLE cursors ADD COLUMN sync_id INTEGER REFERENCES syncs (id);
