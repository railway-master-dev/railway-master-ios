import Foundation

public enum FictionalDataStatus: String, Codable, Equatable, Sendable {
    case placeholder = "PLACEHOLDER"
}

public enum ServiceDirection: String, Codable, CaseIterable, Equatable, Sendable {
    case up
    case down
}

public enum RailwayServiceType: String, Codable, CaseIterable, Equatable, Sendable {
    case express
    case limitedExpress
    case semiExpress
    case local
    case rapid
    case rapidExpress

    public var japaneseName: String {
        switch self {
        case .express: return "急行"
        case .limitedExpress: return "特急"
        case .semiExpress: return "準急"
        case .local: return "各停"
        case .rapid: return "快速"
        case .rapidExpress: return "快速急行"
        }
    }

    /// Fictional performance tiers for the game only; these are not real vehicle limits.
    public var nominalSpeedCapKmh: Double {
        switch self {
        case .limitedExpress: return 85
        case .rapidExpress: return 80
        case .express: return 72
        case .rapid: return 65
        case .semiExpress: return 55
        case .local: return 45
        }
    }

    public var passingPriority: Int {
        switch self {
        case .limitedExpress: return 6
        case .rapidExpress: return 5
        case .express: return 4
        case .rapid: return 3
        case .semiExpress: return 2
        case .local: return 1
        }
    }
}

public enum TimetablePeriod: String, Codable, CaseIterable, Equatable, Sendable {
    case morningRush
    case daytime
    case night

    public var japaneseName: String {
        switch self {
        case .morningRush: return "朝ラッシュ"
        case .daytime: return "昼間"
        case .night: return "夜"
        }
    }

    public var startSecondOfDay: Int {
        switch self {
        case .morningRush: return 6 * 3_600
        case .daytime: return 9 * 3_600
        case .night: return 19 * 3_600
        }
    }

    public var endSecondOfDay: Int {
        switch self {
        case .morningRush: return 9 * 3_600
        case .daytime: return 17 * 3_600
        case .night: return 24 * 3_600
        }
    }

    public func contains(departureSecond: Int) -> Bool {
        departureSecond >= startSecondOfDay && departureSecond < endSecondOfDay
    }
}

public struct FictionalRailwayStation: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let name: String
    public let hasPassingLoop: Bool
    public let passingLoopLengthM: Double?

    public init(id: String, name: String, hasPassingLoop: Bool = false,
                passingLoopLengthM: Double? = nil) throws {
        guard !id.isEmpty, !name.isEmpty,
              passingLoopLengthM.map({ $0.isFinite && $0 > 0 }) ?? true,
              passingLoopLengthM == nil || hasPassingLoop else {
            throw RailwaySignallingError.invalidValue("station id/name")
        }
        self.id = id
        self.name = name
        self.hasPassingLoop = hasPassingLoop
        self.passingLoopLengthM = passingLoopLengthM
    }
}

/// One physical corridor segment. The up/down track IDs may be equal for a fictional single-track section.
public struct FictionalRailwaySegment: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let fromStationID: String
    public let toStationID: String
    public let lengthM: Double
    /// Physical chainage on this continuous track family, increasing from `fromStationID` to `toStationID`.
    public let trackStartChainageM: Double
    public let upTrackID: String
    public let downTrackID: String
    public let branchID: String?

    public init(
        id: String,
        fromStationID: String,
        toStationID: String,
        lengthM: Double,
        trackStartChainageM: Double = 0,
        upTrackID: String,
        downTrackID: String,
        branchID: String? = nil
    ) throws {
        guard !id.isEmpty, !fromStationID.isEmpty, !toStationID.isEmpty,
              fromStationID != toStationID, lengthM.isFinite, lengthM > 0,
              trackStartChainageM.isFinite, trackStartChainageM >= 0,
              !upTrackID.isEmpty, !downTrackID.isEmpty else {
            throw RailwaySignallingError.invalidValue("network segment")
        }
        self.id = id
        self.fromStationID = fromStationID
        self.toStationID = toStationID
        self.lengthM = lengthM
        self.trackStartChainageM = trackStartChainageM
        self.upTrackID = upTrackID
        self.downTrackID = downTrackID
        self.branchID = branchID
    }

    public func trackID(for direction: ServiceDirection) -> String {
        direction == .up ? upTrackID : downTrackID
    }
}

/// A directed station-to-station path through one or more physical segments.
public struct FictionalServiceRoute: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let originStationID: String
    public let destinationStationID: String
    public let direction: ServiceDirection
    public let segmentIDs: [String]

    public init(id: String, originStationID: String, destinationStationID: String,
                direction: ServiceDirection, segmentIDs: [String]) throws {
        guard !id.isEmpty, !originStationID.isEmpty, !destinationStationID.isEmpty,
              originStationID != destinationStationID, !segmentIDs.isEmpty,
              Set(segmentIDs).count == segmentIDs.count else {
            throw RailwaySignallingError.invalidValue("service route")
        }
        self.id = id
        self.originStationID = originStationID
        self.destinationStationID = destinationStationID
        self.direction = direction
        self.segmentIDs = segmentIDs
    }
}

/// A fictional, validated route graph; lengths count each physical corridor once, not once per direction.
public struct FictionalRailwayNetwork: Codable, Equatable, Sendable {
    public let networkID: String
    public let stations: [FictionalRailwayStation]
    public let segments: [FictionalRailwaySegment]
    public let routes: [FictionalServiceRoute]
    public let dataStatus: FictionalDataStatus

