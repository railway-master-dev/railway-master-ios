import XCTest
@testable import RailwayAudioEnhancements

final class FictionalTrackImpactTests: XCTestCase {
    func testTurnoutSpansCoverJunctionDepotAndStations() {
        let spans = FictionalTrackImpactSchedule.turnouts
        // batch120: only drawn turnouts are registered. The
        // placeholder junction/depot spans (branchJunction,
        // depotLead and yardLadder roles) are gone — no
        // session world draws a turnout at any of their
        // chainages, so they fired clatter over plain track.
        XCTAssertTrue(spans.allSatisfy { $0.role == .stationConnection })
        let phantomIDs = [
            "depot-throat-main", "depot-lead", "depot-yard-ladder",
            "branch-junction-main", "branch-junction-branch",
            "zoo-junction", "park-junction"
        ]
        for id in phantomIDs {
            XCTAssertFalse(spans.contains { $0.id == id }, "\(id) must stay deleted")
        }
        XCTAssertTrue(spans.filter { $0.line == .depotSpur }.isEmpty)
        XCTAssertTrue(spans.filter { $0.line == .zoo }.isEmpty)
        XCTAssertTrue(spans.filter { $0.line == .park }.isEmpty)
        XCTAssertEqual(Set(spans.filter { $0.line == .branch }.map(\.id)), ["B04-crossover"])
        // batch78: the drawn terminal crossovers are registered
        // with their full S-curve length (toes 560–690 m from
        // each line end); every other span stays a compact
        // points-plus-frog length.
        // batch107: B04-crossover joins the set — the branch
        // terminal's drawn siding divergence, registered at
        // its full 340 m S-curve length on the branch line.
        let crossovers = spans.filter { $0.id.hasSuffix("-crossover") }
        XCTAssertEqual(Set(crossovers.map(\.id)), ["S01-crossover", "S28-crossover", "B04-crossover"])
        XCTAssertTrue(crossovers.contains { $0.line == .main && $0.startM == 560 && $0.endM == 690 })
        XCTAssertTrue(crossovers.contains { $0.line == .main && $0.startM == 59_310 && $0.endM == 59_440 })
        XCTAssertTrue(crossovers.filter { $0.line == .main }.allSatisfy { $0.lengthM == 130 })
        XCTAssertTrue(crossovers.contains { $0.id == "B04-crossover" && $0.line == .branch && $0.role == .stationConnection && $0.startM == 7_460 && $0.endM == 7_800 && $0.lengthM == 340 })
        // batch89: the drawn throat fans at the diagram v4
        // passing stations are registered with their true
        // transition lengths (entry 240 m, exit 300 m — the
        // lateral-transition portions of the 340 m fan
        // easements, see FictionalTrackImpactSchedule).
        // batch120: S15 joins the set — its placeholder loop
        // spans were deleted in the same change, so the set
        // is all 15 fan stations x 2 plus one fan span per
        // terminal, and the length assertions below now
        // cover S15's registration too.
        let fanIDs: Set<String> = [
            "S03-entry", "S03-exit", "S04-entry", "S04-exit",
            "S06-entry", "S06-exit", "S07-entry", "S07-exit",
            "S09-entry", "S09-exit", "S11-entry", "S11-exit",
            "S12-entry", "S12-exit", "S14-entry", "S14-exit",
            "S15-entry", "S15-exit",
            "S17-entry", "S17-exit", "S19-entry", "S19-exit",
            "S22-entry", "S22-exit", "S23-entry", "S23-exit",
            "S24-entry", "S24-exit", "S27-entry", "S27-exit",
            "S01-exit", "S28-entry"
        ]
        let fanSpans = spans.filter { fanIDs.contains($0.id) }
        XCTAssertEqual(fanSpans.count, fanIDs.count)
        XCTAssertTrue(fanSpans.allSatisfy { $0.line == .main && $0.role == .stationConnection })
        XCTAssertTrue(fanSpans.filter { $0.id.hasSuffix("-entry") }.allSatisfy { $0.lengthM == 240 })
        XCTAssertTrue(fanSpans.filter { $0.id.hasSuffix("-exit") }.allSatisfy { $0.lengthM == 300 })
        // Spot-check the derivation: S03's entry fan is the
        // 240 m transition ending 200 m short of its 3,871
        // centre; S01's exit fan starts at its canonical
        // centre 100 + 140; S28's entry fan ends 200 m short
        // of its canonical centre 59,900.
        XCTAssertTrue(fanSpans.contains { $0.id == "S03-entry" && $0.startM == 3_431 && $0.endM == 3_671 })
        XCTAssertTrue(fanSpans.contains { $0.id == "S01-exit" && $0.startM == 240 && $0.endM == 540 })
        XCTAssertTrue(fanSpans.contains { $0.id == "S28-entry" && $0.startM == 59_460 && $0.endM == 59_700 })
        // batch120: S15's spans are the fan derivation at
        // its 30,677 centre — the drawn transitions — not
        // the deleted placeholder pair ([30,491, 30,515] /
        // [30,825, 30,851]).
        XCTAssertTrue(fanSpans.contains { $0.id == "S15-entry" && $0.startM == 30_237 && $0.endM == 30_477 })
        XCTAssertTrue(fanSpans.contains { $0.id == "S15-exit" && $0.startM == 30_817 && $0.endM == 31_117 })
        XCTAssertTrue(spans.filter { !$0.id.hasSuffix("-crossover") && !fanIDs.contains($0.id) }.allSatisfy { $0.lengthM >= 16 && $0.lengthM <= 40 })
        // No two spans on a line overlap: the tracker fires
        // once per span entered, so an overlap (or a nest)
        // would double-fire a bogie at a single turnout.
        for line in [FictionalTrackLine.main, .branch, .depotSpur, .zoo, .park] {
            let sorted = spans.filter { $0.line == line }.sorted { $0.startM < $1.startM }
            for (a, b) in zip(sorted, sorted.dropFirst()) {
                XCTAssertLessThanOrEqual(a.endM, b.startM, "\(a.id) overlaps \(b.id)")
            }
        }
        // batch105: 51 -> 41 after the phantom placeholder
        // loop spans (S05/S10/S20/S25/B02) were deleted.
        // batch107: 41 -> 42 — B04-crossover registers the
        // branch terminal's drawn siding divergence.
        // batch120: 42 -> 35 — the seven phantom junction/
        // depot spans are deleted; S15's placeholder pair is
        // replaced by its two fan spans (count-neutral).
        XCTAssertEqual(spans.count, 35)
        XCTAssertEqual(Set(spans.map(\.id)).count, spans.count)
    }

