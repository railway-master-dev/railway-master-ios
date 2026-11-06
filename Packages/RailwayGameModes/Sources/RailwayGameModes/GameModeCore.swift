import Foundation

/// このパッケージが扱うのは架空ゲーム状態のみです。実際の鉄道運転・安全訓練には使用できません。
public enum GameModeID: String, Codable, CaseIterable, Equatable, Hashable, Sendable, Identifiable {
    case driver
    case timetable
    case free
    case conductor
    case disruption
    case training
    case fullLine
    case tourism
    case companyOperations

    public var id: String { rawValue }
}

public enum GameModeDataLabel: String, Codable, Equatable, Sendable {
    case placeholder = "PLACEHOLDER — 架空ゲームデータ"
}

/// 仕様書2のプレイ種別。9つのシナリオモードとは直交するセッション設定。
public enum GameModePlayStyle: String, Codable, Equatable, Sendable {
    case practice
    case standard
    case disruptionTraining
    case freeRun
}

public enum GameModeSessionStatus: String, Codable, Equatable, Sendable {
    case ready
    case active
    case succeeded
    case failed
    case blocked
    case completed
    case abandoned

    public var isTerminal: Bool {
        switch self {
        case .succeeded, .failed, .blocked, .completed, .abandoned: return true
        case .ready, .active: return false
        }
    }
}

public enum GameModeOutcome: String, Codable, Equatable, Sendable {
    case success
    case failure
    case blocked
    case selfDirected
    case abandoned
}

public enum GameModeBlockingReason: String, Codable, Equatable, Sendable {
    case missingDriverChecklist
    case missingStops
    case missingTrainingSteps
    case missingLandmarks
    case missingDispatchPlan
    case missingTrainSnapshots
    case missingStationAnnouncements
    case unknownInitialDoorState
    case mustStartAtRouteOrigin
}

public enum GameModeError: Error, Equatable, Sendable {
    case invalidValue(String)
    case routeMismatch(expected: String, received: String)
    case timeRegression
    case actionNotSupported(mode: GameModeID)
    case actionUnavailable(String)
    case unknownIdentifier(String)
    case invalidAssignment(String)
    case missingTrain(String)
    case sessionAlreadyEnded
}

public enum GameModeDoorState: String, Codable, Equatable, Sendable {
    case unknown
    case closed
    case openLeft
    case openRight

    public var isOpen: Bool { self == .openLeft || self == .openRight }
}

public enum GameModePlatformSide: String, Codable, Equatable, Sendable {
    case left
    case right
}

public enum GameModeStationEvent: String, Codable, Equatable, Sendable {
    case arrival
    case departure
}

/// 車両1編成分のホスト側シミュレーション値。位置m、速度m/s、加速度m/s²。
public struct GameModeTrainSnapshot: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let routeID: String
    public let trackID: String
    public let positionM: Double
    public let speedMps: Double

    public init(id: String, routeID: String, trackID: String, positionM: Double, speedMps: Double) throws {
        guard !id.isEmpty, !routeID.isEmpty, !trackID.isEmpty,
              positionM.isFinite, positionM >= 0,
              speedMps.isFinite, speedMps >= 0 else {
            throw GameModeError.invalidValue("train snapshot")
        }
        self.id = id
        self.routeID = routeID
        self.trackID = trackID
        self.positionM = positionM
        self.speedMps = speedMps
    }
}

/// ホストの物理・路線モデルから受け取る読み取り専用のゲーム用スナップショット。
public struct GameModeSimulationSnapshot: Codable, Equatable, Sendable {
    public let simulationTimeSeconds: Double
    public let fixedTick: UInt64
    public let routeID: String
    public let routeLengthM: Double
    public let positionM: Double
    public let speedMps: Double
    public let accelerationMps2: Double
    public let speedLimitKmh: Double
    public let atStationID: String?
    public let stationEvent: GameModeStationEvent?
    public let doors: GameModeDoorState
    public let visibleLandmarkID: String?
    public let vehicleID: String?
    public let weatherID: String?
    public let timeOfDayID: String?
    public let seasonID: String?
    public let passengerLoadFactor: Double?
    public let trainingPromptID: String?
    public let trains: [GameModeTrainSnapshot]

