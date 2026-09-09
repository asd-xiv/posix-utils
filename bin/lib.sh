#!/bin/sh

# NAME
#   lib.sh - Shared primitives for posix-utils scripts
#
# SYNOPSIS
#   SCRIPT_DIR=$(dirname "$(realpath "$0")")
#   LOG_NAMESPACE="my-script"
#   . "$SCRIPT_DIR/../lib.sh"
#
# DESCRIPTION
#   Sourced, never executed. A primitive that answers a question prints the
#   answer to stdout. Everything else goes to stderr.
#
#   Logging is ordered: error < warning < success < info < debug.
#   LOG_LEVEL is the cut-off: it and everything before it print.
#
# ENVIRONMENT
#   LOG_LEVEL       Cut-off level to print (default: info)
#   LOG_NAMESPACE   Label printed before the message
#   NO_COLOR        If set, disables color
#
# SEE ALSO
#   fancy-log, curl(1)

# ╭───
# │ Logging
# ╰───

# Ordered scale. A level prints when its rank is <= the LOG_LEVEL rank.
_level_rank() {
  case "$1" in
    error) echo 0 ;;
    warning) echo 1 ;;
    success) echo 2 ;;
    info) echo 3 ;;
    debug) echo 4 ;;
    *) echo 99 ;;
  esac
}

# Color only when stderr is a terminal that wants it.
_has_color() {
  [ -t 2 ] && [ -z "${NO_COLOR:-}" ] && [ "${TERM:-dumb}" != "dumb" ]
}

# _log <level> [-v <key> <val>]... <message>
#
# Data always goes through %s. Escapes live in the format string only,
# so a value containing a backslash prints as written.
_log() {
  log_level="$1"
  shift

  [ "$(_level_rank "$log_level")" -le "$(_level_rank "${LOG_LEVEL:-info}")" ] || return 0

  case "$log_level" in
    error) log_label="ERR" log_color=31 ;;
    warning) log_label="WRN" log_color=33 ;;
    success) log_label="SUC" log_color=32 ;;
    info) log_label="INF" log_color=34 ;;
    *) log_label="DBG" log_color=90 ;;
  esac

  if _has_color; then
    printf '\033[90m%s\033[0m \033[1;%sm%s\033[0m ' \
      "$(date +%T)" "$log_color" "$log_label" >&2
    [ -n "${LOG_NAMESPACE:-}" ] \
      && printf '\033[90m%s:\033[0m ' "$LOG_NAMESPACE" >&2
  else
    printf '%s %s ' "$(date +%T)" "$log_label" >&2
    [ -n "${LOG_NAMESPACE:-}" ] && printf '%s: ' "$LOG_NAMESPACE" >&2
  fi

  # Pairs are collected first, then printed after the message, so the
  # message reads first and the data trails it.
  log_pairs=""
  while [ "$#" -gt 1 ]; do
    case "$1" in
      -v | --var)
        [ "$#" -lt 3 ] && break
        if _has_color; then
          log_pairs="${log_pairs}$(printf ' \033[90m%s=\033[0m%s' "$2" "$3")"
        else
          log_pairs="${log_pairs}$(printf ' %s=%s' "$2" "$3")"
        fi
        shift 3
        ;;
      *) break ;;
    esac
  done

  printf '%s' "${1:-}" >&2
  [ -n "$log_pairs" ] && printf '%s' "$log_pairs" >&2
  printf '\n' >&2

  return 0
}

_debug() { _log debug "$@"; }
_info() { _log info "$@"; }
_ok() { _log success "$@"; }
_warn() { _log warning "$@"; }

# _fail <code> [-v <key> <val>]... <message>
#
# Print at error level, then exit with <code>. What a code means is the
# caller's convention, not this library's, so every call names its own:
#
#   _fail 2 "--max needs a count."
#   _fail 3 -v status "$status" "grep failed."
#
# The rest goes to _log untouched. Inside $( ) it exits the subshell only.
_fail() {
  # Checked here, not through _assert, which would call _fail back.
  # This also catches a call that forgot the code and passed a message.
  case "${1:-}" in
    "" | *[!0-9]* | 0)
      _log error -v got "${1:-}" "_fail needs an exit code of 1 or more."
      exit 1
      ;;
  esac

  fail_code="$1"
  shift

  _log error "$@"
  exit "$fail_code"
}

