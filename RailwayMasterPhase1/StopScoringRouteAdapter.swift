import Foundation
import RailwayRouteData
import StopScoring

/// Prepared route-relative station targets plus the independent game-only scoring engine.
struct PreparedStopScoringSession {
    let activeStops: [RegionalRouteStop]
    let stationDefinitions: [StopScoring.StationStopDefinition]
    let engine: StopScoring.StopScoringEngine
}

enum StopScoringRouteAdapter {
    static func prepare(
        trip: RegionalPlayableRoute,
        plan: FictionalOperationsPlan,
        routePackage: RailwayRouteData.RoutePackage,
        trainLengthMeters: Double,
        scheduleByStationID: [String: StopScoring.StopSchedule] = [:]
    ) throws -> PreparedStopScoringSession {
        guard trainLengthMeters.isFinite, trainLengthMeters > 0,
              trip.stops.count >= 2,
              abs(trip.profile.distanceM - trip.stops.last!.positionM) < 0.1 else {
            throw StopScoring.StopScoringError.invalidConfiguration("Route stops or fictional consist length are invalid.")
        }

        let stationsByID = Dictionary(
            routePackage.route.stations.map { ($0.stationID, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let stationPlanByID = Dictionary(
            plan.stations.map { ($0.stationId, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let mainlineLengthM = plan.network.mainlineLengthKm * 1_000
        let routeLengthM = trip.profile.distanceM
        let junctionChainageM = stationPlanByID[plan.network.branchJunctionStationID].map { $0.chainageKm * 1_000 }

        var adjustedStops = trip.stops
        var definitions: [StopScoring.StationStopDefinition] = []
        definitions.reserveCapacity(max(0, trip.stops.count - 1))

        // The first stop is the run origin. Only arrivals after the player begins the service are scored.
        for index in trip.stops.indices.dropFirst() {
            let stop = trip.stops[index]
            let platformBounds: (start: Double, end: Double)

            if trip.variant == .depotTransfer {
                // A yard stop zone is the canonical 2 km depot spur, not a passenger platform.
                platformBounds = (0, routeLengthM)
            } else if trip.variant == .zooLine || trip.variant == .parkLine {
                // The zoo / theme park terminals are synthetic stops
                // outside the canonical plan; score them against a
                // 120 m terminal platform zone.
                platformBounds = (max(0, routeLengthM - 120), routeLengthM)
            } else if trip.variant == .branchShuttle,
                      stop.stationID == plan.network.branchJunctionStationID {
                // The junction's canonical platform is on the main line; project its PLACEHOLDER length
                // onto this branch-only route's terminal so the same full consist can be evaluated.
                guard let sourceStation = stationsByID[stop.stationID],
                      let sourcePlatform = sourceStation.platforms.first(where: { $0.trackID == "main_line" }),
                      let length = sourcePlatform.lengthM.value, length >= trainLengthMeters else {
                    throw StopScoring.StopScoringError.invalidConfiguration("The branch-junction stop zone cannot fit the selected fictional consist.")
                }
                let isTerminal = index == trip.stops.count - 1
                platformBounds = isTerminal
                    ? (max(0, routeLengthM - length), routeLengthM)
                    : (0, min(routeLengthM, length))
            } else {
                guard let sourceStation = stationsByID[stop.stationID],
                      let planStation = stationPlanByID[stop.stationID] else {
                    throw StopScoring.StopScoringError.invalidConfiguration("Canonical station \(stop.stationID) is missing from RouteData or the operations plan.")
                }
                let sourceTrackID: String
                if stop.trackID.hasPrefix("branch-") {
                    sourceTrackID = "branch_line"
                } else if stop.trackID.hasPrefix("main-") {
                    sourceTrackID = "main_line"
                } else {
                    throw StopScoring.StopScoringError.invalidConfiguration("Unsupported canonical passenger track for \(stop.stationID).")
                }
                guard let platform = sourceStation.platforms.first(where: { $0.trackID == sourceTrackID }),
                      let rawStart = platform.startChainageM.value,
                      let rawEnd = platform.endChainageM.value,
                      rawStart < rawEnd else {
                    throw StopScoring.StopScoringError.invalidConfiguration("Canonical PLACEHOLDER platform is missing for \(stop.stationID).")
                }

                let stationRawChainageM = planStation.chainageKm * 1_000
                func routeProgress(_ sourceChainage: Double) -> Double {
                    switch trip.variant {
                    case .mainline:
                        return sourceChainage
                    case .throughBranch:
                        return sourceTrackID == "branch_line" ? mainlineLengthM + sourceChainage : sourceChainage
                    case .branchShuttle:
                        // The junction is the branch route's zero; ordinary branch stations already use local chainage.
                        return sourceTrackID == "branch_line" ? sourceChainage : sourceChainage - (junctionChainageM ?? stationRawChainageM)
                    case .depotTransfer:
                        return sourceChainage
                    case .zooLine:
                        // The zoo route's zero is 大野 (mainline chainage 50,710 m).
                        return sourceChainage - 50_710
                    case .parkLine:
                        // The park route's zero is 館川 (mainline chainage 55,161 m).
                        return sourceChainage - 55_161
                    }
                }
                let progressA = routeProgress(rawStart)
                let progressB = routeProgress(rawEnd)
                let physicalStart = min(progressA, progressB)
                let physicalEnd = max(progressA, progressB)
                let localStart: Double
                let localEnd: Double
                if trip.direction == .up {
                    localStart = physicalStart
                    localEnd = physicalEnd
                } else {
                    localStart = routeLengthM - physicalEnd
                    localEnd = routeLengthM - physicalStart
                }
                platformBounds = (localStart, localEnd)
            }

            guard platformBounds.start.isFinite, platformBounds.end.isFinite,
                  platformBounds.start >= -0.1, platformBounds.end <= routeLengthM + 0.1,
                  platformBounds.end - platformBounds.start >= trainLengthMeters else {
                throw StopScoring.StopScoringError.invalidConfiguration("The PLACEHOLDER stop zone at \(stop.stationID) cannot fit the selected consist within this route.")
            }

            // All playable route coordinates increase in travel order, including down services.
            let safeLower = platformBounds.start + trainLengthMeters
            let safeUpper = platformBounds.end
            guard safeLower <= safeUpper else {
                throw StopScoring.StopScoringError.invalidConfiguration("The PLACEHOLDER platform at \(stop.stationID) is shorter than the selected consist.")
            }
            let target = min(max(stop.positionM, safeLower), safeUpper)
            let window = try StopScoring.StopPositionWindow(
                lowerBoundMeters: max(safeLower, target - 4),
                upperBoundMeters: min(safeUpper, target + 4)
            )
            let definition = try StopScoring.StationStopDefinition(
                stationID: stop.stationID,
                displayName: stop.name,
                stationChainageMeters: stop.positionM,
                targetStopChainageMeters: target,
                platformStartChainageMeters: platformBounds.start,
                platformEndChainageMeters: platformBounds.end,
                permittedStopWindow: window,
                schedule: scheduleByStationID[stop.stationID] ?? .none
            )
            definitions.append(definition)
            adjustedStops[index] = RegionalRouteStop(
                stationID: stop.stationID,
                name: stop.name,
                positionM: target,
                trackID: stop.trackID
            )
        }

        guard zip(adjustedStops, adjustedStops.dropFirst()).allSatisfy({ $0.positionM < $1.positionM }) else {
            throw StopScoring.StopScoringError.invalidConfiguration("Consist-safe stop targets are not strictly ordered along the PLACEHOLDER route.")
        }
        let policy = StopScoring.GameScoringPolicy(
            weights: StopScoring.ComponentWeights(stop: 75, timetable: 25, doors: 0, procedures: 0),
            stoppedSpeedThresholdMetersPerSecond: 0.15
        )
        let engine = try StopScoring.StopScoringEngine(
            trainLengthMeters: trainLengthMeters,
            direction: .increasingChainage,
            stations: definitions,
            policy: policy
        )
        return PreparedStopScoringSession(
            activeStops: adjustedStops,
            stationDefinitions: definitions,
            engine: engine
        )
    }
}
