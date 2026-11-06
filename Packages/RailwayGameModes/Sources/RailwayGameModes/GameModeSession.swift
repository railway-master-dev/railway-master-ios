import Foundation

public struct DriverModeProgress: Codable, Equatable, Sendable {
    public var departureConfirmed = false
    public var completedDutyStepIDs: [String] = []
    public var visitedStopIDs: [String] = []
    public var overspeedSamples = 0
    public var routeProgressM = 0.0
    public var maximumAbsoluteAccelerationMps2 = 0.0
    public var maximumJerkMps3 = 0.0
}

public struct TimetableModeProgress: Codable, Equatable, Sendable {
    public var observedStopIDs: [String] = []
    public var orderViolations = 0
    public var arrivalDelayByStop: [String: Double] = [:]
    public var departureDelayByStop: [String: Double] = [:]
    public var recoveryCreditCount = 1
    public var recoveryUsedForStopIDs: Set<String> = []
    public var routeProgressM = 0.0
}

public struct FreeModeProgress: Codable, Equatable, Sendable {
    public var goal: String?
    public var selectedRouteID: String
    public var selectedVehicleID: String?
    public var selectedWeatherID: String?
    public var selectedTimeOfDayID: String?
    public var selectedSeasonID: String?
    public var selectedPassengerLoadFactor: Double?
    public var requestedRouteID: String?
    public var requestedVehicleID: String?
    public var requestedWeatherID: String?
    public var requestedTimeOfDayID: String?
    public var requestedSeasonID: String?
    public var requestedPassengerLoadFactor: Double?
    public var waypointIDs: [String] = []
    public var elapsedSeconds = 0.0
    public var environmentRequestCount = 0
}

public struct ConductorModeProgress: Codable, Equatable, Sendable {
    public var doors: GameModeDoorState
    public var activeStationID: String?
    public var completedStopIDs: [String] = []
    public var closureConfirmedStopIDs: [String] = []
    public var playedAnnouncementIDs: [String] = []
    public var sequenceErrors = 0
}

public enum GameModeIncidentProgressState: String, Codable, Equatable, Sendable {
    case waiting
    case active
    case resolved
    case incorrect
    case missed
}

public struct DisruptionModeProgress: Codable, Equatable, Sendable {
    public var state: GameModeIncidentProgressState = .waiting
    public var eventID: String
    public var eventStartedAtSeconds: Double?
    public var response: GameModeIncidentChoice?
    public var hintCount = 0
}

public struct TrainingModeProgress: Codable, Equatable, Sendable {
    public var completedStepIDs: [String] = []
    public var hintCount = 0
    public var mistakes = 0
}

public struct FullLineModeProgress: Codable, Equatable, Sendable {
    public var routeProgressM = 0.0
    public var visitedStopIDs: [String] = []
    public var orderViolations = 0
}

public struct TourismModeProgress: Codable, Equatable, Sendable {
    public var observedLandmarkIDs: [String] = []
    public var routeProgressM = 0.0
    public var elapsedSeconds = 0.0
}

public struct CompanyOperationsModeProgress: Codable, Equatable, Sendable {
    public var assignmentsByTaskID: [String: String] = [:]
    public var conflictPairs: Set<String> = []
    public var overdueTaskIDs: Set<String> = []
}

/// Versioned package-owned continuation for a single reducer session.
public struct GameModeSessionStateSnapshot: Codable, Equatable, Sendable {
    public static let currentRevision = 1
    public var revision: Int
    public var mode: GameModeID
    public var playStyle: GameModePlayStyle
    public var status: GameModeSessionStatus
    public var progress: GameModeProgress
    public var failureReason: GameModeFailureReason?
    public var evaluation: GameModeEvaluation?
    public var lastSnapshot: GameModeSimulationSnapshot
    public var sessionStartTimeSeconds: Double
    public var hintCount: Int
}

public enum GameModeProgress: Codable, Equatable, Sendable {
    case driver(DriverModeProgress)
    case timetable(TimetableModeProgress)
    case free(FreeModeProgress)
    case conductor(ConductorModeProgress)
    case disruption(DisruptionModeProgress)
    case training(TrainingModeProgress)
    case fullLine(FullLineModeProgress)
    case tourism(TourismModeProgress)
    case companyOperations(CompanyOperationsModeProgress)
}

/// Deterministic reducer for one mode. It consumes host snapshots and emits game-only effects;
/// it never advances physics or changes the host simulation by itself.
public struct GameModeSession: Sendable {
    public let mode: GameModeID
    public let playStyle: GameModePlayStyle
    public let scenario: GameModeScenario
    public let definition: GameModeDefinition
    public private(set) var status: GameModeSessionStatus = .ready
    public private(set) var progress: GameModeProgress
    public private(set) var failureReason: GameModeFailureReason?
    public private(set) var evaluation: GameModeEvaluation?
    public private(set) var lastSnapshot: GameModeSimulationSnapshot
    public private(set) var pendingHostEffects: [GameModeHostEffect] = []
    public private(set) var hintCount = 0

    public private(set) var sessionStartTimeSeconds: Double

