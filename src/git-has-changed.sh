#!/usr/bin/env sh

# NAME
#  git-has-changed.sh - Check if a file has changed since a given git commit
#
# SYNOPSIS
#  git-has-changed.sh <file> --since <commit-ref>
#
# DESCRIPTION
#  Check if a file has changed since a given git commit reference.
#  Exits with code 0 if file has changed, 1 if unchanged or on error.
#  Useful for conditional build steps in npm scripts.
#
# ARGUMENTS
#  <file>
#   The file path to check for changes.
#
#  <commit-ref>
#   Git commit reference to compare against. Can be HEAD~1, v1.2.3,
#   origin/main, or any valid git revision.
#
# EXIT CODES
#  0 - File has changed since the specified commit
#  1 - File unchanged or error occurred
#
# EXAMPLE
#  git-has-changed.sh package.json --since HEAD~1 || npm run build:lock

# Get the directory where this script is located (symlink aware)
SCRIPT_DIR="$(dirname "$(realpath "$0")")"

# ╭───┤ Functions
# ╰─

_log() {
  LOG_NAMESPACE="git-has-changed" "$SCRIPT_DIR/log.sh" "$@"
}

validate_git_repo() {
  if ! git rev-parse --git-dir >/dev/null 2>&1; then
    _log error "Not in a git repository"
    exit 1
  fi
}

validate_file() {
  if [ ! -f "$1" ]; then
    _log error "File not found: $1"
    exit 1
  fi
}

validate_commit_ref() {
  if ! git rev-parse --verify "$1" >/dev/null 2>&1; then
    _log error "Invalid commit reference: $1"
    exit 1
  fi
}

check_file_changed() {
  file="$1"
  commit_ref="$2"

  if git diff --quiet "$commit_ref" "$file" 2>/dev/null; then
    _log info "$file unchanged since $commit_ref"
    exit 1
  else
    _log info "$file has changed since $commit_ref"
    exit 0
  fi
}

# ╭───┤ Main. Start here.
# ╰─

if [ $# -ne 3 ]; then
  _log error "Usage: git-has-changed.sh <file> --since <commit-ref>"
  exit 1
fi

FILE="$1"
SINCE_FLAG="$2"
COMMIT_REF="$3"

if [ "$SINCE_FLAG" != "--since" ]; then
  _log error "Expected --since flag, got: $SINCE_FLAG"
  exit 1
fi

validate_git_repo
validate_file "$FILE"
validate_commit_ref "$COMMIT_REF"
check_file_changed "$FILE" "$COMMIT_REF"
