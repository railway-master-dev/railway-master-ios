import Foundation

enum RegionalRouteVariant: String, CaseIterable, Identifiable, Sendable {
    case mainline
    case throughBranch
    case branchShuttle
    case depotTransfer
    case zooLine
    case parkLine

    var id: String { rawValue }
    var title: String {
        switch self {
        case .mainline: return "本線 全線"
        case .throughBranch: return "本線・支線直通"
        case .branchShuttle: return "支線区間"
        case .depotTransfer: return "車庫引込線"
        case .zooLine: return "動物園線"
        case .parkLine: return "テーマパーク線"
        }
    }

    var distanceDescription: String {
        switch self {
        case .mainline: return "60 km"
        case .throughBranch: return "68 km"
        case .branchShuttle: return "8 km"
        case .depotTransfer: return "2 km"
        case .zooLine: return "2.5 km"
        case .parkLine: return "2 km"
        }
    }
}

enum RegionalTravelDirection: String, CaseIterable, Identifiable, Sendable {
    case up
    case down

    var id: String { rawValue }
    var title: String { self == .up ? "上り" : "下り" }
}

struct RegionalRouteStop: Identifiable, Equatable, Sendable {
    let stationID: String
    let name: String
    let positionM: Double
    let trackID: String
    var id: String { stationID }
}

struct RegionalPlayableRoute: Sendable {
    let routeID: String
    let variant: RegionalRouteVariant
    let category: ServiceCategory
    let direction: RegionalTravelDirection
    let profile: RailwayRouteProfile
    let stops: [RegionalRouteStop]
    let geometrySeed: UInt64
    let dataStatusLabel: String

    var firstStop: RegionalRouteStop? { stops.first }
    var finalStop: RegionalRouteStop? { stops.last }
}

enum RegionalRouteFactoryError: Error, Equatable {
    case missingService
    case invalidStationReference
    case invalidStopSequence
    case invalidDistance
}

/// Converts the validated, fictional 60 + 8 + 2 km operations plan into driveable linear paths.
/// The line geometry generated here is explicitly placeholder gameplay data, not survey data.
private struct GeneratedAlignmentRegion {
    enum Kind: Equatable { case mainline, branch, depot, zoo, park }
    let kind: Kind
    let offsetM: Double
    let lengthM: Double
    let tangentRange: ClosedRange<Double>
    let transitionRange: ClosedRange<Double>
    let circularRange: ClosedRange<Double>
    let radiusRange: ClosedRange<Double>
    let cantRange: ClosedRange<Double>
    let leadingMarginM: Double
    let trailingMarginM: Double
    let seedSalt: UInt64
}

private struct GeneratedCurveRun {
    let transition: RouteCurveTransition
    let radiusM: Double
    let direction: Int
    let cantMm: Double
}

/// Alignment zone along the mainline (up-direction chainage), sharing
/// the district bands the scenery uses (urban core 0-4.2 km, fringe
/// 4.2-6 km and 22.6-25.8 km, coast 38.5-40.5 / 43.6-48.6 / 53-60 km).
/// Radii follow the BVE measurements (Toyoko R200-2000, Tojo R300-10000):
/// tight in the city and broad across the rural stretches, so the curve
/// is readable in the forward view instead of everything looking
/// straight. Cant stays 55-105 mm everywhere, and since the 2026-11-11
/// recalibration the curve limit credits that fitted cant plus 55 mm
/// of cant deficiency (passenger practice).
private enum MainlineAlignmentZone {
    case urbanCore
    case fringe
    case suburban
    case rural
    case coastal

    var radiusRange: ClosedRange<Double> {
        switch self {
        case .urbanCore: return 300...700
        case .fringe: return 400...900
        case .suburban: return 550...1_400
        case .rural: return 1_600...4_000
        case .coastal: return 800...2_000
        }
    }

    var tangentRange: ClosedRange<Double> {
        switch self {
        case .urbanCore: return 200...650
        case .fringe: return 350...1_000
        case .suburban: return 550...1_800
        case .rural: return 1_200...3_000
        case .coastal: return 800...2_000
        }
    }

    /// Line speed cap for the zone (2026-11-11, user request: a big
    /// private railway profile — the city belt winds at 80 km/h at
    /// most, the hub fringe allows 90, and the limit is only released
    /// once the line is clear of the city). Rural and coastal zones
    /// sit at the 110 base-table maximum, so the cap is a no-op
    /// there; the curve limit still binds on their tighter radii.
    var speedCapKmh: Double {
        switch self {
        case .urbanCore: return 80
        case .fringe: return 90
        case .suburban: return 80
        case .rural: return 110
        case .coastal: return 110
        }
    }

