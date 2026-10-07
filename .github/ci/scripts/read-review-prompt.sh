#!/usr/bin/env bash
#
# This file is part of the Valkyrja GitHub package.
#
# Copyright (c) 2016-present Melech Mizrachi
#
# Released under the MIT License. See LICENSE.md for details.
#
# ---------------------------------------------------------------------------
# Claude review prompt reader.
#
# The review instructions live in .github/ci/claude-review/prompt.md rather
# than in the workflow, so a review run before the push can read the same
# instructions. A caller that passes its own prompt replaces them. The script
# writes whichever applies to GITHUB_OUTPUT as `prompt`.
#
# Reads PROMPT, PROMPT_FILE, and GITHUB_OUTPUT from the environment.
#
# Usage:
#
#     GITHUB_OUTPUT=/dev/stdout PROMPT_FILE=.github/ci/claude-review/prompt.md \
#         .github/ci/scripts/read-review-prompt.sh
# ---------------------------------------------------------------------------

# A bare `run:` step invokes this script, so it sets `set -e`.
# `.github/workflows/README.md` holds the rule for each family, under Scripts.
set -e

: "${PROMPT_FILE:?PROMPT_FILE must name the review prompt file}"

# The prompt holds newlines, so it needs a delimiter that its text cannot contain.
DELIMITER="PROMPT_$(openssl rand -hex 16)"

{
  echo "prompt<<$DELIMITER"

  if [[ -n "$PROMPT" ]]; then
    printf '%s\n' "$PROMPT"
  else
    cat "$PROMPT_FILE"
  fi

  echo "$DELIMITER"
} >> "$GITHUB_OUTPUT"
