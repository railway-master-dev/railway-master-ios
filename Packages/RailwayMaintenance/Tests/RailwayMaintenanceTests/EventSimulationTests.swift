import XCTest
@testable import RailwayMaintenance

final class EventSimulationTests: XCTestCase {
    private func snapshot(
        time: Double = 0,
        tick: UInt64 = 0,
        fixedTimeStep: Double = 1,
        trains: [MaintenanceTrainSnapshot] = [
            MaintenanceTrainSnapshot(
                trainID: "T1", trackID: "track-A", positionM: 100, speedMps: 12,
                direction: .increasingChainage, lengthM: 200
            )
        ],
        crossings: [MaintenanceCrossingSnapshot] = [],
        weather: MaintenanceWeatherSnapshot = .clear,
        flags: Set<String> = []
    ) -> MaintenanceSimulationSnapshot {
        MaintenanceSimulationSnapshot(
            routeID: "fictional-route",
            routeLengthM: 5_000,
            simulationTimeSeconds: time,
            fixedTick: tick,
            fixedTimeStepSeconds: fixedTimeStep,
            trackIDs: ["track-A"],
            stationIDs: ["station-1"],
            trains: trains,
            crossings: crossings,
            weather: weather,
            scenarioFlags: flags
        )
    }

    func testThreeFamiliesRemainButKindsAndDomainsAreMoreDetailed() {
        XCTAssertEqual(Set(MaintenanceEventFamily.allCases), Set([.abnormal, .incident, .disaster]))
        XCTAssertGreaterThan(MaintenanceEventDomain.allCases.count, MaintenanceEventFamily.allCases.count)
        XCTAssertGreaterThan(MaintenanceEventKind.allCases.count, 10)
        XCTAssertEqual(MaintenanceEventKind.vehicleBrakeFault.domain, .rollingStock)
        XCTAssertEqual(MaintenanceEventKind.passengerMedicalIncident.domain, .passengerAndOnboard)
        XCTAssertEqual(MaintenanceEventKind.earthquakeScenario.family, .disaster)
    }

    func testSeededRandomEventGenerationIsRepeatable() {
        let definition = MaintenanceEventDefinition(
            kind: .vehicleTractionFault,
            trigger: .atLeastOneTrainMoving,
            scopeSelector: .movingTrain,
            occurrenceRatePerHour: 1_000_000,
            cooldownSeconds: 100,
            duration: MaintenanceDurationRange(minimumSeconds: 10, maximumSeconds: 10),
            recoveryRule: .eventDurationElapsed,
            impact: MaintenanceEventImpact(tractionMultiplier: 0.5)
        )
        var lhs = MaintenanceEventEngine(seed: 52, definitions: [definition])
        var rhs = MaintenanceEventEngine(seed: 52, definitions: [definition])
        let first = lhs.advance(snapshot: snapshot())
        let second = rhs.advance(snapshot: snapshot())
        XCTAssertEqual(first.startedEvents, second.startedEvents)
        XCTAssertEqual(first.startedEvents.first?.kind, .vehicleTractionFault)
        XCTAssertEqual(first.startedEvents.first?.scope, .train(trainID: "T1"))
    }

    func testEventStateCanBeSavedAndRestored() throws {
        let definition = MaintenanceEventDefinition(
            kind: .precedingTrainDelay,
            trigger: .always,
            scopeSelector: .route,
            occurrenceRatePerHour: 0,
            cooldownSeconds: 0,
            duration: MaintenanceDurationRange(minimumSeconds: 15, maximumSeconds: 15),
            recoveryRule: .eventDurationElapsed,
            impact: MaintenanceEventImpact(additionalDwellSeconds: 12)
        )
        var engine = MaintenanceEventEngine(seed: 19, definitions: [definition])
        _ = try engine.startScenario(
            kind: .precedingTrainDelay,
            scope: .route(routeID: "fictional-route"),
            snapshot: snapshot()
        )
        let encoded = try JSONEncoder().encode(engine.state)
        let restored = try JSONDecoder().decode(MaintenanceEventEngineState.self, from: encoded)
        XCTAssertEqual(restored, engine.state)
    }

    func testConditionalWeatherEventDoesNotStartUntilConditionIsMet() {
        let definition = MaintenanceEventDefinition(
            kind: .heavyRainScenario,
            trigger: .rainAtLeast(40),
            scopeSelector: .route,
            occurrenceRatePerHour: 1_000_000,
            cooldownSeconds: 0,
            duration: MaintenanceDurationRange(minimumSeconds: 10, maximumSeconds: 10),
            recoveryRule: .eventDurationElapsed,
            impact: MaintenanceEventImpact(tractionMultiplier: 0.8)
        )
        var engine = MaintenanceEventEngine(seed: 1, definitions: [definition])
        XCTAssertTrue(engine.advance(snapshot: snapshot()).startedEvents.isEmpty)
        let storm = MaintenanceWeatherSnapshot(rainRateMmPerHour: 50)
        let result = engine.advance(snapshot: snapshot(time: 1, tick: 1, weather: storm))
        XCTAssertEqual(result.startedEvents.first?.scope, .route(routeID: "fictional-route"))
    }

