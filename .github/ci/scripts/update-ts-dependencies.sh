#!/usr/bin/env bash
#
# This file is part of the Valkyrja GitHub package.
#
# Copyright (c) 2016-present Melech Mizrachi
#
# Released under the MIT License. See LICENSE.md for details.
#
# ---------------------------------------------------------------------------
# TypeScript dependency update.
#
# Runs `npm update` in each directory the calling workflow passes in the
# `dependencies` input, and syncs each caret range in `package.json` to the
# version npm installed.
#
# Reads DEPENDENCIES from the environment, and writes one `name|from|to` line
# per bumped package to /tmp/dependency_changes.txt.
#
# Usage:
#
#     .github/ci/scripts/update-ts-dependencies.sh
# ---------------------------------------------------------------------------

# A bare `run:` step invokes this script, so it sets `set -e`.
# `.github/workflows/README.md` holds the rule for each family, under Scripts.
set -e

: > /tmp/dependency_changes.txt

LENGTH=$(echo "$DEPENDENCIES" | jq 'length')
for i in $(seq 0 $((LENGTH - 1))); do
  NAME=$(echo "$DEPENDENCIES" | jq -r ".[$i].name")
  DIR=$(echo "$DEPENDENCIES" | jq -r ".[$i].directory")

  LOCK_FILE="$DIR/package-lock.json"
  BEFORE=""
  if [[ -f "$LOCK_FILE" ]]; then
    BEFORE=$(jq -r '.packages | to_entries[] | select(.key != "") | "\(.key | ltrimstr("node_modules/")) \(.value.version)"' "$LOCK_FILE" 2>/dev/null || echo "")
  fi

  echo "Updating $NAME..."
  cd "$DIR"
  npm update

  # Sync package.json so the manifest matches the lock file: bump each
  # directly referenced caret range to the version npm just installed.
  # Transitive dependencies are left as lock-only updates.
  for SECTION in dependencies devDependencies; do
    SPECS=$(npm pkg get "$SECTION")
    [[ "$SPECS" = "{}" ]] && continue
    while IFS=$'\t' read -r PKG CURRENT; do
      [[ -z "$PKG" ]] && continue
      # Only sync caret ranges (the constraint style used across Valkyrja manifests).
      case "$CURRENT" in
        ^*) ;;
        *) continue ;;
      esac
      INSTALLED=$(jq -r --arg p "$PKG" '.packages["node_modules/" + $p].version // empty' package-lock.json)
      [[ -z "$INSTALLED" ]] && continue
      NEW="^$INSTALLED"
      [[ "$CURRENT" = "$NEW" ]] && continue
      npm pkg set "$SECTION.$PKG=$NEW"
      echo "  [$SECTION] $PKG: $CURRENT -> $NEW"
    done < <(echo "$SPECS" | jq -r 'to_entries[] | "\(.key)\t\(.value)"')
  done

  cd -

  AFTER=""
  if [[ -f "$LOCK_FILE" ]]; then
    AFTER=$(jq -r '.packages | to_entries[] | select(.key != "") | "\(.key | ltrimstr("node_modules/")) \(.value.version)"' "$LOCK_FILE" 2>/dev/null || echo "")
  fi

  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    PKG=$(echo "$line" | awk '{print $1}')
    NEW_VER=$(echo "$line" | awk '{print $2}')
    OLD_VER=$(echo "$BEFORE" | grep "^$PKG " | awk '{print $2}')
    if [[ -n "$OLD_VER" ]] && [[ "$OLD_VER" != "$NEW_VER" ]]; then
      echo "$PKG|v$OLD_VER|v$NEW_VER" >> /tmp/dependency_changes.txt
    fi
  done <<< "$AFTER"
done
