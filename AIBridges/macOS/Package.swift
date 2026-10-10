// swift-tools-version:6.0
import PackageDescription
import Foundation

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
    name: "macAIBridge",
    platforms: [
       .macOS("26.0")
    ],
    dependencies: [
        // 💧 A server-side Swift web framework.
        .package(url: "https://github.com/vapor/vapor.git", from: "4.89.0"),
        .package(path: "../../frameworks/AIPromptCore"),
        .package(path: "../Shared")
    ],
    targets: [
        .executableTarget(
            name: "App",
            dependencies: [
                .product(name: "Vapor", package: "vapor"),
                .product(name: "AIPromptCore", package: "AIPromptCore"),
                .product(name: "AIBridgeKit", package: "Shared")
            ],
            swiftSettings: swiftSettings
        ),
        .testTarget(
            name: "AppTests",
            dependencies: [
                .target(name: "App"),
                .product(name: "XCTVapor", package: "vapor"),
            ],
            swiftSettings: swiftSettings
        )
    ]
)
