// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "VehicleGeometryUV",
    products: [
        .library(name: "VehicleGeometryUV", targets: ["VehicleGeometryUV"])
    ],
    targets: [
        .target(name: "VehicleGeometryUV"),
        .testTarget(name: "VehicleGeometryUVTests", dependencies: ["VehicleGeometryUV"])
    ]
)
