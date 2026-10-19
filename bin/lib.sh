#!/bin/sh

# NAME
#   lib.sh - Shared primitives for posix-utils scripts
#
# SYNOPSIS
#   SCRIPT_DIR=$(dirname "$(realpath "$0")")
#   . "$SCRIPT_DIR/../lib.sh"
#
#   export LOG_NAMESPACE="my-script"
#   export LOG_LEVEL="${LOG_LEVEL:-info}"
#
# DESCRIPTION
#   Domain-agnostic primitives: logging, predicates, guards, files, text,
#   terminal and help. A script sources it, never executes it.
#
#   A primitive prints its result to stdout. A predicate answers with its
#   status and prints nothing. Everything else goes to stderr.
#
#   The comment above each function lists its statuses under RETURNS and its
#   exit codes under EXIT.
#
#   Only _is checks its positional count. Under set -u, a missing positional
#   ends the script with the shell's own code.
#
# ENVIRONMENT
#   LOG_LEVEL       Last level to print, in the order of _log (default: info).
#                   An unknown level ends the script with 2 at the first log
#                   line
#   LOG_NAMESPACE   Label printed before the message
#   NO_LOG_TIME     Hides the time when set and non-empty
#   NO_COLOR        Disables color when set and non-empty
#   TERM            Disables color when unset, empty or "dumb"
#
# SEE ALSO
#   curl(1)

# ╭───
# │ Logging
# ╰───

# _level_rank <level>
#
# Print the rank of <level>, from 0 for error to 4 for debug.
#
# RETURNS
#   1   <level> is not a level or a short form, the reason is on stderr
_level_rank() {
  case "$1" in
    error | err) printf '0' ;;
    warning | wrn | warn) printf '1' ;;
    success | suc | succ) printf '2' ;;
    info | inf) printf '3' ;;
    debug | dbg) printf '4' ;;
    *)
      # Not through _log, which calls back here
      printf 'lib.sh/_level_rank: Unknown log level "%s". Use error, warning, success, info or debug\n' \
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

# _log <level> [-v <key> <val>]... [--] <message>...
#
# Print one line to stderr at <level>. Print nothing when <level> comes after
# LOG_LEVEL in this order: error < warning < success < info < debug.
#
# <level> also has short forms: err, wrn, warn, suc, succ, inf, dbg. -v has the
# long form --var. -- ends the pairs, so a message that starts with -v prints as
# written.
#
# Data always goes through %s. Only the format string holds escapes, so a
# value containing a backslash prints as written.
#
# Newlines inside a <val> print as ",", so a list with one item per line
# reads "a,b,c". <message> prints as written.
#
# EXIT
#   2   <level> or LOG_LEVEL is not a level or a short form
_log() {
  lib_l_level="$1"
  shift

  lib_l_rank=$(_level_rank "$lib_l_level") || exit 2
  lib_l_cutoff=$(_level_rank "${LOG_LEVEL:-info}") || exit 2

  [ "$lib_l_rank" -le "$lib_l_cutoff" ] || return 0

  case "$lib_l_level" in
    error | err) lib_l_label="ERR" lib_l_color=31 ;;
    warning | wrn | warn) lib_l_label="WRN" lib_l_color=33 ;;
    success | suc | succ) lib_l_label="SUC" lib_l_color=32 ;;
    info | inf) lib_l_label="INF" lib_l_color=34 ;;
    debug | dbg) lib_l_label="DBG" lib_l_color=90 ;;
  esac

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
# Call _log at one level: debug, info, success, warning, error.
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
# Print at error level, then exit with <code>.
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

# ╭───
# │ Predicates & Guards
# ╰───

