import XCTest
import Foundation
import RailwayRouteData
import RailwaySignalling
import TrafficSimulation
@testable import RailwayMasterPhase1

final class RegionalIntegrationTests: XCTestCase {
    func testSeededMainlineCurvesAreDeterministicContinuousAndBounded() throws {
        let plan = try XCTUnwrap(FictionalOperationsPlan.loadBundled())
        let seed: UInt64 = 0x1234_5678_9ABC_DEF0
        let route = try RegionalRouteFactory.make(plan: plan, variant: .mainline, direction: .up, geometrySeed: seed)
        let sameSeed = try RegionalRouteFactory.make(plan: plan, variant: .mainline, direction: .up, geometrySeed: seed)
        let otherSeed = try RegionalRouteFactory.make(plan: plan, variant: .mainline, direction: .up, geometrySeed: seed &+ 1)

        XCTAssertEqual(route.geometrySeed, seed)
        XCTAssertEqual(try JSONEncoder().encode(route.profile.sections), try JSONEncoder().encode(sameSeed.profile.sections))
        XCTAssertNotEqual(try JSONEncoder().encode(route.profile.sections), try JSONEncoder().encode(otherSeed.profile.sections))
        XCTAssertFalse(route.profile.validateData().contains { $0.severity == .error })

        let baseRadii = route.profile.sections.compactMap(\.curveRadiusM)
        XCTAssertFalse(baseRadii.isEmpty)
        XCTAssertTrue(baseRadii.allSatisfy { (900...1_850).contains($0) })
        let baseCants = route.profile.sections.compactMap(\.cantMm)
        XCTAssertTrue(baseCants.allSatisfy { (55...105).contains($0) })
        XCTAssertEqual(Set(route.profile.sections.compactMap(\.curveDirection)), Set([-1, 1]))

        let uniqueRuns = Dictionary(
            grouping: route.profile.sections.compactMap(\.curveTransition),
            by: \.startM
        ).values.compactMap(\.first)
        XCTAssertGreaterThan(uniqueRuns.count, 10)
        XCTAssertTrue(uniqueRuns.allSatisfy(\.isValid))

        var curvedSamples = 0
        var totalSamples = 0
        var previousCurvature = 0.0
        var previousCant = 0.0
        for chainage in stride(from: 0.0, through: 60_000.0, by: 10.0) {
            let condition = route.profile.condition(at: chainage)
            let curvature = condition.curveRadiusM.map { 1 / $0 } ?? 0
            let cant = condition.cantMm ?? 0
            if condition.curveRadiusM != nil { curvedSamples += 1 }
            if totalSamples > 0 {
                XCTAssertLessThanOrEqual(abs(curvature - previousCurvature), 0.0002)
                XCTAssertLessThanOrEqual(abs(cant - previousCant), 4.2)
            }
            previousCurvature = curvature
            previousCant = cant
            totalSamples += 1
        }
        let curvedShare = Double(curvedSamples) / Double(totalSamples)
        XCTAssertTrue((0.45...0.70).contains(curvedShare), "Unexpected randomized curve share: \(curvedShare)")
    }

    func testBranchAndDepotUseTheirOwnCurveRadiusRangesAndBranchLineIsReusable() throws {
        let plan = try XCTUnwrap(FictionalOperationsPlan.loadBundled())
        let seed = RegionalRouteFactory.defaultGeometrySeed
        let branch = try RegionalRouteFactory.make(plan: plan, variant: .branchShuttle, direction: .up, geometrySeed: seed)
        let depot = try RegionalRouteFactory.make(plan: plan, variant: .depotTransfer, direction: .up, geometrySeed: seed)
        let through = try RegionalRouteFactory.make(plan: plan, variant: .throughBranch, direction: .up, geometrySeed: seed)
        let branchRadii = branch.profile.sections.compactMap(\.curveRadiusM)
        let depotRadii = depot.profile.sections.compactMap(\.curveRadiusM)
        XCTAssertFalse(branchRadii.isEmpty)
        XCTAssertFalse(depotRadii.isEmpty)
        XCTAssertTrue(branchRadii.allSatisfy { (450...900).contains($0) })
        XCTAssertTrue(depotRadii.allSatisfy { (450...650).contains($0) })

        for localM in stride(from: 0.0, through: 7_950.0, by: 50.0) {
            let throughCondition = through.profile.condition(at: 60_000 + localM)
            let branchCondition = branch.profile.condition(at: localM)
            XCTAssertEqual(throughCondition.curveRadiusM ?? 0, branchCondition.curveRadiusM ?? 0, accuracy: 1e-9)
            XCTAssertEqual(throughCondition.curveDirection, branchCondition.curveDirection)
            XCTAssertEqual(throughCondition.cantMm ?? 0, branchCondition.cantMm ?? 0, accuracy: 1e-9)
            XCTAssertEqual(throughCondition.gradientPermille, branchCondition.gradientPermille, accuracy: 1e-9)
        }
    }

