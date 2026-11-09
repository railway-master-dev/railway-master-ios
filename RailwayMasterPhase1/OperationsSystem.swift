import Foundation

// MARK: - Shared validation and labeling

/// すべて架空の教材用データであり、実設備・実運転の安全判断には使用できません。
public enum OperationsSystemLabel: String, Codable, Sendable {
    case fictionalEducational = "FICTIONAL / EDUCATIONAL ONLY"
}

public enum OperationsValidationError: Error, Equatable, Sendable {
    case invalidValue(String)
    case emptyCollection(String)
    case duplicateIdentifier(String)
    case outOfRoute(String)
    case timeMustIncrease
}

private func isFiniteNonnegative(_ value: Double) -> Bool {
    value.isFinite && value >= 0
}

// MARK: - Kilometre-post block occupancy and three-aspect signals

public struct RailwayBlock: Codable, Equatable, Sendable {
    public let identifier: String
    /// Independent track identifier; overlaps between different tracks are allowed.
    public let trackID: String
    /// ブロック始端キロ程 [m]。
    public let startM: Double
    /// ブロック終端キロ程 [m]。
    public let endM: Double

    public init(identifier: String, startM: Double, endM: Double, trackID: String = "default") throws {
        guard !identifier.isEmpty, !trackID.isEmpty, startM.isFinite, endM.isFinite, startM >= 0, endM > startM else {
            throw OperationsValidationError.invalidValue("block identifier/startM/endM")
        }
        self.identifier = identifier
        self.trackID = trackID
        self.startM = startM
        self.endM = endM
    }
}

public struct BlockOccupant: Codable, Equatable, Sendable {
    public let trainID: String
    public let trackID: String
    /// 列車先頭のキロ程 [m]。
    public let frontPositionM: Double
    /// 列車長 [m]。
    public let trainLengthM: Double

    public init(trainID: String, frontPositionM: Double, trainLengthM: Double, trackID: String = "default") throws {
        guard !trainID.isEmpty, !trackID.isEmpty, isFiniteNonnegative(frontPositionM), trainLengthM.isFinite, trainLengthM > 0 else {
            throw OperationsValidationError.invalidValue("occupant trainID/frontPositionM/trainLengthM")
        }
        self.trainID = trainID
        self.trackID = trackID
        self.frontPositionM = frontPositionM
        self.trainLengthM = trainLengthM
    }

    fileprivate var rearPositionM: Double { max(0, frontPositionM - trainLengthM) }
}

public enum ThreeAspectSignal: String, Codable, CaseIterable, Sendable {
    case red
    case yellow
    case green
}

public struct BlockSignalReading: Codable, Equatable, Sendable {
    public let blockID: String
    public let aspect: ThreeAspectSignal
    /// 対象ブロックの始端 [m]。赤信号の停止目標として利用できます。
    public let blockStartM: Double
    public let label: OperationsSystemLabel
}

/// 先頭・最後尾のキロ程とブロック重複に基づく教材用の3現示。
/// 対象ブロック占有=赤、次ブロック占有=黄、それ以外=緑。
public struct ThreeAspectBlockSystem: Codable, Equatable, Sendable {
    public let blocks: [RailwayBlock]
    public let label: OperationsSystemLabel

    public init(blocks: [RailwayBlock]) throws {
        guard !blocks.isEmpty else { throw OperationsValidationError.emptyCollection("blocks") }
        let ordered = blocks.sorted { lhs, rhs in
            lhs.startM == rhs.startM ? lhs.trackID < rhs.trackID : lhs.startM < rhs.startM
        }
        guard Set(ordered.map(\.identifier)).count == ordered.count else {
            throw OperationsValidationError.duplicateIdentifier("block id")
        }
        for trackGroup in Dictionary(grouping: ordered, by: \.trackID).values {
            let trackBlocks = trackGroup.sorted { $0.startM < $1.startM }
            for index in trackBlocks.indices where index > 0 {
                if trackBlocks[index].startM < trackBlocks[index - 1].endM - 0.001 {
                    throw OperationsValidationError.invalidValue("blocks overlap")
                }
            }
        }
        self.blocks = ordered
        self.label = .fictionalEducational
    }

