import Combine
import Foundation
import RailwayMaintenance

/// Host-owned projection of the shared fictional simulation state consumed by maintenance gameplay.
/// IDs and units must match the host route/traffic model (metres, m/s, simulation seconds).
struct MaintenanceGameplayHostInput: Equatable {
    let routeID: String
    let routeLengthM: Double
    let simulationTimeSeconds: Double
    let fixedTick: UInt64
    let fixedTimeStepSeconds: Double
    let trackIDs: [String]
    let stationIDs: [String]
    let trains: [MaintenanceTrainSnapshot]
    let crossings: [MaintenanceCrossingSnapshot]
    let weather: MaintenanceWeatherSnapshot
    let scenarioFlags: Set<String>

    init(
        routeID: String,
        routeLengthM: Double,
        simulationTimeSeconds: Double,
        fixedTick: UInt64,
        fixedTimeStepSeconds: Double,
        trackIDs: [String],
        stationIDs: [String] = [],
        trains: [MaintenanceTrainSnapshot],
        crossings: [MaintenanceCrossingSnapshot] = [],
        weather: MaintenanceWeatherSnapshot = .clear,
        scenarioFlags: Set<String> = []
    ) {
        self.routeID = routeID
        self.routeLengthM = routeLengthM
        self.simulationTimeSeconds = simulationTimeSeconds
        self.fixedTick = fixedTick
        self.fixedTimeStepSeconds = fixedTimeStepSeconds
        self.trackIDs = trackIDs
        self.stationIDs = stationIDs
        self.trains = trains
        self.crossings = crossings
        self.weather = weather
        self.scenarioFlags = scenarioFlags
    }

    init(snapshot: MaintenanceSimulationSnapshot) {
        self.init(
            routeID: snapshot.routeID,
            routeLengthM: snapshot.routeLengthM,
            simulationTimeSeconds: snapshot.simulationTimeSeconds,
            fixedTick: snapshot.fixedTick,
            fixedTimeStepSeconds: snapshot.fixedTimeStepSeconds,
            trackIDs: snapshot.trackIDs,
            stationIDs: snapshot.stationIDs,
            trains: snapshot.trains,
            crossings: snapshot.crossings,
            weather: snapshot.weather,
            scenarioFlags: snapshot.scenarioFlags
        )
    }

    var snapshot: MaintenanceSimulationSnapshot {
        MaintenanceSimulationSnapshot(
            routeID: routeID,
            routeLengthM: routeLengthM,
            simulationTimeSeconds: simulationTimeSeconds,
            fixedTick: fixedTick,
            fixedTimeStepSeconds: fixedTimeStepSeconds,
            trackIDs: trackIDs,
            stationIDs: stationIDs,
            trains: trains,
            crossings: crossings,
            weather: weather,
            scenarioFlags: scenarioFlags
        )
    }
}

/// UI-facing, single-owner facade. All engine mutation stays on the main actor; fixed ticks are
/// accepted once and only once in increasing tick order, never from a SwiftUI render callback.
@MainActor
final class MaintenanceGameplayCoordinator: ObservableObject {
    @Published private var module: RailwayMaintenanceModule
    @Published private(set) var hostInput: MaintenanceGameplayHostInput
    @Published private(set) var latestTickResult: MaintenanceModuleTickResult?
    @Published private(set) var latestDepotEvents: [DepotOperationEvent] = []
    @Published private(set) var message: String?

    private var lastProcessedFixedTick: UInt64?
    private var queuedActions: [MaintenanceEventAction] = []

    var eventState: MaintenanceEventEngineState { module.eventEngine.state }
    var depotState: DepotOperationState { module.depotEngine.state }
    var currentSnapshot: MaintenanceSimulationSnapshot { hostInput.snapshot }
    var activeEvents: [MaintenanceEventInstance] { eventState.activeEvents.sorted { $0.startedAtSeconds > $1.startedAtSeconds } }

    init(
        seed: UInt64,
        depots: [DepotDefinition],
        vehicles: [MaintenanceVehicleRecord],
        hostInput: MaintenanceGameplayHostInput,
        eventDefinitions: [MaintenanceEventDefinition] = MaintenanceEventCatalog.defaultDefinitions,
        maximumConcurrentEvents: Int = 4
    ) {
        self.module = RailwayMaintenanceModule(
            seed: seed,
            eventDefinitions: eventDefinitions,
            maximumConcurrentEvents: maximumConcurrentEvents,
            depots: depots,
            vehicles: vehicles
        )
        self.hostInput = hostInput
    }

