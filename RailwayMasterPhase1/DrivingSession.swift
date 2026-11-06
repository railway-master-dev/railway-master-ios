import Foundation

// MARK: - Provenance and capability state

/// 評価対象の路線データの確度。数値が存在することだけで VERIFIED にはならない。
public enum DriveRouteDataStatus: String, Codable, Sendable {
    case verified = "VERIFIED"
    case measured = "MEASURED"
    case estimated = "ESTIMATED"
    case placeholder = "PLACEHOLDER"
    case unknown = "UNKNOWN"
}

/// アプリ内の機能がどの程度実装されているか。採点結果とともに保存される。
public enum DriveCapabilityState: String, Codable, Sendable {
    case implemented
    case simulated
    case unimplemented
    case unknown
}

public struct DriveSystemStates: Codable, Equatable, Sendable {
    public var signalSystem: DriveCapabilityState
    public var safetyProtection: DriveCapabilityState
    public var confirmationTracking: DriveCapabilityState
    public var timetable: DriveCapabilityState

    public init(
        signalSystem: DriveCapabilityState = .unimplemented,
        safetyProtection: DriveCapabilityState = .unimplemented,
        confirmationTracking: DriveCapabilityState = .unimplemented,
        timetable: DriveCapabilityState = .unimplemented
    ) {
        self.signalSystem = signalSystem
        self.safetyProtection = safetyProtection
        self.confirmationTracking = confirmationTracking
        self.timetable = timetable
    }
}

public enum DriveWarningSeverity: String, Codable, Sendable {
    case information
    case caution
    case critical
    case unknown
}

/// 目視・喚呼などの確認行動。記録されていないことを「実施した」と推定しない。
public struct DriveConfirmation: Codable, Equatable, Sendable {
    public let actionID: String
    public let label: String
    public let wasPerformed: Bool?

    public init(actionID: String, label: String, wasPerformed: Bool? = true) {
        self.actionID = actionID
        self.label = label
        self.wasPerformed = wasPerformed
    }
}

// MARK: - Bounded telemetry sample

/// 1件の間引き済み運転記録。距離はm、速度はkm/h、加速度はm/s²。
public struct DriveSample: Codable, Equatable, Sendable {
    public let simulationTimeSeconds: Double
    public let positionM: Double
    public let speedKmh: Double
    public let accelerationMps2: Double
    public let powerNotch: Int
    public let brakeNotch: Int
    public let emergencyBrakeOn: Bool
    public let speedLimitKmh: Double?
    public let signalAspect: String?
    public let warning: String?
    public let warningSeverity: DriveWarningSeverity
    public let warningAcknowledged: Bool?
    public let confirmations: [DriveConfirmation]

    public init(
        simulationTimeSeconds: Double,
        positionM: Double,
        speedKmh: Double,
        accelerationMps2: Double,
        powerNotch: Int,
        brakeNotch: Int,
        emergencyBrakeOn: Bool = false,
        speedLimitKmh: Double? = nil,
        signalAspect: String? = nil,
        warning: String? = nil,
        warningSeverity: DriveWarningSeverity = .unknown,
        warningAcknowledged: Bool? = nil,
        confirmations: [DriveConfirmation] = []
    ) {
        self.simulationTimeSeconds = simulationTimeSeconds
        self.positionM = positionM
        self.speedKmh = speedKmh
        self.accelerationMps2 = accelerationMps2
        self.powerNotch = powerNotch
        self.brakeNotch = brakeNotch
        self.emergencyBrakeOn = emergencyBrakeOn
        self.speedLimitKmh = speedLimitKmh
        self.signalAspect = signalAspect
        self.warning = warning
        self.warningSeverity = warningSeverity
        self.warningAcknowledged = warningAcknowledged
        self.confirmations = confirmations
    }

    fileprivate var hasFiniteRequiredValues: Bool {
        simulationTimeSeconds.isFinite && positionM.isFinite && speedKmh.isFinite &&
        accelerationMps2.isFinite && (speedLimitKmh?.isFinite ?? true)
    }
}

// MARK: - Session and evaluation criteria

