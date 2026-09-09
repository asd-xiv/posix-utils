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
# Print at error level, then exit with <code>. Valid exit codes between 1 and 125.
_fail() {
  fail_code=$(printf '%d' "${1:-}" 2>/dev/null) || fail_code=0

  if [ "$fail_code" -lt 1 ] || [ "$fail_code" -gt 125 ]; then
    _log error -v got "${1:-}" "_fail needs an exit code of 1 to 125."
    exit 2
  fi

  shift
  _log error "$@"
  exit "$fail_code"
}

# ╭───
# │ Predicates & Guards
# ╰───

# _is <type> <value>
#
# Predicate checking common value shapes. Returns 1 on no, exits 3 on a type it
# does not know.
#
#   positive-integer   0-9, no leading zero
#   version            0-9 and dots, eg. 1.13.4
#   slug               A-Za-z0-9_-
#   identifier         A-Za-z0-9_, cannot start with a digit
#
# Each type rejects with a negated class, the only form that reads the whole
# string. [A-Za-z_][A-Za-z0-9_]* tests two characters and lets the rest through,
# accepting "ab; rm -rf /". Inside a class "-" goes last and "]" first.
_is() {
  [ "$#" -eq 2 ] || _fail 3 "_is needs <type> <value>."
  [ -n "$2" ] || return 1

  case "$1" in
    positive-integer)
      # 0* rejects zero and every leading zero with it, so no arithmetic runs
      # and a 20-digit value cannot abort the shell with "Illegal number".
      case "$2" in
        *[!0-9]* | 0*) return 1 ;;
      esac
      ;;
    version)
      case "$2" in
        *[!0-9.]* | .* | *. | *..*) return 1 ;;
      esac
      ;;
    slug)
      case "$2" in
        *[!A-Za-z0-9_-]*) return 1 ;;
      esac
      ;;
    identifier)
      case "$2" in
        *[!A-Za-z0-9_]* | [0-9]*) return 1 ;;
      esac
      ;;
    *)
      _fail 3 -v type "$1" "Unknown type."
      ;;
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
    _is identifier "$require_name" \
      || _fail 3 -v name "$require_name" "_require_var takes variable names."

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
