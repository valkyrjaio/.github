#!/usr/bin/env bash
#
# This file is part of the Valkyrja GitHub package.
#
# Copyright (c) 2016-present Melech Mizrachi
#
# Released under the MIT License. See LICENSE.md for details.
#
# ---------------------------------------------------------------------------
# Bot pull request auto merge.
#
# This script sweeps every repository in the organization and merges the bot's
# own pull requests once each one qualifies. A pull request merges only when
# the author, the title root, the base branch, the head branch, every changed
# path, and every required status check all pass. Anything else stays open for
# a person, and the script requests a review from REVIEWER on it — the
# generators request nobody at creation, so this is how that person hears
# about the one pull request that did not merge on its own.
#
# The app bypasses the required-status-check rulesets, so GitHub holds no merge
# open on its behalf. The script therefore applies the check gate itself,
# against the contexts the branch's own ruleset names.
#
# The script writes a summary table to GITHUB_STEP_SUMMARY. It exits 1 when a
# pull request touched a path outside its allowlist, because that means a
# generator started writing files nobody expected.
#
# Reads GH_TOKEN, ORG, BOT_LOGIN, ENABLED_TYPES, EXCLUDE_REPOS,
# SUPPORTED_VERSIONS, REVIEWER, DRY_RUN, SINGLE_REPO, and GITHUB_STEP_SUMMARY
# from the environment.
#
# Usage:
#
#     .github/ci/scripts/auto-merge-bot-prs.sh
# ---------------------------------------------------------------------------

# Warning: `-u` and `pipefail` are deliberately absent. A GitHub Actions `run:`
# block runs under `bash -e` alone, and this script holds the block that ran
# there. `pipefail` would change what the script does, because a pipeline here
# takes its status from the last stage and an earlier stage that fails is not
# a failure today.
set -e

# Every gate below is required rather than defaulted. A default here
# would decide, silently and org-wide, which author's pull requests
# merge without a human — the one decision that must never be
# inherited from a workflow file nobody re-reads.
if [[ -z "$BOT_LOGIN" ]]; then
  echo "bot-login is empty. Refusing to merge without an explicit author to match."
  exit 1
fi

if [[ -z "$ENABLED_TYPES" ]]; then
  echo "types is empty. Refusing to merge without an explicit set of title roots."
  exit 1
fi

if [[ -z "$SUPPORTED_VERSIONS" ]]; then
  echo "SUPPORTED_VERSIONS is not set. Refusing to sweep without a version filter."
  exit 1
fi

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

type_enabled() {
  local type="$1"

  case ",$ENABLED_TYPES," in
    *",$type,"*) return 0 ;;
    *) ;;
  esac
  return 1
}

repo_excluded() {
  local repo="$1"

  case ",$EXCLUDE_REPOS," in
    *",$repo,"*) return 0 ;;
    *) ;;
  esac
  return 1
}

# The bounds on what a bot pull request may touch. The generators use
# `git add -A` after running a package manager, so nothing upstream
# constrains the file set — whatever the tool rewrote gets committed.
# This is the only place that constraint exists, which is why it is
# expressed as an allowlist of shapes rather than a denylist: a path
# nobody anticipated blocks the merge instead of riding along with it.
path_allowed() {
  local type="$1"
  local path="$2"

  case "$type" in
    Workflow)
      # Callers under .github/workflows, and the templates in
      # required-workflows that seed them. Both carry pinned refs.
      [[ "$path" =~ ^\.github/workflows/[^/]+\.yml$ ]] && return 0
      [[ "$path" =~ ^required-workflows/([^/]+/)?[^/]+\.yml$ ]] && return 0
      ;;
    Dependency)
      # Manifests and lock files only, at any depth — the per-tool CI
      # directories each carry their own pair. Basename matching keeps
      # nested layouts (app/build.gradle.kts, .github/ci/*/composer.json)
      # in scope without enumerating every directory.
      case "$(basename "$path")" in
        composer.json|composer.lock) return 0 ;;
        package.json|package-lock.json) return 0 ;;
        build.gradle.kts) return 0 ;;
        pyproject.toml|uv.lock) return 0 ;;
        go.mod|go.sum) return 0 ;;
        *) ;;
      esac
      ;;
    *) ;;
  esac

  return 1
}

