// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Lumina",
    platforms: [.macOS(.v26)],
    dependencies: [
        // Keep in sync with SPARKLE_VERSION in .github/workflows/release.yml,
        // which downloads the matching release tools.
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.9.6"),
    ],
    targets: [
        .executableTarget(
            name: "Lumina",
            dependencies: [
                .product(name: "Sparkle", package: "Sparkle"),
            ],
            path: "Sources/Lumina",
            linkerSettings: [
                // Sparkle.framework is embedded in Lumina.app/Contents/Frameworks.
                .unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"]),
            ]
        )
    ]
)