    public init(
        simulationTimeSeconds: Double,
        fixedTick: UInt64 = 0,
        routeID: String,
        routeLengthM: Double,
        positionM: Double,
        speedMps: Double,
        accelerationMps2: Double = 0,
        speedLimitKmh: Double,
        atStationID: String? = nil,
        stationEvent: GameModeStationEvent? = nil,
        doors: GameModeDoorState = .unknown,
        visibleLandmarkID: String? = nil,
        vehicleID: String? = nil,
        weatherID: String? = nil,
        timeOfDayID: String? = nil,
        seasonID: String? = nil,
        passengerLoadFactor: Double? = nil,
        trainingPromptID: String? = nil,
        trains: [GameModeTrainSnapshot] = []
    ) throws {
        guard simulationTimeSeconds.isFinite, simulationTimeSeconds >= 0,
              !routeID.isEmpty, routeLengthM.isFinite, routeLengthM > 0,
              positionM.isFinite, positionM >= 0, positionM <= routeLengthM + 0.1,
              speedMps.isFinite, speedMps >= 0,
              accelerationMps2.isFinite,
              speedLimitKmh.isFinite, speedLimitKmh >= 0,
              vehicleID.map({ !$0.isEmpty }) ?? true,
              weatherID.map({ !$0.isEmpty }) ?? true,
              timeOfDayID.map({ !$0.isEmpty }) ?? true,
              seasonID.map({ !$0.isEmpty }) ?? true,
              passengerLoadFactor.map({ $0.isFinite && $0 >= 0 && $0 <= 2 }) ?? true,
              trainingPromptID.map({ !$0.isEmpty }) ?? true,
              Set(trains.map(\.id)).count == trains.count else {
            throw GameModeError.invalidValue("simulation snapshot")
        }
        self.simulationTimeSeconds = simulationTimeSeconds
        self.fixedTick = fixedTick
        self.routeID = routeID
        self.routeLengthM = routeLengthM
        self.positionM = positionM
        self.speedMps = speedMps
        self.accelerationMps2 = accelerationMps2
        self.speedLimitKmh = speedLimitKmh
        self.atStationID = atStationID
        self.stationEvent = stationEvent
        self.doors = doors
        self.visibleLandmarkID = visibleLandmarkID
        self.vehicleID = vehicleID
        self.weatherID = weatherID
        self.timeOfDayID = timeOfDayID
        self.seasonID = seasonID
        self.passengerLoadFactor = passengerLoadFactor
        self.trainingPromptID = trainingPromptID
        self.trains = trains
    }
}

/// UI/シミュレーター所有側が現在値を提供する境界。モジュールは物理値を書き換えません。
public protocol GameModeSimulationSource {
    var gameModeSnapshot: GameModeSimulationSnapshot { get }
}

public struct GameModeStopPlan: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let stationNameAnnouncementID: String?
    public let positionM: Double
    public let scheduledArrivalSeconds: Double
    public let scheduledDepartureSeconds: Double?
    public let expectedPlatformSide: GameModePlatformSide
    public let arrivalToleranceSeconds: Double

    public init(
        id: String,
        stationNameAnnouncementID: String? = nil,
        positionM: Double,
        scheduledArrivalSeconds: Double,
        scheduledDepartureSeconds: Double? = nil,
        expectedPlatformSide: GameModePlatformSide = .left,
        arrivalToleranceSeconds: Double = 30
    ) {
        self.id = id
        self.stationNameAnnouncementID = stationNameAnnouncementID
        self.positionM = positionM
        self.scheduledArrivalSeconds = scheduledArrivalSeconds
        self.scheduledDepartureSeconds = scheduledDepartureSeconds
        self.expectedPlatformSide = expectedPlatformSide
        self.arrivalToleranceSeconds = arrivalToleranceSeconds
    }
}

