import Foundation

/// Provenance state for a single route-data value. Never infer this from whether a value is present.
public enum AccuracyStatus: String, Codable, CaseIterable, Sendable {
    case verified = "VERIFIED"
    case measured = "MEASURED"
    case estimated = "ESTIMATED"
    case placeholder = "PLACEHOLDER"
    case unknown = "UNKNOWN"
}

public enum Confidence: String, Codable, Sendable {
    case high = "HIGH"
    case medium = "MEDIUM"
    case low = "LOW"
    case unrated = "UNRATED"
}

/// A value together with item-level quality and source references.
public struct Evidence<Value: Codable & Sendable>: Codable, Sendable {
    public let value: Value?
    public let status: AccuracyStatus
    public let sourceIDs: [String]
    /// Absolute uncertainty in the value's native unit, where meaningful.
    public let uncertainty: Double?
    public let confidence: Confidence
    public let note: String?

    public init(
        value: Value?,
        status: AccuracyStatus,
        sourceIDs: [String] = [],
        uncertainty: Double? = nil,
        confidence: Confidence = .unrated,
        note: String? = nil
    ) {
        self.value = value
        self.status = status
        self.sourceIDs = sourceIDs
        self.uncertainty = uncertainty
        self.confidence = confidence
        self.note = note
    }
}

public struct SourceMetadata: Codable, Sendable {
    public let sourceID: String
    public let title: String
    public let publisher: String
    public let url: String?
    /// ISO-8601 date string; stored as text to keep source dates stable across encoders.
    public let accessedAt: String?
    public let publishedAt: String?
    public let license: String
    public let attribution: String?
    public let usageNotes: String?
    public let reliabilityNotes: String?
}

public struct GeoCoordinate: Codable, Sendable {
    public let latitudeDeg: Double
    public let longitudeDeg: Double
    public let elevationM: Double?

    public init(latitudeDeg: Double, longitudeDeg: Double, elevationM: Double? = nil) {
        self.latitudeDeg = latitudeDeg
        self.longitudeDeg = longitudeDeg
        self.elevationM = elevationM
    }
}

public struct PositionSample: Codable, Sendable {
    public let chainageM: Evidence<Double>
    public let coordinate: Evidence<GeoCoordinate>
}

public enum TravelDirection: String, Codable, Sendable {
    case increasingChainage = "INCREASING_CHAINAGE"
    case decreasingChainage = "DECREASING_CHAINAGE"
    case both = "BOTH"
    case unknown = "UNKNOWN"
}

public enum AlignmentKind: String, Codable, Sendable {
    case tangent = "TANGENT"
    case circularCurve = "CIRCULAR_CURVE"
    case transitionCurve = "TRANSITION_CURVE"
    case unknown = "UNKNOWN"
}

public enum TrackStructureKind: String, Codable, Sendable {
    case ballasted = "BALLASTED"
    case slab = "SLAB"
    case mixed = "MIXED"
    case unknown = "UNKNOWN"
}

public struct TrackSegment: Codable, Sendable {
    public let segmentID: String
    public let startChainageM: Evidence<Double>
    public let endChainageM: Evidence<Double>
    public let alignment: Evidence<AlignmentKind>
    public let curveRadiusM: Evidence<Double>
    public let transitionLengthM: Evidence<Double>
    public let cantMM: Evidence<Double>
    public let cantTransitionLengthM: Evidence<Double>
    public let gradientPermille: Evidence<Double>
    public let speedLimitKmh: Evidence<Double>
    public let trackStructure: Evidence<TrackStructureKind>
    public let railProfile: Evidence<String>
    public let sleeperType: Evidence<String>
    public let longWeldedRail: Evidence<Bool>
    public let notes: String?
}

public struct Track: Codable, Sendable {
    public let trackID: String
    public let name: Evidence<String>
    public let direction: Evidence<TravelDirection>
    public let gaugeMM: Evidence<Double>
    public let centerSpacingMM: Evidence<Double>
    public let geometry: [PositionSample]
    public let segments: [TrackSegment]
    /// When true, validation expects contiguous signal-block coverage over this track's route extent.
    public let blockCoverageRequired: Bool
}

