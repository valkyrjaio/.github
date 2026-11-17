#!/usr/bin/env bash
#
# This file is part of the Valkyrja GitHub package.
#
# Copyright (c) 2016-present Melech Mizrachi
#
# Released under the MIT License. See LICENSE.md for details.
#
# ---------------------------------------------------------------------------
# Outdated PHP dependency check.
#
# Reads COMPOSER_COMMAND, which names the composer script to run and decides
# whether this is the major check, and NAME, which names the dependency
# context a matrix leg checks.
#
# Usage:
#
#     COMPOSER_COMMAND=phpunit-outdated-check NAME=PHPUnit \
#         .github/ci/scripts/check-outdated-php-dependencies.sh
# ---------------------------------------------------------------------------

# A composite action step invokes this script, so it sets `set -euo pipefail`.
# `.github/workflows/README.md` holds the rule for each family, under Scripts.
set -euo pipefail

# A *-major-release check asks whether a newer MAJOR exists. That lives
# outside the current constraints, so `composer update` can never propose it —
# taking a major means editing composer.json by hand. Deciding this check with
# the resolver would make it pass unconditionally: a gate that never gates.
# Only `composer outdated` can see across a major, and a major it reports is
# genuinely actionable, so the report is the verdict here.
case "$COMPOSER_COMMAND" in
  *-major-release*)
    output=$(eval "composer ${COMPOSER_COMMAND}" 2>&1) || true
    echo "$output"

    if [[ "$output" == *"All your direct dependencies are up to date"* ]]; then
      echo "No major $NAME updates outstanding. Proceeding..."
      exit 0
    fi

    echo "Major dependency updates must be taken before opening a new version line."
    exit 1
    ;;
  *) ;;
esac

# Everything below is the ordinary (minor-only) check.
#
# `composer outdated` reports what exists on Packagist, not what this
# dependency graph can actually resolve to. When a sibling package pins a
# shared transitive dependency, the newer version is reported forever and no
# update run can ever clear it — a permanently red gate for something nobody
# can fix here. So the resolver decides: can it improve on the lock at all?
# Within fixed constraints that question is exactly right, and unlike the
# major case the resolver can act on the whole answer.
#
# The directory is embedded in the composer script ("cd <dir> && composer …"),
# so read it from there rather than changing every caller's inputs.
DIR=$(jq -r --arg c "${COMPOSER_COMMAND%% *}" '.scripts[$c] // "" | if type == "array" then .[0] else . end' composer.json \
  | sed -nE 's|^cd ([^ ]+) &&.*|\1|p')
DIR=${DIR:-.}

echo "Checking whether $NAME can resolve to anything newer (in ${DIR})..."
resolution=$(cd "$DIR" && composer update --dry-run --no-interaction 2>&1) || true

if [[ "$resolution" == *"Nothing to modify in lock file"* ]]; then
  echo "All $NAME dependencies are at their best resolvable versions. Proceeding..."
  exit 0
fi

echo "::group::What the resolver would change"
echo "$resolution"
echo "::endgroup::"

# Only now pay for the install that `composer outdated` needs — it names the
# packages and the versions to move to, which is what makes the failure
# actionable.
echo "Composer dependencies must be updated before releasing:"
eval "composer ${COMPOSER_COMMAND}" 2>&1 || true
exit 1
