import Foundation
import XCTest
@testable import ProtectionSystems

final class ProtectionSystemsTests: XCTestCase {
    private func makeNetwork(extraRoute: Bool = false) throws -> RailwayNetwork {
        let trackID = "sim-main"
        let blocks = [
            try BlockSection(id: "b0", trackID: trackID, startM: 0, endM: 400),
            try BlockSection(id: "b1", trackID: trackID, startM: 400, endM: 800),
            try BlockSection(id: "b2", trackID: trackID, startM: 800, endM: 1200)
        ]
        let track = try RailwayTrack(id: trackID, lengthM: 1200, blocks: blocks)
        let equipment = [
            try RouteEquipment(id: "beacon-s", trackID: trackID, kind: .atsSBeacon, positionM: 200),
            try RouteEquipment(id: "target-p", trackID: trackID, kind: .atsPProfileTarget, positionM: 250,
                               targetPositionM: 600, targetSpeedKmh: 0),
            try RouteEquipment(id: "beacon-ps", trackID: trackID, kind: .atsPsSpeedBeacon, positionM: 700,
                               targetSpeedKmh: 25, supervisionDistanceM: 100),
            try RouteEquipment(id: "zone-atc", trackID: trackID, kind: .atcCommandZone, positionM: 500,
                               targetSpeedKmh: 60, zoneStartM: 0, zoneEndM: 1200),
            try RouteEquipment(id: "target-ato", trackID: trackID, kind: .atoTarget, positionM: 500,
                               targetPositionM: 900, targetSpeedKmh: 0)
        ]
        let switches = [try SwitchDefinition(id: "sw0", trackID: trackID, positionM: 820, positions: ["main", "branch"])]
        var routes = [
            try RouteDefinition(id: "R-main", trackID: trackID, protectedBlockIDs: ["b1", "b2"],
                                requiredSwitchPositions: ["sw0": "main"], conflictsWithRouteIDs: ["R-branch"]),
            try RouteDefinition(id: "R-branch", trackID: trackID, protectedBlockIDs: ["b1", "b2"],
                                requiredSwitchPositions: ["sw0": "branch"], conflictsWithRouteIDs: ["R-main"])
        ]
        if extraRoute {
            routes.append(try RouteDefinition(id: "R-second", trackID: trackID, protectedBlockIDs: ["b1"],
                                              requiredSwitchPositions: ["sw0": "main"], conflictsWithRouteIDs: ["R-main"]))
        }
        let signals = [
            try SignalDefinition(id: "sig-b1", trackID: trackID, positionM: 380, protectedBlockID: "b1", governingRouteID: "R-main"),
            try SignalDefinition(id: "sig-b2", trackID: trackID, positionM: 780, protectedBlockID: "b2", governingRouteID: "R-main")
        ]
        return try RailwayNetwork(id: "fictional-test-net", tracks: [track], equipment: equipment,
                                  switches: switches, routes: routes, signals: signals)
    }

    private func makeTrain(_ id: String, _ position: Double, _ speed: Double, _ length: Double = 100,
                           trackID: String = "sim-main", direction: TravelDirection = .increasingChainage) throws -> TrainState {
        try TrainState(id: id, trackID: trackID, frontPositionM: position, speedKmh: speed,
                       lengthM: length, direction: direction)
    }

    private func makeFrame(_ tick: UInt64, _ time: Double, _ trains: [TrainState],
                           switches: [String: String] = ["sw0": "main"],
                           routes: [String: String] = [:],
                           inputs: [String: OperatorInput] = [:],
                           timetable: [TimetableRouteAssignment] = []) throws -> SimulationFrame {
        try SimulationFrame(fixedTick: tick, timeSeconds: time, trains: trains,
                            switchPositions: switches, routeRequests: routes,
                            operatorInputs: inputs, timetableAssignments: timetable)
    }

    private func makeConfiguration(
        atsSTimeout: Double = 2,
        atspDeceleration: Double = 0.8,
        atspMargin: Double = 0,
        ebWarning: Double = 2,
        ebBrake: Double = 4,
        deadmanWarning: Double = 1,
        deadmanBrake: Double = 2,
        prcLead: Double = 30
    ) throws -> ProtectionEngineConfiguration {
        try ProtectionEngineConfiguration(
            approachRadiusM: 300,
            atssAcknowledgementTimeoutSeconds: atsSTimeout,
            atspVirtualDecelerationMps2: atspDeceleration,
            atspSafetyMarginM: atspMargin,
            overspeedToleranceKmh: 0,
            atcSpeedCommandsByClearBlocks: [0: 0, 1: 25, 2: 50, 3: 80],
            driverActivityWarningSeconds: ebWarning,
            driverActivityBrakeSeconds: ebBrake,
            deadmanWarningSeconds: deadmanWarning,
            deadmanBrakeSeconds: deadmanBrake,
            atoMaximumSpeedKmh: 75,
            atoVirtualDecelerationMps2: 1,
            atoAccelerationGain: 0.08,
            atoBrakeGain: 0.15,
            prcDispatchLeadSeconds: prcLead
        )
    }

