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
# than in the workflow, so a review run locally can read the same
# instructions. A caller that passes its own prompt replaces them. The script
# writes whichever applies to GITHUB_OUTPUT as `prompt`.
#
# Reads PROMPT_FILE and GITHUB_OUTPUT from the environment. PROMPT is optional:
# a caller that passes its own review instructions sets it, and an empty or
# unset value reads PROMPT_FILE instead.
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

[[ -f "$PROMPT_FILE" ]] || {
  printf 'No review prompt at %s.\n' "$PROMPT_FILE" >&2
  exit 1
}

if [[ -n "${PROMPT:-}" ]]; then
  REVIEW_PROMPT="$PROMPT"
else
  REVIEW_PROMPT="$(cat "$PROMPT_FILE")"
fi

# The prompt holds newlines, so it needs a delimiter that its text cannot contain. The whole
# block is written at once, after the prompt is read, so the delimiter always closes it on a
# line of its own, whether or not the prompt ends in a newline.
DELIMITER="PROMPT_$(openssl rand -hex 16)"

printf 'prompt<<%s\n%s\n%s\n' "$DELIMITER" "$REVIEW_PROMPT" "$DELIMITER" >> "$GITHUB_OUTPUT"
