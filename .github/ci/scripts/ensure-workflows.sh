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
# on a `deps/` branch. It opens one pull request for each base branch whose
# branch carries work. That covers a base branch this run changed, and one whose
# branch a previous run left with no pull request. It merges the missing jobs
# into an existing `ci.yml` rather than replacing the file.
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

# Warning: `-u` and `pipefail` are deliberately absent. A GitHub Actions `run:`
# block that names no shell runs under `bash -e {0}`, and this script holds the
# block that ran there. The `bash --noprofile --norc -eo pipefail {0}` form is
# what an explicit `shell: bash` selects, which is why a script that
# `run-script` invokes sets `pipefail` and this one does not.
set -e

# Work the sweep could not finish, at every step that can leave it unfinished.
# The count decides the exit, and the list decides where an operator looks.
# `update-workflow-refs.sh` keeps `SKIPPED_REPOS` for the same reason.
#
# One run covers every non-archived repository in the organization. A repository
# takes a branch list, and each of its base branches takes up to two ref reads.
# A base branch also takes a contents read for each required workflow, and a
# write for each file it is missing. A base branch whose update branch exists and
# landed nothing takes a compare. A compare that finds the branch ahead adds a
# commit read and a merged pull request list. Two pull request calls follow
# wherever the branch carries work. Every call above asks up to three times, and
# a bare number names nothing across that.
UNFINISHED=0
UNFINISHED_WORK=""

record_unfinished() {
  UNFINISHED=$((UNFINISHED + 1))
  UNFINISHED_WORK="$UNFINISHED_WORK"$'\n'"  - $1"
}

# Warning: this helper retries a write. Every write it runs is one a second attempt cannot
# repeat. GitHub refuses a second reference with the same name, and a second pull request for
# the same head branch. GitHub also refuses a contents write that does not carry the file's
# current `sha`. A caller that adds a write a repeat could apply twice must pass a fragment
# that ends the loop on the first answer.
#
# The contents writes and the reference write pass no fragment. Each of them reads the
# branch it writes to first, so the refusal it can still meet is rare. That refusal costs two
# more calls on a run already red. `gh pr create` does pass one, because a pull request the
# sweep opened last week is the answer it meets most.
#
# Runs a `gh` command up to three times, as `fetch_json` does in `update-workflow-refs.sh` and
# in `auto-merge-bot-prs.sh`. A 403 secondary rate limit or a 5xx is transient, and this sweep
# asks enough of the API in one run to meet one.
#
# Takes a label for the log, then the fragment that ends the loop at once, then the command. The
# fragment is what the API says when a second attempt cannot change the answer. It is that
# call's own wording rather than a status, so a REST read takes `HTTP 404` and the GraphQL
# create takes `already exists`. The label is passed rather than taken from the command,
# because a command line carries a pull request body.
#
# Sets RETRY_OUT, RETRY_ERR, RETRY_STATUS and RETRY_OK. Read them straight after the call,
# because the next call overwrites them.
retry_gh() {
  local label="$1"
  local definite="$2"
  shift 2

  local attempt err_file
  err_file=$(mktemp)

  for attempt in 1 2 3; do
    RETRY_OUT=$("$@" 2>"$err_file") && RETRY_STATUS=0 || RETRY_STATUS=$?
    RETRY_ERR=$(cat "$err_file")

    if [[ "$RETRY_STATUS" -eq 0 ]]; then
      RETRY_OK=1
      break
    fi

    RETRY_OK=0

    if [[ -n "$definite" ]] && [[ "$RETRY_ERR" == *"$definite"* ]]; then
      break
    fi

    if [[ "$attempt" -lt 3 ]]; then
      echo "  Retrying $label after: ${RETRY_ERR:-it exited $RETRY_STATUS with no message}"
      sleep "$attempt"
    fi
  done

  rm -f "$err_file"
}

# The script names a sibling file below, and the caller runs it from the workspace root
# rather than from this directory. `BASH_SOURCE` is what makes the sibling reachable from
# either one.
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

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

# Workflows the root and every language flavor both carry, which `ensure_workflow` adds.
SHARED_WORKFLOWS=(
  "create-version-branch.yml"
  "release-new-version.yml"
)

# `ci.yml` sits beside them in both places, and `ensure_ci_jobs` adds it, so it is named apart.
CI_WORKFLOW="ci.yml"

# The language flavors, and the suffix each one claims. The loop below reads this array rather
# than a second list of names, so a flavor cannot reach the sweep without reaching the guard.
LANG_DIRS=(
  "php"
  "go"
  "python"
  "java"
  "ts"
)

