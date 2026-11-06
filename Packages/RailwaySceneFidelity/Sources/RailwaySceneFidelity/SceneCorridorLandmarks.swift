import Foundation

/// Fictional wayside beats. These are PLACEHOLDER shapes for the driving view.
/// They are not surveyed bridges, cuttings, earthworks, waterways, or level crossings,
/// and they do not carry official gradient, cant, speed, or interlocking data.
public enum SceneCorridorLandmarkKind: String, Codable, CaseIterable, Hashable, Sendable {
    case riverBridge
    case cutting
    case embankment
    case levelCrossing
}

public struct SceneCorridorLandmark: Codable, Hashable, Sendable, Identifiable {
    public let id: String
    public let kind: SceneCorridorLandmarkKind
    /// Absolute route chainage where the fictional span begins.
    public let startChainageM: Double
    public let endChainageM: Double
    /// Index of the repeating 1.6 km beat. Stable for a given route chainage.
    public let periodIndex: Int

    public var lengthM: Double { endChainageM - startChainageM }

    public func contains(_ chainage: Double, margin: Double = 0) -> Bool {
        guard chainage.isFinite, margin.isFinite else { return false }
        return chainage >= startChainageM - margin && chainage <= endChainageM + margin
    }

    public func overlaps(_ start: Double, _ end: Double, margin: Double = 0) -> Bool {
        guard start.isFinite, end.isFinite, margin.isFinite else { return false }
        let lower = min(start, end) - margin
        let upper = max(start, end) + margin
        return startChainageM < upper && lower < endChainageM
    }
}

/// Deterministic PLACEHOLDER cadence along chainage.
///
/// Each 1,600 m beat places one major structure (bridge, cutting, or embankment,
/// cycling in that order) and one static level crossing. The crossing is scenery
/// only: barriers are drawn raised, and nothing in this schedule stops the train
/// or claims an interlocking. Spans that would run through a platform, including
/// a clearance margin, are omitted rather than punched through the station.
public enum SceneCorridorLandmarkSchedule {
    public static let periodM = 1_600.0
    public static let majorOffsetM = 420.0
    public static let crossingOffsetM = 1_080.0
    public static let crossingLengthM = 16.0
    public static let minimumKeptLengthM = 8.0
    public static let platformClearanceM = 24.0

    public static func majorLengthM(period: Int) -> Double {
        let step = ((period % 5) + 5) % 5
        return 96 + Double(step) * 12
    }

    public static func majorKind(period: Int) -> SceneCorridorLandmarkKind {
        switch ((period % 3) + 3) % 3 {
        case 0: return .riverBridge
        case 1: return .cutting
        default: return .embankment
        }
    }

    /// Landmarks that overlap `[startChainageM, endChainageM]` by at least `minimumKeptLengthM`.
    /// Non-finite or empty ranges return `[]`. The list is sorted and repeatable.
    public static func landmarks(
        from startChainageM: Double,
        to endChainageM: Double,
        avoiding platforms: [ScenePlatformSpecification] = []
    ) -> [SceneCorridorLandmark] {
        guard startChainageM.isFinite, endChainageM.isFinite, endChainageM > startChainageM else { return [] }
        let first = Int(floor(startChainageM / periodM)) - 1
        let last = Int(floor((endChainageM - 1e-6) / periodM)) + 1
        guard first <= last, last - first < 100_000 else { return [] }

        var output: [SceneCorridorLandmark] = []
        for period in first...last {
            let origin = Double(period) * periodM
            let kind = majorKind(period: period)
            if let major = make(
                id: "fictional-\(kind.rawValue)-p\(period)",
                kind: kind,
                start: origin + majorOffsetM,
                end: origin + majorOffsetM + majorLengthM(period: period),
                period: period,
                routeStart: startChainageM,
                routeEnd: endChainageM,
                platforms: platforms
            ) {
                output.append(major)
            }
            if let crossing = make(
                id: "fictional-levelCrossing-p\(period)",
                kind: .levelCrossing,
                start: origin + crossingOffsetM,
                end: origin + crossingOffsetM + crossingLengthM,
                period: period,
                routeStart: startChainageM,
                routeEnd: endChainageM,
                platforms: platforms
            ) {
                output.append(crossing)
            }
        }
        return output.sorted {
            if $0.startChainageM == $1.startChainageM { return $0.id < $1.id }
            return $0.startChainageM < $1.startChainageM
        }
    }

    /// Clearance used when roads, buildings, and trees should not occupy a span.
    public static func urbanClearanceM(for kind: SceneCorridorLandmarkKind) -> Double {
        kind == .levelCrossing ? 2 : 10
    }

    private static func make(
        id: String,
        kind: SceneCorridorLandmarkKind,
        start: Double,
        end: Double,
        period: Int,
        routeStart: Double,
        routeEnd: Double,
        platforms: [ScenePlatformSpecification]
    ) -> SceneCorridorLandmark? {
        guard start.isFinite, end.isFinite, end > start else { return nil }
        let overlap = min(end, routeEnd) - max(start, routeStart)
        guard overlap >= minimumKeptLengthM else { return nil }
        for platform in platforms {
            guard platform.startChainageM.isFinite, platform.endChainageM.isFinite else { continue }
            let lower = min(platform.startChainageM, platform.endChainageM) - platformClearanceM
            let upper = max(platform.startChainageM, platform.endChainageM) + platformClearanceM
            if start < upper && lower < end { return nil }
        }
        return SceneCorridorLandmark(
            id: id,
            kind: kind,
            startChainageM: start,
            endChainageM: end,
            periodIndex: period
        )
    }
}
