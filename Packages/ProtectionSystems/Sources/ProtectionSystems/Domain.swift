import Foundation

/// Every result from this package is a fictional game/simulation output, never an operational authority.
public enum ProtectionModelLabel: String, Codable, Equatable, Sendable {
    case fictionalSimulationOnly = "FICTIONAL SIMULATION ONLY"
}

public enum ProtectionPackageError: Error, Equatable, Sendable {
    case invalidValue(String)
    case duplicateIdentifier(String)
    case unknownIdentifier(String)
    case inconsistentReference(String)
    case timeMustIncrease
}

public enum TravelDirection: String, Codable, CaseIterable, Equatable, Sendable {
    case increasingChainage
    case decreasingChainage
}

public struct BlockSection: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let trackID: String
    public let startM: Double
    public let endM: Double

    public init(id: String, trackID: String, startM: Double, endM: Double) throws {
        guard !id.isEmpty, !trackID.isEmpty, startM.isFinite, endM.isFinite,
              startM >= 0, endM > startM else {
            throw ProtectionPackageError.invalidValue("block id/track/start/end")
        }
        self.id = id
        self.trackID = trackID
        self.startM = startM
        self.endM = endM
    }
}

public struct RailwayTrack: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let lengthM: Double
    public let blocks: [BlockSection]

    public init(id: String, lengthM: Double, blocks: [BlockSection]) throws {
        guard !id.isEmpty, lengthM.isFinite, lengthM > 0, !blocks.isEmpty else {
            throw ProtectionPackageError.invalidValue("track id/length/blocks")
        }
        guard blocks.allSatisfy({ $0.trackID == id && $0.startM >= 0 && $0.endM <= lengthM }) else {
            throw ProtectionPackageError.inconsistentReference("block outside track \(id)")
        }
        guard Set(blocks.map(\.id)).count == blocks.count else {
            throw ProtectionPackageError.duplicateIdentifier("block on \(id)")
        }
        let ordered = blocks.sorted { $0.startM < $1.startM }
        guard abs(ordered[0].startM) <= 0.001,
              abs(ordered[ordered.count - 1].endM - lengthM) <= 0.001 else {
            throw ProtectionPackageError.invalidValue("blocks must cover track \(id)")
        }
        for index in ordered.indices where index > 0 {
            guard abs(ordered[index].startM - ordered[index - 1].endM) <= 0.001 else {
                throw ProtectionPackageError.invalidValue("blocks must be contiguous and non-overlapping on \(id)")
            }
        }
        self.id = id
        self.lengthM = lengthM
        self.blocks = ordered
    }
}

public enum RouteEquipmentKind: String, Codable, CaseIterable, Equatable, Sendable {
    case atsSBeacon
    case atsPProfileTarget
    case atsPsSpeedBeacon
    case atcCommandZone
    case atoTarget
}

