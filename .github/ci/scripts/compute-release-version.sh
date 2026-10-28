#!/usr/bin/env bash
#
# This file is part of the Valkyrja GitHub package.
#
# Copyright (c) 2016-present Melech Mizrachi
#
# Released under the MIT License. See LICENSE.md for details.
#
# ---------------------------------------------------------------------------
# Release version computation.
#
# Computes the version that the release publishes, and says whether anything is
# pending. Writes `version`, `major-version`, and `should-release` to
# `$GITHUB_OUTPUT`.
#
# Every explicit bump releases. Only `auto` decides that nothing is pending,
# and it reads the conventional types merged since the last tag.
#
# A stable release comes from a major version branch. A release candidate comes
# from master, and it targets a year that has no branch yet.
#
# Reads BUMP, BRANCH, GITHUB_REPOSITORY, and GITHUB_OUTPUT from the
# environment, and GH_TOKEN for the `gh` calls. SUPPORTED_VERSIONS is the year
# gate. It is optional for a stable release, and an RC fails without it.
# ---------------------------------------------------------------------------

# A bare `run:` step invokes this script, so it sets `set -e` alone.
# `.github/workflows/README.md` holds the rule for each family, under Scripts.
set -e

: "${BUMP:?BUMP must name the version component to bump}"
: "${BRANCH:?BRANCH must name the branch the release runs from}"

# Every explicit bump releases. Only "auto" can decide there is nothing to do.
echo "should-release=true" >> "$GITHUB_OUTPUT"

# Release candidates must come from master and target the next unreleased major
if [[ "$BUMP" = "rc" ]]; then
  if [[ "$BRANCH" != "master" ]]; then
    echo "Release candidates must be created from master. Current branch: $BRANCH"
    exit 1
  fi

  # Find the highest existing major version branch
  HIGHEST_MAJOR=$(gh api "repos/$GITHUB_REPOSITORY/branches" --paginate \
    --jq '.[].name' 2>/dev/null \
    | grep -E '^[0-9]+\.x$' \
    | sed 's/\.x//' \
    | sort -n \
    | tail -1 || echo "")

  if [[ -z "$HIGHEST_MAJOR" ]]; then
    echo "No version branches found. Cannot determine next major version for RC."
    exit 1
  fi

  NEXT_MAJOR=$((HIGHEST_MAJOR + 1))

  # An RC targets a year that has not opened yet, so gate it on both facts
  # that make that true. Without these the RC path publishes whatever
  # "highest branch + 1" happens to be, with nothing confirming the year is
  # real — `validate-release-version.sh` returns early for an RC-shaped
  # version, so it never reaches its own SUPPORTED_VERSIONS check.
  if [[ -z "$SUPPORTED_VERSIONS" ]]; then
    echo "SUPPORTED_VERSIONS is not set. Refusing to publish an RC with no year gate."
    exit 1
  elif ! [[ "$NEXT_MAJOR" =~ $SUPPORTED_VERSIONS ]]; then
    echo "An RC here would target v${NEXT_MAJOR}.0.0, but $NEXT_MAJOR is not in the supported versions ($SUPPORTED_VERSIONS)."
    echo "Widen SUPPORTED_VERSIONS before opening the next year. Aborting."
    exit 1
  fi

  if gh api "repos/$GITHUB_REPOSITORY/branches/${NEXT_MAJOR}.x" --silent 2>/dev/null; then
    echo "Branch ${NEXT_MAJOR}.x already exists, so v${NEXT_MAJOR} is no longer unreleased."
    echo "Release from that branch with a yearly bump instead of an RC. Aborting."
    exit 1
  fi

  echo "v${NEXT_MAJOR} is supported and ${NEXT_MAJOR}.x does not exist yet. Proceeding."

  # Find the highest existing RC number for this next major
  LATEST_RC=$(gh release list --repo "$GITHUB_REPOSITORY" --limit 100 \
    --json tagName,isPrerelease \
    --jq '.[] | select(.isPrerelease == true) | .tagName' 2>/dev/null \
    | grep -E "^v${NEXT_MAJOR}\.0\.0-RC[0-9]+$" \
    | sed "s/^v${NEXT_MAJOR}\.0\.0-RC//" \
    | sort -n \
    | tail -1 || echo "0")

  NEXT_RC=$((LATEST_RC + 1))
  NEW_VERSION="${NEXT_MAJOR}.0.0-RC${NEXT_RC}"

  echo "Computed RC version: v$NEW_VERSION (based on highest version branch: ${HIGHEST_MAJOR}.x)"
  echo "version=$NEW_VERSION" >> "$GITHUB_OUTPUT"
  echo "major-version=$NEXT_MAJOR" >> "$GITHUB_OUTPUT"
  exit 0
fi

# Validate branch — all stable releases must come from a major version branch
if [[ "$BRANCH" = "master" ]]; then
  echo "Stable releases cannot be triggered from master."
  echo "Create a version branch (e.g. 26.x) first, then release from it."
  echo "For a release candidate, use the 'rc' bump type."
  exit 1
elif [[ "$BRANCH" =~ ^([0-9]+)\.x$ ]]; then
  BRANCH_MAJOR="${BASH_REMATCH[1]}"
else
  echo "Releases must be triggered from a major version branch (e.g. 26.x)."
  exit 1
fi