    /// Transitions stay at 260 m or longer: the integration tests cap
    /// the cant step at 4.2 mm per 10 m sample and the curvature step
    /// at 0.0002, and 105 mm cant over 260 m is 4.04 mm per step
    /// (R300 over 260 m is 0.00013 per step).
    var transitionRange: ClosedRange<Double> {
        switch self {
        case .urbanCore: return 260...350
        case .fringe: return 260...400
        case .suburban: return 300...500
        case .rural: return 400...600
        case .coastal: return 300...500
        }
    }

    var circularRange: ClosedRange<Double> {
        switch self {
        case .urbanCore: return 220...700
        case .fringe: return 300...900
        case .suburban: return 550...1_800
        case .rural: return 1_200...3_000
        case .coastal: return 600...1_800
        }
    }

}

private func mainlineZone(at localM: Double) -> MainlineAlignmentZone {
    if localM < 4_200 { return .urbanCore }
    if localM < 6_000 { return .fringe }
    if localM < 22_600 { return .suburban }
    if localM < 25_800 { return .fringe }
    if localM < 38_500 { return .rural }
    if localM < 40_500 { return .coastal }
    if localM < 43_600 { return .suburban }
    if localM < 48_600 { return .coastal }
    if localM < 53_000 { return .rural }
    return .coastal
}

/// Canonical mainline grade table (up frame, permille). Everything
/// not listed is level. Ruling grade 10 permille on the tunnel-1
/// climb; ordinary grades <= 5 permille; both tunnels at +2 permille
/// drainage grade; both termini at about 0 m. This replaces the old
/// zone-amplitude sine (urban core amplitude 25 permille, no level
/// section anywhere, 81 m of elevation range) with a localised,
/// realistic profile.
private let mainlineGradeSpans: [(startM: Double, endM: Double, permille: Double)] = [
    (2_000, 4_200, -5),     // fringe dip (cutting under the viaduct belt)
    (4_200, 6_500, 5),      //   back to datum
    (12_500, 15_500, 10),   // hill climb to tunnel 1 (ruling grade)
    (15_500, 17_800, 3),    //   climb eases
    (17_800, 19_250, 2),    // tunnel 1
    (19_250, 25_800, -5),   // descent to Touou-Chihara (S12)
    (25_800, 32_000, 3),    // rural rolling
    (32_000, 38_500, -3),   //
    (38_500, 40_500, -2),   // settle to sea level, coastal window 1
    (40_500, 42_100, 8),    // climb to tunnel 2
    (42_100, 43_600, 2),    // tunnel 2
    (43_600, 48_600, -3.5), // cliff descent, coastal window 2
    (53_000, 56_500, 1.5),  // coastal window 3, gentle
    (56_500, 60_000, -1.5)  //   back to about 0 at Kamogawa (S28)
]

/// The grade table's raw value at a chainage: the containing span's
/// permille, or 0 (level) outside every span.
private func mainlineTableGrade(at localM: Double) -> Double {
    for span in mainlineGradeSpans where localM >= span.startM && localM < span.endM {
        return span.permille
    }
    return 0
}

/// Mainline gradient for one 250 m section, sampled at its midpoint
/// `localM` (the same point the old sine sampled). The value is
/// built from the table (see `mainlineGradeSpans`), smoothed by a
/// boundary blend, and flattened by the station pad:
/// - Boundary blend: within +/-375 m of a span boundary, linearly
///   blend from the previous span's value to the next. The blend
///   must span at least two sections on each side: sections are
///   sampled at their midpoints, so a +/-125 m blend would land
///   exactly on its own endpoints (t = 0 and t = 1) at the two
///   neighbouring midpoints and smooth nothing — the full span
///   step (up to 10 permille) would survive between adjacent
///   sections. At +/-375 m the per-section step stays at about
///   3.3 permille even for the ruling-grade step, which is also
///   what keeps the car-body pitch tracking the local gradient
///   (the pitch test's 0.002 rad tolerance).
/// - Station pad: a section whose midpoint lies within +/-200 m
///   of a station chainage (the 200 m platform span plus a margin
///   that keeps every platform section level for any station
///   position) is level — real railways hold station throats at
///   or near level, and every stop, dwell and restart then
///   happens on the level. Outside the pad the grade fades back
///   in linearly over the next 400 m, for the same
///   midpoint-sampling reason as the boundary blend: a hard
///   pad edge inside the 10 permille climb would otherwise step
///   0 -> 10 permille between adjacent sections (the pitch test
///   measures that step at about 0.0025 rad against a 0.002
///   tolerance). The fade is kept as short as the step limit
///   allows — a longer fade flattens so much of the line (a
///   station every ~2.2 km) that the elevation range collapses
///   below the pinned "line is not flat" bounds. Station
///   positions come from the `stations` parameter the factory
///   already passes in (up frame); no second copy of the
///   chainage list is hardcoded here.
private func mainlineGradePermille(at localM: Double, stations: [RegionalRouteStop]) -> Double {
    var boundaries: [Double] = []
    for span in mainlineGradeSpans {
        if !boundaries.contains(span.startM) { boundaries.append(span.startM) }
        if !boundaries.contains(span.endM) { boundaries.append(span.endM) }
    }
    var grade = mainlineTableGrade(at: localM)
    for boundary in boundaries where abs(localM - boundary) < 375 {
        let previous = mainlineTableGrade(at: boundary - 1)
        let next = mainlineTableGrade(at: boundary + 1)
        let t = (localM - (boundary - 375)) / 750
        grade = previous + (next - previous) * t
        break
    }
    var nearestStationDistance = Double.greatestFiniteMagnitude
    for station in stations {
        nearestStationDistance = min(nearestStationDistance, abs(localM - station.positionM))
    }
    if nearestStationDistance <= 200 {
        return 0
    }
    if nearestStationDistance < 600 {
        return grade * (nearestStationDistance - 200) / 400
    }
    return grade
}

