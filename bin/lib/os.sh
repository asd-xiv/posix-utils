#!/bin/sh

# NAME
#   os.sh - Run functions on exit, create a temporary folder and delete it on
#   exit, find OS folders
#
# SYNOPSIS
#   . "$_SCRIPT_DIR/../lib/os.sh"
#
# DESCRIPTION
#   Needs log.sh. A script sources it before this file.

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

_EXIT_FUNCTIONS="" # space-separated, the last registered first
_DELETE_DIR=""     # the folder to delete on exit

# _on_exit <function>
#
# Register <function> to run when the script exits, or when INT, TERM or HUP
# ends it. <function> gets the exit code as $1: the code of the script on
# EXIT, 130 on INT, 143 on TERM, 129 on HUP. The last function registered runs
# first, and each runs once. A failed one does not stop the rest.
#
# _on_exit owns the traps of EXIT, INT, TERM and HUP. Its first call replaces
# any the script set, and a later `trap` on one of them replaces its own.
#
# Call it in the main shell. A subshell, eg. $(...), starts with no traps but
# keeps _EXIT_FUNCTIONS. If the list is empty, _on_exit sets the traps of the
# subshell, and the function runs when the subshell exits. If not, it sets no
# trap, and the function never runs.
#
# EXIT
#   3   <function> is not a defined function
_on_exit() {
  # command -v prints the name of a function, a builtin or a reserved word, the
  # path of a program, or nothing. A builtin passes, eg. `true`, and does no
  # harm
  [ "$(command -v -- "$1")" = "$1" ] \
    || _fail 3 -v function "$1" "_on_exit takes a defined function"

  # The traps read _EXIT_FUNCTIONS when they run, so only the first call sets
  # the traps
  if [ -z "$_EXIT_FUNCTIONS" ]; then
    trap '_run_exit_functions $?' EXIT
    trap '_end_by_signal INT 130' INT   # Ctrl-C
    trap '_end_by_signal TERM 143' TERM # kill, timeout, cancelled CI job
    trap '_end_by_signal HUP 129' HUP   # lost SSH connection, closed window
  fi

  _EXIT_FUNCTIONS="$1 $_EXIT_FUNCTIONS"
}

# _run_exit_functions <exit-code>
#
# Take each function off _EXIT_FUNCTIONS, then run it with <exit-code>. A
# function that exits during a signal trap makes the shell run the EXIT trap,
# which runs only the functions left.
_run_exit_functions() {
  while [ -n "$_EXIT_FUNCTIONS" ]; do
    lib_ref_function=${_EXIT_FUNCTIONS%% *}
    _EXIT_FUNCTIONS=${_EXIT_FUNCTIONS#* }
    "$lib_ref_function" "$1" || true
  done
}

# _end_by_signal <signal> <exit-code>
#
# Run the functions _on_exit registered with <exit-code>, then end the script
# by <signal>, so its caller sees the signal. A trap runs in place of the
# default action of <signal>, so _end_by_signal clears the traps of EXIT and
# <signal>, then resends <signal>.
_end_by_signal() {
  _run_exit_functions "$2"
  trap - EXIT "$1"
  kill -s "$1" $$
}

# _delete_on_exit <dir>
#
# Delete the absolute folder <dir> when the script exits, or when INT, TERM or
# HUP ends it. A function that a later _on_exit call registers runs first.
#
# A script calls it once. Create any other temporary folder inside <dir>, eg.
# `mktemp -d "$_TEMP_DIR/part.XXXXXX"`.
#
# EXIT
#   3   A second call, or a <dir> that is not an absolute path
_delete_on_exit() {
  [ -z "$_DELETE_DIR" ] \
    || _fail 3 -v dir "$1" "_delete_on_exit takes one folder per script. Create this one inside the first"

  # The script can cd before it exits, and a relative path then names
  # another folder
  case "$1" in
    /*) ;;
    *) _fail 3 -v dir "$1" "_delete_on_exit takes an absolute path" ;;
  esac

  _DELETE_DIR=$1
  _on_exit _delete_dir
}

# _delete_dir
#
# Delete _DELETE_DIR.
# shellcheck disable=SC2329 # _delete_on_exit registers it with _on_exit
_delete_dir() {
  rm -rf -- "$_DELETE_DIR"
}