public struct DriveEvaluationCriteria: Codable, Equatable, Sendable {
    public var scheduledDurationSeconds: Double?
    public var punctualityToleranceSeconds: Double
    public var stopMarkerM: Double?
    public var stopPositionToleranceM: Double
    public var overshootToleranceM: Double
    public var stopSpeedThresholdKmh: Double
    public var requiredStopDwellSeconds: Double
    public var maximumStopSampleGapSeconds: Double
    public var accelerationComfortLimitMps2: Double
    public var jerkComfortLimitMps3: Double
    public var requiredConfirmationActionIDs: [String]

    public init(
        scheduledDurationSeconds: Double? = nil,
        punctualityToleranceSeconds: Double = 30,
        stopMarkerM: Double? = nil,
        stopPositionToleranceM: Double = 5,
        overshootToleranceM: Double = 10,
        stopSpeedThresholdKmh: Double = 0.5,
        requiredStopDwellSeconds: Double = 2,
        maximumStopSampleGapSeconds: Double = 3,
        accelerationComfortLimitMps2: Double = 1.0,
        jerkComfortLimitMps3: Double = 0.8,
        requiredConfirmationActionIDs: [String] = []
    ) {
        self.scheduledDurationSeconds = scheduledDurationSeconds
        self.punctualityToleranceSeconds = max(punctualityToleranceSeconds, 0.1)
        self.stopMarkerM = stopMarkerM
        self.stopPositionToleranceM = max(stopPositionToleranceM, 0.1)
        self.overshootToleranceM = max(overshootToleranceM, 0)
        self.stopSpeedThresholdKmh = max(stopSpeedThresholdKmh, 0)
        self.requiredStopDwellSeconds = max(requiredStopDwellSeconds, 0)
        self.maximumStopSampleGapSeconds = max(maximumStopSampleGapSeconds, 0.1)
        self.accelerationComfortLimitMps2 = max(accelerationComfortLimitMps2, 0.05)
        self.jerkComfortLimitMps3 = max(jerkComfortLimitMps3, 0.05)
        self.requiredConfirmationActionIDs = requiredConfirmationActionIDs
    }
}

public struct DrivingSessionMetadata: Codable, Equatable, Sendable {
    public let sessionID: UUID
    public let startedAt: Date
    public var routeName: String
    public var routeDataStatus: DriveRouteDataStatus
    public var isVirtualSimulation: Bool
    public var systemStates: DriveSystemStates
    public var criteria: DriveEvaluationCriteria
    public var notes: String?

    public init(
        sessionID: UUID = UUID(),
        startedAt: Date = Date(),
        routeName: String = "",
        routeDataStatus: DriveRouteDataStatus = .unknown,
        isVirtualSimulation: Bool = true,
        systemStates: DriveSystemStates = DriveSystemStates(),
        criteria: DriveEvaluationCriteria = DriveEvaluationCriteria(),
        notes: String? = nil
    ) {
        self.sessionID = sessionID
        self.startedAt = startedAt
        self.routeName = routeName
        self.routeDataStatus = routeDataStatus
        self.isVirtualSimulation = isVirtualSimulation
        self.systemStates = systemStates
        self.criteria = criteria
        self.notes = notes
    }
}

public struct DrivingSession: Codable, Equatable, Sendable {
    public let metadata: DrivingSessionMetadata
    public let samples: [DriveSample]
    public let discardedSampleCount: Int
    public let rejectedSampleCount: Int

    public init(metadata: DrivingSessionMetadata, samples: [DriveSample], discardedSampleCount: Int = 0, rejectedSampleCount: Int = 0) {
        self.metadata = metadata
        self.samples = samples
        self.discardedSampleCount = max(discardedSampleCount, 0)
        self.rejectedSampleCount = max(rejectedSampleCount, 0)
    }

    public var summary: DrivingSessionSummary {
        DrivingSessionEvaluator.evaluate(self)
    }
}

// MARK: - Summary types

public enum DrivingScoreCategory: String, Codable, CaseIterable, Sendable {
    case punctuality
    case stoppingPosition
    case speedCompliance
    case rideComfort
    case operation
    case safety
    case confirmationActions

    public var japaneseTitle: String {
        switch self {
        case .punctuality: return "定時性"
        case .stoppingPosition: return "停止位置"
        case .speedCompliance: return "速度遵守"
        case .rideComfort: return "乗り心地"
        case .operation: return "操作"
        case .safety: return "安全"
        case .confirmationActions: return "確認動作"
        }
    }
}

