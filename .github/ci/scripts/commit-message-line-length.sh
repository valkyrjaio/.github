#!/usr/bin/env bash
#
# This file is part of the Valkyrja GitHub package.
#
# Copyright (c) 2016-present Melech Mizrachi
#
# Released under the MIT License. See LICENSE.md for details.
#
# ---------------------------------------------------------------------------
# Commit message line length check.
#
# No line of a commit message on the pull request may exceed 120 characters.
#
# Reads GH_TOKEN, GH_REPO, and PR_NUMBER from the environment.
#
# Usage:
#
#     GH_REPO=owner/repo PR_NUMBER=1 .github/ci/scripts/commit-message-line-length.sh
# ---------------------------------------------------------------------------

set -euo pipefail

: "${GH_REPO:?GH_REPO must name the repository}"
: "${PR_NUMBER:?PR_NUMBER must name the pull request}"

readonly LIMIT=120

COMMITS="$(gh api "repos/$GH_REPO/pulls/$PR_NUMBER/commits" --jq '.[].commit.message')"

FAILED=0

while IFS= read -r LINE; do
    if [[ "${#LINE}" -gt "$LIMIT" ]]; then
        printf 'Line exceeds %s characters: %s\n' "$LIMIT" "$LINE"
        FAILED=1
    fi
done <<< "$COMMITS"

# Warning: report every long line, and do not stop at the first. The check that ran before this one
# stopped at the first, so a contributor fixed one line, pushed, and learned of the next. Naming
# them all costs one run rather than several.
if [[ "$FAILED" -ne 0 ]]; then
    exit 1
fi

printf 'No commit message line exceeds %s characters.\n' "$LIMIT"
