import Foundation
import Observation

/// Coarse phase of the scanner used to drive UI affordances.
enum ScanPhase: Sendable, Equatable {
    case idle
    case scanning
    case done(visited: Int, duration: TimeInterval)
    case failed(String)
}

/// The app-wide observable state. SwiftUI views read this; mutations happen
/// on the main actor. Background work is delegated to the `Scanner` actor.
@MainActor
@Observable
final class VaultStore {
    // MARK: - Inventory state

    private(set) var artifacts: [Artifact] = []
    private(set) var deniedRoots: [URL] = []
    private(set) var phase: ScanPhase = .idle
    private(set) var lastVisitedCount: Int = 0
    private(set) var lastScanDuration: TimeInterval = 0

    // MARK: - Filter / selection state

    var selectedCategory: ArtifactCategory? = nil
    var selectedSource: ArtifactSource? = nil
    var searchText: String = ""
    var sortOrder: ArtifactSortOrder = .modifiedNewest
    var showCustomOnly: Bool = false
    var showCached: Bool = false {
        didSet { Task { await rescan() } }
    }
    var selectedArtifactID: Artifact.ID? = nil

    // MARK: - Roots / heuristic

    private(set) var scanRoots: [ScanRoot]
    private(set) var heuristic: IsCustomHeuristic
    private var customOverrides: [String: Bool] {
        get { loadOverrides() }
        set { saveOverrides(newValue); heuristic = IsCustomHeuristic.defaults(overrides: newValue) }
    }

    // MARK: - Workers

    private let preferences: UserDefaults
    private var scanGeneration = 0
    private let scanner: Scanner
    private let mcpExtractor = McpExtractor()

    // MARK: - Init

    init(preferences: UserDefaults = .standard, defaultRoots: [ScanRoot] = ScanRoot.defaults()) {
        self.preferences = preferences
        let overrides = preferences.dictionary(forKey: Self.overridesKey) as? [String: Bool] ?? [:]
        let heuristic = IsCustomHeuristic.defaults(overrides: overrides)
        let roots = Self.mergedRoots(
            defaults: defaultRoots,
            customPaths: preferences.stringArray(forKey: Self.customRootsKey) ?? []
        )
        let enabledStates = preferences.dictionary(forKey: Self.rootEnabledKey) as? [String: Bool] ?? [:]
        self.scanRoots = roots.map { root in
            var root = root
            root.isEnabled = enabledStates[root.id] ?? root.isEnabled
            return root
        }
        self.heuristic = heuristic
        self.scanner = Scanner(classifier: ArtifactClassifier(heuristic: heuristic))
    }

    // MARK: - Scan

    /// Run a fresh scan over the active roots.
    func rescan() async {
        scanGeneration += 1
        let generation = scanGeneration
        phase = .scanning
        let activeRoots = scanRoots.filter { $0.isEnabled && ($0.isCanonical || showCached) }
        let excludedRoots = scanRoots.filter { !$0.isEnabled }.map(\.url)
        // When caches are opted in, list them as forceWalk so the parent-child
        // pruner doesn't skip them when they're the explicit target root.
        let forceWalk = showCached
            ? activeRoots.filter { !$0.isCanonical }.map(\.url)
            : []
        let forcedPaths = Set(forceWalk.map { $0.standardizedFileURL.path(percentEncoded: false) })
        let startedAt = Date()
        var scannedArtifacts: [Artifact] = []
        var denied: [URL] = []
        var visited = 0

        artifacts = []
        deniedRoots = []
        lastVisitedCount = 0
        lastScanDuration = 0

        for root in activeRoots {
            let rootPath = root.url.standardizedFileURL.path(percentEncoded: false)
            let rootForceWalk = forcedPaths.contains(rootPath) ? [root.url] : []
            let result = await scanner.scan(roots: [root], forceWalk: rootForceWalk, excludedRoots: excludedRoots)
            guard generation == scanGeneration else { return }

            scannedArtifacts.append(contentsOf: result.artifacts)
            denied.append(contentsOf: result.deniedRoots)
            visited += result.visitedCount

            publishScanProgress(
                artifacts: scannedArtifacts,
                deniedRoots: denied,
                visited: visited,
                duration: Date().timeIntervalSince(startedAt)
            )
        }

        let duration = Date().timeIntervalSince(startedAt)
        publishScanProgress(
            artifacts: scannedArtifacts,
            deniedRoots: denied,
            visited: visited,
            duration: duration
        )
        phase = .done(visited: visited, duration: duration)
    }

