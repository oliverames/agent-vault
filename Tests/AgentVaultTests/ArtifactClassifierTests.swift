import Foundation
import Testing
@testable import AgentVault

@Suite("ArtifactClassifier")
struct ArtifactClassifierTests {
    @Test("classifies skill metadata from frontmatter")
    func classifiesSkillMetadata() throws {
        let root = try temporaryDirectory()
        let skillDir = root
            .appending(path: "plugins")
            .appending(path: "demo-plugin")
            .appending(path: "skills")
            .appending(path: "sample-skill", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: skillDir, withIntermediateDirectories: true)
        let skillURL = skillDir.appending(path: "SKILL.md")
        try """
        ---
        name: sample-skill
        author: Oliver Ames
        version: 1.2.3
        repository: https://github.com/oliverames/agent-vault
        ---

        Skill body.
        """.write(to: skillURL, atomically: true, encoding: .utf8)

        let classifier = ArtifactClassifier(
            heuristic: IsCustomHeuristic(authoringRoots: [root], installedRoots: [], excludeSegments: [], overrides: [:])
        )
        let artifact = classifier.classify(
            url: skillURL,
            isDirectory: false,
            modifiedAt: .now,
            sizeBytes: 12
        )

        #expect(artifact?.category == .skill)
        #expect(artifact?.title == "sample-skill")
        #expect(artifact?.isCustom == true)
        #expect(artifact?.metadata.author == "Oliver Ames")
        #expect(artifact?.metadata.version == "1.2.3")
        #expect(artifact?.metadata.plugin == "demo-plugin")
    }

    @Test("classifies MCP JSON manifests as config files")
    func classifiesMCPJSONManifest() throws {
        let root = try temporaryDirectory()
        let manifestURL = root
            .appending(path: ".codex-plugin", directoryHint: .isDirectory)
            .appending(path: "mcp.json")
        try FileManager.default.createDirectory(
            at: manifestURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try #"{"mcpServers":{}}"#.write(to: manifestURL, atomically: true, encoding: .utf8)

        let classifier = ArtifactClassifier(
            heuristic: IsCustomHeuristic(authoringRoots: [root], installedRoots: [], excludeSegments: [], overrides: [:])
        )
        let artifact = classifier.classify(
            url: manifestURL,
            isDirectory: false,
            modifiedAt: .now,
            sizeBytes: 12
        )

        #expect(artifact?.category == .configFile)
        #expect(artifact?.source == .codex)
        #expect(artifact?.title == "mcp.json")
    }

    private func temporaryDirectory() throws -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "AgentVaultTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
