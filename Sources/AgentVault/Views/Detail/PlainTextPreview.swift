import SwiftUI

/// Source view for JSON/TOML/other text files. No syntax highlighting in v1
/// — just monospaced selectable text.
struct PlainTextPreview: View {
    let url: URL
    @State private var text: String = ""
    @State private var error: String?

    var body: some View {
        ScrollView([.vertical, .horizontal]) {
            if let error {
                Text(error).foregroundStyle(.red).padding()
            } else {
                Text(text)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(20)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .task(id: url) { load() }
    }

    private func load() {
        do {
            let data = try Data(contentsOf: url)
            text = String(data: data, encoding: .utf8) ?? "(binary or non-UTF8 file)"
            error = nil
        } catch {
            self.error = "Couldn't load: \(error.localizedDescription)"
        }
    }
}
