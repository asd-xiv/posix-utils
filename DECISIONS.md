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

## One terminal setting for the package, PU_TERMINAL

**2026-10-12**

**Context:**

- Three commands open a terminal window: open-os-menu for an item, `jot` for
  Neovim, the browser of `recheck` for Alt+Enter
- The terminal, the window manager and the class of a floating window belong to
  the session of the user, not to a command
- `recheck` had `RECHECK_TERMINAL`
- `jot` named alacritty in its code

**Decision:**

- `PU_TERMINAL` holds the command that opens a terminal window and runs the
  command written after it
- Every command that needs a terminal window reads it
- No command has a terminal setting of its own
- A command that runs in a terminal does not open one. Without a terminal on
  stdin, `recheck browse` exits 3. Its caller opens the terminal, as
  open-os-menu and a waybar click do

**Rejected:**

- A setting per command, `RECHECK_TERMINAL` and `OS_MENU_TERMINAL`: each held
  the same value under the name of one reader
- `recheck browse` opening its own terminal when it has none: a call from a
  script would open a window nobody asked for. The window, its class and its
  focus belong to the caller
- `TERMINAL`, run with `-e`: it holds a program name only, so it cannot set a
  window class

**Deferred:**

- A setting for one command, read before `PU_TERMINAL`, eg.
  `PU_RECHECK_TERMINAL`
  - **Revisit when** a command needs a window of another class
- Alt+Enter that edits in the terminal of the browser, through the fzf `execute`
  action, so `recheck` reads no terminal setting
  - **Revisit when** `recheck` must run with no display

## open-os-menu lists the commands a person opens by hand

**2026-10-12**

**Context:**

- A person in a sway session needs one menu of the commands they can open
- `sys_menu`, a script in the dotfiles of the author, lists commands that are
  not in this package
- Each command has its own needs, eg. `recheck browse` needs fzf and a terminal
- rofi 1.7.5 has the row option `meta`: words it matches and does not show
- rofi 1.7.5 has the row option `nonselectable`: a person cannot pick the row

**Decision:**

- open-os-menu lists only commands of this package: `yank-symbol` and
  `recheck browse`
- An item is one line of data: icon, name, command, where it opens, health
  command, what it does, the words that find it
- open-os-menu finds a command by its path in the package, as recheck-bar finds
  recheck
- An item says if its command opens its own window or needs a terminal.
  open-os-menu opens the terminal with `PU_TERMINAL`
- open-os-menu checks two reasons an item cannot open: its command file is
  missing or not executable, and `PU_TERMINAL` is not set for an item that
  needs a terminal. Every other reason comes from the command: an item names a
  health command, eg. `recheck health`, that prints the reason and exits 1
- `recheck health` reports on the whole of recheck, not on `recheck browse`
  alone: a missing command, an fzf too old, `PU_TERMINAL` not set
- A row has two lines: the icon, the name and the command, then what the item
  does
- The command and what the item does are dim, by alpha. A reason is not dim
- The icon is one Unicode character in the text of the row, so it takes the
  color of the theme. An invisible copy of it starts the second line, so the
  name and what the item does start in the same column in any font
- The extra words a person types to find an item go in `meta`
- An item that cannot open stays in the menu with the reason, marked
  `nonselectable`
- The pure primitives, `escape_markup` and `print_row`, have a test file each.
  No test file runs rofi or a fake of it

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
  above the input and the line of shortcuts under the list. Each copy is two
  lines of rofi theme, and the sway group has no sourced file yet
  - **Revisit when** a third rofi script needs it. Then elevate it

## get-youtube-transcript prints captions in three formats

**2026-10-12**

**Context:**

- A reader needs the start and the end of each caption, to find the section of
  a video about a topic
- YouTube sends the start and the duration of each caption, in milliseconds. It
  does not send the end
- An auto-generated caption stays on screen after the next one starts, a manual
  caption does not
- An auto-generated track carries the offset of each word, a manual track
  carries none

**Decision:**

- `--format` names the output format: `text`, `clipped-jsonl` or
  `original-jsonl`
- `clipped-jsonl` sets `endMs` to the smaller of start plus duration and the
  start of the next caption, so no two captions overlap
- The keys `startMs` and `endMs` name the unit
- `original-jsonl` prints each event as YouTube sends it, for a reader who
  needs the offset of a word. A caption is an event with text

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
- The app API, the one the YouTube apps call, answers a request from the
  Android client with no API key and no cookie
- The app API is internal. YouTube can change it, or refuse a client version,
  with no notice
- Only a request to YouTube proves that the script still prints captions

**Decision:**

- The script calls the app API of YouTube as the Android client, with `curl`
  and `jq`
- One test file, `smoke`, runs the script on one public video

**Rejected:**

- YouTube Data API v3: `captions.download` needs OAuth and edit rights on the
  video, so a user downloads the captions of their own videos only. With an API
  key alone, it downloads none
- The watch page: YouTube answers the caption URLs of the page with HTTP 200
  and 0 bytes, unless the request carries a token that the JavaScript of the
  page makes
- `GET /api/timedtext?v=<id>&lang=en`: YouTube answers it with HTTP 200 and 0
  bytes too

**Deferred:**

- `yt-dlp`: it works, but took 3.5 s and 3.7 s in two runs on one video. The
  script makes two `curl` requests. Together they took 0.3 s in each run.
  `yt-dlp` also adds a dependency
  - **Revisit when** the script exits 3, could not run, on a working network,
    and a new client version does not fix it
- `smoke` runs in CI, from a GitHub runner. YouTube may refuse a request from
  one. Nobody tried
  - **Revisit when** `smoke` fails in CI and passes outside CI. Then skip
    `smoke` in CI

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
