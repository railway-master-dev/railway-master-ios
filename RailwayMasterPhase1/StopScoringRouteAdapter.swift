import Foundation
import RailwayRouteData
import StopScoring

/// Prepared route-relative station targets plus the independent game-only scoring engine.
struct PreparedStopScoringSession {
    let activeStops: [RegionalRouteStop]
    let stationDefinitions: [StopScoring.StationStopDefinition]
    let engine: StopScoring.StopScoringEngine
    /// batch60: the adjusted target for the run origin itself.
    /// batch121 supersedes the batch74 front-aligned origin
    /// rule: the origin target now CENTRES the consist in the
    /// platform span on every line (see the computation in
    /// prepare), so a run starts with the train standing in
    /// the middle of the origin platform instead of with its
    /// front 5 m from the platform end. The origin is never
    /// scored, but the model places the train there on reset.
    let originTargetM: Double
}

enum StopScoringRouteAdapter {
    /// batch71 (user rule, 2026-11-15): the train's front must
    /// stop at least this far short of the platform end —
    /// overrun margin, as on a real railway. batch74: the
    /// margin line is the stop target itself, not just a clamp
    /// on the old centred target (see the scoring loop).
    static let platformEndMarginM = 5.0
    /// batch116: the length of each depot stop's own zone at
    /// the spur ends (see the depot branch of bounds(forStop:)).
    static let depotZoneLengthM = 200.0
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
                // batch116 (2026-11-16, IPA #12 device report):
                // the yard used to be ONE zone for both stops,
                // so the centred target formula put the origin
                // target and the final target on the same spot
                // (1,078 m for an 8-car consist), reset placed
                // the train exactly on the final target, and the
                // run completed itself after the 2 s arrival
                // dwell without the train ever moving. Each
                // stop now gets its own 200 m zone — the origin
                // at the spur start, the terminal at the spur
                // end, the same shape as the zoo / park
                // synthetic terminal zone below — so the centred
                // targets split (origin ≈ 178 m, final ≈ 1,978 m
                // for 8 cars) and the transfer is a real
                // ~1.8 km drive. The zones key on travel order
                // (index), like the branch-junction branch
                // below: route coordinates always run in travel
                // order, so in the down direction the physical
                // spur end is the origin and takes the start
                // zone in route coordinates.
                if index == trip.stops.count - 1 {
                    return (max(0, routeLengthM - Self.depotZoneLengthM), routeLengthM)
                }
                return (0, min(routeLengthM, Self.depotZoneLengthM))
            } else if trip.variant == .zooLine || trip.variant == .parkLine {
                // batch121 (2026-11-16, IPA #12 device reports +
                // design study §1.6/§2.5): EVERY stop on a zoo /
                // park route takes a 200 m zone at its own end of
                // the route, keyed on travel order exactly like
                // the depot branch above. Two stops used to break
                // this shape:
                // - The synthetic terminal (ZOO_END / PARK_END,
                // outside the canonical plan) took the far-end
                // zone unconditionally, so in the down direction
                // — where it is the ORIGIN — its zone sat at the
                // opposite end of the line from the stop itself.
                // (batch9: the zone is 200 m, not the old 120 m,
                // because the consist rule fixes zoo / park
                // services at 8 cars = 156 m and a shorter zone
                // made the fit guard throw for every legal
                // consist.)
                // - The junction station (大野 S24 / 館川 S26)
                // fell through to the canonical branch, whose
                // platform is the station centre ± 100 m in
                // mainline chainage. At the route end that maps
                // to a travel-frame range ending 100 m PAST the
                // route end in the down direction, so the
                // scoring loop's route-bounds guard threw and
                // prepare failed wholesale for down zoo / park
                // sessions — no stop scoring, no adjusted stops,
                // no origin placement (the train spawned at 0).
                // The junction platform is therefore projected
                // onto the route end it sits on, the same
                // treatment the branch-junction branch below
                // gives the shuttle's junction and the same
                // 200 m the scene's canonicalPlatformBounds now
                // draws for these variants, so the drawn
                // platform and the stop data agree.
                if index == trip.stops.count - 1 {
                    return (max(0, routeLengthM - 200), routeLengthM)
                }
                return (0, min(routeLengthM, 200))
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
        // target is computed from the same bounds as the scored
        // targets below, so a reset can place the train stopped
        // at the origin platform (batch121: centred in the span
        // — see the rule inside). The route-bounds
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
            // batch121 (2026-11-16, design study §2.5 — user
            // reports on IPA #12: at 海袋 and on the branch the
            // origin showed only the platform's end slope ahead
            // of the cab, and on the zoo / park up shuttles the
            // placed train sat ~95 m from the drawn platform's
            // centre): the origin placement is its own rule,
            // unified across ALL lines — the consist is CENTRED
            // in the platform span (front = span start +
            // consist length + half the leftover), clamped to
            // the fit window and to the batch71 margin line at
            // the span end. batch74's front-aligned origin
            // (platformEnd − margin, the ARRIVAL rule) is
            // superseded for origins only; every non-origin
            // stop below keeps the arrival rule unchanged. The
            // depot yard already used this centred formula
            // (batch116) and keeps the identical numbers.
            let targetUpper = originBounds.end - Self.platformEndMarginM
            let platformCenterM = (originBounds.start + originBounds.end) / 2
            return min(max(platformCenterM + trainLengthMeters / 2, safeLower), targetUpper)
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

        // batch112 (2026-11-16, IPA #12 device report): the
        // origin stop must carry the same adjusted target as
        // every other stop. prepare has always computed
        // originTargetM for train placement (batch60/74), but
        // adjustedStops[0] kept the raw station position (0),
        // so the model's 4 m stop-match consumers — the
        // automatic door cycle, the departure bell and the HUD
        // schedule line — could never recognise the train as
        // standing at the origin (195 m away at S01): the
        // doors never opened there and the whole batch108
        // departure sequence was skipped. Mirror the target
        // into index 0, but only where the strict ordering
        // checked below still holds. On the depot transfer
        // both stops share the single yard zone and the same
        // centred formula, so the origin target EQUALS the
        // second stop's target; the raw origin position is
        // kept there (the depot has no door sequence by spec,
        // and its placement still comes from the returned
        // originTargetM field, which is unchanged).
        // batch116: the depot zones are split now (see the
        // depot branch of bounds(forStop:)), so the depot
        // origin target (178 m) differs from its final target
        // (1,978 m), the condition below holds, and the write
        // fires on the depot too — its origin stop carries the
        // adjusted target like every other route's. The depot
        // still has no timetable-anchored departure sequence
        // (it has no timetable selection at all) and
        // door-procedure scoring still excludes it; placement
        // still comes from the returned originTargetM field.
        if adjustedStops.count >= 2, originTargetM < adjustedStops[1].positionM {
            let origin = adjustedStops[0]
            adjustedStops[0] = RegionalRouteStop(
                stationID: origin.stationID,
                name: origin.name,
                positionM: originTargetM,
                trackID: origin.trackID
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
