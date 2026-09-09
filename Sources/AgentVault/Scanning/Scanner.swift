import Foundation

/// Result of one scan pass.
struct ScanResult: Sendable {
    var artifacts: [Artifact]
    /// Roots that returned an access-denied error. The UI surfaces these
    /// behind a "Grant Full Disk Access" banner.
    var deniedRoots: [URL]
    /// Total files visited (for progress UI).
    var visitedCount: Int
    /// How long the scan took.
    var duration: TimeInterval
}

/// Background scanner. One actor instance per app; UI calls `scan(roots:)`
/// and awaits the result. The scanner never touches `@MainActor` state.
actor Scanner {
    private let classifier: ArtifactClassifier
    /// Directory names skipped wholesale regardless of context. `.github`
    /// is pruned because VS Code / Antigravity extensions ship GitHub
    /// Actions workflow metadata under `.github/skills/` which collides
    /// with our SKILL.md classifier but isn't user-facing.
    private let prunedDirectoryNames: Set<String> = [
        ".git",
        ".github",
        "node_modules",
        ".venv",
        "venv",
        ".build",
        "DerivedData",
        ".next",
        "dist",
        "build",
        ".Trash",
    ]
    /// Parent/child name pairs that, when seen mid-walk, cause the child to
    /// be pruned. Used to skip the plugin-cache and plugin-marketplace
    /// subtrees while still walking the rest of `~/.claude`, `~/.codex`, etc.
    /// These mirror the non-canonical `ScanRoot`s so opting in via the
    /// "showCached" toggle adds them back as separate scan passes without
    /// double-counting.
    private let prunedParentChildPairs: [(parent: String, child: String)] = [
        ("plugins", "marketplaces"),
        ("plugins", "cache"),
        ("plugins", ".marketplace-plugin-source-staging"),
        (".codex", ".tmp"),
        (".claude", "scheduled-tasks"),
        (".claude", "shell-snapshots"),
        (".claude", "todos"),
        (".claude", "statsig"),
        (".hermes", "cache"),
        (".hermes", "image_cache"),
        (".hermes", "logs"),
        (".hermes", "sessions"),
        (".hermes", "sandboxes"),
        (".hermes", "hermes-agent"),
    ]
    /// Path substrings that mean "this is a backup or staging copy".
    /// Anything matching is skipped wholesale.
    private let backupPathSubstrings: [String] = [
        "/.codex-backups/",
        "/.bak/",
        "/work-backups/",
        "/file-backups/",
        "/archived_sessions/",
        "/local-agent-mode-sessions/",
        "/Documents/Codex/2026-",        // dated codex backup trees
        "/Brew Backups/",
    ]

    init(classifier: ArtifactClassifier) {
        self.classifier = classifier
    }

    /// Scan every root, accumulating artifacts. Roots that can't be opened
    /// because of TCC denial are recorded in `deniedRoots` rather than
    /// thrown. Other errors are silently skipped so one bad subtree doesn't
    /// abort the whole pass.
    ///
    /// - Parameter forceWalk: paths that should be walked even if they match
    ///   `prunedParentChildPairs`. When the user toggles "include caches" we
    ///   pass the cache roots in via `roots` AND list them here so the
    ///   pruner doesn't bail on them. Comparing by `standardizedFileURL`
    ///   handles iCloud `Mobile Documents` symlinks correctly.
    func scan(roots: [ScanRoot], forceWalk: [URL] = [], excludedRoots: [URL] = []) async -> ScanResult {
        let start = Date()
        var artifacts: [Artifact] = []
        var denied: [URL] = []
        var visited = 0
        let forced = Set(forceWalk.map { $0.standardizedFileURL.path(percentEncoded: false) })

        // Exclude paused subtrees even when an enabled ancestor overlaps them.
        let excluded = Set((excludedRoots + roots.filter { !$0.isEnabled }.map(\.url))
            .map { $0.standardizedFileURL.path(percentEncoded: false) })

        for root in roots where root.isEnabled && !isExcluded(root.url, paths: excluded) {
            let (rootArtifacts, isDenied, count) = scanRoot(root, forceWalkPaths: forced, excludedPaths: excluded)
            artifacts.append(contentsOf: rootArtifacts)
            visited += count
            if isDenied { denied.append(root.url) }
        }

        return ScanResult(
            artifacts: dedupe(artifacts),
            deniedRoots: denied,
            visitedCount: visited,
            duration: Date().timeIntervalSince(start)
        )
    }

    private func isExcluded(_ url: URL, paths: Set<String>) -> Bool {
        let path = url.standardizedFileURL.path(percentEncoded: false)
        return paths.contains { path == $0 || path.hasPrefix($0.hasSuffix("/") ? $0 : $0 + "/") }
    }

    /// Walk a single root. Returns `(artifacts, isDenied, visitedCount)`.
    private func scanRoot(_ root: ScanRoot, forceWalkPaths: Set<String>, excludedPaths: Set<String>) -> ([Artifact], Bool, Int) {
        let fm = FileManager.default
        let path = root.url.path(percentEncoded: false)

        guard fm.fileExists(atPath: path) else {
            return ([], false, 0)
        }

        // Avoid a full directory listing as the access probe. File Provider
        // backed roots can block there before the scan publishes any results.
        guard fm.isReadableFile(atPath: path) else {
            return ([], true, 0)
        }

        let keys: [URLResourceKey] = [
            .isDirectoryKey,
            .contentModificationDateKey,
            .fileSizeKey,
            .nameKey,
            .isSymbolicLinkKey,
        ]

        guard let enumerator = fm.enumerator(
            at: root.url,
            includingPropertiesForKeys: keys,
            options: [],   // include hidden dirs (.remember, .claude, .codex, ...)
            errorHandler: { _, _ in true }
        ) else {
            return ([], false, 0)
        }

        var artifacts: [Artifact] = []
        var count = 0

        while let item = enumerator.nextObject() as? URL {
            if isExcluded(item, paths: excludedPaths) {
                enumerator.skipDescendants()
                continue
            }
            count += 1

            // Pull resource values in one shot.
            guard let values = try? item.resourceValues(forKeys: Set(keys)) else { continue }
            let isDirectory = values.isDirectory ?? false
            let name = values.name ?? item.lastPathComponent

            // Prune noisy / unwanted subtrees before classifying.
            if isDirectory && prunedDirectoryNames.contains(name) {
                enumerator.skipDescendants()
                continue
            }

            // Skip anything inside a known backup/staging tree.
            let itemPath = item.path(percentEncoded: false)
            if backupPathSubstrings.contains(where: { itemPath.contains($0) }) {
                if isDirectory { enumerator.skipDescendants() }
                continue
            }

            // Parent-aware prune: skip plugin caches & marketplaces when
            // they're descended into from a parent walk (e.g. ~/.claude),
            // unless the user explicitly listed them in forceWalkPaths.
            if isDirectory {
                let parentName = item.deletingLastPathComponent().lastPathComponent
                if prunedParentChildPairs.contains(where: { $0.parent == parentName && $0.child == name }) {
                    let standardizedPath = item.standardizedFileURL.path(percentEncoded: false)
                    if !forceWalkPaths.contains(standardizedPath) {
                        enumerator.skipDescendants()
                        continue
                    }
                }
            }

            // Skip symlinks to avoid double-counting (e.g. ~/CLAUDE.md →
            // ~/.claude/CLAUDE.md). The symlink target will be discovered
            // when we walk the actual location.
            if values.isSymbolicLink == true { continue }

            let modifiedAt = values.contentModificationDate ?? .distantPast
            let sizeBytes = Int64(values.fileSize ?? 0)

            if let artifact = classifier.classify(
                url: item,
                isDirectory: isDirectory,
                modifiedAt: modifiedAt,
                sizeBytes: sizeBytes
            ) {
                artifacts.append(artifact)

                // If we matched a directory-backed artifact (.remember or
                // memory), we don't need to enumerate its contents — the
                // detail view loads children on demand.
                if isDirectory {
                    enumerator.skipDescendants()
                }
            }
        }

        return (artifacts, false, count)
    }

    /// Merge overlapping paths and dual-host manifests in the same marketplace root.
    /// Names alone never identify a marketplace across separate repositories.
    private func dedupe(_ artifacts: [Artifact]) -> [Artifact] {
        var grouped: [String: Artifact] = [:]
        var order: [String] = []
        let marketplaces = artifacts.filter { $0.category == .marketplace }
        let references = RuntimeAttribution.localReferences(in: marketplaces)
        for original in artifacts {
            let key = original.category == .marketplace
                ? RuntimeAttribution.marketplaceIdentity(for: original)
                : original.url.resolvingSymlinksInPath().standardizedFileURL.path
            let linked = RuntimeAttribution.linkedSources(for: original, references: references)
            let artifact = Artifact(
                id: key, url: original.url, category: original.category,
                source: original.source, sources: linked.isEmpty ? original.sources : linked,
                isCustom: original.isCustom, title: original.title, subtitle: original.subtitle,
                modifiedAt: original.modifiedAt, sizeBytes: original.sizeBytes,
                tags: original.tags, metadata: original.metadata
            )
            guard let previous = grouped[key] else {
                grouped[key] = artifact
                order.append(key)
                continue
            }
            let sources = ArtifactSource.allCases.filter {
                $0 != .other && (previous.sources.contains($0) || artifact.sources.contains($0))
            }
            var metadata = previous.metadata
            metadata.installedInto = ArtifactSource.allCases.filter {
                previous.metadata.installedInto.contains($0) || artifact.metadata.installedInto.contains($0)
            }
            grouped[key] = Artifact(
                id: previous.id, url: previous.url, category: previous.category,
                source: previous.source, sources: sources.isEmpty ? [.other] : sources,
                isCustom: previous.isCustom, title: previous.title, subtitle: previous.subtitle,
                modifiedAt: max(previous.modifiedAt, artifact.modifiedAt), sizeBytes: previous.sizeBytes,
                tags: previous.tags, metadata: metadata
            )
        }
        return order.compactMap { grouped[$0] }
    }
}
