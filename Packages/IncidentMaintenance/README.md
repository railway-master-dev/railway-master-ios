# IncidentMaintenance

Independent pure-Swift package for fictional railway-game incidents and depot/maintenance lifecycle state. Targets iOS 17 and macOS 13 and imports only Foundation in its library target. It does not prescribe real operating, emergency, inspection, or repair actions.

> **FICTIONAL GAME CONTENT — NOT REAL RAILWAY PROCEDURE OR SAFETY TRAINING**
>
> This warning is embedded in and enforced for every response/recovery prompt. All effects, ticks, scopes, actions, and state names describe game state only.

## Design

- Stable explicit `EventDefinitionID`, `EventInstanceID`, `VehicleID`, and `DepotID` values; occurrence IDs derive from definition ID and a saved monotonic sequence.
- Declarative manual-signal, metric-threshold, and inclusive eligible-time-window triggers, with `all`/`any` composition. Each eligible fixed tick has a configured parts-per-million chance. Definitions are evaluated in stable ID order.
- A per-engine xorshift64* PRNG, seeded per run and persisted with the next event sequence. A sampled whole-tick duration range varies event duration. Recovery can occur after the sampled minimum when an elapsed/action/metric/game condition matches; otherwise it occurs at the sampled duration boundary.
- Explicit impact scope/effects, active/recovered event history, fixed-tick API, duplicate-active-definition suppression, and validated configuration/restore.
- Depot flow: `stabled → inspectionInProgress → needsMaintenance/ready → maintenanceInProgress → reinspectionRequired → reinspectionInProgress → ready → dispatchable`. Invalid transitions throw. Work status, latest state and full transition history are retained.
- Explicit versioned `IncidentMaintenanceSaveDTO: Codable` plus `exportSave()` and `restore(from:)`, including RNG state and event history so replay can continue deterministically.

## Minimal use

```swift
import IncidentMaintenance

let disclaimer = incidentMaintenanceFictionDisclaimer
let event = IncidentEventDefinition(
    id: EventDefinitionID("scenario.vehicle-event"),
    kind: .vehicleFailure,
    trigger: .all([
        .manualSignal("game.trigger.vehicle-event"),
        .eligibleTimeWindow(from: GameTick(1), through: GameTick(300))
    ]),
    occurrenceChancePerEligibleTick: 250_000,
    duration: EventDurationRange(minimumTicks: 20, maximumTicks: 80),
    impactScope: .vehicle(VehicleID("vehicle-01")),
    effects: GameEffects(serviceDelayTicks: 10, tractionMultiplier: 0.8),
    recoveryRule: .actionRequired("game.clear-event"),
    fictionalResponsePrompt: "\(disclaimer) — Fictional scenario prompt: choose a game response.",
    fictionalRecoveryPrompt: "\(disclaimer) — Fictional scenario prompt: mark the scenario resolved."
)

var engine = try IncidentMaintenanceEngine(
    seed: 42,
    eventDefinitions: [event],
    depotRecord: DepotRecord(vehicleID: VehicleID("vehicle-01"), depotID: DepotID("depot-main"))
)
let firstTick = try engine.advanceOneTick(input: TickInput(manualSignals: ["game.trigger.vehicle-event"]))
let save: IncidentMaintenanceSaveDTO = engine.exportSave()
let restored = try IncidentMaintenanceEngine.restore(from: save)
```

A host should call `advanceOneTick` once per authoritative fixed simulation tick, not once per rendered frame. Send the same stable input tokens and metric snapshot to each run during replay. The package does not read a clock or advance itself.

## Integration contract

1. The host owns authoritative tick cadence and sends `TickInput` on each call. `GameTick(0)` is the initial state; the first call processes tick 1. Do not call the package from a variable-frame update loop.
2. Keep definition IDs and scope IDs stable across save/load and host subsystems. Definitions are embedded in the save DTO. Do not reuse an event definition ID for a different scenario meaning within a save-compatible game version.
3. `IncidentTickResult.startedEvents`, `recoveredEvents`, and `activeEvents` are presentation/game-state outputs. Host code may render or apply the explicit fictional `GameEffects`; it must not treat them as real-world limits or instructions.
4. Response/recovery prose is author-supplied game UI content only. Both strings must contain the exact disclaimer; the initializer remains nonthrowing for Codable ergonomics, while engine initialization rejects invalid definitions.
5. Depot actions must be submitted at or before the current simulation tick. State transitions and history are fictional game bookkeeping and do not constitute real inspections, maintenance, or dispatch clearance.
6. Persist the complete DTO and restore it before advancing. It includes the nonzero PRNG state, next ID sequence, event definitions, active/recovered history and depot lifecycle/history. Keep the schema version and migration policy explicit if the DTO later evolves.
7. The package is deterministic for a given saved state and sequence of inputs. Definition processing is sorted by stable ID; event IDs do not depend on UI order or frame rate.

## Build and tests

```sh
swift test
```

The XCTest suite covers trigger matching, seeded reproducibility/variation, recovery boundaries, explicit scope/effects and stable event IDs, save/restore plus PRNG continuation/Codable, depot flow and invalid transitions, and validation/duplicate suppression.