    public func occupiedBlockIDs(by occupants: [BlockOccupant]) -> Set<String> {
        Set(blocks.filter { block in
            occupants.contains { occupant in
                occupant.trackID == block.trackID &&
                occupant.frontPositionM >= block.startM && occupant.rearPositionM < block.endM
            }
        }.map(\.identifier))
    }

    /// `blockID` は信号が守るブロック。黄色は直後のブロックが占有中を示します。
    public func reading(for blockID: String, occupants: [BlockOccupant]) -> BlockSignalReading? {
        guard let index = blocks.firstIndex(where: { $0.identifier == blockID }) else { return nil }
        let occupied = occupiedBlockIDs(by: occupants)
        let block = blocks[index]
        let aspect: ThreeAspectSignal
        if occupied.contains(block.identifier) {
            aspect = .red
        } else if let nextBlock = blocks.first(where: {
            $0.trackID == block.trackID && $0.startM >= block.endM - 0.001
        }), occupied.contains(nextBlock.identifier) {
            aspect = .yellow
        } else {
            aspect = .green
        }
        return BlockSignalReading(blockID: block.identifier, aspect: aspect, blockStartM: block.startM, label: .fictionalEducational)
    }

    public func reading(at positionM: Double, occupants: [BlockOccupant]) -> BlockSignalReading? {
        guard positionM.isFinite, let block = blocks.first(where: { positionM >= $0.startM && positionM < $0.endM }) else { return nil }
        return reading(for: block.identifier, occupants: occupants)
    }
}

// MARK: - Safety speed pattern

public struct SafetyStopTarget: Codable, Equatable, Sendable {
    public let identifier: String
    /// 停止点または目標点のキロ程 [m]。
    public let positionM: Double
    /// 目標点で許容する速度 [km/h]。停止目標は0。
    public let targetSpeedKmh: Double
    /// 目標ごとの余裕距離の上書き [m]。nil の場合はパターン全体の余裕を使う。
    /// 駅停止目標は 0 を渡す：全体の余裕（18m）を駅停止にも適用すると許容速度が
    /// 停止位置の18m手前で0になり、列車が駅に到達できない（CI #213で実証）。
    public let safetyMarginM: Double?

    public init(identifier: String, positionM: Double, targetSpeedKmh: Double = 0, safetyMarginM: Double? = nil) throws {
        guard !identifier.isEmpty, isFiniteNonnegative(positionM), isFiniteNonnegative(targetSpeedKmh) else {
            throw OperationsValidationError.invalidValue("safety target")
        }
        if let safetyMarginM, !isFiniteNonnegative(safetyMarginM) {
            throw OperationsValidationError.invalidValue("safety target margin")
        }
        self.identifier = identifier
        self.positionM = positionM
        self.targetSpeedKmh = targetSpeedKmh
        self.safetyMarginM = safetyMarginM
    }
}

public struct SpeedPatternPoint: Codable, Equatable, Sendable {
    public let positionM: Double
    public let permittedSpeedKmh: Double
    public let limitingTargetID: String?
}

/// 路線制限と停止・速度目標から、一定減速度の平方根制動包絡を計算します。
/// これは教材用の単純化で、制動遅れ・勾配・粘着・実車性能を保証しません。
public struct RailwaySafetySpeedPattern: Codable, Equatable, Sendable {
    public let route: RailwayRouteProfile
    public let targets: [SafetyStopTarget]
    /// 想定減速度 [m/s²]。
    public let serviceDecelerationMps2: Double
    /// 目標点手前の余裕距離 [m]。
    public let safetyMarginM: Double
    public let label: OperationsSystemLabel

