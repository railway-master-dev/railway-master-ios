import XCTest
@testable import RailwaySceneFidelity

final class RailwaySceneFidelityTests: XCTestCase {
    private func curvedRoute() throws -> SceneChainageRoute {
        try SceneChainageRoute(controlPoints: [
            SceneRouteControlPoint(chainageM: 0, position: SceneVector3(0, 0, 0),
                                   tangentPerMeter: SceneVector3(0.02, 0, 1)),
            SceneRouteControlPoint(chainageM: 120, position: SceneVector3(15, 0.8, 118),
                                   tangentPerMeter: SceneVector3(0.18, 0.01, 0.98), bankRadians: 0.035),
            SceneRouteControlPoint(chainageM: 260, position: SceneVector3(66, 1.2, 245),
                                   tangentPerMeter: SceneVector3(0.45, 0, 0.89), bankRadians: 0.06),
            SceneRouteControlPoint(chainageM: 500, position: SceneVector3(178, 0, 457),
                                   tangentPerMeter: SceneVector3(0.42, 0, 0.91))
        ])
    }

    private func camera(on route: SceneChainageRoute, at chainage: Double = 20,
                        forward: SceneVector3 = SceneVector3(0.02, 0, 1)) -> SceneCameraState {
        let frame = route.frame(at: chainage)!
        return SceneCameraState(position: frame.position + frame.up * 1.68,
                                forward: forward, chainageM: chainage,
                                verticalFieldOfViewRadians: 70 * .pi / 180,
                                aspectRatio: 1.8, farDistanceM: 1_500)
    }

    func testHermiteRouteUsesChainageAndCurveTangents() throws {
        let route = try curvedRoute()
        let start = try XCTUnwrap(route.frame(at: 10))
        let middle = try XCTUnwrap(route.frame(at: 190))
        let end = try XCTUnwrap(route.frame(at: 500))

        XCTAssertEqual(route.lengthM, 500, accuracy: 1e-9)
        XCTAssertNotEqual(start.forward.x, middle.forward.x, accuracy: 0.05)
        XCTAssertGreaterThan(middle.position.x, start.position.x)
        XCTAssertEqual(middle.forward.length, 1, accuracy: 1e-8)
        XCTAssertEqual(middle.right.length, 1, accuracy: 1e-8)
        XCTAssertEqual(middle.up.length, 1, accuracy: 1e-8)
        XCTAssertEqual(middle.forward.dot(middle.right), 0, accuracy: 1e-7)
        XCTAssertNil(route.frame(at: 501))
        XCTAssertEqual(end.chainageM, 500, accuracy: 1e-9)
    }

    func testRouteRejectsNonMonotonicAndCoincidentControlPoints() {
        XCTAssertThrowsError(try SceneChainageRoute(controlPoints: [
            SceneRouteControlPoint(chainageM: 10, position: SceneVector3.zero),
            SceneRouteControlPoint(chainageM: 9, position: SceneVector3(0, 0, 1))
        ]))
        XCTAssertThrowsError(try SceneChainageRoute(controlPoints: [
            SceneRouteControlPoint(chainageM: 0, position: .zero),
            SceneRouteControlPoint(chainageM: 1, position: .zero)
        ]))
    }

    func testBuilderCreatesDetailedTrackWiresAndSyntheticPlaceholderTags() throws {
        let route = try curvedRoute()
        let station = ScenePlatformSpecification(id: "fixture-platform", startChainageM: 0,
            endChainageM: 100, side: 1, offsetFromTrackCenterM: 4.8, widthM: 3.8)
        let corridor = SceneCorridorSpecification(platforms: [station])
        let viewpoint = camera(on: route)
        let plan = RailwaySceneFidelityBuilder.build(route: route, corridor: corridor,
            camera: viewpoint, density: .preset(.highDetail))
        let roles = Set(plan.assemblies.map(\.role))

        XCTAssertTrue(roles.contains(.trackBed))
        XCTAssertTrue(roles.contains(.rail))
        XCTAssertTrue(roles.contains(.sleeper))
        XCTAssertTrue(roles.contains(.trackFastener))
        XCTAssertTrue(roles.contains(.catenarySupport))
        XCTAssertTrue(roles.contains(.overheadWire))
        XCTAssertTrue(roles.contains(.platform))
        XCTAssertTrue(roles.contains(.roadSurface))
        XCTAssertTrue(roles.contains(.building))
        XCTAssertTrue(roles.contains(.roadVehicle))
        XCTAssertTrue(roles.contains(.pedestrian))
        XCTAssertTrue(roles.contains(.vegetation))
        XCTAssertGreaterThan(plan.diagnostics.generatedPieceCount, plan.assemblies.count)
        XCTAssertTrue(plan.assemblies.allSatisfy { $0.syntheticPlaceholderLabel?.contains("SYNTHETIC") == true })
        let supports = plan.assemblies.filter { $0.role == .catenarySupport }.sorted { $0.chainageM < $1.chainageM }
        XCTAssertGreaterThan(supports.count, 1)
        for (left, right) in zip(supports, supports.dropFirst()) {
            XCTAssertEqual(right.chainageM - left.chainageM, corridor.catenarySpacingM, accuracy: 1e-8)
        }

        let rail = try XCTUnwrap(plan.assemblies.first(where: { $0.role == .rail }))
        XCTAssertLessThan(abs(rail.forward.x), 0.2, "Rail assembly should follow local route tangent, not a world-axis plane")
        XCTAssertTrue(rail.pieces.contains(where: { $0.material == .polishedRailSteel }))
        let sleepers = plan.assemblies.flatMap(\.pieces).filter { $0.name.hasPrefix("sleeper-") }
        XCTAssertGreaterThan(sleepers.count, 20)
        XCTAssertTrue(plan.assemblies.contains(where: { $0.role == .stationFurniture }))
    }

