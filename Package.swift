// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Pismo",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Pismo",
            dependencies: ["PismoCore"],
            path: "Sources/Pismo",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .target(
            name: "PismoCore",
            path: "Sources/PismoCore",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "PismoCoreTests",
            dependencies: ["PismoCore"],
            path: "Tests/PismoCoreTests",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
