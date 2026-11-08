#!/bin/sh

# The primitives every t212 command shares. A command sets _SCRIPT_DIR to
# t212.d, then sources this file. So does a test of a primitive. This file
# sources bin/lib.sh, sets no shell options and runs nothing.

. "$_SCRIPT_DIR/../../../lib.sh"

_MAX_TRIES=3 # calls per request while the API answers HTTP 429

# ╭───
# │ Text
# ╰───

# _find_header <name> <headers-file>
#
# Print the value of the HTTP header <name> in <headers-file>, the file
# "curl -D" writes. Match <name> in any case. When the file has several
# responses, read the last. Print nothing when that response lacks <name>.
_find_header() {
  awk -v name="$1" '
    BEGIN { name = tolower(name) }
    { sub(/\r$/, "") }
    /^HTTP\// { value = "" }
    {
      i = index($0, ":")
      if (i > 0 && tolower(substr($0, 1, i - 1)) == name) {
        value = substr($0, i + 1)
        sub(/^[ \t]+/, "", value)
      }
    }
    END { if (value != "") print value }' "$2"
}

# _to_iso_time <http-date>
#
# Print <http-date>, the format of an HTTP Date header, as ISO 8601 in UTC,
# eg. "Sun, 08 Nov 2026 14:27:46 GMT" gives 2026-11-08T14:27:46Z.
#
# RETURNS
#   1   <http-date> has another shape. Prints nothing
_to_iso_time() {
  printf '%s\n' "$1" | awk '
    BEGIN {
      split("Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec", names, " ")
      for (i = 1; i <= 12; i++) month[names[i]] = sprintf("%02d", i)
    }
    NF == 6 && $6 == "GMT" && ($3 in month) && $2 ~ /^[0-9][0-9]$/ \
      && $4 ~ /^[0-9][0-9][0-9][0-9]$/ && $5 ~ /^[0-9][0-9]:[0-9][0-9]:[0-9][0-9]$/ {
      printf "%s-%s-%sT%sZ\n", $4, month[$3], $2, $5
      is_found = 1
    }
    END { exit !is_found }'
}

# _quote_sql <text>
#
# Print <text> as an SQL string: between single quotes, each quote inside
# doubled.
_quote_sql() {
  printf "'%s'" "$(printf '%s' "$1" | sed "s/'/''/g")"
}

# _to_wait_seconds <period> <limit>
#
# Print the seconds until the API frees one call: <period> / <limit>, rounded
# up, eg. 3 for 20 calls per 60 s. Print 1 unless both are positive integers.
#
# x-ratelimit-reset gives the same time by the clock of the server. t212 does
# not read it: a local clock off by a minute would make t212 wait a minute
# too long or too short.
_to_wait_seconds() {
  if _is positive-integer "$1" && _is positive-integer "$2"; then
    printf '%s\n' "$((($1 + $2 - 1) / $2))"
  else
    printf '1\n'
  fi
}

# _is_ticker <value>
#
# Tell if <value> has the shape of a ticker: A-Za-z0-9_., eg. AAPL_US_EQ.
#
# RETURNS
#   1   <value> is empty or has another character
_is_ticker() {
  case "$1" in
    "" | *[!A-Za-z0-9_.]*) return 1 ;;
  esac
}

# _is_history_kind <value>
#
# Tell if <value> is a kind of history: orders, dividends or transactions.
#
# RETURNS
#   1   <value> is another word, or empty
_is_history_kind() {
  case "$1" in
    orders | dividends | transactions) ;;
    *) return 1 ;;
  esac
}

# ╭───
# │ Flags and positionals
# ╰───

# _fail_unknown_flag <flag>
#
# End the script on a flag the command does not take. On --live, say that it
# goes before the command: only t212 reads it.
#
# EXIT
#   2   Always
_fail_unknown_flag() {
  if [ "$1" = "--live" ]; then
    _fail 2 "--live goes before the command, eg. t212 --live summary"
  fi

  _fail 2 -v flag "$1" "Unknown flag"
}

# _parse_args <script> <max> [flag-or-positional...]
#
# Read the flags and positionals of a command that takes no flag but --help,
# and up to <max> positionals, 0 or 1. Set _POSITIONAL to the positional, ""
# when there is none. On -h or --help, print the help of <script> and exit 0.
# After --, read the rest as positionals.
#
# EXIT
#   2   A flag, or more than <max> positionals
_parse_args() {
  pa_script="$1"
  pa_max="$2"
  shift 2

  _POSITIONAL=""
  pa_count=0
  pa_is_end=""
  for pa_arg in "$@"; do
    if [ -z "$pa_is_end" ]; then
      case "$pa_arg" in
        -h | --help)
          _show_help "$pa_script"
          exit 0
          ;;
        --)
          pa_is_end="true"
          continue
          ;;
        -?*) _fail_unknown_flag "$pa_arg" ;;
      esac
    fi

    pa_count=$((pa_count + 1))
    if [ "$pa_count" -gt "$pa_max" ]; then
      _fail 2 -v positional "$pa_arg" "Too many positionals"
    fi
    _POSITIONAL="$pa_arg"
  done
}

