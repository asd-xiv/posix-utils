#!/bin/sh

# NAME
#   sandbox.sh - The sandbox and helpers of the recheck tests
#
# DESCRIPTION
#   A test file sources it after tools/test-lib.sh and after it sets
#   SCRIPT_DIR to its own folder.
#
#   recheck writes the real crontab and config of the user. A test that runs
#   it calls build_sandbox first, from before_each. The sandbox points HOME,
#   XDG_CONFIG_HOME and XDG_STATE_HOME at the test folder and puts a fake
#   crontab first on PATH. Nothing in it calls the real crontab.
#
#   BusyBox runs its own crontab applet before anything on PATH, so a fake
#   crontab would not be called. The whole file is skipped there.

# An applet has no path: "crontab", not "/usr/bin/crontab"
case "$(command -v crontab)" in
  "" | /*) ;;
  *) _skip_all "BusyBox runs its own crontab applet, not the fake one" ;;
esac

# shellcheck disable=SC2034 # the test files read it
RECHECK="$SCRIPT_DIR/../recheck"

# build_sandbox
# Create the config, the state and a fake crontab in the current folder, then
# make recheck use only them.
#
# RETURNS
#   3   The fake crontab is not the first crontab on PATH
build_sandbox() {
  mkdir -p config/recheck/checks state bin home
  cat >bin/crontab <<'FAKE'
#!/bin/sh
store="$(dirname "$0")/crontab.txt"
case "${1:-}" in
  -l)
    [ -f "$store" ] || { printf 'no crontab for fake\n' >&2; exit 1; }
    cat "$store"
    ;;
  -) cat >"$store" ;;
  *) exit 2 ;;
esac
FAKE
  chmod +x bin/crontab

  HOME="$PWD/home"
  XDG_CONFIG_HOME="$PWD/config"
  XDG_STATE_HOME="$PWD/state"
  PATH="$PWD/bin:$PATH"
  export HOME XDG_CONFIG_HOME XDG_STATE_HOME PATH

  if [ "$(command -v crontab)" != "$PWD/bin/crontab" ]; then
    printf 'build_sandbox: the fake crontab is not first on PATH\n' >&2
    return 3
  fi
}

# add_check <id> <exit-code>
# Write an enabled check that exits with <exit-code>, due every minute.
add_check() {
  printf '#!/bin/sh\n# CRON: * * * * *\nexit %s\n' "$2" \
    >"config/recheck/checks/$1"
  chmod +x "config/recheck/checks/$1"
}

# add_output <id> <printf-format>
# Write the output file of a check, as a run would, without running it.
add_output() {
  mkdir -p "state/recheck/$1"
  # shellcheck disable=SC2059 # the format is the argument
  printf "$2" >"state/recheck/$1/output"
}

# add_state <id> <state>
# Write the file "last" of a check without running it. Its one line holds the
# four fields of a run in their order: time, state, exit code, seconds. Only
# <state> varies. The exit code is 0 for every state.
add_state() {
  mkdir -p "state/recheck/$1"
  printf '2023-11-14T22:13:20+0000\t%s\t0\t1s\n' "$2" >"state/recheck/$1/last"
}

# add_hook
# Write an on-update hook that appends a line to hook.log in the current
# folder.
add_hook() {
  printf '#!/bin/sh\nprintf "ran\\n" >>"%s/hook.log"\n' "$PWD" \
    >config/recheck/on-update
  chmod +x config/recheck/on-update
}
