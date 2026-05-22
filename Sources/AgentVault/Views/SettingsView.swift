import SwiftUI
import AppKit

struct SettingsView: View {
    @Environment(VaultStore.self) private var store
    @State private var rootError: String?

    var body: some View {
        TabView {
            scanTab
                .tabItem { Label("Scan Roots", systemImage: "folder") }
            aboutTab
                .tabItem { Label("About", systemImage: "info.circle") }
        }
        .padding(20)
    }

    private var scanTab: some View {
        @Bindable var bindable = store
        return VStack(alignment: .leading, spacing: 16) {
            Text("Scan Roots")
                .font(.title2.bold())

            Text("These directories are walked when Agent Vault scans for artifacts. Canonical roots are always scanned. Cache and marketplace roots are noisier and opt-in.")
                .font(.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            List {
                Section("Canonical") {
                    ForEach(store.scanRoots.filter { $0.isCanonical && !$0.isUserAdded }) { root in
                        ScanRootRow(root: root)
                    }
                }
                Section {
                    let customRoots = store.scanRoots.filter(\.isUserAdded)
                    if customRoots.isEmpty {
                        Text("No custom roots")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(customRoots) { root in
                            ScanRootRow(root: root) {
                                store.removeCustomScanRoot(root)
                            }
                        }
                    }
                } header: {
                    HStack {
                        Text("Custom")
                        Spacer()
                        Button {
                            addCustomRoot()
                        } label: {
                            Label("Add", systemImage: "folder.badge.plus")
                        }
                        .buttonStyle(.borderless)
                        .labelStyle(.iconOnly)
                        .help("Add Custom Scan Root")
                    }
                }
                Section("Caches & Marketplaces (opt-in)") {
                    ForEach(store.scanRoots.filter { !$0.isCanonical }) { root in
                        ScanRootRow(root: root)
                    }
                }
            }
            .listStyle(.inset)

            Divider()

            Toggle("Include caches & marketplaces in scans", isOn: $bindable.showCached)
                .toggleStyle(.switch)

            HStack {
                if let rootError {
                    Text(rootError)
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                Spacer()
                Button {
                    addCustomRoot()
                } label: {
                    Label("Add Root", systemImage: "folder.badge.plus")
                }
                .buttonStyle(.glass)

                Button("Rescan Now") {
                    Task { await store.rescan() }
                }
                .buttonStyle(.glassProminent)
            }
        }
    }

    private var aboutTab: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Agent Vault").font(.largeTitle.bold())
            Text("Version 1.0.0-beta.2").foregroundStyle(.secondary)
            Text("A unified inventory of skills, MCPs, plugins, marketplaces, config files, instruction files, work logs, remember buffers, and memory stores across Claude Code, Codex, and Antigravity on your Mac.")
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func addCustomRoot() {
        let panel = NSOpenPanel()
        panel.title = "Add Scan Root"
        panel.prompt = "Add"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false

        guard panel.runModal() == .OK, let url = panel.url else { return }
        if store.addCustomScanRoot(url) {
            rootError = nil
        } else {
            rootError = "That root is already being scanned."
        }
    }
}

private struct ScanRootRow: View {
    let root: ScanRoot
    var onRemove: (() -> Void)? = nil

    var body: some View {
        HStack {
            Image(systemName: exists ? "folder" : "folder.badge.questionmark")
                .foregroundStyle(exists ? Color.accentColor : Color.orange)
            VStack(alignment: .leading, spacing: 1) {
                Text(root.displayName)
                Text(root.url.path(percentEncoded: false))
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            if !exists {
                Text("not found")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            if let onRemove {
                Button(role: .destructive) {
                    onRemove()
                } label: {
                    Image(systemName: "minus.circle")
                }
                .buttonStyle(.borderless)
                .help("Remove Custom Root")
            }
        }
    }

    private var exists: Bool {
        FileManager.default.fileExists(atPath: root.url.path(percentEncoded: false))
    }
}
