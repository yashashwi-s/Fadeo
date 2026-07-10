// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "FadeoCore",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "FadeoCore", targets: ["FadeoCore"]),
    ],
    targets: [
        // Pure, OS-independent core: the model + the resolver.
        // No dependencies on purpose — this is the correctness heart and must be
        // trivially unit-testable with `swift test`.
        .target(
            name: "FadeoCore",
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
