# Decisions

One record per decision, newest first. Each record opens with a heading and its
date, then has up to five parts, in this order. Leave out a part that is empty.

- **Context**: the need, the facts and the limits that held at the time and
  shaped the Decision. A fact that explains one Rejected or Deferred item sits
  on that item
- **Decision**: the choice
- **Rejected**: an option not chosen, with the reason, and no plan to return
- **Deferred**: work, a known gap or an option left for later, each item with a
  **Revisit when**
- **Acknowledgments**: a known gap the Decision accepts, with the reason or the
  thing that limits it, and no **Revisit when**

## Lock a `recheck` check with a folder, in `_get_runtime_dir`

**2026-10-27**

**Context:**

- "Lock with a folder in the runtime folder, one file per value" deferred the
  move of `recheck` to the folder lock
- A `recheck` check had a `noclobber` marker `<id>.running`, holding the pid and
  the start time on one line

**Decision:**

- The lock of a check is `$(_get_runtime_dir)/recheck/<id>.lock/`, holding
  `pid` and `started`, each written once
- `run` removes the lock with `rm -r` in its cleanup and at the end of the
  check, only when it took the lock
- When `run` cannot write `pid` or `started`, it removes the lock and counts the
  check as one it could not lock
- Kept from "Lock a `recheck` check with a marker in `XDG_RUNTIME_DIR`":
  - Every command trusts the lock: no command takes a lock over or checks its
    pid
  - Without a runtime folder, `run` skips every check and exits 3

**Rejected:**

- A hand-written `${XDG_RUNTIME_DIR:-/run/user/<user id>}`: `_get_runtime_dir`
  holds that rule for every command

**Deferred:**

- A command that removes a stale lock, after `ps -p <pid> -o args=` shows it
  does not run `recheck.d/run`
  - **Revisit when** a lock left by `kill -9` keeps a check skipped

**Acknowledgments:**

- `run` can still exit 3 for a check that just ran: another run removes the lock
  between a failed `mkdir` and the `[ -d ]` that follows

## Lock with a folder in the runtime folder, one file per value

**2026-10-27**

**Context:**

- `screenrecord` gets `start` and `stop`, one recording at a time
  - `stop`, `capture-terminal` and a status bar read the pid, the state and the
    output file of the recording in progress
- `mkdir` creates a folder only when there is none, in one system call
- `$XDG_RUNTIME_DIR` is the user's folder, mode 700, that a boot clears
  - cron sets no `XDG_RUNTIME_DIR`. The login manager still makes
    `/run/user/<user id>`

**Decision:**

- A lock is a folder made with `mkdir` in the runtime folder, eg.
  `$XDG_RUNTIME_DIR/screenrecord.lock`
  - It holds one file per value: `pid` first, then eg. `state` and `file`
  - The run that made it removes it with `rm -r` in its cleanup trap
- `_get_runtime_dir` in `lib.sh` prints `$XDG_RUNTIME_DIR`, else
  `/run/user/<user id>`, else exits 3
- A lock whose pid is gone, or whose pid runs another program, is stale
  - Only an explicit command removes it, eg. `screenrecord stop`
  - It checks the program with `ps -p <pid> -o args=` before it sends a signal
- Supersedes two rejections of "Lock a `recheck` check with a marker in
  `XDG_RUNTIME_DIR`": the folder as a lock, and `ps` on the pid of a marker

**Rejected:**

- A fallback to `/tmp/<name>-<user id>`: another user can create it first, and a
  boot does not always clear `/tmp`
- A `noclobber` file with `key=value` lines: every reader parses the separator,
  and a value with a newline
- `kill -0` alone on the pid of a lock: the pid can belong to another program by
  then, and `stop` would signal it

**Deferred:**

- `ps -o args=` shows a command, not when its process started. Between the check
  and the signal, the process can end and its pid can go to another
  `screenrecord start`
  - **Revisit when** a `stop` ends the wrong recording
- Move `recheck` to the folder lock and `_get_runtime_dir`
  - **Revisit when** the next change to `recheck`

## Open a new draft behind the zettel under the cursor, with Alt+Enter

**2026-10-14**

**Context:**

- A thought often comes from the zettel the user reads in the browser
- `sync` elevates a draft that holds a valid, free id, and opens no picker

**Decision:**

- Alt+Enter in the browser runs `create --behind <id>`, with the id under the
  cursor
  - `create` writes the next free child id of `<id>` into the front matter of
    the new draft, in the buffer only. An id in a draft counts as taken
  - In the drafts list, Alt+Enter opens a draft with no parent
  - The user can edit or drop `id:` in Neovim. `sync` checks it as any other id
