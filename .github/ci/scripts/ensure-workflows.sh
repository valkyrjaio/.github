#!/usr/bin/env bash
#
# This file is part of the Valkyrja GitHub package.
#
# Copyright (c) 2016-present Melech Mizrachi
#
# Released under the MIT License. See LICENSE.md for details.
#
# ---------------------------------------------------------------------------
# Required workflow presence check.
#
# `required-workflows/` holds the workflow files that every repository in the
# organization receives. This script adds each missing file to each repository,
# on a `deps/` branch, and it opens one pull request for each base branch it
# changed. It merges the missing jobs into an existing `ci.yml` rather than
# replacing the file.
#
# The templates come from the working tree, so the job checks this repository
# out at `dot-github` and the script reads `dot-github/required-workflows`.
# Every repository it writes to it reaches through the GitHub API.
#
# This repository excludes itself. Its own callers use local `./` references,
# so a template pinned to a release SHA would run the released workflow rather
# than the branch under test.
#
# Reads GH_TOKEN, ORG, and SUPPORTED_VERSIONS from the environment.
#
# Usage:
#
#     dot-github/.github/ci/scripts/ensure-workflows.sh
# ---------------------------------------------------------------------------

# A bare `run:` step invokes this script, so it sets `set -e`.
# `.github/workflows/README.md` holds the rule for each family, under Scripts.
set -e

# The script names a sibling file below, and the caller runs it from the workspace root
# rather than from this directory. `BASH_SOURCE` is what makes the sibling reachable from
# either one.
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

LATEST_TAG=$(gh api "repos/$ORG/.github/releases/latest" --jq '.tag_name')
LATEST_SHA=$(gh api "repos/$ORG/.github/commits/$LATEST_TAG" --jq '.sha')
echo "Latest .github release: $LATEST_TAG ($LATEST_SHA)"

TEMPLATE_DIR="dot-github/required-workflows"

REQUIRED_WORKFLOWS=(
  "cherry-pick-commits.yml"
  "claude-review.yml"
  "pr.yml"
  "rebase-from-master.yml"
  "rebase-to-master.yml"
  "restore-branch-from-backup.yml"
)

# Workflows that only exist in a language-specific flavor, so they are
# sourced from required-workflows/<lang>/ rather than the root.
LANG_WORKFLOWS=(
  "update-dependencies.yml"
)

PHP_EXCLUDED_REPOS="valkyrja-benchmarking-php valkyrja-docker-php"

# The .github repo excludes itself on purpose. Its own callers use local
# `./` refs, so a synced template pinned to a release SHA would be wrong
# here: it would run the released workflow instead of the branch under
# test. This repo therefore adds its own copies by hand.
REPOS=$(gh repo list "$ORG" --limit 200 --json name,isArchived \
  --jq '.[] | select(.isArchived == false and .name != ".github") | .name')

create_branch_if_needed() {
  local base_branch="$1"
  local update_branch="$2"
  local repo_name="$3"

  [[ -n "$BRANCH_EXISTS" ]] && return 0

  echo "  [$base_branch] Creating branch $update_branch..."
  local base_sha
  base_sha=$(gh api "repos/$ORG/$repo_name/git/refs/heads/$base_branch" \
    --jq '.object.sha' 2>/dev/null || true)
  if [[ -z "$base_sha" ]]; then
    echo "  [$base_branch] Could not get base branch SHA, skipping"
    return 2
  fi
  local branch_create_err
  branch_create_err=$(gh api --method POST "repos/$ORG/$repo_name/git/refs" \
    --field "ref=refs/heads/$update_branch" \
    --field "sha=$base_sha" 2>&1 >/dev/null || true)
  if [[ -n "$branch_create_err" ]]; then
    echo "  [$base_branch] Branch creation failed: $branch_create_err"
    return 2
  fi
  echo "  [$base_branch] Branch $update_branch created."
  BRANCH_EXISTS="$base_sha"
}

