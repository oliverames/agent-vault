<p align="center">
  <img src="https://img.shields.io/badge/macOS-26%2B-f5a542?style=for-the-badge&logo=apple&logoColor=white" alt="macOS 26+" height="36">
</p>

<h1 align="center">Agent Vault</h1>

<p align="center">
  A native macOS inventory for four local agent environments: Claude Code, Codex, Antigravity, and Nous Research's Hermes Agent.
</p>

<p align="center">
  <a href="https://github.com/oliverames/agent-vault/actions/workflows/ci.yml"><img src="https://github.com/oliverames/agent-vault/actions/workflows/ci.yml/badge.svg" alt="CI"></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-f5a542?style=flat-square" alt="MIT License"></a>
  <img src="https://img.shields.io/badge/Swift-6-f5a542?style=flat-square&logo=swift&logoColor=white" alt="Swift 6">
  <img src="https://img.shields.io/badge/Apple_silicon-arm64-f5a542?style=flat-square" alt="Apple silicon">
</p>

Agent Vault scans the directories these tools actually use and puts the results in one searchable window. It recognizes skills, MCP configuration, plugin and marketplace manifests, runtime settings, instruction files, work logs, `.remember` buffers, and memory stores. The Coverage view groups related capabilities across runtimes, while Operations can create readable exports or restore backups.

Version `1.0.0-beta.3` is intended for personal testing on macOS 26. The coverage matrix remains read-only until Agent Vault can model runtime precedence safely.

## Privacy comes first

Agent Vault reads files that may contain API keys, tokens, personal instructions, or conversation-derived memory. The app does not send scan results, file contents, or analytics anywhere. Inventory data stays in memory unless you choose an export or backup operation.

Clean Export applies best-effort redaction to common secret fields and token formats. You still need to review an export before sharing it. Restore backups and memory exports preserve original content and may contain secrets. Read [Privacy](docs/PRIVACY.md) and the [threat model](docs/THREAT_MODEL.md) before granting Full Disk Access or sharing an export.

## What it finds

| Category | Examples |
| --- | --- |
| Skills | `SKILL.md` files and their frontmatter |
| MCP servers | Entries from JSON, TOML, and supported YAML configuration |
| Plugins and marketplaces | `plugin.json`, supported Hermes manifests, and `marketplace.json` |
| Runtime configuration | Claude Code, Codex, Antigravity, Hermes Agent, and desktop config files |
| Project instructions | `CLAUDE.md`, `AGENTS.md`, and `WORKLOG.md` |
| Session and memory data | `.remember` directories plus Claude, Codex, and Hermes memory stores |

Settings includes a persisted switch for each scan root. Turn a root off to skip it and its subdirectories without removing its configuration. Re-enable it to resume scanning. Cache roots still require the separate cache opt-in. Existing roots remain enabled when upgrading.

Agent Vault parses provenance from skill frontmatter and plugin manifests, including author, version, marketplace, plugin, repository, and installed runtime when available. It distinguishes canonical authoring roots from installed caches and skips common build, backup, and staging trees.

## Requirements

- Apple silicon Mac
- macOS 26 or later
- Xcode 26 or later when building from source

Agent Vault is not sandboxed because its job is to inspect configuration across several locations. Full Disk Access is optional, but macOS may require it for Documents, Desktop, and iCloud Drive. The app displays a permission banner when a selected root cannot be read.

## Build and run

```sh
git clone https://github.com/oliverames/agent-vault.git
cd agent-vault
swift test
./scripts/build-app.sh
open build/AgentVault.app
```

The local build is ad-hoc signed so macOS can retain its TCC identity between rebuilds. The project also includes a Codex Run action:

```sh
./script/build_and_run.sh --verify
```

## Release packaging

```sh
./scripts/package-release.sh
./scripts/verify-release.sh dist/AgentVault-1.0.0-beta.3.zip
```

That path creates an ad-hoc signed archive for local verification. Public downloads should use the Developer ID and notarization workflow documented in [Releasing](docs/RELEASING.md). Signing certificates and notarization keys are supplied by the local keychain or GitHub Actions secrets; they are never stored in this repository.

## Safety boundaries

- The scanner skips symbolic links instead of following them into other trees.
- Clean exports redact common credential assignments and recognizable token formats.
- Restore reads stored files only from inside the selected backup directory.
- Restore Missing leaves existing files alone. Restore & Overwrite requires confirmation.
- The editor checks modification time before saving and warns when another process changed the file.
- Agent Vault does not change runtime configuration from the Coverage view.

See [Security](SECURITY.md) for reporting instructions and [Contributing](CONTRIBUTING.md) for the local verification checklist.

## Project layout

```text
Sources/AgentVault/     SwiftUI app, scanner, stores, and file operations
Tests/AgentVaultTests/  Swift Testing suites
AppResources/           Info.plist, entitlements, and app icon
scripts/                Build, package, and release verification
.github/workflows/      CI and signed release automation
```

## Roadmap

- Model source and override precedence before allowing cross-runtime configuration changes.
- Collapse duplicate dual-host marketplace entries.
- Evaluate a local CodeMirror editor without weakening conflict protection.

Agent Vault is available under the [MIT License](LICENSE). It was built by [Oliver Ames](https://ames.consulting).
