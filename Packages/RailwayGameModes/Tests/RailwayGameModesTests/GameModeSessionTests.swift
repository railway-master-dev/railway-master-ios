import XCTest
@testable import RailwayGameModes

final class GameModeSessionTests: XCTestCase {
    private func makeScenario(playStyle: GameModePlayStyle = .standard) throws -> GameModeScenario {
        let base = try GameModeScenario.placeholder()
        guard playStyle != .standard else { return base }
        return try GameModeScenario(
            routeID: base.routeID,
            routeLengthM: base.routeLengthM,
            stops: base.stops,
            driverDutyStepIDs: base.driverDutyStepIDs,
            driverDepartureCheckStepID: base.driverDepartureCheckStepID,
            playStyle: playStyle,
            landmarks: base.landmarks,
            trainingSteps: base.trainingSteps,
            incident: base.incident,
            requiredAnnouncementIDs: base.requiredAnnouncementIDs,
            dispatchTasks: base.dispatchTasks,
            dispatchSlots: base.dispatchSlots,
            minimumTrainSeparationM: base.minimumTrainSeparationM
        )
    }

    private func snapshot(
        _ scenario: GameModeScenario,
        time: Double = 0,
        tick: UInt64 = 0,
        routeID: String? = nil,
        routeLength: Double? = nil,
        position: Double = 0,
        speed: Double = 0,
        acceleration: Double = 0,
        speedLimit: Double = 80,
        stationID: String? = nil,
        stationEvent: GameModeStationEvent? = nil,
        doors: GameModeDoorState = .closed,
        landmarkID: String? = nil,
        vehicleID: String? = nil,
        weatherID: String? = nil,
        timeOfDayID: String? = nil,
        seasonID: String? = nil,
        passengerLoad: Double? = nil,
        trainingPromptID: String? = nil,
        trains: [GameModeTrainSnapshot] = []
    ) throws -> GameModeSimulationSnapshot {
        try GameModeSimulationSnapshot(
            simulationTimeSeconds: time,
            fixedTick: tick,
            routeID: routeID ?? scenario.routeID,
            routeLengthM: routeLength ?? scenario.routeLengthM,
            positionM: position,
            speedMps: speed,
            accelerationMps2: acceleration,
            speedLimitKmh: speedLimit,
            atStationID: stationID,
            stationEvent: stationEvent,
            doors: doors,
            visibleLandmarkID: landmarkID,
            vehicleID: vehicleID,
            weatherID: weatherID,
            timeOfDayID: timeOfDayID,
            seasonID: seasonID,
            passengerLoadFactor: passengerLoad,
            trainingPromptID: trainingPromptID,
            trains: trains
        )
    }

    func testCatalogDefinesExactlyNineModesWithCompleteContracts() {
        XCTAssertEqual(Set(GameModeCatalog.all.map(\.id)), Set(GameModeID.allCases))
        XCTAssertEqual(GameModeCatalog.all.count, 9)
        for definition in GameModeCatalog.all {
            XCTAssertFalse(definition.initialState.isEmpty)
            XCTAssertFalse(definition.objective.isEmpty)
            XCTAssertFalse(definition.operations.isEmpty)
            XCTAssertFalse(definition.successConditions.isEmpty)
            XCTAssertFalse(definition.failureConditions.isEmpty)
            XCTAssertFalse(definition.uiFields.isEmpty)
            XCTAssertFalse(definition.evaluation.isEmpty)
            XCTAssertEqual(definition.dataLabel, .placeholder)
        }
    }