    func testDensityChangesDetailBudgetWithoutChangingPhysicalSleeperCadence() throws {
        let route = try curvedRoute()
        let viewpoint = camera(on: route, at: 20)
        let lowDensity = SceneDensityControls(visibleDistanceM: 240, railChunkLengthM: 4.5,
            scenerySpacingM: 28, maxSceneryAssemblies: 300, detailLevel: 0,
            includeRoadVehicles: false, includePeople: false, includeVegetation: false)
        let highDensity = SceneDensityControls(visibleDistanceM: 240, railChunkLengthM: 1.5,
            scenerySpacingM: 8, maxSceneryAssemblies: 800, detailLevel: 2,
            includeRoadVehicles: false, includePeople: false, includeVegetation: false)
        let corridor = SceneCorridorSpecification(generateUrbanScenery: false)
        let low = RailwaySceneFidelityBuilder.build(route: route, corridor: corridor,
            camera: viewpoint, density: lowDensity)
        let high = RailwaySceneFidelityBuilder.build(route: route, corridor: corridor,
            camera: viewpoint, density: highDensity)
        let lowSleeperNames = low.assemblies.flatMap(\.pieces).filter { $0.name.hasPrefix("sleeper-") }.map(\.name).sorted()
        let highSleeperNames = high.assemblies.flatMap(\.pieces).filter { $0.name.hasPrefix("sleeper-") }.map(\.name).sorted()
        let lowSleepers = lowSleeperNames.count
        let highSleepers = highSleeperNames.count

        XCTAssertEqual(lowSleepers, highSleepers, "A quality preset must not distort the corridor's physical sleeper spacing")
        XCTAssertEqual(lowSleeperNames, highSleeperNames, "Sleeper chainage indices must not depend on track chunk size")
        XCTAssertEqual(lowSleepers, 434, "The [0, 260) m build interval contains 434 sleepers at 0.60 m spacing")
        XCTAssertGreaterThan(high.diagnostics.generatedPieceCount, low.diagnostics.generatedPieceCount)
        XCTAssertLessThanOrEqual(low.diagnostics.generatedAssemblyCount, high.diagnostics.generatedAssemblyCount + 20)
    }

    func testCullingUsesViewFrustumAndDistanceAndLodBands() {
        let controls = SceneDensityControls(visibleDistanceM: 800, detailLevel: 2)
        let camera = SceneCameraState(position: .zero, forward: .forward, chainageM: 0,
                                      verticalFieldOfViewRadians: 60 * .pi / 180,
                                      aspectRatio: 1, farDistanceM: 800)
        func assembly(_ id: String, at position: SceneVector3, radius: Double = 1) -> SceneAssembly {
            SceneAssembly(id: id, role: .building, chainageM: 0, position: position,
                          forward: .forward, right: SceneVector3(1, 0, 0), up: .up,
                          boundingRadiusM: radius, pieces: [], syntheticPlaceholderLabel: "SYNTHETIC TEST")
        }
        XCTAssertTrue(SceneCullingPolicy.isVisible(assembly("front", at: SceneVector3(0, 0, 35)),
                                                   camera: camera, maxDistanceM: controls.visibleDistanceM))
        XCTAssertFalse(SceneCullingPolicy.isVisible(assembly("behind", at: SceneVector3(0, 0, -35)),
                                                    camera: camera, maxDistanceM: controls.visibleDistanceM))
        XCTAssertFalse(SceneCullingPolicy.isVisible(assembly("far", at: SceneVector3(0, 0, 900)),
                                                    camera: camera, maxDistanceM: controls.visibleDistanceM))
        XCTAssertEqual(SceneCullingPolicy.levelOfDetail(distanceM: 25, controls: controls), .high)
        XCTAssertEqual(SceneCullingPolicy.levelOfDetail(distanceM: 200, controls: controls), .medium)
        XCTAssertEqual(SceneCullingPolicy.levelOfDetail(distanceM: 600, controls: controls), .far)
    }

    func testSceneryCapDoesNotRemoveEssentialTrack() throws {
        let route = try curvedRoute()
        let controls = SceneDensityControls(visibleDistanceM: 220, maxSceneryAssemblies: 0,
            detailLevel: 0, includeRoadVehicles: true, includePeople: true, includeVegetation: true)
        let plan = RailwaySceneFidelityBuilder.build(route: route,
            corridor: SceneCorridorSpecification(), camera: camera(on: route), density: controls)
        let roles = Set(plan.assemblies.map(\.role))
        XCTAssertTrue(roles.contains(.trackBed))
        XCTAssertTrue(roles.contains(.rail))
        XCTAssertTrue(roles.contains(.sleeper))
        XCTAssertTrue(roles.contains(.catenarySupport))
        XCTAssertFalse(roles.contains(.building))
        XCTAssertFalse(roles.contains(.roadVehicle))
        XCTAssertFalse(roles.contains(.vegetation))
    }

    func testSurfaceWeatherNormalizesInputsAndHandlesNonFiniteValues() {
        let clamped = SceneSurfaceWeather(wetness: 1.8, snowCoverage: -0.4)
        XCTAssertEqual(clamped.wetness, 1)
        XCTAssertEqual(clamped.snowCoverage, 0)

        let nonFinite = SceneSurfaceWeather(wetness: .nan, snowCoverage: .infinity)
        XCTAssertEqual(nonFinite.wetness, 0)
        XCTAssertEqual(nonFinite.snowCoverage, 0)
        XCTAssertEqual(SceneSurfaceWeather.dry, SceneSurfaceWeather())
    }
}
