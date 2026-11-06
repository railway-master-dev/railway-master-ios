import Foundation

public struct PermittedSpeedReading: Codable, Equatable, Sendable {
    public let positionM: Double
    public let permittedSpeedKmh: Double
    public let currentRouteLimitKmh: Double
    public let limitingRestrictionID: String?
    public let label: RailwayModelLabel
}

/// 路線速度制限と減速度モデルから、簡易な平方根制動包絡を算出します。
/// 制動遅れ・勾配・粘着・実車性能を保証する保安装置ではありません。
public struct VirtualSpeedProfile: Sendable {
    public let topology: RailwayTopology
    public let serviceDecelerationMps2: Double
    public let safetyMarginM: Double

    public init(topology: RailwayTopology, serviceDecelerationMps2: Double, safetyMarginM: Double = 0) throws {
        guard serviceDecelerationMps2.isFinite, serviceDecelerationMps2 > 0,
              safetyMarginM.isFinite, safetyMarginM >= 0 else {
            throw RailwaySignallingError.invalidValue("deceleration/safetyMarginM")
        }
        self.topology = topology
        self.serviceDecelerationMps2 = serviceDecelerationMps2
        self.safetyMarginM = safetyMarginM
    }

    public func reading(atPositionM positionM: Double) throws -> PermittedSpeedReading {
        guard positionM.isFinite, positionM >= 0, positionM <= topology.lengthM else {
            throw RailwaySignallingError.outOfRoute("speed profile position")
        }
        let active = topology.speedRestrictions.filter { positionM >= $0.startM && positionM < $0.endM }
        let currentLimit = active.map(\.maximumSpeedKmh).min() ?? topology.defaultSpeedLimitKmh
        var permitted = currentLimit
        var limitingID: String? = active.min(by: { $0.maximumSpeedKmh < $1.maximumSpeedKmh })?.id

        for restriction in topology.speedRestrictions where restriction.startM >= positionM {
            let availableDistanceM = max(0, restriction.startM - positionM - safetyMarginM)
            let targetMps = restriction.maximumSpeedKmh / 3.6
            let envelopeKmh = sqrt(targetMps * targetMps + 2 * serviceDecelerationMps2 * availableDistanceM) * 3.6
            if envelopeKmh < permitted {
                permitted = envelopeKmh
                limitingID = restriction.id
            }
        }

        return PermittedSpeedReading(positionM: positionM, permittedSpeedKmh: max(0, permitted),
                                     currentRouteLimitKmh: currentLimit, limitingRestrictionID: limitingID,
                                     label: .virtualEducational)
    }
}

public enum VirtualATSMode: String, Codable, CaseIterable, Equatable, Sendable {
    /// 仮想の停止信号確認・期限超過ブレーキ動作。実ATS-Sの仕様ではありません。
    case atsSLike
    /// 仮想の連続速度照査・超過ブレーキ動作。実ATS-Pの仕様ではありません。
    case atsPLike
}

public enum VirtualATSState: String, Codable, Equatable, Sendable {
    case idle
    case awaitingAcknowledgement
    case acknowledged
    case automaticBrakeApplied
}

public struct VirtualATSStatus: Codable, Equatable, Sendable {
    public let mode: VirtualATSMode
    public let state: VirtualATSState
    public let acknowledgementDeadlineSeconds: Double?
    public let automaticBrakeCommanded: Bool
    public let label: RailwayModelLabel
    public let warning: String
}

/// ATS-S/Pに似た教育用の挙動だけを提供します。実在規格・車上装置・安全機能との互換性はありません。
public struct VirtualATSController: Codable, Equatable, Sendable {
    public let mode: VirtualATSMode
    public let acknowledgementTimeoutSeconds: Double
    public let overspeedToleranceKmh: Double
    public private(set) var state: VirtualATSState
    public private(set) var acknowledgementDeadlineSeconds: Double?
    public private(set) var lastObservedTimeSeconds: Double

