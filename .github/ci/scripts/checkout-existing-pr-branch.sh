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
# Reads GH_TOKEN, BASE, and GITHUB_OUTPUT from the environment. RESET_TO_BASE
# is optional: set it to `true` for an updater that can only move a version
# forward, so a reused branch recomputes from the base instead of building on
# the previous run.
#
# Usage:
#
#     .github/ci/scripts/checkout-existing-pr-branch.sh
# ---------------------------------------------------------------------------

# A bare `run:` step invokes this script, so it sets `set -e`.
# `.github/workflows/README.md` holds the rule for each family, under Scripts.
set -e

# Warning: capture the base commit before anything checks another branch out.
if [[ "${RESET_TO_BASE:-}" == 'true' ]]; then
  BASE_SHA=$(git rev-parse HEAD)
fi

EXISTING=$(gh pr list \
  --base "$BASE" \
  --state open \
  --json headRefName \
  --jq '[.[] | select(.headRefName | startswith("deps/update-dependencies-"))] | first | .headRefName // ""')

if [[ -n "$EXISTING" ]]; then
  echo "Found existing PR branch: $EXISTING"
  git fetch origin "$EXISTING"
  git checkout "$EXISTING"

  # Warning: an updater that only moves a version forward can never walk one back, so
  # building on the previous run's tree makes a bad bump permanent. Resetting means every
  # run recomputes from the base. Any commit pushed onto the branch by hand is discarded.
  if [[ "${RESET_TO_BASE:-}" == 'true' ]]; then
    git reset --hard "$BASE_SHA"
  fi
  echo "branch=$EXISTING" >> "$GITHUB_OUTPUT"
  echo "is-new=false" >> "$GITHUB_OUTPUT"
else
  # Warning: the base belongs in the name. The lookup above is already scoped to one base, so
  # two supported majors refreshed on the same day each find nothing of their own and would
  # otherwise pick the same new name — and the second force-push would take the first one's
  # branch. A release now refreshes its own dependencies, so that collision would fail a
  # release rather than a dependency run.
  #
  # The name can also match a branch a merged pull request already used, when a repository does
  # not delete a head branch on merge and a second refresh runs the same day. `--force-with-lease`
  # refuses to push without a remote-tracking ref, so fetch one when the remote still has it.
  BRANCH="deps/update-dependencies-$BASE-$(date +%Y-%m-%d)"

  if git ls-remote --exit-code --heads origin "$BRANCH" >/dev/null 2>&1; then
    echo "Remote still carries $BRANCH from an earlier run. Fetching it so the push has a lease."
    git fetch origin "$BRANCH"
  fi
  echo "No existing PR branch. Will create: $BRANCH"
  echo "branch=$BRANCH" >> "$GITHUB_OUTPUT"
  echo "is-new=true" >> "$GITHUB_OUTPUT"
fi
