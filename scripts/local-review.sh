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
# the push. The script reads the prompt, the model, the verdict schema and
# the tool lists from the workflow and its prompt file. So the clone follows
# the bot when the bot changes.
#
# The script leaves out the tools that reach a pull request on GitHub,
# because no pull request exists yet. The reviewer writes its findings in the
# structured output, not in inline comments.
#
# Each draw starts with no memory of an earlier draw, as the bot does. A
# reviewer that remembers its own findings tends to accept their fixes. So
# each draw is a new session with no auto-memory and no user settings.
#
# Each draw also runs in `--safe-mode`, which keeps out every CLAUDE.md. A
# CLAUDE.md of the user or of a parent directory holds rules that the bot
# never reads. The repository CLAUDE.md goes out with them, so the prompt
# sends the reviewer to the guides of the repository, as it does the bot.
#
# Warning: `--safe-mode` also turns off skills, plugins, hooks, MCP servers,
# custom commands and agents, output styles and workflows, and the bot keeps
# all of them. In a repository that ships any of them, a draw is not an exact
# copy of the bot.
#
# The reviewer reads the guides from the local architecture checkout,
# ARCHITECTURE_DIR. The default is the `architecture` directory beside the
# `.github` checkout. The script warns when one of these is true:
#
#   - The architecture checkout is on a branch that the bot does not read.
#   - The architecture checkout is behind or ahead of that branch.
#   - The architecture checkout has uncommitted changes or untracked files.
#   - The review instructions in the `.github` checkout differ from the tip of
#     the base branch. The bot reads the `.github` ref that its caller pins.
#     That ref can be older than the tip, so this warning is only a hint.
#   - The review instructions in the `.github` checkout have uncommitted
#     changes.
#
# The push sends HEAD, so the working tree must match HEAD. The script stops
# when the working tree has a change that is not committed. Untracked files
# under `.claude/` are Claude Code state, and the script does not count them.
#
# When a pull request for the branch already exists and `gh` can read it, the
# prompt names its title, as the bot sees it.
#
# A draw is one run of `claude`. The same reviewer finds different things in
# the same code, so one draw shows only part of what the bot can find. The
# script runs DRAWS draws in parallel. The script passes only when every draw
# is clean.
#
# Run the script from the repository under review. BASE is the branch that
# the pull request goes into, and the script requires it. DRAWS is 2 by
# default. OUTPUT_DIR keeps the findings of each draw. The default is a new
# temporary directory.
#
# Requires: `claude` (logged in), `jq`, and a local checkout of the
# architecture repository.
#
# Exit codes:
#
#   0  Every draw approves, with no blocking and no advisory finding.
#   1  A draw reports a finding.
#   2  A draw does not complete, or the review cannot start.
#
# Usage:
#
#     <dot-github>/scripts/local-review.sh BASE
#     DRAWS=3 <dot-github>/scripts/local-review.sh 26.x
#     <dot-github>/scripts/local-review.sh --help
#
# <dot-github> is the path to the local checkout of `valkyrjaio/.github`.
# ---------------------------------------------------------------------------

# A tool in `scripts/` sets `-euo pipefail`, and every failure to start exits 2 through `fail`.
# `.github/workflows/README.md` holds the rule for each family, under Scripts.
set -euo pipefail

# Stops the review before it starts, with the exit code that says so.
fail() {
  printf '%s\n' "$1" >&2
  exit 2
}

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
GITHUB_ROOT="$(dirname -- "$SCRIPT_DIR")"

# The help is the header of this file, from its title to the closing rule.
case "${1:-}" in
  -h | --help)
    sed -n '/^# Local clone of the Claude review/,/^# ---/p' "${BASH_SOURCE[0]}" | sed -e '$d' -e 's/^# \{0,1\}//'
    exit 0
    ;;
  *) ;;
esac

# The script takes one argument, so a second one is a mistake rather than an option.
[[ "$#" -le 1 ]] || fail "Too many arguments. Name only the base branch, and set DRAWS in the environment."

