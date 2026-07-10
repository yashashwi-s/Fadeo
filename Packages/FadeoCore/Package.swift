// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "FadeoCore",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "FadeoCore", targets: ["FadeoCore"]),
    ],
    dependencies: [
        // Yams is pure Swift (no OS calls) so it doesn't compromise FadeoCore's
        // OS-independence — the YAML codec stays unit-testable with `swift test`.
        .package(url: "https://github.com/jpsim/Yams.git", from: "5.1.0"),
    ],
    targets: [
        // Pure, OS-independent core: the model + the resolver.
        // The only dependency is Yams (config serialization) — this is the correctness
        // heart and must stay trivially unit-testable with `swift test`.
        .target(
            name: "FadeoCore",
            dependencies: ["Yams"],
            swiftSettings: [
                .swiftLanguageMode(.v6),
            ]
        ),
        .testTarget(
            name: "FadeoCoreTests",
            dependencies: ["FadeoCore"],
            swiftSettings: [
                .swiftLanguageMode(.v6),
            ]
        ),
    ]
)
