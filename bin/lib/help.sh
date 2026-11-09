#!/bin/sh

# NAME
#   help.sh - Print the man page of a script
#
# SYNOPSIS
#   . "$_SCRIPT_DIR/../lib/help.sh"
#
# DESCRIPTION
#   Needs log.sh. A script sources it before this file.

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
