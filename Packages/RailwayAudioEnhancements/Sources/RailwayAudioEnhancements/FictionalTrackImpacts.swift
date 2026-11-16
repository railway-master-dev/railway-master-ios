import Foundation

/// PLACEHOLDER wheel-impact map for the fictional 60 + 8 + 2 km network.
///
/// Turnouts are chainage spans (points plus frog), not a scenery beat.
/// Jointed rail uses 25 m, a common Japanese standard-rail length and a public
/// running-sound category, not a copied recording. Open main line is mostly
/// continuous welded rail with rare joints. None of these locations are surveyed.
public enum FictionalTrackLine: String, Equatable, Sendable {
    case main
    case branch
    case depotSpur
    case zoo
    case park
}

public enum FictionalPlayablePath: String, Equatable, Sendable {
    case mainline
    case throughBranch
    case branchShuttle
    case depotTransfer
    case zooLine
    case parkLine
}

public enum FictionalPathDirection: String, Equatable, Sendable {
    case up
    case down
}

public enum FictionalTurnoutRole: String, Equatable, Sendable {
    case branchJunction
    case depotLead
    case stationConnection
    case yardLadder
}

public struct FictionalTurnoutSpan: Equatable, Sendable, Identifiable {
    public var id: String
    public var line: FictionalTrackLine
    public var role: FictionalTurnoutRole
    public var startM: Double
    public var endM: Double

    public var lengthM: Double { endM - startM }

    public func contains(_ chainageM: Double) -> Bool {
        chainageM >= startM && chainageM < endM
    }
}

public enum FictionalTrackImpactKind: String, Equatable, Sendable {
    case pointClatter
    case railJoint
}

public struct FictionalTrackImpact: Equatable, Sendable {
    public var kind: FictionalTrackImpactKind
    public var intensity: Float
    public var bogieIndex: Int
    public var routePositionM: Double
    public var lineChainageM: Double
    public var sourceID: String
}

public struct FictionalTrackImpactFrame: Equatable, Sendable {
    public var impacts: [FictionalTrackImpact]
    public var insideTurnout: Bool
}

public enum FictionalTrackImpactSchedule {
    public static let mainLengthM = 60_000.0
    public static let branchLengthM = 8_000.0
    public static let depotLengthM = 2_000.0
    public static let zooLengthM = 2_500.0
    public static let parkLengthM = 2_000.0
    /// PLACEHOLDER standard-rail length. Not a copied asset.
    public static let jointedSpacingM = 25.0
    /// PLACEHOLDER insulation joint / rare weld on continuous-welded rail.
    public static let cwrSpacingM = 800.0
    public static let stationJointedRadiusM = 400.0
    public static let carLengthM = 19.5
    public static let bogieInsetM = 2.8
    public static let stoppedSpeedMps = 0.35

    /// Station chainages copied from the fictional operations plan so jointed zones sit at stations.
    public static let mainStationChainageM: [Double] = [
        0, 1_839, 3_871, 6_000, 8_226, 10_355, 12_387, 14_613, 16_935, 19_161,
        21_290, 24_194, 26_323, 28_452, 30_677, 32_903, 35_129, 37_355, 39_581,
        41_806, 44_032, 46_258, 48_484, 50_710, 52_935, 55_161, 57_387, 60_000
    ]
    public static let branchStationChainageM: [Double] = [0, 2_000, 4_000, 6_000, 8_000]

