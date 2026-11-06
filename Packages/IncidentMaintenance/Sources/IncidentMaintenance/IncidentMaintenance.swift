import Foundation

/// Every user-facing response/recovery prompt must contain this exact disclaimer.
public let incidentMaintenanceFictionDisclaimer = "FICTIONAL GAME CONTENT — NOT REAL RAILWAY PROCEDURE OR SAFETY TRAINING"

// MARK: - Stable identifiers and simulation time

public struct EventDefinitionID: Codable, Hashable, Sendable {
    public let rawValue: String
    public init(_ rawValue: String) { self.rawValue = rawValue }
    public var isValid: Bool { !rawValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
}

public struct EventInstanceID: Codable, Hashable, Sendable {
    public let rawValue: String
    public init(_ rawValue: String) { self.rawValue = rawValue }
}

public struct VehicleID: Codable, Hashable, Sendable {
    public let rawValue: String
    public init(_ rawValue: String) { self.rawValue = rawValue }
    public var isValid: Bool { !rawValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
}

public struct DepotID: Codable, Hashable, Sendable {
    public let rawValue: String
    public init(_ rawValue: String) { self.rawValue = rawValue }
    public var isValid: Bool { !rawValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
}

public struct GameTick: Codable, Hashable, Comparable, Sendable {
    public let value: UInt64
    public init(_ value: UInt64) { self.value = value }
    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.value < rhs.value }
}

// MARK: - Events: declarations are game content, never operating guidance

public enum IncidentKind: String, Codable, CaseIterable, Sendable {
    case vehicleFailure
    case passengerMedicalEvent
    case onboardDisruption
    case levelCrossingObstruction
    case trackObstruction
    case precedingTrainDelay
    case adverseWeather
    case stoppedSignalScenario
    case lightningScenario
    case earthquakeRestrictionScenario
    case emergencyStopScenario
    case serviceResumptionScenario
}

/// Scope is explicit so host systems do not have to infer the affected game entities.
public enum ImpactScope: Codable, Hashable, Sendable {
    case vehicle(VehicleID)
    case station(String)
    case track(String)
    case route(String)
    case network
}

/// Purely fictional values for game/UI systems; they are not real performance or safety limits.
public struct GameEffects: Codable, Equatable, Sendable {
    public let serviceDelayTicks: Int
    public let tractionMultiplier: Double
    public let brakingMultiplier: Double
    public let speedMultiplier: Double
    public let departureHeld: Bool

    public init(serviceDelayTicks: Int = 0, tractionMultiplier: Double = 1,
                brakingMultiplier: Double = 1, speedMultiplier: Double = 1,
                departureHeld: Bool = false) {
        self.serviceDelayTicks = serviceDelayTicks
        self.tractionMultiplier = tractionMultiplier
        self.brakingMultiplier = brakingMultiplier
        self.speedMultiplier = speedMultiplier
        self.departureHeld = departureHeld
    }