# Fails the run on a file this repository does not hold. The templates and `merge_ci_jobs.py`
# ship here, so a renamed or emptied one is a defect in this repository. It is not an answer
# about any repository the sweep visits.
#
# The call sits above every API call. A guard inside the loop would report the one defect once
# for each repository-branch, and only after the sweep spent its whole budget.
check_templates() {
  local dir workflow tmpl
  local bad=""

  for workflow in "${REQUIRED_WORKFLOWS[@]}" "${SHARED_WORKFLOWS[@]}" "$CI_WORKFLOW"; do
    tmpl="$TEMPLATE_DIR/$workflow"

    if [[ ! -r "$tmpl" ]] || [[ ! -s "$tmpl" ]]; then
      bad="$bad"$'\n'"  - $tmpl"
    fi
  done

  for dir in "${LANG_DIRS[@]}"; do
    for workflow in "${LANG_WORKFLOWS[@]}" "${SHARED_WORKFLOWS[@]}" "$CI_WORKFLOW"; do
      tmpl="$TEMPLATE_DIR/$dir/$workflow"

      if [[ ! -r "$tmpl" ]] || [[ ! -s "$tmpl" ]]; then
        bad="$bad"$'\n'"  - $tmpl"
      fi
    done
  done

  if [[ ! -r "$SCRIPT_DIR/merge_ci_jobs.py" ]] || [[ ! -s "$SCRIPT_DIR/merge_ci_jobs.py" ]]; then
    bad="$bad"$'\n'"  - $SCRIPT_DIR/merge_ci_jobs.py"
  fi

  if [[ -n "$bad" ]]; then
    echo "This repository is missing a file the sweep names:"
    printf '%s\n' "${bad#$'\n'}"
    exit 1
  fi
}

check_templates

# Reads something the whole run needs, and ends the run when the read fails. Each caller below
# runs at top level. There `set -e` would end the sweep on a 403 secondary rate limit and leave
# nothing behind that says why.
#
# Takes the label, then the fragment that ends the retry, then the command, as `retry_gh` does.
require_gh() {
  local label="$1"
  local definite="$2"
  shift 2

  retry_gh "$label" "$definite" "$@"

  if [[ "$RETRY_OK" -eq 0 ]]; then
    echo "Could not read $label: ${RETRY_ERR:-no message}"
    exit 1
  fi
}

require_gh "the latest .github release" 'HTTP 404' gh api "repos/$ORG/.github/releases/latest" --jq '.tag_name'
LATEST_TAG="$RETRY_OUT"

require_gh "the commit for $LATEST_TAG" 'HTTP 404' gh api "repos/$ORG/.github/commits/$LATEST_TAG" --jq '.sha'
LATEST_SHA="$RETRY_OUT"

echo "Latest .github release: $LATEST_TAG ($LATEST_SHA)"


PHP_EXCLUDED_REPOS="valkyrja-benchmarking-php valkyrja-docker-php"

# The .github repo excludes itself on purpose. Its own callers use local
# `./` refs, so a synced template pinned to a release SHA would be wrong
# here: it would run the released workflow instead of the branch under
# test. This repo therefore adds its own copies by hand.
#
# No fragment. This call's one refusal names an organization GitHub cannot resolve, and the
# workflow fixes `$ORG`, so the sweep meets only transient refusals here.
require_gh "the repository list" '' gh repo list "$ORG" --limit 200 --json name,isArchived \
  --jq '.[] | select(.isArchived == false and .name != ".github") | .name'
REPOS="$RETRY_OUT"

# Asks whether something exists, and separates the answers a read can give.
#
# Takes the API path, an optional `--jq` filter, and an optional third argument that turns on
# `--paginate`. Any non-empty third argument does it; the call sites pass `paginate` so the
# line reads.
#
# Sets READ_BODY to the response, READ_STATE to `ok`, `absent` or `unread`, and READ_MESSAGE
# to what `gh` said. Read all three straight after the call, because the next call overwrites
# them.
#
# Warning: the exit status decides whether the read succeeded. `gh api` skips `--jq` on an
# error, so an error body reaches stdout unfiltered and reads as data. That is how an
# unreadable branch list once aimed this sweep at `master`. The body and the message then
# separate the three states, but neither one decides success.
#
# Warning: `unread` also covers a `--jq` filter that does not fit a response the server
# returned in full. That is a defect in this script rather than a transient answer. It
# reaches the same exit, because neither gives the sweep a result it can use.
#
# `retry_gh` runs the read, so a 2xx and a definite 404 each end the loop at once and every
# other answer is asked again. This function keeps the classification.
read_exists() {
  local url="$1"
  local jq_filter="${2:-}"
  local paginate="${3:-}"
  local args=(api "$url")

  [[ -n "$jq_filter" ]] && args+=(--jq "$jq_filter")
  [[ -n "$paginate" ]] && args+=(--paginate)

  retry_gh "$url" 'HTTP 404' gh "${args[@]}"
  READ_BODY="$RETRY_OUT"

  if [[ "$RETRY_OK" -eq 1 ]]; then
    READ_MESSAGE=""

    # `--jq` writes a string raw and encodes anything else, so a filter that finds nothing on
    # a 200 arrives as the four characters `null`. That is an absent thing, not a body.
    if [[ "$READ_BODY" == "null" ]]; then
      READ_BODY=""
      READ_STATE="absent"
    else
      READ_STATE="ok"
    fi

    return 0
  fi

  READ_BODY=""
  READ_MESSAGE="${RETRY_ERR:-gh exited $RETRY_STATUS with no message}"

  if [[ "$RETRY_ERR" == *"HTTP 404"* ]]; then
    READ_STATE="absent"
  else
    READ_STATE="unread"
  fi

  return 0
}