if [[ -n "$SINGLE_REPO" ]]; then
  REPOS="$SINGLE_REPO"
else
  REPOS=$(gh repo list "$ORG" --limit 200 --json name,isArchived \
    --jq '.[] | select(.isArchived == false) | .name')
fi

MERGED=0
WAITING=0
BLOCKED=0
VIOLATIONS=0
ERRORS=0
MERGED_LIST=""
ATTENTION_LIST=""

# The summary is where a person goes after the sweep, and every row it
# holds is a row someone has to open — a merge to confirm, a failure to
# chase. A bare `#213` is a number to copy into a search box, so both
# tables carry the repository and the pull request as links instead.
repo_link() {
  local repo="$1"

  # shellcheck disable=SC2016 # The backticks are Markdown, not a command substitution.
  printf '[`%s`](https://github.com/%s/%s)' "$repo" "$ORG" "$repo"
}

pr_link() {
  local repo="$1" number="$2"

  printf '[#%s](https://github.com/%s/%s/pull/%s)' "$number" "$ORG" "$repo" "$number"
}

note_merged() {
  local repo="$1" number="$2" note="$3"

  MERGED_LIST="$MERGED_LIST"$'\n'"| $(repo_link "$repo") | $(pr_link "$repo" "$number") | $note |"
}

# The generators request no reviewer when they open a pull request,
# because a pull request that merges on its own needs nobody's time. A
# pull request in the attention table is the one that could not, so a
# person must look at it — and the step summary of an hourly sweep is
# not where a person looks. The review request is the notification.
#
# Warning: GitHub notifies on every repeat request, and the sweep runs
# hourly. The function therefore skips a pull request where the
# reviewer is already requested or has already reviewed, so a pull
# request that stays broken pings the person once, not once an hour.
request_reviewer() {
  local repo="$1" number="$2"
  local reviewer_lower login existing

  [[ -z "$REVIEWER" ]] && return 0
  [[ "$DRY_RUN" = "true" ]] && return 0

  reviewer_lower=$(printf '%s' "$REVIEWER" | tr '[:upper:]' '[:lower:]')

  # A failed read leaves the list empty and the request goes out again.
  # The worst case is one extra notification, so the read does not gate
  # the sweep the way fetch_json does elsewhere.
  existing=$(gh pr view "$number" --repo "$ORG/$repo" \
    --json reviewRequests,reviews \
    --jq '(.reviewRequests[]?.login // empty), (.reviews[]?.author.login // empty)' \
    2>/dev/null || true)

  while IFS= read -r login; do
    [[ -z "$login" ]] && continue
    if [[ "$(printf '%s' "$login" | tr '[:upper:]' '[:lower:]')" == "$reviewer_lower" ]]; then
      return 0
    fi
  done <<< "$existing"

  if gh pr edit "$number" --repo "$ORG/$repo" --add-reviewer "$REVIEWER" >/dev/null 2>&1; then
    echo "  #$number: requested review from $REVIEWER."
  else
    echo "  #$number: could not request review from $REVIEWER."
  fi
}

note_attention() {
  local repo="$1" number="$2" note="$3"

  ATTENTION_LIST="$ATTENTION_LIST"$'\n'"| $(repo_link "$repo") | $(pr_link "$repo" "$number") | $note |"
  request_reviewer "$repo" "$number"
}

