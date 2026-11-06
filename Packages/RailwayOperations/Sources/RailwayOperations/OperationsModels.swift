import Foundation

/// Every procedure-like prompt in this module is a fictional game rule, not an operator procedure.
public enum OperationsContentLabel: String, Codable, CaseIterable, Sendable {
    case fictionalGameRules = "FICTIONAL GAME RULES — NOT A RAILWAY OPERATING PROCEDURE"
    case gameOnlyNotSafetyTraining = "GAME ONLY — NOT RAILWAY SAFETY TRAINING"
}

public enum OperationsError: Error, Equatable, Sendable {
    case invalidValue(String)
    case invalidScenario(String)
    case invalidTransition(String)
    case unmetRequirements([String])
    case unknownIdentifier(String)
    case duplicateIdentifier(String)
    case checkpointNotDue(String)
    case checkpointAlreadyResolved(String)
    case eventNotActive(String)
    case timeMustNotRegress
}

public enum TrainingMode: String, Codable, CaseIterable, Sendable {
    case practice
    case standard
    case disruptionTraining

    public var profile: TrainingModeProfile {
        switch self {
        case .practice:
            return TrainingModeProfile(mode: self, showsHints: true, promptLevel: .all, toleranceMultiplier: 1.75, enablesDisruptions: false)
        case .standard:
            return TrainingModeProfile(mode: self, showsHints: false, promptLevel: .importantOnly, toleranceMultiplier: 1.0, enablesDisruptions: false)
        case .disruptionTraining:
            return TrainingModeProfile(mode: self, showsHints: true, promptLevel: .eventDriven, toleranceMultiplier: 1.0, enablesDisruptions: true)
        }
    }
}

public enum TrainingPromptLevel: String, Codable, Sendable {
    case all
    case importantOnly
    case eventDriven
}

public struct TrainingModeProfile: Codable, Equatable, Sendable {
    public let mode: TrainingMode
    public let showsHints: Bool
    public let promptLevel: TrainingPromptLevel
    /// Multiplier for game scoring tolerances. It changes scoring only, not simulated physics.
    public let toleranceMultiplier: Double
    public let enablesDisruptions: Bool

    public init(mode: TrainingMode, showsHints: Bool, promptLevel: TrainingPromptLevel, toleranceMultiplier: Double, enablesDisruptions: Bool) {
        self.mode = mode
        self.showsHints = showsHints
        self.promptLevel = promptLevel
        self.toleranceMultiplier = toleranceMultiplier
        self.enablesDisruptions = enablesDisruptions
    }
}

public enum WorkflowPhase: String, Codable, CaseIterable, Sendable {
    case preDutyChecks
    case cabSetup
    case depotExit
    case departurePreparation
    case enRoute
    case stationStop
    case endOfRun
    case completed
}

public enum PreDutyCheck: String, Codable, CaseIterable, Sendable {
    case gameBriefing
    case vehicleConditionPrompt
    case routeAndTimetablePrompt
    case cabEquipmentPrompt
}

public enum CabSetupCheck: String, Codable, CaseIterable, Sendable {
    case controllerNeutralPrompt
    case brakeGaugePrompt
    case statusDisplayPrompt
}

public enum DepartureCheck: String, Codable, CaseIterable, Sendable {
    case routeMarkerPrompt
    case doorsClosedPrompt
    case gameSignalPrompt
}

public enum PostRunCheck: String, Codable, CaseIterable, Sendable {
    case reviewRunLogPrompt
    case secureCabPrompt
    case closeOutPrompt
}

public enum GameSignalAspect: String, Codable, CaseIterable, Sendable {
    case proceed
    case caution
    case stop
}

public struct OperationsStopDefinition: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let stationName: String
    public let targetPositionM: Double
    public let scheduledArrivalSeconds: Double
    public let scheduledDepartureSeconds: Double
    public let positionToleranceM: Double

    public init(id: String, stationName: String, targetPositionM: Double, scheduledArrivalSeconds: Double, scheduledDepartureSeconds: Double, positionToleranceM: Double = 1.0) throws {
        guard !id.isEmpty, !stationName.isEmpty,
              targetPositionM.isFinite, targetPositionM >= 0,
              scheduledArrivalSeconds.isFinite, scheduledArrivalSeconds >= 0,
              scheduledDepartureSeconds.isFinite, scheduledDepartureSeconds >= scheduledArrivalSeconds,
              positionToleranceM.isFinite, positionToleranceM > 0 else {
            throw OperationsError.invalidValue("stop definition")
        }
        self.id = id
        self.stationName = stationName
        self.targetPositionM = targetPositionM
        self.scheduledArrivalSeconds = scheduledArrivalSeconds
        self.scheduledDepartureSeconds = scheduledDepartureSeconds
        self.positionToleranceM = positionToleranceM
    }
}

