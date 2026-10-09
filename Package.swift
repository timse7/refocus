// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "Refocus",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Refocus",
            path: "Sources/Refocus",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
