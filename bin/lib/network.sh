#!/bin/sh

# NAME
#   network.sh - Download a file
#
# SYNOPSIS
#   . "$_SCRIPT_DIR/../lib/network.sh"
#
# DESCRIPTION
#   Needs log.sh. A script sources it before this file.
#
# SEE ALSO
#   curl(1)

# _download_file <url> <output-file>
#
# Download <url> into <output-file>.
#
# EXIT
#   3   The download fails
_download_file() {
  curl --silent --show-error --fail --location --output "$2" "$1" \
    || _fail 3 -v url "$1" "Download failed"
}
