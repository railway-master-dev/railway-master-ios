import Foundation

/// 必ずUI上でプロンプトと評価に併記する、現実の手順・訓練ではない旨の表示。
public enum CrewWorkflowContent {
    public static let disclaimer = "FICTIONAL GAME CONTENT — NOT REAL RAILWAY PROCEDURE OR SAFETY TRAINING"

    /// 現実の業務指示を含まない、ゲーム上の段階表示文。
    public static func prompt(for phase: CrewWorkflowPhase) -> String {
        "\(disclaimer)\nゲーム内段階「\(phase.displayName)」です。ゲーム画面でこの段階を完了する選択をしてください。"
    }

    /// 評価文は架空のゲーム評価であり、現実の運転評価・安全判断には使用しない。
    public static let evaluations: [CrewWorkflowEvaluation] = [
        CrewWorkflowEvaluation(id: "punctuality", title: "定時性", description: "架空のゲーム時刻スコア。現実の運行判断には使用しません。"),
        CrewWorkflowEvaluation(id: "stop_accuracy", title: "停止精度", description: "架空のゲーム内スコア。現実の停止操作の評価には使用しません。"),
        CrewWorkflowEvaluation(id: "acceleration", title: "加速操作", description: "架空のゲーム内スコア。現実の運転操作の評価には使用しません。"),
        CrewWorkflowEvaluation(id: "braking", title: "ブレーキ", description: "架空のゲーム内スコア。現実の運転操作の評価には使用しません。"),
        CrewWorkflowEvaluation(id: "signal", title: "信号", description: "架空のゲーム内スコア。現実の信号判断には使用しません。"),
        CrewWorkflowEvaluation(id: "speed", title: "速度", description: "架空のゲーム内スコア。現実の速度判断には使用しません。"),
        CrewWorkflowEvaluation(id: "safety", title: "安全", description: "架空のゲーム内スコア。現実の安全判断や訓練には使用しません。"),
        CrewWorkflowEvaluation(id: "announcements", title: "放送", description: "架空のゲーム内スコア。現実の案内放送には使用しません。"),
        CrewWorkflowEvaluation(id: "confirmations", title: "確認", description: "架空のゲーム内スコア。現実の確認手順には使用しません。")
    ]
}

public struct CrewWorkflowEvaluation: Codable, Equatable, Sendable {
    public let id: String
    public let title: String
    /// 返却値の表示時は必ず `CrewWorkflowContent.disclaimer` も表示してください。
    public let description: String

    public init(id: String, title: String, description: String) {
        self.id = id
        self.title = title
        self.description = description
    }

    public var labeledText: String {
        "\(CrewWorkflowContent.disclaimer)\n\(title): \(description)"
    }
}

/// 工程IDは永続化・イベント連携向けの安定したsnake_case raw string。
public enum CrewWorkflowPhase: String, CaseIterable, Codable, Sendable {
    case attendanceRollCall = "attendance_roll_call"
    case preTripVehicleCheck = "pre_trip_vehicle_check"
    case cabStartup = "cab_startup"
    case instrumentCheck = "instrument_check"
    case depotExit = "depot_exit"
    case shunting = "shunting"
    case preDepartureCheck = "pre_departure_check"
    case doorClosing = "door_closing"
    case departure = "departure"
    case signalCheck = "signal_check"
    case speedCheck = "speed_check"
    case speedLimitCompliance = "speed_limit_compliance"
    case stationApproach = "station_approach"
    case preciseStop = "precise_stop"
    case postStopCheck = "post_stop_check"
    case crewCommunication = "crew_communication"
    case abnormalResponse = "abnormal_response"
    case terminalArrival = "terminal_arrival"
    case depotEntry = "depot_entry"
    case dutyEnd = "duty_end"

    public var displayName: String {
        switch self {
        case .attendanceRollCall: return "出勤・点呼"
        case .preTripVehicleCheck: return "乗務前車両確認"
        case .cabStartup: return "運転台起動"
        case .instrumentCheck: return "計器確認"
        case .depotExit: return "出庫"
        case .shunting: return "入換"
        case .preDepartureCheck: return "出発前確認"
        case .doorClosing: return "戸閉"
        case .departure: return "発車"
        case .signalCheck: return "信号確認"
        case .speedCheck: return "速度確認"
        case .speedLimitCompliance: return "制限速度遵守"
        case .stationApproach: return "駅進入"
        case .preciseStop: return "定位置停止"
        case .postStopCheck: return "停車後確認"
        case .crewCommunication: return "乗務員間の連絡"
        case .abnormalResponse: return "異常時対応"
        case .terminalArrival: return "終着到着"
        case .depotEntry: return "入庫"
        case .dutyEnd: return "乗務終了"
        }
    }

