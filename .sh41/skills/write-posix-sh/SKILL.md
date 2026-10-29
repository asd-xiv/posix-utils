---
name: write-posix-sh
description: |
  Write POSIX shell scripts and the primitives in `posix-utils/bin/lib.sh`.
  Use whenever the work is a shell script: writing, updating, reviewing, or
  porting one from bash or zsh, whatever the path or extension.
  Not for Node CLI entry points, which are TypeScript wrappers around commander.
---

<!-- POSIX.1-2024 main additions are pipefail and realpath -->

Write composable, portable POSIX.1-2024 shell scripts that do one thing well.

<!--
Sources used for various decisions in this skill:

- Utility Conventions: https://pubs.opengroup.org/onlinepubs/9799919799/basedefs/V1_chap12.html
- XDG Base Directory Specification: https://specifications.freedesktop.org/basedir/latest/
-->

## Files

```text
<posix-utils-root>/
`-- bin/            <- Group by the running environment
  |-- lib.sh        <- Primitives every script sources
  |-- cli/          <- Terminal and CI, no display server
  `-- sway/         <- Sway session, needs Wayland and a notifier

<domain-pkg-root>/bin/   <- Scripts that only this package needs
```

<!--
When editing this skill, use these terms consistently.

| Term       | Example                                 | Means                                    | Not                       |
| ---------- | --------------------------------------- | ---------------------------------------- | ------------------------- |
| flag       | `-m`, `--max`                           | A named input to the script              | option, switch            |
| positional | `<pattern>`, `$1`                       | An unnamed input, placed after flags     | argument, file argument   |
| setting    | `_MAX_COUNT`                            | A top-level variable a flag sets once    | global, knob, config knob |
| primitive  | `_is`, `_search_file`                   | A domain or domain-agnostic function     | helper, util              |
| elevate    | `_ping_service_x` -> `_http_ping <url>` | Move a domain primitive up into `lib.sh` | move, promote, extract    |
| status     | `$?` after `grep` or a pipe             | What anything the script runs gives back | exit code, return value   |
| exit code  | `exit 2`, under `EXIT CODES`            | What the script itself ends with         | status, return code       |

- Man page headings keep their standard names, `OPTIONS` and `ARGUMENTS`
- `set` takes shell options, not flags
-->

## Conventions

Apply these everywhere:

- Write POSIX: no bashisms, no GNU-only flags
- Put `--` before the positionals you pass, eg. `rm -f -- "$file"`. A command
  reads a value that starts with `-` as a flag
- Check each item inside a glob loop, eg. `[ -f "$file" ] || continue`
  - A pattern that matches nothing stays literal, `for file in docs/*.md` then
    runs the body once, on the pattern itself
- Keep state that must outlast a reboot in
  `${XDG_STATE_HOME:-$HOME/.local/state}`

**Naming and scope**:

- `_lower_snake` for a private function and `_UPPER_SNAKE` for a private
  top-level variable, in a script or a lib file. Private means not part of the
  public contract, not meant for the user
- `UPPER_SNAKE` for any public global variable: an environment variable the
  script reads, eg. `NO_COLOR`, or exports for a child, eg. a config path
- Name the variables of a function `lower_snake`, prefixed with the function
  acronym, eg. `sf_status` in `_search_file`
- The prefix must be unique across the script and every file it sources
- Never shadow a builtin, a shell variable or a standard environment variable:
  `type`, `test`, `read`, `IFS`, `PATH`, `TMPDIR`
- Name a path variable for what it holds, `_dir` or `_file`, unless its noun
  already does, eg. `link_script`. Keep `_path` for a search list, as in `PATH`

**Locks**:

- Take a lock with `mkdir` in `$(_get_runtime_dir)`. `mkdir` is atomic
  - A boot clears that directory, so no lock outlasts a reboot
- Write each value to its own file in the lock, `pid` first, eg.
  `<runtime-dir>/<cmd-name>.lock/pid`
