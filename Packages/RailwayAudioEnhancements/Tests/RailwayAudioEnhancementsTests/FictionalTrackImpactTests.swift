import XCTest
@testable import RailwayAudioEnhancements

final class FictionalTrackImpactTests: XCTestCase {
    func testTurnoutSpansCoverJunctionDepotAndStations() {
        let spans = FictionalTrackImpactSchedule.turnouts
        XCTAssertTrue(spans.contains { $0.role == .branchJunction && $0.line == .main })
        XCTAssertTrue(spans.contains { $0.role == .branchJunction && $0.line == .branch })
        XCTAssertTrue(spans.contains { $0.role == .depotLead && $0.line == .depotSpur })
        XCTAssertTrue(spans.contains { $0.role == .depotLead && $0.line == .main })
        XCTAssertTrue(spans.contains { $0.role == .stationConnection })
        XCTAssertTrue(spans.contains { $0.role == .yardLadder })
        XCTAssertTrue(spans.allSatisfy { $0.lengthM >= 16 && $0.lengthM <= 40 })
        XCTAssertEqual(Set(spans.map(\.id)).count, spans.count)
    }

    func testCrossingATurnoutFiresPointClatterForEachBogieInEitherDirection() {
        let forward = impacts(path: .depotTransfer, direction: .up, from: 0, to: 70, speed: 12, cars: 2)
        let clatters = forward.filter { $0.kind == .pointClatter && $0.sourceID == "depot-lead" }
        let bogies = Set(clatters.map(\.bogieIndex))
        XCTAssertTrue(bogies.isSuperset(of: [0, 1]))
        let first = clatters.filter { $0.bogieIndex == 0 }.map(\.routePositionM).min() ?? 0
        let second = clatters.filter { $0.bogieIndex == 1 }.map(\.routePositionM).min() ?? 0
        XCTAssertGreaterThan(second, first + 10, "The rear bogie reaches the frog later")
        XCTAssertGreaterThan(clatters[0].intensity, 0.4)

        let back = impacts(path: .depotTransfer, direction: .down, from: 1_900, to: 1_990, speed: 10, cars: 1)
        XCTAssertTrue(back.contains { $0.kind == .pointClatter && $0.sourceID == "depot-lead" })

        let stopped = impacts(path: .depotTransfer, direction: .up, from: 0, to: 70, speed: 0, cars: 2)
        XCTAssertTrue(stopped.isEmpty)
    }

    func testInsideTurnoutOnlyWhileABogieIsInTheSpan() {
        var tracker = FictionalTrackImpactTracker(carCount: 1)
        let before = tracker.advance(routePositionM: 0, speedMps: 10, path: .depotTransfer, direction: .up)
        XCTAssertFalse(before.insideTurnout)
        var inside = false
        var outsideAgain = false
        var position = 0.5
        while position < 80 {
            let frame = tracker.advance(routePositionM: position, speedMps: 10, path: .depotTransfer, direction: .up)
            let leadBogie = position - FictionalTrackImpactSchedule.bogieInsetM
            if leadBogie >= 14 && leadBogie < 40 {
                if frame.insideTurnout { inside = true }
            }
            if position > 60 && !frame.insideTurnout { outsideAgain = true }
            position += 0.5
        }
        XCTAssertTrue(inside)
        XCTAssertTrue(outsideAgain)
    }

    func testJointedRailClicksEvery25MetresAndOpenMainlineDoesNot() {
        let branch = impacts(path: .branchShuttle, direction: .up, from: 1_000, to: 1_200, speed: 16, cars: 1)
        let branchJoints = branch.filter { $0.kind == .railJoint && $0.bogieIndex == 0 }
        XCTAssertGreaterThanOrEqual(branchJoints.count, 6)
        XCTAssertLessThanOrEqual(branchJoints.count, 10)
        XCTAssertTrue(branchJoints.allSatisfy { $0.sourceID.contains("branch") })

        let main = impacts(path: .mainline, direction: .up, from: 3_000, to: 3_150, speed: 16, cars: 1)
        XCTAssertTrue(main.filter { $0.kind == .railJoint }.isEmpty, "Open main line is CWR, not a click every 25 m")

        let weld = impacts(path: .mainline, direction: .up, from: 3_100, to: 3_300, speed: 16, cars: 1)
        let weldJoints = weld.filter { $0.kind == .railJoint && $0.bogieIndex == 0 }
        XCTAssertEqual(weldJoints.count, 1)
        XCTAssertEqual(weldJoints.first?.lineChainageM ?? 0, 3_200, accuracy: 0.1)

        XCTAssertTrue(FictionalTrackImpactSchedule.isJointedRail(line: .branch, chainageM: 1_100))
        XCTAssertFalse(FictionalTrackImpactSchedule.isJointedRail(line: .main, chainageM: 3_050))
        XCTAssertTrue(FictionalTrackImpactSchedule.isJointedRail(line: .main, chainageM: 60))
    }

    func testPointClatterRailJointAndBridgeRumbleStayDistinct() {
        let point = FictionalCueCatalog.recipe(.pointClatter, family: .fieldChopper)
        let joint = FictionalCueCatalog.recipe(.railJoint, family: .fieldChopper)
        let bridge = FictionalCueCatalog.recipe(.bridgeRumble, family: .fieldChopper)
        XCTAssertGreaterThan(point.durationSeconds, joint.durationSeconds * 4)
        XCTAssertLessThan(point.fundamentalHertz, joint.fundamentalHertz)
        XCTAssertGreaterThan(point.noiseMix, joint.noiseMix)
        XCTAssertGreaterThan(point.pulseHertz, 0)
        XCTAssertEqual(joint.pulseHertz, 0)
        XCTAssertNotEqual(point.waveform, joint.waveform)
        XCTAssertLessThan(bridge.fundamentalHertz, point.fundamentalHertz)
        XCTAssertGreaterThan(bridge.durationSeconds, point.durationSeconds)
        XCTAssertEqual(point.dataStatus, "PLACEHOLDER")
        XCTAssertEqual(joint.dataStatus, "PLACEHOLDER")
    }

    private func impacts(
        path: FictionalPlayablePath,
        direction: FictionalPathDirection,
        from: Double,
        to: Double,
        speed: Double,
        cars: Int
    ) -> [FictionalTrackImpact] {
        var tracker = FictionalTrackImpactTracker(carCount: cars)
        var output: [FictionalTrackImpact] = []
        var position = from
        let step = 0.25
        while position <= to {
            output += tracker.advance(routePositionM: position, speedMps: speed, path: path, direction: direction).impacts
            position += step
        }
        return output
    }
}
