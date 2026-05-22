import Foundation

/// User-facing sort modes for the inventory list. Grouping still happens in
/// the list view; this controls the order inside each group.
enum ArtifactSortOrder: String, CaseIterable, Identifiable {
    case modifiedNewest = "Recently Modified"
    case name = "Name"
    case source = "Source"
    case sizeLargest = "Largest"

    var id: String { rawValue }

    func compare(_ lhs: Artifact, _ rhs: Artifact) -> Bool {
        switch self {
        case .modifiedNewest:
            if lhs.modifiedAt != rhs.modifiedAt { return lhs.modifiedAt > rhs.modifiedAt }
            return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
        case .name:
            let title = lhs.title.localizedCaseInsensitiveCompare(rhs.title)
            if title != .orderedSame { return title == .orderedAscending }
            return lhs.url.path(percentEncoded: false) < rhs.url.path(percentEncoded: false)
        case .source:
            if lhs.source != rhs.source { return lhs.source.rawValue < rhs.source.rawValue }
            return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
        case .sizeLargest:
            if lhs.sizeBytes != rhs.sizeBytes { return lhs.sizeBytes > rhs.sizeBytes }
            return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
        }
    }
}