    func testCrossingATurnoutFiresPointClatterForEachBogieInEitherDirection() {
        // batch120: this test used to run over the depot
        // path's depot-lead span, which is deleted (no
        // turnout is drawn in the depot session world). It
        // now runs over S03's drawn entry fan on the
        // mainline path — same tracker semantics.
        let forward = impacts(path: .mainline, direction: .up, from: 3_400, to: 3_750, speed: 12, cars: 2)
        let clatters = forward.filter { $0.kind == .pointClatter && $0.sourceID == "S03-entry" }
        let bogies = Set(clatters.map(\.bogieIndex))
        XCTAssertTrue(bogies.isSuperset(of: [0, 1]))
        let first = clatters.filter { $0.bogieIndex == 0 }.map(\.routePositionM).min() ?? 0
        let second = clatters.filter { $0.bogieIndex == 1 }.map(\.routePositionM).min() ?? 0
        XCTAssertGreaterThan(second, first + 10, "The rear bogie reaches the frog later")
        XCTAssertGreaterThan(clatters[0].intensity, 0.4)

        let back = impacts(path: .mainline, direction: .down, from: 56_250, to: 56_600, speed: 10, cars: 1)
        XCTAssertTrue(back.contains { $0.kind == .pointClatter && $0.sourceID == "S03-entry" })

        let stopped = impacts(path: .mainline, direction: .up, from: 3_400, to: 3_750, speed: 0, cars: 2)
        XCTAssertTrue(stopped.isEmpty)
    }

    func testInsideTurnoutOnlyWhileABogieIsInTheSpan() {
        // batch120: re-based on S03-entry [3,431, 3,671)
        // after the depot-lead span it used was deleted.
        var tracker = FictionalTrackImpactTracker(carCount: 1)
        let before = tracker.advance(routePositionM: 3_400, speedMps: 10, path: .mainline, direction: .up)
        XCTAssertFalse(before.insideTurnout)
        var inside = false
        var outsideAgain = false
        var position = 3_400.5
        while position < 3_750 {
            let frame = tracker.advance(routePositionM: position, speedMps: 10, path: .mainline, direction: .up)
            let leadBogie = position - FictionalTrackImpactSchedule.bogieInsetM
            if leadBogie >= 3_431 && leadBogie < 3_671 {
                if frame.insideTurnout { inside = true }
            }
            if position > 3_690 && !frame.insideTurnout { outsideAgain = true }
            position += 0.5
        }
        XCTAssertTrue(inside)
        XCTAssertTrue(outsideAgain)
    }

    func testS28CrossoverFiresOnMainlineButNotOnThroughBranch() {
        // batch120: the S28 terminal throat is not drawn in
        // the throughBranch world, so its crossover span is
        // scoped to the paths whose worlds draw it.
        let chainage = 59_375.0
        let onMainline = FictionalTrackImpactSchedule.turnouts(containing: .main, chainageM: chainage, path: .mainline)
        XCTAssertTrue(onMainline.contains { $0.id == "S28-crossover" })
        let onThrough = FictionalTrackImpactSchedule.turnouts(containing: .main, chainageM: chainage, path: .throughBranch)
        XCTAssertFalse(onThrough.contains { $0.id == "S28-crossover" })

        let through = impacts(path: .throughBranch, direction: .up, from: 59_200, to: 59_600, speed: 12, cars: 1)
        XCTAssertFalse(through.contains { $0.kind == .pointClatter && $0.sourceID == "S28-crossover" })
        let main = impacts(path: .mainline, direction: .up, from: 59_200, to: 59_600, speed: 12, cars: 1)
        XCTAssertTrue(main.contains { $0.kind == .pointClatter && $0.sourceID == "S28-crossover" })
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
