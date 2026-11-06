import Foundation
import XCTest
@testable import DoorProcedureScoring

final class DoorProcedureScoringEngineTests: XCTestCase {
    func testCorrectDoorSideAndExpectedRoleProcedureEarnFullScore() throws {
        let station = try makeStation(
            id: "PLACEHOLDER-01",
            doorSide: .known(.left),
            procedures: .known([
                try ProcedureRequirement(stepID: "fictional.prompt-choice", role: .conductor)
            ])
        )
        let engine = try DoorProcedureScoringEngine(stations: [station])

        try engine.record(event("door-1", station: station.stationID, time: 2, kind: .doorSideAcknowledged(.left)))
        try engine.record(event("step-1", station: station.stationID, time: 3,
                                kind: .procedureStep(stepID: "fictional.prompt-choice", role: .conductor, outcome: .completed)))
        let result = try engine.finalizeStation(stationID: station.stationID, at: 4)
        let score = try XCTUnwrap(result.stationEvaluations.first)

        XCTAssertEqual(score.earnedPoints, 2)
        XCTAssertEqual(score.possiblePoints, 2)
        XCTAssertEqual(score.scorePercent, 100)
        XCTAssertEqual(score.doorSideAssessment, .earned(expected: .left, observed: .left))
        guard case let .requirements(steps) = score.procedureAssessment else {
            return XCTFail("Expected known procedure requirements.")
        }
        XCTAssertEqual(steps.first?.result, .completed)
    }

    func testKnownButOmittedRequirementsScoreZeroOnlyAfterFinalization() throws {
        let station = try makeStation(
            id: "PLACEHOLDER-02",
            doorSide: .known(.right),
            procedures: .known([try ProcedureRequirement(stepID: "fictional.marker-choice", role: .driver)])
        )
        let engine = try DoorProcedureScoringEngine(stations: [station])

        let inProgress = engine.evaluation().stationEvaluations[0]
        XCTAssertNil(inProgress.scorePercent)
        XCTAssertEqual(inProgress.possiblePoints, 2)
        XCTAssertEqual(inProgress.doorSideAssessment, .pending(expected: .right))
        guard case let .requirements(pendingSteps) = inProgress.procedureAssessment else {
            return XCTFail("Expected requirement while station is in progress.")
        }
        XCTAssertEqual(pendingSteps.first?.result, .pending)

        let final = try engine.finalizeStation(stationID: station.stationID, at: 10)
        let score = final.stationEvaluations[0]
        XCTAssertEqual(score.earnedPoints, 0)
        XCTAssertEqual(score.scorePercent, 0)
        XCTAssertEqual(score.doorSideAssessment, .notPerformed(expected: .right))
        guard case let .requirements(finalSteps) = score.procedureAssessment else {
            return XCTFail("Expected known procedure requirements.")
        }
        XCTAssertEqual(finalSteps.first?.result, .notPerformed)
    }

    func testMissingAndUnknownFieldsAreNotInferredOrPenalized() throws {
        let missing = try makeStation(id: "PLACEHOLDER-MISSING", doorSide: .missing, procedures: .missing)
        let unknown = try makeStation(
            id: "PLACEHOLDER-UNKNOWN",
            doorSide: .unknown(.sourceDoesNotSpecify),
            procedures: .unknown(.notCollected)
        )
        let engine = try DoorProcedureScoringEngine(stations: [missing, unknown])

        try engine.record(event("m-1", station: missing.stationID, time: 1, kind: .doorSideAcknowledged(.left)))
        try engine.record(event("m-2", station: missing.stationID, time: 2,
                                kind: .procedureStep(stepID: "unlisted-step", role: .driver, outcome: .completed)))
        try engine.finalizeStation(stationID: missing.stationID, at: 3)
        try engine.finalizeStation(stationID: unknown.stationID, at: 4)

        let results = engine.evaluation().stationEvaluations
        XCTAssertEqual(results[0].possiblePoints, 0)
        XCTAssertNil(results[0].scorePercent)
        XCTAssertEqual(results[0].doorSideAssessment, .notEvaluable(.missing))
        XCTAssertEqual(results[0].procedureAssessment, .requirementsUnavailable(.missing))
        XCTAssertEqual(results[0].unmatchedProcedureEventIDs, ["m-2"])
        XCTAssertEqual(results[1].possiblePoints, 0)
        XCTAssertNil(results[1].scorePercent)
        XCTAssertEqual(results[1].doorSideAssessment, .notEvaluable(.unknown(.sourceDoesNotSpecify)))
        XCTAssertEqual(results[1].procedureAssessment, .requirementsUnavailable(.unknown(.notCollected)))
        XCTAssertNil(engine.evaluation().scorePercent)
    }

