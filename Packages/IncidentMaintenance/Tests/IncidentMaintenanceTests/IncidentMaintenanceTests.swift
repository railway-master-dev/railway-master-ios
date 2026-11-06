import Foundation
import XCTest
@testable import IncidentMaintenance

final class IncidentMaintenanceTests: XCTestCase {
    private let disclaimer = incidentMaintenanceFictionDisclaimer

    private func definition(
        id: String = "event.alpha",
        trigger: EventTrigger = .manualSignal("go"),
        chance: UInt32 = 1_000_000,
        minimum: Int = 2,
        maximum: Int = 2,
        rule: RecoveryRule = .actionRequired("resolve")
    ) -> IncidentEventDefinition {
        IncidentEventDefinition(
            id: EventDefinitionID(id), kind: .vehicleFailure, trigger: trigger,
            occurrenceChancePerEligibleTick: chance,
            duration: EventDurationRange(minimumTicks: minimum, maximumTicks: maximum),
            impactScope: .vehicle(VehicleID("vehicle-07")),
            effects: GameEffects(serviceDelayTicks: 4, tractionMultiplier: 0.75, departureHeld: true),
            recoveryRule: rule,
            fictionalResponsePrompt: "\(disclaimer) Fictional game prompt: select a scenario option.",
            fictionalRecoveryPrompt: "\(disclaimer) Fictional game prompt: mark the scenario resolved."
        )
    }

    func testTriggerNonmatchMatchImpactAndStableEventID() throws {
        var engine = try IncidentMaintenanceEngine(seed: 7, eventDefinitions: [
            definition(trigger: .all([.manualSignal("go"), .metricAtLeast(name: "load", threshold: 3),
                                      .eligibleTimeWindow(from: GameTick(1), through: GameTick(4))]))
        ], depotRecord: depot())
        XCTAssertTrue(try engine.advanceOneTick(input: TickInput(manualSignals: ["go"], metrics: ["load": 2])).startedEvents.isEmpty)
        XCTAssertTrue(try engine.advanceOneTick(input: TickInput(manualSignals: [], metrics: ["load": 3])).startedEvents.isEmpty)
        let result = try engine.advanceOneTick(input: TickInput(manualSignals: ["go"], metrics: ["load": 3]))
        let event = try XCTUnwrap(result.startedEvents.first)
        XCTAssertEqual(event.id, EventInstanceID("event.alpha#1"))
        XCTAssertEqual(event.impactScope, .vehicle(VehicleID("vehicle-07")))
        XCTAssertEqual(event.effects.serviceDelayTicks, 4)
        XCTAssertTrue(event.effects.departureHeld)
        XCTAssertTrue(event.fictionalResponsePrompt.contains(disclaimer))
    }

    func testTimingAndDurationVaryAcrossSeedsButReplayIsReproducible() throws {
        let event = definition(trigger: .eligibleTimeWindow(from: GameTick(1), through: GameTick(50)),
                               chance: 180_000, minimum: 1, maximum: 12)
        var observedStarts = Set<UInt64>()
        var observedDurations = Set<Int>()
        for seed in UInt64(1)...UInt64(30) {
            var a = try IncidentMaintenanceEngine(seed: seed, eventDefinitions: [event], depotRecord: depot())
            var b = try IncidentMaintenanceEngine(seed: seed, eventDefinitions: [event], depotRecord: depot())
            var startsA: [IncidentEventRecord] = []
            var startsB: [IncidentEventRecord] = []
            for _ in 1...50 {
                startsA += try a.advanceOneTick().startedEvents
                startsB += try b.advanceOneTick().startedEvents
            }
            XCTAssertEqual(startsA, startsB)
            if let first = startsA.first {
                observedStarts.insert(first.startedAt.value)
                observedDurations.insert(first.sampledDurationTicks)
            }
        }
        XCTAssertGreaterThan(observedStarts.count, 1)
        XCTAssertGreaterThan(observedDurations.count, 1)
    }

    func testRecoveryActionMinimumAndSampledDurationBoundary() throws {
        var actionEngine = try IncidentMaintenanceEngine(seed: 1, eventDefinitions: [
            definition(minimum: 3, maximum: 5)
        ], depotRecord: depot())
        XCTAssertEqual(try actionEngine.advanceOneTick(input: TickInput(manualSignals: ["go"]))
            .startedEvents.count, 1)
        XCTAssertEqual(try actionEngine.advanceOneTick(input: TickInput(recoveryActionIDs: ["resolve"]))
            .activeEvents.count, 1)
        XCTAssertEqual(try actionEngine.advanceOneTick(input: TickInput(recoveryActionIDs: ["resolve"]))
            .activeEvents.count, 1)
        let resolved = try actionEngine.advanceOneTick(input: TickInput(recoveryActionIDs: ["resolve"]))
        XCTAssertEqual(resolved.recoveredEvents.first?.recoveredAt, GameTick(4))

        var timedEngine = try IncidentMaintenanceEngine(seed: 2, eventDefinitions: [
            definition(minimum: 2, maximum: 2, rule: .actionRequired("never"))
        ], depotRecord: depot())
        _ = try timedEngine.advanceOneTick(input: TickInput(manualSignals: ["go"]))
        XCTAssertTrue(try timedEngine.advanceOneTick().recoveredEvents.isEmpty)
        XCTAssertEqual(try timedEngine.advanceOneTick().recoveredEvents.first?.recoveredAt, GameTick(3))
    }

