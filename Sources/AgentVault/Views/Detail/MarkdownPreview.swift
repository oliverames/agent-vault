import SwiftUI
import MarkdownUI

/// Renders a Markdown file with full heading/list/table/code support via
/// swift-markdown-ui. Falls back to raw text on load error.
struct MarkdownPreview: View {
    let url: URL
    @State private var text: String = ""
    @State private var error: String?

    var body: some View {
        ScrollView {
            if let error {
                Text(error)
                    .foregroundStyle(.red)
                    .padding()
            } else {
                Markdown(text)
                    .markdownTheme(.gitHub)
                    .textSelection(.enabled)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 18)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .task(id: url) {
            load()
        }
    }

    private func load() {
        do {
            let data = try Data(contentsOf: url)
            text = String(data: data, encoding: .utf8) ?? ""
            error = nil
        } catch {
            self.error = "Couldn't load: \(error.localizedDescription)"
        }
    }
}
