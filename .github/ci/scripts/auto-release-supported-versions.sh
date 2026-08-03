#!/usr/bin/env bash
#
# This file is part of the Valkyrja GitHub package.
#
# Copyright (c) 2016-present Melech Mizrachi
#
# Released under the MIT License. See LICENSE.md for details.
#
# ---------------------------------------------------------------------------
# Auto release sweep across supported version branches.
#
# This script dispatches each repository's own release workflow on every `??.x`
# branch whose major matches SUPPORTED_VERSIONS. It never dispatches to
# `master`, because a release is never cut from `master`.
#
# The sweep releases in tiers, and it waits for each tier before it starts the
# next one. A dependency therefore always ships before the repository that
# consumes it. Between tiers the sweep can refresh each repository's
# dependencies, so a dependent carries the version its dependency just
# published.
#
# The script reads and writes through the GitHub API. It never checks a
# released repository out.
#
# Reads GH_TOKEN, ORG, SUPPORTED_VERSIONS, TIERS, REFRESH_DEPENDENCIES,
# STAGE_TIMEOUT_MINUTES, DRY_RUN, SINGLE_REPO, THIS_REPO, THIS_REF, and
# GITHUB_STEP_SUMMARY from the environment.
#
# Usage:
#
#     .github/ci/scripts/auto-release-supported-versions.sh
# ---------------------------------------------------------------------------

# Warning: `-u` and `pipefail` are deliberately absent. A GitHub Actions `run:`
# block that names no shell runs under `bash -e {0}`, and this script holds the
# block that ran there. The `bash --noprofile --norc -eo pipefail {0}` form is
# what an explicit `shell: bash` selects, which is why a script that
# `run-script` invokes sets `pipefail` and this one does not.
set -e

if [ -z "$SUPPORTED_VERSIONS" ]; then
  echo "SUPPORTED_VERSIONS is not set. Refusing to sweep without a version filter."
  exit 1
fi

if [ -z "${TIERS// /}" ]; then
  echo "tiers is empty. Refusing to sweep without a release order."
  exit 1
fi

POLL_SECONDS=20
STAGE_TIMEOUT=$((STAGE_TIMEOUT_MINUTES * 60))

TIER_COUNT=0
while IFS= read -r line; do
  [ -z "${line// /}" ] && continue
  TIER_COUNT=$((TIER_COUNT + 1))
done <<< "$TIERS"

# A repository no tier names still has to release, so it goes last —
# after everything that anything could depend on has already shipped.
UNMATCHED_TIER=$((TIER_COUNT + 1))

tier_of() {
  local name="$1" idx=0 line pattern

  while IFS= read -r line; do
    [ -z "${line// /}" ] && continue
    idx=$((idx + 1))
    for pattern in $line; do
      case "$name" in
        $pattern) echo "$idx"; return 0 ;;
      esac
    done
  done <<< "$TIERS"

  echo "$UNMATCHED_TIER"
}

now_utc() { date -u +%Y-%m-%dT%H:%M:%SZ; }

# Wait for the run this sweep just started. `gh workflow run` does not
# report a run id, so the run is the newest one on that workflow and
# branch created at or after the dispatch. Both timestamps are UTC in
# the same format, so a string comparison orders them correctly.
# Echoes the run conclusion, or `timeout` / `missing`.
wait_for_dispatch() {
  local repo="$1" workflow="$2" branch="$3" since="$4" deadline="${5:-$STAGE_TIMEOUT}"
  local run_id="" waited=0 status

  while [ "$waited" -lt "$deadline" ]; do
    if [ -z "$run_id" ]; then
      run_id=$(gh run list --repo "$ORG/$repo" --workflow "$workflow" --branch "$branch" \
        --limit 20 --json databaseId,createdAt \
        --jq "[.[] | select(.createdAt >= \"$since\")] | sort_by(.createdAt) | last | .databaseId // empty" \
        2>/dev/null || true)
    fi

    if [ -n "$run_id" ]; then
      status=$(gh run view "$run_id" --repo "$ORG/$repo" --json status,conclusion \
        --jq '"\(.status)|\(.conclusion // "")"' 2>/dev/null || true)
      case "$status" in
        completed\|*) echo "${status#completed|}"; return 0 ;;
      esac
    fi

    sleep "$POLL_SECONDS"
    waited=$((waited + POLL_SECONDS))
  done

  if [ -n "$run_id" ]; then echo "timeout"; else echo "missing"; fi
}

