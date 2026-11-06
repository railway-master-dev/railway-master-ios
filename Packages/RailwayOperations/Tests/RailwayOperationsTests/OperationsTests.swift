import XCTest
@testable import RailwayOperations

final class OperationsTests: XCTestCase {
    private func makeScenario() throws -> OperationsScenario {
        let stop = try OperationsStopDefinition(
            id: "station-b",
            stationName: "水鏡台",
            targetPositionM: 900,
            scheduledArrivalSeconds: 100,
            scheduledDepartureSeconds: 120,
            positionToleranceM: 1
        )
        return try OperationsScenario(
            runID: "run-1",
            routeID: "fictional-line",
            routeLengthM: 1_000,
            originStationID: "station-a",
            originScheduledDepartureSeconds: 10,
            stops: [stop]
        )
    }

    private func prepareDeparture(_ workflow: inout OperationsWorkflow) throws {
        var time = 0.0
        for check in PreDutyCheck.allCases {
            try workflow.apply(.completePreDutyCheck(check), at: time)
            time += 1
        }
        try workflow.apply(.startCab, at: time)
        time += 1
        for check in CabSetupCheck.allCases {
            try workflow.apply(.completeCabCheck(check), at: time)
            time += 1
        }
        try workflow.apply(.completeDepotExit, at: time)
        time += 1
        try workflow.apply(.observeGameSignal(.proceed), at: time)
        time += 1
        for check in DepartureCheck.allCases {
            try workflow.apply(.completeDepartureCheck(check), at: time)
            time += 1
        }
    }

    func testWorkflowRequiresOrderedPromptsAndEndsAfterPostRunChecks() throws {
        var workflow = OperationsWorkflow(scenario: try makeScenario(), mode: .standard)
        XCTAssertThrowsError(try workflow.apply(.startCab, at: 0))
        try prepareDeparture(&workflow)
        XCTAssertEqual(workflow.phase, .departurePreparation)
        try workflow.apply(.depart, at: 20)
        XCTAssertEqual(workflow.phase, .enRoute)
        try workflow.apply(.arrive(stationID: "station-b", positionM: 900.4, speedMps: 0.05), at: 100)
        XCTAssertEqual(workflow.phase, .stationStop)
        XCTAssertEqual(workflow.stopAssessments.first?.positionErrorM ?? .nan, 0.4, accuracy: 0.0001)
        try workflow.apply(.openDoors, at: 101)
        try workflow.apply(.closeDoors, at: 102)
        XCTAssertThrowsError(try workflow.apply(.depart, at: 103))
        try workflow.apply(.finishRun, at: 104)
        XCTAssertThrowsError(try workflow.apply(.closeOut, at: 105))
        for check in PostRunCheck.allCases {
            try workflow.apply(.completePostRunCheck(check), at: 106)
        }
        try workflow.apply(.closeOut, at: 107)
        XCTAssertEqual(workflow.phase, .completed)
        XCTAssertTrue(workflow.events.allSatisfy { $0.label == .fictionalGameRules })
    }

    func testWorkflowRejectsUnpreparedDepartureAndTimeRegression() throws {
        var workflow = OperationsWorkflow(scenario: try makeScenario(), mode: .practice)
        XCTAssertThrowsError(try workflow.apply(.depart, at: 0))
        try prepareDeparture(&workflow)
        XCTAssertThrowsError(try workflow.apply(.completeDepartureCheck(.routeMarkerPrompt), at: 0))
    }

    func testPointingCallingRequiresDueCheckpointAndScoresExactGamePhrase() throws {
        let definition = try PointingCallingDefinition(
            id: "signal-1",
            trigger: .signalEncounter,
            contextID: "sig-1",
            targetLabel: "信号表示",
            acceptedCallouts: ["信号よし"]
        )
        var tracker = try PointingCallingTracker(definitions: [definition])
        XCTAssertThrowsError(try tracker.perform(checkpointID: "signal-1", callout: "信号よし", at: 1))
        XCTAssertEqual(try tracker.activate(trigger: .signalEncounter, contextID: "sig-1", at: 1, positionM: 30), ["signal-1"])
        let record = try tracker.perform(checkpointID: "signal-1", callout: "信号 よし。", at: 1.5, positionM: 31)
        XCTAssertEqual(record.result, .correct)
        XCTAssertEqual(tracker.coverageRate, 1)
        XCTAssertThrowsError(try tracker.perform(checkpointID: "signal-1", callout: "信号よし", at: 2))
    }

