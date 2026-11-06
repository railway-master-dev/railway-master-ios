import Foundation

/// Deterministic, single-thread-confined scorer for fictional railway-simulator game rules.
/// It has no dependency on app-specific station, timetable, vehicle, or route types.
public final class StopScoringEngine {
    private final class StationState {
        let definition: StationStopDefinition
        var arrivalSeconds: Double?
        var departureSeconds: Double?
        var stopMeasurement: StopMeasurement?
        var doorOperations: [DoorOperationRecord] = []
        var procedureRecords: [ProcedureRecord] = []
        var openDoorSides: Set<DoorSide> = []
        var doorSequenceViolations = 0
        var procedureOrderViolations = 0
        var highestSuccessfulProcedureIndex: Int?
        var successfulRequiredProcedureIndices: Set<Int> = []
        var lastEventSeconds: Double?

        init(definition: StationStopDefinition) {
            self.definition = definition
        }
    }

    private let trainLengthMeters: Double
    private let direction: TravelDirection
    private let policy: GameScoringPolicy
    private let orderedStations: [StationState]
    private var stationByID: [String: StationState]
    private var seenEventIDs: Set<String> = []
    private var lastTick: SimulationTick?
    private var isFinished = false

    /// - Parameters:
    ///   - trainLengthMeters: Full consist length, used to ensure the whole train fits the platform.
    ///   - direction: Direction along the caller-provided chainage axis.
    ///   - stations: Stops for this scenario/service, in route order; pass only stations the service is expected to stop at.
    ///   - policy: Tunable fictional game scoring rules. Defaults are not real-world operating standards.
    public init(
        trainLengthMeters: Double,
        direction: TravelDirection,
        stations: [StationStopDefinition],
        policy: GameScoringPolicy = GameScoringPolicy()
    ) throws {
        try policy.validate()
        guard trainLengthMeters.isFinite, trainLengthMeters > 0 else {
            throw StopScoringError.invalidConfiguration("Train length must be finite and greater than zero metres.")
        }
        guard !stations.isEmpty else {
            throw StopScoringError.invalidConfiguration("At least one service stop is required.")
        }
        guard Set(stations.map(\.stationID)).count == stations.count else {
            throw StopScoringError.invalidConfiguration("Station IDs must be unique within a session.")
        }
        for station in stations {
            let platformLength = station.platformEndChainageMeters - station.platformStartChainageMeters
            guard trainLengthMeters <= platformLength else {
                throw StopScoringError.invalidConfiguration("Train is longer than the platform at station \(station.stationID).")
            }
            let physicallySafeWindow: (lower: Double, upper: Double)
            switch direction {
            case .increasingChainage:
                physicallySafeWindow = (station.platformStartChainageMeters + trainLengthMeters,
                                        station.platformEndChainageMeters)
            case .decreasingChainage:
                physicallySafeWindow = (station.platformStartChainageMeters,
                                        station.platformEndChainageMeters - trainLengthMeters)
            }
            guard physicallySafeWindow.lower <= physicallySafeWindow.upper,
                  station.permittedStopWindow.lowerBoundMeters >= physicallySafeWindow.lower,
                  station.permittedStopWindow.upperBoundMeters <= physicallySafeWindow.upper else {
                throw StopScoringError.invalidConfiguration("Permitted leading-end stop window does not keep the full train on the platform at station \(station.stationID).")
            }
        }

        self.trainLengthMeters = trainLengthMeters
        self.direction = direction
        self.policy = policy
        let states = stations.map { StationState(definition: $0) }
        self.orderedStations = states
        self.stationByID = Dictionary(uniqueKeysWithValues: states.map { ($0.definition.stationID, $0) })
    }

    /// Accept one increasing simulation tick and zero or more events observed at that tick.
    /// A batch is processed in array order and is not transactional: if an event throws,
    /// the tick and any earlier accepted events in that batch remain applied.
    @discardableResult
    public func process(tick: SimulationTick, events: [StationEvent] = []) throws -> JourneyEvaluation {
        guard !isFinished else { throw StopScoringError.sessionFinished }
        if let lastTick {
            guard tick.sequence > lastTick.sequence else {
                throw StopScoringError.invalidTick("Tick sequence must strictly increase.")
            }
            guard tick.simulationTimeSeconds >= lastTick.simulationTimeSeconds else {
                throw StopScoringError.invalidTick("Simulation time cannot move backwards.")
            }
        }
        lastTick = tick
        for event in events {
            try apply(event, at: tick)
        }
        return evaluation()
    }