    /// Call exactly once from the host's fixed simulation update, passing one immutable shared-state projection.
    /// Duplicate or out-of-order ticks are ignored to prevent accidental render-rate advancement.
    @discardableResult
    func advanceFixedTick(
        with input: MaintenanceGameplayHostInput,
        eventActions: [MaintenanceEventAction] = []
    ) -> MaintenanceModuleTickResult? {
        if let lastProcessedFixedTick {
            guard lastProcessedFixedTick < UInt64.max,
                  input.fixedTick == lastProcessedFixedTick + 1 else {
                message = "固定tick \(input.fixedTick) は次に必要なtick \(lastProcessedFixedTick &+ 1) ではないため処理しませんでした。"
                return nil
            }
        }
        hostInput = input
        let result = module.step(snapshot: input.snapshot, eventActions: queuedActions + eventActions)
        queuedActions.removeAll(keepingCapacity: true)
        latestTickResult = result
        latestDepotEvents = result.depotEvents
        lastProcessedFixedTick = input.fixedTick
        message = nil
        return result
    }

    /// Adds a player-selected recovery action. The event engine records it on the next fixed tick;
    /// time/weather requirements in the same recovery rule still have to be satisfied.
    func chooseRecoveryAction(eventInstanceID: String, actionID: String) {
        guard !actionID.isEmpty,
              eventState.events.contains(where: { $0.id == eventInstanceID && $0.status == .active }) else {
            message = "対応対象のイベントが見つからないか、すでに復旧しています。"
            return
        }
        guard !queuedActions.contains(where: { $0.eventInstanceID == eventInstanceID && $0.actionID == actionID }) else {
            message = "この対応は次の固定tickに登録済みです。"
            return
        }
        queuedActions.append(MaintenanceEventAction(eventInstanceID: eventInstanceID, actionID: actionID))
        message = "ゲーム内対応を次の固定tickへ登録しました。時間・天候条件も満たすと復旧します。"
    }

    @discardableResult
    func startScenario(kind: MaintenanceEventKind, scope: MaintenanceEventScope) -> MaintenanceEventInstance? {
        do {
            let event = try module.startScenario(kind: kind, scope: scope, snapshot: currentSnapshot)
            message = "固定シナリオ「\(kind.rawValue)」を開始しました。"
            return event
        } catch {
            message = "シナリオを開始できませんでした: \(error)"
            return nil
        }
    }

    @discardableResult
    func performDepotCommand(_ command: DepotCommand) -> DepotOperationEvent? {
        do {
            let event = try module.handleDepotCommand(
                command,
                at: hostInput.simulationTimeSeconds,
                snapshot: currentSnapshot
            )
            latestDepotEvents = [event]
            message = "基地ゲーム操作を登録しました: \(event.kind.rawValue)"
            return event
        } catch {
            message = "基地ゲーム操作を実行できませんでした: \(error)"
            return nil
        }
    }

    /// Convenience only for the self-contained fictional sheet preview; a live host should supply its own ticks.
    @discardableResult
    func advanceFictionalPreviewOneTick() -> MaintenanceModuleTickResult? {
        let snapshot = currentSnapshot
        let next = MaintenanceGameplayHostInput(
            routeID: snapshot.routeID,
            routeLengthM: snapshot.routeLengthM,
            simulationTimeSeconds: snapshot.simulationTimeSeconds + snapshot.fixedTimeStepSeconds,
            fixedTick: snapshot.fixedTick &+ 1,
            fixedTimeStepSeconds: snapshot.fixedTimeStepSeconds,
            trackIDs: snapshot.trackIDs,
            stationIDs: snapshot.stationIDs,
            trains: snapshot.trains,
            crossings: snapshot.crossings,
            weather: snapshot.weather,
            scenarioFlags: snapshot.scenarioFlags
        )
        return advanceFixedTick(with: next)
    }

    /// Deterministic, fictional fixture for previewing the screen without coupling it to a live route.
    static func fictionalPreview() -> MaintenanceGameplayCoordinator {
        let routeID = "gameplay-preview-route"
        let trainID = "PREVIEW-TRAIN-01"
        let trackID = "preview-main-track"
        let snapshot = MaintenanceGameplayHostInput(
            routeID: routeID,
            routeLengthM: 5_000,
            simulationTimeSeconds: 0,
            fixedTick: 0,
            fixedTimeStepSeconds: 1,
            trackIDs: [trackID],
            stationIDs: ["preview-origin", "preview-terminal"],
            trains: [MaintenanceTrainSnapshot(
                trainID: trainID,
                trackID: trackID,
                positionM: 0,
                speedMps: 0,
                direction: .increasingChainage,
                lengthM: 80,
                stationID: "preview-origin"
            )],
            crossings: [MaintenanceCrossingSnapshot(crossingID: "preview-crossing", trackID: trackID, chainageM: 1_200)]
        )
        let depot = DepotDefinition(
            id: "preview-depot",
            routeID: routeID,
            accessTrackID: trackID,
            accessChainageM: 0,
            entryTransferDurationSeconds: 3,
            exitTransferDurationSeconds: 3,
            tracks: [DepotTrackDefinition(id: "preview-yard-track", capacity: 4)]
        )
        let vehicle = MaintenanceVehicleRecord(
            id: trainID,
            profileID: "fictional-preview-profile",
            lengthM: 80,
            location: .onRoute(trackID: trackID, chainageM: 0)
        )
        return MaintenanceGameplayCoordinator(seed: 42, depots: [depot], vehicles: [vehicle], hostInput: snapshot)
    }
}