public struct GameModeLandmarkPlan: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let displayName: String
    public let positionM: Double
    public let observationRadiusM: Double
    public let maximumObservationSpeedMps: Double

    public init(
        id: String,
        displayName: String,
        positionM: Double,
        observationRadiusM: Double = 80,
        maximumObservationSpeedMps: Double = 12
    ) {
        self.id = id
        self.displayName = displayName
        self.positionM = positionM
        self.observationRadiusM = observationRadiusM
        self.maximumObservationSpeedMps = maximumObservationSpeedMps
    }
}

public enum GameModeTrainingRequirement: String, Codable, Equatable, Sendable {
    case stopped
    case withinCurrentSpeedLimit
    case atStation
    case promptVisible
}

public struct GameModeTrainingStep: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let title: String
    public let requirement: GameModeTrainingRequirement
    public let requiredPromptID: String?

    public init(id: String, title: String, requirement: GameModeTrainingRequirement, requiredPromptID: String? = nil) {
        self.id = id
        self.title = title
        self.requirement = requirement
        self.requiredPromptID = requiredPromptID
    }
}

public enum GameModeIncidentChoice: String, Codable, CaseIterable, Equatable, Sendable {
    case acknowledgeGamePrompt
    case requestGameHint
    case waitForGameUpdate
}

public enum GameModeIncidentKind: String, Codable, CaseIterable, Equatable, Sendable {
    case vehicleFault
    case passengerMedicalEvent
    case crossingObstruction
    case trackObstruction
    case signalDisplayAnomaly
    case weatherRestriction
}

public struct GameModeIncidentPlan: Codable, Equatable, Sendable {
    public let id: String
    public let kind: GameModeIncidentKind
    public let displayText: String
    public let triggerAfterSeconds: Double
    public let responseDeadlineSeconds: Double
    public let expectedChoice: GameModeIncidentChoice

    public init(
        id: String,
        kind: GameModeIncidentKind,
        displayText: String,
        triggerAfterSeconds: Double,
        responseDeadlineSeconds: Double,
        expectedChoice: GameModeIncidentChoice
    ) {
        self.id = id
        self.kind = kind
        self.displayText = displayText
        self.triggerAfterSeconds = triggerAfterSeconds
        self.responseDeadlineSeconds = responseDeadlineSeconds
        self.expectedChoice = expectedChoice
    }
}

public struct GameModeDispatchSlot: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let trackID: String
    public let startTimeSeconds: Double
    public let endTimeSeconds: Double

    public init(id: String, trackID: String, startTimeSeconds: Double, endTimeSeconds: Double) {
        self.id = id
        self.trackID = trackID
        self.startTimeSeconds = startTimeSeconds
        self.endTimeSeconds = endTimeSeconds
    }
}

public struct GameModeDispatchTask: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let trainID: String
    public let deadlineSeconds: Double
    public let allowedSlotIDs: [String]

    public init(id: String, trainID: String, deadlineSeconds: Double, allowedSlotIDs: [String]) {
        self.id = id
        self.trainID = trainID
        self.deadlineSeconds = deadlineSeconds
        self.allowedSlotIDs = allowedSlotIDs
    }
}

/// 架空の路線・駅・イベントを注入するシナリオ設定。未指定の実データを推測しません。
public struct GameModeScenario: Codable, Equatable, Sendable {
    public static let defaultDriverDutyStepIDs = [
        "PLACEHOLDER-roll-call", "PLACEHOLDER-pre-service-inspection", "PLACEHOLDER-cab-setup",
        "PLACEHOLDER-departure-check", "PLACEHOLDER-depot-exit", "PLACEHOLDER-point-call",
        "PLACEHOLDER-signal-check", "PLACEHOLDER-station-check", "PLACEHOLDER-terminal-arrival",
        "PLACEHOLDER-depot-return", "PLACEHOLDER-duty-close"
    ]

    public let routeID: String
    public let routeLengthM: Double
    public let stops: [GameModeStopPlan]
    public let driverDutyStepIDs: [String]
    public let driverDepartureCheckStepID: String
    public let playStyle: GameModePlayStyle
    public let landmarks: [GameModeLandmarkPlan]
    public let trainingSteps: [GameModeTrainingStep]
    public let incident: GameModeIncidentPlan
    public let requiredAnnouncementIDs: [String]
    public let dispatchTasks: [GameModeDispatchTask]
    public let dispatchSlots: [GameModeDispatchSlot]
    public let minimumTrainSeparationM: Double
    public let dataLabel: GameModeDataLabel

