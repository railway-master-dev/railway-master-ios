import XCTest
@testable import RailwaySceneFidelity

final class SceneCorridorLandmarkTests: XCTestCase {
    func testLandmarkScheduleIsDeterministicAndSkipsPlatforms() {
        let first = SceneCorridorLandmarkSchedule.landmarks(from: 0, to: 4_500)
        let second = SceneCorridorLandmarkSchedule.landmarks(from: 0, to: 4_500)
        XCTAssertEqual(first, second)
        XCTAssertEqual(first.map(\.startChainageM), first.map(\.startChainageM).sorted())

        let majors = first.filter { $0.kind != .levelCrossing }
        XCTAssertEqual(majors.map(\.kind), [.riverBridge, .cutting, .embankment])
        XCTAssertEqual(majors[0].startChainageM, 420, accuracy: 0.001)
        XCTAssertEqual(majors[0].lengthM, 96, accuracy: 0.001)
        XCTAssertEqual(majors[1].startChainageM, 2_020, accuracy: 0.001)
        XCTAssertEqual(majors[2].startChainageM, 3_620, accuracy: 0.001)

        let crossings = first.filter { $0.kind == .levelCrossing }
        XCTAssertEqual(crossings.map(\.startChainageM), [1_080, 2_680, 4_280])
        XCTAssertTrue(crossings.allSatisfy { $0.lengthM == SceneCorridorLandmarkSchedule.crossingLengthM })

        let blocked = ScenePlatformSpecification(
            id: "station-over-bridge", startChainageM: 400, endChainageM: 600, side: 1
        )
        let avoided = SceneCorridorLandmarkSchedule.landmarks(from: 0, to: 2_000, avoiding: [blocked])
        XCTAssertFalse(avoided.contains { $0.kind == .riverBridge })
        XCTAssertTrue(avoided.contains { $0.id == "fictional-levelCrossing-p0" })

        XCTAssertTrue(SceneCorridorLandmarkSchedule.landmarks(from: .nan, to: 100).isEmpty)
        XCTAssertTrue(SceneCorridorLandmarkSchedule.landmarks(from: 20, to: 10).isEmpty)
        XCTAssertTrue(SceneCorridorLandmarkSchedule.landmarks(from: 0, to: 424).isEmpty,
                      "A span with less than 8 m on the route is omitted")
        XCTAssertEqual(SceneCorridorLandmarkSchedule.landmarks(from: 0, to: 430).map(\.kind), [.riverBridge])
        XCTAssertFalse(first[0].contains(.nan))
    }

    func testBuilderPlacesFictionalCorridorLandmarksAndClearsUrbanFabric() throws {
        let plan = try fullPlan(urban: true, sceneryBudget: 4_000, vegetation: true)
        let roles = Set(plan.assemblies.map(\.role))
        XCTAssertTrue(roles.contains(.bridgeStructure))
        XCTAssertTrue(roles.contains(.cuttingWall))
        XCTAssertTrue(roles.contains(.embankment))
        XCTAssertTrue(roles.contains(.levelCrossing))
        XCTAssertTrue(roles.contains(.roadSurface))
        XCTAssertTrue(roles.contains(.building))

        let pieces = plan.assemblies.flatMap(\.pieces)
        XCTAssertTrue(pieces.contains { $0.material == .riverWater })
        XCTAssertTrue(pieces.contains { $0.material == .grassSlope })
        XCTAssertTrue(pieces.contains { $0.name == "raised-barrier-arm-1" })
        XCTAssertFalse(pieces.contains { $0.name.contains("lowered-barrier") })

        let landmarks = plan.assemblies.filter {
            [.bridgeStructure, .cuttingWall, .embankment, .levelCrossing].contains($0.role)
        }
        XCTAssertFalse(landmarks.isEmpty)
        XCTAssertTrue(landmarks.allSatisfy { $0.syntheticPlaceholderLabel?.contains("SYNTHETIC") == true })
        let crossing = try XCTUnwrap(plan.assemblies.first { $0.role == .levelCrossing })
        XCTAssertTrue(crossing.syntheticPlaceholderLabel?.contains("NOT INTERLOCKED") == true)

        let bridge = try XCTUnwrap(SceneCorridorLandmarkSchedule.landmarks(from: 0, to: 4_500).first { $0.kind == .riverBridge })
        let roadsOnBridge = plan.assemblies.filter {
            $0.role == .roadSurface && bridge.contains($0.chainageM, margin: 0)
        }
        XCTAssertTrue(roadsOnBridge.isEmpty)
        XCTAssertTrue(plan.assemblies.contains { $0.role == .roadSurface && $0.chainageM < 300 })

        let cutting = try XCTUnwrap(SceneCorridorLandmarkSchedule.landmarks(from: 0, to: 4_500).first { $0.kind == .cutting })
        XCTAssertFalse(plan.assemblies.contains { $0.role == .building && cutting.contains($0.chainageM) })
        XCTAssertFalse(plan.assemblies.contains { $0.role == .vegetation && cutting.contains($0.chainageM) })
        XCTAssertTrue(plan.assemblies.contains { $0.role == .building && $0.chainageM < 300 })
    }