    public init(networkID: String, stations: [FictionalRailwayStation],
                segments: [FictionalRailwaySegment], routes: [FictionalServiceRoute]) throws {
        guard !networkID.isEmpty, !stations.isEmpty, !segments.isEmpty, !routes.isEmpty else {
            throw RailwaySignallingError.emptyCollection("network/stations/segments/routes")
        }
        guard segments.reduce(0, { $0 + $1.lengthM }).isFinite else {
            throw RailwaySignallingError.invalidValue("network total track length")
        }
        guard Set(stations.map(\.id)).count == stations.count else {
            throw RailwaySignallingError.duplicateIdentifier("network station")
        }
        guard Set(segments.map(\.id)).count == segments.count else {
            throw RailwaySignallingError.duplicateIdentifier("network segment")
        }
        guard Set(routes.map(\.id)).count == routes.count else {
            throw RailwaySignallingError.duplicateIdentifier("service route")
        }
        let stationIDs = Set(stations.map(\.id))
        let segmentByID = Dictionary(uniqueKeysWithValues: segments.map { ($0.id, $0) })
        guard stations.allSatisfy({
            !$0.id.isEmpty && !$0.name.isEmpty &&
                ($0.passingLoopLengthM.map { $0.isFinite && $0 > 0 } ?? true) &&
                ($0.passingLoopLengthM == nil || $0.hasPassingLoop)
        }) else { throw RailwaySignallingError.invalidValue("station fields") }
        for segment in segments {
            guard !segment.id.isEmpty, !segment.fromStationID.isEmpty, !segment.toStationID.isEmpty,
                  segment.fromStationID != segment.toStationID, segment.lengthM.isFinite, segment.lengthM > 0,
                  segment.trackStartChainageM.isFinite, segment.trackStartChainageM >= 0,
                  (segment.trackStartChainageM + segment.lengthM).isFinite,
                  !segment.upTrackID.isEmpty, !segment.downTrackID.isEmpty,
                  (segment.branchID.map { !$0.isEmpty } ?? true) else {
                throw RailwaySignallingError.invalidValue("segment fields \(segment.id)")
            }
            guard stationIDs.contains(segment.fromStationID), stationIDs.contains(segment.toStationID) else {
                throw RailwaySignallingError.unknownIdentifier("segment station \(segment.id)")
            }
        }
        var segmentsByTrackID: [String: [FictionalRailwaySegment]] = [:]
        for segment in segments {
            segmentsByTrackID[segment.upTrackID, default: []].append(segment)
            if segment.downTrackID != segment.upTrackID {
                segmentsByTrackID[segment.downTrackID, default: []].append(segment)
            }
        }
        for (trackID, trackSegments) in segmentsByTrackID {
            let ordered = trackSegments.sorted { $0.trackStartChainageM < $1.trackStartChainageM }
            for index in 1..<ordered.count {
                let previous = ordered[index - 1]
                let current = ordered[index]
                guard abs(current.trackStartChainageM - (previous.trackStartChainageM + previous.lengthM)) <= 0.001 else {
                    throw RailwaySignallingError.invalidValue("track \(trackID) has discontinuous or overlapping chainage")
                }
            }
        }
        for route in routes {
            guard !route.id.isEmpty, !route.originStationID.isEmpty, !route.destinationStationID.isEmpty,
                  route.originStationID != route.destinationStationID, !route.segmentIDs.isEmpty,
                  Set(route.segmentIDs).count == route.segmentIDs.count else {
                throw RailwaySignallingError.invalidValue("route fields \(route.id)")
            }
            guard stationIDs.contains(route.originStationID), stationIDs.contains(route.destinationStationID) else {
                throw RailwaySignallingError.unknownIdentifier("route endpoint \(route.id)")
            }
            var currentStationID = route.originStationID
            var visitedStationIDs: Set<String> = [currentStationID]
            for segmentID in route.segmentIDs {
                guard let segment = segmentByID[segmentID] else {
                    throw RailwaySignallingError.unknownIdentifier("route segment \(segmentID)")
                }
                switch route.direction {
                case .up:
                    guard segment.fromStationID == currentStationID else {
                        throw RailwaySignallingError.invalidValue("up route \(route.id) is not contiguous")
                    }
                    currentStationID = segment.toStationID
                case .down:
                    guard segment.toStationID == currentStationID else {
                        throw RailwaySignallingError.invalidValue("down route \(route.id) is not contiguous")
                    }
                    currentStationID = segment.fromStationID
                }
                guard visitedStationIDs.insert(currentStationID).inserted else {
                    throw RailwaySignallingError.invalidValue("route \(route.id) repeats a station")
                }
            }
            guard currentStationID == route.destinationStationID else {
                throw RailwaySignallingError.invalidValue("route \(route.id) destination does not match its path")
            }
        }
        self.networkID = networkID
        self.stations = stations
        self.segments = segments
        self.routes = routes
        self.dataStatus = .placeholder
    }

    private enum CodingKeys: String, CodingKey {
        case networkID, stations, segments, routes, dataStatus
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(networkID: container.decode(String.self, forKey: .networkID),
                      stations: container.decode([FictionalRailwayStation].self, forKey: .stations),
                      segments: container.decode([FictionalRailwaySegment].self, forKey: .segments),
                      routes: container.decode([FictionalServiceRoute].self, forKey: .routes))
    }

    /// Sum of unique physical segments, excluding parallel directional track duplication.
    public var totalTrackLengthM: Double { segments.reduce(0) { $0 + $1.lengthM } }

    public func route(_ routeID: String) throws -> FictionalServiceRoute {
        guard let route = routes.first(where: { $0.id == routeID }) else {
            throw RailwaySignallingError.unknownIdentifier("service route \(routeID)")
        }
        return route
    }

    public func routeLengthM(_ routeID: String) throws -> Double {
        let route = try self.route(routeID)
        let byID = Dictionary(uniqueKeysWithValues: segments.map { ($0.id, $0) })
        return route.segmentIDs.reduce(0) { $0 + (byID[$1]?.lengthM ?? 0) }
    }

    public func routeSegments(_ routeID: String) throws -> [FictionalRailwaySegment] {
        let route = try self.route(routeID)
        let byID = Dictionary(uniqueKeysWithValues: segments.map { ($0.id, $0) })
        return try route.segmentIDs.map {
            guard let segment = byID[$0] else { throw RailwaySignallingError.unknownIdentifier("segment \($0)") }
            return segment
        }
    }

    public func stationSequence(_ routeID: String) throws -> [String] {
        let route = try self.route(routeID)
        let path = try routeSegments(routeID)
        var sequence = [route.originStationID]
        for segment in path {
            sequence.append(route.direction == .up ? segment.toStationID : segment.fromStationID)
        }
        return sequence
    }

    public func trackIDs(_ routeID: String) throws -> [String] {
        let route = try self.route(routeID)
        return try routeSegments(routeID).map { $0.trackID(for: route.direction) }
    }

