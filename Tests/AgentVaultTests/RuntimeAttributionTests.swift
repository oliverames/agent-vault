import Foundation
import Testing
@testable import AgentVault

@Suite("Marketplace identity and host attribution")
struct RuntimeAttributionTests {
    private func write(_ root: URL, _ path: String, _ text: String) throws -> URL {
        let url = root.appending(path: path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    @Test func dualHostAndSeparateRepositories() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let json = #"{"name":"same-name","plugins":[{"name":"example","source":"./plugins/example"}]}"#
        for repo in ["first", "second"] {
            for folder in [".claude-plugin", ".codex-plugin"] {
                _ = try write(root, "\(repo)/\(folder)/marketplace.json", json)
            }
            _ = try write(root, "\(repo)/plugins/example/skills/demo/SKILL.md", "---\nname: demo\n---\nExample")
        }
        let scanner = Scanner(classifier: ArtifactClassifier(heuristic: IsCustomHeuristic(
            authoringRoots: [root], installedRoots: [], excludeSegments: [], overrides: [:]
        )))
        let result = await scanner.scan(roots: [ScanRoot(url: root, displayName: "Fixture", isCanonical: true)])
        let marketplaces = result.artifacts.filter { $0.category == .marketplace }
        #expect(marketplaces.count == 2)
        #expect(marketplaces.allSatisfy { Set($0.sources) == [.claudeCode, .codex] })
        let skills = result.artifacts.filter { $0.category == .skill }
        #expect(skills.count == 2)
        #expect(skills.allSatisfy { Set($0.sources) == [.claudeCode, .codex] })
        let paused = await scanner.scan(roots: [ScanRoot(url: root, displayName: "Fixture", isCanonical: true)],
                                        excludedRoots: [root.appending(path: "first")])
        #expect(paused.artifacts.count == 2)
        #expect(paused.artifacts.allSatisfy { $0.url.path.contains("/second/") })
    }

    @Test func canonicalTargetsAndNoUnrelatedAttribution() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        _ = try write(root, "repo/.claude-plugin/marketplace.json", #"{"name":"fixture","plugins":[{"source":"./plugins/linked"}]}"#)
        let skill = try write(root, "shared/demo/SKILL.md", "Example")
        try FileManager.default.createDirectory(at: root.appending(path: "repo/plugins"), withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: root.appending(path: "repo/plugins/linked"), withDestinationURL: root.appending(path: "shared"))
        // A symlink into a runtime has direct, verifiable host provenance.
        let runtime = try write(root, ".codex/skills/demo/SKILL.md", "Example")
        let alias = root.appending(path: "alias.md")
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: runtime)
        #expect(RuntimeAttribution.sources(for: alias) == [.codex])
        #expect(RuntimeAttribution.sources(for: skill).isEmpty)
        let unrelated = try write(root, "repo/docs/SKILL.md", "Example")
        #expect(RuntimeAttribution.sources(for: unrelated).isEmpty)
        let scanner = Scanner(classifier: ArtifactClassifier(heuristic: IsCustomHeuristic(
            authoringRoots: [root], installedRoots: [], excludeSegments: [], overrides: [:]
        )))
        let result = await scanner.scan(roots: [ScanRoot(url: root, displayName: "Fixture", isCanonical: true)])
        #expect(result.artifacts.first { $0.url.resolvingSymlinksInPath().path == skill.resolvingSymlinksInPath().path }?.sources == [.claudeCode])
        #expect(result.artifacts.first { $0.url.resolvingSymlinksInPath().path == unrelated.resolvingSymlinksInPath().path }?.sources == [.other])
    }
}
