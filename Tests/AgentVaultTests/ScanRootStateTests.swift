import Foundation
import Testing
@testable import AgentVault

@Suite("Scan root enablement")
struct ScanRootStateTests {
    @Test("disabled roots are not visited, including through overlapping ancestors")
    func disabledRootsAreExcluded() async throws {
        let directory = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let paused = directory.appending(path: "paused")
        let sibling = directory.appending(path: "paused-sibling")
        for folder in [paused, sibling] {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try "# Instructions".write(to: folder.appending(path: "CLAUDE.md"), atomically: true, encoding: .utf8)
        }
        let scanner = Scanner(classifier: ArtifactClassifier(heuristic: IsCustomHeuristic(
            authoringRoots: [directory], installedRoots: [], excludeSegments: [], overrides: [:]
        )))
        var root = ScanRoot(url: paused, displayName: "Paused", isCanonical: true, isEnabled: false)
        let disabled = await scanner.scan(roots: [root], forceWalk: [paused])
        #expect(disabled.visitedCount == 0)
        #expect(disabled.artifacts.isEmpty)
        #expect(disabled.deniedRoots.isEmpty)

        let parent = ScanRoot(url: directory, displayName: "Parent", isCanonical: true)
        let overlap = await scanner.scan(roots: [parent, root], forceWalk: [paused])
        #expect(overlap.artifacts.map { $0.url.standardizedFileURL } == [sibling.appending(path: "CLAUDE.md").standardizedFileURL])

        root.isEnabled = true
        let resumed = await scanner.scan(roots: [root])
        #expect(resumed.artifacts.map { $0.url.standardizedFileURL } == [paused.appending(path: "CLAUDE.md").standardizedFileURL])
        #expect(resumed.visitedCount == 1)
    }

    @MainActor
    private func finishScan(_ store: VaultStore) async throws {
        await store.rescan()
        // A preference change can queue a newer scan while this one awaits the actor.
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while store.phase == .scanning && ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(1))
        }
        #expect(store.phase != .scanning)
    }

    @MainActor
    @Test("legacy custom paths survive and canonical and custom switches persist")
    func persistedStates() async throws {
        let suite = "AgentVaultTests.\(UUID().uuidString)"
        let preferences = try #require(UserDefaults(suiteName: suite))
        defer { preferences.removePersistentDomain(forName: suite) }
        let directory = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let canonical = ScanRoot(url: directory.appending(path: "canonical"), displayName: "Canonical", isCanonical: true)
        let customURL = directory.appending(path: "custom")
        let cache = ScanRoot(url: directory.appending(path: "cache"), displayName: "Cache", isCanonical: false)
        for folder in [canonical.url, customURL, cache.url] {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try "# Fixture".write(to: folder.appending(path: "CLAUDE.md"), atomically: true, encoding: .utf8)
        }
        let pathsKey = "com.oliverames.AgentVault.customScanRoots"
        preferences.set([customURL.path], forKey: pathsKey)
        let store = VaultStore(preferences: preferences, defaultRoots: [canonical, cache])
        #expect(store.scanRoots.count == 3)
        #expect(store.scanRoots.allSatisfy { $0.isEnabled })
        let custom = try #require(store.scanRoots.first { $0.isUserAdded })
        store.setScanRootEnabled(canonical, isEnabled: false)
        store.setScanRootEnabled(custom, isEnabled: false)
        try await finishScan(store)
        #expect(store.artifacts.isEmpty)
        #expect(preferences.stringArray(forKey: pathsKey) == [customURL.path])

        let reopened = VaultStore(preferences: preferences, defaultRoots: [canonical, cache])
        #expect(reopened.scanRoots.first { $0.id == canonical.id }?.isEnabled == false)
        #expect(reopened.scanRoots.first { $0.id == custom.id }?.isEnabled == false)
        #expect(reopened.scanRoots.first { $0.id == cache.id }?.isEnabled == true)
        reopened.setScanRootEnabled(custom, isEnabled: true)
        try await finishScan(reopened)
        #expect(reopened.artifacts.map { $0.url.standardizedFileURL } == [customURL.appending(path: "CLAUDE.md").standardizedFileURL])
        reopened.setScanRootEnabled(cache, isEnabled: false)
        reopened.showCached = true
        try await finishScan(reopened)
        #expect(reopened.artifacts.map { $0.url.standardizedFileURL } == [customURL.appending(path: "CLAUDE.md").standardizedFileURL])
        reopened.setScanRootEnabled(cache, isEnabled: true)
        try await finishScan(reopened)
        #expect(reopened.artifacts.count == 2)
        let finalStore = VaultStore(preferences: preferences, defaultRoots: [canonical, cache])
        #expect(finalStore.scanRoots.first { $0.id == custom.id }?.isEnabled == true)
        finalStore.setScanRootEnabled(custom, isEnabled: false)
        finalStore.removeCustomScanRoot(custom)
        #expect(finalStore.addCustomScanRoot(customURL))
        try await finishScan(finalStore)
        let afterReadd = VaultStore(preferences: preferences, defaultRoots: [canonical, cache])
        #expect(afterReadd.scanRoots.first { $0.id == custom.id }?.isEnabled == true)
    }
}
