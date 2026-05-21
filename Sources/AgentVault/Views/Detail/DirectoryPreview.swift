import SwiftUI
import AppKit

/// Detail view for directory-backed artifacts (`.remember/`, Claude
/// auto-memory `memory/`). Lists immediate children with a quick-look
/// preview of the selected child's contents.
struct DirectoryPreview: View {
    let url: URL
    @State private var children: [Child] = []
    @State private var selectedChild: Child.ID?
    @State private var error: String?

    struct Child: Identifiable, Hashable {
        let id: String
        let url: URL
        let name: String
        let modified: Date
        let size: Int64
        var modifiedFormatted: String {
            let f = RelativeDateTimeFormatter()
            f.unitsStyle = .short
            return f.localizedString(for: modified, relativeTo: .now)
        }
        var sizeFormatted: String {
            ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
        }
    }

    var body: some View {
        HSplitView {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("Files").font(.caption.bold()).foregroundStyle(.secondary)
                    Spacer()
                    Text("\(children.count)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 12).padding(.vertical, 8)

                if let error {
                    Text(error).foregroundStyle(.red).padding()
                } else {
                    List(selection: $selectedChild) {
                        ForEach(children) { child in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(child.name).font(.callout.weight(.medium))
                                HStack(spacing: 8) {
                                    Text(child.modifiedFormatted)
                                    Text("•")
                                    Text(child.sizeFormatted)
                                }
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.secondary)
                            }
                            .tag(child.id)
                            .padding(.vertical, 2)
                        }
                    }
                    .listStyle(.inset)
                }
            }
            .frame(minWidth: 240, idealWidth: 280)

            if let child = currentChild {
                if child.url.pathExtension.lowercased() == "md" {
                    MarkdownPreview(url: child.url)
                } else {
                    PlainTextPreview(url: child.url)
                }
            } else {
                ContentUnavailableView("Pick a file", systemImage: "doc.text")
            }
        }
        .task(id: url) { load() }
    }

    private var currentChild: Child? {
        children.first(where: { $0.id == selectedChild })
    }

    private func load() {
        let fm = FileManager.default
        let path = url.path(percentEncoded: false)
        do {
            let entries = try fm.contentsOfDirectory(at: url,
                                                     includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey, .isRegularFileKey])
            let regular = entries.compactMap { entryURL -> Child? in
                let values = try? entryURL.resourceValues(forKeys: [.isRegularFileKey, .contentModificationDateKey, .fileSizeKey])
                guard values?.isRegularFile == true else { return nil }
                return Child(
                    id: entryURL.path(percentEncoded: false),
                    url: entryURL,
                    name: entryURL.lastPathComponent,
                    modified: values?.contentModificationDate ?? .distantPast,
                    size: Int64(values?.fileSize ?? 0)
                )
            }
            children = regular.sorted { $0.modified > $1.modified }
            selectedChild = children.first?.id
            error = nil
            _ = path
        } catch {
            self.error = "Couldn't list directory: \(error.localizedDescription)"
        }
    }
}
