// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ClaudeBar",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(
            url: "https://github.com/pointfreeco/swift-snapshot-testing",
            from: "1.17.0"
        ),
    ],
    targets: [
        .target(
            name: "ClaudeBarLib",
            path: "Sources/ClaudeBar"
        ),
        .executableTarget(
            name: "ClaudeBar",
            dependencies: ["ClaudeBarLib"],
            path: "Sources/ClaudeBarApp"
        ),
        .testTarget(
            name: "ClaudeBarTests",
            dependencies: [
                "ClaudeBarLib",
                .product(name: "SnapshotTesting", package: "swift-snapshot-testing"),
            ],
            path: "Tests/ClaudeBarTests"
        )
    ]
)
