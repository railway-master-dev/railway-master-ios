import Foundation

public struct WeekendTimetablePlan: Decodable, Sendable {
    public let schemaVersion: String
    public let dataStatus: String
    public let sourceNetworkPackageID: String
    public let disclaimer: String
    public let weekendCalendars: [WeekendCalendarRule]
    public let gameOperationsModel: GameOperationsModelRecord
}

public struct WeekendCalendarRule: Decodable, Sendable {
    public let calendar: String
    public let dataStatus: String
    public let windows: [WeekendWindowRule]
}

public struct WeekendWindowRule: Decodable, Sendable {
    public let direction: String
    public let daypart: String
    public let startTime: String
    public let endTime: String
    public let headwayMinutesByCategory: [String: Int]
    public let dataStatus: String
}

public struct GameOperationsModelRecord: Decodable, Sendable {
    public let virtualMinimumSameDirectionHeadwaySeconds: Int
    public let recoverySecondsAtDwell: Int
    public let recoverySecondsWhenSkippingStop: Int
    public let scopeNote: String
    public let dataStatus: String
}

public enum TimetablePlanLoader {
    public static func loadBundled() throws -> WeekendTimetablePlan {
        try loadBundled(bundle: .module)
    }

    public static func loadBundled(bundle: Bundle) throws -> WeekendTimetablePlan {
        guard let url = bundle.url(forResource: "WeekendTimetableRules", withExtension: "json", subdirectory: "Resources") else {
            throw TimetableError.missingResource("WeekendTimetableRules.json")
        }
        return try JSONDecoder().decode(WeekendTimetablePlan.self, from: Data(contentsOf: url))
    }

    public static func decode(_ data: Data, decoder: JSONDecoder = JSONDecoder()) throws -> WeekendTimetablePlan {
        try decoder.decode(WeekendTimetablePlan.self, from: data)
    }
}

public enum TimetableBuilder {
    private static let fixedDaypartBounds: [Daypart: (Int, Int)] = [
        .morningRush: (6 * 60, 9 * 60),
        .daytime: (9 * 60, 17 * 60),
        .evening: (17 * 60, 22 * 60),
        .night: (22 * 60, 24 * 60)
    ]

