#!/usr/bin/env bash
#
# This file is part of the Valkyrja GitHub package.
#
# Copyright (c) 2016-present Melech Mizrachi
#
# Released under the MIT License. See LICENSE.md for details.
#
# ---------------------------------------------------------------------------
# Local clone of the Claude review.
#
# This script runs the review of `_claude-review.yml` on your machine before
# the push. It reads the prompt, the model, the verdict schema and the tool
# lists from the workflow and its prompt file. So the clone follows the bot
# when the bot changes.
#
# The script leaves out the tools that reach a pull request on GitHub,
# because no pull request exists yet. The reviewer writes its findings in the
# structured output, not in inline comments.
#
# Each draw starts with no memory of an earlier draw, as the bot does. A
# reviewer that remembers its own findings tends to accept their fixes. So
# the script runs `claude` in `--safe-mode`, with no auto-memory and no user
# settings. The prompt tells the reviewer to read the guides of the
# repository, as the prompt tells the bot.
#
# The reviewer reads the guides from the local architecture checkout,
# ARCHITECTURE_DIR. The default is the `architecture` directory beside the
# `.github` checkout. The script warns when one of these is true:
#
#   - The architecture checkout is on a branch that the bot does not read.
#   - The architecture checkout is behind that branch.
#   - The architecture checkout has uncommitted changes.
#   - The `.github` checkout lacks commits of the base branch.
#   - The review instructions in the `.github` checkout have uncommitted
#     changes.
#
# The push sends HEAD, so the working tree must match HEAD. The script stops
# when the working tree has a change that is not committed.
#
# A draw is one run of `claude`. The same reviewer finds different things in
# the same code, so one draw shows only part of what the bot can find. The
# script runs DRAWS draws in parallel. The script passes only when every draw
# is clean.
#
# Run the script from the repository under review. BASE is the branch that
# the pull request goes into, and the script requires it. DRAWS is 2 by
# default. OUTPUT_DIR keeps the findings of each draw. The
# default is a new temporary directory.
#
# Requires: `claude` (logged in) and `jq`.
#
# Exit codes:
#
#   0  Every draw approves, with no blocking and no advisory finding.
#   1  A draw reports a finding.
#   2  A draw does not complete, or the review cannot start.
#
# Usage:
#
#     path/to/.github/scripts/local-review.sh BASE
#     DRAWS=3 path/to/.github/scripts/local-review.sh 26.x
# ---------------------------------------------------------------------------

# No workflow runs this script, so it sets `-euo pipefail`. Every failure to
# start goes through `fail`, which exits 2.
set -euo pipefail

# Stops the review before it starts, with the exit code that says so.
fail() {
  printf '%s\n' "$1" >&2
  exit 2
}

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
GITHUB_ROOT="$(dirname -- "$SCRIPT_DIR")"
PROMPT_FILE="$GITHUB_ROOT/.github/ci/claude-review/prompt.md"
WORKFLOW_FILE="$GITHUB_ROOT/.github/workflows/_claude-review.yml"

DRAWS="${DRAWS:-2}"
ARCHITECTURE_DIR="${ARCHITECTURE_DIR:-$(dirname -- "$GITHUB_ROOT")/architecture}"

[[ "$DRAWS" =~ ^[1-9][0-9]*$ ]] || fail "DRAWS must be a positive whole number, not '$DRAWS'."

command -v claude > /dev/null || fail 'No claude command. Install Claude Code and log in.'
command -v jq > /dev/null || fail 'No jq command. Install jq.'

REPO_ROOT="$(git rev-parse --show-toplevel 2> /dev/null)" || fail 'Run this from inside a git repository.'

# The default branch of a repository can differ from the branch its pull requests go into, so
# the caller names the base branch.
BASE_REF="${1:-}"

[[ -n "$BASE_REF" ]] || fail 'Name the base branch, such as 26.x.'

# The bot falls back to the default branch of the repository under review for the guides. The
# script asks the remote, because the local `origin/HEAD` changes only on a clone.
DEFAULT_REF="$(git -C "$REPO_ROOT" ls-remote --symref origin HEAD 2> /dev/null \
  | sed -n 's|^ref: refs/heads/\([^[:space:]]*\).*|\1|p' | sed -n 1p || true)"

