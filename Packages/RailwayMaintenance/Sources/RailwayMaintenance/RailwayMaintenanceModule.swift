import Foundation

public struct MaintenanceModuleTickResult: Codable, Equatable, Sendable {
    public let eventResult: MaintenanceTickResult
    public let depotEvents: [DepotOperationEvent]
    public let integrationWarnings: [String]

    public init(eventResult: MaintenanceTickResult, depotEvents: [DepotOperationEvent], integrationWarnings: [String]) {
        self.eventResult = eventResult
        self.depotEvents = depotEvents
        self.integrationWarnings = integrationWarnings
    }
}

/// Top-level adapter for a shared simulation snapshot and the two independent state machines.
public struct RailwayMaintenanceModule: Sendable {
    public private(set) var eventEngine: MaintenanceEventEngine
    public private(set) var depotEngine: DepotOperationEngine

    public init(
        seed: UInt64,
        eventDefinitions: [MaintenanceEventDefinition] = MaintenanceEventCatalog.defaultDefinitions,
        maximumConcurrentEvents: Int = 4,
        depots: [DepotDefinition],
        vehicles: [MaintenanceVehicleRecord],
        depotStoppedSpeedThresholdMps: Double = 0.1,
        depotAccessToleranceM: Double = 5
    ) {
        self.eventEngine = MaintenanceEventEngine(
            seed: seed,
            definitions: eventDefinitions,
            maximumConcurrentEvents: maximumConcurrentEvents
        )
        self.depotEngine = DepotOperationEngine(
            depots: depots,
            vehicles: vehicles,
            stoppedSpeedThresholdMps: depotStoppedSpeedThresholdMps,
            accessToleranceM: depotAccessToleranceM
        )
    }

    public init(
        restoring eventState: MaintenanceEventEngineState,
        depotState: DepotOperationState,
        eventDefinitions: [MaintenanceEventDefinition] = MaintenanceEventCatalog.defaultDefinitions,
        maximumConcurrentEvents: Int = 4,
        depotStoppedSpeedThresholdMps: Double = 0.1,
        depotAccessToleranceM: Double = 5
    ) {
        self.eventEngine = MaintenanceEventEngine(
            restoring: eventState,
            definitions: eventDefinitions,
            maximumConcurrentEvents: maximumConcurrentEvents
        )
        self.depotEngine = DepotOperationEngine(
            restoring: depotState,
            stoppedSpeedThresholdMps: depotStoppedSpeedThresholdMps,
            accessToleranceM: depotAccessToleranceM
        )
    }

    /// One call per host fixed tick. Vehicle fault events are mirrored into matching depot records;
    /// the host consumes the returned modifiers and handles all non-maintenance simulation systems.
    public mutating func step(
        snapshot: MaintenanceSimulationSnapshot,
        eventActions: [MaintenanceEventAction] = []
    ) -> MaintenanceModuleTickResult {
        let eventResult = eventEngine.advance(snapshot: snapshot, actions: eventActions)
        var depotEvents: [DepotOperationEvent] = []
        var warnings: [String] = []
        let knownVehicleIDs = Set(depotEngine.state.vehicles.map(\.id))

        for event in eventResult.startedEvents where event.domain == .rollingStock {
            guard case .train(let vehicleID) = event.scope, knownVehicleIDs.contains(vehicleID) else { continue }
            do {
                let depotEvent = try depotEngine.handle(
                    .recordScenarioFault(vehicleID: vehicleID, eventInstanceID: event.id),
                    at: snapshot.simulationTimeSeconds
                )
                depotEvents.append(depotEvent)
            } catch {
                warnings.append("故障イベント \(event.id) を車両状態へ接続できませんでした: \(error)")
            }
        }
        depotEvents.append(contentsOf: depotEngine.advance(to: snapshot.simulationTimeSeconds))
        return MaintenanceModuleTickResult(
            eventResult: eventResult,
            depotEvents: depotEvents,
            integrationWarnings: warnings
        )
    }

    @discardableResult
    public mutating func startScenario(
        kind: MaintenanceEventKind,
        scope: MaintenanceEventScope,
        snapshot: MaintenanceSimulationSnapshot
    ) throws -> MaintenanceEventInstance {
        let event = try eventEngine.startScenario(kind: kind, scope: scope, snapshot: snapshot)
        if event.domain == .rollingStock,
           case .train(let vehicleID) = event.scope,
           depotEngine.state.vehicles.contains(where: { $0.id == vehicleID }) {
            _ = try depotEngine.handle(
                .recordScenarioFault(vehicleID: vehicleID, eventInstanceID: event.id),
                at: snapshot.simulationTimeSeconds
            )
        }
        return event
    }

    @discardableResult
    public mutating func handleDepotCommand(
        _ command: DepotCommand,
        at simulationTimeSeconds: Double,
        snapshot: MaintenanceSimulationSnapshot? = nil
    ) throws -> DepotOperationEvent {
        try depotEngine.handle(command, at: simulationTimeSeconds, snapshot: snapshot)
    }
}
