import Foundation

/// Tunable fictional game points. These values are not railway rules, safety
/// standards, or training scores. Unknown/missing fields never contribute points.
public struct DoorProcedureScoringPolicy: Codable, Equatable, Sendable {
    public let doorSidePoints: Double
    public let procedureStepPoints: Double

    public init(doorSidePoints: Double = 1, procedureStepPoints: Double = 1) throws {
        guard doorSidePoints.isFinite, doorSidePoints > 0,
              procedureStepPoints.isFinite, procedureStepPoints > 0 else {
            throw DoorProcedureScoringError.invalidConfiguration("Point values must be finite and greater than zero.")
        }
        self.doorSidePoints = doorSidePoints
        self.procedureStepPoints = procedureStepPoints
    }

    public static let fictionalDefault = try! DoorProcedureScoringPolicy()

    private enum CodingKeys: String, CodingKey {
        case doorSidePoints
        case procedureStepPoints
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            doorSidePoints: try container.decode(Double.self, forKey: .doorSidePoints),
            procedureStepPoints: try container.decode(Double.self, forKey: .procedureStepPoints)
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(doorSidePoints, forKey: .doorSidePoints)
        try container.encode(procedureStepPoints, forKey: .procedureStepPoints)
    }
}

/// Deterministic, single-thread-confined scorer for fictional PLACEHOLDER station data.
/// It is independent of StopScoring and does not issue or validate operating instructions.
public final class DoorProcedureScoringEngine {
    private final class StationState {
        let definition: StationScoringDefinition
        var doorEvents: [DoorSideAcknowledgementRecord] = []
        var procedureEvents: [ProcedureEventRecord] = []
        var finalizedAtSeconds: Double?

        init(definition: StationScoringDefinition) {
            self.definition = definition
        }
    }

    private let orderedStations: [StationState]
    private let stationByID: [String: StationState]
    private let policy: DoorProcedureScoringPolicy
    private var seenEventIDs: Set<String> = []
    private var lastAcceptedTimeSeconds: Double?
    private var isFinished = false

    /// Pass only the scenario's ordered service stops. The scorer never derives
    /// data from real stations, the route, door controls, or training policy.
    public init(
        stations: [StationScoringDefinition],
        policy: DoorProcedureScoringPolicy = .fictionalDefault
    ) throws {
        guard !stations.isEmpty else {
            throw DoorProcedureScoringError.invalidConfiguration("At least one station definition is required.")
        }
        let ids = stations.map(\.stationID)
        guard Set(ids).count == ids.count else {
            throw DoorProcedureScoringError.invalidConfiguration("Station IDs must be unique within a session.")
        }
        self.policy = policy
        let states = stations.map { StationState(definition: $0) }
        self.orderedStations = states
        self.stationByID = Dictionary(uniqueKeysWithValues: states.map { ($0.definition.stationID, $0) })
    }

    /// Records one explicit UI/gameplay event. Same-time events are allowed; time
    /// may not move backward. Replayed IDs are rejected, not silently double-counted.
    @discardableResult
    public func record(_ event: ScoringEvent) throws -> JourneyScoringEvaluation {
        guard !isFinished else { throw DoorProcedureScoringError.sessionFinished }
        guard let state = stationByID[event.stationID] else {
            throw DoorProcedureScoringError.unknownStation(event.stationID)
        }
        guard state.finalizedAtSeconds == nil else {
            throw DoorProcedureScoringError.stationAlreadyFinalized(event.stationID)
        }
        guard !seenEventIDs.contains(event.eventID) else {
            throw DoorProcedureScoringError.duplicateEventID(event.eventID)
        }
        if let lastAcceptedTimeSeconds, event.simulationTimeSeconds < lastAcceptedTimeSeconds {
            throw DoorProcedureScoringError.invalidTime("Event time cannot move backwards within a session.")
        }

        switch event.kind {
        case let .doorSideAcknowledged(side):
            state.doorEvents.append(DoorSideAcknowledgementRecord(
                eventID: event.eventID,
                atSeconds: event.simulationTimeSeconds,
                side: side
            ))
        case let .procedureStep(stepID, role, outcome):
            state.procedureEvents.append(ProcedureEventRecord(
                eventID: event.eventID,
                atSeconds: event.simulationTimeSeconds,
                stepID: stepID,
                role: role,
                outcome: outcome
            ))
        }

        seenEventIDs.insert(event.eventID)
        lastAcceptedTimeSeconds = event.simulationTimeSeconds
        return evaluation()
    }