public struct Platform: Codable, Sendable {
    public let platformID: String
    public let trackID: String
    public let trackSide: Evidence<String>
    public let startChainageM: Evidence<Double>
    public let endChainageM: Evidence<Double>
    public let lengthM: Evidence<Double>
    public let widthM: Evidence<Double>
    public let heightAboveRailM: Evidence<Double>
    public let alignment: Evidence<AlignmentKind>
    public let gradientPermille: Evidence<Double>
    public let hasPlatformDoors: Evidence<Bool>
    public let roofType: Evidence<String>
    public let stationBuildingPosition: Evidence<GeoCoordinate>
    public let equipmentNotes: Evidence<String>
}

public struct Station: Codable, Sendable {
    public let stationID: String
    public let name: Evidence<String>
    public let chainageM: Evidence<Double>
    public let stopPositionChainageM: Evidence<Double>
    public let location: Evidence<GeoCoordinate>
    public let trackIDs: [String]
    public let platforms: [Platform]
    public let trackLayoutNotes: Evidence<String>
}

public enum RestrictionKind: String, Codable, Sendable {
    case permanent = "PERMANENT"
    case curve = "CURVE"
    case turnout = "TURNOUT"
    case station = "STATION"
    case temporary = "TEMPORARY"
    case workZone = "WORK_ZONE"
    case signal = "SIGNAL"
    case vehicleSpecific = "VEHICLE_SPECIFIC"
    case other = "OTHER"
}

public struct SpeedRestriction: Codable, Sendable {
    public let restrictionID: String
    public let trackID: String
    public let startChainageM: Evidence<Double>
    public let endChainageM: Evidence<Double>
    public let limitKmh: Evidence<Double>
    public let kind: Evidence<RestrictionKind>
    public let direction: Evidence<TravelDirection>
    public let appliesToVehicleIDs: [String]
    public let signChainageM: Evidence<Double>
    public let description: Evidence<String>
}

public enum SignalKind: String, Codable, Sendable {
    case home = "HOME"
    case departure = "DEPARTURE"
    case block = "BLOCK"
    case repeater = "REPEATER"
    case shunting = "SHUNTING"
    case routeIndicator = "ROUTE_INDICATOR"
    case other = "OTHER"
    case unknown = "UNKNOWN"
}

public struct Signal: Codable, Sendable {
    public let signalID: String
    public let trackID: String
    public let chainageM: Evidence<Double>
    public let coordinate: Evidence<GeoCoordinate>
    public let kind: Evidence<SignalKind>
    public let direction: Evidence<TravelDirection>
    public let sightSide: Evidence<String>
    public let aspects: [Evidence<String>]
    public let linkedBlockID: String?
    public let interlockingID: String?
    public let protectionSystem: Evidence<String>
    public let notes: Evidence<String>
}

public struct BlockSection: Codable, Sendable {
    public let blockID: String
    public let trackID: String
    public let startChainageM: Evidence<Double>
    public let endChainageM: Evidence<Double>
    public let entrySignalID: String?
    public let exitSignalID: String?
    public let trackCircuit: Evidence<String>
    public let controlSystem: Evidence<String>
}

public struct SwitchRoute: Codable, Sendable {
    public let routeID: String
    public let destinationTrackID: String
    public let destinationChainageM: Evidence<Double>
    public let routeKind: Evidence<String>
    public let divergingSpeedKmh: Evidence<Double>
}

public struct Switch: Codable, Sendable {
    public let switchID: String
    public let trackID: String
    public let chainageM: Evidence<Double>
    public let coordinate: Evidence<GeoCoordinate>
    public let switchKind: Evidence<String>
    public let connectedTrackIDs: [String]
    public let routes: [SwitchRoute]
    public let interlockingID: String?
    public let notes: Evidence<String>
}

public struct Interlocking: Codable, Sendable {
    public let interlockingID: String
    public let controlledSignalIDs: [String]
    public let controlledSwitchIDs: [String]
    public let routeIDs: [String]
    public let systemDescription: Evidence<String>
}

public enum StructureKind: String, Codable, Sendable {
    case bridge = "BRIDGE"
    case viaduct = "VIADUCT"
    case tunnel = "TUNNEL"
    case levelCrossing = "LEVEL_CROSSING"
    case depot = "DEPOT"
    case siding = "SIDING"
    case retainingWall = "RETAINING_WALL"
    case station = "STATION"
    case other = "OTHER"
}