    // MARK: - Derived

    var filteredArtifacts: [Artifact] {
        artifacts
            .filter { matchesFilters($0, includeCategory: true, includeSource: true) }
            .sorted(by: sortOrder.compare)
    }

    /// Map of category -> count for sidebar badges (respecting current
    /// source/custom/search filters but ignoring the category filter so the
    /// other badges stay visible).
    var sidebarCounts: [ArtifactCategory: Int] {
        var counts: [ArtifactCategory: Int] = [:]
        for artifact in artifacts {
            guard matchesFilters(artifact, includeCategory: false, includeSource: true) else { continue }
            counts[artifact.category, default: 0] += 1
        }
        return counts
    }

    /// Map of source -> count for the Sources section of the sidebar.
    var sourceCounts: [ArtifactSource: Int] {
        var counts: [ArtifactSource: Int] = [:]
        for artifact in artifacts {
            guard matchesFilters(artifact, includeCategory: true, includeSource: false) else { continue }
            counts[artifact.source, default: 0] += 1
        }
        return counts
    }

    /// Count for the "All Categories" row, respecting every filter except the
    /// current category selection.
    var categoryScopeCount: Int {
        artifacts.filter { matchesFilters($0, includeCategory: false, includeSource: true) }.count
    }

    /// Count for the "All Sources" row, respecting every filter except the
    /// current source selection.
    var sourceScopeCount: Int {
        artifacts.filter { matchesFilters($0, includeCategory: true, includeSource: false) }.count
    }

    var selectedArtifact: Artifact? {
        guard let id = selectedArtifactID else { return nil }
        return artifacts.first { $0.id == id }
    }

    // MARK: - Overrides

    func setCustomOverride(_ url: URL, isCustom: Bool?) {
        var overrides = customOverrides
        if let isCustom {
            overrides[url.path(percentEncoded: false)] = isCustom
        } else {
            overrides.removeValue(forKey: url.path(percentEncoded: false))
        }
        customOverrides = overrides
        Task { await rescan() }
    }

    private func publishScanProgress(
        artifacts scannedArtifacts: [Artifact],
        deniedRoots: [URL],
        visited: Int,
        duration: TimeInterval
    ) {
        let mcps = mcpExtractor.extract(from: scannedArtifacts)
        let combined = dedupe(scannedArtifacts + mcps).sorted { a, b in
            // First by category order (matches sidebar), then by modified date desc.
            if a.category != b.category {
                return a.category.rawValue < b.category.rawValue
            }
            return a.modifiedAt > b.modifiedAt
        }

        artifacts = combined
        self.deniedRoots = deniedRoots
        lastVisitedCount = visited
        lastScanDuration = duration

        if let selectedArtifactID, combined.contains(where: { $0.id == selectedArtifactID }) {
            return
        }
        selectedArtifactID = filteredArtifacts.first?.id ?? combined.first?.id
    }

    private func dedupe(_ artifacts: [Artifact]) -> [Artifact] {
        var seen = Set<String>()
        var out: [Artifact] = []
        out.reserveCapacity(artifacts.count)
        for artifact in artifacts where seen.insert(artifact.id).inserted {
            out.append(artifact)
        }
        return out
    }

    func setScanRootEnabled(_ root: ScanRoot, isEnabled: Bool) {
        guard let index = scanRoots.firstIndex(where: { $0.id == root.id }),
              scanRoots[index].isEnabled != isEnabled else { return }
        scanRoots[index].isEnabled = isEnabled
        var states = preferences.dictionary(forKey: Self.rootEnabledKey) as? [String: Bool] ?? [:]
        states[root.id] = isEnabled
        preferences.set(states, forKey: Self.rootEnabledKey)
        Task { await rescan() }
    }

