#!/usr/bin/env bash
#
# This file is part of the Valkyrja GitHub package.
#
# Copyright (c) 2016-present Melech Mizrachi
#
# Released under the MIT License. See LICENSE.md for details.
#
# ---------------------------------------------------------------------------
# Outdated Go dependency check.
#
# Every path in this script is relative — `go.mod` and `.` — and the caller
# sets the directory with `working-directory`, so a matrix leg checks its own
# module.
#
# Reads NAME from the environment, which names the module a matrix leg checks.
# The `go` toolchain reads GONOPROXY, which the step passes as well.
#
# Usage, from the module's own directory:
#
#     NAME=golangci-lint /path/to/.github/ci/scripts/check-outdated-go-dependencies.sh
# ---------------------------------------------------------------------------

# A bare `run:` step invokes this script, so it sets `set -e` alone.
# `.github/workflows/README.md` holds the rule for each family, under Scripts.
#
# Warning: `pipefail` must stay absent. `head -1` closes the pipe below, and
# `find` is signalled once it has more output than the pipe buffer holds, which
# a small module never reaches. With `pipefail` the `elif` reads that as a
# failure, so the check skips `go get -u ./...` and passes.
set -e

# Rather than interpreting `go list -u -m` output, this performs the very
# same upgrade `_go-update-dependencies.yml` would perform and then asks
# git whether anything moved. The check therefore can never disagree with
# the workflow that does the updating. Nothing is committed — this runs on
# a throwaway CI checkout.
if grep -qE '^tool[ (]' go.mod; then
  # Tool module: it declares no packages of its own, so ./... matches
  # nothing. The `tool` meta-pattern upgrades every declared tool instead.
  # No `-u` here, matching `_go-update-dependencies.yml` — the tool moves
  # to its latest release and MVS resolves its dependencies from that
  # release's go.mod, so this check can never report a tool module as
  # outdated in a way the updater would not actually produce.
  go get tool
# The `set` line above explains why `pipefail` must stay absent for this pipeline.
elif find . -name '*.go' -not -path '*/vendor/*' | head -1 | grep -q .; then
  go get -u ./...
else
  echo "$NAME has no Go packages and no tool directive; checking tidiness only."
fi

go mod tidy

# Scoped to this dependency's own directory so a matrix leg only ever
# reports on the module it was asked to check.
if ! git diff --quiet -- .; then
  echo ""
  echo "Outdated dependencies found in $NAME! Update all dependencies before releasing."
  echo ""
  git --no-pager diff -- go.mod
  exit 1
fi

echo "All $NAME dependencies are up to date."