    public init(mode: GameModeID, snapshot: GameModeSimulationSnapshot, scenario: GameModeScenario) throws {
        if scenario.playStyle == .freeRun && mode != .free {
            throw GameModeError.invalidValue("freeRun play style requires free mode")
        }
        if scenario.playStyle == .disruptionTraining && mode != .disruption {
            throw GameModeError.invalidValue("disruptionTraining play style requires disruption mode")
        }
        guard snapshot.routeID == scenario.routeID else {
            throw GameModeError.routeMismatch(expected: scenario.routeID, received: snapshot.routeID)
        }
        guard abs(snapshot.routeLengthM - scenario.routeLengthM) <= 0.1 else {
            throw GameModeError.invalidValue("snapshot and scenario route length differ")
        }
        self.mode = mode
        self.playStyle = scenario.playStyle
        self.scenario = scenario
        self.definition = GameModeCatalog.definition(for: mode)
        self.lastSnapshot = snapshot
        self.sessionStartTimeSeconds = snapshot.simulationTimeSeconds
        switch mode {
        case .driver:
            self.progress = .driver(DriverModeProgress(routeProgressM: snapshot.positionM))
        case .timetable:
            self.progress = .timetable(TimetableModeProgress(routeProgressM: snapshot.positionM))
        case .free:
            self.progress = .free(FreeModeProgress(
                selectedRouteID: snapshot.routeID,
                selectedVehicleID: snapshot.vehicleID,
                selectedWeatherID: snapshot.weatherID,
                selectedTimeOfDayID: snapshot.timeOfDayID,
                selectedSeasonID: snapshot.seasonID,
                selectedPassengerLoadFactor: snapshot.passengerLoadFactor
            ))
        case .conductor:
            self.progress = .conductor(ConductorModeProgress(doors: snapshot.doors))
        case .disruption:
            self.progress = .disruption(DisruptionModeProgress(eventID: scenario.incident.id))
        case .training:
            self.progress = .training(TrainingModeProgress())
        case .fullLine:
            self.progress = .fullLine(FullLineModeProgress(routeProgressM: snapshot.positionM))
        case .tourism:
            self.progress = .tourism(TourismModeProgress(routeProgressM: snapshot.positionM))
        case .companyOperations:
            self.progress = .companyOperations(CompanyOperationsModeProgress())
        }
        if let reason = Self.blockingReason(for: mode, scenario: scenario, snapshot: snapshot) {
            self.status = .blocked
            let detail = reason == .mustStartAtRouteOrigin ? "全線モードは始発位置から開始してください。" : "必須PLACEHOLDER入力がありません。"
            self.evaluation = GameModeEvaluation(
                mode: mode,
                outcome: .blocked,
                scorePercent: nil,
                summary: "\(GameModeCatalog.definition(for: mode).title)モード判定不能: \(detail)失敗扱いではありません。",
                metrics: [:],
                blockingReason: reason
            )
        } else if mode == .companyOperations {
            updateCompanyOperations(with: snapshot)
        }
    }

    public init(mode: GameModeID, source: GameModeSimulationSource, scenario: GameModeScenario) throws {
        try self.init(mode: mode, snapshot: source.gameModeSnapshot, scenario: scenario)
    }

    /// Feed one coherent simulation sample. Repeated samples at the same simulation time are allowed.
    public func stateSnapshot() -> GameModeSessionStateSnapshot {
        GameModeSessionStateSnapshot(
            revision: GameModeSessionStateSnapshot.currentRevision,
            mode: mode,
            playStyle: playStyle,
            status: status,
            progress: progress,
            failureReason: failureReason,
            evaluation: evaluation,
            lastSnapshot: lastSnapshot,
            sessionStartTimeSeconds: sessionStartTimeSeconds,
            hintCount: hintCount
        )
    }

    /// Reconstitutes reducer progress only when it matches the trusted scenario and route.
    public mutating func restoreState(from saved: GameModeSessionStateSnapshot) throws {
        guard saved.revision == GameModeSessionStateSnapshot.currentRevision else {
            throw GameModeError.invalidValue("unsupported game-mode state revision")
        }
        guard saved.mode == mode, saved.playStyle == playStyle,
              saved.playStyle == scenario.playStyle,
              saved.lastSnapshot.routeID == scenario.routeID,
              abs(saved.lastSnapshot.routeLengthM - scenario.routeLengthM) <= 0.1 else {
            throw GameModeError.routeMismatch(expected: scenario.routeID, received: saved.lastSnapshot.routeID)
        }
        guard Self.progress(saved.progress, matches: mode), saved.hintCount >= 0,
              saved.hintCount <= 1_000_000,
              saved.sessionStartTimeSeconds.isFinite,
              saved.lastSnapshot.simulationTimeSeconds.isFinite,
              saved.sessionStartTimeSeconds >= 0,
              saved.sessionStartTimeSeconds <= saved.lastSnapshot.simulationTimeSeconds,
              saved.evaluation.map({ $0.mode == mode }) ?? true,
              saved.status != .failed || saved.failureReason != nil else {
            throw GameModeError.invalidValue("invalid game-mode continuation state")
        }
        status = saved.status
        progress = saved.progress
        failureReason = saved.failureReason
        evaluation = saved.evaluation
        lastSnapshot = saved.lastSnapshot
        sessionStartTimeSeconds = saved.sessionStartTimeSeconds
        hintCount = saved.hintCount
        pendingHostEffects.removeAll(keepingCapacity: true)
    }

    private static func progress(_ progress: GameModeProgress, matches mode: GameModeID) -> Bool {
        switch (mode, progress) {
        case (.driver, .driver(_)), (.timetable, .timetable(_)), (.free, .free(_)), (.conductor, .conductor(_)),
             (.disruption, .disruption(_)), (.training, .training(_)), (.fullLine, .fullLine(_)),
             (.tourism, .tourism(_)), (.companyOperations, .companyOperations(_)): true
        default: false
        }
    }

    public mutating func update(with snapshot: GameModeSimulationSnapshot) throws {
        guard !status.isTerminal else { throw GameModeError.sessionAlreadyEnded }
        guard snapshot.simulationTimeSeconds >= lastSnapshot.simulationTimeSeconds,
              snapshot.fixedTick >= lastSnapshot.fixedTick else {
            throw GameModeError.timeRegression
        }
        guard mode == .free || (snapshot.routeID == scenario.routeID && abs(snapshot.routeLengthM - scenario.routeLengthM) <= 0.1) else {
            fail(.routeMismatch)
            return
        }
        status = .active
        switch mode {
        case .driver:
            updateDriver(with: snapshot)
        case .timetable:
            updateTimetable(with: snapshot)
        case .free:
            updateFree(with: snapshot)
        case .conductor:
            updateConductor(with: snapshot)
        case .disruption:
            updateDisruption(with: snapshot)
        case .training:
            break
        case .fullLine:
            updateFullLine(with: snapshot)
        case .tourism:
            updateTourism(with: snapshot)
        case .companyOperations:
            updateCompanyOperations(with: snapshot)
        }
        lastSnapshot = snapshot
    }

    public mutating func update(from source: GameModeSimulationSource) throws {
        try update(with: source.gameModeSnapshot)
    }

