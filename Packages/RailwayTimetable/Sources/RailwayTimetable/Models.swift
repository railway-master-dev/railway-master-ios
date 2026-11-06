import Foundation

/// This package contains synthetic game data only. It is not an operating timetable.
public enum TimetableDataStatus: String, Codable, Hashable, Sendable {
    case placeholder = "PLACEHOLDER"
}

public enum ServiceCategory: String, Codable, CaseIterable, Hashable, Sendable {
    case local
    case rapid
    case semiExpress
    case express
    case rapidExpress
    case limitedExpress

    public var displayNameJa: String {
        switch self {
        case .local: return "各駅停車"
        case .rapid: return "快速"
        case .semiExpress: return "準急"
        case .express: return "急行"
        case .rapidExpress: return "快速急行"
        case .limitedExpress: return "特急"
        }
    }
}

public enum ServiceDirection: String, Codable, CaseIterable, Hashable, Sendable {
    case up
    case down
}

public enum ServiceCalendar: String, Codable, CaseIterable, Hashable, Sendable {
    case weekday = "WEEKDAY_PLACEHOLDER"
    case saturday = "SATURDAY_PLACEHOLDER"
    case holiday = "HOLIDAY_PLACEHOLDER"
}

public enum Daypart: String, Codable, CaseIterable, Hashable, Sendable {
    case morningRush
    case daytime
    case evening
    case night
}

public enum StopEventKind: String, Codable, Hashable, Sendable {
    case stop = "STOP"
    case passThrough = "PASS_THROUGH"
}

public enum DepotMovementKind: String, Codable, Hashable, Sendable {
    case outbound = "DEPOT_OUTBOUND"
    case inbound = "DEPOT_INBOUND"
}

public struct TimetableStation: Codable, Hashable, Sendable {
    public let stationID: String
    public let name: String
    /// Original chainage on the station's own track, in metres.
    public let chainageM: Double
    public let trackIDs: [String]
    /// Progress from the first passenger terminal along the imported through route.
    public let routeProgressM: Double
    public let dataStatus: TimetableDataStatus
}

public struct ServiceDefinition: Codable, Hashable, Sendable {
    public let category: ServiceCategory
    public let routeDistanceKm: Double
    public let plannedRuntimeMinutes: Int
    /// Station IDs in the canonical down direction, sourced from the operations plan.
    public let stopStationIDs: [String]
    public let dataStatus: TimetableDataStatus
}

public struct DepotDefinition: Codable, Hashable, Sendable {
    public let depotID: String
    public let trackID: String
    public let connectedStationID: String
    public let spurLengthM: Double
    public let dataStatus: TimetableDataStatus
}

public struct DepotProcedure: Codable, Hashable, Sendable {
    public let category: ServiceCategory
    public let direction: ServiceDirection
    public let kind: DepotMovementKind
    /// Offset from the revenue trip's origin departure, retained from the source placeholder plan.
    public let timeOffsetMinutesFromPassengerDeparture: Int
    public let dataStatus: TimetableDataStatus
}

public struct ImportedTimetableInputs: Sendable {
    public let routeID: String
    public let routePackageID: String
    public let sourceNetworkIdentifier: String
    public let timezone: String
    public let physicalNetworkLengthM: Double
    public let passengerRouteLengthM: Double
    public let routePathStationIDs: [String]
    public let stations: [TimetableStation]
    public let services: [ServiceDefinition]
    public let weekdayPatterns: [TimetablePattern]
    public let depot: DepotDefinition
    public let depotProcedures: [DepotProcedure]

    public init(
        routeID: String,
        routePackageID: String,
        sourceNetworkIdentifier: String,
        timezone: String,
        physicalNetworkLengthM: Double,
        passengerRouteLengthM: Double,
        routePathStationIDs: [String],
        stations: [TimetableStation],
        services: [ServiceDefinition],
        weekdayPatterns: [TimetablePattern],
        depot: DepotDefinition,
        depotProcedures: [DepotProcedure]
    ) {
        self.routeID = routeID
        self.routePackageID = routePackageID
        self.sourceNetworkIdentifier = sourceNetworkIdentifier
        self.timezone = timezone
        self.physicalNetworkLengthM = physicalNetworkLengthM
        self.passengerRouteLengthM = passengerRouteLengthM
        self.routePathStationIDs = routePathStationIDs
        self.stations = stations
        self.services = services
        self.weekdayPatterns = weekdayPatterns
        self.depot = depot
        self.depotProcedures = depotProcedures
    }
}

public struct TimetablePattern: Codable, Hashable, Sendable, Identifiable {
    public var id: String {
        "\(calendar.rawValue)|\(direction.rawValue)|\(daypart.rawValue)|\(category.rawValue)"
    }

    public let category: ServiceCategory
    public let direction: ServiceDirection
    public let daypart: Daypart
    public let calendar: ServiceCalendar
    /// Minutes after midnight; end is exclusive.
    public let startMinute: Int
    public let endMinute: Int
    public let headwayMinutes: Int
    public let dataStatus: TimetableDataStatus
}

public struct TimetableStopEvent: Codable, Hashable, Sendable {
    public let stationID: String
    public let stationName: String
    public let kind: StopEventKind
    /// Seconds from the start of the service day. May exceed 86,400 for a next-day arrival.
    public let arrivalSeconds: Int
    public let departureSeconds: Int
    public let dwellSeconds: Int
    public let routeProgressM: Double
}

public struct ScheduledTrip: Codable, Hashable, Sendable, Identifiable {
    public var id: String { tripID }

