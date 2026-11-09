#!/bin/sh

# NAME
#   sway.sh - Pick, split and clamp a geometry, hide the cursor, in Sway
#
# SYNOPSIS
#   . "$_SCRIPT_DIR/../lib/sway.sh"
#
# DESCRIPTION
#   Needs log.sh. A script sources it before this file.
#
# SEE ALSO
#   swaymsg(1), slurp(1), jq(1)

# _split_geometry <geometry>
#
# Print the four numbers of <geometry>, eg. "10,20 30x40" gives
# "10 20 30 40".
_split_geometry() {
  lib_sg_y=${1#*,}
  lib_sg_size=${1##* }

  printf '%s %s %s %s\n' \
    "${1%%,*}" "${lib_sg_y%% *}" "${lib_sg_size%%x*}" "${lib_sg_size#*x}"
}

# _clamp_geometry <geometry> <bounds>
#
# Print the part of <geometry> inside the geometry <bounds>, eg.
# "-10,-10 120x60" in "0,0 1920x1080" gives "0,0 110x50".
#
# RETURNS
#   1   No part of <geometry> is inside <bounds>. Prints nothing
_clamp_geometry() {
  # shellcheck disable=SC2046 # _split_geometry prints four words
  set -- $(_split_geometry "$1") $(_split_geometry "$2")

  lib_cg_left=$1 lib_cg_top=$2
  lib_cg_right=$(($1 + $3)) lib_cg_bottom=$(($2 + $4))
  [ "$lib_cg_left" -ge "$5" ] || lib_cg_left=$5
  [ "$lib_cg_top" -ge "$6" ] || lib_cg_top=$6
  [ "$lib_cg_right" -le $(($5 + $7)) ] || lib_cg_right=$(($5 + $7))
  [ "$lib_cg_bottom" -le $(($6 + $8)) ] || lib_cg_bottom=$(($6 + $8))

  if [ "$lib_cg_right" -le "$lib_cg_left" ] \
    || [ "$lib_cg_bottom" -le "$lib_cg_top" ]; then
    return 1
  fi

  printf '%s,%s %sx%s\n' "$lib_cg_left" "$lib_cg_top" \
    "$((lib_cg_right - lib_cg_left))" "$((lib_cg_bottom - lib_cg_top))"
}

# _require_sway
#
# End the script unless it runs in a Sway session.
#
# EXIT
#   3   SWAYSOCK is unset or empty
_require_sway() {
  [ -n "${SWAYSOCK:-}" ] || _fail 3 "No Sway session, SWAYSOCK is not set"
}

# _pick_sway_geometry <window|region>
#
# Let the user pick with slurp and print the geometry: a visible window they
# click, or a rectangle they draw.
#
# RETURNS
#   1   The user pressed Esc, or no window is visible
_pick_sway_geometry() {
  case "$1" in
    window)
      swaymsg -t get_tree | jq -r '.. | objects | select(.pid? and .visible?)
        | "\(.rect.x),\(.rect.y) \(.rect.width)x\(.rect.height)"' \
        | slurp -r
      ;;
    *) slurp ;;
  esac
}

_IS_SWAY_CURSOR_HIDDEN="" # "true" once _hide_sway_cursor hid the cursor

# _hide_sway_cursor
#
# Hide the cursor until _restore_sway_cursor. Sway hides it once it stops
# moving for 100 ms, so wait 0.2 s.
_hide_sway_cursor() {
  _IS_SWAY_CURSOR_HIDDEN="true"
  swaymsg --quiet "seat - hide_cursor 100" >/dev/null 2>&1 \
    || _warn "Could not hide the cursor"
  sleep 0.2
}

# _restore_sway_cursor
#
# Set the Sway hide_cursor timeout back to 0, the Sway default: never hide.
# A hide_cursor from the sway config stays off until the next reload.
_restore_sway_cursor() {
  if [ -n "$_IS_SWAY_CURSOR_HIDDEN" ]; then
    swaymsg --quiet "seat - hide_cursor 0" >/dev/null 2>&1 || true
    _IS_SWAY_CURSOR_HIDDEN=""
  fi
}