    /// Apply a mode-specific user action against the most recently received simulation state.
    public mutating func apply(_ action: GameModeAction) throws {
        guard !status.isTerminal else { throw GameModeError.sessionAlreadyEnded }
        switch action {
        case .start:
            guard status == .ready else { throw GameModeError.actionUnavailable("session already started") }
            status = .active
        case .abandon:
            status = .abandoned
            evaluation = makeEvaluation(outcome: .abandoned)
        case .finish:
            try finish()
        default:
            guard status == .active else { throw GameModeError.actionUnavailable("start the mode before acting") }
            try applyModeAction(action)
        }
    }

    /// Host should consume these requests and feed the resulting values back in later snapshots.
    public mutating func drainHostEffects() -> [GameModeHostEffect] {
        defer { pendingHostEffects.removeAll() }
        return pendingHostEffects
    }

    private static func blockingReason(for mode: GameModeID, scenario: GameModeScenario, snapshot: GameModeSimulationSnapshot) -> GameModeBlockingReason? {
        switch mode {
        case .driver:
            if scenario.driverDutyStepIDs.isEmpty { return .missingDriverChecklist }
            return scenario.stops.contains(where: { $0.positionM > 0.1 }) ? nil : .missingStops
        case .timetable, .fullLine:
            if mode == .fullLine && snapshot.positionM > 0.1 { return .mustStartAtRouteOrigin }
            return scenario.stops.contains(where: { $0.positionM > 0.1 }) ? nil : .missingStops
        case .conductor:
            if snapshot.doors == .unknown { return .unknownInitialDoorState }
            if scenario.stops.contains(where: { $0.positionM > 0.1 && $0.stationNameAnnouncementID == nil }) {
                return .missingStationAnnouncements
            }
            return scenario.stops.contains(where: { $0.positionM > 0.1 }) ? nil : .missingStops
        case .training:
            return scenario.trainingSteps.isEmpty ? .missingTrainingSteps : nil
        case .tourism:
            return scenario.landmarks.isEmpty ? .missingLandmarks : nil
        case .companyOperations:
            if scenario.dispatchTasks.isEmpty || scenario.dispatchSlots.isEmpty { return .missingDispatchPlan }
            let presentTrainIDs = Set(snapshot.trains.filter { $0.routeID == scenario.routeID }.map(\.id))
            return scenario.dispatchTasks.allSatisfy({ presentTrainIDs.contains($0.trainID) }) ? nil : .missingTrainSnapshots
        case .free, .disruption:
            return nil
        }
    }

    private var requiredStopIDs: [String] {
        scenario.stops.filter { $0.positionM > 0.1 }.map(\.id)
    }

    private var requiredLandmarkCount: Int {
        min(2, max(1, scenario.landmarks.count))
    }

    private var elapsedSeconds: Double {
        max(0, lastSnapshot.simulationTimeSeconds - sessionStartTimeSeconds)
    }

    private mutating func updateDriver(with snapshot: GameModeSimulationSnapshot) {
        guard case .driver(var state) = progress else { return }
        state.routeProgressM = max(state.routeProgressM, snapshot.positionM)
        state.maximumAbsoluteAccelerationMps2 = max(state.maximumAbsoluteAccelerationMps2, abs(snapshot.accelerationMps2))
        let sampleInterval = snapshot.simulationTimeSeconds - lastSnapshot.simulationTimeSeconds
        if sampleInterval > 0 {
            let jerk = abs(snapshot.accelerationMps2 - lastSnapshot.accelerationMps2) / sampleInterval
            state.maximumJerkMps3 = max(state.maximumJerkMps3, jerk)
        }
        if snapshot.speedLimitKmh > 0, snapshot.speedMps * 3.6 > snapshot.speedLimitKmh + 1 {
            state.overspeedSamples += 1
            progress = .driver(state)
            fail(.overspeedObserved)
            return
        }
        if snapshot.doors.isOpen && snapshot.speedMps > 0.1 {
            progress = .driver(state)
            fail(.doorOpenWhileMoving)
            return
        }
        if let stationID = snapshot.atStationID, !state.visitedStopIDs.contains(stationID) {
            let expectedIndex = state.visitedStopIDs.count
            if expectedIndex < requiredStopIDs.count, requiredStopIDs[expectedIndex] == stationID {
                state.visitedStopIDs.append(stationID)
            } else if requiredStopIDs.contains(stationID) {
                state.visitedStopIDs.append(stationID)
                progress = .driver(state)
                fail(.stopOrderViolation)
                return
            }
        }
        progress = .driver(state)
    }

    private mutating func updateTimetable(with snapshot: GameModeSimulationSnapshot) {
        guard case .timetable(var state) = progress else { return }
        state.routeProgressM = max(state.routeProgressM, snapshot.positionM)
        if let stationID = snapshot.atStationID,
           let stop = scenario.stops.first(where: { $0.id == stationID }),
           stop.positionM > 0.1 {
            if snapshot.stationEvent == .arrival && !state.observedStopIDs.contains(stationID) {
                let expectedIndex = state.observedStopIDs.count
                if expectedIndex < requiredStopIDs.count && requiredStopIDs[expectedIndex] == stationID {
                    state.observedStopIDs.append(stationID)
                } else if requiredStopIDs.contains(stationID) {
                    state.orderViolations += 1
                    progress = .timetable(state)
                    fail(.stopOrderViolation)
                    return
                }
            }
            let elapsed = snapshot.simulationTimeSeconds - sessionStartTimeSeconds
            if snapshot.stationEvent == .departure, let plannedDeparture = stop.scheduledDepartureSeconds,
               state.departureDelayByStop[stationID] == nil {
                state.departureDelayByStop[stationID] = elapsed - plannedDeparture
            } else if snapshot.stationEvent == .arrival, state.arrivalDelayByStop[stationID] == nil {
                state.arrivalDelayByStop[stationID] = elapsed - stop.scheduledArrivalSeconds
            }
        }
        progress = .timetable(state)
    }

