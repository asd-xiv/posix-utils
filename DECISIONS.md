# Decisions

One record per decision, newest first. Each record opens with its date, then
has up to four parts, in this order. Leave out a part that is empty.

- **Context**: the need, the facts and the limits that held at the time and
  shaped the Decision. A fact that explains one Rejected or Deferred item sits
  on that item
- **Decision**: the choice
- **Rejected**: an option not chosen, with the reason, and no plan to return
- **Deferred**: work, a known gap or an option left for later, each item with a
  **Revisit when**

## Tests use a home-made harness, POSIX sh only

**2026-10-10**

**Decision:**

- `tools/test-lib.sh` is the harness, `tools/test` is the runner
- The package colocates a test file with the code it proves, one per function
  or command: `bin/lib.t/<function>`, `bin/cli/recheck.t/<command>`
- A test file sources the harness and runs alone:
  `dash bin/lib.t/_replace_block`
- A test defines `actual`, and `prepare` when it needs one. The harness keeps
  the exit code, stdout and stderr of each as a file
- A test states what it expects with `_expect [!] <verb> <file> <value>` and
  nothing else. The verbs are `equal`, `contain`, `start-with` and `end-with`
- `_send_keys` runs a command in a pseudo-terminal, through `busybox script`
- The runner runs every test file under dash, BusyBox and bash

**Rejected:**

- bats-core: needs bash
- ShellSpec: last release in January 2021
- Python for the pseudo-terminal: a second language

**Deferred:**

- `_expect` fails on a missing file, negated or not. No verb passes on one
  - **Revisit when** a test must prove that a file is absent
- The tests run on the host, not in a container
  - A file in `recheck.d` runs under the `/bin/sh` of the host, whatever shell
    runs the test file
  - The tests passed in a bubblewrap container with dash as `/bin/sh`.
    bubblewrap starts in 4 ms, `docker run` in 384 ms
  - **Revisit when** a file in `recheck.d` must run under a shell that is not
    the `/bin/sh` of the host
- The `recheck` tests skip themselves under BusyBox
  - They put a fake `crontab` first on `PATH`. BusyBox runs its own `crontab`
    applet instead
  - Nobody tried BusyBox in the bubblewrap container
  - **Revisit when** a `recheck` command must pass under BusyBox
- The `browse` test sends its keys after fixed waits, so it can fail on a slow
  machine
  - **Revisit when** it fails with no change to the code

## Install records a receipt, it does not roll back

**2026-09-16**

**Decision:**

- `install` now writes `$XDG_STATE_HOME/posix-utils/receipt` before touching
  the filesystem, recording `data_dir`, `bin_dir`, `group`, `ref`, and
  `archive_url`
- `uninstall` reads it and needs no options
- A partial install leaves both paths named in the receipt, so `uninstall` can
  clean up without extra information

**Deferred:**

- Atomic installs via `<data-dir>.new` staging and swap. `install` replaces an
  existing install, so a failed run would need to restore the previous version
  rather than remove everything — requiring the old tree kept aside, links
  rebuilt from it, and the previous ref recorded
  - **Revisit when** upgrades must never break a working install
