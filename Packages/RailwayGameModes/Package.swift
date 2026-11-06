// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "RailwayGameModes",
    platforms: [
        .iOS(.v17),
        .macOS(.v13)
    ],
    products: [
        .library(name: "RailwayGameModes", targets: ["RailwayGameModes"])
    ],
    targets: [
        .target(
            name: "RailwayGameModes",
            path: "Sources/RailwayGameModes"
        ),
        .testTarget(
            name: "RailwayGameModesTests",
            dependencies: ["RailwayGameModes"],
            path: "Tests/RailwayGameModesTests"
        )
    ]
)
