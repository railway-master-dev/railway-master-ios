import XCTest
@testable import TrafficSimulation

final class TrafficActorPoseSamplerTests: XCTestCase {
    func testFrameContainsOpposingTrainsCarsAndWalkingPlatformPassengers() throws {
        let scenario = TrafficScenarioLibrary.fictionalParallelCorridor
        var engine = try TrafficSimulationEngine(scenario: scenario)
        let snapshot = try engine.advance(realDeltaSeconds: 80)
        let frame = try TrafficActorPoseSampler.sample(scenario: scenario, snapshot: snapshot)

        XCTAssertEqual(frame.simulationTimeSeconds, snapshot.simulationTimeSeconds, accuracy: 1e-9)
        XCTAssertEqual(frame.fixedTick, snapshot.fixedTick)
        XCTAssertEqual(frame.poses.count, scenario.trains.count + scenario.roadVehicles.count + scenario.passengerTrips.count)
        XCTAssertTrue(frame.poses.allSatisfy { $0.id.hasPrefix(scenario.scenarioID + "/") })

        let east = try XCTUnwrap(frame.poses.first { $0.sourceID == "ai-east-01" })
        let west = try XCTUnwrap(frame.poses.first { $0.sourceID == "ai-west-01" })
        XCTAssertEqual(east.kind, .train)
        XCTAssertEqual(west.kind, .train)
        XCTAssertEqual(east.headingRadians, 0, accuracy: 1e-9)
        XCTAssertEqual(west.headingRadians, .pi, accuracy: 1e-9)
        XCTAssertTrue(east.isVisible)
        XCTAssertTrue(west.isVisible)

        let cars = frame.poses.filter { $0.kind == .roadVehicle }
        XCTAssertEqual(cars.count, scenario.roadVehicles.count)
        XCTAssertTrue(cars.contains { abs($0.wheelRotationRadians) > 0.01 })

        let people = frame.poses.filter { $0.kind == .platformPassenger }
        XCTAssertEqual(people.count, scenario.passengerTrips.count)
        XCTAssertTrue(people.contains { $0.phase == .walking })
        XCTAssertTrue(people.allSatisfy { $0.isVisible })
        XCTAssertEqual(Set(frame.poses.map(\.id)).count, frame.poses.count)
    }

    func testInterpolationUsesSimulationTimeAndIsRepeatable() throws {
        let scenario = TrafficScenarioLibrary.fictionalParallelCorridor
        var engine = try TrafficSimulationEngine(scenario: scenario)
        let before = try engine.advance(realDeltaSeconds: 5)
        let after = try engine.advance(realDeltaSeconds: scenario.fixedTimeStepSeconds)
        let sampleTime = (before.simulationTimeSeconds + after.simulationTimeSeconds) * 0.5

        let middle = try TrafficActorPoseSampler.sample(
            scenario: scenario, previous: before, current: after, simulationTimeSeconds: sampleTime
        )
        let repeated = try TrafficActorPoseSampler.sample(
            scenario: scenario, previous: before, current: after, simulationTimeSeconds: sampleTime
        )
        XCTAssertEqual(middle, repeated)

        let priorTrain = try XCTUnwrap(before.trains.first { $0.id == "ai-east-01" })
        let nextTrain = try XCTUnwrap(after.trains.first { $0.id == "ai-east-01" })
        let sampledTrain = try XCTUnwrap(middle.poses.first { $0.sourceID == "ai-east-01" })
        XCTAssertEqual(sampledTrain.positionM, (priorTrain.positionM + nextTrain.positionM) * 0.5, accuracy: 1e-8)
        XCTAssertEqual(middle.simulationTimeSeconds, sampleTime, accuracy: 1e-9)
    }

    func testPoseIdentityAndTrajectorySurviveSaveRestoreAndReplay() throws {
        let scenario = TrafficScenarioLibrary.fictionalParallelCorridor
        var original = try TrafficSimulationEngine(scenario: scenario)
        _ = try original.advance(realDeltaSeconds: 18.375)
        let initialFrame = try TrafficActorPoseSampler.sample(scenario: scenario, snapshot: original.snapshot())

        let encoded = try JSONEncoder().encode(original.stateSnapshot())
        let saved = try JSONDecoder().decode(TrafficSimulationStateSnapshot.self, from: encoded)
        var restored = try TrafficSimulationEngine(scenario: scenario)
        try restored.restoreState(from: saved)
        let restoredFrame = try TrafficActorPoseSampler.sample(scenario: scenario, snapshot: restored.snapshot())
        XCTAssertEqual(initialFrame, restoredFrame)

        let delta = 2.75
        let originalNext = try original.advance(realDeltaSeconds: delta)
        let restoredNext = try restored.advance(realDeltaSeconds: delta)
        XCTAssertEqual(originalNext, restoredNext)
        XCTAssertEqual(
            try TrafficActorPoseSampler.sample(scenario: scenario, snapshot: originalNext),
            try TrafficActorPoseSampler.sample(scenario: scenario, snapshot: restoredNext)
        )
    }

    func testSamplerRejectsSnapshotsFromAnotherScenario() throws {
        let scenario = TrafficScenarioLibrary.fictionalParallelCorridor
        let engine = try TrafficSimulationEngine(scenario: scenario)
        let snapshot = engine.snapshot()
        var incompatible = snapshot
        incompatible = TrafficSnapshot(
            scenarioID: "other-scenario", routeID: snapshot.routeID,
            routeLengthM: snapshot.routeLengthM, totalNetworkLengthM: snapshot.totalNetworkLengthM,
            routePaths: snapshot.routePaths, dataStatus: snapshot.dataStatus,
            simulationTimeSeconds: snapshot.simulationTimeSeconds, fixedTick: snapshot.fixedTick,
            fixedTimeStepSeconds: snapshot.fixedTimeStepSeconds, playerTrain: snapshot.playerTrain,
            trains: snapshot.trains, roadVehicles: snapshot.roadVehicles, passengers: snapshot.passengers
        )
        XCTAssertThrowsError(try TrafficActorPoseSampler.sample(scenario: scenario, snapshot: incompatible))
    }
}
