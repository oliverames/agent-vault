# CLAUDE.md — Agent Vault

Native macOS app that scans Claude Code, Codex, and Antigravity directories and surfaces every skill, MCP, plugin, marketplace, config file, CLAUDE.md, AGENTS.md, WORKLOG.md, .remember buffer, and memory store in one searchable inventory.

## Tech stack

- **Swift 6** with strict concurrency, `@Observable`, `@MainActor`
- **SwiftUI** with Liquid Glass APIs (`glassEffect`, `GlassEffectContainer`, `.glass` / `.glassProminent` button styles)
- **Deployment target: macOS 26** (Tahoe) — set in `Package.swift` as `.macOS("26.0")`. Don't lower this without availability-gating every Liquid Glass call.
- **SwiftPM-only** — there is no `.xcodeproj`. The `.app` bundle is assembled by `scripts/build-app.sh` which wraps the SwiftPM executable.
- Sole external dependency: `swift-markdown-ui` (gonzalezreal) for rendering `.md` files.

## Building & running

```sh
./scripts/build-app.sh        # builds release, assembles .app, ad-hoc signs
open build/AgentVault.app
```

The build script:
1. Runs `swift build -c release --arch arm64`
2. Copies the executable into `build/AgentVault.app/Contents/MacOS/`
3. Copies `AppResources/Info.plist` to `Contents/Info.plist`
4. Copies any SwiftPM resource bundles into `Contents/Resources/`
5. Ad-hoc signs with the entitlements file (`AppResources/AgentVault.entitlements`)

**Important**: Ad-hoc signing matters because TCC keys grants on code-identity hash. Without it, every rebuild looks like a "new app" and re-prompts for Full Disk Access.

## Layout

```
Sources/AgentVault/
├── AgentVaultApp.swift          // @main entry, Scene composition
├── ContentView.swift            // NavigationSplitView root
├── Models/
│   ├── Artifact.swift           // The core record + ArtifactMetadata
│   ├── ArtifactCategory.swift   // 10 categories (skill, mcp, marketplace, ...)
│   ├── ArtifactSource.swift     // claudeCode / codex / antigravity / other
│   ├── ScanRoot.swift           // Configurable scan locations
│   └── IsCustomHeuristic.swift  // User-authored vs installed detection
├── Scanning/
│   ├── Scanner.swift            // actor Scanner; walks roots, applies prunes
│   ├── ArtifactClassifier.swift // URL → Artifact mapping per category
│   ├── MetadataExtractor.swift  // Parses YAML frontmatter, plugin.json, marketplace.json
│   └── McpExtractor.swift       // Pulls MCP entries from settings.json + config.toml
├── Stores/
│   ├── VaultStore.swift         // @MainActor @Observable — UI state + scan results
│   └── FileBuffer.swift         // Editor backing model with mtime conflict detection
└── Views/
    ├── Sidebar/SidebarView.swift
    ├── List/ArtifactListView.swift, ArtifactRowView.swift
    ├── Detail/
    │   ├── ArtifactDetailView.swift  // Title + provenance strip + content + footer
    │   ├── MarkdownPreview.swift     // swift-markdown-ui renderer
    │   ├── PlainTextPreview.swift    // JSON/TOML/etc. as monospaced text
    │   ├── DirectoryPreview.swift    // HSplitView for .remember/ and memory/
    │   ├── EditorView.swift          // In-app editor sheet
    │   └── SourceEditorView.swift    // AppKit-backed source editor
    ├── Matrix/CapabilityMatrixView.swift // Read-only cross-runtime coverage matrix
    ├── PermissionBanner.swift    // TCC-denial deep-link banner
    └── SettingsView.swift        // ⌘, — scan roots, About
```

## Conventions

### Scanning

- **Canonical roots scan-by-default**: `~/.claude`, `~/.codex`, `~/.antigravity`, iCloud `Developer/Projects`, `~/Documents`, etc.
- **Opt-in roots**: `~/.claude/plugins/cache`, `~/.claude/plugins/marketplaces`, `~/.codex/plugins/cache` — added when "Include caches & marketplaces" is on.
- **Parent-child prunes** in `Scanner.prunedParentChildPairs` skip noisy subtrees (`plugins/cache`, `plugins/marketplaces`, `.codex/.tmp`, etc.) when walking a parent canonical root, without affecting the opt-in flow.
- **Backup-tree prunes**: `Scanner.backupPathSubstrings` skips `*/.codex-backups/`, `*/.bak/`, `*/work-backups/`, etc. wholesale.
- **Classifier rules** in `ArtifactClassifier.classify(...)` match by filename (`SKILL.md`, `CLAUDE.md`, `marketplace.json`, etc.) or directory name (`.remember`, project `memory/` dirs). Adding a category means editing one place.

