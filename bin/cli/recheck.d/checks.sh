#!/bin/sh

# The settings and primitives that two or more recheck commands use. Each
# command file sets SCRIPT_DIR, then sources this file.

. "$SCRIPT_DIR/../../lib.sh"

# _log reads these
export LOG_NAMESPACE="recheck"
export LOG_LEVEL="${LOG_LEVEL:-info}"

# The public command. A command file runs another command only through it
RECHECK_FILE=$(realpath "$SCRIPT_DIR/../recheck")

CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/recheck"
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/recheck"
# The parent of the locks. cron sets no XDG_RUNTIME_DIR, so _get_runtime_dir
# falls back to /run/user/<user id>, the folder the login manager makes for the
# user. A boot clears it. Empty when the user has neither: then no check has a
# lock, and run can take none
RUNTIME_DIR=""
if RUNTIME_PARENT_DIR=$(_get_runtime_dir 2>/dev/null); then
  RUNTIME_DIR="$RUNTIME_PARENT_DIR/recheck"
fi
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

# The lock of a check is the folder "<id>.lock" in the runtime folder. "run"
# makes it with mkdir before the check starts and removes it when the check
# ends. It holds one file per value: "pid", the process id of the run command,
# then "started", the time the check started. "show" prints the time. The
# process id is for a person who finds a lock that a run command left. recheck
# trusts the lock: a check with a lock is running, and "run" skips it. No
# command asks whether the process still runs. A run command that ends without
# its traps, eg. by kill -9, leaves its lock. Then the check runs again only
# after a person removes the lock, or a boot clears the runtime folder.

# print_lock_dir <id>
# Print the path of the lock of a check, whether the check has one or not.
# Return 1 when the user has no runtime folder.
print_lock_dir() {
  [ -n "$RUNTIME_DIR" ] || return 1
  printf '%s' "$RUNTIME_DIR/$1.lock"
}

# find_run_start <id>
# Print the time the run in progress started. Return 1 when the check has no
# lock. A lock has no "started" for an instant after mkdir. Then print an empty
# time and return 0.
find_run_start() {
  start_dir=$(print_lock_dir "$1") || return 1
  [ -d "$start_dir" ] || return 1

  # The time stays empty before run writes it, and when the run ended after the
  # guard above and removed the lock
  start_time=""
  { read -r start_time <"$start_dir/started" || true; } 2>/dev/null

  printf '%s' "$start_time"
}

# is_running <id>
# Return 0 when the check has a lock.
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

# is_recheck_file_safe
# Return 0 when RECHECK_FILE, the path of recheck, is safe to write unquoted.
# A crontab line and the fzf commands of the browser hold it. cron reads "%"
# as a newline, and a shell would split or expand most other characters.
is_recheck_file_safe() {
  case "$RECHECK_FILE" in
    *[!A-Za-z0-9_@+=:,./-]*) return 1 ;;
  esac

  return 0
}

# guard_recheck_file
# Exit 3 unless is_recheck_file_safe.
guard_recheck_file() {
  is_recheck_file_safe \
    || _fail 3 -v path "$RECHECK_FILE" \
      "The script path has a character outside A-Za-z0-9_@+=:,./-"

  return 0
}

# guard_sync
# Exit 3 unless a sync can run: the commands it needs are there, and the
# path of recheck can stand in a crontab line. sync, enable, disable and edit
# call it before they change anything, so a failure changes nothing.
guard_sync() {
  _require_cmd crontab awk
  guard_recheck_file
}

# find_fzf_version
# Print the version fzf reports, eg. 0.74.4. Print nothing when fzf is missing
# or prints no version.
find_fzf_version() {
  command -v fzf >/dev/null 2>&1 || return 0

  # fzf prints "0.74.4 (a140afeb)", or "0.74" when built without a tag
  find_reported=$(fzf --version 2>/dev/null) || return 0
  printf '%s' "${find_reported%% *}"
}

# is_fzf_new_enough <version>
# Return 0 when <version> is 0.73.0 or newer, 1 when it is older or not a
# version. browse needs --id-nth, new in fzf 0.71.0, and the "every" event,
# new in fzf 0.73.0.
is_fzf_new_enough() {
  _is version "$1" || return 1

  enough_major="${1%%.*}"
  enough_minor="${1#*.}"
  enough_minor="${enough_minor%%.*}"

  if [ "$enough_major" -eq 0 ] && [ "$enough_minor" -lt 73 ]; then
    return 1
  fi

  return 0
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
