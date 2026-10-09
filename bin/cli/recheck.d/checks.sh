#!/bin/sh

# The settings and primitives that two or more recheck commands use. Each
# file in recheck.d sets SCRIPT_DIR, then sources this file.

. "$SCRIPT_DIR/../../lib.sh"

# _log reads these
export LOG_NAMESPACE="recheck"
export LOG_LEVEL="${LOG_LEVEL:-info}"

# The public command. A file in recheck.d runs another command only through it
RECHECK_FILE=$(realpath "$SCRIPT_DIR/../recheck")

CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/recheck"
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/recheck"
CHECKS_DIR="$CONFIG_DIR/checks"
ENV_FILE="$CONFIG_DIR/env"
# shellcheck disable=SC2034 # the command files read it
UPDATE_HOOK_FILE="$CONFIG_DIR/on-update"
# shellcheck disable=SC2034 # the command files read it
RUN_LOG_FILE="$STATE_DIR/runs.log" # a slug has no ".", so no id can take it
TAB=$(printf '\t')

# ╭───
# │ Primitives
# ╰───

# find_ids
# Print the id of every check, one per line, sorted. The id is the file name
# without the "_" that disables a check.
find_ids() {
  for find_file in "$CHECKS_DIR"/*; do
    [ -f "$find_file" ] || continue

    find_name="${find_file##*/}"
    find_id="${find_name#_}"

    if ! _is slug "$find_id"; then
      _warn -v id "$find_id" -v path "$find_file" "Id is not a slug, skipping"
    elif [ "$find_name" != "$find_id" ] && [ -f "$CHECKS_DIR/$find_id" ]; then
      _warn -v path "$find_file" "The same check is also enabled, skipping"
    else
      printf '%s\n' "$find_id"
    fi
    # By id, not by file name: a check keeps its place when "_" disables it
  done | LC_ALL=C sort
}

# is_enabled <id>
# Return 0 when the check file has no "_" in front of its name.
is_enabled() {
  [ -f "$CHECKS_DIR/$1" ]
}

# find_enabled_ids
# Print the id of every enabled check, one per line.
find_enabled_ids() {
  for enabled_id in $(find_ids); do
    if is_enabled "$enabled_id"; then
      printf '%s\n' "$enabled_id"
    fi
  done
}

# pick_ids
# Read ids from stdin, let the user pick some in fzf, print the picked ones.
# Exit 4 when the user picks nothing, 3 when fzf fails.
pick_ids() {
  pick_status=0
  fzf --multi || pick_status=$?

  # fzf: 1 is Enter with no match, 130 is Esc or Ctrl-C
  case "$pick_status" in
    0) return 0 ;;
    1 | 130)
      _warn "Nothing picked"
      exit 4
      ;;
    *) _fail 3 -v status "$pick_status" "fzf failed" ;;
  esac
}

# find_check_file <id>
# Print the file of a check, enabled or disabled. Return 1 when it has none.
find_check_file() {
  for check_file in "$CHECKS_DIR/$1" "$CHECKS_DIR/_$1"; do
    if [ -f "$check_file" ]; then
      printf '%s' "$check_file"
      return 0
    fi
  done

  return 1
}

# guard_id <id>...
# Exit 2 unless every <id> names a check.
guard_id() {
  for guarded_id in "$@"; do
    # Both are no slug either. Each gets the message that says what to fix
    case "$guarded_id" in
      -*) _fail 2 -v flag "$guarded_id" "Unknown flag" ;;
      _*) _fail 2 -v id "$guarded_id" "An id does not start with _" ;;
    esac

    _is slug "$guarded_id" || _fail 2 -v id "$guarded_id" "Not a slug"
    find_check_file "$guarded_id" >/dev/null \
      || _fail 2 -v id "$guarded_id" "No such check"
  done

  return 0
}

# find_cron_pattern <id>
# Print the cron pattern of a check. Return 1 unless it has five fields of
# digits, "*", "/", "," and "-". Names and "@daily" differ between crons.
find_cron_pattern() {
  pattern_file=$(find_check_file "$1") || return 1
  pattern_line=$(sed -n 's/^# CRON:[[:space:]]*//p' -- "$pattern_file" | head -n 1)

  # No globbing while splitting, most fields are "*"
  set -f
  # shellcheck disable=SC2086 # split into fields on purpose
  set -- $pattern_line
  set +f

  [ "$#" -eq 5 ] || return 1

  for pattern_field in "$@"; do
    case "$pattern_field" in
      *[!0-9*/,-]*) return 1 ;;
    esac
  done

  printf '%s' "$*"
}

