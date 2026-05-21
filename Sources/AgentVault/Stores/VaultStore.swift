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
    var showCustomOnly: Bool = false
    var showCached: Bool = false {
        didSet { Task { await rescan() } }
    }
    var selectedArtifactID: Artifact.ID? = nil

    // MARK: - Roots / heuristic

    private(set) var scanRoots: [ScanRoot]
    private(set) var heuristic: IsCustomHeuristic
    private var customOverrides: [String: Bool] {
        get { Self.loadOverrides() }
        set { Self.saveOverrides(newValue); heuristic = IsCustomHeuristic.defaults(overrides: newValue) }
    }

    // MARK: - Workers

    private let scanner: Scanner
    private let mcpExtractor = McpExtractor()

    // MARK: - Init

    init() {
        let overrides = Self.loadOverrides()
        let heuristic = IsCustomHeuristic.defaults(overrides: overrides)
        self.scanRoots = ScanRoot.defaults()
        self.heuristic = heuristic
        self.scanner = Scanner(classifier: ArtifactClassifier(heuristic: heuristic))
    }

    // MARK: - Scan

    /// Run a fresh scan over the active roots.
    func rescan() async {
        phase = .scanning
        let activeRoots = scanRoots.filter { $0.isCanonical || showCached }
        // When caches are opted in, list them as forceWalk so the parent-child
        // pruner doesn't skip them when they're the explicit target root.
        let forceWalk = showCached
            ? scanRoots.filter { !$0.isCanonical }.map(\.url)
            : []
        let result = await scanner.scan(roots: activeRoots, forceWalk: forceWalk)
        let mcps = mcpExtractor.extract(from: result.artifacts)
        let combined = (result.artifacts + mcps).sorted { a, b in
            // First by category order (matches sidebar), then by modified date desc.
            if a.category != b.category {
                return a.category.rawValue < b.category.rawValue
            }
            return a.modifiedAt > b.modifiedAt
        }
        artifacts = combined
        deniedRoots = result.deniedRoots
        lastVisitedCount = result.visitedCount
        lastScanDuration = result.duration
        phase = .done(visited: result.visitedCount, duration: result.duration)
    }

    // MARK: - Derived

    var filteredArtifacts: [Artifact] {
        var items = artifacts
        if let cat = selectedCategory {
            items = items.filter { $0.category == cat }
        }
        if let src = selectedSource {
            items = items.filter { $0.source == src }
        }
        if showCustomOnly {
            items = items.filter { $0.isCustom }
        }
        let q = searchText.trimmingCharacters(in: .whitespaces)
        if !q.isEmpty {
            items = items.filter {
                $0.title.localizedCaseInsensitiveContains(q)
                || ($0.subtitle?.localizedCaseInsensitiveContains(q) ?? false)
                || $0.tags.contains(where: { $0.localizedCaseInsensitiveContains(q) })
            }
        }
        return items
    }

    /// Map of category -> count for sidebar badges (respecting current
    /// source/custom/search filters but ignoring the category filter so the
    /// other badges stay visible).
    var sidebarCounts: [ArtifactCategory: Int] {
        var counts: [ArtifactCategory: Int] = [:]
        for artifact in artifacts {
            if let src = selectedSource, artifact.source != src { continue }
            if showCustomOnly, !artifact.isCustom { continue }
            counts[artifact.category, default: 0] += 1
        }
        return counts
    }

    /// Map of source -> count for the Sources section of the sidebar.
    var sourceCounts: [ArtifactSource: Int] {
        var counts: [ArtifactSource: Int] = [:]
        for artifact in artifacts {
            counts[artifact.source, default: 0] += 1
        }
        return counts
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

    // MARK: - UserDefaults

    private static let overridesKey = "com.oliverames.AgentVault.customOverrides"

    private static func loadOverrides() -> [String: Bool] {
        UserDefaults.standard.dictionary(forKey: overridesKey) as? [String: Bool] ?? [:]
    }

    private static func saveOverrides(_ value: [String: Bool]) {
        UserDefaults.standard.set(value, forKey: overridesKey)
    }
}
