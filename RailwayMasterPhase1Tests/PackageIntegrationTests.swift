import CrewWorkflow
import Foundation
import IncidentMaintenance
import ProtectionSystems
import RailwayAudioEnhancements
import RailwaySceneFidelity
import RailwayVehicleHighFidelity
import XCTest

final class PackageIntegrationTests: XCTestCase {
    func testHighFidelityVehicleSpecificationIsValid() {
        XCTAssertTrue(RailwayVehicleHighFidelitySpecification.fictionalPrototype.validationIssues().isEmpty)
    }

    func testProtectionSystemsPackageProducesFictionalTickResult() throws {
        let block = try BlockSection(id: "integration-block", trackID: "integration-track", startM: 0, endM: 500)
        let track = try RailwayTrack(id: "integration-track", lengthM: 500, blocks: [block])
        let network = try ProtectionSystems.RailwayNetwork(id: "integration-network", tracks: [track])
        var engine = ProtectionSystemEngine(network: network, systemsByTrain: ["PLAYER": [.atsS]])
        let train = try TrainState(id: "PLAYER", trackID: track.id, frontPositionM: 100, speedKmh: 20, lengthM: 40)
        let frame = try SimulationFrame(fixedTick: 1, timeSeconds: 1.0 / 60.0, trains: [train])

        let result = try engine.step(frame)
        XCTAssertEqual(result.fixedTick, frame.fixedTick)
        XCTAssertEqual(result.label, .fictionalSimulationOnly)
        XCTAssertEqual(result.protectionStates.map(\.system), [ProtectionSystemKind.atsS.rawValue])
    }

    func testCrewWorkflowProgressAndSaveRestore() throws {
        var workflow = CrewWorkflow(runID: "integration-run")
        let phase = try XCTUnwrap(workflow.currentPhase)
        let event = try workflow.complete(
            phase: phase,
            at: Date(timeIntervalSinceReferenceDate: 3),
            satisfiedRequirementIDs: phase.requiredRequirementIDs
        )
        XCTAssertEqual(event.eventID, "integration-run:phase:1")
        XCTAssertEqual(workflow.currentPhase, .preTripVehicleCheck)
        let data = try JSONEncoder().encode(workflow.exportSave())
        let dto = try JSONDecoder().decode(CrewWorkflowSaveDTO.self, from: data)
        let restored = try CrewWorkflow.restore(from: dto)
        XCTAssertEqual(restored.events, workflow.events)
        XCTAssertEqual(restored.currentPhase, workflow.currentPhase)
    }

    func testIncidentTickRecoverySaveRestoreAndDepotTransitions() throws {
        let disclaimer = incidentMaintenanceFictionDisclaimer
        let definition = IncidentEventDefinition(
            id: EventDefinitionID("fictional.integration.event"),
            kind: .vehicleFailure,
            trigger: .manualSignal("game.trigger.integration"),
            occurrenceChancePerEligibleTick: 1_000_000,
            duration: EventDurationRange(minimumTicks: 1, maximumTicks: 3),
            impactScope: .vehicle(VehicleID("PLAYER")),
            effects: GameEffects(tractionMultiplier: 0.9, speedMultiplier: 0.95),
            recoveryRule: .actionRequired("game.recover.integration"),
            fictionalResponsePrompt: "\(disclaimer) — 架空ゲームイベント。画面上の選択肢を使います。",
            fictionalRecoveryPrompt: "\(disclaimer) — 架空ゲームイベントをゲーム内で復旧済みにします。"
        )
        var engine = try IncidentMaintenanceEngine(
            seed: 42,
            eventDefinitions: [definition],
            depotRecord: DepotRecord(vehicleID: VehicleID("PLAYER"), depotID: DepotID("fictional-depot"))
        )
        let start = try engine.advanceOneTick(input: TickInput(manualSignals: ["game.trigger.integration"]))
        XCTAssertEqual(start.startedEvents.count, 1)
        let serialized = try JSONEncoder().encode(engine.exportSave())
        let restoredDTO = try JSONDecoder().decode(IncidentMaintenanceSaveDTO.self, from: serialized)
        engine = try IncidentMaintenanceEngine.restore(from: restoredDTO)
        let recovery = try engine.advanceOneTick(input: TickInput(recoveryActionIDs: ["game.recover.integration"]))
        XCTAssertEqual(recovery.recoveredEvents.count, 1)
        try engine.applyDepotAction(.beginInspection, at: recovery.tick)
        try engine.applyDepotAction(.completeInspection(.needsMaintenance), at: recovery.tick)
        try engine.applyDepotAction(.beginMaintenance, at: recovery.tick)
        try engine.applyDepotAction(.completeMaintenance, at: recovery.tick)
        XCTAssertEqual(engine.state.depotRecord.state, .reinspectionRequired)
        XCTAssertEqual(engine.exportSave().depotRecord.history.count, 4)
    }

    func testAudioAnnouncementSchedulingUsesSimulationClock() throws {
        let request = AnnouncementRequest(
            template: .approachingStation,
            locale: .english,
            context: AnnouncementContext(stationName: "Fictional Central"),
            channel: .onboardAutomated
        )
        let instruction = try XCTUnwrap(AnnouncementRenderer.render(request))
        XCTAssertEqual(instruction.languageTag, "en-GB")
        XCTAssertEqual(instruction.text, "We will soon arrive at Fictional Central.")

        let scheduler = AudioEventScheduler(startTime: 0)
        let event = AudioScheduledEvent(
            id: "integration:announcement:1",
            scheduledTime: 2,
            priority: 3,
            deduplicationKey: "integration:approach:Fictional Central",
            bus: instruction.audioBus,
            payload: .announcement(request)
        )
        XCTAssertEqual(scheduler.schedule(event), .scheduled)
        XCTAssertTrue(try scheduler.advance(to: 1.5).isEmpty)
        XCTAssertEqual(try scheduler.advance(to: 2), [event])
        XCTAssertTrue(try scheduler.advance(to: 2).isEmpty)
    }

    func testSceneFidelityBuildsAChainageBoundedSyntheticCorridor() throws {
        let route = try SceneChainageRoute(controlPoints: [
            SceneRouteControlPoint(
                chainageM: 0,
                position: SceneVector3(0, 0, 0),
                tangentPerMeter: SceneVector3(0, 0, -1)
            ),
            SceneRouteControlPoint(
                chainageM: 160,
                position: SceneVector3(0, 0, -160),
                tangentPerMeter: SceneVector3(0, 0, -1)
            )
        ])
        let camera = SceneCameraState(
            position: SceneVector3(0, 3, 8),
            forward: SceneVector3(0, 0, -1),
            chainageM: 10,
            farDistanceM: 120
        )
        let density = SceneDensityControls(
            visibleDistanceM: 120,
            railChunkLengthM: 12,
            scenerySpacingM: 40,
            maxSceneryAssemblies: 80,
            detailLevel: 0,
            includeRoadVehicles: false,
            includePeople: false,
            includeVegetation: false
        )
        let plan = RailwaySceneFidelityBuilder.build(
            route: route,
            corridor: SceneCorridorSpecification(generateUrbanScenery: false),
            camera: camera,
            density: density
        )
        XCTAssertGreaterThan(plan.diagnostics.generatedAssemblyCount, 0)
        XCTAssertGreaterThan(plan.diagnostics.generatedPieceCount, 0)
        XCTAssertTrue(plan.assemblies.contains(where: { $0.role == .rail }))
    }
}
