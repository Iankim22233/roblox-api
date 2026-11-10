#!/bin/bash
# Installs the built app into /Applications, replacing any existing copy,
# and clears the quarantine flag so Finder-launch behaves the same as a
# direct Terminal launch (no App Translocation, no stale TCC identity).
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="Keyboard Overlay"
SRC="build/$APP_NAME.app"
DEST="/Applications/$APP_NAME.app"

if [ ! -d "$SRC" ]; then
  echo "Run ./build.sh first — $SRC not found." >&2
  exit 1
fi

echo "Quitting any running copy..."
killall KeyboardOverlay 2>/dev/null || true

echo "Removing old install at $DEST (if any)..."
rm -rf "$DEST"

echo "Installing to $DEST..."
cp -R "$SRC" "$DEST"

echo "Clearing quarantine/extended attributes..."
xattr -cr "$DEST"

echo "Done. Launch it from /Applications."
