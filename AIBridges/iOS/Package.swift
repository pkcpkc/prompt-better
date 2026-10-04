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
    name: "iosAIBridge",
    platforms: [
        .iOS("26.0"), // Match AIPromptCore
        .macOS("26.0")
    ],
    products: [
        .executable(name: "iosAIBridge", targets: ["App"])
    ],
    dependencies: [
        .package(url: "https://github.com/vapor/vapor.git", from: "4.89.0"),
        .package(path: "../../frameworks/AIPromptCore")
    ],
    targets: [
        .executableTarget(
            name: "App",
            dependencies: [
                .product(name: "Vapor", package: "vapor"),
                .product(name: "AIPromptCore", package: "AIPromptCore")
            ],
            path: "Sources/App",
            swiftSettings: swiftSettings
        )
    ]
)