- `sync` drops a draft only when it is empty: no front matter, no claim, no body
  - Drop `has_text`, add `is_empty_draft`

**Rejected:**

- A draft with only a front matter counts as empty: `sync` would drop an id the
  user kept on purpose

**Acknowledgments:**

- Two new drafts behind one parent, open at once, get the same id. `sync`
  elevates the newer and writes a sync message into the older

## Switch the browser between the box and the drafts with Tab

**2026-10-14**

**Context:**

- The browser listed the zettels only. The user could open a draft with a sync
  message only from outside `zettel`
- The record of 2026-10-13 deferred a command that lists the drafts and opens
  one again
- fzf has no variable that one key binding sets and another reads

**Decision:**

- Tab switches the browser between the box and the drafts
  - The prompt holds which list is open: `box> ` or `drafts> `. The bindings of
    Tab and Enter read it in a `transform` action
  - `browse --drafts` opens on the drafts. The box is the default
- A draft row shows the day folder, the name and the claim of the draft. A draft
  without a claim shows its first line of text instead
- The row of a draft with a sync message shows `⚠` and the reason
- `show` and `edit` take a zettel id or the path of a draft or a zettel
- The picker of `place` lists zettels only: a parent is a zettel

**Rejected:**

- "box" for the whole folder in `PU_ZETTEL_DIR`: a draft is outside the box
  until `sync` elevates it, as a slip on the desk is outside Luhmann's box
- `--box drafts|zettels`: two lists and one default need a yes/no flag only

## Show one line per zettel in the picker and the browser

**2026-10-14**

**Context:**

- Each row in fzf had a second line: the body of the zettel, dim
  - fzf searched the names and the bodies
  - Two-line rows need `--read0`, a NUL after each row and fzf 0.53.0 or newer

**Decision:**

- A row is one line: the id, the path and the name, with a tab between them
  - fzf shows and searches the name only

**Rejected:**

- The body in a field fzf does not show, for search: fzf searches only the
  fields that `--with-nth` shows

**Acknowledgments:**

- A word that is only in the body no longer finds the zettel

## Keep the rules of the box and the drafts in `zettel sync`

**2026-10-14**

**Context:**

- The name of a zettel was the only copy of its id
  - A rename by hand or by another app loses the id, and with it the lineage
- Syncthing keeps a conflict copy under a new name, with the same text
- A new claim in `edit` left the old slug in the name
- The user edits several files in one Neovim session and expects each change to
  apply when Neovim closes

**Decision:**

- The front matter of a zettel holds `id:` and `placed:`
  - `sync` builds the name from the text: the id from the front matter, the slug
    from the claim
  - `placed:` is the time the zettel got its id. `sync` writes a new time when
    the id differs from the id in the old name
- `sync` runs every rule of the box and the drafts, in three parts
  - `refresh_box` checks each zettel, oldest `placed:` first
  - `refresh_drafts` removes the drafts with no text and runs the picker for a
    draft with a claim and no `id:`
  - `elevate_valid_drafts` moves each draft with a claim and `id:` into the box
- `sync` runs two checks on the box and on the drafts: one for the format, one
  for the rules of the box
  - `validate_zettel` checks one file: the front matter closes, `id:` is a
    Folgezettel id, a claim gives a slug
  - `validate_box_entry` checks the box: no other zettel holds the id
  - `sync` moves a zettel that fails a check to the drafts. It keeps a draft
    that fails a check in the drafts. Each gets the reason in a message above
    its claim. The message is not a claim, so `sync` leaves the file alone until
    the user removes it
- The first file to reach an id keeps it
  - `refresh_box` goes oldest `placed:` first. A zettel whose id changed counts
    as placed now, so the zettel that held the id keeps it
  - `elevate_valid_drafts` runs after `refresh_box`, so `sync` never moves a
    zettel out of the box to make room for a draft
- `place` writes `id:` and `placed:` into the draft. `sync` is the only command
  that writes into the box
  - `place` skips each id in a draft, so a zettel that left the box returns
    under its id
- `_is folgezettel` in `lib.sh` accepts digits and lowercase letters, a digit
  from 1 to 9 first, and no run of digits that starts with 0
  - `1b03` and `1b3` would name one position in the tree
- `create` runs `sync`. `edit` runs `sync --no-place`: only a user who just
  wrote a draft gets a picker
