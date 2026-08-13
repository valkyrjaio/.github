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
SKIPPED_NO_BRANCH=0
SKIPPED_OTHER_COHORT=0
CATCHALL_REPOS=""

while IFS= read -r REPO_NAME; do
  [[ -z "$REPO_NAME" ]] && continue

  COHORT=$(cohort_of "$REPO_NAME")

  if [[ " $SLOT_COHORTS " != *" $COHORT "* ]]; then
    SKIPPED_OTHER_COHORT=$((SKIPPED_OTHER_COHORT + 1))
    continue
  fi

  WORKFLOW_EXISTS=$(gh api "repos/$ORG/$REPO_NAME/contents/.github/workflows/$ACTION_WORKFLOW" \
    --jq '.name' 2>/dev/null || true)

  if [[ -z "$WORKFLOW_EXISTS" ]]; then
    SKIPPED_NO_WORKFLOW=$((SKIPPED_NO_WORKFLOW + 1))
    continue
  fi

  BRANCHES=$(release_branches_for "$REPO_NAME")

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
  echo "| Timed out waiting | $TIMED_OUT |"
  echo "| Skipped (other cohort) | $SKIPPED_OTHER_COHORT |"
  echo "| Skipped (no $ACTION_WORKFLOW) | $SKIPPED_NO_WORKFLOW |"
  echo "| Skipped (no supported version branch) | $SKIPPED_NO_BRANCH |"

  if [[ -n "$RESULTS" ]]; then
    echo
    echo "| Repository | Branch | Outcome |"
    echo "|------------|--------|---------|"
    printf '%s\n' "${RESULTS#$'\n'}"
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

# A failure fails the slot, so the day's plan shows red where it broke. A
# timeout does not: the run the sweep stopped watching may still finish.
if [[ "$FAILED" -gt 0 ]]; then
  echo "$FAILED $SLOT_ACTION dispatch(es) failed."
  exit 1
fi
