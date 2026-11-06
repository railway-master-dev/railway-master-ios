// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "EnvironmentConditions",
    products: [
        .library(name: "EnvironmentConditions", targets: ["EnvironmentConditions"])
    ],
    targets: [
        .target(name: "EnvironmentConditions"),
        .testTarget(name: "EnvironmentConditionsTests", dependencies: ["EnvironmentConditions"])
    ]
)
