import Foundation
import RailwayRouteData
import StopScoring

/// Prepared route-relative station targets plus the independent game-only scoring engine.
struct PreparedStopScoringSession {
    let activeStops: [RegionalRouteStop]
    let stationDefinitions: [StopScoring.StationStopDefinition]
    let engine: StopScoring.StopScoringEngine
    /// batch60: the adjusted target for the run origin itself
    /// (batch74: front-aligned to platformEnd − margin, like
    /// every scored stop). The origin is never scored, but the
    /// model places the train there on reset so a run starts
    /// stopped at the origin platform instead of with the
    /// consist front on the station centre at chainage 0.
    let originTargetM: Double
}

enum StopScoringRouteAdapter {
    /// batch71 (user rule, 2026-11-15): the train's front must
    /// stop at least this far short of the platform end —
    /// overrun margin, as on a real railway. batch74: the
    /// margin line is the stop target itself, not just a clamp
    /// on the old centred target (see the scoring loop).
    static let platformEndMarginM = 5.0
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

        // batch60: the platform-bounds computation is shared by
        // the scoring loop below and the origin placement target,
        // so both use exactly the same zones. It throws when the
        // canonical data for a stop is missing.
        func bounds(forStop stop: RegionalRouteStop, index: Int) throws -> (start: Double, end: Double) {
            if trip.variant == .depotTransfer {
                // A yard stop zone is the canonical 2 km depot spur, not a passenger platform.
                return (0, routeLengthM)
            } else if (trip.variant == .zooLine || trip.variant == .parkLine),
                      stationPlanByID[stop.stationID] == nil {
                // The zoo / theme park terminals are synthetic stops
                // outside the canonical plan; score them against a
                // 200 m terminal platform zone, the same length as
                // every canonical platform on the network.
                // batch9 (2026-11-12, static test audit bycatch):
                // this zone used to be 120 m, but the consist rule
                // fixes zoo / park services at 8 cars = 156 m, so
                // the fit guard below threw for every legal
                // consist and stop scoring silently disabled
                // itself (stopScoringError) on both lines.
                // batch60: the synthetic zone now applies only to
                // stops outside the canonical plan — the zoo / park
                // ORIGIN is the canonical junction station and must
                // take the canonical branch below when its own
                // placement target is computed.
                return (max(0, routeLengthM - 200), routeLengthM)
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
                if isTerminal {
                    return (max(0, routeLengthM - length), routeLengthM)
                }
                return (0, min(routeLengthM, length))
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
                return (localStart, localEnd)
            }
        }

        // batch60: the origin is not scored, but its adjusted
        // target uses the same bounds and the same centring as
        // the scored targets below, so a reset can place the
        // train stopped at the origin platform. The route-bounds
        // guard from the scoring loop (start >= -0.1 etc.) is
        // deliberately NOT applied: at the origin the consist
        // legitimately extends behind chainage 0. When no
        // fitting target can be computed the raw stop position
        // is kept, which is the pre-batch60 behaviour.
        let originTargetM: Double = {
            guard let origin = trip.stops.first,
                  let originBounds = try? bounds(forStop: origin, index: 0),
                  originBounds.end - originBounds.start >= trainLengthMeters else {
                return trip.stops.first?.positionM ?? 0
            }
            let safeLower = originBounds.start + trainLengthMeters
            let safeUpper = originBounds.end
            guard safeLower <= safeUpper else { return origin.positionM }
            // batch74: the origin placement uses the same
            // front-aligned target as every scored stop (see the
            // scoring loop): the front stands on the margin
            // line, platformEnd − margin. The depot yard zone is
            // not a passenger platform and keeps the centred
            // placement it has always used.
            let targetUpper = originBounds.end - Self.platformEndMarginM
            if trip.variant == .depotTransfer {
                let platformCenterM = (originBounds.start + originBounds.end) / 2
                return min(max(platformCenterM + trainLengthMeters / 2, safeLower), targetUpper)
            }
            return max(safeLower, targetUpper)
        }()

        // The first stop is the run origin. Only arrivals after the player begins the service are scored.
        for index in trip.stops.indices.dropFirst() {
            let stop = trip.stops[index]
            let platformBounds = try bounds(forStop: stop, index: index)

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
            // batch34 (2026-11-14) made the stop target the
            // centred stop — the front half a consist past the
            // platform centre, where the diamond stop markers
            // stand. batch71 (2026-11-15, user rule) clamped
            // that target to platformEnd − 5 m, but the clamp
            // only binds when the centred target passes the
            // margin line (consist longer than platform − 10 m):
            // a 10-car consist (195 m) was held to end − 5, but
            // an 8-car consist (156 m) on a 200 m platform still
            // stopped exactly centred, front 22 m short of the
            // platform end — the user's "every stop sits in the
            // middle of the platform" report on IPA #6.
            // batch74 (2026-11-15): the target IS the margin
            // line. The front stops at platformEnd − margin at
            // every consist length (safeLower still guarantees
            // the rear stays on the platform), and the scoring
            // window's upper bound stays on the same line, so a
            // stop past the margin line never scores as correct.
            // The depot yard zone is not a passenger platform
            // and keeps the centred target.
            let targetUpper = platformBounds.end - Self.platformEndMarginM
            let target: Double
            if trip.variant == .depotTransfer {
                let platformCenterM = (platformBounds.start + platformBounds.end) / 2
                target = min(max(platformCenterM + trainLengthMeters / 2, safeLower), targetUpper)
            } else {
                target = max(safeLower, targetUpper)
            }
            let window = try StopScoring.StopPositionWindow(
                lowerBoundMeters: max(safeLower, target - 4),
                upperBoundMeters: min(targetUpper, target + 4)
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

        // batch43 (2026-11-14) restored the terminal stop's MODEL
        // position to exactly the route end, because the
        // game-mode session's completion gate required the train
        // to reach routeLengthM − 0.1. batch71 (2026-11-15)
        // supersedes that: the terminal now keeps its adjusted
        // target like every other stop — the front stops at
        // least 5 m short of the platform end (the user's
        // overrun-margin rule; with the old restoration the front
        // was driven flush to the platform end / buffer at every
        // terminal) — and GameModeSession.finish now keys its
        // completion gate on the final stop's position instead
        // of the route end, so sessions still complete at the
        // terminal stop.

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
            engine: engine,
            originTargetM: originTargetM
        )
    }
}
