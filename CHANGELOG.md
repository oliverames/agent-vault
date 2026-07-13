# Changelog

Agent Vault follows semantic versioning while it is in beta. Dates use the `YYYY-MM-DD` format.

## 1.0.0-beta.3, 2026-07-13

- Added CI on GitHub's macOS 26 arm64 runner.
- Added Developer ID signing and notarization automation with external credentials.
- Added release archive verification for bundle metadata, architecture, checksums, symbolic links, and code signatures.
- Added best-effort secret redaction to Clean Export.
- Rejected backup entries whose stored paths leave the selected backup directory or pass through a symbolic link.
- Added scanner, export symlink, restore path, and secret redaction tests.
- Added in-app warnings that distinguish redacted Clean Export from unredacted backups and memory exports.
- Documented privacy, security reporting, the threat model, contribution checks, and release operations.
- Updated the public README to describe Nous Research Hermes Agent support, Apple silicon requirements, and current safety boundaries.

## 1.0.0-beta.2, 2026-05-22

- Added persistent custom scan roots and inventory sorting.
- Expanded search to paths and provenance metadata.
- Added plugin-local MCP manifest support.
- Connected Coverage selections to the detail pane.
- Improved scan progress publishing for slower File Provider roots.

## 1.0.0-beta.1, 2026-05-21

- Added the read-only Coverage view.
- Added the native AppKit-backed source editor with modification-time conflict protection.
- Added release packaging and the project-local build and run action.

## 0.1.0, 2026-05-21

- Added the first native inventory for skills, MCP servers, plugins, marketplaces, runtime configuration, project instructions, work logs, remember buffers, and memory stores.
