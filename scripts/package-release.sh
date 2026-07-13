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
NOTARIZE="${NOTARIZE:-0}"
SIGNING_IDENTITY="${SIGNING_IDENTITY:--}"

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

case "$NOTARIZE" in
  1|true|TRUE|yes|YES)
    if [ "$SIGNING_IDENTITY" = "-" ]; then
      echo "NOTARIZE requires a Developer ID SIGNING_IDENTITY" >&2
      exit 2
    fi

    notary_args=()
    if [ -n "${NOTARY_KEYCHAIN_PROFILE:-}" ]; then
      notary_args+=(--keychain-profile "$NOTARY_KEYCHAIN_PROFILE")
    elif [ -n "${NOTARY_KEY_PATH:-}" ] && [ -n "${NOTARY_KEY_ID:-}" ] && [ -n "${NOTARY_ISSUER_ID:-}" ]; then
      if [ ! -f "$NOTARY_KEY_PATH" ]; then
        echo "NOTARY_KEY_PATH does not exist: $NOTARY_KEY_PATH" >&2
        exit 2
      fi
      notary_args+=(
        --key "$NOTARY_KEY_PATH"
        --key-id "$NOTARY_KEY_ID"
        --issuer "$NOTARY_ISSUER_ID"
      )
    else
      echo "NOTARIZE requires NOTARY_KEYCHAIN_PROFILE or App Store Connect API key variables" >&2
      exit 2
    fi

    echo "==> Submitting Agent Vault to Apple notarization"
    xcrun notarytool submit "$ZIP_PATH" --wait "${notary_args[@]}"
    xcrun stapler staple "$STAGE_DIR/AgentVault.app"
    xcrun stapler validate "$STAGE_DIR/AgentVault.app"
    codesign --verify --deep --strict --verbose=2 "$STAGE_DIR/AgentVault.app"
    spctl --assess --type execute --verbose=2 "$STAGE_DIR/AgentVault.app"

    rm -f "$ZIP_PATH"
    ditto -c -k --keepParent --norsrc "$STAGE_DIR/AgentVault.app" "$ZIP_PATH"
    ;;
  0|false|FALSE|no|NO)
    ;;
  *)
    echo "NOTARIZE must be 0 or 1" >&2
    exit 2
    ;;
esac

(
  cd "$DIST_DIR"
  shasum -a 256 "$(basename "$ZIP_PATH")" > "$(basename "$CHECKSUM_PATH")"
)

"$ROOT/scripts/verify-release.sh" "$ZIP_PATH"

echo "$ZIP_PATH"
echo "$CHECKSUM_PATH"