    /// Closes one station's scoring window. Known requirements without a successful
    /// matching event become unearned; unknown or missing requirements remain unscored.
    @discardableResult
    public func finalizeStation(stationID: String, at simulationTimeSeconds: Double) throws -> JourneyScoringEvaluation {
        guard !isFinished else { throw DoorProcedureScoringError.sessionFinished }
        guard let state = stationByID[stationID] else {
            throw DoorProcedureScoringError.unknownStation(stationID)
        }
        guard state.finalizedAtSeconds == nil else {
            throw DoorProcedureScoringError.stationAlreadyFinalized(stationID)
        }
        guard simulationTimeSeconds.isFinite, simulationTimeSeconds >= 0 else {
            throw DoorProcedureScoringError.invalidTime("Finalization time must be finite and non-negative.")
        }
        if let lastAcceptedTimeSeconds, simulationTimeSeconds < lastAcceptedTimeSeconds {
            throw DoorProcedureScoringError.invalidTime("Finalization time cannot precede the latest accepted event.")
        }
        state.finalizedAtSeconds = simulationTimeSeconds
        lastAcceptedTimeSeconds = simulationTimeSeconds
        return evaluation()
    }

    /// Freeze the session. Unfinalized stations remain unscored rather than being
    /// treated as visited or as missed requirements. Repeated calls are safe.
    @discardableResult
    public func finish() -> JourneyScoringEvaluation {
        isFinished = true
        return evaluation()
    }

    /// Captures all state needed to resume this engine with identical scoring semantics.
    public func snapshot() -> DoorProcedureScoringEngineSnapshot {
        DoorProcedureScoringEngineSnapshot(
            scoringPolicy: policy,
            stationDefinitions: orderedStations.map(\.definition),
            stationStates: orderedStations.map { state in
                DoorProcedureStationStateSnapshot(
                    stationID: state.definition.stationID,
                    doorEvents: state.doorEvents,
                    procedureEvents: state.procedureEvents,
                    finalizedAtSeconds: state.finalizedAtSeconds
                )
            },
            seenEventIDs: seenEventIDs.sorted(),
            lastAcceptedTimeSeconds: lastAcceptedTimeSeconds,
            isFinished: isFinished
        )
    }

