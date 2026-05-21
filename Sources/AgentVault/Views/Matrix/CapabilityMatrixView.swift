import SwiftUI

/// Read-only coverage matrix inspired by cross-agent capability dashboards.
/// It only reflects artifacts Agent Vault actually scanned, so Beta 1 avoids
/// unreliable toggles or config mutation across runtimes.
struct CapabilityMatrixView: View {
    @Environment(VaultStore.self) private var store
    @State private var category: ArtifactCategory = .skill

    private let visibleCategories: [ArtifactCategory] = [.skill, .plugin, .mcp]

    var body: some View {
        VStack(spacing: 0) {
            matrixHeader
            Divider()
            if rows.isEmpty {
                emptyState
            } else {
                CapabilityMatrixColumnHeader()
                    .frame(minWidth: 760)
                    .background(Color.primary.opacity(0.035))
                ScrollView([.vertical, .horizontal]) {
                    VStack(spacing: 0) {
                        ForEach(rows) { row in
                            CapabilityMatrixRow(row: row) {
                                store.selectedArtifactID = row.preferredArtifact?.id
                            }
                        }
                    }
                    .frame(minWidth: 760)
                }
            }
        }
        .navigationTitle("Coverage")
        .navigationSubtitle("\(rows.count) \(category.displayName.lowercased())")
        .onAppear {
            if let selected = store.selectedCategory, visibleCategories.contains(selected) {
                category = selected
            }
        }
        .onChange(of: store.selectedCategory) { _, newValue in
            if let newValue, visibleCategories.contains(newValue) {
                category = newValue
            }
        }
    }

    private var matrixHeader: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("Capability type", selection: $category) {
                Text("Skills").tag(ArtifactCategory.skill)
                Text("Plugins").tag(ArtifactCategory.plugin)
                Text("MCP Servers").tag(ArtifactCategory.mcp)
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 360)

            HStack(spacing: 14) {
                Label("\(store.artifacts.count) scanned", systemImage: "tray.full")
                if store.showCustomOnly {
                    Label("custom only", systemImage: "person.crop.circle")
                }
                if store.showCached {
                    Label("caches included", systemImage: "externaldrive")
                }
                Spacer()
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No coverage rows", systemImage: "rectangle.grid.3x2")
        } description: {
            Text(store.phase == .scanning
                 ? "Scanning your AI runtimes..."
                 : "Try a different capability type or clear the current filters.")
        }
    }

    private var rows: [CapabilityMatrixEntry] {
        var artifacts = store.artifacts.filter { $0.category == category }
        if let source = store.selectedSource {
            artifacts = artifacts.filter { $0.source == source }
        }
        if store.showCustomOnly {
            artifacts = artifacts.filter(\.isCustom)
        }
        let query = store.searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !query.isEmpty {
            artifacts = artifacts.filter { artifact in
                artifact.title.localizedCaseInsensitiveContains(query)
                    || (artifact.subtitle?.localizedCaseInsensitiveContains(query) ?? false)
                    || artifact.tags.contains { $0.localizedCaseInsensitiveContains(query) }
                    || (artifact.metadata.plugin?.localizedCaseInsensitiveContains(query) ?? false)
                    || (artifact.metadata.marketplace?.localizedCaseInsensitiveContains(query) ?? false)
            }
        }

        let grouped = Dictionary(grouping: artifacts, by: groupingKey(for:))
        return grouped.values.map { CapabilityMatrixEntry(category: category, artifacts: $0) }
            .sorted { lhs, rhs in
                if lhs.isCustom != rhs.isCustom { return lhs.isCustom && !rhs.isCustom }
                if lhs.coveredSourceCount != rhs.coveredSourceCount { return lhs.coveredSourceCount > rhs.coveredSourceCount }
                return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
            }
    }

    private func groupingKey(for artifact: Artifact) -> String {
        switch artifact.category {
        case .plugin:
            artifact.metadata.plugin ?? artifact.title
        case .marketplace:
            artifact.metadata.marketplace ?? artifact.title
        default:
            artifact.title
        }
    }
}

private struct CapabilityMatrixEntry: Identifiable {
    let category: ArtifactCategory
    let artifacts: [Artifact]

    var id: String { "\(category.rawValue):\(title.lowercased())" }

    var title: String {
        artifacts.first?.metadata.plugin
            ?? artifacts.first?.metadata.marketplace
            ?? artifacts.first?.title
            ?? "Untitled"
    }

    var subtitle: String {
        let labels = Set(artifacts.compactMap { artifact in
            artifact.metadata.marketplace ?? artifact.metadata.plugin ?? artifact.subtitle
        })
        return labels.sorted().prefix(2).joined(separator: " / ")
    }

    var isCustom: Bool {
        artifacts.contains(where: \.isCustom)
    }

    var coveredSourceCount: Int {
        Set(artifacts.map(\.source)).count
    }

    var preferredArtifact: Artifact? {
        artifacts.sorted { lhs, rhs in
            if lhs.isCustom != rhs.isCustom { return lhs.isCustom && !rhs.isCustom }
            return lhs.modifiedAt > rhs.modifiedAt
        }.first
    }

    func artifacts(for source: ArtifactSource) -> [Artifact] {
        artifacts.filter { $0.source == source }
    }
}

private struct CapabilityMatrixColumnHeader: View {
    var body: some View {
        HStack(spacing: 12) {
            Text("Capability")
                .frame(width: 245, alignment: .leading)
            Text("Type")
                .frame(width: 58, alignment: .leading)
            ForEach(ArtifactSource.allCases) { source in
                Text(source.rawValue)
                    .lineLimit(1)
                    .frame(width: 76)
            }
            Text("Status")
                .frame(width: 72, alignment: .leading)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(.primary)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
}

private struct CapabilityMatrixRow: View {
    let row: CapabilityMatrixEntry
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                capabilityCell
                    .frame(width: 245, alignment: .leading)
                Text(row.category.displayName.dropTrailingPlural)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(width: 58, alignment: .leading)
                ForEach(ArtifactSource.allCases) { source in
                    SourceCoverageCell(artifacts: row.artifacts(for: source))
                        .frame(width: 76)
                }
                statusCell
                    .frame(width: 72, alignment: .leading)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 9)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        Divider()
            .padding(.leading, 16)
    }

    private var capabilityCell: some View {
        HStack(spacing: 10) {
            Image(systemName: row.category.sfSymbol)
                .foregroundStyle(.tint)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(row.title)
                        .font(.body.weight(.semibold))
                        .lineLimit(1)
                    if row.isCustom {
                        Text("CUSTOM")
                            .font(.caption2.bold())
                            .foregroundStyle(.white)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(.tint, in: Capsule())
                    }
                }
                if !row.subtitle.isEmpty {
                    Text(row.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
        }
    }

    private var statusCell: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(row.isCustom ? Color.accentColor : Color.green)
                .frame(width: 7, height: 7)
            Text(row.isCustom ? "Authored" : "Installed")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }
}

private struct SourceCoverageCell: View {
    let artifacts: [Artifact]

    var body: some View {
        if artifacts.isEmpty {
            Image(systemName: "minus")
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity)
                .accessibilityLabel("Not present")
        } else {
            HStack(spacing: 4) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.tint)
                if artifacts.count > 1 {
                    Text("\(artifacts.count)")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity)
            .help(artifacts.map { $0.subtitle ?? $0.url.lastPathComponent }.joined(separator: "\n"))
        }
    }
}

private extension String {
    var dropTrailingPlural: String {
        hasSuffix("s") ? String(dropLast()) : self
    }
}
