import Foundation

/// Reasons a supplied value is unknown. These values describe data quality only;
/// they are never converted to a guessed station side or procedure requirement.
public enum UnknownDataReason: String, Codable, CaseIterable, Equatable, Sendable {
    case sourceDoesNotSpecify
    case explicitlyUnknown
    case explicitNull
    case notCollected
    case unsupportedLegacyValue
}

/// Preserves the difference between a known value, an explicitly unknown value,
/// and a field absent from the source. Missing data is not inferred.
public enum FieldData<Value: Codable & Equatable & Sendable>: Codable, Equatable, Sendable {
    case known(Value)
    case unknown(UnknownDataReason)
    case missing

    private enum CodingKeys: String, CodingKey {
        case status
        case value
        case reason
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let status = try container.decode(String.self, forKey: .status)
        switch status {
        case "known":
            self = .known(try container.decode(Value.self, forKey: .value))
        case "unknown":
            self = .unknown(try container.decode(UnknownDataReason.self, forKey: .reason))
        case "missing":
            self = .missing
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .status,
                in: container,
                debugDescription: "FieldData status must be known, unknown, or missing."
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .known(value):
            try container.encode("known", forKey: .status)
            try container.encode(value, forKey: .value)
        case let .unknown(reason):
            try container.encode("unknown", forKey: .status)
            try container.encode(reason, forKey: .reason)
        case .missing:
            try container.encode("missing", forKey: .status)
        }
    }
}

public enum DataIssue: Equatable, Sendable {
    case missing
    case unknown(UnknownDataReason)
}

public enum DoorSide: String, Codable, CaseIterable, Equatable, Sendable {
    case left
    case right
    case both
    /// An explicit fictional game value meaning that no side is expected.
    case noDoorSide
}

/// Fictional gameplay roles. They are labels for scoring events, not job guidance.
public enum ScoringRole: String, Codable, CaseIterable, Equatable, Hashable, Sendable {
    case driver
    case conductor
    case stationStaff
}

/// A scenario-authored game checkpoint. IDs and titles must be fictional and must
/// not be presented as a real railway instruction or training procedure.
public struct ProcedureRequirement: Codable, Equatable, Sendable {
    public let stepID: String
    public let role: ScoringRole
    public let title: String?

    public init(stepID: String, role: ScoringRole, title: String? = nil) throws {
        let normalizedID = stepID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedID.isEmpty else {
            throw DoorProcedureScoringError.invalidConfiguration("Procedure step ID cannot be empty.")
        }
        if let title, title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw DoorProcedureScoringError.invalidConfiguration("Procedure title must be omitted or non-empty.")
        }
        self.stepID = normalizedID
        self.role = role
        self.title = title?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private enum CodingKeys: String, CodingKey {
        case stepID
        case role
        case title
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            stepID: try container.decode(String.self, forKey: .stepID),
            role: try container.decode(ScoringRole.self, forKey: .role),
            title: try container.decodeIfPresent(String.self, forKey: .title)
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(stepID, forKey: .stepID)
        try container.encode(role, forKey: .role)
        try container.encodeIfPresent(title, forKey: .title)
    }
}

/// Fictional per-station inputs. Omitted JSON fields decode as `.missing`;
/// explicit JSON null decodes as `.unknown(.explicitNull)`.
public struct StationScoringDefinition: Codable, Equatable, Sendable {
    public let stationID: String
    public let displayName: String?
    public let expectedDoorSide: FieldData<DoorSide>
    public let procedureRequirements: FieldData<[ProcedureRequirement]>