# The default branch of a repository can differ from the branch its pull requests go into, so
# the caller names the base branch.
BASE_REF="${1:-}"

[[ -n "$BASE_REF" ]] || fail 'Name the base branch, such as 26.x.'

DRAWS="${DRAWS:-2}"

# The default sits beside the main `.github` checkout, also when the script runs from a worktree.
MAIN_GIT_DIR="$(git -C "$GITHUB_ROOT" rev-parse --path-format=absolute --git-common-dir 2> /dev/null || true)"
MAIN_ROOT="$(dirname -- "${MAIN_GIT_DIR:-$GITHUB_ROOT/.git}")"
ARCHITECTURE_DIR="${ARCHITECTURE_DIR:-$(dirname -- "$MAIN_ROOT")/architecture}"

[[ "$DRAWS" =~ ^[1-9][0-9]*$ ]] || fail "DRAWS must be a positive whole number, not '$DRAWS'."

command -v claude > /dev/null || fail 'No claude command. Install Claude Code and log in.'
command -v jq > /dev/null || fail 'No jq command. Install jq.'

REPO_ROOT="$(git rev-parse --show-toplevel 2> /dev/null)" || fail 'Run this from inside a git repository.'

# The bot falls back to the default branch of the repository under review for the guides. The
# script asks the remote, because the local `origin/HEAD` changes only on a clone.
DEFAULT_REF="$(git -C "$REPO_ROOT" ls-remote --symref origin HEAD 2> /dev/null \
  | sed -n 's|^ref: refs/heads/\([^[:space:]]*\).*|\1|p' | sed -n 1p || true)"

# A `.github` change under review carries its own instructions, also from a worktree or a symlink.
GITHUB_GIT_DIR="$(git -C "$GITHUB_ROOT" rev-parse --path-format=absolute --git-common-dir 2> /dev/null || true)"
REPO_GIT_DIR="$(git -C "$REPO_ROOT" rev-parse --path-format=absolute --git-common-dir 2> /dev/null || true)"
REVIEWING_GITHUB=false

if [[ -n "$REPO_GIT_DIR" && "$GITHUB_GIT_DIR" == "$REPO_GIT_DIR" ]]; then
  REVIEWING_GITHUB=true
  GITHUB_ROOT="$REPO_ROOT"
fi

PROMPT_FILE="$GITHUB_ROOT/.github/ci/claude-review/prompt.md"
WORKFLOW_FILE="$GITHUB_ROOT/.github/workflows/_claude-review.yml"

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

# The MCP comment tools and the `gh` calls reach a pull request that does not exist yet. `grep -v`
# exits 1 when it keeps nothing, and the guard below reports that empty list.
ALLOWED_TOOLS="$(read_workflow_flag '--allowedTools' | tr ',' '\n' \
  | { grep -v -e '^mcp__' -e '^Bash(gh ' || true; } | paste -s -d ',' -)"

[[ -n "$MODEL" ]] || fail "No --model in $WORKFLOW_FILE."
[[ -n "$SCHEMA" ]] || fail "No --json-schema in $WORKFLOW_FILE."
[[ -n "$DISALLOWED_TOOLS" ]] || fail "No --disallowedTools in $WORKFLOW_FILE."
[[ -n "$ALLOWED_TOOLS" ]] || fail "No --allowedTools in $WORKFLOW_FILE."

# Lists what is not committed: tracked changes everywhere, and untracked files outside `.claude/`,
# which holds Claude Code state that no clone ignores.
uncommitted() {
  local root="$1"

  git -C "$root" status --porcelain --untracked-files=no 2> /dev/null || true
  git -C "$root" ls-files --others --exclude-standard -- . ':(exclude).claude' 2> /dev/null || true
}

[[ -z "$(uncommitted "$REPO_ROOT")" ]] \
  || fail 'The working tree has changes that are not committed. Commit them, then review.'