# find_state <id>
# Print the state of a check. Print "-" before its first run.
find_state() {
  if [ ! -f "$STATE_DIR/$1/last" ]; then
    printf '%s' "-"
    return 0
  fi

  # The file "last" is one line: time, state, exit code, seconds. Cut the
  # second field out without a process, ls asks this once per check
  read -r state_line <"$STATE_DIR/$1/last" || true
  state_line="${state_line#*"$TAB"}"
  printf '%s' "${state_line%%"$TAB"*}"
}

# The marker of a run is the file "running" in the state folder of its check.
# It holds "<process id> <time>" for as long as the run lasts.

# find_run_start <id>
# Print the time the run in progress started. Return 1 when the check is not
# running. A marker outlives its run after a kill -9 or a power loss, and its
# process id can then belong to any program. So the process must be alive and
# must be a recheck.
find_run_start() {
  [ -f "$STATE_DIR/$1/running" ] || return 1

  read -r start_pid start_time <"$STATE_DIR/$1/running" || return 1
  _is positive-integer "$start_pid" || return 1
  kill -0 "$start_pid" 2>/dev/null || return 1

  # A ps without -p, as in BusyBox, cannot say. Then a live process is enough
  start_args=$(ps -o args= -p "$start_pid" 2>/dev/null) || start_args="recheck"
  case "$start_args" in
    *recheck*) ;;
    *) return 1 ;;
  esac

  printf '%s' "$start_time"
}

# is_running <id>
# Return 0 while a run of the check is in progress.
is_running() {
  find_run_start "$1" >/dev/null
}

# run_with_env <command> [arg...]
# Run a command in a subshell, with the env file sourced first.
run_with_env() (
  # The user writes the env file. It may fail under -e and -u, eg. nvm.sh
  set +eu

  if [ -f "$ENV_FILE" ]; then
    # shellcheck source=/dev/null
    . "$ENV_FILE"
  fi

  exec "$@"
)

# run_hook <hook-file> [arg...]
# Run a hook with the env file sourced, when the hook is executable. A hook
# that fails is a warning, the work it follows is already done.
run_hook() {
  [ -x "$1" ] || return 0

  run_with_env "$@" >&2 || _warn -v hook "$1" "The hook failed"

  return 0
}

# guard_script_file
# Exit 3 unless RECHECK_FILE, the path of recheck, is safe to write unquoted.
# A crontab line and the fzf commands of the browser hold it. cron reads "%"
# as a newline, and a shell would split or expand most other characters.
guard_script_file() {
  case "$RECHECK_FILE" in
    *[!A-Za-z0-9_@+=:,./-]*)
      _fail 3 -v path "$RECHECK_FILE" \
        "The script path has a character outside A-Za-z0-9_@+=:,./-"
      ;;
  esac

  return 0
}

# guard_sync
# Exit 3 unless a sync can run: the commands it needs are there, and the
# script path can stand in a crontab line. Called before anything is renamed
# or edited, so a failure changes nothing.
guard_sync() {
  _require_cmd crontab awk
  guard_script_file
}

# list_cron_lines
# Print the crontab line of each enabled check. Warn about a check without a
# valid cron pattern and leave it out. Return 1 when one was left out, after
# printing the rest.
list_cron_lines() {
  cron_has_skipped=""

  for cron_id in $(find_enabled_ids); do
    if cron_pattern=$(find_cron_pattern "$cron_id"); then
      # cron mails what a job prints. Drop the results, keep the errors
      printf '%s %s run %s >/dev/null\n' "$cron_pattern" "$RECHECK_FILE" "$cron_id"
    else
      _warn -v id "$cron_id" "No valid cron pattern in a '# CRON:' line, skipping"
      cron_has_skipped="true"
    fi
  done

  if [ -n "$cron_has_skipped" ]; then
    return 1
  fi

  return 0
}

# wait_for_enter
# Stop until the user presses Enter. A window opened only for this command
# closes with it, and would take what it shows along.
wait_for_enter() {
  printf 'Press Enter to close ' >&2
  # shellcheck disable=SC2034 # read needs a name, nobody reads it
  read -r wait_reply || true
}

HAS_TITLE="" # "true" once set_title changed the window title

# set_title <title>
# Name the terminal window, when stderr is a terminal. The escape codes are
# xterm's and most terminals read them, a flag such as --title differs per
# terminal. The first code saves the old title, restore_title restores it.
set_title() {
  [ -t 2 ] || return 0

  printf '\033[22;0t\033]0;%s\007' "$1" >&2
  HAS_TITLE="true"
}

# restore_title
# Restore the title that set_title saved. The window may be gone, and a
# failed write must not stop the rest.
restore_title() {
  if [ -n "$HAS_TITLE" ]; then
    printf '\033[23;0t' >&2 2>/dev/null || true
    HAS_TITLE=""
  fi
}
