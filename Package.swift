// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AsciiDraw",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "AsciiDrawCore", targets: ["AsciiDrawCore"]),
        .executable(name: "asciidraw", targets: ["AsciiDrawCLI"]),
        .executable(name: "AsciiDrawApp", targets: ["AsciiDrawApp"]),
    ],
    targets: [
        .target(
            name: "AsciiDrawCore",
            path: "Sources/AsciiDrawCore",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "AsciiDrawCLI",
            dependencies: ["AsciiDrawCore"],
            path: "Sources/AsciiDrawCLI",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "AsciiDrawApp",
            dependencies: ["AsciiDrawCore"],
            path: "Sources/AsciiDrawApp",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "AsciiDrawCoreTests",
            dependencies: ["AsciiDrawCore"],
            path: "Tests/AsciiDrawCoreTests",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
