# Security policy

## Supported versions

Agent Vault is still in beta. Security fixes are applied to the latest beta on the `main` branch.

## Report a vulnerability

Please use [GitHub's private vulnerability reporting form](https://github.com/oliverames/agent-vault/security/advisories/new). If that form is unavailable, open an issue with no vulnerability details and ask for a private reporting channel. Do not publish a vulnerability that could expose local files, credentials, or unsafe restore behavior.

Include the affected version, macOS version, reproduction steps, and the smallest synthetic fixture that demonstrates the problem. Do not send real tokens, private memory files, or other people's data.

## Scope

Reports are especially useful when they involve:

- reading files outside a selected or documented scan root;
- following a symbolic link into an unrelated location;
- exposing secrets through Clean Export;
- escaping the selected backup directory during restore;
- overwriting a changed file without warning;
- unexpected network transmission or telemetry;
- signature, notarization, or release archive integrity.

Agent Vault's best-effort redactor cannot guarantee that every secret format will be recognized. A missed pattern is still worth reporting, but users must review Clean Export output before sharing it. Restore backups and memory exports intentionally preserve original content and are expected to contain sensitive information.
