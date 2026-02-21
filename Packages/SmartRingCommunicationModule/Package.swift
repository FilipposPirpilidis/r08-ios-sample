// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SmartRingCommunicationModule",
    platforms: [
        .iOS(.v16),
        .macOS(.v10_15)
    ],
    products: [
        .library(
            name: "SmartRingCommunicationModule",
            targets: ["SmartRingCommunicationModule"]
        )
    ],
    dependencies: [
        .package(name: "Core", path: "../Core")
    ],
    targets: [
        .target(
            name: "SmartRingCommunicationModule",
            dependencies: ["Core"],
            path: "Sources/SmartRingCommunicationModule"
        )
    ]
)
