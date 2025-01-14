#!/usr/bin/env bash
set -e

LANG=C
LC_NUMERIC=C

SYMBOLS=("$@")

if ! $(type jq > /dev/null 2>&1); then
  echo "'jq' is not in the PATH. (See: https://stedolan.github.io/jq/)"
  exit 1
fi

if [ -z "$SYMBOLS" ]; then
  echo "Usage: ./ticker.sh AAPL MSFT GOOG BTC-USD"
  exit
fi

FIELDS=(symbol marketState regularMarketPrice regularMarketChange regularMarketChangePercent \
  preMarketPrice preMarketChange preMarketChangePercent postMarketPrice postMarketChange postMarketChangePercent \
  regularMarketVolume regularMarketDayLow regularMarketDayHigh averageDailyVolume3Month)
API_ENDPOINT="https://query1.finance.yahoo.com/v6/finance/quote?lang=en-US&region=US&corsDomain=finance.yahoo.com"

if [ -z "$NO_COLOR" ]; then
  : "${COLOR_BOLD:=\e[1;37m}"
  : "${COLOR_GREEN:=\e[32m}"
  : "${COLOR_RED:=\e[31m}"
  : "${COLOR_RESET:=\e[00m}"
fi

symbols=$(IFS=,; echo "${SYMBOLS[*]}")
fields=$(IFS=,; echo "${FIELDS[*]}")

results=$(curl --silent "$API_ENDPOINT&fields=$fields&symbols=$symbols" \
  | jq '.quoteResponse .result')

query () {
  echo $results | jq -r "[.[] | select(.symbol == \"$1\") | .$2][0]"
}

for symbol in $(IFS=' '; echo "${SYMBOLS[*]}" | tr '[:lower:]' '[:upper:]'); do
  marketState="$(query $symbol 'marketState')"

  if [ "$marketState" = "null" ]; then
    printf "%-10s No data! Is symbol valid?\n" $symbol
    continue
  fi

  preMarketChange="$(query $symbol 'preMarketChange')"
  postMarketChange="$(query $symbol 'postMarketChange')"

  if [ "$marketState" == "PRE" ] \
    && [ $preMarketChange != "0" ] \
    && [ $preMarketChange != "null" ]; then
    nonRegularMarketSign='*'
    price=$(query $symbol 'preMarketPrice')
    diff=$preMarketChange
    percent=$(query $symbol 'preMarketChangePercent')
  elif [ "$marketState" != "REGULAR" ] \
    && [ $postMarketChange != "0" ] \
    && [ $postMarketChange != "null" ]; then
    nonRegularMarketSign='*'
    price=$(query $symbol 'postMarketPrice')
    diff=$postMarketChange
    percent=$(query $symbol 'postMarketChangePercent')
  else
    nonRegularMarketSign='-'
    price=$(query $symbol 'regularMarketPrice')
    diff=$(query $symbol 'regularMarketChange')
    percent=$(query $symbol 'regularMarketChangePercent')
  fi

  if [ "$price" = "null" ]; then
    printf "%-10s Market data are missing. Is symbol active?\n" $symbol
    continue
  fi

  if [ "$percent" = "null" ]; then
    # IPO?
    percent="0"
  fi

  if [ "$diff" = "null" ]; then
    # IPO?
    diff="0"
  fi
  regularMarketDayLow=$(query $symbol 'regularMarketDayLow')
  regularMarketDayHigh=$(query $symbol 'regularMarketDayHigh')
  regularMarketVolume=$(query $symbol 'regularMarketVolume')
  averageDailyVolume3Month=$(query $symbol 'averageDailyVolume3Month')
  if [ "$regularMarketDayLow" == "null" ]; then
    regularMarketDayLow=0
  fi

  if [ "$regularMarketDayHigh" == "null" ]; then
    regularMarketDayHigh=0
  fi

  if [ "$regularMarketVolume" == "null" ]; then
    regularMarketVolume=0
  fi

  if [ "$diff" == "0" ] || [ "$diff" == "0.0" ]; then
    color=
  elif ( echo "$diff" | grep -q ^- ); then
    color=$COLOR_RED
  else
    color=$COLOR_GREEN
  fi

  if [ "$price" != "null" ]; then
    printf "%-10s$COLOR_BOLD%11.5f$COLOR_RESET" $symbol $price
    printf "$color%13.5f%12s$COLOR_RESET" $diff $(printf "(%.2f%%)" $percent)
    printf " %s\n" "$nonRegularMarketSign"
  fi
done
