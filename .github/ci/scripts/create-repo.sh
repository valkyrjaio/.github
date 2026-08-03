#!/usr/bin/env bash
#
# This file is part of the Valkyrja GitHub package.
#
# Copyright (c) 2016-present Melech Mizrachi
#
# Released under the MIT License. See LICENSE.md for details.
#
# ---------------------------------------------------------------------------
# Repository creation and configuration.
#
# This script creates the repository and applies the organization's standard
# settings to it. It scaffolds from `project-template-<lang>` when the name
# ends in a supported language, and it creates a bare repository otherwise.
# A project template has no template of its own, so it is the one exception.
#
# Reads GH_TOKEN, ORG, REPO_NAME, DESCRIPTION, and SUPPORTED_LANGUAGES from the environment.
#
# Usage:
#
#     .github/ci/scripts/create-repo.sh
# ---------------------------------------------------------------------------

# Warning: `-u` and `pipefail` are deliberately absent. A `run:` step that names
# no shell runs under `bash -e {0}`, and this script holds such a block. The
# `bash --noprofile --norc -eo pipefail {0}` form is what an explicit
# `shell: bash` selects, which is why a script that `run-script` invokes sets
# `pipefail` and this one does not.
set -e

# A repo's language is the final '-'-delimited segment of its name
# (see REPOSITORY_NAMING.md): valkyrja-php → php, ci-junit-java → java,
# sindri-ts → ts. It only counts as a language when listed in the
# org-level vars.SUPPORTED_LANGUAGES (space-separated), so e.g.
# some-global-repo resolves to nothing.
LANG_SUFFIX=$(echo "${REPO_NAME##*-}" | tr '[:upper:]' '[:lower:]')

# Scaffold from project-template-<lang> when the repo targets a known
# language — except for the project templates themselves, which have no
# template of their own (and must not reference one that may not exist
# yet when a new language is introduced).
TEMPLATE_FLAG=""
if [[ " $SUPPORTED_LANGUAGES " == *" $LANG_SUFFIX "* && "$REPO_NAME" != project-template-* ]]; then
  echo "Detected language '$LANG_SUFFIX'; using template $ORG/project-template-$LANG_SUFFIX"
  TEMPLATE_FLAG="--template $ORG/project-template-$LANG_SUFFIX"
else
  echo "No language template for '$REPO_NAME'; creating a bare repo."
fi

gh repo create "$ORG/$REPO_NAME" \
  --public \
  --description "$DESCRIPTION" \
  $TEMPLATE_FLAG

# Warning: `gh repo create --template` returns before GitHub finishes copying
# the template. The repository exists, its metadata reads back, and its
# contents are still empty. Every later step that reads the repository then
# finds nothing, takes its own "nothing to do" path, and reports success. The
# repository keeps the template's package identifier and gets no master
# branch, while the job reports the repository as created.
#
# This was measured on `valkyrja-python`. The clone three seconds after
# creation printed `You appear to have cloned an empty repository`, and the
# API still reported `master` as the default branch rather than the
# template's. Both steps below then did nothing.
#
# Wait for the first commit, which is what the copy produces.
if [[ -n "$TEMPLATE_FLAG" ]]; then
  # Read the exit code, never the body. The endpoint answers 409 while the
  # repository holds no commit, and 404 before it resolves at all. Both write
  # a JSON body to stdout, and a numeric test on that body is not a test.
  for _ in $(seq 1 60); do
    if gh api "repos/$ORG/$REPO_NAME/commits?per_page=1" --silent 2>/dev/null; then
      COPIED=1
      break
    fi

    sleep 2
  done

  if [[ -z "${COPIED:-}" ]]; then
    printf 'The template copy did not finish within 120 seconds.\n' >&2
    printf 'The repository exists and holds no commit, so no later step can read it.\n' >&2
    exit 1
  fi

  echo "The template copy finished."
fi

gh api --method PATCH "repos/$ORG/$REPO_NAME" \
  --field allow_squash_merge=true \
  --field allow_merge_commit=false \
  --field allow_rebase_merge=false \
  --field delete_branch_on_merge=true \
  --field squash_merge_commit_title="PR_TITLE" \
  --field squash_merge_commit_message="PR_BODY" \
  --field has_wiki=false \
  --field has_projects=false

gh api --method PUT "repos/$ORG/$REPO_NAME/vulnerability-alerts" > /dev/null
gh api --method PUT "repos/$ORG/$REPO_NAME/automated-security-fixes" > /dev/null

# Warning: an owner can enforce immutable releases for every repository it owns, and the
# API then rejects a per-repository PUT with 409. The step runs under `bash -e`, so an
# unguarded PUT ends the job, and no step below it runs. The repository then keeps the
# template's package identifier, and it gets no branch ruleset, while the job reports the
# repository as created. Read the state first, and send the PUT only where the setting is
# off. Any other failure is still a real one.
if [[ "$(gh api "repos/$ORG/$REPO_NAME/immutable-releases" --jq '.enabled')" != 'true' ]]; then
  gh api --method PUT "repos/$ORG/$REPO_NAME/immutable-releases" > /dev/null
fi
