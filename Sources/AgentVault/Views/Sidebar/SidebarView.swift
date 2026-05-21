import SwiftUI

struct SidebarView: View {
    @Environment(VaultStore.self) private var store

    var body: some View {
        @Bindable var bindable = store

        List {
            Section("Sources") {
                SourceRow(
                    label: "All Sources",
                    symbol: "circle.grid.2x2",
                    count: nil,
                    isSelected: store.selectedSource == nil
                ) {
                    store.selectedSource = nil
                }
                ForEach(ArtifactSource.allCases) { source in
                    SourceRow(
                        label: source.rawValue,
                        symbol: source.sfSymbol,
                        count: store.sourceCounts[source] ?? 0,
                        isSelected: store.selectedSource == source
                    ) {
                        store.selectedSource = (store.selectedSource == source) ? nil : source
                    }
                }
            }

            Section("Categories") {
                CategoryRow(
                    label: "All Categories",
                    symbol: "tray.2",
                    count: store.artifacts.count,
                    isSelected: store.selectedCategory == nil
                ) {
                    store.selectedCategory = nil
                }
                ForEach(ArtifactCategory.allCases) { category in
                    CategoryRow(
                        label: category.displayName,
                        symbol: category.sfSymbol,
                        count: store.sidebarCounts[category] ?? 0,
                        isSelected: store.selectedCategory == category
                    ) {
                        store.selectedCategory = (store.selectedCategory == category) ? nil : category
                    }
                }
            }

            Section("Filters") {
                Toggle("Custom only", isOn: $bindable.showCustomOnly)
                    .toggleStyle(.switch)
                Toggle("Include caches & marketplaces", isOn: $bindable.showCached)
                    .toggleStyle(.switch)
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom) {
            ScanStatusFooter()
        }
    }
}

// MARK: - Rows

private struct SourceRow: View {
    let label: String
    let symbol: String
    let count: Int?
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: symbol)
                    .frame(width: 18)
                    .foregroundStyle(.tint)
                Text(label)
                    .foregroundStyle(.primary)
                Spacer()
                if let count {
                    Text("\(count)")
                        .font(.callout)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.caption.bold())
                        .foregroundStyle(.tint)
                }
            }
            .contentShape(Rectangle())
            .padding(.vertical, 2)
        }
        .buttonStyle(.plain)
    }
}

private struct CategoryRow: View {
    let label: String
    let symbol: String
    let count: Int
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: symbol)
                    .frame(width: 18)
                    .foregroundStyle(isSelected ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.secondary))
                Text(label)
                    .foregroundStyle(.primary)
                    .fontWeight(isSelected ? .semibold : .regular)
                Spacer()
                Text("\(count)")
                    .font(.callout)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(isSelected ? Color.accentColor.opacity(0.18) : Color.gray.opacity(0.15),
                                in: Capsule())
            }
            .contentShape(Rectangle())
            .padding(.vertical, 2)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Status footer

private struct ScanStatusFooter: View {
    @Environment(VaultStore.self) private var store

    var body: some View {
        HStack(spacing: 10) {
            statusIcon
            VStack(alignment: .leading, spacing: 1) {
                Text(statusTitle)
                    .font(.callout)
                Text(statusDetail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                Task { await store.rescan() }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .help("Rescan")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.bar)
    }

    private var statusIcon: some View {
        Group {
            switch store.phase {
            case .scanning:
                ProgressView().controlSize(.small)
            case .done:
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
            case .failed:
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            case .idle:
                Image(systemName: "circle.dashed").foregroundStyle(.secondary)
            }
        }
        .frame(width: 18)
    }

    private var statusTitle: String {
        switch store.phase {
        case .idle: "Ready"
        case .scanning: "Scanning…"
        case .done: "\(store.artifacts.count) artifacts"
        case .failed(let msg): "Scan failed: \(msg)"
        }
    }

    private var statusDetail: String {
        switch store.phase {
        case .done(let visited, let duration):
            "\(visited) files in \(String(format: "%.1f", duration))s"
        default:
            ""
        }
    }
}
