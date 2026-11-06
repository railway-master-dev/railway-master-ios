// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "RailwayTrainPhysics",
    platforms: [
        .iOS(.v17),
        .macOS(.v13)
    ],
    products: [
        .library(name: "RailwayTrainPhysics", targets: ["TrainPhysics"])
    ],
    targets: [
        .target(
            name: "TrainPhysics",
            resources: [.process("Resources")]
        ),
        .testTarget(
            name: "TrainPhysicsTests",
            dependencies: ["TrainPhysics"]
        )
    ]
)