    public func distanceFromOriginM(to stationID: String, on routeID: String) throws -> Double {
        let sequence = try stationSequence(routeID)
        guard let stationIndex = sequence.firstIndex(of: stationID) else {
            throw RailwaySignallingError.unknownIdentifier("station \(stationID) is not on route \(routeID)")
        }
        let path = try routeSegments(routeID)
        return path.prefix(stationIndex).reduce(0) { $0 + $1.lengthM }
    }

    public static func fictional70kmSample() throws -> FictionalRailwayNetwork {
        let stations = try [
            FictionalRailwayStation(id: "aoba", name: "青葉", hasPassingLoop: false),
            FictionalRailwayStation(id: "midoriba", name: "緑場", hasPassingLoop: true, passingLoopLengthM: 400),
            FictionalRailwayStation(id: "kuroishi", name: "黒石", hasPassingLoop: true, passingLoopLengthM: 450),
            FictionalRailwayStation(id: "minato", name: "湊", hasPassingLoop: true, passingLoopLengthM: 400),
            FictionalRailwayStation(id: "takane", name: "高嶺", hasPassingLoop: false),
            FictionalRailwayStation(id: "hoshizawa", name: "星沢", hasPassingLoop: true, passingLoopLengthM: 350),
            FictionalRailwayStation(id: "depot", name: "環雲車両基地", hasPassingLoop: false)
        ]
        let segments = try [
            FictionalRailwaySegment(id: "M1", fromStationID: "aoba", toStationID: "midoriba", lengthM: 12_000,
                                    trackStartChainageM: 0, upTrackID: "main-up", downTrackID: "main-down"),
            FictionalRailwaySegment(id: "M2", fromStationID: "midoriba", toStationID: "kuroishi", lengthM: 18_000,
                                    trackStartChainageM: 12_000, upTrackID: "main-up", downTrackID: "main-down"),
            FictionalRailwaySegment(id: "M3", fromStationID: "kuroishi", toStationID: "minato", lengthM: 15_000,
                                    trackStartChainageM: 30_000, upTrackID: "main-up", downTrackID: "main-down"),
            FictionalRailwaySegment(id: "M4", fromStationID: "minato", toStationID: "takane", lengthM: 15_000,
                                    trackStartChainageM: 45_000, upTrackID: "main-up", downTrackID: "main-down"),
            FictionalRailwaySegment(id: "B1", fromStationID: "takane", toStationID: "hoshizawa", lengthM: 8_000,
                                    trackStartChainageM: 0,
                                    upTrackID: "branch-up-1", downTrackID: "branch-down-1", branchID: "regional-branch"),
            FictionalRailwaySegment(id: "D1", fromStationID: "depot", toStationID: "aoba", lengthM: 2_000,
                                    trackStartChainageM: 0, upTrackID: "depot-spur", downTrackID: "depot-spur", branchID: "depot-spur")
        ]
        let routes = try [
            FictionalServiceRoute(id: "main-up", originStationID: "aoba", destinationStationID: "takane",
                                  direction: .up, segmentIDs: ["M1", "M2", "M3", "M4"]),
            FictionalServiceRoute(id: "main-down", originStationID: "takane", destinationStationID: "aoba",
                                  direction: .down, segmentIDs: ["M4", "M3", "M2", "M1"]),
            FictionalServiceRoute(id: "branch-up", originStationID: "aoba", destinationStationID: "hoshizawa",
                                  direction: .up, segmentIDs: ["M1", "M2", "M3", "M4", "B1"]),
            FictionalServiceRoute(id: "branch-down", originStationID: "hoshizawa", destinationStationID: "aoba",
                                  direction: .down, segmentIDs: ["B1", "M4", "M3", "M2", "M1"])
        ]
        return try FictionalRailwayNetwork(networkID: "fictional-70km-network", stations: stations,
                                           segments: segments, routes: routes)
    }
}

public struct ScheduledServiceStop: Codable, Equatable, Sendable {
    public let stationID: String
    public let arrivalOffsetSeconds: Int
    public let departureOffsetSeconds: Int

    public init(stationID: String, arrivalOffsetSeconds: Int, departureOffsetSeconds: Int) {
        self.stationID = stationID
        self.arrivalOffsetSeconds = arrivalOffsetSeconds
        self.departureOffsetSeconds = departureOffsetSeconds
    }
}

