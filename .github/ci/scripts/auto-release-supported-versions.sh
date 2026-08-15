#!/usr/bin/env bash
#
# This file is part of the Valkyrja GitHub package.
#
# Copyright (c) 2016-present Melech Mizrachi
#
# Released under the MIT License. See LICENSE.md for details.
#
# ---------------------------------------------------------------------------
# Staggered auto release slots across supported version branches.
#
# The day is divided into slots. Each slot dispatches one action — a
# dependency refresh or a release — to one cohort of repositories, on every
# `??.x` branch whose major matches SUPPORTED_VERSIONS. It never dispatches to
# `master`, because a release is never cut from `master`.
#
# A cohort that consumes a first-party dependency refreshes two hours before
# it releases, so the hourly auto-merge sweep lands the bump pull requests in
# between. The infra cohort has no refresh slot, because it gates on no
# first-party dependency. A cohort releases after the cohorts it depends on,
# with enough of a gap for each registry to serve what the dependency shipped.
# The dispatches inside one release slot go out seconds apart, so every
# outdated-dependency gate evaluates before the first sibling publishes.
#
# A repository's cohort is derived from its name, per REPOSITORY_NAMING.md. A
# repository that no cohort claims lands in `catchall`, releases in the last
# slot, and is named in the run summary so it can be given a proper slot.
#
# The script reads and writes through the GitHub API. It never checks a
# released repository out.
#
# Reads APP_ID, APP_PRIVATE_KEY, ORG, SUPPORTED_VERSIONS, SUPPORTED_LANGUAGES,
# SLOTS, SLOT, SCHEDULE, STAGE_TIMEOUT_MINUTES, DRY_RUN, SINGLE_REPO, and
# GITHUB_STEP_SUMMARY from the environment.
#
# Usage:
#
#     .github/ci/scripts/auto-release-supported-versions.sh
# ---------------------------------------------------------------------------

# A bare `run:` step invokes this script, so it sets `set -e`.
# `.github/workflows/README.md` holds the rule for each family, under Scripts.
set -e

if [[ -z "$SUPPORTED_VERSIONS" ]]; then
  echo "SUPPORTED_VERSIONS is not set. Refusing to sweep without a version filter."
  exit 1
fi

if [[ -z "$SUPPORTED_LANGUAGES" ]]; then
  echo "SUPPORTED_LANGUAGES is not set. Refusing to sweep without a language list."
  exit 1
fi

if [[ -z "${SLOTS// /}" ]]; then
  echo "slots is empty. Refusing to sweep without a slot table."
  exit 1
fi

if [[ -z "$APP_ID" ]] || [[ -z "$APP_PRIVATE_KEY" ]]; then
  echo "APP_ID or APP_PRIVATE_KEY is not set. The sweep cannot mint a token."
  exit 1
fi

POLL_SECONDS=20
STAGE_TIMEOUT=$((STAGE_TIMEOUT_MINUTES * 60))

# The sweep authenticates as the GitHub App, and it mints the installation
# token itself. A minted token lives one hour. A slot run is normally far
# shorter than that, but a wait on a slow release can approach the limit, and
# a stale token turns every later dispatch into HTTP 401.
TOKEN_MINTED_AT=0
TOKEN_MAX_AGE_SECONDS=$((40 * 60))

# The `--` is load-bearing: `tr` reads a `-_` operand as an option without it.
base64url() { openssl base64 -A | tr -- '+/' '-_' | tr -d '='; }

mint_token() {
  local now header payload unsigned signature jwt installation_id

  now=$(date +%s)
  header=$(printf '{"alg":"RS256","typ":"JWT"}' | base64url)
  payload=$(printf '{"iat":%d,"exp":%d,"iss":"%s"}' \
    "$((now - 60))" "$((now + 540))" "$APP_ID" | base64url)
  unsigned="$header.$payload"
  signature=$(printf '%s' "$unsigned" \
    | openssl dgst -sha256 -sign <(printf '%s\n' "$APP_PRIVATE_KEY") -binary \
    | base64url)
  jwt="$unsigned.$signature"

  installation_id=$(curl -sf \
    -H "Authorization: Bearer $jwt" \
    -H "Accept: application/vnd.github+json" \
    "https://api.github.com/orgs/$ORG/installation" | jq -r '.id')

  if [[ -z "$installation_id" ]] || [[ "$installation_id" == "null" ]]; then
    echo "Could not resolve the app installation for $ORG." >&2
    exit 1
  fi

  GH_TOKEN=$(curl -sf -X POST \
    -H "Authorization: Bearer $jwt" \
    -H "Accept: application/vnd.github+json" \
    "https://api.github.com/app/installations/$installation_id/access_tokens" \
    | jq -r '.token')

  if [[ -z "$GH_TOKEN" ]] || [[ "$GH_TOKEN" == "null" ]]; then
    echo "Could not mint an installation token." >&2
    exit 1
  fi

  export GH_TOKEN
  TOKEN_MINTED_AT=$now

  echo "Minted a fresh installation token." >&2
}

