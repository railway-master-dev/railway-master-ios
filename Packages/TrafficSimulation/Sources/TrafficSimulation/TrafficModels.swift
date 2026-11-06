import Foundation

// MARK: - Shared route, clock, and player-train concepts

/// This mirrors the route identity/chainage concept used by the host simulator.
/// Route coordinates are fictional simulation metres, not surveyed railway data.
public struct SharedRouteReference: Codable, Equatable, Sendable {
    public let routeID: String
    public let lengthM: Double

    public init(routeID: String, lengthM: Double) {
        self.routeID = routeID
        self.lengthM = lengthM
    }
}

/// Clock contract compatible with a host SimulationSnapshot's time and fixed tick.
public struct SharedSimulationClock: Codable, Equatable, Sendable {
    public let simulationTimeSeconds: Double
    public let fixedTick: UInt64
    public let fixedTimeStepSeconds: Double

    public init(simulationTimeSeconds: Double, fixedTick: UInt64, fixedTimeStepSeconds: Double) {
        self.simulationTimeSeconds = simulationTimeSeconds
        self.fixedTick = fixedTick
        self.fixedTimeStepSeconds = fixedTimeStepSeconds
    }

    public static func zero(fixedTimeStepSeconds: Double) -> SharedSimulationClock {
        SharedSimulationClock(simulationTimeSeconds: 0, fixedTick: 0, fixedTimeStepSeconds: fixedTimeStepSeconds)
    }
}

public enum TrafficDirection: Int, Codable, CaseIterable, Equatable, Hashable, Sendable {
    case decreasing = -1
    case increasing = 1

    public var sign: Double { Double(rawValue) }
    public var serviceDirection: RailwayServiceDirection { self == .increasing ? .up : .down }
}

public enum RailwayServiceDirection: String, Codable, CaseIterable, Equatable, Hashable, Sendable {
    case up
    case down
}

public enum TrainServiceType: String, Codable, CaseIterable, Equatable, Hashable, Sendable {
    case local
    case rapid
    case semiExpress
    case express
    case rapidExpress
    case limitedExpress
}

public enum TrafficServicePeriod: String, Codable, CaseIterable, Equatable, Hashable, Sendable {
    case morningRush
    case daytime
    case night
}

public enum TrafficOperationKind: String, Codable, CaseIterable, Equatable, Hashable, Sendable {
    case passengerService
    case depotEntry
    case depotExit
    case depotShunting
}

public enum TrafficRoutePathKind: String, Codable, CaseIterable, Equatable, Hashable, Sendable {
    case mainline
    case branch
    case depotSpur
}

public enum TrafficDataStatus: String, Codable, CaseIterable, Equatable, Hashable, Sendable {
    case placeholder = "PLACEHOLDER"
}

/// Topology/length reference only; it deliberately contains no surveyed geometry.
public struct TrafficRoutePathDefinition: Codable, Equatable, Sendable {
    public let id: String
    public let lengthM: Double
    public let kind: TrafficRoutePathKind
    public let connectsToPathID: String?
    public let junctionPositionM: Double?
    public let dataStatus: TrafficDataStatus

    public init(id: String, lengthM: Double, kind: TrafficRoutePathKind, connectsToPathID: String? = nil, junctionPositionM: Double? = nil, dataStatus: TrafficDataStatus = .placeholder) {
        self.id = id
        self.lengthM = lengthM
        self.kind = kind
        self.connectsToPathID = connectsToPathID
        self.junctionPositionM = junctionPositionM
        self.dataStatus = dataStatus
    }
}

/// Current player-controlled train state, sampled from the host simulator.
public struct SharedTrainState: Codable, Equatable, Sendable {
    public let trainID: String
    public let trackID: String
    public let positionM: Double
    public let speedMps: Double
    public let direction: TrafficDirection
    public let lengthM: Double

