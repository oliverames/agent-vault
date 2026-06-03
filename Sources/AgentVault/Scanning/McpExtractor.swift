import Foundation

/// Extracts virtual `Artifact`s for individual MCP server entries inside
/// already-discovered config files. Runs as a post-pass after the scan: the
/// scanner finds `settings.json`/`config.toml`/`claude_desktop_config.json`
/// and tags them as `.configFile`; this extractor opens each one, parses out
/// the MCP server entries, and emits one `.mcp` artifact per entry.
///
/// We don't parse TOML with a real parser — codex's `config.toml` uses a
/// well-known shape and regex on `[mcp_servers.<name>]` headers is enough.
struct McpExtractor: Sendable {
    /// Given the full set of artifacts from a scan, return additional MCP
    /// artifacts to add.
    func extract(from artifacts: [Artifact]) -> [Artifact] {
        var out: [Artifact] = []
        for artifact in artifacts where artifact.category == .configFile {
            let name = artifact.url.lastPathComponent
            switch name {
            case "settings.json",
                 "settings.local.json",
                 "claude_desktop_config.json",
                 ".mcp.json",
                 "mcp.json":
                out.append(contentsOf: parseJSON(at: artifact.url))
            case "config.toml":
                out.append(contentsOf: parseTOML(at: artifact.url))
            case "config.yaml", "config.yml":
                if ArtifactSource.infer(from: artifact.url) == .hermes {
                    out.append(contentsOf: parseHermesYAML(at: artifact.url))
                }
            default:
                continue
            }
        }
        return out
    }

    // MARK: - JSON (Claude family)

