-- A run keeps the exit code of sync, as the man page of sync defines it, eg.
-- 4 when the API refused a call. NULL while the run goes, or after a signal
-- killed it. A run from before this migration that finished gets 0. One that
-- did not finish keeps NULL: its exit code is lost.

ALTER TABLE syncs ADD COLUMN exit_code INTEGER;

UPDATE syncs SET exit_code = 0 WHERE finished_at IS NOT NULL;
