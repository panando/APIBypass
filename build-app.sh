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

echo "==> Done: $APP_DIR"
