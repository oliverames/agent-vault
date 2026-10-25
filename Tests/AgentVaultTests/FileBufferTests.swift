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

    @Test("save detects an external edit within one second of the read")
    func saveDetectsSubsecondExternalModification() throws {
        let url = try temporaryFile(contents: "one")
        let buffer = FileBuffer(url: url)
        buffer.load()
        let readMtime = try #require(buffer.mtimeAtRead)

        buffer.text = "two"
        try "external edit".write(to: url, atomically: true, encoding: .utf8)
        try setModificationDate(readMtime.addingTimeInterval(0.4), of: url)

        #expect(isConflict(buffer.save()))
        #expect(try String(contentsOf: url, encoding: .utf8) == "external edit")
    }

    @Test("save detects a same-size replacement that keeps the read timestamp")
    func saveDetectsSameTimestampReplacement() throws {
        let url = try temporaryFile(contents: "one")
        let buffer = FileBuffer(url: url)
        buffer.load()
        let readMtime = try #require(buffer.mtimeAtRead)

        buffer.text = "two"
        try "uno".write(to: url, atomically: true, encoding: .utf8)
        try setModificationDate(readMtime, of: url)

        #expect(isConflict(buffer.save()))
        #expect(try String(contentsOf: url, encoding: .utf8) == "uno")
    }

    @Test("save accepts an unchanged file and consecutive saves")
    func saveAcceptsUnchangedFile() throws {
        let url = try temporaryFile(contents: "one")
        let buffer = FileBuffer(url: url)
        buffer.load()

        buffer.text = "two"
        #expect(buffer.save() == .saved)
        buffer.text = "three"
        #expect(buffer.save() == .saved)
        #expect(try String(contentsOf: url, encoding: .utf8) == "three")
    }

    @Test("force save overwrites a conflicting external edit")
    func forceSaveOverwritesConflict() throws {
        let url = try temporaryFile(contents: "one")
        let buffer = FileBuffer(url: url)
        buffer.load()
        let readMtime = try #require(buffer.mtimeAtRead)

        buffer.text = "two"
        try "external edit".write(to: url, atomically: true, encoding: .utf8)
        try setModificationDate(readMtime.addingTimeInterval(0.4), of: url)

        #expect(isConflict(buffer.save()))
        #expect(buffer.save(force: true) == .saved)
        #expect(try String(contentsOf: url, encoding: .utf8) == "two")
        #expect(buffer.save() == .saved)
    }

    private func isConflict(_ outcome: FileBuffer.SaveOutcome) -> Bool {
        if case .conflict = outcome { return true }
        return false
    }

    private func setModificationDate(_ date: Date, of url: URL) throws {
        try FileManager.default.setAttributes(
            [.modificationDate: date],
            ofItemAtPath: url.path(percentEncoded: false)
        )
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
