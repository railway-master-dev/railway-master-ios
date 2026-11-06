// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "DoorProcedureScoring",
    platforms: [.iOS(.v16), .macOS(.v13)],
    products: [
        .library(name: "DoorProcedureScoring", targets: ["DoorProcedureScoring"])
    ],
    targets: [
        .target(name: "DoorProcedureScoring"),
        .testTarget(name: "DoorProcedureScoringTests", dependencies: ["DoorProcedureScoring"])
    ]
)
