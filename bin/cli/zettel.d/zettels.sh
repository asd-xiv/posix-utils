#!/bin/sh

# The settings and primitives that two or more zettel commands use, or that
# a test file sources. Each
# command file sets SCRIPT_DIR, then sources this file.

. "$SCRIPT_DIR/../../lib.sh"

# _log reads these
export LOG_NAMESPACE="zettel"
export LOG_LEVEL="${LOG_LEVEL:-info}"

# The public command. A command file runs another command only through it.
# The fzf commands of the picker and the browser read it from the environment,
# as "$PUBLIC_FILE" in quotes: a path with a space or a quote stays one word
PUBLIC_FILE=$(realpath "$SCRIPT_DIR/../zettel")
export PUBLIC_FILE

NOTES_DIR="${PU_ZETTEL_DIR:-$HOME/NeoNotes}"
DRAFT_DIR="$NOTES_DIR/draft"
BOX_DIR="$NOTES_DIR/box"
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/zettel"
# shellcheck disable=SC2034 # the command files read it
PLACE_HOOK_FILE="$CONFIG_DIR/on-place"
# shellcheck disable=SC2034 # the command files read it
UPDATE_HOOK_FILE="$CONFIG_DIR/on-update"
TAB=$(printf '\t')
NL="
"

# ╭───
# │ Primitives
# ╰───

# An id is a Folgezettel id, see "_is folgezettel" in lib.sh: runs of digits
# and runs of lowercase letters, eg. 1b3. Each run names one step of the
# lineage: 1b3 stands behind 1b, and 1b behind 1.
#
# awk compares two values that look like numbers as numbers, and the id 1e2
# looks like 100. "" after a value makes it a string.

# sort_ids
# Read rows from stdin, print them in Folgezettel order. A row is an id, or an
# id, a tab and any text. The order: 1, 1a, 1a1, 1a2, 1a10, 1b, 1z, 1aa, 2, 10.
# awk builds a key that plain sort orders: each run of digits padded to 8
# digits, each run of letters behind its length, so "z" comes before "aa". The
# ids hold no padding, only the key does. A row that starts with no id ends the
# list.
sort_ids() {
  awk -F '\t' '{
    rest = $1; key = ""
    while (length(rest) > 0) {
      if (match(rest, /^[0-9]+/)) {
        key = key sprintf("%08d", substr(rest, 1, RLENGTH))
      } else if (match(rest, /^[a-z]+/)) {
        key = key sprintf("%02d%s", RLENGTH, substr(rest, 1, RLENGTH))
      } else {
        exit 1
      }
      rest = substr(rest, RLENGTH + 1)
    }
    print key "\t" $0
  }' | LC_ALL=C sort | cut -f 2-
}

# print_lineage <id>
# Print the ids from the top-level id down to <id>, one per line: 1b3 gives 1,
# 1b and 1b3.
print_lineage() {
  printf '%s\n' "$1" | awk '{
    rest = $0; id = ""
    while (length(rest) > 0) {
      if (!match(rest, /^[0-9]+/) && !match(rest, /^[a-z]+/)) {
        exit 1
      }
      id = id substr(rest, 1, RLENGTH)
      rest = substr(rest, RLENGTH + 1)
      print id
    }
  }'
}

# print_next_child_id <parent-id>
# Read the ids in use from stdin, print the id of the next child of
# <parent-id>: its largest child plus one. An empty <parent-id> stands for the
# top level. The children of an id that ends in a digit are runs of letters: a
# to z, then aa, ab. All other children are numbers from 1. A gap stays empty,
# because an id never changes. When the user removes the largest child, place
# gives its id again.
print_next_child_id() {
  LC_ALL=C awk -v parent="$1" '
    # The run of letters after <letters>: a -> b, z -> aa, az -> ba, zz -> aaa
    function next_letters(letters,    alphabet, place, at) {
      alphabet = "abcdefghijklmnopqrstuvwxyz"

      for (place = length(letters); place > 0; place--) {
        at = index(alphabet, substr(letters, place, 1))
        if (at < 26) {
          return substr(letters, 1, place - 1) substr(alphabet, at + 1, 1) \
            substr(letters, place + 1)
        }
        letters = substr(letters, 1, place - 1) "a" substr(letters, place + 1)
      }

      return "a" letters
    }

    BEGIN {
      is_number = (parent == "" || parent ~ /[a-z]$/)
      largest = ""
    }

    substr($0, 1, length(parent)) "" == parent "" {
      child = substr($0, length(parent) + 1)

      if (is_number && child ~ /^[0-9]+$/) {
        if (child + 0 > largest + 0) {
          largest = child
        }
      }

      # A longer run is larger, two runs of one length compare as text
      if (!is_number && child ~ /^[a-z]+$/) {
        if (length(child) > length(largest) \
          || (length(child) == length(largest) && child "" > largest "")) {
          largest = child
        }
      }
    }

    END {
      if (is_number) {
        print parent (largest + 1)
      } else {
        print parent next_letters(largest)
      }
    }'
}