    fileprivate var isValid: Bool {
        serviceDelayTicks >= 0 && tractionMultiplier.isFinite && tractionMultiplier >= 0 &&
        brakingMultiplier.isFinite && brakingMultiplier >= 0 && speedMultiplier.isFinite && speedMultiplier >= 0
    }
}

/// Eligible time window is inclusive. Metric and signal conditions are evaluated per fixed tick.
public indirect enum EventTrigger: Codable, Equatable, Sendable {
    case manualSignal(String)
    case metricAtLeast(name: String, threshold: Int)
    case eligibleTimeWindow(from: GameTick, through: GameTick)
    case all([EventTrigger])
    case any([EventTrigger])

    fileprivate var isValid: Bool {
        switch self {
        case .manualSignal(let value): return !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .metricAtLeast(let name, _): return !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .eligibleTimeWindow(let from, let through): return from <= through
        case .all(let rules), .any(let rules): return !rules.isEmpty && rules.allSatisfy(\.isValid)
        }
    }
}

/// Duration is sampled uniformly in whole ticks. Recovery conditions can end the event
/// after the sampled minimum; otherwise it ends no later than the sampled duration.
public indirect enum RecoveryRule: Codable, Equatable, Sendable {
    case elapsedTicks(Int)
    case actionRequired(String)
    case metricAtMost(name: String, threshold: Int)
    case all([RecoveryRule])
    case any([RecoveryRule])

    fileprivate var isValid: Bool {
        switch self {
        case .elapsedTicks(let ticks): return ticks >= 0
        case .actionRequired(let id): return !id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .metricAtMost(let name, _): return !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .all(let rules), .any(let rules): return !rules.isEmpty && rules.allSatisfy(\.isValid)
        }
    }
}

public struct EventDurationRange: Codable, Equatable, Sendable {
    public let minimumTicks: Int
    public let maximumTicks: Int
    public init(minimumTicks: Int, maximumTicks: Int) {
        self.minimumTicks = minimumTicks
        self.maximumTicks = maximumTicks
    }
    fileprivate var isValid: Bool {
        minimumTicks >= 1 && maximumTicks >= minimumTicks && maximumTicks - minimumTicks < Int.max
    }
}

public struct IncidentEventDefinition: Codable, Equatable, Sendable {
    public let id: EventDefinitionID
    public let kind: IncidentKind
    public let trigger: EventTrigger
    /// Chance, in parts per million, checked independently on every eligible fixed tick.
    public let occurrenceChancePerEligibleTick: UInt32
    public let duration: EventDurationRange
    public let impactScope: ImpactScope
    public let effects: GameEffects
    public let recoveryRule: RecoveryRule
    public let fictionalResponsePrompt: String
    public let fictionalRecoveryPrompt: String

    public init(id: EventDefinitionID, kind: IncidentKind, trigger: EventTrigger,
                occurrenceChancePerEligibleTick: UInt32, duration: EventDurationRange,
                impactScope: ImpactScope, effects: GameEffects, recoveryRule: RecoveryRule,
                fictionalResponsePrompt: String, fictionalRecoveryPrompt: String) {
        self.id = id
        self.kind = kind
        self.trigger = trigger
        self.occurrenceChancePerEligibleTick = occurrenceChancePerEligibleTick
        self.duration = duration
        self.impactScope = impactScope
        self.effects = effects
        self.recoveryRule = recoveryRule
        self.fictionalResponsePrompt = fictionalResponsePrompt
        self.fictionalRecoveryPrompt = fictionalRecoveryPrompt
    }

