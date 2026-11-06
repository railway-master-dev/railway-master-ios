// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "IncidentMaintenance",
    platforms: [.iOS(.v17), .macOS(.v13)],
    products: [
        .library(name: "IncidentMaintenance", targets: ["IncidentMaintenance"])
    ],
    targets: [
        .target(name: "IncidentMaintenance"),
        .testTarget(name: "IncidentMaintenanceTests", dependencies: ["IncidentMaintenance"])
    ]
)