# The instructions in this `.github` checkout must match the base branch tip and be committed.
# The bot reads the canonical repository, not the `origin` of the local checkout, which can be a fork.
GITHUB_REMOTE='https://github.com/valkyrjaio/.github.git'
INSTRUCTION_FILES=('.github/ci/claude-review/prompt.md' '.github/workflows/_claude-review.yml')

if [[ "$REVIEWING_GITHUB" == 'false' ]]; then
  if git -C "$GITHUB_ROOT" fetch --quiet "$GITHUB_REMOTE" "refs/heads/$BASE_REF" 2> /dev/null; then
    git -C "$GITHUB_ROOT" diff --quiet FETCH_HEAD HEAD -- "${INSTRUCTION_FILES[@]}" 2> /dev/null \
      || printf 'Warning: the review instructions in the .github checkout differ from %s.\n' \
        "$BASE_REF" >&2
  else
    # A base branch that `.github` does not hold, such as a stacked branch, has nothing to compare.
    LS_STATUS=0
    git -C "$GITHUB_ROOT" ls-remote --exit-code --heads "$GITHUB_REMOTE" "refs/heads/$BASE_REF" > /dev/null 2>&1 \
      || LS_STATUS=$?

    if [[ "$LS_STATUS" -ne 2 ]]; then
      echo "Warning: could not fetch $BASE_REF into the .github checkout to check its instructions." >&2
    fi
  fi

  if [[ -n "$(git -C "$GITHUB_ROOT" status --porcelain -- "${INSTRUCTION_FILES[@]}" 2> /dev/null)" ]]; then
    echo 'Warning: the review instructions in the .github checkout have uncommitted changes.' >&2
  fi
fi

# The bot reads the canonical repository, not the `origin` of the local checkout, which can be a fork.
ARCHITECTURE_REMOTE='https://github.com/valkyrjaio/architecture.git'

# Reports whether the architecture repository holds the branch: 0 when it does, 1 when it does
# not, and 2 when the query failed. `checkout-architecture-guides.sh` makes the same test.
architecture_has_branch() {
  local candidate="$1"
  local status=0

  git -C "$ARCHITECTURE_DIR" ls-remote --exit-code --heads "$ARCHITECTURE_REMOTE" "refs/heads/$candidate" \
    > /dev/null 2>&1 \
    || status=$?

  case "$status" in
    0) return 0 ;;
    2) return 1 ;;
    *) return 2 ;;
  esac
}

# The script finds the guides branch by the fallbacks of `checkout-architecture-guides.sh`. The
# value is empty when any query failed.
GUIDES_REF=''
GUIDES_STATUS=0
architecture_has_branch "$BASE_REF" || GUIDES_STATUS=$?

if [[ "$GUIDES_STATUS" -eq 0 ]]; then
  GUIDES_REF="$BASE_REF"
elif [[ "$GUIDES_STATUS" -eq 1 ]]; then
  DEFAULT_STATUS=1

  # An empty DEFAULT_REF means its own query failed, which is not the same as an absent branch.
  if [[ -z "$DEFAULT_REF" ]]; then
    DEFAULT_STATUS=2
  elif [[ "$BASE_REF" != "$DEFAULT_REF" ]]; then
    DEFAULT_STATUS=0
    architecture_has_branch "$DEFAULT_REF" || DEFAULT_STATUS=$?
  fi

  if [[ "$DEFAULT_STATUS" -eq 0 ]]; then
    GUIDES_REF="$DEFAULT_REF"
  elif [[ "$DEFAULT_STATUS" -eq 1 ]]; then
    GUIDES_REF="$(git -C "$ARCHITECTURE_DIR" ls-remote --symref "$ARCHITECTURE_REMOTE" HEAD 2> /dev/null \
      | sed -n 's|^ref: refs/heads/\([^[:space:]]*\).*|\1|p' | sed -n 1p || true)"
  fi
fi

if [[ -z "$GUIDES_REF" && "$GUIDES_STATUS" -eq 1 && -z "$DEFAULT_REF" ]]; then
  echo 'Warning: could not ask origin of the repository under review for its default branch.' >&2