while IFS= read -r REPO_NAME; do
  [[ -z "$REPO_NAME" ]] && continue

  if repo_excluded "$REPO_NAME"; then
    echo "$ORG/$REPO_NAME: excluded, skipping."
    continue
  fi

  OPEN_PRS=$(gh pr list --repo "$ORG/$REPO_NAME" --state open --limit 100 \
    --json number,title,author,baseRefName,headRefName,isDraft \
    --jq '.[] | select(.author.is_bot == true and .author.login == env.BOT_LOGIN and .isDraft == false) | @json' \
    2>/dev/null || true)

  [[ -z "$OPEN_PRS" ]] && continue

  echo "$ORG/$REPO_NAME:"

  while IFS= read -r PR_JSON; do
    [[ -z "$PR_JSON" ]] && continue

    PR_NUMBER=$(echo "$PR_JSON" | jq -r '.number')
    PR_TITLE=$(echo "$PR_JSON" | jq -r '.title')
    BASE_BRANCH=$(echo "$PR_JSON" | jq -r '.baseRefName')
    HEAD_BRANCH=$(echo "$PR_JSON" | jq -r '.headRefName')

    # The title root is what classifies the pull request, and it is
    # also what the commit-message check already enforces, so it is a
    # shape the repository guarantees rather than one assumed here.
    PR_TYPE=$(echo "$PR_TITLE" | sed -n 's/^\[\([A-Za-z]*\)\].*/\1/p')

    if [[ -z "$PR_TYPE" ]] || ! type_enabled "$PR_TYPE"; then
      continue
    fi

    # Release branches only. A release is never cut from master, and
    # nothing should land there unattended either.
    if [[ ! "$BASE_BRANCH" =~ ^([0-9]+)\.x$ ]]; then
      echo "  #$PR_NUMBER targets $BASE_BRANCH, skipping."
      continue
    fi

    if [[ ! "${BASH_REMATCH[1]}" =~ $SUPPORTED_VERSIONS ]]; then
      echo "  #$PR_NUMBER targets unsupported $BASE_BRANCH, skipping."
      continue
    fi

    if [[ ! "$HEAD_BRANCH" =~ ^deps/ ]]; then
      echo "  #$PR_NUMBER: head $HEAD_BRANCH is not a deps/ branch, needs a look."
      note_attention "$REPO_NAME" "$PR_NUMBER" "Unexpected head branch \`$HEAD_BRANCH\`"
      VIOLATIONS=$((VIOLATIONS + 1))
      continue
    fi

    CHANGED=$(fetch_json "repos/$ORG/$REPO_NAME/pulls/$PR_NUMBER/files?per_page=100") || {
      echo "  #$PR_NUMBER: could not read changed files, skipping."
      ERRORS=$((ERRORS + 1))
      continue
    }

    OFFENDING=""
    while IFS= read -r CHANGED_PATH; do
      [[ -z "$CHANGED_PATH" ]] && continue
      if ! path_allowed "$PR_TYPE" "$CHANGED_PATH"; then
        OFFENDING="$OFFENDING $CHANGED_PATH"
      fi
    done < <(echo "$CHANGED" | jq -r '.[]?.filename')

    if [[ -n "$OFFENDING" ]]; then
      echo "  #$PR_NUMBER touches paths outside the $PR_TYPE allowlist:$OFFENDING"
      note_attention "$REPO_NAME" "$PR_NUMBER" "Touches \`$(echo "$OFFENDING" | xargs | tr ' ' ',')\`"
      VIOLATIONS=$((VIOLATIONS + 1))
      continue
    fi

    # The app bypasses the required-status-check rulesets, so GitHub
    # will not hold a merge open on its behalf. The gate has to be
    # applied here instead, against the same contexts the ruleset
    # names — which also keeps advisory checks (SonarCloud, Coveralls,
    # Scrutinizer) from blocking a merge they were never meant to gate.
    REQUIRED_JSON=$(fetch_json "repos/$ORG/$REPO_NAME/rules/branches/$BASE_BRANCH") || {
      echo "  #$PR_NUMBER: could not read branch rules, skipping."
      ERRORS=$((ERRORS + 1))
      continue
    }

    REQUIRED_CONTEXTS=$(echo "$REQUIRED_JSON" \
      | jq -r '[.[]? | select(.type == "required_status_checks")
          | .parameters.required_status_checks[]?.context] | unique | .[]')

    if [[ -z "$REQUIRED_CONTEXTS" ]]; then
      echo "  #$PR_NUMBER: $BASE_BRANCH requires no status checks, leaving it alone."
      note_attention "$REPO_NAME" "$PR_NUMBER" "No required status checks on \`$BASE_BRANCH\`"
      BLOCKED=$((BLOCKED + 1))
      continue
    fi

    ROLLUP=$(gh pr view "$PR_NUMBER" --repo "$ORG/$REPO_NAME" \
      --json statusCheckRollup \
      --jq '[.statusCheckRollup[]? | {name: (.name // .context), result: (.conclusion // .state)}]' \
      2>/dev/null || true)

    if [[ -z "$ROLLUP" ]]; then
      echo "  #$PR_NUMBER: no checks reported yet, waiting."
      WAITING=$((WAITING + 1))
      continue
    fi

    PENDING=""
    FAILING=""
    while IFS= read -r CONTEXT; do
      [[ -z "$CONTEXT" ]] && continue
      RESULT=$(echo "$ROLLUP" | jq -r --arg c "$CONTEXT" \
        '[.[] | select(.name == $c) | .result] | last // "MISSING"')
      case "$RESULT" in
        SUCCESS) ;;
        MISSING|PENDING|EXPECTED|null|"") PENDING="$PENDING $CONTEXT" ;;
        *) FAILING="$FAILING $CONTEXT($RESULT)" ;;
      esac
    done <<< "$REQUIRED_CONTEXTS"

    if [[ -n "$FAILING" ]]; then
      echo "  #$PR_NUMBER: required checks failing:$FAILING"
      note_attention "$REPO_NAME" "$PR_NUMBER" "Failing:$FAILING"
      BLOCKED=$((BLOCKED + 1))
      continue
    fi

    if [[ -n "$PENDING" ]]; then
      echo "  #$PR_NUMBER: waiting on$PENDING"
      WAITING=$((WAITING + 1))
      continue
    fi

    if [[ "$DRY_RUN" = "true" ]]; then
      echo "  [dry run] would merge #$PR_NUMBER — $PR_TITLE"
      note_merged "$REPO_NAME" "$PR_NUMBER" "$PR_TITLE"
      MERGED=$((MERGED + 1))
      continue
    fi

    # Mergeability is computed lazily and reads UNKNOWN until GitHub
    # gets around to it, so asking first would just add a round trip
    # that answers nothing. The merge call is the authority: a branch
    # that cannot merge fails here and is reported.
    MERGE_ERR=$(gh pr merge "$PR_NUMBER" --repo "$ORG/$REPO_NAME" --squash 2>&1 >/dev/null || true)

    if [[ -n "$MERGE_ERR" ]]; then
      echo "  #$PR_NUMBER: merge failed: $MERGE_ERR"
      note_attention "$REPO_NAME" "$PR_NUMBER" "Merge failed"
      BLOCKED=$((BLOCKED + 1))
      continue
    fi

    echo "  #$PR_NUMBER merged — $PR_TITLE"
    note_merged "$REPO_NAME" "$PR_NUMBER" "$PR_TITLE"
    MERGED=$((MERGED + 1))
  done <<< "$OPEN_PRS"
