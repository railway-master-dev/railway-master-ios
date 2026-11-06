import Foundation

/// このモジュールは架空の教育用シミュレーション専用です。実設備・実運転の安全判断には使用できません。
public enum RailwaySignallingError: Error, Equatable, Sendable {
    case invalidValue(String)
    case emptyCollection(String)
    case duplicateIdentifier(String)
    case unknownIdentifier(String)
    case outOfRoute(String)
    case conflictingRoute(String)
    case timeMustIncrease
}

private func isFiniteNonnegative(_ value: Double) -> Bool {
    value.isFinite && value >= 0
}

public enum PointPosition: String, Codable, CaseIterable, Equatable, Sendable {
    case normal
    case reverse
}

public struct TrackBlock: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let startM: Double
    public let endM: Double

    public init(id: String, startM: Double, endM: Double) throws {
        guard !id.isEmpty, startM.isFinite, endM.isFinite, startM >= 0, endM > startM else {
            throw RailwaySignallingError.invalidValue("block id/startM/endM")
        }
        self.id = id
        self.startM = startM
        self.endM = endM
    }
}

public struct RailwayPoint: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let positionM: Double

    public init(id: String, positionM: Double) throws {
        guard !id.isEmpty, isFiniteNonnegative(positionM) else {
            throw RailwaySignallingError.invalidValue("point id/positionM")
        }
        self.id = id
        self.positionM = positionM
    }
}

/// 進路が要求する線路範囲、閉そく列、分岐器位置を表します。
public struct RailwayRouteDefinition: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let entryBlockID: String
    public let protectedBlockIDs: [String]
    public let requiredPointPositions: [String: PointPosition]

    public init(
        id: String,
        entryBlockID: String,
        protectedBlockIDs: [String],
        requiredPointPositions: [String: PointPosition] = [:]
    ) throws {
        guard !id.isEmpty, !entryBlockID.isEmpty, !protectedBlockIDs.isEmpty,
              Set(protectedBlockIDs).count == protectedBlockIDs.count,
              protectedBlockIDs.first == entryBlockID else {
            throw RailwaySignallingError.invalidValue("route id/blocks")
        }
        self.id = id
        self.entryBlockID = entryBlockID
        self.protectedBlockIDs = protectedBlockIDs
        self.requiredPointPositions = requiredPointPositions
    }
}

/// 速度制限は指定範囲 [startM, endM) に適用され、上限は km/h です。
public struct SpeedRestriction: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let startM: Double
    public let endM: Double
    public let maximumSpeedKmh: Double

    public init(id: String, startM: Double, endM: Double, maximumSpeedKmh: Double) throws {
        guard !id.isEmpty, startM.isFinite, endM.isFinite, startM >= 0, endM > startM,
              maximumSpeedKmh.isFinite, maximumSpeedKmh > 0 else {
            throw RailwaySignallingError.invalidValue("speed restriction")
        }
        self.id = id
        self.startM = startM
        self.endM = endM
        self.maximumSpeedKmh = maximumSpeedKmh
    }
}

/// 単一路線の静的な信号・運行設備データ。閉そくは路線全長を隙間なく覆います。
public struct RailwayTopology: Codable, Equatable, Sendable {
    public let lineID: String
    public let lengthM: Double
    public let defaultSpeedLimitKmh: Double
    public let blocks: [TrackBlock]
    public let points: [RailwayPoint]
    public let routes: [RailwayRouteDefinition]
    public let speedRestrictions: [SpeedRestriction]

