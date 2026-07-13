import Foundation

struct VaultOperationResult: Sendable {
    let rootURL: URL
    let itemCount: Int
    let skippedCount: Int
    let detail: String
}

struct VaultRestoreResult: Sendable {
    let rootURL: URL
    let restoredCount: Int
    let conflictCount: Int
    let skippedCount: Int
    let detail: String
}

enum VaultExportError: LocalizedError {
    case unsupportedManifestVersion(Int)
    case invalidBackupPath(String)

    var errorDescription: String? {
        switch self {
        case let .unsupportedManifestVersion(version):
            "This backup uses unsupported manifest version \(version)."
        case let .invalidBackupPath(path):
            "The backup contains an unsafe stored path: \(path)"
        }
    }
}

struct VaultExportService {
    private let fileManager: FileManager
    private let redactor = SensitiveValueRedactor()

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func exportClean(
        artifacts: [Artifact],
        to destination: URL,
        generatedAt: Date = .now
    ) throws -> VaultOperationResult {
        let root = try makeContainer(
            prefix: "Agent Vault Clean Export",
            destination: destination,
            generatedAt: generatedAt
        )

        let exportable = artifacts.filter { !isVirtualOnly($0) || fileManager.fileExists(atPath: $0.url.path(percentEncoded: false)) }
        var copied = 0
        var skipped = 0
        var rows: [String] = []

        for artifact in exportable.sorted(by: readableSort) {
            guard let sourceURL = backingSourceURL(for: artifact),
                  fileManager.fileExists(atPath: sourceURL.path(percentEncoded: false))
            else {
                skipped += 1
                continue
            }

            let folder = root
                .appending(path: folderName(for: artifact.source), directoryHint: .isDirectory)
                .appending(path: folderName(for: artifact.category), directoryHint: .isDirectory)
                .appending(path: uniqueLeaf(for: artifact, existingUnder: root), directoryHint: .isDirectory)
            try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)

            if isDirectory(sourceURL) {
                try copyDirectoryContents(
                    from: sourceURL,
                    to: folder,
                    pruningForReadableExport: true,
                    redactSensitiveValues: true
                )
            } else {
                try copyFile(
                    from: sourceURL,
                    to: folder.appending(path: sourceURL.lastPathComponent),
                    redactSensitiveValues: true
                )
            }

            copied += 1
            rows.append(markdownRow(for: artifact, exportedPath: folder.path(percentEncoded: false)))
        }

        try writeCleanReadme(
            at: root,
            generatedAt: generatedAt,
            itemCount: copied,
            skippedCount: skipped,
            rows: rows
        )