    public init(
        routeID: String,
        routeLengthM: Double,
        stops: [GameModeStopPlan],
        driverDutyStepIDs: [String] = GameModeScenario.defaultDriverDutyStepIDs,
        driverDepartureCheckStepID: String = "PLACEHOLDER-departure-check",
        playStyle: GameModePlayStyle = .standard,
        landmarks: [GameModeLandmarkPlan] = [],
        trainingSteps: [GameModeTrainingStep] = [],
        incident: GameModeIncidentPlan,
        requiredAnnouncementIDs: [String] = [],
        dispatchTasks: [GameModeDispatchTask] = [],
        dispatchSlots: [GameModeDispatchSlot] = [],
        minimumTrainSeparationM: Double = 300
    ) throws {
        guard !routeID.isEmpty, routeLengthM.isFinite, routeLengthM > 0,
              minimumTrainSeparationM.isFinite, minimumTrainSeparationM > 0,
              !incident.id.isEmpty, !incident.displayText.isEmpty,
              incident.triggerAfterSeconds.isFinite, incident.triggerAfterSeconds >= 0,
              incident.responseDeadlineSeconds.isFinite, incident.responseDeadlineSeconds > 0,
              Set(stops.map(\.id)).count == stops.count,
              !driverDepartureCheckStepID.isEmpty,
              Set(driverDutyStepIDs).count == driverDutyStepIDs.count,
              driverDutyStepIDs.contains(driverDepartureCheckStepID),
              Set(landmarks.map(\.id)).count == landmarks.count,
              Set(trainingSteps.map(\.id)).count == trainingSteps.count,
              Set(requiredAnnouncementIDs).count == requiredAnnouncementIDs.count,
              Set(dispatchTasks.map(\.id)).count == dispatchTasks.count,
              Set(dispatchSlots.map(\.id)).count == dispatchSlots.count else {
            throw GameModeError.invalidValue("scenario identifiers or required values")
        }
        guard stops.allSatisfy({ stop in
            !stop.id.isEmpty && (stop.stationNameAnnouncementID.map({ !$0.isEmpty }) ?? true) &&
            stop.positionM.isFinite && stop.positionM >= 0 && stop.positionM <= routeLengthM &&
            stop.scheduledArrivalSeconds.isFinite && stop.scheduledArrivalSeconds >= 0 &&
            (stop.scheduledDepartureSeconds.map({ departure in departure.isFinite && departure >= stop.scheduledArrivalSeconds }) ?? true) &&
            stop.arrivalToleranceSeconds.isFinite && stop.arrivalToleranceSeconds >= 0
        }),
              driverDutyStepIDs.allSatisfy({ !$0.isEmpty }),
              landmarks.allSatisfy({ !$0.id.isEmpty && !$0.displayName.isEmpty && $0.positionM.isFinite && $0.positionM >= 0 && $0.positionM <= routeLengthM && $0.observationRadiusM.isFinite && $0.observationRadiusM > 0 && $0.maximumObservationSpeedMps.isFinite && $0.maximumObservationSpeedMps >= 0 }),
              trainingSteps.allSatisfy({ step in
                  !step.id.isEmpty && !step.title.isEmpty &&
                  (step.requiredPromptID.map({ !$0.isEmpty }) ?? true) &&
                  (step.requirement != .promptVisible || step.requiredPromptID != nil)
              }),
              requiredAnnouncementIDs.allSatisfy({ !$0.isEmpty }),
              dispatchTasks.allSatisfy({ !$0.id.isEmpty && !$0.trainID.isEmpty && $0.deadlineSeconds.isFinite && $0.deadlineSeconds >= 0 && !$0.allowedSlotIDs.isEmpty }),
              dispatchSlots.allSatisfy({ !$0.id.isEmpty && !$0.trackID.isEmpty && $0.startTimeSeconds.isFinite && $0.startTimeSeconds >= 0 && $0.endTimeSeconds.isFinite && $0.endTimeSeconds > $0.startTimeSeconds }) else {
            throw GameModeError.invalidValue("scenario fields")
        }
        for index in stops.indices where index > 0 {
            guard stops[index].positionM >= stops[index - 1].positionM,
                  stops[index].scheduledArrivalSeconds >= stops[index - 1].scheduledArrivalSeconds,
                  stops[index - 1].scheduledDepartureSeconds.map({ stops[index].scheduledArrivalSeconds >= $0 }) ?? true else {
                throw GameModeError.invalidValue("stops must be ordered by position and schedule")
            }
        }
        let slotIDs = Set(dispatchSlots.map(\.id))
        guard dispatchTasks.allSatisfy({ $0.allowedSlotIDs.allSatisfy(slotIDs.contains) }) else {
            throw GameModeError.invalidValue("dispatch task references an unknown slot")
        }
        self.routeID = routeID
        self.routeLengthM = routeLengthM
        self.stops = stops
        self.driverDutyStepIDs = driverDutyStepIDs
        self.driverDepartureCheckStepID = driverDepartureCheckStepID
        self.playStyle = playStyle
        self.landmarks = landmarks
        self.trainingSteps = trainingSteps
        self.incident = incident
        self.requiredAnnouncementIDs = requiredAnnouncementIDs
        self.dispatchTasks = dispatchTasks
        self.dispatchSlots = dispatchSlots
        self.minimumTrainSeparationM = minimumTrainSeparationM
        self.dataLabel = .placeholder
    }