public struct RailwayServiceTrip: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let trainID: String
    public let serviceType: RailwayServiceType
    public let direction: ServiceDirection
    public let routeID: String
    public let period: TimetablePeriod
    /// Seconds after midnight; sample trips do not cross midnight.
    public let scheduledDepartureSeconds: Int
    public let scheduledArrivalSeconds: Int
    public let consistLengthM: Double
    public let stops: [ScheduledServiceStop]

    public var runDurationSeconds: Int { scheduledArrivalSeconds - scheduledDepartureSeconds }
    public var calledStationIDs: [String] { stops.map(\.stationID) }

    public init(id: String, trainID: String, serviceType: RailwayServiceType,
                direction: ServiceDirection, routeID: String, period: TimetablePeriod,
                scheduledDepartureSeconds: Int, scheduledArrivalSeconds: Int,
                consistLengthM: Double = 120,
                stops: [ScheduledServiceStop]) throws {
        guard !id.isEmpty, !trainID.isEmpty, !routeID.isEmpty, !stops.isEmpty,
              (0..<86_400).contains(scheduledDepartureSeconds),
              (0..<86_400).contains(scheduledArrivalSeconds),
              consistLengthM.isFinite, consistLengthM > 0,
              scheduledArrivalSeconds > scheduledDepartureSeconds else {
            throw RailwaySignallingError.invalidValue("service trip identity/time")
        }
        let duration = scheduledArrivalSeconds - scheduledDepartureSeconds
        guard duration >= 3_600 else {
            throw RailwaySignallingError.invalidValue("every service run must take at least 3600 seconds")
        }
        if serviceType == .local && duration > 9_000 {
            throw RailwaySignallingError.invalidValue("local service must not exceed 9000 seconds")
        }
        guard stops.count >= 2 else { throw RailwaySignallingError.invalidValue("service requires origin and destination stops") }
        var previousDeparture = -1
        for stop in stops {
            guard !stop.stationID.isEmpty, stop.arrivalOffsetSeconds >= 0,
                  stop.departureOffsetSeconds >= stop.arrivalOffsetSeconds,
                  stop.departureOffsetSeconds <= duration,
                  stop.arrivalOffsetSeconds >= previousDeparture else {
                throw RailwaySignallingError.invalidValue("service stop order/time")
            }
            previousDeparture = stop.departureOffsetSeconds
        }
        guard stops.first?.arrivalOffsetSeconds == 0,
              stops.first?.departureOffsetSeconds == 0,
              stops.last?.arrivalOffsetSeconds == duration,
              stops.last?.departureOffsetSeconds == duration else {
            throw RailwaySignallingError.invalidValue("service origin/destination time")
        }
        self.id = id
        self.trainID = trainID
        self.serviceType = serviceType
        self.direction = direction
        self.routeID = routeID
        self.period = period
        self.scheduledDepartureSeconds = scheduledDepartureSeconds
        self.scheduledArrivalSeconds = scheduledArrivalSeconds
        self.consistLengthM = consistLengthM
        self.stops = stops
    }

    private enum CodingKeys: String, CodingKey {
        case id, trainID, serviceType, direction, routeID, period
        case scheduledDepartureSeconds, scheduledArrivalSeconds, consistLengthM, stops
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(id: container.decode(String.self, forKey: .id),
                      trainID: container.decode(String.self, forKey: .trainID),
                      serviceType: container.decode(RailwayServiceType.self, forKey: .serviceType),
                      direction: container.decode(ServiceDirection.self, forKey: .direction),
                      routeID: container.decode(String.self, forKey: .routeID),
                      period: container.decode(TimetablePeriod.self, forKey: .period),
                      scheduledDepartureSeconds: container.decode(Int.self, forKey: .scheduledDepartureSeconds),
                      scheduledArrivalSeconds: container.decode(Int.self, forKey: .scheduledArrivalSeconds),
                      consistLengthM: container.decodeIfPresent(Double.self, forKey: .consistLengthM) ?? 120,
                      stops: container.decode([ScheduledServiceStop].self, forKey: .stops))
    }
}

public struct FictionalDepot: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let stationID: String
    public let leadTrackID: String

    public init(id: String, stationID: String, leadTrackID: String) throws {
        guard !id.isEmpty, !stationID.isEmpty, !leadTrackID.isEmpty else {
            throw RailwaySignallingError.invalidValue("depot")
        }
        self.id = id
        self.stationID = stationID
        self.leadTrackID = leadTrackID
    }
}

public enum DepotMovementKind: String, Codable, CaseIterable, Equatable, Sendable {
    case enterDepot
    case exitDepot
}

public struct DepotMovement: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let trainID: String
    public let depotID: String
    public let kind: DepotMovementKind
    public let scheduledStartSeconds: Int
    public let durationSeconds: Int

    public var scheduledEndSeconds: Int { scheduledStartSeconds + durationSeconds }

    public init(id: String, trainID: String, depotID: String, kind: DepotMovementKind,
                scheduledStartSeconds: Int, durationSeconds: Int) throws {
        guard !id.isEmpty, !trainID.isEmpty, !depotID.isEmpty,
              (0..<86_400).contains(scheduledStartSeconds), durationSeconds > 0,
              durationSeconds <= 86_400 - scheduledStartSeconds else {
            throw RailwaySignallingError.invalidValue("depot movement")
        }
        self.id = id
        self.trainID = trainID
        self.depotID = depotID
        self.kind = kind
        self.scheduledStartSeconds = scheduledStartSeconds
        self.durationSeconds = durationSeconds
    }

    private enum CodingKeys: String, CodingKey {
        case id, trainID, depotID, kind, scheduledStartSeconds, durationSeconds
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(id: container.decode(String.self, forKey: .id),
                      trainID: container.decode(String.self, forKey: .trainID),
                      depotID: container.decode(String.self, forKey: .depotID),
                      kind: container.decode(DepotMovementKind.self, forKey: .kind),
                      scheduledStartSeconds: container.decode(Int.self, forKey: .scheduledStartSeconds),
                      durationSeconds: container.decode(Int.self, forKey: .durationSeconds))
    }
}

/// Validates planned service patterns against the fictional network and its directed route paths.
public struct RailwayServiceTimetable: Codable, Equatable, Sendable {
    public let network: FictionalRailwayNetwork
    public let services: [RailwayServiceTrip]
    public let depots: [FictionalDepot]
    public let depotMovements: [DepotMovement]
    public let timeZoneIdentifier: String
    public let dataStatus: FictionalDataStatus