    func testLandmarkGeometrySurvivesZeroSceneryBudget() throws {
        let route = try straightRoute(length: 4_500)
        let camera = camera(on: route, at: 200, far: 400)
        let blocked = SceneDensityControls(
            visibleDistanceM: 400, railChunkLengthM: 4,
            scenerySpacingM: 17, maxSceneryAssemblies: 0, detailLevel: 1,
            includeRoadVehicles: true, includePeople: true, includeVegetation: true
        )
        let plan = RailwaySceneFidelityBuilder.build(
            route: route, corridor: SceneCorridorSpecification(), camera: camera, density: blocked
        )
        let roles = Set(plan.assemblies.map(\.role))
        XCTAssertTrue(roles.contains(.trackBed))
        XCTAssertTrue(roles.contains(.bridgeStructure))
        XCTAssertTrue(plan.assemblies.contains { $0.pieces.contains { $0.material == .riverWater } })
        XCTAssertFalse(roles.contains(.building))
        XCTAssertFalse(roles.contains(.vegetation))
        XCTAssertFalse(roles.contains(.roadVehicle))
        XCTAssertTrue(plan.assemblies.contains { $0.role == .roadSurface && $0.chainageM < 350 })
    }

    func testLandmarkIdentityIsStableAcrossCameraWindows() throws {
        let wide = try fullPlan(urban: false, sceneryBudget: 0, vegetation: false)
        let route = try straightRoute(length: 4_500)
        let window = RailwaySceneFidelityBuilder.build(
            route: route,
            corridor: SceneCorridorSpecification(generateUrbanScenery: false),
            camera: camera(on: route, at: 470, far: 80),
            density: SceneDensityControls(visibleDistanceM: 80, maxSceneryAssemblies: 0, detailLevel: 2,
                                          includeRoadVehicles: false, includePeople: false, includeVegetation: false)
        )
        let windowIDs = window.assemblies.filter { $0.role == .bridgeStructure }.map(\.id)
        let wideIDs = Set(wide.assemblies.map(\.id))
        XCTAssertGreaterThan(windowIDs.count, 1)
        XCTAssertTrue(windowIDs.allSatisfy { wideIDs.contains($0) })
        let repeated = window.assemblies.filter { $0.role == .bridgeStructure }.map(\.id)
        XCTAssertEqual(windowIDs, repeated)
        XCTAssertEqual(Set(windowIDs).count, windowIDs.count)
    }

    private func fullPlan(urban: Bool, sceneryBudget: Int, vegetation: Bool) throws -> SceneBuildPlan {
        let route = try straightRoute(length: 4_500)
        let density = SceneDensityControls(
            visibleDistanceM: 5_000, railChunkLengthM: 6,
            scenerySpacingM: 40, maxSceneryAssemblies: sceneryBudget, detailLevel: 2,
            includeRoadVehicles: false, includePeople: false, includeVegetation: vegetation
        )
        return RailwaySceneFidelityBuilder.build(
            route: route,
            corridor: SceneCorridorSpecification(generateUrbanScenery: urban),
            camera: camera(on: route, at: 0, far: 5_000),
            density: density
        )
    }

    private func straightRoute(length: Double) throws -> SceneChainageRoute {
        try SceneChainageRoute(controlPoints: [
            SceneRouteControlPoint(chainageM: 0, position: .zero, tangentPerMeter: SceneVector3(0, 0, 1)),
            SceneRouteControlPoint(chainageM: length, position: SceneVector3(0, 0, length), tangentPerMeter: SceneVector3(0, 0, 1))
        ])
    }

    private func camera(on route: SceneChainageRoute, at chainage: Double, far: Double) -> SceneCameraState {
        let frame = route.frame(at: chainage) ?? route.frame(at: 0)!
        return SceneCameraState(
            position: frame.position + frame.up * 1.7,
            forward: frame.forward,
            chainageM: chainage,
            farDistanceM: far,
            towardIncreasingChainage: true
        )
    }
}
