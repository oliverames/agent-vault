<p align="center">
  <img src="https://img.shields.io/badge/macOS-26+-f5a542?style=for-the-badge&logo=apple&logoColor=white" alt="macOS 26+" height="36">
</p>

<h1 align="center">Agent Vault</h1>

<p align="center">
  <strong>Every skill, MCP, plugin, and instruction file across Claude Code, Codex, and Antigravity — in one native macOS inventory.</strong>
</p>

<p align="center">
  <code>10 categories</code> &bull;
  <code>Coverage matrix</code> &bull;
  <code>SwiftUI · macOS 26</code> &bull;
  <code>~25k files in 2.6s</code>
</p>

<p align="center">
  <a href="LICENSE">
    <img src="https://img.shields.io/badge/license-MIT-f5a542?style=flat-square" alt="License">
  </a>
  <a href="https://github.com/oliverames/agent-vault">
    <img src="https://img.shields.io/badge/swift-6.0-f5a542?style=flat-square&logo=swift&logoColor=white" alt="Swift 6">
  </a>
  <a href="https://github.com/oliverames/agent-vault">
    <img src="https://img.shields.io/badge/Liquid_Glass-ready-f5a542?style=flat-square" alt="Liquid Glass ready">
  </a>
  <a href="https://www.buymeacoffee.com/oliverames">
    <img src="https://img.shields.io/badge/Buy_Me_a_Coffee-support-f5a542?style=flat-square&logo=buy-me-a-coffee&logoColor=white" alt="Buy Me a Coffee">
  </a>
</p>

---

Agent Vault is a native macOS app that scans the directories Claude Code, Codex, and Antigravity actually use, then puts every artifact you have — skills, MCP servers, plugins, marketplaces, config files, project `CLAUDE.md` / `AGENTS.md` / `WORKLOG.md` files, `.remember` buffers, and auto-memory stores — into one searchable inventory. Click any item to see rendered Markdown, parsed provenance (author, version, source marketplace), and the runtimes that have it installed.

It is inspired by Glaze's [Skill Vault](https://www.glaze.app/app/skill-vault-vDXO9z), but expanded from one category to ten and built natively in SwiftUI with adaptive Liquid Glass styling.

## Beta status

`1.0.0-beta.1` is the first GitHub beta. It is designed for local, personal use on macOS 26 while the editing and cross-runtime management surfaces harden. The coverage matrix is intentionally read-only: it shows where skills, plugins, and MCP servers are present across scanned runtimes, but it does not mutate runtime configs yet.

## Why this exists

If you use more than one AI runtime, your tooling is scattered across at least a dozen places: skills in `~/.claude/plugins/marketplaces/`, MCP servers in `~/.claude/settings.json`, Codex skills in `~/.codex/skills/`, project rules in `iCloud/Developer/Projects/*/CLAUDE.md`, session buffers in every `.remember/` directory, auto-memory in `~/.claude/projects/<slug>/memory/`. Listing everything you've installed, authored, or written for these tools requires a `find` command that takes most people an hour to get right.

Agent Vault knows where each runtime keeps its stuff. It distinguishes the files you *authored* (your marketplaces, your skills) from the ones you *installed* (third-party marketplaces, bundled runtime skills). It detects which runtimes a given marketplace is registered into. It reads SKILL.md frontmatter and `plugin.json` manifests so the inventory carries the author, version, and source repository — not just file paths.

If you publish your own marketplaces and install them across runtimes, Agent Vault gives you the "publishing dashboard" view that the runtimes themselves don't ship.

The Coverage view adds a dashboard-style matrix for skills, plugins, and MCP servers. It groups scanned artifacts by capability and marks whether Agent Vault found each one under Claude Code, Codex, Antigravity, or another project/source root.

## What it surfaces

| Category | What gets matched | Sources |
|---|---|---|
| **Skills** | `SKILL.md` files (with parsed YAML frontmatter for author, version, etc.) | User project plugin dirs, Codex bundled skills, optionally installed marketplaces |
| **MCPs** | One artifact per server entry parsed out of `settings.json` (Claude) and `config.toml` (Codex) | `~/.claude/settings.json`, `~/.codex/config.toml`, `~/Library/Application Support/Claude/claude_desktop_config.json` |
| **Marketplaces** | `marketplace.json` files, with installed-into detection | User repos + opt-in installed clones |
| **Plugins** | `plugin.json` files | User repos + opt-in installed clones |
| **Config Files** | `settings.json`, `settings.local.json`, `config.toml`, `argv.json`, `claude_desktop_config.json` | Each runtime's home + project-local `.claude/` dirs |
| **CLAUDE.md / AGENTS.md / WORKLOG.md** | Every instance under scanned roots | Global, project-scoped, iCloud-resident |
| **.remember** | Every `.remember/` directory (with file listing for the contents) | Anywhere |
| **Memory** | Claude per-project memory dirs + Codex memories | `~/.claude/projects/*/memory/`, `~/.codex/memories/` |

## Quick start

```sh
# Requires Xcode 26+ and macOS 26+
./scripts/build-app.sh
open build/AgentVault.app
```

First launch will scan your canonical AI directories (typically 20k–60k files in 2–5 seconds). If any iCloud or Documents path can't be read, Agent Vault shows a non-blocking banner that deep-links to System Settings → Privacy → Full Disk Access. Grant it once and the cascade goes away — Agent Vault is ad-hoc signed with a stable code identity so TCC remembers.

## Design decisions

