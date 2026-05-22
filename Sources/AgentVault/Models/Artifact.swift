import Foundation

/// Provenance metadata extracted from a manifest or frontmatter.
struct ArtifactMetadata: Hashable, Sendable {
    var author: String?
    var version: String?
    /// The marketplace this artifact belongs to (e.g. "ames-plugins").
    var marketplace: String?
    /// Plugin name when the artifact is inside one (e.g. for a skill).
    var plugin: String?
    /// Repository or origin URL.
    var repoURL: URL?
    /// True if this artifact is bundled with the runtime itself (Claude
    /// Code / Codex) rather than installed by the user.
    var isBundled: Bool
    /// Which runtimes have this marketplace installed (only set for the
    /// `.marketplace` category).
    var installedInto: [ArtifactSource]

    static let empty = ArtifactMetadata(
        author: nil, version: nil, marketplace: nil, plugin: nil,
        repoURL: nil, isBundled: false, installedInto: []
    )
}

/// One thing surfaced in Agent Vault: a file or directory representing a
/// skill, MCP entry, plugin manifest, instruction file, remember buffer, etc.
struct Artifact: Identifiable, Hashable, Sendable {
    let id: String                 // stable: SHA-friendly path hash
    let url: URL
    let category: ArtifactCategory
    let source: ArtifactSource
    let isCustom: Bool             // user-authored vs system/installed
    let title: String              // display name (skill name, project, etc.)
    let subtitle: String?          // path snippet, parent project, kind
    let modifiedAt: Date
    let sizeBytes: Int64
    let tags: [String]             // extra labels (e.g. plugin name, version)
    let metadata: ArtifactMetadata

    init(
        id: String? = nil,
        url: URL,
        category: ArtifactCategory,
        source: ArtifactSource,
        isCustom: Bool,
        title: String,
        subtitle: String? = nil,
        modifiedAt: Date,
        sizeBytes: Int64,
        tags: [String] = [],
        metadata: ArtifactMetadata = .empty
    ) {
        self.id = id ?? url.path(percentEncoded: false)
        self.url = url
        self.category = category
        self.source = source
        self.isCustom = isCustom
        self.title = title
        self.subtitle = subtitle
        self.modifiedAt = modifiedAt
        self.sizeBytes = sizeBytes
        self.tags = tags
        self.metadata = metadata
    }

    /// Human-readable size, e.g. "4.2 KB", "1.1 MB".
    var sizeFormatted: String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: sizeBytes)
    }

    /// Relative time, e.g. "2d ago".
    var modifiedFormatted: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: modifiedAt, relativeTo: .now)
    }
}