    private mutating func updateFree(with snapshot: GameModeSimulationSnapshot) {
        guard case .free(var state) = progress else { return }
        state.elapsedSeconds = max(state.elapsedSeconds, snapshot.simulationTimeSeconds - sessionStartTimeSeconds)
        state.selectedRouteID = snapshot.routeID
        state.selectedVehicleID = snapshot.vehicleID
        state.selectedWeatherID = snapshot.weatherID
        state.selectedTimeOfDayID = snapshot.timeOfDayID
        state.selectedSeasonID = snapshot.seasonID
        state.selectedPassengerLoadFactor = snapshot.passengerLoadFactor
        if state.requestedRouteID == snapshot.routeID { state.requestedRouteID = nil }
        if state.requestedVehicleID == snapshot.vehicleID { state.requestedVehicleID = nil }
        if state.requestedWeatherID == snapshot.weatherID { state.requestedWeatherID = nil }
        if state.requestedTimeOfDayID == snapshot.timeOfDayID { state.requestedTimeOfDayID = nil }
        if state.requestedSeasonID == snapshot.seasonID { state.requestedSeasonID = nil }
        if state.requestedPassengerLoadFactor == snapshot.passengerLoadFactor { state.requestedPassengerLoadFactor = nil }
        progress = .free(state)
    }

    private mutating func updateConductor(with snapshot: GameModeSimulationSnapshot) {
        guard case .conductor(var state) = progress else { return }
        if state.doors.isOpen && snapshot.speedMps > 0.1 {
            progress = .conductor(state)
            fail(.doorOpenWhileMoving)
            return
        }
        if let activeStationID = state.activeStationID,
           lastSnapshot.atStationID == activeStationID,
           snapshot.atStationID != activeStationID,
           !state.closureConfirmedStopIDs.contains(activeStationID) {
            state.sequenceErrors += 1
            progress = .conductor(state)
            fail(.conductorSequenceError)
            return
        }
        if snapshot.doors == .closed, !state.doors.isOpen {
            state.doors = .closed
        }
        progress = .conductor(state)
    }

    private mutating func updateDisruption(with snapshot: GameModeSimulationSnapshot) {
        guard case .disruption(var state) = progress else { return }
        let elapsed = snapshot.simulationTimeSeconds - sessionStartTimeSeconds
        if state.state == .waiting && elapsed >= scenario.incident.triggerAfterSeconds {
            state.state = .active
            state.eventStartedAtSeconds = sessionStartTimeSeconds + scenario.incident.triggerAfterSeconds
        }
        if state.state == .active,
           let start = state.eventStartedAtSeconds,
           snapshot.simulationTimeSeconds - start > scenario.incident.responseDeadlineSeconds {
            state.state = .missed
            progress = .disruption(state)
            fail(.incidentDeadlineExpired)
            return
        }
        progress = .disruption(state)
    }

    private mutating func updateFullLine(with snapshot: GameModeSimulationSnapshot) {
        guard case .fullLine(var state) = progress else { return }
        state.routeProgressM = max(state.routeProgressM, snapshot.positionM)
        if let stationID = snapshot.atStationID, !state.visitedStopIDs.contains(stationID), requiredStopIDs.contains(stationID) {
            let expectedIndex = state.visitedStopIDs.count
            if expectedIndex < requiredStopIDs.count, requiredStopIDs[expectedIndex] == stationID {
                state.visitedStopIDs.append(stationID)
            } else {
                state.orderViolations += 1
                progress = .fullLine(state)
                fail(.stopOrderViolation)
                return
            }
        }
        progress = .fullLine(state)
        if snapshot.positionM >= scenario.routeLengthM - 0.1, state.visitedStopIDs.count < requiredStopIDs.count {
            fail(.routeIncomplete)
        }
    }

    private mutating func updateTourism(with snapshot: GameModeSimulationSnapshot) {
        guard case .tourism(var state) = progress else { return }
        state.routeProgressM = max(state.routeProgressM, snapshot.positionM)
        state.elapsedSeconds = max(state.elapsedSeconds, snapshot.simulationTimeSeconds - sessionStartTimeSeconds)
        progress = .tourism(state)
        if snapshot.positionM >= scenario.routeLengthM - 0.1,
           state.observedLandmarkIDs.count < requiredLandmarkCount {
            fail(.insufficientLandmarks)
        }
    }

    private mutating func updateCompanyOperations(with snapshot: GameModeSimulationSnapshot) {
        guard case .companyOperations(var state) = progress else { return }
        let elapsed = snapshot.simulationTimeSeconds - sessionStartTimeSeconds
        for task in scenario.dispatchTasks where state.assignmentsByTaskID[task.id] == nil && elapsed > task.deadlineSeconds {
            state.overdueTaskIDs.insert(task.id)
        }
        let activeTrains = snapshot.trains.sorted { $0.id < $1.id }
        if activeTrains.count > 1 {
            for leftIndex in 0..<(activeTrains.count - 1) {
                for rightIndex in (leftIndex + 1)..<activeTrains.count {
                    let left = activeTrains[leftIndex]
                    let right = activeTrains[rightIndex]
                    if left.routeID == right.routeID,
                       left.trackID == right.trackID,
                       abs(left.positionM - right.positionM) < scenario.minimumTrainSeparationM {
                        state.conflictPairs.insert("\(left.id)|\(right.id)")
                    }
                }
            }
        }
        progress = .companyOperations(state)
        if !state.conflictPairs.isEmpty {
            fail(.dispatchConflict)
        } else if !state.overdueTaskIDs.isEmpty {
            fail(.dispatchDeadlineExpired)
        }
    }