    public init(trainID: String, trackID: String, positionM: Double, speedMps: Double, direction: TrafficDirection, lengthM: Double) {
        self.trainID = trainID
        self.trackID = trackID
        self.positionM = positionM
        self.speedMps = speedMps
        self.direction = direction
        self.lengthM = lengthM
    }
}

// MARK: - Scenario definitions

public struct TrafficTrackDefinition: Codable, Equatable, Sendable {
    public let id: String
    public let routePathID: String
    /// Tracks in one parallel group can visually pass one another.
    public let parallelGroupID: String
    public let direction: TrafficDirection
    /// Renderer-facing lateral offset from the shared route centerline.
    public let lateralOffsetM: Double

    public init(id: String, routePathID: String = "mainline", parallelGroupID: String, direction: TrafficDirection, lateralOffsetM: Double) {
        self.id = id
        self.routePathID = routePathID
        self.parallelGroupID = parallelGroupID
        self.direction = direction
        self.lateralOffsetM = lateralOffsetM
    }
}

public struct ParallelRoadDefinition: Codable, Equatable, Sendable {
    public let id: String
    public let routePathID: String
    public let parallelGroupID: String
    public let direction: TrafficDirection
    public let lateralOffsetM: Double

    public init(id: String, routePathID: String = "mainline", parallelGroupID: String, direction: TrafficDirection, lateralOffsetM: Double) {
        self.id = id
        self.routePathID = routePathID
        self.parallelGroupID = parallelGroupID
        self.direction = direction
        self.lateralOffsetM = lateralOffsetM
    }
}

public struct TrafficPlatformDefinition: Codable, Equatable, Sendable {
    public let id: String
    public let stationID: String
    public let trackID: String
    public let chainageM: Double
    public let lengthM: Double
    public let lateralOffsetM: Double

    public init(id: String, stationID: String, trackID: String, chainageM: Double, lengthM: Double, lateralOffsetM: Double) {
        self.id = id
        self.stationID = stationID
        self.trackID = trackID
        self.chainageM = chainageM
        self.lengthM = lengthM
        self.lateralOffsetM = lateralOffsetM
    }
}

public struct TrafficTrainStop: Codable, Equatable, Sendable {
    public let positionM: Double
    public let dwellSeconds: Double

    public init(positionM: Double, dwellSeconds: Double) {
        self.positionM = positionM
        self.dwellSeconds = dwellSeconds
    }
}

/// A single, deterministic AI train run. The train accelerates, cruises, and brakes
/// toward its listed stops and destination using the supplied fictional parameters.
public struct AITrainPlan: Codable, Equatable, Sendable {
    public let id: String
    public let trackID: String
    public let departureTimeSeconds: Double
    public let startPositionM: Double
    public let destinationPositionM: Double
    public let maximumSpeedMps: Double
    public let accelerationMps2: Double
    public let brakingDecelerationMps2: Double
    public let lengthM: Double
    public let stops: [TrafficTrainStop]
    public let serviceType: TrainServiceType
    public let servicePeriod: TrafficServicePeriod
    public let operationKind: TrafficOperationKind
    public let scheduledTripDurationSeconds: Double?

    public init(
        id: String,
        trackID: String,
        departureTimeSeconds: Double,
        startPositionM: Double,
        destinationPositionM: Double,
        maximumSpeedMps: Double,
        accelerationMps2: Double,
        brakingDecelerationMps2: Double,
        lengthM: Double,
        stops: [TrafficTrainStop] = [],
        serviceType: TrainServiceType = .local,
        servicePeriod: TrafficServicePeriod = .daytime,
        operationKind: TrafficOperationKind = .passengerService,
        scheduledTripDurationSeconds: Double? = nil
    ) {
        self.id = id
        self.trackID = trackID
        self.departureTimeSeconds = departureTimeSeconds
        self.startPositionM = startPositionM
        self.destinationPositionM = destinationPositionM
        self.maximumSpeedMps = maximumSpeedMps
        self.accelerationMps2 = accelerationMps2
        self.brakingDecelerationMps2 = brakingDecelerationMps2
        self.lengthM = lengthM
        self.stops = stops
        self.serviceType = serviceType
        self.servicePeriod = servicePeriod
        self.operationKind = operationKind
        self.scheduledTripDurationSeconds = scheduledTripDurationSeconds
    }
}

