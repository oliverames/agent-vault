import SwiftUI
import AppKit

/// Non-blocking banner shown across the top of the window when the scanner
/// reports denied roots. Single button opens the Full Disk Access pane in
/// System Settings.
struct PermissionBanner: View {
    @Environment(VaultStore.self) private var store

    var body: some View {
        if !store.deniedRoots.isEmpty {
            HStack(spacing: 12) {
                Image(systemName: "lock.shield")
                    .foregroundStyle(.tint)
                    .font(.title3)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Some folders couldn't be read")
                        .font(.headline)
                    Text("\(store.deniedRoots.count) location\(store.deniedRoots.count == 1 ? "" : "s") need Full Disk Access. Agent Vault can still show what it can reach.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Open Settings…") {
                    openFullDiskAccessPane()
                }
                .controlSize(.large)
                .buttonStyle(.glassProminent)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(.thinMaterial)
            }
            .padding(.horizontal, 12)
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }

    private func openFullDiskAccessPane() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_AllFiles") {
            NSWorkspace.shared.open(url)
        }
    }
}
