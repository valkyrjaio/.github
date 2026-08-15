#!/usr/bin/env bash
#
# This file is part of the Valkyrja GitHub package.
#
# Copyright (c) 2016-present Melech Mizrachi
#
# Released under the MIT License. See LICENSE.md for details.
#
# ---------------------------------------------------------------------------
# Trailing newline repair across the organization.
#
# Every tracked file ends with a newline, and the trailing newline check gates
# a pull request on it. This script repairs the files that predate the check.
# It reads every repository, appends the missing newline to each text file that
# lacks one, and opens one pull request for each base branch it changed.
#
# It skips a binary file and an empty file, the same two exceptions the check
# makes.
#
# The script reads and writes through the GitHub API. It never checks a
# repository out.
#
# Reads GH_TOKEN, ORG, REVIEWER, and SUPPORTED_VERSIONS from the environment.
#
# Usage:
#
#     .github/ci/scripts/fix-trailing-newlines.sh
# ---------------------------------------------------------------------------

# A bare `run:` step invokes this script, so it sets `set -e`.
# `.github/workflows/README.md` holds the rule for each family, under Scripts.
set -e

TMPFILE=$(mktemp)
trap 'rm -f "$TMPFILE"' EXIT

REPOS=$(gh repo list "$ORG" --limit 200 --json name,isArchived \
  --jq '.[] | select(.isArchived == false) | .name')

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

  while IFS= read -r BASE_BRANCH; do
    [[ -z "$BASE_BRANCH" ]] && continue

    if [[ "$BASE_BRANCH" = "master" ]]; then
      UPDATE_BRANCH="deps/fix-trailing-newlines"
    else
      UPDATE_BRANCH="deps/fix-trailing-newlines-$BASE_BRANCH"
    fi

    # `git/ref/` rather than `git/refs/`, on purpose. `git blame` this line for why.
    BRANCH_EXISTS=$(gh api "repos/$ORG/$REPO_NAME/git/ref/heads/$UPDATE_BRANCH" \
      --jq '.object.sha' 2>/dev/null) || BRANCH_EXISTS=""

    FILES_UPDATED=0
    FILES_LIST=""

    ALL_FILES=$(gh api "repos/$ORG/$REPO_NAME/git/trees/$BASE_BRANCH?recursive=1" \
      --jq '.tree[] | select(.type == "blob") | .path' 2>/dev/null || true)

    [[ -z "$ALL_FILES" ]] && continue

    while IFS= read -r FILE_PATH; do
      FILE_DATA=$(gh api "repos/$ORG/$REPO_NAME/contents/$FILE_PATH?ref=$BASE_BRANCH" \
        2>/dev/null || true)
      [[ -z "$FILE_DATA" ]] && continue

      FILE_SIZE=$(echo "$FILE_DATA" | jq -r '.size')
      [[ "$FILE_SIZE" = "0" ]] && continue
      [[ "$FILE_SIZE" -gt 1048576 ]] && continue

      FILE_SHA=$(echo "$FILE_DATA" | jq -r '.sha')
      CONTENT_B64=$(echo "$FILE_DATA" | jq -r '.content // empty' | tr -d '\n')
      [[ -z "$CONTENT_B64" ]] && continue

      echo "$CONTENT_B64" | base64 -d > "$TMPFILE" 2>/dev/null || continue

      if file --mime-encoding "$TMPFILE" 2>/dev/null | grep -q 'binary'; then
        continue
      fi

      if [[ "$(tail -c 1 "$TMPFILE" | wc -l)" -eq 1 ]]; then
        continue
      fi

      echo "  [$BASE_BRANCH] $FILE_PATH: missing trailing newline"

      if [[ -z "$BRANCH_EXISTS" ]]; then
        echo "  [$BASE_BRANCH] Creating branch $UPDATE_BRANCH..."

        BASE_SHA=$(gh api "repos/$ORG/$REPO_NAME/git/ref/heads/$BASE_BRANCH" \
          --jq '.object.sha' 2>/dev/null) || BASE_SHA=""
        if [[ -z "$BASE_SHA" ]]; then
          echo "  [$BASE_BRANCH] Could not get base branch SHA, skipping"
          break
        fi
        BRANCH_CREATE_ERR=$(gh api --method POST "repos/$ORG/$REPO_NAME/git/refs" \
          --field "ref=refs/heads/$UPDATE_BRANCH" \
          --field "sha=$BASE_SHA" 2>&1 >/dev/null || true)
        if [[ -n "$BRANCH_CREATE_ERR" ]]; then
          echo "  [$BASE_BRANCH] Branch creation failed: $BRANCH_CREATE_ERR"
          break
        fi
        echo "  [$BASE_BRANCH] Branch $UPDATE_BRANCH created."
        BRANCH_EXISTS="$BASE_SHA"
      fi

      echo "  [$BASE_BRANCH] Committing $FILE_PATH to $UPDATE_BRANCH..."

      printf '\n' >> "$TMPFILE"
      NEW_CONTENT_B64=$(base64 < "$TMPFILE" | tr -d '\n')

      PUT_BODY=$(jq -cn \
        --arg message "[Git] style: Add the missing trailing newline to $FILE_PATH." \
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
      FILES_LIST+="$FILE_PATH"$'\n'
      FILES_UPDATED=$((FILES_UPDATED + 1))
    done <<< "$ALL_FILES"

    if [[ "$FILES_UPDATED" -gt 0 ]]; then
      echo "  [$BASE_BRANCH] $FILES_UPDATED file(s) updated — checking for existing PR..."

      EXISTING_PR=$(gh pr list --repo "$ORG/$REPO_NAME" \
        --state open \
        --json headRefName \
        --jq "[.[] | select(.headRefName == \"$UPDATE_BRANCH\")] | first | .headRefName // \"\"" \
        2>/dev/null || true)

      if [[ -z "$EXISTING_PR" ]]; then
        REVIEWER_FLAGS=()
        if [[ -n "$REVIEWER" ]]; then
          REVIEWER_FLAGS=(--assignee "$REVIEWER" --reviewer "$REVIEWER")
        fi

        BODY="# Description"$'\n'$'\n'
        BODY+="Add missing trailing newlines to files in \`$REPO_NAME\`."$'\n'$'\n'
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
        while IFS= read -r file; do
          [[ -z "$file" ]] && continue
          BODY+="| \`$file\` | Added trailing newline |"$'\n'
        done <<< "$FILES_LIST"

        echo "  [$BASE_BRANCH] Creating PR from $UPDATE_BRANCH → $BASE_BRANCH..."

        if ! gh pr create \
          --repo "$ORG/$REPO_NAME" \
          --title "[Git] style: Add missing trailing newlines" \
          --body "$BODY" \
          --base "$BASE_BRANCH" \
          --head "$UPDATE_BRANCH" \
          "${REVIEWER_FLAGS[@]}" 2>/dev/null; then
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