enum RegionalRouteFactory {
    static let defaultGeometrySeed: UInt64 = 0x6B6F_6E79_756E_2026

    static func make(
        plan: FictionalOperationsPlan,
        variant: RegionalRouteVariant,
        category: ServiceCategory = .local,
        direction: RegionalTravelDirection = .up,
        geometrySeed: UInt64 = 0x6B6F_6E79_756E_2026
    ) throws -> RegionalPlayableRoute {
        guard let service = plan.services.first(where: { $0.category == category }) else {
            throw RegionalRouteFactoryError.missingService
        }

        let mainlineLengthM = plan.network.mainlineLengthKm * 1_000
        let branchLengthM = plan.network.branchLengthKm * 1_000
        let depotLengthM = plan.network.depotSpurLengthKm * 1_000
        // Zoo line (quality42): a short 2.5 km shuttle branching at 大野
        // (S24, mainline chainage 50.71 km). Its length lives here, not in
        // the operations plan, so the canonical 60+8+2 network is untouched.
        let zooLengthM = 2_500.0
        let zooJunctionStationID = "S24"
        // Theme park line (quality41): a short 2.0 km shuttle branching
        // at 館川 (S26, mainline chainage 55.161 km).
        let parkLengthM = 2_000.0
        let parkJunctionStationID = "S26"
        let stationByID = Dictionary(plan.stations.map { ($0.stationId, $0) }, uniquingKeysWith: { first, _ in first })
        guard let mainStart = stationByID[plan.network.mainlineTermini.first ?? ""],
              let mainEnd = stationByID[plan.network.mainlineTermini.last ?? ""],
              let branchEnd = stationByID[plan.network.branchTerminalStationID],
              mainStart.lineId == plan.network.mainlineID,
              abs(mainStart.chainageKm) < 0.001,
              abs(mainEnd.chainageKm * 1_000 - mainlineLengthM) < 1,
              abs(branchEnd.chainageKm * 1_000 - branchLengthM) < 1 else {
            throw RegionalRouteFactoryError.invalidStationReference
        }

        let orderedIDs: [String]
        let routeLengthM: Double
        let title: String
        switch variant {
        case .mainline:
            let mainlineIDs = service.stopStationIDs.filter { stationByID[$0]?.lineId == plan.network.mainlineID }
            orderedIDs = mainlineIDs
            routeLengthM = mainlineLengthM
            title = "\(plan.network.name) 本線 \(category.displayName)"
        case .throughBranch:
            orderedIDs = service.stopStationIDs
            routeLengthM = mainlineLengthM + branchLengthM
            title = "\(plan.network.name) \(category.displayName)直通"
        case .branchShuttle:
            let branchStops = plan.stations
                .filter { $0.lineId == plan.network.branchID }
                .sorted { $0.chainageKm < $1.chainageKm }
                .map(\.stationId)
                .filter { service.stopStationIDs.contains($0) }
            orderedIDs = [plan.network.branchJunctionStationID] + branchStops
            routeLengthM = branchLengthM
            title = "\(plan.network.name) 支線 \(category.displayName)"
        case .depotTransfer:
            orderedIDs = [plan.network.depotStationID, "DEPOT_END"]
            routeLengthM = depotLengthM
            title = "\(plan.network.name) 車庫入出庫"
        case .zooLine:
            orderedIDs = [zooJunctionStationID, "ZOO_END"]
            routeLengthM = zooLengthM
            title = "\(plan.network.name) 動物園線 \(category.displayName)"
        case .parkLine:
            orderedIDs = [parkJunctionStationID, "PARK_END"]
            routeLengthM = parkLengthM
            title = "\(plan.network.name) テーマパーク線 \(category.displayName)"
        }

        let pathIDs = direction == .up ? orderedIDs : Array(orderedIDs.reversed())
        guard pathIDs.count >= 2 else { throw RegionalRouteFactoryError.invalidStopSequence }
        var stops: [RegionalRouteStop] = []
        for stationID in pathIDs {
            let rawPosition: Double
            let station: FictionalOperationsPlan.Station?
            if stationID == "DEPOT_END" {
                guard variant == .depotTransfer else { throw RegionalRouteFactoryError.invalidStationReference }
                rawPosition = depotLengthM
                station = nil
            } else if stationID == "ZOO_END" {
                guard variant == .zooLine else { throw RegionalRouteFactoryError.invalidStationReference }
                rawPosition = zooLengthM
                station = nil
            } else if stationID == "PARK_END" {
                guard variant == .parkLine else { throw RegionalRouteFactoryError.invalidStationReference }
                rawPosition = parkLengthM
                station = nil
            } else {
                guard let item = stationByID[stationID] else { throw RegionalRouteFactoryError.invalidStationReference }
                station = item
                switch variant {
                case .mainline:
                    guard item.lineId == plan.network.mainlineID else { throw RegionalRouteFactoryError.invalidStationReference }
                    rawPosition = item.chainageKm * 1_000
                case .throughBranch:
                    rawPosition = item.lineId == plan.network.mainlineID
                        ? item.chainageKm * 1_000
                        : mainlineLengthM + item.chainageKm * 1_000
                case .branchShuttle:
                    rawPosition = item.lineId == plan.network.mainlineID
                        ? 0
                        : item.chainageKm * 1_000
                case .depotTransfer:
                    rawPosition = 0
                case .zooLine:
                    rawPosition = 0
                case .parkLine:
                    rawPosition = 0
                }
            }
            let position = direction == .up ? rawPosition : routeLengthM - rawPosition
            let lineID = station?.lineId ?? (stationID == "ZOO_END" ? "ZOO" : (stationID == "PARK_END" ? "PARK" : plan.network.depotSpurID))
            let trackID = trackIdentifier(lineID: lineID, direction: direction)
            let name = station?.name ?? (stationID == "ZOO_END" ? "動物園" : (stationID == "PARK_END" ? "テーマパーク" : "東央車両基地（架空）"))
            if stops.last.map({ position <= $0.positionM }) == true { throw RegionalRouteFactoryError.invalidStopSequence }
            stops.append(RegionalRouteStop(stationID: stationID, name: name, positionM: position, trackID: trackID))
        }
        guard abs((stops.first?.positionM ?? -1)) < 0.001,
              abs((stops.last?.positionM ?? -1) - routeLengthM) < 0.001 else {
            throw RegionalRouteFactoryError.invalidStopSequence
        }

        // Section generation judges station proximity in the up-direction
        // layout; the reversal for the down direction happens afterwards.
        // Passing already-reversed stops would skew the near-station speed cap.
        let sectionStations = direction == .up
            ? stops
            : stops.map { RegionalRouteStop(stationID: $0.stationID, name: $0.name, positionM: routeLengthM - $0.positionM, trackID: $0.trackID) }
        let sections = makePlaceholderSections(
            lengthM: routeLengthM,
            direction: direction,
            variant: variant,
            stations: sectionStations,
            mainlineLengthM: mainlineLengthM,
            branchLengthM: branchLengthM,
            depotLengthM: depotLengthM,
            geometrySeed: geometrySeed
        )
        let profile = RailwayRouteProfile(
            lineName: title,
            departureStation: stops[0].name,
            arrivalStation: stops[stops.count - 1].name,
            distanceM: routeLengthM,
            stopMarkerM: routeLengthM,
            sections: sections,
            trackGaugeMm: 1_067,
            dataStatus: .placeholder,
            dataProvenance: [RouteDataProvenance(
                field: "route-geometry-and-infrastructure",
                status: .placeholder,
                sourceName: "FictionalOperationsPlan.json + deterministic gameplay generator",
                methodOrBasis: "60 km本線・8 km支線・2 km車庫線の構成と駅キロ程のみを架空正本から使用。同じgeometrySeedなら同じ線形を再現し、seedを変えると線形が変わるゲーム用PLACEHOLDER生成値。実測/公式諸元ではありません。",
                confidence: "実在鉄道情報との対応なし",
                licenseNote: "プロジェクト内で独自生成した架空データ。第三者素材を含まない。"
            )]
        )
        let routeID = "fictional-\(variant.rawValue)-\(category.rawValue)-\(direction.rawValue)"
        return RegionalPlayableRoute(
            routeID: routeID,
            variant: variant,
            category: category,
            direction: direction,
            profile: profile,
            stops: stops,
            geometrySeed: geometrySeed,
            dataStatusLabel: "PLACEHOLDER · 架空ゲーム路線"
        )
    }

