// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AgentM",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "AgentMCore"),
        .executableTarget(
            name: "AgentM",
            dependencies: ["AgentMCore"]
        ),
        .testTarget(
            name: "AgentMCoreTests",
            dependencies: ["AgentMCore"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
