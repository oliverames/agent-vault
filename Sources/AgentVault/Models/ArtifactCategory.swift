import Foundation

/// Top-level taxonomy for everything Agent Vault surfaces. Order here is the
/// order shown in the sidebar.
enum ArtifactCategory: String, CaseIterable, Identifiable, Sendable, Hashable {
    case skill
    case mcp
    case marketplace
    case plugin
    case configFile
    case claudeMd
    case agentsMd
    case worklogMd
    case rememberDir
    case memoryDir

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .skill: "Skills"
        case .mcp: "MCPs"
        case .marketplace: "Marketplaces"
        case .plugin: "Plugins"
        case .configFile: "Config Files"
        case .claudeMd: "CLAUDE.md"
        case .agentsMd: "AGENTS.md"
        case .worklogMd: "WORKLOG.md"
        case .rememberDir: ".remember"
        case .memoryDir: "Memory"
        }
    }

    var sfSymbol: String {
        switch self {
        case .skill: "sparkles"
        case .mcp: "bolt.horizontal.circle"
        case .marketplace: "storefront"
        case .plugin: "puzzlepiece.extension"
        case .configFile: "gearshape"
        case .claudeMd: "doc.text"
        case .agentsMd: "doc.text"
        case .worklogMd: "list.bullet.rectangle"
        case .rememberDir: "tray.full"
        case .memoryDir: "brain"
        }
    }

    /// Whether this category's artifacts are directories instead of single
    /// files. Directory-based artifacts get an expanded detail view that lists
    /// children.
    var isDirectoryBacked: Bool {
        self == .rememberDir || self == .memoryDir
    }
}