# Cheap enough to call inside every poll loop. Warning: command substitution
# runs a function in a subshell, so a re-mint inside `wait_for_dispatch`
# serves that one wait — each caller in the parent shell re-mints for itself.
maybe_mint_token() {
  local age

  age=$(($(date +%s) - TOKEN_MINTED_AT))

  if [[ "$age" -ge "$TOKEN_MAX_AGE_SECONDS" ]]; then
    mint_token
  fi
}

trim() {
  local s="$1"

  s="${s#"${s%%[![:space:]]*}"}"
  s="${s%"${s##*[![:space:]]}"}"
  printf '%s' "$s"
}

# Selects the slot to run. A manual dispatch names the slot; a scheduled run
# carries the cron that fired, and the table maps it back to a slot. A cron
# the table does not name fails the run, so the trigger list and the table
# cannot drift apart silently.
# Sets SLOT_NAME, SLOT_ACTION, and SLOT_COHORTS.
resolve_slot() {
  local line name cron action cohorts

  SLOT_NAME=""
  SLOT_ACTION=""
  SLOT_COHORTS=""

  while IFS= read -r line; do
    [[ -z "${line// /}" ]] && continue

    IFS='|' read -r name cron action cohorts <<< "$line"
    name=$(trim "$name")
    cron=$(trim "$cron")
    action=$(trim "$action")
    cohorts=$(trim "$cohorts")

    if [[ -n "$SLOT" && "$name" == "$SLOT" ]] \
      || [[ -z "$SLOT" && -n "$SCHEDULE" && "$cron" == "$SCHEDULE" ]]; then
      SLOT_NAME="$name"
      SLOT_ACTION="$action"
      SLOT_COHORTS="$cohorts"
      return 0
    fi
  done <<< "$SLOTS"

  if [[ -n "$SLOT" ]]; then
    echo "Slot '$SLOT' is not in the slot table."
  else
    echo "Schedule '$SCHEDULE' is not in the slot table. The trigger list and the table are out of sync."
  fi
  exit 1
}

# Maps a repository name to its cohort, per REPOSITORY_NAMING.md. The language
# suffix set is closed and comes from SUPPORTED_LANGUAGES, so a two-token name
# such as `valkyrja-php` cannot be confused with a project component such as
# `valkyrja-docker-php`.
cohort_of() {
  local name="$1" lang

  case "$name" in
    .github|architecture|art) echo "infra"; return 0 ;;
    *) ;;
  esac

  for lang in $SUPPORTED_LANGUAGES; do
    case "$name" in
      ci-*-"$lang") echo "ci"; return 0 ;;
      valkyrja-"$lang") echo "frameworks"; return 0 ;;
      sindri-"$lang") echo "sindri"; return 0 ;;
      valkyrja-starter-*-"$lang"|project-template-"$lang") echo "projects"; return 0 ;;
      *) ;;
    esac
  done

  echo "catchall"
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

  while [[ "$waited" -lt "$deadline" ]]; do
    maybe_mint_token

    if [[ -z "$run_id" ]]; then
      run_id=$(gh run list --repo "$ORG/$repo" --workflow "$workflow" --branch "$branch" \
        --limit 20 --json databaseId,createdAt \
        --jq "[.[] | select(.createdAt >= \"$since\")] | sort_by(.createdAt) | last | .databaseId // empty" \
        2>/dev/null || true)
    fi

    if [[ -n "$run_id" ]]; then
      status=$(gh run view "$run_id" --repo "$ORG/$repo" --json status,conclusion \
        --jq '"\(.status)|\(.conclusion // "")"' 2>/dev/null || true)
      case "$status" in
        completed\|*) echo "${status#completed|}"; return 0 ;;
        *) ;;
      esac
    fi

    sleep "$POLL_SECONDS"
    waited=$((waited + POLL_SECONDS))
  done

  if [[ -n "$run_id" ]]; then echo "timeout"; else echo "missing"; fi
}

