import RailwayTimetable
import RailwayGameModes
import TrainPhysics
import RailwayRouteData
import StopScoring
import XCTest
@testable import RailwayMasterPhase1

final class GameSystemsIntegrationTests: XCTestCase {
    func testCanonicalTimetableIncludesAllCalendarsAndSixServices() throws {
        let network = try RegionalTimetableAdapter.loadCanonicalNetwork()
        XCTAssertEqual(network.dataStatus, .placeholder)
        XCTAssertEqual(network.physicalNetworkLengthM, 70_000, accuracy: 0.01)
        XCTAssertEqual(network.passengerRouteLengthM, 68_000, accuracy: 0.01)
        XCTAssertEqual(network.services.count, 6)
        XCTAssertEqual(network.patterns.count, 3 * 6 * 2 * 4)
        XCTAssertEqual(Set(network.patterns.map(\.calendar)), Set(RailwayTimetable.ServiceCalendar.allCases))
        XCTAssertFalse(network.depotMovements.isEmpty)
        XCTAssertTrue(network.depotMovements.allSatisfy { $0.dataStatus == .placeholder })
    }

    func testDelayScenarioBuildsOriginHoldAndStationScoringSchedules() throws {
        let network = try RegionalTimetableAdapter.loadCanonicalNetwork()
        let plan = try XCTUnwrap(FictionalOperationsPlan.loadBundled())
        let trip = try RegionalRouteFactory.make(
            plan: plan,
            variant: .throughBranch,
            category: .local,
            direction: .up
        )
        let origin = try XCTUnwrap(trip.stops.first?.stationID)
        let selection = try RegionalTimetableAdapter.selectRun(
            network: network,
            category: .local,
            direction: .up,
            calendar: .weekday,
            daypart: .morningRush,
            initialDelayMinutes: 5,
            routeOriginStationID: origin
        )
        XCTAssertGreaterThanOrEqual(selection.routeOriginDelaySeconds, 300)
        let schedules = RegionalTimetableAdapter.stopSchedules(from: selection, activeStops: trip.stops)
        XCTAssertEqual(schedules.count, trip.stops.count - 1)
        XCTAssertTrue(schedules.values.allSatisfy {
            ($0.scheduledArrivalSeconds ?? -1) >= 0 &&
            ($0.scheduledDepartureSeconds ?? -1) >= ($0.scheduledArrivalSeconds ?? .infinity)
        })
    }

    func testPerStopScoreIncludesPrecisionAndSelectedTimetablePenalty() throws {
        let network = try RegionalTimetableAdapter.loadCanonicalNetwork()
        let plan = try XCTUnwrap(FictionalOperationsPlan.loadBundled())
        let trip = try RegionalRouteFactory.make(
            plan: plan,
            variant: .mainline,
            category: .local,
            direction: .up
        )
        let origin = try XCTUnwrap(trip.stops.first?.stationID)
        let selection = try RegionalTimetableAdapter.selectRun(
            network: network,
            category: .local,
            direction: .up,
            calendar: .weekday,
            daypart: .daytime,
            initialDelayMinutes: 0,
            routeOriginStationID: origin
        )
        let schedules = RegionalTimetableAdapter.stopSchedules(from: selection, activeStops: trip.stops)
        let routePackage = try RailwayRouteData.RoutePackageLoader.loadResource(named: "fictional_70km_network")
        let prepared = try StopScoringRouteAdapter.prepare(
            trip: trip,
            plan: plan,
            routePackage: routePackage,
            trainLengthMeters: 78,
            scheduleByStationID: schedules
        )
        let definition = try XCTUnwrap(prepared.stationDefinitions.first)
        let plannedArrival = try XCTUnwrap(definition.schedule.scheduledArrivalSeconds)
        var scorer = prepared.engine
        let tick = try StopScoring.SimulationTick(
            sequence: 1,
            simulationTimeSeconds: plannedArrival + 150,
            leadingEndChainageMeters: definition.targetStopChainageMeters,
            speedMetersPerSecond: 0
        )
        let events = [
            try StopScoring.StationEvent(eventID: "timing-arrival", stationID: definition.stationID, kind: .arrival),
            try StopScoring.StationEvent(eventID: "timing-stop", stationID: definition.stationID, kind: .stopCompleted)
        ]
        let evaluation = try scorer.process(tick: tick, events: events)
        let station = try XCTUnwrap(evaluation.stationEvaluations.first { $0.stationID == definition.stationID })
        let measurement = try XCTUnwrap(station.stopMeasurement)

        XCTAssertEqual(measurement.absoluteErrorMeters, 0, accuracy: 0.01)
        XCTAssertEqual(station.componentScores.stop, 100, accuracy: 0.01)
        XCTAssertGreaterThan(station.arrivalDeviationSeconds ?? 0, 100)
        XCTAssertLessThan(station.componentScores.timetable, 100)
    }

