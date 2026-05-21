import SwiftUI

struct ArtifactRowView: View {
    let artifact: Artifact

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: artifact.category.sfSymbol)
                .font(.title3)
                .frame(width: 26, height: 26)
                .foregroundStyle(.tint)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(artifact.title)
                        .font(.body.weight(.semibold))
                        .lineLimit(1)
                    if artifact.isCustom {
                        CustomBadge()
                    }
                }
                if let subtitle = artifact.subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                HStack(spacing: 6) {
                    SourceChip(source: artifact.source)
                    if let marketplace = artifact.metadata.marketplace,
                       artifact.category != .marketplace {
                        OriginChip(icon: "storefront", text: marketplace)
                    }
                    if artifact.metadata.isBundled {
                        OriginChip(icon: "shippingbox.fill", text: "bundled", subtle: true)
                    }
                    if !artifact.metadata.installedInto.isEmpty {
                        OriginChip(
                            icon: "arrow.down.app",
                            text: artifact.metadata.installedInto.map(\.rawValue).joined(separator: ", "),
                            subtle: true
                        )
                    }
                }
                .padding(.top, 1)
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 2) {
                Text(artifact.modifiedFormatted)
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
                Text(artifact.sizeFormatted)
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 4)
    }
}

private struct CustomBadge: View {
    var body: some View {
        Text("CUSTOM")
            .font(.caption2.bold())
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .foregroundStyle(.white)
            .background(.tint, in: Capsule())
    }
}

private struct SourceChip: View {
    let source: ArtifactSource
    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: source.sfSymbol).font(.caption2)
            Text(source.rawValue).font(.caption2)
        }
        .padding(.horizontal, 5)
        .padding(.vertical, 1)
        .foregroundStyle(.secondary)
        .background(.quaternary, in: Capsule())
    }
}

private struct TagChip: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.caption2)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .foregroundStyle(.secondary)
            .background(.quinary, in: Capsule())
    }
}

private struct OriginChip: View {
    let icon: String
    let text: String
    var subtle: Bool = false
    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: icon).font(.caption2)
            Text(text).font(.caption2)
        }
        .padding(.horizontal, 5)
        .padding(.vertical, 1)
        .foregroundStyle(subtle ? AnyShapeStyle(.tertiary) : AnyShapeStyle(.secondary))
        .background(subtle ? Color.gray.opacity(0.08) : Color.accentColor.opacity(0.12),
                    in: Capsule())
    }
}
