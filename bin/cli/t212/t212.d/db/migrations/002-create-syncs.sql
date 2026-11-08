-- Give every run of sync an id. A snapshot keeps the id of its run, and the
-- time the API answered, from the Date header of the answer. A history row
-- keeps the id of the run that first saw it. A row from before this
-- migration has no sync id.

-- A view that names a dropped table breaks the ALTER TABLEs below. sync
-- creates the views again from views.sql after the migrations
DROP VIEW IF EXISTS cash_flows;
DROP VIEW IF EXISTS latest_positions;
DROP VIEW IF EXISTS flows;
DROP VIEW IF EXISTS income;

-- started_at and finished_at come from the clock of this machine: they time
-- the run, not the data. finished_at is NULL while a run goes, or after it
-- failed
CREATE TABLE syncs (
  id          INTEGER PRIMARY KEY,
  started_at  TEXT NOT NULL,
  finished_at TEXT
);

-- sync and syncs would differ by one letter. The table has where the first
-- sync of each kind stopped
ALTER TABLE sync RENAME TO cursors;

ALTER TABLE transactions ADD COLUMN sync_id INTEGER REFERENCES syncs (id);
ALTER TABLE dividends ADD COLUMN sync_id INTEGER REFERENCES syncs (id);
ALTER TABLE orders ADD COLUMN sync_id INTEGER REFERENCES syncs (id);

-- The snapshots from before this migration have no sync id, and they cover a
-- few hours. Start them again
DROP TABLE positions;
DROP TABLE summaries;

-- One row per position per snapshot. The rows show the account over time,
-- which the API does not return
CREATE TABLE positions (
  sync_id            INTEGER NOT NULL REFERENCES syncs (id),
  fetched_at         TEXT NOT NULL,
  raw                TEXT NOT NULL CHECK (json_valid(raw)),
  ticker             TEXT GENERATED ALWAYS AS (raw ->> '$.instrument.ticker') VIRTUAL NOT NULL,
  quantity           REAL GENERATED ALWAYS AS (raw ->> '$.quantity') VIRTUAL,
  current_price      REAL GENERATED ALWAYS AS (raw ->> '$.currentPrice') VIRTUAL,
  average_price_paid REAL GENERATED ALWAYS AS (raw ->> '$.averagePricePaid') VIRTUAL,
  total_cost         REAL GENERATED ALWAYS AS (raw ->> '$.walletImpact.totalCost') VIRTUAL,
  current_value      REAL GENERATED ALWAYS AS (raw ->> '$.walletImpact.currentValue') VIRTUAL,
  unrealized_pl      REAL GENERATED ALWAYS AS (raw ->> '$.walletImpact.unrealizedProfitLoss') VIRTUAL
);
CREATE UNIQUE INDEX positions_sync_id_ticker ON positions (sync_id, ticker);

-- One row per snapshot: the cash and the totals of the account, which the
-- positions leave out
CREATE TABLE summaries (
  sync_id        INTEGER NOT NULL PRIMARY KEY REFERENCES syncs (id),
  fetched_at     TEXT NOT NULL,
  raw            TEXT NOT NULL CHECK (json_valid(raw)),
  total_value    REAL GENERATED ALWAYS AS (raw ->> '$.totalValue') VIRTUAL,
  cash           REAL GENERATED ALWAYS AS (raw ->> '$.cash.availableToTrade') VIRTUAL,
  invested_value REAL GENERATED ALWAYS AS (raw ->> '$.investments.currentValue') VIRTUAL,
  invested_cost  REAL GENERATED ALWAYS AS (raw ->> '$.investments.totalCost') VIRTUAL,
  realized_pl    REAL GENERATED ALWAYS AS (raw ->> '$.investments.realizedProfitLoss') VIRTUAL,
  unrealized_pl  REAL GENERATED ALWAYS AS (raw ->> '$.investments.unrealizedProfitLoss') VIRTUAL
);