# print_slug <claim>
# Print the slug of <claim>: lower case, each run of characters
# outside a-z0-9 as one "-", no "-" at either end. tr runs in the C locale,
# so a letter outside ASCII is outside a-z. Return 1 and print nothing when
# nothing is left.
print_slug() {
  slug_text=$(
    printf '%s' "$1" \
      | LC_ALL=C tr '[:upper:]' '[:lower:]' \
      | LC_ALL=C tr -cs 'a-z0-9' '-'
  )
  slug_text="${slug_text#-}"
  slug_text="${slug_text%-}"

  [ -n "$slug_text" ] || return 1

  printf '%s' "$slug_text"
}

# trim_blanks <text>
# Print <text> without the spaces and tabs at each end.
trim_blanks() {
  trim_text="$1"
  trim_text="${trim_text#"${trim_text%%[! "$TAB"]*}"}"
  trim_text="${trim_text%"${trim_text##*[! "$TAB"]}"}"
  printf '%s' "$trim_text"
}

# print_now
# Print the time now, in UTC, as front matter holds it: 2026-10-14T12:00:00Z.
# The text order of two such times is their order in time.
print_now() {
  date -u +%Y-%m-%dT%H:%M:%SZ
}

# write_atomic <file> <command> [arg...]
# Write the output of <command> over <file>: into a hidden file next to it
# first, then rename that over <file>. No command reads half a file.
write_atomic() {
  atomic_file="$1"
  shift
  atomic_temp_file="${atomic_file%/*}/.${atomic_file##*/}.tmp"

  "$@" >"$atomic_temp_file"
  mv -- "$atomic_temp_file" "$atomic_file"
}

# find_claim <file>
# Print the claim of a note, the text after "#" on its claim line. In a
# draft, it is line 1. In
# a zettel, the front matter and the empty lines after it come first, and the
# claim is the next line. Blanks around the claim do not count, so "#claim" and
# "# claim" both give "claim". Return 1 when that line holds no claim: a bare
# "#", a "##" heading, any other text, or no <file>.
find_claim() {
  [ -f "$1" ] || return 1

  claim_text=$(
    awk '
      NR == 1 && $0 == "---" { front = 1; next }
      front == 1 { if ($0 == "---") { front = 2 }; next }
      front == 2 && /^[ \t]*$/ { next }
      front != 1 { print; exit }' "$1"
  )

  case "$claim_text" in
    "#"*) claim_text="${claim_text#?}" ;;
    *) return 1 ;;
  esac

  claim_text=$(trim_blanks "$claim_text")

  case "$claim_text" in
    "" | "#"*) return 1 ;;
  esac

  printf '%s' "$claim_text"
}

# find_front_matter_value <key> <file>
# Print the value of the line "<key>: <value>" in the front matter of <file>:
# the lines between a "---" on line 1 and the next "---". Blanks around the
# value do not count. The first line with <key> counts.
#
# RETURNS
#   0   The value is printed, it can be empty
#   1   No <file>, no front matter, or no line with <key> in it
#   2   The front matter has no closing "---"
find_front_matter_value() {
  [ -f "$2" ] || return 1

  front_line=""
  front_value=""
  front_has_key=""
  {
    IFS= read -r front_line || true
    [ "$front_line" = "---" ] || return 1

    # A last line without a newline sets front_line, and read returns 1
    while IFS= read -r front_line || [ -n "$front_line" ]; do
      case "$front_line" in
        "---")
          [ -n "$front_has_key" ] || return 1

          trim_blanks "$front_value"
          return 0
          ;;
        "$1:"*)
          if [ -z "$front_has_key" ]; then
            front_value="${front_line#"$1:"}"
            front_has_key="true"
          fi
          ;;
      esac
      front_line=""
    done
  } <"$2"

  return 2
}

# has_front_matter_key <key> <file>
# Return 0 when the front matter of <file> has a line with <key>. A front
# matter without its closing "---" counts too: validate_zettel says why.
has_front_matter_key() {
  key_status=0
  find_front_matter_value "$1" "$2" >/dev/null || key_status=$?

  [ "$key_status" -ne 1 ]
}

