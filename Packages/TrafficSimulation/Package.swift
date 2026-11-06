// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "TrafficSimulation",
    platforms: [.iOS(.v17), .macOS(.v13)],
    products: [.library(name: "TrafficSimulation", targets: ["TrafficSimulation"])],
    targets: [
        .target(name: "TrafficSimulation", resources: [.process("Resources")]),
        .testTarget(name: "TrafficSimulationTests", dependencies: ["TrafficSimulation"])
    ]
)
