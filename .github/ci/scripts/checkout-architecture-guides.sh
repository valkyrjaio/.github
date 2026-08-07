#!/usr/bin/env bash
#
# This file is part of the Valkyrja GitHub package.
#
# Copyright (c) 2016-present Melech Mizrachi
#
# Released under the MIT License. See LICENSE.md for details.
#
# ---------------------------------------------------------------------------
# Architecture guide checkout.
#
# Clones the architecture repository that a Claude review reads the guides
# from. The review judges a pull request against the guides that govern the
# branch the pull request lands on, so the ref follows the base branch.
#
# A documentation fix lands on the lowest supported version branch and moves
# up from there, so a version branch carries the rules for its own line.
#
# Two refs cannot be followed, and each one falls back. A stacked pull request
# bases on a feature branch, which the architecture repository does not hold.
# A new version branch exists in this repository before the architecture
# repository creates its own. Both fall back to the default branch of the
# repository under review, which is that repository's current version branch.
# The architecture repository does not always hold that branch either, and the
# last fallback is `master`.
#
# Reads ARCHITECTURE_REF, BASE_REF, DEFAULT_REF, and RUNNER_TEMP from the
# environment. An empty ARCHITECTURE_REF follows the base branch.
#
# Usage:
#
#     .github/ci/scripts/checkout-architecture-guides.sh
# ---------------------------------------------------------------------------

# Warning: `-u` and `pipefail` are deliberately absent. This script carries a
# block from a `run:` step that names no shell, and GitHub runs that as
# `bash -e {0}`.
set -e

ARCHITECTURE_REPOSITORY='https://github.com/valkyrjaio/architecture.git'

# Reports whether the architecture repository holds the branch. `--exit-code`
# reports 2 for a branch the repository does not hold, and every other non-zero
# status is a query that failed. A failed query reported as an absent branch
# sends the review to `master` in silence, so the script stops instead. The
# pattern is anchored, because an unanchored one also matches a nested branch
# that `git clone --branch` cannot check out.
has_branch() {
  local candidate="$1"
  local status=0

  [[ -n "$candidate" ]] || return 1

  git ls-remote --exit-code --heads "$ARCHITECTURE_REPOSITORY" "refs/heads/$candidate" > /dev/null || status=$?

  case "$status" in
    0) return 0 ;;
    2) return 1 ;;
    *)
      echo "The query for the $candidate branch failed with status $status." >&2
      exit "$status"
      ;;
  esac
}

REF="$ARCHITECTURE_REF"

if [[ -n "$REF" ]]; then
  echo "The caller asked for $REF."
elif has_branch "$BASE_REF"; then
  REF="$BASE_REF"
  echo "The pull request bases on $REF, and the architecture repository holds that branch."
elif has_branch "$DEFAULT_REF"; then
  REF="$DEFAULT_REF"
  echo "The architecture repository holds no $BASE_REF branch, so the guides come from $REF."
elif [[ "$BASE_REF" == "$DEFAULT_REF" ]]; then
  REF='master'
  echo "The architecture repository holds no $BASE_REF branch, so the guides come from $REF."
else
  REF='master'
  echo "The architecture repository holds neither $BASE_REF nor $DEFAULT_REF, so the guides come from $REF."
fi

git clone --depth 1 --branch "$REF" "$ARCHITECTURE_REPOSITORY" "$RUNNER_TEMP/architecture"

echo "The review reads the guides from $REF."
