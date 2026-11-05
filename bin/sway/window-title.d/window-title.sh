#!/bin/sh

# The primitives of window-title. window-title sources this file, and so does
# each test file. This file sources nothing and sets no shell options.

# _get_contrast_color <color> <candidate> [candidate...]
#
# Print the candidate with the highest WCAG contrast ratio against <color>.
# Each color is "#rrggbb", in upper or lower case. On a tie, print the first.
#
# EXIT
#   3   Fewer than two colors given
_get_contrast_color() {
  [ "$#" -ge 2 ] || _fail 3 "_get_contrast_color needs <color> <candidate>"

  printf '%s\n' "$@" | awk '
    function channel(hex, at,   value) {
      value = (index(DIGITS, substr(hex, at, 1)) - 1) * 16 \
        + index(DIGITS, substr(hex, at + 1, 1)) - 1
      value /= 255
      return value <= 0.03928 ? value / 12.92 : ((value + 0.055) / 1.055) ^ 2.4
    }
    function luminance(hex) {
      hex = tolower(hex)
      return 0.2126 * channel(hex, 2) + 0.7152 * channel(hex, 4) \
        + 0.0722 * channel(hex, 6)
    }
    BEGIN { DIGITS = "0123456789abcdef" }
    NR == 1 { base = luminance($0); next }
    {
      other = luminance($0)
      ratio = other > base \
        ? (other + 0.05) / (base + 0.05) \
        : (base + 0.05) / (other + 0.05)
      if (ratio > best) { best = ratio; picked = $0 }
    }
    END { print picked }'
}