create_branch_if_needed() {
  local base_branch="$1"
  local update_branch="$2"
  local repo_name="$3"

  [[ -n "$BRANCH_EXISTS" ]] && return 0

  echo "  [$base_branch] Creating branch $update_branch..."
  # A 404 here is an answer: the base branch does not exist. The `master` fallback produces
  # that for a repository carrying neither a version branch nor `master`. Counting it as unread
  # would fail the sweep on a fact the API stated.
  # `git/ref/` rather than `git/refs/`. The plural path prefix-matches, so a name with no exact
  # ref answers with an array of the refs that extend it. `.object.sha` then fails on a branch
  # the API could have called absent, and `restore-branch-from-backup.yml` puts a
  # `<branch>-backup` beside every branch it restores.
  read_exists "repos/$ORG/$repo_name/git/ref/heads/$base_branch" '.object.sha'
  local base_sha="$READ_BODY"

  if [[ "$READ_STATE" == "unread" ]]; then
    echo "  [$base_branch] Could not read the base branch SHA: $READ_MESSAGE"
    record_unfinished "$repo_name [$base_branch]: base branch SHA: $READ_MESSAGE"
    BRANCH_FAILED=1
    return 2
  fi

  if [[ "$READ_STATE" == "absent" ]]; then
    echo "  [$base_branch] Base branch does not exist, skipping"
    BRANCH_FAILED=1
    return 2
  fi

  retry_gh "branch $update_branch" '' gh api --method POST "repos/$ORG/$repo_name/git/refs" \
    --field "ref=refs/heads/$update_branch" \
    --field "sha=$base_sha"

  if [[ "$RETRY_OK" -eq 0 ]]; then
    echo "  [$base_branch] Branch creation failed: ${RETRY_ERR:-no message}"
    record_unfinished "$repo_name [$base_branch]: branch creation: ${RETRY_ERR:-no message}"
    BRANCH_FAILED=1
    return 2
  fi
  echo "  [$base_branch] Branch $update_branch created."
  BRANCH_EXISTS="$base_sha"

  # Cut from the base branch a moment ago, so the two carry the same files. The base-branch
  # reads below have nothing to add for this branch.
  BRANCH_PREDATES_RUN=""
}

# Names the branch a file read has to ask about. It is the branch the write lands on, and a file
# already there is a file this run does not add. Before that branch exists the base branch is
# the only answer.
#
# Warning: the two branches diverge. The update branch is the base branch as it stood when the
# branch was cut, and nothing merges the base branch into it afterwards. A file the base branch
# gained since then reads as absent here. The sweep proposes it again, and GitHub reports the
# conflict on the pull request.
read_ref() {
  local base_branch="$1"
  local update_branch="$2"

  if [[ -n "$BRANCH_EXISTS" ]]; then
    printf '%s' "$update_branch"
    return 0
  fi

  printf '%s' "$base_branch"
}