# _is <type> <value>
#
# Tell if <value> has the shape of <type>.
#
#   positive-integer   0-9, no leading zero
#   version            0-9 in groups, one dot between two groups, eg. 1.13.4
#   slug               A-Za-z0-9_-, starts with a letter or a digit
#   identifier         A-Za-z0-9_, cannot start with a digit
#   folgezettel        a-z0-9, starts with 1-9, a run of digits never starts
#                      with 0, eg. 1b3. 1b03 and 1b3 would name one place
#
# RETURNS
#   0   <value> has the shape
#   1   <value> does not have it, or is empty
#
# EXIT
#   3   <type> is not one of the five and <value> is not empty, or the call
#       does not have two positionals
_is() {
  [ "$#" -eq 2 ] || _fail 3 "_is needs <type> <value>"
  [ -n "$2" ] || return 1

  # Reject with a negated class, which checks every character.
  # [A-Za-z_][A-Za-z0-9_]* checks two characters and accepts "ab; rm -rf /".
  # Inside a class, put "-" last and "]" first.
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
        *[!A-Za-z0-9_-]* | [_-]*) return 1 ;;
      esac
      ;;
    identifier)
      case "$2" in
        *[!A-Za-z0-9_]* | [0-9]*) return 1 ;;
      esac
      ;;
    folgezettel)
      case "$2" in
        *[!0-9a-z]* | [!1-9]* | *[a-z]0*) return 1 ;;
      esac
      ;;
    *)
      _fail 3 -v type "$1" "Unknown type"
      ;;
  esac

  return 0
}

# _require_cmd <cmd>...
#
# End the script unless the shell finds every <cmd>.
#
# EXIT
#   3   The shell cannot find a <cmd>
_require_cmd() {
  lib_rc_missing=""
  for lib_rc_cmd in "$@"; do
    command -v "$lib_rc_cmd" >/dev/null 2>&1 \
      || lib_rc_missing="${lib_rc_missing:+$lib_rc_missing, }$lib_rc_cmd"
  done

  [ -n "$lib_rc_missing" ] \
    && _fail 3 -v missing "$lib_rc_missing" "Required commands not found"

  return 0
}

# _require_var <NAME>...
#
# End the script unless every <NAME> is set and non-empty.
#
# EXIT
#   2   A <NAME> is unset or empty
#   3   A <NAME> is not an identifier
_require_var() {
  lib_rv_missing=""
  for lib_rv_name in "$@"; do
    _is identifier "$lib_rv_name" \
      || _fail 3 -v name "$lib_rv_name" "_require_var takes variable names"

    eval "lib_rv_value=\${$lib_rv_name:-}"
    [ -z "$lib_rv_value" ] \
      && lib_rv_missing="${lib_rv_missing:+$lib_rv_missing, }$lib_rv_name"
  done

  [ -n "$lib_rv_missing" ] \
    && _fail 2 -v missing "$lib_rv_missing" "Required variables not set"

  return 0
}

# ╭───
# │ Files
# ╰───

# _download_file <url> <output-file>
#
# Download <url> into <output-file>.
#
# EXIT
#   3   curl is not on PATH, or the download fails
_download_file() {
  _require_cmd curl
  curl --silent --show-error --fail --location --output "$2" "$1" \
    || _fail 3 -v url "$1" "Download failed"
}

# _resolve_bin_dir
#
# Print the first writable bin dir of /usr/local/bin and ~/.local/bin.
# ~/.local/bin is the user bin dir in the "XDG Base Directory Specification":
# https://specifications.freedesktop.org/basedir/latest/
#
# EXIT
#   3   Neither /usr/local/bin nor ~/.local/bin is a writable directory
_resolve_bin_dir() {
  for lib_rbd_dir in /usr/local/bin "${HOME:-}/.local/bin"; do
    [ -d "$lib_rbd_dir" ] && [ -w "$lib_rbd_dir" ] && {
      printf '%s' "$lib_rbd_dir"
      return 0
    }
  done

  _fail 3 -v current_user "$(whoami)" \
    "No writable bin dir (/usr/local/bin, ~/.local/bin)"
}

# ╭───
# │ Text
# ╰───

