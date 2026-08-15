#!/usr/bin/env bash
#
# This file is part of the Valkyrja GitHub package.
#
# Copyright (c) 2016-present Melech Mizrachi
#
# Released under the MIT License. See LICENSE.md for details.
#
# ---------------------------------------------------------------------------
# Workflow reference update.
#
# A consumer repository names a reusable workflow by commit SHA. This script
# rewrites each of those references to the SHA of the source repository's
# latest release, and it opens one pull request for each base branch it
# changed.
#
# SOURCE_REPO names the repository the references point at, so the same logic
# repins a reference to `.github` or to a shared `ci-*` repository.
#
# The source repository excludes itself. It owns the templates rather than
# consumes them, and its own release pins its own references before it makes
# the tag.
#
# The script reads and writes through the GitHub API. It never checks a
# consumer repository out.
#
# Reads GH_TOKEN, ORG, SOURCE_REPO, and SUPPORTED_VERSIONS from the
# environment.
#
# Usage:
#
#     .github/ci/scripts/update-workflow-refs.sh
# ---------------------------------------------------------------------------

# A bare `run:` step invokes this script, so it sets `set -e`.
# `.github/workflows/README.md` holds the rule for each family, under Scripts.
#
# `pipefail` would change what this script does. The pipeline that decodes the
# file content ends in `base64`, and `set -e` reads that last status, so an
# earlier stage that fails is not a failure today.
set -e

# Fetch an API endpoint and echo the response only when it parses as
# JSON. An empty or non-JSON body (a network blip, or an HTML error
# page from the API edge) is transient, so retry a couple of times
# before giving up — otherwise a single bad response aborts the whole
# org-wide sweep. A JSON error body (404, 409, …) is returned as-is
# for the caller to inspect.
fetch_json() {
  local response
  local attempt

  for attempt in 1 2 3; do
    response=$(gh api "$@" 2>/dev/null || true)

    if [[ -n "$response" ]] && echo "$response" | jq -e . >/dev/null 2>&1; then
      printf '%s' "$response"
      return 0
    fi

    sleep "$attempt"
  done

  return 1
}

LATEST_TAG=$(gh api "repos/$ORG/$SOURCE_REPO/releases/latest" --jq '.tag_name')
LATEST_SHA=$(gh api "repos/$ORG/$SOURCE_REPO/commits/$LATEST_TAG" --jq '.sha')
echo "Latest $SOURCE_REPO release: $LATEST_TAG ($LATEST_SHA)"

# Escape dots in source repo name for use in sed/grep patterns
SOURCE_REPO_ESCAPED="${SOURCE_REPO//./\\.}"

# The .github repository excludes itself. It owns the templates rather than consuming
# them, and its release bakes its own references in before it makes the tag. A pull
# request from here would repin what the release already pinned, and it would name the
# release bookkeeping commit instead of the workflow-code commit the release chose.
REPOS=$(gh repo list "$ORG" --limit 200 --json name,isArchived \
  --jq '.[] | select(.isArchived == false and .name != ".github") | .name')

# Repositories the sweep could not finish. A single unreadable API
# response must never abort the loop and strand every repository after
# it on the previous release, so each failure is recorded here and
# reported once at the end, which fails the job while still leaving
# every other repository updated.
SKIPPED_REPOS=""

skip_repo() {
  local repo="$1" reason="$2"

  echo "  $reason, skipping"
  SKIPPED_REPOS="$SKIPPED_REPOS"$'\n'"  - $repo: $reason"
}

