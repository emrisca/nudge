// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Nudge",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "NudgeCore", targets: ["NudgeCore"]),
        .library(name: "NudgeIntents", targets: ["NudgeIntents"]),
        .executable(name: "Nudge", targets: ["NudgeApp"]),
        .executable(name: "nudge-cli", targets: ["NudgeCLI"]),
        .executable(name: "nudge-helper", targets: ["NudgeHelper"]),
        .executable(name: "nudge-test-runner", targets: ["NudgeTestRunner"])
    ],
    dependencies: [],
    targets: [
        .target(
            name: "NudgeCore",
            dependencies: [],
            path: "Sources/NudgeCore",
            linkerSettings: [
                .linkedFramework("IOKit"),
                .linkedFramework("AppKit"),
                .linkedFramework("ServiceManagement")
            ]
        ),
        .target(
            name: "NudgeIntents",
            dependencies: ["NudgeCore"],
            path: "Sources/NudgeIntents",
            linkerSettings: [
                .linkedFramework("AppIntents")
            ]
        ),
        .executableTarget(
            name: "NudgeApp",
            dependencies: ["NudgeCore", "NudgeIntents"],
            path: "Sources/NudgeApp",
            linkerSettings: [
                .linkedFramework("SwiftUI"),
                .linkedFramework("AppKit"),
                .linkedFramework("Charts"),
                .linkedFramework("AppIntents")
            ]
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
        .executableTarget(
            name: "NudgeTestRunner",
            dependencies: ["NudgeCore", "NudgeIntents"],
            path: "Sources/NudgeTestRunner"
        ),
        .testTarget(
            name: "NudgeCoreTests",
            dependencies: ["NudgeCore"],
            path: "Tests/NudgeCoreTests"
        )
    ]
)
