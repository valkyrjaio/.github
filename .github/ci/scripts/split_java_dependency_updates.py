#
# This file is part of the Valkyrja GitHub package.
#
# Copyright (c) 2016-present Melech Mizrachi
#
# Released under the MIT License. See LICENSE.md for details.
#
# ---------------------------------------------------------------------------
# Dependency update classification for the Java outdated check.
#
# Reads the `gradle dependencyUpdates` report and splits each available upgrade
# by the major boundary, because policy reserves a major for the year boundary.
#
# Takes MAJOR_RELEASE, the module name, and the report's path as arguments.
# Exits 1 when an upgrade blocks the run, and 0 when none does.
# ---------------------------------------------------------------------------

import re, sys

major_release = sys.argv[1] == "true"
name = sys.argv[2]
report = open(sys.argv[3]).read()

# " - group:artifact [1.2.3 -> 1.3.0]"
entry = re.compile(r"^\s*-\s+(\S+?):(\S+?)\s+\[(\S+)\s*->\s*([^\]]+)\]", re.M)

def major(version):
    head = re.match(r"\d+", version)
    return int(head.group()) if head else None

within, across = [], []
for group, artifact, current, latest in entry.findall(report):
    current_major, latest_major = major(current), major(latest.strip())
    line = f"  {group}:{artifact} [{current} -> {latest.strip()}]"
    if current_major is not None and latest_major is not None and latest_major > current_major:
        across.append(line)
    else:
        within.append(line)

if across:
    print(f"Major upgrades available for {name}:")
    print("\n".join(across))

if within:
    print(f"Upgrades within the current major for {name}:")
    print("\n".join(within))

if major_release:
    if within or across:
        print(f"All {name} dependencies must be at their latest, including majors, before creating a major version branch.")
        sys.exit(1)
elif within:
    print(f"{name} dependencies must be updated before releasing.")
    sys.exit(1)
elif across:
    print(f"::notice title={name}::Major upgrades are available but are reserved for the next version line; they do not block this release.")

sys.exit(0)