/// Fictional, chainage-mounted equipment. Optional fields are validated against `kind`.
public struct RouteEquipment: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let trackID: String
    public let kind: RouteEquipmentKind
    public let positionM: Double
    public let targetPositionM: Double?
    public let targetSpeedKmh: Double?
    public let supervisionDistanceM: Double?
    public let zoneStartM: Double?
    public let zoneEndM: Double?

    public init(
        id: String,
        trackID: String,
        kind: RouteEquipmentKind,
        positionM: Double,
        targetPositionM: Double? = nil,
        targetSpeedKmh: Double? = nil,
        supervisionDistanceM: Double? = nil,
        zoneStartM: Double? = nil,
        zoneEndM: Double? = nil
    ) throws {
        guard !id.isEmpty, !trackID.isEmpty, positionM.isFinite, positionM >= 0 else {
            throw ProtectionPackageError.invalidValue("equipment id/track/position")
        }
        func finiteNonnegative(_ value: Double?) -> Bool {
            value.map { $0.isFinite && $0 >= 0 } ?? true
        }
        guard finiteNonnegative(targetPositionM), finiteNonnegative(targetSpeedKmh),
              finiteNonnegative(supervisionDistanceM), finiteNonnegative(zoneStartM), finiteNonnegative(zoneEndM) else {
            throw ProtectionPackageError.invalidValue("equipment numeric parameter")
        }
        switch kind {
        case .atsSBeacon:
            break
        case .atsPProfileTarget, .atoTarget:
            guard targetPositionM != nil, targetSpeedKmh != nil else {
                throw ProtectionPackageError.invalidValue("\(kind.rawValue) requires target position and speed")
            }
        case .atsPsSpeedBeacon:
            guard targetSpeedKmh != nil, let distance = supervisionDistanceM, distance > 0 else {
                throw ProtectionPackageError.invalidValue("atsPsSpeedBeacon requires speed and positive supervision distance")
            }
        case .atcCommandZone:
            guard let speed = targetSpeedKmh, speed > 0,
                  let start = zoneStartM, let end = zoneEndM, end > start,
                  positionM >= start, positionM <= end else {
                throw ProtectionPackageError.invalidValue("atcCommandZone requires speed and a containing zone")
            }
        }
        self.id = id
        self.trackID = trackID
        self.kind = kind
        self.positionM = positionM
        self.targetPositionM = targetPositionM
        self.targetSpeedKmh = targetSpeedKmh
        self.supervisionDistanceM = supervisionDistanceM
        self.zoneStartM = zoneStartM
        self.zoneEndM = zoneEndM
    }
}

public struct SwitchDefinition: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let trackID: String
    public let positionM: Double
    public let positions: [String]

    public init(id: String, trackID: String, positionM: Double, positions: [String]) throws {
        guard !id.isEmpty, !trackID.isEmpty, positionM.isFinite, positionM >= 0,
              positions.count >= 2, positions.allSatisfy({ !$0.isEmpty }), Set(positions).count == positions.count else {
            throw ProtectionPackageError.invalidValue("switch id/track/position/positions")
        }
        self.id = id
        self.trackID = trackID
        self.positionM = positionM
        self.positions = positions.sorted()
    }
}

public struct RouteDefinition: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let trackID: String
    public let protectedBlockIDs: [String]
    public let requiredSwitchPositions: [String: String]
    public let conflictsWithRouteIDs: [String]

    public init(
        id: String,
        trackID: String,
        protectedBlockIDs: [String],
        requiredSwitchPositions: [String: String] = [:],
        conflictsWithRouteIDs: [String] = []
    ) throws {
        guard !id.isEmpty, !trackID.isEmpty, !protectedBlockIDs.isEmpty,
              protectedBlockIDs.allSatisfy({ !$0.isEmpty }), Set(protectedBlockIDs).count == protectedBlockIDs.count,
              requiredSwitchPositions.allSatisfy({ !$0.key.isEmpty && !$0.value.isEmpty }),
              Set(conflictsWithRouteIDs).count == conflictsWithRouteIDs.count else {
            throw ProtectionPackageError.invalidValue("route id/track/blocks/switches")
        }
        self.id = id
        self.trackID = trackID
        self.protectedBlockIDs = protectedBlockIDs
        self.requiredSwitchPositions = requiredSwitchPositions
        self.conflictsWithRouteIDs = conflictsWithRouteIDs
    }
}

public struct SignalDefinition: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let trackID: String
    public let positionM: Double
    public let protectedBlockID: String
    public let governingRouteID: String?

    public init(id: String, trackID: String, positionM: Double, protectedBlockID: String, governingRouteID: String? = nil) throws {
        guard !id.isEmpty, !trackID.isEmpty, positionM.isFinite, positionM >= 0, !protectedBlockID.isEmpty else {
            throw ProtectionPackageError.invalidValue("signal id/track/position/protected block")
        }
        self.id = id
        self.trackID = trackID
        self.positionM = positionM
        self.protectedBlockID = protectedBlockID
        self.governingRouteID = governingRouteID
    }
}