    /// 各段階を進めるために必要な架空ゲーム上の入力ID。現実の確認項目を表しません。
    public var requiredRequirementIDs: Set<String> {
        ["game_ack_\(rawValue)"]
    }

    public var next: CrewWorkflowPhase? {
        guard let index = Self.allCases.firstIndex(of: self), index + 1 < Self.allCases.count else { return nil }
        return Self.allCases[index + 1]
    }
}

public enum CrewWorkflowEventType: String, Codable, Sendable {
    case phaseCompleted = "phase_completed"
}

/// append-onlyの段階完了イベント契約。
public struct CrewWorkflowEvent: Codable, Equatable, Sendable {
    public let eventID: String
    public let runID: String
    /// ホストから渡されたシミュレーション時刻。壁時計は参照しません。
    public let timestamp: Date
    public let eventType: CrewWorkflowEventType
    public let phaseBefore: CrewWorkflowPhase
    public let phaseAfter: CrewWorkflowPhase?
    public let satisfiedRequirementIDs: [String]

    public init(
        eventID: String,
        runID: String,
        timestamp: Date,
        eventType: CrewWorkflowEventType,
        phaseBefore: CrewWorkflowPhase,
        phaseAfter: CrewWorkflowPhase?,
        satisfiedRequirementIDs: [String]
    ) {
        self.eventID = eventID
        self.runID = runID
        self.timestamp = timestamp
        self.eventType = eventType
        self.phaseBefore = phaseBefore
        self.phaseAfter = phaseAfter
        self.satisfiedRequirementIDs = satisfiedRequirementIDs
    }
}

/// 明示的な保存境界。ホストアプリのドメインモデルや保存先とは独立しています。
public struct CrewWorkflowSaveDTO: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 1

    public let schemaVersion: Int
    public let runID: String
    public let currentPhase: CrewWorkflowPhase?
    public let lastSimulationTime: Date?
    public let events: [CrewWorkflowEvent]

    public init(
        schemaVersion: Int = CrewWorkflowSaveDTO.currentSchemaVersion,
        runID: String,
        currentPhase: CrewWorkflowPhase?,
        lastSimulationTime: Date?,
        events: [CrewWorkflowEvent]
    ) {
        self.schemaVersion = schemaVersion
        self.runID = runID
        self.currentPhase = currentPhase
        self.lastSimulationTime = lastSimulationTime
        self.events = events
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case runID
        case currentPhase
        case lastSimulationTime
        case events
    }
}

public enum CrewWorkflowError: Error, Equatable, LocalizedError {
    case outOfOrder(expected: CrewWorkflowPhase?, received: CrewWorkflowPhase)
    case missingRequirements(phase: CrewWorkflowPhase, ids: [String])
    case timeWentBackwards(previous: Date, attempted: Date)
    case noActivePhase
    case invalidSave(String)

    public var errorDescription: String? {
        switch self {
        case let .outOfOrder(expected, received):
            return "順序不正です。期待段階: \(expected?.rawValue ?? "none")、受信段階: \(received.rawValue)。"
        case let .missingRequirements(phase, ids):
            return "\(phase.rawValue) のイベントは記録できません。不足するゲーム要件: \(ids.joined(separator: ", "))"
        case let .timeWentBackwards(previous, attempted):
            return "シミュレーション時刻が逆行しています (\(previous) → \(attempted))。"
        case .noActivePhase:
            return "すべての工程が完了しており、進行中の段階はありません。"
        case let .invalidSave(reason):
            return "保存データが不正です: \(reason)"
        }
    }
}

/// 単一runの順序制御。時刻はすべて呼び出し元が渡すシミュレーション時刻です。
public struct CrewWorkflow {
    public let runID: String
    public private(set) var currentPhase: CrewWorkflowPhase?
    public private(set) var events: [CrewWorkflowEvent]
    public private(set) var lastSimulationTime: Date?

