#!/usr/bin/env bash
#
# This file is part of the Valkyrja GitHub package.
#
# Copyright (c) 2016-present Melech Mizrachi
#
# Released under the MIT License. See LICENSE.md for details.
#
# ---------------------------------------------------------------------------
# go.mod requirement snapshot.
#
# Prints `<module>\t<version>` for every pinned requirement in the go.mod of the
# directory given as the first argument, so a before and an after snapshot can
# be joined into a change list.
#
# Usage:
#
#     .github/ci/scripts/snapshot-gomod.sh <directory>
# ---------------------------------------------------------------------------

set -e

# Warning: strip comments before splitting, or an `// indirect` marker becomes a
# field. Stripping a leading `require` lets the block form and the single-line
# form parse alike. The `$1 ~ /\./` guard keeps module paths, which always carry
# a dot, and drops the `go` and `toolchain` directives.
#
# Warning: `LC_ALL=C` so the order matches the collation `join` expects.
sed -e 's|//.*||' "$1/go.mod" \
  | sed -e 's|^[[:space:]]*require[[:space:]]*||' \
  | awk '$1 ~ /\./ && $2 ~ /^v/ { print $1 "\t" $2 }' \
  | LC_ALL=C sort -u
