#!/bin/bash
set -e

CONFIG="${1:-release}"
VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" Info.plist)
DMG_NAME="APIBypass-${VERSION}.dmg"
STAGING="dmg_staging"

echo "==> Building $CONFIG..."
./build-app.sh "$CONFIG"

if [[ -x ./verify-release.sh ]]; then
    echo "==> Verifying app bundle..."
    ./verify-release.sh APIBypass.app
fi

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

if [[ -x ./verify-release.sh ]]; then
    echo "==> Verifying DMG contents..."
    MOUNT_OUTPUT=$(hdiutil attach "$DMG_NAME" -nobrowse -readonly)
    MOUNT_POINT=$(printf '%s\n' "$MOUNT_OUTPUT" | grep '/Volumes/' | sed 's#.*\(/Volumes/.*\)#\1#' | tail -n 1)
    ./verify-release.sh "$MOUNT_POINT/APIBypass.app"
    hdiutil detach "$MOUNT_POINT"
fi

echo "==> Cleaning up..."
rm -rf "$STAGING"

echo "==> Done: $DMG_NAME"
