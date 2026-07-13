# Contributing

Agent Vault is a SwiftPM macOS app that targets macOS 26. Small, focused pull requests are easiest to review.

## Before changing code

Open an issue for changes that alter scan scope, export behavior, restore behavior, or runtime configuration. These areas can expose private files or overwrite user data, so the safety boundary should be clear before implementation starts.

Do not include real configuration files, tokens, memory content, absolute home paths, or screenshots containing personal data in tests or pull requests. Use synthetic fixtures.

## Local setup

You need an Apple silicon Mac with macOS 26 and Xcode 26 or later.

```sh
git clone https://github.com/oliverames/agent-vault.git
cd agent-vault
swift test
./scripts/build-app.sh
```

## Verification

Run the checks that match your change. Before opening a pull request, run the full set:

```sh
bash -n scripts/*.sh script/*.sh
swift test
./scripts/package-release.sh
./scripts/verify-release.sh dist/AgentVault-*.zip
```

Changes to scanning, exports, or restore should include a synthetic regression test. Changes to UI should include a clear manual test description and should use native SwiftUI behavior unless a custom treatment is necessary.

## Code style

- Keep filesystem rules in the scanner or export service instead of scattering path checks through views.
- Preserve Swift 6 strict concurrency.
- Keep the coverage matrix read-only until source precedence is modeled and tested.
- Never silently overwrite a file that may have changed outside the app.
- Do not add analytics, telemetry, or network access without discussing the privacy change first.

## Pull requests

Describe the behavior change, the risk boundary, and the verification you ran. If the change affects files on disk, state what gets read or written and how conflicts are handled.
