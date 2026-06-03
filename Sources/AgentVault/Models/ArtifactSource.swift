import Foundation

/// Which AI assistant ecosystem an artifact belongs to. "Other" catches
/// project-local artifacts that aren't strongly tied to one runtime.
enum ArtifactSource: String, CaseIterable, Identifiable, Sendable, Hashable {
    case claudeCode = "Claude Code"
    case codex = "Codex"
    case antigravity = "Antigravity"
    case hermes = "Hermes"
    case other = "Other"

    var id: String { rawValue }

    var sfSymbol: String {
        switch self {
        case .claudeCode: "c.square"
        case .codex: "chevron.left.forwardslash.chevron.right"
        case .antigravity: "a.square"
        case .hermes: "h.square"
        case .other: "ellipsis.circle"
        }
    }

    /// Heuristic for inferring source from a file's URL. Walks up the path
    /// looking for a known root segment. Order matters: more specific roots
    /// first.
    static func infer(from url: URL) -> ArtifactSource {
        let path = url.path(percentEncoded: false)
        if path.contains("/.claude/") || path.contains("/Library/Application Support/Claude/") {
            return .claudeCode
        }
        if path.contains("/.codex/") {
            return .codex
        }
        if path.contains("/.codex-plugin/") {
            return .codex
        }
        if path.contains("/.antigravity/") {
            return .antigravity
        }
        if path.contains("/.hermes/") || path.contains("/Library/Application Support/Hermes/") {
            return .hermes
        }
        // Project-authored content — Claude Code is the primary consumer of
        // CLAUDE.md and SKILL.md, so attribute to Claude Code unless an
        // AGENTS.md sits alongside.
        if url.lastPathComponent.lowercased().contains("agents") {
            return .codex
        }
        return .other
    }
}