ensure_workflow() {
  local workflow="$1"
  local tmpl_file="$2"
  local base_branch="$3"
  local update_branch="$4"
  local repo_name="$5"

  local file_path=".github/workflows/$workflow"

  local existing
  existing=$(gh api "repos/$ORG/$repo_name/contents/$file_path?ref=$base_branch" \
    --jq '.name' 2>/dev/null) || existing=""

  if [[ -n "$existing" ]]; then
    echo "  [$base_branch] $file_path: already exists, skipping"
    return 0
  fi

  echo "  [$base_branch] $file_path: missing, will create"

  local content
  content=$(sed "s|valkyrjaio/\.github/\.github/workflows/\([^@]*\)@[0-9a-f]\{40\}|valkyrjaio/.github/.github/workflows/\1@$LATEST_SHA|g" "$tmpl_file")

  create_branch_if_needed "$base_branch" "$update_branch" "$repo_name" || return $?

  echo "  [$base_branch] Committing $file_path to $update_branch..."

  local content_b64
  content_b64=$(printf '%s\n' "$content" | base64 | tr -d '\n')

  local put_body
  put_body=$(jq -cn \
    --arg message "[Workflow] ci: Add the missing $workflow workflow." \
    --arg content "$content_b64" \
    --arg branch "$update_branch" \
    '{message: $message, content: $content, branch: $branch}')

  local commit_err
  commit_err=$(echo "$put_body" | gh api --method PUT "repos/$ORG/$repo_name/contents/$file_path" \
    --input - 2>&1 >/dev/null || true)
  if [[ -n "$commit_err" ]]; then
    echo "  [$base_branch] $file_path commit failed: $commit_err"
    return 1
  fi

  echo "  [$base_branch] $file_path committed."
  FILES_LIST+="| \`.github/workflows/$workflow\` | Added |"$'\n'
  FILES_ADDED=$((FILES_ADDED + 1))
}

ensure_ci_jobs() {
  local base_branch="$1"
  local update_branch="$2"
  local repo_name="$3"
  local tmpl_file="$4"

  local file_path=".github/workflows/ci.yml"
  local tmpl_with_sha
  tmpl_with_sha=$(sed "s|valkyrjaio/\.github/\.github/workflows/\([^@]*\)@[0-9a-f]\{40\}|valkyrjaio/.github/.github/workflows/\1@$LATEST_SHA|g" "$tmpl_file" 2>/dev/null || true)
  if [[ -z "$tmpl_with_sha" ]]; then
    echo "  [$base_branch] Could not read template $tmpl_file, skipping ci.yml"
    return 1
  fi

  local file_data
  file_data=$(gh api "repos/$ORG/$repo_name/contents/$file_path?ref=$base_branch" 2>/dev/null || true)

  if [[ -z "$file_data" ]]; then
    echo "  [$base_branch] $file_path: missing, will create"
    create_branch_if_needed "$base_branch" "$update_branch" "$repo_name" || return $?

    local content_b64
    content_b64=$(printf '%s\n' "$tmpl_with_sha" | base64 | tr -d '\n')
    local put_body
    put_body=$(jq -cn \
      --arg message "[Workflow] ci: Add the missing ci.yml workflow." \
      --arg content "$content_b64" \
      --arg branch "$update_branch" \
      '{message: $message, content: $content, branch: $branch}')
    local commit_err
    commit_err=$(echo "$put_body" | gh api --method PUT "repos/$ORG/$repo_name/contents/$file_path" \
      --input - 2>&1 >/dev/null || true)
    if [[ -n "$commit_err" ]]; then
      echo "  [$base_branch] $file_path commit failed: $commit_err"
      return 1
    fi
    echo "  [$base_branch] $file_path committed."
    FILES_LIST+="| \`.github/workflows/ci.yml\` | Added |"$'\n'
    FILES_ADDED=$((FILES_ADDED + 1))
    return 0
  fi

  local file_sha content_b64
  file_sha=$(echo "$file_data" | jq -r '.sha')
  content_b64=$(echo "$file_data" | jq -r '.content // empty' | tr -d '\n')
  echo "$content_b64" | base64 -d > /tmp/ci_existing.yml
  printf '%s\n' "$tmpl_with_sha" > /tmp/ci_template.yml

  local updated_content
  if ! updated_content=$(python3 "$SCRIPT_DIR/merge_ci_jobs.py" /tmp/ci_existing.yml /tmp/ci_template.yml 2>/dev/null); then
    echo "  [$base_branch] $file_path: all required jobs present"
    return 0
  fi

  echo "  [$base_branch] $file_path: missing required jobs, will update"
  create_branch_if_needed "$base_branch" "$update_branch" "$repo_name" || return $?

  local new_content_b64
  new_content_b64=$(printf '%s\n' "$updated_content" | base64 | tr -d '\n')
  local put_body
  put_body=$(jq -cn \
    --arg message "[Workflow] ci: Add the missing required jobs to ci.yml." \
    --arg content "$new_content_b64" \
    --arg sha "$file_sha" \
    --arg branch "$update_branch" \
    '{message: $message, content: $content, sha: $sha, branch: $branch}')
  local commit_err
  commit_err=$(echo "$put_body" | gh api --method PUT "repos/$ORG/$repo_name/contents/$file_path" \
    --input - 2>&1 >/dev/null || true)
  if [[ -n "$commit_err" ]]; then
    echo "  [$base_branch] $file_path commit failed: $commit_err"
    return 1
  fi
  echo "  [$base_branch] $file_path updated with missing jobs."
  FILES_LIST+="| \`.github/workflows/ci.yml\` | Updated (added missing jobs) |"$'\n'
  FILES_ADDED=$((FILES_ADDED + 1))
}

