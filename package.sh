#!/bin/bash
# Builds GridSnap and packages it as a shareable DMG in ./dist
set -euo pipefail
cd "$(dirname "$0")"

./build.sh

APP=GridSnap
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Resources/Info.plist)"
DMG="dist/$APP-$VERSION.dmg"

STAGING="$(mktemp -d)"
trap 'rm -rf "$STAGING"' EXIT
cp -R "build/$APP.app" "$STAGING/"
ln -s /Applications "$STAGING/Applications"
cp "scripts/How to install.txt" "$STAGING/"

mkdir -p dist
rm -f "$DMG"
hdiutil create -volname "$APP $VERSION" -srcfolder "$STAGING" -fs HFS+ -format UDZO -ov "$DMG" >/dev/null

# The DMG is deliberately left unsigned. macOS refuses outright to open a downloaded
# DMG signed with an untrusted (self-signed) certificate, but mounts an unsigned one;
# Gatekeeper then checks the signed app inside when it's first opened.
# (Sign it again once there's a notarised Developer ID setup.)

# Unversioned copy for GitHub releases, so the "latest" download link never changes:
# https://github.com/benwellby/gridsnap/releases/latest/download/GridSnap.dmg
cp "$DMG" "dist/$APP.dmg"

echo "Packaged $DMG ($(du -h "$DMG" | cut -f1)) and dist/$APP.dmg"
