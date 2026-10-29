#!/bin/sh

# The lock and the primitives that start and stop both use. Each command
# file sets _SCRIPT_DIR, then sources this file.

. "$_SCRIPT_DIR/../../lib.sh"

# _log reads these
export LOG_NAMESPACE="screenrecord"
export LOG_LEVEL="${LOG_LEVEL:-info}"

# One file per value: pid, state, file, geometry
_LOCK_DIR="$(_get_runtime_dir)/screenrecord.lock"

# ╭───
# │ Primitives
# ╰───

# _get_lock_value <name>
#
# Print the value <name> of the lock, eg. pid. Print nothing when the lock or
# the value is missing.
_get_lock_value() {
  cat -- "$_LOCK_DIR/$1" 2>/dev/null || true
}

# _set_lock_value <name> <value>
#
# Write <value> to the file <name> of the lock. Write a temporary file, then
# move it in place, so a reader never sees half a file.
_set_lock_value() {
  printf '%s\n' "$2" >"$_LOCK_DIR/$1.tmp"
  mv -f -- "$_LOCK_DIR/$1.tmp" "$_LOCK_DIR/$1"
}

# _is_recorder <pid>
#
# Tell if <pid> runs screenrecord start and is not this script. The pid of a
# stale lock can belong to another program by now.
_is_recorder() {
  _is positive-integer "$1" || return 1
  [ "$1" != "$$" ] || return 1

  case "$(ps -p "$1" -o args= 2>/dev/null)" in
    */screenrecord.d/start*) return 0 ;;
  esac

  return 1
}

# _is_lock_free
#
# Tell if the lock is gone, or its pid no longer runs screenrecord start. It
# reads pid each time, as the recording takes the lock over from start.
# shellcheck disable=SC2329 # called by _wait_until
_is_lock_free() {
  [ ! -d "$_LOCK_DIR" ] || ! _is_recorder "$(_get_lock_value pid)"
}