release_branches_for() {
  local repo="$1" all b major out=""

  all=$(gh api "repos/$ORG/$repo/branches" --paginate --jq '.[].name' 2>/dev/null || true)

  while IFS= read -r b; do
    if [[ "$b" =~ ^([0-9]+)\.x$ ]]; then
      major="${BASH_REMATCH[1]}"
      if [[ "$major" =~ $SUPPORTED_VERSIONS ]]; then
        out="$out"$'\n'"$b"
      fi
    fi
  done <<< "$all"

  # Deliberately no fallback to master. The sibling sweeps fall back to it
  # when a repo has no version branch, but a release must never be cut from
  # master: master is where the next year is prepared, and `rc` is the only
  # release type that comes from there. Keeping master out of reach here is
  # what makes the RC path unreachable from automation by construction
  # rather than by a conditional someone could get wrong.
  printf '%s' "$out"
}

if [ -n "$SINGLE_REPO" ]; then
  REPOS="$SINGLE_REPO"
else
  REPOS=$(gh repo list "$ORG" --limit 200 --json name,isArchived \
    --jq '.[] | select(.isArchived == false) | .name')
fi

# Collect the work before the tier loop runs, so that loop dispatches
# rather than discovers. A repository appears once per version branch.
WORK=""
SKIPPED_NO_WORKFLOW=0
SKIPPED_NO_BRANCH=0

while IFS= read -r REPO_NAME; do
  [ -z "$REPO_NAME" ] && continue

  WORKFLOW_EXISTS=$(gh api "repos/$ORG/$REPO_NAME/contents/.github/workflows/release-new-version.yml" \
    --jq '.name' 2>/dev/null || true)

  if [ -z "$WORKFLOW_EXISTS" ]; then
    SKIPPED_NO_WORKFLOW=$((SKIPPED_NO_WORKFLOW + 1))
    continue
  fi

  BRANCHES=$(release_branches_for "$REPO_NAME")

  if [ -z "$(printf '%s' "$BRANCHES" | tr -d '[:space:]')" ]; then
    echo "$ORG/$REPO_NAME: no supported version branch, skipping."
    SKIPPED_NO_BRANCH=$((SKIPPED_NO_BRANCH + 1))
    continue
  fi

  TIER=$(tier_of "$REPO_NAME")

  while IFS= read -r BRANCH; do
    [ -z "$BRANCH" ] && continue
    WORK="$WORK"$'\n'"$TIER $REPO_NAME $BRANCH"
  done <<< "$BRANCHES"
done <<< "$REPOS"

DISPATCHED=0
RELEASED=0
FAILED=0
TIMED_OUT=0
RESULTS=""

