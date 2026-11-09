#!/bin/sh

# NAME
#   text.sh - Replace a block between markers, end text with a newline
#
# SYNOPSIS
#   . "$_SCRIPT_DIR/../lib/text.sh"
#
# DESCRIPTION
#   Needs log.sh. A script sources it before this file.

# _end_with_newline <text>
#
# Print <text> with a newline at its end, the one $(...) strips. Print nothing
# when <text> is empty, where a plain printf would print one empty line.
_end_with_newline() {
  if [ -n "$1" ]; then
    printf '%s\n' "$1"
  fi
}

# A block is the lines between two marker lines, <begin> and <end>, in a text
# that otherwise belongs to someone else: a crontab, a shell profile. A marker
# is a whole line, compared as written. A text must hold no block, or exactly
# one: one <begin>, and one <end> below it.
#
# awk reads the markers and the block lines from its environment, because
# awk -v rewrites a backslash in them. awk compares two values that look like
# numbers as numbers, so a marker "10" would match a line "10.0". "" after a
# value makes it a string.

# _has_valid_markers <begin> <end> <text>
#
# Tell if the markers in <text> make no block, or exactly one.
#
# RETURNS
#   0   <text> has neither marker, or each marker once with <begin> above <end>
#   1   A marker is there more than once or alone, or <begin> is not above
#       <end>
#
# EXIT
#   3   A marker is empty or holds a newline
_has_valid_markers() {
  # An empty marker matches every empty line, one with a newline matches none
  case "$1$2" in
    *"
"*) _fail 3 "A marker is one line" ;;
  esac

  if [ -z "$1" ] || [ -z "$2" ]; then
    _fail 3 "A marker cannot be empty"
  fi

  # The line number of each marker. -F -x is the whole line, as written
  lib_hvm_begin=$(printf '%s\n' "$3" | grep -n -F -x -e "$1" | cut -d ':' -f 1)
  lib_hvm_end=$(printf '%s\n' "$3" | grep -n -F -x -e "$2" | cut -d ':' -f 1)

  # Each is one number, when its marker is there once
  case "$lib_hvm_begin:$lib_hvm_end" in
    :) return 0 ;;                   # neither marker
    *[!0-9:]* | :* | *:) return 1 ;; # one is there twice, or one is missing
  esac

  [ "$lib_hvm_begin" -lt "$lib_hvm_end" ] || return 1

  return 0
}

# _find_block <begin> <end>
#
# Read a text from stdin, print the lines of its block without the markers.
# Print nothing when the text has no block.
#
# RETURNS
#   1   A marker is there more than once or alone, or <begin> is not above
#       <end>. Prints nothing
#
# EXIT
#   3   A marker is empty or holds a newline
_find_block() {
  lib_fb_text=$(cat)
  _has_valid_markers "$1" "$2" "$lib_fb_text" || return 1

  printf '%s\n' "$lib_fb_text" \
    | BLOCK_BEGIN_MARKER="$1" BLOCK_END_MARKER="$2" awk '
      BEGIN {
        begin = ENVIRON["BLOCK_BEGIN_MARKER"] ""
        end = ENVIRON["BLOCK_END_MARKER"] ""
      }

      $0 == begin { is_inside = 1; next }
      $0 == end { is_inside = 0 }
      is_inside { print }'
}

# _replace_block <begin> <end> <lines>
#
# Read a text from stdin, print it with the lines of its block replaced by
# <lines>. Add the block and its markers at the end when the text has none.
# Drop both when <lines> is empty.
#
# Take the result into a variable and read the status before writing it
# anywhere. In a pipe, the next command reads an empty text when
# _replace_block returns 1 or 2.
#
# RETURNS
#   1   A marker is there more than once or alone, or <begin> is not above
#       <end>. Prints nothing
#   2   One of <lines> is a marker. Prints nothing
#
# EXIT
#   3   A marker is empty or holds a newline
_replace_block() {
  lib_rb_text=$(cat)
  _has_valid_markers "$1" "$2" "$lib_rb_text" || return 1

  # A marker inside the block would make two blocks of it
  if printf '%s\n' "$3" | grep -q -F -x -e "$1" -e "$2"; then
    return 2
  fi

  _end_with_newline "$lib_rb_text" | BLOCK_BEGIN_MARKER="$1" BLOCK_END_MARKER="$2" BLOCK_LINES="$3" awk '
    function put_block() {
      if (lines != "") {
        print begin
        print lines
        print end
      }
      is_put = 1
    }

    BEGIN {
      begin = ENVIRON["BLOCK_BEGIN_MARKER"] ""
      end = ENVIRON["BLOCK_END_MARKER"] ""
      lines = ENVIRON["BLOCK_LINES"] ""
    }

    $0 == begin { is_inside = 1; next }
    $0 == end { is_inside = 0; put_block(); next }
    !is_inside { print }

    END { if (!is_put) put_block() }'
}

# _diff_lines <old-text> <new-text>
#
# Print what changed between two sets of lines: "- <line>" for a line only in
# <old-text>, then "+ <line>" for a line only in <new-text>. The order of the
# lines, repeats and empty lines do not count.
#
# Print the "-" lines red and the "+" lines green when stdout can show color,
# see _has_color.
_diff_lines() {
  lib_dl_color=""
  if _has_color 1; then
    lib_dl_color="true"
  fi

  DIFF_OLD_TEXT="$1" DIFF_NEW_TEXT="$2" awk -v color="$lib_dl_color" '
    BEGIN {
      old_count = split(ENVIRON["DIFF_OLD_TEXT"], old_lines, "\n")
      new_count = split(ENVIRON["DIFF_NEW_TEXT"], new_lines, "\n")

      minus = color ? "\033[31m- %s\033[0m\n" : "- %s\n"
      plus = color ? "\033[32m+ %s\033[0m\n" : "+ %s\n"

      for (i = 1; i <= old_count; i++) is_old[old_lines[i]] = 1
      for (i = 1; i <= new_count; i++) is_new[new_lines[i]] = 1

      for (i = 1; i <= old_count; i++) {
        line = old_lines[i]
        if (line != "" && !(line in is_new) && !(line in is_printed)) {
          printf minus, line
          is_printed[line] = 1
        }
      }

      for (i = 1; i <= new_count; i++) {
        line = new_lines[i]
        if (line != "" && !(line in is_old) && !(line in is_printed)) {
          printf plus, line
          is_printed[line] = 1
        }
      }
    }'
}