    private static func trackIdentifier(lineID: String, direction: RegionalTravelDirection) -> String {
        if lineID == "BRANCH" { return direction == .up ? "branch-up" : "branch-down" }
        if lineID == "DEPOT_SPUR" { return direction == .up ? "depot-in" : "depot-out" }
        if lineID == "ZOO" { return direction == .up ? "zoo-up" : "zoo-down" }
        if lineID == "PARK" { return direction == .up ? "park-up" : "park-down" }
        return direction == .up ? "main-up" : "main-down"
    }

    private static func makePlaceholderSections(
        lengthM: Double,
        direction: RegionalTravelDirection,
        variant: RegionalRouteVariant,
        stations: [RegionalRouteStop],
        mainlineLengthM: Double,
        branchLengthM: Double,
        depotLengthM: Double,
        geometrySeed: UInt64
    ) -> [RouteSection] {
        // Curves are generated separately for each canonical line so the 60 km mainline
        // and 8 km branch are identical whether run alone or as one through service.
        func region(_ kind: GeneratedAlignmentRegion.Kind, offsetM: Double, lengthM: Double) -> GeneratedAlignmentRegion {
            switch kind {
            case .mainline:
                // The ranges below are the suburban default. Mainline
                // curves actually take their shape from
                // MainlineAlignmentZone at the curve (see curveRuns),
                // so the city gets R300-800 and the rural stretches
                // R1600-4000 instead of one flat 900-1850 band.
                return GeneratedAlignmentRegion(kind: kind, offsetM: offsetM, lengthM: lengthM,
                    tangentRange: 650...2_450, transitionRange: 300...500, circularRange: 650...2_250,
                    radiusRange: 900...1_850, cantRange: 55...105,
                    leadingMarginM: 650, trailingMarginM: 450, seedSalt: 0x9E37_79B9_7F4A_7C15)
            case .branch:
                return GeneratedAlignmentRegion(kind: kind, offsetM: offsetM, lengthM: lengthM,
                    tangentRange: 300...850, transitionRange: 130...260, circularRange: 400...1_050,
                    radiusRange: 450...900, cantRange: 45...90,
                    leadingMarginM: 250, trailingMarginM: 250, seedSalt: 0xD1B5_4A32_D192_ED03)
            case .depot:
                return GeneratedAlignmentRegion(kind: kind, offsetM: offsetM, lengthM: lengthM,
                    tangentRange: 160...360, transitionRange: 90...150, circularRange: 220...420,
                    radiusRange: 450...650, cantRange: 35...70,
                    leadingMarginM: 100, trailingMarginM: 100, seedSalt: 0x94D0_49BB_1331_11EB)
            case .zoo:
                // batch31 (2026-11-14, user direction): the zoo
                // shuttle weaves between the enclosures — it is
                // NOT a straight line. The old parameters put
                // the whole 450-1,900 m enclosure stretch on
                // one 520-1,150 m tangent, so the line read as
                // a ruler through empty grass. Short tangents,
                // R300-560 curves and alternating directions
                // (the generator flips side with p=0.76) now
                // give about four S-curves over the 2.5 km;
                // the 30 km/h enclosure-stretch cap keeps the
                // tight radii legal (curve limit at R300 with
                // 60 mm cant is ~58 km/h).
                return GeneratedAlignmentRegion(kind: kind, offsetM: offsetM, lengthM: lengthM,
                    tangentRange: 130...340, transitionRange: 60...120, circularRange: 140...300,
                    radiusRange: 300...560, cantRange: 30...60,
                    leadingMarginM: 120, trailingMarginM: 180, seedSalt: 0x5A4F_4F4C_494E_4531)
            case .park:
                return GeneratedAlignmentRegion(kind: kind, offsetM: offsetM, lengthM: lengthM,
                    tangentRange: 480...1_050, transitionRange: 120...220, circularRange: 450...850,
                    radiusRange: 800...1_600, cantRange: 40...80,
                    leadingMarginM: 200, trailingMarginM: 300, seedSalt: 0x5041_524B_4C49_4E45)
            }
        }

        let regions: [GeneratedAlignmentRegion]
        switch variant {
        case .mainline:
            regions = [region(.mainline, offsetM: 0, lengthM: mainlineLengthM)]
        case .throughBranch:
            regions = [
                region(.mainline, offsetM: 0, lengthM: mainlineLengthM),
                region(.branch, offsetM: mainlineLengthM, lengthM: branchLengthM)
            ]
        case .branchShuttle:
            regions = [region(.branch, offsetM: 0, lengthM: branchLengthM)]
        case .depotTransfer:
            regions = [region(.depot, offsetM: 0, lengthM: depotLengthM)]
        case .zooLine:
            regions = [region(.zoo, offsetM: 0, lengthM: lengthM)]
        case .parkLine:
            regions = [region(.park, offsetM: 0, lengthM: lengthM)]
        }

        func curveRuns(in region: GeneratedAlignmentRegion) -> [GeneratedCurveRun] {
            var rng = SplitMix64(seed: geometrySeed ^ region.seedSalt)
            var cursor = region.offsetM + region.leadingMarginM
            var previousDirection = 0
            let regionEnd = region.offsetM + region.lengthM - region.trailingMarginM
            var runs: [GeneratedCurveRun] = []
            // batch31/32 (2026-11-14, user: every station
            // looked straight, then "add stations on strong
            // curves too — give them character"): stations
            // are pinned onto curves of graded severity, so
            // their platforms — built from the route
            // samples — curve with the track.
            // Mainline: S05 Ishigamiike R950 (gentle),
            // S14 Tsudaike R1100 (gentle), S21 Katsunuma
            // R800 (medium, coastal), S25 Mihama R650
            // (strong, coastal), S16 Misagi R550 (strong —
            // the platform bends ~11 m end to end).
            // Branch: B02 Okitsu R450 (strong, 170 m
            // platform). The spans clear the tunnels
            // (17.8-19.25k, 42.1-43.6k), the depot fan
            // (27.58-27.82k) and the Akimizu fan (12.0k);
            // fan/junction stations keep straight
            // alignments because their turnout geometry is
            // built on tangents. The near-station 55 km/h
            // cap already applies, so the diagram is
            // unaffected; cant is graded with severity so
            // the tight stations visibly lean.
            let pins: [(centerM: Double, radiusM: Double, direction: Int, cantMm: Double)]
            switch region.kind {
            case .mainline:
                pins = [(8_226, 950, 1, 70), (28_452, 1_100, -1, 70), (44_032, 800, 1, 80),
                        (52_935, 650, 1, 85), (32_903, 550, -1, 90)]
            case .branch:
                pins = [(4_000, 450, -1, 80)]
            default:
                pins = []
            }
            // The cant ramp inside a transition is linear, and
            // the profile continuity tests cap the cant step at
            // 4.2 mm per 10 m — a 160 m transition at cant 70
            // steps 4.375 mm and failed the seeded-mainline
            // test on the 2026-11-14 01:15 Mac build (measured
            // steps 4.375 and 7.26). Size each pin's transition
            // from its cant: transition = max(200, cant x 3.0)
            // keeps the step at or below ~3.3 mm per 10 m.
            let pinRuns: [(run: GeneratedCurveRun, span: (start: Double, end: Double))] = pins.map { pin in
                let c = region.offsetM + pin.centerM
                let transitionM = max(200.0, pin.cantMm * 3.0)
                let run = GeneratedCurveRun(
                    transition: RouteCurveTransition(
                        startM: c - transitionM - 150,
                        circularStartM: c - 150,
                        circularEndM: c + 150,
                        endM: c + transitionM + 150
                    ),
                    radiusM: pin.radiusM,
                    direction: pin.direction,
                    cantMm: pin.cantMm
                )
                return (run, (c - transitionM - 150, c + transitionM + 150))
            }
            runs.append(contentsOf: pinRuns.map(\.run))
            let pinSpans: [(start: Double, end: Double)] = pinRuns.map(\.span)
            while cursor < regionEnd {
                // Mainline curves take their shape from the alignment
                // zone at the curve start (BVE-measured radii per
                // district); branch and depot keep their fixed ranges.
                // The draw order and count are unchanged, so the same
                // seed still gives a deterministic profile.
                let zone = region.kind == .mainline ? mainlineZone(at: cursor - region.offsetM) : nil
                let tangentRange = zone?.tangentRange ?? region.tangentRange
                let transitionRange = zone?.transitionRange ?? region.transitionRange
                let circularRange = zone?.circularRange ?? region.circularRange
                cursor += rng.value(in: tangentRange)
                guard cursor < regionEnd else { break }
                let transitionInM = rng.value(in: transitionRange)
                let circularM = rng.value(in: circularRange)
                let transitionOutM = rng.value(in: transitionRange)

                let randomDirection = rng.nextBool() ? 1 : -1
                let direction: Int
                if previousDirection == 0 || rng.nextUnit() >= 0.76 {
                    direction = randomDirection
                } else {
                    direction = -previousDirection
                }
                previousDirection = direction
                let radiusM = rng.value(in: zone?.radiusRange ?? region.radiusRange)
                // Cap one run's total deflection near 86 degrees
                // (1.5 rad): a short radius with a long circular
                // section would otherwise loop back on itself — the
                // plan view showed a hairpin crossing in the urban
                // core. The exact deflection is
                // (transitionIn/2 + circular + transitionOut/2)/R.
                let maxCircularM = max(120, 1.5 * radiusM - (transitionInM + transitionOutM) * 0.5)
                let clampedCircularM = min(circularM, maxCircularM)
                let circularStartM = cursor + transitionInM
                let circularEndM = circularStartM + clampedCircularM
                let endM = circularEndM + transitionOutM
                guard endM <= regionEnd else { break }

                // batch31: never let a random run collide
                // with a pinned station curve — hop past it
                // (the draws are consumed; the profile stays
                // deterministic for the seed).
                if let clash = pinSpans.first(where: { cursor < $0.end + 120 && endM > $0.start - 120 }) {
                    cursor = clash.end + 120
                    continue
                }
                runs.append(GeneratedCurveRun(
                    transition: RouteCurveTransition(
                        startM: cursor,
                        circularStartM: circularStartM,
                        circularEndM: circularEndM,
                        endM: endM
                    ),
                    radiusM: radiusM,
                    direction: direction,
                    cantMm: rng.value(in: region.cantRange)
                ))
                cursor = endM
            }
            return runs
        }

        let runs = regions.flatMap { curveRuns(in: $0) }.sorted { $0.transition.startM < $1.transition.startM }
        let step = 250.0
        let sectionCount = Int(ceil(lengthM / step))
        var sections: [RouteSection] = []
        sections.reserveCapacity(sectionCount)
        for index in 0..<sectionCount {
            let startM = Double(index) * step
            let endM = min(lengthM, startM + step)
            let midpointM = (startM + endM) * 0.5
            let run = runs.first { $0.transition.startM < endM && $0.transition.endM > startM }
            let activeRegion = regions.first { midpointM >= $0.offsetM && midpointM < $0.offsetM + $0.lengthM }
            let localM = midpointM - (activeRegion?.offsetM ?? 0)
            let localSection = max(0, Int(floor(localM / step)))
            let baseLimit = [75.0, 90.0, 100.0, 85.0, 110.0, 95.0][localSection % 6]
            // Curve limit from the cant equilibrium (2026-11-11,
            // recalibrated to passenger practice at the user's
            // request): v = 3.6 * sqrt(g * R * (cant + deficiency)
            // / gauge), crediting each curve's own fitted cant plus
            // 55 mm of cant deficiency on the 1,067 mm gauge. R600
            // with 90 mm cant now allows about 102 km/h, where the
            // old flat 0.65 factor (a 71 mm total allowance) gave 71.
            let curveLimit = run.map { curve in
                min(baseLimit, max(40.0, 3.6 * sqrt(max(1, 9.8 * (curve.cantMm + 55) / 1_067 * curve.radiusM))))
            } ?? baseLimit
            // batch71: no blanket near-station cap. A ±720 m,
            // 55 km/h cap around every station used to sit here;
            // with stations roughly 2 km apart it covered most of
            // the line, so the displayed limit stayed 55 even at a
            // green terminal departure whose section limit is the
            // city-zone 80. Station approach control is the safety
            // pattern's job (the stop-target braking envelope),
            // not a section cap — passing stations run at the
            // section limit, as on a real railway.
            var speedLimit = curveLimit
            if variant == .zooLine {
                // Zoo line zones (up layout): approach 45, the enclosure
                // stretch 450-1,900 m is a hard 30 km/h so passengers can
                // watch the animals, terminal approach 40.
                let zooCap: Double = midpointM < 450 ? 45 : (midpointM < 1_900 ? 30 : 40)
                speedLimit = min(speedLimit, zooCap)
            }
            if variant == .parkLine {
                speedLimit = min(speedLimit, 45)
            }
            // City-belt speed cap (2026-11-11): on the mainline the
            // zone cap binds over the cycling base table, so the run
            // out of the terminus stays at 80 km/h through the winding
            // urban and suburban zones, 90 through the hub fringe,
            // and only opens up on the rural and coastal stretches.
            if activeRegion?.kind == .mainline {
                speedLimit = min(speedLimit, mainlineZone(at: localM).speedCapKmh)
            }
            // Mainline gradients come from the canonical grade
            // table (see `mainlineGradePermille`): ruling grade
            // 10 permille, station pads level, everything unlisted
            // level. Branch and depot keep the old profile so the
            // through-branch/branch-shuttle equality holds.
            let gradient: Double
            if activeRegion?.kind == .mainline {
                gradient = mainlineGradePermille(at: localM, stations: stations)
            } else if activeRegion?.kind == .zoo {
                gradient = sin(localM / 1_900 + 0.5) * 1.8
            } else if activeRegion?.kind == .park {
                gradient = sin(localM / 1_700 + 0.9) * 1.6
            } else {
                gradient = sin(localM / 1_430 + 0.8) * 4.2 + sin(localM / 6_200 + 2.1) * 2.1
            }
            // batch98: the tunnel spans come from the canonical
            // TunnelSpans table (TunnelSpans.swift) — the same
            // table the legacy fallback converter reads, and the
            // one the pinning test in RegionalIntegrationTests
            // guards. localM is the section midpoint in region
            // coordinates, matching the table's frames (mainline
            // chainage / branch-local chainage).
            let tunnel: Bool
            switch activeRegion?.kind {
            case .mainline:
                tunnel = TunnelSpans.contains(mainlineChainage: localM)
            case .branch:
                tunnel = TunnelSpans.contains(branchLocalChainage: localM)
            default:
                tunnel = false
            }
            sections.append(RouteSection(
                startM: startM,
                endM: endM,
                gradientPermille: gradient,
                curveRadiusM: run?.radiusM,
                curveDirection: run?.direction,
                cantMm: run?.cantMm,
                curveTransition: run?.transition,
                speedLimitKmh: speedLimit,
                tunnelResistanceMultiplier: tunnel ? TunnelSpans.resistanceMultiplier : 1
            ))
        }

        guard direction == .down else { return sections }
        return sections.reversed().map { section in
            RouteSection(
                startM: lengthM - section.endM,
                endM: lengthM - section.startM,
                gradientPermille: -section.gradientPermille,
                curveRadiusM: section.curveRadiusM,
                curveDirection: section.curveDirection.map { -$0 },
                cantMm: section.cantMm,
                curveTransition: section.curveTransition?.reversed(over: lengthM),
                speedLimitKmh: section.speedLimitKmh,
                tunnelResistanceMultiplier: section.tunnelResistanceMultiplier
            )
        }
    }
}

