# Read a Yahoo chart answer, print the trading signals of its symbol as one
# JSON object. Takes $input, the symbol or ISIN the caller asked for, so the
# caller can join the object back to its own rows.
#
# A percent and a price have 2 decimals. A signal that needs more closes
# than the answer has is null, eg. ma_200 for a stock listed 3 months ago.

def mean_of_last($values; $n):
  if ($values | length) >= $n then ($values[-$n:] | add / $n) else null end;

def round2: if . == null then null else (. * 100 | round) / 100 end;

def pct($value; $base):
  if $value == null or $base == null or $base == 0 then null
  else (($value / $base - 1) * 100) | round2 end;

.chart.result[0] as $result
| ($result.indicators.quote[0].close | map(select(. != null))) as $closes
| $result.meta.regularMarketPrice as $price
| $result.meta.fiftyTwoWeekHigh as $high
| mean_of_last($closes; 50) as $ma_50
| mean_of_last($closes; 200) as $ma_200
| ([($result.events.dividends // {})[] | .amount] | add // 0) as $dividends
| {
    input: $input,
    symbol: $result.meta.symbol,
    price: $price,
    high_52w: $high,
    below_high_pct: pct($price; $high),
    ma_50: ($ma_50 | round2),
    ma_200: ($ma_200 | round2),
    vs_ma_200_pct: pct($price; $ma_200),
    is_trend_up: (if $ma_50 == null or $ma_200 == null then null
                  else $ma_50 > $ma_200 end),
    momentum_pct: (if ($closes | length) >= 22 then pct($closes[-22]; $closes[0])
                   else null end),
    dividends_12m: (($dividends * 10000 | round) / 10000),
    yield_pct: (if $price == null or $price == 0 then null
                else ($dividends / $price * 100) | round2 end)
  }