    /// Restores a snapshot only when its revision, ordered definitions, and policy
    /// match this engine. All validation completes before any state is mutated.
    public func restore(from snapshot: DoorProcedureScoringEngineSnapshot) throws {
        guard snapshot.revision == DoorProcedureScoringEngineSnapshot.currentRevision else {
            throw DoorProcedureScoringError.incompatibleSnapshot("Unsupported engine snapshot revision.")
        }
        let stationStatesMatch = zip(snapshot.stationStates, orderedStations)
            .allSatisfy { pair in pair.0.stationID == pair.1.definition.stationID }
        guard snapshot.stationDefinitions == orderedStations.map(\.definition),
              snapshot.stationStates.count == orderedStations.count,
              stationStatesMatch else {
            throw DoorProcedureScoringError.incompatibleSnapshot("Station definitions or their order do not match this engine.")
        }
        guard snapshot.scoringPolicy == policy else {
            throw DoorProcedureScoringError.incompatibleSnapshot("Scoring policy does not match this engine.")
        }

        var restoredEventIDs = Set<String>()
        var maximumAcceptedTime: Double?
        func validateTime(_ value: Double, field: String) throws {
            guard value.isFinite, value >= 0 else {
                throw DoorProcedureScoringError.invalidSnapshot("\(field) must be finite and non-negative.")
            }
            maximumAcceptedTime = max(maximumAcceptedTime ?? value, value)
        }
        func validateEventID(_ id: String) throws {
            guard !id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  id == id.trimmingCharacters(in: .whitespacesAndNewlines),
                  restoredEventIDs.insert(id).inserted else {
                throw DoorProcedureScoringError.invalidSnapshot("Event IDs must be unique, non-empty, and normalized.")
            }
        }

        for station in snapshot.stationStates {
            var previousDoorTime: Double?
            for event in station.doorEvents {
                try validateEventID(event.eventID)
                try validateTime(event.atSeconds, field: "Door event time")
                guard previousDoorTime.map({ event.atSeconds >= $0 }) ?? true else {
                    throw DoorProcedureScoringError.invalidSnapshot("Door events must be ordered by accepted time.")
                }
                previousDoorTime = event.atSeconds
            }
            var previousProcedureTime: Double?
            for event in station.procedureEvents {
                try validateEventID(event.eventID)
                try validateTime(event.atSeconds, field: "Procedure event time")
                guard !event.stepID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                      event.stepID == event.stepID.trimmingCharacters(in: .whitespacesAndNewlines),
                      previousProcedureTime.map({ event.atSeconds >= $0 }) ?? true else {
                    throw DoorProcedureScoringError.invalidSnapshot("Procedure event IDs or ordering are invalid.")
                }
                previousProcedureTime = event.atSeconds
            }
            if let finalizedAtSeconds = station.finalizedAtSeconds {
                try validateTime(finalizedAtSeconds, field: "Station finalization time")
                guard (previousDoorTime.map({ finalizedAtSeconds >= $0 }) ?? true),
                      (previousProcedureTime.map({ finalizedAtSeconds >= $0 }) ?? true) else {
                    throw DoorProcedureScoringError.invalidSnapshot("Station finalization cannot precede its events.")
                }
            }
        }

        let suppliedIDs = snapshot.seenEventIDs
        guard Set(suppliedIDs).count == suppliedIDs.count,
              suppliedIDs.allSatisfy({ !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0 == $0.trimmingCharacters(in: .whitespacesAndNewlines) }),
              Set(suppliedIDs) == restoredEventIDs else {
            throw DoorProcedureScoringError.invalidSnapshot("Seen event IDs must exactly match the unique recorded events.")
        }
        if let lastAcceptedTimeSeconds = snapshot.lastAcceptedTimeSeconds {
            guard lastAcceptedTimeSeconds.isFinite, lastAcceptedTimeSeconds >= 0,
                  maximumAcceptedTime == lastAcceptedTimeSeconds else {
                throw DoorProcedureScoringError.invalidSnapshot("Last accepted time must equal the latest recorded event or finalization time.")
            }
        } else if maximumAcceptedTime != nil {
            throw DoorProcedureScoringError.invalidSnapshot("Last accepted time is required when the snapshot contains accepted activity.")
        }

        // Commit only after every compatibility and integrity check above succeeds.
        for (state, saved) in zip(orderedStations, snapshot.stationStates) {
            state.doorEvents = saved.doorEvents
            state.procedureEvents = saved.procedureEvents
            state.finalizedAtSeconds = saved.finalizedAtSeconds
        }
        seenEventIDs = restoredEventIDs
        lastAcceptedTimeSeconds = snapshot.lastAcceptedTimeSeconds
        isFinished = snapshot.isFinished
    }

    public func evaluation() -> JourneyScoringEvaluation {
        let stationResults = orderedStations.map(score)
        let finalized = stationResults.filter(\.isFinalized)
        let earned = finalized.reduce(0) { $0 + $1.earnedPoints }
        let possible = finalized.reduce(0) { $0 + $1.possiblePoints }
        let percent = possible > 0 ? earned / possible * 100 : nil
        return JourneyScoringEvaluation(
            stationEvaluations: stationResults,
            finalizedStationCount: finalized.count,
            unfinalizedStationIDs: stationResults.filter { !$0.isFinalized }.map(\.stationID),
            isFinished: isFinished,
            earnedPoints: earned,
            possiblePoints: possible,
            scorePercent: percent
        )
    }

