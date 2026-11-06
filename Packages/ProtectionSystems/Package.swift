// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "FictionalRailwayProtectionSystems",
    platforms: [.iOS(.v17), .macOS(.v13)],
    products: [
        .library(name: "ProtectionSystems", targets: ["ProtectionSystems"])
    ],
    targets: [
        .target(name: "ProtectionSystems"),
        .testTarget(name: "ProtectionSystemsTests", dependencies: ["ProtectionSystems"])
    ]
)