    /// テスト・試遊用の全架空データ。駅名、時刻、ランドマーク、列車IDは実在情報ではありません。
    public static func placeholder() throws -> GameModeScenario {
        try GameModeScenario(
            routeID: "PLACEHOLDER-fictional-route",
            routeLengthM: 1_200,
            stops: [
                GameModeStopPlan(id: "PLACEHOLDER-origin", stationNameAnnouncementID: "PLACEHOLDER-name-origin", positionM: 0, scheduledArrivalSeconds: 0),
                GameModeStopPlan(id: "PLACEHOLDER-station-a", stationNameAnnouncementID: "PLACEHOLDER-name-station-a", positionM: 600, scheduledArrivalSeconds: 60, scheduledDepartureSeconds: 70, expectedPlatformSide: .left),
                GameModeStopPlan(id: "PLACEHOLDER-terminal", stationNameAnnouncementID: "PLACEHOLDER-name-terminal", positionM: 1_200, scheduledArrivalSeconds: 120, expectedPlatformSide: .right)
            ],
            landmarks: [
                GameModeLandmarkPlan(id: "PLACEHOLDER-view-a", displayName: "架空の水辺", positionM: 300),
                GameModeLandmarkPlan(id: "PLACEHOLDER-view-b", displayName: "架空の丘", positionM: 900)
            ],
            trainingSteps: [
                GameModeTrainingStep(id: "PLACEHOLDER-control-check", title: "架空操作UIの教材確認", requirement: .stopped),
                GameModeTrainingStep(id: "PLACEHOLDER-signal-display", title: "架空信号表示の教材確認", requirement: .promptVisible, requiredPromptID: "PLACEHOLDER-signal-prompt"),
                GameModeTrainingStep(id: "PLACEHOLDER-protection-display", title: "架空保安装置表示の教材確認", requirement: .promptVisible, requiredPromptID: "PLACEHOLDER-protection-prompt"),
                GameModeTrainingStep(id: "PLACEHOLDER-limit", title: "ゲーム内速度表示を確認", requirement: .withinCurrentSpeedLimit),
                GameModeTrainingStep(id: "PLACEHOLDER-stop", title: "架空駅で停止状態を確認", requirement: .atStation)
            ],
            incident: GameModeIncidentPlan(
                id: "PLACEHOLDER-event-delay",
                kind: .vehicleFault,
                displayText: "PLACEHOLDER異常: 架空車両UIの状態通知",
                triggerAfterSeconds: 10,
                responseDeadlineSeconds: 20,
                expectedChoice: .requestGameHint
            ),
            requiredAnnouncementIDs: ["PLACEHOLDER-arrival-announcement"],
            dispatchTasks: [
                GameModeDispatchTask(id: "PLACEHOLDER-task-1", trainID: "PLACEHOLDER-train-1", deadlineSeconds: 30, allowedSlotIDs: ["PLACEHOLDER-slot-1", "PLACEHOLDER-slot-2"]),
                GameModeDispatchTask(id: "PLACEHOLDER-task-2", trainID: "PLACEHOLDER-train-2", deadlineSeconds: 60, allowedSlotIDs: ["PLACEHOLDER-slot-1", "PLACEHOLDER-slot-2"])
            ],
            dispatchSlots: [
                GameModeDispatchSlot(id: "PLACEHOLDER-slot-1", trackID: "PLACEHOLDER-track-1", startTimeSeconds: 0, endTimeSeconds: 60),
                GameModeDispatchSlot(id: "PLACEHOLDER-slot-2", trackID: "PLACEHOLDER-track-2", startTimeSeconds: 0, endTimeSeconds: 60)
            ]
        )
    }
}