# build_with_front_matter_field <key> <value> <file>
# Print <file> with "<key>: <value>" in its front matter: in place of the first
# line with <key>, or as the last line when none has it. Give a file without
# front matter one, and an empty line after it. A front matter without its
# closing "---" stays without it, and gets no new field.
build_with_front_matter_field() {
  FIELD_KEY="$1" FIELD_LINE="$1: $2" awk '
    BEGIN { key = ENVIRON["FIELD_KEY"] ":"; line = ENVIRON["FIELD_LINE"] }

    NR == 1 && $0 == "---" { is_front = 1; next }
    NR == 1 { print "---"; print line; print "---"; print "" }

    is_front && $0 == "---" {
      is_front = 0
      print "---"
      for (at = 1; at <= count; at++) {
        print lines[at]
      }
      if (!has_key) {
        print line
      }
      print "---"
      next
    }

    is_front {
      if (!has_key && index($0, key) == 1) {
        has_key = 1
        $0 = line
      }
      lines[++count] = $0
      next
    }

    { print }

    END {
      if (NR == 0) {
        print "---"; print line; print "---"
      } else if (is_front) {
        print "---"
        for (at = 1; at <= count; at++) {
          print lines[at]
        }
      }
    }' "$3"
}

# write_front_matter_value <key> <value> <file>
# Set "<key>: <value>" in the front matter of <file>, as
# build_with_front_matter_field prints it.
write_front_matter_value() {
  write_atomic "$3" build_with_front_matter_field "$1" "$2" "$3"
}

# build_with_message <message> <file>
# Print <file> with <message> and an empty line above its first line. When
# <file> starts with front matter, put them below it, behind an empty line.
# Before a front matter without its closing "---", the message comes first.
build_with_message() {
  MESSAGE_TEXT="$1" awk '
    BEGIN { message = ENVIRON["MESSAGE_TEXT"] }

    NR == 1 && $0 == "---" { is_front = 1; front = $0; next }

    is_front {
      front = front "\n" $0
      if ($0 == "---") {
        is_front = 0
        print front; print ""; print message
        is_done = 1
      }
      next
    }

    !is_done { print message; print ""; is_done = 1 }
    { print }

    END {
      if (is_front) {
        print message; print ""; print front
      } else if (!is_done) {
        print message
      }
    }' "$2"
}

# validate_zettel <file>
# Check the format of a zettel: a front matter with "id:" and a valid id, then
# a claim that gives a slug. Print the reason it fails.
#
# RETURNS
#   0   The format is valid, nothing printed
#   1   The problem is printed
validate_zettel() {
  validate_status=0
  validate_id=$(find_front_matter_value id "$1") || validate_status=$?

  case "$validate_status" in
    1)
      printf '%s' 'No "id:" in the front matter'
      return 1
      ;;
    2)
      printf '%s' 'The front matter has no closing "---"'
      return 1
      ;;
  esac

  if ! _is folgezettel "$validate_id"; then
    printf 'The front matter holds "id: %s", not an id' "$validate_id"
    return 1
  fi

  if ! validate_claim=$(find_claim "$1"); then
    printf '%s' 'No claim, "# <claim>" after the front matter'
    return 1
  fi

  if ! print_slug "$validate_claim" >/dev/null; then
    printf '%s' 'The claim holds no letter a-z and no digit'
    return 1
  fi

  return 0
}

# validate_box_entry <id> <taken-ids>
# Check the rules of the box for a zettel with <id>: no other zettel holds it.
# <taken-ids> holds one id per line. Print the reason it fails.
#
# RETURNS
#   0   The zettel can enter the box, nothing printed
#   1   The broken rule is printed
validate_box_entry() {
  case "$NL$2$NL" in
    *"$NL$1$NL"*)
      printf 'The id %s is taken by another zettel' "$1"
      return 1
      ;;
  esac

  return 0
}

# build_zettel_name <file>
# Print the file name of a zettel from its text: "<id>.<slug of claim>.md".
# Return 1 and print nothing when validate_zettel finds a problem.
build_zettel_name() {
  validate_zettel "$1" >/dev/null || return 1

  build_id=$(find_front_matter_value id "$1")
  build_slug=$(print_slug "$(find_claim "$1")")

  printf '%s.%s.md' "$build_id" "$build_slug"
}

