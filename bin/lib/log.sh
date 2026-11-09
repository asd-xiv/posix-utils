#!/bin/sh

# NAME
#   log.sh - Print log lines to stderr, and end the script on a failure
#
# SYNOPSIS
#   . "$_SCRIPT_DIR/../lib/log.sh"
#
#   export LOG_NAMESPACE="my-script"
#   export LOG_LEVEL="${LOG_LEVEL:-info}"
#
# DESCRIPTION
#   Needs no other file of bin/lib.
#
# ENVIRONMENT
#   LOG_LEVEL       Last level to print, in the order error < warning < info
#                   < debug, in any case or as a short form: err, warn, wrn,
#                   inf, dbg (default: info). An unknown level ends the script
#                   with 2 at its first _log call
#   LOG_NAMESPACE   Label printed before the message
#   NO_LOG_TIME     Hides the time when set and non-empty
#   NO_COLOR        Disables color when set and non-empty
#   TERM            Disables color when unset, empty or "dumb"

# _level_rank <level>
#
# Print the rank of <level>, from 0 for error to 3 for debug. Read <level> in
# any case, as a name or a short form: error/err, warning/warn/wrn, info/inf,
# debug/dbg.
#
# RETURNS
#   1   <level> is not a level or a short form. Prints the reason to stderr
_level_rank() {
  case $(printf '%s' "$1" | tr '[:upper:]' '[:lower:]') in
    error | err) printf '0' ;;
    warning | warn | wrn) printf '1' ;;
    info | inf) printf '2' ;;
    debug | dbg) printf '3' ;;
    *)
      # Print with printf: _log calls _level_rank, so an unknown LOG_LEVEL
      # would loop
      printf 'log.sh/_level_rank: Unknown log level "%s". Use error, warning, info or debug\n' \
        "$1" >&2
      return 1
      ;;
  esac
}

# _has_color [fd]
#
# Tell if <fd> can show color. <fd> defaults to 2, stderr.
#
# RETURNS
#   0   <fd> is a terminal, NO_COLOR is unset or empty, TERM is set and not
#       "dumb"
#   1   One of the three does not hold
#   2   <fd> is not a number
_has_color() {
  [ -t "${1:-2}" ] && [ -z "${NO_COLOR:-}" ] && [ "${TERM:-dumb}" != "dumb" ]
}

# _log <type> [-v <key> <val>]... [--] <message>...
#
# Print one line of <type> to stderr: error, warning, success, info or debug.
# Print nothing when the level of <type> comes after LOG_LEVEL in this order:
# error < warning < info < debug. success has no level, so LOG_LEVEL never
# hides a success line.
#
# Read <type> in any case, as a name or a short form: err, warn, wrn, suc,
# succ, inf, dbg. -v has the long form --var. -- ends the pairs, so a message
# that starts with -v prints as written.
#
# Data always goes through %s. Only the format string holds escapes, so a
# value containing a backslash prints as written.
#
# Newlines inside a <val> print as ",", so a list with one item per line
# reads "a,b,c". <message> prints as written.
#
# EXIT
#   2   <type> is not a type or a short form, or LOG_LEVEL is not a level or a
#       short form
_log() {
  case $(printf '%s' "$1" | tr '[:upper:]' '[:lower:]') in
    error | err) lib_l_level=error lib_l_label="ERR" lib_l_color=31 ;;
    warning | warn | wrn) lib_l_level=warning lib_l_label="WRN" lib_l_color=33 ;;
    success | suc | succ) lib_l_level="" lib_l_label="SUC" lib_l_color=32 ;;
    info | inf) lib_l_level=info lib_l_label="INF" lib_l_color=34 ;;
    debug | dbg) lib_l_level=debug lib_l_label="DBG" lib_l_color=90 ;;
    *)
      printf 'log.sh/_log: Unknown log type "%s". Use error, warning, success, info or debug\n' \
        "$1" >&2
      exit 2
      ;;
  esac
  shift

  lib_l_cutoff=$(_level_rank "${LOG_LEVEL:-info}") || exit 2

  # The success type has no level, so LOG_LEVEL never hides a success line
  if [ -n "$lib_l_level" ]; then
    lib_l_rank=$(_level_rank "$lib_l_level")
    [ "$lib_l_rank" -le "$lib_l_cutoff" ] || return 0
  fi

  if _has_color; then
    [ -z "${NO_LOG_TIME:-}" ] && printf '\033[90m%s\033[0m ' "$(date +%T)" >&2
    printf '\033[1;%sm%s\033[0m ' "$lib_l_color" "$lib_l_label" >&2
    [ -n "${LOG_NAMESPACE:-}" ] \
      && printf '\033[90m%s:\033[0m ' "$LOG_NAMESPACE" >&2
  else
    [ -z "${NO_LOG_TIME:-}" ] && printf '%s ' "$(date +%T)" >&2
    printf '%s ' "$lib_l_label" >&2
    [ -n "${LOG_NAMESPACE:-}" ] && printf '%s: ' "$LOG_NAMESPACE" >&2
  fi

  # Collect the pairs here and print them after the message.
  lib_l_pairs=""
  while [ "$#" -gt 1 ]; do
    case "$1" in
      -v | --var)
        [ "$#" -lt 3 ] && break

        lib_l_value=$(printf '%s' "$3" | tr '\n' ',')
        if _has_color; then
          lib_l_pairs="${lib_l_pairs}$(printf ' \033[90m%s=\033[0m%s' "$2" "$lib_l_value")"
        else
          lib_l_pairs="${lib_l_pairs}$(printf ' %s=%s' "$2" "$lib_l_value")"
        fi
        shift 3
        ;;
      --)
        shift
        break
        ;;
      *) break ;;
    esac
  done

  # The positionals left are the message. Join them with a space, as echo
  # does.
  printf '%s' "$*" >&2
  [ -n "$lib_l_pairs" ] && printf '%s' "$lib_l_pairs" >&2
  printf '\n' >&2

  return 0
}

# _debug, _info, _ok, _warn, _error [-v <key> <val>]... [--] <message>...
#
# Call _log with one type: debug, info, success, warning, error.
#
# EXIT
#   2   LOG_LEVEL is not a level or a short form
_debug() { _log debug "$@"; }
_info() { _log info "$@"; }
_ok() { _log success "$@"; }
_warn() { _log warning "$@"; }
_error() { _log error "$@"; }

# _fail <code> [-v <key> <val>]... [--] <message>...
#
# Print an error line, then exit with <code>.
#
# EXIT
#   <code>   <code> is 1 to 125
#   2        <code> is not 1 to 125, or LOG_LEVEL is not a level or a short form
_fail() {
  lib_f_code=$(printf '%d' "${1:-}" 2>/dev/null) || lib_f_code=0

  if [ "$lib_f_code" -lt 1 ] || [ "$lib_f_code" -gt 125 ]; then
    _log error -v got "${1:-}" "_fail needs an exit code of 1 to 125"
    exit 2
  fi

  shift
  _log error "$@"
  exit "$lib_f_code"
}