    /// Current score snapshot; incomplete or unvisited stations are included with missing requirements scored as zero where applicable.
    public func evaluation() -> JourneyEvaluation {
        var cumulativeEarned = 0.0
        var evaluations: [StationEvaluation] = []
        evaluations.reserveCapacity(orderedStations.count)

        for state in orderedStations {
            let stationResult = score(state)
            cumulativeEarned += stationResult.total
            let count = Double(evaluations.count + 1)
            evaluations.append(StationEvaluation(
                stationID: state.definition.stationID,
                displayName: state.definition.displayName,
                progress: progress(for: state),
                stopMeasurement: state.stopMeasurement,
                arrivalDeviationSeconds: deviation(actual: state.arrivalSeconds,
                                                   scheduled: state.definition.schedule.scheduledArrivalSeconds),
                departureDeviationSeconds: deviation(actual: state.departureSeconds,
                                                     scheduled: state.definition.schedule.scheduledDepartureSeconds),
                doorOperations: state.doorOperations,
                procedureRecords: state.procedureRecords,
                componentScores: stationResult,
                cumulativeEarnedPointsThroughStation: cumulativeEarned,
                cumulativePossiblePointsThroughStation: count * 100,
                cumulativeAverageScoreThroughStation: cumulativeEarned / count
            ))
        }

        let terminal = orderedStations[orderedStations.count - 1]
        let terminalReached = terminal.arrivalSeconds != nil && terminal.stopMeasurement != nil
        let complete = orderedStations.enumerated().allSatisfy { entry in
            let (index, state) = entry
            let hasStopped = state.arrivalSeconds != nil && state.stopMeasurement != nil
            let hasRequiredDeparture = index == orderedStations.count - 1 || state.departureSeconds != nil
            return hasStopped && hasRequiredDeparture
        }
        let maxPoints = Double(orderedStations.count) * 100
        let average = cumulativeEarned / Double(orderedStations.count)
        return JourneyEvaluation(
            stationEvaluations: evaluations,
            terminalStationID: terminal.definition.stationID,
            terminalReachedAndStopped: terminalReached,
            isComplete: complete,
            cumulativeEarnedPoints: cumulativeEarned,
            cumulativePossiblePoints: maxPoints,
            averageScore: average,
            grade: grade(for: average)
        )
    }

    /// Freeze the session and return the final journey/terminal assessment. Calling it again is safe.
    @discardableResult
    public func finish() -> JourneyEvaluation {
        isFinished = true
        return evaluation()
    }

    /// Capture all dynamic state needed to continue this session after Codable encoding and decoding.
    public func makeSnapshot() -> StopScoringSnapshot {
        let states = orderedStations.map { state in
            SnapshotStationState(
                stationID: state.definition.stationID,
                arrivalSeconds: state.arrivalSeconds,
                departureSeconds: state.departureSeconds,
                stopMeasurement: state.stopMeasurement.map {
                    SnapshotMeasurement(targetChainageMeters: $0.targetChainageMeters,
                                        actualChainageMeters: $0.actualChainageMeters,
                                        signedErrorMeters: $0.signedErrorMeters,
                                        absoluteErrorMeters: $0.absoluteErrorMeters,
                                        absoluteErrorCentimeters: $0.absoluteErrorCentimeters,
                                        insidePermittedWindow: $0.insidePermittedWindow,
                                        trainFitsPlatform: $0.trainFitsPlatform)
                },
                doorOperations: state.doorOperations.map {
                    SnapshotDoorRecord(eventID: $0.eventID, atSeconds: $0.atSeconds,
                                       side: $0.side.rawValue, action: $0.action.rawValue)
                },
                procedureRecords: state.procedureRecords.map {
                    SnapshotProcedureRecord(eventID: $0.eventID, atSeconds: $0.atSeconds,
                                            stepID: $0.stepID, outcome: $0.outcome.rawValue)
                },
                openDoorSides: state.openDoorSides.map(\.rawValue).sorted(),
                doorSequenceViolations: state.doorSequenceViolations,
                procedureOrderViolations: state.procedureOrderViolations,
                highestSuccessfulProcedureIndex: state.highestSuccessfulProcedureIndex,
                successfulRequiredProcedureIndices: state.successfulRequiredProcedureIndices.sorted(),
                lastEventSeconds: state.lastEventSeconds
            )
        }
        return StopScoringSnapshot(compatibility: snapshotCompatibility,
                                   lastTick: lastTick.map {
                                       SnapshotTick(sequence: $0.sequence,
                                                    simulationTimeSeconds: $0.simulationTimeSeconds,
                                                    leadingEndChainageMeters: $0.leadingEndChainageMeters,
                                                    speedMetersPerSecond: $0.speedMetersPerSecond)
                                   },
                                   seenEventIDs: seenEventIDs.sorted(),
                                   isFinished: isFinished,
                                   stations: states)
    }

