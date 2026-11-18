#!/bin/sh

# NAME
#   terminal.sh - Set and restore the title of the terminal, wait for Enter
#
# SYNOPSIS
#   . "$_SCRIPT_DIR/../lib/terminal.sh"
#
# DESCRIPTION
#   Needs log.sh, os.sh. A script sources them before this file.

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

# _set_title_until_exit <title>
#
# Name the terminal window <title> until the script exits, or until INT, TERM
# or HUP ends it, then restore the old title. It registers _restore_title
# with _on_exit.
_set_title_until_exit() {
  _on_exit _restore_title
  _set_title "$1"
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
