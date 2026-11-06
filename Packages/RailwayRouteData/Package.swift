// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "RailwayRouteData",
    platforms: [.iOS(.v16), .macOS(.v13)],
    products: [.library(name: "RailwayRouteData", targets: ["RailwayRouteData"])],
    targets: [
        .target(
            name: "RailwayRouteData",
            path: ".",
            exclude: ["Tests", "Tools", "README.md", "Package.swift"],
            sources: ["Sources/RailwayRouteData"],
            resources: [.copy("Data")]
        )
    ]
)