    public let tripID: String
    public let category: ServiceCategory
    public let direction: ServiceDirection
    public let daypart: Daypart
    public let calendar: ServiceCalendar
    public let departureSeconds: Int
    public let arrivalSeconds: Int
    public let plannedRuntimeSeconds: Int
    public let stationEvents: [TimetableStopEvent]
    public let dataStatus: TimetableDataStatus
}

public struct DepotMovement: Codable, Hashable, Sendable, Identifiable {
    public var id: String { movementID }

    public let movementID: String
    public let tripID: String
    public let depotID: String
    public let trackID: String
    public let kind: DepotMovementKind
    public let fromLocationID: String
    public let toLocationID: String
    public let startSeconds: Int
    public let endSeconds: Int
    public let distanceM: Double
    public let dataStatus: TimetableDataStatus
}

public enum InteractionKind: String, Codable, Hashable, Sendable {
    case opposingDirectionMeet = "OPPOSING_DIRECTION_MEET"
    case overtake = "OVERTAKE"
}

/// A timetable-derived game candidate, never a claim that passing infrastructure exists.
public struct InteractionCandidate: Codable, Hashable, Sendable, Identifiable {
    public var id: String { "\(kind.rawValue)|\(stationID)|\(serviceCategories.map(\.rawValue).sorted().joined(separator: ","))" }

    public let stationID: String
    public let stationName: String
    public let kind: InteractionKind
    public let serviceCategories: [ServiceCategory]
    public let requiresScenarioTrackCapacity: Bool
    public let dataStatus: TimetableDataStatus
}

public struct GameOperationsModel: Codable, Hashable, Sendable {
    public let virtualMinimumSameDirectionHeadwaySeconds: Int
    public let recoverySecondsAtDwell: Int
    public let recoverySecondsWhenSkippingStop: Int
    public let scopeNote: String
    public let dataStatus: TimetableDataStatus
}

public struct TimetableNetwork: Codable, Sendable {
    public let routeID: String
    public let routePackageID: String
    public let sourceNetworkIdentifier: String
    public let timezone: String
    public let physicalNetworkLengthM: Double
    public let passengerRouteLengthM: Double
    public let routePathStationIDs: [String]
    public let stations: [TimetableStation]
    public let services: [ServiceDefinition]
    public let patterns: [TimetablePattern]
    public let trips: [ScheduledTrip]
    public let depot: DepotDefinition
    public let depotMovements: [DepotMovement]
    public let interactionCandidates: [InteractionCandidate]
    public let operationsModel: GameOperationsModel
    public let dataStatus: TimetableDataStatus
    public let disclaimer: String

    public init(
        routeID: String,
        routePackageID: String,
        sourceNetworkIdentifier: String,
        timezone: String,
        physicalNetworkLengthM: Double,
        passengerRouteLengthM: Double,
        routePathStationIDs: [String],
        stations: [TimetableStation],
        services: [ServiceDefinition],
        patterns: [TimetablePattern],
        trips: [ScheduledTrip],
        depot: DepotDefinition,
        depotMovements: [DepotMovement],
        interactionCandidates: [InteractionCandidate],
        operationsModel: GameOperationsModel,
        dataStatus: TimetableDataStatus = .placeholder,
        disclaimer: String
    ) {
        self.routeID = routeID
        self.routePackageID = routePackageID
        self.sourceNetworkIdentifier = sourceNetworkIdentifier
        self.timezone = timezone
        self.physicalNetworkLengthM = physicalNetworkLengthM
        self.passengerRouteLengthM = passengerRouteLengthM
        self.routePathStationIDs = routePathStationIDs
        self.stations = stations
        self.services = services
        self.patterns = patterns
        self.trips = trips
        self.depot = depot
        self.depotMovements = depotMovements
        self.interactionCandidates = interactionCandidates
        self.operationsModel = operationsModel
        self.dataStatus = dataStatus
        self.disclaimer = disclaimer
    }
}

public enum TimetableClock {
    public static func parse(_ value: String) throws -> Int {
        let components = value.split(separator: ":", omittingEmptySubsequences: false)
        guard components.count == 2,
              let hour = Int(components[0]),
              let minute = Int(components[1]),
              (0...24).contains(hour), (0...59).contains(minute),
              !(hour == 24 && minute != 0) else {
            throw TimetableError.invalidClock(value)
        }
        return hour * 60 + minute
    }

    public static func display(_ secondsFromServiceDay: Int) -> String {
        let nonnegative = max(0, secondsFromServiceDay)
        let day = nonnegative / 86_400
        let withinDay = nonnegative % 86_400
        let hour = withinDay / 3_600
        let minute = (withinDay % 3_600) / 60
        let clock = String(format: "%02d:%02d", hour, minute)
        return day == 0 ? clock : "翌日\(clock)"
    }
}

public enum TimetableError: Error, LocalizedError, Equatable, Sendable {
    case invalidClock(String)
    case unsupportedPlaceholderInput(String)
    case inconsistentSources(String)
    case invalidTimetable(String)
    case invalidDisruption(String)
    case missingResource(String)

    public var errorDescription: String? {
        switch self {
        case .invalidClock(let value): return "Invalid HH:mm time: \(value)"
        case .unsupportedPlaceholderInput(let detail): return "Only fictional PLACEHOLDER data is accepted: \(detail)"
        case .inconsistentSources(let detail): return "Canonical route and timetable sources do not agree: \(detail)"
        case .invalidTimetable(let detail): return "Invalid timetable input: \(detail)"
        case .invalidDisruption(let detail): return "Invalid game disruption scenario: \(detail)"
        case .missingResource(let name): return "Bundled timetable resource not found: \(name)"
        }
    }
}