public struct GameModeDefinition: Codable, Equatable, Sendable, Identifiable {
    public let id: GameModeID
    public let title: String
    public let initialState: String
    public let objective: String
    public let operations: [String]
    public let successConditions: [String]
    public let failureConditions: [String]
    public let uiFields: [String]
    public let evaluation: [String]
    public let dataLabel: GameModeDataLabel

    public init(
        id: GameModeID,
        title: String,
        initialState: String,
        objective: String,
        operations: [String],
        successConditions: [String],
        failureConditions: [String],
        uiFields: [String],
        evaluation: [String]
    ) {
        self.id = id
        self.title = title
        self.initialState = initialState
        self.objective = objective
        self.operations = operations
        self.successConditions = successConditions
        self.failureConditions = failureConditions
        self.uiFields = uiFields
        self.evaluation = evaluation
        self.dataLabel = .placeholder
    }
}

/// 表示と選択可能状態に使う9モードの明示的な契約。
public enum GameModeCatalog {
    public static let all: [GameModeDefinition] = [
        GameModeDefinition(
            id: .driver, title: "運転士",
            initialState: "現在の架空列車状態と乗務チェックリスト先頭から開始。",
            objective: "架空の点呼・車両確認・運転台準備・出発確認・運転確認・終着/入庫の各チェックを行い、停車駅順と速度条件を守る。",
            operations: ["乗務チェックを順番に記録", "停止・閉扉状態で出発確認", "位置/速度/加速度スナップショット確認", "駅停車・終着を記録"],
            successConditions: ["架空チェックリスト全件完了", "出発確認済み", "必須駅順守", "終端・停止で終了"],
            failureConditions: ["速度上限超過", "ドア開状態で走行", "停車順違反", "チェック順違反/未完了"],
            uiFields: ["現在位置/速度/加速度", "速度上限", "停車進捗", "次の乗務チェック", "出発確認", "モード状態"],
            evaluation: ["チェックリスト達成率", "停車駅達成数", "速度超過", "最大加速度/ジャーク", "進捗"]
        ),
        GameModeDefinition(
            id: .timetable, title: "ダイヤ",
            initialState: "秒単位の架空到着/発車ダイヤと回復判断枠から開始。",
            objective: "指定駅への到着と発車を観測し、時刻・停車順の達成度を評価する。",
            operations: ["駅到着/発車時刻の採取", "予定との差の確認", "ゲーム内回復判断の記録"],
            successConditions: ["計画イベントを観測", "終端到達", "許容差を満たすか、超過駅で回復判断を記録"],
            failureConditions: ["計画駅/イベント未達", "判断のない許容差超過", "駅順の不一致"],
            uiFields: ["到着/発車予定と実績差", "遅延", "回復判断枠", "次駅"],
            evaluation: ["定時イベント数", "最大遅延秒", "回復判断数"]
        ),
        GameModeDefinition(
            id: .free, title: "フリー",
            initialState: "ホスト提供済みの路線/車両/天候/時間/季節値だけを引き継ぎ、未接続値は未設定。",
            objective: "架空路線・車両・天候・時間・季節を選び、自由走行と任意目標/地点記録を行う。",
            operations: ["路線/車両/天候/時間/季節変更要求", "自己目標", "通過地点記録", "自由終了"],
            successConditions: ["任意終了で自己設定プレイとして完了"],
            failureConditions: ["ゲーム上の失敗条件なし。中断は放棄として区別"],
            uiFields: ["現在/要求路線・車両", "天候/時間/季節", "乗車率", "自己目標", "記録地点", "経過時間"],
            evaluation: ["走行時間", "地点数", "環境変更要求数。合否点は付けない"]
        ),
        GameModeDefinition(
            id: .conductor, title: "車掌",
            initialState: "ドア状態をホスト値から読み、確認未記録の状態で開始。",
            objective: "停車駅ごとにホーム側・ドア状態・閉扉確認を扱い、架空の駅名/車内案内を再生する。",
            operations: ["停車中のゲーム内ドア操作", "閉扉状態をホスト値で確認", "駅名案内/車内放送キュー再生"],
            successConditions: ["全対象駅でドアサイクルと確認を完了", "必須駅名/車内案内を再生"],
            failureConditions: ["誤った架空ホーム側", "ドア開状態で走行", "未確認のまま次駅へ進行"],
            uiFields: ["駅名/ホーム側", "ドア状態", "確認済み駅", "駅名/車内案内キュー", "エラー数"],
            evaluation: ["完了駅数", "案内数", "手順エラー数"]
        ),
        GameModeDefinition(
            id: .disruption, title: "異常対応",
            initialState: "架空の車両故障/急病人/踏切支障等から設定されたイベント条件を待機。",
            objective: "時間制限内に提示されたゲーム専用の選択肢へ応答する。",
            operations: ["イベントカードと期限確認", "ゲームヒント要求", "選択肢応答/解決記録"],
            successConditions: ["期限内に架空イベントの想定ゲーム選択肢を選ぶ"],
            failureConditions: ["誤選択", "期限切れ", "イベントを解決せず終了"],
            uiFields: ["イベント状態", "残り時間", "選択肢", "ヒント数", "注意ラベル"],
            evaluation: ["応答結果", "応答時間", "ヒント要求数"]
        ),
        GameModeDefinition(
            id: .training, title: "教習",
            initialState: "架空の操作・信号表示・保安装置UIの教材ステップ先頭から開始。",
            objective: "ホストが供給するゲーム内条件/表示に基づき、教材を順番に確認する。",
            operations: ["教材/条件確認", "ゲームヒント要求", "ステップ完了"],
            successConditions: ["全ステップを順序どおり完了し、誤り上限未満"],
            failureConditions: ["誤った順序または条件違反を規定回数以上記録"],
            uiFields: ["現在ステップ", "前提条件", "完了数", "ヒント数", "誤り数"],
            evaluation: ["完了ステップ率", "誤り数", "ヒント数"]
        ),
        GameModeDefinition(
            id: .fullLine, title: "全線",
            initialState: "始発から終着までの架空路線全長と順序付き停車駅を読み込む。",
            objective: "路線全体の進捗と駅順を追跡し、全線終端まで走行する。",
            operations: ["路線進捗更新", "停車駅到達記録", "終端で終了"],
            successConditions: ["必須駅を順番どおり通過し路線終端に到達"],
            failureConditions: ["終端到達時に未通過駅", "駅順序違反", "別路線の状態入力"],
            uiFields: ["全線進捗率", "次駅", "通過済み駅", "路線終端", "区間位置"],
            evaluation: ["進捗率", "駅達成数", "順序違反数"]
        ),
        GameModeDefinition(
            id: .tourism, title: "観光",
            initialState: "架空景観ポイント一覧と未発見状態で、車窓を楽しむ走行から開始。",
            objective: "景観が表示されている間に許容速度・位置で観察記録を行う。",
            operations: ["景観カード確認", "表示中ランドマーク観察", "自由終了"],
            successConditions: ["必要数以上の景観ポイントを有効条件で観察"],
            failureConditions: ["路線終端までに必要数へ届かない", "不正な観察操作"],
            uiFields: ["表示中の景観", "発見数", "観察条件", "路線進捗"],
            evaluation: ["有効観察数", "発見率", "終端進捗"]
        ),
        GameModeDefinition(
            id: .companyOperations, title: "会社運行",
            initialState: "複数の架空列車・秒単位の運行タスク・時間枠を未割当で読み込む。",
            objective: "複数列車のダイヤ/運行タスクを許可時間枠へ割り当て、競合と期限を管理する。",
            operations: ["複数列車状態確認", "列車タスク/時間枠/線路割当", "競合と期限の確認"],
            successConditions: ["全列車タスクを期限内に異なる許可枠へ割当", "観測競合なし"],
            failureConditions: ["同一枠競合", "期限超過", "未割当タスクで終了"],
            uiFields: ["列車一覧", "未割当タスク", "時間枠/線路", "競合数", "期限超過"],
            evaluation: ["割当達成数", "競合数", "期限超過タスク数"]
        )
    ]