    private func parseJSON(at url: URL) -> [Artifact] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        guard let top = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return []
        }
        // The two known shapes:
        //   { "mcpServers": { "name": {...} } }
        //   { "claudeCodeSettings": { "mcpServers": ... } }   (unused, but cheap to check)
        // Some plugin repos also use:
        //   { "servers": { "name": {...} } }
        let dict = (top["mcpServers"] as? [String: Any])
            ?? ((top["claudeCodeSettings"] as? [String: Any])?["mcpServers"] as? [String: Any])
            ?? (top["servers"] as? [String: Any])
            ?? [:]

        guard !dict.isEmpty else { return [] }

        let attrs = fileAttributes(for: url)
        return dict.map { name, value in
            let entry = value as? [String: Any] ?? [:]
            let subtitle = subtitleFor(entry: entry)
            return Artifact(
                id: virtualID(configURL: url, serverName: name),
                url: url,
                category: .mcp,
                source: source(for: url),
                isCustom: false,
                title: name,
                subtitle: subtitle,
                modifiedAt: attrs.modified,
                sizeBytes: attrs.size,
                tags: tagsFor(entry: entry, configName: url.lastPathComponent)
            )
        }
    }

    private func subtitleFor(entry: [String: Any]) -> String {
        if let cmd = entry["command"] as? String {
            let args = (entry["args"] as? [Any])?
                .compactMap { $0 as? String }
                .joined(separator: " ") ?? ""
            return args.isEmpty ? cmd : "\(cmd) \(args)"
        }
        if let url = entry["url"] as? String { return url }
        if let type = entry["type"] as? String { return type }
        return "(no command)"
    }

    private func tagsFor(entry: [String: Any], configName: String) -> [String] {
        var tags = ["mcp", configName]
        if entry["url"] != nil { tags.append("sse") }
        if entry["command"] != nil { tags.append("stdio") }
        return tags
    }

    // MARK: - TOML (Codex)

    private func parseTOML(at url: URL) -> [Artifact] {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        // Match `[mcp_servers.<name>]` and capture <name>. Server names in
        // TOML can be bare keys (alnum + dashes + underscores) or quoted;
        // accept both.
        let pattern = #"^\[mcp_servers\.((?:[A-Za-z0-9_\-]+)|(?:"[^"]+"))\]"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.anchorsMatchLines]) else {
            return []
        }
        let range = NSRange(text.startIndex..., in: text)
        let attrs = fileAttributes(for: url)
        var out: [Artifact] = []

        regex.enumerateMatches(in: text, options: [], range: range) { match, _, _ in
            guard let match, match.numberOfRanges >= 2,
                  let nameRange = Range(match.range(at: 1), in: text) else { return }
            var name = String(text[nameRange])
            if name.hasPrefix("\""), name.hasSuffix("\"") {
                name = String(name.dropFirst().dropLast())
            }
            // Lift the server's `command` line as a subtitle if present in
            // the few lines after the header.
            let headerEnd = Range(match.range, in: text)!.upperBound
            let tail = text[headerEnd...].prefix(500)
            let cmdLine = tail.split(separator: "\n", maxSplits: 30, omittingEmptySubsequences: true)
                .first(where: { $0.trimmingCharacters(in: .whitespaces).hasPrefix("command") })
                .map { String($0).trimmingCharacters(in: .whitespaces) }

            out.append(Artifact(
                id: virtualID(configURL: url, serverName: name),
                url: url,
                category: .mcp,
                source: .codex,
                isCustom: false,
                title: name,
                subtitle: cmdLine ?? "(see config.toml)",
                modifiedAt: attrs.modified,
                sizeBytes: attrs.size,
                tags: ["mcp", "codex", "config.toml"]
            ))
        }

        return out
    }

    // MARK: - YAML (Hermes)

    private func parseHermesYAML(at url: URL) -> [Artifact] {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        guard let start = lines.firstIndex(where: { $0 == "mcp_servers:" }) else { return [] }

        let attrs = fileAttributes(for: url)
        var out: [Artifact] = []
        var currentName: String?
        var currentCommand: String?
        var currentURL: String?
        var currentArgs: [String] = []
        var inArgs = false

        func flush() {
            guard let name = currentName else { return }
            let subtitle: String
            if let currentURL, !currentURL.isEmpty {
                subtitle = currentURL
            } else if let currentCommand, !currentCommand.isEmpty {
                let args = currentArgs.joined(separator: " ")
                subtitle = args.isEmpty ? currentCommand : "\(currentCommand) \(args)"
            } else {
                subtitle = "(see config.yaml)"
            }

            out.append(Artifact(
                id: virtualID(configURL: url, serverName: name),
                url: url,
                category: .mcp,
                source: .hermes,
                isCustom: false,
                title: name,
                subtitle: subtitle,
                modifiedAt: attrs.modified,
                sizeBytes: attrs.size,
                tags: ["mcp", "hermes", url.lastPathComponent]
            ))
        }

        for line in lines.dropFirst(start + 1) {
            if !line.hasPrefix(" ") && !line.trimmingCharacters(in: .whitespaces).isEmpty {
                break
            }

            if line.hasPrefix("  "), !line.hasPrefix("    "), line.trimmingCharacters(in: .whitespaces).hasSuffix(":") {
                flush()
                currentName = String(line.trimmingCharacters(in: .whitespaces).dropLast())
                currentCommand = nil
                currentURL = nil
                currentArgs = []
                inArgs = false
                continue
            }

            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("command:") {
                currentCommand = yamlScalar(afterColonIn: trimmed)
                inArgs = false
            } else if trimmed.hasPrefix("url:") {
                currentURL = yamlScalar(afterColonIn: trimmed)
                inArgs = false
            } else if trimmed == "args:" {
                inArgs = true
            } else if inArgs, trimmed.hasPrefix("- ") {
                currentArgs.append(cleanYAMLScalar(String(trimmed.dropFirst(2))))
            } else if !trimmed.isEmpty, !trimmed.hasPrefix("- ") {
                inArgs = false
            }
        }
        flush()

        return out
    }

    // MARK: - Helpers

    private func source(for url: URL) -> ArtifactSource {
        let path = url.path(percentEncoded: false)
        if path.contains("/.claude/") || path.contains("Application Support/Claude/") {
            return .claudeCode
        }
        if path.contains("/.codex/") || path.contains("/.codex-plugin/") { return .codex }
        if path.contains("/.hermes/") || path.contains("Application Support/Hermes/") { return .hermes }
        return .other
    }

    private func virtualID(configURL: URL, serverName: String) -> String {
        "\(configURL.path(percentEncoded: false))#mcp:\(serverName)"
    }

    private func fileAttributes(for url: URL) -> (modified: Date, size: Int64) {
        let attrs = (try? FileManager.default.attributesOfItem(atPath: url.path(percentEncoded: false))) ?? [:]
        let modified = (attrs[.modificationDate] as? Date) ?? .distantPast
        let size = (attrs[.size] as? Int64) ?? 0
        return (modified, size)
    }

    private func yamlScalar(afterColonIn line: String) -> String {
        guard let colon = line.firstIndex(of: ":") else { return "" }
        return cleanYAMLScalar(String(line[line.index(after: colon)...]))
    }

    private func cleanYAMLScalar(_ raw: String) -> String {
        var value = raw.trimmingCharacters(in: .whitespaces)
        if (value.hasPrefix("\"") && value.hasSuffix("\""))
            || (value.hasPrefix("'") && value.hasSuffix("'")) {
            value = String(value.dropFirst().dropLast())
        }
        return value
    }
}
