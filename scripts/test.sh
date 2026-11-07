#!/usr/bin/env bash
# Runs the unit tests. Swift Testing ships with the Command Line Tools but SwiftPM only
# runs it when its framework paths are passed on the command line.
set -euo pipefail
F=/Library/Developer/CommandLineTools/Library/Developer/Frameworks
L=/Library/Developer/CommandLineTools/Library/Developer/usr/lib
cd "$(dirname "$0")/.."
exec swift test -Xswiftc -F"$F" -Xlinker -F"$F" -Xlinker -rpath -Xlinker "$F" -Xlinker -rpath -Xlinker "$L" "$@"
