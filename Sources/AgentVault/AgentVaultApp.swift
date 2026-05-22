import SwiftUI
import AppKit

@main
struct AgentVaultApp: App {
    @State private var store = VaultStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(store)
                .task(id: "initial-scan") {
                    // Initial scan once on launch.
                    await store.rescan()
                }
                .frame(minWidth: 1100, minHeight: 700)
        }
        .windowStyle(.titleBar)
        .commands {
            CommandGroup(after: .newItem) {
                Button("Rescan") {
                    Task { await store.rescan() }
                }
                .keyboardShortcut("r", modifiers: [.command])

                Divider()

                Button("Reveal Selected in Finder") {
                    if let artifact = store.selectedArtifact {
                        NSWorkspace.shared.activateFileViewerSelecting([artifact.url])
                    }
                }
                .keyboardShortcut("r", modifiers: [.command, .shift])
                .disabled(store.selectedArtifact == nil)

                Button("Copy Selected Path") {
                    if let artifact = store.selectedArtifact {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(artifact.url.path(percentEncoded: false), forType: .string)
                    }
                }
                .keyboardShortcut("c", modifiers: [.command, .option])
                .disabled(store.selectedArtifact == nil)
            }
        }

        Settings {
            SettingsView()
                .environment(store)
                .frame(minWidth: 500, minHeight: 400)
        }
    }
}
