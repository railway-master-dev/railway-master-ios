import Foundation

public enum OperationsWorkflowCommand: Codable, Equatable, Sendable {
    case completePreDutyCheck(PreDutyCheck)
    case startCab
    case completeCabCheck(CabSetupCheck)
    case completeDepotExit
    case completeDepartureCheck(DepartureCheck)
    case observeGameSignal(GameSignalAspect)
    case depart
    case arrive(stationID: String, positionM: Double, speedMps: Double)
    case openDoors
    case closeDoors
    case finishRun
    case completePostRunCheck(PostRunCheck)
    case closeOut
}

public struct OperationsWorkflowEvent: Codable, Equatable, Sendable, Identifiable {
    public let id: Int
    public let simulationTimeSeconds: Double
    public let command: OperationsWorkflowCommand
    public let phaseBefore: WorkflowPhase
    public let phaseAfter: WorkflowPhase
    public let label: OperationsContentLabel
}

/// Deterministic gameplay workflow. Its checklist items are fictional prompts only.
public struct OperationsWorkflow: Codable, Equatable, Sendable {
    public let scenario: OperationsScenario
    public let mode: TrainingMode
    public private(set) var phase: WorkflowPhase
    public private(set) var cabStarted: Bool
    public private(set) var doorsClosed: Bool
    public private(set) var currentStopIndex: Int
    public private(set) var latestGameSignal: GameSignalAspect?
    public private(set) var completedPreDutyChecks: Set<PreDutyCheck>
    public private(set) var completedCabChecks: Set<CabSetupCheck>
    public private(set) var completedDepartureChecks: Set<DepartureCheck>
    public private(set) var completedPostRunChecks: Set<PostRunCheck>
    public private(set) var scheduleObservations: [ScheduleObservation]
    public private(set) var stopAssessments: [StopAssessment]
    public private(set) var events: [OperationsWorkflowEvent]
    public private(set) var lastEventTimeSeconds: Double?

    public static let requiredPreDutyChecks: Set<PreDutyCheck> = Set(PreDutyCheck.allCases)
    public static let requiredCabChecks: Set<CabSetupCheck> = Set(CabSetupCheck.allCases)
    public static let requiredDepartureChecks: Set<DepartureCheck> = Set(DepartureCheck.allCases)
    public static let requiredPostRunChecks: Set<PostRunCheck> = Set(PostRunCheck.allCases)
    public static let stoppedSpeedThresholdMps = 0.15

    public init(scenario: OperationsScenario, mode: TrainingMode) {
        self.scenario = scenario
        self.mode = mode
        self.phase = .preDutyChecks
        self.cabStarted = false
        self.doorsClosed = true
        self.currentStopIndex = 0
        self.latestGameSignal = nil
        self.completedPreDutyChecks = []
        self.completedCabChecks = []
        self.completedDepartureChecks = []
        self.completedPostRunChecks = []
        self.scheduleObservations = []
        self.stopAssessments = []
        self.events = []
        self.lastEventTimeSeconds = nil
    }

    public var currentStop: OperationsStopDefinition? {
        guard currentStopIndex < scenario.stops.count else { return nil }
        return scenario.stops[currentStopIndex]
    }

    public var contentLabel: OperationsContentLabel { .fictionalGameRules }

