#!/bin/sh

# The primitives of open-os-menu. The command sources this file, and so does
# each test file. This file sources nothing and sets no shell options.

# escape_markup <text>
#
# Print <text> with "&", "<" and ">" escaped for Pango markup.
escape_markup() {
  printf '%s' "$1" \
    | sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g'
}

# print_row <icon> <name> <command> <what> <words> <reason>
#
# Print one rofi row. <command> is the command as shown, without its group,
# eg. "recheck browse". An empty <reason> means the item can open. Else the
# row says why it cannot and rofi does not let a person pick it.
#
# A row has two lines: the icon, the name and the command, then what the item
# does. The words that find the item go in the row option "meta", which rofi
# matches and does not show. rofi reads "meta" as plain text, so <words> is not
# escaped.
#
# The icon is one Unicode character in the text of the row, so it takes the
# color of the theme. It is not the rofi "icon" row option: rofi 1.7.5 draws a
# text icon black, which cannot be read on a dark row. An invisible copy of the
# icon starts the second line, so the name and what the item does start in the
# same column in any font.
#
# The dim text uses alpha, never a fixed color. The theme of the user inverts
# the colors of the selected row, and a fixed color becomes unreadable there.
# The reason is at full strength, with a bold "Not ready:", so it stands out
# from the dim lines of the items that can open.
#
# A shell variable cannot hold a NUL, so the caller pipes the rows straight
# into rofi.
print_row() {
  print_icon=$(escape_markup "$1")
  print_name=$(escape_markup "$2")
  print_command=$(escape_markup "$3")
  printf '%s  <b>%s</b>  <span alpha="65%%" size="small">%s</span>&#10;' \
    "$print_icon" "$print_name" "$print_command"
  printf '<span alpha="1">%s  </span>' "$print_icon"

  if [ -n "$6" ]; then
    print_reason=$(escape_markup "$6")
    printf '<span size="small"><b>Not ready:</b> %s</span>' "$print_reason"
  else
    print_what=$(escape_markup "$4")
    printf '<span alpha="65%%" size="small">%s</span>' "$print_what"
  fi

  printf '\0meta\037%s' "$5"
  if [ -n "$6" ]; then
    printf '\037nonselectable\037true'
  fi
  printf '\n'
}

# find_reason <command> <opens> <health>
#
# Print why <command> cannot open. Print nothing when it can. <command> and
# <health> are each a path under bin, then arguments. <opens> is "window" or
# "terminal". <health> is empty when the item has none.
#
# The menu checks two reasons, in this order: the file of <command> is not an
# executable file, and <opens> is "terminal" while PU_TERMINAL is unset or
# empty. Every other reason comes from <health>. When it exits non-zero, its
# first line of stdout is the reason.
#
# It reads the filesystem and runs <health>. It needs SCRIPT_DIR, the folder
# of the command file that sources this file, as checks.sh of recheck needs it
# for its settings.
find_reason() {
  find_path=${1%% *}
  if [ ! -f "$SCRIPT_DIR/../$find_path" ] \
    || [ ! -x "$SCRIPT_DIR/../$find_path" ]; then
    printf '%s not found, install the %s group' \
      "${find_path##*/}" "${find_path%%/*}"
    return 0
  fi

  if [ "$2" = "terminal" ] && [ -z "${PU_TERMINAL:-}" ]; then
    printf 'set PU_TERMINAL, see open-os-menu --help'
    return 0
  fi

  [ -n "$3" ] || return 0

  find_health_path=${3%% *}
  find_health_args=${3#"$find_health_path"}
  find_status=0
  # Split the arguments on purpose
  # shellcheck disable=SC2086
  find_output=$("$SCRIPT_DIR/../$find_health_path" $find_health_args) \
    || find_status=$?
  [ "$find_status" -ne 0 ] || return 0

  if [ -n "$find_output" ]; then
    printf '%s' "$find_output" | sed -n 1p
  else
    printf 'cannot open, run %s' "${find_health_path##*/}$find_health_args"
  fi
}
