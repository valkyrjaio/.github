#!/usr/bin/env bash
#
# ---------------------------------------------------------------------------
# Trailing newline check.
#
# Every text file this repository tracks ends with a newline. This script names
# the files that do not.
#
# What it writes is the report a pull request comment carries, so the output is
# Markdown. A caller posts it as it stands, and the message therefore lives here
# rather than in the workflow that runs the script.
#
# Usage:
#
#     .github/ci/scripts/trailing-newline-check.sh
# ---------------------------------------------------------------------------

set -euo pipefail

# `git ls-files` names the files. A shell glob also matches a vendored file under `vendor/`, under
# `node_modules/`, or in a worktree directory, and the check reads only what the repository tracks.
#
# The list is read with `while`, not with `mapfile`. `mapfile` needs bash 4, and macOS ships bash
# 3.2, so `mapfile` stops a person from running this script on their own machine.
missing=()

while IFS= read -r -d '' file; do
    # A directory has no content of its own, and an empty file has no last byte to test.
    [[ -d "$file" ]] && continue
    [[ ! -s "$file" ]] && continue

    # A binary file has no line ending to require.
    if file --mime-encoding "$file" 2>/dev/null | grep -q 'binary'; then
        continue
    fi

    if [[ "$(tail -c 1 "$file" | wc -l)" -eq 0 ]]; then
        missing+=("$file")
    fi
done < <(git ls-files -z)

if [[ "${#missing[@]}" -gt 0 ]]; then
    printf 'The following files are missing a trailing newline:\n\n'
    printf -- '- `%s`\n' "${missing[@]}"

    exit 1
fi

echo 'All files have a trailing newline.'