public struct RailwayStructure: Codable, Sendable {
    public let structureID: String
    public let trackID: String
    public let kind: Evidence<StructureKind>
    public let name: Evidence<String>
    public let centerCoordinate: Evidence<GeoCoordinate>
    public let startChainageM: Evidence<Double>
    public let endChainageM: Evidence<Double>
    public let lengthM: Evidence<Double>
    public let heightM: Evidence<Double>
    public let structureType: Evidence<String>
    public let trackSurface: Evidence<String>
    public let hasLighting: Evidence<Bool>
    /// Optional presentation metadata for a renderer/audio engine; it does not assert a sound implementation.
    public let visualPresetID: String?
    public let acousticPresetID: String?
    public let notes: Evidence<String>
}

public struct LevelCrossing: Codable, Sendable {
    public let crossingID: String
    public let trackID: String
    public let chainageM: Evidence<Double>
    public let coordinate: Evidence<GeoCoordinate>
    public let roadDescription: Evidence<String>
    public let hasWarningBell: Evidence<Bool>
    public let hasBarriers: Evidence<Bool>
    public let warningLeadTimeS: Evidence<Double>
    public let notes: Evidence<String>
}

public struct Landmark: Codable, Sendable {
    public let landmarkID: String
    public let trackID: String?
    public let chainageM: Evidence<Double>
    public let coordinate: Evidence<GeoCoordinate>
    public let name: Evidence<String>
    public let landmarkKind: Evidence<String>
    public let visibilityRangeM: Evidence<Double>
}

public enum ServiceClass: String, Codable, Sendable {
    case express = "EXPRESS"
    case limitedExpress = "LIMITED_EXPRESS"
    case semiExpress = "SEMI_EXPRESS"
    case local = "LOCAL"
    case rapid = "RAPID"
    case rapidExpress = "RAPID_EXPRESS"
    case depotMovement = "DEPOT_MOVEMENT"
}

public enum OperatingPeriod: String, Codable, Sendable {
    case morningRush = "MORNING_RUSH"
    case daytime = "DAYTIME"
    case night = "NIGHT"
    case depot = "DEPOT"
}

public enum MovementKind: String, Codable, Sendable {
    case revenueService = "REVENUE_SERVICE"
    case depotOutbound = "DEPOT_OUTBOUND"
    case depotInbound = "DEPOT_INBOUND"
    case shunting = "SHUNTING"
    case emptyStock = "EMPTY_STOCK"
}

public struct ServicePattern: Codable, Sendable {
    public let servicePatternID: String
    public let serviceClass: Evidence<ServiceClass>
    public let displayName: Evidence<String>
    public let trackIDs: [String]
    public let direction: Evidence<TravelDirection>
    /// Operator-facing label such as 上り/下り; distinct from chainage direction.
    public let operationalDirection: Evidence<String>
    public let callingStationIDs: [String]
    public let plannedRunTimeSeconds: Evidence<Double>
    /// Branch shuttles and depot moves can be shorter than the long mainline run-time policy.
    public let isThroughService: Bool
    public let notes: Evidence<String>
}

public struct OperatingProfile: Codable, Sendable {
    public let profileID: String
    public let period: Evidence<OperatingPeriod>
    public let startTime: Evidence<String>
    public let endTime: Evidence<String>
    public let headwayMinutes: Evidence<Double>
    public let servicePatternIDs: [String]
    public let notes: Evidence<String>
}

public struct Depot: Codable, Sendable {
    public let depotID: String
    public let name: Evidence<String>
    public let trackID: String
    public let chainageM: Evidence<Double>
    public let connectedTrackIDs: [String]
    public let notes: Evidence<String>
}

public struct TimetableStop: Codable, Sendable {
    public let stationID: String
    public let arrivalTime: Evidence<String>
    public let departureTime: Evidence<String>
    public let stopPositionChainageM: Evidence<Double>
}

public struct TimetableTrip: Codable, Sendable {
    public let tripID: String
    public let servicePatternID: String
    public let movementKind: Evidence<MovementKind>
    public let operatingPeriod: Evidence<OperatingPeriod>
    public let direction: Evidence<TravelDirection>
    public let operationalDirection: Evidence<String>
    public let startChainageM: Evidence<Double>
    public let endChainageM: Evidence<Double>
    public let startTime: Evidence<String>
    public let endTime: Evidence<String>
    public let plannedRunTimeSeconds: Evidence<Double>
    public let depotID: String?
    public let trainProfileID: String
    public let trackID: String
    public let stops: [TimetableStop]
}

public struct Timetable: Codable, Sendable {
    public let timetableID: String
    public let timezone: String
    public let trips: [TimetableTrip]
    public let notes: Evidence<String>
}