    public init(runID: String = UUID().uuidString) {
        self.runID = runID
        self.currentPhase = CrewWorkflowPhase.allCases.first
        self.events = []
        self.lastSimulationTime = nil
    }

    /// 期待段階のみを、全ての必要なゲーム入力要件が揃った場合に完了する。
    @discardableResult
    public mutating func complete(
        phase: CrewWorkflowPhase,
        at simulationTime: Date,
        satisfiedRequirementIDs: Set<String>
    ) throws -> CrewWorkflowEvent {
        guard let expected = currentPhase else { throw CrewWorkflowError.noActivePhase }
        guard phase == expected else {
            throw CrewWorkflowError.outOfOrder(expected: expected, received: phase)
        }
        if let previousTime = lastSimulationTime, simulationTime < previousTime {
            throw CrewWorkflowError.timeWentBackwards(previous: previousTime, attempted: simulationTime)
        }
        let missing = phase.requiredRequirementIDs.subtracting(satisfiedRequirementIDs).sorted()
        guard missing.isEmpty else {
            throw CrewWorkflowError.missingRequirements(phase: phase, ids: missing)
        }

        let event = CrewWorkflowEvent(
            eventID: "\(runID):phase:\(events.count + 1)",
            runID: runID,
            timestamp: simulationTime,
            eventType: .phaseCompleted,
            phaseBefore: phase,
            phaseAfter: phase.next,
            satisfiedRequirementIDs: satisfiedRequirementIDs.sorted()
        )
        events.append(event)
        currentPhase = phase.next
        lastSimulationTime = simulationTime
        return event
    }

    public func exportSave() -> CrewWorkflowSaveDTO {
        CrewWorkflowSaveDTO(
            runID: runID,
            currentPhase: currentPhase,
            lastSimulationTime: lastSimulationTime,
            events: events
        )
    }

    public static func restore(from dto: CrewWorkflowSaveDTO) throws -> CrewWorkflow {
        guard dto.schemaVersion == CrewWorkflowSaveDTO.currentSchemaVersion else {
            throw CrewWorkflowError.invalidSave("未対応のschemaVersion \(dto.schemaVersion)。")
        }
        guard !dto.runID.isEmpty else { throw CrewWorkflowError.invalidSave("runIDが空です。") }

        let phases = CrewWorkflowPhase.allCases
        guard dto.events.count <= phases.count else {
            throw CrewWorkflowError.invalidSave("イベント数が工程数を超えています。")
        }
        var seenEventIDs = Set<String>()
        var previousTime: Date?
        for (index, event) in dto.events.enumerated() {
            guard event.runID == dto.runID else { throw CrewWorkflowError.invalidSave("イベントのrunIDが一致しません。") }
            let expectedEventID = "\(dto.runID):phase:\(index + 1)"
            guard event.eventID == expectedEventID, seenEventIDs.insert(event.eventID).inserted else {
                throw CrewWorkflowError.invalidSave("eventIDが空、重複、または工程順と一致しません。")
            }
            guard event.eventType == .phaseCompleted, event.phaseBefore == phases[index] else {
                throw CrewWorkflowError.invalidSave("イベント列が工程順と一致しません。")
            }
            guard event.phaseAfter == phases[index].next else {
                throw CrewWorkflowError.invalidSave("イベントのphaseAfterが不正です。")
            }
            guard Set(event.satisfiedRequirementIDs).isSuperset(of: phases[index].requiredRequirementIDs) else {
                throw CrewWorkflowError.invalidSave("必要なゲーム要件を満たさないイベントがあります。")
            }
            if let previousTime, event.timestamp < previousTime {
                throw CrewWorkflowError.invalidSave("イベント時刻が逆行しています。")
            }
            previousTime = event.timestamp
        }

        let expectedPhase = dto.events.count < phases.count ? phases[dto.events.count] : nil
        guard dto.currentPhase == expectedPhase else { throw CrewWorkflowError.invalidSave("currentPhaseがイベント列と一致しません。") }
        guard dto.lastSimulationTime == previousTime else { throw CrewWorkflowError.invalidSave("lastSimulationTimeがイベント列と一致しません。") }

        var workflow = CrewWorkflow(runID: dto.runID)
        workflow.currentPhase = expectedPhase
        workflow.events = dto.events
        workflow.lastSimulationTime = previousTime
        return workflow
    }
}
