# Privacy

Agent Vault works with files that are private by default. This document explains what it reads, what it stores, and what each export operation writes.

## Data the app reads

Agent Vault recursively enumerates enabled scan roots and reads supported files to classify them, extract metadata, show previews, and find MCP server entries. Depending on your setup, those files can contain:

- API keys, tokens, environment references, and server credentials;
- personal instructions and project rules;
- memory derived from earlier conversations;
- local usernames, project names, and absolute paths;
- plugin and marketplace provenance.

The default roots are listed in `Sources/AgentVault/Models/ScanRoot.swift`. Installed plugin caches and marketplaces are opt-in. You can add more roots in Settings.

## Data that leaves the Mac

Agent Vault does not upload inventory data, file contents, usage data, or crash reports. Markdown previews use bundle-only image providers, so a remote image embedded in a private file is not fetched. Clicking a repository or Markdown link can open that URL in your default browser, which is outside Agent Vault.

The app depends on `swift-markdown-ui` at build time. SwiftPM may contact GitHub when resolving that dependency, but the built app does not use the dependency to make network requests.

## Local persistence

The current inventory stays in memory. Agent Vault stores custom scan root paths and per-artifact authored or installed overrides in `UserDefaults`. It does not cache file contents or the full inventory between launches.

Editing writes only after you choose Edit and Save. The editor checks the file's modification time before saving and warns if another process changed it.

## Exports and backups

Clean Export creates a readable copy and applies best-effort redaction to UTF-8 text files up to 5 MB. It redacts common secret-bearing keys such as API keys, passwords, authorization values, and tokens, plus several recognizable token formats. The redactor does not identify every possible credential, personal name, private path, or sensitive passage. Review the output before sharing it.

Memory Export, Memory Reconcile, and Backup preserve source content. These outputs can contain secrets and personal information. Keep them in a protected location and do not publish them without a separate review.

Restore uses original absolute paths from an Agent Vault backup manifest. Only restore backups you created and trust.

## Full Disk Access

Agent Vault is not sandboxed because it scans configuration across several runtimes and user-selected project roots. macOS may require Full Disk Access for Documents, Desktop, and iCloud Drive. Granting it expands what the app can read, so install only a build you trust and keep the app updated.

You can remove access at any time in System Settings, Privacy & Security, Full Disk Access. Roots that remain inaccessible are reported in the app instead of aborting the scan.
