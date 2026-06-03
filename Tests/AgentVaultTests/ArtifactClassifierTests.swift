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

    @Test("infers Hermes source from Hermes paths")
    func infersHermesSource() {
        let skillURL = URL(fileURLWithPath: "/Users/example/.hermes/skills/research/blogwatcher/SKILL.md")

        #expect(ArtifactSource.infer(from: skillURL) == .hermes)
    }

    @Test("classifies Hermes memories directory")
    func classifiesHermesMemoriesDirectory() throws {
        let root = try temporaryDirectory()
        let memoriesURL = root
            .appending(path: ".hermes", directoryHint: .isDirectory)
            .appending(path: "memories", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: memoriesURL, withIntermediateDirectories: true)

        let classifier = ArtifactClassifier(
            heuristic: IsCustomHeuristic(authoringRoots: [root], installedRoots: [], excludeSegments: [], overrides: [:])
        )
        let artifact = classifier.classify(
            url: memoriesURL,
            isDirectory: true,
            modifiedAt: .now,
            sizeBytes: 0
        )

        #expect(artifact?.category == .memoryDir)
        #expect(artifact?.source == .hermes)
        #expect(artifact?.title == "Hermes memories")
        #expect(artifact?.tags.contains("hermes") == true)
    }

    @Test("classifies Hermes plugin yaml manifests")
    func classifiesHermesPluginYAML() throws {
        let root = try temporaryDirectory()
        let pluginDir = root
            .appending(path: ".hermes", directoryHint: .isDirectory)
            .appending(path: "plugins", directoryHint: .isDirectory)
            .appending(path: "memory", directoryHint: .isDirectory)
            .appending(path: "honcho", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: pluginDir, withIntermediateDirectories: true)
        let pluginURL = pluginDir.appending(path: "plugin.yaml")
        try """
        name: honcho
        version: 0.4.0
        author: Nous Research
        repository: https://github.com/nousresearch/hermes-agent
        """.write(to: pluginURL, atomically: true, encoding: .utf8)

        let classifier = ArtifactClassifier(
            heuristic: IsCustomHeuristic(authoringRoots: [root], installedRoots: [], excludeSegments: [], overrides: [:])
        )
        let artifact = classifier.classify(
            url: pluginURL,
            isDirectory: false,
            modifiedAt: .now,
            sizeBytes: 12
        )

        #expect(artifact?.category == .plugin)
        #expect(artifact?.source == .hermes)
        #expect(artifact?.title == "honcho")
        #expect(artifact?.metadata.author == "Nous Research")
        #expect(artifact?.metadata.version == "0.4.0")
    }

    @Test("classifies only Hermes yaml config files")
    func classifiesOnlyHermesYAMLConfigFiles() throws {
        let root = try temporaryDirectory()
        let hermesConfigURL = root
            .appending(path: ".hermes", directoryHint: .isDirectory)
            .appending(path: "config.yaml")
        try FileManager.default.createDirectory(
            at: hermesConfigURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try "mcp_servers: {}\n".write(to: hermesConfigURL, atomically: true, encoding: .utf8)

        let projectConfigURL = root
            .appending(path: "Project", directoryHint: .isDirectory)
            .appending(path: "config.yaml")
        try FileManager.default.createDirectory(
            at: projectConfigURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try "name: unrelated\n".write(to: projectConfigURL, atomically: true, encoding: .utf8)

        let classifier = ArtifactClassifier(
            heuristic: IsCustomHeuristic(authoringRoots: [root], installedRoots: [], excludeSegments: [], overrides: [:])
        )

        #expect(classifier.classify(
            url: hermesConfigURL,
            isDirectory: false,
            modifiedAt: .now,
            sizeBytes: 12
        )?.category == .configFile)
        #expect(classifier.classify(
            url: projectConfigURL,
            isDirectory: false,
            modifiedAt: .now,
            sizeBytes: 12
        ) == nil)
    }

    private func temporaryDirectory() throws -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "AgentVaultTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