public struct DrivingScoreItem: Codable, Equatable, Sendable {
    public let category: DrivingScoreCategory
    /// 評価条件または観測値が足りない場合は nil（0点に見せかけない）。
    public let score: Double?
    public let reasons: [String]

    public init(category: DrivingScoreCategory, score: Double?, reasons: [String]) {
        self.category = category
        self.score = score.map { min(max($0, 0), 100) }
        self.reasons = reasons
    }
}

public enum DriveStopOutcome: String, Codable, Sendable {
    case notEvaluated
    case completed
    case stoppedShort
    case passedMarker
    case notStopped
    case insufficientSamples
}

public struct DrivingSessionSummary: Codable, Equatable, Sendable {
    public let sessionID: UUID
    public let elapsedSeconds: Double?
    public let scoreItems: [DrivingScoreItem]
    public let overallScore: Double?
    public let stopOutcome: DriveStopOutcome
    public let stopOffsetM: Double?
    public let sampleCount: Int
    public let discardedSampleCount: Int
    public let rejectedSampleCount: Int
    public let routeDataStatus: DriveRouteDataStatus
    public let isVirtualSimulation: Bool
    public let systemStates: DriveSystemStates
    public let interpretationNotes: [String]

    public func item(for category: DrivingScoreCategory) -> DrivingScoreItem? {
        scoreItems.first { $0.category == category }
    }
}

// MARK: - Bounded recorder

public enum DriveRecordResult: Equatable, Sendable {
    case recorded
    case skippedBySamplingInterval
    case rejectedInvalidValues
    case rejectedNonMonotonicTime
}

public struct DrivingSessionRecorderSnapshot: Codable, Equatable, Sendable {
    public static let currentRevision = 1
    public var revision: Int
    public var metadata: DrivingSessionMetadata
    public var samplingIntervalSeconds: Double
    public var maximumSampleCount: Int
    public var samples: [DriveSample]
    public var discardedSampleCount: Int
    public var rejectedSampleCount: Int
}

/// 構造体なので @MainActor の SimulatorModel からそのまま所有・更新できる。
/// 秒単位の無制限蓄積を避け、記録間隔と保持件数を同時に制限する。
public struct DrivingSessionRecorder: Sendable {
    public private(set) var metadata: DrivingSessionMetadata
    public private(set) var samplingIntervalSeconds: Double
    public private(set) var maximumSampleCount: Int
    public private(set) var samples: [DriveSample] = []
    public private(set) var discardedSampleCount = 0
    public private(set) var rejectedSampleCount = 0

    public init(
        metadata: DrivingSessionMetadata = DrivingSessionMetadata(),
        samplingIntervalSeconds: Double = 0.5,
        maximumSampleCount: Int = 20_000
    ) {
        self.metadata = metadata
        self.samplingIntervalSeconds = max(samplingIntervalSeconds, 0.05)
        self.maximumSampleCount = max(maximumSampleCount, 2)
    }

    public func stateSnapshot() -> DrivingSessionRecorderSnapshot {
        DrivingSessionRecorderSnapshot(
            revision: DrivingSessionRecorderSnapshot.currentRevision,
            metadata: metadata,
            samplingIntervalSeconds: samplingIntervalSeconds,
            maximumSampleCount: maximumSampleCount,
            samples: samples,
            discardedSampleCount: discardedSampleCount,
            rejectedSampleCount: rejectedSampleCount
        )
    }

    public mutating func restoreState(from saved: DrivingSessionRecorderSnapshot) throws {
        guard saved.revision == DrivingSessionRecorderSnapshot.currentRevision,
              saved.samplingIntervalSeconds.isFinite, (0.05...60).contains(saved.samplingIntervalSeconds),
              (2...100_000).contains(saved.maximumSampleCount),
              saved.samples.count <= saved.maximumSampleCount,
              saved.discardedSampleCount >= 0, saved.rejectedSampleCount >= 0,
              saved.samples.allSatisfy(\.hasFiniteRequiredValues),
              zip(saved.samples, saved.samples.dropFirst()).allSatisfy({ pair in
                  pair.1.simulationTimeSeconds > pair.0.simulationTimeSeconds &&
                  pair.1.simulationTimeSeconds - pair.0.simulationTimeSeconds + 1e-12 >= saved.samplingIntervalSeconds
              }) else {
            throw DrivingSessionRecorderRestoreError.invalidState
        }
        metadata = saved.metadata
        samplingIntervalSeconds = saved.samplingIntervalSeconds
        maximumSampleCount = saved.maximumSampleCount
        samples = saved.samples
        discardedSampleCount = saved.discardedSampleCount
        rejectedSampleCount = saved.rejectedSampleCount
    }