[[ -s "$PROMPT_FILE" ]] || fail "No review prompt at $PROMPT_FILE."
[[ -f "$WORKFLOW_FILE" ]] || fail "No review workflow at $WORKFLOW_FILE."
[[ -f "$ARCHITECTURE_DIR/AGENTS.md" ]] || fail "No architecture checkout at $ARCHITECTURE_DIR. Set ARCHITECTURE_DIR."

# Each draw runs from the repository root, so a relative path has to become absolute first.
ARCHITECTURE_DIR="$(cd -- "$ARCHITECTURE_DIR" && pwd)"

# Reads the value of one `claude_args` flag from the workflow, without its quotes. The second
# `sed` keeps the first match and reads to the end, so a second match never breaks the pipe.
read_workflow_flag() {
  local flag="$1"

  sed -n "s/^ *$flag ['\"]\(.*\)['\"] *$/\1/p" "$WORKFLOW_FILE" | sed -n 1p
}

MODEL="$(sed -n 's/^ *--model \([^ ]*\) *$/\1/p' "$WORKFLOW_FILE" | sed -n 1p)"
SCHEMA="$(read_workflow_flag '--json-schema')"
DISALLOWED_TOOLS="$(read_workflow_flag '--disallowedTools')"

# The GitHub tools are the MCP comment tools and every `gh` call. Each one reaches a pull request
# that does not exist yet, and some name it through a workflow expression. `grep -v` exits 1 when
# it keeps nothing, which is the empty list the guard below reports.
ALLOWED_TOOLS="$(read_workflow_flag '--allowedTools' | tr ',' '\n' \
  | { grep -v -e '^mcp__' -e '^Bash(gh ' || true; } | paste -s -d ',' -)"

[[ -n "$MODEL" ]] || fail "No --model in $WORKFLOW_FILE."
[[ -n "$SCHEMA" ]] || fail "No --json-schema in $WORKFLOW_FILE."
[[ -n "$DISALLOWED_TOOLS" ]] || fail "No --disallowedTools in $WORKFLOW_FILE."
[[ -n "$ALLOWED_TOOLS" ]] || fail "No --allowedTools in $WORKFLOW_FILE."

# The reviewer reads the files on disk, and the push sends HEAD. A new file that is not committed
# is on disk too, so the check counts untracked files as well.
[[ -z "$(git -C "$REPO_ROOT" status --porcelain)" ]] \
  || fail 'The working tree has changes that are not committed. Commit them, then review.'

# The instructions come from this `.github` checkout. The instructions land on the version
# branch, the same branch as the base branch of the change, and `master` follows only by hand.
# So a checkout that lacks commits of that branch reviews with old instructions.
if git -C "$GITHUB_ROOT" fetch --quiet origin "+refs/heads/$BASE_REF:refs/remotes/origin/$BASE_REF" 2> /dev/null; then
  BEHIND="$(git -C "$GITHUB_ROOT" rev-list --count "HEAD..origin/$BASE_REF" 2> /dev/null || echo 0)"

  if [[ "$BEHIND" -gt 0 ]]; then
    printf 'Warning: the .github checkout lacks %s commit(s) of origin/%s. Merge or pull them.\n' \
      "$BEHIND" "$BASE_REF" >&2
  fi
fi

# The bot reads the committed instructions. An edit that is not committed changes what the clone
# reads and not what the bot reads.
INSTRUCTION_FILES=('.github/ci/claude-review/prompt.md' '.github/workflows/_claude-review.yml')

if [[ -n "$(git -C "$GITHUB_ROOT" status --porcelain -- "${INSTRUCTION_FILES[@]}" 2> /dev/null)" ]]; then
  echo 'Warning: the review instructions in the .github checkout have uncommitted changes.' >&2
fi

# Reports whether the architecture repository holds the branch: 0 when it does, 1 when it does
# not, and 2 when the query failed. `checkout-architecture-guides.sh` makes the same test.
architecture_has_branch() {
  local candidate="$1"
  local status=0

  [[ -n "$candidate" ]] || return 1

  git -C "$ARCHITECTURE_DIR" ls-remote --exit-code --heads origin "refs/heads/$candidate" > /dev/null 2>&1 \
    || status=$?

  case "$status" in
    0) return 0 ;;
    2) return 1 ;;
    *) return 2 ;;
  esac
}

