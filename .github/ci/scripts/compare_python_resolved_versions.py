#
# This file is part of the Valkyrja GitHub package.
#
# Copyright (c) 2016-present Melech Mizrachi
#
# Released under the MIT License. See LICENSE.md for details.
#
# ---------------------------------------------------------------------------
# Resolved version comparison for the Python outdated check.
#
# Reads two lock files and reports each package the second resolves to a
# different version, which is the equivalent of npm's `wanted` vs `latest`.
#
# Takes both lock files' paths as arguments. Exits 1 when a package moved, and
# 0 when none did.
# ---------------------------------------------------------------------------

import sys, tomllib

def resolved(path):
    with open(path, "rb") as handle:
        return {
            package["name"]: package.get("version", "")
            for package in tomllib.load(handle).get("package", [])
        }

current, unbounded = resolved(sys.argv[1]), resolved(sys.argv[2])
moved = sorted(
    (name, current[name], unbounded[name])
    for name in current
    if name in unbounded and current[name] != unbounded[name]
)

for name, was, now in moved:
    print(f"  {name}: {was} -> {now}")

sys.exit(1 if moved else 0)
