import XCTest
@testable import RailwayMaintenance

final class DepotMaintenanceTests: XCTestCase {
    private func makeSnapshot(time: Double = 0, trainID: String = "T1", positionM: Double = 100, speedMps: Double = 0) -> MaintenanceSimulationSnapshot {
        MaintenanceSimulationSnapshot(
            routeID: "fictional-route",
            routeLengthM: 5_000,
            simulationTimeSeconds: time,
            fixedTick: 0,
            fixedTimeStepSeconds: 1,
            trackIDs: ["track-A"],
            trains: [MaintenanceTrainSnapshot(
                trainID: trainID, trackID: "track-A", positionM: positionM, speedMps: speedMps,
                direction: .increasingChainage, lengthM: 200, stationID: nil, isInService: true
            )]
        )
    }

    private func makeEngine(capacity: Int = 1, vehicles: [String] = ["T1"], stoppedSpeedThreshold: Double = 0.1) -> DepotOperationEngine {
        let depot = DepotDefinition(
            id: "depot-1",
            routeID: "fictional-route",
            accessTrackID: "track-A",
            accessChainageM: 100,
            entryTransferDurationSeconds: 2,
            exitTransferDurationSeconds: 3,
            tracks: [DepotTrackDefinition(id: "yard-1", capacity: capacity, allowedVehicleProfileIDs: ["fictional-unit"])]
        )
        let records = vehicles.map {
            MaintenanceVehicleRecord(
                id: $0,
                profileID: "fictional-unit",
                lengthM: 200,
                location: .onRoute(trackID: "track-A", chainageM: 100)
            )
        }
        return DepotOperationEngine(depots: [depot], vehicles: records, stoppedSpeedThresholdMps: stoppedSpeedThreshold)
    }

    private func enterDepot(_ engine: inout DepotOperationEngine, vehicleID: String = "T1") throws {
        _ = try engine.handle(
            .requestEntry(vehicleID: vehicleID, depotID: "depot-1", depotTrackID: "yard-1"),
            at: 0,
            snapshot: makeSnapshot(trainID: vehicleID)
        )
        _ = engine.advance(to: 2)
    }

    private func inspectAndPass(_ engine: inout DepotOperationEngine, vehicleID: String = "T1", at time: Double) throws {
        let started = try engine.handle(
            .beginInspection(vehicleID: vehicleID, kind: .preServiceGameCheck, durationSeconds: 0),
            at: time
        )
        _ = engine.advance(to: time)
        let inspectionID = try XCTUnwrap(started.referenceID, "Inspection start should return an inspection ID")
        _ = try engine.handle(
            .submitInspectionResult(inspectionID: inspectionID, result: .passed(findings: [])),
            at: time
        )
    }

    func testDepotEntryRequiresHostStateAndTracksCapacity() throws {
        var engine = makeEngine(capacity: 1, vehicles: ["T1", "T2"])
        _ = try engine.handle(
            .requestEntry(vehicleID: "T1", depotID: "depot-1", depotTrackID: "yard-1"),
            at: 0,
            snapshot: makeSnapshot()
        )
        XCTAssertThrowsError(try engine.handle(
            .requestEntry(vehicleID: "T2", depotID: "depot-1", depotTrackID: "yard-1"),
            at: 0,
            snapshot: makeSnapshot(trainID: "T2")
        )) { error in
            XCTAssertEqual(error as? DepotOperationError, .depotTrackFull("yard-1"))
        }
        _ = engine.advance(to: 2)
        XCTAssertEqual(engine.state.vehicles.first(where: { $0.id == "T1" })?.operationalState, .inspectionDue)
    }

    func testInspectionAllocationAndExitStateFlow() throws {
        var engine = makeEngine()
        try enterDepot(&engine)
        XCTAssertEqual(engine.state.vehicles[0].operationalState, .inspectionDue)
        try inspectAndPass(&engine, at: 2)
        XCTAssertEqual(engine.state.vehicles[0].operationalState, .ready)
        _ = try engine.handle(.allocate(vehicleID: "T1", serviceID: "service-7"), at: 2)
        XCTAssertEqual(engine.state.vehicles[0].operationalState, .allocated)
        _ = try engine.handle(.requestExit(vehicleID: "T1", serviceID: "service-7"), at: 2)
        XCTAssertEqual(engine.state.vehicles[0].operationalState, .transitToService)
        let completed = engine.advance(to: 5)
        XCTAssertTrue(completed.contains(where: { $0.kind == .movementCompleted }))
        XCTAssertEqual(engine.state.vehicles[0].operationalState, .inService)
        XCTAssertEqual(engine.state.vehicles[0].location, .onRoute(trackID: "track-A", chainageM: 100))
    }