# A yearly bump is the first release on a version branch: always BRANCH_MAJOR.0.0
if [[ "$BUMP" = "yearly" ]]; then
  echo "Yearly bump on $BRANCH: releasing v${BRANCH_MAJOR}.0.0"
  echo "version=${BRANCH_MAJOR}.0.0" >> "$GITHUB_OUTPUT"
  echo "major-version=${BRANCH_MAJOR}" >> "$GITHUB_OUTPUT"
  exit 0
fi

# For auto/feature/patch: only look at this major's releases
FILTER_PATTERN="^v${BRANCH_MAJOR}\.[0-9]+\.[0-9]+$"

LATEST_TAG=$(gh release list --repo "$GITHUB_REPOSITORY" --limit 100 --json tagName --jq '.[].tagName' 2>/dev/null \
  | grep -E "$FILTER_PATTERN" \
  | sort -V \
  | tail -1 \
  || echo "")

# `sort -V` reads a padded component at its numeric value, so a padded tag wins
# only by being the highest. The components below then carry the padding.
if [[ "$LATEST_TAG" =~ ^v[0-9]+\.(0[0-9]+\.[0-9]+|[0-9]+\.0[0-9]+)$ ]]; then
  echo "Latest release $LATEST_TAG carries a leading zero in a version component."
  echo "Delete that release before releasing from v${BRANCH_MAJOR}.x. Aborting."
  exit 1
fi

if [[ -z "$LATEST_TAG" ]]; then
  echo "No existing releases found for v${BRANCH_MAJOR}.x. Releasing v${BRANCH_MAJOR}.0.0"
  echo "version=${BRANCH_MAJOR}.0.0" >> "$GITHUB_OUTPUT"
  echo "major-version=${BRANCH_MAJOR}" >> "$GITHUB_OUTPUT"
  exit 0
else
  LATEST="${LATEST_TAG#v}"
  LATEST_MAJOR=$(echo "$LATEST" | cut -d. -f1)
  LATEST_MINOR=$(echo "$LATEST" | cut -d. -f2)
  LATEST_PATCH=$(echo "$LATEST" | cut -d. -f3)
  echo "Latest release: $LATEST_TAG"
fi

# Resolve "auto" from the conventional types merged since the last tag.
# Subjects are read rather than bodies: squash merges take their subject from
# the PR title, so the subject *is* the conventional line.
if [[ "$BUMP" = "auto" ]]; then
  COMPARE=$(gh api "repos/$GITHUB_REPOSITORY/compare/${LATEST_TAG}...${BRANCH}" 2>/dev/null || echo "")
  if [[ -z "$COMPARE" ]]; then
    echo "Could not compare $LATEST_TAG...$BRANCH. Aborting rather than guessing a bump."
    exit 1
  fi

  TOTAL=$(echo "$COMPARE" | jq -r '.total_commits // 0')
  SUBJECTS=$(echo "$COMPARE" | jq -r '.commits[]?.commit.message | split("\n")[0]')
  RETURNED=$(printf '%s\n' "$SUBJECTS" | grep -cE '\S' || true)

  # Release bookkeeping carries a release-version root ([v26.6.1]) and never
  # triggers a release — that root, not the type, is the non-triggering signal.
  CANDIDATES=$(printf '%s\n' "$SUBJECTS" | grep -vE '^\[v[0-9]' | grep -E '\S' || true)

  TYPES='feat|fix|deprecate|docs|test|refactor|perf|style|build|ci|chore|revert'

  if [[ "$TOTAL" -gt "$RETURNED" ]]; then
    # The compare API caps its commit list. Round up rather than under-bump:
    # a missed feat must never ship as a patch.
    echo "Window holds $TOTAL commits but the API returned $RETURNED; assuming a feature bump."
    BUMP="feature"
  elif [[ -z "$CANDIDATES" ]]; then
    echo "Nothing pending since $LATEST_TAG — no release."
    echo "should-release=false" >> "$GITHUB_OUTPUT"
    exit 0
  elif printf '%s\n' "$CANDIDATES" | grep -qE "^(\[[^]]+\])+ (feat|deprecate)(\(#[0-9]+\))?!?: " \
    || printf '%s\n' "$CANDIDATES" | grep -qE "^(\[[^]]+\])+ ($TYPES)(\(#[0-9]+\))?!: "; then
    echo "Found a feat, deprecate, or breaking change since $LATEST_TAG."
    BUMP="feature"
  else
    echo "Only patch-level types since $LATEST_TAG."
    BUMP="patch"
  fi

  echo "Resolved auto to a $BUMP bump."
fi

# Calculate new version
case "$BUMP" in
  feature)
    NEW_MAJOR="$LATEST_MAJOR"
    NEW_MINOR=$((LATEST_MINOR + 1))
    NEW_PATCH=0
    ;;
  patch)
    NEW_MAJOR="$LATEST_MAJOR"
    NEW_MINOR="$LATEST_MINOR"
    NEW_PATCH=$((LATEST_PATCH + 1))
    ;;
  *)
    echo "Invalid bump type: $BUMP. Must be auto, patch, feature, yearly, or rc."
    exit 1
    ;;
esac

NEW_VERSION="${NEW_MAJOR}.${NEW_MINOR}.${NEW_PATCH}"
echo "Computed version: v$NEW_VERSION"
echo "version=$NEW_VERSION" >> "$GITHUB_OUTPUT"
echo "major-version=$NEW_MAJOR" >> "$GITHUB_OUTPUT"
