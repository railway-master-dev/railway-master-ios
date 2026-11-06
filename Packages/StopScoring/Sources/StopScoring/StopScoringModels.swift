import Foundation

/// Errors from invalid configuration, simulation ticks, or station-event transitions.
public enum StopScoringError: Error, Equatable {
    case invalidConfiguration(String)
    case invalidTick(String)
    case unknownStation(String)
    case invalidEvent(String)
    case duplicateEventID(String)
    case sessionFinished
}

/// The coordinate direction of travel along the caller's route chainage axis.
public enum TravelDirection: String, Equatable, Sendable {
    case increasingChainage
    case decreasingChainage
}

public enum DoorSide: String, Equatable, Hashable, Sendable {
    case left
    case right
}

public enum DoorAction: String, Equatable, Sendable {
    case open
    case close
}

public enum ProcedureOutcome: String, Equatable, Sendable {
    case completed
    case failed
    case skipped
}

/// A closed chainage interval, expressed in metres on the route's coordinate axis.
public struct StopPositionWindow: Equatable, Sendable {
    public let lowerBoundMeters: Double
    public let upperBoundMeters: Double

    public init(lowerBoundMeters: Double, upperBoundMeters: Double) throws {
        guard lowerBoundMeters.isFinite, upperBoundMeters.isFinite,
              lowerBoundMeters <= upperBoundMeters else {
            throw StopScoringError.invalidConfiguration("Stop window bounds must be finite and ordered.")
        }
        self.lowerBoundMeters = lowerBoundMeters
        self.upperBoundMeters = upperBoundMeters
    }

    public func contains(_ chainageMeters: Double) -> Bool {
        chainageMeters >= lowerBoundMeters && chainageMeters <= upperBoundMeters
    }
}

/// Optional timetable checkpoints. Simulation times are seconds on one monotonic scenario clock.
public struct StopSchedule: Equatable, Sendable {
    public let scheduledArrivalSeconds: Double?
    public let scheduledDepartureSeconds: Double?

    public init(scheduledArrivalSeconds: Double? = nil, scheduledDepartureSeconds: Double? = nil) throws {
        if let value = scheduledArrivalSeconds, !value.isFinite {
            throw StopScoringError.invalidConfiguration("Scheduled arrival must be finite.")
        }
        if let value = scheduledDepartureSeconds, !value.isFinite {
            throw StopScoringError.invalidConfiguration("Scheduled departure must be finite.")
        }
        if let arrival = scheduledArrivalSeconds, let departure = scheduledDepartureSeconds, departure < arrival {
            throw StopScoringError.invalidConfiguration("Scheduled departure cannot precede scheduled arrival.")
        }
        self.scheduledArrivalSeconds = scheduledArrivalSeconds
        self.scheduledDepartureSeconds = scheduledDepartureSeconds
    }

    public static var none: StopSchedule {
        // The all-nil construction cannot fail.
        try! StopSchedule()
    }
}

/// A service stop in route order. The stop-position window is in physical route chainage,
/// and the train's leading end is the reference point for target and actual stop positions.
public struct StationStopDefinition: Equatable, Sendable {
    public let stationID: String
    public let displayName: String?
    public let stationChainageMeters: Double
    public let targetStopChainageMeters: Double
    public let platformStartChainageMeters: Double
    public let platformEndChainageMeters: Double
    public let permittedStopWindow: StopPositionWindow
    public let schedule: StopSchedule
    public let expectedDoorSide: DoorSide?
    public let requiredProcedureSteps: [String]

    public init(
        stationID: String,
        displayName: String? = nil,
        stationChainageMeters: Double,
        targetStopChainageMeters: Double,
        platformStartChainageMeters: Double,
        platformEndChainageMeters: Double,
        permittedStopWindow: StopPositionWindow,
        schedule: StopSchedule = .none,
        expectedDoorSide: DoorSide? = nil,
        requiredProcedureSteps: [String] = []
    ) throws {
        guard !stationID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw StopScoringError.invalidConfiguration("Station ID cannot be empty.")
        }
        let numericValues = [stationChainageMeters, targetStopChainageMeters,
                             platformStartChainageMeters, platformEndChainageMeters]
        guard numericValues.allSatisfy({ $0.isFinite }), platformStartChainageMeters < platformEndChainageMeters else {
            throw StopScoringError.invalidConfiguration("Station and platform chainages must be finite; platform bounds must be ordered.")
        }
        guard permittedStopWindow.contains(targetStopChainageMeters) else {
            throw StopScoringError.invalidConfiguration("Target stop position must be inside the permitted stop window.")
        }
        let normalizedSteps = requiredProcedureSteps.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        guard normalizedSteps.allSatisfy({ !$0.isEmpty }), Set(normalizedSteps).count == normalizedSteps.count else {
            throw StopScoringError.invalidConfiguration("Required procedure step IDs must be non-empty and unique per station.")
        }
        self.stationID = stationID
        self.displayName = displayName
        self.stationChainageMeters = stationChainageMeters
        self.targetStopChainageMeters = targetStopChainageMeters
        self.platformStartChainageMeters = platformStartChainageMeters
        self.platformEndChainageMeters = platformEndChainageMeters
        self.permittedStopWindow = permittedStopWindow
        self.schedule = schedule
        self.expectedDoorSide = expectedDoorSide
        self.requiredProcedureSteps = normalizedSteps
    }
}