    public init(route: RailwayRouteProfile, targets: [SafetyStopTarget], serviceDecelerationMps2: Double, safetyMarginM: Double = 0) throws {
        guard serviceDecelerationMps2.isFinite, serviceDecelerationMps2 > 0, isFiniteNonnegative(safetyMarginM) else {
            throw OperationsValidationError.invalidValue("deceleration/safetyMarginM")
        }
        guard targets.allSatisfy({ $0.positionM <= route.distanceM && $0.targetSpeedKmh.isFinite }) else {
            throw OperationsValidationError.outOfRoute("targets")
        }
        self.route = route
        self.targets = targets.sorted { $0.positionM < $1.positionM }
        self.serviceDecelerationMps2 = serviceDecelerationMps2
        self.safetyMarginM = safetyMarginM
        self.label = .fictionalEducational
    }

    public func permittedSpeedKmh(atPositionM positionM: Double) -> Double {
        let position = min(max(positionM, 0), route.distanceM)
        var permitted = max(0, route.condition(at: position).speedLimitKmh)
        for target in targets where target.positionM >= position {
            let availableDistanceM = max(0, target.positionM - position - (target.safetyMarginM ?? safetyMarginM))
            let targetMps = target.targetSpeedKmh / 3.6
            let envelopeKmh = sqrt(targetMps * targetMps + 2 * serviceDecelerationMps2 * availableDistanceM) * 3.6
            permitted = min(permitted, envelopeKmh)
        }
        return permitted
    }

    /// 表示用の一定キロ程サンプル [m]。正の刻み幅が必要です。
    public func sample(stepM: Double) throws -> [SpeedPatternPoint] {
        guard stepM.isFinite, stepM > 0 else { throw OperationsValidationError.invalidValue("stepM") }
        var result: [SpeedPatternPoint] = []
        var position = 0.0
        while position < route.distanceM {
            let limiting = targets.filter { $0.positionM >= position }.min { lhs, rhs in
                let left = lhs.targetSpeedKmh / 3.6
                let right = rhs.targetSpeedKmh / 3.6
                let leftCap = sqrt(left * left + 2 * serviceDecelerationMps2 * max(0, lhs.positionM - position - (lhs.safetyMarginM ?? safetyMarginM))) * 3.6
                let rightCap = sqrt(right * right + 2 * serviceDecelerationMps2 * max(0, rhs.positionM - position - (rhs.safetyMarginM ?? safetyMarginM))) * 3.6
                return leftCap < rightCap
            }
            result.append(SpeedPatternPoint(positionM: position, permittedSpeedKmh: permittedSpeedKmh(atPositionM: position), limitingTargetID: limiting?.identifier))
            position += stepM
        }
        result.append(SpeedPatternPoint(positionM: route.distanceM, permittedSpeedKmh: permittedSpeedKmh(atPositionM: route.distanceM), limitingTargetID: nil))
        return result
    }
}

// MARK: - Deterministic multi-train schedule simulation

public struct ScheduledTrain: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let trackID: String
    /// 先頭キロ程 [m]。
    public var positionM: Double
    /// 速度 [m/s]。
    public var speedMps: Double
    /// 加速度 [m/s²]。
    public var accelerationMps2: Double
    /// 指令速度 [m/s]。
    public var commandedSpeedMps: Double
    /// 車両制限速度 [m/s]。
    public let maximumSpeedMps: Double
    /// 加速上限 [m/s²]。
    public let maximumAccelerationMps2: Double
    /// 常用減速度上限 [m/s²]。
    public let serviceDecelerationMps2: Double
    /// 編成長 [m]。
    public let lengthM: Double

    public init(id: String, positionM: Double, speedMps: Double, accelerationMps2: Double = 0, commandedSpeedMps: Double, maximumSpeedMps: Double, maximumAccelerationMps2: Double, serviceDecelerationMps2: Double, lengthM: Double, trackID: String = "default") throws {
        guard !id.isEmpty, !trackID.isEmpty, isFiniteNonnegative(positionM), isFiniteNonnegative(speedMps), accelerationMps2.isFinite, isFiniteNonnegative(commandedSpeedMps), maximumSpeedMps.isFinite, maximumSpeedMps > 0, maximumAccelerationMps2.isFinite, maximumAccelerationMps2 > 0, serviceDecelerationMps2.isFinite, serviceDecelerationMps2 > 0, lengthM.isFinite, lengthM > 0, speedMps <= maximumSpeedMps else {
            throw OperationsValidationError.invalidValue("scheduled train parameters")
        }
        self.id = id
        self.trackID = trackID
        self.positionM = positionM
        self.speedMps = speedMps
        self.accelerationMps2 = accelerationMps2
        self.commandedSpeedMps = min(commandedSpeedMps, maximumSpeedMps)
        self.maximumSpeedMps = maximumSpeedMps
        self.maximumAccelerationMps2 = maximumAccelerationMps2
        self.serviceDecelerationMps2 = serviceDecelerationMps2
        self.lengthM = lengthM
    }
}

