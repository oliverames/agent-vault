import CryptoKit
import Darwin
import Foundation
import Observation

/// Loads a file's content and records a fingerprint of it (exact modification
/// time, size, and content hash) so we can detect external changes between
/// read and save. The save flow re-fingerprints the file on disk and surfaces
/// a conflict if anything differs.
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

    /// What the file looked like when we last read or wrote it. The mtime is
    /// compared at full nanosecond precision, and the size and SHA-256 catch
    /// an edit that lands inside one timestamp tick or restores the old mtime.
    private struct Fingerprint: Equatable {
        let mtime: timespec
        let size: Int64
        let digest: SHA256.Digest

        static func == (lhs: Fingerprint, rhs: Fingerprint) -> Bool {
            lhs.mtime.tv_sec == rhs.mtime.tv_sec
                && lhs.mtime.tv_nsec == rhs.mtime.tv_nsec
                && lhs.size == rhs.size
                && lhs.digest == rhs.digest
        }

        var date: Date {
            Date(timeIntervalSince1970: TimeInterval(mtime.tv_sec) + TimeInterval(mtime.tv_nsec) / 1_000_000_000)
        }
    }

    let url: URL
    private var fingerprintAtRead: Fingerprint?
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
            // Stat after reading: if the file changed in between, the hash
            // still describes the bytes we hold, so save reports a conflict.
            let fingerprint = Fingerprint(
                mtime: try modificationTime(),
                size: Int64(data.count),
                digest: SHA256.hash(data: data)
            )
            self.originalText = text
            self.text = text
            self.fingerprintAtRead = fingerprint
            self.mtimeAtRead = fingerprint.date
            self.state = .loaded
        } catch {
            self.state = .error(error.localizedDescription)
        }
    }

    /// Save back to disk. If the file on disk no longer matches the
    /// fingerprint captured at read time, return `.conflict` instead of
    /// overwriting; the UI then prompts the user to reload or force-save.
    func save(force: Bool = false) -> SaveOutcome {
        do {
            if !force, let captured = fingerprintAtRead {
                let current = try currentFingerprint()
                if current != captured {
                    return .conflict(diskMtime: current.date)
                }
            }

            try text.write(to: url, atomically: true, encoding: .utf8)
            let written = try currentFingerprint()
            self.fingerprintAtRead = written
            self.mtimeAtRead = written.date
            self.originalText = text
            return .saved
        } catch {
            CrashReporting.report(.editor, "Save failed", error: error)
            return .error(error.localizedDescription)
        }
    }

    /// Discard local edits and re-read from disk.
    func reload() {
        load()
    }

    private func currentFingerprint() throws -> Fingerprint {
        let data = try Data(contentsOf: url)
        return Fingerprint(
            mtime: try modificationTime(),
            size: Int64(data.count),
            digest: SHA256.hash(data: data)
        )
    }

    /// Exact modification time from stat(2). `Date` from FileManager
    /// attributes loses sub-microsecond precision, so compare timespecs.
    private func modificationTime() throws -> timespec {
        var info = stat()
        guard stat(url.path(percentEncoded: false), &info) == 0 else {
            throw CocoaError(.fileReadNoSuchFile)
        }
        return info.st_mtimespec
    }
}
