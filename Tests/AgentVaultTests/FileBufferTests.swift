import Foundation
import Testing
@testable import AgentVault

@MainActor
@Suite("FileBuffer")
struct FileBufferTests {
    @Test("save detects external modification before overwriting")
    func saveDetectsExternalModification() throws {
        let url = try temporaryFile(contents: "one")
        let buffer = FileBuffer(url: url)
        buffer.load()

        buffer.text = "two"
        try "external".write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.modificationDate: Date().addingTimeInterval(5)],
            ofItemAtPath: url.path(percentEncoded: false)
        )

        switch buffer.save() {
        case .conflict:
            break
        case .saved:
            Issue.record("Expected a conflict, got saved")
        case .error(let message):
            Issue.record("Expected a conflict, got error: \(message)")
        }
    }

    @Test("force save updates original text after conflict")
    func forceSaveUpdatesOriginalText() throws {
        let url = try temporaryFile(contents: "one")
        let buffer = FileBuffer(url: url)
        buffer.load()
        buffer.text = "two"

        let outcome = buffer.save(force: true)

        #expect(outcome == .saved)
        #expect(buffer.originalText == "two")
        #expect(buffer.isDirty == false)
        #expect(try String(contentsOf: url, encoding: .utf8) == "two")
    }

    private func temporaryFile(contents: String) throws -> URL {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "AgentVaultTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appending(path: "sample.md")
        try contents.write(to: url, atomically: true, encoding: .utf8)
        return url
    }
}
