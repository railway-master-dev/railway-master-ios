// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "RailwayOperations",
    platforms: [
        .iOS(.v17),
        .macOS(.v13)
    ],
    products: [
        .library(name: "RailwayOperations", targets: ["RailwayOperations"])
    ],
    targets: [
        .target(name: "RailwayOperations"),
        .testTarget(name: "RailwayOperationsTests", dependencies: ["RailwayOperations"])
    ]
)