    func testDriverModeRequiresOrderedDutyChecksStopsAndTerminalStop() throws {
        let scenario = try makeScenario()
        var session = try GameModeSession(mode: .driver, snapshot: snapshot(scenario), scenario: scenario)
        try session.apply(.start)

        for stepID in scenario.driverDutyStepIDs {
            if stepID == scenario.driverDepartureCheckStepID {
                try session.apply(.driverConfirmDeparture)
            } else {
                try session.apply(.driverCompleteDutyStep(stepID))
            }
        }
        try session.update(with: snapshot(scenario, time: 60, tick: 1, position: 600, stationID: "PLACEHOLDER-station-a"))
        try session.update(with: snapshot(scenario, time: 120, tick: 2, position: 1_200, stationID: "PLACEHOLDER-terminal"))
        try session.apply(.finish)

        XCTAssertEqual(session.status, .succeeded)
        XCTAssertEqual(session.evaluation?.metrics["completedDutySteps"] ?? -1, Double(scenario.driverDutyStepIDs.count))
        XCTAssertEqual(session.evaluation?.metrics["visitedStops"] ?? -1, 2.0)
    }

    func testTimetableModeTracksArrivalAndDepartureAgainstSecondBasedPlan() throws {
        let scenario = try makeScenario()
        var session = try GameModeSession(mode: .timetable, snapshot: snapshot(scenario), scenario: scenario)
        try session.apply(.start)
        try session.update(with: snapshot(scenario, time: 60, tick: 1, position: 600, stationID: "PLACEHOLDER-station-a", stationEvent: .arrival))
        try session.update(with: snapshot(scenario, time: 70, tick: 2, position: 600, stationID: "PLACEHOLDER-station-a", stationEvent: .departure))
        try session.update(with: snapshot(scenario, time: 120, tick: 3, position: 1_200, stationID: "PLACEHOLDER-terminal", stationEvent: .arrival))
        try session.apply(.finish)

        XCTAssertEqual(session.status, .succeeded)
        XCTAssertEqual(session.evaluation?.metrics["requiredTimepoints"] ?? -1, 3.0)
        XCTAssertEqual(session.evaluation?.metrics["maxDelaySeconds"] ?? -1, 0.0)
    }

    func testFreeModeQueuesChoicesAndAcceptsHostRouteChangeWithoutInventingValues() throws {
        let scenario = try makeScenario()
        var session = try GameModeSession(mode: .free, snapshot: snapshot(scenario), scenario: scenario)
        try session.apply(.start)
        try session.apply(.freeSetGoal("PLACEHOLDER-goal: visit two views"))
        try session.apply(.freeRequestRoute("PLACEHOLDER-alt-route"))
        try session.apply(.freeRequestVehicle("PLACEHOLDER-vehicle-b"))
        try session.apply(.freeRequestWeather("PLACEHOLDER-rain"))
        try session.apply(.freeRequestTimeOfDay("PLACEHOLDER-evening"))
        try session.apply(.freeRequestSeason("PLACEHOLDER-autumn"))
        try session.apply(.freeRequestPassengerLoad(0.75))
        let effects = session.drainHostEffects()
        XCTAssertTrue(effects.contains(.requestRoute("PLACEHOLDER-alt-route")))
        XCTAssertTrue(effects.contains(.requestVehicle("PLACEHOLDER-vehicle-b")))
        XCTAssertEqual(effects.count, 6)

        try session.update(with: snapshot(
            scenario, time: 30, tick: 1, routeID: "PLACEHOLDER-alt-route", routeLength: 2_000,
            position: 100, vehicleID: "PLACEHOLDER-vehicle-b", weatherID: "PLACEHOLDER-rain",
            timeOfDayID: "PLACEHOLDER-evening", seasonID: "PLACEHOLDER-autumn", passengerLoad: 0.75
        ))
        guard case .free(let progress) = session.progress else { return XCTFail("expected free progress") }
        XCTAssertEqual(progress.selectedRouteID, "PLACEHOLDER-alt-route")
        XCTAssertEqual(progress.selectedVehicleID, "PLACEHOLDER-vehicle-b")
        XCTAssertEqual(progress.selectedWeatherID, "PLACEHOLDER-rain")
        XCTAssertNil(progress.requestedRouteID)
        try session.apply(.finish)
        XCTAssertEqual(session.evaluation?.outcome, .selfDirected)
        XCTAssertNil(session.evaluation?.scorePercent)
    }

