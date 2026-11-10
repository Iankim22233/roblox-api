#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="Keyboard Overlay"
BUNDLE_ID="com.local.keyboard-overlay"
BUILD_DIR="build"
APP_DIR="$BUILD_DIR/$APP_NAME.app"

rm -rf "$BUILD_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"

echo "Compiling..."
swiftc \
  -O \
  -o "$APP_DIR/Contents/MacOS/KeyboardOverlay" \
  Sources/main.swift \
  -framework AppKit \
  -framework WebKit \
  -framework IOKit

cp Info.plist "$APP_DIR/Contents/Info.plist"
cp Resources/*.html Resources/*.css Resources/*.js Resources/*.icns "$APP_DIR/Contents/Resources/"

echo "Ad-hoc signing..."
codesign --force --deep --sign - "$APP_DIR"

echo "Built: $APP_DIR"