    public static let turnouts: [FictionalTurnoutSpan] = {
        // batch120: the seven placeholder junction/depot
        // spans that used to head this list are deleted —
        // depot-throat-main, depot-lead, depot-yard-ladder,
        // branch-junction-main, branch-junction-branch,
        // zoo-junction and park-junction all fired point
        // clatter where no turnout is drawn in the session
        // world that hears them (depot-throat-main sounded
        // inside S01's platforms; the depot session world
        // is a plain single line; no junction geometry is
        // drawn in the branch/zoo/park worlds). The real
        // drawn depot lead on the main line (27,715–27,960)
        // gets its span with the depot-junction work, not
        // here. What remains registered is exactly what is
        // drawn: the terminal crossovers, B04's divergence,
        // and the station throat fans below.
        var spans: [FictionalTurnoutSpan] = [
            // batch78: the drawn terminal crossovers
            // (buildTerminalThroats) — switch toes 560–690 m
            // from each line end, so the S-curve the bogies
            // traverse spans that whole length at both
            // terminals. Until now these were drawn but had
            // no span, so trains crossed them in silence.
            span("S01-crossover", .main, .stationConnection, 560, 690),
            span("S28-crossover", .main, .stationConnection, 59_310, 59_440),
            // batch107: B04's drawn terminal siding
            // divergence (buildTerminalThroats' branch
            // treatment) — both sidings leave the single
            // branch line on one 340 m S-curve that completes
            // at the platform end, 200 m before the line
            // end, so the full S-curve registers as one
            // span: the terminal-crossover equivalent for
            // the branch. Branch-local chainages.
            span("B04-crossover", .branch, .stationConnection, 7_460, 7_800)

        ]
        // batch105: the placeholder loop spans for S05, S10,
        // S20, S25 and B02 are deleted — none of those stations
        // has a drawn fan, siding or point machine (S05's spans
        // sat inside its island-spread ramps, which are plain
        // running track), so point clatter fired where no
        // switch exists. Span count 51 -> 41.
        // batch120: S15's placeholder loop spans are deleted
        // in the same change that registers its true fan
        // transitions below — the replacement is atomic
        // because the old exit span [30,825, 30,851] is
        // nested inside the true convergence [30,817,
        // 31,117] and the old entry span [30,491, 30,515]
        // sits just past the true transition [30,237,
        // 30,477]; keeping either alongside the fan spans
        // would double-fire every bogie (and break the test
        // suite's no-overlap invariant). The placeholder
        // pair fired up to 254 m away from the drawn switch.
        // batch89: the drawn throat fans at the diagram v4
        // passing stations (the scene builder's
        // throatFanSpecs set: PassingWaitPlanner's 15 plus
        // the two terminals). Each fan is a 340 m easement
        // on a throat of the canonical 200 m platform span
        // (centre C, half 100): the "in" fan leaves the
        // running line at C - 440 and reaches the loop line
        // 240 m along; the "out" fan holds the loop line
        // for 40 m and converges over the last 300 m
        // (throatFanLateral). The registered span is that
        // transition — the chainage where a bogie is
        // physically on the switch — not the parallel tail,
        // where the loop is plain separate track. batch120
        // adds S15 to this derivation (its placeholder loop
        // spans are deleted above in the same change), so
        // all 15 fan stations now register identically.
        // The terminals fan on one side only: S01's in-fan
        // and S28's out-fan fall outside the line ends and
        // are never drawn, so each terminal gets the single
        // fan span its geometry allows, keyed on the
        // canonical centres (100 / 59,900 — the head-end
        // platforms sit fully inside the line, so there the
        // centre is not the station chainage).
        let fans: [(String, Double)] = [
            ("S03", 3_871),
            ("S04", 6_000),
            ("S06", 10_355),
            ("S07", 12_387),
            ("S09", 16_935),
            ("S11", 21_290),
            ("S12", 24_194),
            ("S14", 28_452),
            ("S15", 30_677),
            ("S17", 35_129),
            ("S19", 39_581),
            ("S22", 46_258),
            ("S23", 48_484),
            ("S24", 50_710),
            ("S27", 57_387)
        ]
        for fan in fans {
            spans.append(span("\(fan.0)-entry", .main, .stationConnection, fan.1 - 440, fan.1 - 200))
            spans.append(span("\(fan.0)-exit", .main, .stationConnection, fan.1 + 140, fan.1 + 440))
        }
        spans.append(span("S01-exit", .main, .stationConnection, 240, 540))
        spans.append(span("S28-entry", .main, .stationConnection, 59_460, 59_700))
        return spans
    }()