    func testConductorModeRequiresHostClosedDoorAcknowledgementAndStationAnnouncements() throws {
        let scenario = try makeScenario()
        var session = try GameModeSession(mode: .conductor, snapshot: snapshot(scenario), scenario: scenario)
        try session.apply(.start)
        try session.update(with: snapshot(scenario, time: 1, tick: 1, position: 600, stationID: "PLACEHOLDER-station-a"))
        try session.apply(.conductorAnnounceStationName)
        try session.apply(.conductorPlayAnnouncement("PLACEHOLDER-arrival-announcement"))
        try session.apply(.conductorOpenDoors(.left))
        try session.apply(.conductorCloseDoors)
        try session.update(with: snapshot(scenario, time: 1, tick: 2, position: 600, stationID: "PLACEHOLDER-station-a", doors: .closed))
        try session.apply(.conductorConfirmDoorClosure)

        try session.update(with: snapshot(scenario, time: 2, tick: 3, position: 1_200, stationID: "PLACEHOLDER-terminal", doors: .closed))
        try session.apply(.conductorAnnounceStationName)
        try session.apply(.conductorOpenDoors(.right))
        try session.apply(.conductorCloseDoors)
        try session.update(with: snapshot(scenario, time: 2, tick: 4, position: 1_200, stationID: "PLACEHOLDER-terminal", doors: .closed))
        try session.apply(.conductorConfirmDoorClosure)
        try session.apply(.finish)

        XCTAssertEqual(session.status, .succeeded)
        XCTAssertEqual(session.evaluation?.metrics["stationNameAnnouncements"] ?? -1, 2.0)
    }

    func testDisruptionModeTriggersDeadlineAndResolvesExpectedGameChoice() throws {
        let scenario = try makeScenario(playStyle: .disruptionTraining)
        var session = try GameModeSession(mode: .disruption, snapshot: snapshot(scenario), scenario: scenario)
        try session.apply(.start)
        try session.update(with: snapshot(scenario, time: 10, tick: 1))
        guard case .disruption(let active) = session.progress else { return XCTFail("expected event progress") }
        XCTAssertEqual(active.state, .active)
        try session.apply(.disruptionRespond(.requestGameHint))
        try session.apply(.finish)
        XCTAssertEqual(session.status, .succeeded)
        XCTAssertEqual(session.evaluation?.metrics["correctResponses"] ?? -1, 1.0)
    }

    func testTrainingModeRequiresOrderedStepsAndHostPrompts() throws {
        let scenario = try makeScenario()
        var session = try GameModeSession(mode: .training, snapshot: snapshot(scenario), scenario: scenario)
        try session.apply(.start)
        try session.apply(.trainingCompleteStep("PLACEHOLDER-control-check"))
        try session.update(with: snapshot(scenario, time: 1, tick: 1, trainingPromptID: "PLACEHOLDER-signal-prompt"))
        try session.apply(.trainingCompleteStep("PLACEHOLDER-signal-display"))
        try session.update(with: snapshot(scenario, time: 2, tick: 2, trainingPromptID: "PLACEHOLDER-protection-prompt"))
        try session.apply(.trainingCompleteStep("PLACEHOLDER-protection-display"))
        try session.update(with: snapshot(scenario, time: 3, tick: 3))
        try session.apply(.trainingCompleteStep("PLACEHOLDER-limit"))
        try session.update(with: snapshot(scenario, time: 4, tick: 4, stationID: "PLACEHOLDER-station-a"))
        try session.apply(.trainingCompleteStep("PLACEHOLDER-stop"))
        try session.apply(.finish)

        XCTAssertEqual(session.status, .succeeded)
        XCTAssertEqual(session.evaluation?.metrics["completedSteps"] ?? -1, 5.0)
    }