    private mutating func applyModeAction(_ action: GameModeAction) throws {
        switch (mode, action) {
        case (.driver, .driverCompleteDutyStep(let stepID)):
            guard case .driver(var state) = progress else { return }
            let expected = scenario.driverDutyStepIDs.dropFirst(state.completedDutyStepIDs.count).first
            guard expected == stepID, stepID != scenario.driverDepartureCheckStepID else {
                progress = .driver(state)
                fail(.driverChecklistOrderViolation)
                return
            }
            state.completedDutyStepIDs.append(stepID)
            progress = .driver(state)

        case (.driver, .driverConfirmDeparture):
            guard case .driver(var state) = progress else { return }
            let expected = scenario.driverDutyStepIDs.dropFirst(state.completedDutyStepIDs.count).first
            guard expected == scenario.driverDepartureCheckStepID,
                  lastSnapshot.speedMps <= 0.1,
                  lastSnapshot.doors == .closed else {
                throw GameModeError.actionUnavailable("departure check must be next in the game checklist and use an explicitly stopped/closed state")
            }
            state.departureConfirmed = true
            state.completedDutyStepIDs.append(scenario.driverDepartureCheckStepID)
            progress = .driver(state)

        case (.timetable, .timetableUseRecoveryCredit(let stationID)):
            guard case .timetable(var state) = progress else { return }
            let delay = [state.arrivalDelayByStop[stationID], state.departureDelayByStop[stationID]]
                .compactMap { $0 }
                .max(by: { abs($0) < abs($1) })
            guard let delay else {
                throw GameModeError.actionUnavailable("no observed arrival/departure event for this stop")
            }
            guard state.recoveryCreditCount > 0,
                  let stop = scenario.stops.first(where: { $0.id == stationID }),
                  abs(delay) > stop.arrivalToleranceSeconds else {
                throw GameModeError.actionUnavailable("recovery credit is not applicable")
            }
            state.recoveryCreditCount -= 1
            state.recoveryUsedForStopIDs.insert(stationID)
            progress = .timetable(state)

        case (.free, .freeSetGoal(let goal)):
            guard !goal.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  case .free(var state) = progress else {
                throw GameModeError.invalidValue("free-mode goal must not be empty")
            }
            state.goal = goal
            progress = .free(state)

        case (.free, .freeRequestRoute(let routeID)):
            guard !routeID.isEmpty, case .free(var state) = progress else { throw GameModeError.invalidValue("route id") }
            state.requestedRouteID = routeID
            state.environmentRequestCount += 1
            progress = .free(state)
            pendingHostEffects.append(.requestRoute(routeID))

        case (.free, .freeRequestVehicle(let vehicleID)):
            guard !vehicleID.isEmpty, case .free(var state) = progress else { throw GameModeError.invalidValue("vehicle id") }
            state.requestedVehicleID = vehicleID
            state.environmentRequestCount += 1
            progress = .free(state)
            pendingHostEffects.append(.requestVehicle(vehicleID))

        case (.free, .freeRequestWeather(let weatherID)):
            guard !weatherID.isEmpty, case .free(var state) = progress else {
                throw GameModeError.invalidValue("weather id")
            }
            state.requestedWeatherID = weatherID
            state.environmentRequestCount += 1
            progress = .free(state)
            pendingHostEffects.append(.requestWeather(weatherID))

        case (.free, .freeRequestTimeOfDay(let timeOfDayID)):
            guard !timeOfDayID.isEmpty, case .free(var state) = progress else { throw GameModeError.invalidValue("time of day id") }
            state.requestedTimeOfDayID = timeOfDayID
            state.environmentRequestCount += 1
            progress = .free(state)
            pendingHostEffects.append(.requestTimeOfDay(timeOfDayID))

        case (.free, .freeRequestSeason(let seasonID)):
            guard !seasonID.isEmpty, case .free(var state) = progress else { throw GameModeError.invalidValue("season id") }
            state.requestedSeasonID = seasonID
            state.environmentRequestCount += 1
            progress = .free(state)
            pendingHostEffects.append(.requestSeason(seasonID))

        case (.free, .freeRequestPassengerLoad(let factor)):
            guard factor.isFinite, factor >= 0, factor <= 2,
                  case .free(var state) = progress else {
                throw GameModeError.invalidValue("passenger load factor must be between 0 and 2")
            }
            state.requestedPassengerLoadFactor = factor
            state.environmentRequestCount += 1
            progress = .free(state)
            pendingHostEffects.append(.requestPassengerLoad(factor))

        case (.free, .freeRecordWaypoint(let waypointID)):
            guard !waypointID.isEmpty, case .free(var state) = progress else {
                throw GameModeError.invalidValue("waypoint id")
            }
            if !state.waypointIDs.contains(waypointID) { state.waypointIDs.append(waypointID) }
            progress = .free(state)

        case (.conductor, .conductorOpenDoors(let side)):
            guard let stationID = lastSnapshot.atStationID, lastSnapshot.speedMps <= 0.1,
                  lastSnapshot.doors == .closed else {
                throw GameModeError.actionUnavailable("game doors require a stopped station and explicitly closed host state")
            }
            guard case .conductor(var state) = progress else { return }
            guard let stop = scenario.stops.first(where: { $0.id == stationID }) else {
                throw GameModeError.unknownIdentifier(stationID)
            }
            guard stop.expectedPlatformSide == side else {
                state.sequenceErrors += 1
                progress = .conductor(state)
                fail(.wrongPlatformSide)
                return
            }
            guard !state.doors.isOpen else { throw GameModeError.actionUnavailable("game doors are already open") }
            state.activeStationID = stationID
            state.doors = side == .left ? .openLeft : .openRight
            progress = .conductor(state)
            pendingHostEffects.append(.setGameDoorState(state.doors))

        case (.conductor, .conductorCloseDoors):
            guard case .conductor(var state) = progress, state.doors.isOpen else {
                throw GameModeError.actionUnavailable("no game door is open")
            }
            state.doors = .closed
            progress = .conductor(state)
            pendingHostEffects.append(.setGameDoorState(.closed))

        case (.conductor, .conductorConfirmDoorClosure):
            guard case .conductor(var state) = progress,
                  state.doors == .closed,
                  lastSnapshot.doors == .closed,
                  lastSnapshot.speedMps <= 0.1,
                  lastSnapshot.atStationID == state.activeStationID,
                  let stationID = state.activeStationID else {
                throw GameModeError.actionUnavailable("close the game doors at a station before confirming")
            }
            if !state.completedStopIDs.contains(stationID) { state.completedStopIDs.append(stationID) }
            if !state.closureConfirmedStopIDs.contains(stationID) { state.closureConfirmedStopIDs.append(stationID) }
            progress = .conductor(state)

        case (.conductor, .conductorPlayAnnouncement(let announcementID)):
            guard scenario.requiredAnnouncementIDs.contains(announcementID),
                  case .conductor(var state) = progress else {
                throw GameModeError.unknownIdentifier(announcementID)
            }
            if !state.playedAnnouncementIDs.contains(announcementID) {
                state.playedAnnouncementIDs.append(announcementID)
            }
            progress = .conductor(state)
            pendingHostEffects.append(.playGameAnnouncement(announcementID))

        case (.conductor, .conductorAnnounceStationName):
            guard let stationID = lastSnapshot.atStationID,
                  lastSnapshot.speedMps <= 0.1,
                  let stop = scenario.stops.first(where: { $0.id == stationID }),
                  let announcementID = stop.stationNameAnnouncementID,
                  case .conductor(var state) = progress else {
                throw GameModeError.actionUnavailable("no station-name announcement is configured for the stopped PLACEHOLDER station")
            }
            if !state.playedAnnouncementIDs.contains(announcementID) { state.playedAnnouncementIDs.append(announcementID) }
            progress = .conductor(state)
            pendingHostEffects.append(.playGameAnnouncement(announcementID))

        case (.disruption, .disruptionRespond(let choice)):
            guard case .disruption(var state) = progress, state.state == .active,
                  let startedAt = state.eventStartedAtSeconds else {
                throw GameModeError.actionUnavailable("no active game event")
            }
            guard lastSnapshot.simulationTimeSeconds - startedAt <= scenario.incident.responseDeadlineSeconds else {
                state.state = .missed
                progress = .disruption(state)
                fail(.incidentDeadlineExpired)
                return
            }
            state.response = choice
            if choice == scenario.incident.expectedChoice {
                state.state = .resolved
                if choice == .requestGameHint {
                    state.hintCount += 1
                    hintCount += 1
                    pendingHostEffects.append(.presentGameHint(scenario.incident.id))
                }
            } else {
                state.state = .incorrect
                progress = .disruption(state)
                fail(.wrongIncidentChoice)
                return
            }
            progress = .disruption(state)

        case (.training, .trainingRequestHint):
            guard case .training(var state) = progress else { return }
            state.hintCount += 1
            hintCount += 1
            progress = .training(state)
            let next = scenario.trainingSteps.dropFirst(state.completedStepIDs.count).first?.id ?? "PLACEHOLDER-no-next-step"
            pendingHostEffects.append(.presentGameHint(next))

        case (.training, .trainingCompleteStep(let stepID)):
            guard case .training(var state) = progress else { return }
            let expected = scenario.trainingSteps.dropFirst(state.completedStepIDs.count).first
            guard let expected else {
                throw GameModeError.actionUnavailable("all game lesson steps are already complete")
            }
            guard expected.id == stepID, requirementIsMet(expected, snapshot: lastSnapshot) else {
                state.mistakes += 1
                progress = .training(state)
                if state.mistakes >= 3 { fail(.trainingMistakeLimit) }
                return
            }
            state.completedStepIDs.append(stepID)
            progress = .training(state)

        case (_, .modeRequestHint):
            guard playStyle == .practice || playStyle == .disruptionTraining else {
                throw GameModeError.actionUnavailable("mode hints are available only in practice or disruption-training style")
            }
            hintCount += 1
            switch progress {
            case .training(var state):
                state.hintCount += 1
                progress = .training(state)
            case .disruption(var state):
                state.hintCount += 1
                progress = .disruption(state)
            default:
                break
            }
            pendingHostEffects.append(.presentGameHint("PLACEHOLDER-\(mode.rawValue)-hint-\(hintCount)"))

        case (.tourism, .tourismObserve(let landmarkID)):
            guard case .tourism(var state) = progress,
                  let landmark = scenario.landmarks.first(where: { $0.id == landmarkID }) else {
                throw GameModeError.unknownIdentifier(landmarkID)
            }
            guard lastSnapshot.visibleLandmarkID == landmarkID,
                  abs(lastSnapshot.positionM - landmark.positionM) <= landmark.observationRadiusM,
                  lastSnapshot.speedMps <= landmark.maximumObservationSpeedMps else {
                throw GameModeError.actionUnavailable("landmark must be visible, in range, and within its game observation speed")
            }
            if !state.observedLandmarkIDs.contains(landmarkID) { state.observedLandmarkIDs.append(landmarkID) }
            progress = .tourism(state)

        case (.companyOperations, .companyAssign(let taskID, let slotID)):
            guard case .companyOperations(var state) = progress,
                  let task = scenario.dispatchTasks.first(where: { $0.id == taskID }),
                  let slot = scenario.dispatchSlots.first(where: { $0.id == slotID }) else {
                throw GameModeError.unknownIdentifier("\(taskID)/\(slotID)")
            }
            guard task.allowedSlotIDs.contains(slotID) else {
                throw GameModeError.invalidAssignment("slot is not allowed for task")
            }
            guard lastSnapshot.trains.contains(where: { $0.id == task.trainID && $0.routeID == scenario.routeID }) else {
                throw GameModeError.missingTrain(task.trainID)
            }
            let elapsed = lastSnapshot.simulationTimeSeconds - sessionStartTimeSeconds
            guard elapsed <= task.deadlineSeconds,
                  elapsed >= slot.startTimeSeconds,
                  elapsed <= slot.endTimeSeconds else {
                state.overdueTaskIDs.insert(task.id)
                progress = .companyOperations(state)
                fail(.dispatchDeadlineExpired)
                return
            }
            guard state.assignmentsByTaskID[task.id] == nil else {
                throw GameModeError.actionUnavailable("task already assigned")
            }
            let conflictingTaskID = state.assignmentsByTaskID.first { assignment in
                guard let assignedSlot = scenario.dispatchSlots.first(where: { $0.id == assignment.value }) else { return false }
                let overlappingSeconds = min(assignedSlot.endTimeSeconds, slot.endTimeSeconds) - max(assignedSlot.startTimeSeconds, slot.startTimeSeconds)
                return assignedSlot.trackID == slot.trackID && overlappingSeconds > 0
            }?.key
            if let conflictingTaskID {
                state.conflictPairs.insert("\(task.id)|\(conflictingTaskID)")
                progress = .companyOperations(state)
                fail(.dispatchConflict)
                return
            }
            state.assignmentsByTaskID[task.id] = slotID
            progress = .companyOperations(state)

        default:
            throw GameModeError.actionNotSupported(mode: mode)
        }
    }

