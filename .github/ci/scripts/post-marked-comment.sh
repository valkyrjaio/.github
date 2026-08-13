#!/usr/bin/env bash
#
# This file is part of the Valkyrja GitHub package.
#
# Copyright (c) 2016-present Melech Mizrachi
#
# Released under the MIT License. See LICENSE.md for details.
#
# ---------------------------------------------------------------------------
# Marked pull request comment.
#
# Keeps one comment per marker on a pull request. The script always removes the
# comment that carries the marker, and it then posts a new one only when it is
# given a body. An empty body therefore means "clear it", which is what a check
# does when it starts passing again.
#
# Reads GH_TOKEN, GH_REPO, PR_NUMBER, MARKER, and BODY from the environment.
#
# Usage:
#
#     .github/ci/scripts/post-marked-comment.sh
# ---------------------------------------------------------------------------

# Warning: an action step names `shell: bash`, which is `-eo pipefail`, and a
# `run:` step that names no shell gives `bash -e` alone. This script carries a
# block from an action step. Read the shell before you copy a `set` line
# between the two.
#
# `-u` is absent, because the block ran without it.
set -eo pipefail

if [[ -z "$PR_NUMBER" ]]; then
  echo 'No pull request number, so there is nothing to comment on.'
  exit 0
fi

TAG="<!-- workflow-id: $MARKER -->"

# Remove first, then post. A run that now passes removes its old report and stops, and a run that
# still fails replaces the report rather than adding a second one.
#
# Warning: remove EVERY marked comment, not the first one. Two runs racing on a double push each
# leave a marked comment, and deleting one of them leaves the other on the pull request forever.
#
# Warning: `--paginate` is required. The API returns 30 comments per page, so a marked comment on a
# busy pull request sits past the first page and is never found without it.
COMMENT_IDS=$(gh api --paginate "repos/$GH_REPO/issues/$PR_NUMBER/comments" \
  --jq ".[] | select(.body | contains(\"$TAG\")) | .id")

# Warning: never let a failed delete end the script. The same race puts one comment id in both
# runs' lists, so whichever run deletes second gets HTTP 404 and `gh` exits 1. `set -e` would end
# the script on that status — a check that passed would go red, or a failing check would never
# reach the comment it must post. Comment housekeeping must never decide the job result, so report
# and continue.
while IFS= read -r COMMENT_ID; do
  [[ -z "$COMMENT_ID" ]] && continue

  gh api --method DELETE "repos/$GH_REPO/issues/comments/$COMMENT_ID" \
    && echo "Removed a previous $MARKER comment." \
    || echo "Comment $COMMENT_ID is already gone. A concurrent run deleted it."
done <<< "$COMMENT_IDS"

if [[ -z "$BODY" ]]; then
  echo "No body given, so no $MARKER comment was posted."
  exit 0
fi

printf '%s\n\n%s\n' "$BODY" "$TAG" > comment.md
gh pr comment "$PR_NUMBER" --body-file comment.md
echo "Posted the $MARKER comment."