    func testDownDirectionMirrorsMainlineGeometryWithoutDiscontinuities() throws {
        let plan = try XCTUnwrap(FictionalOperationsPlan.loadBundled())
        let seed = RegionalRouteFactory.defaultGeometrySeed
        let up = try RegionalRouteFactory.make(plan: plan, variant: .mainline, direction: .up, geometrySeed: seed)
        let down = try RegionalRouteFactory.make(plan: plan, variant: .mainline, direction: .down, geometrySeed: seed)
        for chainage in stride(from: 0.0, through: 60_000.0, by: 50.0) {
            let forward = up.profile.condition(at: chainage)
            let reverse = down.profile.condition(at: 60_000 - chainage)
            XCTAssertEqual(forward.curveRadiusM ?? 0, reverse.curveRadiusM ?? 0, accuracy: 1e-8)
            XCTAssertEqual(forward.cantMm ?? 0, reverse.cantMm ?? 0, accuracy: 1e-8)
            XCTAssertEqual(forward.gradientPermille, -reverse.gradientPermille, accuracy: 1e-8)
            XCTAssertEqual(forward.speedLimitKmh, reverse.speedLimitKmh, accuracy: 1e-8)
            if let direction = forward.curveDirection {
                XCTAssertEqual(reverse.curveDirection, -direction)
            } else {
                XCTAssertNil(reverse.curveDirection)
            }
        }
    }

    func testSeededPolylineSamplerProducesConnectedFinitePointsAndContinuousFrames() throws {
        let plan = try XCTUnwrap(FictionalOperationsPlan.loadBundled())
        let route = try RegionalRouteFactory.make(
            plan: plan, variant: .mainline, direction: .up, geometrySeed: RegionalRouteFactory.defaultGeometrySeed
        )
        let samples = RegionalRouteGeometrySampler.makeSamples(route: route.profile, interval: 10)
        XCTAssertEqual(samples.count, 6_001)
        XCTAssertEqual(samples.first?.distanceM ?? -1, 0, accuracy: 1e-12)
        XCTAssertEqual(samples.last?.distanceM ?? -1, route.profile.distanceM, accuracy: 1e-12)

        for (first, next) in zip(samples, samples.dropFirst()) {
            let deltaM = next.distanceM - first.distanceM
            let dx = Double(next.x - first.x)
            let dz = Double(next.z - first.z)
            XCTAssertGreaterThan(deltaM, 0)
            XCTAssertEqual(hypot(dx, dz), deltaM, accuracy: 0.03)
            XCTAssertTrue(next.x.isFinite && next.z.isFinite && next.heading.isFinite && next.bankRadians.isFinite)
            XCTAssertLessThan(abs(Double(next.heading - first.heading)), 0.05)
            XCTAssertLessThan(abs(Double(next.bankRadians - first.bankRadians)), 0.01)
        }
    }

    func testCanonicalOperationsPlanUsesOneCoherentPlaceholderNetwork() throws {
        let plan = try XCTUnwrap(FictionalOperationsPlan.loadBundled())
        XCTAssertEqual(plan.network.mainlineLengthKm, 60, accuracy: 0.001)
        XCTAssertEqual(plan.network.branchLengthKm, 8, accuracy: 0.001)
        XCTAssertEqual(plan.network.depotSpurLengthKm, 2, accuracy: 0.001)
        XCTAssertEqual(plan.network.totalRouteLengthKm, 70, accuracy: 0.001)
        XCTAssertEqual(plan.stations.count, 32)
        XCTAssertEqual(plan.services.count, 6)
        XCTAssertEqual(plan.timetablePatterns.count, 48)
        XCTAssertTrue(plan.validationIssues.isEmpty, plan.validationIssues.joined(separator: "\n"))
        XCTAssertTrue(plan.services.allSatisfy { abs($0.routeDistanceKm - 68) < 0.001 })
    }

