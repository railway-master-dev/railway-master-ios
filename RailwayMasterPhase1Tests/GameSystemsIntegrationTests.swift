import RailwayTimetable
import RailwayGameModes
import TrainPhysics
import RailwayRouteData
import StopScoring
import TrafficSimulation
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
    func testDepotGameModeScenarioPinsSingleCoLocatedYardTarget() throws {
        let model = SimulatorModel()
        XCTAssertTrue(model.selectRoute(variant: .depotTransfer, category: .local, direction: .up))
        let context = model.gameModeContext
        XCTAssertEqual(context.variant, .depotTransfer)
        XCTAssertEqual(context.stops.count, 2)
        // The yard is a single zone: StopScoringRouteAdapter
        // bounds every depot stop by the whole spur and centres
        // the target, so the prepared origin target and the
        // final stop's adjusted target coincide, well short of
        // the spur end. This pins the batch103 audit finding —
        // the depot scenario has exactly one target, not a
        // stop-by-stop structure.
        let finalStop = try XCTUnwrap(context.stops.last)
        XCTAssertGreaterThan(context.originTargetM, 0)
        XCTAssertEqual(finalStop.positionM, context.originTargetM, accuracy: 0.1)
        XCTAssertLessThan(finalStop.positionM, context.route.distanceM)
        // The consist is placed at that same target on reset:
        // the run's start position is its only target.
        let snapshot = try XCTUnwrap(model.gameModeSnapshot)
        XCTAssertEqual(snapshot.positionM, context.originTargetM, accuracy: 0.1)
        // The depot exception in validOrderedStops lets the
        // large terminal shortfall through, so an unscored mode
        // still builds, with both plans on the one yard target.
        let freeResult = RegionalGameModeAdapter.build(
            mode: .free, playStyle: .standard, context: context, snapshot: snapshot
        )
        let scenario = try XCTUnwrap(freeResult.scenario)
        XCTAssertEqual(scenario.stops.count, 2)
        XCTAssertEqual(scenario.stops[0].positionM, context.originTargetM, accuracy: 0.1)
        XCTAssertEqual(scenario.stops[1].positionM, scenario.stops[0].positionM, accuracy: 0.1)
    }

    @MainActor
    func testDepotScoredRunModesAreBlockedWhileProcedureModesStayAvailable() throws {
        let model = SimulatorModel()
        XCTAssertTrue(model.selectRoute(variant: .depotTransfer, category: .local, direction: .up))
        let context = model.gameModeContext
        let snapshot = try XCTUnwrap(model.gameModeSnapshot)
        // batch103: driver and full-line success is purely
        // positional (ordered stop visits + the service-end
        // position), and on the depot both are already met at
        // the start position, so the adapter must refuse to
        // certify a run that never moved.
        for mode in [GameModeID.driver, .fullLine] {
            let result = RegionalGameModeAdapter.build(
                mode: mode, playStyle: .standard, context: context, snapshot: snapshot
            )
            XCTAssertNil(result.scenario, "\(mode) must not build a scored depot run")
            XCTAssertFalse(result.blockingMessages.isEmpty)
            XCTAssertThrowsError(try RegionalGameModeAdapter.makeSession(
                mode: mode, playStyle: .standard, context: context, snapshot: snapshot
            ))
        }
        // Conductor scores the door procedure performed at the
        // yard target, not travel between targets, so it stays
        // available; free mode has no stop scoring at all.
        let conductor = try RegionalGameModeAdapter.makeSession(
            mode: .conductor, playStyle: .standard, context: context, snapshot: snapshot
        )
        XCTAssertEqual(conductor.status, .ready)
        let free = try RegionalGameModeAdapter.makeSession(
            mode: .free, playStyle: .standard, context: context, snapshot: snapshot
        )
        XCTAssertEqual(free.status, .ready)
    }

    @MainActor
    func testPassengerTerminalClauseAndDepotExceptionArePinned() throws {
        let model = SimulatorModel()
        let base = model.gameModeContext
        let snapshot = try XCTUnwrap(model.gameModeSnapshot)
        let length = base.route.distanceM
        func contextWithFinalShortfall(_ shortfall: Double, variant: RegionalRouteVariant?) -> RegionalGameModeContext {
            RegionalGameModeContext(
                routeID: base.routeID,
                route: base.route,
                stops: [
                    RegionalRouteStop(stationID: "PIN_ORIGIN", name: "始発", positionM: 0, trackID: "main-up"),
                    RegionalRouteStop(stationID: "PIN_FINAL", name: "終着", positionM: length - shortfall, trackID: "main-up")
                ],
                variant: variant,
                originTargetM: 0,
                timetableByStationID: [:],
                trains: [],
                availableTrainingPromptIDs: []
            )
        }
        // Passenger variants keep the terminal clause: a final
        // stop more than platformEndMarginM + 0.1 short of the
        // route end is not a valid stop list.
        let shortResult = RegionalGameModeAdapter.build(
            mode: .free, playStyle: .standard,
            context: contextWithFinalShortfall(100, variant: .throughBranch),
            snapshot: snapshot
        )
        XCTAssertNil(shortResult.scenario)
        XCTAssertEqual(shortResult.blockingReason, .missingStops)
        // A shortfall inside the margin still builds: the
        // terminal target sits at platformEnd − margin by
        // design (batch74), which is exactly this case.
        let marginResult = RegionalGameModeAdapter.build(
            mode: .free, playStyle: .standard,
            context: contextWithFinalShortfall(StopScoringRouteAdapter.platformEndMarginM, variant: .throughBranch),
            snapshot: snapshot
        )
        XCTAssertNotNil(marginResult.scenario)
        // The same large shortfall is legitimate for the depot
        // transfer, whose single yard-zone target is centred
        // ~900 m short of the spur end by design.
        let depotResult = RegionalGameModeAdapter.build(
            mode: .free, playStyle: .standard,
            context: contextWithFinalShortfall(100, variant: .depotTransfer),
            snapshot: snapshot
        )
        XCTAssertNotNil(depotResult.scenario)
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

    // batch81 regression (IPA #10 device report, 2026-11-15:
    // "when ATS catches me the app dies"): the educational ATS
    // staging must hold — trigger raises the acknowledgement
    // window first, the automatic brake is commanded only when
    // the deadline passes unacknowledged, and a late
    // acknowledgement never releases it.
    func testEducationalATSDeadlineCommandsAutomaticBrake() throws {
        var ats = try EducationalATSConfirmation(acknowledgementTimeoutSeconds: 5)
        try ats.trigger(at: 100)
        let beforeDeadline = try ats.advance(to: 104.9)
        XCTAssertEqual(beforeDeadline.state, .awaitingAcknowledgement)
        XCTAssertFalse(beforeDeadline.automaticBrakeCommanded)
        let atDeadline = try ats.advance(to: 105)
        XCTAssertEqual(atDeadline.state, .automaticBrakeApplied)
        XCTAssertTrue(atDeadline.automaticBrakeCommanded)
        let acceptedLate = try ats.acknowledge(at: 106)
        XCTAssertFalse(acceptedLate)
        XCTAssertTrue(ats.status().automaticBrakeCommanded)
    }

    func testEducationalATSAcknowledgementBeforeDeadlinePreventsAutomaticBrake() throws {
        var ats = try EducationalATSConfirmation(acknowledgementTimeoutSeconds: 5)
        try ats.trigger(at: 0)
        let accepted = try ats.acknowledge(at: 3)
        XCTAssertTrue(accepted)
        let after = try ats.advance(to: 30)
        XCTAssertEqual(after.state, .acknowledged)
        XCTAssertFalse(after.automaticBrakeCommanded)
    }

    // batch81 regression, host level: drive at full power and
    // never brake, so the stopping-pattern envelope for the
    // next station falls below the running speed. The staged
    // intervention must appear in order — no automatic brake at
    // the first overspeed observation (warning stage), the
    // brake only after the acknowledgement grace — and the
    // model must stay alive through the brake application and
    // an ATS acknowledgement. The audio engine is disabled
    // under XCTest (ciAudioDisabled), so this proves the
    // model-side intervention path; the production audio graph
    // remains a device-only surface (hardened separately in
    // batch81: RailwayAudioEngine / ProceduralAudioDSP).
    @MainActor
    func testPatternOverspeedInterventionStagesToAutomaticBrake() throws {
        let model = SimulatorModel()
        model.setThrottle(5)
        var wall = 1_000.0
        model.advance(at: wall)
        var firstOverspeedWall: Double?
        var brakeWall: Double?
        for _ in 0..<480 {
            wall += 0.25
            model.advance(at: wall)
            guard let snapshot = model.operationsSnapshot else { continue }
            let speedKmh = model.telemetry.speedMps * 3.6
            if firstOverspeedWall == nil, speedKmh > snapshot.permittedSpeedKmh + 0.25 {
                firstOverspeedWall = wall
                XCTAssertFalse(snapshot.automaticBrakeActive,
                               "the warning stage must precede any automatic brake")
            }
            if snapshot.automaticBrakeActive {
                brakeWall = wall
                break
            }
        }
        let overspeed = try XCTUnwrap(firstOverspeedWall,
                                      "full power must eventually exceed the stopping pattern")
        let brake = try XCTUnwrap(brakeWall,
                                  "the unacknowledged overspeed must end in an automatic brake")
        XCTAssertGreaterThanOrEqual(brake - overspeed, 4.0,
                                    "the automatic brake must wait out the acknowledgement grace")
        // The intervention moment itself: acknowledging and
        // continuing to advance must not crash or wedge the host.
        _ = model.acknowledgeATS()
        let timeAtBrake = model.simulationTime
        wall += 0.25
        model.advance(at: wall)
        wall += 0.25
        model.advance(at: wall)
        XCTAssertGreaterThanOrEqual(model.simulationTime, timeAtBrake)
    }

    // batch90 (2026-11-16): pins the session-start seed trains
    // that fix "no oncoming trains at all" (batch87 root cause:
    // the game clock starts at the 05:30 zero, every diagram
    // pattern first departs at 06:00 from a terminus, and the
    // engine never poses .scheduled trains — so the first 30
    // minutes of every session were empty by construction).
    // The generated scenario must carry eight seed locals
    // already en route at t=0, and after 90 seconds of engine
    // time the opposing seed at each end must actually be
    // running or dwelling inside the first 10 km of its
    // terminus — a departing player meets traffic in the
    // first minutes, in either direction.
    @MainActor
    func testSeedTrainsPutOpposingTrafficInFirstTenKilometres() throws {
        let model = SimulatorModel()
        let scenario = try XCTUnwrap(model.trafficScenario)
        let seeds = scenario.trains.filter { $0.id.hasPrefix("seed-") }
        XCTAssertEqual(seeds.count, 8)
        XCTAssertTrue(seeds.allSatisfy { $0.departureTimeSeconds == 0 })

        var engine = try TrafficSimulationEngine(scenario: scenario)
        _ = try engine.advance(realDeltaSeconds: 90)
        let snapshot = engine.snapshot()
        let opposingAtS01 = try XCTUnwrap(snapshot.trains.first { $0.id == "seed-main-down-09000" })
        XCTAssertTrue(opposingAtS01.phase == .running || opposingAtS01.phase == .dwelling,
                      "the S01 opposing seed must be posed (running or dwelling), got \(opposingAtS01.phase)")
        XCTAssertLessThanOrEqual(opposingAtS01.positionM, 10_000)
        let opposingAtS28 = try XCTUnwrap(snapshot.trains.first { $0.id == "seed-main-up-51000" })
        XCTAssertTrue(opposingAtS28.phase == .running || opposingAtS28.phase == .dwelling,
                      "the S28 opposing seed must be posed (running or dwelling), got \(opposingAtS28.phase)")
        XCTAssertGreaterThanOrEqual(opposingAtS28.positionM, 50_000)
    }
}