    /// Replace this engine's session state from a snapshot. No state is changed unless every
    /// revision, configuration, identifier, timestamp, measurement and index validates.
    public func restore(from snapshot: StopScoringSnapshot) throws {
        guard snapshot.revision == StopScoringSnapshot.currentRevision else {
            throw StopScoringError.invalidConfiguration("Unsupported StopScoring snapshot revision.")
        }
        guard snapshot.compatibility == snapshotCompatibility else {
            throw StopScoringError.invalidConfiguration("Snapshot configuration does not match this engine's trusted configuration.")
        }
        guard snapshot.stations.count == orderedStations.count,
              zip(snapshot.stations, orderedStations).allSatisfy({ pair in
                  pair.0.stationID == pair.1.definition.stationID
              }) else {
            throw StopScoringError.invalidConfiguration("Snapshot station order or IDs do not match this engine.")
        }

        let restoredTick: SimulationTick?
        if let tick = snapshot.lastTick {
            guard tick.sequence >= 0, tick.simulationTimeSeconds.isFinite,
                  tick.leadingEndChainageMeters.isFinite, tick.speedMetersPerSecond.isFinite,
                  tick.speedMetersPerSecond >= 0 else {
                throw StopScoringError.invalidTick("Snapshot contains an invalid last tick.")
            }
            restoredTick = try SimulationTick(sequence: tick.sequence,
                                              simulationTimeSeconds: tick.simulationTimeSeconds,
                                              leadingEndChainageMeters: tick.leadingEndChainageMeters,
                                              speedMetersPerSecond: tick.speedMetersPerSecond)
        } else {
            restoredTick = nil
        }

        let seenIDs = Set(snapshot.seenEventIDs)
        guard seenIDs.count == snapshot.seenEventIDs.count,
              snapshot.seenEventIDs.allSatisfy(isValidIdentifier) else {
            throw StopScoringError.invalidEvent("Snapshot contains duplicate or empty event IDs.")
        }
        let sessionTime = restoredTick?.simulationTimeSeconds
        var restoredStates: [StationState] = []
        restoredStates.reserveCapacity(orderedStations.count)
        var persistedEventCount = 0
        for (payload, trustedState) in zip(snapshot.stations, orderedStations) {
            let definition = trustedState.definition
            let state = StationState(definition: definition)
            state.arrivalSeconds = payload.arrivalSeconds
            state.departureSeconds = payload.departureSeconds
            state.lastEventSeconds = payload.lastEventSeconds
            state.doorSequenceViolations = payload.doorSequenceViolations
            state.procedureOrderViolations = payload.procedureOrderViolations
            state.highestSuccessfulProcedureIndex = payload.highestSuccessfulProcedureIndex

            func validTime(_ value: Double?) -> Bool {
                guard let value else { return true }
                return value.isFinite && (sessionTime.map { value <= $0 } ?? false)
            }
            guard validTime(payload.arrivalSeconds), validTime(payload.departureSeconds),
                  validTime(payload.lastEventSeconds), payload.doorSequenceViolations >= 0,
                  payload.procedureOrderViolations >= 0 else {
                throw StopScoringError.invalidEvent("Snapshot contains invalid times or violation counts.")
            }
            if payload.arrivalSeconds != nil && restoredTick == nil {
                throw StopScoringError.invalidEvent("Snapshot has station events but no last tick.")
            }
            if let departure = payload.departureSeconds {
                guard let arrival = payload.arrivalSeconds, departure >= arrival else {
                    throw StopScoringError.invalidEvent("Snapshot departure requires an earlier or simultaneous arrival.")
                }
            }
            if let measurement = payload.stopMeasurement {
                guard payload.arrivalSeconds != nil, payload.departureSeconds == nil,
                      [measurement.targetChainageMeters, measurement.actualChainageMeters,
                       measurement.signedErrorMeters, measurement.absoluteErrorMeters,
                       measurement.absoluteErrorCentimeters].allSatisfy(\.isFinite),
                      measurement.targetChainageMeters == definition.targetStopChainageMeters,
                      measurement.signedErrorMeters == measurement.actualChainageMeters - measurement.targetChainageMeters,
                      measurement.absoluteErrorMeters == abs(measurement.signedErrorMeters),
                      measurement.absoluteErrorCentimeters == measurement.absoluteErrorMeters * 100,
                      measurement.insidePermittedWindow == definition.permittedStopWindow.contains(measurement.actualChainageMeters),
                      measurement.trainFitsPlatform == trainFitsPlatform(leadingEndChainageMeters: measurement.actualChainageMeters,
                                                                         station: definition) else {
                    throw StopScoringError.invalidEvent("Snapshot contains an invalid stop measurement.")
                }
                state.stopMeasurement = StopMeasurement(targetChainageMeters: measurement.targetChainageMeters,
                                                        actualChainageMeters: measurement.actualChainageMeters,
                                                        signedErrorMeters: measurement.signedErrorMeters,
                                                        absoluteErrorMeters: measurement.absoluteErrorMeters,
                                                        absoluteErrorCentimeters: measurement.absoluteErrorCentimeters,
                                                        insidePermittedWindow: measurement.insidePermittedWindow,
                                                        trainFitsPlatform: measurement.trainFitsPlatform)
            }

            guard payload.openDoorSides.allSatisfy({ DoorSide(rawValue: $0) != nil }),
                  Set(payload.openDoorSides).count == payload.openDoorSides.count else {
                throw StopScoringError.invalidEvent("Snapshot contains invalid open door sides.")
            }
            var replayOpenSides: Set<DoorSide> = []
            var replayDoorViolations = 0
            var stationRecordIDs: [String] = []
            var previousRecordTime: Double?
            for record in payload.doorOperations {
                guard isValidIdentifier(record.eventID), seenIDs.contains(record.eventID),
                      validTime(record.atSeconds), let side = DoorSide(rawValue: record.side),
                      let action = DoorAction(rawValue: record.action),
                      payload.arrivalSeconds.map({ record.atSeconds >= $0 }) == true,
                      payload.departureSeconds.map({ record.atSeconds <= $0 }) ?? true,
                      previousRecordTime.map({ record.atSeconds >= $0 }) ?? true else {
                    throw StopScoringError.invalidEvent("Snapshot contains an invalid door record.")
                }
                previousRecordTime = record.atSeconds
                stationRecordIDs.append(record.eventID)
                state.doorOperations.append(DoorOperationRecord(eventID: record.eventID,
                                                                 atSeconds: record.atSeconds,
                                                                 side: side, action: action))
                switch action {
                case .open:
                    if replayOpenSides.contains(side) { replayDoorViolations += 1 }
                    replayOpenSides.insert(side)
                case .close:
                    if !replayOpenSides.contains(side) { replayDoorViolations += 1 }
                    replayOpenSides.remove(side)
                }
            }
            if payload.departureSeconds != nil { replayDoorViolations += replayOpenSides.count }
            guard replayDoorViolations == payload.doorSequenceViolations,
                  replayOpenSides.map(\.rawValue).sorted() == payload.openDoorSides.sorted() else {
                throw StopScoringError.invalidEvent("Snapshot door state does not match its ordered records.")
            }
            state.openDoorSides = Set(replayOpenSides)

            var replaySuccessfulIndices: Set<Int> = []
            var replayHighestIndex: Int?
            var replayProcedureViolations = 0
            previousRecordTime = nil
            for record in payload.procedureRecords {
                guard isValidIdentifier(record.eventID), seenIDs.contains(record.eventID),
                      isValidIdentifier(record.stepID), validTime(record.atSeconds),
                      let outcome = ProcedureOutcome(rawValue: record.outcome),
                      payload.arrivalSeconds.map({ record.atSeconds >= $0 }) == true,
                      payload.departureSeconds.map({ record.atSeconds <= $0 }) ?? true,
                      previousRecordTime.map({ record.atSeconds >= $0 }) ?? true else {
                    throw StopScoringError.invalidEvent("Snapshot contains an invalid procedure record.")
                }
                previousRecordTime = record.atSeconds
                stationRecordIDs.append(record.eventID)
                state.procedureRecords.append(ProcedureRecord(eventID: record.eventID,
                                                               atSeconds: record.atSeconds,
                                                               stepID: record.stepID, outcome: outcome))
                if outcome == .completed, let index = definition.requiredProcedureSteps.firstIndex(of: record.stepID) {
                    if let highest = replayHighestIndex, index < highest { replayProcedureViolations += 1 }
                    replayHighestIndex = max(replayHighestIndex ?? index, index)
                    replaySuccessfulIndices.insert(index)
                }
            }
            guard Set(stationRecordIDs).count == stationRecordIDs.count,
                  replayProcedureViolations == payload.procedureOrderViolations,
                  replayHighestIndex == payload.highestSuccessfulProcedureIndex,
                  replaySuccessfulIndices == Set(payload.successfulRequiredProcedureIndices),
                  payload.successfulRequiredProcedureIndices.allSatisfy({ definition.requiredProcedureSteps.indices.contains($0) }),
                  Set(payload.successfulRequiredProcedureIndices).count == payload.successfulRequiredProcedureIndices.count else {
                throw StopScoringError.invalidEvent("Snapshot procedure indexes or records are inconsistent.")
            }
            state.successfulRequiredProcedureIndices = replaySuccessfulIndices
            let knownTimes = [payload.arrivalSeconds, payload.departureSeconds,
                              payload.doorOperations.map(\.atSeconds).max(),
                              payload.procedureRecords.map(\.atSeconds).max()].compactMap { $0 }
            persistedEventCount += (payload.arrivalSeconds == nil ? 0 : 1)
            persistedEventCount += (payload.stopMeasurement == nil ? 0 : 1)
            persistedEventCount += (payload.departureSeconds == nil ? 0 : 1)
            persistedEventCount += payload.doorOperations.count + payload.procedureRecords.count
            if let lastEvent = payload.lastEventSeconds {
                guard knownTimes.allSatisfy({ $0 <= lastEvent }) else {
                    throw StopScoringError.invalidEvent("Snapshot last-event time precedes a station record.")
                }
                guard !knownTimes.isEmpty || payload.stopMeasurement != nil else {
                    throw StopScoringError.invalidEvent("Snapshot has a last-event time for an unvisited station.")
                }
                if payload.stopMeasurement == nil {
                    guard knownTimes.max() == lastEvent else {
                        throw StopScoringError.invalidEvent("Snapshot last-event time does not match its persisted events.")
                    }
                }
            } else if !knownTimes.isEmpty || payload.stopMeasurement != nil {
                throw StopScoringError.invalidEvent("Snapshot omits the last-event time for a visited station.")
            }
            restoredStates.append(state)
        }
        guard persistedEventCount == seenIDs.count else {
            throw StopScoringError.invalidEvent("Snapshot seen-event IDs do not match persisted station events.")
        }
        let allRecordIDs = restoredStates.flatMap { $0.doorOperations.map(\.eventID) + $0.procedureRecords.map(\.eventID) }
        guard Set(allRecordIDs).count == allRecordIDs.count else {
            throw StopScoringError.invalidEvent("Snapshot reuses an event ID across station records.")
        }

        // Commit only after the complete snapshot has passed validation.
        for (target, restored) in zip(orderedStations, restoredStates) {
            target.arrivalSeconds = restored.arrivalSeconds
            target.departureSeconds = restored.departureSeconds
            target.stopMeasurement = restored.stopMeasurement
            target.doorOperations = restored.doorOperations
            target.procedureRecords = restored.procedureRecords
            target.openDoorSides = restored.openDoorSides
            target.doorSequenceViolations = restored.doorSequenceViolations
            target.procedureOrderViolations = restored.procedureOrderViolations
            target.highestSuccessfulProcedureIndex = restored.highestSuccessfulProcedureIndex
            target.successfulRequiredProcedureIndices = restored.successfulRequiredProcedureIndices
            target.lastEventSeconds = restored.lastEventSeconds
        }
        stationByID = Dictionary(uniqueKeysWithValues: orderedStations.map { ($0.definition.stationID, $0) })
        seenEventIDs = seenIDs
        lastTick = restoredTick
        isFinished = snapshot.isFinished
    }