- Remove the lock with `rm -r -- "${_LOCK_DIR:?}"` in the cleanup trap, only
  when this run took it
- A lock is stale when its pid is gone or runs another program
  - Only an explicit command removes it, eg. `screenrecord stop`
  - Check the program with `ps -p <pid> -o args=` before you signal the pid

**Exit codes**:

- `0` success. The work is done, or the answer is yes
- `1` no. A real answer, not a failure. Only a script that asks a yes/no
  question exits with it
- `2` invalid usage. The caller can fix it by retyping (eg. a typo in a flag)
- `3` could not run. The call was right, the work still failed (eg. a missing
  dependency)
- `4`-`125` are free for the script's own outcomes
- Never exit with a code the shell owns: `126` (found, not executable), `127`
  (not found) or `128`+n (killed by signal n, eg. `130` for `Ctrl-C`)

## Specimen: `find-in-files`

<!-- Literate style: the prose explains the code that follows it -->

Sections 1–9 build one script, `find-in-files`, top to bottom. The script shows
the rules at work. It is not a template.

### 1. Shebang and shell options

- Read a status with `rc=0; cmd || rc=$?`. Use `set +e` only for a block where
  every line must run, eg. a cleanup
  - `set -e` is off wherever the shell already checks the status: the condition
    of `if`, `while` and `until`, a pipeline after `!`, and every command but
    the last in an `&&` or `||` list, including the body of a function called
    there
  - `set -e` ends the script on a failed command substitution only when the
    assignment stands alone
    - `echo "$(im-bad)"` does not exit. The line takes `echo`'s status
    - `x=$(im-bad)` exits. An assignment with no command takes the
      substitution's status
  - Catch a command's status only to recover, or to add what the caller cannot
    see. Otherwise let `set -e` stop the script
- With `set -o pipefail`, a pipe returns the status of its last failed command
  (eg. `(exit 3) | (exit 4) | true` -> 4)
  - Turn it on around the pipe that needs it, off after. With it on,
    `find "$dir" -type f | head -n 1` gives status 141 on a large dir, once
    `head` stops reading, and `set -e` ends the script
  - POSIX added it in June 2024. BusyBox `ash` added it in 1.16 (Jan 2010),
    `dash` in 0.5.13 (Sep 2025)

```sh
#!/bin/sh

set -eu
```

### 2. The man page

- Name a script `<verb>-<object>`, eg. `find-in-files`, `download-git`
  - `find-*` exits and `_find_*` returns 0 when it finds nothing, `get-*` and
    `_get_*` non-zero
- Write the man page once, as comments. `_show_help "$0"` prints it back
  - Headings, in order: `NAME`, `SYNOPSIS`, `DESCRIPTION`, `ARGUMENTS`,
    `OPTIONS`, `ENVIRONMENT`, `EXAMPLE`, `EXIT CODES`, `SEE ALSO`
  - Document every code the script exits with under `EXIT CODES`

```sh
# NAME
#   find-in-files - Print the lines that match a pattern
#
# SYNOPSIS
#   find-in-files [OPTIONS] <pattern> [file...]
#   ... | find-in-files [OPTIONS] <pattern>
#
# DESCRIPTION
#   Searches each file for a pattern and prints the matching lines. With no
#   file, reads stdin.
#
# ARGUMENTS
#   pattern   Basic regular expression
#   file      File to search, repeatable
#
# OPTIONS
#   -i, --ignore-case    Match without regard to case
#   -m, --max <count>    Stop after count matches per file
#   -h, --help           Print this help
#
# ENVIRONMENT
#   LOG_LEVEL   Last log level to print (default: info)
#
# EXAMPLE
#   find-in-files TODO src/main.c
#   git log --oneline | find-in-files --max 3 fix
#
# EXIT CODES
#   0   The search ran, whether a line matched or not
#   2   Invalid usage
#   3   The search could not run
#
# SEE ALSO
#   grep
```

### 3. Domain-agnostic primitives