    public static func definition(for id: GameModeID) -> GameModeDefinition {
        // The catalog is a fixed list containing exactly one definition for each GameModeID.
        all.first { $0.id == id }!
    }
}

public enum GameModeAction: Equatable, Sendable {
    case start
    case finish
    case abandon
    case driverCompleteDutyStep(String)
    case driverConfirmDeparture
    case timetableUseRecoveryCredit(stationID: String)
    case freeSetGoal(String)
    case freeRequestRoute(String)
    case freeRequestVehicle(String)
    case freeRequestWeather(String)
    case freeRequestTimeOfDay(String)
    case freeRequestSeason(String)
    case freeRequestPassengerLoad(Double)
    case freeRecordWaypoint(String)
    case conductorOpenDoors(GameModePlatformSide)
    case conductorCloseDoors
    case conductorConfirmDoorClosure
    case conductorPlayAnnouncement(String)
    case conductorAnnounceStationName
    case disruptionRespond(GameModeIncidentChoice)
    case trainingRequestHint
    case trainingCompleteStep(String)
    case modeRequestHint
    case tourismObserve(String)
    case companyAssign(taskID: String, slotID: String)
}

/// ホストへ返すシミュレーション専用要求。実設備・実路線への操作命令ではありません。
public enum GameModeHostEffect: Equatable, Sendable {
    case requestRoute(String)
    case requestVehicle(String)
    case requestWeather(String)
    case requestTimeOfDay(String)
    case requestSeason(String)
    case requestPassengerLoad(Double)
    case setGameDoorState(GameModeDoorState)
    case playGameAnnouncement(String)
    case presentGameHint(String)
}

