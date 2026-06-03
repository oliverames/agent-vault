import Foundation
import Testing
@testable import AgentVault

@Suite("MCP extraction")
struct McpExtractorTests {
    @Test("extracts MCP servers from Codex config.toml")
    func extractsCodexMCPServers() throws {
        let configURL = try temporaryFile(
            name: "config.toml",
            contents: """
            [mcp_servers.github]
            command = "npx"
            args = ["-y", "@modelcontextprotocol/server-github"]

            [mcp_servers."local files"]
            command = "uvx"
            """
        )
        let artifact = configArtifact(url: configURL)

        let mcps = McpExtractor().extract(from: [artifact])

        #expect(Set(mcps.map(\.title)) == ["github", "local files"])
        #expect(Set(mcps.map(\.id)).count == 2)
        #expect(mcps.allSatisfy { $0.category == .mcp })
        #expect(mcps.allSatisfy { $0.source == .codex })
    }

    @Test("extracts MCP servers from Claude JSON settings")
    func extractsClaudeMCPServers() throws {
        let settingsURL = try temporaryFile(
            name: "settings.json",
            contents: """
            {
              "mcpServers": {
                "filesystem": {
                  "command": "npx",
                  "args": ["-y", "@modelcontextprotocol/server-filesystem"]
                }
              }
            }
            """
        )
        let artifact = configArtifact(url: settingsURL)

        let mcps = McpExtractor().extract(from: [artifact])

        #expect(mcps.count == 1)
        #expect(mcps.first?.title == "filesystem")
        #expect(mcps.first?.subtitle?.contains("npx") == true)
    }

    @Test("extracts MCP servers from plugin mcp.json")
    func extractsPluginMCPManifest() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "AgentVaultTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        let manifestDirectory = root.appending(path: ".codex-plugin", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: manifestDirectory, withIntermediateDirectories: true)
        let manifestURL = manifestDirectory.appending(path: "mcp.json")
        try """
        {
          "servers": {
            "local-tool": {
              "command": "swift",
              "args": ["run", "tool"]
            }
          }
        }
        """.write(to: manifestURL, atomically: true, encoding: .utf8)

        let artifact = configArtifact(url: manifestURL)
        let mcps = McpExtractor().extract(from: [artifact])

        #expect(mcps.count == 1)
        #expect(mcps.first?.id == "\(manifestURL.path(percentEncoded: false))#mcp:local-tool")
        #expect(mcps.first?.source == .codex)
        #expect(mcps.first?.subtitle == "swift run tool")
    }

    @Test("extracts MCP servers from Hermes config yaml")
    func extractsHermesMCPServers() throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "AgentVaultTests-\(UUID().uuidString)", directoryHint: .isDirectory)
            .appending(path: ".hermes", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let configURL = directory.appending(path: "config.yaml")
        try """
        agent:
          verbose: false
        mcp_servers:
          apple-docs:
            command: npx
            args:
            - -y
            - '@kimsungwhee/apple-docs-mcp@latest'
          cloudflare-api:
            url: https://mcp.cloudflare.com/mcp
        """.write(to: configURL, atomically: true, encoding: .utf8)

        let artifact = configArtifact(url: configURL)

        let mcps = McpExtractor().extract(from: [artifact])

        #expect(Set(mcps.map(\.title)) == ["apple-docs", "cloudflare-api"])
        #expect(mcps.allSatisfy { $0.source == .hermes })
        #expect(mcps.first { $0.title == "apple-docs" }?.subtitle == "npx -y @kimsungwhee/apple-docs-mcp@latest")
        #expect(mcps.first { $0.title == "cloudflare-api" }?.subtitle == "https://mcp.cloudflare.com/mcp")
    }

    private func configArtifact(url: URL) -> Artifact {
        Artifact(
            url: url,
            category: .configFile,
            source: ArtifactSource.infer(from: url),
            isCustom: false,
            title: url.lastPathComponent,
            modifiedAt: .now,
            sizeBytes: 0
        )
    }

    private func temporaryFile(name: String, contents: String) throws -> URL {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "AgentVaultTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appending(path: name)
        try contents.write(to: url, atomically: true, encoding: .utf8)
        return url
    }
}