public struct ScheduleTrainState: Codable, Equatable, Sendable {
    public let id: String
    public let trackID: String
    public let positionM: Double
    public let speedMps: Double
    public let accelerationMps2: Double
    public let permittedSpeedMps: Double
}

public struct RailwayScheduleFrame: Codable, Equatable, Sendable {
    /// シミュレーション経過時間 [s]。
    public let elapsedSeconds: Double
    public let trains: [ScheduleTrainState]
    public let label: OperationsSystemLabel
}

/// すべての列車を同一の旧状態から評価して同時更新するため、配列順に依存しません。
/// 固定時間刻みは内部に持たず、呼び出し側が各 `advance(timeStepSeconds:)` に渡します。
public struct RailwayScheduleEngine: Codable, Equatable, Sendable {
    public let route: RailwayRouteProfile
    public let blocks: ThreeAspectBlockSystem
    public private(set) var trains: [ScheduledTrain]
    public private(set) var elapsedSeconds: Double
    public let minimumSeparationM: Double
    public let safetyMarginM: Double
    public let label: OperationsSystemLabel

    public init(route: RailwayRouteProfile, blocks: ThreeAspectBlockSystem, trains: [ScheduledTrain], minimumSeparationM: Double = 20, safetyMarginM: Double = 5) throws {
        guard !trains.isEmpty else { throw OperationsValidationError.emptyCollection("trains") }
        guard Set(trains.map(\.id)).count == trains.count else { throw OperationsValidationError.duplicateIdentifier("train id") }
        guard isFiniteNonnegative(minimumSeparationM), isFiniteNonnegative(safetyMarginM) else { throw OperationsValidationError.invalidValue("separation/margin") }
        guard trains.allSatisfy({ $0.positionM <= route.distanceM }) && blocks.blocks.allSatisfy({ $0.endM <= route.distanceM + 0.001 }) else {
            throw OperationsValidationError.outOfRoute("trains/blocks")
        }
        for trackGroup in Dictionary(grouping: trains, by: \.trackID).values {
            let byPosition = trackGroup.sorted { $0.positionM < $1.positionM }
            for index in 0..<max(byPosition.count - 1, 0) {
                let follower = byPosition[index]
                let leader = byPosition[index + 1]
                guard leader.positionM - leader.lengthM - follower.positionM >= minimumSeparationM else {
                    throw OperationsValidationError.invalidValue("initial train separation")
                }
            }
        }
        self.route = route
        self.blocks = blocks
        self.trains = trains.sorted { $0.id < $1.id }
        self.elapsedSeconds = 0
        self.minimumSeparationM = minimumSeparationM
        self.safetyMarginM = safetyMarginM
        self.label = .fictionalEducational
    }

    /// 指令速度変更 [m/s]。
    public mutating func setCommandedSpeed(_ speedMps: Double, for trainID: String) throws {
        guard isFiniteNonnegative(speedMps), let index = trains.firstIndex(where: { $0.id == trainID }) else {
            throw OperationsValidationError.invalidValue("commanded speed or trainID")
        }
        trains[index].commandedSpeedMps = min(speedMps, trains[index].maximumSpeedMps)
    }

