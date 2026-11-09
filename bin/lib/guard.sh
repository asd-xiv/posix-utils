#!/bin/sh

# NAME
#   guard.sh - End the script when a command, a variable or a display is missing
#
# SYNOPSIS
#   . "$_SCRIPT_DIR/../lib/guard.sh"
#
# DESCRIPTION
#   Needs log.sh, validation.sh. A script sources them before this file.

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

# _require_display
#
# End the script unless WAYLAND_DISPLAY or DISPLAY is set. Without a
# display, rofi exits 1, the same status as on Esc.
#
# EXIT
#   3   WAYLAND_DISPLAY and DISPLAY are unset or empty
_require_display() {
  [ -n "${WAYLAND_DISPLAY:-}${DISPLAY:-}" ] || _fail 3 "No Wayland or X display"
}