public struct RailwayNetwork: Codable, Equatable, Sendable {
    public let id: String
    public let tracks: [RailwayTrack]
    public let equipment: [RouteEquipment]
    public let switches: [SwitchDefinition]
    public let routes: [RouteDefinition]
    public let signals: [SignalDefinition]

    public init(
        id: String,
        tracks: [RailwayTrack],
        equipment: [RouteEquipment] = [],
        switches: [SwitchDefinition] = [],
        routes: [RouteDefinition] = [],
        signals: [SignalDefinition] = []
    ) throws {
        guard !id.isEmpty, !tracks.isEmpty else { throw ProtectionPackageError.invalidValue("network id/tracks") }
        func requireUnique(_ ids: [String], _ type: String) throws {
            guard Set(ids).count == ids.count else { throw ProtectionPackageError.duplicateIdentifier(type) }
        }
        try requireUnique(tracks.map(\.id), "track")
        try requireUnique(tracks.flatMap(\.blocks).map(\.id), "block")
        try requireUnique(equipment.map(\.id), "equipment")
        try requireUnique(switches.map(\.id), "switch")
        try requireUnique(routes.map(\.id), "route")
        try requireUnique(signals.map(\.id), "signal")
        let trackByID = Dictionary(uniqueKeysWithValues: tracks.map { ($0.id, $0) })
        let blocks = Dictionary(uniqueKeysWithValues: tracks.flatMap(\.blocks).map { ($0.id, $0) })
        let switchByID = Dictionary(uniqueKeysWithValues: switches.map { ($0.id, $0) })
        let routeByID = Dictionary(uniqueKeysWithValues: routes.map { ($0.id, $0) })
        for device in equipment {
            guard let track = trackByID[device.trackID], device.positionM <= track.lengthM,
                  (device.targetPositionM == nil || device.targetPositionM! <= track.lengthM),
                  (device.zoneEndM == nil || device.zoneEndM! <= track.lengthM) else {
                throw ProtectionPackageError.inconsistentReference("equipment \(device.id)")
            }
        }
        for item in switches {
            guard let track = trackByID[item.trackID], item.positionM <= track.lengthM else {
                throw ProtectionPackageError.inconsistentReference("switch \(item.id)")
            }
        }
        for route in routes {
            guard trackByID[route.trackID] != nil,
                  route.protectedBlockIDs.allSatisfy({ blocks[$0]?.trackID == route.trackID }),
                  route.requiredSwitchPositions.allSatisfy({ switchByID[$0.key]?.trackID == route.trackID && switchByID[$0.key]?.positions.contains($0.value) == true }),
                  route.conflictsWithRouteIDs.allSatisfy({ routeByID[$0] != nil && $0 != route.id }) else {
                throw ProtectionPackageError.inconsistentReference("route \(route.id)")
            }
        }
        for signal in signals {
            let routeMatchesTrack = signal.governingRouteID.map { routeByID[$0]?.trackID == signal.trackID } ?? true
            guard let track = trackByID[signal.trackID], signal.positionM <= track.lengthM,
                  blocks[signal.protectedBlockID]?.trackID == signal.trackID,
                  routeMatchesTrack else {
                throw ProtectionPackageError.inconsistentReference("signal \(signal.id)")
            }
        }
        self.id = id
        self.tracks = tracks.sorted { $0.id < $1.id }
        self.equipment = equipment.sorted { $0.positionM == $1.positionM ? $0.id < $1.id : $0.positionM < $1.positionM }
        self.switches = switches
        self.routes = routes
        self.signals = signals
    }

