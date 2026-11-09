#!/usr/bin/env bash
# Tests the macOS layout and installer on a throwaway Mac (the CI's runner):
# checks the bundle's Info.plist, installs dist/depl.pkg, checks that the bundle
# arrived and types with it as macOS compiles it (test-macos-layout.swift).
#
# Not against Apple's DTD: Apple's own layouts fail it (actions named after
# their characters, such as " " or "^", are no XML IDs; the JIS key maps'
# baseIndex is not declared), so it cannot tell a good layout from a bad one.
#
# Usage: scripts/test-macos.sh [DIST]
set -euo pipefail

dist=${1:-"$(dirname "$0")/../dist"}
target="/Library/Keyboard Layouts/depl.bundle"

plutil -lint "$dist/depl.bundle/Contents/Info.plist"
sudo installer -pkg "$dist/depl.pkg" -target /
test -f "$target/Contents/Resources/depl.keylayout"
cmp "$dist/depl.bundle/Contents/Resources/depl.keylayout" "$target/Contents/Resources/depl.keylayout"
echo "The package installs $target."
swift "$(dirname "$0")/test-macos-layout.swift" "$target"
