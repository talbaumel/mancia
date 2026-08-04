// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "Mancia",
    platforms: [.macOS(.v14)],
    dependencies: [
        // 1.16+ contains unguarded #Preview declarations, but standalone
        // Command Line Tools declares that macro without shipping its plugin.
        .package(
            url: "https://github.com/sindresorhus/KeyboardShortcuts",
            exact: "1.15.0"
        ),
        .package(
            url: "https://github.com/swiftlang/swift-testing.git",
            exact: "0.12.0"
        ),
    ],
    targets: [
        .executableTarget(
            name: "Mancia",
            dependencies: [
                .product(name: "KeyboardShortcuts", package: "KeyboardShortcuts"),
            ],
            path: "Sources/Mancia",
            exclude: ["prompts"]
        ),
        .testTarget(
            name: "ManciaTests",
            dependencies: [
                "Mancia",
                .product(name: "Testing", package: "swift-testing"),
            ],
            path: "Tests/ManciaTests"
        ),
    ],
    swiftLanguageModes: [.v6]
)
