#!/usr/bin/env bash
#
# This file is part of the Valkyrja GitHub package.
#
# Copyright (c) 2016-present Melech Mizrachi
#
# Released under the MIT License. See LICENSE.md for details.
#
# ---------------------------------------------------------------------------
# Markdown formatting check.
#
# Every Markdown file this repository tracks is formatted by Prettier. This
# script names the files that are not.
#
# What it writes is the report a pull request comment carries, so the output is
# Markdown. A caller posts it as it stands, and the message therefore lives here
# rather than in the workflow that runs the script.
#
# Reads PRETTIER_VERSION from the environment.
#
# Usage:
#
#     PRETTIER_VERSION=3.9.6 .github/ci/scripts/markdown-check.sh
# ---------------------------------------------------------------------------

# Warning: `pipefail` is deliberately absent. The pipeline below ends in `xargs`, whose status is
# read on purpose and whose meaning is explained where it is read. With `pipefail` the status would
# instead come from whichever stage failed first, and the reasoning below would no longer hold.
set -eu

: "${PRETTIER_VERSION:?PRETTIER_VERSION must name the Prettier version to run}"

# Three settings carry the whole configuration, so no repository needs a config file.
#
#   --embedded-language-formatting=off  Prettier's default rewrites the code inside every
#                                       fence whose tag it knows. A document shows what a
#                                       repository contains, so the formatter must leave
#                                       the example alone.
#   --prose-wrap=preserve               Keeps every hand-placed line break. Documentation
#                                       prose is wrapped by sentence and by clause, and a
#                                       reflow to a fixed width erases that structure.
#   --no-config                         Keeps the rules identical in every repository. A
#                                       repository's own prettier config governs its other
#                                       file types, never its Markdown.
#
# CHANGELOG.md is excluded because the release automation writes it.
#
# `git ls-files` names the files, rather than a `**/*.md` glob. The glob also matches a
# vendored document under `vendor/`, `node_modules/`, or a worktree directory, and the
# check must read only what the repository tracks.
set +e
DIFFERENT=$(git ls-files -z -- '*.md' ':(exclude)*CHANGELOG.md' \
    | xargs -0 -r npx --yes "prettier@$PRETTIER_VERSION" \
        --no-config \
        --embedded-language-formatting=off \
        --prose-wrap=preserve \
        --list-different)
STATUS=$?
set -e

# Warning: never branch on `$STATUS` before `$DIFFERENT`. `$STATUS` is the exit status of
# `xargs`, not of Prettier, and `xargs` does not pass the child's status through. GNU
# `xargs` reports 123 for any child status in 1 to 125, and BSD `xargs` reports 1, so the
# same drift gives a different number on a runner than on a developer's Mac. What the two
# agree on is the output: `--list-different` writes the unformatted files to stdout, and
# writes an error to stderr. So read the output first, and read the status only to catch
# a Prettier that failed without naming a file.
if [[ -n "$DIFFERENT" ]]; then
    printf 'The Markdown check failed. Please run this command locally and commit the changes:\n\n'
    printf '```bash\n'
    printf "git ls-files -z -- '*.md' ':(exclude)*CHANGELOG.md' \\\\\n"
    printf '  | xargs -0 npx --yes prettier@%s \\\n' "$PRETTIER_VERSION"
    printf '    --no-config \\\n'
    printf '    --embedded-language-formatting=off \\\n'
    printf '    --prose-wrap=preserve \\\n'
    printf '    --write\n'
    printf '```\n\n'
    printf 'These files are not formatted:\n\n'

    # Warning: read the list line by line. Unquoted, `$DIFFERENT` is word split on spaces and then
    # glob expanded, so a path holding a space would break across two bullets, and a path matching
    # a pattern in the working directory would be replaced by whatever it matched. `mapfile` would
    # read it in one call, and macOS ships bash 3.2, which has no `mapfile`.
    while IFS= read -r FILE; do
        # shellcheck disable=SC2016 # The backticks are Markdown, not a command substitution.
        [[ -n "$FILE" ]] && printf -- '- `%s`\n' "$FILE"
    done <<< "$DIFFERENT"

    exit 1
fi

if [[ "$STATUS" -ne 0 ]]; then
    printf 'Prettier failed to run, and it named no file. Exit status %s.\n' "$STATUS"

    exit "$STATUS"
fi

echo 'All Markdown files are formatted.'
