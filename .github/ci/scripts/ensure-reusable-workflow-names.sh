#!/usr/bin/env bash
#
# This file is part of the Valkyrja GitHub package.
#
# Copyright (c) 2016-present Melech Mizrachi
#
# Released under the MIT License. See LICENSE.md for details.
#
# ---------------------------------------------------------------------------
# Reusable workflow name and filename check.
#
# A reusable workflow carries a `_` filename prefix and a `Z Reusable` name
# prefix. The `_` marks the file as `workflow_call` only, and the `Z` sorts the
# workflow below the user-facing workflows in the Actions list.
#
# This script reads every repository in the organization and corrects both
# prefixes. It renames a `workflow_call`-only file that has no `_` prefix, and
# it adds the `Z` to a name that starts with `Reusable`. Each correction goes
# on a `deps/` branch, and the script opens one pull request for each base
# branch it changed.
#
# The script reads and writes through the GitHub API. It never checks a
# repository out.
#
# Reads GH_TOKEN, ORG, and SUPPORTED_VERSIONS from the environment.
#
# Usage:
#
#     .github/ci/scripts/ensure-reusable-workflow-names.sh
# ---------------------------------------------------------------------------

# A bare `run:` step invokes this script, so it sets `set -e`.
# `.github/workflows/README.md` holds the rule for each family, under Scripts.
#
# `pipefail` would change what this script does. The pipeline that decodes the
# file content ends in `base64`, and `set -e` reads that last status, so a `jq`
# that fails is not a failure today.
set -e

is_workflow_call_only() {
  local content="$1"
  local on_value
  on_value=$(echo "$content" | grep '^on:' | sed 's/^on:[[:space:]]*//')
  if [[ "$on_value" = "workflow_call" ]]; then
    return 0
  fi
  # Warning: `grep -c` exits 1 when it counts nothing, and a count of zero is
  # the answer this asks for. `|| true` keeps that status off the assignment,
  # so the count is read rather than the exit.
  local other_triggers
  other_triggers=$(echo "$content" | awk '/^on:/{found=1; next} found && /^[^ ]/{exit} found && /^  [a-zA-Z]/{print}' \
    | grep -c -v '^  workflow_call' || true)
  local has_workflow_call
  has_workflow_call=$(echo "$content" | awk '/^on:/{found=1; next} found && /^[^ ]/{exit} found && /^  workflow_call/{print}' | wc -l)
  [[ "$other_triggers" -eq 0 ]] && [[ "$has_workflow_call" -gt 0 ]]
}

REPOS=$(gh repo list "$ORG" --limit 200 --json name,isArchived \
  --jq '.[] | select(.isArchived == false) | .name')

