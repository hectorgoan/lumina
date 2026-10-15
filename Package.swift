// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Lumina",
    platforms: [.macOS(.v26)],
    targets: [
        .executableTarget(
            name: "Lumina",
            path: "Sources/Lumina"
        )
    ]
)
