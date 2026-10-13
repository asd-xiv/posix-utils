# Decisions

One record per decision, newest first. Each record opens with its date, then has
up to five parts, in this order. Leave out a part that is empty.

- **Context**: the need, the facts and the limits that held at the time and
  shaped the Decision. A fact that explains one Rejected or Deferred item sits
  on that item
- **Decision**: the choice
- **Rejected**: an option not chosen, with the reason, and no plan to return
- **Deferred**: work, a known gap or an option left for later, each item with a
  **Revisit when**
- **Acknowledgments**: a known gap the Decision accepts, with the reason, and no
  **Revisit when**

## Lock a `recheck` check with a marker in `XDG_RUNTIME_DIR`

**2026-10-13**

**Context:**

- cron and a person can start the same check at the same time
- A marker, a file per check, meant "running"
  - `run` took over a marker whose process was gone: look, remove, create
  - Two run commands that started together could both take it over, and both ran
    the check
- With `noclobber`, dash, bash and BusyBox ash create a file only when there is
  none, in one system call
- A shell gives one exit code for "the file exists" and for "cannot create the
  file"
- A login creates `/run/user/<user id>`, a boot removes it
  - cron sets no `XDG_RUNTIME_DIR`

**Decision:**

- The marker is `<id>.running` in the runtime folder, `$XDG_RUNTIME_DIR/recheck`
  - Without `XDG_RUNTIME_DIR`, `/run/user/<user id>/recheck`
- `run` creates the marker with `noclobber` and removes it when the check ends
- Every command trusts the marker: a check with a marker is running
  - No command takes a marker over
- `run` skips a check that has a marker
- `run` skips a check when it cannot create the marker
  - It runs the other checks
  - Then it exits 3

**Rejected:**

- A folder made with `mkdir` as the lock: `kill -9` leaves it as it leaves the
  marker, and a folder holds no start time
- `kill -0` and `ps` to ask whether the process of a marker still runs: the
  process id can belong to another program by then
- `[ -w ]` on the runtime folder: it passes for root and on a full file system
- A second try when `run` cannot create the marker: it runs a check again right
  after another run command ran it

**Deferred:**

- `flock`: the kernel releases the lock when the process ends, in any way
  - A run command that ends by `kill -9` leaves its marker
    - The check runs again only after a person or a boot removes the marker
  - `flock` is not in POSIX
  - **Revisit when** a marker left by `kill -9` keeps a check skipped
- A runtime folder for a user with no session: without `/run/user/<user id>`,
  `run` exits 3
  - **Revisit when** `recheck` must run where its user does not log in
- `run` removes the marker before it records the run
  - Two run commands can record their runs out of order
  - **Revisit when** the bar shows a wrong state
- `run` writes `last` and `state` in place
  - A reader can see an empty file
  - **Revisit when** the bar shows an empty state
- `--fail-fast`, to end the run command at the first marker it cannot create
  - **Revisit when** one cause logs an error for each check of a run command

**Acknowledgments:**

- A run command can exit 3 for a check that just ran
  - Another run command removes the marker after the first fails to create it,
    and before the first asks whether it exists
  - Rare: the check of the other run command must end between those two steps
  - The first run command still runs its other checks

## Skip `get-youtube-transcript -> smoke` test file in CI

**2026-10-13**

**Context:**

- `smoke` runs get-youtube-transcript on one public video
- In the Unit Test job, `smoke` failed: YouTube answered its request with
  `LOGIN_REQUIRED`
  - `smoke` passes outside CI
- GitHub sets `CI` in every job

**Decision:**

- `smoke` skips itself when `CI` is not empty

**Acknowledgments:**

- Nothing in CI proves that get-youtube-transcript still prints captions
  - Outside CI, `tools/test` runs `smoke`

## Run `tools/verify` in CI under three images

**2026-10-12**

**Context:**

