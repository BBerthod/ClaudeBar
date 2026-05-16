// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ClaudeBar",
    platforms: [.macOS(.v14)],
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
            dependencies: ["ClaudeBarLib"],
            path: "Tests/ClaudeBarTests"
        )
    ]
)
