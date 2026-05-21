import SwiftUI

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
            }
        }

        Settings {
            SettingsView()
                .environment(store)
                .frame(minWidth: 500, minHeight: 400)
        }
    }
}
