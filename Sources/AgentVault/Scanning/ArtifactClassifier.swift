import Foundation

/// Maps a file or directory URL to an `Artifact`, or returns nil if the
/// entry doesn't match any category. Centralizes all per-category recognition
/// rules so adding a new category means editing one place.
struct ArtifactClassifier: Sendable {
    let heuristic: IsCustomHeuristic
    let metadata = MetadataExtractor()

    /// Classify a single filesystem entry. The walker passes
    /// `isDirectory` so we don't re-stat.
    func classify(
        url: URL,
        isDirectory: Bool,
        modifiedAt: Date,
        sizeBytes: Int64
    ) -> Artifact? {
        let name = url.lastPathComponent

        if isDirectory {
            return classifyDirectory(url: url, name: name, modifiedAt: modifiedAt, sizeBytes: sizeBytes)
        }
        return classifyFile(url: url, name: name, modifiedAt: modifiedAt, sizeBytes: sizeBytes)
    }

    // MARK: - Directories

    private func classifyDirectory(
        url: URL,
        name: String,
        modifiedAt: Date,
        sizeBytes: Int64
    ) -> Artifact? {
        if name == ".remember" {
            return Artifact(
                url: url,
                category: .rememberDir,
                source: ArtifactSource.infer(from: url),
                isCustom: heuristic.isCustom(url),
                title: parentProjectName(for: url) ?? "remember buffer",
                subtitle: shortPath(url),
                modifiedAt: modifiedAt,
                sizeBytes: sizeBytes,
                tags: []
            )
        }

        // Claude auto-memory dir: `~/.claude/projects/<slug>/memory/`
        if name == "memory" && url.deletingLastPathComponent()
            .deletingLastPathComponent()
            .lastPathComponent == "projects"
        {
            let slug = url.deletingLastPathComponent().lastPathComponent
            return Artifact(
                url: url,
                category: .memoryDir,
                source: .claudeCode,
                isCustom: false,
                title: friendlySlug(slug),
                subtitle: shortPath(url),
                modifiedAt: modifiedAt,
                sizeBytes: sizeBytes,
                tags: ["claude", "auto-memory"]
            )
        }

        // Codex memories root: `~/.codex/memories/`
        if name == "memories" && url.deletingLastPathComponent().lastPathComponent == ".codex" {
            return Artifact(
                url: url,
                category: .memoryDir,
                source: .codex,
                isCustom: false,
                title: "Codex memories",
                subtitle: shortPath(url),
                modifiedAt: modifiedAt,
                sizeBytes: sizeBytes,
                tags: ["codex"]
            )
        }

        return nil
    }

    // MARK: - Files

    private func classifyFile(
        url: URL,
        name: String,
        modifiedAt: Date,
        sizeBytes: Int64
    ) -> Artifact? {
        switch name {
        case "SKILL.md":
            return skillArtifact(url: url, modifiedAt: modifiedAt, sizeBytes: sizeBytes)
        case "CLAUDE.md":
            return mdArtifact(category: .claudeMd, url: url, modifiedAt: modifiedAt, sizeBytes: sizeBytes)
        case "AGENTS.md":
            return mdArtifact(category: .agentsMd, url: url, modifiedAt: modifiedAt, sizeBytes: sizeBytes)
        case "WORKLOG.md":
            return mdArtifact(category: .worklogMd, url: url, modifiedAt: modifiedAt, sizeBytes: sizeBytes)
        case "marketplace.json":
            return marketplaceArtifact(url: url, modifiedAt: modifiedAt, sizeBytes: sizeBytes)
        case "plugin.json":
            return pluginArtifact(url: url, modifiedAt: modifiedAt, sizeBytes: sizeBytes)
        case "settings.json", "settings.local.json",
             "config.toml", "argv.json", "claude_desktop_config.json",
             ".mcp.json", "mcp.json":
            return configArtifact(url: url, name: name, modifiedAt: modifiedAt, sizeBytes: sizeBytes)
        default:
            return nil
        }
    }

    private func skillArtifact(url: URL, modifiedAt: Date, sizeBytes: Int64) -> Artifact {
        let skillDir = url.deletingLastPathComponent()
        let skillName = skillDir.lastPathComponent
        let plugin = pluginContainingPath(for: url)
        let marketplace = marketplaceContainingPath(for: url)
        let isBundled = MetadataExtractor.isBundled(url)
        let extracted = metadata.skillMetadata(
            at: url,
            plugin: plugin,
            marketplace: marketplace,
            isBundled: isBundled
        )
        return Artifact(
            url: url,
            category: .skill,
            source: ArtifactSource.infer(from: url),
            isCustom: heuristic.isCustom(url),
            title: skillName,
            subtitle: plugin,
            modifiedAt: modifiedAt,
            sizeBytes: sizeBytes,
            tags: plugin.map { [$0] } ?? [],
            metadata: extracted
        )
    }

    private func mdArtifact(category: ArtifactCategory, url: URL, modifiedAt: Date, sizeBytes: Int64) -> Artifact {
        let parent = url.deletingLastPathComponent().lastPathComponent
        return Artifact(
            url: url,
            category: category,
            source: ArtifactSource.infer(from: url),
            isCustom: heuristic.isCustom(url),
            title: parent.isEmpty ? url.lastPathComponent : parent,
            subtitle: shortPath(url),
            modifiedAt: modifiedAt,
            sizeBytes: sizeBytes
        )
    }