# Substitutes the release SHA into a template, and sets TEMPLATE_TEXT to the result. Reports a
# template that gives nothing back, and returns non-zero on it. Read TEMPLATE_TEXT straight
# after the call, because the next call overwrites it.
#
# `check_templates` proved every template readable and not empty before the first call, so what
# is left is a read that fails during the run. `set -e` does not catch it: every caller reaches
# this through an `||` list, and errexit is ignored inside a function a list calls.
render_template() {
  local tmpl_file="$1"
  local base_branch="$2"
  local repo_name="$3"
  local skipping="$4"
  local status=0 reason
  local pin_from='valkyrjaio/\.github/\.github/workflows/\([^@]*\)@[0-9a-f]\{40\}'
  local pin_to="valkyrjaio/.github/.github/workflows/\\1@$LATEST_SHA"

  TEMPLATE_TEXT=$(sed "s|$pin_from|$pin_to|g" "$tmpl_file") || status=$?

  if [[ "$status" -eq 0 ]] && [[ -n "$TEMPLATE_TEXT" ]]; then
    return 0
  fi

  reason="sed exited $status"

  if [[ "$status" -eq 0 ]]; then
    reason="the read gave nothing"
  fi

  TEMPLATE_TEXT=""
  echo "  [$base_branch] Template $tmpl_file: $reason, skipping $skipping"
  record_unfinished "$repo_name [$base_branch]: template $tmpl_file: $reason"

  return 1
}

ensure_workflow() {
  local workflow="$1"
  local tmpl_file="$2"
  local base_branch="$3"
  local update_branch="$4"
  local repo_name="$5"

  local file_path=".github/workflows/$workflow"

  # Warning: this read decides whether the file gets created, so a transient answer must not
  # look like an absent file. `|| existing=""` blanked every error alike, including a 403.
  # Only a definite 404 means the file is absent.
  #
  # Read the branch this function writes to. An update branch outlives its pull request until
  # somebody merges it, and it then carries files the base branch still lacks. A read of the
  # base branch would ask GitHub to add a file the update branch already holds. GitHub refuses
  # that for want of a `sha`.
  read_exists "repos/$ORG/$repo_name/contents/$file_path?ref=$(read_ref "$base_branch" "$update_branch")" '.name'

  if [[ "$READ_STATE" == "unread" ]]; then
    echo "  [$base_branch] $file_path: could not read: $READ_MESSAGE"
    record_unfinished "$repo_name [$base_branch]: $file_path: $READ_MESSAGE"
    return 1
  fi

  if [[ "$READ_STATE" == "ok" ]]; then
    echo "  [$base_branch] $file_path: already exists, skipping"
    return 0
  fi

  # The two branches diverge, so a file absent from the update branch can still be on the base
  # branch. Ask before adding it. Without the read the sweep proposes a second copy from an
  # ancestor that has neither. The pull request then conflicts on a file the base branch
  # already carries. `ensure_ci_jobs` asks the same question for its own file.
  if [[ -n "$BRANCH_PREDATES_RUN" ]]; then
    read_exists "repos/$ORG/$repo_name/contents/$file_path?ref=$base_branch" '.name'

    if [[ "$READ_STATE" == "unread" ]]; then
      echo "  [$base_branch] $file_path: could not read on $base_branch: $READ_MESSAGE"
      record_unfinished "$repo_name [$base_branch]: $file_path on $base_branch: $READ_MESSAGE"
      return 1
    fi

    if [[ "$READ_STATE" == "ok" ]]; then
      echo "  [$base_branch] $file_path: already on $base_branch, skipping"
      return 0
    fi
  fi

  echo "  [$base_branch] $file_path: missing, will create"

  render_template "$tmpl_file" "$base_branch" "$repo_name" "$workflow" || return 1
  local content="$TEMPLATE_TEXT"

  create_branch_if_needed "$base_branch" "$update_branch" "$repo_name" || return $?

  echo "  [$base_branch] Committing $file_path to $update_branch..."

  local content_b64
  content_b64=$(printf '%s\n' "$content" | base64 | tr -d '\n')

  local put_file
  put_file=$(mktemp)
  jq -cn \
    --arg message "[Workflow] ci: Add the missing $workflow workflow." \
    --arg content "$content_b64" \
    --arg branch "$update_branch" \
    '{message: $message, content: $content, branch: $branch}' > "$put_file"

  retry_gh "$file_path" '' gh api --method PUT "repos/$ORG/$repo_name/contents/$file_path" --input "$put_file"
  rm -f "$put_file"

  if [[ "$RETRY_OK" -eq 0 ]]; then
    echo "  [$base_branch] $file_path commit failed: ${RETRY_ERR:-no message}"
    record_unfinished "$repo_name [$base_branch]: $file_path commit: ${RETRY_ERR:-no message}"
    return 1
  fi

  echo "  [$base_branch] $file_path committed."
  FILES_LIST+="| \`.github/workflows/$workflow\` | Added |"$'\n'
  FILES_ADDED=$((FILES_ADDED + 1))
}

