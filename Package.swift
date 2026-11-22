// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Nudge",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "nudge-cli", targets: ["NudgeCLI"]),
        .executable(name: "nudge-helper", targets: ["NudgeHelper"]),
        .library(name: "NudgeCore", targets: ["NudgeCore"])
    ],
    dependencies: [],
    targets: [
        .target(
            name: "NudgeCore",
            dependencies: [],
            path: "Sources/NudgeCore"
        ),
        .executableTarget(
            name: "NudgeCLI",
            dependencies: ["NudgeCore"],
            path: "Sources/NudgeCLI"
        ),
        .executableTarget(
            name: "NudgeHelper",
            dependencies: ["NudgeCore"],
            path: "Sources/NudgeHelper"
        ),
        .testTarget(
            name: "NudgeCoreTests",
            dependencies: ["NudgeCore"],
            path: "Tests/NudgeCoreTests"
        )
    ]
)
