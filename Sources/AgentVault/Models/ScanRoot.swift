import Foundation

/// A directory Agent Vault will recursively scan. Defaults cover the major
/// AI-runtime homes plus iCloud Developer projects.
struct ScanRoot: Identifiable, Hashable, Sendable {
    let id: String
    let url: URL
    let displayName: String
    /// `true` if this root is part of the canonical, low-noise set scanned by
    /// default. `false` for caches/marketplaces hidden behind the "show
    /// installed/cached" toggle.
    let isCanonical: Bool

    init(url: URL, displayName: String, isCanonical: Bool) {
        self.id = url.path(percentEncoded: false)
        self.url = url
        self.displayName = displayName
        self.isCanonical = isCanonical
    }
}

extension ScanRoot {
    /// The default set of roots. Computed from `NSHomeDirectory()` so it
    /// follows user-account changes. Canonical roots are scanned on launch;
    /// cache roots are opt-in via the Settings toggle.
    static func defaults() -> [ScanRoot] {
        let home = URL(fileURLWithPath: NSHomeDirectory())
        let cloudDocs = home.appending(path: "Library/Mobile Documents/com~apple~CloudDocs")

        return [
            // Canonical authoring & runtime roots
            ScanRoot(url: home.appending(path: ".claude"),
                     displayName: "~/.claude",
                     isCanonical: true),
            ScanRoot(url: home.appending(path: ".codex"),
                     displayName: "~/.codex",
                     isCanonical: true),
            ScanRoot(url: home.appending(path: ".antigravity"),
                     displayName: "~/.antigravity",
                     isCanonical: true),
            ScanRoot(url: cloudDocs.appending(path: "Developer/Projects"),
                     displayName: "Developer/Projects (iCloud)",
                     isCanonical: true),
            ScanRoot(url: cloudDocs.appending(path: "Developer/Scripts"),
                     displayName: "Developer/Scripts (iCloud)",
                     isCanonical: true),
            ScanRoot(url: home.appending(path: "Documents"),
                     displayName: "~/Documents",
                     isCanonical: true),
            ScanRoot(url: cloudDocs.appending(path: "Family"),
                     displayName: "iCloud Family",
                     isCanonical: true),

            // Opt-in: noisy plugin caches and marketplaces
            ScanRoot(url: home.appending(path: ".claude/plugins/cache"),
                     displayName: "Claude plugin cache",
                     isCanonical: false),
            ScanRoot(url: home.appending(path: ".claude/plugins/marketplaces"),
                     displayName: "Claude marketplaces",
                     isCanonical: false),
            ScanRoot(url: home.appending(path: ".codex/plugins/cache"),
                     displayName: "Codex plugin cache",
                     isCanonical: false),
        ]
    }
}
