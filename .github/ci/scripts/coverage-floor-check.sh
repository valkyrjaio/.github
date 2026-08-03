#!/usr/bin/env bash
#
# This file is part of the Valkyrja GitHub package.
#
# Copyright (c) 2016-present Melech Mizrachi
#
# Released under the MIT License. See LICENSE.md for details.
#
# ---------------------------------------------------------------------------
# Coverage floor check.
#
# PHPUnit has no --fail-under. A repository's `coverage` script writes a report
# and nothing reads it, so a run at 55% passes exactly like one at 100%. The
# only thing that noticed a drop was Coveralls, which reports after the push and
# is not a required check, so it blocks nothing. This script reads the report the
# PHPUnit job just wrote and turns it into the gate.
#
# Line coverage only, deliberately. Xdebug records branch data only under
# --path-coverage, which is roughly ten times slower, and clover's
# `<metrics conditionals>` is 0 without it. A branch assertion over this report
# would silently assert nothing, which is worse than having no assertion at all.
# Branch coverage stays a local concern; on `valkyrja` that is
# `composer phpunit-path-coverage-parallel`.
#
# A floor of exactly 100 is asserted as covered == total rather than as a
# percentage, so no rounding can carry a 99.99% past a "100%" gate, and one
# fully untested new file cannot hide inside a large covered codebase.
#
# Nothing to cover is a pass. A freshly scaffolded repository has no source, and
# 0/0 is not a failure.
#
# Usage:
#
#     scripts/coverage-floor-check.sh [--clover PATH] [--require N]
#
# Defaults: --clover build/logs/clover.xml, --require 100.
# ---------------------------------------------------------------------------

set -euo pipefail

# The environment sets each of these, and an argument overrides the environment. A workflow passes
# the environment, because it runs the script with no arguments. A person passes an argument.
CLOVER_PATH="${CLOVER_PATH:-build/logs/clover.xml}"
REQUIRE_LINE="${REQUIRE_LINE:-100}"

while [[ "$#" -gt 0 ]]; do
    case "$1" in
        --clover)
            [[ "$#" -ge 2 ]] || { printf -- '--clover needs a value.\n' >&2; exit 1; }
            CLOVER_PATH="$2"
            shift 2
            ;;
        --require)
            [[ "$#" -ge 2 ]] || { printf -- '--require needs a value.\n' >&2; exit 1; }
            REQUIRE_LINE="$2"
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

case "$REQUIRE_LINE" in
    ''|*[!0-9]*)
        printf 'The floor must be a whole percentage, and it is: %s\n' "$REQUIRE_LINE" >&2
        exit 1
        ;;
    # A whole number is the one shape that passes.
    *) ;;
esac

if [[ "$REQUIRE_LINE" -gt 100 ]]; then
    printf 'The floor must be 100 or less, and it is: %s\n' "$REQUIRE_LINE" >&2
    exit 1
fi

if [[ ! -f "$CLOVER_PATH" ]]; then
    printf 'No clover report at %s.\n' "$CLOVER_PATH" >&2
    printf 'The coverage run writes it, so this means the run did not reach that point.\n' >&2
    exit 1
fi

# The totals live on `<project><metrics>`. A file carries its own `<metrics>`, and a namespaced file
# sits under `<package>`, so the project element is addressed directly rather than by tag name.
# `if ! VAR="$(...)"` is what propagates the reader's exit status. A bare command substitution
# feeding a here-string does not: `set -e` ignores it, the variables come back empty, and an
# unreadable report then reads as "nothing to cover" and passes. A gate must never pass on a
# report it could not read.
if ! METRICS="$(
    python3 - "$CLOVER_PATH" <<'PY'
import sys
import xml.etree.ElementTree as ET

try:
    root = ET.parse(sys.argv[1]).getroot()
except ET.ParseError as error:
    print(f'The clover report is not readable XML: {error}', file=sys.stderr)
    raise SystemExit(1)

metrics = root.find('project/metrics')

if metrics is None:
    print('The clover report carries no project metrics.', file=sys.stderr)
    raise SystemExit(1)

print(metrics.get('statements', '0'), metrics.get('coveredstatements', '0'))
PY
)"; then
    exit 1
fi

read -r TOTAL COVERED <<< "$METRICS"

# A reader that printed something unexpected must not reach the arithmetic below.
case "$TOTAL$COVERED" in
    ''|*[!0-9]*)
        printf 'The clover report gave no usable totals: %s\n' "$METRICS" >&2
        exit 1
        ;;
    # Two whole numbers are the one shape that passes.
    *) ;;
esac

if [[ "$TOTAL" -eq 0 ]]; then
    printf 'Line coverage: 100.00%% (0/0)\n'
    printf 'PASS  the report holds nothing to cover.\n'
    exit 0
fi

PERCENT="$(awk -v c="$COVERED" -v t="$TOTAL" 'BEGIN { printf "%.2f", c / t * 100 }')"

printf 'Line coverage: %s%% (%s/%s)\n' "$PERCENT" "$COVERED" "$TOTAL"

if [[ "$REQUIRE_LINE" -eq 100 ]]; then
    [[ "$COVERED" -eq "$TOTAL" ]] && MET=1 || MET=0
else
    MET="$(awk -v p="$PERCENT" -v r="$REQUIRE_LINE" 'BEGIN { print (p + 1e-9 >= r) ? 1 : 0 }')"
fi

if [[ "$MET" -eq 1 ]]; then
    printf 'PASS  line coverage is at or above the %s%% floor.\n' "$REQUIRE_LINE"
    exit 0
fi

printf 'FAIL  line coverage is below the %s%% floor, by %s line(s).\n\n' \
    "$REQUIRE_LINE" "$((TOTAL - COVERED))"

# The failure names what to fix. A percentage alone sends a person back to the HTML report to find
# out which file moved.
python3 - "$CLOVER_PATH" <<'PY'
import sys
import xml.etree.ElementTree as ET

root = ET.parse(sys.argv[1]).getroot()
gaps = []

for file_ in root.iter('file'):
    metrics = file_.find('metrics')

    if metrics is None:
        continue

    total = int(metrics.get('statements', '0'))
    covered = int(metrics.get('coveredstatements', '0'))

    if total > covered:
        gaps.append((total - covered, file_.get('name', '?')))

gaps.sort(reverse=True)

print(f'Files below 100% line coverage: {len(gaps)}')

for missing, name in gaps:
    print(f'  {missing:4d} missing  {name}')
PY

exit 1
