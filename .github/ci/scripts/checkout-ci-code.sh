#!/usr/bin/env bash
#
# This file is part of the Valkyrja GitHub package.
#
# Copyright (c) 2016-present Melech Mizrachi
#
# Released under the MIT License. See LICENSE.md for details.
#
# ---------------------------------------------------------------------------
# CI code checkout from the target branch.
#
# A pull request runs the tool with the CI config the target branch holds, so a
# correction to that config reaches every open pull request without a rebase.
#
# The branch's own copy wins where the branch changed it. The `ci` path filter
# answers that question from the file list of this pull request alone, which a
# stacked pull request does not hold: the pull request below it carries the
# change, so the filter reads false and the restore would replace a config the
# branch has already corrected. This script asks git instead, which sees every
# commit the branch carries.
#
# The check needs the commit where the branch left the target, so the job that
# calls this script checks the repository out with `fetch-depth: 0`.
#
# Reads REF and CI_PATHS from the environment. CI_PATHS holds one pathspec for
# each directory the tool reads, separated by spaces.
#
# Usage:
#
#     REF=26.x CI_PATHS='.github/ci/phpstan' \
#         .github/ci/scripts/checkout-ci-code.sh
# ---------------------------------------------------------------------------

# A bare `run:` step invokes this script, so it sets `set -e` alone.
# `.github/workflows/README.md` holds the rule for each family, under Scripts.
set -e

: "${REF:?REF must name the target branch}"
: "${CI_PATHS:?CI_PATHS must name at least one pathspec}"

read -r -a ci_paths <<< "$CI_PATHS"

git fetch origin "$REF"

base=$(git merge-base HEAD "origin/$REF")

if git diff --quiet "$base" HEAD -- "${ci_paths[@]}"; then
  echo "Using CI code from $REF"
  git checkout "origin/$REF" -- "${ci_paths[@]}"
else
  echo "Keeping the CI code the branch carries, which changed it since $REF"
fi