**SwiftPM, not Xcode project.** There is no `.xcodeproj`. `Package.swift` declares the executable and dependencies; `scripts/build-app.sh` wraps the SwiftPM binary in a `.app` bundle and ad-hoc signs it. This avoids 500+ lines of hand-written `project.pbxproj` and keeps the dependency story clean.

**macOS 26 deployment target.** Lets us use Liquid Glass APIs (`glassEffect`, `GlassEffectContainer`, `.glass` / `.glassProminent` button styles) unguarded. The sidebar's translucency, the toolbar glass, and the "Authored by you" provenance chip are all native system materials — no custom blur or scrims.

**Tiered scanning.** Canonical roots scan-on-launch with a parent-aware pruner that skips noisy subtrees (`plugins/cache`, `plugins/marketplaces`, `.codex/.tmp`, `.github/`, dated backup trees). The "Include caches & marketplaces" toggle adds those back as separate roots without double-counting. A naive recursive walk surfaced 2,275 items; the tiered approach drops that to 293 (87% noise reduction).

**`@Observable` store, actor scanner.** UI state is a `@MainActor @Observable VaultStore`. File I/O happens in `actor Scanner` off the main thread. Mtime-based conflict detection in `FileBuffer` guards the in-app editor against silent overwrites from concurrent Claude sessions writing the same file (auto-memory `/dream`, `.remember` hook, etc.).

**Editing is guarded by mtime conflict detection.** The Beta 1 editor uses an AppKit `NSTextView` bridge instead of SwiftUI's basic `TextEditor`, giving markdown/source files native undo, find-panel support, monospaced editing, and spell checking for Markdown. Full MarkEdit/CodeMirror vendoring is still planned, but this keeps the first beta offline and reliable.

**Provenance is parsed, not guessed.** Each skill artifact carries metadata extracted from its SKILL.md YAML frontmatter and its enclosing plugin's `plugin.json`. The detail view shows author, version, marketplace, plugin, and a clickable link to the source repository when known. For marketplaces, `installedInto` is computed by probing `~/.claude/plugins/marketplaces/<name>/` (Claude) and `~/.codex/plugins/cache/<name>/` (Codex — different layout!).

## Configuration

Scan roots are stored as defaults in [`Sources/AgentVault/Models/ScanRoot.swift`](Sources/AgentVault/Models/ScanRoot.swift) and split into canonical vs opt-in. The `isCustom` heuristic lives in [`Sources/AgentVault/Models/IsCustomHeuristic.swift`](Sources/AgentVault/Models/IsCustomHeuristic.swift) and is explicit about authoring roots vs install roots, with a UserDefaults-backed per-artifact override.

| Setting | Default | How to change |
|---|---|---|
| Canonical scan roots | 7 locations | Edit `ScanRoot.defaults()` |
| Opt-in scan roots (caches, marketplaces) | off | Toggle "Include caches & marketplaces" in sidebar |
| Pruned subtrees | parent-child rules | Edit `Scanner.prunedParentChildPairs` |
| Custom-override per artifact | none | Will be exposed via right-click in a later version |

## Layout

```
agent-vault/
├── Package.swift                     SwiftPM manifest, swift-markdown-ui dep
├── AppResources/                     Info.plist + entitlements (outside SwiftPM target)
├── scripts/build-app.sh              Builds release, assembles .app, ad-hoc signs
└── Sources/AgentVault/
    ├── Models/                       Artifact, Category, Source, ScanRoot, IsCustomHeuristic
    ├── Scanning/                     Scanner actor, ArtifactClassifier, McpExtractor, MetadataExtractor
    ├── Stores/                       VaultStore (@MainActor @Observable), FileBuffer (mtime-safe)
    └── Views/                        Sidebar, List, Matrix, Detail previews, Editor, Settings
```

See [`CLAUDE.md`](CLAUDE.md) for the full architecture notes and [`WORKLOG.md`](WORKLOG.md) for build history.

## Building

```sh
swift build -c debug              # quick compile check
./scripts/build-app.sh            # full release build → build/AgentVault.app
./scripts/package-release.sh       # build + zip dist/AgentVault-<version>.zip
```

The `.app` is ad-hoc signed against the entitlements in `AppResources/AgentVault.entitlements`. TCC grants survive rebuilds because the code-identity hash is stable.

## Roadmap

- **MarkEdit-based markdown editor** — vendor [MarkEdit](https://github.com/MarkEdit-app/MarkEdit) (MIT) for syntax-highlighted, theme-aware Markdown editing once the Beta 1 AppKit editor proves the workflow.
- **Sync preferences across runtimes** — copy MCP entries and marketplace registrations between Claude Code and Codex.
- **Marketplace dedupe** — collapse dual-host marketplaces (`claude-plugin/marketplace.json` + `codex/marketplace.json`) into one row with multi-host badges.
- **In-app scan-root editor** — `NSOpenPanel`-based "Add a custom scan root" flow in Settings.
- **Writable coverage matrix** — turn the read-only matrix into a config-safe sync surface after the scanner can prove source/override precedence.

---

<p align="center">
  <a href="https://www.buymeacoffee.com/oliverames">
    <img src="https://img.shields.io/badge/Buy_Me_a_Coffee-support-f5a542?style=for-the-badge&logo=buy-me-a-coffee&logoColor=white" alt="Buy Me a Coffee">
  </a>
</p>

<p align="center">
  <sub>
    Built by <a href="https://ames.consulting">Oliver Ames</a> in Vermont
    &bull; <a href="https://github.com/oliverames">GitHub</a>
    &bull; <a href="https://linkedin.com/in/oliverames">LinkedIn</a>
    &bull; <a href="https://bsky.app/profile/oliverames.bsky.social">Bluesky</a>
  </sub>
</p>
