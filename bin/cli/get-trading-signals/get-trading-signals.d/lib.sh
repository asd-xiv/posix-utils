#!/bin/sh

# The primitives of get-trading-signals. The command sets _SCRIPT_DIR to
# get-trading-signals.d, then sources this file. So does a test of a
# primitive. This file sources bin/lib.sh, sets no shell options and runs
# nothing.

. "$_SCRIPT_DIR/../../../lib.sh"

# Yahoo answers 429 to the user agent of curl. A browser-like one passes
_USER_AGENT="Mozilla/5.0 (X11; Linux x86_64) get-trading-signals"

# ╭───
# │ Text
# ╰───

# _is_isin <value>
#
# Tell if <value> has the shape of an ISIN: 2 capital letters, 9 capital
# letters or digits, then 1 digit, eg. US1912161007.
#
# RETURNS
#   1   <value> has another shape
_is_isin() {
  case "$1" in
    [A-Z][A-Z][A-Z0-9][A-Z0-9][A-Z0-9][A-Z0-9][A-Z0-9][A-Z0-9][A-Z0-9][A-Z0-9][A-Z0-9][0-9]) ;;
    *) return 1 ;;
  esac
}

# _is_symbol <value>
#
# Tell if <value> has the shape of a Yahoo symbol: A-Z, 0-9, "." and "-",
# starting with a letter or a digit, eg. KO, BRK-B or RDSA.AS. The symbol
# goes into a URL as is, so the shape keeps out every other character.
#
# RETURNS
#   1   <value> is empty or has another shape
_is_symbol() {
  case "$1" in
    "" | *[!A-Z0-9.-]* | [.-]*) return 1 ;;
  esac
}

# ╭───
# │ Yahoo
# ╰───

# _call_yahoo <url> <body-file>
#
# Call GET <url> on Yahoo, write the body to <body-file>, print the HTTP
# status.
#
# EXIT
#   3   curl failed
_call_yahoo() {
  curl -sS --max-time 20 -A "$_USER_AGENT" -o "$2" -w '%{http_code}' "$1" \
    || _fail 3 -v url "$1" "Yahoo did not answer"
}

# _find_symbol <isin> <body-file>
#
# Print the Yahoo symbol of <isin>: the first match of a Yahoo search, the
# symbol of today, eg. RITM for the ISIN of the old NRZ. Print nothing when
# Yahoo finds none.
#
# EXIT
#   3   curl failed, or Yahoo refused the call
_find_symbol() {
  fs_http_status=$(_call_yahoo \
    "https://query2.finance.yahoo.com/v1/finance/search?q=$1&quotesCount=1&newsCount=0" \
    "$2")

  if [ "$fs_http_status" != "200" ]; then
    _fail 3 -v isin "$1" -v http_status "$fs_http_status" "Yahoo refused the call"
  fi

  jq -r '.quotes[0].symbol // empty' -- "$2" \
    || _fail 3 -v isin "$1" "Yahoo answered with no JSON"
}

# _fetch_chart <symbol> <body-file>
#
# Write one year of daily prices and dividends of <symbol> to <body-file>:
# the chart answer of Yahoo.
#
# RETURNS
#   1   Yahoo knows no such symbol
#
# EXIT
#   3   curl failed, or Yahoo refused the call
_fetch_chart() {
  fc_http_status=$(_call_yahoo \
    "https://query1.finance.yahoo.com/v8/finance/chart/$1?range=1y&interval=1d&events=div" \
    "$2")

  case "$fc_http_status" in
    200) ;;
    404) return 1 ;;
    *)
      _fail 3 -v symbol "$1" -v http_status "$fc_http_status" \
        "Yahoo refused the call"
      ;;
  esac
}