- `sync` runs the on-place hook when a draft enters the box
- `sync` runs the on-update hook from its exit, when the list of drafts and
  zettels differs from the list at its start
  - A failure or Ctrl+C after a move still runs the hook. A part does not report
    its changes, so it cannot forget one

**Rejected:**

- A folder for zettels that break a rule: the drafts already hold them, each
  with a message
- `sync` reads the id from the name, not from the front matter: a rename by hand
  would give a zettel a new id, and with it a new parent
- Every zettel that shares an id goes back to the drafts: no zettel would hold
  the id, and its children would lose their parent
- A draft with a taken id enters the box and the older of the two keeps the id:
  a fix to one file would make `sync` move another out of the box
- `sync` on each save in Neovim: a rename under an open buffer makes the next
  `:w` write the old name back
- Pickers after `edit`: `sync` would open a picker for a draft from last week
  while the user reads the box

**Deferred:**

- One letter per run in `_is folgezettel`, so `1ab` is not an id
  - **Revisit when** a parent that ends in a digit gets a 27th child. With one
    letter per run, `place` must then refuse it
- A stamp file, so `sync` reads only the files changed since the last sync, and
  `--force` to read all
  - **Revisit when** a `sync` that changes nothing takes more than 200 ms
- A rule of the box that a parent must exist, eg. `2` for `2b`
  - **Revisit when** a zettel without a parent confuses the user. The rule must
    warn and move nothing: otherwise `sync` would move each child of a zettel
    that left the box out of the box

**Acknowledgments:**

- `sync` moves a zettel with no claim to the drafts. `show` and `recent` print
  its bare id in the lineage of each child until it returns
- `create` and `sync` open the picker again for a draft with a claim that the
  user skipped
- `sync` has no test file: it opens fzf and changes the box and the drafts
  - Each pure primitive it uses has one test file, eg. `validate_zettel`,
    `validate_box_entry` and `build_zettel_name`. `has_text` and the `list_`
    primitives have none

## Place a draft in the sitting where the user wrote it, with `zettel`

**2026-10-13**

**Context:**

- The author kept one draft file per day for five years
  - More than half of the drafts with text held several thoughts
  - The author changed 7 of 55 drafts after their first day
- Every structure for permanent notes made the author hold a later sitting to
  turn a draft into a note
  - The author stopped using each one
- A Folgezettel id holds the lineage of a zettel: `1b3` stands behind `1b`, and
  `1b` behind `1`
- A tool that sorts names as text lists `10` before `2`
- When the query changes, fzf keeps the row number that `pos` set
  - A query with fewer matches leaves no row under the cursor, and Enter picks
    nothing

**Decision:**

- A draft is one thought, one file in the folder of its day
- Line 1 holds the claim, the thought as one sentence, as `# <claim>`
  - `create` opens Neovim with `# ` on line 1, in the buffer only: no file
    exists before the first save
  - When Neovim closes, `create` opens the picker for a draft with a claim
  - `create` keeps a draft without a claim and asks nothing
- A zettel is the file `<id>.<slug>.md` in the box
  - The slug is the claim as a file name
- The picker lists every zettel, with the cursor on the last one placed
  - fzf searches the file names and the texts
  - `change:first` puts the cursor on the first match when the query changes
- `place` gives the draft its id: the largest child of the parent plus one
  - A gap stays empty, because an id never changes
- The folder in `PU_ZETTEL_DIR` is the only record: no index and no log
  - A zettel holds the time of its placing on line 2, in UTC, so text order is
    time order
- An id has no padding. `sort_ids` builds a padded key and sorts on it
- `zettel-bar` shows the count of zettels, and the last 5 with their lineage as
  the tooltip
- Two hooks, as in `recheck`
  - `on-place <id> <file>` after a draft is placed, eg. for a notification
  - `on-update` when Neovim closes after `create` or `edit`, and after a draft
    is placed, eg. to refresh the bar
- The browser opens a zettel with `edit`, then reads the box again: the user may
  have removed the zettel in Neovim
- `show --color` prints the text through bat when bat is there
- The icon is `⚑`, in the bar and in `open-os-menu`: a flag stands for a claim
- `open-os-menu` lists the browser as its first item, with `health` as its
  health command
- The name is `zettel`: it names the thing a person keeps
- Elevate `_set_title` and `_restore_title` from `recheck` to `lib.sh`: the
  browser and the editor of `zettel` are their second consumer

**Rejected:**

- An SQLite index: a second copy of every fact, which a rename in Neovim leaves
  stale
- Zero-padded ids: the author reads and writes the id as Luhmann wrote it
- `sort -V`: a GNU flag
- `ls -v`: also GNU, and it lists a child before its parent when a slug holds a
  hyphen
