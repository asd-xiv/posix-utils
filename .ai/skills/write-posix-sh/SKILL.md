---
name: write-posix-sh
description: |
  Write POSIX shell scripts and the primitives in `posix-utils/bin/lib.sh`.
  Use whenever the work is a shell script: writing, changing, reviewing, or
  porting one from bash or zsh, whatever the path or extension.
  Not for Node CLI entry points, which are TypeScript wrappers around commander.
---

Write composable, portable POSIX shell scripts that do one thing well.

## Placement

```text
posix-utils/bin/     <- Group by the running environment
|-- lib.sh           <- Primitives every script sources
|-- cli/             <- Terminal and CI, no display server
`-- sway/            <- Sway session, needs Wayland and a notifier

<package>/bin/       <- scripts only that package needs
```

## Conventions

Literate style, on one real script: `find-in-files`. Concatenate the `sh` blocks
and it runs.

### 1. Shebang and shell options

- Write POSIX: no bashisms, no GNU-only flags
- Switch to `set +e` only to read an exit code, then turn it back on. Where it
  reads clearer, use `rc=0; cmd || rc=$?`
  - `set -e` is off wherever the shell already tests the status: `if`, `while`,
    `until`, `!`, and every command but the last in an `&&` or `||` list,
    including the body of a function called there
  - `set -e` sees a subshell's status only when the assignment stands alone
    - `echo "$(im-bad)"` does not exit, `echo` ran and its status won
    - `x=$(im-bad)` exits, with no command name the status is the subshell's
  - Wrap or separate a command only when recovering is possible, or to add what
    the caller cannot already see, otherwise let `set -e` stop the script
- `set -o pipefail` returns the last failed status in a pipe (eg.
  `(exit 3) | (exit 4) | true` -> 4)
  - Turn it on around the pipe that needs it, off after
  - POSIX added it in June 2024. BusyBox `ash` has it since 1.16 (Jan 2010),
    `dash` since 0.5.13 (Sep 2025)

```sh
#!/bin/sh

set -eu
```

### 2. The man page

- Name a script `<verb>-<object>`, eg. `find-in-files`, `download-git`
  - `find` may return nothing, `get` must exit with non-zero
- Write the man page once, as comments. `_show_help "$0"` prints it back
  - Headings, in order: `NAME`, `SYNOPSIS`, `DESCRIPTION`, `ARGUMENTS`,
    `OPTIONS`, `ENVIRONMENT`, `EXAMPLE`, `EXIT CODES`, `SEE ALSO`
- Exit codes are semantic
  - `0` success. The work is done, or the answer is yes
  - `1` no. A real answer, not a failure. Only a script that asks a yes/no
    question returns it
  - `2` invalid usage. The caller can fix it by retyping (eg. a typo in a flag)
  - `3` could not run. The call was right, the work still failed (eg. a missing
    dependency)
  - `4`-`125` are free for domain specific. Document in `EXIT CODES`
  - Never return a code the shell owns: `126` (found, not executable), `127`
    (not found), `128`+n (killed by signal n) or `130` (`Ctrl-C`)

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
#   pattern   - basic regular expression
#   file      - file path to search, repeatable
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
#   0: At least one line matched
#   1: Nothing matched
#   2: Invalid usage
#   3: The search could not run
#
# SEE ALSO
#   grep
```

### 3. Domain-agnostic primitives

- Never install a dependency. Guard it with `_require_cmd`, name it in
  `SEE ALSO`

```text
_log <level> [-v <key> <val>]... <message>   level: error|warning|success|info|debug
_debug|_info|_ok|_warn [-v <key> <val>]... <message>
_fail <code> [-v <key> <val>]... <message>   logs at error level, then exits <code>
_is <type> <value>                           type: positive-integer|version|slug|identifier
_require_cmd <cmd>...                        exit 3 unless every <cmd> is on PATH
_require_var <NAME>...                       exit 2 unless every <NAME> is set
_download_file <url> <output-file>
_resolve_bin_dir                             print the first writable bin dir
_show_help <script-file>                     print the man page to stdout
```

- Levels run `error < warning < success < info < debug`
  - `LOG_LEVEL` is the cut-off: it and everything before it print.
    `LOG_NAMESPACE` labels the line
  - `bin/cli/fancy-log` is the same logger as a command, for when `lib.sh` is
    not sourced
