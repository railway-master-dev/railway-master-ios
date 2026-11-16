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
    func testDepotGameModeScenarioPinsSplitYardTargets() throws {
        let model = SimulatorModel()
        XCTAssertTrue(model.selectRoute(variant: .depotTransfer, category: .local, direction: .up))
        let context = model.gameModeContext
        XCTAssertEqual(context.variant, .depotTransfer)
        XCTAssertEqual(context.stops.count, 2)
        // batch116: the yard is no longer a single zone.
        // StopScoringRouteAdapter gives each depot stop its
        // own 200 m zone (origin at the spur start, terminal
        // at the spur end) and centres the target in it, so
        // the origin target and the final stop's target are
        // ~1.8 km apart instead of co-located — the batch103
        // audit finding this test used to pin is superseded.
        // The bounds below are consist-independent: any
        // consist that fits a 200 m zone centres inside it.
        let finalStop = try XCTUnwrap(context.stops.last)
        XCTAssertGreaterThan(context.originTargetM, 0)
        XCTAssertLessThan(context.originTargetM, StopScoringRouteAdapter.depotZoneLengthM)
        XCTAssertGreaterThan(finalStop.positionM, context.route.distanceM - StopScoringRouteAdapter.depotZoneLengthM)
        XCTAssertLessThan(finalStop.positionM, context.route.distanceM)
        XCTAssertGreaterThan(finalStop.positionM - context.originTargetM, 1_500)
        // The consist is placed at the origin target on
        // reset: the run now STARTS there, ~1.8 km short of
        // its only other target.
        let snapshot = try XCTUnwrap(model.gameModeSnapshot)
        XCTAssertEqual(snapshot.positionM, context.originTargetM, accuracy: 0.1)
        // validOrderedStops anchors the first stop on the
        // origin target and bounds the depot terminal
        // shortfall by half the end zone, which the centred
        // final target satisfies, so an unscored mode builds
        // with the two distinct yard targets.
        let freeResult = RegionalGameModeAdapter.build(
            mode: .free, playStyle: .standard, context: context, snapshot: snapshot
        )
        let scenario = try XCTUnwrap(freeResult.scenario)
        XCTAssertEqual(scenario.stops.count, 2)
        XCTAssertEqual(scenario.stops[0].positionM, context.originTargetM, accuracy: 0.1)
        XCTAssertEqual(scenario.stops[1].positionM, finalStop.positionM, accuracy: 0.1)
        XCTAssertGreaterThan(scenario.stops[1].positionM, scenario.stops[0].positionM)
    }

    @MainActor
    func testDepotScoredRunModesAreAvailableWithSplitYardTargets() throws {
        let model = SimulatorModel()
        XCTAssertTrue(model.selectRoute(variant: .depotTransfer, category: .local, direction: .up))
        let context = model.gameModeContext
        let snapshot = try XCTUnwrap(model.gameModeSnapshot)
        // batch103 refused driver and full-line on the depot
        // because success there is purely positional (ordered
        // stop visits + the service-end position) and both
        // gates were already met at the start position, the
        // two yard targets being co-located. batch116 split
        // the yard zones, so the origin target and the final
        // target are ~1.8 km apart, the batch103 co-location
        // guard no longer fires, and the scored modes build
        // like on any other two-target route: certifying a
        // depot run now requires actually driving the spur.
        for mode in [GameModeID.driver, .fullLine] {
            let result = RegionalGameModeAdapter.build(
                mode: mode, playStyle: .standard, context: context, snapshot: snapshot
            )
            XCTAssertNotNil(result.scenario, "\(mode) must build a scored depot run now that the yard targets are split")
            let session = try RegionalGameModeAdapter.makeSession(
                mode: mode, playStyle: .standard, context: context, snapshot: snapshot
            )
            XCTAssertEqual(session.status, .ready)
        }
        // Conductor and free stay available, as before.
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
        // The depot transfer's terminal target is centred in
        // its own 200 m end zone (batch116), so a shortfall up
        // to half the zone — 100 m, the limit as the consist
        // length shrinks — is legitimate there. Beyond the
        // zone the depot is invalid again: that bound is what
        // keeps a collapsed or misplaced yard target from
        // validating (the pre-batch116 whole-spur zone put
        // the target ~900 m short and the clause was skipped
        // entirely).
        let depotResult = RegionalGameModeAdapter.build(
            mode: .free, playStyle: .standard,
            context: contextWithFinalShortfall(100, variant: .depotTransfer),
            snapshot: snapshot
        )
        XCTAssertNotNil(depotResult.scenario)
        let depotShortResult = RegionalGameModeAdapter.build(
            mode: .free, playStyle: .standard,
            context: contextWithFinalShortfall(500, variant: .depotTransfer),
            snapshot: snapshot
        )
        XCTAssertNil(depotShortResult.scenario)
        XCTAssertEqual(depotShortResult.blockingReason, .missingStops)
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
        // batch108: a fresh session starts with the doors open at
        // the origin and the departure sequence (bell, close,
        // buzzer) gates departure, so the train cannot move until
        // the sequence lands. Wait for the doors to close (bounded)
        // before starting the overspeed window; the staging below
        // is about the ATS intervention, not the departure hold.
        // If the doors never close, the sequence itself is broken
        // and this fails here with that message instead of at the
        // overspeed unwrap below.
        var doorsClosedWall: Double?
        for _ in 0..<120 {
            wall += 0.25
            model.advance(at: wall)
            if model.gameModeDoorState == .closed {
                doorsClosedWall = wall
                break
            }
        }
        _ = try XCTUnwrap(doorsClosedWall, "the batch108 departure sequence must close the doors")
        // CI #419: the doors close, but 120 s of running after
        // the close was not enough for the train to exceed the
        // stopping pattern — the pre-batch108 window's margin
        // was thin. Wait until the train is actually rolling
        // (bounded) so the window below measures a running
        // train, and give it 240 s to reach the approach where
        // the pattern drops below full power. If the train
        // never rolls, the departure itself is broken and this
        // fails here with that message instead.
        var rollingWall: Double?
        for _ in 0..<240 {
            wall += 0.25
            model.advance(at: wall)
            if model.telemetry.speedMps > 0.5 {
                rollingWall = wall
                break
            }
        }
        _ = try XCTUnwrap(rollingWall, "the train must start moving after the doors close")
        var firstOverspeedWall: Double?
        var brakeWall: Double?
        for _ in 0..<960 {
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

    // batch119 regression (IPA #12 device report, 2026-11-16:
    // "no oncoming trains at all" on a 06:23–06:32 up
    // service): batch108 anchored the DISPLAY clock to the
    // player's origin departure − 30 s, but the traffic
    // scenario kept the 05:30 service-day zero, so the
    // traffic world in that session was still at 05:47–05:56
    // — before the first 06:00 departures — and the batch90
    // seeds covering the window had already arrived and
    // despawned. The batch90 test above pins the ENGINE
    // alone (playerTrain = nil) on the free-running
    // scenario; this test pins the HOST path: a scheduled
    // session's scenario is generated on the session's own
    // anchor, so the 06:00 departures from the far terminus
    // are already en route in the snapshot reset() installs.
    @MainActor
    func testScheduledSessionStartsWithOncomingDiagramTrainsEnRoute() throws {
        let model = SimulatorModel()
        XCTAssertTrue(model.selectRoute(variant: .mainline, category: .local, direction: .down))
        // The first morning local out of Kamogawa departs
        // just after 06:00 (06:06:05 in the device session),
        // so the anchor (origin departure − 30 s) sits just
        // after 06:00 as well — past the first departures
        // from both termini, not half an hour before them.
        let anchor = model.gameClockAnchorDaySeconds
        XCTAssertGreaterThan(anchor, 21_600, "the session anchor must be past the 06:00 first departures, got \(anchor)")
        XCTAssertLessThan(anchor, 22_200, "the session anchor must stay near 06:05, got \(anchor)")
        let snapshot = try XCTUnwrap(model.trafficSnapshot)
        // Oncoming for a Kamogawa → Kaibukuro player is the
        // main-up track (the geographic down direction).
        let oncoming = snapshot.trains.filter {
            $0.trackID == "main-up" && ($0.phase == .running || $0.phase == .dwelling)
        }
        XCTAssertFalse(oncoming.isEmpty, "diagram trains out of Kaibukuro must already be en route at session start")
        let firstDown = try XCTUnwrap(snapshot.trains.first { $0.id == "v4-local-down-morningRush-360" })
        XCTAssertTrue(firstDown.phase == .running || firstDown.phase == .dwelling,
                      "the 06:00 Kaibukuro local must be en route at session start, got \(firstDown.phase)")
        XCTAssertGreaterThan(firstDown.positionM, 0)
        XCTAssertLessThan(firstDown.positionM, 20_000)
    }

    // batch112 regression (IPA #12 device report, 2026-11-16:
    // the session started with the doors already closed and
    // no departure sequence ran): reset placed the train
    // front at the adjusted origin target (platformEnd − 5 m,
    // 195 m at S01), but activeStops[0] kept the raw station
    // position (0) — 195 m away, far outside the door cycle's
    // 4 m stop match — so the automatic door cycle never
    // recognised the train as standing at the origin, the
    // doors never opened, and the batch108 bell → close →
    // buzzer sequence never ran. The overspeed test above
    // cannot see this: it waits for .closed, which is also
    // the initial state, so its wait is satisfied vacuously.
    // This test asserts the missing half: the origin stop
    // record carries the placement target, and the doors
    // actually OPEN after reset and close again through the
    // sequence.
    @MainActor
    func testOriginDoorsOpenAfterResetForScheduledService() throws {
        let model = SimulatorModel()
        XCTAssertTrue(model.selectRoute(variant: .mainline, category: .local, direction: .up))
        let originStop = try XCTUnwrap(model.activeStops.first)
        let context = model.gameModeContext
        XCTAssertGreaterThan(context.originTargetM, 0)
        XCTAssertEqual(originStop.positionM, context.originTargetM, accuracy: 0.001,
                       "the origin stop must carry the placement target, not the raw station position")
        // The placed train front stands on that same target.
        let snapshot = try XCTUnwrap(model.gameModeSnapshot)
        XCTAssertEqual(snapshot.positionM, originStop.positionM, accuracy: 0.001)

        var wall = 3_000.0
        model.advance(at: wall)
        var sawOpen = false
        var closedAgain = false
        for _ in 0..<240 {
            wall += 0.25
            model.advance(at: wall)
            if model.gameModeDoorState.isOpen { sawOpen = true }
            if sawOpen, model.gameModeDoorState == .closed {
                closedAgain = true
                break
            }
        }
        XCTAssertTrue(sawOpen, "the automatic door cycle must open the doors at the origin after reset")
        XCTAssertTrue(closedAgain, "the batch108 departure sequence must close the origin doors again")
    }

    // batch116 regression (IPA #12 device report, 2026-11-16:
    // selecting the depot line showed the result sheet before
    // the train moved): both depot stops shared the whole
    // 2 km yard zone, so the centred origin target and the
    // final target coincided (1,078 m for 8 cars), reset
    // placed the train exactly on the final target with
    // nextStopIndex already pointing at it, and
    // updateRunPhase — which has no must-depart-first guard —
    // counted the 2 s arrival dwell from the first tick and
    // completed the run untouched. The batch103 pins pinned
    // the co-location itself, but nothing asserted the normal
    // driving path could not complete at spawn. Phase 1 is
    // that missing assertion; phase 2 drives the spur and
    // pins that a genuine arrival still completes the run.
    @MainActor
    func testDepotRunDoesNotCompleteAtSpawnAndArrivesAtSpurEnd() throws {
        let model = SimulatorModel()
        XCTAssertTrue(model.selectRoute(variant: .depotTransfer, category: .local, direction: .up))
        let finalTarget = try XCTUnwrap(model.activeStops.last).positionM

        // Phase 1: no input for 10 s of simulation — five
        // times the 2 s arrival dwell that used to end the
        // run at spawn. The run must still be live.
        var wall = 5_000.0
        model.advance(at: wall)
        for _ in 0..<40 {
            wall += 0.25
            model.advance(at: wall)
        }
        XCTAssertEqual(model.runPhase, .running,
                       "an untouched depot run must not complete itself at spawn")
        XCTAssertNil(model.completedSummary)

        // Phase 2: drive the ~1.8 km to the spur end and stop
        // on the final target. The controller tracks the lower
        // of the host's own permitted speed and a 0.5 m/s²
        // braking-curve profile for the remaining distance,
        // floored at creep pace while there is still ground
        // to cover, and holds full brake inside the last
        // metres, so the stop lands inside the ±4 m arrival
        // window without tripping the +12 m overshoot
        // completion. (The door cycle opens at the yard
        // origin after the reset and the interlock holds the
        // train until it closes; the loop simply keeps
        // commanding through that, as a driver would.)
        model.reset()
        var arrived = false
        for _ in 0..<2_000 {
            let remaining = finalTarget - model.telemetry.positionM
            let speed = model.telemetry.speedMps
            let permitted = (model.operationsSnapshot?.permittedSpeedKmh ?? 100) / 3.6
            var desired = min(permitted - 0.6, 16)
            desired = min(desired, (max(0, remaining - 2)).squareRoot())
            if remaining < 25 {
                desired = min(desired, max(0.8, remaining / 6))
            }
            if remaining > 3.2 {
                desired = max(desired, 0.8)
            }
            if remaining <= 3.2 {
                model.setThrottle(0)
                model.setBrake(7)
            } else if speed < desired - 0.4 {
                model.setThrottle(4)
                model.setBrake(0)
            } else if speed > desired + 0.2 {
                model.setThrottle(0)
                model.setBrake(3)
            } else {
                model.setThrottle(0)
                model.setBrake(0)
            }
            wall += 0.25
            model.advance(at: wall)
            if model.runPhase == .arrived {
                arrived = true
                break
            }
            XCTAssertNotEqual(model.runPhase, .overshot,
                              "the driven arrival must stop at the target, not run through it")
        }
        XCTAssertTrue(arrived, "driving the depot spur to its end target must complete the run as an arrival")
        XCTAssertNotNil(model.completedSummary)
    }

    // batch121 regression (design study §1.6, IPA #12 device
    // reports): StopScoringRouteAdapter.prepare THREW for
    // every down zoo / park session — the junction station is
    // the final stop there, and its canonical platform
    // (station centre ± 100 m in mainline chainage) maps to a
    // travel-frame range ending 100 m past the route end,
    // tripping the scoring loop's route-bounds guard. The
    // whole preparation failed with it: no stop scoring, no
    // adjusted stops, no origin placement (the train spawned
    // at 0 with the terminal platform drawn at the opposite
    // end of the world). The synthetic terminal's zone was
    // likewise fixed at the far end, so as the down ORIGIN
    // its zone sat 2.3 km from the stop itself. Both stops
    // now take a 200 m zone at their own end of the route,
    // keyed on travel order like the depot zones.
    func testZooAndParkDownPrepareSucceedsWithValidOriginPlacement() throws {
        let plan = try XCTUnwrap(FictionalOperationsPlan.loadBundled())
        let routePackage = try RailwayRouteData.RoutePackageLoader.loadResource(named: "fictional_70km_network")
        // Zoo / park services run 8 cars = 156 m by the
        // consist rule; centred in a 200 m span the front
        // stands at 0 + 156 + (200 − 156) / 2 = 178.
        for (variant, routeLength) in [(RegionalRouteVariant.zooLine, 2_500.0), (RegionalRouteVariant.parkLine, 2_000.0)] {
            let trip = try RegionalRouteFactory.make(plan: plan, variant: variant, category: .local, direction: .down)
            let prepared = try StopScoringRouteAdapter.prepare(
                trip: trip,
                plan: plan,
                routePackage: routePackage,
                trainLengthMeters: 156
            )
            XCTAssertEqual(prepared.originTargetM, 178, accuracy: 0.001,
                           "\(variant) down: the origin consist must be centred in its 200 m end zone")
            XCTAssertEqual(prepared.activeStops.count, 2)
            XCTAssertEqual(prepared.activeStops[0].positionM, prepared.originTargetM, accuracy: 0.001,
                           "\(variant) down: the origin stop record must carry the placement target")
            // The junction final stop keeps the ARRIVAL rule
            // (front at platformEnd − 5) inside the far-end
            // zone — prepare succeeding at all is the core
            // regression assertion (it threw before).
            XCTAssertEqual(prepared.activeStops[1].positionM, routeLength - 5, accuracy: 0.001,
                           "\(variant) down: the junction arrival target must sit on the margin line")
            let definition = try XCTUnwrap(prepared.stationDefinitions.first)
            XCTAssertEqual(definition.platformStartChainageMeters, routeLength - 200, accuracy: 0.001)
            XCTAssertEqual(definition.platformEndChainageMeters, routeLength, accuracy: 0.001)
            XCTAssertEqual(definition.targetStopChainageMeters, routeLength - 5, accuracy: 0.001)
        }
        // Host path: selecting a down zoo / park session must
        // leave the model with a prepared scoring session and
        // the train placed on the origin target, not with a
        // prepare error and a spawn at 0.
        for variant in [RegionalRouteVariant.zooLine, RegionalRouteVariant.parkLine] {
            let model = SimulatorModel()
            XCTAssertTrue(model.selectRoute(variant: variant, category: .local, direction: .down))
            XCTAssertNil(model.stopScoringError,
                         "\(variant) down must prepare cleanly through the host path, got \(model.stopScoringError ?? "")")
            let context = model.gameModeContext
            XCTAssertGreaterThan(context.originTargetM, 0,
                                 "\(variant) down: the origin placement must not fall back to 0")
            XCTAssertEqual(model.activeStops.first?.positionM ?? -1, context.originTargetM, accuracy: 0.001)
            XCTAssertGreaterThan(model.activeStops.last?.positionM ?? 0, context.route.distanceM - 200)
        }
    }

    // batch121 (design study §2.5): the origin placement rule
    // is unified across ALL lines — the consist is CENTRED in
    // the origin platform span. Before this batch the origin
    // borrowed the arrival rule (front at platformEnd − 5,
    // batch74), so at 海袋 and on the branch only the end
    // slope was visible ahead of the cab, and on the zoo /
    // park up shuttles the train sat at 95 m while the drawn
    // platform was centred on 0. Non-origin stops keep the
    // arrival rule; the depot keeps the centred numbers it
    // already had (batch116).
    func testOriginTargetIsCentredInPlatformSpanOnEveryLine() throws {
        let plan = try XCTUnwrap(FictionalOperationsPlan.loadBundled())
        let routePackage = try RailwayRouteData.RoutePackageLoader.loadResource(named: "fictional_70km_network")
        func originTarget(_ variant: RegionalRouteVariant, _ direction: RegionalTravelDirection) throws -> PreparedStopScoringSession {
            let trip = try RegionalRouteFactory.make(plan: plan, variant: variant, category: .local, direction: direction)
            return try StopScoringRouteAdapter.prepare(
                trip: trip,
                plan: plan,
                routePackage: routePackage,
                trainLengthMeters: 156
            )
        }
        // Every passenger origin span is 200 m, so an 8-car
        // consist centres with its front at 178 everywhere:
        // mainline both ways, branch both ways, zoo / park
        // both ways.
        for (variant, direction) in [
            (RegionalRouteVariant.mainline, RegionalTravelDirection.up),
            (RegionalRouteVariant.mainline, RegionalTravelDirection.down),
            (RegionalRouteVariant.branchShuttle, RegionalTravelDirection.up),
            (RegionalRouteVariant.branchShuttle, RegionalTravelDirection.down),
            (RegionalRouteVariant.zooLine, RegionalTravelDirection.up),
            (RegionalRouteVariant.zooLine, RegionalTravelDirection.down),
            (RegionalRouteVariant.parkLine, RegionalTravelDirection.up),
            (RegionalRouteVariant.parkLine, RegionalTravelDirection.down),
        ] {
            let prepared = try originTarget(variant, direction)
            XCTAssertEqual(prepared.originTargetM, 178, accuracy: 0.001,
                           "\(variant)/\(direction): origin front must centre the consist in the 200 m span")
            XCTAssertEqual(prepared.activeStops[0].positionM, 178, accuracy: 0.001,
                           "\(variant)/\(direction): the origin stop record must carry the centred target")
        }
        // The arrival rule is untouched for non-origin stops:
        // S02's target is still its platform end − 5.
        let mainlineUp = try originTarget(.mainline, .up)
        let s02 = try XCTUnwrap(mainlineUp.stationDefinitions.first)
        XCTAssertEqual(s02.stationID, "S02")
        XCTAssertEqual(s02.platformStartChainageMeters, 1_739, accuracy: 0.001)
        XCTAssertEqual(s02.platformEndChainageMeters, 1_939, accuracy: 0.001)
        XCTAssertEqual(s02.targetStopChainageMeters, 1_934, accuracy: 0.001)
        // Depot: batch116's centred split-zone targets are
        // exactly what the unified rule produces — unchanged.
        let depot = try originTarget(.depotTransfer, .up)
        XCTAssertEqual(depot.originTargetM, 178, accuracy: 0.001)
        XCTAssertEqual(depot.activeStops.last?.positionM ?? -1, 1_978, accuracy: 0.001)
    }

    // batch121 (user decision 2026-11-16, real-world
    // convention): 上り means travel toward the line's origin
    // — mainline toward 海袋 (decreasing chainage), branch /
    // zoo / park toward their junction station. Internally
    // RegionalTravelDirection.up keeps its chainage meaning
    // (increasing), so the case labelled 上り is .down; the
    // pin below keeps the label, the factory travel and the
    // plan's ServiceDirection (whose .up already meant
    // decreasing and already displayed 上り) in agreement.
    func testUpLabelMeansTravelTowardTheOrigin() throws {
        XCTAssertEqual(RegionalTravelDirection.down.title, "上り")
        XCTAssertEqual(RegionalTravelDirection.up.title, "下り")
        XCTAssertEqual(ServiceDirection.up.displayName, "上り")
        XCTAssertEqual(ServiceDirection.down.displayName, "下り")
        let plan = try XCTUnwrap(FictionalOperationsPlan.loadBundled())
        // Selecting 上り on the mainline (the .down case)
        // yields travel from 鴨河 toward the 海袋 terminus.
        let nobori = try RegionalRouteFactory.make(plan: plan, variant: .mainline, category: .local, direction: .down)
        XCTAssertEqual(nobori.stops.first?.stationID, "S28")
        XCTAssertEqual(nobori.stops.last?.stationID, "S01")
        XCTAssertEqual(nobori.profile.departureStation, "鴨河")
        XCTAssertEqual(nobori.profile.arrivalStation, "海袋")
        let kudari = try RegionalRouteFactory.make(plan: plan, variant: .mainline, category: .local, direction: .up)
        XCTAssertEqual(kudari.stops.first?.stationID, "S01")
        XCTAssertEqual(kudari.stops.last?.stationID, "S28")
        // On the branch lines 上り ends at the junction
        // station, not at the outer terminal.
        let zooNobori = try RegionalRouteFactory.make(plan: plan, variant: .zooLine, category: .local, direction: .down)
        XCTAssertEqual(zooNobori.stops.map(\.stationID), ["ZOO_END", "S24"])
        let branchNobori = try RegionalRouteFactory.make(plan: plan, variant: .branchShuttle, category: .local, direction: .down)
        XCTAssertEqual(branchNobori.stops.first?.stationID, "B04")
        XCTAssertEqual(branchNobori.stops.last?.stationID, "S28")
    }
}
