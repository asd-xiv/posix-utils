#!/bin/sh

# NAME
#   test-lib.sh - A small TAP test harness for POSIX shell
#
# SYNOPSIS
#   . "$TEST_ROOT/tools/test-lib.sh"
#
# DESCRIPTION
#   A test file sources it, through the setup.sh of its folder, and holds
#   _describe, _test, the functions before_each, prepare and actual, and
#   _expect. It also holds _send_keys, for a command that needs a terminal.
#   tools/test runs the file, so does a shell: dash <test-file>.
#
#   _describe prints the group once, as a comment line before its tests. A
#   result line holds the sentence of the test only:
#
#     # lib.sh :: _replace_block
#     ok 1 - given [both markers] should [replace the lines between them]
#     not ok 2 - given [no new lines] should [drop the block and its markers]
#
#   A test runs once, at its first _expect, in a subshell inside a new empty
#   folder: before_each, prepare, actual. They share one environment and run
#   under "set -e". Their output goes to prepare.* and actual.* files there.
#   "set -e" stays off wherever a command is a condition, eg. in "a && b; c"
#   or in a pipe that does not end on the failing command.
#
#   Sourcing it sets an EXIT trap. The trap prints the result of the last
#   test and the plan "1..N", then exits 1 when a test failed. A status of the
#   test file that is not 0 stays. A test file that sets its own EXIT trap
#   must call finish_all from it.
#
# EXIT CODES
#   0   Every test passed, or the file was skipped
#   1   A test failed
#   2   A broken test file, eg. an unknown verb in _expect

TEST_NAME=""  # the test in progress, "" before the first _test
TEST_STATE="" # "" not run yet, "ran", "broken" when it could not run
TEST_NOTES="" # one line per fact about a failure, printed after "not ok"
TEST_DIR=""   # the folder of the test in progress
TEST_COUNT=0
TEST_FAILED=0

# note_line <line>
# Keep a line to print under the result of the test.
note_line() {
  TEST_NOTES="$TEST_NOTES$1
"
}

# note_value <label> <value>
# Keep a value on one line, or indented below its label when it has several.
note_value() {
  case "$2" in
    "") note_line "  $(printf '%-11s' "$1") (empty)" ;;
    *"
"*) note_line "  $1
$(printf '%s\n' "$2" | sed 's/^/    /')" ;;
    *) note_line "  $(printf '%-11s' "$1") $2" ;;
  esac
}

# is_function <name>
# Return 0 when <name> is a shell function, not a program on PATH.
is_function() {
  [ "$(command -v "$1")" = "$1" ]
}

# finish_test
# Print the result of the test in progress, then forget the test.
finish_test() {
  [ -n "$TEST_NAME" ] || return 0

  if [ "$TEST_STATE" = "ran" ] && [ -n "$TEST_NOTES" ] \
    && [ -s "$TEST_DIR/actual.stderr" ]; then
    note_line "actual.stderr
$(head -n 5 "$TEST_DIR/actual.stderr" | sed 's/^/  /')"
  fi
  [ -n "$TEST_STATE" ] || note_line "no _expect"

  if [ -n "$TEST_NOTES" ]; then
    TEST_FAILED=$((TEST_FAILED + 1))
    printf 'not ok %s - %s\n' "$TEST_COUNT" "$TEST_NAME"
    printf '%s' "$TEST_NOTES" | sed 's/^/# /'
  else
    printf 'ok %s - %s\n' "$TEST_COUNT" "$TEST_NAME"
  fi

  rm -rf -- "$TEST_DIR"
  unset -f prepare actual
  TEST_NAME="" TEST_STATE="" TEST_NOTES="" TEST_DIR=""
}

# run_test
# Run the test in progress. Each phase is a plain command under "set -e", the
# subshell is too: neither stands in an "if" or "||".
run_test() {
  TEST_STATE="broken"
  if ! is_function actual; then
    note_line "no actual"
    return 0
  fi

  TEST_DIR=$(mktemp -d "${TMPDIR:-/tmp}/test.XXXXXX") || exit 3
  (
    cd "$TEST_DIR" || exit 3
    set -e
    : >"$TEST_DIR/prepare.stdout"
    : >"$TEST_DIR/prepare.stderr"
    if is_function before_each; then
      before_each </dev/null >/dev/null 2>>"$TEST_DIR/prepare.stderr"
    fi
    if is_function prepare; then
      prepare </dev/null >"$TEST_DIR/prepare.stdout" \
        2>>"$TEST_DIR/prepare.stderr"
    fi
    printf 0 >"$TEST_DIR/prepare.exit"
    actual <"$TEST_DIR/prepare.stdout" >"$TEST_DIR/actual.stdout" \
      2>"$TEST_DIR/actual.stderr"
  ) >/dev/null
  run_status=$?

  if [ -f "$TEST_DIR/prepare.exit" ]; then
    printf '%s' "$run_status" >"$TEST_DIR/actual.exit"
    TEST_STATE="ran"
  else
    printf '%s' "$run_status" >"$TEST_DIR/prepare.exit"
    note_line "prepare failed, exit $run_status"
    if [ -s "$TEST_DIR/prepare.stderr" ]; then
      note_line "$(head -n 5 "$TEST_DIR/prepare.stderr" | sed 's/^/  /')"
    fi
  fi
}

