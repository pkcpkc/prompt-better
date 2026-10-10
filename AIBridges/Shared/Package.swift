// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "AIBridgeKit",
    platforms: [
        .iOS("26.0"),
        .macOS("26.0")
    ],
    products: [
        .library(name: "AIBridgeKit", targets: ["AIBridgeKit"])
    ],
    dependencies: [
        .package(url: "https://github.com/vapor/vapor.git", from: "4.89.0"),
        .package(path: "../../frameworks/AIPromptCore")
    ],
    targets: [
        .target(
            name: "AIBridgeKit",
            dependencies: [
                .product(name: "Vapor", package: "vapor"),
                .product(name: "AIPromptCore", package: "AIPromptCore")
            ]
        )
    ]
)
