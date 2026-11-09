#!/bin/sh

# NAME
#   wait.sh - Run a command until it succeeds, or until a time runs out
#
# SYNOPSIS
#   . "$_SCRIPT_DIR/../lib/wait.sh"
#
# DESCRIPTION
#   Needs no other file of bin/lib.

# _wait_until <seconds> <cmd> [arg...]
#
# Run <cmd> every 0.05 s until it exits 0, for up to <seconds>. <seconds>
# must be a positive integer. sleep 0.05 is not POSIX. coreutils and
# BusyBox read a fraction.
#
# RETURNS
#   1   <cmd> did not exit 0 in <seconds>
_wait_until() {
  lib_wu_tries=$(($1 * 20))
  shift

  until "$@"; do
    [ "$lib_wu_tries" -gt 0 ] || return 1
    lib_wu_tries=$((lib_wu_tries - 1))
    sleep 0.05
  done
}