done <<< "$REPOS"

{
  echo "### Auto merge bot pull requests"
  echo
  if [[ "$DRY_RUN" = "true" ]]; then
    echo "Dry run — nothing was merged."
    echo
  fi
  echo "Types: \`$ENABLED_TYPES\`"
  echo
  echo "| Result | Count |"
  echo "|--------|-------|"
  echo "| Merged | $MERGED |"
  echo "| Waiting on checks | $WAITING |"
  echo "| Blocked | $BLOCKED |"
  echo "| Outside the allowlist | $VIOLATIONS |"
  echo "| Errors | $ERRORS |"

  if [[ -n "$MERGED_LIST" ]]; then
    echo
    echo "#### Merged"
    echo
    echo "| Repository | PR | Title |"
    echo "|------------|----|-------|"
    printf '%s\n' "${MERGED_LIST#$'\n'}"
  fi

  if [[ -n "$ATTENTION_LIST" ]]; then
    echo
    echo "#### Needs a look"
    echo
    echo "| Repository | PR | Reason |"
    echo "|------------|----|--------|"
    printf '%s\n' "${ATTENTION_LIST#$'\n'}"
  fi
} >> "$GITHUB_STEP_SUMMARY"

# A pull request outside the allowlist means a generator started
# writing files nobody expected, which is worth interrupting someone
# over. Checks that merely fail are the gate doing its job, and a
# transient API error resolves itself on the next run, so neither
# fails the sweep.
if [[ "$VIOLATIONS" -gt 0 ]]; then
  echo "$VIOLATIONS pull request(s) touched paths outside the allowlist."
  exit 1
fi
