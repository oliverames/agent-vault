#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(dirname "$SCRIPT_DIR")"
INFO_PLIST="$ROOT/AppResources/Info.plist"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$INFO_PLIST")"
DIST_DIR="$ROOT/dist"
ZIP_PATH="$DIST_DIR/AgentVault-$VERSION.zip"
CHECKSUM_PATH="$ZIP_PATH.sha256"
STAGE_DIR="$(mktemp -d "${TMPDIR:-/tmp}/agent-vault-release.XXXXXX")"

cleanup() {
  rm -rf "$STAGE_DIR"
}
trap cleanup EXIT

cd "$ROOT"

APP_DIR="$STAGE_DIR/AgentVault.app" "$ROOT/scripts/build-app.sh"

rm -rf "$DIST_DIR"
mkdir -p "$DIST_DIR"

codesign --verify --deep --strict "$STAGE_DIR/AgentVault.app"
ditto -c -k --keepParent --norsrc "$STAGE_DIR/AgentVault.app" "$ZIP_PATH"
(
  cd "$DIST_DIR"
  shasum -a 256 "$(basename "$ZIP_PATH")" > "$(basename "$CHECKSUM_PATH")"
)

echo "$ZIP_PATH"
echo "$CHECKSUM_PATH"
