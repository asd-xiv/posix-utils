---
name: write-posix-sh
description: |
  Write POSIX shell scripts and the primitives in `posix-utils/bin/lib.sh`.
  Use whenever the work is a shell script: writing, changing, reviewing, or
  porting one from bash or zsh, whatever the path or extension.
  Not for Node CLI entry points, which are TypeScript wrappers around commander.
---

Write composable, portable POSIX shell scripts that do one thing well.

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

<domain-pkg-root>/bin/   <- Scripts only that package needs
```

<!--
When editing this skill, use these terms consistently.

| Term       | Example                                | Means                                    | Not                       |
| ---------- | -------------------------------------- | ---------------------------------------- | ------------------------- |
| flag       | `-m`, `--max`                          | A named input to the script              | option, switch            |
| positional | `<pattern>`, `$1`                      | An unnamed input, placed after flags     | argument, file argument   |
| setting    | `MAX_COUNT`                            | A top-level variable a flag sets once    | global, knob, config knob |
| primitive  | `_is`, `search_file`                   | A domain or domain-agnostic function     | helper, util              |
| elevate    | `ping_service_x` -> `_http_ping <url>` | Rewrite a domain primitive into `lib.sh` | move, promote, extract    |
| status     | `$?` after `grep`                      | What a command or function gives back    | exit code, return value   |
| exit code  | `exit 2`, under `EXIT CODES`           | What the script ends with, on purpose    | status, return code       |

- Man page headings keep their standard names, `OPTIONS` and `ARGUMENTS`
- `set` takes shell options, not flags
-->

## Conventions

<!--
Intentionaly using "Literate style" jargon to prime LLM for better progresive
disclosure and colocation.
-->

Literate style, on one script: `find-in-files`.

Apply these everywhere:

- Write POSIX: no bashisms, no GNU-only flags
- Put `--` before the positionals you pass, eg. `rm -f -- "$path"`. A value that
  starts with `-` is interpreted as a flag
- Test each item inside a glob loop, eg. `[ -f "$file" ] || continue`. A pattern
  that matches nothing stays literal, so `docs/*.md` runs the body once
- Name by case: `lower_snake` for functions and the variables used only inside
  them, `UPPER_SNAKE` for the rest
  - POSIX has no `local`, every variable is global. Prefix a function's
    variables with its verb, eg. `search_status` in `search_file`. The prefix
    must be unique to the function
  - Never shadow a builtin or a shell variable: `type`, `test`, `read`, `PATH`,
    `IFS`, `TMPDIR`
- Name a path variable for what it holds, `_dir` or `_file`, unless its noun
  already does, eg. `link_script`. Keep `_path` for a search list, as in `PATH`
- Return the exit code that names what happened
  - `0` success. The work is done, or the answer is yes
  - `1` no. A real answer, not a failure. Only a script that asks a yes/no
    question returns it
  - `2` invalid usage. The caller can fix it by retyping (eg. a typo in a flag)
  - `3` could not run. The call was right, the work still failed (eg. a missing
    dependency)
  - `4`-`125` are free for the script's own outcomes
  - Never return a code the shell owns: `126` (found, not executable), `127`
    (not found) or `128`+n (killed by signal n, eg. `130` for `Ctrl-C`)

### 1. Shebang and shell options

- Read a status with `rc=0; cmd || rc=$?`. Use `set +e` only for a block where
  every line must run, eg. a cleanup
  - `set -e` is off wherever the shell already tests the status: `if`, `while`,
    `until`, `!`, and every command but the last in an `&&` or `||` list,
    including the body of a function called there
  - `set -e` sees a command substitution's status only when the assignment
    stands alone
    - `echo "$(im-bad)"` does not exit, `echo`'s status wins
    - `x=$(im-bad)` exits, with no command name the status is the substitution's
  - Wrap or separate a command only when recovering is possible, or to add what
    the caller cannot already see, otherwise let `set -e` stop the script
- `set -o pipefail` returns the last failed status in a pipe (eg.
  `(exit 3) | (exit 4) | true` -> 4)
  - Turn it on around the pipe that needs it, off after. With it on,
    `find "$dir" -type f | head -n 1` exits 141 on a large dir, once `head`
    stops reading
  - POSIX added it in June 2024. BusyBox `ash` has it since 1.16 (Jan 2010),
    `dash` since 0.5.13 (Sep 2025)

```sh
#!/bin/sh

set -eu
```

### 2. The man page

- Name a script `<verb>-<object>`, eg. `find-in-files`, `download-git`
  - `find` may return nothing, `get` exits non-zero when it finds nothing
- Write the man page once, as comments. `_show_help "$0"` prints it back
  - Headings, in order: `NAME`, `SYNOPSIS`, `DESCRIPTION`, `ARGUMENTS`,
    `OPTIONS`, `ENVIRONMENT`, `EXAMPLE`, `EXIT CODES`, `SEE ALSO`
  - Document every code the script returns under `EXIT CODES`

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
# EXAMPLE
#   find-in-files TODO src/main.c
#   git log --oneline | find-in-files --max 3 fix
#
# EXIT CODES
#   0   At least one line matched
#   1   Nothing matched
#   2   Invalid usage
#   3   The search could not run
#
# SEE ALSO
#   grep
```

### 3. Domain-agnostic primitives

- `_log <level> [-v <key> <val>]... <message>`, `<level>` is
  `error|warning|success|info|debug`
  - `_debug|_info|_ok|_warn [-v <key> <val>]... <message>`, `_log` at
    `debug|info|success|warning`
- `_fail <code> [-v <key> <val>]... <message>`, log at `error`, then exit
  `<code>`
- `_is <type> <value>`, `<type>` is `positive-integer|version|slug|identifier`
- `_require_cmd <cmd>...`, exit 3 unless every `<cmd>` is on `PATH`
- `_require_var <NAME>...`, exit 2 unless every `<NAME>` is set
- `_download_file <url> <output-file>`
- `_resolve_bin_dir`, print `/usr/local/bin` or `~/.local/bin`, the first
  writable
- `_show_help <script-file>`, print the man page to stdout

- Levels run `error < warning < success < info < debug`
  - Short forms work too: `err`, `wrn|warn`, `suc|succ`, `inf`, `dbg`
  - `_log` exits 2 on a `<level>` or a `LOG_LEVEL` it does not know
  - `LOG_LEVEL` is the cut-off: it and everything before it print.
    `LOG_NAMESPACE` labels the line
  - `bin/cli/fancy-log` is the same logger as a command, for when `lib.sh` is
    not sourced
- Write a new primitive in the script. When a second script needs it, elevate it
  to `lib.sh`: eg. `ping_service_x` -> `_http_ping <url>`, and add it to the
  list

```sh
# tools/install symlinks this script, so dirname "$0" names the link. realpath
# follows it to find lib.sh
SCRIPT_DIR=$(dirname "$(realpath "$0")")
. "$SCRIPT_DIR/../lib.sh"

# lib.sh -> fancy-log settings
export LOG_NAMESPACE="find-in-files"
export LOG_LEVEL="${LOG_LEVEL:-info}"
```

### 4. Settings

- Declare the settings up front, each with an explicit default. What the script
  computes belongs where it is computed

```sh
IGNORE_CASE="" # -i/--ignore-case, "true" or ""
MAX_COUNT=""   # -m/--max, a positive integer
```

### 5. Domain primitives

- A primitive takes per-call data as positionals. A flag sets a setting once,
  never use one to pass data between functions
- `return` ends the function, `_fail` ends the script
- A function owns its positional list. `shift` and `set --` inside it never
  touch the caller's `"$@"`
- Read a command's status before acting on it, so "no match" never reads as
  "broken"

```sh
# ╭───
# │ Primitives
# ╰───

# search_file <pattern> <file>
# Print the matching lines. Return 0 for a match, 1 for none, 2 when grep failed.
search_file() {
  search_status=0
  grep ${IGNORE_CASE:+-i} ${MAX_COUNT:+-m "$MAX_COUNT"} -- "$1" "$2" \
    || search_status=$?

  # POSIX promises only >1 for a failure, so fold every failure into 2
  case "$search_status" in
    0 | 1) return "$search_status" ;;
    *) return 2 ;;
  esac
}
```

### 6. Bootstrap

- Never install a dependency. Guard it with `_require_cmd` after the help
  branch, so `--help` works without them. Name it under `SEE ALSO`

```sh
# ╭───
# │ Bootstrap
# ╰───

case "${1:-}" in
  -h | --help)
    _show_help "$0"
    exit 0
    ;;
  "")
    _show_help "$0"
    exit 2
    ;;
esac

_require_cmd grep
```

### 7. Flags and positionals

- Flags first, then the positionals
- Always handle `--`, always catch `-?*`. The `?` lets a lone `-` through
- Guard before every `shift 2`. `dash` aborts with
  `shift: can't shift that many`
- Name the shape a value must have and reject the rest. A list of bad shapes
  always misses an edge case

```sh
while [ "$#" -gt 0 ]; do
  case "$1" in
    -i | --ignore-case)
      IGNORE_CASE="true"
      shift
      ;;
    -m | --max)
      [ "$#" -lt 2 ] && _fail 2 "--max needs a count."
      _is positive-integer "$2" || _fail 2 -v max "$2" "Not a count"
      MAX_COUNT="$2"
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

PATTERN="$1"
shift
```

### 8. Cleanup

- Register the trap before the first thing it must clean
- End a signal trap by resending the signal. A trap stops the signal from ending
  the script, so without it the script runs on past its own cleanup
  - Call `cleanup` and clear EXIT in it. POSIX leaves open whether EXIT runs
    when a signal kills the script

```sh
# ╭───
# │ Cleanup
# ╰───

# shellcheck disable=SC2329 # called by trap
cleanup() {
  # 'set -u' aborts on an unset TEMP_DIR, so default it
  rm -rf "${TEMP_DIR:-}"
}

trap cleanup EXIT # normal exit
trap 'cleanup; trap - EXIT INT; kill -INT $$' INT # Ctrl-C
trap 'cleanup; trap - EXIT TERM; kill -TERM $$' TERM # kill, timeout, CI cancel
trap 'cleanup; trap - EXIT HUP; kill -HUP $$' HUP # SSH drop, closed window

TEMP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/find-in-files.XXXXXX") \
  || _fail 3 "Could not create a temporary directory"
```

### 9. Main

- Print results to stdout, everything else to stderr
  - `printf` over `echo`, data through `%s`
  - Never `printf '%b'` on data. It reads the escapes inside, eg. `C:\new`
    prints a newline
- Read stdin when no file is given
  - Read only when `[ ! -t 0 ]`
- Ignore stdin when a file is given, as `grep` and `wc` do
- Warn and skip an item you cannot use, finish the rest, then fail

```sh
# ╭───
# │ Main
# ╰───

if [ "$#" -eq 0 ] && [ ! -t 0 ]; then
  STDIN_FILE=$(mktemp "$TEMP_DIR/stdin.XXXXXX")
  cat > "$STDIN_FILE"
  set -- "$STDIN_FILE"
fi

if [ "$#" -eq 0 ]; then
  _fail 2 "No file and no piped input"
fi

FOUND=""
SKIPPED=""
for FILE in "$@"; do
  FILE_STATUS=0
  search_file "$PATTERN" "$FILE" || FILE_STATUS=$?

  case "$FILE_STATUS" in
    0) FOUND="true" ;;
    1) ;;
    *)
      _warn -v path "$FILE" "Search failed, skipping"
      SKIPPED="true"
      ;;
  esac
done
```

### 10. The last line

- Never end a script or a function on a bare `[ ] && { }`
  - A false test becomes the exit code, eg. `[ -n "$FOUND" ] && exit 0` alone
    exits 1 when nothing matched, by accident
- Exit on purpose in every branch, and return the code the man page promised

```sh
if [ -n "$SKIPPED" ]; then
  _fail 3 "Some files could not be searched"
fi

if [ -n "$FOUND" ]; then
  exit 0
fi

_info -v pattern "$PATTERN" "Nothing matched"
exit 1
```

## Verify

Run `npm run lint`, or directly `./tools/verify ./bin ./tools`, before handing
over. It checks every script with:

- `shellcheck -s sh`
- `dash -n` and `busybox sh -n`
- `--help` exits 0, an unknown flag exits 2
- a command has `+x`, a `*.sh` library does not