- Read `bin/lib.sh` before you write a script and reuse what fits
- Write a new primitive in the script
- When a second script needs it, elevate it to `lib.sh`
  - Drop the domain from its name, eg. `_ping_service_x` -> `_http_ping <url>`
  - Start its variable prefix with `lib_`, eg. `lib_hp_status`, to avoid
    collisions with the variables of a script that sources it
- `bin/cli/fancy-log` is the command form of `_log`, for a shell that does not
  source `lib.sh`

```sh
# tools/install symlinks this script, so "$0" names the link. realpath follows
# it to find lib.sh
_SCRIPT_DIR=$(dirname "$(realpath "$0")")
. "$_SCRIPT_DIR/../lib.sh"

# _log reads these
export LOG_NAMESPACE="find-in-files"
export LOG_LEVEL="${LOG_LEVEL:-info}"
```

### 4. Settings

- Declare the settings up front, each with an explicit default. Assign every
  other top-level variable, eg. `_PATTERN`, where the script first knows its
  value

```sh
_IGNORE_CASE="" # -i/--ignore-case, "true" or ""
_MAX_COUNT=""   # -m/--max, a positive integer
```

### 5. Domain primitives

- A primitive takes per-call data as positionals. A flag sets a setting once.
  Never use a setting to pass data between functions
- `return` ends the function, `_fail` ends the script
- Each function has its own positional list. `shift` and `set --` inside it
  never update the caller's `"$@"`
- Tell a command's statuses apart before you act on one, so the script never
  treats "no match" as "broken"
- Above a function, write its signature and what it does, then `RETURNS` with
  each status and `EXIT` with each exit code, as in a man page. Leave out a 0
  that only says the work is done

```sh
# ╭───
# │ Primitives
# ╰───

# _search_file <pattern> <file>
#
# Print the lines of <file> that match <pattern>, at most _MAX_COUNT of them.
#
# RETURNS
#   0   A line matched
#   1   No line matched
#   2   grep failed
_search_file() {
  sf_status=0

  if [ -z "$_MAX_COUNT" ]; then
    grep ${_IGNORE_CASE:+-i} -- "$1" "$2" || sf_status=$?
  else
    # POSIX `grep` has no -m, so the search pipes into `head` as a workaround.
    # `pipefail` gives the pipe `grep`'s status: `head` exits 0 whether a line
    # matched or not
    set -o pipefail
    grep ${_IGNORE_CASE:+-i} -- "$1" "$2" | head -n "$_MAX_COUNT" \
      || sf_status=$?
    set +o pipefail
  fi

  # POSIX `grep` gives a status above 1 on any error. Return 2 for each one
  case "$sf_status" in
    0 | 1) return "$sf_status" ;;
    # 141 is 128 + SIGPIPE. `head` reads _MAX_COUNT lines and exits, which
    # closes the pipe. The system sends SIGPIPE to `grep` at its next write
    141) return 0 ;;
    *) return 2 ;;
  esac
}
```

### 6. Flags and positionals

- Flags first, then the positionals
  - The exception is a command word, eg. `ls` in `recheck ls --color` or `info`
    in `fancy-log info --no-color`. It comes before its flags
- Always handle `--`, always catch `-?*`. The `?` lets a lone `-` through
- Guard before every `shift 2`. `dash` aborts with
  `shift: can't shift that many`
- Name the shape a value must have and reject the rest. A list of bad shapes
  always misses an edge case
- Use a boolean flag instead of a value with two choices and a default, eg.
  `--ignore-case`, not `--case <match|ignore>`
- Never install a dependency. Guard it with `_require_cmd` after the script
  reads the flags and the positionals, so `--help` works without it
  - Name it under `SEE ALSO`
  - Report invalid usage (exit `2`) before a missing dependency (exit `3`)

