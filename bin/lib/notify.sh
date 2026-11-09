#!/bin/sh

# NAME
#   notify.sh - Play the success and cancel sounds
#
# SYNOPSIS
#   . "$_SCRIPT_DIR/../lib/notify.sh"
#
# DESCRIPTION
#   Needs log.sh, validation.sh, os.sh. A script sources them before this
#   file.
#
# ENVIRONMENT
#   NO_NOTIFY   Skips the sounds and notifications when set and non-empty
#
# SEE ALSO
#   doomst, beep_success, beep_cancel

# _notify_cancel
#
# Play the cancel sound, unless NO_NOTIFY is non-empty. beep_cancel comes
# from the dotfiles of the author, so a system without it plays nothing.
_notify_cancel() {
  [ -z "${NO_NOTIFY:-}" ] || return 0

  _run_if_found beep_cancel || _warn "beep_cancel failed"
}

# _notify_success <title> <message>
#
# Play the success sound and send a notification, unless NO_NOTIFY is
# non-empty. Skip either one when its command is missing.
_notify_success() {
  [ -z "${NO_NOTIFY:-}" ] || return 0

  _run_if_found beep_success || _warn "beep_success failed"
  _run_if_found doomst --type success "$1" "$2" || _warn "doomst failed"
}