        return VaultOperationResult(
            rootURL: root,
            itemCount: copied,
            skippedCount: skipped,
            detail: "\(copied) items exported, \(skipped) skipped"
        )
    }

    func exportMemories(
        artifacts: [Artifact],
        to destination: URL,
        generatedAt: Date = .now
    ) throws -> VaultOperationResult {
        let memories = artifacts.filter { $0.category == .memoryDir }
        let root = try makeContainer(
            prefix: "Agent Vault Memory Export",
            destination: destination,
            generatedAt: generatedAt
        )

        var copied = 0
        var skipped = 0
        var rows: [String] = []

        for artifact in memories.sorted(by: readableSort) {
            guard fileManager.fileExists(atPath: artifact.url.path(percentEncoded: false)) else {
                skipped += 1
                continue
            }

            let folder = root
                .appending(path: folderName(for: artifact.source), directoryHint: .isDirectory)
                .appending(path: slug(artifact.title), directoryHint: .isDirectory)
            try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
            try copyDirectoryContents(from: artifact.url, to: folder, pruningForReadableExport: false)
            copied += 1
            rows.append(markdownRow(for: artifact, exportedPath: folder.path(percentEncoded: false)))
        }

        try writeMemoryExportReadme(
            at: root,
            generatedAt: generatedAt,
            itemCount: copied,
            skippedCount: skipped,
            rows: rows
        )

        return VaultOperationResult(
            rootURL: root,
            itemCount: copied,
            skippedCount: skipped,
            detail: "\(copied) memory stores exported, \(skipped) skipped"
        )
    }

    func reconcileMemories(
        artifacts: [Artifact],
        to destination: URL,
        generatedAt: Date = .now
    ) throws -> VaultOperationResult {
        let memories = artifacts.filter { $0.category == .memoryDir }
        let root = try makeContainer(
            prefix: "Agent Vault Memory Reconcile",
            destination: destination,
            generatedAt: generatedAt
        )
        let byAgent = root.appending(path: "By Agent", directoryHint: .isDirectory)
        try fileManager.createDirectory(at: byAgent, withIntermediateDirectories: true)

        var copied = 0
        var skipped = 0
        var mergedSections: [String] = [
            "# Merged Memory Draft",
            "",
            "Generated: \(formatDate(generatedAt))",
            "",
            "This is a non-destructive reconciliation draft. Review it before copying anything back into a live agent memory store.",
        ]
        var rows: [String] = []

        for artifact in memories.sorted(by: readableSort) {
            guard fileManager.fileExists(atPath: artifact.url.path(percentEncoded: false)) else {
                skipped += 1
                continue
            }

            let folder = byAgent
                .appending(path: folderName(for: artifact.source), directoryHint: .isDirectory)
                .appending(path: slug(artifact.title), directoryHint: .isDirectory)
            try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
            try copyDirectoryContents(from: artifact.url, to: folder, pruningForReadableExport: false)
            copied += 1
            rows.append(markdownRow(for: artifact, exportedPath: folder.path(percentEncoded: false)))
            mergedSections.append(contentsOf: mergedMemorySections(for: artifact))
        }

        try mergedSections.joined(separator: "\n").write(
            to: root.appending(path: "MERGED-MEMORY.md"),
            atomically: true,
            encoding: .utf8
        )
        try writeReconcileReadme(
            at: root,
            generatedAt: generatedAt,
            itemCount: copied,
            skippedCount: skipped,
            rows: rows
        )

        return VaultOperationResult(
            rootURL: root,
            itemCount: copied,
            skippedCount: skipped,
            detail: "\(copied) memory stores reconciled into a draft, \(skipped) skipped"
        )
    }

    func createBackup(
        artifacts: [Artifact],
        to destination: URL,
        generatedAt: Date = .now
    ) throws -> VaultOperationResult {
        let root = try makeContainer(
            prefix: "Agent Vault Backup",
            destination: destination,
            generatedAt: generatedAt
        )
        let itemsRoot = root.appending(path: "Items", directoryHint: .isDirectory)
        try fileManager.createDirectory(at: itemsRoot, withIntermediateDirectories: true)

        var entries: [VaultBackupEntry] = []
        var seen = Set<String>()
        var copied = 0
        var skipped = 0

        for artifact in artifacts.sorted(by: readableSort) {
            guard let sourceURL = backingSourceURL(for: artifact),
                  fileManager.fileExists(atPath: sourceURL.path(percentEncoded: false))
            else {
                skipped += 1
                continue
            }

            let sourcePath = sourceURL.path(percentEncoded: false)
            guard seen.insert(sourcePath).inserted else { continue }

            let leaf = "\(String(format: "%04d", copied + 1))-\(slug(artifact.title))"
            let storedURL = itemsRoot.appending(path: leaf, directoryHint: .isDirectory)
            if isDirectory(sourceURL) {
                try fileManager.copyItem(at: sourceURL, to: storedURL)
            } else {
                try fileManager.createDirectory(at: storedURL, withIntermediateDirectories: true)
                try copyFile(from: sourceURL, to: storedURL.appending(path: sourceURL.lastPathComponent))
            }

            let relativeStoredPath = "Items/\(leaf)" + (isDirectory(sourceURL) ? "" : "/\(sourceURL.lastPathComponent)")
            entries.append(VaultBackupEntry(
                artifactID: artifact.id,
                title: artifact.title,
                category: artifact.category.rawValue,
                source: artifact.source.rawValue,
                originalPath: sourcePath,
                storedPath: relativeStoredPath,
                isDirectory: isDirectory(sourceURL)
            ))
            copied += 1
        }

        let manifest = VaultBackupManifest(
            version: 1,
            generatedAt: generatedAt,
            entries: entries
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(manifest).write(to: root.appending(path: "Manifest.json"))
        try writeBackupReadme(at: root, generatedAt: generatedAt, itemCount: copied, skippedCount: skipped)

        return VaultOperationResult(
            rootURL: root,
            itemCount: copied,
            skippedCount: skipped,
            detail: "\(copied) items backed up, \(skipped) skipped"
        )
    }

    func restoreBackup(from backupURL: URL, overwriteExisting: Bool) throws -> VaultRestoreResult {
        let root = backupURL.lastPathComponent == "Manifest.json"
            ? backupURL.deletingLastPathComponent()
            : backupURL
        let manifestURL = root.appending(path: "Manifest.json")
        let data = try Data(contentsOf: manifestURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let manifest = try decoder.decode(VaultBackupManifest.self, from: data)
        guard manifest.version == 1 else {
            throw VaultExportError.unsupportedManifestVersion(manifest.version)
        }

        var restored = 0
        var conflicts = 0
        var skipped = 0

        for entry in manifest.entries {
            let storedURL = try validatedStoredURL(in: root, storedPath: entry.storedPath)
            guard entry.originalPath.hasPrefix("/") else {
                throw VaultExportError.invalidBackupPath(entry.originalPath)
            }
            let destinationURL = URL(fileURLWithPath: entry.originalPath, isDirectory: entry.isDirectory)

            guard fileManager.fileExists(atPath: storedURL.path(percentEncoded: false)) else {
                skipped += 1
                continue
            }

            let destinationPath = destinationURL.path(percentEncoded: false)
            if fileManager.fileExists(atPath: destinationPath) {
                guard overwriteExisting else {
                    conflicts += 1
                    continue
                }
                try fileManager.removeItem(at: destinationURL)
            }

            try fileManager.createDirectory(
                at: destinationURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try fileManager.copyItem(at: storedURL, to: destinationURL)
            restored += 1
        }

        return VaultRestoreResult(
            rootURL: root,
            restoredCount: restored,
            conflictCount: conflicts,
            skippedCount: skipped,
            detail: "\(restored) restored, \(conflicts) conflicts, \(skipped) skipped"
        )
    }

    // MARK: - Artifact backing

    private func backingSourceURL(for artifact: Artifact) -> URL? {
        switch artifact.category {
        case .skill, .plugin, .marketplace:
            artifact.url.deletingLastPathComponent()
        case .rememberDir, .memoryDir:
            artifact.url
        case .mcp, .configFile, .claudeMd, .agentsMd, .worklogMd:
            artifact.url
        }
    }

    private func isVirtualOnly(_ artifact: Artifact) -> Bool {
        artifact.category == .mcp && artifact.id.contains("#mcp:")
    }

    // MARK: - Readmes

    private func writeCleanReadme(
        at root: URL,
        generatedAt: Date,
        itemCount: Int,
        skippedCount: Int,
        rows: [String]
    ) throws {
        let body = """
        # Agent Vault Clean Export

        Generated: \(formatDate(generatedAt))

        This folder is not a restore backup. It is a readable, grouped copy of the selected Agent Vault artifacts so skills, marketplaces, plugins, MCP configs, instruction files, and memory stores are easy to browse outside the app.

        Agent Vault applied best-effort secret redaction to supported text files. Review the entire export before sharing it because uncommon credentials, personal paths, and sensitive prose may remain.

        ## Contents

        - Exported items: \(itemCount)
        - Skipped items: \(skippedCount)

        ## Index

        | Source | Category | Title | Original path |
        | --- | --- | --- | --- |
        \(rows.isEmpty ? "| | | No items exported | |" : rows.joined(separator: "\n"))
        """
        try body.write(to: root.appending(path: "README.md"), atomically: true, encoding: .utf8)
    }

    private func writeMemoryExportReadme(
        at root: URL,
        generatedAt: Date,
        itemCount: Int,
        skippedCount: Int,
        rows: [String]
    ) throws {
        let body = """
        # Agent Vault Memory Export

        Generated: \(formatDate(generatedAt))

        This export copies discovered memory stores by agent. It does not modify live memory files. The copied content is not redacted and may contain credentials or personal information.

        - Exported memory stores: \(itemCount)
        - Skipped memory stores: \(skippedCount)

        | Source | Category | Title | Original path |
        | --- | --- | --- | --- |
        \(rows.isEmpty ? "| | | No memory stores exported | |" : rows.joined(separator: "\n"))
        """
        try body.write(to: root.appending(path: "README.md"), atomically: true, encoding: .utf8)
    }

    private func writeReconcileReadme(
        at root: URL,
        generatedAt: Date,
        itemCount: Int,
        skippedCount: Int,
        rows: [String]
    ) throws {
        let body = """
        # Agent Vault Memory Reconcile

        Generated: \(formatDate(generatedAt))

        No live memory files were modified. Agent Vault copied each discovered memory store into `By Agent/` and wrote `MERGED-MEMORY.md` as a review draft. The copied content and merged draft are not redacted.

        ## Cleanup command status

        - Claude Code: no non-destructive cleanup command is configured in Agent Vault.
        - Codex: no non-destructive cleanup command is configured in Agent Vault.
        - Antigravity: no memory cleanup command was discovered in the scanned roots.
        - Hermes: `hermes memory status` exists; `hermes memory reset` is destructive, so Agent Vault does not run it for reconciliation.

        ## Contents

        - Memory stores included: \(itemCount)
        - Memory stores skipped: \(skippedCount)

        | Source | Category | Title | Original path |
        | --- | --- | --- | --- |
        \(rows.isEmpty ? "| | | No memory stores included | |" : rows.joined(separator: "\n"))
        """
        try body.write(to: root.appending(path: "README.md"), atomically: true, encoding: .utf8)
    }

    private func writeBackupReadme(at root: URL, generatedAt: Date, itemCount: Int, skippedCount: Int) throws {
        let body = """
        # Agent Vault Backup

        Generated: \(formatDate(generatedAt))

        This folder is a restore backup. `Manifest.json` maps every copied item back to its original path. Files are exact, unredacted copies and may contain credentials or personal information.

        - Backed up items: \(itemCount)
        - Skipped items: \(skippedCount)

        Restore behavior:

        - Restore Missing skips existing destinations and reports conflicts.
        - Restore & Overwrite replaces existing destinations after confirmation in the app.
        """
        try body.write(to: root.appending(path: "README.md"), atomically: true, encoding: .utf8)
    }

    // MARK: - Memory merge

    private func mergedMemorySections(for artifact: Artifact) -> [String] {
        let memoryFiles = memoryFileURLs(in: artifact.url)
        guard !memoryFiles.isEmpty else {
            return [
                "",
                "## \(artifact.source.rawValue): \(artifact.title)",
                "",
                "_No Markdown memory files were found in \(artifact.url.path(percentEncoded: false))._",
            ]
        }

        var sections = [
            "",
            "## \(artifact.source.rawValue): \(artifact.title)",
            "",
            "Original path: `\(artifact.url.path(percentEncoded: false))`",
        ]

        for file in memoryFiles {
            let text = (try? String(contentsOf: file, encoding: .utf8)) ?? ""
            sections.append(contentsOf: [
                "",
                "### \(file.lastPathComponent)",
                "",
                text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? "_Empty file._"
                    : text.trimmingCharacters(in: .whitespacesAndNewlines),
            ])
        }

        return sections
    }

    private func memoryFileURLs(in directory: URL) -> [URL] {
        let candidates = ["MEMORY.md", "USER.md", "memory_summary.md", "raw_memories.md"]
            .map { directory.appending(path: $0) }
            .filter { fileManager.fileExists(atPath: $0.path(percentEncoded: false)) }

        if !candidates.isEmpty {
            return candidates
        }

        guard let enumerator = fileManager.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var files: [URL] = []
        while let item = enumerator.nextObject() as? URL {
            guard item.pathExtension.lowercased() == "md",
                  (try? item.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) != true
            else { continue }
            files.append(item)
        }
        return files.sorted { $0.path(percentEncoded: false) < $1.path(percentEncoded: false) }
    }

    // MARK: - Filesystem helpers

    private func makeContainer(prefix: String, destination: URL, generatedAt: Date) throws -> URL {
        try fileManager.createDirectory(at: destination, withIntermediateDirectories: true)
        let base = destination.appending(path: "\(prefix) \(fileSafeTimestamp(generatedAt))", directoryHint: .isDirectory)
        var candidate = base
        var suffix = 2
        while fileManager.fileExists(atPath: candidate.path(percentEncoded: false)) {
            candidate = destination.appending(path: "\(base.lastPathComponent)-\(suffix)", directoryHint: .isDirectory)
            suffix += 1
        }
        try fileManager.createDirectory(at: candidate, withIntermediateDirectories: true)
        return candidate
    }

    private func copyDirectoryContents(
        from source: URL,
        to destination: URL,
        pruningForReadableExport: Bool,
        redactSensitiveValues: Bool = false
    ) throws {
        try fileManager.createDirectory(at: destination, withIntermediateDirectories: true)

        guard let enumerator = fileManager.enumerator(
            at: source,
            includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
            options: []
        ) else { return }

        while let item = enumerator.nextObject() as? URL {
            let values = try item.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            let isDirectory = values.isDirectory == true
            if values.isSymbolicLink == true { continue }

            if pruningForReadableExport, isDirectory, readableExportPrunedDirectoryNames.contains(item.lastPathComponent) {
                enumerator.skipDescendants()
                continue
            }

            let relative = relativePath(from: source, to: item)
            let target = destination.appending(path: relative)
            if isDirectory {
                try fileManager.createDirectory(at: target, withIntermediateDirectories: true)
            } else {
                try fileManager.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
                try copyFile(from: item, to: target, redactSensitiveValues: redactSensitiveValues)
            }
        }
    }

    private func copyFile(
        from source: URL,
        to destination: URL,
        redactSensitiveValues: Bool = false
    ) throws {
        if fileManager.fileExists(atPath: destination.path(percentEncoded: false)) {
            try fileManager.removeItem(at: destination)
        }
        try fileManager.copyItem(at: source, to: destination)

        guard redactSensitiveValues,
              let data = try? Data(contentsOf: destination),
              data.count <= 5_000_000,
              !data.contains(0),
              let sourceText = String(data: data, encoding: .utf8)
        else { return }

        let redactedText = redactor.redact(sourceText)
        guard redactedText != sourceText else { return }
        try Data(redactedText.utf8).write(to: destination)
    }

    private func validatedStoredURL(in root: URL, storedPath: String) throws -> URL {
        guard !storedPath.isEmpty, !storedPath.hasPrefix("/") else {
            throw VaultExportError.invalidBackupPath(storedPath)
        }

        let components = NSString(string: storedPath).pathComponents
        guard !components.contains("..") else {
            throw VaultExportError.invalidBackupPath(storedPath)
        }

        let canonicalRoot = root.standardizedFileURL
        let candidate = root.appending(path: storedPath).standardizedFileURL
        var rootPath = canonicalRoot.path(percentEncoded: false)
        while rootPath.count > 1, rootPath.hasSuffix("/") {
            rootPath.removeLast()
        }
        let candidatePath = candidate.path(percentEncoded: false)
        guard candidatePath.hasPrefix(rootPath + "/") else {
            throw VaultExportError.invalidBackupPath(storedPath)
        }

        var componentURL = canonicalRoot
        for component in components {
            componentURL.append(path: component)
            let values = try? componentURL.resourceValues(forKeys: [.isSymbolicLinkKey])
            if values?.isSymbolicLink == true {
                throw VaultExportError.invalidBackupPath(storedPath)
            }
        }

        return candidate
    }

    private func isDirectory(_ url: URL) -> Bool {
        var isDir: ObjCBool = false
        fileManager.fileExists(atPath: url.path(percentEncoded: false), isDirectory: &isDir)
        return isDir.boolValue
    }

    private func relativePath(from root: URL, to item: URL) -> String {
        let rootPath = root.path(percentEncoded: false).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let itemPath = item.path(percentEncoded: false).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard itemPath.hasPrefix(rootPath) else { return item.lastPathComponent }
        let start = itemPath.index(itemPath.startIndex, offsetBy: rootPath.count)
        return String(itemPath[start...]).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    // MARK: - Formatting

    private func readableSort(_ lhs: Artifact, _ rhs: Artifact) -> Bool {
        if lhs.source != rhs.source { return lhs.source.rawValue < rhs.source.rawValue }
        if lhs.category != rhs.category { return lhs.category.displayName < rhs.category.displayName }
        return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
    }

    private func folderName(for source: ArtifactSource) -> String {
        source.rawValue
    }

    private func folderName(for category: ArtifactCategory) -> String {
        category.displayName
    }

    private func uniqueLeaf(for artifact: Artifact, existingUnder root: URL) -> String {
        // The export container is new, so the normal case keeps the folder
        // readable. The path hash only matters when two artifacts share a title.
        let base = slug(artifact.title)
        let sibling = root
            .appending(path: folderName(for: artifact.source), directoryHint: .isDirectory)
            .appending(path: folderName(for: artifact.category), directoryHint: .isDirectory)
            .appending(path: base, directoryHint: .isDirectory)

        guard fileManager.fileExists(atPath: sibling.path(percentEncoded: false)) else { return base }
        return "\(base)-\(shortStableSuffix(artifact.id))"
    }

    private func slug(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_ ."))
        let scalars = value.unicodeScalars.map { allowed.contains($0) ? Character($0) : "-" }
        let collapsed = String(scalars)
            .replacingOccurrences(of: " ", with: "-")
            .split(separator: "-")
            .joined(separator: "-")
            .trimmingCharacters(in: CharacterSet(charactersIn: "-_."))
        return collapsed.isEmpty ? "untitled" : collapsed
    }

    private func shortStableSuffix(_ value: String) -> String {
        String(abs(value.hashValue), radix: 36).prefix(6).lowercased()
    }

    private func markdownRow(for artifact: Artifact, exportedPath: String) -> String {
        "| \(escapeMarkdown(artifact.source.rawValue)) | \(escapeMarkdown(artifact.category.displayName)) | \(escapeMarkdown(artifact.title)) | `\(artifact.url.path(percentEncoded: false))` |"
    }

    private func escapeMarkdown(_ value: String) -> String {
        value.replacingOccurrences(of: "|", with: "\\|")
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }

    private func fileSafeTimestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: date)
    }

    private var readableExportPrunedDirectoryNames: Set<String> {
        [
            ".git",
            ".github",
            ".build",
            ".next",
            ".venv",
            "build",
            "dist",
            "node_modules",
            "__pycache__",
        ]
    }
}

private struct VaultBackupManifest: Codable {
    let version: Int
    let generatedAt: Date
    let entries: [VaultBackupEntry]
}

private struct VaultBackupEntry: Codable {
    let artifactID: String
    let title: String
    let category: String
    let source: String
    let originalPath: String
    let storedPath: String
    let isDirectory: Bool
}