    private func state(_ system: ProtectionSystemKind, in result: SimulationResult, trainID: String = "player") -> SystemProtectionState? {
        result.protectionStates.first { $0.trainID == trainID && $0.system == system.rawValue }
    }

    func testATSSTriggerAcknowledgementAndTimeoutAreSeparateStates() throws {
        var engine = ProtectionSystemEngine(network: try makeNetwork(), systemsByTrain: ["player": [.atsS]],
                                            configuration: try makeConfiguration())
        _ = try engine.step(makeFrame(1, 0, [makeTrain("player", 180, 20)]))
        let warning = try engine.step(makeFrame(2, 1, [makeTrain("player", 205, 20)]))
        XCTAssertTrue(warning.events.contains { $0.kind == .warning && $0.system == "atsS" })
        XCTAssertEqual(state(.atsS, in: warning)?.brakeCommanded, false)
        let expired = try engine.step(makeFrame(3, 3, [makeTrain("player", 220, 20)]))
        XCTAssertEqual(state(.atsS, in: expired)?.brakeCommanded, true)
        XCTAssertTrue(expired.events.contains { $0.kind == .automaticBrake && $0.system == "atsS" })
    }

    func testATSSAcknowledgementBeforeConfiguredDeadlineAvoidsSimulatedBrake() throws {
        var engine = ProtectionSystemEngine(network: try makeNetwork(), systemsByTrain: ["player": [.atsS]],
                                            configuration: try makeConfiguration())
        _ = try engine.step(makeFrame(1, 0, [makeTrain("player", 180, 20)]))
        _ = try engine.step(makeFrame(2, 1, [makeTrain("player", 205, 20)]))
        let acknowledged = try engine.step(makeFrame(3, 2, [makeTrain("player", 210, 20)],
                                                      inputs: ["player": OperatorInput(acknowledgeATSS: true)]))
        XCTAssertEqual(state(.atsS, in: acknowledged)?.brakeCommanded, false)
        XCTAssertEqual(state(.atsS, in: acknowledged)?.stateDescription, "standby / acknowledged")
    }

    func testATSPUsesDistanceProfileWhileATSPSUsesBoundedPointBeaconWindow() throws {
        var atsPEngine = ProtectionSystemEngine(network: try makeNetwork(), systemsByTrain: ["player": [.atsP]],
                                                configuration: try makeConfiguration(atspDeceleration: 0.8))
        let atsP = try atsPEngine.step(makeFrame(1, 0, [makeTrain("player", 580, 50)]))
        XCTAssertEqual(state(.atsP, in: atsP)?.brakeCommanded, true)
        XCTAssertNotNil(state(.atsP, in: atsP)?.permittedSpeedKmh)
        XCTAssertTrue(atsP.events.contains { $0.kind == .overspeed && $0.system == "atsP" })

        var atsPsEngine = ProtectionSystemEngine(network: try makeNetwork(), systemsByTrain: ["player": [.atsPs]],
                                                 configuration: try makeConfiguration())
        let beforeBeacon = try atsPsEngine.step(makeFrame(1, 0, [makeTrain("player", 690, 30)]))
        XCTAssertNil(state(.atsPs, in: beforeBeacon)?.permittedSpeedKmh)
        let crossedBeacon = try atsPsEngine.step(makeFrame(2, 1, [makeTrain("player", 705, 30)]))
        XCTAssertEqual(state(.atsPs, in: crossedBeacon)?.permittedSpeedKmh, 25)
        XCTAssertEqual(state(.atsPs, in: crossedBeacon)?.brakeCommanded, true)
        let leftWindow = try atsPsEngine.step(makeFrame(3, 2, [makeTrain("player", 805, 20)]))
        XCTAssertNil(state(.atsPs, in: leftWindow)?.permittedSpeedKmh)
    }

