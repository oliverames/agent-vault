import Foundation

/// Uses local manifest evidence, never a display name, to identify host support.
enum RuntimeAttribution {
    static let manifests: [(String, ArtifactSource)] = [
        (".claude-plugin", .claudeCode), ("claude-plugin", .claudeCode),
        (".codex-plugin", .codex), (".codex", .codex), ("codex", .codex),
    ]

    static func object(_ url: URL) -> [String: Any]? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    static func sources(for url: URL) -> [ArtifactSource] {
        let canonical = url.resolvingSymlinksInPath().standardizedFileURL
        let direct = ArtifactSource.infer(from: url)
        if direct != .other { return [direct] }
        let resolved = ArtifactSource.infer(from: canonical)
        if resolved != .other { return [resolved] }
        var sources = Set<ArtifactSource>()
        var directory = canonical.deletingLastPathComponent()
        while directory.path != "/" {
            for (folder, source) in manifests {
                let manifestDir = directory.appending(path: folder)
                if object(manifestDir.appending(path: "plugin.json")) != nil {
                    sources.insert(source)
                }
                let marketplace = manifestDir.appending(path: "marketplace.json")
                if let json = object(marketplace) {
                    if canonical == marketplace.resolvingSymlinksInPath().standardizedFileURL {
                        sources.insert(source)
                    }
                    for plugin in json["plugins"] as? [[String: Any]] ?? [] {
                        guard let path = plugin["source"] as? String,
                              path.hasPrefix("./") else { continue }
                        let target = directory.appending(path: path).resolvingSymlinksInPath().standardizedFileURL.path
                        if canonical.path == target || canonical.path.hasPrefix(target + "/") {
                            sources.insert(source)
                        }
                    }
                }
            }
            // Don't inherit host declarations from outside the owning repository.
            if FileManager.default.fileExists(atPath: directory.appending(path: ".git").path) { break }
            directory.deleteLastPathComponent()
        }
        return ArtifactSource.allCases.filter { sources.contains($0) }
    }

    struct LocalReference {
        let path: String
        let host: ArtifactSource
    }

    static func localReferences(in marketplaces: [Artifact]) -> [LocalReference] {
        var references: [LocalReference] = []
        for marketplace in marketplaces {
            let manifest = marketplace.url
            let parent = manifest.deletingLastPathComponent()
            guard let host = manifests.first(where: { $0.0 == parent.lastPathComponent })?.1,
                  let json = object(manifest) else { continue }
            for plugin in json["plugins"] as? [[String: Any]] ?? [] {
                guard let path = plugin["source"] as? String, path.hasPrefix("./") else { continue }
                let target = parent.deletingLastPathComponent().appending(path: path)
                    .resolvingSymlinksInPath().standardizedFileURL.path
                references.append(LocalReference(path: target, host: host))
            }
        }
        return references
    }

    /// Match scanned source files to local plugin references, including symlink targets.
    static func linkedSources(for artifact: Artifact, references: [LocalReference]) -> [ArtifactSource] {
        let canonical = artifact.url.resolvingSymlinksInPath().standardizedFileURL.path
        var sources = Set(artifact.sources.filter { $0 != .other })
        for reference in references {
            if canonical == reference.path || canonical.hasPrefix(reference.path + "/") {
                sources.insert(reference.host)
            }
        }
        return ArtifactSource.allCases.filter { sources.contains($0) }
    }

    static func marketplaceIdentity(for artifact: Artifact) -> String {
        let canonical = artifact.url.resolvingSymlinksInPath().standardizedFileURL
        let parent = canonical.deletingLastPathComponent()
        let root = manifests.contains { $0.0 == parent.lastPathComponent }
            ? parent.deletingLastPathComponent() : parent
        return "marketplace:\(root.path):\(artifact.metadata.marketplace ?? artifact.title)"
    }
}
