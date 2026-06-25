// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AgentMonitor",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "AgentMonitorCore"),
        .executableTarget(
            name: "AgentMonitor",
            dependencies: ["AgentMonitorCore"]
        ),
        .testTarget(
            name: "AgentMonitorCoreTests",
            dependencies: ["AgentMonitorCore"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