    private enum CodingKeys: String, CodingKey { case id, tracks, equipment, switches, routes, signals }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let id = try values.decode(String.self, forKey: .id)
        let decodedTracks = try values.decode([RailwayTrack].self, forKey: .tracks)
        let tracks = try decodedTracks.map { track in
            let blocks = try track.blocks.map { block in
                try BlockSection(id: block.id, trackID: block.trackID, startM: block.startM, endM: block.endM)
            }
            return try RailwayTrack(id: track.id, lengthM: track.lengthM, blocks: blocks)
        }
        let decodedEquipment = try values.decodeIfPresent([RouteEquipment].self, forKey: .equipment) ?? []
        let equipment = try decodedEquipment.map {
            try RouteEquipment(id: $0.id, trackID: $0.trackID, kind: $0.kind, positionM: $0.positionM,
                               targetPositionM: $0.targetPositionM, targetSpeedKmh: $0.targetSpeedKmh,
                               supervisionDistanceM: $0.supervisionDistanceM, zoneStartM: $0.zoneStartM,
                               zoneEndM: $0.zoneEndM)
        }
        let decodedSwitches = try values.decodeIfPresent([SwitchDefinition].self, forKey: .switches) ?? []
        let switches = try decodedSwitches.map {
            try SwitchDefinition(id: $0.id, trackID: $0.trackID, positionM: $0.positionM, positions: $0.positions)
        }
        let decodedRoutes = try values.decodeIfPresent([RouteDefinition].self, forKey: .routes) ?? []
        let routes = try decodedRoutes.map {
            try RouteDefinition(id: $0.id, trackID: $0.trackID, protectedBlockIDs: $0.protectedBlockIDs,
                                requiredSwitchPositions: $0.requiredSwitchPositions,
                                conflictsWithRouteIDs: $0.conflictsWithRouteIDs)
        }
        let decodedSignals = try values.decodeIfPresent([SignalDefinition].self, forKey: .signals) ?? []
        let signals = try decodedSignals.map {
            try SignalDefinition(id: $0.id, trackID: $0.trackID, positionM: $0.positionM,
                                 protectedBlockID: $0.protectedBlockID, governingRouteID: $0.governingRouteID)
        }
        try self.init(id: id, tracks: tracks, equipment: equipment, switches: switches, routes: routes, signals: signals)
    }

    public func track(_ id: String) -> RailwayTrack? { tracks.first { $0.id == id } }
    public func route(_ id: String) -> RouteDefinition? { routes.first { $0.id == id } }
    public func block(_ id: String) -> BlockSection? { tracks.lazy.flatMap(\.blocks).first { $0.id == id } }
}

public struct TrainState: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let trackID: String
    /// Leading end in the direction of travel, measured in track chainage.
    public let frontPositionM: Double
    public let speedKmh: Double
    public let lengthM: Double
    public let direction: TravelDirection

    public init(id: String, trackID: String, frontPositionM: Double, speedKmh: Double, lengthM: Double, direction: TravelDirection = .increasingChainage) throws {
        guard !id.isEmpty, !trackID.isEmpty, frontPositionM.isFinite, frontPositionM >= 0,
              speedKmh.isFinite, speedKmh >= 0, lengthM.isFinite, lengthM > 0 else {
            throw ProtectionPackageError.invalidValue("train id/track/position/speed/length")
        }
        self.id = id
        self.trackID = trackID
        self.frontPositionM = frontPositionM
        self.speedKmh = speedKmh
        self.lengthM = lengthM
        self.direction = direction
    }

    public var occupiedRangeM: ClosedRange<Double> {
        switch direction {
        case .increasingChainage: return max(0, frontPositionM - lengthM)...frontPositionM
        case .decreasingChainage: return frontPositionM...(frontPositionM + lengthM)
        }
    }

    public func distanceAhead(to positionM: Double) -> Double {
        direction == .increasingChainage ? positionM - frontPositionM : frontPositionM - positionM
    }
}