    private func marketplaceArtifact(url: URL, modifiedAt: Date, sizeBytes: Int64) -> Artifact {
        let dir = url.deletingLastPathComponent().lastPathComponent
        let isBundled = MetadataExtractor.isBundled(url)
        let extracted = metadata.marketplaceMetadata(at: url, isBundled: isBundled)
        return Artifact(
            url: url,
            category: .marketplace,
            source: ArtifactSource.infer(from: url),
            isCustom: heuristic.isCustom(url),
            title: extracted.marketplace ?? dir,
            subtitle: shortPath(url),
            modifiedAt: modifiedAt,
            sizeBytes: sizeBytes,
            tags: ["marketplace"],
            metadata: extracted
        )
    }

    private func pluginArtifact(url: URL, modifiedAt: Date, sizeBytes: Int64) -> Artifact {
        let pluginDir = url.deletingLastPathComponent().lastPathComponent
        let marketplace = marketplaceContainingPath(for: url)
        let isBundled = MetadataExtractor.isBundled(url)
        let extracted = metadata.pluginMetadata(at: url, marketplace: marketplace, isBundled: isBundled)
        return Artifact(
            url: url,
            category: .plugin,
            source: ArtifactSource.infer(from: url),
            isCustom: heuristic.isCustom(url),
            title: extracted.plugin ?? pluginDir,
            subtitle: shortPath(url),
            modifiedAt: modifiedAt,
            sizeBytes: sizeBytes,
            tags: ["plugin"],
            metadata: extracted
        )
    }

    private func configArtifact(url: URL, name: String, modifiedAt: Date, sizeBytes: Int64) -> Artifact {
        Artifact(
            url: url,
            category: .configFile,
            source: ArtifactSource.infer(from: url),
            isCustom: heuristic.isCustom(url),
            title: name,
            subtitle: shortPath(url),
            modifiedAt: modifiedAt,
            sizeBytes: sizeBytes,
            tags: [name]
        )
    }

    // MARK: - Helpers

    /// Returns the name of the plugin directory enclosing a skill, e.g.
    /// `/foo/plugins/ames-standalone-skills/skills/humanizer/SKILL.md`
    /// returns "ames-standalone-skills".
    private func pluginContainingPath(for url: URL) -> String? {
        let parts = url.pathComponents
        guard let pluginsIdx = parts.lastIndex(of: "plugins"),
              pluginsIdx + 1 < parts.count
        else { return nil }
        return parts[pluginsIdx + 1]
    }

    /// Returns the marketplace name enclosing an artifact. The marketplace
    /// is the directory directly above the innermost `plugins/` segment.
    /// Examples:
    ///   `~/Developer/Projects/ames-plugins/plugins/X/...` → "ames-plugins"
    ///   `~/.claude/plugins/marketplaces/ames-plugins/plugins/X/...` → "ames-plugins"
    /// Using `lastIndex(of: "plugins")` handles both: in the second case it
    /// matches the inner `plugins/` (after the marketplace name), not the
    /// outer `plugins/marketplaces` directory.
    private func marketplaceContainingPath(for url: URL) -> String? {
        let parts = url.pathComponents
        guard let pluginsIdx = parts.lastIndex(of: "plugins"),
              pluginsIdx > 0
        else { return nil }
        return parts[pluginsIdx - 1]
    }

    /// Best-guess project name for a `.remember/` directory: the parent
    /// directory's name, unless that's home, in which case we say "home".
    private func parentProjectName(for url: URL) -> String? {
        let parent = url.deletingLastPathComponent()
        let name = parent.lastPathComponent
        if parent.path(percentEncoded: false) == NSHomeDirectory() {
            return "Home (~)"
        }
        return name
    }

    /// Convert a Claude project slug like
    /// `-Users-oliverames-Developer-Projects-ames-plugins` into a friendly
    /// label.
    private func friendlySlug(_ slug: String) -> String {
        guard slug.hasPrefix("-") else { return slug }
        let trimmed = String(slug.dropFirst())
        let parts = trimmed.split(separator: "-")
        // Try to find the meaningful tail after "Projects" or "Documents".
        if let projectsIdx = parts.firstIndex(of: "Projects"), projectsIdx + 1 < parts.count {
            return parts[(projectsIdx + 1)...].joined(separator: "-")
        }
        if let documentsIdx = parts.firstIndex(of: "Documents"), documentsIdx + 1 < parts.count {
            return parts[(documentsIdx + 1)...].joined(separator: "-")
        }
        return parts.suffix(3).joined(separator: "/")
    }

    /// Shorten a file URL for display by replacing the home directory with
    /// `~` and trimming the leaf name.
    private func shortPath(_ url: URL) -> String {
        var path = url.deletingLastPathComponent().path(percentEncoded: false)
        let home = NSHomeDirectory()
        if path.hasPrefix(home) {
            path = "~" + path.dropFirst(home.count)
        }
        // Make iCloud paths readable.
        path = path.replacingOccurrences(
            of: "~/Library/Mobile Documents/com~apple~CloudDocs",
            with: "~/iCloud"
        )
        return path
    }
}