/// Per-component shares of a station's 100-point fictional game score.
public struct ComponentWeights: Equatable, Sendable {
    public let stop: Double
    public let timetable: Double
    public let doors: Double
    public let procedures: Double

    public init(stop: Double, timetable: Double, doors: Double, procedures: Double) {
        self.stop = stop
        self.timetable = timetable
        self.doors = doors
        self.procedures = procedures
    }

    public static let fictionalDefault = ComponentWeights(stop: 55, timetable: 20, doors: 15, procedures: 10)
}

/// All values here are tunable fictional game rules, not real railway operating or assessment rules.
public struct GameScoringPolicy: Equatable, Sendable {
    public let weights: ComponentWeights
    public let stopPrecisionToleranceMeters: Double
    public let earlyLateGraceSeconds: Double
    public let timetablePenaltyPointsPerMinute: Double
    public let stoppedSpeedThresholdMetersPerSecond: Double
    public let wrongDoorSidePenaltyPoints: Double
    public let missingExpectedDoorOpenPenaltyPoints: Double
    public let missingExpectedDoorClosePenaltyPoints: Double
    public let doorSequenceViolationPenaltyPoints: Double
    public let outOfOrderProcedurePenaltyPoints: Double

    public init(
        weights: ComponentWeights = .fictionalDefault,
        stopPrecisionToleranceMeters: Double = 0.25,
        earlyLateGraceSeconds: Double = 30,
        timetablePenaltyPointsPerMinute: Double = 2,
        stoppedSpeedThresholdMetersPerSecond: Double = 0.1,
        wrongDoorSidePenaltyPoints: Double = 25,
        missingExpectedDoorOpenPenaltyPoints: Double = 50,
        missingExpectedDoorClosePenaltyPoints: Double = 50,
        doorSequenceViolationPenaltyPoints: Double = 20,
        outOfOrderProcedurePenaltyPoints: Double = 15
    ) {
        self.weights = weights
        self.stopPrecisionToleranceMeters = stopPrecisionToleranceMeters
        self.earlyLateGraceSeconds = earlyLateGraceSeconds
        self.timetablePenaltyPointsPerMinute = timetablePenaltyPointsPerMinute
        self.stoppedSpeedThresholdMetersPerSecond = stoppedSpeedThresholdMetersPerSecond
        self.wrongDoorSidePenaltyPoints = wrongDoorSidePenaltyPoints
        self.missingExpectedDoorOpenPenaltyPoints = missingExpectedDoorOpenPenaltyPoints
        self.missingExpectedDoorClosePenaltyPoints = missingExpectedDoorClosePenaltyPoints
        self.doorSequenceViolationPenaltyPoints = doorSequenceViolationPenaltyPoints
        self.outOfOrderProcedurePenaltyPoints = outOfOrderProcedurePenaltyPoints
    }

    internal func validate() throws {
        let values = [weights.stop, weights.timetable, weights.doors, weights.procedures,
                      stopPrecisionToleranceMeters, earlyLateGraceSeconds,
                      timetablePenaltyPointsPerMinute, stoppedSpeedThresholdMetersPerSecond,
                      wrongDoorSidePenaltyPoints, missingExpectedDoorOpenPenaltyPoints,
                      missingExpectedDoorClosePenaltyPoints, doorSequenceViolationPenaltyPoints,
                      outOfOrderProcedurePenaltyPoints]
        guard values.allSatisfy({ $0.isFinite && $0 >= 0 }) else {
            throw StopScoringError.invalidConfiguration("Scoring weights and policy values must be finite and non-negative.")
        }
        let weightTotal = weights.stop + weights.timetable + weights.doors + weights.procedures
        guard abs(weightTotal - 100) <= 0.000_001 else {
            throw StopScoringError.invalidConfiguration("Component weights must total exactly 100 points.")
        }
    }
}