for TIER in $(seq 1 "$UNMATCHED_TIER"); do
  TIER_WORK=$(printf '%s\n' "$WORK" | awk -v t="$TIER" '$1 == t')
  [ -z "$(printf '%s' "$TIER_WORK" | tr -d '[:space:]')" ] && continue

  echo "::group::Tier $TIER"
  printf '%s\n' "$TIER_WORK" | awk 'NF {print "  " $2 " (" $3 ")"}'

  if [ "$DRY_RUN" = "true" ]; then
    while read -r _ REPO_NAME BRANCH; do
      [ -z "$REPO_NAME" ] && continue
      echo "  [dry run] would release $REPO_NAME on $BRANCH"
      RESULTS="$RESULTS"$'\n'"| $TIER | \`$REPO_NAME\` | $BRANCH | dry run |"
      DISPATCHED=$((DISPATCHED + 1))
    done <<< "$TIER_WORK"
    echo "::endgroup::"
    continue
  fi

  # A tier depends only on the tiers before it, so what it needs has
  # already shipped by the time this runs. Its manifest still names the
  # previous version though, and the release gate refuses to release
  # against an outdated direct dependency. The refresh here is what
  # lets a dependent release in the same pass as its dependency.
  if [ "$REFRESH_DEPENDENCIES" = "true" ] && [ "$TIER" -gt 1 ]; then
    REFRESH_SINCE=$(now_utc)
    REFRESHED=""

    while read -r _ REPO_NAME BRANCH; do
      [ -z "$REPO_NAME" ] && continue

      HAS_UPDATE=$(gh api "repos/$ORG/$REPO_NAME/contents/.github/workflows/update-dependencies.yml" \
        --jq '.name' 2>/dev/null || true)
      [ -z "$HAS_UPDATE" ] && continue

      if gh workflow run update-dependencies.yml --repo "$ORG/$REPO_NAME" --ref "$BRANCH" \
           >/dev/null 2>&1; then
        echo "  Refreshing dependencies: $REPO_NAME ($BRANCH)"
        REFRESHED="$REFRESHED"$'\n'"$REPO_NAME $BRANCH"
      else
        echo "  Could not trigger update-dependencies on $REPO_NAME ($BRANCH)"
      fi
    done <<< "$TIER_WORK"

    while read -r REPO_NAME BRANCH; do
      [ -z "$REPO_NAME" ] && continue
      OUTCOME=$(wait_for_dispatch "$REPO_NAME" "update-dependencies.yml" "$BRANCH" "$REFRESH_SINCE")
      echo "  Dependency refresh $REPO_NAME ($BRANCH): $OUTCOME"
    done <<< "$REFRESHED"

    # The auto-merge sweep lands the bump, gated on the allowlist and
    # the required checks it applies everywhere else. Calling it here
    # rather than merging directly keeps one definition of what may
    # merge unattended. It repeats because the bump pull request has to
    # go green first, and its checks start only once the refresh above
    # has pushed.
    if [ -n "$(printf '%s' "$REFRESHED" | tr -d '[:space:]')" ]; then
      # Measured against the clock rather than counted in iterations.
      # Each pass also waits on a dispatched run, so crediting a fixed
      # amount per pass would undercount the time the pass really took
      # and let this block run far past the stage timeout it claims to
      # honor. The remaining budget also bounds the inner wait, so the
      # whole block stays inside one stage timeout.
      MERGE_START=$(date +%s)
      MERGE_REMAINING=$STAGE_TIMEOUT

      while [ "$MERGE_REMAINING" -gt 0 ]; do
        MERGE_SINCE=$(now_utc)
        gh workflow run auto-merge-bot-prs.yml --repo "$ORG/$THIS_REPO" \
          --ref "$THIS_REF" >/dev/null 2>&1 || true
        wait_for_dispatch "$THIS_REPO" "auto-merge-bot-prs.yml" "$THIS_REF" \
          "$MERGE_SINCE" "$MERGE_REMAINING" >/dev/null

        STILL_OPEN=0
        STILL_RUNNING=0

        while read -r REPO_NAME BRANCH; do
          [ -z "$REPO_NAME" ] && continue

          OPEN_PRS=$(gh pr list --repo "$ORG/$REPO_NAME" --state open --base "$BRANCH" \
            --json number,title \
            --jq '.[] | select(.title | startswith("[Dependency]")) | .number' \
            2>/dev/null || true)

          while IFS= read -r PR_NUMBER; do
            [ -z "$PR_NUMBER" ] && continue
            STILL_OPEN=$((STILL_OPEN + 1))

            # A pull request whose checks have not all reported cannot
            # have been judged yet, so the wait is still worth it.
            UNSETTLED=$(gh pr checks "$PR_NUMBER" --repo "$ORG/$REPO_NAME" \
              --json bucket --jq '[.[] | select(.bucket == "pending")] | length' \
              2>/dev/null || echo 1)
            case "$UNSETTLED" in ''|*[!0-9]*) UNSETTLED=1 ;; esac
            [ "$UNSETTLED" -gt 0 ] && STILL_RUNNING=$((STILL_RUNNING + 1))
          done <<< "$OPEN_PRS"
        done <<< "$REFRESHED"

        [ "$STILL_OPEN" -eq 0 ] && break

        # Every remaining pull request has had its checks reported and
        # the auto-merge sweep still left it open. It declines for a
        # reason it will keep having — a failing check, a path outside
        # the allowlist, a repository it excludes — so more waiting
        # cannot change the answer. Release anyway and let the
        # outdated-dependency gate be the one to object.
        if [ "$STILL_RUNNING" -eq 0 ]; then
          echo "  $STILL_OPEN dependency pull request(s) will not land on their own; continuing."
          break
        fi

        echo "  $STILL_OPEN dependency pull request(s) not landed yet, waiting."
        sleep "$POLL_SECONDS"
        MERGE_REMAINING=$((STAGE_TIMEOUT - ($(date +%s) - MERGE_START)))
      done
    fi
  fi

  RELEASE_SINCE=$(now_utc)
  TIER_DISPATCHED=""

  while read -r _ REPO_NAME BRANCH; do
    [ -z "$REPO_NAME" ] && continue

    TRIGGER_ERR=$(gh workflow run release-new-version.yml \
      --repo "$ORG/$REPO_NAME" \
      --ref "$BRANCH" \
      -f bump=auto 2>&1 >/dev/null || true)

    if [ -n "$TRIGGER_ERR" ]; then
      echo "  Failed to dispatch $REPO_NAME on $BRANCH: $TRIGGER_ERR"
      RESULTS="$RESULTS"$'\n'"| $TIER | \`$REPO_NAME\` | $BRANCH | dispatch failed |"
      FAILED=$((FAILED + 1))
      continue
    fi

    echo "  Dispatched bump=auto on $REPO_NAME ($BRANCH)."
    DISPATCHED=$((DISPATCHED + 1))
    TIER_DISPATCHED="$TIER_DISPATCHED"$'\n'"$REPO_NAME $BRANCH"
  done <<< "$TIER_WORK"

  # The wait is the whole point of the tier. A sweep that returned here
  # would put every dispatch back on one starting line, which is what
  # made the order a coin toss.
  while read -r REPO_NAME BRANCH; do
    [ -z "$REPO_NAME" ] && continue

    OUTCOME=$(wait_for_dispatch "$REPO_NAME" "release-new-version.yml" "$BRANCH" "$RELEASE_SINCE")
    echo "  Release $REPO_NAME ($BRANCH): $OUTCOME"
    RESULTS="$RESULTS"$'\n'"| $TIER | \`$REPO_NAME\` | $BRANCH | $OUTCOME |"

    case "$OUTCOME" in
      success) RELEASED=$((RELEASED + 1)) ;;
      timeout|missing) TIMED_OUT=$((TIMED_OUT + 1)) ;;
      *) FAILED=$((FAILED + 1)) ;;
    esac
  done <<< "$TIER_DISPATCHED"

  echo "::endgroup::"
