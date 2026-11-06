// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "RailwaySceneFidelity",
    platforms: [.iOS(.v17)],
    products: [
        .library(name: "RailwaySceneFidelity", targets: ["RailwaySceneFidelity"])
    ],
    targets: [
        .target(
            name: "RailwaySceneFidelity",
            resources: [.process("Resources")]
        ),
        .testTarget(name: "RailwaySceneFidelityTests", dependencies: ["RailwaySceneFidelity"])
    ]
)