    func testScenarioFaultRequiresCorrectiveTaskAndReinspection() throws {
        var engine = makeEngine()
        try enterDepot(&engine)
        try inspectAndPass(&engine, at: 2)
        _ = try engine.handle(.recordScenarioFault(vehicleID: "T1", eventInstanceID: "fault-1"), at: 2)
        XCTAssertEqual(engine.state.vehicles[0].inspectionClearance, .repairRequired)
        XCTAssertEqual(engine.state.vehicles[0].operationalState, .repairHold)

        let scheduled = try engine.handle(
            .scheduleMaintenance(vehicleID: "T1", kind: .correctiveScenarioRepair, durationSeconds: 5, requiresReinspection: true),
            at: 2
        )
        let taskID = try XCTUnwrap(scheduled.referenceID, "Scheduling should return a maintenance task ID")
        _ = try engine.handle(.beginMaintenance(taskID: taskID), at: 2)
        _ = engine.advance(to: 7)
        XCTAssertTrue(engine.state.vehicles[0].activeScenarioFaultEventIDs.isEmpty)
        XCTAssertEqual(engine.state.vehicles[0].inspectionClearance, .reinspectionRequired)
        XCTAssertEqual(engine.state.vehicles[0].operationalState, .inspectionDue)

        try inspectAndPass(&engine, at: 7)
        XCTAssertEqual(engine.state.vehicles[0].inspectionClearance, .cleared)
        XCTAssertEqual(engine.state.vehicles[0].operationalState, .ready)
    }

    func testEntryRejectsMovingOrDistantTrain() {
        var engine = makeEngine()
        let moving = MaintenanceSimulationSnapshot(
            routeID: "fictional-route", routeLengthM: 5_000, simulationTimeSeconds: 0,
            fixedTick: 0, fixedTimeStepSeconds: 1, trackIDs: ["track-A"],
            trains: [MaintenanceTrainSnapshot(trainID: "T1", trackID: "track-A", positionM: 100, speedMps: 2, lengthM: 200)]
        )
        XCTAssertThrowsError(try engine.handle(
            .requestEntry(vehicleID: "T1", depotID: "depot-1", depotTrackID: "yard-1"),
            at: 0,
            snapshot: moving
        )) { error in
            XCTAssertEqual(error as? DepotOperationError, .vehicleNotAtDepotAccess)
        }
    }

    func testDepotStateCanBeSavedAndRestored() throws {
        var engine = makeEngine()
        try enterDepot(&engine)
        let encoded = try JSONEncoder().encode(engine.state)
        let restored = try JSONDecoder().decode(DepotOperationState.self, from: encoded)
        XCTAssertEqual(restored, engine.state)
    }

    func testMaintenanceCannotStartDuringInProgressOrAwaitingInspection() throws {
        var engine = makeEngine()
        try enterDepot(&engine)
        let scheduled = try engine.handle(
            .scheduleMaintenance(vehicleID: "T1", kind: .scheduledGameplayService, durationSeconds: 5, requiresReinspection: false),
            at: 2
        )
        let taskID = try XCTUnwrap(scheduled.referenceID, "Scheduling should return a maintenance task ID")
        let inspection = try engine.handle(
            .beginInspection(vehicleID: "T1", kind: .scheduledGameCheck, durationSeconds: 10),
            at: 2
        )

        XCTAssertThrowsError(try engine.handle(.beginMaintenance(taskID: taskID), at: 2)) { error in
            XCTAssertEqual(error as? DepotOperationError, .activeInspection)
        }
        _ = engine.advance(to: 12)
        XCTAssertThrowsError(try engine.handle(.beginMaintenance(taskID: taskID), at: 12)) { error in
            XCTAssertEqual(error as? DepotOperationError, .activeInspection)
        }
        let inspectionID = try XCTUnwrap(inspection.referenceID, "Inspection start should return an inspection ID")
        _ = try engine.handle(
            .submitInspectionResult(inspectionID: inspectionID, result: .passed(findings: [])),
            at: 12
        )
        XCTAssertEqual(try engine.handle(.beginMaintenance(taskID: taskID), at: 12).kind, .maintenanceStarted)
    }

    func testConfiguredDepotStoppedThresholdIsAppliedWithoutDefaultSnapshotThreshold() throws {
        var engine = makeEngine(stoppedSpeedThreshold: 0.5)
        _ = try engine.handle(
            .requestEntry(vehicleID: "T1", depotID: "depot-1", depotTrackID: "yard-1"),
            at: 0,
            snapshot: makeSnapshot(speedMps: 0.4)
        )
        XCTAssertEqual(engine.state.vehicles[0].operationalState, .transitToDepot)
    }
}