private struct SplitMix64 {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
    mutating func nextUnit() -> Double { Double(next() >> 11) / Double(1 << 53) }
    mutating func nextBool() -> Bool { (next() & 1) == 0 }
    mutating func value(in range: ClosedRange<Double>) -> Double {
        range.lowerBound + nextUnit() * (range.upperBound - range.lowerBound)
    }
}

struct RegionalRouteGeometrySample: Sendable {
    let distanceM: Double
    let x: Float
    let z: Float
    let heading: Float
    let bankRadians: Float
    /// Track height above the route origin datum, integrated from the
    /// section gradients (trapezoidal, same rule as the heading
    /// integral). The scenery used to be flat while the physics ran
    /// over +/-25 permille: with an 81 m elevation range over the
    /// mainline the flat ground read as "not a railway". Every
    /// route-following surface and object now rides on this value.
    let elevationM: Float
}

/// The same seeded-profile integration used by the RealityKit host, exposed internally for geometry tests.
enum RegionalRouteGeometrySampler {
    static func makeSamples(route: RailwayRouteProfile, interval: Double) -> [RegionalRouteGeometrySample] {
        guard interval.isFinite, interval > 0 else { return [] }
        let count = max(Int(ceil(route.distanceM / interval)), 1)
        var output: [RegionalRouteGeometrySample] = []
        output.reserveCapacity(count + 1)
        var x = 0.0
        var z = 0.0
        var heading = 0.0
        var elevation = 0.0
        var previousDistance = 0.0

        for index in 0...count {
            let distance = min(Double(index) * interval, route.distanceM)
            if index > 0 {
                let delta = distance - previousDistance
                let startCurvature = signedCurvature(at: previousDistance, route: route)
                let endCurvature = signedCurvature(at: distance, route: route)
                heading += (startCurvature + endCurvature) * delta * 0.5
                x += sin(heading) * delta
                z -= cos(heading) * delta
                // Gradient is piecewise constant per 250 m section, so
                // the trapezoidal rule is exact inside a section and
                // off by at most |dg|*delta/2 at a section boundary
                // (a few cm). The Python mirror
                // (verify_elevation_quality20.py) uses the same rule,
                // so the two agree exactly.
                let startGradient = route.condition(at: previousDistance).gradientPermille
                let endGradient = route.condition(at: distance).gradientPermille
                elevation += (startGradient + endGradient) * 0.5 * delta / 1_000.0
            }
            let cantCondition = route.condition(at: distance)
            let cantRatio = (cantCondition.cantMm ?? 0) / route.trackGaugeMm
            let bankDirection = Double(cantCondition.curveDirection ?? 1)
            output.append(RegionalRouteGeometrySample(
                distanceM: distance,
                x: Float(x),
                z: Float(z),
                heading: Float(heading),
                bankRadians: Float(atan(cantRatio) * bankDirection),
                elevationM: Float(elevation)
            ))
            previousDistance = distance
        }
        return output
    }

    /// Body pitch of one car from its two bogie heights. The bogies sit
    /// ±6.35 m from the car centre (12.7 m apart); the front bogie is
    /// toward increasing chainage. Positive = nose up on an upgrade.
    /// Without it a car stays level while the rail climbs, so on a 25‰
    /// grade the car ends float/sink by up to ±0.24 m off the rail head.
    static func carBodyPitchRadians(frontBogieElevationM: Float, rearBogieElevationM: Float) -> Float {
        atan2(frontBogieElevationM - rearBogieElevationM, 12.7)
    }

    private static func signedCurvature(at chainageM: Double, route: RailwayRouteProfile) -> Double {
        let condition = route.condition(at: chainageM)
        guard let radius = condition.curveRadiusM, radius.isFinite, radius > 0 else { return 0 }
        let sectionIndex = route.sections.firstIndex(where: { chainageM >= $0.startM && chainageM < $0.endM }) ?? 0
        let direction = condition.curveDirection ?? (sectionIndex.isMultiple(of: 2) ? 1 : -1)
        return Double(direction) / radius
    }
}
