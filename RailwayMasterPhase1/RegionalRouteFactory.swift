import Foundation

enum RegionalRouteVariant: String, CaseIterable, Identifiable, Sendable {
    case mainline
    case throughBranch
    case branchShuttle
    case depotTransfer

    var id: String { rawValue }
    var title: String {
        switch self {
        case .mainline: return "本線 全線"
        case .throughBranch: return "本線・支線直通"
        case .branchShuttle: return "支線区間"
        case .depotTransfer: return "車庫引込線"
        }
    }

    var distanceDescription: String {
        switch self {
        case .mainline: return "60 km"
        case .throughBranch: return "68 km"
        case .branchShuttle: return "8 km"
        case .depotTransfer: return "2 km"
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
    enum Kind: Equatable { case mainline, branch, depot }
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
                }
            }
            let position = direction == .up ? rawPosition : routeLengthM - rawPosition
            let lineID = station?.lineId ?? plan.network.depotSpurID
            let trackID = trackIdentifier(lineID: lineID, direction: direction)
            let name = station?.name ?? "環雲車両基地（架空）"
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
        }

        func curveRuns(in region: GeneratedAlignmentRegion) -> [GeneratedCurveRun] {
            var rng = SplitMix64(seed: geometrySeed ^ region.seedSalt)
            var cursor = region.offsetM + region.leadingMarginM
            var previousDirection = 0
            let regionEnd = region.offsetM + region.lengthM - region.trailingMarginM
            var runs: [GeneratedCurveRun] = []
            while cursor < regionEnd {
                cursor += rng.value(in: region.tangentRange)
                guard cursor < regionEnd else { break }
                let transitionInM = rng.value(in: region.transitionRange)
                let circularM = rng.value(in: region.circularRange)
                let transitionOutM = rng.value(in: region.transitionRange)
                let circularStartM = cursor + transitionInM
                let circularEndM = circularStartM + circularM
                let endM = circularEndM + transitionOutM
                guard endM <= regionEnd else { break }

                let randomDirection = rng.nextBool() ? 1 : -1
                let direction: Int
                if previousDirection == 0 || rng.nextUnit() >= 0.76 {
                    direction = randomDirection
                } else {
                    direction = -previousDirection
                }
                previousDirection = direction
                runs.append(GeneratedCurveRun(
                    transition: RouteCurveTransition(
                        startM: cursor,
                        circularStartM: circularStartM,
                        circularEndM: circularEndM,
                        endM: endM
                    ),
                    radiusM: rng.value(in: region.radiusRange),
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
            let nearStation = stations.contains { abs($0.positionM - midpointM) < 720 }
            let baseLimit = [75.0, 90.0, 100.0, 85.0, 110.0, 95.0][localSection % 6]
            let curveLimit = run.map { min(baseLimit, max(40.0, 3.6 * sqrt(max(1, 0.65 * $0.radiusM)))) } ?? baseLimit
            let speedLimit = nearStation ? min(curveLimit, 55.0) : curveLimit
            let gradient = sin(localM / 1_430 + 0.8) * 4.2 + sin(localM / 6_200 + 2.1) * 2.1
            let tunnel = (activeRegion?.kind == .mainline &&
                ((localM > 17_800 && localM < 19_250) || (localM > 42_100 && localM < 43_600)))
                || (activeRegion?.kind == .branch && localM > 3_500 && localM < 4_050)
            sections.append(RouteSection(
                startM: startM,
                endM: endM,
                gradientPermille: gradient,
                curveRadiusM: run?.radiusM,
                curveDirection: run?.direction,
                cantMm: run?.cantMm,
                curveTransition: run?.transition,
                speedLimitKmh: speedLimit,
                tunnelResistanceMultiplier: tunnel ? 1.25 : 1
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
            }
            let cantCondition = route.condition(at: distance)
            let cantRatio = (cantCondition.cantMm ?? 0) / route.trackGaugeMm
            let bankDirection = Double(cantCondition.curveDirection ?? 1)
            output.append(RegionalRouteGeometrySample(
                distanceM: distance,
                x: Float(x),
                z: Float(z),
                heading: Float(heading),
                bankRadians: Float(atan(cantRatio) * bankDirection)
            ))
            previousDistance = distance
        }
        return output
    }

    private static func signedCurvature(at chainageM: Double, route: RailwayRouteProfile) -> Double {
        let condition = route.condition(at: chainageM)
        guard let radius = condition.curveRadiusM, radius.isFinite, radius > 0 else { return 0 }
        let sectionIndex = route.sections.firstIndex(where: { chainageM >= $0.startM && chainageM < $0.endM }) ?? 0
        let direction = condition.curveDirection ?? (sectionIndex.isMultiple(of: 2) ? 1 : -1)
        return Double(direction) / radius
    }
}