    public init(
        lineID: String,
        lengthM: Double,
        defaultSpeedLimitKmh: Double,
        blocks: [TrackBlock],
        points: [RailwayPoint] = [],
        routes: [RailwayRouteDefinition] = [],
        speedRestrictions: [SpeedRestriction] = []
    ) throws {
        guard !lineID.isEmpty, lengthM.isFinite, lengthM > 0,
              defaultSpeedLimitKmh.isFinite, defaultSpeedLimitKmh > 0 else {
            throw RailwaySignallingError.invalidValue("lineID/length/defaultSpeedLimitKmh")
        }
        guard !blocks.isEmpty else { throw RailwaySignallingError.emptyCollection("blocks") }
        guard blocks.allSatisfy({ !$0.id.isEmpty && $0.startM.isFinite && $0.endM.isFinite && $0.startM >= 0 && $0.endM > $0.startM }) else {
            throw RailwaySignallingError.invalidValue("block fields")
        }
        guard points.allSatisfy({ !$0.id.isEmpty && isFiniteNonnegative($0.positionM) }) else {
            throw RailwaySignallingError.invalidValue("point fields")
        }
        guard routes.allSatisfy({
            !$0.id.isEmpty && !$0.entryBlockID.isEmpty && !$0.protectedBlockIDs.isEmpty &&
                $0.protectedBlockIDs.first == $0.entryBlockID &&
                Set($0.protectedBlockIDs).count == $0.protectedBlockIDs.count &&
                $0.requiredPointPositions.keys.allSatisfy { !$0.isEmpty }
        }) else {
            throw RailwaySignallingError.invalidValue("route fields")
        }
        guard speedRestrictions.allSatisfy({
            !$0.id.isEmpty && $0.startM.isFinite && $0.endM.isFinite && $0.startM >= 0 &&
                $0.endM > $0.startM && $0.maximumSpeedKmh.isFinite && $0.maximumSpeedKmh > 0
        }) else {
            throw RailwaySignallingError.invalidValue("speed restriction fields")
        }
        guard Set(blocks.map(\.id)).count == blocks.count else { throw RailwaySignallingError.duplicateIdentifier("block") }
        guard Set(points.map(\.id)).count == points.count else { throw RailwaySignallingError.duplicateIdentifier("point") }
        guard Set(routes.map(\.id)).count == routes.count else { throw RailwaySignallingError.duplicateIdentifier("route") }
        guard Set(speedRestrictions.map(\.id)).count == speedRestrictions.count else {
            throw RailwaySignallingError.duplicateIdentifier("speed restriction")
        }

        let orderedBlocks = blocks.sorted { $0.startM < $1.startM }
        guard abs(orderedBlocks[0].startM) <= 0.001,
              abs(orderedBlocks[orderedBlocks.count - 1].endM - lengthM) <= 0.001 else {
            throw RailwaySignallingError.invalidValue("blocks must cover the whole line")
        }
        for index in orderedBlocks.indices {
            let block = orderedBlocks[index]
            guard block.endM <= lengthM + 0.001 else {
                throw RailwaySignallingError.outOfRoute("block \(block.id)")
            }
            if index > 0 && abs(block.startM - orderedBlocks[index - 1].endM) > 0.001 {
                throw RailwaySignallingError.invalidValue("blocks must be contiguous and non-overlapping")
            }
        }
        let blockIDs = Set(orderedBlocks.map(\.id))
        let pointIDs = Set(points.map(\.id))
        for point in points where point.positionM > lengthM {
            throw RailwaySignallingError.outOfRoute("point \(point.id)")
        }
        for route in routes {
            guard blockIDs.contains(route.entryBlockID), route.protectedBlockIDs.allSatisfy(blockIDs.contains),
                  route.requiredPointPositions.keys.allSatisfy(pointIDs.contains) else {
                throw RailwaySignallingError.unknownIdentifier("route \(route.id) references missing equipment")
            }
        }
        for restriction in speedRestrictions where restriction.endM > lengthM {
            throw RailwaySignallingError.outOfRoute("speed restriction \(restriction.id)")
        }

        self.lineID = lineID
        self.lengthM = lengthM
        self.defaultSpeedLimitKmh = defaultSpeedLimitKmh
        self.blocks = orderedBlocks
        self.points = points.sorted { $0.positionM < $1.positionM }
        self.routes = routes
        self.speedRestrictions = speedRestrictions.sorted { $0.startM < $1.startM }
    }

