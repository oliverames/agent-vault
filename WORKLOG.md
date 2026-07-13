# Agent Vault — Worklog

## 2026-07-13 - beta 3 release status

**Current state**: The repository is public and `v1.0.0-beta.3` is published as a signed and notarized prerelease. The release contains the app archive and its checksum. GitHub now has all six signing and notarization secrets required by the release workflow, so the missing-secret gate recorded earlier today is closed.

**What remains**: Beta distribution is ready. Before publishing a stable `1.0.0`, decide whether the beta has had enough real-world use, close any release-blocking feedback, and publish a non-prerelease tag with final release notes. There is no remaining signing or repository-visibility blocker.

---

## 2026-07-13 - beta 3 release hardening

**What changed**: Prepared `1.0.0-beta.3` with macOS 26 CI, externally supplied Developer ID signing and notarization automation, independent archive verification, and public privacy, security, contribution, threat-model, and release documentation. Clean Export now applies best-effort secret redaction, while restore rejects stored paths that leave the selected backup or pass through a symbolic link.

**Verification**: Added scanner, export symlink, secret redaction, and restore path tests. The full Swift Testing suite passes with 25 tests across seven suites. Both ad-hoc and local Developer ID archives passed checksum, bundle metadata, arm64 architecture, symlink, and code-signature verification.

**Release boundary**: The repository remains private. A notarized GitHub release still requires the documented repository secrets; no release secrets are currently configured.

## 2026-06-04 - Hermes, export, restore, and release UI pass

**What changed**: Added Hermes-aware inventory coverage for skills, MCPs, plugin manifests, config files, and memory directories. Added the Operations surface for clean human-readable exports, manifest-backed backups, restore flows, memory export, and non-destructive memory reconcile drafts. Polished the release UI so Coverage uses a two-column split with an aligned scrollable matrix, Operations buttons have clearer labels and affordance, and Settings/About copy names Hermes.

**Decisions made**: Clean export remains separate from backup/restore: clean export writes readable folders plus README-style context, while backup/restore preserves original paths through a manifest. Memory reconcile writes a draft rather than mutating memory files automatically.

**Left off at**: `main` is pushed through `5a91ced` with a clean working tree. Verification passed with `swift test`, `./script/build_and_run.sh --verify`, and a live Computer Use pass over Inventory, Hermes source counts, Operations, Coverage search/layout, and Settings/About.

**Open questions**: None for the shipped release pass. Future work can still revisit writable coverage/config sync once source precedence is modeled.

---

## 2026-05-22 — 1.0.0-beta.2 release pass

- Raised app metadata to `1.0.0-beta.2` / build `102`.
- Added persistent custom scan roots in Settings with an `NSOpenPanel` add flow and removable user-added roots.
- Added inventory sort controls for recently modified, name, source, and size.
- Made search and sidebar counts include paths and provenance metadata, so filtering by marketplace, plugin, author, or repo URL behaves as expected.
- Fixed virtual MCP artifacts to use unique IDs per server entry instead of reusing the parent config file path.
- Added `.mcp.json` / `mcp.json` classification and MCP extraction for plugin-local manifests, including `servers` and `mcpServers` JSON shapes.
- Changed Coverage into a three-column flow so selecting a matrix row opens the artifact in the detail pane.
- Added row context-menu actions and app menu commands for reveal/copy path on the selected artifact.
- Reworked the sidebar footer and filter placement so the status panel does not cover controls at the default window size.
- Changed scan publishing to update after each root and removed the blocking root directory-list probe, so a slow File Provider location no longer leaves the inventory blank.
- Added Swift Testing coverage for plugin-local MCP manifests and MCP JSON classification.

## 2026-05-21 — 1.0.0-beta.1 release pass

- Raised the app metadata to `1.0.0-beta.1` / build `101`.
- Added a read-only Coverage view inspired by the agent/capability matrix concept: skills, plugins, and MCP servers are grouped by capability and shown across Claude Code, Codex, Antigravity, and Other sources.
- Replaced the editor sheet's SwiftUI `TextEditor` with a MarkEdit-inspired AppKit `NSTextView` bridge for reliable offline markdown/source editing, native undo, find-panel support, and mtime conflict protection.
- Added Swift Testing coverage for MCP extraction, skill classification, and `FileBuffer` conflict handling.
- Added a release packaging script that builds the app, zips `AgentVault.app`, and writes a SHA-256 checksum.
- Added a Codex Run action via `script/build_and_run.sh` and `.codex/environments/environment.toml`.

### Beta 1 scope decision

Full MarkEdit vendoring remains a follow-up. The screenshot-style matrix is included only as a read-only dashboard in Beta 1 because mutating runtime config across Claude Code, Codex, and other agents needs a stronger precedence model than the scanner currently has.

## 2026-05-21 — v0.1.0 ships

Built Agent Vault from scratch as a native macOS SwiftUI app that scans Claude Code, Codex, and Antigravity directories and surfaces every skill, MCP, plugin, marketplace, config file, instruction file, work log, remember buffer, and memory store in one unified inventory. Inspired by Glaze's Skill Vault but expanded from 1 category to 10.

### Architecture decisions

