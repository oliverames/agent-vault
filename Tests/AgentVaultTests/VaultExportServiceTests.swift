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
        #expect(readme.contains("best-effort secret redaction"))
    }

    @Test("clean export redacts config secrets")
    func cleanExportRedactsConfigSecrets() throws {
        let root = try temporaryDirectory()
        let configURL = root.appending(path: "config.toml")
        let secret = "sk-" + "test-0123456789abcdefghijklmnop"
        try "OPENAI_API_KEY = \"\(secret)\"\nsafe = \"visible\"\n".write(
            to: configURL,
            atomically: true,
            encoding: .utf8
        )

        let service = VaultExportService()
        let result = try service.exportClean(
            artifacts: [configArtifact(url: configURL, source: .codex)],
            to: root.appending(path: "Exports", directoryHint: .isDirectory)
        )
        let exportedConfig = result.rootURL
            .appending(path: "Codex")
            .appending(path: "Config Files")
            .appending(path: "config.toml")
            .appending(path: "config.toml")
        let contents = try String(contentsOf: exportedConfig, encoding: .utf8)

        #expect(!contents.contains(secret))
        #expect(contents.contains("<redacted>"))
        #expect(contents.contains("safe = \"visible\""))
    }

    @Test("clean export does not follow symbolic links")
    func cleanExportDoesNotFollowSymbolicLinks() throws {
        let root = try temporaryDirectory()
        let skillDir = root.appending(path: "demo-skill", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: skillDir, withIntermediateDirectories: true)
        let skillURL = skillDir.appending(path: "SKILL.md")
        try "# Demo\n".write(to: skillURL, atomically: true, encoding: .utf8)

        let outside = root.appending(path: "outside-secret.txt")
        try "do not copy\n".write(to: outside, atomically: true, encoding: .utf8)
        try FileManager.default.createSymbolicLink(
            at: skillDir.appending(path: "linked-secret.txt"),
            withDestinationURL: outside
        )
        let outsideDirectory = root.appending(path: "outside-directory", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: outsideDirectory, withIntermediateDirectories: true)
        try "do not copy this directory\n".write(
            to: outsideDirectory.appending(path: "nested-secret.txt"),
            atomically: true,
            encoding: .utf8
        )
        try FileManager.default.createSymbolicLink(
            at: skillDir.appending(path: "linked-directory", directoryHint: .isDirectory),
            withDestinationURL: outsideDirectory
        )

        let service = VaultExportService()
        let result = try service.exportClean(
            artifacts: [skillArtifact(url: skillURL, source: .codex, title: "demo-skill")],
            to: root.appending(path: "Exports", directoryHint: .isDirectory)
        )
        let linkedExport = result.rootURL
            .appending(path: "Codex")
            .appending(path: "Skills")
            .appending(path: "demo-skill")
            .appending(path: "linked-secret.txt")

        #expect(!FileManager.default.fileExists(atPath: linkedExport.path(percentEncoded: false)))
        #expect(!FileManager.default.fileExists(
            atPath: result.rootURL
                .appending(path: "Codex")
                .appending(path: "Skills")
                .appending(path: "demo-skill")
                .appending(path: "linked-directory")
                .appending(path: "nested-secret.txt")
                .path(percentEncoded: false)
        ))
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

    @Test("restore rejects stored paths outside the backup")
    func restoreRejectsStoredPathTraversal() throws {
        let root = try temporaryDirectory()
        let backup = root.appending(path: "Untrusted Backup", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: backup, withIntermediateDirectories: true)
        let outside = root.appending(path: "outside.txt")
        let destination = root.appending(path: "restored.txt")
        try "outside\n".write(to: outside, atomically: true, encoding: .utf8)
        let manifest = """
        {
          "version" : 1,
          "generatedAt" : "2027-01-15T08:00:00Z",
          "entries" : [
            {
              "artifactID" : "malicious",
              "title" : "malicious",
              "category" : "configFile",
              "source" : "Codex",
              "originalPath" : "\(destination.path(percentEncoded: false))",
              "storedPath" : "../outside.txt",
              "isDirectory" : false
            }
          ]
        }
        """
        try manifest.write(to: backup.appending(path: "Manifest.json"), atomically: true, encoding: .utf8)

        let service = VaultExportService()
        do {
            _ = try service.restoreBackup(from: backup, overwriteExisting: false)
            Issue.record("Expected restore to reject a stored path outside the backup")
        } catch VaultExportError.invalidBackupPath {
            #expect(!FileManager.default.fileExists(atPath: destination.path(percentEncoded: false)))
        } catch {
            Issue.record("Unexpected restore error: \(error)")
        }
    }

    @Test("restore rejects a symbolic link inside the backup")
    func restoreRejectsStoredSymbolicLink() throws {
        let root = try temporaryDirectory()
        let backup = root.appending(path: "Untrusted Backup", directoryHint: .isDirectory)
        let items = backup.appending(path: "Items", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: items, withIntermediateDirectories: true)
        let outside = root.appending(path: "outside.txt")
        let destination = root.appending(path: "restored.txt")
        try "outside\n".write(to: outside, atomically: true, encoding: .utf8)
        try FileManager.default.createSymbolicLink(
            at: items.appending(path: "linked.txt"),
            withDestinationURL: outside
        )
        let manifest = """
        {
          "version" : 1,
          "generatedAt" : "2027-01-15T08:00:00Z",
          "entries" : [
            {
              "artifactID" : "malicious-link",
              "title" : "malicious-link",
              "category" : "configFile",
              "source" : "Codex",
              "originalPath" : "\(destination.path(percentEncoded: false))",
              "storedPath" : "Items/linked.txt",
              "isDirectory" : false
            }
          ]
        }
        """
        try manifest.write(to: backup.appending(path: "Manifest.json"), atomically: true, encoding: .utf8)

        let service = VaultExportService()
        do {
            _ = try service.restoreBackup(from: backup, overwriteExisting: false)
            Issue.record("Expected restore to reject a symbolic link inside the backup")
        } catch VaultExportError.invalidBackupPath {
            #expect(!FileManager.default.fileExists(atPath: destination.path(percentEncoded: false)))
        } catch {
            Issue.record("Unexpected restore error: \(error)")
        }
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