elif [[ -z "$GUIDES_REF" ]]; then
  echo 'Warning: could not ask the architecture repository which branch the bot reads.' >&2
else
  ARCHITECTURE_BRANCH="$(git -C "$ARCHITECTURE_DIR" branch --show-current 2> /dev/null || true)"

  # The bot reads the tip of that branch, so a checkout behind or ahead judges by other guides.
  # On another branch, the counts measure divergence instead, so the script skips them.
  if [[ "$ARCHITECTURE_BRANCH" != "$GUIDES_REF" ]]; then
    printf 'Warning: the guides are read from %s, but the bot reads them from %s.\n' \
      "${ARCHITECTURE_BRANCH:-a detached HEAD}" "$GUIDES_REF" >&2
  elif git -C "$ARCHITECTURE_DIR" fetch --quiet "$ARCHITECTURE_REMOTE" "refs/heads/$GUIDES_REF" 2> /dev/null; then
    COUNTS="$(git -C "$ARCHITECTURE_DIR" rev-list --left-right --count 'HEAD...FETCH_HEAD' 2> /dev/null || true)"

    [[ -n "$COUNTS" ]] \
      || echo "Warning: could not compare the architecture checkout with $GUIDES_REF." >&2
    AHEAD="${COUNTS%%[[:space:]]*}"
    BEHIND="${COUNTS##*[[:space:]]}"

    if [[ "${BEHIND:-0}" -gt 0 ]]; then
      printf 'Warning: the architecture checkout is %s commit(s) behind %s. Pull it.\n' \
        "$BEHIND" "$GUIDES_REF" >&2
    fi

    if [[ "${AHEAD:-0}" -gt 0 ]]; then
      printf 'Warning: the architecture checkout is %s commit(s) ahead of %s, which the bot does not read.\n' \
        "$AHEAD" "$GUIDES_REF" >&2
    fi
  else
    echo "Warning: could not fetch $GUIDES_REF into the architecture checkout, so its age is not known." >&2
  fi
fi

# A new guide file that is not committed is on disk too, so the check counts untracked files.
if [[ -n "$(uncommitted "$ARCHITECTURE_DIR")" ]]; then
  echo 'Warning: the architecture checkout has uncommitted changes or untracked files, which the bot does not see.' >&2
fi

# The explicit refspec updates `origin/$BASE_REF` in a single-branch clone, and offline the local
# ref stands. Without that ref the reviewer cannot read the diff, so the script stops.
git -C "$REPO_ROOT" fetch --quiet origin "+refs/heads/$BASE_REF:refs/remotes/origin/$BASE_REF" 2> /dev/null \
  || echo "Warning: could not fetch $BASE_REF from origin, so the review uses the local origin/$BASE_REF." >&2
git -C "$REPO_ROOT" rev-parse --verify --quiet "origin/$BASE_REF" > /dev/null \
  || fail "origin/$BASE_REF does not resolve."

# A HEAD with no commit past the base branch gives an empty diff, and a clean verdict on it says
# nothing.
[[ "$(git -C "$REPO_ROOT" rev-list --count "origin/$BASE_REF..HEAD")" -gt 0 ]] \
  || fail "HEAD has no commit that origin/$BASE_REF lacks, so there is no change to review."

if [[ -z "${OUTPUT_DIR:-}" ]]; then
  OUTPUT_DIR="$(mktemp -d "${TMPDIR:-/tmp}/local-review.XXXXXX")" || fail 'Could not make a temporary directory.'
fi

# Resolves a path that may not exist yet through its nearest existing ancestor, without symlinks.
physical_path() {
  local path="$1"
  local rest=''

  while [[ ! -d "$path" ]]; do
    rest="/$(basename -- "$path")$rest"
    path="$(dirname -- "$path")"
  done

  printf '%s%s\n' "$(cd -- "$path" && pwd -P)" "$rest"
}