    public init(mode: VirtualATSMode, acknowledgementTimeoutSeconds: Double = 5, overspeedToleranceKmh: Double = 0) throws {
        guard acknowledgementTimeoutSeconds.isFinite, acknowledgementTimeoutSeconds > 0,
              overspeedToleranceKmh.isFinite, overspeedToleranceKmh >= 0 else {
            throw RailwaySignallingError.invalidValue("ATS timeout/tolerance")
        }
        self.mode = mode
        self.acknowledgementTimeoutSeconds = acknowledgementTimeoutSeconds
        self.overspeedToleranceKmh = overspeedToleranceKmh
        self.state = .idle
        self.acknowledgementDeadlineSeconds = nil
        self.lastObservedTimeSeconds = 0
    }

    public mutating func triggerStopSignal(at timeSeconds: Double) throws {
        guard mode == .atsSLike else {
            throw RailwaySignallingError.invalidValue("stop-signal acknowledgement is only available in atsSLike mode")
        }
        try observe(timeSeconds)
        guard state != .automaticBrakeApplied else { return }
        acknowledgementDeadlineSeconds = timeSeconds + acknowledgementTimeoutSeconds
        state = .awaitingAcknowledgement
    }

    /// 期限時刻より前の確認を受け付けます。期限到達後の自動ブレーキは確認で解除されません。
    @discardableResult
    public mutating func acknowledge(at timeSeconds: Double) throws -> Bool {
        guard mode == .atsSLike else {
            throw RailwaySignallingError.invalidValue("acknowledgement is only available in atsSLike mode")
        }
        try observe(timeSeconds)
        guard state == .awaitingAcknowledgement,
              let deadline = acknowledgementDeadlineSeconds, timeSeconds <= deadline else { return false }
        state = .acknowledged
        return true
    }

    /// 実速度が許容速度+許容幅を超えたときに仮想自動ブレーキをラッチします。
    public mutating func superviseSpeed(actualSpeedKmh: Double, permittedSpeedKmh: Double, at timeSeconds: Double) throws -> VirtualATSStatus {
        guard mode == .atsPLike else {
            throw RailwaySignallingError.invalidValue("continuous speed supervision is only available in atsPLike mode")
        }
        guard actualSpeedKmh.isFinite, actualSpeedKmh >= 0,
              permittedSpeedKmh.isFinite, permittedSpeedKmh >= 0 else {
            throw RailwaySignallingError.invalidValue("actual/permitted speed")
        }
        try observe(timeSeconds)
        if state != .automaticBrakeApplied && actualSpeedKmh > permittedSpeedKmh + overspeedToleranceKmh {
            state = .automaticBrakeApplied
        }
        return status
    }

    @discardableResult
    public mutating func advance(to timeSeconds: Double) throws -> VirtualATSStatus {
        try observe(timeSeconds)
        if mode == .atsSLike, state == .awaitingAcknowledgement,
           let deadline = acknowledgementDeadlineSeconds, timeSeconds >= deadline {
            state = .automaticBrakeApplied
        }
        return status
    }

    /// ラッチ解除は停止後の明示的なシミュレーション操作に限定します。
    public mutating func resetAfterStop(at timeSeconds: Double, speedKmh: Double) throws {
        guard speedKmh.isFinite, speedKmh >= 0, speedKmh <= 0.1 else {
            throw RailwaySignallingError.invalidValue("ATS reset requires a stopped train")
        }
        try observe(timeSeconds)
        state = .idle
        acknowledgementDeadlineSeconds = nil
    }

    public var status: VirtualATSStatus {
        VirtualATSStatus(mode: mode, state: state,
                         acknowledgementDeadlineSeconds: acknowledgementDeadlineSeconds,
                         automaticBrakeCommanded: state == .automaticBrakeApplied,
                         label: .virtualEducational,
                         warning: "架空・教材専用。実際のATS規格・設備・運転保安を表さず、実運用に使用しないでください。")
    }

    private mutating func observe(_ timeSeconds: Double) throws {
        guard timeSeconds.isFinite, timeSeconds >= lastObservedTimeSeconds else {
            throw RailwaySignallingError.timeMustIncrease
        }
        lastObservedTimeSeconds = timeSeconds
        if mode == .atsSLike, state == .awaitingAcknowledgement,
           let deadline = acknowledgementDeadlineSeconds, timeSeconds >= deadline {
            state = .automaticBrakeApplied
        }
    }
}
