import XCTest
@testable import StopScoring

final class StopScoringEngineTests: XCTestCase {
    private func window(_ lower: Double, _ upper: Double) throws -> StopPositionWindow {
        try StopPositionWindow(lowerBoundMeters: lower, upperBoundMeters: upper)
    }

    private func station(
        _ id: String = "S1",
        chainage: Double = 100,
        target: Double = 100,
        platformStart: Double = 0,
        platformEnd: Double = 120,
        allowed: (Double, Double) = (90, 110),
        schedule: StopSchedule = .none,
        door: DoorSide? = nil,
        procedures: [String] = []
    ) throws -> StationStopDefinition {
        try StationStopDefinition(
            stationID: id,
            displayName: id,
            stationChainageMeters: chainage,
            targetStopChainageMeters: target,
            platformStartChainageMeters: platformStart,
            platformEndChainageMeters: platformEnd,
            permittedStopWindow: window(allowed.0, allowed.1),
            schedule: schedule,
            expectedDoorSide: door,
            requiredProcedureSteps: procedures
        )
    }

    private func tick(
        _ sequence: Int,
        time: Double,
        position: Double = 100,
        speed: Double = 0
    ) throws -> SimulationTick {
        try SimulationTick(sequence: sequence,
                          simulationTimeSeconds: time,
                          leadingEndChainageMeters: position,
                          speedMetersPerSecond: speed)
    }

    private func event(_ id: String, _ stationID: String = "S1", _ kind: StationEventKind) throws -> StationEvent {
        try StationEvent(eventID: id, stationID: stationID, kind: kind)
    }

    func testPermittedWindowIsInclusiveAndOutsideStopGetsZeroStopScore() throws {
        let definition = try station(allowed: (90, 110))
        let engine = try StopScoringEngine(trainLengthMeters: 10, direction: .increasingChainage, stations: [definition])
        let result = try engine.process(
            tick: tick(0, time: 1, position: 110),
            events: [event("arrive", "S1", .arrival), event("stop", "S1", .stopCompleted)]
        )
        let measurement = try XCTUnwrap(result.stationEvaluations.first?.stopMeasurement)
        XCTAssertTrue(measurement.insidePermittedWindow)
        XCTAssertTrue(measurement.trainFitsPlatform)
        XCTAssertEqual(measurement.signedErrorMeters, 10, accuracy: 0.000_001)
        XCTAssertEqual(measurement.absoluteErrorCentimeters, 1_000, accuracy: 0.000_001)
        XCTAssertEqual(result.stationEvaluations[0].componentScores.stop, 0, accuracy: 0.000_001)

        let outside = try StopScoringEngine(trainLengthMeters: 10, direction: .increasingChainage,
                                            stations: [try station(allowed: (90, 110))])
        let outsideResult = try outside.process(
            tick: tick(0, time: 1, position: 110.01),
            events: [event("arrive", "S1", .arrival), event("stop", "S1", .stopCompleted)]
        )
        XCTAssertFalse(try XCTUnwrap(outsideResult.stationEvaluations[0].stopMeasurement).insidePermittedWindow)
        XCTAssertEqual(outsideResult.stationEvaluations[0].componentScores.stop, 0, accuracy: 0.000_001)
    }

    func testPrecisionToleranceBoundaryAndCentimeterConversion() throws {
        let engine = try StopScoringEngine(trainLengthMeters: 10, direction: .increasingChainage,
                                           stations: [try station()])
        let within = try engine.process(
            tick: tick(0, time: 1, position: 100.25),
            events: [event("a", "S1", .arrival), event("s", "S1", .stopCompleted)]
        )
        XCTAssertEqual(within.stationEvaluations[0].componentScores.stop, 100, accuracy: 0.000_001)
        XCTAssertEqual(try XCTUnwrap(within.stationEvaluations[0].stopMeasurement).absoluteErrorCentimeters,
                       25, accuracy: 0.000_001)

        let beyond = try StopScoringEngine(trainLengthMeters: 10, direction: .increasingChainage,
                                           stations: [try station()])
        let outsideTolerance = try beyond.process(
            tick: tick(0, time: 1, position: 100.26),
            events: [event("a", "S1", .arrival), event("s", "S1", .stopCompleted)]
        )
        XCTAssertLessThan(outsideTolerance.stationEvaluations[0].componentScores.stop, 100)
        XCTAssertGreaterThan(outsideTolerance.stationEvaluations[0].componentScores.stop, 0)
    }