while IFS= read -r REPO_NAME; do
  echo "Checking $ORG/$REPO_NAME..."

  ALL_WORKFLOW_FILES=$(gh api "repos/$ORG/$REPO_NAME/contents/.github/workflows" \
    --jq '[.[] | select(.type == "file" and (.name | endswith(".yml"))) | .path][]' 2>/dev/null || true)

  [[ -z "$ALL_WORKFLOW_FILES" ]] && continue

  ALL_BRANCHES=$(gh api "repos/$ORG/$REPO_NAME/branches" --paginate \
    --jq '.[].name' 2>/dev/null || true)

  BASE_BRANCHES=""
  while IFS= read -r b; do
    if [[ "$b" =~ ^([0-9]+)\.x$ ]]; then
      MAJOR="${BASH_REMATCH[1]}"
      if [[ -n "$SUPPORTED_VERSIONS" ]] && [[ "$MAJOR" =~ $SUPPORTED_VERSIONS ]]; then
        BASE_BRANCHES="$BASE_BRANCHES"$'\n'"$b"
      fi
    fi
  done <<< "$ALL_BRANCHES"

  if [[ -z "$BASE_BRANCHES" ]]; then
    BASE_BRANCHES="master"
  fi

  while IFS= read -r BASE_BRANCH; do
    [[ -z "$BASE_BRANCH" ]] && continue

    if [[ "$BASE_BRANCH" = "master" ]]; then
      UPDATE_BRANCH="deps/ensure-reusable-workflow-names"
    else
      UPDATE_BRANCH="deps/ensure-reusable-workflow-names-$BASE_BRANCH"
    fi

    BRANCH_EXISTS=$(gh api "repos/$ORG/$REPO_NAME/git/ref/heads/$UPDATE_BRANCH" \
      --jq '.object.sha' 2>/dev/null) || BRANCH_EXISTS=""

    FILES_UPDATED=0
    FILES_LIST=""

    create_branch_if_needed() {
      [[ -n "$BRANCH_EXISTS" ]] && return 0
      echo "  [$BASE_BRANCH] Creating branch $UPDATE_BRANCH..."
      local base_sha
      base_sha=$(gh api "repos/$ORG/$REPO_NAME/git/ref/heads/$BASE_BRANCH" \
        --jq '.object.sha' 2>/dev/null) || base_sha=""
      if [[ -z "$base_sha" ]]; then
        echo "  [$BASE_BRANCH] Could not get base branch SHA, skipping"
        return 2
      fi
      local branch_create_err
      branch_create_err=$(gh api --method POST "repos/$ORG/$REPO_NAME/git/refs" \
        --field "ref=refs/heads/$UPDATE_BRANCH" \
        --field "sha=$base_sha" 2>&1 >/dev/null || true)
      if [[ -n "$branch_create_err" ]]; then
        echo "  [$BASE_BRANCH] Branch creation failed: $branch_create_err"
        return 2
      fi
      echo "  [$BASE_BRANCH] Branch $UPDATE_BRANCH created."
      BRANCH_EXISTS="$base_sha"
    }

    while IFS= read -r FILE_PATH; do
      FILE_BASENAME=$(basename "$FILE_PATH")

      FILE_DATA=$(gh api "repos/$ORG/$REPO_NAME/contents/$FILE_PATH?ref=$BASE_BRANCH" \
        2>/dev/null || true)
      [[ -z "$FILE_DATA" ]] && continue

      FILE_SHA=$(echo "$FILE_DATA" | jq -r '.sha')
      CONTENT=$(echo "$FILE_DATA" | jq -r '.content // empty' | tr -d '\n' | base64 -d)
      [[ -z "$CONTENT" ]] && continue

      # Fix name prefix on _-prefixed files missing "Z Reusable"
      if [[ "$FILE_BASENAME" == _* ]]; then
        if ! echo "$CONTENT" | grep -q '^name: Reusable'; then
          echo "  [$BASE_BRANCH] $FILE_PATH: name already correct, skipping"
          continue
        fi

        echo "  [$BASE_BRANCH] $FILE_PATH: missing Z prefix in name, will update"
        # shellcheck disable=SC2001 # `^` anchors each line, and `${var//}` anchors nothing.
        NEW_CONTENT=$(echo "$CONTENT" | sed 's/^name: Reusable/name: Z Reusable/')

        create_branch_if_needed || continue

        echo "  [$BASE_BRANCH] Committing $FILE_PATH to $UPDATE_BRANCH..."
        NEW_CONTENT_B64=$(printf '%s\n' "$NEW_CONTENT" | base64 | tr -d '\n')
        PUT_BODY=$(jq -cn \
          --arg message "[Workflow] ci: Add the Z Reusable prefix to the workflow name." \
          --arg content "$NEW_CONTENT_B64" \
          --arg sha "$FILE_SHA" \
          --arg branch "$UPDATE_BRANCH" \
          '{message: $message, content: $content, sha: $sha, branch: $branch}')
        COMMIT_ERR=$(echo "$PUT_BODY" | gh api --method PUT "repos/$ORG/$REPO_NAME/contents/$FILE_PATH" \
          --input - 2>&1 >/dev/null || true)
        if [[ -n "$COMMIT_ERR" ]]; then
          echo "  [$BASE_BRANCH] $FILE_PATH commit failed: $COMMIT_ERR"
          continue
        fi
        echo "  [$BASE_BRANCH] $FILE_PATH committed."
        FILES_LIST+="| \`$FILE_PATH\` | Added \`Z Reusable\` prefix to \`name\` |"$'\n'
        FILES_UPDATED=$((FILES_UPDATED + 1))

      # Rename non-_-prefixed files that are workflow_call-only
      else
        if ! is_workflow_call_only "$CONTENT"; then
          continue
        fi

        NEW_FILE_PATH=".github/workflows/_$FILE_BASENAME"
        echo "  [$BASE_BRANCH] $FILE_PATH: workflow_call-only but missing _ prefix, will rename to $NEW_FILE_PATH"

        # Also fix name prefix if needed
        NEW_CONTENT="$CONTENT"
        if echo "$CONTENT" | grep -q '^name: Reusable'; then
          # shellcheck disable=SC2001 # `^` anchors each line, and `${var//}` anchors nothing.
          NEW_CONTENT=$(echo "$CONTENT" | sed 's/^name: Reusable/name: Z Reusable/')
        fi

        create_branch_if_needed || continue

        # Create new _-prefixed file
        echo "  [$BASE_BRANCH] Creating $NEW_FILE_PATH..."
        NEW_CONTENT_B64=$(printf '%s\n' "$NEW_CONTENT" | base64 | tr -d '\n')
        PUT_BODY=$(jq -cn \
          --arg message "[Workflow] ci: Rename $FILE_BASENAME to _$FILE_BASENAME." \
          --arg content "$NEW_CONTENT_B64" \
          --arg branch "$UPDATE_BRANCH" \
          '{message: $message, content: $content, branch: $branch}')
        COMMIT_ERR=$(echo "$PUT_BODY" | gh api --method PUT "repos/$ORG/$REPO_NAME/contents/$NEW_FILE_PATH" \
          --input - 2>&1 >/dev/null || true)
        if [[ -n "$COMMIT_ERR" ]]; then
          echo "  [$BASE_BRANCH] $NEW_FILE_PATH create failed: $COMMIT_ERR"
          continue
        fi

        # Delete old file
        echo "  [$BASE_BRANCH] Deleting $FILE_PATH..."
        DEL_BODY=$(jq -cn \
          --arg message "[Workflow] ci: Remove $FILE_BASENAME (renamed to _$FILE_BASENAME)." \
          --arg sha "$FILE_SHA" \
          --arg branch "$UPDATE_BRANCH" \
          '{message: $message, sha: $sha, branch: $branch}')
        DEL_ERR=$(echo "$DEL_BODY" | gh api --method DELETE "repos/$ORG/$REPO_NAME/contents/$FILE_PATH" \
          --input - 2>&1 >/dev/null || true)
        if [[ -n "$DEL_ERR" ]]; then
          echo "  [$BASE_BRANCH] $FILE_PATH delete failed: $DEL_ERR"
          continue
        fi

        echo "  [$BASE_BRANCH] $FILE_PATH renamed to $NEW_FILE_PATH."
        FILES_LIST+="| \`$FILE_PATH\` | Renamed to \`$NEW_FILE_PATH\` |"$'\n'
        FILES_UPDATED=$((FILES_UPDATED + 1))
      fi
    done <<< "$ALL_WORKFLOW_FILES"

    if [[ "$FILES_UPDATED" -gt 0 ]]; then
      echo "  [$BASE_BRANCH] $FILES_UPDATED file(s) updated — checking for existing PR..."

      EXISTING_PR=$(gh pr list --repo "$ORG/$REPO_NAME" \
        --state open \
        --json headRefName \
        --jq "[.[] | select(.headRefName == \"$UPDATE_BRANCH\")] | first | .headRefName // \"\"" \
        2>/dev/null || true)

      if [[ -z "$EXISTING_PR" ]]; then
        BODY="# Description"$'\n'$'\n'
        BODY+="Ensure reusable workflows in \`$REPO_NAME\` follow naming conventions."$'\n'$'\n'
        BODY+="## Types of changes"$'\n'$'\n'
        BODY+="- [X] Improvement _(non-breaking change which improves code)_"$'\n'
        BODY+="- [ ] Bug fix _(non-breaking change which fixes an issue)_"$'\n'
        BODY+="- [ ] New feature _(non-breaking change which adds functionality)_"$'\n'
        BODY+="- [ ] Deprecation _(breaking change which removes functionality)_"$'\n'
        BODY+="- [ ] Breaking change _(fix or feature that would cause existing functionality to change)_"$'\n'
        BODY+="- [ ] Documentation improvement"$'\n'$'\n'
        BODY+="## Changes"$'\n'$'\n'
        BODY+="| File | Change |"$'\n'
        BODY+="|------|--------|"$'\n'
        BODY+="$FILES_LIST"

        echo "  [$BASE_BRANCH] Creating PR from $UPDATE_BRANCH → $BASE_BRANCH..."

        if ! gh pr create \
          --repo "$ORG/$REPO_NAME" \
          --title "[Workflow] ci: Ensure reusable workflow naming conventions" \
          --body "$BODY" \
          --base "$BASE_BRANCH" \
          --head "$UPDATE_BRANCH" 2>/dev/null; then
          echo "  [$BASE_BRANCH] PR creation failed, skipping"
        else
          echo "  [$BASE_BRANCH] PR created."
        fi
      else
        echo "  [$BASE_BRANCH] PR already exists, skipping."
      fi
    fi
  done <<< "$BASE_BRANCHES"
done <<< "$REPOS"