    func testATCContinuousCommandUsesOtherTrainBlockOccupancy() throws {
        var engine = ProtectionSystemEngine(network: try makeNetwork(), systemsByTrain: ["player": [.atc]],
                                            configuration: try makeConfiguration())
        let result = try engine.step(makeFrame(1, 0, [makeTrain("player", 350, 40), makeTrain("lead", 950, 10)]))
        XCTAssertEqual(state(.atc, in: result)?.permittedSpeedKmh, 25)
        XCTAssertEqual(state(.atc, in: result)?.brakeCommanded, true)
        XCTAssertTrue(result.blockOccupancy.first { $0.id == "b2" }?.trainIDs.contains("lead") == true)
    }

    func testInterlockingDeniesOccupiedBlockAndMisalignedSwitch() throws {
        let network = try makeNetwork()
        let evaluator = InterlockingEvaluator(network: network)
        let occupied = try evaluator.evaluate(makeFrame(1, 0, [makeTrain("player", 100, 0), makeTrain("lead", 850, 0)],
                                                         routes: ["player": "R-main"]))
        XCTAssertEqual(occupied.routeGrants.first { $0.trainID == "player" }?.granted, false)
        XCTAssertTrue(occupied.routeGrants.first { $0.trainID == "player" }?.denialReason?.contains("occupied") == true)
        XCTAssertEqual(occupied.signals.first { $0.id == "sig-b1" }?.aspect, .stop)

        let misaligned = try evaluator.evaluate(makeFrame(2, 1, [makeTrain("player", 100, 0)],
                                                           switches: ["sw0": "branch"], routes: ["player": "R-main"]))
        XCTAssertEqual(misaligned.routeGrants.first?.granted, false)
        XCTAssertTrue(misaligned.routeGrants.first?.denialReason?.contains("switch") == true)
    }

    func testConflictingRoutesCannotBothBeGranted() throws {
        let network = try makeNetwork(extraRoute: true)
        let evaluator = InterlockingEvaluator(network: network)
        let result = try evaluator.evaluate(makeFrame(1, 0, [makeTrain("first", 100, 0), makeTrain("second", 120, 0)],
                                                       routes: ["first": "R-main", "second": "R-second"]))
        XCTAssertEqual(result.routeGrants.first { $0.trainID == "first" }?.granted, true)
        XCTAssertEqual(result.routeGrants.first { $0.trainID == "second" }?.granted, false)
        XCTAssertTrue(result.routeGrants.first { $0.trainID == "second" }?.denialReason?.contains("conflicts") == true)
    }

    func testATOCommandHoldsForUnapprovedRouteOrStopSignal() throws {
        var engine = ProtectionSystemEngine(network: try makeNetwork(), systemsByTrain: ["player": [.ato]],
                                            configuration: try makeConfiguration())
        let result = try engine.step(makeFrame(1, 0, [makeTrain("player", 500, 20)], switches: ["sw0": "branch"],
                                                routes: ["player": "R-main"]))
        let command = result.atoCommands["player"]
        XCTAssertEqual(command?.holdForRoute, true)
        XCTAssertEqual(command?.brakeFraction, 1)
        XCTAssertEqual(result.routeGrants.first?.granted, false)
    }

    func testEBAndDeadmanUseDistinctTimers() throws {
        var engine = ProtectionSystemEngine(network: try makeNetwork(), systemsByTrain: ["player": [.eb, .deadman]],
                                            configuration: try makeConfiguration(ebWarning: 2, ebBrake: 4,
                                                                                 deadmanWarning: 1, deadmanBrake: 2))
        let first = try engine.step(makeFrame(1, 0, [makeTrain("player", 100, 20)],
                                              inputs: ["player": OperatorInput(deadmanHeld: false)]))
        XCTAssertEqual(state(.eb, in: first)?.brakeCommanded, false)
        XCTAssertEqual(state(.deadman, in: first)?.brakeCommanded, false)
        let second = try engine.step(makeFrame(2, 2, [makeTrain("player", 110, 20)],
                                               inputs: ["player": OperatorInput(deadmanHeld: false)]))
        XCTAssertEqual(state(.eb, in: second)?.brakeCommanded, false)
        XCTAssertEqual(state(.deadman, in: second)?.brakeCommanded, true)
        let third = try engine.step(makeFrame(3, 4, [makeTrain("player", 120, 20)],
                                              inputs: ["player": OperatorInput(deadmanHeld: false)]))
        XCTAssertEqual(state(.eb, in: third)?.brakeCommanded, true)
        XCTAssertEqual(state(.deadman, in: third)?.brakeCommanded, true)
    }

