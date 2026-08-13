#!/usr/bin/env bash
#
# This file is part of the Valkyrja GitHub package.
#
# Copyright (c) 2016-present Melech Mizrachi
#
# Released under the MIT License. See LICENSE.md for details.
#
# ---------------------------------------------------------------------------
# Go dependency update.
#
# Updates each module directory the calling repository declares in
# `.github/update-dependencies.yml`, and records every pinned requirement whose
# version moved.
#
# Reads DEPENDENCIES and GONOPROXY from the environment, and writes one
# `module|from|to` line per change to /tmp/dependency_changes.txt.
#
# Usage:
#
#     .github/ci/scripts/update-go-dependencies.sh
# ---------------------------------------------------------------------------

# Warning: a bare `run:` step runs this, so `-u` and `pipefail` stay off. The
# rule and the shell table are in `.github/workflows/README.md`, under Scripts.
set -e

: > /tmp/dependency_changes.txt

# Extract "<module>\t<version>" for every pinned requirement in a go.mod,
# so the before/after snapshots can be diffed into a change table.
# Comments are stripped first so "// indirect" markers do not become fields,
# and a leading single-line "require " prefix is removed so both the block
# and single-line require forms parse identically. The `$1 ~ /\./` guard
# keeps module paths (which always contain a dot) and drops the `go` and
# `toolchain` directives.
cat > /tmp/snapshot_gomod.sh <<'SH'
#!/bin/sh
# LC_ALL=C so the sort order matches the collation `join` expects below.
sed -e 's|//.*||' "$1/go.mod" \
  | sed -e 's|^[[:space:]]*require[[:space:]]*||' \
  | awk '$1 ~ /\./ && $2 ~ /^v/ { print $1 "\t" $2 }' \
  | LC_ALL=C sort -u
SH
chmod +x /tmp/snapshot_gomod.sh

LENGTH=$(echo "$DEPENDENCIES" | jq 'length')
for i in $(seq 0 $((LENGTH - 1))); do
  NAME=$(echo "$DEPENDENCIES" | jq -r ".[$i].name")
  DIR=$(echo "$DEPENDENCIES" | jq -r ".[$i].directory")

  if [[ ! -f "$DIR/go.mod" ]]; then
    echo "No go.mod in $DIR, skipping $NAME."
    continue
  fi

  echo "Updating $NAME ($DIR)..."
  /tmp/snapshot_gomod.sh "$DIR" > /tmp/before.txt

  if grep -qE '^tool[ (]' "$DIR/go.mod"; then
    # Tool module (e.g. a pinned golangci-lint): it declares no packages of
    # its own, so ./... would match nothing. The `tool` meta-pattern updates
    # every tool listed in the go.mod instead.
    #
    # Deliberately no `-u`: the tool itself still moves to its latest
    # release, but its dependencies are then resolved by MVS from that
    # release's own go.mod. `-u` would instead drag the whole transitive
    # graph to latest, including modules whose newest release is
    # API-incompatible with the tool — a build that the tool's authors
    # never sanctioned. That is not hypothetical: go-header v1.0.0 rewrote
    # its API under the same module path (no /v2), and `-u` pulled it into
    # a golangci-lint v2.12.2 that requires v0.5.0, so the pinned linter no
    # longer compiled and every consumer's lint job failed.
    ( cd "$DIR" && go get tool )
  elif find "$DIR" -name '*.go' -not -path '*/vendor/*' | head -1 | grep -q .; then
    ( cd "$DIR" && go get -u ./... )
  else
    echo "$NAME has no Go packages and no tool directive; tidying only."
  fi

  ( cd "$DIR" && go mod tidy )

  /tmp/snapshot_gomod.sh "$DIR" > /tmp/after.txt
  LC_ALL=C join -t "$(printf '\t')" -j 1 -o 0,1.2,2.2 /tmp/before.txt /tmp/after.txt \
    | awk -F'\t' '$2 != $3 { print $1 "|" $2 "|" $3 }' >> /tmp/dependency_changes.txt
done

LC_ALL=C sort -u -o /tmp/dependency_changes.txt /tmp/dependency_changes.txt
