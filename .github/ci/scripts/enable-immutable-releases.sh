#!/usr/bin/env bash
#
# This file is part of the Valkyrja GitHub package.
#
# Copyright (c) 2016-present Melech Mizrachi
#
# Released under the MIT License. See LICENSE.md for details.
#
# ---------------------------------------------------------------------------
# Immutable releases.
#
# Enables immutable releases on one repository.
#
# Reads GH_TOKEN, ORG, and REPO_NAME from the environment.
#
# Usage:
#
#     .github/ci/scripts/enable-immutable-releases.sh
# ---------------------------------------------------------------------------

set -euo pipefail

# Immutable releases may already be enforced org-wide by the owner, in which
# case the per-repo PUT returns 409 — that's the desired state, so treat only
# a 409 as success and surface any other error.
if ! immutable_err=$(gh api --method PUT "repos/$ORG/$REPO_NAME/immutable-releases" 2>&1 >/dev/null); then
  if echo "$immutable_err" | grep -q "HTTP 409"; then
    echo 'Immutable releases already enforced org-wide; skipping.'
    exit 0
  fi

  echo "$immutable_err" >&2
  exit 1
fi

echo 'Immutable releases are enabled.'
