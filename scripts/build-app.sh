#!/usr/bin/env bash
# Build AgentVault as a proper .app bundle. SwiftPM only produces a Unix
# executable; macOS needs the .app wrapper so NSApplication activates as a
# foreground GUI app (menu bar, dock icon, etc.) and Info.plist/entitlements
# are picked up.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(dirname "$SCRIPT_DIR")"
CONFIG="${CONFIG:-release}"

cd "$ROOT"

echo "==> swift build -c $CONFIG"
swift build -c "$CONFIG" --arch arm64

BIN_PATH="$(swift build -c "$CONFIG" --arch arm64 --show-bin-path)"
APP_DIR="${APP_DIR:-$ROOT/build/AgentVault.app}"

echo "==> Assembling $APP_DIR"
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"

# Executable
cp "$BIN_PATH/AgentVault" "$APP_DIR/Contents/MacOS/AgentVault"
chmod +x "$APP_DIR/Contents/MacOS/AgentVault"

# Info.plist
cp "$ROOT/AppResources/Info.plist" "$APP_DIR/Contents/Info.plist"

# App icon
if [ -f "$ROOT/AppResources/AppIcon.icns" ]; then
  cp "$ROOT/AppResources/AppIcon.icns" "$APP_DIR/Contents/Resources/AppIcon.icns"
fi

# Resource bundles SwiftPM produces (e.g., MarkdownUI assets, our own resources)
for bundle in "$BIN_PATH"/*.bundle; do
  if [ -e "$bundle" ]; then
    cp -R "$bundle" "$APP_DIR/Contents/Resources/"
  fi
done

# iCloud and Finder can add extended attributes that strict code signing
# rejects inside app bundles. Strip them before signing.
xattr -cr "$APP_DIR" >/dev/null 2>&1 || true

# Ad-hoc sign so Gatekeeper / TCC has a stable code identity for this build
codesign --force --sign - --entitlements "$ROOT/AppResources/AgentVault.entitlements" --options runtime "$APP_DIR" >/dev/null 2>&1 || \
  codesign --force --sign - "$APP_DIR" >/dev/null 2>&1 || true

echo "==> Done: $APP_DIR"