    @discardableResult
    public mutating func record(_ sample: DriveSample) -> DriveRecordResult {
        guard sample.hasFiniteRequiredValues else {
            rejectedSampleCount += 1
            return .rejectedInvalidValues
        }
        if let last = samples.last {
            guard sample.simulationTimeSeconds > last.simulationTimeSeconds else {
                rejectedSampleCount += 1
                return .rejectedNonMonotonicTime
            }
            guard sample.simulationTimeSeconds - last.simulationTimeSeconds >= samplingIntervalSeconds else {
                return .skippedBySamplingInterval
            }
        }
        samples.append(sample)
        if samples.count > maximumSampleCount {
            let overflow = samples.count - maximumSampleCount
            samples.removeFirst(overflow)
            discardedSampleCount += overflow
        }
        return .recorded
    }

    public mutating func updateNotes(_ notes: String?) {
        metadata.notes = notes
    }

    public func makeSession() -> DrivingSession {
        DrivingSession(
            metadata: metadata,
            samples: samples,
            discardedSampleCount: discardedSampleCount,
            rejectedSampleCount: rejectedSampleCount
        )
    }

    public func summary() -> DrivingSessionSummary {
        makeSession().summary
    }

    public mutating func reset(metadata newMetadata: DrivingSessionMetadata? = nil) {
        if let newMetadata { metadata = newMetadata }
        samples.removeAll(keepingCapacity: true)
        discardedSampleCount = 0
        rejectedSampleCount = 0
    }

    /// JSONファイルへのローカル保存。書き込みは原子的に行う。
    public func save(to url: URL) throws {
        try makeSession().encodedEnvelope().write(to: url, options: .atomic)
    }

    public static func load(from url: URL) throws -> DrivingSession {
        try DrivingSession.decodeEnvelope(Data(contentsOf: url))
    }
}

public enum DrivingSessionRecorderRestoreError: Error, Equatable, Sendable {
    case invalidState
}

// MARK: - Versioned JSON envelope

public struct DrivingSessionEnvelope: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 1
    public let schema: String
    public let schemaVersion: Int
    public let savedAt: Date
    public let session: DrivingSession

    public init(session: DrivingSession, savedAt: Date = Date()) {
        self.schema = "jp.railwaymaster.driving-session"
        self.schemaVersion = Self.currentSchemaVersion
        self.savedAt = savedAt
        self.session = session
    }
}

public enum DrivingSessionStorageError: Error, Equatable {
    case unsupportedSchema(String)
    case unsupportedVersion(Int)
}

public extension DrivingSession {
    func encodedEnvelope() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(DrivingSessionEnvelope(session: self))
    }

    static func decodeEnvelope(_ data: Data) throws -> DrivingSession {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let envelope = try decoder.decode(DrivingSessionEnvelope.self, from: data)
        guard envelope.schema == "jp.railwaymaster.driving-session" else {
            throw DrivingSessionStorageError.unsupportedSchema(envelope.schema)
        }
        guard envelope.schemaVersion == DrivingSessionEnvelope.currentSchemaVersion else {
            throw DrivingSessionStorageError.unsupportedVersion(envelope.schemaVersion)
        }
        return envelope.session
    }
}

// MARK: - Deterministic, explainable evaluator