public enum GameModeFailureReason: String, Codable, Equatable, Sendable {
    case overspeedObserved
    case doorOpenWhileMoving
    case stopOrderViolation
    case departureNotConfirmed
    case driverChecklistOrderViolation
    case driverChecklistIncomplete
    case routeIncomplete
    case missedTimepoint
    case conductorSequenceError
    case wrongPlatformSide
    case wrongIncidentChoice
    case incidentDeadlineExpired
    case unresolvedIncident
    case trainingIncomplete
    case trainingMistakeLimit
    case insufficientLandmarks
    case dispatchConflict
    case dispatchDeadlineExpired
    case unassignedTasks
    case routeMismatch
}

public struct GameModeEvaluation: Codable, Equatable, Sendable {
    public let mode: GameModeID
    public let outcome: GameModeOutcome
    public let scorePercent: Double?
    public let summary: String
    public let metrics: [String: Double]
    public let failureReason: GameModeFailureReason?
    public let blockingReason: GameModeBlockingReason?
    public let dataLabel: GameModeDataLabel

    public init(
        mode: GameModeID,
        outcome: GameModeOutcome,
        scorePercent: Double?,
        summary: String,
        metrics: [String: Double],
        failureReason: GameModeFailureReason? = nil,
        blockingReason: GameModeBlockingReason? = nil
    ) {
        self.mode = mode
        self.outcome = outcome
        self.scorePercent = scorePercent
        self.summary = summary
        self.metrics = metrics
        self.failureReason = failureReason
        self.blockingReason = blockingReason
        self.dataLabel = .placeholder
    }
}
