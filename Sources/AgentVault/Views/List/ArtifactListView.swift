import SwiftUI

struct ArtifactListView: View {
    @Environment(VaultStore.self) private var store

    var body: some View {
        let items = store.filteredArtifacts

        Group {
            if items.isEmpty {
                emptyState
            } else if store.selectedCategory == nil {
                // No category filter → group by category for scannability.
                groupedList(items: items)
            } else if store.selectedCategory == .marketplace {
                // Marketplaces get a "Yours / Installed" split so the
                // user's authored marketplaces surface first.
                marketplaceGroupedList(items: items)
            } else {
                flatList(items: items)
            }
        }
        .navigationTitle(navTitle)
        .navigationSubtitle("\(items.count) item\(items.count == 1 ? "" : "s")")
    }

    private var navTitle: String {
        if let category = store.selectedCategory {
            return category.displayName
        }
        return "All Artifacts"
    }

    @ViewBuilder
    private var emptyState: some View {
        ContentUnavailableView {
            Label("Nothing matches", systemImage: "magnifyingglass")
        } description: {
            Text(store.phase == .scanning
                 ? "Scanning your AI runtimes…"
                 : "Try clearing filters or rescanning.")
        } actions: {
            Button("Rescan") {
                Task { await store.rescan() }
            }
            .buttonStyle(.glass)
        }
    }

    private func flatList(items: [Artifact]) -> some View {
        List(selection: Binding(
            get: { store.selectedArtifactID },
            set: { store.selectedArtifactID = $0 }
        )) {
            ForEach(items) { artifact in
                ArtifactRowView(artifact: artifact)
                    .tag(artifact.id)
            }
        }
        .listStyle(.inset)
    }

    private func groupedList(items: [Artifact]) -> some View {
        let groups = Dictionary(grouping: items, by: { $0.category })
        let ordered = ArtifactCategory.allCases.filter { groups[$0] != nil }

        return List(selection: Binding(
            get: { store.selectedArtifactID },
            set: { store.selectedArtifactID = $0 }
        )) {
            ForEach(ordered) { category in
                Section(category.displayName) {
                    ForEach(groups[category] ?? []) { artifact in
                        ArtifactRowView(artifact: artifact)
                            .tag(artifact.id)
                    }
                }
            }
        }
        .listStyle(.inset)
    }

    private func marketplaceGroupedList(items: [Artifact]) -> some View {
        let yours = items.filter { $0.isCustom }
        let installed = items.filter { !$0.isCustom }

        return List(selection: Binding(
            get: { store.selectedArtifactID },
            set: { store.selectedArtifactID = $0 }
        )) {
            if !yours.isEmpty {
                Section {
                    ForEach(yours) { artifact in
                        ArtifactRowView(artifact: artifact)
                            .tag(artifact.id)
                    }
                } header: {
                    HStack {
                        Image(systemName: "person.crop.circle.badge.checkmark")
                        Text("Your Marketplaces").fontWeight(.semibold)
                        Spacer()
                        Text("\(yours.count)").foregroundStyle(.secondary).monospacedDigit()
                    }
                }
            }
            if !installed.isEmpty {
                Section {
                    ForEach(installed) { artifact in
                        ArtifactRowView(artifact: artifact)
                            .tag(artifact.id)
                    }
                } header: {
                    HStack {
                        Image(systemName: "arrow.down.app")
                        Text("Installed Marketplaces").fontWeight(.semibold)
                        Spacer()
                        Text("\(installed.count)").foregroundStyle(.secondary).monospacedDigit()
                    }
                }
            }
        }
        .listStyle(.inset)
    }
}