release_branches_for() {
  local repo="$1" all b major out=""

  # Warning: read the exit status. `gh api --jq` leaves an error body unfiltered, so a
  # failed read arrives as JSON that matches no branch pattern below — and an empty result
  # reads as "this repository has no version branch". A transient answer would drop the
  # repository from the slot in silence, which is the failure this guard exists to prevent.
  #
  # The message is kept rather than suppressed. The caller fails the slot on this, and a
  # repository name alone does not say whether a second run would answer differently. Only
  # stdout is captured here, so `gh` writes its message straight to the job log.
  if ! all=$(gh api "repos/$ORG/$repo/branches" --paginate --jq '.[].name'); then
    return 1
  fi

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

mint_token
resolve_slot

case "$SLOT_ACTION" in
  deps) ACTION_WORKFLOW="update-dependencies.yml" ;;
  release) ACTION_WORKFLOW="release-new-version.yml" ;;
  *)
    echo "Slot '$SLOT_NAME' has unknown action '$SLOT_ACTION'. Must be deps or release."
    exit 1
    ;;
esac

echo "Slot: $SLOT_NAME ($SLOT_ACTION for: $SLOT_COHORTS)"

if [[ -n "$SINGLE_REPO" ]]; then
  REPOS="$SINGLE_REPO"
else
  REPOS=$(gh repo list "$ORG" --limit 200 --json name,isArchived \
    --jq '.[] | select(.isArchived == false) | .name')
fi

# Collect the work before the dispatch loop runs, so that loop dispatches
# rather than discovers. A repository appears once per version branch.
WORK=""
SKIPPED_NO_WORKFLOW=0
SKIPPED_NO_BRANCH_WORKFLOW=0
SKIPPED_NO_BRANCH=0
SKIPPED_OTHER_COHORT=0
UNREADABLE_BRANCHES=0
UNREADABLE_BRANCH_REPOS=""
MISSING_BRANCH_WORKFLOW=""
CATCHALL_REPOS=""

while IFS= read -r REPO_NAME; do
  [[ -z "$REPO_NAME" ]] && continue

  COHORT=$(cohort_of "$REPO_NAME")

  if [[ " $SLOT_COHORTS " != *" $COHORT "* ]]; then
    SKIPPED_OTHER_COHORT=$((SKIPPED_OTHER_COHORT + 1))
    continue
  fi

  # Two independent conditions decide whether the dispatch below succeeds, and this is the
  # first. `gh workflow run` resolves the workflow against the repository's registered
  # workflows, which come from the default branch, so a file absent there answers HTTP 404
  # before `ref` is read at all. The answer does not vary by branch, so it is asked once.
  #
  # Warning: read the message, never the body. `gh api --jq` leaves an error body unfiltered,
  # so a 404 arrives as the error JSON rather than as the empty string an absent workflow
  # should produce. Only a definite 404 skips. Every other answer says nothing about the
  # workflow, so it goes to the dispatch, which reports a failure and fails the slot rather
  # than dropping the repository in silence.
  WORKFLOW_ERR=$(gh api "repos/$ORG/$REPO_NAME/contents/.github/workflows/$ACTION_WORKFLOW" \
    --silent 2>&1 >/dev/null || true)

  if [[ "$WORKFLOW_ERR" == *"HTTP 404"* ]]; then
    echo "$ORG/$REPO_NAME: no $ACTION_WORKFLOW on the default branch, skipping."
    SKIPPED_NO_WORKFLOW=$((SKIPPED_NO_WORKFLOW + 1))
    continue
  fi

  if [[ -n "$WORKFLOW_ERR" ]]; then
    echo "$ORG/$REPO_NAME: could not check for $ACTION_WORKFLOW, dispatching anyway: $WORKFLOW_ERR"
  fi

  if ! BRANCHES=$(release_branches_for "$REPO_NAME"); then
    echo "$ORG/$REPO_NAME: could not read the branch list. This fails the slot."
    UNREADABLE_BRANCHES=$((UNREADABLE_BRANCHES + 1))
    UNREADABLE_BRANCH_REPOS="$UNREADABLE_BRANCH_REPOS"$'\n'"$REPO_NAME"
    continue
  fi

  if [[ -z "$(printf '%s' "$BRANCHES" | tr -d '[:space:]')" ]]; then
    echo "$ORG/$REPO_NAME: no supported version branch, skipping."
    SKIPPED_NO_BRANCH=$((SKIPPED_NO_BRANCH + 1))
    continue
  fi

  if [[ "$COHORT" == "catchall" ]]; then
    CATCHALL_REPOS="$CATCHALL_REPOS"$'\n'"$REPO_NAME"
  fi

  while IFS= read -r BRANCH; do
    [[ -z "$BRANCH" ]] && continue

    # The second condition. The workflow resolved against the default branch above, but the
    # dispatch runs the file as this branch carries it, and a branch without it answers HTTP
    # 422. The two branches differ for most of a year: the default branch follows the current
    # major, and an older major stays supported alongside it.
    #
    # While one major is supported this repeats the probe above, because the only supported
    # branch is the default branch. One call per repository-branch costs less than a guard
    # that someone must revisit when the next major opens.
    #
    # The same reading rule as above applies — a definite 404 skips, and every other answer
    # goes to the dispatch.
    BRANCH_WORKFLOW_ERR=$(gh api "repos/$ORG/$REPO_NAME/contents/.github/workflows/$ACTION_WORKFLOW?ref=$BRANCH" \
      --silent 2>&1 >/dev/null || true)

    if [[ "$BRANCH_WORKFLOW_ERR" == *"HTTP 404"* ]]; then
      # Warning: the two 404s do not mean the same thing. Absent on the default branch means
      # the repository never opted the workflow in, which is a steady state nobody needs to
      # hear about. Absent here, with the file on the default branch, means this branch is
      # behind or the file was dropped, and for a release that means the branch stops
      # releasing. A count in a table does not say which branch, so it earns a warning
      # block of its own.
      echo "$ORG/$REPO_NAME ($BRANCH): branch carries no $ACTION_WORKFLOW, skipping."
      SKIPPED_NO_BRANCH_WORKFLOW=$((SKIPPED_NO_BRANCH_WORKFLOW + 1))
      MISSING_BRANCH_WORKFLOW="$MISSING_BRANCH_WORKFLOW"$'\n'"$REPO_NAME $BRANCH"
      continue
    fi

    if [[ -n "$BRANCH_WORKFLOW_ERR" ]]; then
      echo "$ORG/$REPO_NAME ($BRANCH): could not check for $ACTION_WORKFLOW, dispatching anyway: $BRANCH_WORKFLOW_ERR"
    fi

    WORK="$WORK"$'\n'"$REPO_NAME $BRANCH"
  done <<< "$BRANCHES"