# Answers whether the update branch carries work that no pull request shows. A create that
# failed leaves that state, and so does a pull request somebody closed without merging.
#
# Warning: `ahead_by` alone does not answer it. This organization squash-merges and deletes no
# branch. A squash merge writes one new commit onto the base rather than taking the head
# branch's commits into its history. A merged branch therefore stays ahead of its base for
# good, and `ahead_by` would open one pull request a week for work that merged already.
#
# The pull request that merged dates the work it took. A branch tip no newer than that date is
# work the merge took, and a tip newer than it is work no pull request shows.
branch_carries_unmerged_work() {
  local base_branch="$1"
  local update_branch="$2"
  local repo_name="$3"
  local ahead tip_date merged_at

  read_exists "repos/$ORG/$repo_name/compare/$base_branch...$update_branch" '.ahead_by'
  ahead="$READ_BODY"

  # A 404 is an answer: one of the two branches is gone since the ref read. Counting it as
  # unread would fail the sweep on a fact the API stated.
  if [[ "$READ_STATE" == "absent" ]]; then
    echo "  [$base_branch] $base_branch or $update_branch is gone, skipping the compare"
    return 1
  fi

  if [[ "$READ_STATE" != "ok" ]]; then
    echo "  [$base_branch] Could not compare $base_branch with $update_branch: $READ_MESSAGE"
    record_unfinished "$repo_name [$base_branch]: branch compare: $READ_MESSAGE"
    return 1
  fi

  if [[ "$ahead" == "0" ]]; then
    return 1
  fi

  read_exists "repos/$ORG/$repo_name/commits/$BRANCH_EXISTS" '.commit.committer.date'
  tip_date="$READ_BODY"

  if [[ "$READ_STATE" == "absent" ]]; then
    echo "  [$base_branch] The tip of $update_branch is gone, skipping the compare"
    return 1
  fi

  if [[ "$READ_STATE" != "ok" ]]; then
    echo "  [$base_branch] Could not date $update_branch: $READ_MESSAGE"
    record_unfinished "$repo_name [$base_branch]: branch tip date: $READ_MESSAGE"
    return 1
  fi

  retry_gh "merged pull requests for $update_branch" '' gh pr list --repo "$ORG/$repo_name" \
    --state merged \
    --head "$update_branch" \
    --json mergedAt \
    --jq 'first | .mergedAt // ""'

  if [[ "$RETRY_OK" -eq 0 ]]; then
    echo "  [$base_branch] Could not list merged pull requests: ${RETRY_ERR:-no message}"
    record_unfinished "$repo_name [$base_branch]: merged pull request list: ${RETRY_ERR:-no message}"
    return 1
  fi

  merged_at="$RETRY_OUT"

  # Both dates are UTC in the same format, so one string comparison orders them.
  if [[ -n "$merged_at" ]] && ! [[ "$merged_at" < "$tip_date" ]]; then
    return 1
  fi

  echo "  [$base_branch] $update_branch is ahead by $ahead commit(s) that no pull request shows."

  return 0
}

# Adds each workflow in turn, and stops when the update branch cannot be created.
#
# Warning: capture the status into a variable rather than testing `$?` inside a `||` group. The
# group's own status then decides whether the call failed, and how `set -e` reads a compound
# command decides the control flow.
add_workflows() {
  local tmpl_dir="$1"
  local base_branch="$2"
  local update_branch="$3"
  local repo_name="$4"
  shift 4
  local workflow rc

  # The branch failed earlier for this base branch, so nothing here can land. Each file would
  # still cost a contents read, and log `missing, will create` for a file that nothing creates.
  if [[ -n "$BRANCH_FAILED" ]]; then
    local pending=("${@/#/.github/workflows/}")
    echo "  [$base_branch] Skipping ${pending[*]}: the branch did not land"

    return 0
  fi

  local index=0
  local remaining=()

  for workflow in "$@"; do
    index=$((index + 1))
    rc=0
    ensure_workflow "$workflow" "$tmpl_dir/$workflow" \
      "$base_branch" "$update_branch" "$repo_name" || rc=$?

    # 2 means the branch could not be created, so the rest of this branch's files cannot land
    # either. Any other non-zero is one file's failure, and the loop carries on.
    if [[ "$rc" -eq 2 ]]; then
      local rest=("${@:$((index + 1))}")

      if [[ "${#rest[@]}" -gt 0 ]]; then
        remaining=("${rest[@]/#/.github/workflows/}")
        echo "  [$base_branch] Skipping ${remaining[*]}: the branch did not land"
      fi

      break
    fi
  done
}