- **SwiftPM, not Xcode project**: `Package.swift` + `scripts/build-app.sh` wrapping the SwiftPM executable in a `.app` bundle. Avoids 500+ lines of hand-written `project.pbxproj` boilerplate while keeping dependency management (swift-markdown-ui) trivial.
- **macOS 26 target**: lets us use Liquid Glass APIs (`.glass`, `.glassProminent`, `GlassEffectContainer`) without availability gating.
- **Unsandboxed + ad-hoc signed**: needed for full disk access to `~/.claude`, `~/.codex`, iCloud Developer/, etc. Ad-hoc signing gives a stable code identity so TCC grants persist across rebuilds.
- **Actor-based scanner**: `actor Scanner` does the file walk off the main thread; `@MainActor @Observable VaultStore` holds UI state. Mtime-based conflict detection in `FileBuffer` guards against silent overwrites from concurrent Claude sessions (auto-memory consolidation, .remember hook, /dream).
- **Tiered scanning**: canonical roots scanned by default; plugin caches and marketplaces are opt-in via the "Include caches & marketplaces" toggle. A parent-child prune (`plugins/cache`, `plugins/marketplaces`, `.codex/.tmp`) keeps the walk from over-counting.

### Categories surfaced (10)

Skills · MCPs · Marketplaces · Plugins · Config Files · CLAUDE.md · AGENTS.md · WORKLOG.md · .remember · Memory

### Numbers (Oliver's machine)

- 25,454 files visited in 2.6 s
- 293 canonical artifacts surfaced
- 138 → 118 skills after pruning `.github/` and marketplace-source-staging
- Initial naive walk: 2,275 artifacts (pre-prune) → 293 with parent-child rules (87% noise reduction)

### Provenance metadata

Each artifact carries:
- **author** (from SKILL.md frontmatter or `plugin.json`)
- **version** (e.g. humanizer v2.5.2)
- **marketplace** (e.g. `ames-plugins`)
- **plugin** (e.g. `ames-community-skills`)
- **repoURL** (clickable link to GitHub when known)
- **isBundled** (Codex's `~/.codex/skills/`, Claude binary distribution, Claude Extensions all detected)
- **installedInto** (`Claude Code`, `Codex`, derived by checking `~/.claude/plugins/marketplaces/<name>` and `~/.codex/plugins/cache/<name>`)

### UI choices

- 3-pane NavigationSplitView (Liquid Glass sidebar auto-applies)
- Sidebar uses **Button-based selection** instead of `List(selection:)` — much more reliable when sections mix Buttons (Sources), tagged rows (Categories), and Toggles (Filters)
- Marketplaces category gets a special "Your Marketplaces" / "Installed Marketplaces" split based on `isCustom`
- Detail view has a provenance strip below the title with chips for author / version / marketplace / plugin / installed-into / repo link
- Permission banner deep-links to System Settings → Privacy → Full Disk Access if any scan root returns access-denied
- In-app editor (`EditorView`) uses mtime conflict detection — refuses to overwrite if the file changed under us, surfaces a Reload/Overwrite alert instead

### Known follow-ups

#### MarkEdit-based editor (substantial — own session)

MarkEdit (MIT licensed) is the canonical native macOS CodeMirror 6 host. Repo: https://github.com/MarkEdit-app/MarkEdit. Audit:

- **499 files total** (232 Swift, 170 TS/JS, plus assets)
- Modules: `CoreEditor` (CodeMirror bridge, 195 files mostly TS), `MarkEditCore` (Swift wrapper, 19 files), `MarkEditKit` (shared logic, 45 files), `MarkEditMac` (app shell, 202 files — not needed)
- No Swift Package distribution yet — would need to fork and extract `CoreEditor` + `MarkEditCore` + minimal `MarkEditKit` glue
- TypeScript files compile via their `MarkEditTools/` build pipeline (esbuild) to a single bundled JS file loaded into a WKWebView

**Phased integration plan**:

1. **Phase 1 (minimal viable)** — write our own ~150-line WKWebView host that loads vanilla CodeMirror 6 from a local resource bundle. No syntax extensions, no theming bridge. Tells us whether the WKWebView round-trip is acceptable UX. Scope: 1 session.
2. **Phase 2 (vendored MarkEdit core)** — fork MarkEdit, extract `CoreEditor` + `MarkEditCore`, vendor their TS bundle. Replace the Phase 1 stub. Get full markdown syntax highlighting, find-in-page, etc. Scope: 1–2 sessions.
3. **Phase 3 (upstream contribution)** — if it works well, propose a clean Swift Package split of `MarkEditCore` back to upstream so others can depend on it. Future.

Don't attempt all three in one session — Phase 1 first to validate the bridge approach, Phase 2 only if the result feels right.

#### Other items

- **Sync preferences from X → Y** (e.g. copy MCPs from Claude config to Codex config). Future session.
- **Marketplace dedupe**: `ames-plugins` shows as 2 entries because the project has separate `claude-plugin/marketplace.json` and `codex/marketplace.json` (dual-host pattern). Could merge into one row with multi-host badges.
- **Symlink-aware source attribution**: items under `~/Developer/Projects/ames-plugins/` are currently labeled `Other` source — could intelligently tag them `Claude Code + Codex` since the dual-host pattern targets both.
- **Per-root enable toggles** for custom roots.
- Writable coverage matrix once config precedence is tested.