private enum DrivingSessionEvaluator {
    static func evaluate(_ session: DrivingSession) -> DrivingSessionSummary {
        let samples = session.samples
        let criteria = session.metadata.criteria
        let elapsed = samples.count >= 2 ? samples.last!.simulationTimeSeconds - samples.first!.simulationTimeSeconds : nil
        var items: [DrivingScoreItem] = []
        items.append(punctuality(samples: samples, elapsed: elapsed, criteria: criteria, historyWasTruncated: session.discardedSampleCount > 0))
        let stop = stopping(samples: samples, criteria: criteria, historyWasTruncated: session.discardedSampleCount > 0)
        items.append(stop.item)
        items.append(speedCompliance(samples: samples))
        items.append(rideComfort(samples: samples, criteria: criteria))
        items.append(operation(samples: samples))
        items.append(safety(samples: samples))
        items.append(confirmations(samples: samples, criteria: criteria, capability: session.metadata.systemStates.confirmationTracking))

        let scored = items.compactMap(\.score)
        let overall = scored.isEmpty ? nil : scored.reduce(0, +) / Double(scored.count)
        var notes: [String] = []
        if session.metadata.isVirtualSimulation {
            notes.append("これは仮想シミュレーションの採点です。実車・実路線の運転技能評価ではありません。")
        }
        switch session.metadata.routeDataStatus {
        case .placeholder:
            notes.append("路線データはPLACEHOLDERです。停止位置・速度制限などの評価は架空の設定に対する結果です。")
        case .unknown:
            notes.append("路線データの確度はUNKNOWNです。路線固有の妥当性を確認できていません。")
        case .estimated:
            notes.append("路線データにはESTIMATED値が含まれます。誤差の影響を考慮してください。")
        case .measured, .verified:
            break
        }
        if session.metadata.systemStates.signalSystem == .unimplemented {
            notes.append("信号・閉そくシステムは未実装です。信号現示に基づく保安評価は行っていません。")
        }
        if session.metadata.systemStates.safetyProtection == .unimplemented {
            notes.append("保安装置は未実装です。ATS/ATC等の実在システムの動作・適合性を評価していません。")
        }
        if session.discardedSampleCount > 0 {
            notes.append("保存上限により古い記録を\(session.discardedSampleCount)件破棄しました。全走行を網羅した評価ではありません。")
        }
        if session.rejectedSampleCount > 0 {
            notes.append("不正値または時刻逆行により\(session.rejectedSampleCount)件を記録しませんでした。")
        }
        if samples.count < 2 {
            notes.append("採点可能な時間範囲を得るには、時刻の異なる有効サンプルが2件以上必要です。")
        }
        return DrivingSessionSummary(
            sessionID: session.metadata.sessionID,
            elapsedSeconds: elapsed,
            scoreItems: items,
            overallScore: overall,
            stopOutcome: stop.outcome,
            stopOffsetM: stop.offset,
            sampleCount: samples.count,
            discardedSampleCount: session.discardedSampleCount,
            rejectedSampleCount: session.rejectedSampleCount,
            routeDataStatus: session.metadata.routeDataStatus,
            isVirtualSimulation: session.metadata.isVirtualSimulation,
            systemStates: session.metadata.systemStates,
            interpretationNotes: notes
        )
    }

    private static func punctuality(samples: [DriveSample], elapsed: Double?, criteria: DriveEvaluationCriteria, historyWasTruncated: Bool) -> DrivingScoreItem {
        guard !historyWasTruncated else {
            return .init(category: .punctuality, score: nil, reasons: ["古いサンプルが保存上限で破棄されているため、全区間の所要時間を確定できません。"])
        }
        guard let target = criteria.scheduledDurationSeconds, target > 0,
              let elapsed, elapsed >= 0 else {
            return .init(category: .punctuality, score: nil, reasons: ["目標所要時間または有効な走行時間がないため採点していません。"])
        }
        let difference = elapsed - target
        let deviation = abs(difference)
        let tolerance = criteria.punctualityToleranceSeconds
        let score = deviation <= tolerance ? 100 : max(0, 100 - 100 * (deviation - tolerance) / max(target, tolerance))
        let direction = difference > 0 ? "遅れ" : "早着"
        let reason = deviation <= tolerance
            ? "所要時間は\(fmt(elapsed))秒（目標\(fmt(target))秒）で、許容差±\(fmt(tolerance))秒以内です。"
            : "所要時間は\(fmt(elapsed))秒（目標\(fmt(target))秒）で、\(direction)\(fmt(deviation))秒。許容差±\(fmt(tolerance))秒を超えました。"
        return .init(category: .punctuality, score: score, reasons: [reason])
    }