- Never add a domain shape to `_is`. Write a local predicate in the script

```sh
# install symlinks this into PU_BIN_DIR, so dirname "$0" would point at the
# link. realpath reads through it so lib.sh can be resolved.
SCRIPT_DIR=$(dirname "$(realpath "$0")")
LOG_NAMESPACE="find-in-files"
. "$SCRIPT_DIR/../lib.sh"
```

### 4. Globals

- Declare the knobs up front, each with an explicit default. What the script
  computes belongs where it is computed
- Case implies scope: `UPPER_SNAKE` globals, `lower_snake` locals and functions
  - Never shadow a builtin: `type`, `test`, `read`, `printf`
- Name a path for what it holds, `_dir` or `_file`, unless its noun already
  does. Keep `_path` for a search list, as in `PATH`

```sh
IGNORE_CASE="" # -i/--ignore-case, "true" or ""
MAX_COUNT=""   # -m/--max, a positive integer
```

### 5. Domain primitives

- A primitive takes per-call data as arguments. A global is a config knob, set
  once from the flags, never a channel between two functions
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
# Print the matching lines. Return 0 for a match, 1 for none.
search_file() {
  # grep says 0 for a match, 1 for none and 2 for a real failure
  set +e
  grep ${IGNORE_CASE:+--ignore-case} ${MAX_COUNT:+--max-count="$MAX_COUNT"} \
    -- "$1" "$2"
  search_status=$?
  set -e

  case "$search_status" in
    0) return 0 ;;
    1) return 1 ;;
    *) _fail 3 -v path "$2" -v status "$search_status" "grep failed." ;;
  esac
}
```

### 6. Bootstrap

- Guard dependencies after the help branch. `--help` names them in `SEE ALSO`,
  so it must work to allow learning about them

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
- Always handle `--`, always catch `-?*`
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
      _is positive-integer "$2" || _fail 2 -v max "$2" "Not a count."
      MAX_COUNT="$2"
      shift 2
      ;;
    # the first positional starts with a dash, eg. the pattern -foo
    --)
      shift; break
      ;;
    -?*)
      _fail 2 -v flag "$1" "Unknown flag."
      ;;
    *) break ;;
  esac
done

[ "$#" -eq 0 ] && _fail 2 "No pattern given."

PATTERN="$1"
shift
```

### 8. Cleanup

- Register the trap before the first thing it must clean

```sh
# ╭───
# │ Cleanup
# ╰───

cleanup() {
  # 'set -u' aborts on an unset TEMP_DIR, so default it
  rm -rf "${TEMP_DIR:-}"
}

trap cleanup EXIT INT TERM HUP

TEMP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/find-in-files.XXXXXX") \
  || _fail 3 "Could not create a temporary directory."
```

### 9. Main

- Print results to stdout, everything else to stderr
  - `printf` over `echo`, data through `%s`
  - Never `printf '%b'` on data. It reads the escapes inside, eg. `C:\new`
    prints a newline
- Focus on stdin if file arguments are missing
  - Read only when `[ ! -t 0 ]`
- Ignore stdin when file arguments are present, as `grep` and `wc` do
- Warn and continue on a skipped item, exit on a broken one

```sh
# ╭───
# │ Main
# ╰───

if [ "$#" -eq 0 ] && [ ! -t 0 ]; then
  stdin_file=$(mktemp "$TEMP_DIR/stdin.XXXXXX")
  cat > "$stdin_file"
  set -- "$stdin_file"
fi

if [ "$#" -eq 0 ]; then
  _fail 2 "No file and no piped input."
fi

found=""
for file in "$@"; do
  [ -r "$file" ] || {
    _warn -v path "$file" "Cannot read. Skipping."
    continue
  }

  # search_file is not the last command in the && list, so its 1 is not fatal
  search_file "$PATTERN" "$file" && found="true"
done
```

### 10. The last line

- Never end a script or a function on a bare `[ ] && { }`
  - A false test becomes the exit code, eg. `[ -n "$found" ] && exit 0` alone
    exits 1 when nothing matched, by accident rather than on purpose
- Exit on purpose in every branch, and return the code the man page promised

```sh
if [ -n "$found" ]; then
  exit 0
fi

_info -v pattern "$PATTERN" "Nothing matched."
exit 1
```