### Provenance

- `Artifact.metadata` carries author / version / marketplace / plugin / repoURL / isBundled / installedInto.
- `MetadataExtractor.skillMetadata` reads only the first 4 KB of a SKILL.md and parses the YAML frontmatter block (`---` ... `---`). The parser is bespoke, not a full YAML implementation — it handles top-level `key: value` lines with optional quotes. Nested keys are ignored.
- `MetadataExtractor.detectInstalledInto` checks `~/.claude/plugins/marketplaces/<name>` (Claude) and `~/.codex/plugins/cache/<name>` (Codex) — different layouts!
- `MetadataExtractor.isBundled` matches paths under `/.local/share/claude/versions/`, `/.local/share/codex/`, `/.codex/skills/`, `/.codex/vendor_imports/`, `/Library/Application Support/Claude/Claude Extensions/`.

### UI

- **Sidebar selection uses Buttons, not `List(selection:)`**. Earlier experiments showed `List(selection:)` is fragile when sections mix Buttons, tagged rows, and Toggles — the Button approach is straightforward and works.
- **Liquid Glass is mostly automatic** — `NavigationSplitView` and toolbars inherit glass if you don't paint custom backgrounds on them. The `build-macos-apps-codex:liquid-glass` skill is the canonical reference; consult it before adding custom blur or scrims.
- **Provenance strip** is collapsible: only renders if `hasProvenance(artifact)` returns true (some artifact has at least one metadata field).
- **Marketplace category is grouped** into "Your Marketplaces" vs "Installed Marketplaces" via `marketplaceGroupedList(items:)`. Other categories use `flatList` or `groupedList` depending on whether a category filter is active.

### Editor

- `FileBuffer` captures mtime at load. `save()` re-checks mtime before writing; if the file was touched externally (e.g. by a live Claude session running `/dream`), returns `.conflict(diskMtime:)` and the UI prompts Reload-or-Overwrite. Never silently overwrite — this is a load-bearing safety guarantee.
- Beta 1 uses `SourceEditorView`, an AppKit `NSTextView` bridge, instead of SwiftUI `TextEditor`. It keeps editing offline and reliable while preserving native undo, find-panel support, Markdown spell checking, and `FileBuffer` conflict protection.
- Future editor work: vendor MarkEdit-style CodeMirror-in-WKWebView for syntax-highlighted markdown editing. MarkEdit is MIT, so safe to integrate with attribution. See `WORKLOG.md`.

### Coverage matrix

- `CapabilityMatrixView` is read-only by design. It groups skills, plugins, and MCP servers by capability and marks which scanned source roots contain each capability.
- Do not add runtime config toggles to the matrix until source/override precedence is explicitly modeled and tested.

## Gotchas

- **Info.plist forbidden as SwiftPM resource**: when SwiftPM sees `Info.plist` in `resources:` it errors out. We moved it to `AppResources/` outside the target's resource scanning. Don't move it back to `Sources/AgentVault/Resources/`.
- **`@Bindable` is scope-local**: declaring `@Bindable var bindable = store` inside `body` makes `$bindable` available only in that scope, not in computed properties like `scanTab`. Re-declare per-scope.
- **`.tint` and `.orange` don't unify** in a ternary `foregroundStyle(...)` — `.tint` is `TintShapeStyle`, `.orange` is `Color`. Use `Color.accentColor` and `Color.orange` explicitly, or wrap with `AnyShapeStyle(...)`.
- **TCC prompts cascade on first run** unless the user has Full Disk Access. The `PermissionBanner` deep-links to the right pane. `~/.claude`, `~/.codex`, `~/.antigravity` typically don't trigger TCC; `~/Library/Mobile Documents` (iCloud), `~/Documents`, and `~/Desktop` do.

## Testing manually

After any change to scanning or classification:
1. Build: `./scripts/build-app.sh`
2. Run: `open build/AgentVault.app`
3. Verify counts in the sidebar match the inventory generated at `~/Desktop/ai-instruction-inventory.md`
4. If counts deviate, run a `find` audit with the same prune rules (see WORKLOG.md for the script structure)

For UI work, use the peekaboo MCP tools to take screenshots and click elements rather than relying on description. The `screenshot` tool from XcodeBuildMCP is simulator-only — use `peekaboo image --app-target "PID:<pid>"` for native macOS windows.
