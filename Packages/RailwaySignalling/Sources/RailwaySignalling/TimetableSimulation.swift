import Foundation

public struct TimetableTrainPlan: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let scheduledDepartureSeconds: Int
    public let initialPositionM: Double
    public let targetSpeedMps: Double
    public let trainLengthM: Double
    public let maximumAccelerationMps2: Double
    public let serviceDecelerationMps2: Double

    public init(
        id: String,
        scheduledDepartureSeconds: Int,
        initialPositionM: Double,
        targetSpeedMps: Double,
        trainLengthM: Double,
        maximumAccelerationMps2: Double,
        serviceDecelerationMps2: Double
    ) throws {
        guard !id.isEmpty, scheduledDepartureSeconds >= 0,
              initialPositionM.isFinite, initialPositionM >= 0,
              targetSpeedMps.isFinite, targetSpeedMps >= 0,
              trainLengthM.isFinite, trainLengthM > 0,
              maximumAccelerationMps2.isFinite, maximumAccelerationMps2 > 0,
              serviceDecelerationMps2.isFinite, serviceDecelerationMps2 > 0 else {
            throw RailwaySignallingError.invalidValue("timetable train plan")
        }
        self.id = id
        self.scheduledDepartureSeconds = scheduledDepartureSeconds
        self.initialPositionM = initialPositionM
        self.targetSpeedMps = targetSpeedMps
        self.trainLengthM = trainLengthM
        self.maximumAccelerationMps2 = maximumAccelerationMps2
        self.serviceDecelerationMps2 = serviceDecelerationMps2
    }
}

public struct TimetableTrainState: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let scheduledDepartureSeconds: Int
    public let actualDepartureSeconds: Int?
    public let positionM: Double
    public let speedMps: Double
    public let trainLengthM: Double
    public var isDispatched: Bool { actualDepartureSeconds != nil }
    public var delaySeconds: Int? { actualDepartureSeconds.map { max(0, $0 - scheduledDepartureSeconds) } }
}

public struct TimetableFrame: Codable, Equatable, Sendable {
    public let elapsedSeconds: Int
    public let trains: [TimetableTrainState]
    public let label: RailwayModelLabel
}

/// 決定的な1秒刻みの教材用運行モデルです。車両性能を証明する安全シミュレーターではありません。
public struct RailwayTimetableSimulator: Sendable {
    public let topology: RailwayTopology
    public let minimumSeparationM: Double
    public let safetyMarginM: Double
    public private(set) var trains: [TimetableTrainState]
    public private(set) var elapsedSeconds: Int
    private let plansByID: [String: TimetableTrainPlan]
    private let speedProfile: VirtualSpeedProfile

    public init(
        topology: RailwayTopology,
        plans: [TimetableTrainPlan],
        minimumSeparationM: Double = 20,
        safetyMarginM: Double = 5
    ) throws {
        guard !plans.isEmpty else { throw RailwaySignallingError.emptyCollection("timetable plans") }
        guard Set(plans.map(\.id)).count == plans.count else {
            throw RailwaySignallingError.duplicateIdentifier("timetable train")
        }
        guard minimumSeparationM.isFinite, minimumSeparationM >= 0,
              safetyMarginM.isFinite, safetyMarginM >= 0 else {
            throw RailwaySignallingError.invalidValue("separation/safety margin")
        }
        guard plans.allSatisfy({ $0.initialPositionM < topology.lengthM && $0.trainLengthM <= topology.lengthM }) else {
            throw RailwaySignallingError.outOfRoute("timetable train start")
        }
        self.topology = topology
        self.minimumSeparationM = minimumSeparationM
        self.safetyMarginM = safetyMarginM
        self.trains = plans.sorted { $0.id < $1.id }.map {
            TimetableTrainState(id: $0.id, scheduledDepartureSeconds: $0.scheduledDepartureSeconds,
                                actualDepartureSeconds: nil, positionM: $0.initialPositionM,
                                speedMps: 0, trainLengthM: $0.trainLengthM)
        }
        self.elapsedSeconds = 0
        self.plansByID = Dictionary(uniqueKeysWithValues: plans.map { ($0.id, $0) })
        self.speedProfile = try VirtualSpeedProfile(topology: topology,
                                                    serviceDecelerationMps2: plans.map(\.serviceDecelerationMps2).min() ?? 0.1,
                                                    safetyMarginM: safetyMarginM)
    }

