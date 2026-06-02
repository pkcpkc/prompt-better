// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "AIPromptCore",
    platforms: [
        .iOS("26.0"),
        .macOS("26.0")
    ],
    products: [
        // Products define the executables and libraries a package produces, and make them visible to other packages.
        .library(
            name: "AIPromptCore",
            type: .dynamic,
            targets: ["AIPromptCore"]),
    ],
    dependencies: [
        // Dependencies declare other packages that this package depends on.
    ],
    targets: [
        // Targets are the basic building blocks of a package. A target can define a module or a test suite.
        // Targets can depend on other targets in this package, and on products in packages this package depends on.
        .target(
            name: "AIPromptCore",
            dependencies: [],
            path: "Sources/AIPromptCore",
            swiftSettings: [
                // Enable [@MainActor] for better alignment with local AI frameworks
                .unsafeFlags(["-Xfrontend", "-warn-concurrency", "-Xfrontend", "-enable-actor-data-race-checks"])
            ]
        ),
        .testTarget(
            name: "AIPromptCoreTests",
            dependencies: ["AIPromptCore"],
            path: "Tests/AIPromptCoreTests"
        )
    ]
)
