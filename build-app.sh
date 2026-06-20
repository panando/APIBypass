#!/bin/bash
set -e

CONFIG="${1:-release}"
BUILD_DIR=".build/arm64-apple-macosx/$CONFIG"
APP_DIR="APIBypass.app"

echo "==> Building $CONFIG..."
swift build -c "$CONFIG"

echo "==> Creating .app bundle..."
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"

cp "$BUILD_DIR/APIBypass" "$APP_DIR/Contents/MacOS/"
cp "Info.plist" "$APP_DIR/Contents/"
cp "icon.icns" "$APP_DIR/Contents/Resources/AppIcon.icns"

EXECUTABLE="$APP_DIR/Contents/MacOS/APIBypass"
FRAMEWORKS_DIR="$APP_DIR/Contents/Frameworks"
XCODE_SWIFT_RPATH=$(otool -l "$EXECUTABLE" | awk '/path \/Applications\/Xcode\.app\/Contents\/Developer\/Toolchains\/XcodeDefault\.xctoolchain\/usr\/lib\/swift-[^ ]*\/macosx/ { print $2; exit }')

if [[ -n "$XCODE_SWIFT_RPATH" ]]; then
    mkdir -p "$FRAMEWORKS_DIR"
    if [[ -f "$XCODE_SWIFT_RPATH/libswiftCompatibilitySpan.dylib" ]]; then
        cp "$XCODE_SWIFT_RPATH/libswiftCompatibilitySpan.dylib" "$FRAMEWORKS_DIR/"
        install_name_tool -add_rpath "@executable_path/../Frameworks" "$EXECUTABLE"
    fi
    install_name_tool -delete_rpath "$XCODE_SWIFT_RPATH" "$EXECUTABLE"
fi

codesign --force --deep --sign - "$APP_DIR"

echo "==> Done: $APP_DIR"