    func testSaveRestoreCodableAndExactRandomContinuation() throws {
        let event = definition(trigger: .eligibleTimeWindow(from: GameTick(1), through: GameTick(80)),
                               chance: 270_000, minimum: 1, maximum: 9)
        var original = try IncidentMaintenanceEngine(seed: 987654, eventDefinitions: [event], depotRecord: depot())
        for _ in 1...6 { _ = try original.advanceOneTick() }
        let encoded = try JSONEncoder().encode(original.exportSave())
        let decoded = try JSONDecoder().decode(IncidentMaintenanceSaveDTO.self, from: encoded)
        var restored = try IncidentMaintenanceEngine.restore(from: decoded)
        for _ in 1...40 {
            let input = TickInput(metrics: ["weather": 1], recoveryActionIDs: [])
            XCTAssertEqual(try original.advanceOneTick(input: input), try restored.advanceOneTick(input: input))
            XCTAssertEqual(original.exportSave(), restored.exportSave())
        }
        XCTAssertEqual(try JSONDecoder().decode(IncidentMaintenanceSaveDTO.self,
                                                   from: JSONEncoder().encode(restored.exportSave())), restored.exportSave())
    }

    func testDepotInspectionRepairReinspectionDispatchPathAndInvalidTransitions() throws {
        var engine = try IncidentMaintenanceEngine(seed: 3, eventDefinitions: [], depotRecord: depot())
        XCTAssertThrowsError(try engine.applyDepotAction(.dispatch, at: GameTick(0)))
        _ = try engine.advanceOneTick()
        try engine.applyDepotAction(.beginInspection, at: GameTick(1))
        _ = try engine.advanceOneTick()
        try engine.applyDepotAction(.completeInspection(.needsMaintenance), at: GameTick(2))
        XCTAssertEqual(engine.state.depotRecord.state, .needsMaintenance)
        _ = try engine.advanceOneTick()
        try engine.applyDepotAction(.beginMaintenance, at: GameTick(3))
        _ = try engine.advanceOneTick()
        try engine.applyDepotAction(.completeMaintenance, at: GameTick(4))
        XCTAssertEqual(engine.state.depotRecord.state, .reinspectionRequired)
        _ = try engine.advanceOneTick()
        try engine.applyDepotAction(.beginReinspection, at: GameTick(5))
        _ = try engine.advanceOneTick()
        try engine.applyDepotAction(.completeReinspection(.passed), at: GameTick(6))
        XCTAssertEqual(engine.state.depotRecord.state, .ready)
        _ = try engine.advanceOneTick()
        try engine.applyDepotAction(.dispatch, at: GameTick(7))
        XCTAssertEqual(engine.state.depotRecord.state, .dispatchable)
        XCTAssertEqual(engine.state.depotRecord.history.count, 7)
        XCTAssertEqual(engine.state.depotRecord.activeInspectionStatus, .completed)
        XCTAssertEqual(engine.state.depotRecord.activeMaintenanceStatus, .completed)
    }

    func testValidationAndDuplicateSuppression() throws {
        XCTAssertThrowsError(try IncidentMaintenanceEngine(seed: 1, eventDefinitions: [
            definition(id: "duplicate"), definition(id: "duplicate")
        ], depotRecord: depot())) { error in
            XCTAssertEqual(error as? IncidentMaintenanceError, .duplicateDefinitionID("duplicate"))
        }
        let original = definition()
        let missingDisclaimer = IncidentEventDefinition(
            id: original.id, kind: original.kind, trigger: original.trigger,
            occurrenceChancePerEligibleTick: original.occurrenceChancePerEligibleTick,
            duration: original.duration, impactScope: original.impactScope,
            effects: original.effects, recoveryRule: original.recoveryRule,
            fictionalResponsePrompt: "ordinary prose", fictionalRecoveryPrompt: "\(disclaimer) game text")
        XCTAssertThrowsError(try IncidentMaintenanceEngine(seed: 1, eventDefinitions: [missingDisclaimer], depotRecord: depot()))

        var engine = try IncidentMaintenanceEngine(seed: 44, eventDefinitions: [
            definition(trigger: .eligibleTimeWindow(from: GameTick(1), through: GameTick(8)), minimum: 8, maximum: 8)
        ], depotRecord: depot())
        var totalStarted = 0
        for _ in 1...5 { totalStarted += try engine.advanceOneTick().startedEvents.count }
        XCTAssertEqual(totalStarted, 1, "one active event per definition must suppress duplicates")
    }

    private func depot() -> DepotRecord {
        DepotRecord(vehicleID: VehicleID("vehicle-07"), depotID: DepotID("depot-north"))
    }
}