    func testWrongRoleDoesNotEarnProcedurePoints() throws {
        let station = try makeStation(
            id: "PLACEHOLDER-ROLE",
            doorSide: .known(.noDoorSide),
            procedures: .known([try ProcedureRequirement(stepID: "fictional.selection", role: .stationStaff)])
        )
        let engine = try DoorProcedureScoringEngine(stations: [station])
        try engine.record(event("wrong-role", station: station.stationID, time: 1,
                                kind: .procedureStep(stepID: "fictional.selection", role: .driver, outcome: .completed)))
        try engine.record(event("no-side", station: station.stationID, time: 2,
                                kind: .doorSideAcknowledged(.noDoorSide)))

        let final = try engine.finalizeStation(stationID: station.stationID, at: 3)
        let score = final.stationEvaluations[0]
        XCTAssertEqual(score.earnedPoints, 1)
        XCTAssertEqual(score.possiblePoints, 2)
        guard case let .requirements(steps) = score.procedureAssessment else {
            return XCTFail("Expected known procedure requirements.")
        }
        XCTAssertEqual(steps.first?.result, .wrongRole(observedRoles: [.driver]))
    }

    func testExplicitNoDoorSideIsAValidKnownGameValue() throws {
        let station = try makeStation(id: "PLACEHOLDER-NONE", doorSide: .known(.noDoorSide), procedures: .known([]))
        let engine = try DoorProcedureScoringEngine(stations: [station])
        try engine.record(event("none", station: station.stationID, time: 1, kind: .doorSideAcknowledged(.noDoorSide)))
        let score = try engine.finalizeStation(stationID: station.stationID, at: 2).stationEvaluations[0]

        XCTAssertEqual(score.earnedPoints, 1)
        XCTAssertEqual(score.possiblePoints, 1)
        XCTAssertEqual(score.doorSideAssessment, .earned(expected: .noDoorSide, observed: .noDoorSide))
        XCTAssertEqual(score.procedureAssessment, .knownNoRequirements)
    }

    func testLatestAcknowledgementAndExpectedRoleAttemptDetermineResult() throws {
        let station = try makeStation(
            id: "PLACEHOLDER-RETRY",
            doorSide: .known(.left),
            procedures: .known([try ProcedureRequirement(stepID: "fictional.choice", role: .driver)])
        )
        let engine = try DoorProcedureScoringEngine(stations: [station])
        try engine.record(event("side-wrong", station: station.stationID, time: 1, kind: .doorSideAcknowledged(.right)))
        try engine.record(event("step-failed", station: station.stationID, time: 2,
                                kind: .procedureStep(stepID: "fictional.choice", role: .driver, outcome: .incorrect)))
        try engine.record(event("side-correct", station: station.stationID, time: 3, kind: .doorSideAcknowledged(.left)))
        try engine.record(event("step-correct", station: station.stationID, time: 4,
                                kind: .procedureStep(stepID: "fictional.choice", role: .driver, outcome: .completed)))
        let score = try engine.finalizeStation(stationID: station.stationID, at: 5).stationEvaluations[0]

        XCTAssertEqual(score.scorePercent, 100)
        XCTAssertEqual(score.doorSideAssessment, .earned(expected: .left, observed: .left))
    }

