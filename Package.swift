// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "CodexChatMover",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "CodexChatMoverCore", targets: ["CodexChatMoverCore"]),
        .executable(name: "CodexChatMover", targets: ["CodexChatMover"]),
        .executable(name: "ScannerSmokeTests", targets: ["ScannerSmokeTests"]),
        .executable(name: "ScannerDiagnostics", targets: ["ScannerDiagnostics"])
    ],
    targets: [
        .target(
            name: "CodexChatMoverCore",
            path: "Sources/CodexChatMoverCore"
        ),
        .executableTarget(
            name: "CodexChatMover",
            dependencies: ["CodexChatMoverCore"],
            path: "Sources/CodexChatMoverApp"
        ),
        .executableTarget(
            name: "ScannerSmokeTests",
            dependencies: ["CodexChatMoverCore"],
            path: "Tests/ScannerSmokeTests",
            resources: [
                .copy("Fixtures")
            ]
        ),
        .executableTarget(
            name: "ScannerDiagnostics",
            dependencies: ["CodexChatMoverCore"],
            path: "Tests/ScannerDiagnostics"
        )
    ]
)
