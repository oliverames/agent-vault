import SwiftUI
import AppKit

/// Modal editor sheet with mtime-based external-change detection.
///
/// On Save, the buffer re-reads the file's mtime and refuses to overwrite if
/// it changed since the user opened the editor — surfacing a conflict alert
/// instead. This guards against silent overwrites from concurrent Claude
/// sessions that write the same file (auto-memory consolidation, .remember
/// hook, dream pass).
struct EditorView: View {
    let artifact: Artifact
    let onClose: () -> Void

    @State private var buffer: FileBuffer
    @State private var conflictMtime: Date?
    @State private var errorMessage: String?

    init(artifact: Artifact, onClose: @escaping () -> Void) {
        self.artifact = artifact
        self.onClose = onClose
        _buffer = State(initialValue: FileBuffer(url: artifact.url))
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            editor
            Divider()
            footer
        }
        .task { buffer.load() }
        .alert("File changed on disk", isPresented: conflictBinding) {
            Button("Reload from disk", role: .destructive) {
                conflictMtime = nil
                buffer.reload()
            }
            Button("Overwrite anyway") {
                conflictMtime = nil
                let outcome = buffer.save(force: true)
                handle(outcome)
            }
            Button("Cancel", role: .cancel) {
                conflictMtime = nil
            }
        } message: {
            Text("The file was modified by another process at \(formatted(conflictMtime ?? .now)). Your local edits are still in the editor.")
        }
        .alert("Couldn't save", isPresented: errorBinding) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    // MARK: - Sections

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: artifact.category.sfSymbol).foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 1) {
                Text(artifact.title).font(.headline)
                Text(displayPath(artifact.url))
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.head)
            }
            Spacer()
            if buffer.isDirty {
                Text("Unsaved changes")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var editor: some View {
        ZStack(alignment: .topLeading) {
            switch buffer.state {
            case .idle:
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .loaded:
                SourceEditorView(
                    text: bindingForText,
                    isMarkdown: artifact.url.pathExtension.lowercased() == "md"
                )
            case .error(let message):
                ContentUnavailableView(
                    "Couldn't load file",
                    systemImage: "exclamationmark.triangle",
                    description: Text(message)
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var footer: some View {
        HStack {
            Button("Cancel", role: .cancel) {
                onClose()
            }
            Button("Reload from Disk") {
                buffer.reload()
            }
            .disabled(buffer.state != .loaded)

            Spacer()

            Text(editorStats)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)

            Button("Save") { saveTapped() }
                .buttonStyle(.glassProminent)
                .keyboardShortcut("s", modifiers: [.command])
                .disabled(!buffer.isDirty)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - Actions

    private func saveTapped() {
        let outcome = buffer.save()
        handle(outcome)
    }

    private func handle(_ outcome: FileBuffer.SaveOutcome) {
        switch outcome {
        case .saved:
            onClose()
        case .conflict(let diskMtime):
            conflictMtime = diskMtime
        case .error(let message):
            errorMessage = message
        }
    }

    // MARK: - Bindings

    private var bindingForText: Binding<String> {
        Binding(
            get: { buffer.text },
            set: { buffer.text = $0 }
        )
    }

    private var conflictBinding: Binding<Bool> {
        Binding(get: { conflictMtime != nil }, set: { if !$0 { conflictMtime = nil } })
    }

    private var errorBinding: Binding<Bool> {
        Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
    }

    private var editorStats: String {
        let lines = max(1, buffer.text.split(separator: "\n", omittingEmptySubsequences: false).count)
        return "\(lines) line\(lines == 1 ? "" : "s")"
    }

    // MARK: - Formatting

    private func displayPath(_ url: URL) -> String {
        var p = url.path(percentEncoded: false)
        let home = NSHomeDirectory()
        if p.hasPrefix(home) { p = "~" + p.dropFirst(home.count) }
        return p
    }

    private func formatted(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateStyle = .short
        f.timeStyle = .medium
        return f.string(from: date)
    }
}