public struct DrivingScenario: Codable, Sendable {
    public let scenarioID: String
    public let trackID: String
    public let startChainageM: Evidence<Double>
    public let endChainageM: Evidence<Double>
    public let direction: Evidence<TravelDirection>
    public let operationalDirection: Evidence<String>
    public let movementKind: Evidence<MovementKind>
    public let operatingPeriod: Evidence<OperatingPeriod>
    public let servicePatternID: String?
    public let expectedDurationSeconds: Evidence<Double>
    public let timetableID: String?
    public let trainProfileID: String
    public let notes: Evidence<String>
}

public struct ValidationPolicy: Codable, Sendable {
    public let requireFullSpeedCoverage: Bool
    public let maxGeometryGapM: Double
    public let maxCoordinateJumpM: Double
    public let maxHeadingChangeDegrees: Double
    public let minimumThroughRunTimeSeconds: Double
    public let maximumLocalRunTimeSeconds: Double

    public init(
        requireFullSpeedCoverage: Bool = false,
        maxGeometryGapM: Double = 100,
        maxCoordinateJumpM: Double = 100,
        maxHeadingChangeDegrees: Double = 135,
        minimumThroughRunTimeSeconds: Double = 3600,
        maximumLocalRunTimeSeconds: Double = 9000
    ) {
        self.requireFullSpeedCoverage = requireFullSpeedCoverage
        self.maxGeometryGapM = maxGeometryGapM
        self.maxCoordinateJumpM = maxCoordinateJumpM
        self.maxHeadingChangeDegrees = maxHeadingChangeDegrees
        self.minimumThroughRunTimeSeconds = minimumThroughRunTimeSeconds
        self.maximumLocalRunTimeSeconds = maximumLocalRunTimeSeconds
    }
}

public enum DatasetKind: String, Codable, Sendable {
    case realWorld = "REAL_WORLD"
    case fictional = "FICTIONAL"
    case mixed = "MIXED"
}

public struct Route: Codable, Sendable {
    public let routeID: String
    public let name: Evidence<String>
    public let datasetKind: DatasetKind
    public let description: String
    /// Main-line chainage extent; networkLengthM records the distinct physical route-length sum.
    public let totalLengthM: Evidence<Double>
    public let mainTrackID: String
    public let networkLengthM: Evidence<Double>
    /// Operator-published commercial/fare distance; distinct from measured track chainage and route geometry length.
    public let officialCommercialDistanceM: Evidence<Double>
    public let timezone: String
    public let tracks: [Track]
    public let stations: [Station]
    public let speedRestrictions: [SpeedRestriction]
    public let signals: [Signal]
    public let blocks: [BlockSection]
    public let switches: [Switch]
    public let interlockings: [Interlocking]
    public let structures: [RailwayStructure]
    public let levelCrossings: [LevelCrossing]
    public let landmarks: [Landmark]
    public let servicePatterns: [ServicePattern]
    public let operatingProfiles: [OperatingProfile]
    public let depots: [Depot]
    public let timetables: [Timetable]
    public let scenarios: [DrivingScenario]
    public let validationPolicy: ValidationPolicy
    /// Namespaced optional JSON fields let downstream projects extend this schema without modifying core types.
    public let extensions: [String: JSONValue]
}

public struct RoutePackage: Codable, Sendable {
    public let schemaVersion: String
    public let packageID: String
    public let sources: [SourceMetadata]
    public let route: Route

    public init(schemaVersion: String, packageID: String, sources: [SourceMetadata], route: Route) {
        self.schemaVersion = schemaVersion
        self.packageID = packageID
        self.sources = sources
        self.route = route
    }
}

/// Extensible JSON value used only in the namespaced `extensions` object.
public indirect enum JSONValue: Codable, Sendable {
    case string(String)
    case integer(Int)
    case number(Double)
    case boolean(Bool)
    case object([String: JSONValue])
    case array([JSONValue])
    case null

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { self = .null; return }
        if let value = try? container.decode(Bool.self) { self = .boolean(value); return }
        if let value = try? container.decode(Int.self) { self = .integer(value); return }
        if let value = try? container.decode(Double.self) { self = .number(value); return }
        if let value = try? container.decode(String.self) { self = .string(value); return }
        if let value = try? container.decode([String: JSONValue].self) { self = .object(value); return }
        if let value = try? container.decode([JSONValue].self) { self = .array(value); return }
        throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported JSON value")
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value): try container.encode(value)
        case .integer(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .boolean(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .null: try container.encodeNil()
        }
    }
}