    private static func stopping(samples: [DriveSample], criteria: DriveEvaluationCriteria, historyWasTruncated: Bool) -> (item: DrivingScoreItem, outcome: DriveStopOutcome, offset: Double?) {
        guard let target = criteria.stopMarkerM, target.isFinite else {
            return (.init(category: .stoppingPosition, score: nil, reasons: ["停止目標位置が指定されていないため採点していません。"]), .notEvaluated, nil)
        }
        guard samples.count >= 2 else {
            return (.init(category: .stoppingPosition, score: nil, reasons: ["停止完了・過走を判定するには複数のサンプルが必要です。"]), .insufficientSamples, nil)
        }
        if let pass = samples.first(where: { $0.positionM > target + criteria.overshootToleranceM }) {
            let offset = pass.positionM - target
            return (.init(category: .stoppingPosition, score: 0, reasons: ["停止目標\(fmt(target))mを\(fmt(offset))m通過しました（過走許容\(fmt(criteria.overshootToleranceM))m）。過走として判定します。"]), .passedMarker, offset)
        }
        guard !historyWasTruncated else {
            return (.init(category: .stoppingPosition, score: nil, reasons: ["古いサンプルが保存上限で破棄されているため、過走がなかったことや停止完了を確定できません。"]), .insufficientSamples, nil)
        }
        var dwellStart: Double?
        var lastStoppedTime: Double?
        var completedSample: DriveSample?
        for sample in samples {
            let inPosition = abs(sample.positionM - target) <= criteria.stopPositionToleranceM
            let stopped = sample.speedKmh <= criteria.stopSpeedThresholdKmh
            guard inPosition && stopped else {
                dwellStart = nil
                lastStoppedTime = nil
                continue
            }
            if let lastStoppedTime, sample.simulationTimeSeconds - lastStoppedTime > criteria.maximumStopSampleGapSeconds {
                dwellStart = sample.simulationTimeSeconds
            } else if dwellStart == nil {
                dwellStart = sample.simulationTimeSeconds
            }
            lastStoppedTime = sample.simulationTimeSeconds
            if let dwellStart, sample.simulationTimeSeconds - dwellStart >= criteria.requiredStopDwellSeconds {
                completedSample = sample
                break
            }
        }
        if let stopped = completedSample {
            let offset = stopped.positionM - target
            let score = max(0, 100 - 100 * abs(offset) / criteria.stopPositionToleranceM)
            let reason = "目標\(fmt(target))mの許容範囲±\(fmt(criteria.stopPositionToleranceM))m内で、速度\(fmt(stopped.speedKmh))km/hを\(fmt(criteria.requiredStopDwellSeconds))秒以上維持しました（停止位置誤差\(signed(offset))m）。"
            return (.init(category: .stoppingPosition, score: score, reasons: [reason]), .completed, offset)
        }
        if let last = samples.last, last.positionM > target + criteria.stopPositionToleranceM {
            let offset = last.positionM - target
            return (.init(category: .stoppingPosition, score: 0, reasons: ["目標位置を通過しましたが、許容範囲内での停止完了（速度\(fmt(criteria.stopSpeedThresholdKmh))km/h以下を\(fmt(criteria.requiredStopDwellSeconds))秒維持）は確認できません。"]), .notStopped, offset)
        }
        if let nearest = samples.min(by: { abs($0.positionM - target) < abs($1.positionM - target) }) {
            let offset = nearest.positionM - target
            let outcome: DriveStopOutcome = nearest.positionM < target - criteria.stopPositionToleranceM ? .stoppedShort : .notStopped
            let score = outcome == .stoppedShort ? 35.0 : 50.0
            let reason = outcome == .stoppedShort
                ? "最接近位置でも目標より\(fmt(abs(offset)))m手前で、停止許容範囲±\(fmt(criteria.stopPositionToleranceM))mに届きませんでした。"
                : "許容範囲内での停止完了を確認できません（速度\(fmt(criteria.stopSpeedThresholdKmh))km/h以下を\(fmt(criteria.requiredStopDwellSeconds))秒維持する条件）。"
            return (.init(category: .stoppingPosition, score: score, reasons: [reason]), outcome, offset)
        }
        return (.init(category: .stoppingPosition, score: nil, reasons: ["有効な位置サンプルがありません。"]), .insufficientSamples, nil)
    }