# has_text <file>
# Return 0 when <file> holds a line that is not blank and not a bare "#".
has_text() {
  grep -q -v -e '^[[:space:]]*$' -e '^#[[:space:]]*$' -- "$1"
}

# print_tree
# Read rows from stdin, "<id> TAB <label>" or "<id> TAB <label> TAB <mark>",
# in Folgezettel order. Print one line per row: the label, behind an indent
# and "└ " below the top level. The mark stays after the label, behind a tab.
#
#   1.lorem.md
#    └ 1b.ipsum.md
#        └ 1b3.dolor.md
print_tree() {
  awk -F '\t' '{
    # The depth is the count of runs in the id, less one
    rest = $1
    depth = gsub(/[0-9]+/, "", rest) - 1
    rest = $1
    depth += gsub(/[a-z]+/, "", rest)

    line = $2
    if (depth > 0) {
      indent = ""
      for (step = 0; step < 4 * depth - 3; step++) {
        indent = indent " "
      }
      line = indent "└ " $2
    }

    if (NF >= 3 && $3 != "") {
      line = line "\t" $3
    }

    print line
  }'
}

# is_zettel_name <file-name>
# Return 0 when <file-name> is "<id>.<slug>.md".
is_zettel_name() {
  case "$1" in
    *.*.md) ;;
    *) return 1 ;;
  esac

  name_stem="${1%.md}"

  _is folgezettel "${name_stem%%.*}" && _is slug "${name_stem#*.}"
}

# list_zettels
# Print "<id> TAB <file name>" for every zettel in the box, in Folgezettel
# order. Warn and skip a file whose name is not "<id>.<slug>.md", and a second
# file with an id that an earlier file has. Print nothing when there is no box.
list_zettels() {
  [ -d "$BOX_DIR" ] || return 0

  list_seen=""
  for list_file in "$BOX_DIR"/*; do
    [ -f "$list_file" ] || continue

    list_name="${list_file##*/}"
    list_id="${list_name%%.*}"

    if ! is_zettel_name "$list_name"; then
      _warn -v path "$list_file" "The name is not <id>.<slug>.md, skipping"
      continue
    fi

    if ! validate_box_entry "$list_id" "$list_seen" >/dev/null; then
      _warn -v path "$list_file" "Another zettel has this id, skipping"
      continue
    fi
    list_seen="$list_seen$list_id$NL"

    printf '%s\t%s\n' "$list_id" "$list_name"
  done | sort_ids
}

# list_draft_files
# Print the path of every draft, newest first. A day folder and the name of a
# new draft sort in the order of time. A zettel that sync lowered to the drafts
# keeps its name, which does not.
list_draft_files() {
  for listed_draft in "$DRAFT_DIR"/*/*.md; do
    [ -f "$listed_draft" ] || continue
    printf '%s\n' "$listed_draft"
  done | LC_ALL=C sort -r
}

# find_draft_ids
# Print the valid id in the front matter of each draft, one per line. A
# zettel that sync lowered to the drafts keeps its id there, so place does not
# give it to another zettel.
find_draft_ids() {
  list_draft_files | while IFS= read -r draft_ids_file; do
    draft_ids_id=$(find_front_matter_value id "$draft_ids_file") || continue

    if _is folgezettel "$draft_ids_id"; then
      printf '%s\n' "$draft_ids_id"
    fi
  done
}

# find_ids
# Print the id of every zettel, one per line, in Folgezettel order.
find_ids() {
  list_zettels | cut -f 1
}

# find_zettel_file <id>
# Print the path of a zettel. Return 1 when the box has none with this id.
find_zettel_file() {
  for zettel_file in "$BOX_DIR/$1".*.md; do
    if [ -f "$zettel_file" ] && is_zettel_name "${zettel_file##*/}"; then
      printf '%s' "$zettel_file"
      return 0
    fi
  done

  return 1
}

# get_zettel_file <id>
# Print the path of a zettel. Exit 2 when <id> is not an id, or when the box
# has no zettel with it.
get_zettel_file() {
  _is folgezettel "$1" || _fail 2 -v id "$1" "Not an id"
  find_zettel_file "$1" || _fail 2 -v id "$1" "No such zettel"
}

# find_newest_ids <count>
# Read the rows of list_zettels from stdin. Print the ids of the last <count>
# zettels placed, newest first. The front
# matter of a zettel holds the time, "placed: <UTC time>", and the text order
# of those times is their order in time. A zettel without that line counts as
# the oldest.
find_newest_ids() {
  while IFS="$TAB" read -r newest_id newest_name; do
    [ -n "$newest_id" ] || continue

    newest_placed=$(find_front_matter_value placed "$BOX_DIR/$newest_name") \
      || newest_placed=""

    printf '%s\t%s\n' "$newest_placed" "$newest_id"
  done | LC_ALL=C sort -r | head -n "$1" | cut -f 2
}

