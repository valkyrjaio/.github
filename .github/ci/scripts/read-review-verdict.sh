#!/usr/bin/env bash
#
# This file is part of the Valkyrja GitHub package.
#
# Copyright (c) 2016-present Melech Mizrachi
#
# Released under the MIT License. See LICENSE.md for details.
#
# ---------------------------------------------------------------------------
# Claude review verdict reader.
#
# The reviewer writes a structured block, and this script reads the verdict,
# the summary, and the two finding lists out of it. It writes each one to
# GITHUB_OUTPUT for the jobs that report and post them.
#
# A review that did not finish has no verdict, whatever it left behind, so the
# script reports that case rather than parsing it.
#
# Reads REVIEW_OUTCOME, STRUCTURED_OUTPUT, and GITHUB_OUTPUT from the
# environment.
#
# Usage:
#
#     .github/ci/scripts/read-review-verdict.sh
# ---------------------------------------------------------------------------

# Warning: `-u` and `pipefail` are deliberately absent. This script carries a
# block from a `run:` step that names no shell, and GitHub runs that as
# `bash -e {0}`.
#
# An action step is the other case. It names `shell: bash`, which is
# `bash --noprofile --norc -eo pipefail`, so a script it invokes sets
# `pipefail`. Read the shell before you copy a `set` line between the two.
set -e

# A review that did not finish has no verdict to report, whatever it left in its output.
if [[ "$REVIEW_OUTCOME" != 'success' ]]; then
  echo 'The review did not complete, so it reports no verdict.'
  printf 'verdict=errored\nsummary=%s\nblocking-findings=\nadvisory-findings=\n' \
    'The review did not complete. Read the job log for what stopped it.' >> "$GITHUB_OUTPUT"
  exit 0
fi

# `--json-schema` is what fills `structured_output`. An empty or malformed value means the
# reviewer did not meet the contract, which is reported as no verdict rather than guessed
# at — a run that says nothing must never read as an approval.
if ! VERDICT="$(jq -er '.verdict' <<< "$STRUCTURED_OUTPUT" 2> /dev/null)"; then
  echo 'The review produced no structured verdict.' >&2
  printf 'verdict=unknown\nsummary=%s\nblocking-findings=\nadvisory-findings=\n' \
    'The review finished, and it reported no verdict.' >> "$GITHUB_OUTPUT"
  exit 0
fi

# Warning: every field below is text a language model wrote, after reading a diff, a title,
# and a description that this run does not control. `GITHUB_OUTPUT` is a `key=value` file,
# so a newline in a value declares a second output. That is how text under review would
# forge the verdict this job exists to make trustworthy. Each field is therefore checked
# against a shape that cannot carry one, and the one field that must hold a newline gets a
# delimiter that cannot be predicted.
case "$VERDICT" in
  approved | changes_requested | commented) ;;
  *)
    printf 'The review reported a verdict this workflow does not know: %s\n' "$VERDICT" >&2
    printf 'verdict=unknown\nsummary=%s\nblocking-findings=\nadvisory-findings=\n' \
      'The review finished, and it reported a verdict this workflow does not know.' >> "$GITHUB_OUTPUT"
    exit 0
    ;;
esac

# A number reaches an action output as a string, so every field is read as text.
SUMMARY="$(jq -r '.summary // ""' <<< "$STRUCTURED_OUTPUT")"
BLOCKING="$(jq -r '.blocking_findings // "" | tostring' <<< "$STRUCTURED_OUTPUT")"
ADVISORY="$(jq -r '.advisory_findings // "" | tostring' <<< "$STRUCTURED_OUTPUT")"

# A count that is not a count is dropped. It is written for a reader, and a wrong one
# reads as fact.
[[ "$BLOCKING" =~ ^[0-9]+$ ]] || BLOCKING=''
[[ "$ADVISORY" =~ ^[0-9]+$ ]] || ADVISORY=''

# GitHub's guidance for the heredoc form is a delimiter that cannot appear in the value.
# A fixed word would sit in this file for anybody to read, and a summary that repeated it
# would close the value early and turn every later line into an output of its own.
DELIMITER="CLAUDE_REVIEW_EOF_$(openssl rand -hex 16)"

printf 'The review reports the %s verdict.\n' "$VERDICT"

{
  printf 'verdict=%s\n' "$VERDICT"
  printf 'blocking-findings=%s\n' "$BLOCKING"
  printf 'advisory-findings=%s\n' "$ADVISORY"

  # The summary is the reviewer's prose, so it holds newlines.
  printf 'summary<<%s\n%s\n%s\n' "$DELIMITER" "$SUMMARY" "$DELIMITER"
} >> "$GITHUB_OUTPUT"
