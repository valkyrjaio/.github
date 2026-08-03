#!/usr/bin/env bash
#
# This file is part of the Valkyrja GitHub package.
#
# Copyright (c) 2016-present Melech Mizrachi
#
# Released under the MIT License. See LICENSE.md for details.
#
# ---------------------------------------------------------------------------
# Copyright header package identifier.
#
# `gh repo create --template` copies the template byte for byte, so a new
# repository starts with the template's own identifier. COPYRIGHT_HEADER.md
# resolves the identifier per repository, so this script replaces it in the
# new repository and pushes the result.
#
# Reads GH_TOKEN, ORG, REPO_NAME, IDENTIFIER, APP_SLUG, and BOT_USER_ID from the environment.
#
# Usage:
#
#     .github/ci/scripts/set-copyright-identifier.sh
# ---------------------------------------------------------------------------

# Warning: `-u` and `pipefail` are deliberately absent. A `run:` step that names
# no shell runs under `bash -e {0}`, and this script holds such a block. The
# `bash --noprofile --norc -eo pipefail {0}` form is what an explicit
# `shell: bash` selects, which is why a script that `run-script` invokes sets
# `pipefail` and this one does not.
set -e

# `gh repo create --template` copies the template byte for byte, so a new repo
# starts with the template's own identifier, `Project Template`. COPYRIGHT_HEADER.md
# resolves the identifier per repository, so replace it here.
git clone --depth 1 "https://x-access-token:$GH_TOKEN@github.com/$ORG/$REPO_NAME.git" new-repo
cd new-repo

# Warning: this step runs only when `validate` resolved a package identifier,
# and `validate` resolves one only for a repository scaffolded from a language
# template. The template header must therefore be present. Treating its absence
# as "nothing to do" is what let an empty clone pass as success, so this reports
# a failure instead.
if ! git grep -lq 'the Project Template package'; then
  printf 'This repository was scaffolded from a template, so it must carry the template header.\n' >&2
  printf 'The clone holds no such header, so the repository is empty or the template changed.\n' >&2
  exit 1
fi

# Warning: match the name and the word `package`, and stop before the period. A
# tool that enforces the header does not always store the sentence as prose. Ruff
# stores a regular expression, so it holds `package\.` with an escaped period, and
# a pattern that ends with a literal period never matches it. The new repository
# then names itself correctly in every source file while the tool still demands
# `Project Template`, and the gate fails on every file.
#
# `git grep` rather than `grep -r`: it reads only tracked files, so it never
# descends into .git, and its -z output is the same on every platform.
git grep -lz 'the Project Template package' \
  | xargs -0 perl -pi -e \
    's/\Qthe Project Template package\E/the $ENV{IDENTIFIER} package/g'

# Warning: the sentence is not the only place the identifier appears. The
# copyright header check reads `IDENTIFIER` from its own config, and that value is
# a bare name rather than the sentence, so the replacement above never reaches it.
# Every language template carries this file. Left alone, the check compares each
# file against `Project Template` and fails on all of them.
if git grep -lq "^IDENTIFIER='Project Template'$"; then
  git grep -lz "^IDENTIFIER='Project Template'$" \
    | xargs -0 perl -pi -e \
      "s/^IDENTIFIER='Project Template'\$/IDENTIFIER='\$ENV{IDENTIFIER}'/g"
fi

git config user.name "$APP_SLUG[bot]"
git config user.email "$BOT_USER_ID+$APP_SLUG[bot]@users.noreply.github.com"
git add -A
# No trailing period: this commit goes onto a protected branch, so its subject
# is permanent rather than a working-branch ledger entry.
git commit -m "[CopyrightHeader] chore: Set the package identifier to $IDENTIFIER"
git push
