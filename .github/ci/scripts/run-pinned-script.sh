#!/usr/bin/env bash
#
# This file is part of the Valkyrja GitHub package.
#
# Copyright (c) 2016-present Melech Mizrachi
#
# Released under the MIT License. See LICENSE.md for details.
#
# ---------------------------------------------------------------------------
# Pinned script runner.
#
# Runs one script from this repository's `.github/ci/scripts` directory, and
# reports what the script wrote. The step that proves the checkout is the
# pinned commit runs before this script, so the tree is already proven here.
#
# Reads SCRIPT, ACTION_PATH, and GITHUB_OUTPUT from the environment. It writes
# `outcome`, `report`, and `report-markdown` to GITHUB_OUTPUT, and it ends with
# the status of the script it ran.
#
# Usage:
#
#     .github/ci/scripts/run-pinned-script.sh
# ---------------------------------------------------------------------------

# Warning: an action step names `shell: bash`, which is `-eo pipefail`, and a
# `run:` step that names no shell gives `bash -e` alone. This script carries a
# block from an action step. Read the shell before you copy a `set` line
# between the two.
#
# `-u` is absent, because the block ran without it.
set -eo pipefail

# A name only. A separator would let a caller run a file outside the scripts directory.
case "$SCRIPT" in
  */*|'.'|'..'|'') echo "Not a script name: $SCRIPT" >&2; exit 1 ;;
  *) ;;
esac

SCRIPT_PATH="$ACTION_PATH/../../ci/scripts/$SCRIPT"

if [[ ! -x "$SCRIPT_PATH" ]]; then
  echo "No executable script at $SCRIPT_PATH." >&2
  # shellcheck disable=SC2016 # The backticks mark a path for a reader, and nothing expands here.
  echo 'A script lives in `.github/ci/scripts/`, and it carries the executable bit.' >&2
  exit 1
fi

set +e
OUTPUT=$("$SCRIPT_PATH" 2>&1)
STATUS=$?
set -e

printf '%s\n' "$OUTPUT"

# The outputs are written before the script fails, so a later step can read the report of a run
# that did not pass. That is why a caller marks the step `continue-on-error`.
if [[ "$STATUS" -eq 0 ]]; then
  printf 'outcome=success\n' >> "$GITHUB_OUTPUT"
else
  printf 'outcome=failure\n' >> "$GITHUB_OUTPUT"
fi

{
  echo 'report<<RUN_SCRIPT_EOF'
  printf '%s\n' "$OUTPUT"
  echo 'RUN_SCRIPT_EOF'

  echo 'report-markdown<<RUN_SCRIPT_EOF'
  # shellcheck disable=SC2016 # The backticks open and close a markdown fence, and nothing expands.
  printf '```\n%s\n```\n' "$OUTPUT"
  echo 'RUN_SCRIPT_EOF'
} >> "$GITHUB_OUTPUT"

exit "$STATUS"
