import Combine
import Foundation
import RailwayOperations

/// Immutable host-owned state sampled on one completed fixed simulation tick.
/// The coordinator consumes this value; it never reads or controls SimulatorModel.
struct OperationsGameplayHostSnapshot: Equatable, Sendable {
    let simulationTimeSeconds: Double
    let fixedTick: UInt64
    let fixedTimeStepSeconds: Double
    let routeID: String
    let train: SharedTrainSnapshot

    init(
        simulationTimeSeconds: Double,
        fixedTick: UInt64,
        fixedTimeStepSeconds: Double,
        routeID: String,
        train: SharedTrainSnapshot
    ) throws {
        guard simulationTimeSeconds.isFinite, simulationTimeSeconds >= 0,
              fixedTimeStepSeconds.isFinite, fixedTimeStepSeconds > 0,
              !routeID.isEmpty else {
            throw OperationsGameplayCoordinatorError.invalidHostSnapshot
        }
        self.simulationTimeSeconds = simulationTimeSeconds
        self.fixedTick = fixedTick
        self.fixedTimeStepSeconds = fixedTimeStepSeconds
        self.routeID = routeID
        self.train = train
    }
}

enum OperationsGameplayCoordinatorError: LocalizedError {
    case invalidHostSnapshot
    case routeMismatch(expected: String, received: String)
    case tickDidNotAdvance
    case timeDidNotAdvance
    case fixedStepChanged
    case staleHostSnapshot

    var errorDescription: String? {
        switch self {
        case .invalidHostSnapshot:
            return "固定tick snapshotの値が不正です。"
        case let .routeMismatch(expected, received):
            return "路線IDがシナリオと一致しません（期待: \(expected)、入力: \(received)）。"
        case .tickDidNotAdvance:
            return "新しい固定tickが必要です。"
        case .timeDidNotAdvance:
            return "シミュレーション時刻が進んでいません。"
        case .fixedStepChanged:
            return "運転中に固定時間刻みが変わりました。"
        case .staleHostSnapshot:
            return "最新の固定tick snapshotを先に受け取ってください。"
        }
    }
}

/// UI-facing adapter for RailwayOperations. It coordinates gameplay records only;
/// train motion, controls, signals, and any real-world operating decisions stay host-owned.
@MainActor
final class OperationsGameplayCoordinator: ObservableObject {
    let scenario: OperationsScenario
    let mode: TrainingMode

    @Published private(set) var workflow: OperationsWorkflow
    @Published private(set) var pointingCalling: PointingCallingTracker
    @Published private(set) var disruptionSession: DisruptionTrainingSession
    @Published private(set) var latestHostSnapshot: OperationsGameplayHostSnapshot?
    @Published private(set) var operationsSnapshot: OperationsSnapshot?
    @Published private(set) var scorecard: OperationsScorecard
    @Published private(set) var gameRuleOutcomes: [GameRuleOutcome] = []
    @Published private(set) var motionSamples: [MotionSample] = []
    @Published private(set) var lastErrorMessage: String?

    private let scoringConfiguration: OperationsScoringConfiguration

    init(
        scenario: OperationsScenario,
        mode: TrainingMode,
        checkpoints: [PointingCallingDefinition] = [],
        disruptionEvents: [DisruptionEventDefinition] = [],
        scoringConfiguration: OperationsScoringConfiguration = .gameDefaults
    ) throws {
        self.scenario = scenario
        self.mode = mode
        self.workflow = OperationsWorkflow(scenario: scenario, mode: mode)
        self.pointingCalling = try PointingCallingTracker(definitions: checkpoints)
        self.disruptionSession = try DisruptionTrainingSession(mode: mode, definitions: disruptionEvents)
        self.scoringConfiguration = scoringConfiguration
        self.scorecard = OperationsScorer.evaluate(
            OperationsScoringInput(), mode: mode, configuration: scoringConfiguration
        )
    }

    /// Submit a host sample once per completed fixed tick (or a strictly increasing subset).
    /// It is the only operation that advances the adapter's notion of host time.
    func receiveFixedTick(_ host: OperationsGameplayHostSnapshot) throws {
        guard host.routeID == scenario.routeID else {
            throw OperationsGameplayCoordinatorError.routeMismatch(expected: scenario.routeID, received: host.routeID)
        }
        if let previous = latestHostSnapshot {
            guard host.fixedTick > previous.fixedTick else { throw OperationsGameplayCoordinatorError.tickDidNotAdvance }
            guard host.simulationTimeSeconds > previous.simulationTimeSeconds else { throw OperationsGameplayCoordinatorError.timeDidNotAdvance }
            guard abs(host.fixedTimeStepSeconds - previous.fixedTimeStepSeconds) < 1e-9 else {
                throw OperationsGameplayCoordinatorError.fixedStepChanged
            }
        }

        latestHostSnapshot = host
        let sample = try MotionSample(
            id: "tick-\(host.fixedTick)",
            simulationTimeSeconds: host.simulationTimeSeconds,
            accelerationMps2: host.train.accelerationMps2
        )
        motionSamples.append(sample)
        _ = try disruptionSession.activateDueEvents(at: host.simulationTimeSeconds)
        refreshDerivedState(using: host)
    }