while IFS= read -r REPO_NAME; do
  echo "Checking $ORG/$REPO_NAME..."

  WORKFLOW_DIR=$(fetch_json "repos/$ORG/$REPO_NAME/contents/.github/workflows") || {
    skip_repo "$REPO_NAME" "Could not read the workflow directory"
    continue
  }
  WORKFLOW_FILES=$(echo "$WORKFLOW_DIR" \
    | jq -r 'if type == "array" then .[].path else empty end' \
    2>/dev/null || true)

  [[ -z "$WORKFLOW_FILES" ]] && continue

  BRANCH_DATA=$(fetch_json "repos/$ORG/$REPO_NAME/branches" --paginate) || {
    skip_repo "$REPO_NAME" "Could not read the branch list"
    continue
  }
  ALL_BRANCHES=$(echo "$BRANCH_DATA" | jq -r '.[]?.name' 2>/dev/null || true)

  if [[ -z "$ALL_BRANCHES" ]]; then
    skip_repo "$REPO_NAME" "Could not parse the branch list"
    continue
  fi

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
      UPDATE_BRANCH="deps/update-${SOURCE_REPO}-workflow-refs"
    else
      UPDATE_BRANCH="deps/update-${SOURCE_REPO}-workflow-refs-$BASE_BRANCH"
    fi

    # `git/ref/` rather than `git/refs/`, on purpose. `git blame` this line for why.
    BRANCH_EXISTS=$(gh api "repos/$ORG/$REPO_NAME/git/ref/heads/$UPDATE_BRANCH" \
      --jq '.object.sha' 2>/dev/null) || BRANCH_EXISTS=""

    FILES_UPDATED=0
    FILES_LIST=""

    while IFS= read -r FILE_PATH; do
      READ_REF="$BASE_BRANCH"
      [[ -n "$BRANCH_EXISTS" ]] && READ_REF="$UPDATE_BRANCH"
      FILE_DATA=$(fetch_json "repos/$ORG/$REPO_NAME/contents/$FILE_PATH?ref=$READ_REF" || true)
      [[ -z "$FILE_DATA" ]] && continue

      FILE_SHA=$(echo "$FILE_DATA" | jq -r '.sha // empty' 2>/dev/null || true)
      [[ -z "$FILE_SHA" ]] && continue

      CONTENT=$(echo "$FILE_DATA" | jq -r '.content // empty' 2>/dev/null | base64 -d 2>/dev/null || true)
      [[ -z "$CONTENT" ]] && continue

      if ! echo "$CONTENT" | grep -q "valkyrjaio/$SOURCE_REPO_ESCAPED/"; then
        continue
      fi

      # shellcheck disable=SC2001 # A capture group carries the workflow path, and `${var//}` has none.
      NEW_CONTENT=$(echo "$CONTENT" | sed "s|valkyrjaio/$SOURCE_REPO_ESCAPED/\([^@]*\)@[^[:space:]]*|valkyrjaio/$SOURCE_REPO/\1@$LATEST_SHA|g")

      if [[ "$CONTENT" = "$NEW_CONTENT" ]]; then
        echo "  [$BASE_BRANCH] $FILE_PATH: already up to date"
        continue
      fi

      echo "  [$BASE_BRANCH] $FILE_PATH: updating to $LATEST_TAG"

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

      NEW_CONTENT_B64=$(printf '%s\n' "$NEW_CONTENT" | base64 | tr -d '\n')

      PUT_BODY=$(jq -cn \
        --arg message "[Workflow] ci: Update $SOURCE_REPO workflow refs to $LATEST_TAG." \
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
    done <<< "$WORKFLOW_FILES"

    PR_NEEDED=0

    if [[ "$FILES_UPDATED" -gt 0 ]]; then
      PR_NEEDED=1
      echo "  [$BASE_BRANCH] $FILES_UPDATED file(s) updated — checking for existing PR..."
    elif [[ -n "$BRANCH_EXISTS" ]]; then
      # An earlier run may have committed to the update branch and then
      # died before opening the PR. Its files already carry the new ref,
      # so nothing is left to update and FILES_UPDATED stays 0 — recover
      # the branch here rather than orphaning it forever.
      COMPARE=$(fetch_json "repos/$ORG/$REPO_NAME/compare/$BASE_BRANCH...$UPDATE_BRANCH") || COMPARE=""

      AHEAD_BY=$(echo "$COMPARE" | jq -r '.ahead_by // 0' 2>/dev/null || echo 0)
      case "$AHEAD_BY" in
        ''|*[!0-9]*) AHEAD_BY=0 ;;
        *) ;;
      esac

      if [[ -n "$COMPARE" ]] && [[ "$AHEAD_BY" -gt 0 ]]; then
        PR_NEEDED=1
        FILES_LIST=$(echo "$COMPARE" | jq -r '.files[]?.filename' 2>/dev/null || true)
        echo "  [$BASE_BRANCH] $UPDATE_BRANCH is ahead of $BASE_BRANCH — checking for existing PR..."
      fi
    fi

    if [[ "$PR_NEEDED" -eq 1 ]]; then
      EXISTING_PR=$(gh pr list --repo "$ORG/$REPO_NAME" \
        --state open \
        --json number,headRefName,title \
        --jq "[.[] | select(.headRefName == \"$UPDATE_BRANCH\")] | first // \"\"" \
        2>/dev/null || true)

      BODY=""
      BODY+="# Description"$'\n'$'\n'
      BODY+="Update reusable workflow references from \`valkyrjaio/$SOURCE_REPO\` to release \`$LATEST_TAG\`."$'\n'$'\n'
      BODY+="## Types of changes"$'\n'$'\n'
      BODY+="- [X] Improvement _(non-breaking change which improves code)_"$'\n'
      BODY+="- [ ] Bug fix _(non-breaking change which fixes an issue)_"$'\n'
      BODY+="- [ ] New feature _(non-breaking change which adds functionality)_"$'\n'
      BODY+="- [ ] Deprecation _(breaking change which removes functionality)_"$'\n'
      BODY+="- [ ] Breaking change _(fix or feature that would cause existing functionality to change)_"$'\n'
      BODY+="- [ ] Documentation improvement"$'\n'$'\n'
      BODY+="## Changes"$'\n'$'\n'
      BODY+="| File | Updated To |"$'\n'
      BODY+="|------|------------|"$'\n'
      while IFS= read -r file; do
        [[ -z "$file" ]] && continue
        BODY+="| \`$file\` | \`$LATEST_TAG\` |"$'\n'
      done <<< "$FILES_LIST"

      NEW_TITLE="[Workflow] ci: Update $SOURCE_REPO workflow refs to $LATEST_TAG"

      if [[ -z "$EXISTING_PR" ]]; then
        echo "  [$BASE_BRANCH] Creating PR from $UPDATE_BRANCH → $BASE_BRANCH..."
        if ! gh pr create \
          --repo "$ORG/$REPO_NAME" \
          --title "$NEW_TITLE" \
          --body "$BODY" \
          --base "$BASE_BRANCH" \
          --head "$UPDATE_BRANCH" 2>/dev/null; then
          echo "  [$BASE_BRANCH] PR creation failed, skipping"
        else
          echo "  [$BASE_BRANCH] PR created."
        fi
      else
        PR_NUMBER=$(echo "$EXISTING_PR" | jq -r '.number // empty' 2>/dev/null || true)
        CURRENT_TITLE=$(echo "$EXISTING_PR" | jq -r '.title // empty' 2>/dev/null || true)
        if [[ -z "$PR_NUMBER" ]]; then
          echo "  [$BASE_BRANCH] Could not read the existing PR, skipping"
        elif [[ "$CURRENT_TITLE" != "$NEW_TITLE" ]]; then
          echo "  [$BASE_BRANCH] Updating PR #$PR_NUMBER title to reflect $LATEST_TAG..."
          gh pr edit "$PR_NUMBER" --repo "$ORG/$REPO_NAME" \
            --title "$NEW_TITLE" --body "$BODY" 2>/dev/null || true
        else
          echo "  [$BASE_BRANCH] PR already exists and title is current, skipping."
        fi
      fi
    fi
  done <<< "$BASE_BRANCHES"
done <<< "$REPOS"

if [[ -n "$SKIPPED_REPOS" ]]; then
  echo "::error::Some repositories were not updated to $LATEST_TAG:$SKIPPED_REPOS"
  exit 1
fi

echo "All repositories processed for $LATEST_TAG."
