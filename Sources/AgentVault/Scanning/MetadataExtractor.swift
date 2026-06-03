import Foundation

/// Parses provenance metadata from SKILL.md frontmatter, plugin.json, and
/// marketplace.json. Called by the classifier when building each artifact.
///
/// We don't use a real YAML parser — frontmatter is simple enough to walk
/// line-by-line, and the failure mode for an unparseable file is just "no
/// metadata" which is fine.
struct MetadataExtractor: Sendable {
    /// Parse a SKILL.md frontmatter block for `name`, `description`,
    /// `author`, `version`, etc. Returns `.empty` if no frontmatter present.
    func skillMetadata(at url: URL, plugin: String?, marketplace: String?, isBundled: Bool) -> ArtifactMetadata {
        let fm = parseFrontmatter(at: url)
        return ArtifactMetadata(
            author: fm["author"] ?? fm["by"],
            version: fm["version"],
            marketplace: marketplace,
            plugin: plugin,
            repoURL: (fm["repository"] ?? fm["homepage"]).flatMap(URL.init(string:)),
            isBundled: isBundled,
            installedInto: []
        )
    }

    /// Parse a plugin.json for top-level metadata fields.
    func pluginMetadata(at url: URL, marketplace: String?, isBundled: Bool) -> ArtifactMetadata {
        let dict: [String: Any]
        if url.pathExtension.lowercased() == "yaml" || url.pathExtension.lowercased() == "yml" {
            dict = yamlObject(at: url)
        } else {
            guard let json = jsonObject(at: url) else { return .empty }
            dict = json
        }
        let author = (dict["author"] as? String)
            ?? ((dict["author"] as? [String: Any])?["name"] as? String)
        let repoString = (dict["repository"] as? String)
            ?? ((dict["repository"] as? [String: Any])?["url"] as? String)
            ?? (dict["homepage"] as? String)
        return ArtifactMetadata(
            author: author,
            version: dict["version"] as? String,
            marketplace: marketplace,
            plugin: dict["name"] as? String,
            repoURL: repoString.flatMap(URL.init(string:)),
            isBundled: isBundled,
            installedInto: []
        )
    }

    /// Parse a marketplace.json for owner and plugin list, then detect which
    /// runtimes have it installed.
    func marketplaceMetadata(at url: URL, isBundled: Bool) -> ArtifactMetadata {
        let dict = jsonObject(at: url) ?? [:]
        let owner = (dict["owner"] as? String)
            ?? ((dict["owner"] as? [String: Any])?["name"] as? String)
        let repoString = (dict["repository"] as? String)
            ?? ((dict["repository"] as? [String: Any])?["url"] as? String)
            ?? (dict["url"] as? String)

        let marketplaceName = (dict["name"] as? String)
            ?? url.deletingLastPathComponent().lastPathComponent

        return ArtifactMetadata(
            author: owner,
            version: dict["version"] as? String,
            marketplace: marketplaceName,
            plugin: nil,
            repoURL: repoString.flatMap(URL.init(string:)),
            isBundled: isBundled,
            installedInto: detectInstalledInto(marketplaceName: marketplaceName)
        )
    }

    // MARK: - Frontmatter parser

    private func parseFrontmatter(at url: URL) -> [String: String] {
        // Read only the first ~4KB — frontmatter never goes past that.
        guard let handle = try? FileHandle(forReadingFrom: url) else { return [:] }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: 4096),
              let head = String(data: data, encoding: .utf8) else { return [:] }

        // Frontmatter must start at byte 0 with `---`.
        guard head.hasPrefix("---") else { return [:] }
        let afterFirst = head.dropFirst(3)
        // Find the closing `---`.
        guard let closingRange = afterFirst.range(of: "\n---") else { return [:] }
        let block = afterFirst[..<closingRange.lowerBound]

