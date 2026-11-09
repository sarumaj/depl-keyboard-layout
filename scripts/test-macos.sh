#!/usr/bin/env bash
# Tests the macOS layout and installer on a throwaway Mac (the CI's runner):
# checks the layout against Apple's DTD and the bundle's Info.plist, installs
# dist/depl.pkg and checks that the bundle arrived.
#
# Usage: scripts/test-macos.sh [DIST]
set -euo pipefail

dist=${1:-"$(dirname "$0")/../dist"}
target="/Library/Keyboard Layouts/depl.bundle"

xmllint --noout --dtdvalid /System/Library/DTDs/KeyboardLayout.dtd \
    "$dist/depl.bundle/Contents/Resources/depl.keylayout"
plutil -lint "$dist/depl.bundle/Contents/Info.plist"
sudo installer -pkg "$dist/depl.pkg" -target /
test -f "$target/Contents/Resources/depl.keylayout"
cmp "$dist/depl.bundle/Contents/Resources/depl.keylayout" "$target/Contents/Resources/depl.keylayout"
echo "The package installs $target."
