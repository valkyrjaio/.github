#!/usr/bin/env bash
#
# This file is part of the Valkyrja GitHub package.
#
# Copyright (c) 2016-present Melech Mizrachi
#
# Released under the MIT License. See LICENSE.md for details.
#
# ---------------------------------------------------------------------------
# Dependency update pull request.
#
# Opens the pull request that carries a dependency update. The body follows the
# repository's pull request template, and it lists every package the update
# moved.
#
# Reads GH_TOKEN, BASE, BRANCH, TITLE, SUMMARY, and CHANGES_MESSAGE from the
# environment, and fails the step when the caller sets none of them.
#
# COLUMN_HEADING is optional, and it heads the table's first column. A caller
# that sets it gets a table of every package the update moved, read from
# /tmp/dependency_changes.txt as one `name|from|to` line per package. A caller
# whose update script records no version change sets no heading, and the body
# then carries CHANGES_MESSAGE under `## Changes` on every run.
#
# Usage:
#
#     .github/ci/scripts/create-dependency-pull-request.sh
# ---------------------------------------------------------------------------

# A bare `run:` step invokes this script, so it sets `set -e`.
# `.github/workflows/README.md` holds the rule for each family, under Scripts.
set -e

BODY=""
BODY+="# Description"$'\n'$'\n'
BODY+="${SUMMARY:?}"$'\n'$'\n'
BODY+="## Types of changes"$'\n'$'\n'
BODY+="- [X] Improvement _(non-breaking change which improves code)_"$'\n'
BODY+="- [ ] Bug fix _(non-breaking change which fixes an issue)_"$'\n'
BODY+="- [ ] New feature _(non-breaking change which adds functionality)_"$'\n'
BODY+="- [ ] Deprecation _(breaking change which removes functionality)_"$'\n'
BODY+="- [ ] Breaking change _(fix or feature that would cause existing functionality to change)_"$'\n'
BODY+="- [ ] Documentation improvement"$'\n'$'\n'
BODY+="## Changes"$'\n'$'\n'

if [[ -n "${COLUMN_HEADING:-}" && -s /tmp/dependency_changes.txt ]]; then
  # The separator matches the heading it sits under, so the rendered table lines up.
  SEPARATOR="$(printf '%*s' "$(( ${#COLUMN_HEADING} + 2 ))" '' | tr ' ' '-')"

  BODY+="| $COLUMN_HEADING | From | To |"$'\n'
  BODY+="|$SEPARATOR|------|----|"$'\n'

  while IFS='|' read -r NAME FROM TO; do
    BODY+="| \`$NAME\` | $FROM | $TO |"$'\n'
  done < /tmp/dependency_changes.txt
else
  BODY+="${CHANGES_MESSAGE:?}"$'\n'
fi

gh pr create \
  --title "${TITLE:?}" \
  --body "$BODY" \
  --base "${BASE:?}" \
  --head "${BRANCH:?}"