    fileprivate var isValid: Bool {
        id.isValid && occurrenceChancePerEligibleTick <= 1_000_000 && duration.isValid && effects.isValid &&
        fictionalResponsePrompt.contains(incidentMaintenanceFictionDisclaimer) &&
        fictionalRecoveryPrompt.contains(incidentMaintenanceFictionDisclaimer) &&
        trigger.isValid && recoveryRule.isValid && impactScope.isValid
    }
}

private extension ImpactScope {
    var isValid: Bool {
        switch self {
        case .vehicle(let id): return id.isValid
        case .station(let id), .track(let id), .route(let id):
            return !id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .network: return true
        }
    }
}

public struct TickInput: Codable, Equatable, Sendable {
    public let manualSignals: Set<String>
    public let metrics: [String: Int]
    /// Stable action tokens supplied by game logic; not free-form instructions.
    public let recoveryActionIDs: Set<String>
    public init(manualSignals: Set<String> = [], metrics: [String: Int] = [:], recoveryActionIDs: Set<String> = []) {
        self.manualSignals = manualSignals
        self.metrics = metrics
        self.recoveryActionIDs = recoveryActionIDs
    }
}

public enum EventLifecycle: String, Codable, Sendable { case active, recovered }

public struct IncidentEventRecord: Codable, Equatable, Sendable, Identifiable {
    public let id: EventInstanceID
    public let definitionID: EventDefinitionID
    public let kind: IncidentKind
    public let impactScope: ImpactScope
    public let effects: GameEffects
    public let startedAt: GameTick
    public let sampledDurationTicks: Int
    public var lifecycle: EventLifecycle
    public var recoveredAt: GameTick?
    public let fictionalResponsePrompt: String
    public let fictionalRecoveryPrompt: String
}

public struct IncidentTickResult: Codable, Equatable, Sendable {
    public let tick: GameTick
    public let startedEvents: [IncidentEventRecord]
    public let recoveredEvents: [IncidentEventRecord]
    public let activeEvents: [IncidentEventRecord]
}

// MARK: - Depot / fictional inspection and maintenance flow

public enum DepotVehicleState: String, Codable, Sendable {
    case stabled
    case inspectionInProgress
    case needsMaintenance
    case ready
    case maintenanceInProgress
    case reinspectionRequired
    case reinspectionInProgress
    case dispatchable
}

public enum InspectionOutcome: String, Codable, Sendable { case passed, needsMaintenance }

public enum DepotAction: Codable, Equatable, Sendable {
    case beginInspection
    case completeInspection(InspectionOutcome)
    case beginMaintenance
    case completeMaintenance
    case beginReinspection
    case completeReinspection(InspectionOutcome)
    case dispatch
}

public enum DepotWorkStatus: String, Codable, Sendable { case inProgress, completed }

public struct DepotHistoryEntry: Codable, Equatable, Sendable {
    public let tick: GameTick
    public let action: DepotAction
    public let resultingState: DepotVehicleState
}

public struct DepotRecord: Codable, Equatable, Sendable {
    public let vehicleID: VehicleID
    public let depotID: DepotID
    public var state: DepotVehicleState
    public var activeInspectionStatus: DepotWorkStatus?
    public var activeMaintenanceStatus: DepotWorkStatus?
    public var lastTransitionAt: GameTick?
    public var history: [DepotHistoryEntry]

    public init(vehicleID: VehicleID, depotID: DepotID, initialState: DepotVehicleState = .stabled) {
        self.vehicleID = vehicleID
        self.depotID = depotID
        self.state = initialState
        self.activeInspectionStatus = nil
        self.activeMaintenanceStatus = nil
        self.lastTransitionAt = nil
        self.history = []
    }

    fileprivate mutating func apply(_ action: DepotAction, at tick: GameTick) throws {
        if let previous = lastTransitionAt, tick < previous {
            throw IncidentMaintenanceError.timeWentBackwards(previous: previous, proposed: tick)
        }
        let next: DepotVehicleState
        switch (state, action) {
        case (.stabled, .beginInspection):
            next = .inspectionInProgress; activeInspectionStatus = .inProgress
        case (.inspectionInProgress, .completeInspection(.passed)):
            next = .ready; activeInspectionStatus = .completed
        case (.inspectionInProgress, .completeInspection(.needsMaintenance)):
            next = .needsMaintenance; activeInspectionStatus = .completed
        case (.needsMaintenance, .beginMaintenance):
            next = .maintenanceInProgress; activeMaintenanceStatus = .inProgress
        case (.maintenanceInProgress, .completeMaintenance):
            next = .reinspectionRequired; activeMaintenanceStatus = .completed
        case (.reinspectionRequired, .beginReinspection):
            next = .reinspectionInProgress; activeInspectionStatus = .inProgress
        case (.reinspectionInProgress, .completeReinspection(.passed)):
            next = .ready; activeInspectionStatus = .completed
        case (.reinspectionInProgress, .completeReinspection(.needsMaintenance)):
            next = .needsMaintenance; activeInspectionStatus = .completed
        case (.ready, .dispatch):
            next = .dispatchable
        default:
            throw IncidentMaintenanceError.invalidDepotTransition(state: state, action: action)
        }
        state = next
        lastTransitionAt = tick
        history.append(DepotHistoryEntry(tick: tick, action: action, resultingState: next))
    }
}

// MARK: - Explicit persistence contract

/// Public, versioned DTO. It intentionally includes RNG state, event definitions and complete history.
public struct IncidentMaintenanceSaveDTO: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public var simulationTick: GameTick
    public var randomState: UInt64
    public var nextEventSequence: UInt64
    public let eventDefinitions: [IncidentEventDefinition]
    public var eventHistory: [IncidentEventRecord]
    public var depotRecord: DepotRecord