done

{
  echo "### Auto release sweep"
  echo
  if [ "$DRY_RUN" = "true" ]; then
    echo "Dry run — nothing was dispatched."
    echo
  fi
  echo "| Result | Count |"
  echo "|--------|-------|"
  echo "| Dispatched | $DISPATCHED |"
  echo "| Released | $RELEASED |"
  echo "| Failed | $FAILED |"
  echo "| Timed out waiting | $TIMED_OUT |"
  echo "| Skipped (no release workflow) | $SKIPPED_NO_WORKFLOW |"
  echo "| Skipped (no supported version branch) | $SKIPPED_NO_BRANCH |"

  if [ -n "$RESULTS" ]; then
    echo
    echo "| Tier | Repository | Branch | Outcome |"
    echo "|------|------------|--------|---------|"
    printf '%s\n' "${RESULTS#$'\n'}"
  fi

  echo
  echo "A dispatched run releases only if commits are pending — see"
  echo "\`_get-version-for-release.yml\`. Quiet branches produce nothing."
} >> "$GITHUB_STEP_SUMMARY"

# A failed release fails the sweep, because every tier after it was
# sequenced on the assumption that it shipped. A timeout does not: the
# run the sweep stopped watching may still finish and succeed.
if [ "$FAILED" -gt 0 ]; then
  echo "$FAILED release(s) failed."
  exit 1
fi