    /// シミュレーション時計をちょうど1秒進め、全列車を安定ID順で決定的に更新します。
    @discardableResult
    public mutating func advanceOneSecond() throws -> TimetableFrame {
        let nextTime = elapsedSeconds + 1
        var next = trains

        // 予定時刻到来後、出発位置に最低間隔を確保できる列車から実発車します。
        let pendingIndices = next.indices.filter {
            next[$0].actualDepartureSeconds == nil && next[$0].scheduledDepartureSeconds <= nextTime
        }.sorted {
            if next[$0].scheduledDepartureSeconds != next[$1].scheduledDepartureSeconds {
                return next[$0].scheduledDepartureSeconds < next[$1].scheduledDepartureSeconds
            }
            return next[$0].id < next[$1].id
        }
        for index in pendingIndices {
            let candidatePosition = next[index].positionM
            let candidateLength = next[index].trainLengthM
            let hasSafeGap = next.indices.filter { $0 != index && next[$0].isDispatched }.allSatisfy { otherIndex in
                let other = next[otherIndex]
                let availableGap: Double
                if other.positionM >= candidatePosition {
                    availableGap = other.positionM - other.trainLengthM - candidatePosition
                } else {
                    availableGap = candidatePosition - candidateLength - other.positionM
                }
                return availableGap >= minimumSeparationM
            }
            guard hasSafeGap else { continue }
            next[index] = TimetableTrainState(id: next[index].id,
                                              scheduledDepartureSeconds: next[index].scheduledDepartureSeconds,
                                              actualDepartureSeconds: nextTime,
                                              positionM: next[index].positionM,
                                              speedMps: 0,
                                              trainLengthM: next[index].trainLengthM)
        }

        let orderedIndices = next.indices.filter { next[$0].isDispatched }.sorted {
            if next[$0].positionM != next[$1].positionM { return next[$0].positionM > next[$1].positionM }
            return next[$0].id < next[$1].id
        }
        for index in orderedIndices {
            let current = next[index]
            let plan = plansByID[current.id]!
            let leader = orderedIndices
                .filter { $0 != index && next[$0].positionM > current.positionM }
                .map { next[$0] }
                .min { $0.positionM < $1.positionM }
            let speedReading = try speedProfile.reading(atPositionM: min(current.positionM, topology.lengthM))
            var capMps = min(plan.targetSpeedMps, speedReading.permittedSpeedKmh / 3.6)
            let distanceToEndM = max(0, topology.lengthM - current.positionM - safetyMarginM)
            capMps = min(capMps, sqrt(2 * plan.serviceDecelerationMps2 * distanceToEndM))
            if let leader {
                let gapM = max(0, leader.positionM - leader.trainLengthM - current.positionM - minimumSeparationM - safetyMarginM)
                capMps = min(capMps, sqrt(2 * plan.serviceDecelerationMps2 * gapM))
            }

            let speedDelta = capMps - current.speedMps
            let appliedDelta = min(plan.maximumAccelerationMps2, max(-plan.serviceDecelerationMps2, speedDelta))
            let newSpeed = max(0, current.speedMps + appliedDelta)
            let proposedPosition = current.positionM + (current.speedMps + newSpeed) * 0.5
            var newPosition = min(topology.lengthM, proposedPosition)
            var safeSpeed = newPosition >= topology.lengthM ? 0 : newSpeed

            if let leader {
                let maximumFrontM = max(0, leader.positionM - leader.trainLengthM - minimumSeparationM)
                if newPosition > maximumFrontM {
                    newPosition = maximumFrontM
                    safeSpeed = 0
                }
            }
            next[index] = TimetableTrainState(id: current.id,
                                              scheduledDepartureSeconds: current.scheduledDepartureSeconds,
                                              actualDepartureSeconds: current.actualDepartureSeconds,
                                              positionM: newPosition,
                                              speedMps: safeSpeed,
                                              trainLengthM: current.trainLengthM)
        }

        // 二次の幾何制約で数値誤差や1秒刻みの overshoot が最小間隔を割らないようにします。
        let frontToBack = next.indices.filter { next[$0].isDispatched }.sorted {
            if next[$0].positionM != next[$1].positionM { return next[$0].positionM > next[$1].positionM }
            return next[$0].id < next[$1].id
        }
        if frontToBack.count > 1 {
            for order in 1..<frontToBack.count {
                let leaderIndex = frontToBack[order - 1]
                let followerIndex = frontToBack[order]
                let maximumFrontM = max(0, next[leaderIndex].positionM - next[leaderIndex].trainLengthM - minimumSeparationM)
                if next[followerIndex].positionM > maximumFrontM {
                    next[followerIndex] = TimetableTrainState(
                        id: next[followerIndex].id,
                        scheduledDepartureSeconds: next[followerIndex].scheduledDepartureSeconds,
                        actualDepartureSeconds: next[followerIndex].actualDepartureSeconds,
                        positionM: maximumFrontM,
                        speedMps: 0,
                        trainLengthM: next[followerIndex].trainLengthM
                    )
                }
            }
        }

        trains = next
        elapsedSeconds = nextTime
        return frame
    }

    public var frame: TimetableFrame {
        TimetableFrame(elapsedSeconds: elapsedSeconds, trains: trains, label: .virtualEducational)
    }
}