    func testScoringSeparatesFourCategoriesAndDetailedMetrics() throws {
        let schedule = try ScheduleObservation(id: "arrive-b", kind: .arrival, scheduledTimeSeconds: 100, actualTimeSeconds: 110)
        let stop = try StopAssessment(id: "station-b", targetPositionM: 900, actualPositionM: 900.5, toleranceM: 1, stopped: true)
        let samples = [
            try MotionSample(id: "m1", simulationTimeSeconds: 0, accelerationMps2: 0),
            try MotionSample(id: "m2", simulationTimeSeconds: 1, accelerationMps2: 0.2)
        ]
        let rule = try GameRuleOutcome(id: "signal-check", kind: .signalCompliance, passed: true)
        let scorecard = OperationsScorer.evaluate(
            OperationsScoringInput(scheduleObservations: [schedule], stopAssessments: [stop], motionSamples: samples, ruleOutcomes: [rule]),
            mode: .standard
        )
        XCTAssertEqual(scorecard.categories.count, 4)
        XCTAssertEqual(scorecard.score(for: .schedule), 100)
        XCTAssertEqual(scorecard.score(for: .stoppingAccuracy), 100)
        XCTAssertNotNil(scorecard.score(for: .smoothness))
        XCTAssertNotNil(scorecard.score(for: .ruleBasedSkills))
        XCTAssertEqual(scorecard.label, .gameOnlyNotSafetyTraining)
    }

    func testDisruptionEventsAreLimitedToDisruptionModeAndUseFictionalChoices() throws {
        let event = try DisruptionEventDefinition(
            id: "delay-1",
            kind: .simulatedDoorDelay,
            triggerTimeSeconds: 5,
            availableChoices: [.acknowledgeGamePrompt, .requestGameHint],
            expectedGameChoice: .requestGameHint,
            description: "架空のゲーム内遅延イベント"
        )
        XCTAssertThrowsError(try DisruptionTrainingSession(mode: .standard, definitions: [event]))
        var session = try DisruptionTrainingSession(mode: .disruptionTraining, definitions: [event])
        XCTAssertTrue(try session.activateDueEvents(at: 4).isEmpty)
        XCTAssertEqual(try session.activateDueEvents(at: 5).map(\.id), ["delay-1"])
        let result = try session.respond(eventID: "delay-1", choice: .requestGameHint, at: 6)
        XCTAssertTrue(result.matchedGameChoice)
        XCTAssertEqual(result.label, .gameOnlyNotSafetyTraining)
    }

    func testSnapshotEncodesSharedStateAndPreservesContentLabel() throws {
        let workflow = OperationsWorkflow(scenario: try makeScenario(), mode: .practice)
        let train = try SharedTrainSnapshot(trainID: "player", trackID: "track-1", positionM: 12, speedMps: 3, accelerationMps2: 0.1, lengthM: 100)
        let snapshot = try OperationsSnapshot.make(
            workflow: workflow,
            train: train,
            simulationTimeSeconds: 2,
            fixedTick: 240,
            fixedTimeStepSeconds: 1.0 / 120.0
        )
        let data = try JSONEncoder().encode(snapshot)
        let decoded = try JSONDecoder().decode(OperationsSnapshot.self, from: data)
        XCTAssertEqual(decoded, snapshot)
        XCTAssertEqual(decoded.train.positionM, 12)
        XCTAssertEqual(decoded.fixedTick, 240)
        XCTAssertEqual(decoded.contentLabel, .gameOnlyNotSafetyTraining)
    }
}
