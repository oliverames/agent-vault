import SwiftUI
import AppKit

struct ArtifactDetailView: View {
    @Environment(VaultStore.self) private var store
    @State private var editing = false

    var body: some View {
        Group {
            if let artifact = store.selectedArtifact {
                detail(for: artifact)
            } else {
                emptyState
            }
        }
        .navigationTitle(store.selectedArtifact?.title ?? "Agent Vault")
    }

    @ViewBuilder
    private func detail(for artifact: Artifact) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            headerBar(for: artifact)
            if hasProvenance(artifact) {
                provenanceStrip(for: artifact)
            }
            Divider()
            content(for: artifact)
            Divider()
            metadataFooter(for: artifact)
        }
        .sheet(isPresented: $editing) {
            EditorView(artifact: artifact, onClose: { editing = false })
                .frame(minWidth: 700, minHeight: 500)
        }
    }

    private func hasProvenance(_ a: Artifact) -> Bool {
        a.metadata.author != nil
            || a.metadata.version != nil
            || a.metadata.marketplace != nil
            || a.metadata.plugin != nil
            || a.metadata.repoURL != nil
            || a.metadata.isBundled
            || !a.metadata.installedInto.isEmpty
    }

    @ViewBuilder
    private func provenanceStrip(for a: Artifact) -> some View {
        let m = a.metadata
        HStack(spacing: 10) {
            if a.isCustom {
                provenanceChip(icon: "person.crop.circle.fill", text: "Authored by you", tint: .accentColor)
            }
            if m.isBundled {
                provenanceChip(icon: "shippingbox.fill", text: "Bundled", tint: .blue)
            }
            if let author = m.author {
                provenanceChip(icon: "person", text: author, tint: .secondary)
            }
            if let version = m.version {
                provenanceChip(icon: "tag", text: "v\(version)", tint: .secondary)
            }
            if let marketplace = m.marketplace, a.category != .marketplace {
                provenanceChip(icon: "storefront", text: marketplace, tint: .secondary)
            }
            if let plugin = m.plugin, a.category != .plugin {
                provenanceChip(icon: "puzzlepiece.extension", text: plugin, tint: .secondary)
            }
            if !m.installedInto.isEmpty {
                provenanceChip(
                    icon: "arrow.down.app",
                    text: "Installed in: " + m.installedInto.map(\.rawValue).joined(separator: ", "),
                    tint: .green
                )
            }
            if let repo = m.repoURL {
                Link(destination: repo) {
                    HStack(spacing: 4) {
                        Image(systemName: "link")
                        Text(shortRepoLabel(repo))
                    }
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(.quaternary, in: Capsule())
                }
                .buttonStyle(.plain)
                .help(repo.absoluteString)
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.bar)
    }

    private func provenanceChip(icon: String, text: String, tint: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
            Text(text)
        }
        .font(.caption)
        .foregroundStyle(tint)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(tint.opacity(0.12), in: Capsule())
    }

    private func shortRepoLabel(_ url: URL) -> String {
        // For github.com/owner/repo, show "owner/repo"; else show host.
        let host = url.host(percentEncoded: false) ?? "link"
        let path = url.path(percentEncoded: false).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if host.contains("github.com"), !path.isEmpty {
            return path
        }
        return host
    }

    private var emptyState: some View {
        ContentUnavailableView(
            "Select an artifact",
            systemImage: "doc.text.magnifyingglass",
            description: Text("Pick a skill, config file, or memory store from the list to view its contents here.")
        )
    }

    // MARK: - Header

    @ViewBuilder
    private func headerBar(for artifact: Artifact) -> some View {
        HStack(spacing: 12) {
            Image(systemName: artifact.category.sfSymbol)
                .font(.title2)
                .foregroundStyle(.tint)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(artifact.title).font(.title3.bold())
                if let subtitle = artifact.subtitle {
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            actionButtons(for: artifact)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    @ViewBuilder
    private func actionButtons(for artifact: Artifact) -> some View {
        GlassEffectContainer(spacing: 6) {
            HStack(spacing: 6) {
                Button {
                    NSWorkspace.shared.activateFileViewerSelecting([artifact.url])
                } label: {
                    Label("Reveal", systemImage: "folder")
                }
                .help("Reveal in Finder")

                Button {
                    NSWorkspace.shared.open(artifact.url)
                } label: {
                    Label("Open", systemImage: "arrow.up.right.square")
                }
                .help("Open in default app")

                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(artifact.url.path(percentEncoded: false), forType: .string)
                } label: {
                    Label("Copy Path", systemImage: "document.on.document")
                }
                .help("Copy file path")

                if !artifact.category.isDirectoryBacked {
                    Button {
                        editing = true
                    } label: {
                        Label("Edit", systemImage: "square.and.pencil")
                    }
                    .buttonStyle(.glassProminent)
                    .help("Edit in Agent Vault")
                }
            }
            .buttonStyle(.glass)
            .controlSize(.regular)
            .labelStyle(.iconOnly)
        }
    }

    // MARK: - Content

    @ViewBuilder
    private func content(for artifact: Artifact) -> some View {
        if artifact.category.isDirectoryBacked {
            DirectoryPreview(url: artifact.url)
        } else if artifact.url.pathExtension.lowercased() == "md" {
            MarkdownPreview(url: artifact.url)
        } else {
            PlainTextPreview(url: artifact.url)
        }
    }

    // MARK: - Footer

    @ViewBuilder
    private func metadataFooter(for artifact: Artifact) -> some View {
        HStack(spacing: 0) {
            // Meta chips scroll horizontally if the detail pane is narrow,
            // so labels never wrap or hyphenate.
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    ForEach(artifact.sources) { source in
                        metaItem(value: source.rawValue, icon: source.sfSymbol)
                    }
                    metaItem(value: artifact.modifiedFormatted, icon: "clock")
                    metaItem(value: artifact.sizeFormatted, icon: "scalemass")
                    metaItem(
                        value: artifact.isCustom ? "Custom" : "System",
                        icon: artifact.isCustom ? "person.crop.circle" : "gearshape"
                    )
                }
                .padding(.vertical, 2)
            }
            Spacer(minLength: 12)
            Text(displayPath(artifact.url))
                .font(.caption.monospaced())
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .truncationMode(.head)
                .textSelection(.enabled)
                .layoutPriority(-1)        // gives up width before the chips do
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    /// Compact metadata pill — icon + value, no label text. The icon
    /// communicates the field; tooltip on hover spells it out.
    private func metaItem(value: String, icon: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .foregroundStyle(.secondary)
                .font(.caption)
            Text(value)
                .font(.caption.monospacedDigit())
                .lineLimit(1)
        }
        .fixedSize()
    }

    private func displayPath(_ url: URL) -> String {
        var p = url.path(percentEncoded: false)
        let home = NSHomeDirectory()
        if p.hasPrefix(home) { p = "~" + p.dropFirst(home.count) }
        return p
    }
}
