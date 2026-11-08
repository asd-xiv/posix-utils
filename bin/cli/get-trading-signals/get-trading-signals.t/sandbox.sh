#!/bin/sh

# NAME
#   sandbox.sh - The sandbox and primitives of the get-trading-signals tests
#
# DESCRIPTION
#   A test file sets SCRIPT_DIR to its own folder, sources tools/test-lib.sh,
#   then sources this file.
#
#   get-trading-signals calls Yahoo Finance. A test that runs it calls
#   build_sandbox first, from before_each. build_sandbox puts a fake curl
#   first on PATH, so nothing calls Yahoo. sandbox.contract verifies what the
#   fake assumes.
#
#   The fake curl answers call <n> with the files add_answer wrote for <n>,
#   and with HTTP 200 and "{}" when there are none. It appends the URL of
#   each call to calls.log.

# shellcheck disable=SC2034 # the test files read it
SIGNALS="$SCRIPT_DIR/../get-trading-signals"

# build_sandbox
# Create a fake curl in the current folder, then make the command use it.
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

body_file="" url=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    -o) body_file="$2"; shift 2 ;;
    -A | -w | --max-time) shift 2 ;;
    -*) shift ;;
    *) url="$1"; shift ;;
  esac
done

printf '%s\n' "$url" >>"$answers_dir/../calls.log"

http_status=200 body="{}"
[ -f "$answers_dir/$call.http_status" ] && http_status=$(cat "$answers_dir/$call.http_status")
[ -f "$answers_dir/$call.body" ] && body=$(cat "$answers_dir/$call.body")

printf '%s' "$body" >"$body_file"
printf '%s' "$http_status"
FAKE
  chmod +x bin/curl

  PATH="$PWD/bin:$PATH"
  NO_COLOR=1
  NO_LOG_TIME=1
  export PATH NO_COLOR NO_LOG_TIME

  if [ "$(command -v curl)" != "$PWD/bin/curl" ]; then
    printf 'build_sandbox: the fake curl is not the first curl on PATH\n' >&2
    return 3
  fi
}

# add_answer <call> <http-status> <body>
# Make the fake curl answer call <call> with <http-status> and <body>.
add_answer() {
  printf '%s' "$2" >"answers/$1.http_status"
  printf '%s' "$3" >"answers/$1.body"
}

# to_chart <symbol> <price> <high> <first-close> <count> [dividend...]
# Print a Yahoo chart answer of <symbol>: <count> daily closes that rise by 1
# from <first-close>, and one dividend per [dividend].
to_chart() {
  jq -n -c --arg symbol "$1" --argjson price "$2" --argjson high "$3" \
    --argjson first "$4" --argjson count "$5" --args '{
      chart: {result: [{
        meta: {symbol: $symbol, regularMarketPrice: $price, fiftyTwoWeekHigh: $high},
        indicators: {quote: [{close: [range($first; $first + $count)]}]},
        events: {dividends: ($ARGS.positional[5:] | to_entries
          | map({key: (.key | tostring), value: {amount: (.value | tonumber)}})
          | from_entries)}
      }]}
    }' "$@"
}

# A search answer that resolves an ISIN to RITM
# shellcheck disable=SC2034 # the test files read it
_SEARCH_RITM='{"quotes":[{"symbol":"RITM","quoteType":"EQUITY"}]}'
