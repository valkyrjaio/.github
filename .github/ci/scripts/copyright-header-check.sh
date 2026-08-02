#!/usr/bin/env bash
#
# ---------------------------------------------------------------------------
# Copyright header check.
#
# Each language enforces the copyright header with its own formatter, and a
# formatter reads only the language it formats. A file in any other language
# keeps the header a person gives it, and no tool reports that the header is
# wrong. This script covers every such file. It compares text against text, so
# it needs no toolchain.
#
# The check is closed by default. It reads every tracked file, and it requires
# the header in each file that EXCLUDED does not match. A new file fails the
# check until a person adds the header, or adds the file to EXCLUDED. A file
# that holds no program code belongs in EXCLUDED. A document, a workflow, a
# configuration file, and a fixture that a test parses are such files.
#
# The repository supplies its own identifier and its own EXCLUDED list. The
# config file holds both, and the script reads it from the repository root.
#
# Usage:
#
#     scripts/copyright-header-check.sh [--config PATH] [--root PATH]
#
# Defaults: --config .github/ci/copyright-header/config, --root the working
# tree that holds the current directory.
# ---------------------------------------------------------------------------

set -euo pipefail

# The environment sets each of these, and an argument overrides the environment. A workflow passes
# the environment, because it runs the script with no arguments. A person passes an argument.
CONFIG_PATH="${CONFIG_PATH:-.github/ci/copyright-header/config}"
ROOT="${ROOT:-}"

while [[ "$#" -gt 0 ]]; do
    case "$1" in
        --config)
            [[ "$#" -ge 2 ]] || { printf -- '--config needs a value.\n' >&2; exit 1; }
            CONFIG_PATH="$2"
            shift 2
            ;;
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

if [[ ! -f "$CONFIG_PATH" ]]; then
    printf 'No config at %s.\n' "$CONFIG_PATH" >&2
    printf 'The file sets IDENTIFIER, and it sets the EXCLUDED array.\n' >&2
    exit 1
fi

IDENTIFIER=''
EXCLUDED=()

# shellcheck source=/dev/null
. "$CONFIG_PATH"

if [[ -z "$IDENTIFIER" ]]; then
    printf '%s sets no IDENTIFIER.\n' "$CONFIG_PATH" >&2
    printf 'COPYRIGHT_HEADER.md maps every repository to its own identifier.\n' >&2
    exit 1
fi

readonly TEXT_1="This file is part of the ${IDENTIFIER} package."
readonly TEXT_2='Copyright (c) 2016-present Melech Mizrachi'
readonly TEXT_3='Released under the MIT License. See LICENSE.md for details.'

# A language that writes a block comment writes the header between `/*` and `*/`. Every other
# file writes the same text as a line comment, where each delimiter of the block becomes a bare
# comment mark.
BLOCK_COMMENT=()
BLOCK_COMMENT[0]='/*'
BLOCK_COMMENT[1]=" * ${TEXT_1}"
BLOCK_COMMENT[2]=' *'
BLOCK_COMMENT[3]=" * ${TEXT_2}"
BLOCK_COMMENT[4]=' *'
BLOCK_COMMENT[5]=" * ${TEXT_3}"
BLOCK_COMMENT[6]=' */'

LINE_COMMENT=()
LINE_COMMENT[0]='#'
LINE_COMMENT[1]="# ${TEXT_1}"
LINE_COMMENT[2]='#'
LINE_COMMENT[3]="# ${TEXT_2}"
LINE_COMMENT[4]='#'
LINE_COMMENT[5]="# ${TEXT_3}"
LINE_COMMENT[6]='#'

readonly HEADER_LINES=7

# The extensions whose header is a block comment. Each of these languages writes the same text
# between `/*` and `*/`. Every other file writes it as a line comment. A language that owns its own
# header tool belongs in EXCLUDED instead, because that tool is what keeps the header correct.
BLOCK_COMMENT_EXTENSIONS=(
    '*.php'
    '*.java'
    '*.kt' '*.kts'
    '*.go'
    '*.ts' '*.tsx' '*.mts' '*.cts'
    '*.js' '*.jsx' '*.mjs' '*.cjs'
)

is_block_comment() {
    local path="$1"
    local pattern

    for pattern in "${BLOCK_COMMENT_EXTENSIONS[@]}"; do
        # shellcheck disable=SC2053
        if [[ "$path" == $pattern ]]; then
            return 0
        fi
    done

    return 1
}

is_excluded() {
    local path="$1"
    local pattern

    for pattern in ${EXCLUDED[@]+"${EXCLUDED[@]}"}; do
        # shellcheck disable=SC2053
        if [[ "$path" == $pattern ]]; then
            return 0
        fi
    done

    return 1
}

# Reports the line index the header starts on, which is not always the first
# line of the file. A script names its interpreter on line 1. A PHP file opens
# with `<?php`, and it may declare strict types before the header. Every such
# opening is skipped, and the first line after it must open the header.
header_offset() {
    local path="$1"
    local index=0
    local line

    while IFS= read -r line || [[ -n "$line" ]]; do
        if is_block_comment "$path"; then
                case "$line" in
                    '<?php'*|'declare(strict_types=1);'|'')
                        index=$((index + 1))
                        continue
                        ;;
                    # Any other line opens the header, so stop skipping.
                    *) ;;
                esac
        else
                if [[ "$index" -eq 0 ]]; then
                    case "$line" in
                        '#!'*)
                            index=1
                            continue
                            ;;
                        # No shebang, so the header opens on line 1.
                        *) ;;
                    esac
                fi
        fi

        break
    done < "$path"

    printf '%s' "$index"
}

failed=0
checked=0

while IFS= read -r -d '' path; do
    if is_excluded "$path"; then
        continue
    fi

    checked=$((checked + 1))

    offset="$(header_offset "$path")"
    # Warning: read the range with one `sed`, never with `tail | head`. `head` closes the
    # pipe once it has its lines, `tail` then takes SIGPIPE on any file larger than the pipe
    # buffer, and `pipefail` turns that into a crash the moment a large file appears.
    actual="$(sed -n "$((offset + 1)),$((offset + HEADER_LINES))p" "$path")"

    if is_block_comment "$path"; then
        expected="$(printf '%s\n' "${BLOCK_COMMENT[@]}")"
    else
        expected="$(printf '%s\n' "${LINE_COMMENT[@]}")"
    fi

    if [[ "$actual" != "$expected" ]]; then
        printf 'Missing or wrong copyright header: %s\n' "$path" >&2
        failed=1
    fi
done < <(git ls-files -z)

if [[ "$checked" -eq 0 ]]; then
    printf 'EXCLUDED matched every tracked file, so this check verified nothing.\n' >&2
    exit 1
fi

if [[ "$failed" -ne 0 ]]; then
    printf '\nEach file above must carry this header:\n\n' >&2
    printf '%s\n' "${LINE_COMMENT[@]}" >&2
    printf '\nA file of one of these types writes the same text as a block comment: %s\n' \
        "${BLOCK_COMMENT_EXTENSIONS[*]}" >&2
    printf 'The header follows the shebang, or the open tag, where the file has one.\n' >&2
    printf 'A file that holds no program code belongs in EXCLUDED in %s.\n' "$CONFIG_PATH" >&2

    exit 1
fi

printf 'All %s checked files carry the copyright header.\n' "$checked"