    public static func pathLengthM(_ path: FictionalPlayablePath) -> Double {
        switch path {
        case .mainline: mainLengthM
        case .throughBranch: mainLengthM + branchLengthM
        case .branchShuttle: branchLengthM
        case .depotTransfer: depotLengthM
        case .zooLine: zooLengthM
        case .parkLine: parkLengthM
        }
    }

    public static func locate(path: FictionalPlayablePath, direction: FictionalPathDirection, routePositionM: Double) -> (line: FictionalTrackLine, chainageM: Double)? {
        guard routePositionM.isFinite else { return nil }
        let length = pathLengthM(path)
        let clamped = min(max(routePositionM, 0), length)
        let fromUpStart = direction == .up ? clamped : length - clamped
        switch path {
        case .mainline:
            return (.main, fromUpStart)
        case .throughBranch:
            if fromUpStart <= mainLengthM { return (.main, fromUpStart) }
            return (.branch, fromUpStart - mainLengthM)
        case .branchShuttle:
            return (.branch, fromUpStart)
        case .depotTransfer:
            return (.depotSpur, fromUpStart)
        case .zooLine:
            return (.zoo, fromUpStart)
        case .parkLine:
            return (.park, fromUpStart)
        }
    }

    public static func isJointedRail(line: FictionalTrackLine, chainageM: Double) -> Bool {
        switch line {
        case .branch, .depotSpur, .zoo, .park:
            // Short lines run on 25 m standard-length (jointed) rail
            // end to end, so every bogie clicks every 25 m.
            return true
        case .main:
            return mainStationChainageM.contains { abs($0 - chainageM) <= stationJointedRadiusM }
        }
    }

    public static func isRailJoint(line: FictionalTrackLine, chainageM: Double) -> Bool {
        guard chainageM >= -0.01 else { return false }
        let spacing = isJointedRail(line: line, chainageM: chainageM) ? jointedSpacingM : cwrSpacingM
        let nearest = (chainageM / spacing).rounded() * spacing
        return abs(nearest - chainageM) < 0.05 && nearest >= 0
    }

    public static func turnouts(containing line: FictionalTrackLine, chainageM: Double) -> [FictionalTurnoutSpan] {
        turnouts.filter { $0.line == line && $0.contains(chainageM) }
    }

    /// Path-aware lookup used by the tracker. batch120:
    /// S28-crossover is drawn only in the mainline world —
    /// buildTerminalThroats skips the S28 throat when the
    /// throughBranch world is built (the station touches
    /// neither end of that route), so the span must not
    /// fire on the throughBranch path even though the
    /// chainage is traversed there.
    public static func turnouts(containing line: FictionalTrackLine, chainageM: Double, path: FictionalPlayablePath) -> [FictionalTurnoutSpan] {
        turnouts(containing: line, chainageM: chainageM).filter { span in
            !(path == .throughBranch && span.id == "S28-crossover")
        }
    }

    public static func bogieOffsets(carCount: Int, carLengthM: Double = carLengthM) -> [Double] {
        let cars = min(16, max(1, carCount))
        let length = max(8, carLengthM)
        let inset = min(bogieInsetM, length * 0.35)
        var offsets: [Double] = []
        for car in 0..<cars {
            let origin = Double(car) * length
            offsets.append(origin + inset)
            offsets.append(origin + length - inset)
        }
        return offsets
    }

    private static func span(
        _ id: String,
        _ line: FictionalTrackLine,
        _ role: FictionalTurnoutRole,
        _ start: Double,
        _ end: Double
    ) -> FictionalTurnoutSpan {
        FictionalTurnoutSpan(id: id, line: line, role: role, startM: start, endM: end)
    }
}

public struct FictionalTrackImpactTracker: Equatable, Sendable {
    public var carCount: Int
    public var carLengthM: Double
    private var previous: [BogieMemory?]

    public init(carCount: Int, carLengthM: Double = FictionalTrackImpactSchedule.carLengthM) {
        self.carCount = carCount
        self.carLengthM = carLengthM
        previous = []
    }

    public mutating func reset() {
        previous = []
    }

