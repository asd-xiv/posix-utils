#!/bin/sh

# NAME
#   validation.sh - Tell if a value has a shape, eg. a slug or a geometry
#
# SYNOPSIS
#   . "$_SCRIPT_DIR/../lib/validation.sh"
#
# DESCRIPTION
#   Needs log.sh. A script sources it before this file.

# _is <type> <value>
#
# Tell if <value> has the shape of <type>.
#
#   positive-integer       0-9, no leading zero
#   non-negative-integer   0, or a positive-integer
#   version                0-9 in groups, one dot between two groups, eg.
#                          1.13.4
#   slug                   A-Za-z0-9_-, starts with a letter or a digit
#   identifier             A-Za-z0-9_, cannot start with a digit
#   folgezettel            a-z0-9, starts with 1-9, a run of digits never
#                          starts with 0, eg. 1b3. 1b03 and 1b3 would name
#                          one place
#   geometry               "<x>,<y> <width>x<height>", the shape grim, slurp
#                          and wf-recorder read, eg. "-10,0 800x600". x and
#                          y are integers, width and height positive
#
# RETURNS
#   0   <value> has the shape
#   1   <value> does not have it, or is empty
#
# EXIT
#   3   <type> is not a type above and <value> is not empty, or the call
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
    non-negative-integer)
      # 0?* rejects a leading zero. Shell arithmetic reads 010 as octal 8
      case "$2" in
        *[!0-9]* | 0?*) return 1 ;;
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
    geometry)
      case "$2" in
        *[!0-9,x\ -]* | *,*,* | *" "*" "* | *x*x*) return 1 ;;
        *,*" "*x*) ;;
        *) return 1 ;;
      esac

      # "-10,0 800x600": x, y, then the size
      lib_is_x=${2%%,*}
      lib_is_y=${2#*,}
      lib_is_y=${lib_is_y%% *}
      lib_is_size=${2##* }
      _is non-negative-integer "${lib_is_x#-}" \
        && _is non-negative-integer "${lib_is_y#-}" \
        && _is positive-integer "${lib_is_size%%x*}" \
        && _is positive-integer "${lib_is_size#*x}" \
        || return 1
      ;;
    *)
      _fail 3 -v type "$1" "Unknown type"
      ;;
  esac

  return 0
}