ensure_ci_jobs() {
  local base_branch="$1"
  local update_branch="$2"
  local repo_name="$3"
  local tmpl_file="$4"

  local file_path=".github/workflows/ci.yml"

  # The same rule `add_workflows` states, for the one file that helper does not add.
  if [[ -n "$BRANCH_FAILED" ]]; then
    echo "  [$base_branch] Skipping $file_path: the branch did not land"

    return 0
  fi
  render_template "$tmpl_file" "$base_branch" "$repo_name" "ci.yml" || return 1
  local tmpl_with_sha="$TEMPLATE_TEXT"

  # Warning: an absent file and an unanswered call are not the same thing. `|| true` made every
  # answer non-empty, including a 404. The test below then read every file as present, and the
  # create path never ran. Only a definite 404 means the file is absent.
  #
  # The branch this function writes to, for the reason `ensure_workflow` gives. The `sha` and
  # the content below come from the same read. The merge therefore decides against what the
  # branch carries, and the write carries that blob's `sha`.
  read_exists "repos/$ORG/$repo_name/contents/$file_path?ref=$(read_ref "$base_branch" "$update_branch")"
  local file_data="$READ_BODY"
  local sha_on_update=1

  if [[ "$READ_STATE" == "unread" ]]; then
    echo "  [$base_branch] $file_path: could not read: $READ_MESSAGE"
    record_unfinished "$repo_name [$base_branch]: $file_path: $READ_MESSAGE"
    return 1
  fi

  # The two branches diverge, so a file absent from the update branch can still be on the base
  # branch. Ask before taking the create path. That path writes the template whole, and the
  # header promises this script merges into a repository's own `ci.yml` instead.
  if [[ "$READ_STATE" == "absent" ]] && [[ -n "$BRANCH_PREDATES_RUN" ]]; then
    read_exists "repos/$ORG/$repo_name/contents/$file_path?ref=$base_branch"
    file_data="$READ_BODY"
    sha_on_update=0

    if [[ "$READ_STATE" == "unread" ]]; then
      echo "  [$base_branch] $file_path: could not read on $base_branch: $READ_MESSAGE"
      record_unfinished "$repo_name [$base_branch]: $file_path on $base_branch: $READ_MESSAGE"
      return 1
    fi
  fi

  if [[ "$READ_STATE" == "absent" ]]; then
    echo "  [$base_branch] $file_path: missing, will create"
    create_branch_if_needed "$base_branch" "$update_branch" "$repo_name" || return $?

    local content_b64
    content_b64=$(printf '%s\n' "$tmpl_with_sha" | base64 | tr -d '\n')
    local put_file
    put_file=$(mktemp)
    jq -cn \
      --arg message "[Workflow] ci: Add the missing ci.yml workflow." \
      --arg content "$content_b64" \
      --arg branch "$update_branch" \
      '{message: $message, content: $content, branch: $branch}' > "$put_file"

    retry_gh "$file_path" '' gh api --method PUT "repos/$ORG/$repo_name/contents/$file_path" --input "$put_file"
    rm -f "$put_file"

    if [[ "$RETRY_OK" -eq 0 ]]; then
      echo "  [$base_branch] $file_path commit failed: ${RETRY_ERR:-no message}"
      record_unfinished "$repo_name [$base_branch]: $file_path commit: ${RETRY_ERR:-no message}"
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
  local existing_file template_file
  existing_file=$(mktemp)
  template_file=$(mktemp)
  echo "$content_b64" | base64 -d > "$existing_file"
  printf '%s\n' "$tmpl_with_sha" > "$template_file"

  # 3 is the merge saying every job is already there. Any other non-zero is the merge failing,
  # and the two used to share exit 1, so a crashed merge reported a complete `ci.yml`.
  local updated_content merge_status=0 merge_err merge_err_file
  merge_err_file=$(mktemp)
  updated_content=$(python3 "$SCRIPT_DIR/merge_ci_jobs.py" \
    "$existing_file" "$template_file" 2>"$merge_err_file") || merge_status=$?
  merge_err=$(cat "$merge_err_file")
  rm -f "$merge_err_file" "$existing_file" "$template_file"

  if [[ "$merge_status" -eq 3 ]]; then
    echo "  [$base_branch] $file_path: all required jobs present"
    return 0
  fi

  # An empty merge is a failure, not a `ci.yml` with nothing in it.
  if [[ "$merge_status" -ne 0 ]] || [[ -z "$updated_content" ]]; then
    local reason="it exited $merge_status"

    if [[ "$merge_status" -eq 0 ]]; then
      reason="it wrote nothing"
    fi

    echo "  [$base_branch] $file_path: merge failed: ${merge_err:-$reason}"
    record_unfinished "$repo_name [$base_branch]: $file_path merge: ${merge_err:-$reason}"
    return 1
  fi

  echo "  [$base_branch] $file_path: missing required jobs, will update"
  create_branch_if_needed "$base_branch" "$update_branch" "$repo_name" || return $?

  local new_content_b64
  new_content_b64=$(printf '%s\n' "$updated_content" | base64 | tr -d '\n')
  # The blob a `sha` names lives on the branch the write lands on. The update branch holds no
  # such blob when the content comes from the base branch. The write then creates the file, and
  # it carries no `sha`.
  local put_file
  put_file=$(mktemp)
  jq -cn \
    --arg message "[Workflow] ci: Add the missing required jobs to ci.yml." \
    --arg content "$new_content_b64" \
    --arg sha "$file_sha" \
    --arg branch "$update_branch" \
    --argjson sha_on_update "$sha_on_update" \
    'if $sha_on_update == 1
     then {message: $message, content: $content, sha: $sha, branch: $branch}
     else {message: $message, content: $content, branch: $branch}
     end' > "$put_file"

  retry_gh "$file_path" '' gh api --method PUT "repos/$ORG/$repo_name/contents/$file_path" --input "$put_file"
  rm -f "$put_file"

  if [[ "$RETRY_OK" -eq 0 ]]; then
    echo "  [$base_branch] $file_path commit failed: ${RETRY_ERR:-no message}"
    record_unfinished "$repo_name [$base_branch]: $file_path commit: ${RETRY_ERR:-no message}"
    return 1
  fi
  echo "  [$base_branch] $file_path updated with missing jobs."
  FILES_LIST+="| \`.github/workflows/ci.yml\` | Updated (added missing jobs) |"$'\n'
  FILES_ADDED=$((FILES_ADDED + 1))
}

