#!/bin/sh

# NAME
#   sandbox.sh - The sandbox and primitives of the t212 tests
#
# DESCRIPTION
#   A test file sources it after tools/test-lib.sh and after it sets
#   SCRIPT_DIR to its own folder.
#
#   t212 calls the Trading 212 API with a real key. A test that runs it calls
#   build_sandbox first, from before_each. build_sandbox sets fake keys, points
#   XDG_CACHE_HOME and XDG_DATA_HOME at the test folder and puts a fake curl
#   first on PATH. Nothing in it calls the API.
#
#   The fake curl answers call <n> with the files add_answer wrote for <n>,
#   and with HTTP 200 and "{}" when there are none. Each answer has the
#   header "Date: Sun, 08 Nov 2026 14:27:46 GMT", unless add_answer gives a
#   Date of its own. It appends one line per
#   call to calls.log: the URL, a tab, then the curl config it read on stdin.

# shellcheck disable=SC2034 # the test files read it
T212="$SCRIPT_DIR/../t212"

# build_sandbox
# Create a fake curl in the current folder, then make t212 use only it.
#
# RETURNS
#   3   The fake curl is not the first curl on PATH
build_sandbox() {
  mkdir -p bin answers
  cat >bin/curl <<'FAKE'
#!/bin/sh
answers_dir="$(dirname "$0")/../answers"
call=$(($(cat "$answers_dir/count" 2>/dev/null || printf 0) + 1))
printf '%s' "$call" >"$answers_dir/count"

headers_file="" body_file="" url=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    -D) headers_file="$2"; shift 2 ;;
    -o) body_file="$2"; shift 2 ;;
    -K | -w | --max-time) shift 2 ;;
    -*) shift ;;
    *) url="$1"; shift ;;
  esac
done

printf '%s\t%s\n' "$url" "$(cat)" >>"$answers_dir/../calls.log"

http_status=200 headers="" body="{}"
[ -f "$answers_dir/$call.http_status" ] && http_status=$(cat "$answers_dir/$call.http_status")
[ -f "$answers_dir/$call.headers" ] && headers=$(cat "$answers_dir/$call.headers")
[ -f "$answers_dir/$call.body" ] && body=$(cat "$answers_dir/$call.body")

printf 'HTTP/1.1 %s\r\nDate: Sun, 08 Nov 2026 14:27:46 GMT\r\n%s\r\n' \
  "$http_status" "$headers" >"$headers_file"
printf '%s' "$body" >"$body_file"
printf '%s' "$http_status"
FAKE
  chmod +x bin/curl

  PATH="$PWD/bin:$PATH"
  T212_API_KEY_DEMO="demokey"
  T212_API_KEY_LIVE="livekey"
  XDG_CACHE_HOME="$PWD/cache"
  XDG_DATA_HOME="$PWD/data"
  NO_COLOR=1
  NO_LOG_TIME=1
  export PATH T212_API_KEY_DEMO T212_API_KEY_LIVE XDG_CACHE_HOME \
    XDG_DATA_HOME NO_COLOR NO_LOG_TIME

  if [ "$(command -v curl)" != "$PWD/bin/curl" ]; then
    printf 'build_sandbox: the fake curl is not the first curl on PATH\n' >&2
    return 3
  fi
}

# add_answer <call> <http-status> <body> [header-line]
# Make the fake curl answer call <call> with <http-status>, <body> and one
# header.
add_answer() {
  printf '%s' "$2" >"answers/$1.http_status"
  printf '%s' "$3" >"answers/$1.body"
  printf '%s' "${4:-}" >"answers/$1.headers"
}

# db <sql>
# Print what <sql> selects from the demo database.
db() { sqlite3 -batch data/t212/demo.db "$1"; }

# Two pages of transactions, newest first, that sync and sql answer with.
# Page 1 points to page 2, page 2 is the last
# shellcheck disable=SC2034 # the test files read them
_PAGE_1='{"items":[{"reference":"c","type":"FEE","amount":-1,"currency":"USD","dateTime":"2026-01-03T00:00:00.000Z"},{"reference":"b","type":"DEPOSIT","amount":10,"currency":"USD","dateTime":"2026-01-02T00:00:00.000Z"}],"nextPagePath":"/api/v0/equity/history/transactions?limit=50&cursor=a&time=2026-01-01T00:00:00.000Z"}'
_PAGE_2='{"items":[{"reference":"a","type":"DEPOSIT","amount":5,"currency":"USD","dateTime":"2026-01-01T00:00:00.000Z"}],"nextPagePath":null}'

# use_fake_account
# Set what _use_account and _create_temp_dir set, for the demo account, so a
# test calls a primitive of lib.sh without a command. Call it after
# build_sandbox.
use_fake_account() {
  _ACCOUNT="demo"
  _HOST="https://demo.trading212.com"
  _KEY_NAME="T212_API_KEY_DEMO"
  _API_KEY="demokey"
  _TEMP_DIR="$PWD/tmp"
  mkdir -p tmp
}

# A positions answer with two positions, and a summary answer, that a
# snapshot reads
# shellcheck disable=SC2034 # the test files read them
_POSITIONS='[{"instrument":{"ticker":"JPM_US_EQ"},"quantity":2,"currentPrice":335,"averagePricePaid":150,"walletImpact":{"totalCost":300,"currentValue":670,"unrealizedProfitLoss":370}},{"instrument":{"ticker":"KO_US_EQ"},"quantity":4,"currentPrice":95,"averagePricePaid":64,"walletImpact":{"totalCost":256,"currentValue":380,"unrealizedProfitLoss":124}}]'
# shellcheck disable=SC2034 # the test files read them
_SUMMARY='{"totalValue":1092,"cash":{"availableToTrade":42},"investments":{"currentValue":1050,"totalCost":556,"realizedProfitLoss":10,"unrealizedProfitLoss":494}}'
