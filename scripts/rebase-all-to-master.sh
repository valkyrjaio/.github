#!/usr/bin/env bash
#
# This file is part of the Valkyrja GitHub package.
#
# Copyright (c) 2016-present Melech Mizrachi
#
# Released under the MIT License. See LICENSE.md for details.
#
# Dispatch the `rebase-to-master` workflow on every repository in the org,
# bringing each repo's `master` up to date with its latest `N.x` version branch.
#
# Each repo's own `rebase-to-master.yml` authenticates as the org GitHub App
# (a ruleset bypass actor), backs up `master` to `master-backup`, rebases it
# onto the latest version branch, and force-pushes — so this works even though
# `master` is protected against direct pushes.
#
# Requires: gh (authenticated, or GH_TOKEN set) and jq.
#
# Usage:
#   scripts/rebase-all-to-master.sh [--dry-run] [--org ORG] [--repo NAME]
#
# Options:
#   --dry-run     List what would be dispatched without triggering anything.
#   --org ORG     Org to target (default: valkyrjaio, or $ORG).
#   --repo NAME   Only target a single repository.
#   -h, --help    Show this help.
#
set -euo pipefail

ORG="${ORG:-valkyrjaio}"
DRY_RUN=false
ONLY_REPO=""
WORKFLOW="rebase-to-master.yml"

while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) DRY_RUN=true ;;
    --org) ORG="$2"; shift ;;
    --repo) ONLY_REPO="$2"; shift ;;
    -h|--help) grep '^#' "$0" | grep -v '^#!' | sed 's/^#\{1,\} \{0,1\}//'; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; exit 1 ;;
  esac
  shift
done

command -v gh >/dev/null || { echo "gh CLI is required" >&2; exit 1; }
command -v jq >/dev/null || { echo "jq is required" >&2; exit 1; }

echo "Org:  $ORG"
$DRY_RUN && echo "Mode: DRY RUN (nothing will be dispatched)"
echo

if [ -n "$ONLY_REPO" ]; then
  REPOS="$ONLY_REPO"
else
  REPOS=$(gh repo list "$ORG" --limit 500 --no-archived --json name --jq '.[].name' | sort)
fi

dispatched=0
skipped=0
failed=0

while IFS= read -r REPO; do
  [ -z "$REPO" ] && continue
  SLUG="$ORG/$REPO"

  # Latest `N.x` version branch (highest major).
  LATEST=$(gh api "repos/$SLUG/branches" --paginate --jq '.[].name' 2>/dev/null \
    | grep -E '^[0-9]+\.x$' | sort -t. -k1,1n | tail -1 || true)

  if [ -z "$LATEST" ]; then
    echo "- $REPO: no N.x version branch — skipping"
    skipped=$((skipped + 1))
    continue
  fi

  # The per-repo caller workflow must be present.
  if ! gh api "repos/$SLUG/contents/.github/workflows/$WORKFLOW" --jq '.name' >/dev/null 2>&1; then
    echo "- $REPO: no $WORKFLOW — skipping"
    skipped=$((skipped + 1))
    continue
  fi

  # How does master relate to the latest version branch?
  CMP=$(gh api "repos/$SLUG/compare/master...$LATEST" 2>/dev/null || true)
  if [ -z "$CMP" ]; then
    echo "- $REPO: cannot compare master...$LATEST — skipping"
    skipped=$((skipped + 1))
    continue
  fi
  STATUS=$(echo "$CMP" | jq -r '.status')
  BEHIND=$(echo "$CMP" | jq -r '.ahead_by')  # commits the version branch has that master lacks
  OWN=$(echo "$CMP" | jq -r '.behind_by')    # commits master has that the version branch lacks

  if [ "$STATUS" = "identical" ]; then
    echo "- $REPO: master already up to date with $LATEST — skipping"
    skipped=$((skipped + 1))
    continue
  fi

  DESC="master behind by $BEHIND"
  [ "$OWN" -gt 0 ] && DESC="$DESC, +$OWN own commit(s) rebase will replay"

  if $DRY_RUN; then
    echo "- $REPO: would dispatch on $LATEST ($DESC)"
    dispatched=$((dispatched + 1))
    continue
  fi

  if gh workflow run "$WORKFLOW" --repo "$SLUG" --ref "$LATEST" >/dev/null 2>&1; then
    echo "- $REPO: dispatched on $LATEST ($DESC)"
    dispatched=$((dispatched + 1))
  else
    echo "- $REPO: FAILED to dispatch on $LATEST" >&2
    failed=$((failed + 1))
  fi
done <<< "$REPOS"

echo
if $DRY_RUN; then
  echo "Summary (dry run): would dispatch=$dispatched  skipped=$skipped"
else
  echo "Summary: dispatched=$dispatched  skipped=$skipped  failed=$failed"
fi

[ "$failed" -eq 0 ]