    func testBranchShuttleStopsMatchTheSelectedServicePattern() throws {
        let plan = try XCTUnwrap(FictionalOperationsPlan.loadBundled())
        let express = try RegionalRouteFactory.make(
            plan: plan,
            variant: .branchShuttle,
            category: .express,
            direction: .up
        )
        let local = try RegionalRouteFactory.make(
            plan: plan,
            variant: .branchShuttle,
            category: .local,
            direction: .up
        )
        XCTAssertEqual(express.stops.first?.stationID, plan.network.branchJunctionStationID)
        XCTAssertEqual(try XCTUnwrap(express.stops.last?.positionM), 8_000, accuracy: 0.01)
        XCTAssertLessThan(express.stops.count, local.stops.count)
        XCTAssertTrue(express.stops.dropFirst().allSatisfy { stop in
            plan.services.first(where: { $0.category == .express })?.stopStationIDs.contains(stop.stationID) == true
        })
    }

    func testEveryVehicleProfileLoadsItsPerCarPhysicsDefinition() throws {
        for profile in FictionalVehicleProfile.allCases {
            let physics = try TrainPhysics.FictionalProfileCatalog.profile(identifier: profile.physicsProfileIdentifier)
            XCTAssertEqual(physics.cars.count, profile.carCount, profile.rawValue)
            XCTAssertTrue(physics.validationIssues().isEmpty, profile.rawValue)
        }
    }

    func testHostAdvanceExecutesOneAuthoritativeFixedPhysicsTick() throws {
        var engine = try TrainPhysics.TrainPhysicsEngine(
            profile: TrainPhysics.FictionalProfileCatalog.profile(identifier: "fictional-field-chopper-t01"),
            passengerLoadFactor: 0.7
        )
        let ticks = engine.advance(
            realDeltaSeconds: TrainPhysics.PhysicsConstants.fixedTimeStepSeconds,
            controls: TrainPhysics.SimulationControls(throttleNotch: 1),
            track: TrainPhysics.TrackCondition.level,
            surface: .dry
        )
        XCTAssertEqual(ticks, 1)
        XCTAssertEqual(engine.telemetry.cars.count, engine.profile.cars.count)
        XCTAssertEqual(engine.telemetry.simulationTimeSeconds, TrainPhysics.PhysicsConstants.fixedTimeStepSeconds, accuracy: 1e-12)
    }

    @MainActor
    func testGameModeSessionAdvancesFromHostTicksWithoutSheetObserver() throws {
        let model = SimulatorModel()
        let snapshot = try XCTUnwrap(model.gameModeSnapshot)
        let session = try RegionalGameModeAdapter.makeSession(
            mode: .fullLine,
            playStyle: .standard,
            context: model.gameModeContext,
            snapshot: snapshot
        )
        XCTAssertEqual(session.status, .ready)
        model.setGameModeSession(session)

        model.advance(at: 100)
        model.advance(at: 100.25)

        let advanced = try XCTUnwrap(model.gameModeSession)
        XCTAssertEqual(advanced.status, .active)
        XCTAssertGreaterThanOrEqual(advanced.lastSnapshot.fixedTick, 24)
        XCTAssertEqual(advanced.lastSnapshot.routeID, model.routeID)
    }

    @MainActor
    func testGameModeSessionStateSnapshotRestoresAndContinues() throws {
        let model = SimulatorModel()
        let initialSnapshot = try XCTUnwrap(model.gameModeSnapshot)
        var original = try RegionalGameModeAdapter.makeSession(
            mode: .fullLine,
            playStyle: .standard,
            context: model.gameModeContext,
            snapshot: initialSnapshot
        )
        try original.apply(.start)
        let payload = try JSONEncoder().encode(original.stateSnapshot())
        let saved = try JSONDecoder().decode(GameModeSessionStateSnapshot.self, from: payload)

        var restored = try RegionalGameModeAdapter.makeSession(
            mode: .fullLine,
            playStyle: .standard,
            context: model.gameModeContext,
            snapshot: initialSnapshot
        )
        try restored.restoreState(from: saved)
        XCTAssertEqual(restored.stateSnapshot(), original.stateSnapshot())

        model.advance(at: 200)
        model.advance(at: 200.25)
        let nextSnapshot = try XCTUnwrap(model.gameModeSnapshot)
        try original.update(with: nextSnapshot)
        try restored.update(with: nextSnapshot)
        XCTAssertEqual(restored.stateSnapshot(), original.stateSnapshot())
    }

    @MainActor
    func testManualSaveRestoresRunningSimulationAndKeepsItPaused() throws {
        let model = SimulatorModel()
        defer {
            model.setAudioEnabled(true)
            model.setAudioVolume(0.65)
        }
        model.setThrottle(3)
        model.setAudioEnabled(false)
        model.setAudioVolume(0.27)
        model.advance(at: 400)
        model.advance(at: 400.5)
        let savedPosition = model.telemetry.positionM
        let savedTime = model.simulationTime

        XCTAssertTrue(model.saveGame(saveName: "restore-test"))
        let slot = try XCTUnwrap(model.saveSlots.first { $0.saveName == "restore-test" })
        model.reset()
        XCTAssertTrue(model.loadGame(slotID: slot.id))

        XCTAssertEqual(model.telemetry.positionM, savedPosition, accuracy: 1e-6)
        XCTAssertEqual(model.simulationTime, savedTime, accuracy: 1e-6)
        XCTAssertTrue(model.isPaused)
        XCTAssertEqual(model.runPhase, .running)
        XCTAssertFalse(model.audioEnabled)
        XCTAssertEqual(model.audioVolume, 0.27, accuracy: 1e-6)
    }
}