    private static func speedCompliance(samples: [DriveSample]) -> DrivingScoreItem {
        let limited = samples.compactMap { sample -> (Double, Double)? in
            guard let limit = sample.speedLimitKmh, limit > 0 else { return nil }
            return (sample.speedKmh, limit)
        }
        guard !limited.isEmpty else {
            return .init(category: .speedCompliance, score: nil, reasons: ["速度制限値が記録されていないため採点していません。"])
        }
        let violations = limited.map { max(0, $0.0 - $0.1) }.filter { $0 > 0.1 }
        let peak = violations.max() ?? 0
        let fraction = Double(violations.count) / Double(limited.count)
        let score = max(0, 100 - fraction * 70 - min(peak * 2, 30))
        if violations.isEmpty {
            return .init(category: .speedCompliance, score: 100, reasons: ["記録された\(limited.count)件の速度制限付きサンプルで、制限超過はありませんでした（判定余裕0.1km/h）。"])
        }
        return .init(category: .speedCompliance, score: score, reasons: ["\(limited.count)件中\(violations.count)件で速度制限を超過。最大超過は\(fmt(peak))km/h、違反サンプル比率は\(fmt(fraction * 100))%です。サンプル間の瞬間的な超過は検出できません。"])
    }

    private static func rideComfort(samples: [DriveSample], criteria: DriveEvaluationCriteria) -> DrivingScoreItem {
        guard !samples.isEmpty else {
            return .init(category: .rideComfort, score: nil, reasons: ["加速度サンプルがありません。"])
        }
        let peakAcceleration = samples.map { abs($0.accelerationMps2) }.max() ?? 0
        var peakJerk = 0.0
        if samples.count > 1 {
            for index in 1..<samples.count {
                let dt = samples[index].simulationTimeSeconds - samples[index - 1].simulationTimeSeconds
                guard dt > 0 else { continue }
                let jerk = abs(samples[index].accelerationMps2 - samples[index - 1].accelerationMps2) / dt
                peakJerk = max(peakJerk, jerk)
            }
        }
        let accelerationExcess = max(0, peakAcceleration / criteria.accelerationComfortLimitMps2 - 1)
        let jerkExcess = max(0, peakJerk / criteria.jerkComfortLimitMps3 - 1)
        let score = max(0, 100 - min(accelerationExcess * 25, 50) - min(jerkExcess * 20, 50))
        var reasons: [String] = ["最大絶対加速度\(fmt(peakAcceleration))m/s²（目安\(fmt(criteria.accelerationComfortLimitMps2))m/s²）、サンプル差分からの最大推定ジャーク\(fmt(peakJerk))m/s³（目安\(fmt(criteria.jerkComfortLimitMps3))m/s³）。"]
        if peakAcceleration > criteria.accelerationComfortLimitMps2 {
            reasons.append("加速度が設定した乗り心地目安を超えています。")
        }
        if peakJerk > criteria.jerkComfortLimitMps3 {
            reasons.append("加速度変化が設定したジャーク目安を超えています。記録間隔が粗い場合はピークを見逃します。")
        }
        return .init(category: .rideComfort, score: score, reasons: reasons)
    }

    private static func operation(samples: [DriveSample]) -> DrivingScoreItem {
        guard !samples.isEmpty else {
            return .init(category: .operation, score: nil, reasons: ["操作サンプルがありません。"])
        }
        var transitions = 0
        var simultaneousPowerAndBrake = 0
        var abruptChanges = 0
        if samples.count > 1 {
            for index in 1..<samples.count {
                let previous = samples[index - 1]
                let current = samples[index]
                let change = abs(current.powerNotch - previous.powerNotch) + abs(current.brakeNotch - previous.brakeNotch)
                if change > 0 { transitions += 1 }
                if change >= 4 { abruptChanges += 1 }
            }
        }
        for sample in samples where sample.powerNotch > 0 && sample.brakeNotch > 0 {
            simultaneousPowerAndBrake += 1
        }
        let simultaneousRate = Double(simultaneousPowerAndBrake) / Double(samples.count)
        let score = max(0, 100 - Double(abruptChanges) * 8 - simultaneousRate * 50)
        var reasons = ["ノッチ遷移\(transitions)回、1サンプル間に合計4段以上変化した操作\(abruptChanges)回、力行・常用ブレーキ同時指令\(simultaneousPowerAndBrake)件。"]
        if simultaneousPowerAndBrake > 0 {
            reasons.append("力行とブレーキが同時に指令されています。ゲーム内の操作値のみから算出し、実車の制御器挙動は評価しません。")
        }
        return .init(category: .operation, score: score, reasons: reasons)
    }

