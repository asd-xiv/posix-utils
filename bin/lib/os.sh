#!/bin/sh

# NAME
#   os.sh - Create a temporary folder, delete it on exit, find OS folders
#
# SYNOPSIS
#   . "$_SCRIPT_DIR/../lib/os.sh"
#
# DESCRIPTION
#   Needs log.sh, validation.sh. A script sources them before this file.

# _run_if_found <cmd> [arg...]
#
# Run <cmd> with its args when the shell finds it. Do nothing when it does
# not. Use it for an optional command.
#
# RETURNS
#   0       The shell cannot find <cmd>, or <cmd> exits 0
#   other   The status of <cmd>
_run_if_found() {
  command -v "$1" >/dev/null 2>&1 || return 0
  "$@"
}

# _get_user_dir <NAME> <fallback-dir>
#
# Print the XDG user folder <NAME>, eg. PICTURES. Print <fallback-dir> when
# xdg-user-dir is not installed.
_get_user_dir() {
  if command -v xdg-user-dir >/dev/null 2>&1; then
    xdg-user-dir "$1"
  else
    printf '%s\n' "$2"
  fi
}

# _get_runtime_dir
#
# Print the runtime folder of the current user: XDG_RUNTIME_DIR, else
# /run/user/<uid>. The system clears it at boot, so nothing in it outlasts a
# reboot.
#
# EXIT
#   3   XDG_RUNTIME_DIR is unset or empty, and /run/user/<uid> is not a
#       folder
_get_runtime_dir() {
  if [ -n "${XDG_RUNTIME_DIR:-}" ]; then
    printf '%s\n' "$XDG_RUNTIME_DIR"
    return 0
  fi

  lib_grd_dir="/run/user/$(id -u)"
  [ -d "$lib_grd_dir" ] \
    || _fail 3 -v dir "$lib_grd_dir" "No runtime folder, XDG_RUNTIME_DIR is not set"

  printf '%s\n' "$lib_grd_dir"
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

# _create_temp_dir <name>
#
# Create a folder named after <name> under TMPDIR, eg. /tmp/t212.Ab12Cd, and
# print its path. Pass the path to _delete_on_exit on the next line: a signal
# between the two leaves the empty folder behind.
#
# EXIT
#   3   mktemp failed
_create_temp_dir() {
  mktemp -d "${TMPDIR:-/tmp}/$1.XXXXXX" \
    || _fail 3 "Could not create a temporary folder"
}

# _delete_on_exit <path> [on-exit]
#
# Delete <path> when the script exits, or when INT, TERM or HUP stops it. Run
# the function <on-exit> first, with the exit code as its positional: the
# code of the script on EXIT, 130 on INT, 143 on TERM, 129 on HUP. Replaces
# the traps of EXIT, INT, TERM and HUP.
#
# EXIT
#   3   <on-exit> is not a function name
_delete_on_exit() {
  doe_on_exit="${2:-:}"
  if [ "$doe_on_exit" != ":" ] && ! _is identifier "$doe_on_exit"; then
    _fail 3 -v on_exit "$doe_on_exit" "_delete_on_exit takes a function name"
  fi

  # The path goes into the text of the traps, so quote it for the shell
  doe_rm="rm -rf -- '$(printf '%s' "$1" | sed "s/'/'\\\\''/g")'"

  # A signal trap clears the EXIT trap, so <on-exit> runs once. The code is
  # 128 plus the number of the signal, as the shell reports it
  # shellcheck disable=SC2064 # expand the path now, the traps run later
  trap "$doe_on_exit \$?; $doe_rm" EXIT
  # shellcheck disable=SC2064
  trap "$doe_on_exit 130; $doe_rm; trap - EXIT INT; kill -INT $$" INT # Ctrl-C
  # shellcheck disable=SC2064
  trap "$doe_on_exit 143; $doe_rm; trap - EXIT TERM; kill -TERM $$" TERM # kill, timeout, CI cancel
  # shellcheck disable=SC2064
  trap "$doe_on_exit 129; $doe_rm; trap - EXIT HUP; kill -HUP $$" HUP # SSH drop, closed window
}