    private func requirementIsMet(_ step: GameModeTrainingStep, snapshot: GameModeSimulationSnapshot) -> Bool {
        switch step.requirement {
        case .stopped:
            return snapshot.speedMps <= 0.1
        case .withinCurrentSpeedLimit:
            return snapshot.speedMps * 3.6 <= snapshot.speedLimitKmh + 0.1
        case .atStation:
            return snapshot.atStationID != nil && snapshot.speedMps <= 0.1
        case .promptVisible:
            return step.requiredPromptID != nil && snapshot.trainingPromptID == step.requiredPromptID
        }
    }

    private mutating func finish() throws {
        guard status == .active else { throw GameModeError.actionUnavailable("mode must be active to finish") }
        switch mode {
        case .driver:
            guard case .driver(let state) = progress,
                  state.completedDutyStepIDs.count == scenario.driverDutyStepIDs.count,
                  state.departureConfirmed,
                  state.visitedStopIDs.count == requiredStopIDs.count,
                  lastSnapshot.positionM >= scenario.routeLengthM - 0.1,
                  lastSnapshot.speedMps <= 0.1 else {
                if case .driver(let state) = progress, !state.departureConfirmed { fail(.departureNotConfirmed) }
                else if case .driver(let state) = progress, state.completedDutyStepIDs.count != scenario.driverDutyStepIDs.count { fail(.driverChecklistIncomplete) }
                else { fail(.routeIncomplete) }
                return
            }
            succeed()
        case .timetable:
            guard case .timetable(let state) = progress else { return }
            guard lastSnapshot.positionM >= scenario.routeLengthM - 0.1 else {
                fail(.routeIncomplete)
                return
            }
            let allArrivalsObserved = requiredStopIDs.allSatisfy { state.arrivalDelayByStop[$0] != nil }
            let requiredDepartureIDs = requiredStopIDs.filter { stopID in
                scenario.stops.first(where: { $0.id == stopID })?.scheduledDepartureSeconds != nil
            }
            let allDeparturesObserved = requiredDepartureIDs.allSatisfy { state.departureDelayByStop[$0] != nil }
            let unresolvedLate = requiredStopIDs.contains { stopID in
                guard let stop = scenario.stops.first(where: { $0.id == stopID }) else { return true }
                let delays = [state.arrivalDelayByStop[stopID], state.departureDelayByStop[stopID]].compactMap { $0 }
                return delays.contains(where: { abs($0) > stop.arrivalToleranceSeconds }) && !state.recoveryUsedForStopIDs.contains(stopID)
            }
            if !allArrivalsObserved || !allDeparturesObserved { fail(.routeIncomplete) }
            else if unresolvedLate { fail(.missedTimepoint) }
            else { succeed() }
        case .free:
            status = .completed
            evaluation = makeEvaluation(outcome: .selfDirected)
        case .conductor:
            guard case .conductor(let state) = progress else { return }
            let allStops = requiredStopIDs.allSatisfy(state.closureConfirmedStopIDs.contains)
            let allAnnouncements = scenario.requiredAnnouncementIDs.allSatisfy(state.playedAnnouncementIDs.contains)
            let requiredStationNameIDs = scenario.stops.filter { requiredStopIDs.contains($0.id) }.compactMap(\.stationNameAnnouncementID)
            let allStationNames = requiredStationNameIDs.allSatisfy(state.playedAnnouncementIDs.contains)
            if !allStops || !allAnnouncements || !allStationNames { fail(.conductorSequenceError) }
            else { succeed() }
        case .disruption:
            guard case .disruption(let state) = progress, state.state == .resolved else {
                fail(.unresolvedIncident)
                return
            }
            succeed()
        case .training:
            guard case .training(let state) = progress,
                  state.completedStepIDs.count == scenario.trainingSteps.count,
                  state.mistakes < 3 else {
                fail(.trainingIncomplete)
                return
            }
            succeed()
        case .fullLine:
            guard case .fullLine(let state) = progress,
                  state.visitedStopIDs.count == requiredStopIDs.count,
                  lastSnapshot.positionM >= scenario.routeLengthM - 0.1,
                  lastSnapshot.speedMps <= 0.1 else {
                fail(.routeIncomplete)
                return
            }
            succeed()
        case .tourism:
            guard case .tourism(let state) = progress,
                  state.observedLandmarkIDs.count >= requiredLandmarkCount else {
                fail(.insufficientLandmarks)
                return
            }
            succeed()
        case .companyOperations:
            guard case .companyOperations(let state) = progress else { return }
            if !state.conflictPairs.isEmpty { fail(.dispatchConflict) }
            else if !state.overdueTaskIDs.isEmpty { fail(.dispatchDeadlineExpired) }
            else if state.assignmentsByTaskID.count != scenario.dispatchTasks.count { fail(.unassignedTasks) }
            else { succeed() }
        }
    }