    /// 1回の呼び出しで全列車を並列スナップショット更新。戻り値は更新後状態です。
    @discardableResult
    public mutating func advance(timeStepSeconds dt: Double, externalOccupants: [BlockOccupant] = []) throws -> RailwayScheduleFrame {
        guard dt.isFinite, dt > 0 else { throw OperationsValidationError.invalidValue("timeStepSeconds") }
        let previous = trains
        var next = previous
        for index in previous.indices {
            let train = previous[index]
            let leader = previous.filter { $0.id != train.id && $0.trackID == train.trackID && $0.positionM > train.positionM }
                .min { lhs, rhs in lhs.positionM < rhs.positionM }
            var capMps = min(train.commandedSpeedMps, min(train.maximumSpeedMps, route.condition(at: train.positionM).speedLimitKmh / 3.6))
            let terminalDistanceM = max(0, route.distanceM - train.positionM - safetyMarginM)
            capMps = min(capMps, sqrt(max(0, 2 * train.serviceDecelerationMps2 * terminalDistanceM)))

            if let leader {
                let safeFrontM = max(train.positionM, leader.positionM - leader.lengthM - minimumSeparationM - safetyMarginM)
                let distanceM = max(0, safeFrontM - train.positionM)
                capMps = min(capMps, sqrt(max(0, 2 * train.serviceDecelerationMps2 * distanceM)))
            }

            // Red signal target: first occupied block ahead, using a snapshot of every other train.
            var otherOccupants = previous.filter { $0.id != train.id }.compactMap {
                try? BlockOccupant(trainID: $0.id, frontPositionM: $0.positionM, trainLengthM: $0.lengthM, trackID: $0.trackID)
            }
            otherOccupants.append(contentsOf: externalOccupants.filter { $0.trainID != train.id })
            if let occupiedAhead = blocks.blocks.first(where: { block in
                block.trackID == train.trackID &&
                block.startM >= train.positionM && otherOccupants.contains { occupant in
                    occupant.trackID == block.trackID &&
                    occupant.frontPositionM >= block.startM && occupant.rearPositionM < block.endM
                }
            }) {
                let stopM = max(train.positionM, occupiedAhead.startM - safetyMarginM)
                let distanceM = max(0, stopM - train.positionM)
                capMps = min(capMps, sqrt(max(0, 2 * train.serviceDecelerationMps2 * distanceM)))
            }

            let desiredAcceleration = (capMps - train.speedMps) / dt
            let acceleration = min(train.maximumAccelerationMps2, max(-train.serviceDecelerationMps2, desiredAcceleration))
            let newSpeed = max(0, min(train.maximumSpeedMps, train.speedMps + acceleration * dt))
            let travelM = max(0, (train.speedMps + newSpeed) * 0.5 * dt)
            let newPosition = min(route.distanceM, train.positionM + travelM)
            next[index].accelerationMps2 = newPosition >= route.distanceM ? 0 : (newSpeed - train.speedMps) / dt
            next[index].speedMps = newPosition >= route.distanceM ? 0 : newSpeed
            next[index].positionM = newPosition
            next[index].commandedSpeedMps = train.commandedSpeedMps
        }

        // 位置差が数値誤差等で最小間隔を割らないよう、旧位置順に後続を制限する。
        for trackGroup in Dictionary(grouping: previous.indices, by: { previous[$0].trackID }).values {
            let frontToBack = trackGroup.sorted { previous[$0].positionM > previous[$1].positionM }
            if frontToBack.count > 1 {
                for orderIndex in 1..<frontToBack.count {
                    let leaderIndex = frontToBack[orderIndex - 1]
                    let followerIndex = frontToBack[orderIndex]
                    let maximumFrontM = max(0, next[leaderIndex].positionM - previous[leaderIndex].lengthM - minimumSeparationM)
                    if next[followerIndex].positionM > maximumFrontM {
                        next[followerIndex].positionM = maximumFrontM
                        next[followerIndex].speedMps = 0
                        next[followerIndex].accelerationMps2 = 0
                    }
                }
            }
        }
        trains = next
        elapsedSeconds += dt
        return frame()
    }

