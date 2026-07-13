import SwiftUI
import AppKit

struct VaultOperationsView: View {
    @Environment(VaultStore.self) private var store
    @State private var isRunning = false
    @State private var message: OperationMessage?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                operationsGrid
                if let message {
                    OperationResultView(message: message)
                }
            }
            .padding(24)
            .frame(maxWidth: 900, alignment: .leading)
        }
        .navigationTitle("Operations")
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "shippingbox.and.arrow.backward")
                .font(.title2)
                .foregroundStyle(.tint)
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text("Export, Backup, Restore")
                    .font(.title2.bold())
                Text("\(store.artifacts.count) scanned artifacts, \(store.filteredArtifacts.count) in the current view")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if isRunning {
                ProgressView()
                    .controlSize(.small)
            }
        }
    }

    private var operationsGrid: some View {
        Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 14) {
            GridRow {
                operationGroup(
                    title: "Clean Export",
                    symbol: "folder.badge.plus",
                    detail: "Readable folders with common secrets redacted. Review the result before sharing it."
                ) {
                    HStack {
                        Button {
                            cleanExport(artifacts: store.filteredArtifacts, label: "Visible Clean Export")
                        } label: {
                            Label("Visible", systemImage: "line.3.horizontal.decrease.circle")
                        }
                        .buttonStyle(.bordered)
                        Button {
                            cleanExport(artifacts: store.artifacts, label: "Full Clean Export")
                        } label: {
                            Label("All", systemImage: "tray.full")
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }

                operationGroup(
                    title: "Backup",
                    symbol: "archivebox",
                    detail: "Exact, unredacted copies for restoring original paths. Store backups securely."
                ) {
                    Button {
                        createBackup()
                    } label: {
                        Label("Create Backup", systemImage: "archivebox")
                    }
                    .buttonStyle(.borderedProminent)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            GridRow {
                operationGroup(
                    title: "Restore",
                    symbol: "arrow.uturn.backward.circle",
                    detail: "Restore only a backup you trust. Existing files are skipped unless overwrite is confirmed."
                ) {
                    HStack {
                        Button {
                            restoreBackup(overwriteExisting: false)
                        } label: {
                            Label("Restore Missing", systemImage: "arrow.down.doc")
                        }
                        .buttonStyle(.borderedProminent)
                        Button(role: .destructive) {
                            guard confirmOverwriteRestore() else { return }
                            restoreBackup(overwriteExisting: true)
                        } label: {
                            Label("Restore & Overwrite", systemImage: "exclamationmark.arrow.trianglehead.2.clockwise.rotate.90")
                        }
                        .buttonStyle(.bordered)
                        .tint(.red)
                    }
                }

                operationGroup(
                    title: "Memory",
                    symbol: "brain",
                    detail: "Create an unredacted export or a non-destructive merged draft."
                ) {
                    HStack {
                        Button {
                            exportMemories()
                        } label: {
                            Label("Export", systemImage: "square.and.arrow.up")
                        }
                        .buttonStyle(.bordered)
                        Button {
                            reconcileMemories()
                        } label: {
                            Label("Reconcile", systemImage: "arrow.triangle.merge")
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
            }
        }
        .disabled(isRunning || store.artifacts.isEmpty)
    }

    private func operationGroup<Content: View>(
        title: String,
        symbol: String,
        detail: String,
        @ViewBuilder actions: () -> Content
    ) -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: symbol)
                        .frame(width: 20)
                        .foregroundStyle(.tint)
                    Text(title)
                        .font(.headline)
                    Spacer()
                }
                Text(detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                actions()
                    .controlSize(.regular)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(minWidth: 300, maxWidth: .infinity, alignment: .topLeading)
    }

    // MARK: - Operations

    private func cleanExport(artifacts: [Artifact], label: String) {
        guard let destination = chooseDirectory(title: label, prompt: "Export") else { return }
        runOperation(label) {
            try VaultExportService().exportClean(
                artifacts: artifacts,
                to: destination
            )
        }
    }

    private func createBackup() {
        guard let destination = chooseDirectory(title: "Create Agent Vault Backup", prompt: "Backup") else { return }
        let artifacts = store.artifacts
        runOperation("Backup Created") {
            try VaultExportService().createBackup(
                artifacts: artifacts,
                to: destination
            )
        }
    }

    private func exportMemories() {
        guard let destination = chooseDirectory(title: "Export Agent Memories", prompt: "Export") else { return }
        let artifacts = store.artifacts
        runOperation("Memories Exported") {
            try VaultExportService().exportMemories(
                artifacts: artifacts,
                to: destination
            )
        }
    }

    private func reconcileMemories() {
        guard let destination = chooseDirectory(title: "Reconcile Agent Memories", prompt: "Reconcile") else { return }
        let artifacts = store.artifacts
        runOperation("Memory Reconcile Draft Created") {
            try VaultExportService().reconcileMemories(
                artifacts: artifacts,
                to: destination
            )
        }
    }

    private func restoreBackup(overwriteExisting: Bool) {
        guard let backup = chooseBackup() else { return }
        runRestore(overwriteExisting ? "Restore Completed With Overwrite" : "Restore Missing Completed") {
            try VaultExportService().restoreBackup(
                from: backup,
                overwriteExisting: overwriteExisting
            )
        }
    }

    private func runOperation(_ title: String, operation: @escaping @Sendable () throws -> VaultOperationResult) {
        isRunning = true
        message = nil
        Task {
            do {
                let result = try await Task.detached(priority: .userInitiated) {
                    try operation()
                }.value
                message = OperationMessage(title: title, detail: result.detail, url: result.rootURL, isError: false)
            } catch {
                message = OperationMessage(title: "Operation Failed", detail: error.localizedDescription, url: nil, isError: true)
            }
            isRunning = false
        }
    }

    private func runRestore(_ title: String, operation: @escaping @Sendable () throws -> VaultRestoreResult) {
        isRunning = true
        message = nil
        Task {
            do {
                let result = try await Task.detached(priority: .userInitiated) {
                    try operation()
                }.value
                message = OperationMessage(title: title, detail: result.detail, url: result.rootURL, isError: false)
                Task { await store.rescan() }
            } catch {
                message = OperationMessage(title: "Restore Failed", detail: error.localizedDescription, url: nil, isError: true)
            }
            isRunning = false
        }
    }

    // MARK: - Panels

    private func chooseDirectory(title: String, prompt: String) -> URL? {
        let panel = NSOpenPanel()
        panel.title = title
        panel.prompt = prompt
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        return panel.runModal() == .OK ? panel.url : nil
    }

    private func chooseBackup() -> URL? {
        let panel = NSOpenPanel()
        panel.title = "Choose Agent Vault Backup"
        panel.prompt = "Restore"
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        return url.lastPathComponent == "Manifest.json" ? url : url
    }

    private func confirmOverwriteRestore() -> Bool {
        let alert = NSAlert()
        alert.messageText = "Overwrite existing files?"
        alert.informativeText = "Agent Vault will replace destinations listed in the backup manifest. This cannot be undone from inside the app."
        alert.alertStyle = .critical
        alert.addButton(withTitle: "Overwrite")
        alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn
    }
}

private struct OperationMessage: Equatable {
    let title: String
    let detail: String
    let url: URL?
    let isError: Bool
}

private struct OperationResultView: View {
    let message: OperationMessage

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: message.isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                .font(.title3)
                .foregroundStyle(message.isError ? Color.orange : Color.green)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 4) {
                Text(message.title)
                    .font(.headline)
                Text(message.detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                if let url = message.url {
                    Text(url.path(percentEncoded: false))
                        .font(.caption.monospaced())
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                }
            }
            Spacer()
            if let url = message.url {
                Button {
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                } label: {
                    Label("Reveal", systemImage: "folder")
                }
                .buttonStyle(.glass)
            }
        }
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
    }
}
