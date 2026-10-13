#!/bin/sh

# The settings and primitives that two or more zettel commands use. Each
# command file sets SCRIPT_DIR, then sources this file.

. "$SCRIPT_DIR/../../lib.sh"

# _log reads these
export LOG_NAMESPACE="zettel"
export LOG_LEVEL="${LOG_LEVEL:-info}"

# The public command. A command file runs another command only through it
# shellcheck disable=SC2034 # the command files read it
PUBLIC_FILE=$(realpath "$SCRIPT_DIR/../zettel")

NOTES_DIR="${PU_ZETTEL_DIR:-$HOME/NeoNotes}"
DRAFT_DIR="$NOTES_DIR/draft"
BOX_DIR="$NOTES_DIR/box"
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/zettel"
# shellcheck disable=SC2034 # the command files read it
PLACE_HOOK_FILE="$CONFIG_DIR/on-place"
# shellcheck disable=SC2034 # the command files read it
UPDATE_HOOK_FILE="$CONFIG_DIR/on-update"
TAB=$(printf '\t')

# ╭───
# │ Primitives
# ╰───

# An id is a Folgezettel id: runs of digits and runs of lowercase letters that
# alternate, eg. 1b3. A run of digits comes first, and none starts with 0. Each
# run names one step of the lineage: 1b3 stands behind 1b, and 1b behind 1.
#
# awk compares two values that look like numbers as numbers, and the id 1e2
# looks like 100. "" after a value makes it a string.

# is_id <value>
# Return 0 when <value> is an id.
is_id() {
  case "$1" in
    "" | *[!0-9a-z]* | [!1-9]* | *[a-z]0*) return 1 ;;
  esac

  return 0
}

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
# because an id never changes and a removed id is not used again.
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

# find_claim <file>
# Print the claim of a note: line 1 is "#", then the claim. Blanks around the
# claim do not count, so "#claim" and "# claim" both give "claim". Return 1
# when line 1 holds no claim: a bare "#", a "##" heading, any other text, or
# no <file>.
find_claim() {
  [ -f "$1" ] || return 1

  claim_text=""
  IFS= read -r claim_text <"$1" || true

  case "$claim_text" in
    "#"*) claim_text="${claim_text#?}" ;;
    *) return 1 ;;
  esac

  # Cut the blanks at each end: the longest run of them there
  claim_text="${claim_text#"${claim_text%%[! "$TAB"]*}"}"
  claim_text="${claim_text%"${claim_text##*[! "$TAB"]}"}"

  case "$claim_text" in
    "" | "#"*) return 1 ;;
  esac

  printf '%s' "$claim_text"
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

  is_id "${name_stem%%.*}" && _is slug "${name_stem#*.}"
}

# list_zettels
# Print "<id> TAB <file name>" for every zettel in the box, in Folgezettel
# order. Warn and skip a file whose name is not "<id>.<slug>.md", and a second
# file with an id that an earlier file has. Print nothing when there is no box.
list_zettels() {
  [ -d "$BOX_DIR" ] || return 0

  list_seen=" "
  for list_file in "$BOX_DIR"/*; do
    [ -f "$list_file" ] || continue

    list_name="${list_file##*/}"
    list_id="${list_name%%.*}"

    if ! is_zettel_name "$list_name"; then
      _warn -v path "$list_file" "The name is not <id>.<slug>.md, skipping"
      continue
    fi

    case "$list_seen" in
      *" $list_id "*)
        _warn -v path "$list_file" "Another zettel has this id, skipping"
        continue
        ;;
    esac
    list_seen="$list_seen$list_id "

    printf '%s\t%s\n' "$list_id" "$list_name"
  done | sort_ids
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

# find_newest_ids <count>
# Print the ids of the last <count> zettels placed, newest first. Line 2 of a
# zettel holds the time, "placed: <UTC time>", and the text order of those
# times is their order in time. A zettel without that line counts as the
# oldest.
find_newest_ids() {
  # shellcheck disable=SC2034 # read needs a name for line 1
  list_zettels | while IFS="$TAB" read -r newest_id newest_name; do
    newest_placed=""
    { IFS= read -r newest_first && IFS= read -r newest_placed; } \
      <"$BOX_DIR/$newest_name" || true

    case "$newest_placed" in
      "placed: "*) newest_placed="${newest_placed#placed: }" ;;
      *) newest_placed="" ;;
    esac

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
# Print one row per zettel for "fzf --read0", in Folgezettel order:
# "<id> TAB <file path> TAB <indent><file name>", then a NUL. The indent is two
# spaces per step of the lineage. A zettel with a text has a second line in its
# row: the text that follows the claim, as one line, so fzf searches it. It
# prints dim, unless NO_COLOR is set and non-empty.
list_rows() {
  rows_names=$(list_zettels | cut -f 2)
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
# Run a hook when it is executable, its output on stderr. A hook that fails is
# a warning, the work it follows is already done.
run_hook() {
  [ -x "$1" ] || return 0

  "$@" >&2 || _warn -v hook "$1" "The hook failed"

  return 0
}

# remove_empty_day_dir <dir>
# Remove <dir> when it is inside the draft folder and empty.
remove_empty_day_dir() {
  if [ ! -d "$1" ] || [ ! -d "$DRAFT_DIR" ]; then
    return 0
  fi

  case "$(realpath "$1")" in
    "$(realpath "$DRAFT_DIR")"/*) rmdir -- "$1" 2>/dev/null || true ;;
  esac

  return 0
}

# is_public_file_safe
# Return 0 when PUBLIC_FILE, the path of zettel, is safe to write unquoted. The
# fzf commands of the picker and the browser hold it, and a shell would split
# or expand most other characters.
is_public_file_safe() {
  case "$PUBLIC_FILE" in
    *[!A-Za-z0-9_@+=:,./-]*) return 1 ;;
  esac

  return 0
}

# guard_public_file
# Exit 3 unless is_public_file_safe.
guard_public_file() {
  is_public_file_safe \
    || _fail 3 -v path "$PUBLIC_FILE" \
      "The script path has a character outside A-Za-z0-9_@+=:,./-"

  return 0
}
