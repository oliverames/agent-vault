import Foundation
import Observation

/// Loads a file's content and tracks its modification time so we can detect
/// external changes between read and save. The save flow re-reads the mtime
/// from disk and surfaces a conflict if it has moved.
@MainActor
@Observable
final class FileBuffer {
    enum LoadState: Sendable, Equatable {
        case idle
        case loaded
        case error(String)
    }

    /// Result returned by `save(_:)`. The UI uses this to drive the conflict
    /// alert.
    enum SaveOutcome: Sendable, Equatable {
        case saved
        case conflict(diskMtime: Date)
        case error(String)
    }

    let url: URL
    private(set) var originalText: String = ""
    var text: String = ""
    private(set) var mtimeAtRead: Date?
    private(set) var state: LoadState = .idle

    init(url: URL) {
        self.url = url
    }

    /// Returns true if the buffer has unsaved edits.
    var isDirty: Bool { text != originalText }

    func load() {
        do {
            let data = try Data(contentsOf: url)
            let text = String(data: data, encoding: .utf8) ?? ""
            let attrs = try FileManager.default.attributesOfItem(atPath: url.path(percentEncoded: false))
            self.originalText = text
            self.text = text
            self.mtimeAtRead = attrs[.modificationDate] as? Date
            self.state = .loaded
        } catch {
            self.state = .error(error.localizedDescription)
        }
    }

    /// Save back to disk. If the on-disk mtime no longer matches what we
    /// captured at read time, return `.conflict` instead of overwriting; the
    /// UI then prompts the user to reload or force-save.
    func save(force: Bool = false) -> SaveOutcome {
        let path = url.path(percentEncoded: false)
        do {
            let currentMtime = (try FileManager.default.attributesOfItem(atPath: path))[.modificationDate] as? Date

            if !force,
               let captured = mtimeAtRead,
               let current = currentMtime,
               // Use 1s tolerance — APFS resolution can vary slightly.
               abs(current.timeIntervalSince(captured)) > 1.0
            {
                return .conflict(diskMtime: current)
            }

            try text.write(to: url, atomically: true, encoding: .utf8)
            let newAttrs = try FileManager.default.attributesOfItem(atPath: path)
            self.mtimeAtRead = newAttrs[.modificationDate] as? Date
            self.originalText = text
            return .saved
        } catch {
            return .error(error.localizedDescription)
        }
    }

    /// Discard local edits and re-read from disk.
    func reload() {
        load()
    }
}