public struct RoadVehiclePlan: Codable, Equatable, Sendable {
    public let id: String
    public let roadID: String
    public let departureTimeSeconds: Double
    public let startPositionM: Double
    public let destinationPositionM: Double
    public let targetSpeedMps: Double
    public let accelerationMps2: Double
    public let lengthM: Double

    public init(
        id: String,
        roadID: String,
        departureTimeSeconds: Double,
        startPositionM: Double,
        destinationPositionM: Double,
        targetSpeedMps: Double,
        accelerationMps2: Double,
        lengthM: Double
    ) {
        self.id = id
        self.roadID = roadID
        self.departureTimeSeconds = departureTimeSeconds
        self.startPositionM = startPositionM
        self.destinationPositionM = destinationPositionM
        self.targetSpeedMps = targetSpeedMps
        self.accelerationMps2 = accelerationMps2
        self.lengthM = lengthM
    }
}

/// Walking is represented in platform-local metres so renderers can place a person
/// on a platform mesh without requiring scene or engine objects in this module.
public struct PlatformPassengerTrip: Codable, Equatable, Sendable {
    public let id: String
    public let platformID: String
    public let startTimeSeconds: Double
    public let startOffsetM: Double
    public let destinationOffsetM: Double
    public let walkingSpeedMps: Double

    public init(id: String, platformID: String, startTimeSeconds: Double, startOffsetM: Double, destinationOffsetM: Double, walkingSpeedMps: Double) {
        self.id = id
        self.platformID = platformID
        self.startTimeSeconds = startTimeSeconds
        self.startOffsetM = startOffsetM
        self.destinationOffsetM = destinationOffsetM
        self.walkingSpeedMps = walkingSpeedMps
    }
}

