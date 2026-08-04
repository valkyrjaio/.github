#!/usr/bin/env bash
#
# This file is part of the Valkyrja GitHub package.
#
# Copyright (c) 2016-present Melech Mizrachi
#
# Released under the MIT License. See LICENSE.md for details.
#
# ---------------------------------------------------------------------------
# Package availability wait.
#
# A publish step finishes before the registry serves the package, and that gap
# corrupts the next release: a dependent asks for the latest version, reads the
# previous one, and ships against it while every gate passes. This script holds
# the release open until the registry answers for the version that just
# published.
#
# It reads the version from VERSION.md and the package name from the manifest
# the ecosystem uses, both from the calling repository's working tree. Registries
# disagree about the `v` prefix, so every comparison drops it.
#
# It exits 1 when the version does not appear within the deadline. The release
# itself already succeeded by then — the failure says only that nothing may
# release against the package yet.
#
# Reads ECOSYSTEM, WAIT_MINUTES, and SKIP_WHEN_UNKNOWN from the environment.
#
# Usage:
#
#     .github/ci/scripts/wait-for-package-availability.sh
# ---------------------------------------------------------------------------

# Warning: `-u` and `pipefail` are deliberately absent. This script carries a
# block from a `run:` step that names no shell, and GitHub runs that as
# `bash -e {0}`.
#
# `pipefail` would change what this script does. The Packagist branch pipes
# `curl` into `jq` inside an `if`, and it reads the status of `jq` alone. A
# registry that answers slowly or returns a partial body would become a failure
# rather than another poll.
#
# An action step is the other case. It names `shell: bash`, which is
# `bash --noprofile --norc -eo pipefail`, so a script it invokes sets `pipefail`.
set -e

POLL_SECONDS=20
DEADLINE=$((WAIT_MINUTES * 60))

if [[ ! -f VERSION.md ]]; then
  echo "No VERSION.md, so there is no released version to wait for."
  exit 0
fi

# Every language reads the released version from this file, and the
# release commits it before the publish runs. Registries disagree about
# the `v` prefix. Packagist reports the tag, and Maven Central reports
# the bare version. This compares every version without the prefix.
VERSION=$(tr -d '[:space:]' < VERSION.md)
VERSION="${VERSION#v}"

if [[ -z "$VERSION" ]]; then
  echo "VERSION.md is empty, so there is no released version to wait for."
  exit 0
fi

case "$ECOSYSTEM" in
  maven)
    GROUP=$(grep -oE '^group *= *"[^"]+"' build.gradle.kts | grep -oE '"[^"]+"' | tr -d '"')
    # The artifact is the first quoted literal of the `coordinates(...)`
    # call. The other two arguments are `group.toString()` and
    # `version.toString()`, which carry no quotes. The scan starts at
    # the call and continues past the end of the line, because the
    # Kotlin DSL wraps a multi-argument call as often as it does not.
    ARTIFACT=$(awk '/coordinates\(/{f=1} f' build.gradle.kts \
      | grep -oE '"[^"]+"' | head -1 | tr -d '"')

    # Each half is checked on its own. A single missing half still
    # builds a plausible looking coordinate, and the URL it produces
    # answers 404 — which every other branch of this workflow reads as
    # "the registry does not carry this package". A parsing failure
    # must not borrow that meaning.
    if [[ -z "$GROUP" ]] || [[ -z "$ARTIFACT" ]]; then
      echo "Could not read the Maven coordinates from build.gradle.kts (group='$GROUP' artifact='$ARTIFACT')."
      exit 1
    fi

    PACKAGE="$GROUP:$ARTIFACT"
    GROUP_PATH=$(echo "$GROUP" | tr . /)
    ROOT_URL="https://repo1.maven.org/maven2/$GROUP_PATH/$ARTIFACT/maven-metadata.xml"
    VERSION_URL="https://repo1.maven.org/maven2/$GROUP_PATH/$ARTIFACT/$VERSION/$ARTIFACT-$VERSION.pom"
    ;;
  npm)
    PACKAGE=$(jq -r '.name // empty' package.json)
    ROOT_URL="https://registry.npmjs.org/$PACKAGE"
    VERSION_URL="https://registry.npmjs.org/$PACKAGE/$VERSION"
    ;;
  packagist)
    PACKAGE=$(jq -r '.name // empty' composer.json)
    ROOT_URL="https://repo.packagist.org/p2/$PACKAGE.json"
    VERSION_URL=""
    ;;
  pypi)
    PACKAGE=$(grep -oE '^name *= *"[^"]+"' pyproject.toml | grep -oE '"[^"]+"' | head -1 | tr -d '"')
    ROOT_URL="https://pypi.org/pypi/$PACKAGE/json"
    VERSION_URL="https://pypi.org/pypi/$PACKAGE/$VERSION/json"
    ;;
  *)
    echo "Unknown ecosystem '$ECOSYSTEM'."
    exit 1
    ;;