# _end_with_newline <text>
#
# Print <text> with a newline at its end, the one $(...) strips. Print nothing
# when <text> is empty, where a plain printf would print one empty line.
_end_with_newline() {
  if [ -n "$1" ]; then
    printf '%s\n' "$1"
  fi
}

# A block is the lines between two marker lines, <begin> and <end>, in a text
# that otherwise belongs to someone else: a crontab, a shell profile. A marker
# is a whole line, compared as written. A text must hold no block, or exactly
# one: one <begin>, and one <end> below it.
#
# awk reads the markers and the block lines from its environment, because
# awk -v rewrites a backslash in them. awk compares two values that look like
# numbers as numbers, so a marker "10" would match a line "10.0". "" after a
# value makes it a string.

# _has_valid_markers <begin> <end> <text>
#
# Tell if the markers in <text> make no block, or exactly one.
#
# RETURNS
#   0   <text> has neither marker, or each marker once with <begin> above <end>
#   1   A marker is there more than once or alone, or <begin> is not above
#       <end>
#
# EXIT
#   3   A marker is empty or holds a newline
_has_valid_markers() {
  # An empty marker matches every empty line, one with a newline matches none
  case "$1$2" in
    *"
"*) _fail 3 "A marker is one line" ;;
  esac

  if [ -z "$1" ] || [ -z "$2" ]; then
    _fail 3 "A marker cannot be empty"
  fi

  # The line number of each marker. -F -x is the whole line, as written
  lib_hvm_begin=$(printf '%s\n' "$3" | grep -n -F -x -e "$1" | cut -d ':' -f 1)
  lib_hvm_end=$(printf '%s\n' "$3" | grep -n -F -x -e "$2" | cut -d ':' -f 1)

  # Each is one number, when its marker is there once
  case "$lib_hvm_begin:$lib_hvm_end" in
    :) return 0 ;;                   # neither marker
    *[!0-9:]* | :* | *:) return 1 ;; # one is there twice, or one is missing
  esac

  [ "$lib_hvm_begin" -lt "$lib_hvm_end" ] || return 1

  return 0
}

# _find_block <begin> <end>
#
# Read a text from stdin, print the lines of its block without the markers.
# Print nothing when the text has no block.
#
# RETURNS
#   1   A marker is there more than once or alone, or <begin> is not above
#       <end>. Prints nothing
#
# EXIT
#   3   A marker is empty or holds a newline
_find_block() {
  lib_fb_text=$(cat)
  _has_valid_markers "$1" "$2" "$lib_fb_text" || return 1

  printf '%s\n' "$lib_fb_text" \
    | BLOCK_BEGIN_MARKER="$1" BLOCK_END_MARKER="$2" awk '
      BEGIN {
        begin = ENVIRON["BLOCK_BEGIN_MARKER"] ""
        end = ENVIRON["BLOCK_END_MARKER"] ""
      }

      $0 == begin { is_inside = 1; next }
      $0 == end { is_inside = 0 }
      is_inside { print }'
}

# _replace_block <begin> <end> <lines>
#
# Read a text from stdin, print it with the lines of its block replaced by
# <lines>. Add the block and its markers at the end when the text has none.
# Drop both when <lines> is empty.
#
# Take the result into a variable and read the status before writing it
# anywhere. In a pipe, the next command reads an empty text when
# _replace_block returns 1 or 2.
#
# RETURNS
#   1   A marker is there more than once or alone, or <begin> is not above
#       <end>. Prints nothing
#   2   One of <lines> is a marker. Prints nothing
#
# EXIT
#   3   A marker is empty or holds a newline
_replace_block() {
  lib_rb_text=$(cat)
  _has_valid_markers "$1" "$2" "$lib_rb_text" || return 1

  # A marker inside the block would make two blocks of it
  if printf '%s\n' "$3" | grep -q -F -x -e "$1" -e "$2"; then
    return 2
  fi

  _end_with_newline "$lib_rb_text" | BLOCK_BEGIN_MARKER="$1" BLOCK_END_MARKER="$2" BLOCK_LINES="$3" awk '
    function put_block() {
      if (lines != "") {
        print begin
        print lines
        print end
      }
      is_put = 1
    }

    BEGIN {
      begin = ENVIRON["BLOCK_BEGIN_MARKER"] ""
      end = ENVIRON["BLOCK_END_MARKER"] ""
      lines = ENVIRON["BLOCK_LINES"] ""
    }

    $0 == begin { is_inside = 1; next }
    $0 == end { is_inside = 0; put_block(); next }
    !is_inside { print }

    END { if (!is_put) put_block() }'
}

