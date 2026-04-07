// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "AgentPulse",
    platforms: [
        .macOS(.v14)
    ],
    targets: [
        .executableTarget(
            name: "AgentPulse",
            path: "Sources/AgentPulse"
        )
    ]
)