    // MARK: - Custom scan roots

    @discardableResult
    func addCustomScanRoot(_ url: URL) -> Bool {
        let root = Self.customRoot(for: url)
        guard !scanRoots.contains(where: { $0.id == root.id }) else { return false }

        scanRoots.append(root)
        saveCustomRootsFromState()
        Task { await rescan() }
        return true
    }

    func removeCustomScanRoot(_ root: ScanRoot) {
        guard root.isUserAdded else { return }
        scanRoots.removeAll { $0.id == root.id && $0.isUserAdded }
        var states = preferences.dictionary(forKey: Self.rootEnabledKey) as? [String: Bool] ?? [:]
        states.removeValue(forKey: root.id)
        preferences.set(states, forKey: Self.rootEnabledKey)
        saveCustomRootsFromState()
        Task { await rescan() }
    }

    // MARK: - Filtering

    private func matchesFilters(
        _ artifact: Artifact,
        includeCategory: Bool,
        includeSource: Bool
    ) -> Bool {
        if includeCategory, let selectedCategory, artifact.category != selectedCategory {
            return false
        }
        if includeSource, let selectedSource, artifact.source != selectedSource {
            return false
        }
        if showCustomOnly, !artifact.isCustom {
            return false
        }
        return matchesSearch(artifact)
    }

    private func matchesSearch(_ artifact: Artifact) -> Bool {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return true }

        return artifact.title.localizedCaseInsensitiveContains(query)
            || (artifact.subtitle?.localizedCaseInsensitiveContains(query) ?? false)
            || artifact.url.path(percentEncoded: false).localizedCaseInsensitiveContains(query)
            || artifact.tags.contains(where: { $0.localizedCaseInsensitiveContains(query) })
            || (artifact.metadata.author?.localizedCaseInsensitiveContains(query) ?? false)
            || (artifact.metadata.version?.localizedCaseInsensitiveContains(query) ?? false)
            || (artifact.metadata.marketplace?.localizedCaseInsensitiveContains(query) ?? false)
            || (artifact.metadata.plugin?.localizedCaseInsensitiveContains(query) ?? false)
            || (artifact.metadata.repoURL?.absoluteString.localizedCaseInsensitiveContains(query) ?? false)
    }

    // MARK: - UserDefaults

    private static let rootEnabledKey = "com.oliverames.AgentVault.scanRootEnabled"
    private static let overridesKey = "com.oliverames.AgentVault.customOverrides"
    private static let customRootsKey = "com.oliverames.AgentVault.customScanRoots"

    private func loadOverrides() -> [String: Bool] {
        preferences.dictionary(forKey: Self.overridesKey) as? [String: Bool] ?? [:]
    }

    private func saveOverrides(_ value: [String: Bool]) {
        preferences.set(value, forKey: Self.overridesKey)
    }

    private static func mergedRoots(defaults: [ScanRoot], customPaths: [String]) -> [ScanRoot] {
        var seen = Set(defaults.map(\.id))
        var roots = defaults

        for path in customPaths {
            let root = customRoot(for: URL(fileURLWithPath: path, isDirectory: true))
            guard seen.insert(root.id).inserted else { continue }
            roots.append(root)
        }
        return roots
    }

    private static func customRoot(for url: URL) -> ScanRoot {
        ScanRoot(
            url: url,
            displayName: displayName(for: url),
            isCanonical: true,
            isUserAdded: true
        )
    }

    private static func displayName(for url: URL) -> String {
        var path = url.standardizedFileURL.path(percentEncoded: false)
        let home = NSHomeDirectory()
        if path.hasPrefix(home) {
            path = "~" + path.dropFirst(home.count)
        }
        return path.replacingOccurrences(
            of: "~/Library/Mobile Documents/com~apple~CloudDocs",
            with: "~/iCloud"
        )
    }

    private func saveCustomRootsFromState() {
        let paths = scanRoots
            .filter(\.isUserAdded)
            .map { $0.url.path(percentEncoded: false) }
        preferences.set(paths, forKey: Self.customRootsKey)
    }
}
