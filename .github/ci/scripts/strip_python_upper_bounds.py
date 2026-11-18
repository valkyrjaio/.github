#
# This file is part of the Valkyrja GitHub package.
#
# Copyright (c) 2016-present Melech Mizrachi
#
# Released under the MIT License. See LICENSE.md for details.
#
# ---------------------------------------------------------------------------
# Upper bound removal for the Python outdated check.
#
# `uv lock --upgrade` resolves within the declared constraints, so it never
# proposes a newer major. This rewrites a copy of the manifest without the
# upper bounds, and the caller re-resolves that copy to learn the latest major.
#
# Takes the manifest's path as an argument, and rewrites that file in place.
# ---------------------------------------------------------------------------

import re, sys

path = sys.argv[1]
source = open(path).read()
# Drop any upper bound (",<2" / ", <= 2.1") from a dependency specifier,
# leaving the floor and any environment marker untouched.
open(path, "w").write(re.sub(r",\s*<=?\s*[0-9][^,;\"'\]\s]*", "", source))