# print_tree_row <id> [mark]
# Print the row print_tree reads for a zettel: its id, a tab, its file name,
# then a tab and <mark> when given. An id without a zettel gets the id as its
# label.
print_tree_row() {
  row_label="$1"
  if row_file=$(find_zettel_file "$1"); then
    row_label="${row_file##*/}"
  fi

  printf '%s\t%s' "$1" "$row_label"
  if [ -n "${2:-}" ]; then
    printf '\t%s' "$2"
  fi
  printf '\n'
}

# list_rows
# Read the rows of list_zettels from stdin. Print one row per zettel for "fzf --read0", in Folgezettel order:
# "<id> TAB <file path> TAB <indent><file name>", then a NUL. The indent is two
# spaces per step of the lineage. A zettel with a body has a second line in its
# row: the body, the text after the claim, as one line, so fzf searches it.
# list_rows prints it dim, unless NO_COLOR is set and non-empty.
list_rows() {
  rows_names=$(cut -f 2)
  [ -n "$rows_names" ] || return 0

  rows_is_dim="true"
  if [ -n "${NO_COLOR:-}" ]; then
    rows_is_dim=""
  fi

  # A subshell, so the cd stays here. awk reads the box path from its
  # environment, because awk -v rewrites a backslash in it. A zettel that is an
  # empty file gives awk no line, so awk walks its list of files to print a
  # row for that zettel too
  (
    cd -- "$BOX_DIR" || exit 3
    # shellcheck disable=SC2086 # a name is an id, a slug and ".md", safe to split
    ROWS_BOX_DIR="$BOX_DIR" awk -v is_dim="$rows_is_dim" '
      function put_row(name, text,    id, rest, depth, indent, step) {
        id = name
        sub(/\..*$/, "", id)

        rest = id
        depth = gsub(/[0-9]+/, "", rest) - 1
        rest = id
        depth += gsub(/[a-z]+/, "", rest)

        indent = ""
        for (step = 0; step < depth; step++) {
          indent = indent "  "
        }

        if (text != "") {
          if (is_dim != "") {
            text = "\033[2m" text "\033[0m"
          }
          text = "\n" indent "  " text
        }

        # No awk prints a NUL on every system. tr turns this character into one
        printf "%s\t%s/%s\t%s%s%s\036", id, box_dir, name, indent, name, text
      }

      BEGIN { box_dir = ENVIRON["ROWS_BOX_DIR"] }

      FNR == 1 {
        if (at > 0) {
          put_row(ARGV[at], text)
        }
        for (at++; ARGV[at] != FILENAME; at++) {
          put_row(ARGV[at], "")
        }

        text = ""
        is_front_matter = ($0 == "---")
        is_past_claim = 0

        if (is_front_matter) {
          next
        }
      }

      is_front_matter {
        if ($0 == "---") {
          is_front_matter = 0
        }
        next
      }

      # The claim is the first line with text, when it starts with "#"
      !is_past_claim && /^[ \t]*$/ { next }
      !is_past_claim {
        is_past_claim = 1
        if ($0 ~ /^#/) {
          next
        }
      }

      /[^ \t]/ {
        gsub(/\t/, " ")
        text = (text == "" ? $0 : text " " $0)
      }

      END {
        if (at > 0) {
          put_row(ARGV[at], text)
        }
        for (at++; at < ARGC; at++) {
          put_row(ARGV[at], "")
        }
      }' $rows_names
  ) | tr '\036' '\000'
}

# run_hook <hook-file> [arg...]
# Run a hook when it is executable, its output on stderr. Print a line when
# the hook ran, so the user sees it did. Warn when the hook fails. The work
# before it is already done.
run_hook() {
  [ -x "$1" ] || return 0

  if ! "$@" >&2; then
    _warn -v hook "$1" "The hook failed"
    return 0
  fi

  _info -v hook "${1##*/}" "Ran the hook"
}

# make_day_dir
# Create the folder of today in the drafts, when it is not there, and print
# its path.
make_day_dir() {
  day_dir="$DRAFT_DIR/$(date +%y-%j)"
  mkdir -p -- "$day_dir"
  printf '%s' "$day_dir"
}

