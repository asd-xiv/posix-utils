#!/bin/sh

# NAME
#   sandbox.sh - The sandbox and helpers of the recheck tests
#
# DESCRIPTION
#   A test file sets SCRIPT_DIR to its own folder, sources tools/test-lib.sh,
#   this file, then bin/lib/wait.sh, which wait_until_started needs.
#
#   recheck writes the real crontab and config of the user. A test that runs
#   it calls create_sandbox first, from before_each. The sandbox points HOME,
#   XDG_CONFIG_HOME, XDG_STATE_HOME and XDG_RUNTIME_DIR at the test folder and
#   puts a fake crontab first on PATH. Nothing in it calls the real crontab or
#   writes to the real config, state or runtime folder.
#
#   A test builds the state of recheck by running recheck, never by writing
#   its state files: create_check writes a check, "recheck run" writes its
#   state. create_waiting_check and start_background_run keep a run going,
#   with its lock, until finish_background_run.
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

# create_sandbox
# Create the config, the parents of the state and of the runtime folder, and a
# fake crontab in the current folder, then make recheck use only them.
#
# RETURNS
#   3   The fake crontab is not the first crontab on PATH
create_sandbox() {
  mkdir -p config/recheck/checks state runtime bin home
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
  XDG_RUNTIME_DIR="$PWD/runtime"
  PATH="$PWD/bin:$PATH"
  export HOME XDG_CONFIG_HOME XDG_STATE_HOME XDG_RUNTIME_DIR PATH

  if [ "$(command -v crontab)" != "$PWD/bin/crontab" ]; then
    printf 'create_sandbox: the fake crontab is not first on PATH\n' >&2
    return 3
  fi
}

# create_check <id> <exit-code> [command]
# Write an enabled check, due every minute, that runs <command>, then exits
# with <exit-code>.
create_check() {
  printf '#!/bin/sh\n# CRON: * * * * *\n%s\nexit %s\n' "${3:-:}" "$2" \
    >"config/recheck/checks/$1"
  chmod +x "config/recheck/checks/$1"
}

# create_waiting_check <id> <red-runs> [retry-line]
# Write an enabled check that appends "start" to <id>.starts in the current
# folder, and exits 1 for its first <red-runs> runs. After them, it waits
# until the file go exists in the current folder, up to 10 s, then exits 0.
# With <retry-line>, the check has "# RETRY: <retry-line>".
create_waiting_check() {
  cat >"config/recheck/checks/$1" <<CHECK
#!/bin/sh
# CRON: * * * * *
${3:+# RETRY: $3}
printf 'start\\n' >>"$PWD/$1.starts"
[ "\$(wc -l <"$PWD/$1.starts")" -gt $2 ] || exit 1
i=0
while [ ! -f "$PWD/go" ] && [ "\$i" -lt 200 ]; do
  sleep 0.05
  i=\$((i + 1))
done
CHECK
  chmod +x "config/recheck/checks/$1"
}

# start_background_run <id>
# Start "recheck run <id>" in the background, with its stdout and stderr in
# run.stdout and run.stderr. Set BACKGROUND_RUN_PID to its process id. Call it from
# actual, the shell that later waits for it.
start_background_run() {
  "$RECHECK" run "$1" >run.stdout 2>run.stderr &
  BACKGROUND_RUN_PID=$!
}

# wait_until_started <id> <count>
# Wait up to 5 s until the check <id> started <count> times.
#
# RETURNS
#   1   It started fewer times in 5 s
wait_until_started() {
  _wait_until 5 has_started "$1" "$2"
}

# has_started <id> <count>
# Tell if the check <id> started at least <count> times.
has_started() {
  [ -f "$1.starts" ] && [ "$(wc -l <"$1.starts")" -ge "$2" ]
}

# finish_background_run
# Let the waiting check end, then wait for the run of start_background_run.
finish_background_run() {
  : >go
  wait "$BACKGROUND_RUN_PID" || :
}

# create_on_update_hook
# Write an on-update hook that appends a line to hook.log in the current
# folder.
create_on_update_hook() {
  printf '#!/bin/sh\nprintf "ran\\n" >>"%s/hook.log"\n' "$PWD" \
    >config/recheck/on-update
  chmod +x config/recheck/on-update
}