# _guard_id <value>
#
# End the script unless <value> is empty, or an id: a positive integer.
#
# EXIT
#   2   <value> is not an id
_guard_id() {
  if [ -n "$1" ] && ! _is positive-integer "$1"; then
    _fail 2 -v id "$1" "Not an id"
  fi
}

# ╭───
# │ Account
# ╰───

# _get_account
#
# Print the account t212 chose: demo or live.
#
# EXIT
#   3   _T212_ACCOUNT is not demo or live: the command ran without t212
_get_account() {
  case "${_T212_ACCOUNT:-}" in
    demo | live) printf '%s\n' "$_T212_ACCOUNT" ;;
    *) _fail 3 "Run this command through t212" ;;
  esac
}

# _use_account
#
# Set _ACCOUNT, _HOST, _KEY_NAME and _API_KEY for the account t212 chose.
# Every call to the API reads them.
#
# EXIT
#   2   The API key of the account is not set, or not an API key
#   3   curl or jq is missing, or the command ran without t212
_use_account() {
  _ACCOUNT=$(_get_account)

  _KEY_NAME="T212_API_KEY_DEMO"
  if [ "$_ACCOUNT" = "live" ]; then
    _KEY_NAME="T212_API_KEY_LIVE"
  fi

  _require_var "$_KEY_NAME"
  eval "_API_KEY=\$$_KEY_NAME"

  # The key goes into a quoted curl config line, so it must have no quote
  case "$_API_KEY" in
    *[!A-Za-z0-9]*)
      _fail 2 -v key "$_KEY_NAME" "Not an API key, expected A-Za-z0-9"
      ;;
  esac

  _require_cmd curl jq
  _HOST="https://$_ACCOUNT.trading212.com"
}

# _get_db_file <account>
#
# Print the path of the database of <account>.
_get_db_file() {
  printf '%s/t212/%s.db\n' "${XDG_DATA_HOME:-$HOME/.local/share}" "$1"
}

# _run_sql <db-file> <sql> [sqlite3-flag...]
#
# Run <sql> on <db-file> with sqlite3, print what it selects. Pass <sql> on
# stdin, since sqlite3 reads an argument that starts with "-" as a flag, eg.
# the "--" of an SQL comment.
#
# RETURNS
#   other   The status of sqlite3. The caller picks the exit code
_run_sql() {
  rs_db_file="$1"
  rs_sql="$2"
  shift 2

  printf '%s\n' "$rs_sql" | sqlite3 -bail -batch "$@" "$rs_db_file"
}

# ╭───
# │ Cleanup
# ╰───

# shellcheck disable=SC2329 # called by trap
_cleanup() {
  # 'set -u' aborts on an unset _TEMP_DIR, so default it
  rm -rf -- "${_TEMP_DIR:-}"
}

# _create_temp_dir
#
# Create _TEMP_DIR, and register the traps that delete it.
#
# EXIT
#   3   mktemp failed
_create_temp_dir() {
  trap _cleanup EXIT                                    # normal exit
  trap '_cleanup; trap - EXIT INT; kill -INT $$' INT    # Ctrl-C
  trap '_cleanup; trap - EXIT TERM; kill -TERM $$' TERM # kill, timeout, CI cancel
  trap '_cleanup; trap - EXIT HUP; kill -HUP $$' HUP    # SSH drop, closed window

  _TEMP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/t212.XXXXXX") \
    || _fail 3 "Could not create a temporary folder"
}

# ╭───
# │ API
# ╰───