- `tools/verify`:
  - Parsed each script with `dash -n` and `busybox sh -n`
  - Ran the smoke test under dash and BusyBox ash
  - Failed in CI, on the Ubuntu runner with shellcheck 0.9.0
  - Succeeded locally with shellcheck 0.11.0
- `tools/test` runs each test file under `/bin/sh` only
  - CI run them separately in 3 images
- shellcheck 0.11.0 reports `SC2329` on a function that nothing calls by name
  - 0.9.0 and 0.10.0 report `SC2317` on each command inside it
- Alpine 3.22 and Debian trixie have shellcheck 0.10.0, Arch has 0.11.0

**Decision:**

- `tools/verify`:
  - Stop parsing scripts with `dash -n` and `busybox sh -n`
  - Parse each script and run the smoke test under `/bin/sh` only
  - Support shellcheck 0.11.0 or newer (don't have to handle `SC2317`)
- CI:
  - Run `tools/verify` in the Lint job, in the three images of the Unit Test job
  - In each image, use `omnipack` to install shellcheck, pinned at 0.11.0
- `omnipack`:
  - Add a recipe for shellcheck: installs latest version if `SHELLCHECK_VERSION`
    not set

**Acknowledgments:**

- The pre-push hook runs `tools/verify` under one shell, the `/bin/sh` of the
  system
- Only CI runs `tools/verify` under the `/bin/sh` of each of the three images
  - CI publishes a release only after the Lint job passes in all three images

## Use one terminal setting for the package, PU_TERMINAL

**2026-10-12**

**Context:**

- Three commands open a terminal window: open-os-menu for an item, `jot` for
  Neovim, the `recheck` browser for Alt+Enter
- Terminal, window manager and floating window class belong to the user's
  session, not to a command
- `recheck` had `RECHECK_TERMINAL`
- `jot` named alacritty in its code

**Decision:**

- `PU_TERMINAL` holds the command that opens a terminal window and runs the
  command written after it
- Every command that needs a terminal window reads it
- A command that runs in a terminal does not open one:
  - Its caller opens the terminal, as open-os-menu and a waybar click do
  - Without a terminal on stdin, `recheck browse` exits 3

**Rejected:**

- A setting per command, `RECHECK_TERMINAL` and `OS_MENU_TERMINAL`: each held
  the same value under the name of one reader
- `recheck browse` opening its own terminal when it has none: a call from a
  script would open a window nobody asked for
- `TERMINAL`, run with `-e`: it holds a program name only, so it cannot set a
  window class

**Deferred:**

- A setting for one command, read before `PU_TERMINAL`, eg.
  `PU_RECHECK_TERMINAL`
  - **Revisit when** a command needs a window of another class
- Alt+Enter editing in the browser's terminal, through the fzf `execute` action,
  so `recheck` reads no terminal setting
  - **Revisit when** `recheck` must run with no display

## Add `open-os-menu` command

**2026-10-12**

**Context:**

- A person in a sway session needs one menu of the commands they can open
- `sys_menu`, a script in the author's dotfiles, lists commands not in this
  package
- Each command has its own needs, eg. `recheck browse` needs fzf and a terminal
- rofi 1.7.5 row options:
  - `meta`: words rofi matches and does not show
  - `nonselectable`: a person cannot pick the row

**Decision:**

- open-os-menu:
  - Lists only commands of this package: `yank-symbol` and `recheck browse`
  - Finds a command by its path in the package
  - Opens the terminal with `PU_TERMINAL`
- An item is one line of data: icon, name, command, where it opens (its own
  window or a terminal), health command, what it does, the words that find it
- An item that cannot open stays in the menu with the reason, marked
  `nonselectable`
  - open-os-menu checks two reasons: its command file is missing or not
    executable, `PU_TERMINAL` is not set for an item that needs a terminal
  - Every other reason comes from its health command, eg. `recheck health`,
    which prints the reason and exits 1
  - `recheck health` reports on the whole of recheck, not on `recheck browse`
    alone: a missing command, an fzf too old, `PU_TERMINAL` not set
- A row:
  - Two lines: icon, name and command, then what the item does
  - Command and what the item does are dim, by alpha. A reason is not dim
  - The words that find the item go in `meta`
  - Icon is one Unicode character in the row's text, so it takes the theme's
    color
  - An invisible copy of the icon starts the second line, so name and what the
    item does start in the same column in any font
- `escape_markup` and `print_row`, the pure primitives, have a test file each
  - No test file runs rofi or a fake of it

**Rejected:**

- A list of what the browser needs, in `recheck.d/checks.sh`: that file holds
  what two or more commands of recheck use, not the needs of one
- The icon as the rofi `icon` option of the row: rofi 1.7.5 draws a text icon
  black, which cannot be read on a dark row
- A guard on the row number that rofi prints: with `-no-custom` and `-format d`,
  rofi prints only the number of a row it was given
- Icons from a Nerd Font: a system without the font shows empty boxes
- One line per row, with what the item does in a column: the columns line up
  only in a monospace font
- A fixed color for the dim text: the theme inverts the colors of the selected
  row, and a fixed color cannot be read there

**Deferred:**

- The scripts of the dotfiles for removable devices: `lsremovable`,
  `usbauto-ctl`, `usbauto-rofi` and `usbauto-sway`
  - **Revisit when** the author moves them into this package. Then add one item
- `yank-symbol` has no health command
  - **Revisit when** a person picks Symbols and it does not open
- The rofi layout that yank-symbol and open-os-menu both write: the instruction
  above the input and the line of shortcuts under the list
  - Each copy is two lines of rofi theme
  - The sway group has no sourced file yet
  - **Revisit when** a third rofi script needs it. Then elevate it

## The test files run under the /bin/sh of the system, CI runs them in three images

**2026-10-12**

**Context:**

- A test calls a command by its path
  - The command runs under the shell its `#!/bin/sh` names, whatever shell runs
    the test file
- `tools/test` ran each test file under dash, BusyBox ash and bash
  - Where `/bin/sh` is bash, each command ran under bash three times
  - Only a sourced function changed shell
- An image has its own `/bin/sh`, `sed`, `tr` and `mktemp`

**Decision:**

- `tools/test` runs each test file once, under `/bin/sh`
- CI:
  - Runs `tools/test` in a container, once per image: `alpine:3.22` for BusyBox
    ash, `debian:trixie-slim` for dash and `archlinux:latest` for bash
  - In the container, `omnipack` installs the tools the test files need: `jq`
    and `curl`
- `enable`, `disable` and `toggle` have a test file each, as `run` and `ls` do
  - `recheck browse` also calls `show` and `edit`, which have none

**Rejected:**

- Each test file under three shells on one system: it changes the shell of the
  test file, not of the command

**Deferred:**

- A test file for `recheck browse`
  - The one that drove fzf through a pseudo-terminal needed a working `script`
    command and fzf 0.73.0 or newer
  - Alpine 3.22 has fzf 0.62 and no `script` command, Debian trixie has fzf 0.60
  - It ran in one image of the three, took 3.7 s of a 5 s run and proved one key
    binding
  - **Revisit when** a broken key binding reaches a release
- Where `/bin/sh` is bash, a fault that shows only under dash or BusyBox ash
  shows in CI first
  - `tools/verify` parses each script with `dash -n` and `busybox sh -n` before
    a push
  - **Revisit when** CI fails for a fault that a run in an image would have
    shown before the push. Then run the test files in an image from the pre-push
    hook
- A run on macOS, where `/bin/sh` is bash 3.2 and the tools are BSD
  - It needs a macOS runner, not an image
  - **Revisit when** the package must run on macOS

## get-youtube-transcript prints captions in three formats

**2026-10-12**

**Context:**

- A reader needs the start and end of each caption, to find the section of a
  video about a topic
- YouTube sends each caption's start and duration, in milliseconds, not its end
- An auto-generated caption stays on screen after the next one starts, a manual
  caption does not
- An auto-generated track carries the offset of each word, a manual track none

**Decision:**

- `--format` takes `text`, `clipped-jsonl` or `original-jsonl`
- `clipped-jsonl` sets `endMs` to the smaller of start plus duration and the
  start of the next caption, so no two captions overlap
- The keys `startMs` and `endMs` name the unit
- `original-jsonl` prints each event as YouTube sends it, for a reader who needs
  the offset of a word
  - A caption is an event with text

**Rejected:**

- Times in seconds: YouTube sends milliseconds as integers
- Two flags, `--data <clipped|original>` and `--format <text|jsonl>`: `text`
  prints no times, so `--data` would change `jsonl` only

**Deferred:**

- An offset per word in `clipped-jsonl`
  - **Revisit when** a reader needs the offset of a word and cannot read
    `original-jsonl`

## get-youtube-transcript calls the app API of YouTube

**2026-10-12**

**Context:**

- The script must print the captions of a public video of any channel
- The app API, the one the YouTube apps call:
  - Answers a request from the Android client with no API key and no cookie
  - Is internal: YouTube can change it or refuse a client version without notice
- Only a request to YouTube proves that the script still prints captions

**Decision:**

- The script calls the app API as the Android client, with `curl` and `jq`
- One test file, `smoke`, runs the script on one public video

**Rejected:**

- YouTube Data API v3: `captions.download` needs OAuth and edit rights on the
  video, so a user downloads the captions of their own videos only
- The watch page: YouTube answers the page's caption URLs with HTTP 200 and 0
  bytes, unless the request carries a token that the page's JavaScript makes
- `GET /api/timedtext?v=<id>&lang=en`: YouTube answers it with HTTP 200 and 0
  bytes too

**Deferred:**

- `yt-dlp`:
  - Works, but took 3.5 s and 3.7 s in two runs on one video
  - The script's two `curl` requests took 0.3 s together in each run
  - Adds a dependency
  - **Revisit when** the script exits 3, could not run, on a working network,
    and a new client version does not fix it
- `smoke` runs in CI, from a GitHub runner
  - YouTube may refuse a request from one, nobody tried
  - **Revisit when** `smoke` fails in CI and passes outside CI. Then skip
    `smoke` in CI

## Tests use a home-made harness, POSIX sh only

**2026-10-10**

**Decision:**

- `tools/test-lib.sh` is the harness, `tools/test` the runner
- The package colocates a test file with the code it proves, one per function or
  command: `bin/lib.t/<function>`, `bin/cli/recheck.t/<command>`
- A test file sources the harness and runs alone:
  `dash bin/lib.t/_replace_block`
- A test defines `actual`, and `prepare` when it needs one
  - The harness keeps the exit code, stdout and stderr of each as a file
- A test states what it expects with `_expect [!] <verb> <file> <value>` and
  nothing else
  - Verbs: `equal`, `contain`, `start-with` and `end-with`

**Rejected:**

- bats-core: needs bash
- ShellSpec: last release in January 2021

**Deferred:**

- `_expect` fails on a missing file, negated or not
  - **Revisit when** a test must prove that a file is absent

## Install records a receipt, it does not roll back

**2026-09-16**

**Decision:**

- `install` writes `$XDG_STATE_HOME/posix-utils/receipt` before touching the
  filesystem
  - The receipt records `data_dir`, `bin_dir`, `group`, `ref` and `archive_url`
- `uninstall` reads it and needs no options
- A partial install leaves both paths named in the receipt, so `uninstall` can
  clean up

**Deferred:**

- Atomic installs via `<data-dir>.new` staging and swap
  - `install` replaces an existing install, so a failed run would need to
    restore the previous version, not remove everything
  - That needs the old tree kept aside, links rebuilt from it and the previous
    ref recorded
  - **Revisit when** upgrades must never break a working install
