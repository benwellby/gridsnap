#!/bin/bash
# Builds GridSnap.app into ./build
set -euo pipefail
cd "$(dirname "$0")"

APP=GridSnap

# Build for Apple silicon and Intel, then merge into one universal binary.
BINS=()
for ARCH in arm64 x86_64; do
    TRIPLE="$ARCH-apple-macosx15.0"
    swift build -c release --triple "$TRIPLE"
    BINS+=("$(swift build -c release --triple "$TRIPLE" --show-bin-path)/$APP")
done

BUNDLE="build/$APP.app"
rm -rf "$BUNDLE"
mkdir -p "$BUNDLE/Contents/MacOS" "$BUNDLE/Contents/Resources"
lipo -create "${BINS[@]}" -output "$BUNDLE/Contents/MacOS/$APP"
cp Resources/Info.plist "$BUNDLE/Contents/Info.plist"
cp Resources/AppIcon.icns "$BUNDLE/Contents/Resources/AppIcon.icns"

# macOS ties the Accessibility grant to the app's signing certificate. Ad-hoc
# signatures change every build, so the grant is lost on each rebuild. Prefer a
# stable certificate: a self-signed "GridSnap Developer" one (see README), or an
# Apple Development / Developer ID identity.
IDENTITY="$(security find-identity -p codesigning 2>/dev/null | awk -F'"' '/GridSnap Developer/ {print $2; exit}')"
if [ -z "$IDENTITY" ]; then
    IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null | awk -F'"' '/Apple Development|Developer ID Application/ {print $2; exit}')"
fi
if [ -n "$IDENTITY" ]; then
    codesign --force --sign "$IDENTITY" "$BUNDLE"
else
    echo "warning: no signing certificate found; signing ad-hoc (Accessibility must be re-granted after every build)" >&2
    codesign --force --sign - "$BUNDLE"
fi

echo "Built $BUNDLE (signed with: ${IDENTITY:-ad-hoc})"