while IFS= read -r REPO_NAME; do
  echo "Checking $ORG/$REPO_NAME..."

  # Warning: read the exit status. A failed read arrives as the error JSON, which matches no
  # branch pattern below. The repository would then look like one with no supported branch,
  # and the fallback further down would aim the sweep at `master`.
  #
  # The read is paginated, because a page holds 100 branches and a repository can carry more.
  # Two `??.x` branches among 150 others is the case the flag covers. `gh` sets `per_page=100`
  # itself under `--paginate`, so the path names no page size. A failed page fails the read,
  # and `read_exists` blanks the body, so no partial list reaches the loop below.
  read_exists "repos/$ORG/$REPO_NAME/branches" '.[].name' paginate
  ALL_BRANCHES="$READ_BODY"

  if [[ "$READ_STATE" != "ok" ]]; then
    echo "  Could not read the branch list, skipping: $READ_MESSAGE"

    if [[ "$READ_STATE" == "unread" ]]; then
      record_unfinished "$REPO_NAME: branch list: $READ_MESSAGE"
    fi

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

  # Which required-workflows/<lang>/ directory this repo draws from.
  # Empty means the repo has no language-specific flavor (or is excluded
  # from one), and the language-agnostic root templates are used instead.
  LANG_DIR=""
  for FLAVOR in "${LANG_DIRS[@]}"; do
    if [[ "$REPO_NAME" == *-"$FLAVOR" ]]; then
      LANG_DIR="$FLAVOR"
      break
    fi
  done

  if [[ "$LANG_DIR" == "php" ]] && [[ " $PHP_EXCLUDED_REPOS " == *" $REPO_NAME "* ]]; then
    LANG_DIR=""
  fi

  while IFS= read -r BASE_BRANCH; do
    [[ -z "$BASE_BRANCH" ]] && continue

    if [[ "$BASE_BRANCH" = "master" ]]; then
      UPDATE_BRANCH="deps/ensure-workflows"
    else
      UPDATE_BRANCH="deps/ensure-workflows-$BASE_BRANCH"
    fi

    read_exists "repos/$ORG/$REPO_NAME/git/ref/heads/$UPDATE_BRANCH" '.object.sha'
    BRANCH_EXISTS="$READ_BODY"
    BRANCH_PREDATES_RUN="$READ_BODY"
    BRANCH_FAILED=""

    if [[ "$READ_STATE" == "unread" ]]; then
      echo "  [$BASE_BRANCH] Could not check for $UPDATE_BRANCH: $READ_MESSAGE"
      record_unfinished "$REPO_NAME [$BASE_BRANCH]: $UPDATE_BRANCH ref: $READ_MESSAGE"
      continue
    fi

    FILES_ADDED=0
    FILES_LIST=""

    add_workflows "$TEMPLATE_DIR" "$BASE_BRANCH" "$UPDATE_BRANCH" "$REPO_NAME" \
      "${REQUIRED_WORKFLOWS[@]}"

    LANG_TEMPLATE_DIR="$TEMPLATE_DIR"

    if [[ -n "$LANG_DIR" ]]; then
      LANG_TEMPLATE_DIR="$TEMPLATE_DIR/$LANG_DIR"

      add_workflows "$LANG_TEMPLATE_DIR" "$BASE_BRANCH" "$UPDATE_BRANCH" "$REPO_NAME" \
        "${LANG_WORKFLOWS[@]}"
    fi

    add_workflows "$LANG_TEMPLATE_DIR" "$BASE_BRANCH" "$UPDATE_BRANCH" "$REPO_NAME" \
      "${SHARED_WORKFLOWS[@]}"

    ensure_ci_jobs "$BASE_BRANCH" "$UPDATE_BRANCH" "$REPO_NAME" \
      "$LANG_TEMPLATE_DIR/$CI_WORKFLOW" || true

    # A file read asks the update branch, so a branch already carrying every file adds nothing.
    # Without the check below such a branch never reaches the pull request path again, and its
    # commits sit where no pull request shows them.
    BRANCH_AHEAD=0

    if [[ "$FILES_ADDED" -eq 0 ]] && [[ -n "$BRANCH_EXISTS" ]]; then
      if branch_carries_unmerged_work "$BASE_BRANCH" "$UPDATE_BRANCH" "$REPO_NAME"; then
        BRANCH_AHEAD=1
      fi
    fi

    if [[ "$FILES_ADDED" -gt 0 ]] || [[ "$BRANCH_AHEAD" -eq 1 ]]; then
      echo "  [$BASE_BRANCH] $FILES_ADDED file(s) added/updated this run — checking for existing PR..."

      if [[ -z "$FILES_LIST" ]]; then
        FILES_LIST="| — | The branch already carried every file this run would add. |"$'\n'
      fi

      # `read_exists` reads `gh api`, and this reads `gh pr list`, so it applies the same rule
      # by hand: the exit status decides. A failed list takes the create path below, and that
      # create's own outcome then says whether the sweep left anything undone. A branch carrying
      # commits and no pull request is worse than a create that fails on one already there.
      #
      # `--head` asks the server the question. `gh pr list` pages at 30, so a repository with
      # more open pull requests than that can hold this branch's outside the page. A filter over
      # the page would then answer a definite no.
      retry_gh "pull requests for $UPDATE_BRANCH" '' gh pr list --repo "$ORG/$REPO_NAME" \
        --state open \
        --head "$UPDATE_BRANCH" \
        --json headRefName \
        --jq 'first | .headRefName // ""'
      EXISTING_PR="$RETRY_OUT"

      if [[ "$RETRY_OK" -eq 0 ]]; then
        echo "  [$BASE_BRANCH] Could not list pull requests: ${RETRY_ERR:-no message}"
        EXISTING_PR=""
      fi

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

        # Keep the reason. This create is the one a failed pull request list hands off to, and
        # only the message separates its two answers. GitHub refuses a create because the pull
        # request is open already, and that refusal leaves nothing undone. Every other refusal
        # leaves commits on a branch that no pull request shows, so the count below takes it.
        #
        # Keep the URL too. `gh pr create` writes the new pull request's address to stdout, and
        # an operator reads that line to find what the sweep opened.
        retry_gh "pull request for $UPDATE_BRANCH" 'already exists' gh pr create \
          --repo "$ORG/$REPO_NAME" \
          --title "[Workflow] ci: Ensure required workflow files" \
          --body "$BODY" \
          --base "$BASE_BRANCH" \
          --head "$UPDATE_BRANCH"

        if [[ "$RETRY_OK" -eq 0 ]]; then
          echo "  [$BASE_BRANCH] PR creation failed: ${RETRY_ERR:-no message}"

          if [[ "$RETRY_ERR" != *"already exists"* ]]; then
            record_unfinished "$REPO_NAME [$BASE_BRANCH]: PR creation failed: ${RETRY_ERR:-no message}"
          fi
        else
          echo "  [$BASE_BRANCH] PR created: $RETRY_OUT"
        fi
      else
        echo "  [$BASE_BRANCH] PR already exists, skipping."
      fi
    fi
  done <<< "$BASE_BRANCHES"
done <<< "$REPOS"

# Every step above either finishes its work or leaves the sweep without a result it can use.
# The count decides the exit, because a log line alone reports a clean run.
if [[ "$UNFINISHED" -gt 0 ]]; then
  echo "$UNFINISHED step(s) did not finish. The sweep cannot report a clean run."
  printf '%s\n' "${UNFINISHED_WORK#$'\n'}"
  exit 1
fi
