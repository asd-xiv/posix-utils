[![Release](https://github.com/asd-xiv/posix-utils/actions/workflows/main.yml/badge.svg?branch=main)](https://github.com/asd-xiv/posix-utils/actions/workflows/main.yml)
[![npm version](https://img.shields.io/npm/v/@asd14/posix-utils.svg)](https://www.npmjs.com/package/@asd14/posix-utils)

# posix-utils

> Composable, portable POSIX shell scripts.

- :shell: No bashisms, no GNU-only flags
- :test_tube: CI lints and tests every script under `/bin/sh` of:
  - `alpine:3.22` (BusyBox `ash`)
  - `debian:trixie-slim` (`dash`)
  - `archlinux:latest` (`bash`)
- :robot: Ships the `write-posix-sh` skill for AI agents

## Table of Contents

<!-- vim-markdown-toc GFM -->

- [Scripts](#scripts)
- [Settings](#settings)
- [Install](#install)
  - [Uninstall](#uninstall)
  - [Nx monorepo](#nx-monorepo)
- [Primitives](#primitives)
  - [Logging](#logging)
  - [Predicates & Guards](#predicates--guards)
  - [Files](#files)
  - [Text](#text)
  - [Terminal](#terminal)
  - [Help](#help)
- [Exit codes](#exit-codes)
- [Develop](#develop)
- [License](#license)

<!-- vim-markdown-toc -->

## Scripts

`bin/` groups scripts by the environment they need.

| Script                       | Does                                                               | Needs                                                                                              |
| ---------------------------- | ------------------------------------------------------------------ | -------------------------------------------------------------------------------------------------- |
| `cli/fancy-log`              | Print a log line with its time, level and namespace, in color      | terminal or CI                                                                                     |
| `cli/get-youtube-transcript` | Print the transcript of a YouTube video                            | curl, jq                                                                                           |
| `cli/zettel`                 | A Zettelkasten: write a thought down, place it in a box of zettels | Neovim, fzf for `place` and `browse`. bat colors the preview when it is there                      |
| `cli/omnipack`               | Install OS dependencies, package manager agnostic                  | terminal or CI                                                                                     |
| `cli/recheck`                | A terminal UI for cron: run checks, keep the last state of each    | cron. Neovim for `edit`, fzf 0.73.0 or newer for `browse`, `PU_TERMINAL` for Alt+Enter in `browse` |
| `sway/doomst`                | Doomguy themed desktop notifications                               | Wayland, notifier. `pw-play` for `--sound`                                                         |
| `sway/jot`                   | Write a quick note in Neovim, print it to stdout                   | Wayland, Neovim, `PU_TERMINAL`                                                                     |
| `sway/zettel-bar`            | Print the count of zettels, as JSON                                | waybar, jq, `zettel`                                                                               |
| `sway/open-os-menu`          | Pick a command of posix-utils in a rofi menu, open it              | Wayland, rofi. `PU_TERMINAL` and the cli group for `zettel browse` and `recheck browse`            |
| `sway/recheck-bar`           | Print the count of checks per state, as JSON                       | waybar, jq, `recheck`                                                                              |
| `sway/yank-symbol`           | Pick symbols the keyboard lacks in a rofi grid, copy them          | Wayland, rofi, `wl-copy`                                                                           |

## Settings

Each setting is an environment variable.

| Setting         | Holds                                                                                                                                                                                                                                                                                                                                       | Read by                                         |
| --------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------- |
| `PU_TERMINAL`   | Command that opens a terminal window and runs the command written after it. The flag that takes the command differs per terminal, so include it, eg. `alacritty --class float --command`. Every command of posix-utils that opens a terminal window reads it. For `jot`, the `PU_TERMINAL` command must not return before its window closes | `open-os-menu`, `jot`, the browser of `recheck` |
| `PU_ZETTEL_DIR` | Folder that holds the notes: `draft` for drafts, `box` for zettels. Default: `~/NeoNotes`                                                                                                                                                                                                                                                   | `zettel`                                        |

Set `PU_TERMINAL` in a shell profile:

```sh
export PU_TERMINAL='alacritty --class float --command'
```

## Install

```sh
curl -fsSL https://raw.githubusercontent.com/asd-xiv/posix-utils/main/tools/install \
  | sh -s -- --group cli
```

1. `tools/install` copies the scripts into `~/.local/share/posix-utils`
2. Symlinks the group you asked for into `~/.local/bin`
3. Records both paths in `~/.local/state/posix-utils/receipt` - proof the
   package is installed on your system and source of truth for `tools/uninstall`

| Option           | Does                                           | Default                      |
| ---------------- | ---------------------------------------------- | ---------------------------- |
| `-g, --group`    | Which group to install: `cli`, `sway` or `all` | `cli`                        |
| `-d, --data-dir` | Install the scripts here                       | `~/.local/share/posix-utils` |
| `-b, --bin-dir`  | Create the command symlinks here               | `~/.local/bin`               |
| `-r, --ref`      | Branch, tag or commit to fetch                 | `main`                       |

> [!NOTE]  
> The `--bin-dir` is not added to `PATH`. Add it yourself.

### Uninstall

```sh
pu-uninstall
```

1. Reads the receipt `install` placed in `~/.local/state/posix-utils/receipt`
2. Removes the symlinks, the scripts and the receipt, itself included

### Nx monorepo

```sh
npm install @asd14/posix-utils
```

The scripts ship inside the package, so a pipeline can call them by path:

```sh
node_modules/@asd14/posix-utils/bin/cli/fancy-log info "Build finished"
```

## Primitives

`bin/lib.sh` holds domain-agnostic primitives.

### Logging

```sh
LOG_NAMESPACE="find-in-files"
_log info -v path "src/main.c" "Reading"
# => 14:32:07 INF find-in-files: Reading path=src/main.c
```

| Function                                             | Does                                                           |
| ---------------------------------------------------- | -------------------------------------------------------------- |
| `_log <level> [-v <key> <val>]... [--] <message>...` | Print one line to stderr at `<level>`                          |
| `_debug`, `_info`, `_ok`, `_warn`, `_error`          | Call `_log` at one level: debug, info, success, warning, error |
| `_fail <code> [-v <key> <val>]... [--] <message>...` | Print at error level, then exit with `<code>`                  |
| `_has_color [fd]`                                    | Tell if `<fd>` can show color                                  |

| Variable        | Does                                                                                                                       |
| --------------- | -------------------------------------------------------------------------------------------------------------------------- |
| `LOG_LEVEL`     | Last level to print, in the order of `_log` (default: info). An unknown level ends the script with 2 at the first log line |
| `LOG_NAMESPACE` | Label printed before the message                                                                                           |
| `NO_LOG_TIME`   | Hides the time when set and non-empty                                                                                      |
| `NO_COLOR`      | Disables color when set and non-empty                                                                                      |
| `TERM`          | Disables color when unset, empty or "dumb"                                                                                 |

`_log` prints nothing when `<level>` comes after `LOG_LEVEL` in this order:
`error < warning < success < info < debug`.

`<level>` also has short forms: `err`, `wrn`, `warn`, `suc`, `succ`, `inf`,
`dbg`.

> [!NOTE]  
> `cli/fancy-log` is the command form of `_log`. Use it from a shell or a
> pipeline that does not source `lib.sh`.

### Predicates & Guards

```sh
_require_cmd grep
_is positive-integer "$2" || _fail 2 -v max "$2" "Not a count"
```

| Function                 | Does                                                      |
| ------------------------ | --------------------------------------------------------- |
| `_is <type> <value>`     | Tell if `<value>` has the shape of `<type>`               |
| `_require_cmd <cmd>...`  | End the script unless the shell finds every `<cmd>`       |
| `_require_var <NAME>...` | End the script unless every `<NAME>` is set and non-empty |

### Files

| Function                             | Does                                                                    |
| ------------------------------------ | ----------------------------------------------------------------------- |
| `_download_file <url> <output-file>` | Download `<url>` into `<output-file>`                                   |
| `_resolve_bin_dir`                   | Print the first writable bin dir of `/usr/local/bin` and `~/.local/bin` |

### Text

A block is the lines between two marker lines, `<begin>` and `<end>`, in a text
that otherwise belongs to someone else: a crontab, a shell profile. A marker is
a whole line, compared as written. A text must hold no block, or exactly one:
one `<begin>`, and one `<end>` below it.

```sh
new_profile=$(_replace_block "# mine:begin" "# mine:end" 'export EDITOR="nvim"' <"$HOME/.profile") \
  || _fail 3 "The profile must hold both markers once, begin above end, or neither"
_end_with_newline "$new_profile" >"$HOME/.profile"
```

Take the result into a variable and read the status before writing it anywhere.
In a pipe, the next command reads an empty text when `_replace_block` returns 1
or 2.

| Function                               | Does                                                                                                                                      |
| -------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------- |
| `_find_block <begin> <end>`            | Read a text from stdin, print the lines of its block without the markers                                                                  |
| `_replace_block <begin> <end> <lines>` | Read a text from stdin, print it with the lines of its block replaced by `<lines>`                                                        |
| `_diff_lines <old-text> <new-text>`    | Print what changed between two sets of lines: `- <line>` for a line only in `<old-text>`, then `+ <line>` for a line only in `<new-text>` |
| `_end_with_newline <text>`             | Print `<text>` with a newline at its end, the one `$(...)` strips                                                                         |

### Terminal

| Function             | Does                                                                                   |
| -------------------- | -------------------------------------------------------------------------------------- |
| `_set_title <title>` | Set the title of the terminal window, when stderr is a terminal                        |
| `_restore_title`     | Restore the title the window had before `_set_title`                                   |
| `_wait_for_enter`    | Stop until the user presses Enter, so a window that closes with the command stays open |

### Help

| Function                   | Does                                                                                  |
| -------------------------- | ------------------------------------------------------------------------------------- |
| `_show_help <script-file>` | Print the man page of `<script-file>`: the comment block that starts at its NAME line |

## Exit codes

Every script returns the code that names what happened.

| Code      | Means                                                    |
| --------- | -------------------------------------------------------- |
| `0`       | The work is done, or the answer is yes                   |
| `1`       | No. A real answer, not a failure                         |
| `2`       | Invalid usage. The caller can fix it by retyping         |
| `3`       | Could not run. The call was right, the work still failed |
| `4`-`125` | Documented per script, under `EXIT CODES`                |

## Develop

```sh
npm run lint        # shellcheck, /bin/sh -n, --help and flag smoke tests
npm run unit-test   # the test files, under the /bin/sh of this system
npm run format      # shfmt, settings in .editorconfig

# the test files in an image, as CI runs them
docker run --rm -v "$PWD":/src:ro -w /src alpine:3.22 \
  sh -c 'bin/cli/omnipack --refresh jq curl && tools/test'
```

See [`DECISIONS.md`](DECISIONS.md) for what was decided and what was left for
later.

## License

MIT
