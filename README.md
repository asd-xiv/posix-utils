[![Release](https://github.com/asd-xiv/posix-utils/actions/workflows/release.yml/badge.svg?branch=main)](https://github.com/asd-xiv/posix-utils/actions/workflows/release.yml)
[![npm version](https://img.shields.io/npm/v/@asd14/posix-utils.svg)](https://www.npmjs.com/package/@asd14/posix-utils)

# PU, short for Posix Utils

> Cross-platform POSIX utilities for development workflows.

<!-- vim-markdown-toc GFM -->

- [Installation](#installation)
  - [NPM](#npm)
  - [Pacman (ArchLinux)](#pacman-archlinux)
  - [APT (Ubuntu)](#apt-ubuntu)
- [Usage](#usage)
  - [`pu git-has-changed` - Git Changed Detection](#pu-git-has-changed---git-changed-detection)
  - [`pu log` - Fancy Logging](#pu-log---fancy-logging)
  - [`pu ensure-installed` - Cross-Platform Package Installation](#pu-ensure-installed---cross-platform-package-installation)
- [License](#license)

<!-- vim-markdown-toc -->

## Installation

### NPM

```sh
npm install --save-dev @asd14/posix-utils
```

### Pacman (ArchLinux)

TBD

### APT (Ubuntu)

TBD

## Usage

### `pu git-has-changed` - Git Changed Detection

Check if a file has changed since a given git commit reference. This tool
compares the current state of a file against its state at a specific commit,
making it useful for conditional build steps, deployment decisions, and change
detection in CI/CD pipelines.

The tool exits with code 0 if the file has changed, making it perfect for use
in shell conditionals and npm scripts.

```sh
# In npm scripts - regenerate lock only if package.json changed
pu git-has-changed package.json --since HEAD~1 \
    && npm install

# Check against specific version tag
pu git-has-changed src/config.json --since v1.2.0 \
    && npm run rebuild-config
```

### `pu log` - Fancy Logging

Print dated, colored, namespaced, multi-level, CI aware and pretty formatted
log messages. Supports different log levels with automatic filtering and
colored output.

Messages include timestamps and can be enhanced with key-value pairs for
structured logging.

```sh
# Basic logging
pu log info "Build started"
pu log success "Deploy completed"
pu log error "Something went wrong"

# With variables
LOG_NAMESPACE="my-app"
pu log warning "Invalid parameter" \
    -v param-name "username" \
    -v param-value "null"
```

### `pu ensure-installed` - Cross-Platform Package Installation

Cross-platform package installer that automatically detects the system package
manager and installs the specified packages. Supports major Linux
distributions, macOS, and npm packages.

Packages are validated for security (only alphanumeric characters, dots,
underscores, hyphens, and plus signs allowed). Package manager flags can be
passed after -- separator.

```sh
# Auto-detect package manager
pu ensure-installed git curl jq

# Force specific package manager
pu ensure-installed --package-manager npm typescript eslint

# Pass flags to package manager
pu ensure-installed firefox -- --cask

# Install development dependencies
pu ensure-installed build-essential git nodejs npm
```

## License

MIT
