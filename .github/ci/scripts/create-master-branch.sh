#!/usr/bin/env bash
#
# This file is part of the Valkyrja GitHub package.
#
# Copyright (c) 2016-present Melech Mizrachi
#
# Released under the MIT License. See LICENSE.md for details.
#
# ---------------------------------------------------------------------------
# Master branch creation for a new repository.
#
# `gh repo create --template` copies the template's default branch and nothing
# else. Every language template defaults to a version branch, so a new
# repository starts with that one branch. Every other repository in the
# organization holds `master` as well.
#
# Three workflows that each new repository receives require `master`:
# `rebase-to-master`, `rebase-from-master`, and `create-version-branch`, which
# is how the next year's version branch gets cut. All three fail on a
# repository that has no `master`, and the failure appears when someone first
# runs one of them rather than at creation.
#
# This script creates `master` from the default branch.
#
# Warning: run this after the commit that sets the copyright header package
# identifier. `master` points at whatever the default branch holds when the
# script runs, so a run before that commit leaves `master` naming the template
# in every file.
#
# No ruleset blocks the creation. `Protect Master At All Times` holds
# `deletion` and `non_fast_forward` only, and the one ruleset that holds a
# `creation` rule, `Restrict Changes to Unsupported Branches`, targets the
# `*-backup` branches.
#
# `--include-all-branches` is the other way to give a new repository `master`,
# and it takes too much. It copies `master-backup`, which is a transient
# artifact of the rebase tooling, and it copies whatever working branches the
# template holds on the day. This creates the one branch that is wanted.
#
# The script returns 0 and changes nothing in three cases:
#
# - The default branch is already `master`.
# - The repository holds no commit, so it has no branch to copy `master` from.
#   A repository created without a template is such a repository.
# - `master` already exists. The script never touches a branch it did not
#   create.
#
# Usage:
#
#     .github/ci/scripts/create-master-branch.sh [--org NAME] [--repo NAME]
#
# Defaults: --org the ORG environment variable, --repo the REPO_NAME
# environment variable. `gh` reads GH_TOKEN for authentication.
# ---------------------------------------------------------------------------

set -euo pipefail

# The environment sets each of these, and an argument overrides the environment. A workflow passes
# the environment, because it runs the script with no arguments. A person passes an argument.
ORG="${ORG:-}"
REPO_NAME="${REPO_NAME:-}"

while [[ "$#" -gt 0 ]]; do
    case "$1" in
        --org)
            [[ "$#" -ge 2 ]] || { printf -- '--org needs a value.\n' >&2; exit 1; }
            ORG="$2"
            shift 2
            ;;
        --repo)
            [[ "$#" -ge 2 ]] || { printf -- '--repo needs a value.\n' >&2; exit 1; }
            REPO_NAME="$2"
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

if [[ -z "$ORG" ]]; then
    printf 'ORG must name the organization that owns the repository.\n' >&2
    exit 1
fi

if [[ -z "$REPO_NAME" ]]; then
    printf 'REPO_NAME must name the repository.\n' >&2
    exit 1
fi

DEFAULT_BRANCH="$(gh api "repos/$ORG/$REPO_NAME" --jq '.default_branch')"

if [[ "$DEFAULT_BRANCH" == 'master' ]]; then
    printf 'The default branch is already master; nothing to create.\n'
    exit 0
fi

# `gh api` exits non-zero on a 404, which is what an empty repository returns for its default
# branch. The command substitution holds the error body in that case, and the branch below never
# reads it.
if ! SHA="$(gh api "repos/$ORG/$REPO_NAME/git/ref/heads/$DEFAULT_BRANCH" --jq '.object.sha' 2>/dev/null)"; then
    printf 'No %s branch yet, so the repository holds no commit; skipping master.\n' "$DEFAULT_BRANCH"
    exit 0
fi

if gh api "repos/$ORG/$REPO_NAME/git/ref/heads/master" --silent 2>/dev/null; then
    printf 'master already exists; leaving it alone.\n'
    exit 0
fi

gh api --method POST "repos/$ORG/$REPO_NAME/git/refs" \
    -f ref='refs/heads/master' \
    -f sha="$SHA" > /dev/null

printf 'Created master at %s, matching %s.\n' "$SHA" "$DEFAULT_BRANCH"
