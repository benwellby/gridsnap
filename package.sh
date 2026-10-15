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

# Sign the DMG with the same certificate as the app, if available.
IDENTITY="$(security find-identity -p codesigning 2>/dev/null | awk -F'"' '/GridSnap Developer/ {print $2; exit}')"
if [ -n "$IDENTITY" ]; then
    codesign --force --sign "$IDENTITY" "$DMG"
fi

# Unversioned copy for GitHub releases, so the "latest" download link never changes:
# https://github.com/benwellby/gridsnap/releases/latest/download/GridSnap.dmg
cp "$DMG" "dist/$APP.dmg"

echo "Packaged $DMG ($(du -h "$DMG" | cut -f1)) and dist/$APP.dmg"