    public init(schemaVersion: Int = 1, simulationTick: GameTick, randomState: UInt64,
                nextEventSequence: UInt64, eventDefinitions: [IncidentEventDefinition],
                eventHistory: [IncidentEventRecord], depotRecord: DepotRecord) {
        self.schemaVersion = schemaVersion
        self.simulationTick = simulationTick
        self.randomState = randomState
        self.nextEventSequence = nextEventSequence
        self.eventDefinitions = eventDefinitions
        self.eventHistory = eventHistory
        self.depotRecord = depotRecord
    }
}

public enum IncidentMaintenanceError: Error, Equatable, Sendable {
    case invalidConfiguration(String)
    case duplicateDefinitionID(String)
    case unknownEventDefinition(String)
    case invalidRecoveryAction
    case invalidDepotTransition(state: DepotVehicleState, action: DepotAction)
    case timeWentBackwards(previous: GameTick, proposed: GameTick)
    case tickOverflow
    case sequenceOverflow
    case unsupportedSaveVersion(Int)
    case invalidSave(String)
}

/// Per-run deterministic simulation. Call `advanceOneTick` exactly once per fixed game tick.
/// No frame delta, display FPS, wall clock, I/O, global randomness or platform API is used.
public struct IncidentMaintenanceEngine: Sendable {
    public private(set) var state: IncidentMaintenanceSaveDTO

    public init(seed: UInt64, eventDefinitions: [IncidentEventDefinition], depotRecord: DepotRecord) throws {
        try Self.validateDefinitions(eventDefinitions)
        guard depotRecord.vehicleID.isValid, depotRecord.depotID.isValid,
              depotRecord.state == .stabled, depotRecord.history.isEmpty,
              depotRecord.activeInspectionStatus == nil, depotRecord.activeMaintenanceStatus == nil,
              depotRecord.lastTransitionAt == nil else {
            throw IncidentMaintenanceError.invalidConfiguration("depot record must start stabled with valid IDs")
        }
        self.state = IncidentMaintenanceSaveDTO(
            simulationTick: GameTick(0), randomState: seed == 0 ? 0x9E3779B97F4A7C15 : seed,
            nextEventSequence: 1, eventDefinitions: eventDefinitions,
            eventHistory: [], depotRecord: depotRecord)
    }

    public init(restoring save: IncidentMaintenanceSaveDTO) throws {
        try Self.validate(save)
        self.state = save
    }

    public func exportSave() -> IncidentMaintenanceSaveDTO { state }

    public static func restore(from save: IncidentMaintenanceSaveDTO) throws -> IncidentMaintenanceEngine {
        try IncidentMaintenanceEngine(restoring: save)
    }