```sh
# ╭───
# │ Bootstrap
# ╰───

if [ "$#" -eq 0 ]; then
  _show_help "$0" >&2
  exit 2
fi

while [ "$#" -gt 0 ]; do
  case "$1" in
    -h | --help)
      _show_help "$0"
      exit 0
      ;;
    -i | --ignore-case)
      _IGNORE_CASE="true"
      shift
      ;;
    -m | --max)
      [ "$#" -lt 2 ] && _fail 2 "--max needs a count"
      _is positive-integer "$2" || _fail 2 -v max "$2" "Not a count"
      _MAX_COUNT="$2"
      shift 2
      ;;
    --)
      shift; break
      ;;
    -?*)
      _fail 2 -v flag "$1" "Unknown flag"
      ;;
    *) break ;;
  esac
done

[ "$#" -eq 0 ] && _fail 2 "No pattern given"

_PATTERN="$1"
shift

_require_cmd grep
```

### 7. Cleanup

- Register the trap before the first thing it must clean
- End a signal trap by resending the signal. A trap stops the signal from ending
  the script. Without the resend, the script runs on past its own cleanup
  - In each signal trap, call `_cleanup`, then clear the EXIT trap. POSIX leaves
    open whether EXIT runs when a signal kills the script

```sh
# ╭───
# │ Cleanup
# ╰───

# shellcheck disable=SC2329 # called by trap
_cleanup() {
  # 'set -u' aborts on an unset _TEMP_DIR, so default it
  rm -rf -- "${_TEMP_DIR:-}"
}

trap _cleanup EXIT # normal exit
trap '_cleanup; trap - EXIT INT; kill -INT $$' INT # Ctrl-C
trap '_cleanup; trap - EXIT TERM; kill -TERM $$' TERM # kill, timeout, CI cancel
trap '_cleanup; trap - EXIT HUP; kill -HUP $$' HUP # SSH drop, closed window

_TEMP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/find-in-files.XXXXXX") \
  || _fail 3 "Could not add a temporary directory"
```

### 8. Main

- Print results to stdout, everything else to stderr
  - Use `printf`, not `echo`. Pass data through `%s`
  - Never `printf '%b'` on data. It reads the escapes inside, eg. `C:\new`
    prints a newline
- Read stdin when the caller gives no file
  - Read only when `[ ! -t 0 ]`
- Ignore stdin when the caller gives a file, as `grep` and `wc` do
- Warn and skip an item you cannot use, finish the rest, then fail

```sh
# ╭───
# │ Main
# ╰───

if [ "$#" -eq 0 ] && [ ! -t 0 ]; then
  _STDIN_FILE=$(mktemp "$_TEMP_DIR/stdin.XXXXXX")
  cat > "$_STDIN_FILE"
  set -- "$_STDIN_FILE"
fi

if [ "$#" -eq 0 ]; then
  _fail 2 "No file and no piped input"
fi

_FOUND=""
_SKIPPED=""
for _FILE in "$@"; do
  _FILE_STATUS=0
  _search_file "$_PATTERN" "$_FILE" || _FILE_STATUS=$?

  case "$_FILE_STATUS" in
    0) _FOUND="true" ;;
    1) ;;
    *)
      _warn -v path "$_FILE" "Search failed, skipping"
      _SKIPPED="true"
      ;;
  esac
done
```

### 9. The last line

- Never end a script, or a function, on a bare `[ ] && { }`
  - A false test becomes the exit code, eg. `[ -n "$_FOUND" ] && exit 0` alone
    exits 1 when nothing matched, by accident
- Exit on purpose in every branch, with the code the man page promised

```sh
if [ -n "$_SKIPPED" ]; then
  _fail 3 "Some files could not be searched"
fi

if [ -z "$_FOUND" ]; then
  _info -v pattern "$_PATTERN" "Nothing matched"
fi

exit 0
```

## Verify

Run `npm run lint`, or directly `./tools/verify ./bin ./tools`, before you
finish. It checks every script with:

- `shellcheck -s sh`
- `/bin/sh -n`
- `--help` exits 0, an unknown flag exits 2
  - it skips both for a private command, under a `*.d` directory, and for a test
    file, under a `*.t` directory
- a command has `+x`, a `*.sh` library does not
