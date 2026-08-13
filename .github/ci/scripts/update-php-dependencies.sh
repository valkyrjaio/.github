#!/usr/bin/env bash
#
# This file is part of the Valkyrja GitHub package.
#
# Copyright (c) 2016-present Melech Mizrachi
#
# Released under the MIT License. See LICENSE.md for details.
#
# ---------------------------------------------------------------------------
# PHP dependency update.
#
# This script runs the composer commands that the calling workflow passes in
# the `dependencies` input, and it syncs the constraints in `composer.json` to
# what the update resolved. It records the version change of every package, so
# the pull request body can list them.
#
# Reads DEPENDENCIES from the environment. It writes the version change of
# each package to /tmp/dependency_changes.txt, which the pull request body reads.
#
# Usage:
#
#     .github/ci/scripts/update-php-dependencies.sh
# ---------------------------------------------------------------------------

# Warning: `-u` and `pipefail` are deliberately absent. This script carries a
# block from a `run:` step that names no shell, and GitHub runs that as
# `bash -e {0}`. An action step is the other case, and a script it invokes sets
# `pipefail`.
set -e

# Escape a string for literal use in a POSIX BRE. Only . [ * ^ $ \ are
# metacharacters there — escaping | + ? ( ) { } turns them into GNU sed
# operators instead (\| is alternation, which matches the empty string
# and rewrites the wrong span), so they are deliberately left alone.
escape_bre() {
  local literal="$1"

  printf '%s' "$literal" | sed 's/[.[*^$\\]/\\&/g'
}

# Rewrite "$2" to "$3" on package "$1"'s line in $COMPOSER_FILE, then
# confirm the file is still valid JSON so a bad rewrite fails loudly
# here rather than as a cryptic jq parse error later in the loop.
replace_on_package_line() {
  local package="$1" from="$2" to="$3"

  sed -i "\|\"$(escape_bre "$package")\"|s/\"$(escape_bre "$from")\"/\"$to\"/" "$COMPOSER_FILE"

  if ! jq empty "$COMPOSER_FILE" 2>/dev/null; then
    # `::error::` is a workflow command rather than a diagnostic. The runner reads it from
    # standard output to build the run annotation, so it does not go to stderr.
    echo "::error::Rewriting $package ($from -> $to) produced invalid JSON in $COMPOSER_FILE"
    exit 1
  fi
}

: > /tmp/dependency_changes.txt

LENGTH=$(echo "$DEPENDENCIES" | jq 'length')
for i in $(seq 0 $((LENGTH - 1))); do
  NAME=$(echo "$DEPENDENCIES" | jq -r ".[$i].name")
  CMD=$(echo "$DEPENDENCIES" | jq -r ".[$i].command")
  DIR=$(echo "$DEPENDENCIES" | jq -r ".[$i].directory // \".\"")

  LOCK_FILE="$DIR/composer.lock"
  BEFORE=""
  if [[ -f "$LOCK_FILE" ]]; then
    BEFORE=$(jq -r '(.packages + (.["packages-dev"] // []))[] | "\(.name) \(.version)"' "$LOCK_FILE" 2>/dev/null || echo "")
  fi

  echo "Updating $NAME..."
  # shellcheck disable=SC2086 # The value is a whole subcommand with flags, so it must word split.
  composer $CMD

  echo "Syncing $NAME composer.json version constraints..."
  INSTALLED=""
  if [[ -f "$LOCK_FILE" ]]; then
    INSTALLED=$(jq -r '(.packages + (.["packages-dev"] // []))[] | "\(.name) \(.version)"' "$LOCK_FILE" 2>/dev/null || echo "")
  fi

  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    PKG=$(echo "$line" | awk '{print $1}')
    VER=$(echo "$line" | awk '{print $2}' | sed 's/^v//')

    [[ "$VER" =~ ^[0-9]+\.[0-9]+\.[0-9]+ ]] || continue

    COMPOSER_FILE="$DIR/composer.json"
    PKG_ESC=$(escape_bre "$PKG")

    # require / require-dev: "^OLD" → "^NEW"
    for SECTION in require require-dev; do
      OLD=$(jq -r --arg p "$PKG" --arg s "$SECTION" '.[$s][$p] // ""' "$COMPOSER_FILE")
      [[ -z "$OLD" ]] && continue
      # A composite constraint ("^3.5 || ^4.0") deliberately spans
      # majors — collapsing it to the installed version would silently
      # drop support, so leave it for a human to widen or narrow.
      case "$OLD" in
        *'|'*)
          echo "  [$SECTION] $PKG: left composite constraint $OLD unchanged"
          continue
          ;;
        *) ;;
      esac
      NEW="^$VER"
      [[ "$OLD" = "$NEW" ]] && continue
      replace_on_package_line "$PKG" "$OLD" "$NEW"
      echo "  [$SECTION] $PKG: $OLD -> $NEW"
    done

    # conflict: "<OLD" → "<NEW"
    OLD_CONFLICT=$(jq -r --arg p "$PKG" '.conflict[$p] // ""' "$COMPOSER_FILE")
    if [[ -n "$OLD_CONFLICT" ]]; then
      NEW_CONFLICT="<$VER"
      if [[ "$OLD_CONFLICT" != "$NEW_CONFLICT" ]]; then
        replace_on_package_line "$PKG" "$OLD_CONFLICT" "$NEW_CONFLICT"
        echo "  [conflict] $PKG: $OLD_CONFLICT -> $NEW_CONFLICT"
      fi
    fi

    # suggest: update version number(s) embedded in description string
    HAS_SUGGEST=$(jq -r --arg p "$PKG" 'if .suggest and (.suggest | has($p)) then "true" else "false" end' "$COMPOSER_FILE")
    if [[ "$HAS_SUGGEST" = "true" ]]; then
      sed -i -E "\|\"$PKG_ESC\"| s/[0-9]+\.[0-9]+\.[0-9]+[0-9.]*/$VER/g" "$COMPOSER_FILE"
      echo "  [suggest] $PKG: updated version in description"
    fi
    # Track version change for PR body
    OLD_VER=$(echo "$BEFORE" | grep "^$PKG " | awk '{print $2}' | sed 's/^v//')
    if [[ -n "$OLD_VER" ]] && [[ "$OLD_VER" != "$VER" ]]; then
      echo "$PKG|v$OLD_VER|v$VER" >> /tmp/dependency_changes.txt
    fi
  done <<< "$INSTALLED"
done
