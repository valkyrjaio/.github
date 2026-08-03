#!/usr/bin/env bash
#
# This file is part of the Valkyrja GitHub package.
#
# Copyright (c) 2016-present Melech Mizrachi
#
# Released under the MIT License. See LICENSE.md for details.
#
# ---------------------------------------------------------------------------
# Repository settings, labels, and ruleset enforcement.
#
# This script applies the organization's standard settings to every repository
# that the organization owns and has not archived. It applies every label under
# `labels/` and every ruleset under `rulesets/`, and it adds the language ones
# under `labels/<lang>/` and `rulesets/<lang>/` to a repository of that
# language.
#
# It creates a label that is missing and corrects one that has drifted. It
# never deletes a label, because a repository may carry labels of its own and
# deleting one would strip it from every issue and pull request already using
# it.
#
# The label and ruleset files come from the working tree, so the caller checks
# this repository out and runs the script from the repository root. Every
# repository it writes to it reaches through the GitHub API.
#
# Reads GH_TOKEN, ORG, and TARGET_REPO from the environment. TARGET_REPO
# narrows the run to one repository, and an empty value sweeps them all.
#
# Usage:
#
#     .github/ci/scripts/enforce-repo-settings.sh
# ---------------------------------------------------------------------------

# Warning: `-u` and `pipefail` are deliberately absent. A `run:` step that names
# no shell runs under `bash -e {0}`, and this script holds such a block. The
# `bash --noprofile --norc -eo pipefail {0}` form is what an explicit
# `shell: bash` selects, which is why a script that `run-script` invokes sets
# `pipefail` and this one does not.
set -e

shopt -s nullglob

if [ -n "$TARGET_REPO" ]; then
  REPOS=$(gh repo list "$ORG" --limit 200 --json name,description,isArchived \
    --jq ".[] | select(.name == \"$TARGET_REPO\") | [.name, (.description // \"\")] | @json")
else
  REPOS=$(gh repo list "$ORG" --limit 200 --json name,description,isArchived \
    --jq '.[] | select(.isArchived == false) | [.name, (.description // "")] | @json')
fi