/// One deterministic snapshot from the simulator. `leadingEndChainageMeters` and
/// `speedMetersPerSecond` are measured in the same route coordinate/system as station data.
public struct SimulationTick: Equatable, Sendable {
    public let sequence: Int
    public let simulationTimeSeconds: Double
    public let leadingEndChainageMeters: Double
    public let speedMetersPerSecond: Double

    public init(
        sequence: Int,
        simulationTimeSeconds: Double,
        leadingEndChainageMeters: Double,
        speedMetersPerSecond: Double
    ) throws {
        guard sequence >= 0, simulationTimeSeconds.isFinite,
              leadingEndChainageMeters.isFinite, speedMetersPerSecond.isFinite,
              speedMetersPerSecond >= 0 else {
            throw StopScoringError.invalidTick("Tick sequence must be non-negative; time, position and non-negative speed must be finite.")
        }
        self.sequence = sequence
        self.simulationTimeSeconds = simulationTimeSeconds
        self.leadingEndChainageMeters = leadingEndChainageMeters
        self.speedMetersPerSecond = speedMetersPerSecond
    }
}

public enum StationEventKind: Equatable, Sendable {
    case arrival
    case stopCompleted
    case doorOperation(side: DoorSide, action: DoorAction)
    case procedureStep(stepID: String, outcome: ProcedureOutcome)
    case departure
}

/// Event IDs are unique within a scoring session; event timestamps and positions come from their tick.
public struct StationEvent: Equatable, Sendable {
    public let eventID: String
    public let stationID: String
    public let kind: StationEventKind

    public init(eventID: String, stationID: String, kind: StationEventKind) throws {
        guard !eventID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !stationID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw StopScoringError.invalidEvent("Event ID and station ID cannot be empty.")
        }
        if case let .procedureStep(stepID, _) = kind,
           stepID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw StopScoringError.invalidEvent("Procedure step ID cannot be empty.")
        }
        self.eventID = eventID
        self.stationID = stationID
        self.kind = kind
    }
}

public enum StationProgress: String, Equatable, Sendable {
    case notStarted
    case arrived
    case stopped
    case departed
}

public struct StopMeasurement: Equatable, Sendable {
    public let targetChainageMeters: Double
    public let actualChainageMeters: Double
    /// Signed physical-axis error: actual leading-end chainage minus target chainage.
    public let signedErrorMeters: Double
    public let absoluteErrorMeters: Double
    public let absoluteErrorCentimeters: Double
    public let insidePermittedWindow: Bool
    public let trainFitsPlatform: Bool
}

public struct DoorOperationRecord: Equatable, Sendable {
    public let eventID: String
    public let atSeconds: Double
    public let side: DoorSide
    public let action: DoorAction
}

public struct ProcedureRecord: Equatable, Sendable {
    public let eventID: String
    public let atSeconds: Double
    public let stepID: String
    public let outcome: ProcedureOutcome
}

public struct StationComponentScores: Equatable, Sendable {
    /// Each component is normalized to 0...100 before applying its configured weight.
    public let stop: Double
    public let timetable: Double
    public let doors: Double
    public let procedures: Double
    /// Weighted station total, normalized to 0...100.
    public let total: Double
}

public struct StationEvaluation: Equatable, Sendable {
    public let stationID: String
    public let displayName: String?
    public let progress: StationProgress
    public let stopMeasurement: StopMeasurement?
    public let arrivalDeviationSeconds: Double?
    public let departureDeviationSeconds: Double?
    public let doorOperations: [DoorOperationRecord]
    public let procedureRecords: [ProcedureRecord]
    public let componentScores: StationComponentScores
    public let cumulativeEarnedPointsThroughStation: Double
    public let cumulativePossiblePointsThroughStation: Double
    public let cumulativeAverageScoreThroughStation: Double
}

public enum JourneyGrade: String, Equatable, Sendable {
    case A
    case B
    case C
    case D
    case F
}

public struct JourneyEvaluation: Equatable, Sendable {
    public let stationEvaluations: [StationEvaluation]
    public let terminalStationID: String
    public let terminalReachedAndStopped: Bool
    public let isComplete: Bool
    /// Sum of station totals; maximum is 100 points per configured service stop.
    public let cumulativeEarnedPoints: Double
    public let cumulativePossiblePoints: Double
    /// Mean station score, normalized to 0...100 (zero when no stops are configured).
    public let averageScore: Double
    public let grade: JourneyGrade
}
