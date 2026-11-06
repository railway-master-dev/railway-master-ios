import XCTest
@testable import RailwaySceneFidelity

final class SceneryVarietyTests: XCTestCase {
    func testOriginalSurfacesCoverGroundStructuresAndVegetation() throws {
        let required: [SceneMaterialStyle] = [
            .ballast, .concrete, .platformConcrete, .grassSlope, .roadAsphalt,
            .buildingWarm, .buildingCool, .darkSteel, .foliageDeep, .bark
        ]
        for style in required {
            let record = try XCTUnwrap(SceneSurfaceTextureCatalog.record(for: style))
            XCTAssertTrue(record.resourceName.hasPrefix("scenery_"))
            XCTAssertTrue(record.originNote.contains("ORIGINAL"))
            XCTAssertTrue(record.originNote.contains("No downloaded photograph"))
            XCTAssertTrue(record.originNote.contains("cab reference photo"))
        }
        XCTAssertNil(SceneSurfaceTextureCatalog.record(for: .windowGlass))
        XCTAssertEqual(Set(SceneSurfaceTextureCatalog.resourceNames).count, 9)
    }

    func testCabViewGetsMoreThanOneBuildingAndPlantForm() throws {
        let route = try straight(length: 4_500)
        let platform = ScenePlatformSpecification(id: "fictional-platform", startChainageM: 40, endChainageM: 220, side: 1)
        let plan = RailwaySceneFidelityBuilder.build(
            route: route,
            corridor: SceneCorridorSpecification(platforms: [platform], generateUrbanScenery: true),
            camera: camera(on: route, at: 200, far: 4_200),
            density: SceneDensityControls(
                visibleDistanceM: 4_200, railChunkLengthM: 8,
                scenerySpacingM: 40, maxSceneryAssemblies: 4_000, detailLevel: 2,
                includeRoadVehicles: false, includePeople: false, includeVegetation: true
            )
        )
        let names = Set(plan.assemblies.flatMap { $0.pieces.map(\.name) })
        XCTAssertTrue(names.contains("facade-volume"))
        XCTAssertTrue(names.contains("house-roof"))
        XCTAssertTrue(names.contains("warehouse-volume"))
        XCTAssertTrue(names.contains("shop-awning"))
        XCTAssertTrue(names.contains { $0.hasPrefix("hedge-mass") })
        XCTAssertTrue(names.contains { $0.hasPrefix("cluster-trunk") })
        XCTAssertTrue(names.contains("platform-bin"))
        XCTAssertTrue(names.contains { $0.hasPrefix("approach-verge") })

        let crossings = SceneCorridorLandmarkSchedule.landmarks(from: 0, to: 4_500).filter { $0.kind == .levelCrossing }
        XCTAssertEqual(crossings.map(\.startChainageM), [1_080, 2_680, 4_280])
    }

    private func straight(length: Double) throws -> SceneChainageRoute {
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
