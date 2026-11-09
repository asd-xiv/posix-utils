#!/bin/sh

# The domain primitives of the database of an account. A command sources
# bin/lib.sh, then t212.d/lib.sh, then this file. So does a test of a
# primitive. This file sets no shell options and runs nothing.

# _migrate <db-file> <db-dir>
#
# Apply each file in <db-dir>/migrations/ whose number is above the
# user_version of <db-file>, in order. Each runs in one transaction that also
# sets user_version to its number, so a migration is whole or absent. Then
# create the views again, from <db-dir>/views.sql.
#
# EXIT
#   3   A migration or the views failed
_migrate() {
  mg_version=$(_run_sql "$1" "PRAGMA user_version;") \
    || _fail 3 -v db "$1" "sqlite3 failed"

  for mg_file in "$2"/migrations/[0-9][0-9][0-9]-*.sql; do
    [ -f "$mg_file" ] || continue

    # 002-create-syncs.sql gives 2. sed removes the leading zeros, which shell
    # arithmetic would read as octal
    mg_number=$(basename "$mg_file" | cut -c 1-3 | sed 's/^0*//')
    [ "${mg_number:-0}" -gt "$mg_version" ] || continue

    _run_sql "$1" "
      BEGIN;
      $(cat -- "$mg_file")
      PRAGMA user_version = $mg_number;
      COMMIT;" \
      || _fail 3 -v migration "$(basename "$mg_file")" "Migration failed"
    _info -v migration "$(basename "$mg_file")" "Applied"
  done

  _run_sql "$1" "$(cat -- "$2/views.sql")" \
    || _fail 3 -v db "$1" "Could not create the views"
}

# _insert_page <db-file> <kind> <sync-id> <page-file> [--save-next]
#
# Insert the items of <page-file> that the table <kind> lacks, each with
# <sync-id>. Print "<inserted> <items>". Set the sync_id of the cursor of
# <kind> to <sync-id>. With --save-next, also set its next_page_path to the
# one of <page-file>, NULL on the last page. One transaction does it all, so
# a sync that stops never saves a place past the rows it inserted. sqlite3
# reads the page once, into the temp table page.
#
# EXIT
#   3   sqlite3 failed
_insert_page() {
  ip_next="next_page_path"
  if [ "${5:-}" = "--save-next" ]; then
    ip_next="excluded.next_page_path"
  fi

  # An INSERT ... SELECT with ON CONFLICT needs a WHERE, or SQLite reads ON
  # as part of a join
  _run_sql "$1" "
    BEGIN;
    CREATE TEMP TABLE page AS
      SELECT CAST(readfile($(_quote_sql "$4")) AS TEXT) AS json;
    INSERT OR IGNORE INTO $2 (raw, sync_id)
      SELECT value, $3 FROM page, json_each(page.json, '\$.items');
    SELECT changes() || ' ' || json_array_length(json, '\$.items') FROM page;
    INSERT INTO cursors (kind, next_page_path, sync_id)
      SELECT '$2', json ->> '\$.nextPagePath', $3 FROM page
      WHERE true
      ON CONFLICT (kind) DO UPDATE
        SET next_page_path = $ip_next, sync_id = excluded.sync_id;
    COMMIT;" || _fail 3 -v db "$1" "sqlite3 failed"
}

# _insert_snapshot <db-file> <sync-id> <positions-file> <positions-at>
#                  <summary-file> <summary-at>
#
# Insert each position of <positions-file> and the summary of <summary-file>,
# with <sync-id> and the time the API answered each. Print how many
# positions it inserted. One transaction does it all, so a snapshot is
# whole or absent.
#
# EXIT
#   3   sqlite3 failed
_insert_snapshot() {
  _run_sql "$1" "
    BEGIN;
    INSERT OR IGNORE INTO positions (sync_id, fetched_at, raw)
      SELECT $2, $(_quote_sql "$4"), value
      FROM json_each(CAST(readfile($(_quote_sql "$3")) AS TEXT));
    SELECT changes();
    INSERT OR IGNORE INTO summaries (sync_id, fetched_at, raw)
      VALUES ($2, $(_quote_sql "$6"),
        CAST(readfile($(_quote_sql "$5")) AS TEXT));
    COMMIT;" || _fail 3 -v db "$1" "sqlite3 failed"
}
