#!/usr/bin/env bash
# Builds the macOS installer from dist/depl.bundle (scripts/build.py): a package
# that puts the bundle into /Library/Keyboard Layouts, for everyone on the Mac.
# Needs macOS (pkgbuild). The package is not signed: macOS asks once whether to
# open it (README.md).
#
# Usage: scripts/build-macos.sh [DIST]
set -euo pipefail

dist=${1:-"$(dirname "$0")/../dist"}
version=$(cat "$dist/VERSION")
root=$(mktemp -d)
trap 'rm -rf "$root"' EXIT

mkdir -p "$root/Library/Keyboard Layouts"
cp -R "$dist/depl.bundle" "$root/Library/Keyboard Layouts/"
pkgbuild --root "$root" --identifier org.ciepiela.keyboardlayout.depl --version "$version" \
    --install-location / "$dist/depl.pkg"
echo "Built $dist/depl.pkg ($version)"