# _describe <group>
# Name the tests that follow, in a "# <group>" line. Drop the before_each of
# the group before.
_describe() {
  finish_test
  printf '# %s\n' "$1"
  unset -f before_each
}

# _test <sentence>
# Start a test: "given [...] should [...]". The functions prepare and actual
# follow, then _expect lines.
_test() {
  finish_test
  TEST_COUNT=$((TEST_COUNT + 1))
  TEST_NAME="$1"
}

# _expect [!] <verb> <file> <value>
# Compare the content of <file>, relative to the test folder, with <value>.
# The verbs are equal, contain, start-with and end-with. A "!" before the verb
# negates it. <value> is text, never a pattern. A missing <file> fails the test,
# negated or not. The first call of a test runs it.
_expect() {
  expect_is_negated=""
  if [ "${1-}" = "!" ]; then
    expect_is_negated=yes
    shift
  fi
  case "${1-}" in
    equal | contain | start-with | end-with) ;;
    *)
      printf '_expect: unknown verb "%s", use [!] equal, contain, start-with or end-with\n' "${1-}" >&2
      TEST_NAME="" # no result line for a test that did not finish
      exit 2
      ;;
  esac
  if [ "$#" -ne 3 ] || [ -z "$TEST_NAME" ]; then
    printf '_expect: needs [!] <verb> <file> <value>, after a _test\n' >&2
    TEST_NAME="" # no result line for a test that did not finish
    exit 2
  fi

  expect_line="$1 $2"
  [ -z "$expect_is_negated" ] || expect_line="! $expect_line"

  [ -n "$TEST_STATE" ] || run_test
  [ "$TEST_STATE" = "ran" ] || return 0

  if [ ! -f "$TEST_DIR/$2" ]; then
    note_line "$expect_line
  no such file"
    return 0
  fi

  expect_got=$(cat -- "$TEST_DIR/$2")
  expect_is_met=""
  case "$1" in
    equal) case "$expect_got" in "$3") expect_is_met=yes ;; esac ;;
    contain) case "$expect_got" in *"$3"*) expect_is_met=yes ;; esac ;;
    start-with) case "$expect_got" in "$3"*) expect_is_met=yes ;; esac ;;
    end-with) case "$expect_got" in *"$3") expect_is_met=yes ;; esac ;;
  esac
  [ "$expect_is_met" = "$expect_is_negated" ] || return 0

  note_line "$expect_line"
  if [ -z "$expect_is_negated" ]; then
    note_value "expected:" "$3"
    note_value "got:" "$expect_got"
  elif [ "$1" = "equal" ]; then
    note_value "unexpected:" "$expect_got"
  else
    note_value "unexpected:" "$3"
    note_value "got:" "$expect_got"
  fi
}

# _send_keys <command> <step>...
# Run <command> in a pseudo-terminal and send it the steps, for a command that
# needs a terminal, eg. fzf. Kill it after 10 seconds. A step is a number of
# seconds to wait, or a key: tab, enter, esc, up, down, alt-x, alt-e. TERM is
# xterm-256color. It calls busybox script, the only pseudo-terminal tool this
# package already depends on.
_send_keys() {
  send_command="$1"
  shift
  for send_step in "$@"; do
    case "$send_step" in
      tab) printf '\t' ;;
      enter) printf '\r' ;;
      esc) printf '\033' ;;
      up) printf '\033[A' ;;
      down) printf '\033[B' ;;
      alt-x) printf '\033x' ;;
      alt-e) printf '\033e' ;;
      *) sleep "$send_step" ;;
    esac
  done | TERM=xterm-256color busybox timeout 10 busybox script -q -c "$send_command" /dev/null >/dev/null
}

# _skip_all <reason>
# Skip the whole file. A test file or sandbox.sh calls it.
_skip_all() {
  cleanup
  trap - EXIT
  printf '1..0 # SKIP %s\n' "$*"
  exit 0
}

# cleanup
# Remove the folder of the test in progress.
cleanup() {
  rm -rf -- "${TEST_DIR:-}"
}

# finish_all
# Print the last result and the plan, then set the exit status. Call it first
# in an EXIT trap: it reads the status of the test file from $?.
finish_all() {
  finish_status=$?
  finish_test
  printf '1..%s\n' "$TEST_COUNT"
  cleanup
  if [ "$finish_status" -eq 0 ] && [ "$TEST_FAILED" -gt 0 ]; then
    exit 1
  fi
  exit "$finish_status"
}
trap finish_all EXIT
