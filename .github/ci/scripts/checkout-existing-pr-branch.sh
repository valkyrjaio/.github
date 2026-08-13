#!/usr/bin/env bash
#
# This file is part of the Valkyrja GitHub package.
#
# Copyright (c) 2016-present Melech Mizrachi
#
# Released under the MIT License. See LICENSE.md for details.
#
# ---------------------------------------------------------------------------
# Dependency update branch selection.
#
# The dependency update reuses one branch rather than opening a pull request
# per run, so a repository carries one open dependency pull request at a time.
# This script finds that branch when it exists and checks it out, and names a
# new one when it does not.
#
# The script is language agnostic. Every language's dependency update reuses
# the same branch naming, so each one calls this rather than carrying a copy.
#
# Reads GH_TOKEN, BASE, and GITHUB_OUTPUT from the environment.
#
# Usage:
#
#     .github/ci/scripts/checkout-existing-pr-branch.sh
# ---------------------------------------------------------------------------

# A bare `run:` step invokes this script, so it sets `set -e`.
# `.github/workflows/README.md` holds the rule for each family, under Scripts.
set -e

EXISTING=$(gh pr list \
  --base "$BASE" \
  --state open \
  --json headRefName \
  --jq '[.[] | select(.headRefName | startswith("deps/update-dependencies-"))] | first | .headRefName // ""')

if [[ -n "$EXISTING" ]]; then
  echo "Found existing PR branch: $EXISTING"
  git fetch origin "$EXISTING"
  git checkout "$EXISTING"
  echo "branch=$EXISTING" >> "$GITHUB_OUTPUT"
  echo "is-new=false" >> "$GITHUB_OUTPUT"
else
  BRANCH="deps/update-dependencies-$(date +%Y-%m-%d)"
  echo "No existing PR branch. Will create: $BRANCH"
  echo "branch=$BRANCH" >> "$GITHUB_OUTPUT"
  echo "is-new=true" >> "$GITHUB_OUTPUT"
fi
