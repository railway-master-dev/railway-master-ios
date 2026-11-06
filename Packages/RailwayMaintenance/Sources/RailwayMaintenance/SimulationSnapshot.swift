import Foundation

/// Host-simulation projection consumed at one fixed simulation tick.
/// Identifiers and units intentionally match the neighboring route/traffic workstreams;
/// this package has no dependency on their Swift targets so it can be integrated independently.
public struct MaintenanceSimulationSnapshot: Codable, Equatable, Sendable {
    public let routeID: String
    public let routeLengthM: Double
    public let simulationTimeSeconds: Double
    public let fixedTick: UInt64
    public let fixedTimeStepSeconds: Double
    public let trackIDs: [String]
    public let stationIDs: [String]
    public let trains: [MaintenanceTrainSnapshot]
    public let crossings: [MaintenanceCrossingSnapshot]
    public let weather: MaintenanceWeatherSnapshot
    /// Namespaced scenario flags supplied by the host (for example, "power_outage_zone_1").
    public let scenarioFlags: Set<String>

    public init(
        routeID: String,
        routeLengthM: Double,
        simulationTimeSeconds: Double,
        fixedTick: UInt64,
        fixedTimeStepSeconds: Double,
        trackIDs: [String],
        stationIDs: [String] = [],
        trains: [MaintenanceTrainSnapshot],
        crossings: [MaintenanceCrossingSnapshot] = [],
        weather: MaintenanceWeatherSnapshot = .clear,
        scenarioFlags: Set<String> = []
    ) {
        self.routeID = routeID
        self.routeLengthM = routeLengthM
        self.simulationTimeSeconds = simulationTimeSeconds
        self.fixedTick = fixedTick
        self.fixedTimeStepSeconds = fixedTimeStepSeconds
        self.trackIDs = trackIDs
        self.stationIDs = stationIDs
        self.trains = trains
        self.crossings = crossings
        self.weather = weather
        self.scenarioFlags = scenarioFlags
    }

    public func train(id: String) -> MaintenanceTrainSnapshot? {
        trains.first { $0.trainID == id }
    }
}

public enum MaintenanceTravelDirection: String, Codable, CaseIterable, Sendable {
    case decreasingChainage
    case increasingChainage

    public var sign: Double {
        self == .increasingChainage ? 1 : -1
    }
}

public struct MaintenanceTrainSnapshot: Codable, Equatable, Sendable {
    public let trainID: String
    public let trackID: String
    public let positionM: Double
    public let speedMps: Double
    public let direction: MaintenanceTravelDirection
    public let lengthM: Double
    /// Non-nil when the train is stopped at a station in the host simulation.
    public let stationID: String?
    public let isInService: Bool

    public init(
        trainID: String,
        trackID: String,
        positionM: Double,
        speedMps: Double,
        direction: MaintenanceTravelDirection = .increasingChainage,
        lengthM: Double,
        stationID: String? = nil,
        isInService: Bool = true
    ) {
        self.trainID = trainID
        self.trackID = trackID
        self.positionM = positionM
        self.speedMps = speedMps
        self.direction = direction
        self.lengthM = lengthM
        self.stationID = stationID
        self.isInService = isInService
    }

    public var isMoving: Bool { speedMps > 0.1 }
    public var isStopped: Bool { speedMps <= 0.1 }
}

public struct MaintenanceCrossingSnapshot: Codable, Equatable, Sendable {
    public let crossingID: String
    public let trackID: String
    public let chainageM: Double

    public init(crossingID: String, trackID: String, chainageM: Double) {
        self.crossingID = crossingID
        self.trackID = trackID
        self.chainageM = chainageM
    }
}

/// Simulation-only environmental inputs. These are not meteorological observations.
public struct MaintenanceWeatherSnapshot: Codable, Equatable, Sendable {
    public let windSpeedMps: Double
    public let rainRateMmPerHour: Double
    public let snowCoverM: Double
    public let visibilityM: Double
    /// Fictional normalized quake intensity in 0...1, as provided by a scenario.
    public let earthquakeIntensity: Double

    public init(
        windSpeedMps: Double = 0,
        rainRateMmPerHour: Double = 0,
        snowCoverM: Double = 0,
        visibilityM: Double = 10_000,
        earthquakeIntensity: Double = 0
    ) {
        self.windSpeedMps = windSpeedMps
        self.rainRateMmPerHour = rainRateMmPerHour
        self.snowCoverM = snowCoverM
        self.visibilityM = visibilityM
        self.earthquakeIntensity = earthquakeIntensity
    }

    public static let clear = MaintenanceWeatherSnapshot()

    public func value(for metric: MaintenanceWeatherMetric) -> Double {
        switch metric {
        case .windSpeedMps: return windSpeedMps
        case .rainRateMmPerHour: return rainRateMmPerHour
        case .snowCoverM: return snowCoverM
        case .visibilityM: return visibilityM
        case .earthquakeIntensity: return earthquakeIntensity
        }
    }
}

public enum MaintenanceWeatherMetric: String, Codable, CaseIterable, Sendable {
    case windSpeedMps
    case rainRateMmPerHour
    case snowCoverM
    case visibilityM
    case earthquakeIntensity
}