    public mutating func advance(
        routePositionM: Double,
        speedMps: Double,
        path: FictionalPlayablePath,
        direction: FictionalPathDirection
    ) -> FictionalTrackImpactFrame {
        let offsets = FictionalTrackImpactSchedule.bogieOffsets(carCount: carCount, carLengthM: carLengthM)
        if previous.count != offsets.count { previous = Array(repeating: nil, count: offsets.count) }
        let speed = speedMps.isFinite ? max(0, speedMps) : 0
        let audible = speed >= FictionalTrackImpactSchedule.stoppedSpeedMps
        let intensity = min(1, Float(speed / 22))
        var impacts: [FictionalTrackImpact] = []
        var inside = false
        for index in offsets.indices {
            let bogieRoute = routePositionM - offsets[index]
            guard let located = FictionalTrackImpactSchedule.locate(path: path, direction: direction, routePositionM: bogieRoute) else { continue }
            let occupied = Set(FictionalTrackImpactSchedule.turnouts(containing: located.line, chainageM: located.chainageM, path: path).map(\.id))
            if !occupied.isEmpty { inside = true }
            if let prior = previous[index] {
                let seek = abs(bogieRoute - prior.routePositionM) > 40
                if audible && !seek {
                    if prior.line == located.line {
                        let entered = occupied.subtracting(prior.insideTurnoutIDs)
                        for id in entered.sorted() {
                            impacts.append(FictionalTrackImpact(
                                kind: .pointClatter,
                                intensity: intensity,
                                bogieIndex: index,
                                routePositionM: routePositionM,
                                lineChainageM: located.chainageM,
                                sourceID: id
                            ))
                        }
                        impacts += joints(
                            from: prior.chainageM,
                            to: located.chainageM,
                            line: located.line,
                            bogie: index,
                            routePositionM: routePositionM,
                            intensity: intensity
                        )
                    } else if !occupied.isEmpty {
                        for id in occupied.sorted() {
                            impacts.append(FictionalTrackImpact(
                                kind: .pointClatter,
                                intensity: intensity,
                                bogieIndex: index,
                                routePositionM: routePositionM,
                                lineChainageM: located.chainageM,
                                sourceID: id
                            ))
                        }
                    }
                }
            }
            previous[index] = BogieMemory(
                line: located.line,
                chainageM: located.chainageM,
                routePositionM: bogieRoute,
                insideTurnoutIDs: occupied
            )
        }
        return FictionalTrackImpactFrame(impacts: impacts, insideTurnout: inside)
    }

    private func joints(
        from start: Double,
        to end: Double,
        line: FictionalTrackLine,
        bogie: Int,
        routePositionM: Double,
        intensity: Float
    ) -> [FictionalTrackImpact] {
        guard start != end else { return [] }
        let lower = min(start, end)
        let upper = max(start, end)
        var marks: [Double] = []
        func collect(_ spacing: Double) {
            let first = Int((lower / spacing).rounded(.up))
            let last = Int((upper / spacing).rounded(.down))
            guard first <= last else { return }
            for step in first...last {
                let mark = Double(step) * spacing
                if mark > lower + 0.001 && mark <= upper + 0.001 {
                    marks.append(mark)
                }
            }
        }
        collect(FictionalTrackImpactSchedule.jointedSpacingM)
        collect(FictionalTrackImpactSchedule.cwrSpacingM)
        var seen = Set<Int>()
        var impacts: [FictionalTrackImpact] = []
        for mark in marks where seen.insert(Int((mark * 10).rounded())).inserted {
            guard FictionalTrackImpactSchedule.isRailJoint(line: line, chainageM: mark) else { continue }
            impacts.append(FictionalTrackImpact(
                kind: .railJoint,
                intensity: intensity,
                bogieIndex: bogie,
                routePositionM: routePositionM,
                lineChainageM: mark,
                sourceID: "joint-\(line.rawValue)-\(Int(mark.rounded()))"
            ))
        }
        return impacts
    }
}

private struct BogieMemory: Equatable {
    var line: FictionalTrackLine
    var chainageM: Double
    var routePositionM: Double
    var insideTurnoutIDs: Set<String>
}