# _call_api <path> <body-file>
#
# Call GET <path> on the host of the account, write the body to <body-file>.
# On HTTP 429, wait until the API frees one call and call again, up to
# _MAX_TRIES calls. The key goes to curl on stdin, so ps never shows it.
#
# EXIT
#   3   curl failed
#   4   The API answered with an error, or with 429 _MAX_TRIES times
_call_api() {
  ca_try=1

  while :; do
    ca_http_status=$(printf 'header = "Authorization: %s"\n' "$_API_KEY" \
      | curl -sS --max-time 30 -K - -D "$_TEMP_DIR/headers" -o "$2" \
        -w '%{http_code}' "$_HOST$1") \
      || _fail 3 -v path "$1" "curl failed"

    case "$ca_http_status" in
      2??) return 0 ;;
      429) ;;
      401 | 403)
        _fail 4 -v http_status "$ca_http_status" -v key "$_KEY_NAME" \
          "The API refused the key"
        ;;
      *)
        _fail 4 -v path "$1" -v http_status "$ca_http_status" -v body "$(cat -- "$2")" \
          "The API refused the call"
        ;;
    esac

    if [ "$ca_try" -ge "$_MAX_TRIES" ]; then
      _fail 4 -v path "$1" -v calls "$ca_try" "Rate limited, giving up"
    fi

    ca_wait=$(_to_wait_seconds \
      "$(_find_header x-ratelimit-period "$_TEMP_DIR/headers")" \
      "$(_find_header x-ratelimit-limit "$_TEMP_DIR/headers")")

    _info -v path "$1" -v seconds "$ca_wait" "Rate limited, waiting"
    sleep "$ca_wait"
    ca_try=$((ca_try + 1))
  done
}

# _print_json <file>
#
# Print the JSON in <file>, indented at a terminal, on one line otherwise.
#
# EXIT
#   4   <file> has no JSON
_print_json() {
  pj_is_compact="true"
  if [ -t 1 ]; then
    pj_is_compact=""
  fi

  jq ${pj_is_compact:+-c} . -- "$1" || _fail 4 -v file "$1" "Not JSON"
}

# _print_api <path>
#
# Call GET <path> on the host of the account, and print the answer.
_print_api() {
  _call_api "$1" "$_TEMP_DIR/body"
  _print_json "$_TEMP_DIR/body"
}

# _find_next_path <page-file>
#
# Print the nextPagePath of <page-file>. Print nothing on the last page. A
# caller reads it before it uses the items, so a page of the wrong shape
# stops the work before any write.
#
# EXIT
#   4   <page-file> has no items array, or a next page path outside the API
_find_next_path() {
  fnp_path=$(jq -r \
    'if (.items | type) == "array" then .nextPagePath // empty
     else error("no items") end' -- "$1" 2>/dev/null) \
    || _fail 4 "The API answered with no items"

  # The path goes after _HOST, so it must stay inside the API
  case "$fnp_path" in
    "" | /api/v0/*) ;;
    *) _fail 4 -v next "$fnp_path" "Unexpected next page path" ;;
  esac

  _end_with_newline "$fnp_path"
}

# _walk_pages <path> <on-page> [arg...]
#
# Call GET <path>, then each next page. Run "<on-page> [arg...] <page-file>"
# on each page, after _find_next_path guards it. Stop when <on-page> returns
# 1, or after the last page. Do nothing when <path> is empty.
#
# <on-page> runs where set -e is off, since its status is read. So each
# command in it that can fail must end the script itself, eg. with _fail.
#
# EXIT
#   3   curl failed
#   4   The API refused the call, or a page has the wrong shape
_walk_pages() {
  wp_path="$1"
  wp_on_page="$2"
  shift 2

  while [ -n "$wp_path" ]; do
    _call_api "$wp_path" "$_TEMP_DIR/page"
    wp_next_path=$(_find_next_path "$_TEMP_DIR/page")
    "$wp_on_page" "$@" "$_TEMP_DIR/page" || return 0
    wp_path="$wp_next_path"
  done
}

# _get_cached <path>
#
# Print the answer of <path> from the cache, when it is younger than 10
# minutes. Otherwise call the API and cache the answer. Name the cache file
# after the last part of <path>, eg. instruments.
_get_cached() {
  gc_name="${1##*/}"
  gc_dir="${XDG_CACHE_HOME:-$HOME/.cache}/t212/$_ACCOUNT"
  gc_file="$gc_dir/$gc_name.json"
  gc_time_file="$gc_dir/$gc_name.time"
  gc_now=$(date +%s)

  if [ -f "$gc_file" ] && [ -f "$gc_time_file" ]; then
    gc_time=$(cat -- "$gc_time_file")
    if _is non-negative-integer "$gc_time" \
      && [ $((gc_now - gc_time)) -lt 600 ]; then
      _print_json "$gc_file"
      return 0
    fi
  fi

  _call_api "$1" "$_TEMP_DIR/body"
  mkdir -p -- "$gc_dir"
  cp -- "$_TEMP_DIR/body" "$gc_file"
  printf '%s\n' "$gc_now" >"$gc_time_file"
  _print_json "$gc_file"
}