    @discardableResult
    public mutating func apply(_ command: OperationsWorkflowCommand, at simulationTimeSeconds: Double) throws -> OperationsWorkflowEvent {
        guard simulationTimeSeconds.isFinite, simulationTimeSeconds >= 0 else {
            throw OperationsError.invalidValue("simulation time")
        }
        if let lastEventTimeSeconds, simulationTimeSeconds < lastEventTimeSeconds {
            throw OperationsError.timeMustNotRegress
        }

        let before = phase
        switch command {
        case .completePreDutyCheck(let check):
            guard phase == .preDutyChecks else { throw invalid("pre-duty check outside pre-duty phase") }
            completedPreDutyChecks.insert(check)
            if completedPreDutyChecks.isSuperset(of: Self.requiredPreDutyChecks) { phase = .cabSetup }

        case .startCab:
            guard phase == .cabSetup, !cabStarted else { throw invalid("cab can only be started once after game pre-duty prompts") }
            cabStarted = true

        case .completeCabCheck(let check):
            guard phase == .cabSetup, cabStarted else { throw invalid("cab setup prompt requires a started cab") }
            completedCabChecks.insert(check)
            if completedCabChecks.isSuperset(of: Self.requiredCabChecks) { phase = .depotExit }

        case .completeDepotExit:
            guard phase == .depotExit else { throw invalid("depot-exit transition out of order") }
            phase = .departurePreparation
            latestGameSignal = nil
            completedDepartureChecks.removeAll()

        case .completeDepartureCheck(let check):
            guard phase == .departurePreparation || phase == .stationStop else {
                throw invalid("departure prompt outside a departure preparation phase")
            }
            if check == .doorsClosedPrompt && !doorsClosed {
                throw OperationsError.unmetRequirements(["doorsClosedPrompt"])
            }
            if check == .gameSignalPrompt && latestGameSignal != .proceed {
                throw OperationsError.unmetRequirements(["gameSignalPrompt: proceed aspect must be observed in this game"])
            }
            completedDepartureChecks.insert(check)

        case .observeGameSignal(let aspect):
            guard phase == .departurePreparation || phase == .enRoute || phase == .stationStop else {
                throw invalid("game signal observation outside an active run")
            }
            latestGameSignal = aspect
            if phase == .enRoute && aspect == .stop {
                // The host owns physical braking; this module records only game state and scoring evidence.
            }

        case .depart:
            guard phase == .departurePreparation || phase == .stationStop else {
                throw invalid("departure outside origin or station stop")
            }
            if phase == .stationStop && currentStopIndex >= scenario.stops.count - 1 {
                throw invalid("the final scheduled stop must proceed to end-of-run, not another departure")
            }
            let missing = Self.requiredDepartureChecks.subtracting(completedDepartureChecks).map(\.rawValue).sorted()
            var unmet = missing
            if !doorsClosed { unmet.append("doorsClosed") }
            if latestGameSignal != .proceed { unmet.append("gameSignalProceed") }
            guard unmet.isEmpty else { throw OperationsError.unmetRequirements(unmet) }
            if phase == .departurePreparation {
                let observation = try ScheduleObservation(
                    id: "\(scenario.originStationID).departure",
                    kind: .departure,
                    scheduledTimeSeconds: scenario.originScheduledDepartureSeconds,
                    actualTimeSeconds: simulationTimeSeconds
                )
                scheduleObservations.append(observation)
            } else if let stop = currentStop {
                let observation = try ScheduleObservation(
                    id: "\(stop.id).departure",
                    kind: .departure,
                    scheduledTimeSeconds: stop.scheduledDepartureSeconds,
                    actualTimeSeconds: simulationTimeSeconds
                )
                scheduleObservations.append(observation)
                currentStopIndex += 1
            }
            phase = .enRoute
            latestGameSignal = nil
            completedDepartureChecks.removeAll()

        case .arrive(let stationID, let positionM, let speedMps):
            guard phase == .enRoute, let stop = currentStop else { throw invalid("arrival when no scheduled station stop is expected") }
            guard stationID == stop.id else { throw OperationsError.invalidValue("unexpected station id: \(stationID)") }
            guard positionM.isFinite, positionM >= 0, speedMps.isFinite, speedMps >= 0 else {
                throw OperationsError.invalidValue("arrival position/speed")
            }
            guard speedMps <= Self.stoppedSpeedThresholdMps else {
                throw OperationsError.invalidValue("game arrival requires a near-zero speed sample")
            }
            let assessment = try StopAssessment(
                id: stop.id,
                targetPositionM: stop.targetPositionM,
                actualPositionM: positionM,
                toleranceM: stop.positionToleranceM,
                stopped: true
            )
            let arrival = try ScheduleObservation(
                id: "\(stop.id).arrival",
                kind: .arrival,
                scheduledTimeSeconds: scenario.stops[currentStopIndex].scheduledArrivalSeconds,
                actualTimeSeconds: simulationTimeSeconds
            )
            stopAssessments.append(assessment)
            scheduleObservations.append(arrival)
            phase = .stationStop
            doorsClosed = true
            latestGameSignal = nil
            completedDepartureChecks.removeAll()

        case .openDoors:
            guard phase == .stationStop, doorsClosed else { throw invalid("doors can only be opened once at a recorded station stop") }
            doorsClosed = false

        case .closeDoors:
            guard phase == .stationStop, !doorsClosed else { throw invalid("doors are not open at a station stop") }
            doorsClosed = true

        case .finishRun:
            guard phase == .stationStop, currentStopIndex == scenario.stops.count - 1,
                  doorsClosed else {
                throw invalid("finish the final scheduled stop and close the game doors first")
            }
            phase = .endOfRun

        case .completePostRunCheck(let check):
            guard phase == .endOfRun else { throw invalid("post-run prompt outside end-of-run phase") }
            completedPostRunChecks.insert(check)

        case .closeOut:
            guard phase == .endOfRun else { throw invalid("close-out outside end-of-run phase") }
            let missing = Self.requiredPostRunChecks.subtracting(completedPostRunChecks).map(\.rawValue).sorted()
            guard missing.isEmpty else { throw OperationsError.unmetRequirements(missing) }
            phase = .completed
        }

        let event = OperationsWorkflowEvent(
            id: events.count,
            simulationTimeSeconds: simulationTimeSeconds,
            command: command,
            phaseBefore: before,
            phaseAfter: phase,
            label: .fictionalGameRules
        )
        events.append(event)
        lastEventTimeSeconds = simulationTimeSeconds
        return event
    }

    private func invalid(_ message: String) -> OperationsError {
        .invalidTransition(message)
    }
}