    func testPRCProposesButInterlockingApprovesAndCTCReportsSameTick() throws {
        var engine = ProtectionSystemEngine(network: try makeNetwork(), systemsByTrain: ["player": []],
                                            configuration: try makeConfiguration(prcLead: 30))
        let assignment = try TimetableRouteAssignment(id: "plan-1", trainID: "player", nextRouteID: "R-main",
                                                       plannedDepartureTimeSeconds: 30)
        let result = try engine.step(makeFrame(1, 0, [makeTrain("player", 100, 0)], timetable: [assignment]))
        XCTAssertEqual(result.routeGrants.first?.granted, true)
        XCTAssertTrue(result.events.contains { $0.kind == .timetableRouteProposed && $0.system == "PRC" })
        XCTAssertEqual(result.ctcTrains.first?.routeGranted, true)
        XCTAssertEqual(result.ctcTrains.first?.requestedRouteID, "R-main")
        XCTAssertEqual(result.label, .fictionalSimulationOnly)
    }

    func testEquipmentApproachEventIsMountedToRoutePosition() throws {
        var engine = ProtectionSystemEngine(network: try makeNetwork(), systemsByTrain: ["player": []],
                                            configuration: try makeConfiguration())
        let result = try engine.step(makeFrame(1, 0, [makeTrain("player", 100, 0)]))
        XCTAssertTrue(result.events.contains { $0.kind == .equipmentApproach && $0.sourceID == "beacon-s" })
    }

    func testEngineRejectsNonIncreasingFixedTickOrTime() throws {
        var engine = ProtectionSystemEngine(network: try makeNetwork(), systemsByTrain: [:],
                                            configuration: try makeConfiguration())
        _ = try engine.step(makeFrame(2, 2, [makeTrain("player", 100, 0)]))
        XCTAssertThrowsError(try engine.step(makeFrame(2, 3, [makeTrain("player", 110, 0)])))
        XCTAssertThrowsError(try engine.step(makeFrame(3, 2, [makeTrain("player", 110, 0)])))
    }

    func testProtectionLatchCannotBeResetWhileMovingButCanBeResetAfterStop() throws {
        var engine = ProtectionSystemEngine(network: try makeNetwork(), systemsByTrain: ["player": [.atsP]],
                                            configuration: try makeConfiguration())
        let overspeed = try engine.step(makeFrame(1, 0, [makeTrain("player", 580, 50)]))
        XCTAssertEqual(state(.atsP, in: overspeed)?.brakeCommanded, true)
        XCTAssertThrowsError(try engine.step(makeFrame(2, 1, [makeTrain("player", 585, 5)],
                                                       inputs: ["player": OperatorInput(resetProtectionAtStop: true)])))
        let stoppedReset = try engine.step(makeFrame(2, 2, [makeTrain("player", 580, 0)],
                                                      inputs: ["player": OperatorInput(resetProtectionAtStop: true)]))
        XCTAssertEqual(state(.atsP, in: stoppedReset)?.brakeCommanded, false)
        XCTAssertTrue(stoppedReset.events.contains { $0.kind == .protectionReset })
    }

    func testExampleScenarioDecodesAndEmitsIntegratedEvents() throws {
        let exampleURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Examples")
            .appendingPathComponent("approach-scenario.json")
        let exampleData = try Data(contentsOf: exampleURL)
        guard let document = try JSONSerialization.jsonObject(with: exampleData) as? [String: Any],
              let networkObject = document["network"],
              let frameObjects = document["frames"] as? [[String: Any]] else {
            XCTFail("Example scenario must contain a network and frames.")
            return
        }
        let networkData = try JSONSerialization.data(withJSONObject: networkObject)
        let network = try JSONDecoder().decode(RailwayNetwork.self, from: networkData)
        var engine = ProtectionSystemEngine(network: network,
                                            systemsByTrain: ["player": Set(ProtectionSystemKind.allCases)],
                                            configuration: try makeConfiguration())
        var allEvents: [SimulationEvent] = []
        var lastResult: SimulationResult?
        for object in frameObjects {
            let frameData = try JSONSerialization.data(withJSONObject: object)
            let frame = try JSONDecoder().decode(SimulationFrame.self, from: frameData)
            let result = try engine.step(frame)
            allEvents.append(contentsOf: result.events)
            lastResult = result
        }
        XCTAssertTrue(allEvents.contains { $0.kind == .routeDenied })
        XCTAssertTrue(allEvents.contains { $0.kind == .warning && $0.system == "atsS" })
        XCTAssertTrue(allEvents.contains { $0.kind == .overspeed && $0.system == "atsP" })
        XCTAssertTrue(allEvents.contains { $0.kind == .overspeed && $0.system == "atsPs" })
        XCTAssertEqual(lastResult?.label, .fictionalSimulationOnly)
    }
}
