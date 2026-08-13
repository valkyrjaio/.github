#!/usr/bin/env bash
#
# This file is part of the Valkyrja GitHub package.
#
# Copyright (c) 2016-present Melech Mizrachi
#
# Released under the MIT License. See LICENSE.md for details.
#
# ---------------------------------------------------------------------------
# Script environment export.
#
# Reads the `KEY=VALUE` lines that a caller passes to the `run-script` action,
# and writes each one to the environment file. The run step that follows then
# reads them.
#
# Reads SCRIPT_ENV and GITHUB_ENV from the environment.
#
# Usage:
#
#     .github/ci/scripts/export-script-environment.sh
# ---------------------------------------------------------------------------

# Warning: an action step names `shell: bash`, which is `-eo pipefail`, and a
# `run:` step that names no shell gives `bash -e` alone. This script carries a
# block from an action step. Read the shell before you copy a `set` line
# between the two.
#
# `-u` is absent, because the block ran without it.
set -eo pipefail

# Each line becomes an environment variable for the run step. The key is checked first, because
# `GITHUB_ENV` takes whatever it is given, and a malformed key would define a variable no script
# can read, or shadow one the runner set.
while IFS= read -r LINE; do
  [[ -z "$LINE" ]] && continue

  KEY="${LINE%%=*}"

  case "$KEY" in
    "$LINE") echo "Not a KEY=VALUE line: $LINE" >&2; exit 1 ;;
    ''|[0-9]*|*[!A-Za-z0-9_]*) echo "Not a shell name: $KEY" >&2; exit 1 ;;
    *) ;;
  esac

  printf '%s\n' "$LINE" >> "$GITHUB_ENV"
done <<< "$SCRIPT_ENV"