    public init(network: FictionalRailwayNetwork, services: [RailwayServiceTrip],
                depots: [FictionalDepot] = [], depotMovements: [DepotMovement] = [],
                timeZoneIdentifier: String = "Asia/Tokyo") throws {
        guard !services.isEmpty else { throw RailwaySignallingError.emptyCollection("service timetable") }
        guard TimeZone(identifier: timeZoneIdentifier) != nil else {
            throw RailwaySignallingError.invalidValue("timetable time zone")
        }
        try Self.requireUnique(services.map(\.id), name: "service")
        try Self.requireUnique(depots.map(\.id), name: "depot")
        try Self.requireUnique(depotMovements.map(\.id), name: "depot movement")
        let stationIDs = Set(network.stations.map(\.id))
        let depotByID = Dictionary(uniqueKeysWithValues: depots.map { ($0.id, $0) })
        for depot in depots {
            guard !depot.id.isEmpty, !depot.leadTrackID.isEmpty else {
                throw RailwaySignallingError.invalidValue("depot fields")
            }
            guard stationIDs.contains(depot.stationID) else {
                throw RailwaySignallingError.unknownIdentifier("depot station \(depot.stationID)")
            }
        }
        for service in services {
            guard (0..<86_400).contains(service.scheduledDepartureSeconds),
                  (0..<86_400).contains(service.scheduledArrivalSeconds),
                  service.scheduledArrivalSeconds > service.scheduledDepartureSeconds else {
                throw RailwaySignallingError.invalidValue("service scheduled time range")
            }
            let duration = service.scheduledArrivalSeconds - service.scheduledDepartureSeconds
            guard !service.id.isEmpty, !service.trainID.isEmpty, duration >= 3_600,
                  service.consistLengthM.isFinite, service.consistLengthM > 0,
                  service.stops.count >= 2,
                  service.serviceType != .local || duration <= 9_000 else {
                throw RailwaySignallingError.invalidValue("service trip fields/duration")
            }
            let route = try network.route(service.routeID)
            guard route.direction == service.direction else {
                throw RailwaySignallingError.invalidValue("service direction does not match route \(route.id)")
            }
            guard service.period.contains(departureSecond: service.scheduledDepartureSeconds) else {
                throw RailwaySignallingError.invalidValue("service departure is outside period \(service.period.rawValue)")
            }
            let stationSequence = try network.stationSequence(service.routeID)
            var previousStopDeparture = -1
            for stop in service.stops {
                guard !stop.stationID.isEmpty, stop.arrivalOffsetSeconds >= 0,
                      stop.departureOffsetSeconds >= stop.arrivalOffsetSeconds,
                      stop.departureOffsetSeconds <= duration,
                      stop.arrivalOffsetSeconds >= previousStopDeparture else {
                    throw RailwaySignallingError.invalidValue("service stop time order")
                }
                previousStopDeparture = stop.departureOffsetSeconds
            }
            guard service.stops.first?.arrivalOffsetSeconds == 0,
                  service.stops.first?.departureOffsetSeconds == 0,
                  service.stops.last?.arrivalOffsetSeconds == duration,
                  service.stops.last?.departureOffsetSeconds == duration else {
                throw RailwaySignallingError.invalidValue("service endpoint times")
            }
            guard service.stops.first?.stationID == stationSequence.first,
                  service.stops.last?.stationID == stationSequence.last else {
                throw RailwaySignallingError.invalidValue("service stops must include route origin and destination")
            }
            var previousIndex = -1
            for stop in service.stops {
                guard stationIDs.contains(stop.stationID), let index = stationSequence.firstIndex(of: stop.stationID),
                      index > previousIndex else {
                    throw RailwaySignallingError.invalidValue("service stops are not in route order")
                }
                previousIndex = index
            }
            if service.serviceType == .local && service.calledStationIDs != stationSequence {
                throw RailwaySignallingError.invalidValue("local service must stop at every route station")
            }
        }

        for i in services.indices {
            for j in services.indices where j > i && services[i].trainID == services[j].trainID {
                let first = services[i]
                let second = services[j]
                let overlaps = first.scheduledDepartureSeconds < second.scheduledArrivalSeconds &&
                    second.scheduledDepartureSeconds < first.scheduledArrivalSeconds
                if overlaps { throw RailwaySignallingError.conflictingRoute("one train has overlapping service trips") }
            }
        }

        for movement in depotMovements {
            guard !movement.id.isEmpty, !movement.trainID.isEmpty,
                  (0..<86_400).contains(movement.scheduledStartSeconds), movement.durationSeconds > 0,
                  movement.durationSeconds <= 86_400 - movement.scheduledStartSeconds else {
                throw RailwaySignallingError.invalidValue("depot movement fields/time")
            }
            guard let depot = depotByID[movement.depotID] else {
                throw RailwaySignallingError.unknownIdentifier("depot \(movement.depotID)")
            }
            let relatedServices = services.filter { $0.trainID == movement.trainID }
            guard !relatedServices.isEmpty else {
                throw RailwaySignallingError.unknownIdentifier("depot train \(movement.trainID)")
            }
            for service in relatedServices where
                movement.scheduledStartSeconds < service.scheduledArrivalSeconds &&
                service.scheduledDepartureSeconds < movement.scheduledEndSeconds {
                throw RailwaySignallingError.conflictingRoute("depot movement overlaps service \(service.id)")
            }
            switch movement.kind {
            case .exitDepot:
                let hasNextTrip = relatedServices.contains { service in
                    let route = try? network.route(service.routeID)
                    return route?.originStationID == depot.stationID && service.scheduledDepartureSeconds >= movement.scheduledEndSeconds
                }
                guard hasNextTrip else {
                    throw RailwaySignallingError.conflictingRoute("exit-depot movement must precede a trip from the depot station")
                }
            case .enterDepot:
                let hasPreviousTrip = relatedServices.contains { service in
                    let route = try? network.route(service.routeID)
                    return route?.destinationStationID == depot.stationID && service.scheduledArrivalSeconds <= movement.scheduledStartSeconds
                }
                guard hasPreviousTrip else {
                    throw RailwaySignallingError.conflictingRoute("enter-depot movement must follow a trip arriving at the depot station")
                }
            }
        }
        for i in depotMovements.indices {
            for j in depotMovements.indices where j > i {
                let first = depotMovements[i]
                let second = depotMovements[j]
                let overlap = first.scheduledStartSeconds < second.scheduledEndSeconds &&
                    second.scheduledStartSeconds < first.scheduledEndSeconds
                if overlap && (first.trainID == second.trainID || first.depotID == second.depotID) {
                    throw RailwaySignallingError.conflictingRoute("overlapping depot movements")
                }
            }
        }
        self.network = network
        self.services = services
        self.depots = depots
        self.depotMovements = depotMovements
        self.timeZoneIdentifier = timeZoneIdentifier
        self.dataStatus = .placeholder
    }

    private enum CodingKeys: String, CodingKey {
        case network, services, depots, depotMovements, timeZoneIdentifier, dataStatus
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(network: container.decode(FictionalRailwayNetwork.self, forKey: .network),
                      services: container.decode([RailwayServiceTrip].self, forKey: .services),
                      depots: container.decodeIfPresent([FictionalDepot].self, forKey: .depots) ?? [],
                      depotMovements: container.decodeIfPresent([DepotMovement].self, forKey: .depotMovements) ?? [],
                      timeZoneIdentifier: container.decodeIfPresent(String.self, forKey: .timeZoneIdentifier) ?? "Asia/Tokyo")
    }

