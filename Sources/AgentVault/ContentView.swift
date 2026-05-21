import SwiftUI

private enum VaultViewMode: String, CaseIterable, Identifiable {
    case inventory = "Inventory"
    case coverage = "Coverage"

    var id: String { rawValue }
}

struct ContentView: View {
    @Environment(VaultStore.self) private var store
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var mode: VaultViewMode = .inventory

    var body: some View {
        splitView
        .searchable(text: searchBinding(), placement: .toolbar, prompt: "Search artifacts…")
        .toolbar {
            ToolbarItem(placement: .principal) {
                Picker("View", selection: $mode) {
                    ForEach(VaultViewMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 240)
            }
        }
        .overlay(alignment: .top) {
            PermissionBanner()
                .padding(.top, 8)
        }
    }

    @ViewBuilder
    private var splitView: some View {
        switch mode {
        case .inventory:
            NavigationSplitView(columnVisibility: $columnVisibility) {
                SidebarView()
                    .navigationSplitViewColumnWidth(min: 220, ideal: 240, max: 320)
            } content: {
                ArtifactListView()
                    .navigationSplitViewColumnWidth(min: 280, ideal: 360)
            } detail: {
                ArtifactDetailView()
            }
        case .coverage:
            NavigationSplitView(columnVisibility: $columnVisibility) {
                SidebarView()
                    .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 340)
            } detail: {
                CapabilityMatrixView()
            }
        }
    }

    private func searchBinding() -> Binding<String> {
        @Bindable var s = store
        return $s.searchText
    }
}