done <<< "$REPOS"

DISPATCHED=0
SUCCEEDED=0
FAILED=0
TIMED_OUT=0
RESULTS=""

if [[ "$DRY_RUN" = "true" ]]; then
  while read -r REPO_NAME BRANCH; do
    [[ -z "$REPO_NAME" ]] && continue
    echo "[dry run] would run $SLOT_ACTION on $REPO_NAME ($BRANCH)"
    RESULTS="$RESULTS"$'\n'"| \`$REPO_NAME\` | $BRANCH | dry run |"
    DISPATCHED=$((DISPATCHED + 1))
  done <<< "$WORK"
else
  maybe_mint_token

  DISPATCH_SINCE=$(now_utc)
  DISPATCHED_WORK=""

  # Every dispatch in the slot goes out before the first wait starts. The
  # release runs of one cohort therefore all evaluate their gates before any
  # sibling publishes, so a sibling's release cannot turn a gate red mid-slot.
  while read -r REPO_NAME BRANCH; do
    [[ -z "$REPO_NAME" ]] && continue

    if [[ "$SLOT_ACTION" == "release" ]]; then
      TRIGGER_ERR=$(gh workflow run "$ACTION_WORKFLOW" \
        --repo "$ORG/$REPO_NAME" \
        --ref "$BRANCH" \
        -f bump=auto 2>&1 >/dev/null || true)
    else
      TRIGGER_ERR=$(gh workflow run "$ACTION_WORKFLOW" \
        --repo "$ORG/$REPO_NAME" \
        --ref "$BRANCH" 2>&1 >/dev/null || true)
    fi

    if [[ -n "$TRIGGER_ERR" ]]; then
      echo "Failed to dispatch $SLOT_ACTION on $REPO_NAME ($BRANCH): $TRIGGER_ERR"
      RESULTS="$RESULTS"$'\n'"| \`$REPO_NAME\` | $BRANCH | dispatch failed |"
      FAILED=$((FAILED + 1))
      continue
    fi

    echo "Dispatched $SLOT_ACTION on $REPO_NAME ($BRANCH)."
    DISPATCHED=$((DISPATCHED + 1))
    DISPATCHED_WORK="$DISPATCHED_WORK"$'\n'"$REPO_NAME $BRANCH"
  done <<< "$WORK"

  while read -r REPO_NAME BRANCH; do
    [[ -z "$REPO_NAME" ]] && continue

    maybe_mint_token
    OUTCOME=$(wait_for_dispatch "$REPO_NAME" "$ACTION_WORKFLOW" "$BRANCH" "$DISPATCH_SINCE")
    echo "$SLOT_ACTION $REPO_NAME ($BRANCH): $OUTCOME"
    RESULTS="$RESULTS"$'\n'"| \`$REPO_NAME\` | $BRANCH | $OUTCOME |"

    case "$OUTCOME" in
      success) SUCCEEDED=$((SUCCEEDED + 1)) ;;
      timeout|missing) TIMED_OUT=$((TIMED_OUT + 1)) ;;
      *) FAILED=$((FAILED + 1)) ;;
    esac
  done <<< "$DISPATCHED_WORK"