    public static func fictional70kmSample(network: FictionalRailwayNetwork) throws -> RailwayServiceTimetable {
        func stop(_ id: String, _ arrival: Int, _ departure: Int? = nil) -> ScheduledServiceStop {
            ScheduledServiceStop(stationID: id, arrivalOffsetSeconds: arrival,
                                 departureOffsetSeconds: departure ?? arrival)
        }
        let services = try [
            RailwayServiceTrip(id: "express-main-up-am", trainID: "EMU-101", serviceType: .express,
                               direction: .up, routeID: "main-up", period: .morningRush,
                               scheduledDepartureSeconds: 6 * 3_600 + 10 * 60,
                               scheduledArrivalSeconds: 7 * 3_600 + 15 * 60,
                               stops: [stop("aoba", 0), stop("kuroishi", 2_300, 2_360), stop("takane", 3_900)]),
            RailwayServiceTrip(id: "limited-express-branch-am", trainID: "EMU-201", serviceType: .limitedExpress,
                               direction: .up, routeID: "branch-up", period: .morningRush,
                               scheduledDepartureSeconds: 6 * 3_600 + 30 * 60,
                               scheduledArrivalSeconds: 7 * 3_600 + 40 * 60,
                               stops: [stop("aoba", 0), stop("kuroishi", 2_500, 2_580), stop("hoshizawa", 4_200)]),
            RailwayServiceTrip(id: "semi-express-branch-am", trainID: "EMU-301", serviceType: .semiExpress,
                               direction: .down, routeID: "branch-down", period: .morningRush,
                               scheduledDepartureSeconds: 7 * 3_600 + 10 * 60,
                               scheduledArrivalSeconds: 8 * 3_600 + 25 * 60,
                               stops: [stop("hoshizawa", 0), stop("kuroishi", 2_800, 2_860),
                                       stop("midoriba", 3_600, 3_640), stop("aoba", 4_500)]),
            RailwayServiceTrip(id: "local-main-down-am", trainID: "EMU-401", serviceType: .local,
                               direction: .down, routeID: "main-down", period: .morningRush,
                               scheduledDepartureSeconds: 6 * 3_600,
                               scheduledArrivalSeconds: 8 * 3_600 + 30 * 60,
                               stops: [stop("takane", 0), stop("minato", 1_700, 1_740),
                                       stop("kuroishi", 3_650, 3_710), stop("midoriba", 5_400, 5_440),
                                       stop("aoba", 9_000)]),
            RailwayServiceTrip(id: "rapid-main-up-day", trainID: "EMU-501", serviceType: .rapid,
                               direction: .up, routeID: "main-up", period: .daytime,
                               scheduledDepartureSeconds: 12 * 3_600 + 20 * 60,
                               scheduledArrivalSeconds: 13 * 3_600 + 25 * 60,
                               stops: [stop("aoba", 0), stop("midoriba", 1_500, 1_540),
                                       stop("minato", 3_000, 3_040), stop("takane", 3_900)]),
            RailwayServiceTrip(id: "rapid-express-branch-night", trainID: "EMU-601", serviceType: .rapidExpress,
                               direction: .down, routeID: "branch-down", period: .night,
                               scheduledDepartureSeconds: 21 * 3_600,
                               scheduledArrivalSeconds: 22 * 3_600 + 5 * 60,
                               stops: [stop("hoshizawa", 0), stop("kuroishi", 2_200, 2_230), stop("aoba", 3_900)])
        ]
        let depots = try [
            FictionalDepot(id: "aoba-depot", stationID: "aoba", leadTrackID: "depot-aoba-lead"),
            FictionalDepot(id: "takane-depot", stationID: "takane", leadTrackID: "depot-takane-lead")
        ]
        let depotMovements = try [
            DepotMovement(id: "EMU-101-exit", trainID: "EMU-101", depotID: "aoba-depot", kind: .exitDepot,
                          scheduledStartSeconds: 5 * 3_600 + 50 * 60, durationSeconds: 600),
            DepotMovement(id: "EMU-401-exit", trainID: "EMU-401", depotID: "takane-depot", kind: .exitDepot,
                          scheduledStartSeconds: 5 * 3_600 + 35 * 60, durationSeconds: 900),
            DepotMovement(id: "EMU-401-enter", trainID: "EMU-401", depotID: "aoba-depot", kind: .enterDepot,
                          scheduledStartSeconds: 8 * 3_600 + 40 * 60, durationSeconds: 900)
        ]
        return try RailwayServiceTimetable(network: network, services: services,
                                           depots: depots, depotMovements: depotMovements)
    }

    private static func requireUnique(_ ids: [String], name: String) throws {
        guard Set(ids).count == ids.count else { throw RailwaySignallingError.duplicateIdentifier(name) }
    }
}

public struct ServiceTrainPosition: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let serviceType: RailwayServiceType
    public let routeID: String
    public let segmentID: String
    public let trackID: String
    public let direction: ServiceDirection
    /// Physical track chainage; increases from segment.fromStation to segment.toStation even for down trains.
    public let frontPositionM: Double
    public let speedMps: Double
    public let trainLengthM: Double

    public init(id: String, serviceType: RailwayServiceType, routeID: String, segmentID: String,
                trackID: String, direction: ServiceDirection, frontPositionM: Double,
                speedMps: Double, trainLengthM: Double) throws {
        guard !id.isEmpty, !routeID.isEmpty, !segmentID.isEmpty, !trackID.isEmpty,
              frontPositionM.isFinite, frontPositionM >= 0, speedMps.isFinite, speedMps >= 0,
              trainLengthM.isFinite, trainLengthM > 0 else {
            throw RailwaySignallingError.invalidValue("service train position")
        }
        self.id = id
        self.serviceType = serviceType
        self.routeID = routeID
        self.segmentID = segmentID
        self.trackID = trackID
        self.direction = direction
        self.frontPositionM = frontPositionM
        self.speedMps = speedMps
        self.trainLengthM = trainLengthM
    }
}

public enum FollowingStatus: String, Codable, Equatable, Sendable {
    case separateTrack
    case opposingDirectionConflict
    case routeConflictRequiresStop
    case noLeaderAhead
    case followingEnvelope
    case brakingRequired
}

