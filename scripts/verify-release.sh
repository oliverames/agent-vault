#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -ne 1 ]; then
  echo "usage: $0 <AgentVault-version.zip>" >&2
  exit 2
fi

ZIP_PATH="$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"
STAGE_DIR="$(mktemp -d "${TMPDIR:-/tmp}/agent-vault-verify.XXXXXX")"

cleanup() {
  rm -rf "$STAGE_DIR"
}
trap cleanup EXIT

if [ ! -f "$ZIP_PATH" ]; then
  echo "Release archive not found: $ZIP_PATH" >&2
  exit 2
fi

if [ -f "$ZIP_PATH.sha256" ]; then
  (
    cd "$(dirname "$ZIP_PATH")"
    shasum -a 256 -c "$(basename "$ZIP_PATH").sha256"
  )
fi

ditto -x -k "$ZIP_PATH" "$STAGE_DIR"
APP_DIR="$STAGE_DIR/AgentVault.app"
INFO_PLIST="$APP_DIR/Contents/Info.plist"
APP_BINARY="$APP_DIR/Contents/MacOS/AgentVault"

if [ ! -d "$APP_DIR" ] || [ ! -x "$APP_BINARY" ]; then
  echo "Archive does not contain an executable AgentVault.app" >&2
  exit 1
fi

if find "$APP_DIR" -type l -print -quit | grep -q .; then
  echo "Release bundle contains a symbolic link" >&2
  exit 1
fi

plutil -lint "$INFO_PLIST"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$INFO_PLIST")"
MINIMUM_OS="$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "$INFO_PLIST")"

if [ -z "$VERSION" ] || [ "$MINIMUM_OS" != "26.0" ]; then
  echo "Unexpected release metadata: version=$VERSION minimumOS=$MINIMUM_OS" >&2
  exit 1
fi

if ! file "$APP_BINARY" | grep -q 'arm64'; then
  echo "AgentVault binary is not arm64" >&2
  exit 1
fi

codesign --verify --deep --strict --verbose=2 "$APP_DIR"

if [ "${REQUIRE_DISTRIBUTION_SIGNATURE:-0}" = "1" ]; then
  signature_details="$(codesign -dvv "$APP_DIR" 2>&1)"
  case "$signature_details" in
    *"Authority=Developer ID Application:"*)
      ;;
    *)
      echo "Release is not signed with a Developer ID Application identity" >&2
      exit 1
      ;;
  esac
fi

if [ "${REQUIRE_NOTARIZED:-0}" = "1" ]; then
  xcrun stapler validate "$APP_DIR"
  spctl --assess --type execute --verbose=2 "$APP_DIR"
fi

echo "Verified AgentVault $VERSION ($MINIMUM_OS minimum)"