/// Ordered, fictional gameplay itinerary consumed by the operations state machine.
public struct OperationsScenario: Codable, Equatable, Sendable {
    public let runID: String
    public let routeID: String
    public let routeLengthM: Double
    public let originStationID: String
    public let originScheduledDepartureSeconds: Double
    public let stops: [OperationsStopDefinition]

    public init(runID: String, routeID: String, routeLengthM: Double, originStationID: String, originScheduledDepartureSeconds: Double = 0, stops: [OperationsStopDefinition]) throws {
        guard !runID.isEmpty, !routeID.isEmpty, !originStationID.isEmpty,
              routeLengthM.isFinite, routeLengthM > 0,
              originScheduledDepartureSeconds.isFinite, originScheduledDepartureSeconds >= 0,
              !stops.isEmpty else {
            throw OperationsError.invalidScenario("run, route, origin, length, departure time, and at least one stop are required")
        }
        guard Set(stops.map(\.id)).count == stops.count else {
            throw OperationsError.duplicateIdentifier("stop id")
        }
        var previousPosition = 0.0
        var previousDeparture = originScheduledDepartureSeconds
        for stop in stops {
            guard stop.targetPositionM > previousPosition,
                  stop.targetPositionM <= routeLengthM,
                  stop.scheduledArrivalSeconds >= previousDeparture else {
                throw OperationsError.invalidScenario("stops must progress along the route and timetable")
            }
            previousPosition = stop.targetPositionM
            previousDeparture = stop.scheduledDepartureSeconds
        }
        self.runID = runID
        self.routeID = routeID
        self.routeLengthM = routeLengthM
        self.originStationID = originStationID
        self.originScheduledDepartureSeconds = originScheduledDepartureSeconds
        self.stops = stops
    }
}

public enum ScheduleObservationKind: String, Codable, CaseIterable, Sendable {
    case arrival
    case departure
}

public struct ScheduleObservation: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let kind: ScheduleObservationKind
    public let scheduledTimeSeconds: Double
    public let actualTimeSeconds: Double

    public init(id: String, kind: ScheduleObservationKind, scheduledTimeSeconds: Double, actualTimeSeconds: Double) throws {
        guard !id.isEmpty, scheduledTimeSeconds.isFinite, actualTimeSeconds.isFinite,
              scheduledTimeSeconds >= 0, actualTimeSeconds >= 0 else {
            throw OperationsError.invalidValue("schedule observation")
        }
        self.id = id
        self.kind = kind
        self.scheduledTimeSeconds = scheduledTimeSeconds
        self.actualTimeSeconds = actualTimeSeconds
    }

    public var deviationSeconds: Double { actualTimeSeconds - scheduledTimeSeconds }
}

public struct StopAssessment: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let targetPositionM: Double
    public let actualPositionM: Double
    public let toleranceM: Double
    public let stopped: Bool

    public init(id: String, targetPositionM: Double, actualPositionM: Double, toleranceM: Double, stopped: Bool) throws {
        guard !id.isEmpty, targetPositionM.isFinite, targetPositionM >= 0,
              actualPositionM.isFinite, actualPositionM >= 0,
              toleranceM.isFinite, toleranceM > 0 else {
            throw OperationsError.invalidValue("stop assessment")
        }
        self.id = id
        self.targetPositionM = targetPositionM
        self.actualPositionM = actualPositionM
        self.toleranceM = toleranceM
        self.stopped = stopped
    }

    /// Positive error means the train passed the target in increasing chainage.
    public var positionErrorM: Double { actualPositionM - targetPositionM }
    public var overshootM: Double { max(0, positionErrorM) }
}

public struct MotionSample: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let simulationTimeSeconds: Double
    public let accelerationMps2: Double

    public init(id: String, simulationTimeSeconds: Double, accelerationMps2: Double) throws {
        guard !id.isEmpty, simulationTimeSeconds.isFinite, simulationTimeSeconds >= 0,
              accelerationMps2.isFinite else {
            throw OperationsError.invalidValue("motion sample")
        }
        self.id = id
        self.simulationTimeSeconds = simulationTimeSeconds
        self.accelerationMps2 = accelerationMps2
    }
}

public enum GameRuleKind: String, Codable, CaseIterable, Sendable {
    case signalCompliance
    case speedLimitCompliance
    case workflowSequence
    case pointingCalling
    case disruptionResponse
}

public struct GameRuleOutcome: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let kind: GameRuleKind
    public let passed: Bool
    public let deductionPoints: Double
    public let explanation: String

    public init(id: String, kind: GameRuleKind, passed: Bool, deductionPoints: Double = 10, explanation: String = "") throws {
        guard !id.isEmpty, deductionPoints.isFinite, deductionPoints >= 0, deductionPoints <= 100 else {
            throw OperationsError.invalidValue("game rule outcome")
        }
        self.id = id
        self.kind = kind
        self.passed = passed
        self.deductionPoints = deductionPoints
        self.explanation = explanation
    }
}