    private static func safety(samples: [DriveSample]) -> DrivingScoreItem {
        guard !samples.isEmpty else {
            return .init(category: .safety, score: nil, reasons: ["安全評価に利用できるサンプルがありません。"])
        }
        let limited = samples.compactMap { sample -> (DriveSample, Double)? in
            guard let limit = sample.speedLimitKmh, limit > 0 else { return nil }
            return (sample, limit)
        }
        let speedViolations = limited.filter { $0.0.speedKmh > $0.1 + 0.1 }
        let emergencyCount = samples.filter(\.emergencyBrakeOn).count
        let criticalUnacknowledged = samples.filter {
            $0.warning != nil && $0.warningSeverity == .critical && $0.warningAcknowledged == false
        }.count
        let score = max(0, 100 - Double(speedViolations.count) / Double(max(limited.count, 1)) * 60 - Double(emergencyCount) / Double(samples.count) * 20 - Double(criticalUnacknowledged) * 10)
        var reasons: [String] = []
        if limited.isEmpty {
            reasons.append("速度制限がないため、この項目の速度面は評価できません。")
        } else if speedViolations.isEmpty {
            reasons.append("速度制限付きサンプルで超過はありませんでした。")
        } else {
            reasons.append("速度制限超過を\(speedViolations.count)件検出しました。安全上重要な逸脱として減点しています。")
        }
        reasons.append("非常ブレーキ指令\(emergencyCount)件、未確認の重大警告\(criticalUnacknowledged)件。非常ブレーキ使用は原因を特定せず、記録上の発生のみを示します。")
        reasons.append("この点数は記録値に対する限定的なゲーム内指標で、実運転の安全性・法令適合・保安装置動作を認証しません。")
        return .init(category: .safety, score: score, reasons: reasons)
    }

    private static func confirmations(samples: [DriveSample], criteria: DriveEvaluationCriteria, capability: DriveCapabilityState) -> DrivingScoreItem {
        guard !criteria.requiredConfirmationActionIDs.isEmpty else {
            return .init(category: .confirmationActions, score: nil, reasons: ["必須確認動作が設定されていないため採点していません。"])
        }
        guard capability == .implemented || capability == .simulated else {
            let state = capability == .unimplemented ? "未実装" : "状態不明"
            return .init(category: .confirmationActions, score: nil, reasons: ["確認動作の記録機能が\(state)のため、実施状況を採点できません。未記録を未実施とはみなしません。"])
        }
        var missing: [String] = []
        var done = 0
        for actionID in criteria.requiredConfirmationActionIDs {
            let evidence = samples.flatMap(\.confirmations).filter { $0.actionID == actionID }
            if evidence.contains(where: { $0.wasPerformed == true }) {
                done += 1
            } else {
                let label = evidence.first?.label ?? actionID
                missing.append(label)
            }
        }
        let score = Double(done) / Double(criteria.requiredConfirmationActionIDs.count) * 100
        let reason = missing.isEmpty
            ? "必須確認動作\(done)件すべてに実施記録があります。記録は実際の喚呼・確認を証明するものではありません。"
            : "必須\(criteria.requiredConfirmationActionIDs.count)件中\(done)件に実施記録があります。記録なし／未実施: \(missing.joined(separator: "、"))。"
        return .init(category: .confirmationActions, score: score, reasons: [reason])
    }

    private static func fmt(_ value: Double) -> String {
        String(format: "%.1f", locale: Locale(identifier: "en_US_POSIX"), value)
    }

    private static func signed(_ value: Double) -> String {
        String(format: "%+.1f", locale: Locale(identifier: "en_US_POSIX"), value)
    }
}