    public mutating func advanceOneTick(input: TickInput = TickInput()) throws -> IncidentTickResult {
        let (nextValue, overflow) = state.simulationTick.value.addingReportingOverflow(1)
        guard !overflow else { throw IncidentMaintenanceError.tickOverflow }
        let tick = GameTick(nextValue)
        var started: [IncidentEventRecord] = []
        var recovered: [IncidentEventRecord] = []
        let activeDefinitionIDs = Set(state.eventHistory.filter { $0.lifecycle == .active }.map(\.definitionID))
        let definitions = state.eventDefinitions.sorted { $0.id.rawValue < $1.id.rawValue }

        // Existing events recover before this tick's eligible event triggers are evaluated.
        for index in state.eventHistory.indices where state.eventHistory[index].lifecycle == .active {
            var record = state.eventHistory[index]
            guard let definition = definitions.first(where: { $0.id == record.definitionID }) else {
                throw IncidentMaintenanceError.unknownEventDefinition(record.definitionID.rawValue)
            }
            let elapsed = tick.value - record.startedAt.value
            let afterMinimum = elapsed >= UInt64(definition.duration.minimumTicks)
            let durationExpired = elapsed >= UInt64(record.sampledDurationTicks)
            if afterMinimum && (durationExpired || Self.matches(definition.recoveryRule, input: input, elapsed: elapsed)) {
                record.lifecycle = .recovered
                record.recoveredAt = tick
                state.eventHistory[index] = record
                recovered.append(record)
            }
        }

        let stillActive = Set(state.eventHistory.filter { $0.lifecycle == .active }.map(\.definitionID))
        for definition in definitions {
            guard Self.matches(definition.trigger, tick: tick, input: input) else { continue }
            // Always consume one draw for an eligible definition, including suppressed events,
            // so replay behavior is stable if duplicate suppression rules are unchanged.
            let draw = nextRandom()
            guard !stillActive.contains(definition.id), !activeDefinitionIDs.contains(definition.id),
                  draw % 1_000_000 < UInt64(definition.occurrenceChancePerEligibleTick) else { continue }
            guard state.nextEventSequence < UInt64.max else { throw IncidentMaintenanceError.sequenceOverflow }
            let width = UInt64(definition.duration.maximumTicks - definition.duration.minimumTicks + 1)
            let duration = definition.duration.minimumTicks + Int(nextRandom() % width)
            let record = IncidentEventRecord(
                id: EventInstanceID("\(definition.id.rawValue)#\(state.nextEventSequence)"),
                definitionID: definition.id, kind: definition.kind, impactScope: definition.impactScope,
                effects: definition.effects, startedAt: tick, sampledDurationTicks: duration,
                lifecycle: .active, recoveredAt: nil,
                fictionalResponsePrompt: definition.fictionalResponsePrompt,
                fictionalRecoveryPrompt: definition.fictionalRecoveryPrompt)
            state.nextEventSequence += 1
            state.eventHistory.append(record)
            started.append(record)
        }
        state.simulationTick = tick
        return IncidentTickResult(tick: tick, startedEvents: started, recoveredEvents: recovered,
                                  activeEvents: state.eventHistory.filter { $0.lifecycle == .active })
    }

    public mutating func applyDepotAction(_ action: DepotAction, at tick: GameTick) throws {
        guard tick <= state.simulationTick else {
            throw IncidentMaintenanceError.timeWentBackwards(previous: state.simulationTick, proposed: tick)
        }
        try state.depotRecord.apply(action, at: tick)
    }

    private mutating func nextRandom() -> UInt64 {
        // xorshift64*: compact, fully specified PRNG. State is persisted for exact continuation.
        var x = state.randomState
        x ^= x >> 12
        x ^= x << 25
        x ^= x >> 27
        state.randomState = x
        return x &* 0x2545F4914F6CDD1D
    }

    private static func matches(_ trigger: EventTrigger, tick: GameTick, input: TickInput) -> Bool {
        switch trigger {
        case .manualSignal(let signal): return input.manualSignals.contains(signal)
        case .metricAtLeast(let name, let threshold): return (input.metrics[name] ?? Int.min) >= threshold
        case .eligibleTimeWindow(let from, let through): return tick >= from && tick <= through
        case .all(let rules): return !rules.isEmpty && rules.allSatisfy { matches($0, tick: tick, input: input) }
        case .any(let rules): return !rules.isEmpty && rules.contains { matches($0, tick: tick, input: input) }
        }
    }

    private static func matches(_ rule: RecoveryRule, input: TickInput, elapsed: UInt64) -> Bool {
        switch rule {
        case .elapsedTicks(let ticks): return ticks >= 0 && elapsed >= UInt64(ticks)
        case .actionRequired(let id): return input.recoveryActionIDs.contains(id)
        case .metricAtMost(let name, let threshold): return input.metrics[name].map { $0 <= threshold } ?? false
        case .all(let rules): return !rules.isEmpty && rules.allSatisfy { matches($0, input: input, elapsed: elapsed) }
        case .any(let rules): return !rules.isEmpty && rules.contains { matches($0, input: input, elapsed: elapsed) }
        }
    }

