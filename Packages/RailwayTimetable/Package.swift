// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "RailwayTimetable",
    platforms: [.iOS(.v16), .macOS(.v13)],
    products: [
        .library(name: "RailwayTimetable", targets: ["RailwayTimetable"])
    ],
    targets: [
        .target(
            name: "RailwayTimetable",
            path: "Sources/RailwayTimetable",
            resources: [.copy("Resources")]
        ),
        .testTarget(
            name: "RailwayTimetableTests",
            dependencies: ["RailwayTimetable"],
            path: "Tests/RailwayTimetableTests"
        )
    ]
)