    public static func build(
        inputs: ImportedTimetableInputs,
        weekendPlan: WeekendTimetablePlan
    ) throws -> TimetableNetwork {
        guard weekendPlan.dataStatus == "PLACEHOLDER",
              weekendPlan.gameOperationsModel.dataStatus == "PLACEHOLDER" else {
            throw TimetableError.unsupportedPlaceholderInput("bundled weekend/game rules are not PLACEHOLDER")
        }
        guard weekendPlan.sourceNetworkPackageID == inputs.routePackageID else {
            throw TimetableError.inconsistentSources("weekend rules target \(weekendPlan.sourceNetworkPackageID), imported \(inputs.routePackageID)")
        }
        let weekendCalendars = Set(weekendPlan.weekendCalendars.map(\.calendar))
        guard weekendCalendars == Set([ServiceCalendar.saturday.rawValue, ServiceCalendar.holiday.rawValue]),
              weekendPlan.weekendCalendars.count == 2 else {
            throw TimetableError.inconsistentSources("Saturday and holiday calendars must be explicit and unique")
        }
        guard weekendPlan.gameOperationsModel.virtualMinimumSameDirectionHeadwaySeconds > 0,
              weekendPlan.gameOperationsModel.recoverySecondsAtDwell >= 0,
              weekendPlan.gameOperationsModel.recoverySecondsWhenSkippingStop >= 0 else {
            throw TimetableError.invalidTimetable("game operations values must be nonnegative and headway positive")
        }

        var patterns = inputs.weekdayPatterns
        for calendarRule in weekendPlan.weekendCalendars {
            guard calendarRule.dataStatus == "PLACEHOLDER",
                  let calendar = ServiceCalendar(rawValue: calendarRule.calendar),
                  calendar != .weekday,
                  calendarRule.windows.count == ServiceDirection.allCases.count * Daypart.allCases.count else {
                throw TimetableError.inconsistentSources("invalid weekend calendar \(calendarRule.calendar)")
            }
            var seenWindows = Set<String>()
            for window in calendarRule.windows {
                guard window.dataStatus == "PLACEHOLDER",
                      let direction = ServiceDirection(rawValue: window.direction),
                      let daypart = Daypart(rawValue: window.daypart) else {
                    throw TimetableError.unsupportedPlaceholderInput("invalid or non-PLACEHOLDER weekend window")
                }
                let key = "\(direction.rawValue)|\(daypart.rawValue)"
                guard seenWindows.insert(key).inserted,
                      let expectedBounds = fixedDaypartBounds[daypart] else {
                    throw TimetableError.inconsistentSources("duplicate or unsupported weekend window \(key)")
                }
                let start = try TimetableClock.parse(window.startTime)
                let end = try TimetableClock.parse(window.endTime)
                guard start == expectedBounds.0, end == expectedBounds.1,
                      Set(window.headwayMinutesByCategory.keys) == Set(ServiceCategory.allCases.map(\.rawValue)),
                      window.headwayMinutesByCategory.values.allSatisfy({ $0 > 0 }) else {
                    throw TimetableError.inconsistentSources("weekend \(calendar.rawValue) \(key) has invalid bounds or category headways")
                }
                for category in ServiceCategory.allCases {
                    patterns.append(TimetablePattern(
                        category: category,
                        direction: direction,
                        daypart: daypart,
                        calendar: calendar,
                        startMinute: start,
                        endMinute: end,
                        headwayMinutes: window.headwayMinutesByCategory[category.rawValue]!,
                        dataStatus: .placeholder
                    ))
                }
            }
            let expectedKeys = Set(ServiceDirection.allCases.flatMap { direction in
                Daypart.allCases.map { "\(direction.rawValue)|\($0.rawValue)" }
            })
            guard seenWindows == expectedKeys else {
                throw TimetableError.inconsistentSources("weekend calendar \(calendar.rawValue) lacks one or more windows")
            }
        }
        guard patterns.count == ServiceCalendar.allCases.count * ServiceCategory.allCases.count * ServiceDirection.allCases.count * Daypart.allCases.count else {
            throw TimetableError.inconsistentSources("combined timetable should have weekday, Saturday and holiday coverage for all classes/directions/dayparts")
        }

        let stationByID = Dictionary(uniqueKeysWithValues: inputs.stations.map { ($0.stationID, $0) })
        let serviceByCategory = Dictionary(uniqueKeysWithValues: inputs.services.map { ($0.category, $0) })
        var trips: [ScheduledTrip] = []
        for pattern in patterns.sorted(by: patternOrder) {
            guard let service = serviceByCategory[pattern.category] else {
                throw TimetableError.inconsistentSources("pattern references missing service \(pattern.category.rawValue)")
            }
            var departureMinute = pattern.startMinute
            while departureMinute < pattern.endMinute {
                let trip = try makeTrip(
                    service: service,
                    pattern: pattern,
                    departureMinute: departureMinute,
                    routePath: inputs.routePathStationIDs,
                    stationByID: stationByID
                )
                trips.append(trip)
                departureMinute += pattern.headwayMinutes
            }
        }
        trips.sort {
            if $0.departureSeconds != $1.departureSeconds { return $0.departureSeconds < $1.departureSeconds }
            if $0.direction != $1.direction { return $0.direction.rawValue < $1.direction.rawValue }
            if $0.calendar != $1.calendar { return $0.calendar.rawValue < $1.calendar.rawValue }
            return $0.tripID < $1.tripID
        }

        let movements = try makeDepotMovements(trips: trips, inputs: inputs)
        let candidates = makeInteractionCandidates(inputs: inputs)
        let operationsModel = GameOperationsModel(
            virtualMinimumSameDirectionHeadwaySeconds: weekendPlan.gameOperationsModel.virtualMinimumSameDirectionHeadwaySeconds,
            recoverySecondsAtDwell: weekendPlan.gameOperationsModel.recoverySecondsAtDwell,
            recoverySecondsWhenSkippingStop: weekendPlan.gameOperationsModel.recoverySecondsWhenSkippingStop,
            scopeNote: weekendPlan.gameOperationsModel.scopeNote,
            dataStatus: .placeholder
        )
        return TimetableNetwork(
            routeID: inputs.routeID,
            routePackageID: inputs.routePackageID,
            sourceNetworkIdentifier: inputs.sourceNetworkIdentifier,
            timezone: inputs.timezone,
            physicalNetworkLengthM: inputs.physicalNetworkLengthM,
            passengerRouteLengthM: inputs.passengerRouteLengthM,
            routePathStationIDs: inputs.routePathStationIDs,
            stations: inputs.stations,
            services: inputs.services,
            patterns: patterns.sorted(by: patternOrder),
            trips: trips,
            depot: inputs.depot,
            depotMovements: movements,
            interactionCandidates: candidates,
            operationsModel: operationsModel,
            disclaimer: "全駅名・キロ程・運転時刻・運転間隔・車庫時分・運転整理値は架空のPLACEHOLDERです。ゲーム用の生成値であり、実在路線の運行情報、設備情報、安全基準または運転指示として利用できません。待避・追越し候補はゲーム上の検討地点で、待避線・複線・進路・容量の実在を示しません。"
        )
    }