    private enum CodingKeys: String, CodingKey {
        case lineID, lengthM, defaultSpeedLimitKmh, blocks, points, routes, speedRestrictions
    }

    /// Decoded route packages pass through the same checks as programmatically created data.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let lineID = try container.decode(String.self, forKey: .lineID)
        let lengthM = try container.decode(Double.self, forKey: .lengthM)
        let defaultSpeedLimitKmh = try container.decode(Double.self, forKey: .defaultSpeedLimitKmh)
        let blocks = try container.decode([TrackBlock].self, forKey: .blocks)
        let points = try container.decodeIfPresent([RailwayPoint].self, forKey: .points) ?? []
        let routes = try container.decodeIfPresent([RailwayRouteDefinition].self, forKey: .routes) ?? []
        let speedRestrictions = try container.decodeIfPresent([SpeedRestriction].self, forKey: .speedRestrictions) ?? []
        try self.init(
            lineID: lineID,
            lengthM: lengthM,
            defaultSpeedLimitKmh: defaultSpeedLimitKmh,
            blocks: blocks,
            points: points,
            routes: routes,
            speedRestrictions: speedRestrictions
        )
    }

}

/// 1列車のスナップショット。位置は列車先頭、進行方向はキロ程の増加方向です。
public struct TrainPositionSnapshot: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let lineID: String
    public let frontPositionM: Double
    public let speedMps: Double
    public let trainLengthM: Double

    public init(id: String, lineID: String, frontPositionM: Double, speedMps: Double, trainLengthM: Double) throws {
        guard !id.isEmpty, !lineID.isEmpty, isFiniteNonnegative(frontPositionM),
              isFiniteNonnegative(speedMps), trainLengthM.isFinite, trainLengthM > 0 else {
            throw RailwaySignallingError.invalidValue("train snapshot")
        }
        self.id = id
        self.lineID = lineID
        self.frontPositionM = frontPositionM
        self.speedMps = speedMps
        self.trainLengthM = trainLengthM
    }

    public var rearPositionM: Double { max(0, frontPositionM - trainLengthM) }
}

/// 各機能が同じ時刻の列車・分岐器・進路状態を読むための値型境界。
public struct RailwaySignallingSnapshot: Codable, Equatable, Sendable {
    public let simulationTimeSeconds: Double
    public let fixedTick: UInt64
    public let fixedTimeStepSeconds: Double
    public let trains: [TrainPositionSnapshot]
    public let pointPositions: [String: PointPosition]
    /// キーは列車ID、値は要求進路ID。
    public let routeRequests: [String: String]

    public init(
        simulationTimeSeconds: Double,
        fixedTick: UInt64 = 0,
        fixedTimeStepSeconds: Double = 1.0 / 120.0,
        trains: [TrainPositionSnapshot],
        pointPositions: [String: PointPosition] = [:],
        routeRequests: [String: String] = [:]
    ) throws {
        guard isFiniteNonnegative(simulationTimeSeconds), fixedTimeStepSeconds.isFinite, fixedTimeStepSeconds > 0 else {
            throw RailwaySignallingError.invalidValue("simulation clock")
        }
        guard Set(trains.map(\.id)).count == trains.count else {
            throw RailwaySignallingError.duplicateIdentifier("train")
        }
        guard routeRequests.keys.allSatisfy({ trainID in trains.contains(where: { $0.id == trainID }) }) else {
            throw RailwaySignallingError.unknownIdentifier("route request train")
        }
        guard routeRequests.values.allSatisfy({ !$0.isEmpty }) else {
            throw RailwaySignallingError.invalidValue("route request")
        }
        self.simulationTimeSeconds = simulationTimeSeconds
        self.fixedTick = fixedTick
        self.fixedTimeStepSeconds = fixedTimeStepSeconds
        self.trains = trains
        self.pointPositions = pointPositions
        self.routeRequests = routeRequests
    }
}
