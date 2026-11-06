// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "RailwaySignalling",
    platforms: [.iOS(.v17), .macOS(.v13)],
    products: [.library(name: "RailwaySignalling", targets: ["RailwaySignalling"])],
    targets: [.target(name: "RailwaySignalling")]
)
