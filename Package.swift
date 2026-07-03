// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Pearblossom",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Pearblossom",
            path: "Sources/Pearblossom",
            resources: [.process("Resources")]
        )
    ]
)
