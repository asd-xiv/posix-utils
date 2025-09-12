#!/usr/bin/env sh

# NAME
#  log.sh - Print a fancy log message
#
# SYNOPSIS
#  log.sh <type> [-nc|--no-color] [-v|--var <name> <value>] <message>
#
# DESCRIPTION
#  Print a dated, colored, namespaced, multi-level, CI aware and pretty
#  formatted log message.
#
# FLAGS
#  [-ns|--no-color]
#   Do not print colors or icons.
#   Defaults to true if the CI environment variable is set, otherwise false.
#
# OPTIONS
#  [-v|--var <name> <value>]
#   Print a variable name and its value, nicely formatted and color coded,
#   after the message text.
#
# ARGUMENTS
#  <type>
#   The type of message to print. Possible values are "error", "warning",
#   "info", and "success".
#
#  <message>
#   The message to print. Can be passed as the first argument or as
#   standard input.
#
# ENVIRONMENT
#  LOG_LEVEL
#   The minimum level of log messages to print. Possible values are "error",
#   "warning" and "info" ("success" messages will always be printed).
#   Defaults to "error".
#
#  LOG_NAMESPACE
#   If set, the namespace is printed before the message in gray text.
#
#  CI
#   If set, messages are printed without colors.
#
# EXAMPLE
#  log.sh error -v param-name "name" -v param-value "wrong-value" "Invalid parameter value"

LOG_NAMESPACE=${LOG_NAMESPACE:-}
LOG_LEVEL=${LOG_LEVEL:-error}

# ╭───┤ Functions
# ╰─

set_theme() {
  case $1 in
    err | error)
      TYPE_LABEL="ERR"
      TYPE_COLOR="\033[31m"
      ;; # Red
    warn | warning)
      TYPE_LABEL="WRN"
      TYPE_COLOR="\033[33m"
      ;; # Yellow
    info)
      TYPE_LABEL="INF"
      TYPE_COLOR="\033[34m"
      ;; # Blue
    success | succ)
      TYPE_LABEL="SUC"
      TYPE_COLOR="\033[32m"
      ;; # Green
  esac
  # \033[1m -> Bold
  TYPE_LABEL_COLORIZED="${TYPE_COLOR}\033[1m${TYPE_LABEL}\033[0m"
}

should_print() {
  case $LOG_LEVEL in
    err | error) [ "$1" = "error" ] || [ "$1" = "err" ] || [ "$1" = "success" ] ;;
    warn | warning) [ "$1" = "error" ] || [ "$1" = "err" ] || [ "$1" = "warning" ] || [ "$1" = "warn" ] || [ "$1" = "success" ] ;;
    info) [ "$1" = "error" ] || [ "$1" = "err" ] || [ "$1" = "warning" ] || [ "$1" = "warn" ] || [ "$1" = "info" ] || [ "$1" = "success" ] ;;
  esac
}

print_message() {
  has_color=$([ -n "$CI" ] && echo "" || echo "true")
  variables=""

  while [ "$#" -gt 0 ]; do
    case $1 in
      -nc | --no-color)
        has_color=""
        shift
        ;;
      -v | --var)
        key=$2
        shift
        value=$2
        shift

        if [ -z "$has_color" ]; then
          variables="$variables $key=$value"
        else
          variables="$variables\033[90m$key=\033[0m$value " # Gray
        fi
        ;;
      --)
        shift
        break
        ;;
      -*)
        echo "Unknown parameter $1" >&2
        exit 1
        ;;
      *) break ;;
    esac
    shift
  done

  timestamp=$(date +%T)
  styled_namespace=""
  if [ -n "$LOG_NAMESPACE" ]; then
    styled_namespace="\033[90m$LOG_NAMESPACE: \033[0m" # Gray
  fi

  if [ -z "$has_color" ]; then
    printf "%s %s %s%s %s\n" "$timestamp" "$TYPE_LABEL" "${LOG_NAMESPACE:+${LOG_NAMESPACE}: }" "$1" "$variables" >&2
  else
    printf "%s %b %b%s %b\n" "$timestamp" "$TYPE_LABEL_COLORIZED" "$styled_namespace" "$1" "$variables" >&2
  fi
}

# ╭───┤ Main. Start here.
# ╰─

message_type=$1
if [ -z "$message_type" ]; then
  set_theme "error"
  print_message "-v" "example" 'log.sh error "Error message"' \
    "No message type provided, expected one of: error, warning, info, success"
  exit 1
fi
shift

if should_print "$message_type"; then
  set_theme "$message_type"
  print_message "$@"
fi