# The branch the bot reads the guides from, by the fallbacks `checkout-architecture-guides.sh`
# takes: the base branch, then the default branch of the repository under review, then the
# default branch of the architecture repository. The value is empty when the query failed.
GUIDES_REF=''
GUIDES_STATUS=0
architecture_has_branch "$BASE_REF" || GUIDES_STATUS=$?

if [[ "$GUIDES_STATUS" -eq 0 ]]; then
  GUIDES_REF="$BASE_REF"
elif [[ "$GUIDES_STATUS" -eq 1 ]]; then
  if [[ "$BASE_REF" != "$DEFAULT_REF" ]] && architecture_has_branch "$DEFAULT_REF"; then
    GUIDES_REF="$DEFAULT_REF"
  else
    GUIDES_REF="$(git -C "$ARCHITECTURE_DIR" ls-remote --symref origin HEAD 2> /dev/null \
      | sed -n 's|^ref: refs/heads/\([^[:space:]]*\).*|\1|p' | sed -n 1p || true)"
  fi
fi

if [[ -z "$GUIDES_REF" ]]; then
  echo 'Warning: could not ask the architecture repository which branch the bot reads.' >&2
else
  ARCHITECTURE_BRANCH="$(git -C "$ARCHITECTURE_DIR" branch --show-current 2> /dev/null || true)"

  # The bot reads the tip of that branch, so a checkout behind it judges against old guides. On
  # another branch, the count would measure how far the two branches diverge, so it is skipped.
  if [[ "$ARCHITECTURE_BRANCH" != "$GUIDES_REF" ]]; then
    printf 'Warning: the guides are read from %s, but the bot reads them from %s.\n' \
      "${ARCHITECTURE_BRANCH:-a detached HEAD}" "$GUIDES_REF" >&2
  elif git -C "$ARCHITECTURE_DIR" fetch --quiet origin "$GUIDES_REF" 2> /dev/null; then
    BEHIND="$(git -C "$ARCHITECTURE_DIR" rev-list --count "HEAD..origin/$GUIDES_REF" 2> /dev/null || echo 0)"

    if [[ "$BEHIND" -gt 0 ]]; then
      printf 'Warning: the architecture checkout is %s commit(s) behind origin/%s. Pull it.\n' \
        "$BEHIND" "$GUIDES_REF" >&2
    fi
  fi
fi

if [[ -n "$(git -C "$ARCHITECTURE_DIR" status --porcelain --untracked-files=no 2> /dev/null)" ]]; then
  echo 'Warning: the architecture checkout has uncommitted changes, which the bot does not see.' >&2
fi

# The explicit refspec updates `origin/$BASE_REF` even in a clone that tracks one branch. Without
# that ref, the reviewer cannot read the diff and could approve a change it never saw.
git -C "$REPO_ROOT" fetch --quiet origin "+refs/heads/$BASE_REF:refs/remotes/origin/$BASE_REF" \
  || fail "Could not fetch $BASE_REF from origin."
git -C "$REPO_ROOT" rev-parse --verify --quiet "origin/$BASE_REF" > /dev/null \
  || fail "origin/$BASE_REF does not resolve after the fetch."

if [[ -z "${OUTPUT_DIR:-}" ]]; then
  OUTPUT_DIR="$(mktemp -d "${TMPDIR:-/tmp}/local-review.XXXXXX")" || fail 'Could not make a temporary directory.'
fi

mkdir -p -- "$OUTPUT_DIR" 2> /dev/null && [[ -w "$OUTPUT_DIR" ]] || fail "Could not write to $OUTPUT_DIR."
OUTPUT_DIR="$(cd -- "$OUTPUT_DIR" && pwd)"

# The workflow adds a paragraph about the guides after the prompt. The script reads that paragraph
# from the workflow too: the lines of the `prompt:` block after the prompt output, without their
# indentation, with the local guides path in place of the runner path.
GUIDES_PARAGRAPH="$(awk '
  /steps\.prompt\.outputs\.prompt }}/ { found = 1; next }
  found && /^ {12}/ { sub(/^ {12}/, ""); print; started = 1; next }
  found && /^[[:space:]]*$/ { if (started) print; next }
  found { exit }
