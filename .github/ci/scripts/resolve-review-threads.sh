#!/usr/bin/env bash
#
# This file is part of the Valkyrja GitHub package.
#
# Copyright (c) 2016-present Melech Mizrachi
#
# Released under the MIT License. See LICENSE.md for details.
#
# ---------------------------------------------------------------------------
# Review thread resolution.
#
# A later review run answers the threads an earlier run opened. This script
# resolves each thread that the app itself wrote before a given time, so a
# reader sees only the threads the current run stands behind.
#
# Reads GH_TOKEN, OWNER, REPO, PR_NUMBER, APP_SLUG, BEFORE, and GITHUB_OUTPUT from the environment.
#
# Usage:
#
#     .github/ci/scripts/resolve-review-threads.sh
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

if [[ -z "$PR_NUMBER" ]]; then
  echo 'No pull request number, so there are no threads to resolve.'
  printf 'resolved=0\n' >> "$GITHUB_OUTPUT"
  exit 0
fi

if [[ ! "$BEFORE" =~ ^[0-9]{4}(-[0-9]{2}){2}T([0-9]{2}:){2}[0-9]{2}Z$ ]]; then
  echo "Not a UTC timestamp: $BEFORE" >&2
  echo 'Threads are compared against it as text, so a different shape would compare wrong.' >&2
  exit 1
fi

# A thread is a review thread, and REST has no notion of resolving one. `resolveReviewThread`
# is a GraphQL mutation, so the read is GraphQL too, for the node ids it takes.
#
# Warning: `--paginate` needs both the `$endCursor` variable and `pageInfo` in the selection.
# Without them a pull request with more than 100 threads silently reports its first page.
# shellcheck disable=SC2016 # `$owner` and the rest are GraphQL variables, not shell ones.
QUERY='
  query($owner: String!, $repo: String!, $number: Int!, $endCursor: String) {
    repository(owner: $owner, name: $repo) {
      pullRequest(number: $number) {
        reviewThreads(first: 100, after: $endCursor) {
          pageInfo { hasNextPage endCursor }
          nodes {
            id
            isResolved
            comments(first: 100) { nodes { createdAt author { login } } }
          }
        }
      }
    }
  }
'

# A bot reports its slug as its login here, without the `[bot]` suffix the REST API adds.
#
# Warning: `all` over an empty list is true, so a thread with no comments would match every
# test below. There should be no such thread, and one must not be resolved on that basis.
THREAD_IDS="$(
  gh api graphql --paginate \
    -f owner="$OWNER" -f repo="$REPO" -F number="$PR_NUMBER" -f query="$QUERY" \
    | jq -r --arg bot "$APP_SLUG" --arg before "$BEFORE" '
        .data.repository.pullRequest.reviewThreads.nodes[]
        | select(.isResolved | not)
        | select((.comments.nodes | length) > 0)
        | select(all(.comments.nodes[]; .author.login == $bot and .createdAt < $before))
        | .id
      '
)"

if [[ -z "$THREAD_IDS" ]]; then
  echo 'No thread from an earlier run is still open.'
  printf 'resolved=0\n' >> "$GITHUB_OUTPUT"
  exit 0
fi

# shellcheck disable=SC2016 # `$threadId` is a GraphQL variable, not a shell one.
MUTATION='
  mutation($threadId: ID!) {
    resolveReviewThread(input: {threadId: $threadId}) { thread { id } }
  }
'

RESOLVED=0

# Warning: never let one failure end the step. Housekeeping must not decide the job result,
# and a thread another run resolved first would otherwise turn a finished review red.
while IFS= read -r THREAD_ID; do
  if gh api graphql -f threadId="$THREAD_ID" -f query="$MUTATION" --silent; then
    RESOLVED=$((RESOLVED + 1))
    echo "Resolved $THREAD_ID, which an earlier run left open."
  else
    echo "Could not resolve $THREAD_ID." >&2
  fi
done <<< "$THREAD_IDS"

printf 'Resolved %s of the threads earlier runs left open.\n' "$RESOLVED"
printf 'resolved=%s\n' "$RESOLVED" >> "$GITHUB_OUTPUT"