public struct TrafficScenario: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let scenarioID: String
    public let routeID: String
    public let routeLengthM: Double
    public let fixedTimeStepSeconds: Double
    public let minimumTrainGapM: Double
    public let minimumRoadVehicleGapM: Double
    public let passingVisualizationDistanceM: Double
    public let tracks: [TrafficTrackDefinition]
    public let roads: [ParallelRoadDefinition]
    public let platforms: [TrafficPlatformDefinition]
    public let trains: [AITrainPlan]
    public let roadVehicles: [RoadVehiclePlan]
    public let passengerTrips: [PlatformPassengerTrip]
    public let routePaths: [TrafficRoutePathDefinition]
    public let dataStatus: TrafficDataStatus

    public init(
        schemaVersion: Int = 1,
        scenarioID: String,
        routeID: String,
        routeLengthM: Double,
        fixedTimeStepSeconds: Double = 1.0 / 120.0,
        minimumTrainGapM: Double = 30,
        minimumRoadVehicleGapM: Double = 6,
        passingVisualizationDistanceM: Double = 45,
        tracks: [TrafficTrackDefinition],
        roads: [ParallelRoadDefinition],
        platforms: [TrafficPlatformDefinition],
        trains: [AITrainPlan],
        roadVehicles: [RoadVehiclePlan],
        passengerTrips: [PlatformPassengerTrip],
        routePaths: [TrafficRoutePathDefinition]? = nil,
        dataStatus: TrafficDataStatus = .placeholder
    ) {
        self.schemaVersion = schemaVersion
        self.scenarioID = scenarioID
        self.routeID = routeID
        self.routeLengthM = routeLengthM
        self.fixedTimeStepSeconds = fixedTimeStepSeconds
        self.minimumTrainGapM = minimumTrainGapM
        self.minimumRoadVehicleGapM = minimumRoadVehicleGapM
        self.passingVisualizationDistanceM = passingVisualizationDistanceM
        self.tracks = tracks
        self.roads = roads
        self.platforms = platforms
        self.trains = trains
        self.roadVehicles = roadVehicles
        self.passengerTrips = passengerTrips
        self.routePaths = routePaths ?? [TrafficRoutePathDefinition(id: "mainline", lengthM: routeLengthM, kind: .mainline)]
        self.dataStatus = dataStatus
    }

    public var totalNetworkLengthM: Double { routePaths.reduce(0.0) { $0 + $1.lengthM } }

    public var sharedRouteReference: SharedRouteReference {
        SharedRouteReference(routeID: routeID, lengthM: routeLengthM)
    }

    public func trainPlans(in period: TrafficServicePeriod) -> [AITrainPlan] {
        trains.filter { $0.servicePeriod == period }
    }

    public func validate() -> [TrafficDataIssue] {
        var issues: [TrafficDataIssue] = []
        func issue(_ code: String, _ message: String) {
            issues.append(TrafficDataIssue(code: code, message: message))
        }
        func finite(_ values: Double...) -> Bool { values.allSatisfy(\.isFinite) }
        func uniqueIDs(_ values: [String], label: String) {
            if values.contains(where: \.isEmpty) { issue("\(label).emptyID", "\(label) に空のIDがあります。") }
            if Set(values).count != values.count { issue("\(label).duplicateID", "\(label) のIDが重複しています。") }
        }

        if schemaVersion != 1 { issue("scenario.version", "未対応のシナリオスキーマです。") }
        if scenarioID.isEmpty || routeID.isEmpty { issue("scenario.identity", "シナリオIDとルートIDは必須です。") }
        if !finite(routeLengthM, fixedTimeStepSeconds, minimumTrainGapM, minimumRoadVehicleGapM, passingVisualizationDistanceM) || routeLengthM <= 0 || fixedTimeStepSeconds <= 0 || fixedTimeStepSeconds > 1 || minimumTrainGapM < 0 || minimumRoadVehicleGapM < 0 || passingVisualizationDistanceM < 0 {
            issue("scenario.numeric", "路線長、固定刻み、間隔の設定値が不正です。")
        }
        uniqueIDs(routePaths.map(\.id), label: "routePaths")
        let pathByID = Dictionary(routePaths.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let mainlinePaths = routePaths.filter { $0.kind == .mainline }
        if mainlinePaths.count != 1 {
            issue("routePaths.mainlineCount", "メインラインのPLACEHOLDER経路は1本必要です。")
        } else if abs(mainlinePaths[0].lengthM - routeLengthM) > 0.001 {
            issue("routePaths.mainlineLength", "共有ルート長はメインライン経路の長さと一致させてください。")
        }
        for path in routePaths {
            if path.id.isEmpty || !path.lengthM.isFinite || path.lengthM <= 0 {
                issue("routePath.invalid", "経路パス \(path.id) のIDまたは長さが不正です。")
            }
            if path.kind != .mainline {
                guard let connectedID = path.connectsToPathID,
                      let connectedPath = pathByID[connectedID],
                      let junction = path.junctionPositionM,
                      junction.isFinite,
                      junction >= 0,
                      junction <= connectedPath.lengthM else {
                    issue("routePath.connectionInvalid", "支線・車庫支線 \(path.id) には有効な接続先と分岐キロ程が必要です。")
                    continue
                }
            }
        }
        if tracks.isEmpty { issue("tracks.empty", "少なくとも1本の線路が必要です。") }
        uniqueIDs(tracks.map(\.id), label: "tracks")
        uniqueIDs(roads.map(\.id), label: "roads")
        uniqueIDs(platforms.map(\.id), label: "platforms")
        uniqueIDs(trains.map(\.id), label: "trains")
        uniqueIDs(roadVehicles.map(\.id), label: "roadVehicles")
        uniqueIDs(passengerTrips.map(\.id), label: "passengerTrips")

        let trackByID = Dictionary(tracks.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let roadByID = Dictionary(roads.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let platformByID = Dictionary(platforms.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

        for track in tracks where track.id.isEmpty || track.parallelGroupID.isEmpty || pathByID[track.routePathID] == nil || !track.lateralOffsetM.isFinite {
            issue("track.invalid", "線路ID、経路パス、並行グループ、横オフセットを確認してください。")
        }
        for road in roads where road.id.isEmpty || road.parallelGroupID.isEmpty || pathByID[road.routePathID] == nil || !road.lateralOffsetM.isFinite {
            issue("road.invalid", "道路ID、経路パス、並行グループ、横オフセットを確認してください。")
        }
        for platform in platforms {
            let pathLength = trackByID[platform.trackID].flatMap { pathByID[$0.routePathID]?.lengthM } ?? routeLengthM
            if platform.id.isEmpty || platform.stationID.isEmpty || trackByID[platform.trackID] == nil || !finite(platform.chainageM, platform.lengthM, platform.lateralOffsetM) || platform.chainageM < 0 || platform.chainageM > pathLength || platform.lengthM <= 0 {
                issue("platform.invalid", "ホーム \(platform.id) の位置、長さ、または線路参照が不正です。")
            }
        }
        for train in trains {
            guard let track = trackByID[train.trackID] else {
                issue("train.trackMissing", "列車 \(train.id) が存在しない線路を参照しています。")
                continue
            }
            let pathLength = pathByID[track.routePathID]?.lengthM ?? routeLengthM
            let delta = train.destinationPositionM - train.startPositionM
            if !finite(train.departureTimeSeconds, train.startPositionM, train.destinationPositionM, train.maximumSpeedMps, train.accelerationMps2, train.brakingDecelerationMps2, train.lengthM) || train.departureTimeSeconds < 0 || train.startPositionM < 0 || train.startPositionM > pathLength || train.destinationPositionM < 0 || train.destinationPositionM > pathLength || delta * track.direction.sign <= 0 || train.maximumSpeedMps <= 0 || train.accelerationMps2 <= 0 || train.brakingDecelerationMps2 <= 0 || train.lengthM <= 0 {
                issue("train.invalid", "列車 \(train.id) の時刻、位置、方向、性能値を確認してください。")
            }
            if train.operationKind == .passengerService, abs(delta) >= 20_000, train.scheduledTripDurationSeconds == nil {
                issue("train.scheduleDurationMissing", "20km以上の旅客運転には予定所要時間を明示してください。")
            }
            if let duration = train.scheduledTripDurationSeconds {
                if !duration.isFinite || duration <= 0 || (train.operationKind == .passengerService && (duration < 3_600 || (train.serviceType == .local && duration > 9_000))) {
                    issue("train.scheduleDuration", "旅客列車の架空所要時間は60分以上、各停は150分以下で指定してください。")
                }
            }
            var previousProgress = train.startPositionM * track.direction.sign
            for stop in train.stops {
                let progress = stop.positionM * track.direction.sign
                if !finite(stop.positionM, stop.dwellSeconds) || stop.positionM < 0 || stop.positionM > pathLength || stop.dwellSeconds < 0 || progress <= previousProgress || (train.destinationPositionM - stop.positionM) * track.direction.sign < 0 {
                    issue("train.stopInvalid", "列車 \(train.id) の停車位置は進行方向順に路線範囲内で指定してください。")
                    break
                }
                previousProgress = progress
            }
        }
        for vehicle in roadVehicles {
            guard let road = roadByID[vehicle.roadID] else {
                issue("vehicle.roadMissing", "道路車両 \(vehicle.id) が存在しない道路を参照しています。")
                continue
            }
            let pathLength = pathByID[road.routePathID]?.lengthM ?? routeLengthM
            let delta = vehicle.destinationPositionM - vehicle.startPositionM
            if !finite(vehicle.departureTimeSeconds, vehicle.startPositionM, vehicle.destinationPositionM, vehicle.targetSpeedMps, vehicle.accelerationMps2, vehicle.lengthM) || vehicle.departureTimeSeconds < 0 || vehicle.startPositionM < 0 || vehicle.startPositionM > pathLength || vehicle.destinationPositionM < 0 || vehicle.destinationPositionM > pathLength || delta * road.direction.sign <= 0 || vehicle.targetSpeedMps <= 0 || vehicle.accelerationMps2 <= 0 || vehicle.lengthM <= 0 {
                issue("vehicle.invalid", "道路車両 \(vehicle.id) の時刻、位置、方向、性能値を確認してください。")
            }
        }
        for trip in passengerTrips {
            guard let platform = platformByID[trip.platformID] else {
                issue("passenger.platformMissing", "乗客 \(trip.id) が存在しないホームを参照しています。")
                continue
            }
            if !finite(trip.startTimeSeconds, trip.startOffsetM, trip.destinationOffsetM, trip.walkingSpeedMps) || trip.startTimeSeconds < 0 || trip.startOffsetM < 0 || trip.startOffsetM > platform.lengthM || trip.destinationOffsetM < 0 || trip.destinationOffsetM > platform.lengthM || trip.walkingSpeedMps <= 0 {
                issue("passenger.invalid", "乗客 \(trip.id) の時刻、ホーム内位置、歩行速度を確認してください。")
            }
        }
        return issues
    }
}

public struct TrafficDataIssue: Codable, Equatable, Sendable {
    public let code: String
    public let message: String

    public init(code: String, message: String) {
        self.code = code
        self.message = message
    }
}

// MARK: - Renderer-facing immutable snapshots

public enum AITrainPhase: String, Codable, Equatable, Sendable {
    case scheduled
    case running
    case dwelling
    case completed
}

public enum RoadVehiclePhase: String, Codable, Equatable, Sendable {
    case scheduled
    case moving
    case completed
}

public enum PlatformPassengerPhase: String, Codable, Equatable, Sendable {
    case scheduled
    case walking
    case waiting
}

public struct AITrainSnapshot: Codable, Equatable, Sendable {
    public let id: String
    public let trackID: String
    public let routePathID: String
    public let serviceType: TrainServiceType
    public let servicePeriod: TrafficServicePeriod
    public let serviceDirection: RailwayServiceDirection
    public let operationKind: TrafficOperationKind
    public let scheduledArrivalTimeSeconds: Double?
    public let positionM: Double
    public let speedMps: Double
    public let signedSpeedMps: Double
    public let headingRadians: Double
    public let phase: AITrainPhase
    public let isHeldForSeparation: Bool
    public let nearestTrainClearanceM: Double?
    public let isPassing: Bool

    public init(id: String, trackID: String, routePathID: String, serviceType: TrainServiceType, servicePeriod: TrafficServicePeriod, serviceDirection: RailwayServiceDirection, operationKind: TrafficOperationKind, scheduledArrivalTimeSeconds: Double?, positionM: Double, speedMps: Double, signedSpeedMps: Double, headingRadians: Double, phase: AITrainPhase, isHeldForSeparation: Bool, nearestTrainClearanceM: Double?, isPassing: Bool) {
        self.id = id
        self.trackID = trackID
        self.routePathID = routePathID
        self.serviceType = serviceType
        self.servicePeriod = servicePeriod
        self.serviceDirection = serviceDirection
        self.operationKind = operationKind
        self.scheduledArrivalTimeSeconds = scheduledArrivalTimeSeconds
        self.positionM = positionM
        self.speedMps = speedMps
        self.signedSpeedMps = signedSpeedMps
        self.headingRadians = headingRadians
        self.phase = phase
        self.isHeldForSeparation = isHeldForSeparation
        self.nearestTrainClearanceM = nearestTrainClearanceM
        self.isPassing = isPassing
    }
}

public struct RoadVehicleSnapshot: Codable, Equatable, Sendable {
    public let id: String
    public let roadID: String
    public let routePathID: String
    public let positionM: Double
    public let speedMps: Double
    public let headingRadians: Double
    public let phase: RoadVehiclePhase
    public let isHeldForSeparation: Bool
    public let nearestVehicleClearanceM: Double?

    public init(id: String, roadID: String, routePathID: String, positionM: Double, speedMps: Double, headingRadians: Double, phase: RoadVehiclePhase, isHeldForSeparation: Bool, nearestVehicleClearanceM: Double?) {
        self.id = id
        self.roadID = roadID
        self.routePathID = routePathID
        self.positionM = positionM
        self.speedMps = speedMps
        self.headingRadians = headingRadians
        self.phase = phase
        self.isHeldForSeparation = isHeldForSeparation
        self.nearestVehicleClearanceM = nearestVehicleClearanceM
    }
}

public struct PlatformPassengerSnapshot: Codable, Equatable, Sendable {
    public let id: String
    public let platformID: String
    public let alongPlatformM: Double
    public let lateralOffsetM: Double
    public let headingRadians: Double
    public let phase: PlatformPassengerPhase

    public init(id: String, platformID: String, alongPlatformM: Double, lateralOffsetM: Double, headingRadians: Double, phase: PlatformPassengerPhase) {
        self.id = id
        self.platformID = platformID
        self.alongPlatformM = alongPlatformM
        self.lateralOffsetM = lateralOffsetM
        self.headingRadians = headingRadians
        self.phase = phase
    }
}

public struct TrafficSnapshot: Codable, Equatable, Sendable {
    public let scenarioID: String
    public let routeID: String
    public let routeLengthM: Double
    public let totalNetworkLengthM: Double
    public let routePaths: [TrafficRoutePathDefinition]
    public let dataStatus: TrafficDataStatus
    public let simulationTimeSeconds: Double
    public let fixedTick: UInt64
    public let fixedTimeStepSeconds: Double
    public let playerTrain: SharedTrainState?
    public let trains: [AITrainSnapshot]
    public let roadVehicles: [RoadVehicleSnapshot]
    public let passengers: [PlatformPassengerSnapshot]

    public init(scenarioID: String, routeID: String, routeLengthM: Double, totalNetworkLengthM: Double, routePaths: [TrafficRoutePathDefinition], dataStatus: TrafficDataStatus, simulationTimeSeconds: Double, fixedTick: UInt64, fixedTimeStepSeconds: Double, playerTrain: SharedTrainState?, trains: [AITrainSnapshot], roadVehicles: [RoadVehicleSnapshot], passengers: [PlatformPassengerSnapshot]) {
        self.scenarioID = scenarioID
        self.routeID = routeID
        self.routeLengthM = routeLengthM
        self.totalNetworkLengthM = totalNetworkLengthM
        self.routePaths = routePaths
        self.dataStatus = dataStatus
        self.simulationTimeSeconds = simulationTimeSeconds
        self.fixedTick = fixedTick
        self.fixedTimeStepSeconds = fixedTimeStepSeconds
        self.playerTrain = playerTrain
        self.trains = trains
        self.roadVehicles = roadVehicles
        self.passengers = passengers
    }
}

public enum TrafficSimulationError: Error, Equatable, Sendable {
    case invalidScenario([TrafficDataIssue])
    case invalidDelta
    case invalidSharedRoute
    case invalidSharedClock
    case clockMovedBackward
    case invalidPlayerTrain
    case invalidRuntimeState
}

public enum TrafficScenarioLibrary {
    /// Deterministic fictional scenario with two railway tracks, paired roads,
    /// stopping AI trains, and platform-local passenger walks.
    public static let fictionalParallelCorridor = TrafficScenario(
        scenarioID: "fictional-parallel-corridor-v1",
        routeID: "fictional-corridor-01",
        routeLengthM: 2_400,
        fixedTimeStepSeconds: 1.0 / 120.0,
        minimumTrainGapM: 35,
        minimumRoadVehicleGapM: 7,
        passingVisualizationDistanceM: 55,
        tracks: [
            TrafficTrackDefinition(id: "track-east", parallelGroupID: "rail-corridor", direction: .increasing, lateralOffsetM: -2.1),
            TrafficTrackDefinition(id: "track-west", parallelGroupID: "rail-corridor", direction: .decreasing, lateralOffsetM: 2.1)
        ],
        roads: [
            ParallelRoadDefinition(id: "road-east", parallelGroupID: "road-corridor", direction: .increasing, lateralOffsetM: -7.0),
            ParallelRoadDefinition(id: "road-west", parallelGroupID: "road-corridor", direction: .decreasing, lateralOffsetM: 7.0)
        ],
        platforms: [
            TrafficPlatformDefinition(id: "mid-platform-east", stationID: "fictional-mid-station", trackID: "track-east", chainageM: 1_200, lengthM: 180, lateralOffsetM: -4.4),
            TrafficPlatformDefinition(id: "mid-platform-west", stationID: "fictional-mid-station", trackID: "track-west", chainageM: 1_200, lengthM: 180, lateralOffsetM: 4.4)
        ],
        trains: [
            AITrainPlan(id: "ai-east-01", trackID: "track-east", departureTimeSeconds: 0, startPositionM: 0, destinationPositionM: 2_400, maximumSpeedMps: 18, accelerationMps2: 0.65, brakingDecelerationMps2: 0.8, lengthM: 120, stops: [TrafficTrainStop(positionM: 1_200, dwellSeconds: 12)]),
            AITrainPlan(id: "ai-east-02", trackID: "track-east", departureTimeSeconds: 38, startPositionM: 0, destinationPositionM: 2_400, maximumSpeedMps: 16, accelerationMps2: 0.55, brakingDecelerationMps2: 0.75, lengthM: 100, stops: [TrafficTrainStop(positionM: 1_200, dwellSeconds: 9)]),
            AITrainPlan(id: "ai-west-01", trackID: "track-west", departureTimeSeconds: 18, startPositionM: 2_400, destinationPositionM: 0, maximumSpeedMps: 17, accelerationMps2: 0.6, brakingDecelerationMps2: 0.8, lengthM: 110, stops: [TrafficTrainStop(positionM: 1_200, dwellSeconds: 10)])
        ],
        roadVehicles: [
            RoadVehiclePlan(id: "car-east-01", roadID: "road-east", departureTimeSeconds: 0, startPositionM: 0, destinationPositionM: 2_400, targetSpeedMps: 13, accelerationMps2: 1.5, lengthM: 4.6),
            RoadVehiclePlan(id: "car-east-02", roadID: "road-east", departureTimeSeconds: 16, startPositionM: 0, destinationPositionM: 2_400, targetSpeedMps: 11, accelerationMps2: 1.3, lengthM: 4.2),
            RoadVehiclePlan(id: "car-west-01", roadID: "road-west", departureTimeSeconds: 9, startPositionM: 2_400, destinationPositionM: 0, targetSpeedMps: 12, accelerationMps2: 1.4, lengthM: 4.5)
        ],
        passengerTrips: [
            PlatformPassengerTrip(id: "passenger-east-01", platformID: "mid-platform-east", startTimeSeconds: 4, startOffsetM: 12, destinationOffsetM: 166, walkingSpeedMps: 1.15),
            PlatformPassengerTrip(id: "passenger-east-02", platformID: "mid-platform-east", startTimeSeconds: 12, startOffsetM: 155, destinationOffsetM: 34, walkingSpeedMps: 0.95),
            PlatformPassengerTrip(id: "passenger-west-01", platformID: "mid-platform-west", startTimeSeconds: 6, startOffsetM: 20, destinationOffsetM: 145, walkingSpeedMps: 1.05)
        ]
    )

    public static func loadBundledExample() throws -> TrafficScenario {
        guard let url = Bundle.module.url(forResource: "FictionalParallelCorridor", withExtension: "json") else {
            throw CocoaError(.fileNoSuchFile)
        }
        return try JSONDecoder().decode(TrafficScenario.self, from: Data(contentsOf: url))
    }
}
