// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "RailwayMaintenance",
    platforms: [
        .iOS(.v17),
        .macOS(.v13)
    ],
    products: [
        .library(name: "RailwayMaintenance", targets: ["RailwayMaintenance"])
    ],
    targets: [
        .target(name: "RailwayMaintenance"),
        .testTarget(name: "RailwayMaintenanceTests", dependencies: ["RailwayMaintenance"])
    ]
)
