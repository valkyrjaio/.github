#!/usr/bin/env bash
#
# This file is part of the Valkyrja GitHub package.
#
# Copyright (c) 2016-present Melech Mizrachi
#
# Released under the MIT License. See LICENSE.md for details.
#
# ---------------------------------------------------------------------------
# Outdated Python dependency check.
#
# The `uv` command resolves against the current directory, and the caller sets
# that with `working-directory`, so a matrix leg checks its own project.
#
# Reads MAJOR_RELEASE, which says whether a major upgrade blocks the run, and
# NAME, which names the project a matrix leg checks.
#
# Usage, from the project's own directory:
#
#     MAJOR_RELEASE=false NAME=Ruff \
#         /path/to/.github/ci/scripts/check-outdated-python-dependencies.sh
# ---------------------------------------------------------------------------

# A bare `run:` step invokes this script, so it sets `set -e` alone.
# `.github/workflows/README.md` holds the rule for each family, under Scripts.
set -e

# In-range check. `uv lock --upgrade` resolves within the declared
# constraints, so with bounded specifiers this proposes only what a release
# is allowed to take.
uv lock --upgrade --quiet

if ! git diff --quiet -- uv.lock; then
  echo "::group::Outdated $NAME dependencies"
  git --no-pager diff -- uv.lock || true
  echo "::endgroup::"
  echo "Python dependencies must be updated before releasing."
  exit 1
fi

if [[ "$MAJOR_RELEASE" != "true" ]]; then
  echo "All $NAME dependencies are up to date within their declared constraints."
  exit 0
fi

# Major check. A newer major sits outside the declared upper bound, so
# `uv lock --upgrade` can never propose one — deciding this with the same
# command would report clean forever and the year-boundary gate would never
# gate anything. Re-resolve a copy with the upper bounds removed and compare
# resolved versions, which is the equivalent of npm's `wanted` vs `latest`.
PROBE=$(mktemp -d)
cp pyproject.toml uv.lock "$PROBE/"

# The caller runs this script from the project's own directory, so each sibling
# is found through `BASH_SOURCE` rather than the working directory.
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

python3 "$SCRIPT_DIR/strip_python_upper_bounds.py" "$PROBE/pyproject.toml"

( cd "$PROBE" && uv lock --upgrade --quiet )

python3 "$SCRIPT_DIR/compare_python_resolved_versions.py" uv.lock "$PROBE/uv.lock"
status=$?

if [[ "$status" -eq 0 ]]; then
  echo "All $NAME dependencies are at their latest, including majors."
  exit 0
fi

echo "Python dependencies (including major versions) must be updated before creating a major version branch."
exit 1