# Applies every label in a labels directory to the current repository.
# Called with `labels` for every repo, and with `labels/<lang>` for a
# repo of that language, mirroring how rulesets are applied. Add a
# label by appending an object to a file there, or by adding a file;
# nothing here changes either way. Each file holds an array.
# This creates a missing label and corrects a drifted color or
# description. It never deletes: a label these files do not name is
# left alone, because a repository may carry labels of its own, and
# deleting one would strip it from every issue and pull request using
# it.
apply_labels() {
  local label_dir="$1"
  local label_file label_json LABEL_NAME LABEL_COLOR LABEL_DESC

  for label_file in "$label_dir"/*.json; do
    while IFS= read -r label_json; do
      LABEL_NAME=$(echo "$label_json" | jq -r '.name')
      LABEL_COLOR=$(echo "$label_json" | jq -r '.color')
      LABEL_DESC=$(echo "$label_json" | jq -r '.description // ""')

      if gh label create "$LABEL_NAME" --repo "$ORG/$REPO_NAME" \
           --color "$LABEL_COLOR" --description "$LABEL_DESC" --force \
           > /dev/null 2>&1; then
        echo "  Label ensured: $LABEL_NAME"
      else
        echo "  Failed to ensure label: $LABEL_NAME" >&2
        exit 1
      fi
    done < <(jq -c '.[]' "$label_file")
  done
}

apply_or_update_ruleset() {
  local ruleset_file="$1"
  local RULESET_NAME
  RULESET_NAME=$(jq -r '.name' "$ruleset_file")
  local RULESET_ID
  RULESET_ID=$(echo "$EXISTING" | jq -r --arg n "$RULESET_NAME" '.[] | select(.name == $n) | .id')

  if [ -z "$RULESET_ID" ]; then
    echo "  Applying ruleset: $RULESET_NAME"
    jq '{name, target, enforcement, conditions, rules, bypass_actors}' "$ruleset_file" \
      | gh api --method POST "repos/$ORG/$REPO_NAME/rulesets" --input - > /dev/null
  else
    local DESIRED CURRENT
    DESIRED=$(jq -S '{name, target, enforcement, conditions, rules, bypass_actors}' "$ruleset_file")
    CURRENT=$(gh api "repos/$ORG/$REPO_NAME/rulesets/$RULESET_ID" \
      --jq '{name, target, enforcement, conditions, rules, bypass_actors}' | jq -S .)
    if [ "$DESIRED" != "$CURRENT" ]; then
      echo "  Updating ruleset: $RULESET_NAME"
      jq '{name, target, enforcement, conditions, rules, bypass_actors}' "$ruleset_file" \
        | gh api --method PUT "repos/$ORG/$REPO_NAME/rulesets/$RULESET_ID" --input - > /dev/null
    else
      echo "  Ruleset up to date: $RULESET_NAME"
    fi
  fi
}

while IFS= read -r repo_json; do
  REPO_NAME=$(echo "$repo_json" | jq -r '.[0]')
  DESCRIPTION=$(echo "$repo_json" | jq -r '.[1]')

  echo "Enforcing settings for $ORG/$REPO_NAME..."

  gh api --method PATCH "repos/$ORG/$REPO_NAME" \
    --field allow_squash_merge=true \
    --field allow_merge_commit=false \
    --field allow_rebase_merge=false \
    --field delete_branch_on_merge=true \
    --field squash_merge_commit_title="PR_TITLE" \
    --field squash_merge_commit_message="PR_BODY" \
    --field has_wiki=false \
    --field has_projects=false \
    > /dev/null
  echo "  Settings applied"

  gh api --method PUT "repos/$ORG/$REPO_NAME/vulnerability-alerts" > /dev/null
  gh api --method PUT "repos/$ORG/$REPO_NAME/automated-security-fixes" > /dev/null

  # Immutable releases may already be enforced org-wide by the owner,
  # in which case the per-repo PUT returns 409 — that's the desired
  # state, so treat only a 409 as success and surface any other error.
  if ! IMMUTABLE_ERR=$(gh api --method PUT "repos/$ORG/$REPO_NAME/immutable-releases" 2>&1 >/dev/null); then
    if echo "$IMMUTABLE_ERR" | grep -q "HTTP 409"; then
      echo "  Immutable releases already enforced org-wide; skipping."
    else
      echo "$IMMUTABLE_ERR" >&2
      exit 1
    fi
  fi
  echo "  Security settings applied"

  apply_labels labels

  EXISTING=$(gh api "repos/$ORG/$REPO_NAME/rulesets" \
    --jq '[.[] | {id: .id, name: .name}]' 2>/dev/null || echo "[]")

  for ruleset_file in rulesets/*.json; do
    apply_or_update_ruleset "$ruleset_file"
  done

  PHP_EXCLUDED_REPOS="valkyrja-benchmarking-php valkyrja-docker-php"
  COMBINED=$(echo "$REPO_NAME $DESCRIPTION" | tr '[:upper:]' '[:lower:]')
  if echo "$COMBINED" | grep -qi "php" && [[ ! " $PHP_EXCLUDED_REPOS " == *" $REPO_NAME "* ]]; then
    echo "  PHP repo detected, checking PHP-specific rulesets..."
    for ruleset_file in rulesets/php/*.json; do
      apply_or_update_ruleset "$ruleset_file"
    done
    apply_labels labels/php
  fi

  if [[ "$REPO_NAME" =~ -ts$ ]]; then
    echo "  TypeScript repo detected, checking TypeScript-specific rulesets..."
    for ruleset_file in rulesets/ts/*.json; do
      apply_or_update_ruleset "$ruleset_file"
    done
    apply_labels labels/ts
  fi

  if [[ "$REPO_NAME" =~ -java$ ]]; then
    echo "  Java repo detected, checking Java-specific rulesets..."
    for ruleset_file in rulesets/java/*.json; do
      apply_or_update_ruleset "$ruleset_file"
    done
    apply_labels labels/java
  fi

  if [[ "$REPO_NAME" =~ -go$ ]]; then
    echo "  Go repo detected, checking Go-specific rulesets..."
    for ruleset_file in rulesets/go/*.json; do
      apply_or_update_ruleset "$ruleset_file"
    done
    apply_labels labels/go
  fi

  if [[ "$REPO_NAME" =~ -python$ ]]; then
    echo "  Python repo detected, checking Python-specific rulesets..."
    for ruleset_file in rulesets/python/*.json; do
      apply_or_update_ruleset "$ruleset_file"
    done
    apply_labels labels/python
  fi
done <<< "$REPOS"
