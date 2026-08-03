#!/usr/bin/env bash
#
# ---------------------------------------------------------------------------
# Commit message check report.
#
# Four checks run before this script, and each one reports its own outcome.
# This script turns those outcomes into the report a pull request comment
# carries, and it decides the result of the whole check.
#
# The four checks are separate steps because three of them are a third-party
# action rather than a script, so they cannot be one script. What they share is
# the message, and the message lives here.
#
# Reads COMMIT_TYPE_OUTCOME, NO_TRAILING_PERIOD_OUTCOME, LINE_LENGTH_OUTCOME,
# and PERIOD_AT_END_OUTCOME from the environment. Each holds a step outcome,
# which is `success`, `failure`, or `skipped`.
#
# Exits 1 when any check failed, so the caller reports the failure and posts
# what this script wrote.
#
# Usage:
#
#     COMMIT_TYPE_OUTCOME=success ... .github/ci/scripts/commit-message-report.sh
# ---------------------------------------------------------------------------

set -euo pipefail

: "${COMMIT_TYPE_OUTCOME:?COMMIT_TYPE_OUTCOME must hold the step outcome}"
: "${NO_TRAILING_PERIOD_OUTCOME:?NO_TRAILING_PERIOD_OUTCOME must hold the step outcome}"
: "${LINE_LENGTH_OUTCOME:?LINE_LENGTH_OUTCOME must hold the step outcome}"
: "${PERIOD_AT_END_OUTCOME:?PERIOD_AT_END_OUTCOME must hold the step outcome}"

FAILURES=()

if [[ "$COMMIT_TYPE_OUTCOME" == 'failure' ]]; then
    FAILURES+=('- The PR title and every commit must match `[Root] type: Description` — e.g. `[Http] fix: Normalize header casing.` Types: `feat`, `fix`, `deprecate`, `docs`, `test`, `refactor`, `perf`, `style`, `build`, `ci`, `chore`, `revert`. Add `!` before the colon for a breaking change, and `(#123)` for an issue.')
fi

if [[ "$NO_TRAILING_PERIOD_OUTCOME" == 'failure' ]]; then
    FAILURES+=('- PR title must not end with a period')
fi

if [[ "$LINE_LENGTH_OUTCOME" == 'failure' ]]; then
    FAILURES+=('- No commit message line may exceed 120 characters')
fi

if [[ "$PERIOD_AT_END_OUTCOME" == 'failure' ]]; then
    FAILURES+=('- Each commit message (excluding PR title) must end with a period')
fi

if [[ "${#FAILURES[@]}" -eq 0 ]]; then
    echo 'Every commit message check passed.'

    exit 0
fi

printf 'One or more commit message checks failed:\n\n'
printf '%s\n' "${FAILURES[@]}"

exit 1
