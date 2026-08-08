#!/usr/bin/env bash
#
# This file is part of the Valkyrja GitHub package.
#
# Copyright (c) 2016-present Melech Mizrachi
#
# Released under the MIT License. See LICENSE.md for details.
#
# ---------------------------------------------------------------------------
# Dependency refresh for a release.
#
# A release refreshes its own dependencies. This script dispatches the
# repository's `update-dependencies.yml` on the branch being released, and it
# waits for that run to finish. The job that follows merges the pull request
# the run opens, and the outdated-dependency gate then reads what the merge
# landed.
#
# The refresh belongs to the release because a registry publishes at any hour.
# A refresh that runs on its own schedule leaves a window between itself and
# the release, and a package published inside that window fails the gate.
#
# A repository that carries no `update-dependencies.yml` has nothing to
# refresh. The script reports that and exits 0, rather than failing a release
# over a workflow the repository never had.
#
# Reads GH_TOKEN, ORG, REPO, BRANCH, WORKFLOW, and RUN_TIMEOUT_MINUTES from
# the environment.
#
# Usage:
#
#     .github/ci/scripts/update-dependencies-for-release.sh
# ---------------------------------------------------------------------------

# Warning: `-u` and `pipefail` are deliberately absent. This script carries a
# block from a `run:` step that names no shell, and GitHub runs that as
# `bash -e {0}`. An action step is the other case, and a script it invokes sets
# `pipefail`.
set -e

# Warning: WORKFLOW belongs here with the rest. `-u` is absent, so an empty one expands to
# nothing and the probe below asks for the workflows directory instead of a file — a listing,
# which answers 200 for every repository. Neither pass would see a 404, and the dispatch would
# go out with no workflow named.
if [[ -z "$ORG" ]] || [[ -z "$REPO" ]] || [[ -z "$BRANCH" ]] || [[ -z "$WORKFLOW" ]]; then
  echo "ORG, REPO, BRANCH, and WORKFLOW are all required."
  exit 1
fi

POLL_SECONDS=15
DEADLINE=$(( ${RUN_TIMEOUT_MINUTES:-12} * 60 ))

# Two independent conditions decide whether the dispatch below succeeds, and both have to be
# asked. `gh workflow run` resolves the workflow against the repository's registered workflows,
# which come from the default branch, so a file absent there answers HTTP 404 before `ref` is
# read. The dispatch then runs the file as the branch carries it, so a branch without it answers
# HTTP 422. Asking only one leaves the other to `set -e`, which fails the release — the case the
# header promises never to fail on.
#
# The two branches differ for most of a year: the default branch follows the current major, and
# an older major stays supported alongside it.
#
# Warning: read the message, never the body. `gh api --jq` leaves an error body unfiltered, so a
# 404 arrives as the error JSON rather than as the empty string an absent workflow should
# produce. Only a definite 404 means there is nothing to refresh. Every other answer says
# nothing about the workflow, so the dispatch decides — and a release that cannot reach its own
# dependency update should stop rather than proceed unrefreshed.
for probe in "" "?ref=$BRANCH"; do
  WORKFLOW_ERR=$(gh api "repos/$ORG/$REPO/contents/.github/workflows/$WORKFLOW$probe" \
    --silent 2>&1 >/dev/null || true)

  if [[ "$WORKFLOW_ERR" == *"HTTP 404"* ]]; then
    if [[ -z "$probe" ]]; then
      echo "$ORG/$REPO carries no $WORKFLOW on its default branch. Nothing to refresh."
    else
      echo "$ORG/$REPO ($BRANCH) carries no $WORKFLOW. Nothing to refresh."
    fi

    exit 0
  fi

  if [[ -n "$WORKFLOW_ERR" ]]; then
    echo "Could not check for $WORKFLOW, dispatching anyway: $WORKFLOW_ERR"
  fi
done

SINCE=$(date -u +%Y-%m-%dT%H:%M:%SZ)

# A workflow_dispatch triggered with GITHUB_TOKEN creates no run, so this
# authenticates as the app. The token the workflow passes is already one.
gh workflow run "$WORKFLOW" --repo "$ORG/$REPO" --ref "$BRANCH"

echo "Dispatched $WORKFLOW on $ORG/$REPO ($BRANCH). Waiting for it to finish..."

# `gh workflow run` reports no run id, so the run is the newest one on that
# workflow and branch created at or after the dispatch. Both timestamps are
# UTC in the same format, so a string comparison orders them correctly.
RUN_ID=""

# Warning: measure the wall clock, not the sleeping. Every pass also makes one
# or two `gh` calls, and counting only `POLL_SECONDS` would leave that time out
# of the budget, so the wait would run past what it says.
STARTED_AT=$(date +%s)

while [[ "$(( $(date +%s) - STARTED_AT ))" -lt "$DEADLINE" ]]; do
  if [[ -z "$RUN_ID" ]]; then
    RUN_ID=$(gh run list --repo "$ORG/$REPO" --workflow "$WORKFLOW" --branch "$BRANCH" \
      --limit 20 --json databaseId,createdAt \
      --jq "[.[] | select(.createdAt >= \"$SINCE\")] | sort_by(.createdAt) | last | .databaseId // empty" \
      2>/dev/null || true)
  fi

  if [[ -n "$RUN_ID" ]]; then
    STATUS=$(gh run view "$RUN_ID" --repo "$ORG/$REPO" --json status,conclusion \
      --jq '"\(.status)|\(.conclusion // "")"' 2>/dev/null || true)

    case "$STATUS" in
      completed\|success)
        echo "$WORKFLOW completed: success."
        exit 0
        ;;
      completed\|*)
        echo "$WORKFLOW completed: ${STATUS#completed|}."
        exit 1
        ;;
      *) ;;
    esac
  fi

  sleep "$POLL_SECONDS"
done

if [[ -n "$RUN_ID" ]]; then
  echo "Timed out waiting for run $RUN_ID after ${RUN_TIMEOUT_MINUTES:-12} minutes."
else
  echo "Timed out after ${RUN_TIMEOUT_MINUTES:-12} minutes: no $WORKFLOW run appeared on $BRANCH."
fi

exit 1
