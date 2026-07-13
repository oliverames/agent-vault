import Foundation
import Testing
@testable import AgentVault

@Suite("Scanner safety")
struct ScannerTests {
    @Test("scanner ignores symbolic links")
    func scannerIgnoresSymbolicLinks() async throws {
        let root = try temporaryDirectory()
        let target = root.appending(path: "private-instructions.md")
        let link = root.appending(path: "CLAUDE.md")
        try "private\n".write(to: target, atomically: true, encoding: .utf8)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)

        let heuristic = IsCustomHeuristic(
            authoringRoots: [root],
            installedRoots: [],
            excludeSegments: [],
            overrides: [:]
        )
        let scanner = Scanner(classifier: ArtifactClassifier(heuristic: heuristic))
        let result = await scanner.scan(roots: [
            ScanRoot(url: root, displayName: "Fixture", isCanonical: true),
        ])

        #expect(result.artifacts.isEmpty)
    }

    private func temporaryDirectory() throws -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "AgentVaultScannerTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
