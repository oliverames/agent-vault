import Foundation
import Testing
@testable import AgentVault

@Suite("Vault export service")
struct VaultExportServiceTests {
    @Test("clean export writes readable grouped folders and readme")
    func cleanExportWritesReadableGroupedFoldersAndReadme() throws {
        let root = try temporaryDirectory()
        let skillDir = root
            .appending(path: ".hermes", directoryHint: .isDirectory)
            .appending(path: "skills", directoryHint: .isDirectory)
            .appending(path: "demo-skill", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: skillDir, withIntermediateDirectories: true)
        let skillURL = skillDir.appending(path: "SKILL.md")
        try "# Demo skill\n".write(to: skillURL, atomically: true, encoding: .utf8)

        let destination = root.appending(path: "Exports", directoryHint: .isDirectory)
        let service = VaultExportService()
        let result = try service.exportClean(
            artifacts: [skillArtifact(url: skillURL, source: .hermes, title: "demo-skill")],
            to: destination,
            generatedAt: Date(timeIntervalSince1970: 1_800_000_000)
        )

        #expect(result.itemCount == 1)
        #expect(FileManager.default.fileExists(atPath: result.rootURL.appending(path: "README.md").path(percentEncoded: false)))
        #expect(FileManager.default.fileExists(
            atPath: result.rootURL
                .appending(path: "Hermes")
                .appending(path: "Skills")
                .appending(path: "demo-skill")
                .appending(path: "SKILL.md")
                .path(percentEncoded: false)
        ))

        let readme = try String(contentsOf: result.rootURL.appending(path: "README.md"), encoding: .utf8)
        #expect(readme.contains("Clean Export"))
        #expect(readme.contains("This folder is not a restore backup"))
    }

    @Test("backup manifest restores missing backing directory")
    func backupManifestRestoresMissingBackingDirectory() throws {
        let root = try temporaryDirectory()
        let skillDir = root.appending(path: "demo-skill", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: skillDir, withIntermediateDirectories: true)
        let skillURL = skillDir.appending(path: "SKILL.md")
        try "# Demo skill\n".write(to: skillURL, atomically: true, encoding: .utf8)

        let service = VaultExportService()
        let backup = try service.createBackup(
            artifacts: [skillArtifact(url: skillURL, source: .codex, title: "demo-skill")],
            to: root.appending(path: "Backups", directoryHint: .isDirectory),
            generatedAt: Date(timeIntervalSince1970: 1_800_000_000)
        )

        try FileManager.default.removeItem(at: skillDir)
        let restore = try service.restoreBackup(from: backup.rootURL, overwriteExisting: false)

        #expect(restore.restoredCount == 1)
        #expect(restore.conflictCount == 0)
        #expect(FileManager.default.fileExists(atPath: skillURL.path(percentEncoded: false)))
    }

    @Test("restore reports conflict instead of overwriting existing files")
    func restoreReportsConflictInsteadOfOverwritingExistingFiles() throws {
        let root = try temporaryDirectory()
        let configURL = root.appending(path: "config.toml")
        try "before\n".write(to: configURL, atomically: true, encoding: .utf8)

        let service = VaultExportService()
        let backup = try service.createBackup(
            artifacts: [configArtifact(url: configURL, source: .codex)],
            to: root.appending(path: "Backups", directoryHint: .isDirectory),
            generatedAt: Date(timeIntervalSince1970: 1_800_000_000)
        )
        try "after\n".write(to: configURL, atomically: true, encoding: .utf8)

        let restore = try service.restoreBackup(from: backup.rootURL, overwriteExisting: false)
        let contents = try String(contentsOf: configURL, encoding: .utf8)

        #expect(restore.restoredCount == 0)
        #expect(restore.conflictCount == 1)
        #expect(contents == "after\n")
    }

    @Test("memory reconcile writes non-destructive merged draft")
    func memoryReconcileWritesMergedDraft() throws {
        let root = try temporaryDirectory()
        let claudeMemory = root
            .appending(path: ".claude", directoryHint: .isDirectory)
            .appending(path: "projects", directoryHint: .isDirectory)
            .appending(path: "demo", directoryHint: .isDirectory)
            .appending(path: "memory", directoryHint: .isDirectory)
        let hermesMemory = root
            .appending(path: ".hermes", directoryHint: .isDirectory)
            .appending(path: "memories", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: claudeMemory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: hermesMemory, withIntermediateDirectories: true)
        try "Claude memory\n".write(to: claudeMemory.appending(path: "MEMORY.md"), atomically: true, encoding: .utf8)
        try "Hermes memory\n".write(to: hermesMemory.appending(path: "MEMORY.md"), atomically: true, encoding: .utf8)
        try "Hermes user\n".write(to: hermesMemory.appending(path: "USER.md"), atomically: true, encoding: .utf8)

        let service = VaultExportService()
        let result = try service.reconcileMemories(
            artifacts: [
                memoryArtifact(url: claudeMemory, source: .claudeCode, title: "Claude demo"),
                memoryArtifact(url: hermesMemory, source: .hermes, title: "Hermes memories"),
            ],
            to: root.appending(path: "Memory Reconcile", directoryHint: .isDirectory),
            generatedAt: Date(timeIntervalSince1970: 1_800_000_000)
        )

        let merged = try String(contentsOf: result.rootURL.appending(path: "MERGED-MEMORY.md"), encoding: .utf8)
        let readme = try String(contentsOf: result.rootURL.appending(path: "README.md"), encoding: .utf8)

        #expect(merged.contains("Claude memory"))
        #expect(merged.contains("Hermes memory"))
        #expect(merged.contains("Hermes user"))
        #expect(readme.contains("No live memory files were modified"))
        #expect(readme.contains("Hermes"))
    }

    private func skillArtifact(url: URL, source: ArtifactSource, title: String) -> Artifact {
        Artifact(
            url: url,
            category: .skill,
            source: source,
            isCustom: true,
            title: title,
            modifiedAt: .now,
            sizeBytes: 0
        )
    }

    private func configArtifact(url: URL, source: ArtifactSource) -> Artifact {
        Artifact(
            url: url,
            category: .configFile,
            source: source,
            isCustom: true,
            title: url.lastPathComponent,
            modifiedAt: .now,
            sizeBytes: 0
        )
    }

    private func memoryArtifact(url: URL, source: ArtifactSource, title: String) -> Artifact {
        Artifact(
            url: url,
            category: .memoryDir,
            source: source,
            isCustom: false,
            title: title,
            modifiedAt: .now,
            sizeBytes: 0
        )
    }

    private func temporaryDirectory() throws -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "AgentVaultTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
