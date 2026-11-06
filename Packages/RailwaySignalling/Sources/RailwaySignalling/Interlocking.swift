import Foundation

public enum RailwayModelLabel: String, Codable, Equatable, Sendable {
    case virtualEducational = "VIRTUAL / EDUCATIONAL ONLY"
}

public enum SignalAspect: String, Codable, CaseIterable, Equatable, Sendable {
    case stop
    case caution
    case proceed
}

public struct SignalReading: Codable, Equatable, Sendable {
    public let blockID: String
    public let aspect: SignalAspect
    public let signalPositionM: Double
    public let occupiedBlockIDs: [String]
    public let explanation: String
    public let label: RailwayModelLabel
}

public struct RouteGrantReading: Codable, Equatable, Sendable {
    public let routeID: String
    public let trainID: String
    public let isGranted: Bool
    public let denialReason: String?
    public let label: RailwayModelLabel
}

/// 閉そく占有と進路要求から教材用の3現示、および分岐器を含む進路許可を算出します。
/// これは実在の連動装置・信号方式を再現または認証するものではありません。
public struct RailwayInterlocking: Sendable {
    public let topology: RailwayTopology

    public init(topology: RailwayTopology) {
        self.topology = topology
    }

    public func occupiedBlockIDs(in snapshot: RailwaySignallingSnapshot) throws -> Set<String> {
        try validate(snapshot)
        return Set(topology.blocks.filter { block in
            snapshot.trains.contains { train in
                train.frontPositionM >= block.startM && train.rearPositionM < block.endM
            }
        }.map(\.id))
    }

    public func grant(routeID: String, to trainID: String, in snapshot: RailwaySignallingSnapshot) throws -> RouteGrantReading {
        try validate(snapshot)
        guard let route = topology.routes.first(where: { $0.id == routeID }) else {
            throw RailwaySignallingError.unknownIdentifier("route \(routeID)")
        }
        guard snapshot.trains.contains(where: { $0.id == trainID }) else {
            throw RailwaySignallingError.unknownIdentifier("train \(trainID)")
        }
        guard snapshot.routeRequests[trainID] == routeID else {
            return denied(routeID, trainID, "この列車からの進路要求がありません。")
        }

        for (pointID, requiredPosition) in route.requiredPointPositions {
            guard snapshot.pointPositions[pointID] == requiredPosition else {
                return denied(routeID, trainID, "分岐器 \(pointID) の位置が要求と一致しません。")
            }
        }

        let occupied = try occupiedBlockIDs(in: snapshot)
        let otherTrainIDs = Set(snapshot.trains.map(\.id)).subtracting([trainID])
        for blockID in route.protectedBlockIDs where occupied.contains(blockID) {
            let occupiedByAnotherTrain = snapshot.trains.contains { train in
                otherTrainIDs.contains(train.id) &&
                    topology.blocks.first(where: { $0.id == blockID }).map {
                        train.frontPositionM >= $0.startM && train.rearPositionM < $0.endM
                    } == true
            }
            if occupiedByAnotherTrain {
                return denied(routeID, trainID, "進路内の閉そく \(blockID) が他列車に占有されています。")
            }
        }

        for (otherTrainID, otherRouteID) in snapshot.routeRequests where otherTrainID != trainID {
            guard let otherRoute = topology.routes.first(where: { $0.id == otherRouteID }) else { continue }
            let sharedBlocks = Set(route.protectedBlockIDs).intersection(otherRoute.protectedBlockIDs)
            let sharedPoints = Set(route.requiredPointPositions.keys).intersection(otherRoute.requiredPointPositions.keys)
            if !sharedBlocks.isEmpty || !sharedPoints.isEmpty {
                return denied(routeID, trainID, "他列車の進路 \(otherRouteID) と閉そくまたは分岐器が競合します。")
            }
        }

        return RouteGrantReading(routeID: routeID, trainID: trainID, isGranted: true, denialReason: nil, label: .virtualEducational)
    }

