// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription
import Foundation

// Check whether speech support should be enabled (default: false / without speech)
let enableSpeech = ProcessInfo.processInfo.environment["ENABLE_SPEECH"] == "1" ||
                   ProcessInfo.processInfo.environment["WITH_SPEECH"] == "1" ||
                   ProcessInfo.processInfo.environment["AIPROMPT_ENABLE_SPEECH"] == "1" ||
                   ProcessInfo.processInfo.arguments.contains("--enable-speech") ||
                   ProcessInfo.processInfo.arguments.contains("--with-speech")

var swiftSettings: [SwiftSetting] = [
    // Enable [@MainActor] for better alignment with local AI frameworks
    .unsafeFlags(["-Xfrontend", "-warn-concurrency", "-Xfrontend", "-enable-actor-data-race-checks"])
]

if enableSpeech {
    swiftSettings.append(.define("ENABLE_SPEECH"))
}

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
            swiftSettings: swiftSettings
        ),
        .testTarget(
            name: "AIPromptCoreTests",
            dependencies: ["AIPromptCore"],
            path: "Tests/AIPromptCoreTests",
            swiftSettings: swiftSettings
        )
    ]
)