    public func frame() -> RailwayScheduleFrame {
        let states = trains.map { train in
            let permitted = min(train.commandedSpeedMps, min(train.maximumSpeedMps, route.condition(at: train.positionM).speedLimitKmh / 3.6))
            return ScheduleTrainState(id: train.id, trackID: train.trackID, positionM: train.positionM, speedMps: train.speedMps, accelerationMps2: train.accelerationMps2, permittedSpeedMps: permitted)
        }
        return RailwayScheduleFrame(elapsedSeconds: elapsedSeconds, trains: states, label: .fictionalEducational)
    }
}

// MARK: - Educational ATS acknowledgement and automatic brake

public enum EducationalATSState: String, Codable, Sendable {
    case idle
    case awaitingAcknowledgement
    case acknowledged
    case automaticBrakeApplied
}

public struct EducationalATSStatus: Codable, Equatable, Sendable {
    public let state: EducationalATSState
    public let deadlineSeconds: Double?
    public let remainingSeconds: Double?
    public let automaticBrakeCommanded: Bool
    public let label: OperationsSystemLabel
    public let warning: String
}

/// ACK期限を超えた場合に教材シミュレーション上の自動制動フラグを立てます。
/// 実ATSの挙動・認証・安全機能を表すものではありません。
public struct EducationalATSConfirmation: Codable, Equatable, Sendable {
    public private(set) var state: EducationalATSState
    public private(set) var deadlineSeconds: Double?
    public private(set) var lastObservedTimeSeconds: Double
    public let acknowledgementTimeoutSeconds: Double
    public let label: OperationsSystemLabel

    public init(acknowledgementTimeoutSeconds: Double) throws {
        guard acknowledgementTimeoutSeconds.isFinite, acknowledgementTimeoutSeconds > 0 else {
            throw OperationsValidationError.invalidValue("acknowledgementTimeoutSeconds")
        }
        self.acknowledgementTimeoutSeconds = acknowledgementTimeoutSeconds
        self.state = .idle
        self.deadlineSeconds = nil
        self.lastObservedTimeSeconds = 0
        self.label = .fictionalEducational
    }

    public mutating func trigger(at timeSeconds: Double) throws {
        guard timeSeconds.isFinite, timeSeconds >= lastObservedTimeSeconds else { throw OperationsValidationError.timeMustIncrease }
        lastObservedTimeSeconds = timeSeconds
        deadlineSeconds = timeSeconds + acknowledgementTimeoutSeconds
        state = .awaitingAcknowledgement
    }

    /// 期限時刻以下で受け付けます。期限後のACKは自動制動を解除しません。
    @discardableResult
    public mutating func acknowledge(at timeSeconds: Double) throws -> Bool {
        try observe(timeSeconds)
        guard state == .awaitingAcknowledgement, let deadlineSeconds, timeSeconds <= deadlineSeconds else { return false }
        state = .acknowledged
        return true
    }

    /// 時刻はシミュレーション経過秒。期限到達時に自動制動状態へ遷移します。
    public mutating func advance(to timeSeconds: Double) throws -> EducationalATSStatus {
        try observe(timeSeconds)
        if state == .awaitingAcknowledgement, let deadlineSeconds, timeSeconds >= deadlineSeconds {
            state = .automaticBrakeApplied
        }
        return status(at: timeSeconds)
    }

    public func status(at timeSeconds: Double? = nil) -> EducationalATSStatus {
        let now = timeSeconds ?? lastObservedTimeSeconds
        let remaining = deadlineSeconds.map { max(0, $0 - now) }
        let warning = "架空・教材専用。実際のATS規格・設備・運転保安を表さず、実運用に使用しないでください。"
        return EducationalATSStatus(state: state, deadlineSeconds: deadlineSeconds, remainingSeconds: remaining,
                                    automaticBrakeCommanded: state == .automaticBrakeApplied,
                                    label: .fictionalEducational, warning: warning)
    }

    private mutating func observe(_ timeSeconds: Double) throws {
        guard timeSeconds.isFinite, timeSeconds >= lastObservedTimeSeconds else { throw OperationsValidationError.timeMustIncrease }
        lastObservedTimeSeconds = timeSeconds
        if state == .awaitingAcknowledgement, let deadlineSeconds, timeSeconds >= deadlineSeconds {
            state = .automaticBrakeApplied
        }
    }
}