        var out: [String: String] = [:]
        for rawLine in block.split(separator: "\n") {
            let line = String(rawLine)
            // Only top-level keys (no leading whitespace).
            guard !line.isEmpty, !line.hasPrefix(" ") else { continue }
            guard let colon = line.firstIndex(of: ":") else { continue }
            let key = String(line[..<colon]).trimmingCharacters(in: .whitespaces)
            var value = String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
            // Strip surrounding quotes.
            if (value.hasPrefix("\"") && value.hasSuffix("\""))
                || (value.hasPrefix("'") && value.hasSuffix("'")) {
                value = String(value.dropFirst().dropLast())
            }
            if !value.isEmpty {
                out[key.lowercased()] = value
            }
        }
        return out
    }

    private func parseTopLevelYAML(at url: URL) -> [String: String] {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return [:] }
        var out: [String: String] = [:]

        for rawLine in text.split(separator: "\n") {
            let line = String(rawLine)
            guard !line.isEmpty,
                  !line.hasPrefix(" "),
                  !line.hasPrefix("\t"),
                  !line.hasPrefix("#"),
                  let colon = line.firstIndex(of: ":")
            else { continue }

            let key = String(line[..<colon]).trimmingCharacters(in: .whitespaces)
            var value = String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
            if (value.hasPrefix("\"") && value.hasSuffix("\""))
                || (value.hasPrefix("'") && value.hasSuffix("'")) {
                value = String(value.dropFirst().dropLast())
            }
            if !key.isEmpty, !value.isEmpty {
                out[key.lowercased()] = value
            }
        }

        return out
    }

    // MARK: - JSON helper

    private func jsonObject(at url: URL) -> [String: Any]? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    private func yamlObject(at url: URL) -> [String: Any] {
        parseTopLevelYAML(at: url)
    }

    // MARK: - "Installed into" detection

    /// Check standard install locations for a marketplace name. Returns the
    /// runtimes that have it installed. Locations:
    /// - Claude Code: `~/.claude/plugins/marketplaces/<name>/`
    /// - Codex: `~/.codex/plugins/cache/<name>/` (codex uses the cache dir
    ///   directly; there's no separate `marketplaces/` subdir)
    private func detectInstalledInto(marketplaceName: String) -> [ArtifactSource] {
        let home = URL(fileURLWithPath: NSHomeDirectory())
        let fm = FileManager.default
        var out: [ArtifactSource] = []

        let claudePath = home
            .appending(path: ".claude/plugins/marketplaces")
            .appending(path: marketplaceName)
        if fm.fileExists(atPath: claudePath.path(percentEncoded: false)) {
            out.append(.claudeCode)
        }
        let codexPath = home
            .appending(path: ".codex/plugins/cache")
            .appending(path: marketplaceName)
        if fm.fileExists(atPath: codexPath.path(percentEncoded: false)) {
            out.append(.codex)
        }
        let hermesPath = home
            .appending(path: ".hermes/plugins")
            .appending(path: marketplaceName)
        if fm.fileExists(atPath: hermesPath.path(percentEncoded: false)) {
            out.append(.hermes)
        }
        return out
    }
}

// MARK: - Bundled-path detection

extension MetadataExtractor {
    /// Returns true if the URL is inside a runtime's bundled distribution.
    /// Bundled = ships with the runtime itself, not installed by the user
    /// via `plugin install`. Includes:
    /// - Claude binary versions under `~/.local/share/claude/versions/`
    /// - Codex bundled skills at `~/.codex/skills/` (the skills directory
    ///   not under `plugins/`)
    /// - Codex vendor-imported skills at `~/.codex/vendor_imports/`
    /// - Claude Desktop extensions
    static func isBundled(_ url: URL) -> Bool {
        let path = url.path(percentEncoded: false)
        return path.contains("/.local/share/claude/versions/")
            || path.contains("/.local/share/codex/")
            || path.contains("/.codex/skills/")
            || path.contains("/.codex/vendor_imports/")
            || path.contains("/.hermes/hermes-agent/")
            || path.contains("/Library/Application Support/Claude/Claude Extensions/")
    }
}
