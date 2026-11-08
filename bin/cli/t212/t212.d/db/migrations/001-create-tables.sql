-- The tables of t212 before it had migrations. IF NOT EXISTS makes this
-- file a no-op on a database that t212 created before, at user_version 0.
--
-- One table per kind. Each row keeps the item in raw, as the API returned it.
-- SQLite derives every other column from raw, so sync inserts a page without
-- mapping fields. A new API field needs one ALTER TABLE ADD COLUMN. SQLite
-- allows that only for a VIRTUAL column, so every column here is VIRTUAL.

CREATE TABLE IF NOT EXISTS transactions (
  raw       TEXT NOT NULL CHECK (json_valid(raw)),
  reference TEXT GENERATED ALWAYS AS (raw ->> '$.reference') VIRTUAL NOT NULL,
  type      TEXT GENERATED ALWAYS AS (raw ->> '$.type') VIRTUAL,
  amount    REAL GENERATED ALWAYS AS (raw ->> '$.amount') VIRTUAL,
  currency  TEXT GENERATED ALWAYS AS (raw ->> '$.currency') VIRTUAL,
  date_time TEXT GENERATED ALWAYS AS (raw ->> '$.dateTime') VIRTUAL
);
CREATE UNIQUE INDEX IF NOT EXISTS transactions_reference
  ON transactions (reference);

CREATE TABLE IF NOT EXISTS dividends (
  raw                    TEXT NOT NULL CHECK (json_valid(raw)),
  reference              TEXT GENERATED ALWAYS AS (raw ->> '$.reference') VIRTUAL NOT NULL,
  ticker                 TEXT GENERATED ALWAYS AS (raw ->> '$.ticker') VIRTUAL,
  type                   TEXT GENERATED ALWAYS AS (raw ->> '$.type') VIRTUAL,
  amount                 REAL GENERATED ALWAYS AS (raw ->> '$.amount') VIRTUAL,
  currency               TEXT GENERATED ALWAYS AS (raw ->> '$.currency') VIRTUAL,
  quantity               REAL GENERATED ALWAYS AS (raw ->> '$.quantity') VIRTUAL,
  gross_amount_per_share REAL GENERATED ALWAYS AS (raw ->> '$.grossAmountPerShare') VIRTUAL,
  paid_on                TEXT GENERATED ALWAYS AS (raw ->> '$.paidOn') VIRTUAL
);
CREATE UNIQUE INDEX IF NOT EXISTS dividends_reference
  ON dividends (reference);

-- One row per fill: an order filled in two trades has two rows. A cancelled
-- order has one row, with NULL fill columns
CREATE TABLE IF NOT EXISTS orders (
  raw             TEXT NOT NULL CHECK (json_valid(raw)),
  id              INTEGER GENERATED ALWAYS AS (raw ->> '$.order.id') VIRTUAL NOT NULL,
  ticker          TEXT GENERATED ALWAYS AS (raw ->> '$.order.ticker') VIRTUAL,
  side            TEXT GENERATED ALWAYS AS (raw ->> '$.order.side') VIRTUAL,
  type            TEXT GENERATED ALWAYS AS (raw ->> '$.order.type') VIRTUAL,
  status          TEXT GENERATED ALWAYS AS (raw ->> '$.order.status') VIRTUAL,
  created_at      TEXT GENERATED ALWAYS AS (raw ->> '$.order.createdAt') VIRTUAL,
  filled_quantity REAL GENERATED ALWAYS AS (raw ->> '$.order.filledQuantity') VIRTUAL,
  filled_value    REAL GENERATED ALWAYS AS (raw ->> '$.order.filledValue') VIRTUAL,
  fill_id         INTEGER GENERATED ALWAYS AS (raw ->> '$.fill.id') VIRTUAL,
  filled_at       TEXT GENERATED ALWAYS AS (raw ->> '$.fill.filledAt') VIRTUAL,
  fill_price      REAL GENERATED ALWAYS AS (raw ->> '$.fill.price') VIRTUAL,
  fill_type       TEXT GENERATED ALWAYS AS (raw ->> '$.fill.type') VIRTUAL,
  net_value       REAL GENERATED ALWAYS AS (raw ->> '$.fill.walletImpact.netValue') VIRTUAL,
  fx_rate         REAL GENERATED ALWAYS AS (raw ->> '$.fill.walletImpact.fxRate') VIRTUAL,
  realised_pl     REAL GENERATED ALWAYS AS (raw ->> '$.fill.walletImpact.realisedProfitLoss') VIRTUAL
);
-- A unique index allows any number of NULLs. Without the coalesce, each sync
-- would add a new row for a cancelled order
CREATE UNIQUE INDEX IF NOT EXISTS orders_id_fill_id
  ON orders (id, coalesce(fill_id, 0));

-- One row per position per snapshot. "t212 sync snapshot" stamps every row
-- of one run with the time of that run, in UTC. The rows show the account
-- over time, which the API does not return
CREATE TABLE IF NOT EXISTS positions (
  taken_at           TEXT NOT NULL,
  raw                TEXT NOT NULL CHECK (json_valid(raw)),
  ticker             TEXT GENERATED ALWAYS AS (raw ->> '$.instrument.ticker') VIRTUAL NOT NULL,
  quantity           REAL GENERATED ALWAYS AS (raw ->> '$.quantity') VIRTUAL,
  current_price      REAL GENERATED ALWAYS AS (raw ->> '$.currentPrice') VIRTUAL,
  average_price_paid REAL GENERATED ALWAYS AS (raw ->> '$.averagePricePaid') VIRTUAL,
  total_cost         REAL GENERATED ALWAYS AS (raw ->> '$.walletImpact.totalCost') VIRTUAL,
  current_value      REAL GENERATED ALWAYS AS (raw ->> '$.walletImpact.currentValue') VIRTUAL,
  unrealized_pl      REAL GENERATED ALWAYS AS (raw ->> '$.walletImpact.unrealizedProfitLoss') VIRTUAL
);
CREATE UNIQUE INDEX IF NOT EXISTS positions_taken_at_ticker
  ON positions (taken_at, ticker);

-- One row per snapshot: the cash and the totals of the account, which the
-- positions leave out
CREATE TABLE IF NOT EXISTS summaries (
  taken_at       TEXT NOT NULL PRIMARY KEY,
  raw            TEXT NOT NULL CHECK (json_valid(raw)),
  total_value    REAL GENERATED ALWAYS AS (raw ->> '$.totalValue') VIRTUAL,
  cash           REAL GENERATED ALWAYS AS (raw ->> '$.cash.availableToTrade') VIRTUAL,
  invested_value REAL GENERATED ALWAYS AS (raw ->> '$.investments.currentValue') VIRTUAL,
  invested_cost  REAL GENERATED ALWAYS AS (raw ->> '$.investments.totalCost') VIRTUAL,
  realized_pl    REAL GENERATED ALWAYS AS (raw ->> '$.investments.realizedProfitLoss') VIRTUAL,
  unrealized_pl  REAL GENERATED ALWAYS AS (raw ->> '$.investments.unrealizedProfitLoss') VIRTUAL
);

-- One row per kind sync has read. next_page_path is where the first sync of
-- the kind stopped, NULL once it reached the oldest page
CREATE TABLE IF NOT EXISTS sync (
  kind           TEXT PRIMARY KEY
                 CHECK (kind IN ('orders', 'dividends', 'transactions')),
  next_page_path TEXT,
  synced_at      TEXT NOT NULL
);