    func testWholeTrainFitsAtDirectionSpecificPlatformBoundaries() throws {
        let increasingStation = try station(target: 10, platformStart: 0, platformEnd: 30, allowed: (10, 20))
        let increasing = try StopScoringEngine(trainLengthMeters: 10, direction: .increasingChainage,
                                               stations: [increasingStation])
        let forwardResult = try increasing.process(
            tick: tick(0, time: 1, position: 10),
            events: [event("a", "S1", .arrival), event("s", "S1", .stopCompleted)]
        )
        XCTAssertTrue(try XCTUnwrap(forwardResult.stationEvaluations[0].stopMeasurement).trainFitsPlatform)

        let decreasingStation = try station(target: 10, platformStart: 0, platformEnd: 20, allowed: (0, 10))
        let decreasing = try StopScoringEngine(trainLengthMeters: 10, direction: .decreasingChainage,
                                               stations: [decreasingStation])
        let reverseResult = try decreasing.process(
            tick: tick(0, time: 1, position: 10),
            events: [event("a", "S1", .arrival), event("s", "S1", .stopCompleted)]
        )
        XCTAssertTrue(try XCTUnwrap(reverseResult.stationEvaluations[0].stopMeasurement).trainFitsPlatform)
    }

    func testInvalidTrainAndPolicyConfigurationAreRejected() throws {
        XCTAssertThrowsError(try StopScoringEngine(trainLengthMeters: 31, direction: .increasingChainage,
                                                   stations: [try station(target: 10, platformStart: 0, platformEnd: 30, allowed: (10, 20))]))
        XCTAssertThrowsError(try StopScoringEngine(trainLengthMeters: 0, direction: .increasingChainage,
                                                   stations: [try station()]))
        let badPolicy = GameScoringPolicy(weights: ComponentWeights(stop: 50, timetable: 20, doors: 20, procedures: 5))
        XCTAssertThrowsError(try StopScoringEngine(trainLengthMeters: 10, direction: .increasingChainage,
                                                   stations: [try station()], policy: badPolicy))
        XCTAssertThrowsError(try window(2, 1))
    }

    func testEarlyAndLateArrivalAndDepartureDeviationsAreSignedAndScored() throws {
        let schedule = try StopSchedule(scheduledArrivalSeconds: 100, scheduledDepartureSeconds: 120)
        let engine = try StopScoringEngine(trainLengthMeters: 10, direction: .increasingChainage,
                                           stations: [try station(schedule: schedule)])
        _ = try engine.process(tick: tick(0, time: 60), events: [event("a", "S1", .arrival)])
        _ = try engine.process(tick: tick(1, time: 61), events: [event("s", "S1", .stopCompleted)])
        let result = try engine.process(tick: tick(2, time: 200), events: [event("d", "S1", .departure)])
        let stationResult = result.stationEvaluations[0]
        XCTAssertEqual(try XCTUnwrap(stationResult.arrivalDeviationSeconds), -40, accuracy: 0.000_001)
        XCTAssertEqual(try XCTUnwrap(stationResult.departureDeviationSeconds), 80, accuracy: 0.000_001)
        XCTAssertEqual(stationResult.componentScores.timetable, 99, accuracy: 0.000_001)
    }

    func testDoorAndProcedureEventsAreRecordedAndMistakesAffectGameScore() throws {
        let definition = try station(door: .right, procedures: ["apply", "verify"])
        let engine = try StopScoringEngine(trainLengthMeters: 10, direction: .increasingChainage, stations: [definition])
        let result = try engine.process(
            tick: tick(0, time: 5),
            events: [
                event("arrival", "S1", .arrival),
                event("stop", "S1", .stopCompleted),
                event("wrong-side", "S1", .doorOperation(side: .left, action: .open)),
                event("open", "S1", .doorOperation(side: .right, action: .open)),
                event("close", "S1", .doorOperation(side: .right, action: .close)),
                event("verify-first", "S1", .procedureStep(stepID: "verify", outcome: .completed)),
                event("apply-second", "S1", .procedureStep(stepID: "apply", outcome: .completed)),
                event("depart", "S1", .departure)
            ]
        )
        let stationResult = result.stationEvaluations[0]
        XCTAssertEqual(stationResult.doorOperations.count, 3)
        XCTAssertEqual(stationResult.procedureRecords.count, 2)
        // Wrong-side operation costs 25 points; leaving that door open at departure costs another 20.
        XCTAssertEqual(stationResult.componentScores.doors, 55, accuracy: 0.000_001)
        XCTAssertEqual(stationResult.componentScores.procedures, 85, accuracy: 0.000_001)
    }