# _diff_lines <old-text> <new-text>
#
# Print what changed between two sets of lines: "- <line>" for a line only in
# <old-text>, then "+ <line>" for a line only in <new-text>. The order of the
# lines, repeats and empty lines do not count.
#
# Print the "-" lines red and the "+" lines green when stdout can show color,
# see _has_color.
_diff_lines() {
  lib_dl_color=""
  if _has_color 1; then
    lib_dl_color="true"
  fi

  DIFF_OLD_TEXT="$1" DIFF_NEW_TEXT="$2" awk -v color="$lib_dl_color" '
    BEGIN {
      old_count = split(ENVIRON["DIFF_OLD_TEXT"], old_lines, "\n")
      new_count = split(ENVIRON["DIFF_NEW_TEXT"], new_lines, "\n")

      minus = color ? "\033[31m- %s\033[0m\n" : "- %s\n"
      plus = color ? "\033[32m+ %s\033[0m\n" : "+ %s\n"

      for (i = 1; i <= old_count; i++) is_old[old_lines[i]] = 1
      for (i = 1; i <= new_count; i++) is_new[new_lines[i]] = 1

      for (i = 1; i <= old_count; i++) {
        line = old_lines[i]
        if (line != "" && !(line in is_new) && !(line in is_printed)) {
          printf minus, line
          is_printed[line] = 1
        }
      }

      for (i = 1; i <= new_count; i++) {
        line = new_lines[i]
        if (line != "" && !(line in is_old) && !(line in is_printed)) {
          printf plus, line
          is_printed[line] = 1
        }
      }
    }'
}

# ╭───
# │ Terminal
# ╰───

_HAS_TITLE="" # "true" once _set_title changed the window title

# _set_title <title>
#
# Name the terminal window, when stderr is a terminal. The escape codes are
# xterm's and most terminals read them, a flag such as --title differs per
# terminal. The first code saves the old title, _restore_title restores it.
_set_title() {
  [ -t 2 ] || return 0

  printf '\033[22;0t\033]0;%s\007' "$1" >&2
  _HAS_TITLE="true"
}

# _restore_title
#
# Restore the title that _set_title saved. The window may be gone, and a
# failed write must not stop the rest.
_restore_title() {
  if [ -n "$_HAS_TITLE" ]; then
    printf '\033[23;0t' >&2 2>/dev/null || true
    _HAS_TITLE=""
  fi
}

# _wait_for_enter
#
# Stop until the user presses Enter. A window opened only for the calling
# command closes with it, before the user reads what it shows. Without a
# terminal on stdin, read takes the next line or finds none, and the wait
# ends at once.
_wait_for_enter() {
  printf 'Press Enter to continue ' >&2
  # shellcheck disable=SC2034 # read needs a name, nobody reads it
  read -r lib_wfe_reply || true
}

# ╭───
# │ Help
# ╰───

# _show_help <script-file>
#
# Print the man page of <script-file>: the comment block that starts at its
# NAME line.
#
# EXIT
#   2   <script-file> is not a file
_show_help() {
  if [ ! -f "$1" ]; then
    _fail 2 -v path "$1" "Script not found"
  fi

  sed -n '/^# NAME$/,/^$/p' "$1" \
    | sed -e 's/^# \{0,1\}//'
}
