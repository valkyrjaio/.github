#!/usr/bin/env bash
#
# This file is part of the Valkyrja GitHub package.
#
# Copyright (c) 2016-present Melech Mizrachi
#
# Released under the MIT License. See LICENSE.md for details.
#
# ---------------------------------------------------------------------------
# Required workflow reference update.
#
# `required-workflows/` holds the workflow templates that every repository in
# the organization receives. Each template names this repository by commit SHA.
# This script rewrites each of those references to the commit that holds the
# workflow code the template names.
#
# The release runs the script before it makes the tag. The tag then holds a
# template that names the workflow code of that same release, and no later
# pull request has to correct the template.
#
# The script names the last commit that changed the workflow code. It does not
# name a commit that the release makes, because a commit cannot name itself.
# The last workflow-code commit is an ancestor of every commit the release
# makes, and no release commit touches the workflow code, so the script reads
# the same value at each step of the release. A second run finds each reference
# already correct and changes no file.
#
# A Markdown file under the pinned paths is documentation. A reader reaches it
# through the repository, and a reference never reaches it, so a change to a
# Markdown file does not move the references.
#
# Warning: the script reads the git history. A shallow checkout holds one
# commit, and `git log` then reports the wrong commit. The script stops on a
# shallow checkout rather than write a wrong reference. `actions/checkout`
# makes a shallow checkout by default, so the workflow deepens it first.
#
# A repository that holds no `required-workflows/` directory needs no rewrite.
# The script reports that and exits 0.
#
# Usage:
#
#     .github/ci/scripts/update-required-workflow-refs.sh [--root PATH]
#
# Defaults: --root the working tree that holds the current directory.
# ---------------------------------------------------------------------------

# A bare `run:` step invokes this script, so it sets `set -e`.
# `.github/workflows/README.md` holds the rule for each family, under Scripts.
set -e

# The environment sets each of these, and an argument overrides the environment. A workflow passes
# the environment, because it runs the script with no arguments. A person passes an argument.
ROOT="${ROOT:-}"
OWNER="${OWNER:-valkyrjaio}"
TEMPLATE_DIR="${TEMPLATE_DIR:-required-workflows}"

while [[ "$#" -gt 0 ]]; do
    case "$1" in
        --root)
            [[ "$#" -ge 2 ]] || { printf -- '--root needs a value.\n' >&2; exit 1; }
            ROOT="$2"
            shift 2
            ;;
        -h|--help)
            grep '^#' "$0" | cut -c 3-
            exit 0
            ;;
        *)
            printf 'Unknown argument: %s\n' "$1" >&2
            exit 1
            ;;
    esac
done

if [[ -z "$ROOT" ]]; then
    ROOT="$(git rev-parse --show-toplevel)"
fi

cd "$ROOT"

if [[ ! -d "$TEMPLATE_DIR" ]]; then
    printf 'No %s directory, so there is no reference to update.\n' "$TEMPLATE_DIR"
    exit 0
fi

# The paths a reference reaches. `uses: <repo>/.github/workflows/<file>@<sha>` loads the workflow
# file from that commit, and a relative `uses:` inside that file loads from the same commit. A
# workflow also checks this repository out at that commit to reach the composite actions in
# `.github/actions/`, and an action runs a script from `.github/ci/`. A change to any of them
# changes what the reference runs, so each one moves the reference.
PIN_PATHS=(
    '.github/workflows'
    '.github/actions'
    '.github/ci'
    ':(exclude)*.md'
)

if [[ "$(git rev-parse --is-shallow-repository)" == 'true' ]]; then
    printf 'This is a shallow checkout, so git log cannot find the last workflow-code commit.\n' >&2
    printf 'Deepen the checkout first: git fetch --unshallow.\n' >&2
    exit 1
fi

PIN_SHA="$(git log -1 --format=%H -- "${PIN_PATHS[@]}")"

if [[ -z "$PIN_SHA" ]]; then
    printf 'No commit in this history changed the pinned paths.\n' >&2
    printf 'A reference needs such a commit to name, so nothing is written.\n' >&2
    exit 1
fi

printf 'Workflow code last changed in %s.\n' "$PIN_SHA"
printf '  %s\n\n' "$(git log -1 --format=%s "$PIN_SHA")"

# `.` is a regex metacharacter, and both the owner and the `.github` repository name reach the
# pattern. Escape each one so the pattern matches the text rather than any character.
OWNER_PATTERN="${OWNER//./\\.}"
MATCH="$OWNER_PATTERN/\\.github/\\.github/workflows/\\([^@]*\\)@[0-9a-f]\\{40\\}"
REPLACE="$OWNER/.github/.github/workflows/\\1@$PIN_SHA"

CHANGED=0
UNCHANGED=0

while IFS= read -r FILE; do
    [[ -n "$FILE" ]] || continue

    # Warning: write through the file, and never move a temporary one over it. `mktemp` makes a
    # file with mode 600, and `mv` carries that mode onto the template. Git records only the
    # executable bit, so a template that is executable would silently lose it, and one that is not
    # would still end the run readable by its owner alone.
    #
    # A command substitution drops trailing newlines, and both sides here lose them equally, so the
    # comparison is fair. The write then puts back exactly one, which is what the trailing newline
    # check in this repository requires of every file.
    UPDATED="$(sed "s|$MATCH|$REPLACE|g" "$FILE")"

    if [[ "$UPDATED" == "$(cat "$FILE")" ]]; then
        UNCHANGED=$((UNCHANGED + 1))
        continue
    fi

    printf '%s\n' "$UPDATED" > "$FILE"
    printf 'Updated %s\n' "$FILE"
    CHANGED=$((CHANGED + 1))
done < <(git ls-files "$TEMPLATE_DIR")

printf '\n%s file(s) updated, %s already correct.\n' "$CHANGED" "$UNCHANGED"
