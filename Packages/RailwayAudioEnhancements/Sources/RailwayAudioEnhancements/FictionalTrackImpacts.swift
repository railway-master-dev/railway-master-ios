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
        var spans: [FictionalTurnoutSpan] = [
            span("depot-throat-main", .main, .depotLead, 18, 42),
            span("depot-lead", .depotSpur, .depotLead, 14, 40),
            span("depot-yard-ladder", .depotSpur, .yardLadder, 1_962, 1_988),
            span("branch-junction-main", .main, .branchJunction, 59_974, 60_000),
            span("branch-junction-branch", .branch, .branchJunction, 0, 28),
            span("zoo-junction", .zoo, .branchJunction, 0, 28),
            span("park-junction", .park, .branchJunction, 0, 28)

        ]
        let loops: [(String, FictionalTrackLine, Double)] = [
            ("S05", .main, 8_226),
            ("S10", .main, 19_161),
            ("S15", .main, 30_677),
            ("S20", .main, 41_806),
            ("S25", .main, 52_935),
            ("B02", .branch, 4_000)
        ]
        for loop in loops {
            spans.append(span("\(loop.0)-entry", loop.1, .stationConnection, loop.2 - 186, loop.2 - 162))
            spans.append(span("\(loop.0)-exit", loop.1, .stationConnection, loop.2 + 148, loop.2 + 174))
        }
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
            let occupied = Set(FictionalTrackImpactSchedule.turnouts(containing: located.line, chainageM: located.chainageM).map(\.id))
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
