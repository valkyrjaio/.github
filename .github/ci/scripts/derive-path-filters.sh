#!/usr/bin/env bash
#
# This file is part of the Valkyrja GitHub package.
#
# Copyright (c) 2016-present Melech Mizrachi
#
# Released under the MIT License. See LICENSE.md for details.
#
# ---------------------------------------------------------------------------
# Path filter derivation.
#
# Writes the `dorny/paths-filter` spec that gates the expensive steps of a job.
# Every workflow with a path filter needs the same spec. This script derives it
# once, so one correction reaches all of them.
#
# Both keys share the CI config that decides the tool's behavior, and `files`
# adds the repository's own sources on top. `ci` controls whether the
# base-branch CI directory is restored, and `files` whether the expensive steps
# run at all.
#
# Reads CI_DIR, SOURCE_PATHS, and GITHUB_OUTPUT from the environment.
# ADDITIONAL_DIR is optional, and a workflow that takes no
# `additional-directory` input leaves it unset.
#
# Usage:
#
#     CI_DIR=.github/ci/phpstan SOURCE_PATHS='src/**/*.php' \
#         .github/ci/scripts/derive-path-filters.sh
# ---------------------------------------------------------------------------

# A bare `run:` step invokes this script, so it sets `set -e` alone.
# `.github/workflows/README.md` holds the rule for each family, under Scripts.
set -e

: "${CI_DIR:?CI_DIR must name the CI directory}"
: "${SOURCE_PATHS:?SOURCE_PATHS must name the source globs}"

CONFIG=$(
  printf "  - '%s/**'\n" "$CI_DIR"
  if [[ -n "$ADDITIONAL_DIR" ]]; then
    printf "  - '%s/**'\n" "$ADDITIONAL_DIR"
  fi
  printf "  - '.github/workflows/ci.yml'\n"
)

{
  echo 'spec<<PATH_FILTERS_EOF'
  echo 'ci:'
  printf '%s\n' "$CONFIG"
  echo 'files:'
  printf '%s\n' "$CONFIG"
  printf '%s\n' "$SOURCE_PATHS" | while IFS= read -r glob; do
    glob=$(printf '%s' "$glob" | tr -d "\"' " )
    # `&& printf` would make an empty line the last command and, under `bash -e`,
    # fail the step. `source-paths` is a block scalar so it always ends in one.
    if [[ -n "$glob" ]]; then
      printf "  - '%s'\n" "$glob"
    fi
  done
  echo 'PATH_FILTERS_EOF'
} >> "$GITHUB_OUTPUT"
