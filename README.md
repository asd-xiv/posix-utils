[![Release](https://github.com/asd-xiv/posix-utils/actions/workflows/main.yml/badge.svg?branch=main)](https://github.com/asd-xiv/posix-utils/actions/workflows/main.yml)
[![npm version](https://img.shields.io/npm/v/@asd14/posix-utils.svg)](https://www.npmjs.com/package/@asd14/posix-utils)

# posix-utils

> Composable, portable POSIX shell scripts.

<!-- vim-markdown-toc GFM -->

- [Scripts](#scripts)
- [Install](#install)
  - [Local](#local)
  - [In a Node monorepo](#in-a-node-monorepo)
- [The primitive library](#the-primitive-library)
- [Develop](#develop)
- [License](#license)

<!-- vim-markdown-toc -->

## Scripts

`bin/` groups scripts by the environment they need.

| Script          | Does                                              | Needs             |
| --------------- | ------------------------------------------------- | ----------------- |
| `cli/fancy-log` | Dated, colored, namespaced log messages           | terminal or CI    |
| `cli/omnipack`  | Install OS dependencies, package manager agnostic | terminal or CI    |
| `sway/doomst`   | Doomguy themed desktop notifications              | Wayland, notifier |
| `sway/jot`      | Write a quick note in Neovim, print it to stdout  | Wayland, Neovim   |

> [!NOTE]  
> Every script prints its own man page: `fancy-log --help`

## Install

### Local

`install` symlinks each script into the first writable system bin directory.

```sh
git clone git@github.com:asd-xiv/posix-utils.git
cd posix-utils
./install
```

`./uninstall` removes the symlinks.

### In a Node monorepo

npm carries the version and the dependency edge, nothing runs through node. The
package ships `bin/` and nothing else, so point at it by path:

```sh
npm install --save-dev @asd14/posix-utils
```

```sh
export POSIX_UTILS="node_modules/@asd14/posix-utils/bin/cli"
"$POSIX_UTILS/fancy-log" info "Build started"
```

Or add that directory to `PATH` once, in the pipeline or the Dockerfile.

## The primitive library

`bin/lib.sh` holds the primitives every script sources: logging, guards,
downloads, help. It is sourced, never executed.

```sh
#!/bin/sh

set -eu

SCRIPT_DIR=$(dirname "$(realpath "$0")")
LOG_NAMESPACE="my-script"
. "$SCRIPT_DIR/../lib.sh"

_require_cmd curl
_assert positive-integer retries "$RETRIES"
_ok -v url "$URL" "Downloaded."
```

`realpath` matters: `install` symlinks the script, so `dirname "$0"` alone would
point at the link rather than at the script.

Read `bin/lib.sh` for the full list, and
[`.ai/skills/write-posix-sh/SKILL.md`](.ai/skills/write-posix-sh/SKILL.md) for
the conventions every script here follows.

## Develop

One script runs every check, in CI and on your machine:

```sh
./verify
```

It runs `shellcheck` over each script in `bin/`, then parses and smoke tests
each one under `dash` and BusyBox `ash`. It installs nothing — a missing tool
exits 3 and says which.

## License

MIT
