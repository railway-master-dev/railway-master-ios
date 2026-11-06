import Foundation
import XCTest
@testable import CrewWorkflow

final class CrewWorkflowTests: XCTestCase {
    private func simTime(_ seconds: TimeInterval) -> Date {
        Date(timeIntervalSinceReferenceDate: seconds)
    }

    private func completeRemainingPhases(_ workflow: inout CrewWorkflow, startingAt start: TimeInterval = 100) throws {
        let phases = CrewWorkflowPhase.allCases
        guard let currentPhase = workflow.currentPhase,
              let startIndex = phases.firstIndex(of: currentPhase) else { return }
        for (offset, phase) in phases.dropFirst(startIndex).enumerated() {
            try workflow.complete(
                phase: phase,
                at: simTime(start + Double(offset)),
                satisfiedRequirementIDs: phase.requiredRequirementIDs
            )
        }
    }

    func testCompletesEntireWorkflowInSpecifiedOrder() throws {
        var workflow = CrewWorkflow(runID: "test-run")
        XCTAssertEqual(CrewWorkflowPhase.allCases.map(\.rawValue), [
            "attendance_roll_call", "pre_trip_vehicle_check", "cab_startup", "instrument_check",
            "depot_exit", "shunting", "pre_departure_check", "door_closing", "departure",
            "signal_check", "speed_check", "speed_limit_compliance", "station_approach",
            "precise_stop", "post_stop_check", "crew_communication", "abnormal_response",
            "terminal_arrival", "depot_entry", "duty_end"
        ])
        try completeRemainingPhases(&workflow)
        XCTAssertNil(workflow.currentPhase)
        XCTAssertEqual(workflow.events.count, CrewWorkflowPhase.allCases.count)
        XCTAssertThrowsError(try workflow.complete(phase: .dutyEnd, at: simTime(200), satisfiedRequirementIDs: [])) {
            XCTAssertEqual($0 as? CrewWorkflowError, .noActivePhase)
        }
    }

    func testRejectsOutOfOrderAndMissingRequirementsWithReasons() throws {
        var workflow = CrewWorkflow(runID: "ordered")
        XCTAssertThrowsError(try workflow.complete(phase: .cabStartup, at: simTime(1), satisfiedRequirementIDs: [])) {
            XCTAssertEqual($0 as? CrewWorkflowError, .outOfOrder(expected: .attendanceRollCall, received: .cabStartup))
        }
        XCTAssertThrowsError(try workflow.complete(phase: .attendanceRollCall, at: simTime(1), satisfiedRequirementIDs: [])) {
            XCTAssertEqual($0 as? CrewWorkflowError, .missingRequirements(phase: .attendanceRollCall, ids: ["game_ack_attendance_roll_call"]))
            XCTAssertTrue(($0 as? LocalizedError)?.errorDescription?.contains("game_ack_attendance_roll_call") == true)
        }
        XCTAssertTrue(workflow.events.isEmpty)
        XCTAssertEqual(workflow.currentPhase, .attendanceRollCall)
    }

    func testRejectsSimulationTimeGoingBackwards() throws {
        var workflow = CrewWorkflow(runID: "clock")
        try workflow.complete(phase: .attendanceRollCall, at: simTime(10), satisfiedRequirementIDs: CrewWorkflowPhase.attendanceRollCall.requiredRequirementIDs)
        XCTAssertThrowsError(try workflow.complete(phase: .preTripVehicleCheck, at: simTime(9), satisfiedRequirementIDs: CrewWorkflowPhase.preTripVehicleCheck.requiredRequirementIDs)) {
            XCTAssertEqual($0 as? CrewWorkflowError, .timeWentBackwards(previous: simTime(10), attempted: simTime(9)))
        }
        XCTAssertEqual(workflow.events.count, 1)
    }

    func testEventAndStableIDContract() throws {
        var workflow = CrewWorkflow(runID: "contract-run")
        let event = try workflow.complete(phase: .attendanceRollCall, at: simTime(42), satisfiedRequirementIDs: CrewWorkflowPhase.attendanceRollCall.requiredRequirementIDs)
        XCTAssertEqual(event.eventID, "contract-run:phase:1")
        XCTAssertEqual(event.runID, "contract-run")
        XCTAssertEqual(event.timestamp, simTime(42))
        XCTAssertEqual(event.eventType, .phaseCompleted)
        XCTAssertEqual(event.phaseBefore.rawValue, "attendance_roll_call")
        XCTAssertEqual(event.phaseAfter?.rawValue, "pre_trip_vehicle_check")
        XCTAssertEqual(event.satisfiedRequirementIDs, ["game_ack_attendance_roll_call"])
        XCTAssertEqual(CrewWorkflowPhase.terminalArrival.rawValue, "terminal_arrival")
        XCTAssertTrue(CrewWorkflowContent.prompt(for: .departure).contains(CrewWorkflowContent.disclaimer))
        XCTAssertTrue(CrewWorkflowContent.evaluations.allSatisfy { $0.labeledText.contains(CrewWorkflowContent.disclaimer) })
    }

    func testCodableSaveRestoreAndResumeMidRun() throws {
        var original = CrewWorkflow(runID: "persisted-run")
        for (index, phase) in CrewWorkflowPhase.allCases.prefix(7).enumerated() {
            try original.complete(phase: phase, at: simTime(100 + Double(index)), satisfiedRequirementIDs: phase.requiredRequirementIDs)
        }
        let dto = original.exportSave()
        let encoded = try JSONEncoder().encode(dto)
        let decoded = try JSONDecoder().decode(CrewWorkflowSaveDTO.self, from: encoded)
        XCTAssertEqual(decoded, dto)

        var resumed = try CrewWorkflow.restore(from: decoded)
        XCTAssertEqual(resumed.runID, "persisted-run")
        XCTAssertEqual(resumed.currentPhase, .doorClosing)
        XCTAssertEqual(resumed.events, original.events)
        XCTAssertEqual(resumed.events.map(\.eventID), original.events.map(\.eventID))
        try completeRemainingPhases(&resumed, startingAt: 107)
        XCTAssertNil(resumed.currentPhase)
        XCTAssertEqual(resumed.events.count, CrewWorkflowPhase.allCases.count)
        XCTAssertTrue(resumed.events.allSatisfy { $0.runID == "persisted-run" })
    }

    func testRestoreRejectsInconsistentSave() throws {
        let invalid = CrewWorkflowSaveDTO(runID: "bad", currentPhase: .departure, lastSimulationTime: nil, events: [])
        XCTAssertThrowsError(try CrewWorkflow.restore(from: invalid))

        var workflow = CrewWorkflow(runID: "verified")
        let validEvent = try workflow.complete(phase: .attendanceRollCall, at: simTime(1),
                                               satisfiedRequirementIDs: CrewWorkflowPhase.attendanceRollCall.requiredRequirementIDs)
        let alteredEvent = CrewWorkflowEvent(eventID: "not-stable", runID: validEvent.runID,
                                             timestamp: validEvent.timestamp, eventType: validEvent.eventType,
                                             phaseBefore: validEvent.phaseBefore, phaseAfter: validEvent.phaseAfter,
                                             satisfiedRequirementIDs: validEvent.satisfiedRequirementIDs)
        let alteredSave = CrewWorkflowSaveDTO(runID: "verified", currentPhase: .preTripVehicleCheck,
                                              lastSimulationTime: simTime(1), events: [alteredEvent])
        XCTAssertThrowsError(try CrewWorkflow.restore(from: alteredSave))
    }
}