' "$WORKFLOW_FILE")"
RUNNER_GUIDES_DIR="\${{ runner.temp }}/architecture"
GUIDES_PARAGRAPH="${GUIDES_PARAGRAPH//"$RUNNER_GUIDES_DIR"/$ARCHITECTURE_DIR}"

[[ "$GUIDES_PARAGRAPH" == *"$ARCHITECTURE_DIR"* ]] || fail "No guides paragraph in the prompt of $WORKFLOW_FILE."

PROMPT="$(cat "$PROMPT_FILE")

$GUIDES_PARAGRAPH

This review runs before the pull request is opened, so there is no pull
request, no thread, and no inline comment tool. The change is
\`git diff origin/$BASE_REF...HEAD\`, and its commits are
\`git log origin/$BASE_REF..HEAD\`. Put every finding in \`summary\`
instead of an inline comment, each naming its file and line."

printf 'Reviewing %s against origin/%s with %s, %s draw(s). Findings go to %s.\n' \
  "$(git -C "$REPO_ROOT" rev-parse --short HEAD)" "$BASE_REF" "$MODEL" "$DRAWS" "$OUTPUT_DIR"

# `--safe-mode` turns off hooks, MCP servers, commands and agents from every source.
# `--setting-sources project` leaves out the settings of the user, such as permissions that grant
# more tools than the workflow does. The settings of the repository stay, as they do for the bot,
# which runs `claude` in a checkout of the repository.
PIDS=()

for ((DRAW = 1; DRAW <= DRAWS; DRAW++)); do
  (
    cd -- "$REPO_ROOT"
    CLAUDE_CODE_DISABLE_AUTO_MEMORY=1 claude -p "$PROMPT" \
      --safe-mode \
      --model "$MODEL" \
      --setting-sources project \
      --strict-mcp-config \
      --no-session-persistence \
      --add-dir "$ARCHITECTURE_DIR" \
      --allowedTools "$ALLOWED_TOOLS" \
      --disallowedTools "$DISALLOWED_TOOLS" \
      --json-schema "$SCHEMA" \
      --output-format json > "$OUTPUT_DIR/draw-$DRAW.json"
  ) &
  PIDS+=("$!")
done

STATUS=0

for INDEX in "${!PIDS[@]}"; do
  DRAW=$((INDEX + 1))
  RESULT="$OUTPUT_DIR/draw-$DRAW.json"

  if ! wait "${PIDS[$INDEX]}" || ! jq -e '.structured_output.verdict' "$RESULT" > /dev/null 2>&1; then
    printf '\n== Draw %s did not complete. Its output is in %s.\n' "$DRAW" "$RESULT"

    # The CLI says why a run stopped in `result`, as for an expired login, in `errors`, or only in
    # `subtype`, as for a run out of turns. The first of them that says anything is the reason.
    REASON="$(jq -r '[.result, ((.errors // []) | map(tostring) | join("; ")), .subtype]
      | map(select(type == "string" and . != "")) | first // empty' "$RESULT" 2> /dev/null || true)"

    if [[ -n "$REASON" ]]; then
      printf '\n%s\n' "$REASON"
    fi

    STATUS=2
    continue
  fi

  jq -r --arg draw "$DRAW" '.structured_output |
    "\n== Draw \($draw): \(.verdict), \(.blocking_findings) blocking, \(.advisory_findings) advisory\n\n\(.summary)"' "$RESULT"

  # Clean means the reviewer approved and counted nothing, so a verdict the counts contradict fails.
  if ! jq -e '.structured_output | .verdict == "approved" and .blocking_findings == 0 and .advisory_findings == 0' \
    "$RESULT" > /dev/null; then
    [[ "$STATUS" -eq 2 ]] || STATUS=1
  fi
done

case "$STATUS" in
  0) printf '\nEvery draw is clean. Push.\n' ;;
  1) printf '\nFix every finding above, commit, and run this again.\n' ;;
  2) printf '\nA draw did not complete, so the review is not clean.\n' ;;
  *) printf '\nThe review ended with status %s, which this script does not set.\n' "$STATUS" ;;
esac

exit "$STATUS"