public struct TimetableRouteAssignment: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let trainID: String
    public let nextRouteID: String
    public let plannedDepartureTimeSeconds: Double

    public init(id: String, trainID: String, nextRouteID: String, plannedDepartureTimeSeconds: Double) throws {
        guard !id.isEmpty, !trainID.isEmpty, !nextRouteID.isEmpty,
              plannedDepartureTimeSeconds.isFinite, plannedDepartureTimeSeconds >= 0 else {
            throw ProtectionPackageError.invalidValue("timetable assignment")
        }
        self.id = id
        self.trainID = trainID
        self.nextRouteID = nextRouteID
        self.plannedDepartureTimeSeconds = plannedDepartureTimeSeconds
    }
}

public struct OperatorInput: Codable, Equatable, Sendable {
    public let acknowledgeATSS: Bool
    public let driverActivityPulse: Bool
    public let deadmanHeld: Bool
    public let resetProtectionAtStop: Bool

    public init(acknowledgeATSS: Bool = false, driverActivityPulse: Bool = false, deadmanHeld: Bool = true,
                resetProtectionAtStop: Bool = false) {
        self.acknowledgeATSS = acknowledgeATSS
        self.driverActivityPulse = driverActivityPulse
        self.deadmanHeld = deadmanHeld
        self.resetProtectionAtStop = resetProtectionAtStop
    }

    private enum CodingKeys: String, CodingKey { case acknowledgeATSS, driverActivityPulse, deadmanHeld, resetProtectionAtStop }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.init(acknowledgeATSS: try values.decodeIfPresent(Bool.self, forKey: .acknowledgeATSS) ?? false,
                  driverActivityPulse: try values.decodeIfPresent(Bool.self, forKey: .driverActivityPulse) ?? false,
                  deadmanHeld: try values.decodeIfPresent(Bool.self, forKey: .deadmanHeld) ?? true,
                  resetProtectionAtStop: try values.decodeIfPresent(Bool.self, forKey: .resetProtectionAtStop) ?? false)
    }
}

public struct SimulationFrame: Codable, Equatable, Sendable {
    public let fixedTick: UInt64
    public let timeSeconds: Double
    public let trains: [TrainState]
    public let switchPositions: [String: String]
    public let routeRequests: [String: String]
    public let operatorInputs: [String: OperatorInput]
    public let timetableAssignments: [TimetableRouteAssignment]

    public init(
        fixedTick: UInt64,
        timeSeconds: Double,
        trains: [TrainState],
        switchPositions: [String: String] = [:],
        routeRequests: [String: String] = [:],
        operatorInputs: [String: OperatorInput] = [:],
        timetableAssignments: [TimetableRouteAssignment] = []
    ) throws {
        guard timeSeconds.isFinite, timeSeconds >= 0 else { throw ProtectionPackageError.invalidValue("simulation time") }
        guard Set(trains.map(\.id)).count == trains.count else { throw ProtectionPackageError.duplicateIdentifier("train in frame") }
        let trainIDs = Set(trains.map(\.id))
        guard routeRequests.keys.allSatisfy(trainIDs.contains), operatorInputs.keys.allSatisfy(trainIDs.contains),
              timetableAssignments.allSatisfy({ trainIDs.contains($0.trainID) }) else {
            throw ProtectionPackageError.inconsistentReference("frame train references")
        }
        self.fixedTick = fixedTick
        self.timeSeconds = timeSeconds
        self.trains = trains
        self.switchPositions = switchPositions
        self.routeRequests = routeRequests
        self.operatorInputs = operatorInputs
        self.timetableAssignments = timetableAssignments
    }

