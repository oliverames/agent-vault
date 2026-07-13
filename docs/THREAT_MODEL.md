# Threat model

## Protected assets

Agent Vault is designed to protect the original configuration, instruction, and memory files that it inventories. Those files may contain credentials, private writing, local paths, and operational details. Export archives and backup manifests are sensitive assets too.

## Trust boundaries

The app crosses three important boundaries:

1. It reads across multiple runtime homes and user-selected project roots.
2. It can write exports or backups to a destination the user selects.
3. It can restore files to original absolute paths recorded in a backup manifest.

Agent Vault trusts the local macOS user and the app binary. It does not treat arbitrary files inside a scan root or an imported backup as trusted instructions.

## Threats and mitigations

### Unexpected filesystem traversal

A symbolic link or crafted backup path could point outside the expected tree. The scanner and readable export walker skip symbolic links. Restore rejects stored paths that are absolute, contain `..`, leave the selected backup directory, or pass through a symbolic link.

Restore still honors the original absolute destination recorded by a valid backup because that is the feature's purpose. Restore & Overwrite removes an existing destination after explicit confirmation. Users should restore only backups they created and trust.

### Secret duplication

Configuration files often contain credentials. Clean Export applies best-effort redaction to common secret assignments and recognizable token formats. Tests cover JSON, TOML, YAML-style assignments, bearer tokens, GitHub tokens, npm tokens, and OpenAI-style keys.

Redaction is not a data-loss-prevention system. It does not parse arbitrary binary formats, non-UTF-8 text, files larger than 5 MB, novel token formats, personal names, or sensitive prose. Backups and memory operations preserve source content and do not redact it.

### Silent data loss

The editor records modification time when it opens a file and checks again before saving. If another process changed the file, Agent Vault asks the user to reload or deliberately overwrite it. Restore Missing reports conflicts instead of replacing existing destinations.

### Excessive access

The app is not sandboxed and may receive Full Disk Access. That access is needed to inventory several protected locations, but it increases the impact of a compromised build. Release builds use Developer ID signing, the hardened runtime, notarization, and stapling. Local development builds use an ad-hoc signature and should not be distributed.

### Data transmission

Inventory data and previews remain local. Markdown previews use bundle-only image providers so embedded remote images are not fetched. Repository and Markdown links open in the user's default browser only after the user clicks them. The app has no telemetry code.

### Dependency compromise

The only runtime dependency is `swift-markdown-ui`, locked through `Package.resolved`. CI builds and tests the locked dependency graph. A dependency compromise could still affect the app, so dependency changes require review.

## Out of scope and known limits

- Agent Vault does not protect data from another process already running as the same user with equivalent filesystem access.
- It does not encrypt exports or backups.
- It does not guarantee complete secret redaction.
- It does not validate the truth of metadata inside third-party manifests.
- It does not make runtime configuration changes from the Coverage view.
- A user who confirms Restore & Overwrite can replace the destinations listed in a trusted manifest.