public struct FollowingAssessment: Codable, Equatable, Sendable {
    public let followerID: String
    public let leaderID: String
    public let status: FollowingStatus
    public let gapM: Double?
    public let permittedFollowerSpeedMps: Double?
    public let label: FictionalDataStatus
}

public struct OvertakeAssessment: Codable, Equatable, Sendable {
    public let isAllowed: Bool
    public let passingStationID: String?
    public let reason: String
    public let label: FictionalDataStatus
}

/// Service-aware, direction-aware safety envelope and passing-loop assessment for the fictional timetable.
public struct ServiceTrafficController: Sendable {
    public let network: FictionalRailwayNetwork
    public let minimumSeparationM: Double
    public let serviceDecelerationMps2: Double

    public init(network: FictionalRailwayNetwork, minimumSeparationM: Double = 30,
                serviceDecelerationMps2: Double = 0.8) throws {
        guard minimumSeparationM.isFinite, minimumSeparationM >= 0,
              serviceDecelerationMps2.isFinite, serviceDecelerationMps2 > 0 else {
            throw RailwaySignallingError.invalidValue("service separation/deceleration")
        }
        self.network = network
        self.minimumSeparationM = minimumSeparationM
        self.serviceDecelerationMps2 = serviceDecelerationMps2
    }

    /// Calculates a conservative following envelope only for trains on the same directed track.
    public func assessFollowing(follower: ServiceTrainPosition, leader: ServiceTrainPosition) throws -> FollowingAssessment {
        guard follower.id != leader.id else { throw RailwaySignallingError.invalidValue("follower and leader must differ") }
        try validateOnNetwork(follower)
        try validateOnNetwork(leader)
        if follower.trackID != leader.trackID {
            let followerOccupancy = try occupiedTrackBySegment(for: follower)
            let leaderOccupancy = try occupiedTrackBySegment(for: leader)
            let sharedTrackOverlap = followerOccupancy.contains { entry in
                leaderOccupancy[entry.key] == entry.value
            }
            if sharedTrackOverlap {
                let status: FollowingStatus = follower.direction == leader.direction
                    ? .routeConflictRequiresStop : .opposingDirectionConflict
                return FollowingAssessment(followerID: follower.id, leaderID: leader.id, status: status,
                                           gapM: nil, permittedFollowerSpeedMps: 0, label: .placeholder)
            }
            return FollowingAssessment(followerID: follower.id, leaderID: leader.id, status: .separateTrack,
                                       gapM: nil, permittedFollowerSpeedMps: follower.serviceType.nominalSpeedCapKmh / 3.6,
                                       label: .placeholder)
        }
        if follower.direction != leader.direction {
            return FollowingAssessment(followerID: follower.id, leaderID: leader.id,
                                       status: .opposingDirectionConflict, gapM: nil,
                                       permittedFollowerSpeedMps: 0, label: .placeholder)
        }

        let leaderIsAhead: Bool
        let gap: Double
        switch follower.direction {
        case .up:
            leaderIsAhead = leader.frontPositionM >= follower.frontPositionM
            gap = leader.frontPositionM - leader.trainLengthM - follower.frontPositionM
        case .down:
            leaderIsAhead = leader.frontPositionM <= follower.frontPositionM
            gap = follower.frontPositionM - (leader.frontPositionM + leader.trainLengthM)
        }
        guard leaderIsAhead else {
            return FollowingAssessment(followerID: follower.id, leaderID: leader.id, status: .noLeaderAhead,
                                       gapM: nil, permittedFollowerSpeedMps: follower.serviceType.nominalSpeedCapKmh / 3.6,
                                       label: .placeholder)
        }
        let availableDistance = max(0, gap - minimumSeparationM)
        let kinematicCap = sqrt(max(0, leader.speedMps * leader.speedMps +
                                    2 * serviceDecelerationMps2 * availableDistance))
        let serviceTypeCap = follower.serviceType.nominalSpeedCapKmh / 3.6
        let permitted = gap <= 0 ? 0 : min(serviceTypeCap, kinematicCap)
        let status: FollowingStatus = gap < minimumSeparationM || follower.speedMps > permitted
            ? .brakingRequired : .followingEnvelope
        return FollowingAssessment(followerID: follower.id, leaderID: leader.id, status: status,
                                   gapM: gap, permittedFollowerSpeedMps: permitted, label: .placeholder)
    }