    public init(
        stationID: String,
        displayName: String? = nil,
        expectedDoorSide: FieldData<DoorSide> = .missing,
        procedureRequirements: FieldData<[ProcedureRequirement]> = .missing
    ) throws {
        let normalizedID = stationID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedID.isEmpty else {
            throw DoorProcedureScoringError.invalidConfiguration("Station ID cannot be empty.")
        }
        if let displayName, displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw DoorProcedureScoringError.invalidConfiguration("Display name must be omitted or non-empty.")
        }
        if case let .known(requirements) = procedureRequirements {
            let ids = requirements.map(\.stepID)
            guard Set(ids).count == ids.count else {
                throw DoorProcedureScoringError.invalidConfiguration("Known procedure step IDs must be unique within a station.")
            }
        }
        self.stationID = normalizedID
        self.displayName = displayName?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.expectedDoorSide = expectedDoorSide
        self.procedureRequirements = procedureRequirements
    }

    private enum CodingKeys: String, CodingKey {
        case stationID
        case displayName
        case expectedDoorSide
        case procedureRequirements
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let doorSide: FieldData<DoorSide>
        if !container.contains(.expectedDoorSide) {
            doorSide = .missing
        } else if try container.decodeNil(forKey: .expectedDoorSide) {
            doorSide = .unknown(.explicitNull)
        } else {
            doorSide = try container.decode(FieldData<DoorSide>.self, forKey: .expectedDoorSide)
        }

        let procedures: FieldData<[ProcedureRequirement]>
        if !container.contains(.procedureRequirements) {
            procedures = .missing
        } else if try container.decodeNil(forKey: .procedureRequirements) {
            procedures = .unknown(.explicitNull)
        } else {
            procedures = try container.decode(FieldData<[ProcedureRequirement]>.self, forKey: .procedureRequirements)
        }

        try self.init(
            stationID: try container.decode(String.self, forKey: .stationID),
            displayName: try container.decodeIfPresent(String.self, forKey: .displayName),
            expectedDoorSide: doorSide,
            procedureRequirements: procedures
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(stationID, forKey: .stationID)
        try container.encodeIfPresent(displayName, forKey: .displayName)
        try container.encode(expectedDoorSide, forKey: .expectedDoorSide)
        try container.encode(procedureRequirements, forKey: .procedureRequirements)
    }
}

/// Per-event outcome values are fictional game labels, not real-world assessments.
public enum ProcedureEventOutcome: String, Codable, Equatable, Sendable {
    case completed
    case skipped
    case incorrect
}

public enum ScoringEventKind: Equatable, Sendable {
    case doorSideAcknowledged(DoorSide)
    case procedureStep(stepID: String, role: ScoringRole, outcome: ProcedureEventOutcome)
}

/// Caller-supplied event ID is the deduplication key for the session.
public struct ScoringEvent: Equatable, Sendable {
    public let eventID: String
    public let stationID: String
    public let simulationTimeSeconds: Double
    public let kind: ScoringEventKind

    public init(eventID: String, stationID: String, simulationTimeSeconds: Double, kind: ScoringEventKind) throws {
        let normalizedEventID = eventID.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedStationID = stationID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedEventID.isEmpty, !normalizedStationID.isEmpty,
              simulationTimeSeconds.isFinite, simulationTimeSeconds >= 0 else {
            throw DoorProcedureScoringError.invalidEvent("Event and station IDs must be non-empty; simulation time must be finite and non-negative.")
        }
        if case let .procedureStep(stepID, _, _) = kind,
           stepID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw DoorProcedureScoringError.invalidEvent("Procedure event step ID cannot be empty.")
        }
        let normalizedKind: ScoringEventKind
        if case let .procedureStep(stepID, role, outcome) = kind {
            normalizedKind = .procedureStep(
                stepID: stepID.trimmingCharacters(in: .whitespacesAndNewlines),
                role: role,
                outcome: outcome
            )
        } else {
            normalizedKind = kind
        }
        self.eventID = normalizedEventID
        self.stationID = normalizedStationID
        self.simulationTimeSeconds = simulationTimeSeconds
        self.kind = normalizedKind
    }
}

public struct DoorSideAcknowledgementRecord: Codable, Equatable, Sendable {
    public let eventID: String
    public let atSeconds: Double
    public let side: DoorSide
}

public struct ProcedureEventRecord: Codable, Equatable, Sendable {
    public let eventID: String
    public let atSeconds: Double
    public let stepID: String
    public let role: ScoringRole
    public let outcome: ProcedureEventOutcome
}

/// State for one station in a serialized scoring-engine snapshot.
public struct DoorProcedureStationStateSnapshot: Codable, Equatable, Sendable {
    public let stationID: String
    public let doorEvents: [DoorSideAcknowledgementRecord]
    public let procedureEvents: [ProcedureEventRecord]
    public let finalizedAtSeconds: Double?

