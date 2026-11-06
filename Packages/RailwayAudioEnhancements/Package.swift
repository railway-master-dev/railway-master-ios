// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "RailwayAudioEnhancements",
    platforms: [.iOS(.v17), .macOS(.v13)],
    products: [
        .library(name: "RailwayAudioEnhancements", targets: ["RailwayAudioEnhancements"])
    ],
    targets: [
        .target(name: "RailwayAudioEnhancements"),
        .testTarget(
            name: "RailwayAudioEnhancementsTests",
            dependencies: ["RailwayAudioEnhancements"]
        )
    ]
)
