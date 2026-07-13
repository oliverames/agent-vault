# Releasing

Public Agent Vault archives must be signed with a Developer ID Application certificate, notarized by Apple, stapled, and verified before upload. Local ad-hoc packages are useful for CI, but they are not public releases.

## Version preparation

1. Update `CFBundleShortVersionString` and `CFBundleVersion` in `AppResources/Info.plist`.
2. Add the release and date to `CHANGELOG.md`.
3. Run the full local verification sequence.
4. Commit and push the release preparation.

```sh
bash -n scripts/*.sh script/*.sh
swift test
./scripts/package-release.sh
./scripts/verify-release.sh dist/AgentVault-*.zip
```

## Local signed package

The signing identity must already exist in the login keychain. Notarization can use a `notarytool` keychain profile:

```sh
SIGNING_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
NOTARY_KEYCHAIN_PROFILE="agent-vault-notary" \
NOTARIZE=1 \
./scripts/package-release.sh

REQUIRE_DISTRIBUTION_SIGNATURE=1 \
REQUIRE_NOTARIZED=1 \
./scripts/verify-release.sh dist/AgentVault-*.zip
```

The package script also accepts `NOTARY_KEY_PATH`, `NOTARY_KEY_ID`, and `NOTARY_ISSUER_ID` for an App Store Connect API key. Keep the `.p8` file outside the repository.

## GitHub Actions credentials

The Signed release workflow expects these repository secrets:

- `MACOS_CERTIFICATE_BASE64`: base64-encoded Developer ID Application `.p12`
- `MACOS_CERTIFICATE_PASSWORD`: password for that `.p12`
- `MACOS_SIGNING_IDENTITY`: full certificate identity
- `NOTARY_API_KEY_BASE64`: base64-encoded App Store Connect `.p8`
- `NOTARY_KEY_ID`: App Store Connect API key ID
- `NOTARY_ISSUER_ID`: App Store Connect API issuer ID

The workflow imports the certificate into a temporary keychain and writes the API key under `$RUNNER_TEMP`. GitHub destroys the runner after the job.

## Publish

Create and push an annotated tag that exactly matches the app version:

```sh
git tag -a v1.0.0-beta.3 -m "Agent Vault 1.0.0-beta.3"
git push origin v1.0.0-beta.3
```

The workflow rejects a tag that does not match `CFBundleShortVersionString`. For a tag build, it publishes the notarized zip and SHA-256 checksum as a GitHub release. A manual workflow run builds the same signed artifact without publishing a release.

## Final checks

Download the GitHub release archive on a Mac that does not have the development certificate. Confirm that Gatekeeper opens the app without a warning, the first scan completes, inaccessible roots appear in the permission banner, and the About view reports the expected version.