    private var snapshotCompatibility: SnapshotCompatibility {
        SnapshotCompatibility(
            trainLengthMeters: trainLengthMeters,
            direction: direction.rawValue,
            policy: SnapshotPolicy(weights: [policy.weights.stop, policy.weights.timetable,
                                             policy.weights.doors, policy.weights.procedures],
                                   stopPrecisionToleranceMeters: policy.stopPrecisionToleranceMeters,
                                   earlyLateGraceSeconds: policy.earlyLateGraceSeconds,
                                   timetablePenaltyPointsPerMinute: policy.timetablePenaltyPointsPerMinute,
                                   stoppedSpeedThresholdMetersPerSecond: policy.stoppedSpeedThresholdMetersPerSecond,
                                   wrongDoorSidePenaltyPoints: policy.wrongDoorSidePenaltyPoints,
                                   missingExpectedDoorOpenPenaltyPoints: policy.missingExpectedDoorOpenPenaltyPoints,
                                   missingExpectedDoorClosePenaltyPoints: policy.missingExpectedDoorClosePenaltyPoints,
                                   doorSequenceViolationPenaltyPoints: policy.doorSequenceViolationPenaltyPoints,
                                   outOfOrderProcedurePenaltyPoints: policy.outOfOrderProcedurePenaltyPoints),
            stations: orderedStations.map { state in
                let station = state.definition
                return SnapshotStationDefinition(stationID: station.stationID, displayName: station.displayName,
                                                 stationChainageMeters: station.stationChainageMeters,
                                                 targetStopChainageMeters: station.targetStopChainageMeters,
                                                 platformStartChainageMeters: station.platformStartChainageMeters,
                                                 platformEndChainageMeters: station.platformEndChainageMeters,
                                                 permittedWindowLowerMeters: station.permittedStopWindow.lowerBoundMeters,
                                                 permittedWindowUpperMeters: station.permittedStopWindow.upperBoundMeters,
                                                 scheduledArrivalSeconds: station.schedule.scheduledArrivalSeconds,
                                                 scheduledDepartureSeconds: station.schedule.scheduledDepartureSeconds,
                                                 expectedDoorSide: station.expectedDoorSide?.rawValue,
                                                 requiredProcedureSteps: station.requiredProcedureSteps)
            }
        )
    }