esac

if [[ -z "$PACKAGE" ]]; then
  echo "Could not read the package name from the manifest for $ECOSYSTEM."
  exit 1
fi

echo "Waiting for $PACKAGE $VERSION on $ECOSYSTEM."

# Only a caller that also runs where nothing publishes asks for this.
# A publish workflow does not: it just uploaded the package, so the
# registry has to answer for it, and an unknown package there means
# the upload has not landed rather than that the repository opted out.
#
# The distinction decides a first release. Maven Central builds
# `maven-metadata.xml` during the same sync this waits on, so the very
# first version of a new `group:artifact` has no metadata file yet.
# Reading that 404 as "does not publish here" would end the wait at the
# one moment it is most needed, and report a package as resolvable
# while `repo1.maven.org` returns nothing.
if [[ "$SKIP_WHEN_UNKNOWN" = "true" ]]; then
  ROOT_STATUS=$(curl -sS -o /dev/null -w '%{http_code}' "$ROOT_URL" || echo 000)

  if [[ "$ROOT_STATUS" = "404" ]]; then
    echo "$ECOSYSTEM does not know $PACKAGE, so this repository does not publish there."
    exit 0
  fi
fi

WAITED=0

while [[ "$WAITED" -lt "$DEADLINE" ]]; do
  if [[ "$ECOSYSTEM" = "packagist" ]]; then
    # Packagist serves every version in one document and reports the
    # tag, so the prefix comes off before the comparison.
    if curl -sS "$ROOT_URL" \
         | jq -e --arg v "$VERSION" --arg p "$PACKAGE" \
             '[.packages[$p][]?.version | sub("^v"; "")] | index($v)' \
             >/dev/null 2>&1; then
      echo "$PACKAGE $VERSION is available on $ECOSYSTEM after ${WAITED}s."
      exit 0
    fi
  else
    STATUS=$(curl -sS -o /dev/null -w '%{http_code}' "$VERSION_URL" || echo 000)
    if [[ "$STATUS" = "200" ]]; then
      echo "$PACKAGE $VERSION is available on $ECOSYSTEM after ${WAITED}s."
      exit 0
    fi
  fi

  sleep "$POLL_SECONDS"
  WAITED=$((WAITED + POLL_SECONDS))
done

# The release itself succeeded — the tag, the GitHub release, and the
# upload are all done. This failure says the package is not resolvable
# yet, so anything that depends on it must not release against it. The
# release sweep reads a failed release as a reason to stop, which is
# the outcome this protects: a dependent that resolves the previous
# version reads it as current, and ships against it without any gate
# objecting.
# Warning: `::error::` is a workflow command rather than a diagnostic. The runner reads it from
# standard output and turns it into an annotation on the run, which is what names the package a
# release must not ship against. It stays on standard output for that reason.
echo "::error::$PACKAGE $VERSION did not appear on $ECOSYSTEM within ${WAIT_MINUTES}m."
exit 1
