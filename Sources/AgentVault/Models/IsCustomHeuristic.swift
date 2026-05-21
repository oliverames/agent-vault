import Foundation

/// Decides whether an artifact is user-authored ("custom") or
/// system/installed. Encapsulated so the rule lives in one place and is easy
/// to audit later.
///
/// **Decision order**
/// 1. Explicit user override → wins.
/// 2. Path under any user authoring project root → `true`.
/// 3. Path under a known cache/marketplace root → `false`.
/// 4. Default → `false`.
struct IsCustomHeuristic {
    /// Paths considered user-authored. Anything inside these (and not inside
    /// a backup/temp subdirectory) is treated as custom.
    let authoringRoots: [URL]
    /// Paths considered installed/system. Anything inside these is treated
    /// as not-custom even if it happens to live under an authoring root.
    let installedRoots: [URL]
    /// Path segments that mark a backup or temp tree; these invalidate the
    /// "authoring root" match because the file is no longer the canonical
    /// edit location.
    let excludeSegments: [String]
    /// User-set overrides keyed by full path string.
    let overrides: [String: Bool]

    func isCustom(_ url: URL) -> Bool {
        let path = url.path(percentEncoded: false)

        if let override = overrides[path] {
            return override
        }

        // installedRoots dominate authoringRoots so installed copies of
        // plugin files (e.g. mirrored into ~/.claude/plugins/cache) are
        // never marked custom.
        for installed in installedRoots where path.hasPrefix(installed.path(percentEncoded: false)) {
            return false
        }

        for excl in excludeSegments where path.contains("/\(excl)/") {
            return false
        }

        for authoring in authoringRoots where path.hasPrefix(authoring.path(percentEncoded: false)) {
            return true
        }

        return false
    }
}

extension IsCustomHeuristic {
    /// Default heuristic configured for Oliver's workspace conventions. The
    /// authoring roots are the canonical iCloud Developer project trees; the
    /// installed roots are the plugin caches and marketplace clones.
    static func defaults(overrides: [String: Bool] = [:]) -> IsCustomHeuristic {
        let home = URL(fileURLWithPath: NSHomeDirectory())
        let projects = home.appending(path: "Library/Mobile Documents/com~apple~CloudDocs/Developer/Projects")

        return IsCustomHeuristic(
            authoringRoots: [
                projects.appending(path: "ames-plugins"),
                projects.appending(path: "ames-connectors"),
                projects, // any other repo under Developer/Projects
            ],
            installedRoots: [
                home.appending(path: ".claude/plugins/cache"),
                home.appending(path: ".claude/plugins/marketplaces"),
                home.appending(path: ".codex/plugins/cache"),
                home.appending(path: ".codex/plugins/marketplaces"),
                home.appending(path: ".codex/.tmp"),
            ],
            excludeSegments: [
                ".codex-backups",
                ".bak",
                "node_modules",
                "Backups",
                "backups",
                "work-backups",
            ],
            overrides: overrides
        )
    }
}
