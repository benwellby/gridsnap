#!/bin/bash
# Publishes a GitHub release for the version in Resources/Info.plist.
# Usage: ./release.sh ["Release notes"]
#
# Bump CFBundleShortVersionString (and CFBundleVersion) first and commit.
set -euo pipefail
cd "$(dirname "$0")"

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Resources/Info.plist)"
TAG="v$VERSION"
NOTES="${1:-GridSnap $VERSION}"

if [ -n "$(git status --porcelain)" ]; then
    echo "error: commit your changes before releasing" >&2
    exit 1
fi
if gh release view "$TAG" >/dev/null 2>&1; then
    echo "error: release $TAG already exists; bump the version in Resources/Info.plist" >&2
    exit 1
fi

./package.sh

# Tag the current commit if it isn't tagged yet, then push.
if ! git rev-parse "$TAG" >/dev/null 2>&1; then
    git tag -a "$TAG" -m "GridSnap $VERSION"
fi
git push origin HEAD "$TAG"

# GridSnap.dmg keeps the "latest" download link stable; the versioned copy is for reference.
gh release create "$TAG" dist/GridSnap.dmg "dist/GridSnap-$VERSION.dmg" \
    --title "GridSnap $VERSION" --notes "$NOTES" --latest

echo "Released $TAG: https://github.com/benwellby/gridsnap/releases/tag/$TAG"