    func testMissingDoorCloseAndUnclosedDepartureArePenalized() throws {
        let engine = try StopScoringEngine(trainLengthMeters: 10, direction: .increasingChainage,
                                           stations: [try station(door: .right)])
        let result = try engine.process(
            tick: tick(0, time: 1),
            events: [event("a", "S1", .arrival), event("s", "S1", .stopCompleted),
                     event("o", "S1", .doorOperation(side: .right, action: .open)),
                     event("d", "S1", .departure)]
        )
        XCTAssertEqual(result.stationEvaluations[0].componentScores.doors, 30, accuracy: 0.000_001)
    }

    func testCumulativeStationScoresAndTerminalAssessment() throws {
        let first = try station("A", chainage: 100, target: 100, platformStart: 0, platformEnd: 120, allowed: (90, 110))
        let last = try station("B", chainage: 200, target: 200, platformStart: 120, platformEnd: 220, allowed: (190, 210))
        let engine = try StopScoringEngine(trainLengthMeters: 10, direction: .increasingChainage,
                                           stations: [first, last])
        _ = try engine.process(tick: tick(0, time: 1, position: 100), events: [
            event("a-arrive", "A", .arrival), event("a-stop", "A", .stopCompleted)
        ])
        _ = try engine.process(tick: tick(1, time: 10, position: 100), events: [event("a-depart", "A", .departure)])
        let journey = try engine.process(tick: tick(2, time: 20, position: 200), events: [
            event("b-arrive", "B", .arrival), event("b-stop", "B", .stopCompleted)
        ])
        XCTAssertTrue(journey.isComplete)
        XCTAssertTrue(journey.terminalReachedAndStopped)
        XCTAssertEqual(journey.terminalStationID, "B")
        XCTAssertEqual(journey.cumulativeEarnedPoints, 200, accuracy: 0.000_001)
        XCTAssertEqual(journey.cumulativePossiblePoints, 200, accuracy: 0.000_001)
        XCTAssertEqual(journey.averageScore, 100, accuracy: 0.000_001)
        XCTAssertEqual(journey.grade, .A)
        XCTAssertEqual(journey.stationEvaluations[0].cumulativeEarnedPointsThroughStation, 100, accuracy: 0.000_001)
        XCTAssertEqual(journey.stationEvaluations[1].cumulativeEarnedPointsThroughStation, 200, accuracy: 0.000_001)

        let final = engine.finish()
        XCTAssertEqual(final, journey)
        XCTAssertThrowsError(try engine.process(tick: tick(3, time: 21)))
    }

    func testJourneyWithMissingStopOrDepartureIsIncomplete() throws {
        let first = try station("A", target: 100, platformStart: 0, platformEnd: 120, allowed: (90, 110))
        let last = try station("B", chainage: 200, target: 200, platformStart: 120, platformEnd: 220, allowed: (190, 210))
        let engine = try StopScoringEngine(trainLengthMeters: 10, direction: .increasingChainage,
                                           stations: [first, last])
        let result = try engine.process(tick: tick(0, time: 1), events: [event("a", "A", .arrival)])
        XCTAssertFalse(result.isComplete)
        XCTAssertFalse(result.terminalReachedAndStopped)
        XCTAssertEqual(result.stationEvaluations[0].componentScores.stop, 0, accuracy: 0.000_001)
        XCTAssertEqual(result.stationEvaluations[1].progress, .notStarted)
    }

    func testTickAndEventBoundariesRejectDuplicatesAndInvalidTransitions() throws {
        let engine = try StopScoringEngine(trainLengthMeters: 10, direction: .increasingChainage,
                                           stations: [try station()])
        let arrival = try event("same-id", "S1", .arrival)
        _ = try engine.process(tick: tick(4, time: 4), events: [arrival])
        XCTAssertThrowsError(try engine.process(tick: tick(4, time: 5)))
        XCTAssertThrowsError(try engine.process(tick: tick(5, time: 3)))
        XCTAssertThrowsError(try engine.process(tick: tick(5, time: 5), events: [arrival]))

        let another = try StopScoringEngine(trainLengthMeters: 10, direction: .increasingChainage,
                                            stations: [try station()])
        XCTAssertThrowsError(try another.process(tick: tick(0, time: 1), events: [
            event("stop-too-soon", "S1", .stopCompleted)
        ]))
        XCTAssertThrowsError(try another.process(tick: tick(1, time: 2), events: [
            event("unknown", "missing", .arrival)
        ]))
    }

    func testStopMustBeBelowConfiguredGameSpeedThreshold() throws {
        let engine = try StopScoringEngine(trainLengthMeters: 10, direction: .increasingChainage,
                                           stations: [try station()])
        XCTAssertThrowsError(try engine.process(
            tick: tick(0, time: 1, speed: 0.11),
            events: [event("a", "S1", .arrival), event("s", "S1", .stopCompleted)]
        ))
    }