- One draft file per day, with a selection placed out of it: placing is then a
  second act the user must start
- A count of drafts, a count per day and a streak: each can fall
- Note types and tags: the id is the one link a zettel must have
- The name `notes`: the author has an older command with that name
- The name `neo-notes`: "neo" is true only while the older command exists
- An icon from a Nerd Font: a system without the font shows an empty square
- Stop words left out of the slug: a slug without "they" and "in" loses the
  claim
- `_run_hook` in `lib.sh`: the `run_hook` of `recheck` sources an env file
  first, for cron
- `start:pos`, `result:pos` and `load:pos` with `unbind`: each leaves the same
  row number in place after a query

**Deferred:**

- A view that ranks branches by size
  - **Revisit when** the box holds 30 zettels
- The picker sorted by the words a zettel shares with the draft
  - **Revisit when** the box holds 100 zettels
- Scores from a model beside the draft window, for the likely parent and branch
  of the draft
  - **Revisit when** the user places with the sorted picker and still picks a
    wrong parent
- A command that lists the drafts and opens one again
  - **Revisit when** the user opens a draft by hand a second time
- A slug for a claim outside ASCII
  - **Revisit when** `place` rejects a claim, or a slug loses a whole word

**Acknowledgments:**

- Only `zettel` shows the Folgezettel order
- Two machines that place a draft offline can give two files the same id
  - `zettel ls` warns and skips the second file
- `create`, `place`, `browse` and `edit` have no test file: each needs Neovim,
  fzf or a terminal
  - The pure primitives have one test file each

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
  - **Revisit when** `run` logs the same error for each check of a run command

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
  - Ran each command with `--help` and with an unknown flag, under dash and
    BusyBox ash
  - Failed in CI, on the Ubuntu runner with shellcheck 0.9.0
  - Succeeded locally with shellcheck 0.11.0
- `tools/test` runs each test file under `/bin/sh` only
  - CI runs them once in each of the three images
- shellcheck 0.11.0 reports `SC2329` on a function that nothing calls by name
  - 0.9.0 and 0.10.0 report `SC2317` on each command inside it
- Alpine 3.22 and Debian trixie have shellcheck 0.10.0, Arch has 0.11.0

**Decision:**

- `tools/verify`:
  - Stop parsing scripts with `dash -n` and `busybox sh -n`
  - Parse each script, and run each command with `--help` and with an unknown
    flag, under `/bin/sh` only
  - Support shellcheck 0.11.0 or newer only, so a script disables `SC2329` and
    never `SC2317`
- CI:
  - Run `tools/verify` in the Lint job, in the three images of the Unit Test job
  - In each image, use `omnipack` to install shellcheck, pinned at 0.11.0
- `omnipack`:
  - Add a recipe for shellcheck. It installs the latest version when
    `SHELLCHECK_VERSION` is not set

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
  - open-os-menu checks two reasons: the command file of the item is missing or
    not executable, `PU_TERMINAL` is not set for an item that needs a terminal
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
  - The one that ran fzf in a pseudo-terminal needed a working `script` command
    and fzf 0.73.0 or newer
  - Alpine 3.22 has fzf 0.62 and no `script` command, Debian trixie has fzf 0.60
  - It ran in one image of the three, took 3.7 s of a 5 s run and proved one key
    binding
  - **Revisit when** a release has a broken key binding
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
  - **Revisit when** the script exits 3 on a working network, and a new client
    version does not fix it
- `smoke` runs in CI, from a GitHub runner
  - YouTube may refuse a request from one. Nobody tried
  - **Revisit when** `smoke` fails in CI and passes outside CI. Then skip
    `smoke` in CI

## Tests use a home-made harness, POSIX sh only

**2026-10-10**

**Decision:**

- `tools/test-lib.sh` is the harness, `tools/test` the runner
- The author colocates a test file with the code it proves, one per function or
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

- `install` writes `$XDG_STATE_HOME/posix-utils/receipt` before it changes any
  other file
  - The receipt records `data_dir`, `bin_dir`, `group`, `ref` and `archive_url`
- `uninstall` reads it and needs no options
- After a partial install the receipt still names both paths, so `uninstall` can
  remove them

**Deferred:**

- An atomic install: write the new tree to `<data-dir>.new`, then swap it with
  the old one
  - `install` replaces an existing install, so a failed run would need to
    restore the previous version, not remove everything
  - That needs the old tree kept aside, links rebuilt from it and the previous
    ref recorded
  - **Revisit when** upgrades must never break a working install
