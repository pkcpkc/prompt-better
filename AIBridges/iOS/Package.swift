// swift-tools-version:6.0
import PackageDescription

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
            swiftSettings: [
                .unsafeFlags(["-Xfrontend", "-warn-concurrency", "-Xfrontend", "-enable-actor-data-race-checks"])
            ]
        )
    ]
)