    private func score(_ state: StationState) -> StationScoringEvaluation {
        let doorAssessment = assessDoorSide(state)
        let procedureAssessment = assessProcedures(state)
        let doorAvailable: Bool
        switch state.definition.expectedDoorSide {
        case .known(_): doorAvailable = true
        case .unknown(_), .missing: doorAvailable = false
        }

        var earned = 0.0
        var possible = 0.0
        if doorAvailable {
            possible += policy.doorSidePoints
            if case .earned(_, _) = doorAssessment { earned += policy.doorSidePoints }
        }

        switch procedureAssessment {
        case .requirementsUnavailable(_):
            break
        case .knownNoRequirements:
            break
        case let .requirements(requirements):
            for requirement in requirements {
                possible += requirement.possiblePoints
                earned += requirement.earnedPoints
            }
        }

        let isFinalized = state.finalizedAtSeconds != nil
        let percent = isFinalized && possible > 0 ? earned / possible * 100 : nil
        let knownStepIDs: Set<String>
        if case let .known(requirements) = state.definition.procedureRequirements {
            knownStepIDs = Set(requirements.map(\.stepID))
        } else {
            knownStepIDs = []
        }
        let unmatchedIDs = state.procedureEvents
            .filter { !knownStepIDs.contains($0.stepID) }
            .map(\.eventID)

        return StationScoringEvaluation(
            stationID: state.definition.stationID,
            displayName: state.definition.displayName,
            isFinalized: isFinalized,
            finalizedAtSeconds: state.finalizedAtSeconds,
            doorSideAssessment: doorAssessment,
            procedureAssessment: procedureAssessment,
            doorSideEvents: state.doorEvents,
            procedureEvents: state.procedureEvents,
            unmatchedProcedureEventIDs: unmatchedIDs,
            earnedPoints: earned,
            possiblePoints: possible,
            scorePercent: percent
        )
    }

    private func assessDoorSide(_ state: StationState) -> DoorSideAssessment {
        let expected: DoorSide
        switch state.definition.expectedDoorSide {
        case let .known(value): expected = value
        case .missing:
            return .notEvaluable(.missing)
        case let .unknown(reason):
            return .notEvaluable(.unknown(reason))
        }

        guard let latest = state.doorEvents.last else {
            return state.finalizedAtSeconds == nil ? .pending(expected: expected) : .notPerformed(expected: expected)
        }
        return latest.side == expected
            ? .earned(expected: expected, observed: latest.side)
            : .incorrect(expected: expected, observed: latest.side)
    }

    private func assessProcedures(_ state: StationState) -> ProcedureSetAssessment {
        let requirements: [ProcedureRequirement]
        switch state.definition.procedureRequirements {
        case .missing:
            return .requirementsUnavailable(.missing)
        case let .unknown(reason):
            return .requirementsUnavailable(.unknown(reason))
        case let .known(values):
            requirements = values
        }
        guard !requirements.isEmpty else { return .knownNoRequirements }

        let assessments = requirements.map { requirement -> ProcedureRequirementAssessment in
            let matchingStep = state.procedureEvents.filter { $0.stepID == requirement.stepID }
            let expectedRoleEvents = matchingStep.filter { $0.role == requirement.role }
            let result: ProcedureStepResult
            var earnedPoints = 0.0
            if let latestExpectedRoleEvent = expectedRoleEvents.last {
                if latestExpectedRoleEvent.outcome == .completed {
                    result = .completed
                    earnedPoints = policy.procedureStepPoints
                } else {
                    result = .notCompleted(latestExpectedRoleEvent.outcome)
                }
            } else if !matchingStep.isEmpty {
                let observedRoles = Array(Set(matchingStep.map(\.role))).sorted { $0.rawValue < $1.rawValue }
                result = .wrongRole(observedRoles: observedRoles)
            } else {
                result = state.finalizedAtSeconds == nil ? .pending : .notPerformed
            }
            return ProcedureRequirementAssessment(
                stepID: requirement.stepID,
                expectedRole: requirement.role,
                title: requirement.title,
                result: result,
                earnedPoints: earnedPoints,
                possiblePoints: policy.procedureStepPoints
            )
        }
        return .requirements(assessments)
    }
}
