#!/usr/bin/env bash
#
# This file is part of the Valkyrja GitHub package.
#
# Copyright (c) 2016-present Melech Mizrachi
#
# Released under the MIT License. See LICENSE.md for details.
#
# ---------------------------------------------------------------------------
# Python dependency update.
#
# Runs `uv lock --upgrade` in each directory the calling repository declares in
# `.github/update-dependencies.yml`, and syncs each declared lower bound in
# `pyproject.toml` to the version the lock resolved.
#
# Reads DEPENDENCIES from the environment. It writes the version change of
# each package to /tmp/dependency_changes.txt, which the pull request body reads.
#
# Usage:
#
#     .github/ci/scripts/update-python-dependencies.sh
# ---------------------------------------------------------------------------

# Warning: a bare `run:` step runs this, so `-u` and `pipefail` stay off. The
# rule and the shell table are in `.github/workflows/README.md`, under Scripts.
set -e

: > /tmp/dependency_changes.txt

# Warning: a transitive dependency stays lock-only. Raising a bound the manifest
# never declared would pin a version the project does not depend on.
cat > /tmp/sync_pyproject.py <<'PY'
import re
import sys
import tomllib

directory = sys.argv[1]
manifest_path = f"{directory}/pyproject.toml"
lock_path = f"{directory}/uv.lock"


def normalize(name):
    # PEP 503 normalization: lowercase, runs of -_. collapse to a single -.
    return re.sub(r"[-_.]+", "-", name).lower()


with open(manifest_path, "rb") as fh:
    manifest = tomllib.load(fh)
with open(lock_path, "rb") as fh:
    lock = tomllib.load(fh)

# Resolved versions, excluding the project's own local (virtual/editable) root.
resolved = {}
for package in lock.get("package", []):
    source = package.get("source", {})
    if "virtual" in source or "editable" in source:
        continue
    resolved[normalize(package["name"])] = package["version"]

# Every directly declared requirement string.
requirements = []
project = manifest.get("project", {})
requirements += [r for r in project.get("dependencies", []) if isinstance(r, str)]
for extra in project.get("optional-dependencies", {}).values():
    requirements += [r for r in extra if isinstance(r, str)]
for group in manifest.get("dependency-groups", {}).values():
    requirements += [r for r in group if isinstance(r, str)]

with open(manifest_path, encoding="utf-8") as fh:
    raw = fh.read()

name_re = re.compile(r"^\s*([A-Za-z0-9][A-Za-z0-9._-]*)\s*(\[[^\]]*\])?\s*(.*)$")
floor_re = re.compile(r">=\s*([0-9][^,;\s]*)")

changes = []
for requirement in requirements:
    match = name_re.match(requirement)
    if not match:
        continue
    floor = floor_re.search(match.group(3))
    if not floor:
        continue
    old = floor.group(1)
    new = resolved.get(normalize(match.group(1)))
    if not new or new == old:
        continue
    updated, count = re.subn(
        r"(>=\s*)" + re.escape(old), r"\g<1>" + new, requirement, count=1
    )
    if count and updated != requirement and requirement in raw:
        raw = raw.replace(requirement, updated, 1)
        changes.append((match.group(1), old, new))

if changes:
    with open(manifest_path, "w", encoding="utf-8") as fh:
        fh.write(raw)
for name, old, new in changes:
    print(f"{name}|>={old}|>={new}")
PY

LENGTH=$(echo "$DEPENDENCIES" | jq 'length')
for i in $(seq 0 $((LENGTH - 1))); do
  NAME=$(echo "$DEPENDENCIES" | jq -r ".[$i].name")
  DIR=$(echo "$DEPENDENCIES" | jq -r ".[$i].directory")

  echo "Updating $NAME ($DIR)..."
  ( cd "$DIR" && uv lock --upgrade )

  echo "Syncing $NAME pyproject.toml lower bounds to uv.lock..."
  uv run --no-project python /tmp/sync_pyproject.py "$DIR" >> /tmp/dependency_changes.txt

  # uv.lock records the manifest's constraint in [package.metadata]
  # requires-dist, so rewriting pyproject.toml above leaves that line
  # describing the pre-update constraint. Re-lock to bring it back in
  # step. Without this the outdated check — which fails when
  # `uv lock --upgrade` produces any diff — reports the dependency as
  # outdated forever, because every update run recreates the mismatch.
  echo "Re-locking $NAME so uv.lock records the new constraint..."
  ( cd "$DIR" && uv lock --quiet )
done
