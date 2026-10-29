#!/bin/sh

# NAME
#   scene.sh - The default scene, for a use case with no scene.sh of its own
#
# DESCRIPTION
#   capture-terminal runs a scene twice, in the folder of the scene.
#
# ENVIRONMENT
#   CAPTURE_TERMINAL_DRY_RUN     1 in the dry run, which counts the rows
#   CAPTURE_TERMINAL_CODE_FILE   Path to the code.ts of the use case, set by
#                                refresh
#
# EXAMPLE
#   For a use case that needs more steps, add docs/media/<use-case>/scene.sh:
#
#     #!/bin/sh
#     . ../../.capture-terminal/lib.sh
#
#     _say "Parse the config"
#     _run tsx code.ts

. ./lib.sh

tsx "$CAPTURE_TERMINAL_CODE_FILE"