    private static func makeTrip(
        service: ServiceDefinition,
        pattern: TimetablePattern,
        departureMinute: Int,
        routePath: [String],
        stationByID: [String: TimetableStation]
    ) throws -> ScheduledTrip {
        let orderedIDs = pattern.direction == .down ? routePath : Array(routePath.reversed())
        let orientedStopIDs = pattern.direction == .down ? service.stopStationIDs : Array(service.stopStationIDs.reversed())
        let stopIDs = Set(orientedStopIDs)
        guard orderedIDs.count >= 2,
              orderedIDs.first.map({ stopIDs.contains($0) }) == true,
              orderedIDs.last.map({ stopIDs.contains($0) }) == true else {
            throw TimetableError.invalidTimetable("\(service.category.rawValue) must call at both oriented route terminals")
        }
        let stationEvents = try orderedIDs.map { id -> (TimetableStation, Bool) in
            guard let station = stationByID[id] else {
                throw TimetableError.inconsistentSources("trip references unknown canonical station \(id)")
            }
            return (station, stopIDs.contains(id))
        }
        let runtimeSeconds = service.plannedRuntimeMinutes * 60
        let dwellSeconds = dwellSecondsPerIntermediateStop(for: service.category)
        let intermediateStops = stationEvents.dropFirst().dropLast().filter { $0.1 }.count
        let totalDwellSeconds = intermediateStops * dwellSeconds
        guard totalDwellSeconds < runtimeSeconds else {
            throw TimetableError.invalidTimetable("dwell time consumes the entire \(service.category.rawValue) runtime")
        }
        let legDistances = zip(stationEvents, stationEvents.dropFirst()).map {
            abs($0.1.0.routeProgressM - $0.0.0.routeProgressM)
        }
        let allocatedTravelSeconds = try RuntimeAllocator.allocate(
            totalSeconds: runtimeSeconds - totalDwellSeconds,
            distances: legDistances
        )
        let startSeconds = departureMinute * 60
        var currentDeparture = startSeconds
        var outputEvents: [TimetableStopEvent] = []
        for index in stationEvents.indices {
            let (station, isStop) = stationEvents[index]
            let arrival: Int
            if index == 0 {
                arrival = startSeconds
            } else {
                arrival = currentDeparture + allocatedTravelSeconds[index - 1]
            }
            let isTerminal = index == stationEvents.count - 1
            let dwell = isStop && !isTerminal && index != 0 ? dwellSeconds : 0
            let departure = arrival + dwell
            outputEvents.append(TimetableStopEvent(
                stationID: station.stationID,
                stationName: station.name,
                kind: isStop ? .stop : .passThrough,
                arrivalSeconds: arrival,
                departureSeconds: departure,
                dwellSeconds: dwell,
                routeProgressM: station.routeProgressM
            ))
            currentDeparture = departure
        }
        guard outputEvents.last?.arrivalSeconds == startSeconds + runtimeSeconds else {
            throw TimetableError.invalidTimetable("runtime allocation did not preserve the planned end-to-end time")
        }
        let tripID = [
            pattern.calendar.rawValue,
            pattern.direction.rawValue.uppercased(),
            service.category.rawValue.uppercased(),
            pattern.daypart.rawValue.uppercased(),
            String(departureMinute)
        ].joined(separator: "_")
        return ScheduledTrip(
            tripID: tripID,
            category: service.category,
            direction: pattern.direction,
            daypart: pattern.daypart,
            calendar: pattern.calendar,
            departureSeconds: startSeconds,
            arrivalSeconds: startSeconds + runtimeSeconds,
            plannedRuntimeSeconds: runtimeSeconds,
            stationEvents: outputEvents,
            dataStatus: .placeholder
        )
    }

    private static func dwellSecondsPerIntermediateStop(for category: ServiceCategory) -> Int {
        switch category {
        case .local: return 45
        case .rapid: return 40
        case .semiExpress: return 35
        case .express: return 40
        case .rapidExpress: return 50
        case .limitedExpress: return 60
        }
    }

