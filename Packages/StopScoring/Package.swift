// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "StopScoring",
    platforms: [.iOS(.v16), .macOS(.v13)],
    products: [
        .library(name: "StopScoring", targets: ["StopScoring"])
    ],
    targets: [
        .target(name: "StopScoring"),
        .testTarget(name: "StopScoringTests", dependencies: ["StopScoring"])
    ]
)