    private mutating func succeed() {
        status = .succeeded
        evaluation = makeEvaluation(outcome: .success)
    }

    private mutating func fail(_ reason: GameModeFailureReason) {
        guard !status.isTerminal else { return }
        status = .failed
        failureReason = reason
        evaluation = makeEvaluation(outcome: .failure)
    }

    private func makeEvaluation(outcome: GameModeOutcome) -> GameModeEvaluation {
        var metrics: [String: Double] = [:]
        var score: Double? = nil
        switch progress {
        case .driver(let state):
            metrics = [
                "completedDutySteps": Double(state.completedDutyStepIDs.count),
                "requiredDutySteps": Double(scenario.driverDutyStepIDs.count),
                "visitedStops": Double(state.visitedStopIDs.count),
                "requiredStops": Double(requiredStopIDs.count),
                "overspeedSamples": Double(state.overspeedSamples),
                "maximumAbsoluteAccelerationMps2": state.maximumAbsoluteAccelerationMps2,
                "maximumJerkMps3": state.maximumJerkMps3,
                "routeProgressM": state.routeProgressM,
                "routeProgressPercent": min(100, max(0, state.routeProgressM / scenario.routeLengthM * 100))
            ]
            let checklistRate = percentage(state.completedDutyStepIDs.count, of: scenario.driverDutyStepIDs.count)
            let stopRate = percentage(state.visitedStopIDs.count, of: requiredStopIDs.count)
            let routeRate = min(100, max(0, state.routeProgressM / scenario.routeLengthM * 100))
            score = state.overspeedSamples == 0 ? (checklistRate + stopRate + routeRate) / 3 : 0
        case .timetable(let state):
            let arrivalOnTime = requiredStopIDs.filter { stopID in
                guard let delay = state.arrivalDelayByStop[stopID], let stop = scenario.stops.first(where: { $0.id == stopID }) else { return false }
                return abs(delay) <= stop.arrivalToleranceSeconds || state.recoveryUsedForStopIDs.contains(stopID)
            }.count
            let requiredDepartureIDs = requiredStopIDs.filter { stopID in
                scenario.stops.first(where: { $0.id == stopID })?.scheduledDepartureSeconds != nil
            }
            let departureOnTime = requiredDepartureIDs.filter { stopID in
                guard let delay = state.departureDelayByStop[stopID], let stop = scenario.stops.first(where: { $0.id == stopID }) else { return false }
                return abs(delay) <= stop.arrivalToleranceSeconds || state.recoveryUsedForStopIDs.contains(stopID)
            }.count
            let allDelays = Array(state.arrivalDelayByStop.values) + Array(state.departureDelayByStop.values)
            let maxDelay = allDelays.map(abs).max() ?? 0
            let totalEvents = requiredStopIDs.count + requiredDepartureIDs.count
            let onTimeEvents = arrivalOnTime + departureOnTime
            metrics = ["onTimeEvents": Double(onTimeEvents), "requiredTimepoints": Double(totalEvents), "visitedStops": Double(state.observedStopIDs.count), "orderViolations": Double(state.orderViolations), "maxDelaySeconds": maxDelay, "recoveryCreditsUsed": Double(state.recoveryUsedForStopIDs.count)]
            score = percentage(onTimeEvents, of: totalEvents)
        case .free(let state):
            metrics = ["elapsedSeconds": state.elapsedSeconds, "waypoints": Double(state.waypointIDs.count), "environmentRequests": Double(state.environmentRequestCount), "hasVehicleSelection": state.selectedVehicleID == nil ? 0 : 1, "hasWeatherSelection": state.selectedWeatherID == nil ? 0 : 1]
        case .conductor(let state):
            let requiredStationNameIDs = scenario.stops.filter { requiredStopIDs.contains($0.id) }.compactMap(\.stationNameAnnouncementID)
            let playedStationNames = requiredStationNameIDs.filter(state.playedAnnouncementIDs.contains).count
            let playedRequiredAnnouncements = scenario.requiredAnnouncementIDs.filter(state.playedAnnouncementIDs.contains).count
            let completedRequirements = state.closureConfirmedStopIDs.count + playedStationNames + playedRequiredAnnouncements
            let totalRequirements = requiredStopIDs.count + requiredStationNameIDs.count + scenario.requiredAnnouncementIDs.count
            metrics = ["confirmedStops": Double(state.closureConfirmedStopIDs.count), "requiredStops": Double(requiredStopIDs.count), "announcements": Double(state.playedAnnouncementIDs.count), "requiredAnnouncements": Double(scenario.requiredAnnouncementIDs.count), "stationNameAnnouncements": Double(playedStationNames), "requiredStationNameAnnouncements": Double(requiredStationNameIDs.count), "sequenceErrors": Double(state.sequenceErrors)]
            score = percentage(completedRequirements, of: totalRequirements)
        case .disruption(let state):
            let correct = state.state == .resolved ? 1.0 : 0.0
            metrics = ["correctResponses": correct, "hintCount": Double(state.hintCount), "responseSeconds": max(0, (lastSnapshot.simulationTimeSeconds - (state.eventStartedAtSeconds ?? lastSnapshot.simulationTimeSeconds)))]
            score = correct * 100
        case .training(let state):
            metrics = ["completedSteps": Double(state.completedStepIDs.count), "requiredSteps": Double(scenario.trainingSteps.count), "mistakes": Double(state.mistakes), "hints": Double(state.hintCount)]
            score = percentage(state.completedStepIDs.count, of: scenario.trainingSteps.count)
        case .fullLine(let state):
            metrics = ["visitedStops": Double(state.visitedStopIDs.count), "requiredStops": Double(requiredStopIDs.count), "routeProgressM": state.routeProgressM, "routeLengthM": scenario.routeLengthM, "orderViolations": Double(state.orderViolations)]
            score = percentage(state.visitedStopIDs.count, of: requiredStopIDs.count)
        case .tourism(let state):
            metrics = ["observedLandmarks": Double(state.observedLandmarkIDs.count), "requiredLandmarks": Double(requiredLandmarkCount), "routeProgressM": state.routeProgressM, "routeLengthM": scenario.routeLengthM]
            score = percentage(state.observedLandmarkIDs.count, of: requiredLandmarkCount)
        case .companyOperations(let state):
            metrics = ["assignedTasks": Double(state.assignmentsByTaskID.count), "requiredTasks": Double(scenario.dispatchTasks.count), "conflicts": Double(state.conflictPairs.count), "overdueTasks": Double(state.overdueTaskIDs.count)]
            score = percentage(state.assignmentsByTaskID.count, of: scenario.dispatchTasks.count)
        }
        let summary: String
        switch outcome {
        case .success: summary = "\(definition.title)モード成功。架空ゲーム評価です。"
        case .failure: summary = "\(definition.title)モード失敗: \(failureReason?.rawValue ?? "条件未達")。架空ゲーム評価です。"
        case .blocked: summary = "\(definition.title)モード判定不能。必須データ未接続で、失敗扱いではありません。"
        case .selfDirected: summary = "フリー運転を自己設定プレイとして終了しました。合否評価はありません。"
        case .abandoned: summary = "\(definition.title)モードを放棄しました。"
        }
        return GameModeEvaluation(mode: mode, outcome: outcome, scorePercent: score, summary: summary, metrics: metrics, failureReason: failureReason)
    }

    private func percentage(_ numerator: Int, of denominator: Int) -> Double {
        guard denominator > 0 else { return 100 }
        return min(100, max(0, Double(numerator) / Double(denominator) * 100))
    }
}