    /// Apply a workflow command only against the most recently received fixed tick.
    func apply(_ command: OperationsWorkflowCommand, using host: OperationsGameplayHostSnapshot) throws {
        try requireLatest(host)
        var updated = workflow
        _ = try updated.apply(command, at: host.simulationTimeSeconds)
        workflow = updated
        let outcome = try GameRuleOutcome(
            id: "workflow-\(updated.events.last?.id ?? 0)",
            kind: .workflowSequence,
            passed: true,
            explanation: "ゲーム内ワークフローの操作を記録"
        )
        gameRuleOutcomes.append(outcome)
        refreshDerivedState(using: host)
    }

    /// Activate fictional callout prompts at a host-selected game checkpoint.
    @discardableResult
    func activateCheckpoint(
        _ trigger: GameCheckpointTrigger,
        contextID: String? = nil,
        using host: OperationsGameplayHostSnapshot
    ) throws -> [String] {
        try requireLatest(host)
        var updated = pointingCalling
        let ids = try updated.activate(
            trigger: trigger,
            contextID: contextID,
            at: host.simulationTimeSeconds,
            positionM: host.train.positionM
        )
        pointingCalling = updated
        refreshDerivedState(using: host)
        return ids
    }

    func recordCallout(_ text: String, for checkpointID: String, using host: OperationsGameplayHostSnapshot) throws {
        try requireLatest(host)
        var updated = pointingCalling
        let record = try updated.perform(
            checkpointID: checkpointID,
            callout: text,
            at: host.simulationTimeSeconds,
            positionM: host.train.positionM
        )
        pointingCalling = updated
        if record.result != .correct {
            gameRuleOutcomes.append(try GameRuleOutcome(
                id: "callout-\(record.id)", kind: .pointingCalling, passed: false,
                explanation: "ゲーム内コール判定"
            ))
        }
        refreshDerivedState(using: host)
    }

    func markCheckpointMissed(_ checkpointID: String, using host: OperationsGameplayHostSnapshot) throws {
        try requireLatest(host)
        var updated = pointingCalling
        let record = try updated.markMissed(
            checkpointID: checkpointID,
            at: host.simulationTimeSeconds,
            positionM: host.train.positionM
        )
        pointingCalling = updated
        gameRuleOutcomes.append(try GameRuleOutcome(
            id: "missed-callout-\(record.id)", kind: .pointingCalling, passed: false,
            explanation: "ゲーム内チェックポイント未実施"
        ))
        refreshDerivedState(using: host)
    }

    /// Record a fictional rule-event result. This does not enforce or represent real railway rules.
    func recordGameRule(_ kind: GameRuleKind, passed: Bool, explanation: String, using host: OperationsGameplayHostSnapshot) throws {
        try requireLatest(host)
        let outcome = try GameRuleOutcome(
            id: "game-rule-\(UUID().uuidString)",
            kind: kind,
            passed: passed,
            explanation: explanation
        )
        gameRuleOutcomes.append(outcome)
        refreshDerivedState(using: host)
    }

    func respondToDisruption(
        eventID: String,
        choice: DisruptionGameChoice,
        using host: OperationsGameplayHostSnapshot
    ) throws {
        try requireLatest(host)
        var updated = disruptionSession
        let record = try updated.respond(eventID: eventID, choice: choice, at: host.simulationTimeSeconds)
        disruptionSession = updated
        if !record.matchedGameChoice {
            gameRuleOutcomes.append(try GameRuleOutcome(
                id: "disruption-\(record.id)", kind: .disruptionResponse, passed: false,
                explanation: "架空イベントに対するゲーム選択肢"
            ))
        }
        refreshDerivedState(using: host)
    }

    /// Recalculate the four game-score categories from recorded observations.
    func evaluateScorecard() {
        scorecard = OperationsScorer.evaluate(scoringInput, mode: mode, configuration: scoringConfiguration)
        if let latestHostSnapshot { refreshOperationsSnapshot(using: latestHostSnapshot) }
    }

    func present(error: Error) {
        lastErrorMessage = error.localizedDescription
    }

    func clearError() {
        lastErrorMessage = nil
    }

    private var scoringInput: OperationsScoringInput {
        OperationsScoringInput(
            scheduleObservations: workflow.scheduleObservations,
            stopAssessments: workflow.stopAssessments,
            motionSamples: motionSamples,
            ruleOutcomes: gameRuleOutcomes,
            pointingCallingRecords: pointingCalling.records,
            disruptionResponses: disruptionSession.records.map {
                try! DisruptionResponseOutcome(id: "\($0.eventID)-\($0.id)", matchedGameChoice: $0.matchedGameChoice)
            }
        )
    }

    private func requireLatest(_ host: OperationsGameplayHostSnapshot) throws {
        guard latestHostSnapshot == host else { throw OperationsGameplayCoordinatorError.staleHostSnapshot }
    }

    private func refreshDerivedState(using host: OperationsGameplayHostSnapshot) {
        scorecard = OperationsScorer.evaluate(scoringInput, mode: mode, configuration: scoringConfiguration)
        refreshOperationsSnapshot(using: host)
    }

    private func refreshOperationsSnapshot(using host: OperationsGameplayHostSnapshot) {
        operationsSnapshot = try? OperationsSnapshot.make(
            workflow: workflow,
            train: host.train,
            simulationTimeSeconds: host.simulationTimeSeconds,
            fixedTick: host.fixedTick,
            fixedTimeStepSeconds: host.fixedTimeStepSeconds,
            pointingCalling: pointingCalling,
            activeDisruptionIDs: disruptionSession.activeEventIDs,
            scorecard: scorecard
        )
    }
}