while IFS= read -r REPO_NAME; do
  echo "Checking $ORG/$REPO_NAME..."

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

  # Which required-workflows/<lang>/ directory this repo draws from.
  # Empty means the repo has no language-specific flavor (or is excluded
  # from one), and the language-agnostic root templates are used instead.
  LANG_DIR=""
  if [[ "$REPO_NAME" == *-php ]]; then
    LANG_DIR="php"
    if [[ " $PHP_EXCLUDED_REPOS " == *" $REPO_NAME "* ]]; then
      LANG_DIR=""
    fi
  elif [[ "$REPO_NAME" == *-go ]]; then
    LANG_DIR="go"
  elif [[ "$REPO_NAME" == *-python ]]; then
    LANG_DIR="python"
  elif [[ "$REPO_NAME" == *-java ]]; then
    LANG_DIR="java"
  elif [[ "$REPO_NAME" == *-ts ]]; then
    LANG_DIR="ts"
  fi

  while IFS= read -r BASE_BRANCH; do
    [[ -z "$BASE_BRANCH" ]] && continue

    if [[ "$BASE_BRANCH" = "master" ]]; then
      UPDATE_BRANCH="deps/ensure-workflows"
    else
      UPDATE_BRANCH="deps/ensure-workflows-$BASE_BRANCH"
    fi

    BRANCH_EXISTS=$(gh api "repos/$ORG/$REPO_NAME/git/refs/heads/$UPDATE_BRANCH" \
      --jq '.object.sha' 2>/dev/null) || BRANCH_EXISTS=""

    FILES_ADDED=0
    FILES_LIST=""

    for WORKFLOW in "${REQUIRED_WORKFLOWS[@]}"; do
      ensure_workflow "$WORKFLOW" "$TEMPLATE_DIR/$WORKFLOW" \
        "$BASE_BRANCH" "$UPDATE_BRANCH" "$REPO_NAME" || \
        { [[ $? -eq 2 ]] && break; }
    done

    if [[ -n "$LANG_DIR" ]]; then
      for WORKFLOW in "${LANG_WORKFLOWS[@]}"; do
        ensure_workflow "$WORKFLOW" "$TEMPLATE_DIR/$LANG_DIR/$WORKFLOW" \
          "$BASE_BRANCH" "$UPDATE_BRANCH" "$REPO_NAME" || \
          { [[ $? -eq 2 ]] && break; }
      done
      ensure_workflow "create-version-branch.yml" "$TEMPLATE_DIR/$LANG_DIR/create-version-branch.yml" \
        "$BASE_BRANCH" "$UPDATE_BRANCH" "$REPO_NAME" || true
      ensure_workflow "release-new-version.yml" "$TEMPLATE_DIR/$LANG_DIR/release-new-version.yml" \
        "$BASE_BRANCH" "$UPDATE_BRANCH" "$REPO_NAME" || true
      ensure_ci_jobs "$BASE_BRANCH" "$UPDATE_BRANCH" "$REPO_NAME" \
        "$TEMPLATE_DIR/$LANG_DIR/ci.yml" || true
    else
      ensure_workflow "create-version-branch.yml" "$TEMPLATE_DIR/create-version-branch.yml" \
        "$BASE_BRANCH" "$UPDATE_BRANCH" "$REPO_NAME" || true
      ensure_workflow "release-new-version.yml" "$TEMPLATE_DIR/release-new-version.yml" \
        "$BASE_BRANCH" "$UPDATE_BRANCH" "$REPO_NAME" || true
      ensure_ci_jobs "$BASE_BRANCH" "$UPDATE_BRANCH" "$REPO_NAME" \
        "$TEMPLATE_DIR/ci.yml" || true
    fi

    if [[ "$FILES_ADDED" -gt 0 ]]; then
      echo "  [$BASE_BRANCH] $FILES_ADDED file(s) added/updated — checking for existing PR..."

      EXISTING_PR=$(gh pr list --repo "$ORG/$REPO_NAME" \
        --state open \
        --json headRefName \
        --jq "[.[] | select(.headRefName == \"$UPDATE_BRANCH\")] | first | .headRefName // \"\"" \
        2>/dev/null || true)

      if [[ -z "$EXISTING_PR" ]]; then
        BODY="# Description"$'\n'$'\n'
        BODY+="Ensure required workflow files exist in \`$REPO_NAME\` pinned to \`$LATEST_TAG\`."$'\n'$'\n'
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
        BODY+=$'\n'
        BODY+="> [!NOTE]"$'\n'
        BODY+="> \`release-new-version.yml\` may require updating \`info-class-path\` and \`info-class-name\` for this repository if it is a PHP repo."$'\n'

        echo "  [$BASE_BRANCH] Creating PR from $UPDATE_BRANCH → $BASE_BRANCH..."

        if ! gh pr create \
          --repo "$ORG/$REPO_NAME" \
          --title "[Workflow] ci: Ensure required workflow files" \
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