    /// blockIDで示す閉そくを守る信号現示を返します。線路はキロ程増加方向へ進む単一路線です。
    public func signal(for blockID: String, in snapshot: RailwaySignallingSnapshot) throws -> SignalReading {
        try validate(snapshot)
        guard let index = topology.blocks.firstIndex(where: { $0.id == blockID }) else {
            throw RailwaySignallingError.unknownIdentifier("block \(blockID)")
        }
        let block = topology.blocks[index]
        let occupied = try occupiedBlockIDs(in: snapshot)
        let occupiedOrdered = topology.blocks.filter { occupied.contains($0.id) }.map(\.id)
        let routeOptions = topology.routes.filter { $0.entryBlockID == blockID }

        if !routeOptions.isEmpty {
            let routeIDs = Set(routeOptions.map(\.id))
            let request = snapshot.routeRequests.sorted { $0.key < $1.key }.first { routeIDs.contains($0.value) }
            guard let request else {
                return reading(block, .stop, occupiedOrdered, "進路が設定されていません。")
            }
            let grant = try self.grant(routeID: request.value, to: request.key, in: snapshot)
            guard grant.isGranted else {
                return reading(block, .stop, occupiedOrdered, grant.denialReason ?? "進路が許可されていません。")
            }
        }

        if occupied.contains(blockID) {
            return reading(block, .stop, occupiedOrdered, "保護する閉そくが占有されています。")
        }
        if index + 1 < topology.blocks.count, occupied.contains(topology.blocks[index + 1].id) {
            return reading(block, .caution, occupiedOrdered, "直後の閉そくが占有されています。")
        }
        return reading(block, .proceed, occupiedOrdered, "保護する閉そくと直後の閉そくが空いています。")
    }

    private func validate(_ snapshot: RailwaySignallingSnapshot) throws {
        guard snapshot.simulationTimeSeconds.isFinite, snapshot.simulationTimeSeconds >= 0,
              snapshot.fixedTimeStepSeconds.isFinite, snapshot.fixedTimeStepSeconds > 0,
              Set(snapshot.trains.map(\.id)).count == snapshot.trains.count else {
            throw RailwaySignallingError.invalidValue("snapshot time/train identifiers")
        }
        for train in snapshot.trains {
            guard !train.id.isEmpty, train.lineID == topology.lineID,
                  train.frontPositionM.isFinite, train.frontPositionM >= 0,
                  train.speedMps.isFinite, train.speedMps >= 0,
                  train.trainLengthM.isFinite, train.trainLengthM > 0 else {
                throw RailwaySignallingError.invalidValue("train \(train.id) snapshot fields/lineID")
            }
            guard train.frontPositionM <= topology.lengthM + 0.001 else {
                throw RailwaySignallingError.outOfRoute("train \(train.id)")
            }
        }
        let knownPointIDs = Set(topology.points.map(\.id))
        guard snapshot.pointPositions.keys.allSatisfy(knownPointIDs.contains) else {
            throw RailwaySignallingError.unknownIdentifier("point state")
        }
        let knownRouteIDs = Set(topology.routes.map(\.id))
        let knownTrainIDs = Set(snapshot.trains.map(\.id))
        guard snapshot.routeRequests.keys.allSatisfy(knownTrainIDs.contains),
              snapshot.routeRequests.values.allSatisfy(knownRouteIDs.contains) else {
            throw RailwaySignallingError.unknownIdentifier("route request")
        }
    }

    private func denied(_ routeID: String, _ trainID: String, _ reason: String) -> RouteGrantReading {
        RouteGrantReading(routeID: routeID, trainID: trainID, isGranted: false, denialReason: reason, label: .virtualEducational)
    }

    private func reading(_ block: TrackBlock, _ aspect: SignalAspect, _ occupied: [String], _ explanation: String) -> SignalReading {
        SignalReading(blockID: block.id, aspect: aspect, signalPositionM: block.startM,
                      occupiedBlockIDs: occupied, explanation: explanation, label: .virtualEducational)
    }
}