    func testSnapshotCodableRoundTrip() throws {
        let definition = try station(door: .right, procedures: ["apply", "verify"])
        let engine = try StopScoringEngine(trainLengthMeters: 10, direction: .increasingChainage,
                                           stations: [definition])
        _ = try engine.process(tick: tick(0, time: 5), events: [
            event("arrival", "S1", .arrival), event("stop", "S1", .stopCompleted),
            event("open", "S1", .doorOperation(side: .right, action: .open)),
            event("apply", "S1", .procedureStep(stepID: "apply", outcome: .completed))
        ])

        let snapshot = engine.makeSnapshot()
        let encoded = try JSONEncoder().encode(snapshot)
        let decoded = try JSONDecoder().decode(StopScoringSnapshot.self, from: encoded)
        XCTAssertEqual(snapshot, decoded)
        XCTAssertEqual(decoded.revision, 1)
    }

    func testRestoredSessionContinuesWithSameEvaluation() throws {
        let definition = try station(door: .right, procedures: ["apply", "verify"])
        let original = try StopScoringEngine(trainLengthMeters: 10, direction: .increasingChainage,
                                             stations: [definition])
        _ = try original.process(tick: tick(0, time: 5), events: [
            event("arrival", "S1", .arrival), event("stop", "S1", .stopCompleted),
            event("open", "S1", .doorOperation(side: .right, action: .open)),
            event("apply", "S1", .procedureStep(stepID: "apply", outcome: .completed))
        ])
        let snapshot = try JSONDecoder().decode(StopScoringSnapshot.self,
                                               from: JSONEncoder().encode(original.makeSnapshot()))
        let restored = try StopScoringEngine(trainLengthMeters: 10, direction: .increasingChainage,
                                             stations: [definition])
        try restored.restore(from: snapshot)
        XCTAssertEqual(restored.evaluation(), original.evaluation())

        let nextEvents = [
            try event("close", "S1", .doorOperation(side: .right, action: .close)),
            try event("verify", "S1", .procedureStep(stepID: "verify", outcome: .completed)),
            try event("departure", "S1", .departure)
        ]
        let nextTick = try tick(1, time: 10)
        XCTAssertEqual(try original.process(tick: nextTick, events: nextEvents),
                       try restored.process(tick: nextTick, events: nextEvents))
    }

    func testSnapshotRejectsMismatchedStationOrder() throws {
        let a = try station("A")
        let b = try station("B")
        let source = try StopScoringEngine(trainLengthMeters: 10, direction: .increasingChainage,
                                           stations: [a, b])
        let target = try StopScoringEngine(trainLengthMeters: 10, direction: .increasingChainage,
                                           stations: [b, a])
        XCTAssertThrowsError(try target.restore(from: source.makeSnapshot()))
    }

    func testSnapshotRejectsMalformedTimesAndProcedureIndexesWithoutMutation() throws {
        let definition = try station(procedures: ["apply"])
        let source = try StopScoringEngine(trainLengthMeters: 10, direction: .increasingChainage,
                                           stations: [definition])
        _ = try source.process(tick: tick(0, time: 5), events: [
            event("arrival", "S1", .arrival), event("apply", "S1", .procedureStep(stepID: "apply", outcome: .completed))
        ])
        let baseData = try JSONEncoder().encode(source.makeSnapshot())
        let baseline = try StopScoringEngine(trainLengthMeters: 10, direction: .increasingChainage,
                                             stations: [definition])
        let beforeRestore = baseline.evaluation()

        var malformedTime = try XCTUnwrap(JSONSerialization.jsonObject(with: baseData) as? [String: Any])
        var timeStations = try XCTUnwrap(malformedTime["stations"] as? [[String: Any]])
        timeStations[0]["arrivalSeconds"] = 99.0
        malformedTime["stations"] = timeStations
        let timeSnapshot = try JSONDecoder().decode(StopScoringSnapshot.self,
                                                   from: JSONSerialization.data(withJSONObject: malformedTime))
        XCTAssertThrowsError(try baseline.restore(from: timeSnapshot))
        XCTAssertEqual(baseline.evaluation(), beforeRestore)

        var malformedIndex = try XCTUnwrap(JSONSerialization.jsonObject(with: baseData) as? [String: Any])
        var indexStations = try XCTUnwrap(malformedIndex["stations"] as? [[String: Any]])
        indexStations[0]["successfulRequiredProcedureIndices"] = [99]
        malformedIndex["stations"] = indexStations
        let indexSnapshot = try JSONDecoder().decode(StopScoringSnapshot.self,
                                                     from: JSONSerialization.data(withJSONObject: malformedIndex))
        XCTAssertThrowsError(try baseline.restore(from: indexSnapshot))
        XCTAssertEqual(baseline.evaluation(), beforeRestore)
    }
}
