// swift-tools-version:6.0
import PackageDescription
let package = Package(
    name: "RepoSentinel",
    platforms: [.macOS("26.0")],
    targets: [
        .executableTarget(name: "RepoSentinel", swiftSettings: [.swiftLanguageMode(.v5)]),
        .testTarget(name: "RepoSentinelTests", dependencies: ["RepoSentinel"], swiftSettings: [.swiftLanguageMode(.v5)]),
    ]
)
