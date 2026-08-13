#!/usr/bin/env bash
#
# This file is part of the Valkyrja GitHub package.
#
# Copyright (c) 2016-present Melech Mizrachi
#
# Released under the MIT License. See LICENSE.md for details.
#
# ---------------------------------------------------------------------------
# Java dependency update.
#
# Runs `gradle useLatestVersions` in each module directory the caller passes.
#
# Reads DEPENDENCIES from the environment.
#
# Usage:
#
#     .github/ci/scripts/update-java-dependencies.sh
# ---------------------------------------------------------------------------

# Warning: a bare `run:` step runs this, so `-u` and `pipefail` stay off. The
# rule and the shell table are in `.github/workflows/README.md`, under Scripts.
set -e

: > /tmp/dependency_changes.txt

LENGTH=$(echo "$DEPENDENCIES" | jq 'length')
for i in $(seq 0 $((LENGTH - 1))); do
  NAME=$(echo "$DEPENDENCIES" | jq -r ".[$i].name")
  DIR=$(echo "$DEPENDENCIES" | jq -r ".[$i].directory")

  echo "Updating $NAME..."
  # --refresh-dependencies is required: Gradle caches resolved dynamic versions for 24
  # hours by default, and the versions plugin does not override that. Because
  # setup-gradle restores ~/.gradle between runs, a release published since the last
  # re-resolution would otherwise stay invisible for up to a day.
  (cd "$DIR" && gradle useLatestVersions --refresh-dependencies) || echo "useLatestVersions not available for $NAME, skipping."
done