    private static func validateDefinitions(_ definitions: [IncidentEventDefinition]) throws {
        var ids = Set<String>()
        for definition in definitions {
            guard definition.isValid else { throw IncidentMaintenanceError.invalidConfiguration(definition.id.rawValue) }
            guard ids.insert(definition.id.rawValue).inserted else {
                throw IncidentMaintenanceError.duplicateDefinitionID(definition.id.rawValue)
            }
        }
    }

    private static func validate(_ save: IncidentMaintenanceSaveDTO) throws {
        guard save.schemaVersion == 1 else { throw IncidentMaintenanceError.unsupportedSaveVersion(save.schemaVersion) }
        try validateDefinitions(save.eventDefinitions)
        guard save.nextEventSequence > 0 else { throw IncidentMaintenanceError.invalidSave("nextEventSequence must be positive") }
        guard save.depotRecord.vehicleID.isValid, save.depotRecord.depotID.isValid else {
            throw IncidentMaintenanceError.invalidSave("invalid vehicle or depot ID")
        }
        let definitions = Dictionary(uniqueKeysWithValues: save.eventDefinitions.map { ($0.id, $0) })
        var instanceIDs = Set<EventInstanceID>()
        var activeDefinitionIDs = Set<EventDefinitionID>()
        var maxSequence: UInt64 = 0
        guard save.randomState != 0 else { throw IncidentMaintenanceError.invalidSave("zero PRNG state") }
        for record in save.eventHistory {
            guard let definition = definitions[record.definitionID], instanceIDs.insert(record.id).inserted,
                  record.sampledDurationTicks >= definition.duration.minimumTicks,
                  record.sampledDurationTicks <= definition.duration.maximumTicks,
                  record.kind == definition.kind, record.impactScope == definition.impactScope,
                  record.effects == definition.effects,
                  record.fictionalResponsePrompt == definition.fictionalResponsePrompt,
                  record.fictionalRecoveryPrompt == definition.fictionalRecoveryPrompt,
                  record.startedAt <= save.simulationTick else {
                throw IncidentMaintenanceError.invalidSave("invalid event history")
            }
            let prefix = definition.id.rawValue + "#"
            guard record.id.rawValue.hasPrefix(prefix),
                  let sequence = UInt64(String(record.id.rawValue.dropFirst(prefix.count))),
                  sequence > 0, sequence < save.nextEventSequence else {
                throw IncidentMaintenanceError.invalidSave("invalid event instance ID/sequence")
            }
            maxSequence = max(maxSequence, sequence)
            if record.lifecycle == .active {
                guard record.recoveredAt == nil,
                      save.simulationTick.value - record.startedAt.value < UInt64(record.sampledDurationTicks),
                      activeDefinitionIDs.insert(record.definitionID).inserted else {
                    throw IncidentMaintenanceError.invalidSave("invalid or duplicate active event")
                }
            } else {
                guard let recoveredAt = record.recoveredAt,
                      recoveredAt >= record.startedAt, recoveredAt <= save.simulationTick else {
                    throw IncidentMaintenanceError.invalidSave("invalid recovered event time")
                }
            }
        }
        guard save.nextEventSequence > maxSequence else {
            throw IncidentMaintenanceError.invalidSave("event sequence did not advance")
        }
        let depot = save.depotRecord
        guard depot.history.allSatisfy({ $0.tick <= save.simulationTick }) &&
              zip(depot.history, depot.history.dropFirst()).allSatisfy({ pair in pair.0.tick <= pair.1.tick }) &&
              (depot.history.last?.resultingState ?? .stabled) == depot.state &&
              (!depot.history.isEmpty || (depot.activeInspectionStatus == nil && depot.activeMaintenanceStatus == nil)) else {
            throw IncidentMaintenanceError.invalidSave("depot history is later than simulation tick")
        }
    }
}
