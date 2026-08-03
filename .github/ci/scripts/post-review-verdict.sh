#!/usr/bin/env bash
#
# This file is part of the Valkyrja GitHub package.
#
# Copyright (c) 2016-present Melech Mizrachi
#
# Released under the MIT License. See LICENSE.md for details.
#
# ---------------------------------------------------------------------------
# Claude review verdict.
#
# The review writes a verdict, and this script submits it as a pull request
# review. It posts an approval, a comment, or a request for changes, and it
# writes the outcome for the job that reads it.
#
# Reads GH_TOKEN, GH_REPO, PR_NUMBER, APP_SLUG, VERDICT, SUMMARY, BLOCKING,
# ADVISORY, REQUEST_CHANGES, GITHUB_OUTPUT, and GITHUB_STEP_SUMMARY from the
# environment. It writes the verdict to GITHUB_OUTPUT, and the report a person
# reads to GITHUB_STEP_SUMMARY.
#
# Usage:
#
#     .github/ci/scripts/post-review-verdict.sh
# ---------------------------------------------------------------------------

# Warning: this script carries a block from a composite action, and an action
# step names `shell: bash`. That form is `bash --noprofile --norc -eo pipefail`,
# so the block already ran with `pipefail` and the script keeps it.
#
# A script that a bare `run:` step invokes is the other case, and it sets
# `set -e` alone. A `run:` step that names no shell gives `bash -e` and no
# `pipefail`. Read the shell before you copy a `set` line between the two.
#
# `-u` is absent, because the block ran without it.
set -eo pipefail

# The review event GitHub accepts from anybody, including the author of the pull
# request. Every branch below falls back to it, so it is named rather than
# repeated.
readonly COMMENT_EVENT='COMMENT'

if [[ -z "$PR_NUMBER" ]]; then
  echo 'No pull request number, so there is no review to submit.'
  exit 0
fi

case "$VERDICT" in
  approved)
    EVENT='APPROVE'
    HEADING='Approved'
    ;;
  changes_requested)
    HEADING='Changes requested'
    # The default is a comment. See the `request-changes` input for why a block is opt in.
    if [[ "$REQUEST_CHANGES" == 'true' ]]; then
      EVENT='REQUEST_CHANGES'
    else
      EVENT="$COMMENT_EVENT"
    fi
    ;;
  commented)
    EVENT="$COMMENT_EVENT"
    HEADING='Commented'
    ;;
  errored)
    EVENT="$COMMENT_EVENT"
    HEADING='The review did not complete'
    ;;
  *)
    # A verdict this action does not know is reported as one, never guessed at. A run whose
    # structured output was empty or malformed must not read as an approval.
    EVENT="$COMMENT_EVENT"
    HEADING='No verdict'
    VERDICT='unknown'
    ;;
esac

# GitHub refuses `APPROVE` and `REQUEST_CHANGES` from the author of the pull request with a
# 422, and an installation token reviews as the app's own bot user. Nothing labels a bot's
# pull request today, so this cannot happen yet; it is guarded because the day it can, the
# failure would be a red job on a pull request that is otherwise fine.
AUTHOR="$(gh api "repos/$GH_REPO/pulls/$PR_NUMBER" --jq '.user.login')"

if [[ "$AUTHOR" == "${APP_SLUG}[bot]" && "$EVENT" != "$COMMENT_EVENT" ]]; then
  printf 'The pull request is authored by %s[bot], which cannot review itself.\n' "$APP_SLUG"
  echo 'The verdict is submitted as a comment instead.'
  EVENT="$COMMENT_EVENT"
fi

# A count is written only when it is one. The reviewer produces these, so a value that is
# not a number means the contract was not met, and a wrong count reads as fact.
COUNTS=''

if [[ "$BLOCKING" =~ ^[0-9]+$ && "$ADVISORY" =~ ^[0-9]+$ ]]; then
  COUNTS="$BLOCKING blocking, $ADVISORY advisory."
fi

{
  printf '### Claude review: %s\n\n' "$HEADING"

  if [[ -n "$COUNTS" ]]; then
    printf '%s\n\n' "$COUNTS"
  fi

  # A `COMMENT` review with an empty body is a 422, so the body always says something.
  printf '%s\n' "${SUMMARY:-The reviewer produced no summary.}"

  # The marker is what reads the verdict back without parsing prose.
  printf '\n<!-- claude-review-verdict: %s -->\n' "$VERDICT"
} > review.md

submit_review() {
  local event="$1"

  # The body is passed as JSON rather than as a `-f` field. `gh` converts a field value that
  # looks like a number or a boolean, and a summary is arbitrary text.
  jq -n --arg event "$event" --rawfile body review.md '{event: $event, body: $body}' \
    | gh api --method POST "repos/$GH_REPO/pulls/$PR_NUMBER/reviews" --input - --silent
}

if submit_review "$EVENT"; then
  printf 'Submitted a %s review carrying the %s verdict.\n' "$EVENT" "$VERDICT"
elif [[ "$EVENT" == "$COMMENT_EVENT" ]]; then
  echo 'The verdict could not be submitted as a review.' >&2
  exit 1
else
  # A refusal must not lose the verdict. Whatever GitHub declined to accept as a state, it
  # accepts as a comment, and a comment with the marker still says what the reviewer found.
  printf 'GitHub refused a %s review, so the verdict is submitted as a comment.\n' "$EVENT" >&2
  EVENT="$COMMENT_EVENT"

  if ! submit_review "$EVENT"; then
    echo 'The verdict could not be submitted as a review.' >&2
    exit 1
  fi
fi

{
  printf 'event=%s\n' "$EVENT"
  printf 'verdict=%s\n' "$VERDICT"
} >> "$GITHUB_OUTPUT"

{
  printf '### Claude review: %s\n\n' "$HEADING"

  if [[ -n "$COUNTS" ]]; then
    printf '%s\n\n' "$COUNTS"
  fi

  # shellcheck disable=SC2016 # The backticks are Markdown, and the format holds no expansion.
  printf 'Submitted as a `%s` review.\n' "$EVENT"
} >> "$GITHUB_STEP_SUMMARY"
