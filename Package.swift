// swift-tools-version:6.0
// TestsAgent: functional tests for an app built on Granite, on mock backend responses, as a Granite agent package.
// An app that links it finds the `tests` agent through Granite's roster, with nothing listed by hand.

import PackageDescription

let package = Package(
    name: "TestsAgent",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "TestsAgent", targets: ["TestsAgent"]),
    ],
    dependencies: [
        .package(url: "https://github.com/riteshpakala/Granite.git", branch: "main"),
    ],
    targets: [
        .target(
            name: "TestsAgent",
            dependencies: [.product(name: "GraniteAgents", package: "Granite")],
            swiftSettings: [.swiftLanguageMode(.v6)]),
        .testTarget(
            name: "TestsAgentTests",
            dependencies: ["TestsAgent", .product(name: "GraniteAgents", package: "Granite")],
            swiftSettings: [.swiftLanguageMode(.v6)]),
    ]
)