    /// A passing candidate is only approved when the caller confirms the loop and interlocking are clear.
    public func assessOvertake(follower: RailwayServiceTrip, leader: RailwayServiceTrip,
                               passingLoopClear: Bool = false,
                               junctionRouteLockAvailable: Bool = false,
                               opposingMovementClear: Bool = false) throws -> OvertakeAssessment {
        guard follower.direction == leader.direction else {
            return OvertakeAssessment(isAllowed: false, passingStationID: nil,
                                      reason: "上下方向が異なるため追越し候補ではありません。", label: .placeholder)
        }
        guard follower.serviceType.passingPriority > leader.serviceType.passingPriority else {
            return OvertakeAssessment(isAllowed: false, passingStationID: nil,
                                      reason: "後続列車の種別優先度が先行列車を上回りません。", label: .placeholder)
        }
        let followerRoute = try network.route(follower.routeID)
        let leaderRoute = try network.route(leader.routeID)
        guard followerRoute.direction == follower.direction, leaderRoute.direction == leader.direction else {
            throw RailwaySignallingError.invalidValue("service direction/route mismatch")
        }
        let followerStations = try network.stationSequence(follower.routeID)
        let leaderStations = try network.stationSequence(leader.routeID)
        let sharedSegments = Set(followerRoute.segmentIDs).intersection(leaderRoute.segmentIDs)
        guard !sharedSegments.isEmpty else {
            return OvertakeAssessment(isAllowed: false, passingStationID: nil,
                                      reason: "同じ線路区間を共有しません。", label: .placeholder)
        }
        let leaderCalls = Set(leader.calledStationIDs)
        let stationByID = Dictionary(uniqueKeysWithValues: network.stations.map { ($0.id, $0) })
        var candidate: FictionalRailwayStation?
        for (followerIndex, stationID) in followerStations.enumerated() {
            guard let station = stationByID[stationID], station.hasPassingLoop,
                  let loopLength = station.passingLoopLengthM,
                  loopLength >= follower.consistLengthM + leader.consistLengthM + minimumSeparationM,
                  leaderCalls.contains(stationID),
                  let leaderIndex = leaderStations.firstIndex(of: stationID),
                  followerIndex > 0, leaderIndex > 0 else { continue }
            let followerApproach = Set(followerRoute.segmentIDs.prefix(followerIndex))
            let leaderApproach = Set(leaderRoute.segmentIDs.prefix(leaderIndex))
            guard !followerApproach.intersection(leaderApproach).isEmpty,
                  let leaderStop = leader.stops.first(where: { $0.stationID == stationID }),
                  leaderStop.departureOffsetSeconds > leaderStop.arrivalOffsetSeconds else { continue }

            let followerPassage = try plannedPassageTime(follower, at: stationID)
            let leaderArrival = Double(leader.scheduledDepartureSeconds + leaderStop.arrivalOffsetSeconds)
            let leaderDeparture = Double(leader.scheduledDepartureSeconds + leaderStop.departureOffsetSeconds)
            guard followerPassage >= leaderArrival, followerPassage < leaderDeparture else { continue }
            candidate = station
            break
        }
        guard let candidate else {
            return OvertakeAssessment(isAllowed: false, passingStationID: nil,
                                      reason: "共通経路の時刻窓に、編成を収容できる待避線付き停車駅がありません。", label: .placeholder)
        }
        guard passingLoopClear else {
            return OvertakeAssessment(isAllowed: false, passingStationID: candidate.id,
                                      reason: "待避線の在線確認が未完了です。", label: .placeholder)
        }
        guard junctionRouteLockAvailable else {
            return OvertakeAssessment(isAllowed: false, passingStationID: candidate.id,
                                      reason: "分岐器・進路のロック確認が未完了です。", label: .placeholder)
        }
        guard opposingMovementClear else {
            return OvertakeAssessment(isAllowed: false, passingStationID: candidate.id,
                                      reason: "反対方向の進路競合確認が未完了です。", label: .placeholder)
        }
        return OvertakeAssessment(isAllowed: true, passingStationID: candidate.id,
                                  reason: "種別差・到着時刻・待避線長・在線・進路ロックを確認した仮想追越し候補です。", label: .placeholder)
    }

    private func plannedPassageTime(_ trip: RailwayServiceTrip, at stationID: String) throws -> Double {
        if let stop = trip.stops.first(where: { $0.stationID == stationID }) {
            return Double(trip.scheduledDepartureSeconds + stop.arrivalOffsetSeconds)
        }
        let stationSequence = try network.stationSequence(trip.routeID)
        guard let targetIndex = stationSequence.firstIndex(of: stationID) else {
            throw RailwaySignallingError.unknownIdentifier("passing station \(stationID)")
        }
        let indexedStops = trip.stops.compactMap { stop -> (index: Int, value: ScheduledServiceStop)? in
            guard let index = stationSequence.firstIndex(of: stop.stationID) else { return nil }
            return (index, stop)
        }
        guard let previous = indexedStops.last(where: { $0.index < targetIndex }),
              let next = indexedStops.first(where: { $0.index > targetIndex }) else {
            throw RailwaySignallingError.invalidValue("cannot bracket planned passage time")
        }
        let previousDistance = try network.distanceFromOriginM(to: previous.value.stationID, on: trip.routeID)
        let nextDistance = try network.distanceFromOriginM(to: next.value.stationID, on: trip.routeID)
        let targetDistance = try network.distanceFromOriginM(to: stationID, on: trip.routeID)
        guard nextDistance > previousDistance else {
            throw RailwaySignallingError.invalidValue("non-increasing route distance")
        }
        let fraction = (targetDistance - previousDistance) / (nextDistance - previousDistance)
        let startTime = Double(trip.scheduledDepartureSeconds + previous.value.departureOffsetSeconds)
        let endTime = Double(trip.scheduledDepartureSeconds + next.value.arrivalOffsetSeconds)
        return startTime + (endTime - startTime) * fraction
    }

    /// Includes every route segment touched by the train's full length, including a branch/junction boundary.
    private func occupiedTrackBySegment(for train: ServiceTrainPosition) throws -> [String: String] {
        let route = try network.route(train.routeID)
        let segments = try network.routeSegments(train.routeID)
        guard let activeIndex = route.segmentIDs.firstIndex(of: train.segmentID) else {
            throw RailwaySignallingError.unknownIdentifier("train segment on route")
        }
        let active = segments[activeIndex]
        let distanceIntoActive: Double
        switch train.direction {
        case .up:
            distanceIntoActive = train.frontPositionM - active.trackStartChainageM
        case .down:
            distanceIntoActive = active.trackStartChainageM + active.lengthM - train.frontPositionM
        }
        let frontRouteDistance = segments.prefix(activeIndex).reduce(0) { $0 + $1.lengthM } + distanceIntoActive
        let rearRouteDistance = max(0, frontRouteDistance - train.trainLengthM)
        var occupied: [String: String] = [:]
        var segmentStart = 0.0
        for segment in segments {
            let segmentEnd = segmentStart + segment.lengthM
            if segmentEnd >= rearRouteDistance && segmentStart <= frontRouteDistance {
                occupied[segment.id] = segment.trackID(for: train.direction)
            }
            segmentStart = segmentEnd
        }
        return occupied
    }

    private func validateOnNetwork(_ train: ServiceTrainPosition) throws {
        let route = try network.route(train.routeID)
        guard !train.id.isEmpty, train.frontPositionM.isFinite,
              train.speedMps.isFinite, train.speedMps >= 0,
              train.trainLengthM.isFinite, train.trainLengthM > 0,
              route.direction == train.direction, route.segmentIDs.contains(train.segmentID),
              let segment = network.segments.first(where: { $0.id == train.segmentID }),
              segment.trackID(for: train.direction) == train.trackID,
              train.frontPositionM >= segment.trackStartChainageM - 0.001,
              train.frontPositionM <= segment.trackStartChainageM + segment.lengthM + 0.001 else {
            throw RailwaySignallingError.invalidValue("train route/track/direction/position mismatch")
        }
    }
}
