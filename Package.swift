// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "AgentVault",
    platforms: [.macOS("26.0")],
    products: [
        .executable(name: "AgentVault", targets: ["AgentVault"])
    ],
    dependencies: [
        .package(url: "https://github.com/gonzalezreal/swift-markdown-ui", from: "2.4.0"),
        .package(url: "https://github.com/getsentry/sentry-cocoa", exact: "9.31.0")
    ],
    targets: [
        .executableTarget(
            name: "AgentVault",
            dependencies: [
                .product(name: "MarkdownUI", package: "swift-markdown-ui"),
                .product(name: "Sentry", package: "sentry-cocoa")
            ],
            path: "Sources/AgentVault"
        ),
        .testTarget(
            name: "AgentVaultTests",
            dependencies: [
                "AgentVault",
                .product(name: "Sentry", package: "sentry-cocoa")
            ],
            path: "Tests/AgentVaultTests"
        )
    ]
)