    private enum CodingKeys: String, CodingKey {
        case fixedTick, timeSeconds, trains, switchPositions, routeRequests, operatorInputs, timetableAssignments
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let fixedTick = try values.decode(UInt64.self, forKey: .fixedTick)
        let timeSeconds = try values.decode(Double.self, forKey: .timeSeconds)
        let decodedTrains = try values.decode([TrainState].self, forKey: .trains)
        let trains = try decodedTrains.map {
            try TrainState(id: $0.id, trackID: $0.trackID, frontPositionM: $0.frontPositionM,
                           speedKmh: $0.speedKmh, lengthM: $0.lengthM, direction: $0.direction)
        }
        let decodedAssignments = try values.decodeIfPresent([TimetableRouteAssignment].self, forKey: .timetableAssignments) ?? []
        let assignments = try decodedAssignments.map {
            try TimetableRouteAssignment(id: $0.id, trainID: $0.trainID, nextRouteID: $0.nextRouteID,
                                         plannedDepartureTimeSeconds: $0.plannedDepartureTimeSeconds)
        }
        try self.init(fixedTick: fixedTick, timeSeconds: timeSeconds, trains: trains,
                      switchPositions: values.decodeIfPresent([String: String].self, forKey: .switchPositions) ?? [:],
                      routeRequests: values.decodeIfPresent([String: String].self, forKey: .routeRequests) ?? [:],
                      operatorInputs: values.decodeIfPresent([String: OperatorInput].self, forKey: .operatorInputs) ?? [:],
                      timetableAssignments: assignments)
    }
}

public enum SimulationEventKind: String, Codable, CaseIterable, Equatable, Sendable {
    case equipmentApproach
    case warning
    case overspeed
    case automaticBrake
    case routeGranted
    case routeDenied
    case timetableRouteProposed
    case protectionReset
}

public struct SimulationEvent: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let kind: SimulationEventKind
    public let timeSeconds: Double
    public let trainID: String?
    public let system: String?
    public let sourceID: String?
    public let message: String
    public let speedKmh: Double?
    public let permittedSpeedKmh: Double?
    public let label: ProtectionModelLabel

    public init(id: String, kind: SimulationEventKind, timeSeconds: Double, trainID: String? = nil,
                system: String? = nil, sourceID: String? = nil, message: String,
                speedKmh: Double? = nil, permittedSpeedKmh: Double? = nil) {
        self.id = id
        self.kind = kind
        self.timeSeconds = timeSeconds
        self.trainID = trainID
        self.system = system
        self.sourceID = sourceID
        self.message = message
        self.speedKmh = speedKmh
        self.permittedSpeedKmh = permittedSpeedKmh
        self.label = .fictionalSimulationOnly
    }
}

public enum SignalAspect: String, Codable, CaseIterable, Equatable, Sendable {
    case stop
    case caution
    case proceed
}

public struct BlockOccupancy: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let trainIDs: [String]
    public var isOccupied: Bool { !trainIDs.isEmpty }
}

public struct RouteGrant: Codable, Equatable, Sendable, Identifiable {
    public var id: String { "\(trainID):\(routeID)" }
    public let trainID: String
    public let routeID: String
    public let granted: Bool
    public let denialReason: String?
}

public struct SignalState: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let aspect: SignalAspect
    public let reason: String
}

public struct ATOCommand: Codable, Equatable, Sendable {
    public let targetSpeedKmh: Double
    public let tractionFraction: Double
    public let brakeFraction: Double
    public let holdForRoute: Bool
    public let label: ProtectionModelLabel
}

public struct SystemProtectionState: Codable, Equatable, Sendable, Identifiable {
    public var id: String { "\(trainID):\(system)" }
    public let trainID: String
    public let system: String
    public let permittedSpeedKmh: Double?
    public let brakeCommanded: Bool
    public let stateDescription: String
}

public struct CTCTrainSummary: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let trackID: String
    public let frontPositionM: Double
    public let speedKmh: Double
    public let requestedRouteID: String?
    public let routeGranted: Bool?
    public let timetableDelaySeconds: Double?
}

public struct SimulationResult: Codable, Equatable, Sendable {
    public let fixedTick: UInt64
    public let timeSeconds: Double
    public let blockOccupancy: [BlockOccupancy]
    public let routeGrants: [RouteGrant]
    public let signals: [SignalState]
    public let protectionStates: [SystemProtectionState]
    public let atoCommands: [String: ATOCommand]
    public let ctcTrains: [CTCTrainSummary]
    public let events: [SimulationEvent]
    public let label: ProtectionModelLabel
}
