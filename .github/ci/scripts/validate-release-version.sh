#!/usr/bin/env bash
#
# This file is part of the Valkyrja GitHub package.
#
# Copyright (c) 2016-present Melech Mizrachi
#
# Released under the MIT License. See LICENSE.md for details.
#
# ---------------------------------------------------------------------------
# Release version validation.
#
# Checks the computed version before the release publishes it. A release
# candidate carries its own format, so it passes the format check and skips the
# rest.
#
# Reads VERSION and BUMP from the environment. SUPPORTED_VERSIONS is the year
# gate, and the script skips that one check when it is empty.
# ---------------------------------------------------------------------------

# A composite action step invokes this script, so it sets `set -euo pipefail`.
# `.github/workflows/README.md` holds the rule for each family, under Scripts.
set -euo pipefail

: "${VERSION:?VERSION must hold the computed version}"
: "${BUMP:?BUMP must name the version component to bump}"

# SUPPORTED_VERSIONS is optional, and `set -u` aborts on a bare read of a
# variable the caller never set. The skip branch below would never reach its
# empty case. An organization variable can be scoped to selected repositories,
# so a workflow that reads one outside that scope passes an empty value.
SUPPORTED_VERSIONS="${SUPPORTED_VERSIONS:-}"

# RC versions have their own format; skip standard semver checks
if [[ "$VERSION" =~ ^[0-9]+\.0\.0-RC[0-9]+$ ]]; then
  echo "RC version v$VERSION passed format check."
  exit 0
fi

# Verify semver format
if ! [[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "Computed version '$VERSION' is not valid semver. Aborting."
  exit 1
fi

MAJOR=$(echo "$VERSION" | cut -d. -f1)
MINOR=$(echo "$VERSION" | cut -d. -f2)
PATCH=$(echo "$VERSION" | cut -d. -f3)

# Verify major version is supported
if [[ -z "$SUPPORTED_VERSIONS" ]]; then
  echo "SUPPORTED_VERSIONS not set; skipping version support check."
elif ! [[ "$MAJOR" =~ $SUPPORTED_VERSIONS ]]; then
  echo "Computed major version $MAJOR is not in the supported versions ($SUPPORTED_VERSIONS). Aborting."
  exit 1
else
  echo "Major version $MAJOR matches supported versions ($SUPPORTED_VERSIONS)."
fi

# Verify the correct component is zero for the bump type. "auto" is excluded:
# it resolves to feature or patch inside the compute step, so the input no
# longer describes the shape by the time we get here.
#
# The components compare as strings, because a valid component is the exact
# string `0`. Semver forbids a leading zero, so `00` is no more valid than
# `08`.
#
# `[[ ]]` also reads an operand of `-ne` as an arithmetic expression. A leading
# zero makes that expression octal, so `08` fails to parse and the test returns
# false. A gate must not pass a version it cannot read.
case "$BUMP" in
  yearly)
    if [[ "$MINOR" != "0" ]] || [[ "$PATCH" != "0" ]]; then
      echo "Yearly bump should produce X.0.0 but got $VERSION. Aborting."
      exit 1
    fi
    ;;
  feature)
    if [[ "$PATCH" != "0" ]]; then
      echo "Feature bump should produce X.Y.0 but got $VERSION. Aborting."
      exit 1
    fi
    ;;
  *) ;;
esac

echo "Version v$VERSION passed all sanity checks."
