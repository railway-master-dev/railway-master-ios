import Foundation

/// A revisioned, Codable representation of a StopScoring session.
/// Obtain snapshots from `StopScoringEngine.makeSnapshot()` and restore them only into an
/// engine initialized with the same trusted station definitions and scoring configuration.
public struct StopScoringSnapshot: Codable, Equatable, Sendable {
    /// Current serialized format revision. Unsupported revisions are rejected on restore.
    public let revision: Int

    let compatibility: SnapshotCompatibility
    let lastTick: SnapshotTick?
    let seenEventIDs: [String]
    let isFinished: Bool
    let stations: [SnapshotStationState]

    init(compatibility: SnapshotCompatibility, lastTick: SnapshotTick?, seenEventIDs: [String],
         isFinished: Bool, stations: [SnapshotStationState]) {
        self.revision = Self.currentRevision
        self.compatibility = compatibility
        self.lastTick = lastTick
        self.seenEventIDs = seenEventIDs
        self.isFinished = isFinished
        self.stations = stations
    }

    static let currentRevision = 1
}

struct SnapshotCompatibility: Codable, Equatable, Sendable {
    let trainLengthMeters: Double
    let direction: String
    let policy: SnapshotPolicy
    let stations: [SnapshotStationDefinition]
}

struct SnapshotPolicy: Codable, Equatable, Sendable {
    let weights: [Double]
    let stopPrecisionToleranceMeters: Double
    let earlyLateGraceSeconds: Double
    let timetablePenaltyPointsPerMinute: Double
    let stoppedSpeedThresholdMetersPerSecond: Double
    let wrongDoorSidePenaltyPoints: Double
    let missingExpectedDoorOpenPenaltyPoints: Double
    let missingExpectedDoorClosePenaltyPoints: Double
    let doorSequenceViolationPenaltyPoints: Double
    let outOfOrderProcedurePenaltyPoints: Double
}

struct SnapshotStationDefinition: Codable, Equatable, Sendable {
    let stationID: String
    let displayName: String?
    let stationChainageMeters: Double
    let targetStopChainageMeters: Double
    let platformStartChainageMeters: Double
    let platformEndChainageMeters: Double
    let permittedWindowLowerMeters: Double
    let permittedWindowUpperMeters: Double
    let scheduledArrivalSeconds: Double?
    let scheduledDepartureSeconds: Double?
    let expectedDoorSide: String?
    let requiredProcedureSteps: [String]
}

struct SnapshotTick: Codable, Equatable, Sendable {
    let sequence: Int
    let simulationTimeSeconds: Double
    let leadingEndChainageMeters: Double
    let speedMetersPerSecond: Double
}

struct SnapshotMeasurement: Codable, Equatable, Sendable {
    let targetChainageMeters: Double
    let actualChainageMeters: Double
    let signedErrorMeters: Double
    let absoluteErrorMeters: Double
    let absoluteErrorCentimeters: Double
    let insidePermittedWindow: Bool
    let trainFitsPlatform: Bool
}

struct SnapshotDoorRecord: Codable, Equatable, Sendable {
    let eventID: String
    let atSeconds: Double
    let side: String
    let action: String
}

struct SnapshotProcedureRecord: Codable, Equatable, Sendable {
    let eventID: String
    let atSeconds: Double
    let stepID: String
    let outcome: String
}

struct SnapshotStationState: Codable, Equatable, Sendable {
    let stationID: String
    let arrivalSeconds: Double?
    let departureSeconds: Double?
    let stopMeasurement: SnapshotMeasurement?
    let doorOperations: [SnapshotDoorRecord]
    let procedureRecords: [SnapshotProcedureRecord]
    let openDoorSides: [String]
    let doorSequenceViolations: Int
    let procedureOrderViolations: Int
    let highestSuccessfulProcedureIndex: Int?
    let successfulRequiredProcedureIndices: [Int]
    let lastEventSeconds: Double?
}
