#!/bin/bash
set -e

CONFIG="${1:-release}"
VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" Info.plist)
DMG_NAME="APIBypass-${VERSION}.dmg"
STAGING="dmg_staging"

echo "==> Building $CONFIG..."
./build-app.sh "$CONFIG"

echo "==> Preparing DMG staging..."
rm -rf "$STAGING"
mkdir "$STAGING"
cp -R APIBypass.app "$STAGING/"

# Create Applications symlink for drag-to-install
ln -s /Applications "$STAGING/Applications"

echo "==> Creating $DMG_NAME..."
rm -f "$DMG_NAME"
hdiutil create -volname "APIBypass $VERSION" \
    -srcfolder "$STAGING" \
    -ov \
    -format UDZO \
    "$DMG_NAME"

echo "==> Cleaning up..."
rm -rf "$STAGING"

echo "==> Done: $DMG_NAME"