# Findings inside the repository would fail the clean-tree check on the next run.
[[ "$OUTPUT_DIR" == /* ]] || OUTPUT_DIR="$PWD/$OUTPUT_DIR"
OUTPUT_DIR="$(physical_path "$OUTPUT_DIR")"
REPO_PHYSICAL="$(cd -- "$REPO_ROOT" && pwd -P)"
[[ "$OUTPUT_DIR/" != "$REPO_PHYSICAL/"* ]] || fail "OUTPUT_DIR must sit outside the repository under review."

mkdir -p -- "$OUTPUT_DIR" 2> /dev/null && [[ -w "$OUTPUT_DIR" ]] || fail "Could not write to $OUTPUT_DIR."
OUTPUT_DIR="$(cd -- "$OUTPUT_DIR" && pwd -P)"

# The guides paragraph follows the prompt output in the workflow's `prompt:` block, indented by
# twelve literal spaces, since some awk versions lack the `{12}` interval.
GUIDES_PARAGRAPH="$(awk '
  /steps\.prompt\.outputs\.prompt }}/ { found = 1; next }
  found && /^            / { print substr($0, 13); started = 1; next }
  found && /^[[:space:]]*$/ { if (started) print; next }
  found { exit }
' "$WORKFLOW_FILE")"
RUNNER_GUIDES_DIR="\${{ runner.temp }}/architecture"
GUIDES_PARAGRAPH="${GUIDES_PARAGRAPH//"$RUNNER_GUIDES_DIR"/"$ARCHITECTURE_DIR"}"

[[ "$GUIDES_PARAGRAPH" == *"$ARCHITECTURE_DIR"* ]] || fail "No guides paragraph in the prompt of $WORKFLOW_FILE."

PROMPT="$(cat "$PROMPT_FILE")

$GUIDES_PARAGRAPH

This review runs before the pull request is opened, so there is no pull
request, no thread, and no inline comment tool. The change is
\`git diff origin/$BASE_REF...HEAD\`, and its commits are
\`git log origin/$BASE_REF..HEAD\`. Put every finding in \`summary\`
instead of an inline comment, each naming its file and line."

# The bot reads the title of the pull request, so a draw reads it too when one already exists.
PR_TITLE="$(cd -- "$REPO_ROOT" && gh pr view --json title --jq .title 2> /dev/null || true)"

if [[ -n "$PR_TITLE" ]]; then
  PROMPT="$PROMPT

A pull request for this branch is already open. Its title is: $PR_TITLE"
fi

printf 'Reviewing %s against origin/%s with %s, %s draw(s). Findings go to %s.\n' \
  "$(git -C "$REPO_ROOT" rev-parse --short HEAD)" "$BASE_REF" "$MODEL" "$DRAWS" "$OUTPUT_DIR"

PIDS=()

for ((DRAW = 1; DRAW <= DRAWS; DRAW++)); do
  (
    cd -- "$REPO_ROOT"

    # The environment variable turns auto-memory off, and `--setting-sources project` leaves out the
    # settings of the user, whose permissions can grant more tools than the workflow does.
    CLAUDE_CODE_DISABLE_AUTO_MEMORY=1 claude -p "$PROMPT" \
      --safe-mode \
      --model "$MODEL" \
      --setting-sources project \
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

    # The reason is the first field that says anything: `result`, then `errors`, then `subtype`.
    REASON="$(jq -r '[.result, ((.errors // []) | map(tostring) | join("; ")), .subtype]
      | map(select(type == "string" and . != "")) | first // empty' "$RESULT" 2> /dev/null || true)"

    if [[ -n "$REASON" ]]; then
      printf '\n%s\n' "$REASON"
    fi

    STATUS=2
    continue
  fi

  jq -r --arg draw "$DRAW" '.structured_output
    | "\n== Draw \($draw): \(.verdict), \(.blocking_findings) blocking, "
      + "\(.advisory_findings) advisory\n\n\(.summary)"' "$RESULT"

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