    func testRapidAndExpressHaveDistinctOrderedStopsOnTheSameFictionalPassengerRoute() throws {
        let plan = try XCTUnwrap(FictionalOperationsPlan.loadBundled())
        let rapidService = try XCTUnwrap(plan.services.first { $0.category == .rapid })
        let expressService = try XCTUnwrap(plan.services.first { $0.category == .express })
        let rapidIDs = ["S01", "S04", "S07", "S10", "S12", "S16", "S20", "S24", "S28", "B02", "B04"]
        let expressIDs = ["S01", "S07", "S12", "S16", "S20", "S24", "S28", "B02", "B04"]

        XCTAssertEqual(rapidService.stopStationIDs, rapidIDs)
        XCTAssertEqual(expressService.stopStationIDs, expressIDs)

        // Service hierarchy must be monotonic: in rank order
        // limitedExpress > rapidExpress > express > rapid > semiExpress > local,
        // stop counts and planned durations must both strictly increase.
        let rapidExpressService = try XCTUnwrap(plan.services.first { $0.category == .rapidExpress })
        XCTAssertEqual(rapidExpressService.stopStationIDs, ["S01", "S11", "S16", "S21", "S26", "S28", "B04"])
        let hierarchyOrder: [ServiceCategory] = [.limitedExpress, .rapidExpress, .express, .rapid, .semiExpress, .local]
        let hierarchyServices = try hierarchyOrder.map { category in
            try XCTUnwrap(plan.services.first { $0.category == category })
        }
        for (faster, slower) in zip(hierarchyServices, hierarchyServices.dropFirst()) {
            XCTAssertLessThan(faster.stopStationIDs.count, slower.stopStationIDs.count)
            XCTAssertLessThan(faster.plannedDurationMinutes, slower.plannedDurationMinutes)
            XCTAssertEqual(faster.stopStationIDs.first, slower.stopStationIDs.first)
            XCTAssertEqual(faster.stopStationIDs.last, slower.stopStationIDs.last)
        }
        XCTAssertNotEqual(rapidIDs, expressIDs)
        XCTAssertTrue(Set(expressIDs).isSubset(of: Set(rapidIDs)))
        XCTAssertEqual(rapidIDs.first, plan.network.mainlineTermini.first)
        XCTAssertEqual(expressIDs.first, plan.network.mainlineTermini.first)
        XCTAssertEqual(Array(rapidIDs.suffix(3)), ["S28", "B02", "B04"])
        XCTAssertEqual(Array(expressIDs.suffix(3)), ["S28", "B02", "B04"])
        XCTAssertEqual(rapidIDs.last, plan.network.branchTerminalStationID)
        XCTAssertEqual(expressIDs.last, plan.network.branchTerminalStationID)

        let stationNames = Dictionary(uniqueKeysWithValues: plan.stations.map { ($0.stationId, $0.name) })
        for (category, expectedIDs) in [(ServiceCategory.rapid, rapidIDs), (.express, expressIDs)] {
            let up = try RegionalRouteFactory.make(plan: plan, variant: .throughBranch, category: category, direction: .up)
            let down = try RegionalRouteFactory.make(plan: plan, variant: .throughBranch, category: category, direction: .down)
            XCTAssertEqual(up.stops.map(\.stationID), expectedIDs)
            XCTAssertEqual(down.stops.map(\.stationID), Array(expectedIDs.reversed()))
            for trip in [up, down] {
                XCTAssertEqual(trip.stops.first?.positionM ?? -1, 0, accuracy: 0.001)
                XCTAssertEqual(trip.stops.last?.positionM ?? -1, 68_000, accuracy: 0.001)
                XCTAssertTrue(zip(trip.stops, trip.stops.dropFirst()).allSatisfy { pair in
                    pair.0.positionM < pair.1.positionM
                })
                XCTAssertTrue(trip.stops.allSatisfy { stop in
                    stop.name == (stationNames[stop.stationID] ?? "")
                })
            }
        }

        XCTAssertTrue(plan.timetablePatterns.filter { $0.category == .rapid }.allSatisfy {
            $0.plannedDurationMinutes == rapidService.plannedDurationMinutes
        })
        XCTAssertTrue(plan.timetablePatterns.filter { $0.category == .express }.allSatisfy {
            $0.plannedDurationMinutes == expressService.plannedDurationMinutes
        })
    }

