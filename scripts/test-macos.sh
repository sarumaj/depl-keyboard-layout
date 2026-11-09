#!/usr/bin/env bash
# Tests the macOS layout and installer on a throwaway Mac (the CI's runner):
# checks the layout against Apple's DTD and the bundle's Info.plist, installs
# dist/depl.pkg, checks that the bundle arrived and types with it
# (test-macos-layout.swift).
#
# Usage: scripts/test-macos.sh [DIST]
set -euo pipefail

dist=${1:-"$(dirname "$0")/../dist"}
target="/Library/Keyboard Layouts/depl.bundle"

# The layout is XML 1.1 (control characters as &#x0008;), which libxml2 cannot read:
# xmllint checks a copy as XML 1.0 with those characters as spaces.
copy=$(mktemp)
trap 'rm -f "$copy"' EXIT
sed -e '1s/version="1.1"/version="1.0"/' -e 's/&#x00[01][0-9A-Fa-f];/\&#x0020;/g' \
    "$dist/depl.bundle/Contents/Resources/depl.keylayout" > "$copy"
xmllint --noout --dtdvalid /System/Library/DTDs/KeyboardLayout.dtd "$copy"
plutil -lint "$dist/depl.bundle/Contents/Info.plist"
sudo installer -pkg "$dist/depl.pkg" -target /
test -f "$target/Contents/Resources/depl.keylayout"
cmp "$dist/depl.bundle/Contents/Resources/depl.keylayout" "$target/Contents/Resources/depl.keylayout"
echo "The package installs $target."
swift "$(dirname "$0")/test-macos-layout.swift" "$target"
