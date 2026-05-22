import SwiftUI
import AppKit

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
        .safeAreaInset(edge: .top) {
            listControls(count: items.count)
        }
        .onAppear {
            selectFirstIfNeeded(visibleIDs: items.map(\.id))
        }
        .onChange(of: items.map(\.id)) { _, ids in
            selectFirstIfNeeded(visibleIDs: ids)
        }
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
                artifactRow(artifact)
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
                        artifactRow(artifact)
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
                        artifactRow(artifact)
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
                        artifactRow(artifact)
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

    private func listControls(count: Int) -> some View {
        @Bindable var bindable = store

        return HStack(spacing: 10) {
            Label("\(count)", systemImage: "tray.full")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)

            if hasActiveFilters {
                Button {
                    clearFilters()
                } label: {
                    Label("Clear", systemImage: "xmark.circle")
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
            }

            Spacer()

            Picker("Sort", selection: $bindable.sortOrder) {
                ForEach(ArtifactSortOrder.allCases) { order in
                    Text(order.rawValue).tag(order)
                }
            }
            .pickerStyle(.menu)
            .controlSize(.small)
            .frame(width: 168)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.bar)
    }

    @ViewBuilder
    private func artifactRow(_ artifact: Artifact) -> some View {
        ArtifactRowView(artifact: artifact)
            .tag(artifact.id)
            .contextMenu {
                Button {
                    NSWorkspace.shared.activateFileViewerSelecting([artifact.url])
                } label: {
                    Label("Reveal in Finder", systemImage: "folder")
                }

                Button {
                    NSWorkspace.shared.open(artifact.url)
                } label: {
                    Label("Open", systemImage: "arrow.up.right.square")
                }

                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(artifact.url.path(percentEncoded: false), forType: .string)
                } label: {
                    Label("Copy Path", systemImage: "document.on.document")
                }
            }
    }

    private var hasActiveFilters: Bool {
        store.selectedCategory != nil
            || store.selectedSource != nil
            || store.showCustomOnly
            || !store.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func clearFilters() {
        store.selectedCategory = nil
        store.selectedSource = nil
        store.showCustomOnly = false
        store.searchText = ""
    }

    private func selectFirstIfNeeded(visibleIDs: [Artifact.ID]) {
        guard !visibleIDs.isEmpty else {
            store.selectedArtifactID = nil
            return
        }
        if let selected = store.selectedArtifactID, visibleIDs.contains(selected) {
            return
        }
        store.selectedArtifactID = visibleIDs.first
    }
}