    func testFullLineModeRequiresRouteOriginAndOrderedStopsToTerminal() throws {
        let scenario = try makeScenario()
        let initial = try snapshot(scenario)
        var session = try GameModeSession(mode: .fullLine, snapshot: initial, scenario: scenario)
        try session.apply(.start)
        try session.update(with: snapshot(scenario, time: 60, tick: 1, position: 600, stationID: "PLACEHOLDER-station-a"))
        try session.update(with: snapshot(scenario, time: 120, tick: 2, position: 1_200, stationID: "PLACEHOLDER-terminal"))
        try session.apply(.finish)
        XCTAssertEqual(session.status, .succeeded)

        let midRouteStart = try snapshot(scenario, position: 100)
        let blocked = try GameModeSession(mode: .fullLine, snapshot: midRouteStart, scenario: scenario)
        XCTAssertEqual(blocked.status, .blocked)
        XCTAssertEqual(blocked.evaluation?.blockingReason, .mustStartAtRouteOrigin)
    }

    func testTourismModeOnlyCountsVisibleNearbySlowEnoughLandmarks() throws {
        let scenario = try makeScenario()
        var session = try GameModeSession(mode: .tourism, snapshot: snapshot(scenario), scenario: scenario)
        try session.apply(.start)
        try session.update(with: snapshot(scenario, time: 10, tick: 1, position: 300, speed: 8, landmarkID: "PLACEHOLDER-view-a"))
        try session.apply(.tourismObserve("PLACEHOLDER-view-a"))
        try session.update(with: snapshot(scenario, time: 20, tick: 2, position: 900, speed: 8, landmarkID: "PLACEHOLDER-view-b"))
        try session.apply(.tourismObserve("PLACEHOLDER-view-b"))
        try session.update(with: snapshot(scenario, time: 30, tick: 3, position: 1_200))
        try session.apply(.finish)
        XCTAssertEqual(session.status, .succeeded)
        XCTAssertEqual(session.evaluation?.metrics["observedLandmarks"] ?? -1, 2.0)
    }

    func testCompanyOperationsAssignsMultipleTrainsToNonConflictingSlots() throws {
        let scenario = try makeScenario()
        let trains = [
            try GameModeTrainSnapshot(id: "PLACEHOLDER-train-1", routeID: scenario.routeID, trackID: "PLACEHOLDER-track-1", positionM: 0, speedMps: 0),
            try GameModeTrainSnapshot(id: "PLACEHOLDER-train-2", routeID: scenario.routeID, trackID: "PLACEHOLDER-track-2", positionM: 1_000, speedMps: 0)
        ]
        var session = try GameModeSession(mode: .companyOperations, snapshot: snapshot(scenario, trains: trains), scenario: scenario)
        try session.apply(.start)
        try session.apply(.companyAssign(taskID: "PLACEHOLDER-task-1", slotID: "PLACEHOLDER-slot-1"))
        try session.apply(.companyAssign(taskID: "PLACEHOLDER-task-2", slotID: "PLACEHOLDER-slot-2"))
        try session.apply(.finish)
        XCTAssertEqual(session.status, .succeeded)
        XCTAssertEqual(session.evaluation?.metrics["assignedTasks"] ?? -1, 2.0)
    }

