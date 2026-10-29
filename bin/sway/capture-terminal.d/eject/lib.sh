#!/bin/sh

# NAME
#   lib.sh - Functions for capture-terminal scenes
#
# DESCRIPTION
#   Each scene sources this file. Use to customize `_say`, or add functionality.
#
# NOTES
#   `capture-terminal eject` doesn't overwrite exisiting files.
#
# ENVIRONMENT
#   CAPTURE_TERMINAL_DRY_RUN   1 in the dry run, which counts the rows

# Run the tools of the repo, eg. tsx, without npx. Under `npm run`, a nested
# npm warns about the config it inherits, so print only its errors
PATH="$(npm root --loglevel=error)/.bin:$PATH"

# _pause [seconds]
#
# Wait <seconds>, 1 by default, except in the dry run.
_pause() {
  if [ -z "${CAPTURE_TERMINAL_DRY_RUN:-}" ]; then
    sleep "${1:-1}"
  fi
}

# _say <text>
#
# Print <text> in gray, to narrate between commands.
_say() {
  printf '\033[90m󰭹 %s\033[0m\n' "$*"
}

# _run <command> [arg...]
#
# Print "$ <command> [arg...]", pause, then run <command>.
#
# RETURNS
#   The status of <command>
_run() {
  if command -v bat >/dev/null 2>&1; then
    printf '$ %s\n' "$*" | bat --style=grid --language sh --paging=never
  else
    printf '$ %s\n' "$*"
  fi

  _pause
  "$@"
}
