// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "RailwayVehicleHighFidelity",
    platforms: [.iOS(.v17)],
    products: [
        .library(name: "RailwayVehicleHighFidelity", targets: ["RailwayVehicleHighFidelity"])
    ],
    dependencies: [
        .package(path: "../RailwayAudioEnhancements")
    ],
    targets: [
        .target(
            name: "RailwayVehicleHighFidelity",
            dependencies: [.product(name: "RailwayAudioEnhancements", package: "RailwayAudioEnhancements")]
        ),
        .testTarget(name: "RailwayVehicleHighFidelityTests", dependencies: ["RailwayVehicleHighFidelity"])
    ]
)