    func testFailureAndBlockedAreDistinctFromSuccess() throws {
        let scenario = try makeScenario()
        var driver = try GameModeSession(mode: .driver, snapshot: snapshot(scenario), scenario: scenario)
        try driver.apply(.start)
        try driver.update(with: snapshot(scenario, time: 1, tick: 1, speed: 30))
        XCTAssertEqual(driver.status, .failed)
        XCTAssertEqual(driver.failureReason, .overspeedObserved)

        let sparse = try GameModeScenario(
            routeID: "PLACEHOLDER-empty-route",
            routeLengthM: 100,
            stops: [],
            driverDutyStepIDs: GameModeScenario.defaultDriverDutyStepIDs,
            incident: GameModeIncidentPlan(id: "PLACEHOLDER-event", kind: .vehicleFault, displayText: "PLACEHOLDER event", triggerAfterSeconds: 10, responseDeadlineSeconds: 10, expectedChoice: .acknowledgeGamePrompt)
        )
        let blocked = try GameModeSession(
            mode: .training,
            snapshot: GameModeSimulationSnapshot(simulationTimeSeconds: 0, routeID: sparse.routeID, routeLengthM: sparse.routeLengthM, positionM: 0, speedMps: 0, speedLimitKmh: 0),
            scenario: sparse
        )
        XCTAssertEqual(blocked.status, .blocked)
        XCTAssertEqual(blocked.evaluation?.outcome, .blocked)
        XCTAssertNil(blocked.failureReason)
        XCTAssertEqual(blocked.evaluation?.blockingReason, .missingTrainingSteps)
    }

    func testPlayStylesAreIndependentAndPracticeHintsAreTestable() throws {
        let practice = try makeScenario(playStyle: .practice)
        var session = try GameModeSession(mode: .free, snapshot: snapshot(practice), scenario: practice)
        try session.apply(.start)
        try session.apply(.modeRequestHint)
        XCTAssertEqual(session.hintCount, 1)
        XCTAssertTrue(session.drainHostEffects().contains { if case .presentGameHint = $0 { return true }; return false })

        XCTAssertThrowsError(try GameModeSession(mode: .driver, snapshot: snapshot(practice), scenario: try makeScenario(playStyle: .freeRun)))
    }

    func testTimeAndFixedTickCannotRegress() throws {
        let scenario = try makeScenario()
        let initial = try snapshot(scenario, time: 1, tick: 5)
        var session = try GameModeSession(mode: .free, snapshot: initial, scenario: scenario)
        XCTAssertThrowsError(try session.update(with: snapshot(scenario, time: 1, tick: 4)))
        XCTAssertEqual(session.status, .ready)
    }

    func testTimetableOutOfOrderArrivalFailsDistinctly() throws {
        let scenario = try makeScenario()
        var session = try GameModeSession(mode: .timetable, snapshot: snapshot(scenario), scenario: scenario)
        try session.apply(.start)
        try session.update(with: snapshot(scenario, time: 120, tick: 1, position: 1_200, stationID: "PLACEHOLDER-terminal", stationEvent: .arrival))
        XCTAssertEqual(session.status, .failed)
        XCTAssertEqual(session.failureReason, .stopOrderViolation)
        XCTAssertEqual(session.evaluation?.metrics["orderViolations"] ?? -1, 1.0)
    }

    func testConductorWrongPlatformSideFailsAndUnknownDoorInputBlocks() throws {
        let scenario = try makeScenario()
        var session = try GameModeSession(mode: .conductor, snapshot: snapshot(scenario), scenario: scenario)
        try session.apply(.start)
        try session.update(with: snapshot(scenario, time: 1, tick: 1, position: 600, stationID: "PLACEHOLDER-station-a"))
        try session.apply(.conductorOpenDoors(.right))
        XCTAssertEqual(session.status, .failed)
        XCTAssertEqual(session.failureReason, .wrongPlatformSide)

        let unknownDoorSnapshot = try snapshot(scenario, doors: .unknown)
        let blocked = try GameModeSession(mode: .conductor, snapshot: unknownDoorSnapshot, scenario: scenario)
        XCTAssertEqual(blocked.status, .blocked)
        XCTAssertEqual(blocked.evaluation?.blockingReason, .unknownInitialDoorState)
    }

    func testCompanyOperationsBlocksUntilRequiredTrainSnapshotsExist() throws {
        let scenario = try makeScenario()
        let session = try GameModeSession(mode: .companyOperations, snapshot: snapshot(scenario), scenario: scenario)
        XCTAssertEqual(session.status, .blocked)
        XCTAssertEqual(session.evaluation?.blockingReason, .missingTrainSnapshots)
        XCTAssertNil(session.failureReason)
    }
}