    private func isValidIdentifier(_ value: String) -> Bool {
        !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func apply(_ event: StationEvent, at tick: SimulationTick) throws {
        guard !seenEventIDs.contains(event.eventID) else {
            throw StopScoringError.duplicateEventID(event.eventID)
        }
        guard let state = stationByID[event.stationID] else {
            throw StopScoringError.unknownStation(event.stationID)
        }
        if let lastSeconds = state.lastEventSeconds, tick.simulationTimeSeconds < lastSeconds {
            throw StopScoringError.invalidEvent("Events for a station must be chronological.")
        }
        let definition = state.definition

        switch event.kind {
        case .arrival:
            guard state.arrivalSeconds == nil, state.departureSeconds == nil else {
                throw StopScoringError.invalidEvent("Station may have only one arrival, before departure.")
            }
            state.arrivalSeconds = tick.simulationTimeSeconds

        case .stopCompleted:
            guard state.arrivalSeconds != nil, state.departureSeconds == nil,
                  state.stopMeasurement == nil else {
                throw StopScoringError.invalidEvent("A completed stop requires an arrival and may be recorded only once before departure.")
            }
            guard tick.speedMetersPerSecond <= policy.stoppedSpeedThresholdMetersPerSecond else {
                throw StopScoringError.invalidEvent("Stop-completed event exceeds the configured game stop-speed threshold.")
            }
            let error = tick.leadingEndChainageMeters - definition.targetStopChainageMeters
            let fits = trainFitsPlatform(leadingEndChainageMeters: tick.leadingEndChainageMeters,
                                         station: definition)
            state.stopMeasurement = StopMeasurement(
                targetChainageMeters: definition.targetStopChainageMeters,
                actualChainageMeters: tick.leadingEndChainageMeters,
                signedErrorMeters: error,
                absoluteErrorMeters: abs(error),
                absoluteErrorCentimeters: abs(error) * 100,
                insidePermittedWindow: definition.permittedStopWindow.contains(tick.leadingEndChainageMeters),
                trainFitsPlatform: fits
            )

        case let .doorOperation(side, action):
            guard state.arrivalSeconds != nil, state.departureSeconds == nil else {
                throw StopScoringError.invalidEvent("Door operations are accepted only after arrival and before departure.")
            }
            state.doorOperations.append(DoorOperationRecord(eventID: event.eventID,
                                                            atSeconds: tick.simulationTimeSeconds,
                                                            side: side,
                                                            action: action))
            switch action {
            case .open:
                if state.openDoorSides.contains(side) { state.doorSequenceViolations += 1 }
                state.openDoorSides.insert(side)
            case .close:
                if !state.openDoorSides.contains(side) { state.doorSequenceViolations += 1 }
                state.openDoorSides.remove(side)
            }

        case let .procedureStep(stepID, outcome):
            guard state.arrivalSeconds != nil, state.departureSeconds == nil else {
                throw StopScoringError.invalidEvent("Procedure steps are accepted only after arrival and before departure.")
            }
            state.procedureRecords.append(ProcedureRecord(eventID: event.eventID,
                                                          atSeconds: tick.simulationTimeSeconds,
                                                          stepID: stepID,
                                                          outcome: outcome))
            if outcome == .completed,
               let stepIndex = definition.requiredProcedureSteps.firstIndex(of: stepID) {
                if let highest = state.highestSuccessfulProcedureIndex, stepIndex < highest {
                    state.procedureOrderViolations += 1
                }
                state.highestSuccessfulProcedureIndex = max(state.highestSuccessfulProcedureIndex ?? stepIndex, stepIndex)
                state.successfulRequiredProcedureIndices.insert(stepIndex)
            }

        case .departure:
            guard state.arrivalSeconds != nil, state.departureSeconds == nil else {
                throw StopScoringError.invalidEvent("Departure requires a prior arrival and may be recorded only once.")
            }
            state.departureSeconds = tick.simulationTimeSeconds
            state.doorSequenceViolations += state.openDoorSides.count
        }

        state.lastEventSeconds = tick.simulationTimeSeconds
        seenEventIDs.insert(event.eventID)
    }

    private func trainFitsPlatform(leadingEndChainageMeters: Double, station: StationStopDefinition) -> Bool {
        let safeLower: Double
        let safeUpper: Double
        switch direction {
        case .increasingChainage:
            safeLower = station.platformStartChainageMeters + trainLengthMeters
            safeUpper = station.platformEndChainageMeters
        case .decreasingChainage:
            safeLower = station.platformStartChainageMeters
            safeUpper = station.platformEndChainageMeters - trainLengthMeters
        }
        return leadingEndChainageMeters >= safeLower && leadingEndChainageMeters <= safeUpper
    }

    private func score(_ state: StationState) -> StationComponentScores {
        let stopScore = scoreStop(state)
        let timetableScore = scoreTimetable(state)
        let doorScore = scoreDoors(state)
        let procedureScore = scoreProcedures(state)
        let weights = policy.weights
        let total = (stopScore * weights.stop + timetableScore * weights.timetable +
                     doorScore * weights.doors + procedureScore * weights.procedures) / 100
        return StationComponentScores(stop: stopScore,
                                      timetable: timetableScore,
                                      doors: doorScore,
                                      procedures: procedureScore,
                                      total: clamp(total))
    }

    private func scoreStop(_ state: StationState) -> Double {
        guard let measurement = state.stopMeasurement,
              measurement.insidePermittedWindow,
              measurement.trainFitsPlatform else { return 0 }
        if measurement.absoluteErrorMeters <= policy.stopPrecisionToleranceMeters { return 100 }
        let window = state.definition.permittedStopWindow
        let maxAllowedDeviation = max(
            abs(state.definition.targetStopChainageMeters - window.lowerBoundMeters),
            abs(window.upperBoundMeters - state.definition.targetStopChainageMeters)
        )
        guard maxAllowedDeviation > 0 else { return 0 }
        return clamp(100 * (1 - measurement.absoluteErrorMeters / maxAllowedDeviation))
    }

    private func scoreTimetable(_ state: StationState) -> Double {
        let schedule = state.definition.schedule
        var checkpointScores: [Double] = []
        if let scheduled = schedule.scheduledArrivalSeconds {
            checkpointScores.append(timeCheckpointScore(actual: state.arrivalSeconds, scheduled: scheduled))
        }
        if let scheduled = schedule.scheduledDepartureSeconds {
            checkpointScores.append(timeCheckpointScore(actual: state.departureSeconds, scheduled: scheduled))
        }
        guard !checkpointScores.isEmpty else { return 100 }
        return checkpointScores.reduce(0, +) / Double(checkpointScores.count)
    }

    private func timeCheckpointScore(actual: Double?, scheduled: Double) -> Double {
        guard let actual else { return 0 }
        let excessSeconds = max(0, abs(actual - scheduled) - policy.earlyLateGraceSeconds)
        return clamp(100 - (excessSeconds / 60) * policy.timetablePenaltyPointsPerMinute)
    }

    private func scoreDoors(_ state: StationState) -> Double {
        guard let expectedSide = state.definition.expectedDoorSide else { return 100 }
        let wrongSideCount = state.doorOperations.filter { $0.side != expectedSide }.count
        let expectedSideWasOpened = state.doorOperations.contains { $0.side == expectedSide && $0.action == .open }
        var score = 100.0
        score -= Double(wrongSideCount) * policy.wrongDoorSidePenaltyPoints
        if !expectedSideWasOpened { score -= policy.missingExpectedDoorOpenPenaltyPoints }
        if expectedSideWasOpened && state.openDoorSides.contains(expectedSide) {
            score -= policy.missingExpectedDoorClosePenaltyPoints
        }
        score -= Double(state.doorSequenceViolations) * policy.doorSequenceViolationPenaltyPoints
        return clamp(score)
    }

    private func scoreProcedures(_ state: StationState) -> Double {
        let requiredCount = state.definition.requiredProcedureSteps.count
        guard requiredCount > 0 else { return 100 }
        let completion = 100 * Double(state.successfulRequiredProcedureIndices.count) / Double(requiredCount)
        return clamp(completion - Double(state.procedureOrderViolations) * policy.outOfOrderProcedurePenaltyPoints)
    }

    private func progress(for state: StationState) -> StationProgress {
        if state.departureSeconds != nil { return .departed }
        if state.stopMeasurement != nil { return .stopped }
        if state.arrivalSeconds != nil { return .arrived }
        return .notStarted
    }

    private func deviation(actual: Double?, scheduled: Double?) -> Double? {
        guard let actual, let scheduled else { return nil }
        return actual - scheduled
    }

    private func grade(for score: Double) -> JourneyGrade {
        if score >= 90 { return .A }
        if score >= 80 { return .B }
        if score >= 70 { return .C }
        if score >= 60 { return .D }
        return .F
    }

    private func clamp(_ value: Double) -> Double {
        min(100, max(0, value))
    }
}