    func testPackageFixturesUseCanonicalNetworkLengths() throws {
        let route = try RoutePackageLoader.loadResource(named: "fictional_70km_network")
        let routeReport = RouteValidator.validate(route)
        XCTAssertTrue(routeReport.isStructurallyValid)
        XCTAssertEqual(route.route.totalLengthM.value ?? 0, 60_000, accuracy: 0.001)
        XCTAssertEqual(route.route.networkLengthM.value ?? 0, 70_000, accuracy: 0.001)
        XCTAssertEqual(route.route.stations.count, 32)
        XCTAssertEqual(Set(route.route.tracks.map(\.trackID)), Set(["main_line", "branch_line", "depot_spur"]))
        let extents = Dictionary(uniqueKeysWithValues: route.route.tracks.map { track in
            (track.trackID, (track.segments.last?.endChainageM.value ?? 0) - (track.segments.first?.startChainageM.value ?? 0))
        })
        XCTAssertEqual(extents["main_line"] ?? 0, 60_000, accuracy: 0.001)
        XCTAssertEqual(extents["branch_line"] ?? 0, 8_000, accuracy: 0.001)
        XCTAssertEqual(extents["depot_spur"] ?? 0, 2_000, accuracy: 0.001)
        let origin = RouteQuery.position(at: 0, trackID: route.route.mainTrackID, in: route)
        XCTAssertNotNil(origin)
        XCTAssertNotNil(origin?.nextStation)

        let signalling = try FictionalRailwayNetwork.fictional70kmSample()
        XCTAssertEqual(signalling.totalTrackLengthM, 70_000, accuracy: 0.001)
        XCTAssertEqual(try signalling.distanceFromOriginM(to: "takane", on: "main-up"), 60_000, accuracy: 0.001)
        XCTAssertEqual(try signalling.distanceFromOriginM(to: "hoshizawa", on: "branch-up"), 68_000, accuracy: 0.001)

        let traffic = try TrafficScenarioLibrary.loadBundledRegionalNetwork()
        XCTAssertTrue(traffic.validate().isEmpty, traffic.validate().map(\.message).joined(separator: "\n"))
        XCTAssertEqual(traffic.totalNetworkLengthM, 70_000, accuracy: 0.001)
    }

    func testRegionalAdaptersAgreeAndTrafficPreviewAdvances() throws {
        let report = RegionalNetworkIntegration.load()
        XCTAssertTrue(report.issues.isEmpty, report.issues.joined(separator: "\n"))
        XCTAssertEqual(report.canonicalTrackLengthKm ?? 0, 70, accuracy: 0.001)
        XCTAssertEqual(report.canonicalServiceCount, 6)
        XCTAssertNotNil(report.sourceRoutePosition)
        XCTAssertTrue(report.sourceRouteValidation?.isStructurallyValid ?? false)
        XCTAssertEqual(report.trafficValidationIssues.count, 0)

        let scenario = try XCTUnwrap(report.trafficScenario)
        var engine = try TrafficSimulationEngine(scenario: scenario)
        let initial = engine.snapshot()
        let advanced = try engine.advance(realDeltaSeconds: 10)
        XCTAssertEqual(advanced.simulationTimeSeconds, 10, accuracy: 0.02)
        XCTAssertGreaterThan(advanced.fixedTick, initial.fixedTick)
        XCTAssertEqual(advanced.trains.count, initial.trains.count)
    }

    func testEveryRouteVariantServiceAndDirectionProducesOrderedPlayableStops() throws {
        let plan = try XCTUnwrap(FictionalOperationsPlan.loadBundled())
        var combinations = 0
        for variant in RegionalRouteVariant.allCases {
            for service in ServiceCategory.allCases {
                for direction in RegionalTravelDirection.allCases {
                    let trip = try RegionalRouteFactory.make(
                        plan: plan,
                        variant: variant,
                        category: service,
                        direction: direction
                    )
                    combinations += 1
                    XCTAssertEqual(trip.profile.dataStatus, .placeholder)
                    XCTAssertGreaterThanOrEqual(trip.stops.count, 2)
                    XCTAssertEqual(trip.stops.first?.positionM ?? -1, 0, accuracy: 0.001)
                    XCTAssertEqual(trip.stops.last?.positionM ?? -1, trip.profile.distanceM, accuracy: 0.001)
                    XCTAssertTrue(zip(trip.stops, trip.stops.dropFirst()).allSatisfy { pair in
                        pair.0.positionM < pair.1.positionM
                    }, "Non-increasing stops for \(variant)/\(service)/\(direction)")
                    XCTAssertFalse(trip.profile.validateData().contains { $0.severity == .error })
                }
            }
        }
        XCTAssertEqual(combinations, RegionalRouteVariant.allCases.count * ServiceCategory.allCases.count * RegionalTravelDirection.allCases.count)
    }

    func testTrafficRuntimeStateRoundTripsAndContinuesDeterministically() throws {
        let scenario = try TrafficScenarioLibrary.loadBundledRegionalNetwork()
        var original = try TrafficSimulationEngine(scenario: scenario)
        _ = try original.advance(realDeltaSeconds: 19.375)
        let data = try JSONEncoder().encode(original.stateSnapshot())
        let saved = try JSONDecoder().decode(TrafficSimulationStateSnapshot.self, from: data)
        var restored = try TrafficSimulationEngine(scenario: scenario)
        try restored.restoreState(from: saved)

        XCTAssertEqual(restored.stateSnapshot(), original.stateSnapshot())
        _ = try original.advance(realDeltaSeconds: 3.25)
        _ = try restored.advance(realDeltaSeconds: 3.25)
        XCTAssertEqual(restored.snapshot(), original.snapshot())

        var incompatible = saved
        incompatible.scenarioID = "different-scenario"
        XCTAssertThrowsError(try restored.restoreState(from: incompatible))
    }
}