    private static func makeDepotMovements(
        trips: [ScheduledTrip],
        inputs: ImportedTimetableInputs
    ) throws -> [DepotMovement] {
        var movements: [DepotMovement] = []
        for trip in trips {
            let procedureKind: DepotMovementKind
            // The depot spur connects only at its canonical station. Down trips start there
            // and may leave the depot; up trips end there and may return to it. No empty-stock
            // movement is invented along the 68 km passenger route.
            if trip.direction == .down,
               trip.stationEvents.first?.stationID == inputs.depot.connectedStationID {
                procedureKind = .outbound
            } else if trip.direction == .up,
                      trip.stationEvents.last?.stationID == inputs.depot.connectedStationID {
                procedureKind = .inbound
            } else {
                continue
            }
            guard let procedure = inputs.depotProcedures.first(where: {
                $0.category == trip.category && $0.direction == trip.direction && $0.kind == procedureKind
            }) else {
                continue
            }
            let start: Int
            let end: Int
            let from: String
            let to: String
            switch procedureKind {
            case .outbound:
                guard procedure.timeOffsetMinutesFromPassengerDeparture < 0 else {
                    throw TimetableError.inconsistentSources("outbound depot offset must precede the down departure")
                }
                start = trip.departureSeconds + procedure.timeOffsetMinutesFromPassengerDeparture * 60
                end = trip.departureSeconds
                from = inputs.depot.depotID
                to = inputs.depot.connectedStationID
            case .inbound:
                let arrivalOffsetMinutes = trip.plannedRuntimeSeconds / 60
                guard procedure.timeOffsetMinutesFromPassengerDeparture > arrivalOffsetMinutes else {
                    throw TimetableError.inconsistentSources("inbound depot offset must follow the up arrival at the depot connection")
                }
                start = trip.arrivalSeconds
                end = trip.departureSeconds + procedure.timeOffsetMinutesFromPassengerDeparture * 60
                from = inputs.depot.connectedStationID
                to = inputs.depot.depotID
            }
            movements.append(DepotMovement(
                movementID: "\(trip.tripID)_\(procedureKind.rawValue)",
                tripID: trip.tripID,
                depotID: inputs.depot.depotID,
                trackID: inputs.depot.trackID,
                kind: procedureKind,
                fromLocationID: from,
                toLocationID: to,
                startSeconds: start,
                endSeconds: end,
                distanceM: inputs.depot.spurLengthM,
                dataStatus: .placeholder
            ))
        }
        return movements
    }

    private static func makeInteractionCandidates(inputs: ImportedTimetableInputs) -> [InteractionCandidate] {
        let stationByID = Dictionary(uniqueKeysWithValues: inputs.stations.map { ($0.stationID, $0) })
        let path = inputs.routePathStationIDs
        let terminalIDs = Set([path.first, path.last].compactMap { $0 })
        var candidates: [InteractionCandidate] = []
        for stationID in path where !terminalIDs.contains(stationID) {
            guard let station = stationByID[stationID] else { continue }
            candidates.append(InteractionCandidate(
                stationID: stationID,
                stationName: station.name,
                kind: .opposingDirectionMeet,
                serviceCategories: [.local],
                requiresScenarioTrackCapacity: true,
                dataStatus: .placeholder
            ))
            for faster in [ServiceCategory.rapid, .semiExpress, .express, .rapidExpress, .limitedExpress]
            where inputs.services.first(where: { $0.category == faster })?.stopStationIDs.contains(stationID) == true {
                candidates.append(InteractionCandidate(
                    stationID: stationID,
                    stationName: station.name,
                    kind: .overtake,
                    serviceCategories: [.local, faster],
                    requiresScenarioTrackCapacity: true,
                    dataStatus: .placeholder
                ))
            }
        }
        return candidates
    }

    private static func patternOrder(_ lhs: TimetablePattern, _ rhs: TimetablePattern) -> Bool {
        if lhs.calendar != rhs.calendar { return lhs.calendar.rawValue < rhs.calendar.rawValue }
        if lhs.direction != rhs.direction { return lhs.direction.rawValue < rhs.direction.rawValue }
        if lhs.startMinute != rhs.startMinute { return lhs.startMinute < rhs.startMinute }
        return lhs.category.rawValue < rhs.category.rawValue
    }
}

/// Integer apportionment keeps every trip's summed leg time exact and deterministic.
enum RuntimeAllocator {
    static func allocate(totalSeconds: Int, distances: [Double]) throws -> [Int] {
        guard totalSeconds >= 0,
              !distances.isEmpty,
              distances.allSatisfy({ $0 >= 0 && $0.isFinite }),
              distances.reduce(0, +) > 0 else {
            throw TimetableError.invalidTimetable("cannot distribute runtime over empty or invalid route segments")
        }
        let totalDistance = distances.reduce(0, +)
        let exact = distances.map { Double(totalSeconds) * $0 / totalDistance }
        var allocated = exact.map { Int(floor($0)) }
        let remainder = totalSeconds - allocated.reduce(0, +)
        let order = exact.indices.sorted {
            let left = exact[$0] - Double(allocated[$0])
            let right = exact[$1] - Double(allocated[$1])
            if left != right { return left > right }
            return $0 < $1
        }
        for index in order.prefix(remainder) { allocated[index] += 1 }
        return allocated
    }
}
