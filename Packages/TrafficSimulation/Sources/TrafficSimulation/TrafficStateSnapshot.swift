import Foundation

public struct TrafficTrainRuntimeSnapshot: Codable, Equatable, Sendable {
    public var id: String
    public var positionM: Double
    public var speedMps: Double
    public var phase: AITrainPhase
    public var nextStopIndex: Int
    public var dwellRemainingSeconds: Double
    public var isHeldForSeparation: Bool
    public var actualDepartureTimeSeconds: Double?
}

public struct TrafficRoadVehicleRuntimeSnapshot: Codable, Equatable, Sendable {
    public var id: String
    public var positionM: Double
    public var speedMps: Double
    public var phase: RoadVehiclePhase
    public var isHeldForSeparation: Bool
}

public struct TrafficPassengerRuntimeSnapshot: Codable, Equatable, Sendable {
    public var id: String
    public var alongPlatformM: Double
    public var phase: PlatformPassengerPhase
}

public struct TrafficSimulationStateSnapshot: Codable, Equatable, Sendable {
    public static let currentRevision = 1
    public var revision: Int
    public var scenarioID: String
    public var routeID: String
    public var simulationTimeSeconds: Double
    public var fixedTick: UInt64
    public var accumulatorSeconds: Double
    public var trains: [TrafficTrainRuntimeSnapshot]
    public var roadVehicles: [TrafficRoadVehicleRuntimeSnapshot]
    public var passengers: [TrafficPassengerRuntimeSnapshot]
}
