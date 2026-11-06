// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "RailwaySessionPersistence",
    platforms: [
        .iOS(.v17),
        .macOS(.v13)
    ],
    products: [
        .library(name: "RailwaySessionPersistence", targets: ["RailwaySessionPersistence"])
    ],
    targets: [
        .target(name: "RailwaySessionPersistence"),
        .testTarget(
            name: "RailwaySessionPersistenceTests",
            dependencies: ["RailwaySessionPersistence"]
        )
    ]
)