# ╭───
# │ Guards
# ╰───

# _assert <type> <label> <value>
#
# Exit 2 unless <value> has the shape <type> names. Every type here is
# domain-agnostic. A script that needs a shape of its own writes it as a local
# guard in the same form, eg. assert_package in cli/omnipack.
#
#   positive-integer   0-9, no leading zero
#   version            0-9 and dots, eg. 1.13.4
#   slug               A-Za-z0-9_-
#   identifier         A-Za-z0-9_, cannot start with a digit
#
# Every type rejects with a negated class, the only form that reads the whole
# string. A positive pattern is a fixed number of bracket expressions and a
# trailing *, so [A-Za-z_][A-Za-z0-9_]* tests characters one and two and lets
# everything after them through — it accepts "ab; rm -rf /" and rejects "a".
#
# Inside a class "-" goes last and "]" first, or the class means something else.
_assert() {
  [ "$#" -eq 3 ] || _fail 3 "_assert needs <type> <label> <value>."
  [ -n "$3" ] || _fail 2 -v type "$1" "Empty $2."

  case "$1" in
    positive-integer)
      # 0* rejects zero and every leading zero with it, so no arithmetic runs
      # and a 20-digit value cannot abort the shell with "Illegal number".
      case "$3" in
        *[!0-9]* | 0*) _fail 2 -v "$2" "$3" "Not a whole number above zero." ;;
      esac
      ;;
    version)
      case "$3" in
        *[!0-9.]* | .* | *. | *..*)
          _fail 2 -v "$2" "$3" "Not a version number."
          ;;
      esac
      ;;
    slug)
      case "$3" in
        *[!A-Za-z0-9_-]*) _fail 2 -v "$2" "$3" "Not a slug." ;;
      esac
      ;;
    identifier)
      case "$3" in
        *[!A-Za-z0-9_]* | [0-9]*) _fail 2 -v "$2" "$3" "Not an identifier." ;;
      esac
      ;;
    *) _fail 3 -v type "$1" "Unknown type." ;;
  esac

  return 0
}

# _require_cmd <cmd>...
_require_cmd() {
  require_missing=""
  for require_cmd in "$@"; do
    command -v "$require_cmd" >/dev/null 2>&1 \
      || require_missing="${require_missing:+$require_missing, }$require_cmd"
  done

  [ -n "$require_missing" ] \
    && _fail 3 -v missing "$require_missing" "Required commands not found."

  return 0
}

# _require_var <NAME>...
_require_var() {
  require_missing=""
  for require_name in "$@"; do
    _assert identifier var "$require_name"

    eval "require_value=\${$require_name:-}"
    [ -z "$require_value" ] \
      && require_missing="${require_missing:+$require_missing, }$require_name"
  done

  [ -n "$require_missing" ] \
    && _fail 2 -v missing "$require_missing" "Required variables not set."

  return 0
}

# ╭───
# │ Files
# ╰───

# _download_file <url> <output-path>
_download_file() {
  _require_cmd curl
  curl --silent --show-error --fail --location --output "$2" "$1" \
    || _fail 3 -v url "$1" "Download failed."
}

# _resolve_bin_dir
# Print the first writable directory for system binaries.
_resolve_bin_dir() {
  for resolve_dir in /usr/local/bin /usr/bin; do
    [ -d "$resolve_dir" ] && [ -w "$resolve_dir" ] && {
      printf '%s' "$resolve_dir"
      return 0
    }
  done

  _fail 3 "No writable bin dir (/usr/local/bin, /usr/bin). Run as root?"
}

# ╭───
# │ Help
# ╰───

# _show_help <script-path>
# Print the first NAME comment block of a script to stdout.
_show_help() {
  if [ ! -f "$1" ]; then
    _fail 2 -v path "$1" "Script not found."
  fi

  sed -n '/^# NAME$/,/^$/p' "$1" \
    | sed -e 's/^# \{0,1\}//'
}