    func testEffectsAreLimitedToAffectedTrainAndRecoveryNeedsAllConditions() throws {
        let definition = MaintenanceEventDefinition(
            kind: .vehicleTractionFault,
            trigger: .always,
            scopeSelector: .movingTrain,
            occurrenceRatePerHour: 0,
            cooldownSeconds: 0,
            duration: MaintenanceDurationRange(minimumSeconds: 5, maximumSeconds: 5),
            recoveryRule: .all([.elapsedAtLeast(10), .actionRequired("gameplay_recovery")]),
            impact: MaintenanceEventImpact(tractionMultiplier: 0.4, maximumSpeedMultiplier: 0.8)
        )
        var engine = MaintenanceEventEngine(seed: 9, definitions: [definition])
        let event = try engine.startScenario(
            kind: .vehicleTractionFault,
            scope: .train(trainID: "T1"),
            snapshot: snapshot()
        )
        let twoTrains = [
            MaintenanceTrainSnapshot(trainID: "T1", trackID: "track-A", positionM: 100, speedMps: 12, lengthM: 200),
            MaintenanceTrainSnapshot(trainID: "T2", trackID: "track-A", positionM: 300, speedMps: 12, lengthM: 200)
        ]
        var result = engine.advance(snapshot: snapshot(time: 5, trains: twoTrains), actions: [
            MaintenanceEventAction(eventInstanceID: event.id, actionID: "gameplay_recovery")
        ])
        XCTAssertEqual(result.effects(for: "T1").tractionMultiplier, 0.4, accuracy: 0.0001)
        XCTAssertEqual(result.effects(for: "T2").tractionMultiplier, 1, accuracy: 0.0001)
        XCTAssertTrue(result.activeEvents.contains(where: { $0.id == event.id }))

        result = engine.advance(snapshot: snapshot(time: 11, tick: 11, trains: twoTrains))
        XCTAssertTrue(result.recoveredEvents.contains(where: { $0.id == event.id }))
        XCTAssertEqual(result.effects(for: "T1").tractionMultiplier, 1, accuracy: 0.0001)
    }

    func testEventProgressesWithFixedStepLongerThanOneSecond() throws {
        let definition = MaintenanceEventDefinition(
            kind: .precedingTrainDelay,
            trigger: .always,
            scopeSelector: .route,
            occurrenceRatePerHour: 0,
            cooldownSeconds: 0,
            duration: MaintenanceDurationRange(minimumSeconds: 1, maximumSeconds: 1),
            recoveryRule: .eventDurationElapsed,
            impact: MaintenanceEventImpact(additionalDwellSeconds: 10)
        )
        var engine = MaintenanceEventEngine(seed: 11, definitions: [definition])
        let event = try engine.startScenario(
            kind: .precedingTrainDelay,
            scope: .route(routeID: "fictional-route"),
            snapshot: snapshot()
        )
        let result = engine.advance(snapshot: snapshot(time: 2, tick: 1, fixedTimeStep: 2))
        XCTAssertTrue(result.recoveredEvents.contains(where: { $0.id == event.id }))
    }

    func testCrossingEventHasCrossingScopeAndApproachInfluence() throws {
        let crossing = MaintenanceCrossingSnapshot(crossingID: "crossing-1", trackID: "track-A", chainageM: 400)
        let definition = MaintenanceEventDefinition(
            kind: .levelCrossingObstruction,
            trigger: .crossingAvailable,
            scopeSelector: .nearestCrossingAhead,
            occurrenceRatePerHour: 0,
            cooldownSeconds: 0,
            duration: MaintenanceDurationRange(minimumSeconds: 30, maximumSeconds: 30),
            recoveryRule: .actionRequired("clear_scenario_obstruction"),
            impact: MaintenanceEventImpact(speedCapKmh: 15, influenceRadiusM: 500)
        )
        var engine = MaintenanceEventEngine(seed: 2, definitions: [definition])
        let event = try engine.startScenario(
            kind: .levelCrossingObstruction,
            scope: .crossing(crossingID: crossing.crossingID, trackID: crossing.trackID, chainageM: crossing.chainageM),
            snapshot: snapshot(crossings: [crossing])
        )
        XCTAssertEqual(event.family, .incident)
        let result = engine.advance(snapshot: snapshot(time: 1, tick: 1, crossings: [crossing]))
        XCTAssertEqual(result.effects(for: "T1").speedCapKmh, 15)
    }

    func testScenarioScopeValidationRejectsUnknownTrain() {
        var engine = MaintenanceEventEngine(seed: 3)
        XCTAssertThrowsError(try engine.startScenario(
            kind: .vehicleTractionFault,
            scope: .train(trainID: "missing"),
            snapshot: snapshot()
        )) { error in
            XCTAssertEqual(error as? MaintenanceEventEngineError, .invalidScope)
        }
    }

    func testVehicleFaultEventIsMirroredIntoDepotVehicleRecord() {
        let definition = MaintenanceEventDefinition(
            kind: .vehicleTractionFault,
            trigger: .atLeastOneTrainMoving,
            scopeSelector: .movingTrain,
            occurrenceRatePerHour: 1_000_000,
            cooldownSeconds: 1_000,
            duration: MaintenanceDurationRange(minimumSeconds: 20, maximumSeconds: 20),
            recoveryRule: .actionRequired("gameplay_recovery"),
            impact: MaintenanceEventImpact(tractionMultiplier: 0.4)
        )
        let vehicle = MaintenanceVehicleRecord(
            id: "T1", profileID: "fictional-unit", lengthM: 200,
            location: .onRoute(trackID: "track-A", chainageM: 100)
        )
        var module = RailwayMaintenanceModule(
            seed: 4,
            eventDefinitions: [definition],
            depots: [],
            vehicles: [vehicle]
        )

        let result = module.step(snapshot: snapshot())
        XCTAssertEqual(result.eventResult.startedEvents.first?.kind, .vehicleTractionFault)
        XCTAssertTrue(result.depotEvents.contains(where: { $0.kind == .scenarioFaultRecorded }))
        XCTAssertEqual(module.depotEngine.state.vehicles.first?.activeScenarioFaultEventIDs.count, 1)
    }
}