fi

{
  echo "### Auto release slot: $SLOT_NAME"
  echo
  echo "Action: \`$SLOT_ACTION\` — cohorts: \`$SLOT_COHORTS\`"
  echo
  if [[ "$DRY_RUN" = "true" ]]; then
    echo "Dry run — nothing was dispatched."
    echo
  fi
  echo "| Result | Count |"
  echo "|--------|-------|"
  echo "| Dispatched | $DISPATCHED |"
  echo "| Succeeded | $SUCCEEDED |"
  echo "| Failed | $FAILED |"
  echo "| Failed (branch list unreadable) | $UNREADABLE_BRANCHES |"
  echo "| Timed out waiting | $TIMED_OUT |"
  echo "| Skipped (other cohort) | $SKIPPED_OTHER_COHORT |"
  echo "| Skipped (no $ACTION_WORKFLOW on the default branch) | $SKIPPED_NO_WORKFLOW |"
  echo "| Skipped (branch carries no $ACTION_WORKFLOW) | $SKIPPED_NO_BRANCH_WORKFLOW |"
  echo "| Skipped (no supported version branch) | $SKIPPED_NO_BRANCH |"

  if [[ -n "$RESULTS" ]]; then
    echo
    echo "| Repository | Branch | Outcome |"
    echo "|------------|--------|---------|"
    printf '%s\n' "${RESULTS#$'\n'}"
  fi

  if [[ -n "$(printf '%s' "$UNREADABLE_BRANCH_REPOS" | tr -d '[:space:]')" ]]; then
    echo
    echo "Warning: the branch list would not read for these repositories, so the slot failed."
    echo "The \`gh\` message for each one is in the run log:"
    echo
    printf '%s\n' "$UNREADABLE_BRANCH_REPOS" | awk 'NF {print "- `" $1 "`"}'
  fi

  if [[ -n "$(printf '%s' "$MISSING_BRANCH_WORKFLOW" | tr -d '[:space:]')" ]]; then
    echo
    echo "Warning: these branches carry no \`$ACTION_WORKFLOW\`, and the repository passed the default branch check."
    echo "Each one is out of the $SLOT_ACTION rotation until the file reaches it:"
    echo
    printf '%s\n' "$MISSING_BRANCH_WORKFLOW" | awk 'NF {print "- `" $1 "` (" $2 ")"}'
  fi

  if [[ -n "$(printf '%s' "$CATCHALL_REPOS" | tr -d '[:space:]')" ]]; then
    echo
    echo "Warning: these repositories match no cohort and ran in \`catchall\`."
    echo "Give each one a slot, or a cohort rule in \`cohort_of\`:"
    echo
    printf '%s\n' "$CATCHALL_REPOS" | awk 'NF {print "- `" $1 "`"}'
  fi

  echo
  echo "A dispatched release runs only if commits are pending — see"
  echo "\`_get-version-for-release.yml\`. Quiet branches produce nothing."
} >> "$GITHUB_STEP_SUMMARY"

# A failure fails the slot, so the day's plan shows red where it broke. A wait
# that ends without an answer does not. The script either stops watching
# an unfinished run, or never finds the run to watch. Either way the script
# gives up on the answer rather than on the run.
#
# Warning: the two conditions below are independent, and one run can hit both. Each reports
# before anything exits, so the last lines of the log name every reason the slot is red.
SLOT_FAILED=0

if [[ "$FAILED" -gt 0 ]]; then
  echo "$FAILED $SLOT_ACTION dispatch(es) failed."
  SLOT_FAILED=1
fi

# A repository whose branch list would not read was neither dispatched nor deliberately
# skipped, so the slot says so rather than reporting a clean run over it.
if [[ "$UNREADABLE_BRANCHES" -gt 0 ]]; then
  echo "$UNREADABLE_BRANCHES repository branch list(s) could not be read."
  SLOT_FAILED=1
fi

if [[ "$SLOT_FAILED" -gt 0 ]]; then
  exit 1
fi
