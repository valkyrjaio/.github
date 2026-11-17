#!/usr/bin/env bash
#
# This file is part of the Valkyrja GitHub package.
#
# Copyright (c) 2016-present Melech Mizrachi
#
# Released under the MIT License. See LICENSE.md for details.
#
# ---------------------------------------------------------------------------
# Outdated Java dependency check.
#
# The `gradle` command resolves against the current directory, and the caller
# sets that with `working-directory`, so a matrix leg checks its own module.
#
# Reads MAJOR_RELEASE, which says whether a major upgrade blocks the run, and
# NAME, which names the module a matrix leg checks.
#
# Usage, from the module's own directory:
#
#     MAJOR_RELEASE=false NAME=JUnit \
#         /path/to/.github/ci/scripts/check-outdated-java-dependencies.sh
# ---------------------------------------------------------------------------

# A bare `run:` step invokes this script, so it sets `set -e` alone.
# `.github/workflows/README.md` holds the rule for each family, under Scripts.
set -e

# --refresh-dependencies is required: Gradle caches resolved dynamic versions for 24
# hours by default, and the versions plugin does not override that. Without it a release
# published since the last re-resolution stays invisible and this check passes while the
# dependencies are in fact outdated.
output=$(gradle dependencyUpdates --refresh-dependencies 2>&1)
echo "$output"

if ! echo "$output" | grep -q "The following dependencies have later release versions"; then
  echo "All $NAME dependencies are up to date."
  exit 0
fi

# Dependencies are pinned exactly, so every newer release shows up here —
# including majors, which policy reserves for the year boundary. Split the
# report so an ordinary release is not blocked on a major upgrade it is not
# allowed to take.
printf '%s\n' "$output" > /tmp/dependency-updates.txt

# The caller runs this script from the module's own directory, so the sibling is
# found through `BASH_SOURCE` rather than the working directory.
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

python3 "$SCRIPT_DIR/split_java_dependency_updates.py" \
  "$MAJOR_RELEASE" "$NAME" /tmp/dependency-updates.txt
