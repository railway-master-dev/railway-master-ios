// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "RailwayRendering",
    platforms: [.iOS(.v17)],
    products: [
        .library(name: "RailwayRendering", targets: ["RailwayRendering"]),
        .library(name: "RailwayCameraRendering", targets: ["RailwayCameraRendering"]),
        .library(name: "RailwayEnvironmentRendering", targets: ["RailwayEnvironmentRendering"]),
        .library(name: "RailwayQualityRendering", targets: ["RailwayQualityRendering"])
    ],
    targets: [
        .target(name: "RailwayRenderingCore"),
        .target(name: "RailwayCameraRendering", dependencies: ["RailwayRenderingCore"]),
        .target(name: "RailwayEnvironmentRendering", dependencies: ["RailwayRenderingCore"]),
        .target(name: "RailwayQualityRendering", dependencies: ["RailwayRenderingCore"]),
        .target(
            name: "RailwayRendering",
            dependencies: [
                "RailwayRenderingCore",
                "RailwayCameraRendering",
                "RailwayEnvironmentRendering",
                "RailwayQualityRendering"
            ]
        ),
        .testTarget(name: "RailwayRenderingTests", dependencies: ["RailwayRendering"])
    ]
)
