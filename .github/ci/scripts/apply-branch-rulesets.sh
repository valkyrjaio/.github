#!/usr/bin/env bash
#
# This file is part of the Valkyrja GitHub package.
#
# Copyright (c) 2016-present Melech Mizrachi
#
# Released under the MIT License. See LICENSE.md for details.
#
# ---------------------------------------------------------------------------
# Branch ruleset application for a new repository.
#
# This script applies every ruleset under `rulesets/` to the new repository,
# and the language ones under `rulesets/<lang>/` when the name ends in a
# supported language. The ruleset files come from the working tree, so the
# caller runs this from the repository root.
#
# Reads GH_TOKEN, ORG, REPO_NAME, and SUPPORTED_LANGUAGES from the environment.
#
# Usage:
#
#     .github/ci/scripts/apply-branch-rulesets.sh
# ---------------------------------------------------------------------------

# Warning: `-u` and `pipefail` are deliberately absent. A `run:` step that names
# no shell runs under `bash -e {0}`, and this script holds such a block. The
# `bash --noprofile --norc -eo pipefail {0}` form is what an explicit
# `shell: bash` selects, which is why a script that `run-script` invokes sets
# `pipefail` and this one does not.
set -e

shopt -s nullglob

for ruleset_file in rulesets/*.json; do
  echo "Applying ruleset: $(basename "$ruleset_file")"
  jq '{name, target, enforcement, conditions, rules, bypass_actors}' "$ruleset_file" \
    | gh api --method POST "repos/$ORG/$REPO_NAME/rulesets" --input -
done

# Apply language-specific rulesets from rulesets/<lang>/ for known
# languages (same suffix rule as the template step).
LANG_SUFFIX=$(echo "${REPO_NAME##*-}" | tr '[:upper:]' '[:lower:]')
if [[ " $SUPPORTED_LANGUAGES " == *" $LANG_SUFFIX "* && -d "rulesets/$LANG_SUFFIX" ]]; then
  echo "Applying $LANG_SUFFIX-specific rulesets..."
  for ruleset_file in rulesets/"$LANG_SUFFIX"/*.json; do
    echo "Applying $LANG_SUFFIX ruleset: $(basename "$ruleset_file")"
    jq '{name, target, enforcement, conditions, rules, bypass_actors}' "$ruleset_file" \
      | gh api --method POST "repos/$ORG/$REPO_NAME/rulesets" --input -
  done
fi
