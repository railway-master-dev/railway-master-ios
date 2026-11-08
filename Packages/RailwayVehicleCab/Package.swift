// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "RailwayVehicleCab",
    platforms: [.iOS(.v17)],
    products: [
        .library(name: "RailwayVehicleCab", targets: ["RailwayVehicleCab"])
    ],
    dependencies: [
        .package(path: "../RailwayAudioEnhancements")
    ],
    targets: [
        .target(
            name: "RailwayVehicleCab",
            dependencies: [.product(name: "RailwayAudioEnhancements", package: "RailwayAudioEnhancements")],
            resources: [.process("Resources")]
        ),
        .testTarget(name: "RailwayVehicleCabTests", dependencies: ["RailwayVehicleCab"])
    ]
)