    func testDefinitionDecodingPreservesAbsentAndExplicitNull() throws {
        let absentJSON = Data(#"{"stationID":"PLACEHOLDER-ABSENT"}"#.utf8)
        let nullJSON = Data(#"{"stationID":"PLACEHOLDER-NULL","expectedDoorSide":null,"procedureRequirements":null}"#.utf8)
        let absent = try JSONDecoder().decode(StationScoringDefinition.self, from: absentJSON)
        let explicitNull = try JSONDecoder().decode(StationScoringDefinition.self, from: nullJSON)

        XCTAssertEqual(absent.expectedDoorSide, .missing)
        XCTAssertEqual(absent.procedureRequirements, .missing)
        XCTAssertEqual(explicitNull.expectedDoorSide, .unknown(.explicitNull))
        XCTAssertEqual(explicitNull.procedureRequirements, .unknown(.explicitNull))
    }

    func testDuplicateEventUnknownStationAndTimeRegressionAreRejected() throws {
        let station = try makeStation(id: "PLACEHOLDER-ERRORS", doorSide: .known(.left), procedures: .known([]))
        let engine = try DoorProcedureScoringEngine(stations: [station])
        let accepted = try event("same-id", station: station.stationID, time: 2, kind: .doorSideAcknowledged(.left))
        try engine.record(accepted)

        XCTAssertThrowsError(try engine.record(accepted)) { error in
            XCTAssertEqual(error as? DoorProcedureScoringError, .duplicateEventID("same-id"))
        }
        XCTAssertThrowsError(try engine.record(event("unknown", station: "NO-SUCH-STATION", time: 3,
                                                       kind: .doorSideAcknowledged(.left)))) { error in
            XCTAssertEqual(error as? DoorProcedureScoringError, .unknownStation("NO-SUCH-STATION"))
        }
        XCTAssertThrowsError(try engine.record(event("early", station: station.stationID, time: 1,
                                                       kind: .doorSideAcknowledged(.left)))) { error in
            guard let scoringError = error as? DoorProcedureScoringError,
                  case .invalidTime(_) = scoringError else {
                return XCTFail("Expected invalidTime, got \(error)")
            }
        }
        XCTAssertEqual(engine.evaluation().stationEvaluations[0].doorSideEvents.count, 1)
    }

    func testFinishLeavesUnvisitedStationsUnscoredAndFreezesEvents() throws {
        let station = try makeStation(id: "PLACEHOLDER-UNVISITED", doorSide: .known(.left), procedures: .known([]))
        let engine = try DoorProcedureScoringEngine(stations: [station])
        let finished = engine.finish()

        XCTAssertTrue(finished.isFinished)
        XCTAssertEqual(finished.finalizedStationCount, 0)
        XCTAssertEqual(finished.unfinalizedStationIDs, [station.stationID])
        XCTAssertEqual(finished.possiblePoints, 0)
        XCTAssertNil(finished.scorePercent)
        XCTAssertThrowsError(try engine.record(event("late", station: station.stationID, time: 1,
                                                       kind: .doorSideAcknowledged(.left)))) { error in
            XCTAssertEqual(error as? DoorProcedureScoringError, .sessionFinished)
        }
        XCTAssertEqual(engine.finish(), finished)
    }

    func testSnapshotRoundTripAndContinuationAreEquivalent() throws {
        let first = try makeStation(id: "PLACEHOLDER-SNAPSHOT-1", doorSide: .known(.left), procedures: .known([]))
        let second = try makeStation(
            id: "PLACEHOLDER-SNAPSHOT-2",
            doorSide: .known(.right),
            procedures: .known([try ProcedureRequirement(stepID: "fictional.resume", role: .driver)])
        )
        let policy = try DoorProcedureScoringPolicy(doorSidePoints: 2, procedureStepPoints: 3)
        let original = try DoorProcedureScoringEngine(stations: [first, second], policy: policy)
        try original.record(event("snapshot-door", station: first.stationID, time: 2, kind: .doorSideAcknowledged(.left)))
        try original.finalizeStation(stationID: first.stationID, at: 3)

        let encoded = try JSONEncoder().encode(original.snapshot())
        let decoded = try JSONDecoder().decode(DoorProcedureScoringEngineSnapshot.self, from: encoded)
        let restored = try DoorProcedureScoringEngine(stations: [first, second], policy: policy)
        try restored.restore(from: decoded)
        XCTAssertEqual(restored.evaluation(), original.evaluation())
        XCTAssertEqual(decoded.stationDefinitions, [first, second])
        XCTAssertEqual(decoded.stationStates[0].finalizedAtSeconds, 3)
        XCTAssertEqual(decoded.seenEventIDs, ["snapshot-door"])

        let nextDoor = try event("resumed-door", station: second.stationID, time: 4, kind: .doorSideAcknowledged(.right))
        let nextProcedure = try event("resumed-step", station: second.stationID, time: 5,
                                      kind: .procedureStep(stepID: "fictional.resume", role: .driver, outcome: .completed))
        try original.record(nextDoor)
        try original.record(nextProcedure)
        try restored.record(nextDoor)
        try restored.record(nextProcedure)
        XCTAssertEqual(try original.finalizeStation(stationID: second.stationID, at: 6),
                       try restored.finalizeStation(stationID: second.stationID, at: 6))
        XCTAssertEqual(original.finish(), restored.finish())
        let finishedSnapshotData = try JSONEncoder().encode(restored.snapshot())
        let finishedSnapshot = try JSONDecoder().decode(DoorProcedureScoringEngineSnapshot.self, from: finishedSnapshotData)
        let finishedRestored = try DoorProcedureScoringEngine(stations: [first, second], policy: policy)
        try finishedRestored.restore(from: finishedSnapshot)
        XCTAssertTrue(finishedRestored.evaluation().isFinished)
        XCTAssertThrowsError(try finishedRestored.record(event("after-finish", station: second.stationID, time: 7,
                                                               kind: .doorSideAcknowledged(.right))))
    }

    func testSnapshotRejectsIncompatibleStationOrderAndDefinitions() throws {
        let first = try makeStation(id: "PLACEHOLDER-IDENTITY-1", doorSide: .known(.left), procedures: .known([]))
        let second = try makeStation(id: "PLACEHOLDER-IDENTITY-2", doorSide: .known(.right), procedures: .known([]))
        let engine = try DoorProcedureScoringEngine(stations: [first, second])
        let snapshot = engine.snapshot()

        let reordered = try DoorProcedureScoringEngine(stations: [second, first])
        XCTAssertThrowsError(try reordered.restore(from: snapshot)) { error in
            guard case .some(.incompatibleSnapshot(_)) = error as? DoorProcedureScoringError else {
                return XCTFail("Expected incompatible station definitions, got \(error)")
            }
        }
        let changed = try makeStation(id: first.stationID, doorSide: .known(.right), procedures: .known([]))
        let altered = try DoorProcedureScoringEngine(stations: [changed, second])
        XCTAssertThrowsError(try altered.restore(from: snapshot))
    }

    func testMalformedSnapshotIsRejectedWithoutMutatingEngine() throws {
        let station = try makeStation(id: "PLACEHOLDER-MALFORMED", doorSide: .known(.left), procedures: .known([]))
        let source = try DoorProcedureScoringEngine(stations: [station])
        try source.record(event("valid-event", station: station.stationID, time: 5, kind: .doorSideAcknowledged(.left)))
        let valid = source.snapshot()
        let malformed = DoorProcedureScoringEngineSnapshot(
            scoringPolicy: valid.scoringPolicy,
            stationDefinitions: valid.stationDefinitions,
            stationStates: valid.stationStates,
            seenEventIDs: valid.seenEventIDs,
            lastAcceptedTimeSeconds: 1,
            isFinished: valid.isFinished
        )
        let target = try DoorProcedureScoringEngine(stations: [station])
        let before = target.evaluation()
        XCTAssertThrowsError(try target.restore(from: malformed)) { error in
            guard case .some(.invalidSnapshot(_)) = error as? DoorProcedureScoringError else {
                return XCTFail("Expected malformed snapshot rejection, got \(error)")
            }
        }
        XCTAssertEqual(target.evaluation(), before)
        try target.record(event("after-rejection", station: station.stationID, time: 1, kind: .doorSideAcknowledged(.right)))
        XCTAssertEqual(target.evaluation().stationEvaluations[0].doorSideEvents.map(\.eventID), ["after-rejection"])
    }

    func testDuplicateRequirementIDsAreRejected() throws {
        let duplicateA = try ProcedureRequirement(stepID: "fictional.same", role: .driver)
        let duplicateB = try ProcedureRequirement(stepID: "fictional.same", role: .conductor)
        XCTAssertThrowsError(try StationScoringDefinition(
            stationID: "PLACEHOLDER-DUPLICATE",
            procedureRequirements: .known([duplicateA, duplicateB])
        ))
    }

    private func makeStation(
        id: String,
        doorSide: FieldData<DoorSide>,
        procedures: FieldData<[ProcedureRequirement]>
    ) throws -> StationScoringDefinition {
        try StationScoringDefinition(
            stationID: id,
            displayName: "Fictional \(id)",
            expectedDoorSide: doorSide,
            procedureRequirements: procedures
        )
    }

    private func event(_ id: String, station: String, time: Double, kind: ScoringEventKind) throws -> ScoringEvent {
        try ScoringEvent(eventID: id, stationID: station, simulationTimeSeconds: time, kind: kind)
    }
}
