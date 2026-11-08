-- A view has no data, so sync creates each view again on each run, after
-- the migrations, and a change here reaches every database. The views sum
-- in USD, the currency of the account. A EUR deposit or withdrawal has a USD
-- leg, so the USD rows alone count the money that crossed the edge of the
-- account

-- The positions of the newest snapshot. summaries has one row per snapshot,
-- even one with no positions, so its newest sync id is the newest snapshot.
-- max(sync_id) of positions would skip a snapshot with no positions and list
-- the one before
DROP VIEW IF EXISTS latest_positions;
CREATE VIEW latest_positions AS
SELECT * FROM positions
WHERE sync_id = (SELECT max(sync_id) FROM summaries);

-- The money in and out of the account per year. A TRANSFER refunded an
-- earlier deposit to the card it came from
DROP VIEW IF EXISTS flows;
CREATE VIEW flows AS
SELECT strftime('%Y', date_time) AS year,
  round(sum(amount) FILTER (WHERE type = 'DEPOSIT'), 2) AS deposited,
  round(-sum(amount) FILTER (WHERE type IN ('WITHDRAW', 'TRANSFER')), 2)
    AS withdrawn
FROM transactions
WHERE currency = 'USD' AND type IN ('DEPOSIT', 'WITHDRAW', 'TRANSFER')
GROUP BY year;

-- The dividends, the interest on cash and on lent shares, and the fees, per
-- year
DROP VIEW IF EXISTS income;
CREATE VIEW income AS
WITH rows AS (
  SELECT strftime('%Y', paid_on) AS year,
    amount AS dividends, 0 AS interest, 0 AS fees
  FROM dividends
  UNION ALL
  SELECT strftime('%Y', date_time),
    0,
    iif(type = 'FEE', 0, amount),
    iif(type = 'FEE', amount, 0)
  FROM transactions
  WHERE currency = 'USD'
    AND type IN ('INTEREST_ON_FREE_CASH', 'LENDING_INTEREST', 'FEE')
)
SELECT year,
  round(sum(dividends), 2) AS dividends,
  round(sum(interest), 2) AS interest,
  round(sum(fees), 2) AS fees
FROM rows
GROUP BY year;
