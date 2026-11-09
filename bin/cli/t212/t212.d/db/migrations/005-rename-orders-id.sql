-- id repeats once per fill, so a reader takes it for the key of the row.
-- order_id names the order a fill belongs to, beside fill_id. SQLite updates
-- the index with the column. Delete and create it again to match its name.

ALTER TABLE orders RENAME COLUMN id TO order_id;

DROP INDEX orders_id_fill_id;
CREATE UNIQUE INDEX orders_order_id_fill_id
  ON orders (order_id, coalesce(fill_id, 0));
