#!/usr/bin/env bash
# Build AgentVault as a proper .app bundle. SwiftPM only produces a Unix
# executable; macOS needs the .app wrapper so NSApplication activates as a
# foreground GUI app (menu bar, dock icon, etc.) and Info.plist/entitlements
# are picked up.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(dirname "$SCRIPT_DIR")"
CONFIG="${CONFIG:-release}"
ARCH="${ARCH:-arm64}"
SIGNING_IDENTITY="${SIGNING_IDENTITY:--}"

cd "$ROOT"

echo "==> swift build -c $CONFIG --arch $ARCH"
swift build -c "$CONFIG" --arch "$ARCH"

BIN_PATH="$(swift build -c "$CONFIG" --arch "$ARCH" --show-bin-path)"
APP_DIR="${APP_DIR:-$ROOT/build/AgentVault.app}"

echo "==> Assembling $APP_DIR"
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"

# Executable
cp "$BIN_PATH/AgentVault" "$APP_DIR/Contents/MacOS/AgentVault"
chmod +x "$APP_DIR/Contents/MacOS/AgentVault"

# Debug symbols for Sentry symbolication, from the object files the build
# left in .build. Only when DSYM_PATH is set (scripts/package-release.sh).
if [ -n "${DSYM_PATH:-}" ]; then
  rm -rf "$DSYM_PATH"
  dsymutil "$APP_DIR/Contents/MacOS/AgentVault" -o "$DSYM_PATH"
  if [ "$(dwarfdump --uuid "$APP_DIR/Contents/MacOS/AgentVault" | awk '{print $2}' | sort)" != \
       "$(dwarfdump --uuid "$DSYM_PATH" | awk '{print $2}' | sort)" ]; then
    echo "dSYM UUIDs do not match the app binary" >&2
    exit 1
  fi
fi

# Info.plist
cp "$ROOT/AppResources/Info.plist" "$APP_DIR/Contents/Info.plist"

# Crash reporting. Builds have it off unless SENTRY_DSN is set or
# CONFIGURE_SENTRY=1 reads the DSN from 1Password; either way the value is
# written into the bundle only, never printed or committed.
if [ -n "${SENTRY_DSN:-}" ] || [ "${CONFIGURE_SENTRY:-0}" = "1" ]; then
  python3 "$ROOT/scripts/configure-diagnostics.py" --plist "$APP_DIR/Contents/Info.plist"
fi

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

# Local builds use an ad-hoc signature so TCC sees a stable identity. Release
# automation can supply a Developer ID identity through SIGNING_IDENTITY.
if [ "$SIGNING_IDENTITY" = "-" ]; then
  echo "==> Ad-hoc signing $APP_DIR"
  codesign \
    --force \
    --sign - \
    --entitlements "$ROOT/AppResources/AgentVault.entitlements" \
    --options runtime \
    --timestamp=none \
    "$APP_DIR"
else
  echo "==> Developer ID signing $APP_DIR"
  codesign \
    --force \
    --sign "$SIGNING_IDENTITY" \
    --entitlements "$ROOT/AppResources/AgentVault.entitlements" \
    --options runtime \
    --timestamp \
    "$APP_DIR"
fi

codesign --verify --deep --strict --verbose=2 "$APP_DIR"

echo "==> Done: $APP_DIR"
