// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "CrewWorkflow",
    platforms: [
        .iOS(.v17),
        .macOS(.v13)
    ],
    products: [
        .library(name: "CrewWorkflow", targets: ["CrewWorkflow"])
    ],
    targets: [
        .target(name: "CrewWorkflow"),
        .testTarget(name: "CrewWorkflowTests", dependencies: ["CrewWorkflow"])
    ]
)