    public init(
        stationID: String,
        doorEvents: [DoorSideAcknowledgementRecord],
        procedureEvents: [ProcedureEventRecord],
        finalizedAtSeconds: Double?
    ) {
        self.stationID = stationID
        self.doorEvents = doorEvents
        self.procedureEvents = procedureEvents
        self.finalizedAtSeconds = finalizedAtSeconds
    }
}

/// Revisioned, Codable engine state. Definitions and their order are included
/// as an identity check; restoration still requires caller-supplied trusted definitions.
public struct DoorProcedureScoringEngineSnapshot: Codable, Equatable, Sendable {
    public static let currentRevision = 1

    public let revision: Int
    public let scoringPolicy: DoorProcedureScoringPolicy
    public let stationDefinitions: [StationScoringDefinition]
    public let stationStates: [DoorProcedureStationStateSnapshot]
    public let seenEventIDs: [String]
    public let lastAcceptedTimeSeconds: Double?
    public let isFinished: Bool

    public init(
        revision: Int = currentRevision,
        scoringPolicy: DoorProcedureScoringPolicy,
        stationDefinitions: [StationScoringDefinition],
        stationStates: [DoorProcedureStationStateSnapshot],
        seenEventIDs: [String],
        lastAcceptedTimeSeconds: Double?,
        isFinished: Bool
    ) {
        self.revision = revision
        self.scoringPolicy = scoringPolicy
        self.stationDefinitions = stationDefinitions
        self.stationStates = stationStates
        self.seenEventIDs = seenEventIDs
        self.lastAcceptedTimeSeconds = lastAcceptedTimeSeconds
        self.isFinished = isFinished
    }
}

public enum DoorSideAssessment: Equatable, Sendable {
    case pending(expected: DoorSide)
    case earned(expected: DoorSide, observed: DoorSide)
    case incorrect(expected: DoorSide, observed: DoorSide)
    case notPerformed(expected: DoorSide)
    case notEvaluable(DataIssue)
}

public enum ProcedureStepResult: Equatable, Sendable {
    case pending
    case completed
    case notPerformed
    case wrongRole(observedRoles: [ScoringRole])
    case notCompleted(ProcedureEventOutcome)
}

public struct ProcedureRequirementAssessment: Equatable, Sendable {
    public let stepID: String
    public let expectedRole: ScoringRole
    public let title: String?
    public let result: ProcedureStepResult
    public let earnedPoints: Double
    public let possiblePoints: Double
}

public enum ProcedureSetAssessment: Equatable, Sendable {
    case requirementsUnavailable(DataIssue)
    case knownNoRequirements
    case requirements([ProcedureRequirementAssessment])
}

public struct StationScoringEvaluation: Equatable, Sendable {
    public let stationID: String
    public let displayName: String?
    public let isFinalized: Bool
    public let finalizedAtSeconds: Double?
    public let doorSideAssessment: DoorSideAssessment
    public let procedureAssessment: ProcedureSetAssessment
    public let doorSideEvents: [DoorSideAcknowledgementRecord]
    public let procedureEvents: [ProcedureEventRecord]
    /// Event IDs for procedure step IDs not present in the station's known requirement list.
    /// These are retained for adapter diagnostics and never scored or inferred.
    public let unmatchedProcedureEventIDs: [String]
    public let earnedPoints: Double
    public let possiblePoints: Double
    /// Nil while in progress or when no known scoring denominator exists.
    public let scorePercent: Double?
}

public struct JourneyScoringEvaluation: Equatable, Sendable {
    public let stationEvaluations: [StationScoringEvaluation]
    public let finalizedStationCount: Int
    public let unfinalizedStationIDs: [String]
    public let isFinished: Bool
    public let earnedPoints: Double
    public let possiblePoints: Double
    /// Nil when there is no known, finalized scoring denominator.
    public let scorePercent: Double?
}

public enum DoorProcedureScoringError: Error, Equatable, Sendable {
    case invalidConfiguration(String)
    case invalidEvent(String)
    case unknownStation(String)
    case duplicateEventID(String)
    case stationAlreadyFinalized(String)
    case invalidTime(String)
    case sessionFinished
    case invalidSnapshot(String)
    case incompatibleSnapshot(String)
}
