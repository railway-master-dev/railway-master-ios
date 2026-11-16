import Combine
import CrewWorkflow
import DoorProcedureScoring
import IncidentMaintenance
import EnvironmentConditions
import Foundation
import RailwayMaintenance
import RailwayGameModes
import RailwayOperations
import RailwayAudioEnhancements
import RailwayRendering
import RailwayRouteData
import RailwaySessionPersistence
import RailwayTimetable
import StopScoring
import TrafficSimulation
import TrainPhysics
import ProtectionSystems
import RailwaySceneFidelity

/// A single immutable view of the fictional simulation's operational state.
/// Every railway-system status here is for gameplay/education, not real railway operation.
struct SimulatorOperationsSnapshot: Equatable, Sendable {
    let signalReading: BlockSignalReading?
    let signalDistanceM: Double?
    let permittedSpeedKmh: Double
    let otherTrains: [ScheduleTrainState]
    let atsStatus: EducationalATSStatus?
    let automaticBrakeActive: Bool
    let automaticBrakeReason: String?
    let label: OperationsSystemLabel
}

enum SimulationRunPhase: String, Sendable {
    case running
    case arrived
    case overshot
}

/// Passing waits （待避）, 2026-11-11 (user request): at the three
/// multi-track stations a low-priority train (rapid / semi-express /
/// local) pulls into the outer siding platform and waits while a
/// faster train passes on the main line. Priorities follow the
/// service hierarchy (fewer stops = higher priority). The siding
/// runs outside the station platform (its outer face serves the
/// siding), 9.64 m from the route centre; the player crosses the
/// turnout fans at 45 km/h under a caution home signal （場内・注意）.
enum PassingWaitPlanner {
    /// The loop-equipped stations: 東央千原 (major 5-track),
    /// 東央佐原 and 木更川 (passing 3-track layouts) plus 秋水・
    /// 日原・上総二ノ宮・大野, added 2026-11-11 when the user
    /// approved building the diagram properly — the loops are
    /// spaced along the whole line so an overtake can always be
    /// absorbed nearby. （西立河 was the other candidate for the
    /// western gap, but its throat sits inside the tunnel section,
    /// so 日原 carries that slot.)
    static let stationIDs: Set<String> = ["S03", "S04", "S06", "S07", "S09", "S11", "S12", "S14", "S15", "S17", "S19", "S22", "S23", "S24", "S27"]
    /// Platform half length (105 m) plus the 340 m turnout fan.
    static let sidingHalfSpanM = 445.0
    /// Diverging speed over the turnout fans (12号分岐の目安).
    static let turnoutLimitKmh = 45.0

    static func priority(of category: ServiceCategory) -> Int {
        switch category {
        case .limitedExpress: return 0
        case .rapidExpress: return 1
        case .express: return 2
        case .rapid: return 3
        case .semiExpress: return 4
        case .local: return 5
        }
    }

    static func priority(of type: TrainServiceType) -> Int {
        switch type {
        case .limitedExpress: return 0
        case .rapidExpress: return 1
        case .express: return 2
        case .rapid: return 3
        case .semiExpress: return 4
        case .local: return 5
        }
    }

    /// Only the lower-priority services wait, and only for a
    /// strictly faster passer.
    static func shouldRoute(player: ServiceCategory, passer: TrainServiceType) -> Bool {
        priority(of: player) >= 3 && priority(of: passer) < priority(of: player)
    }
}

@MainActor
final class SimulatorModel: ObservableObject {
    private static let blockLengthM = 500.0
    private static let safetyMarginM = 18.0
    private static let arrivalToleranceM = 4.0
    private static let overshootToleranceM = 12.0
    private static let requiredArrivalDwellSeconds = 2.0

    @Published private(set) var train: TrainParameters
    @Published private(set) var route: RailwayRouteProfile
    @Published private(set) var routeVariant: RegionalRouteVariant = .throughBranch
    @Published private(set) var serviceCategory: ServiceCategory = .local
    @Published private(set) var travelDirection: RegionalTravelDirection = .up
    @Published private(set) var routeID: String = "fictional-throughBranch-local-up"
    @Published private(set) var activeStops: [RegionalRouteStop] = []
    @Published private(set) var stopScoringEvaluation: StopScoring.JourneyEvaluation?
    @Published private(set) var stopScoringError: String?
    @Published private(set) var doorProcedureEvaluation: DoorProcedureScoring.JourneyScoringEvaluation?
    @Published private(set) var doorProcedureScoringError: String?
    @Published private(set) var nextStopIndex: Int = 1
    @Published private(set) var trafficSnapshot: TrafficSnapshot?
    @Published private(set) var selectedVehicleProfile: FictionalVehicleProfile = .fieldChopperDC
    @Published private(set) var selectedSoundProfile: RailwayTractionSoundProfile = .fieldChopperDC
    @Published private(set) var environmentSelection: EnvironmentQualitySelection = .default
    @Published private(set) var trainingMode: TrainingMode = .standard
    @Published private(set) var operationsGameplayCoordinator: OperationsGameplayCoordinator?
    @Published private(set) var maintenanceGameplayCoordinator: MaintenanceGameplayCoordinator?
    @Published private(set) var maintenanceWarning: String?
    @Published private(set) var crewWorkflow = CrewWorkflow()
    @Published private(set) var incidentMaintenanceEngine: IncidentMaintenanceEngine?
    @Published private(set) var incidentTickResult: IncidentTickResult?
    @Published private(set) var incidentNotice: String?
    @Published private(set) var announcementLocale: AnnouncementLocale = .japanese

    @Published private(set) var controls = TrainControls()
    @Published private(set) var weather: WeatherCondition = .dry
    @Published private(set) var telemetry: TrainTelemetry
    @Published private(set) var trainPhysicsTelemetry: TrainPhysics.TrainPhysicsTelemetry
    @Published private(set) var stoppingDistanceEstimate: TrainPhysics.StoppingDistanceEstimate?
    @Published private(set) var timetableCalendar: RailwayTimetable.ServiceCalendar = .weekday
    @Published private(set) var timetableDaypart: RailwayTimetable.Daypart = .morningRush
    @Published private(set) var timetableInitialDelayMinutes = 0
    @Published private(set) var timetableSelection: RegionalTimetableSelection?
    @Published private(set) var timetableSelectionError: String?
    @Published private(set) var timetableSettingsPendingRestart = false
    @Published private(set) var isPaused = false
    @Published private(set) var simulationTime: Double = 0
    @Published private(set) var operationsSnapshot: SimulatorOperationsSnapshot?
    @Published private(set) var runPhase: SimulationRunPhase = .running
    @Published private(set) var completedSummary: DrivingSessionSummary?
    @Published private(set) var completedReview: PostRunReview?
    @Published private(set) var latestSessionURL: URL?
    @Published private(set) var storageNotice: String?
    /// batch71: staged progress reports from inside selectRoute
    /// (percent, status). ContentView wires this into the loading
    /// screen's progress flow so the route-application and
    /// scenario-reset stages — previously invisible synchronous
    /// work before the loading screen could appear — report the
    /// first few percent. Nil in tests and demo launches, where
    /// the reports are simply skipped.
    var routeApplyProgressHandler: ((Int, String) -> Void)?
    @Published private(set) var dataValidationIssues: [RouteDataIssue] = []
    @Published private(set) var gameModeSession: GameModeSession?
    @Published private(set) var gameModeHostNotice: String?
    @Published private(set) var gameModeDoorState: GameModeDoorState = .closed
    /// batch108: door interlock condition — the doors are not
    /// fully closed (open, or a chime-timed closure is still
    /// pending and the doors have not landed yet). While this
    /// holds, the physics tick and the audio snapshot both see
    /// an interlocked command (see simulationTick / advance).
    private var doorInterlockActive: Bool {
        gameModeDoorState != .closed || pendingDoorClose != nil
    }
    @Published private(set) var saveSlots: [SaveSlotSummary] = []

    var gameModeContext: RegionalGameModeContext {
        let promptIDs: Set<String> = blockSystem.blocks.isEmpty || atsSystem == nil
            ? []
            : ["PLACEHOLDER-training-signal-display", "PLACEHOLDER-training-protection-display"]
        return RegionalGameModeContext(
            routeID: routeID,
            route: route,
            stops: activeStops,
            variant: routeVariant,
            originTargetM: stopScoringOriginTargetM ?? 0,
            timetableByStationID: RegionalGameModeContext.timetableEvents(
                from: timetableSelection,
                activeStops: activeStops
            ),
            trains: makeRegionalGameModeTrainStates(),
            availableTrainingPromptIDs: promptIDs
        )
    }

    /// The reading the lineside signal ahead should display, with the
    /// block start chainage where that signal stands. The 3D scene uses
    /// this to light the matching trackside signal.
    var tracksideSignalReading: BlockSignalReading? {
        latestOperationsSnapshot?.signalReading
    }

    var gameModeSnapshot: GameModeSimulationSnapshot? {
        guard !activeStops.isEmpty else { return nil }
        let context = gameModeContext
        let readings = engine.telemetry
        let projected = TrainPhysicsProfileAdapter.projectTelemetry(
            readings,
            engine: engine,
            route: route,
            stoppingDistance: stoppingDistanceEstimate
        )
        // Frame unification (follow-up to batch74): the game-mode
        // layer shares the physics route frame — no offset is
        // applied here. Every scenario stop plan is a front stop
        // target in this frame (batch74), and the origin stop
        // plan carries the origin target itself
        // (RegionalGameModeAdapter.makeStopPlans), so the
        // full-line origin check compares the snapshot position
        // against that anchor instead of ~0. batch60's
        // −originStartPositionM shift made the snapshot agree
        // with the origin check while stop plans sat at station
        // centres, but once batch74 moved the plans to stop
        // targets the shift left every finish gate short by
        // exactly the origin target (up to 195 m): a correctly
        // driven full run could never complete a session.
        // Only positionM / speedMps / accelerationMps2 /
        // passengerLoadFactor flow into the game snapshot; the
        // published telemetry and the scene keep the raw
        // leading-end chainage.
        let gameTelemetry = TrainTelemetry(
            positionM: projected.positionM,
            speedMps: projected.speedMps,
            accelerationMps2: projected.accelerationMps2,
            tractionForceN: projected.tractionForceN,
            brakingForceN: projected.brakingForceN,
            regenerativeBrakeForceN: projected.regenerativeBrakeForceN,
            airBrakeForceN: projected.airBrakeForceN,
            rollingResistanceN: projected.rollingResistanceN,
            gradientForceN: projected.gradientForceN,
            curveResistanceN: projected.curveResistanceN,
            appliedBrakeFraction: projected.appliedBrakeFraction,
            brakePipePressureKPa: projected.brakePipePressureKPa,
            brakeCylinderPressureKPa: projected.brakeCylinderPressureKPa,
            mainReservoirPressureKPa: projected.mainReservoirPressureKPa,
            effectiveMassKg: projected.effectiveMassKg,
            passengerLoadFactor: projected.passengerLoadFactor,
            currentGradientPermille: projected.currentGradientPermille,
            currentCantMm: projected.currentCantMm,
            lateralAccelerationMps2: projected.lateralAccelerationMps2,
            currentSpeedLimitKmh: projected.currentSpeedLimitKmh,
            distanceToStopMarkerM: projected.distanceToStopMarkerM,
            predictedStoppingDistanceM: projected.predictedStoppingDistanceM,
            isStoppedAtMarker: projected.isStoppedAtMarker,
            isWheelSlipActive: projected.isWheelSlipActive,
            isBrakeSlipActive: projected.isBrakeSlipActive
        )
        let promptID: String?
        if let aspect = latestOperationsSnapshot?.signalReading?.aspect {
            promptID = aspect == .green
                ? "PLACEHOLDER-training-protection-display"
                : "PLACEHOLDER-training-signal-display"
        } else {
            promptID = nil
        }
        let event = pendingGameModeStationEvent
        let stationID = event?.stationID ?? (engine.speedMps <= 0.1 ? gameModeCurrentStationID : nil)
        return try? RegionalGameModeAdapter.makeSimulationSnapshot(
            context: context,
            telemetry: gameTelemetry,
            simulationTimeSeconds: simulationTime,
            fixedTick: UInt64(max(0, (simulationTime / TrainPhysics.PhysicsConstants.fixedTimeStepSeconds).rounded())),
            speedLimitKmh: latestOperationsSnapshot?.permittedSpeedKmh ?? route.condition(at: engine.positionM).speedLimitKmh,
            doors: gameModeDoorState,
            nativeStationID: stationID,
            stationEvent: event?.event,
            visibleLandmarkID: gameModeVisibleLandmarkID(),
            trainingPromptID: promptID,
            vehicleID: selectedVehicleProfile.physicsProfileIdentifier,
            weather: weather,
            timeOfDayID: environmentSelection.environment.dayPeriod.rawValue,
            seasonID: environmentSelection.environment.season.rawValue,
            trains: context.trains
        )
    }

    var timetableDepartureRemainingSeconds: Double {
        // batch65: 初発ホールドは完全撤廃。ダイヤ遅延
        // （appliedTimetableDepartureDelaySeconds）は停車評価と
        // 保存・復元のためだけに保持し、操作系と HUD の待ち時間
        // 表示には一切影響させない。プレイヤーはドアを閉めれば
        // 即出発できるため、このプロパティは常に 0 を返す。
        0
    }

    var incidentTick: GameTick { incidentMaintenanceEngine?.state.simulationTick ?? GameTick(0) }
    var incidentDepotRecord: DepotRecord? { incidentMaintenanceEngine?.state.depotRecord }
    var activeIncidentEvents: [IncidentEventRecord] {
        incidentMaintenanceEngine?.state.eventHistory.filter { $0.lifecycle == .active } ?? []
    }

    private var activeIncidentEffects: IncidentMaintenance.GameEffects {
        let events = activeIncidentEvents.filter { record in
            switch record.impactScope {
            case .vehicle(let id): return id.rawValue == "PLAYER"
            case .route(let id): return id == routeID
            case .network: return true
            case .station, .track: return false
            }
        }
        return IncidentMaintenance.GameEffects(
            serviceDelayTicks: events.reduce(0) { min(1_000_000, $0 + $1.effects.serviceDelayTicks) },
            tractionMultiplier: events.reduce(1) { $0 * $1.effects.tractionMultiplier },
            brakingMultiplier: events.reduce(1) { $0 * $1.effects.brakingMultiplier },
            speedMultiplier: events.reduce(1) { $0 * $1.effects.speedMultiplier },
            departureHeld: events.contains { $0.effects.departureHeld }
        )
    }

    private var engine: TrainPhysics.TrainPhysicsEngine
    private var blockSystem: ThreeAspectBlockSystem
    private var scheduleEngine: RailwayScheduleEngine?
    private var regionalPlan: FictionalOperationsPlan?
    private var canonicalRoutePackage: RailwayRouteData.RoutePackage?
    private var timetableNetwork: RailwayTimetable.TimetableNetwork?
    /// batch93: one-entry memos for two deterministic rebuilds
    /// that a single session build used to repeat for identical
    /// inputs (see factoryTrip and makeTimetableSelection).
    private var memoizedFactoryTrip: RegionalPlayableRoute?
    private var memoizedFactoryTripKey: String?
    private var memoizedTimetableSelection: RegionalTimetableSelection?
    private var memoizedTimetableSelectionKey: String?
    private var appliedTimetableDepartureDelaySeconds = 0
    private var trafficEngine: TrafficSimulationEngine?
    /// batch105: lazy traffic-engine build failure latch, keyed
    /// on the scenario generation. The build is deterministic
    /// per scenario (TrafficSimulationEngine.init only validates
    /// the immutable scenario value, and a failed init throws
    /// before it can advance the generation), so a failure can
    /// never succeed on a retry against the same generation.
    /// Every scenario assignment advances
    /// TrafficScenarioGeneration (init / reset / restore — the
    /// same obligation the pose caches already rely on), which
    /// is exactly when a retry becomes meaningful again; a
    /// future assignment site must advance it too, or this
    /// latch (like the pose caches) would keep the old
    /// scenario's verdict.
    private var trafficBuildFailedGeneration: UInt64?
    private var trafficBuildLastFailureTick: UInt64 = 0
    private var trafficBuildFailureCount = 0
    /// batch119: the advance catch below can fire on every
    /// traffic advance for a whole session; the pulled log
    /// gets the failure once per engine, not once per tick.
    private var trafficAdvanceFailureLogged = false
    // batch51 (2026-11-14): private(set) so ContentView can hand
    // THIS assembled scenario (diagram v4 + branch shuttles +
    // depot movements + the tour meet train) to the scene. Until
    // batch51 ContentView fed the scene its own bundled
    // placeholder scenario instead, so every engine actor failed
    // the scene's plan lookup and no AI train ever rendered.
    private(set) var trafficScenario: TrafficScenario?
    /// Active passing wait: the player is routed to the siding at
    /// `stationCenterM` (travel frame) until the passer clears.
    private struct PassingWaitState {
        let stationID: String
        let stationCenterM: Double
        let stationPathM: Double
        let passerID: String
        let passerType: TrainServiceType
        let latchedAtSeconds: Double
    }
    private var passingWait: PassingWaitState?
    @Published private(set) var passingWaitMessage: String?
    private var maintenanceEffects = MaintenanceTrainEffects.neutral(trainID: "PLAYER")
    private var atsSystem: EducationalATSConfirmation?
    private var protectionSession: FictionalLiveProtectionSession?
    private var protectionTick: UInt64 = 0
    private var protectionActivityPulse = false
    private var protectionAcknowledge = false
    private var protectionReset = false
    @Published private(set) var appliedDrivingControls = TrainControls()
    @Published private(set) var protectionActingSystems: [String] = []
    private var lastProtectionActingSystems = Set<String>()
    private var lastATSSAwaiting = false
    private var lastExceededPattern = false
    /// batch67: 速度パターン超過の段階動作（警告→確認猶予→制動）。
    /// 従来は超過した tick に即 B7 が入っていた。猶予秒数は教材ATS
    /// （EducationalATSConfirmation）の確認期限 5 秒に揃える
    /// （init で acknowledgementTimeoutSeconds: 5 を渡している
    /// 本プロジェクト既存の設計値）。
    private static let atsPatternGraceSeconds: Double = 5
    private var patternWarningStartTime: Double?
    private var patternWarningAcknowledged = false
    private var patternBrakeActive = false
    private var patternBrakeEmergency = false
    /// batch67: ATS警報ベルの次回再生時刻（simulationTime）。
    /// 警報需要が続く間、updateAudio がこの周期でベルを回す。
    private var atsBellNextRingTime: Double = 0
    /// batch67: 発車メロディを停車ごとに1回だけ鳴らすための記録。
    private var departureBellPlayedForCurrentStop = false
    private var playedChopperStartBuzzer = false
    private var stationPatternAlarmStopID: String?
    private var doorWarningStopID: String?

    /// A door closure held back until the recorded door chime has finished
    /// (resistance-control stock: chime first, then the doors move).
    private struct PendingDoorClose {
        let state: GameModeDoorState
        let applyAt: Double
    }
    private var pendingDoorClose: PendingDoorClose?
    private var trackImpactTracker = FictionalTrackImpactTracker(carCount: 6)
    private var lastCrossingLandmarkID: String?
    private var lastBridgeLandmarkID: String?
    private var audioOnBridge = false
    private var audioOnPoints = false
    private var audioOnJointedRail = false
    /// batch78: armed by reset() (a new drive session) and
    /// consumed by the first live advance() frame, which plays
    /// the key + reverser cues once. Snapshot restore never
    /// calls reset(), so it never re-arms; pause/resume cannot
    /// re-fire because the flag is already consumed.
    private var sessionStartCuesArmed = false
    /// batch63: コンプレッサー実録音の簡易トリガー用状態
    /// （updateCompressorSound 参照）。時刻はすべて simulationTime。
    private var lastCompressorStartTime: Double = -1_000
    private var compressorSoundEndsAt: Double = 0
    private var lastBrakeReleaseOrDoorEventTime: Double = -1_000
    private var previousAudioDoorsOpen = false
    private var previousAudioBrakeCommand: Double = 0
    @Published private(set) var protectionNeedsAcknowledgement = false
    private var recorder: DrivingSessionRecorder
    private var latestOperationsSnapshot: SimulatorOperationsSnapshot?
    private let audio = RailwayAudioEngine.shared
    private var lastFrameTime: TimeInterval?
    private var fixedStepAccumulator = 0.0
    private var arrivalDwellSeconds = 0.0
    private var stopScoringEngine: StopScoring.StopScoringEngine?
    /// batch60: adjusted origin-platform target from the latest
    /// stop-scoring preparation; reset() places the train there.
    private var stopScoringOriginTargetM: Double?
    /// batch60: the chainage reset() placed the train at for the
    /// current run (0 when no adjusted origin target exists).
    /// "Has not departed yet" checks compare against this instead
    /// of assuming a run always starts at chainage 0.
    private var originStartPositionM: Double = 0
    private var scoringStationID: String?
    private var pendingScoringDepartureStationID: String?
    private var stopScoringTickSequence = 0
    private var stopScoringEventSequence = 0
    private var pendingStopScoringEvents: [StopScoring.StationEvent] = []
    private var doorProcedureScoringEngine: DoorProcedureScoring.DoorProcedureScoringEngine?
    private var doorProcedureEventSequence = 0
    private var gameModeCurrentStationID: String?
    private var pendingGameModeStationEvent: (stationID: String, event: GameModeStationEvent)?
    private var lastATSProtectedBlockID: String?
    private var pendingConfirmations: [DriveConfirmation] = []
    private var pendingIncidentManualSignals: Set<String> = []
    private var pendingIncidentRecoveryActionIDs: Set<String> = []
    private var audioEventScheduler = AudioEventScheduler(startTime: 0)
    private var audioEventSequence: UInt64 = 0
    private var automaticAnnouncedStopIDs: Set<String> = []
    private let saveStore: FileSaveStore?
    @Published private(set) var audioEnabled = true
    @Published private(set) var audioVolume = 0.65

    init() {
        // Screenshot verification of the rebuilt cab (CI only): the
        // -RMCabView launch argument starts the app in the cab view
        // instead of the default forward view.
        if ProcessInfo.processInfo.arguments.contains("-RMCabView") {
            environmentSelection = EnvironmentQualitySelection(
                environment: .clearDay,
                cameraPreset: .cab,
                renderQuality: .medium,
                timeOfDayHours: 12
            )
        }
        let supportDirectory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        saveStore = try? FileSaveStore(
            directoryURL: supportDirectory.appendingPathComponent("RailwayMaster/SessionSaves", isDirectory: true)
        )
        let profile = FictionalVehicleProfile.fieldChopperDC
        let loadedTrain = profile.makeParameters()
        let loadedPhysics = TrainPhysicsProfileAdapter.makeEngine(for: profile, passengerLoadFactor: 0.7)
        let plan = FictionalOperationsPlan.loadBundled()
        let routePackage = try? RailwayRouteData.RoutePackageLoader.loadResource(named: "fictional_70km_network")
        let trip = plan.flatMap { try? RegionalRouteFactory.make(plan: $0, variant: .throughBranch, category: .local, direction: .up) }
        // batch93: loadRoute() decodes the 110 KB legacy mainline
        // package and validates it, yet every consumer below
        // takes the trip branch whenever the factory trip exists
        // — the loaded route only ever feeds the trip == nil
        // fallback. Build it only on that fallback path.
        let initialProfile: RailwayRouteProfile
        let initialIssues: [RouteDataIssue]
        if let trip {
            initialProfile = trip.profile
            initialIssues = trip.profile.validateData()
        } else {
            let loadedRoute = Self.loadRoute()
            initialProfile = loadedRoute.profile
            initialIssues = loadedRoute.issues
        }
        train = loadedTrain
        selectedVehicleProfile = profile
        selectedSoundProfile = profile.soundProfile
        route = initialProfile
        routeID = trip?.routeID ?? "fictional-legacy-route"
        regionalPlan = plan
        canonicalRoutePackage = routePackage
        timetableNetwork = try? RegionalTimetableAdapter.loadCanonicalNetwork()
        activeStops = trip?.stops ?? [
            RegionalRouteStop(stationID: "LEGACY_START", name: initialProfile.departureStation, positionM: 0, trackID: "main-up"),
            RegionalRouteStop(stationID: "LEGACY_END", name: initialProfile.arrivalStation, positionM: initialProfile.stopMarkerM, trackID: "main-up")
        ]
        engine = loadedPhysics
        blockSystem = Self.makeBlocks(route: initialProfile)
        scheduleEngine = Self.makeSchedule(route: initialProfile, train: loadedTrain, blocks: blockSystem)
        trafficScenario = Self.makeTrafficScenario()
        // batch64: scenario (re)installed — advance the
        // generation the pose caches key on.
        TrafficScenarioGeneration.advance()
        // batch93: the traffic ENGINE (scenario validation over
        // all 798 trains plus the runtime maps) and its first
        // snapshot are still built here for demo-drive launches,
        // which drive the default working without a route
        // selection. A normal launch discards both at the first
        // selectRoute → reset() rebuild, and nothing reads
        // trafficSnapshot before the first advance, so a normal
        // launch defers the engine to the first traffic advance
        // (see advanceTrafficAtCurrentTick); reset() keeps
        // building it eagerly exactly as before. (The argument
        // is read directly here — self, and with it the
        // demoDriveEnabled computed property, is not available
        // until every stored property has a value.)
        if ProcessInfo.processInfo.arguments.contains("-RMDemoDrive") {
            trafficEngine = trafficScenario.flatMap(Self.makeTrafficEngine(from:))
            trafficSnapshot = trafficEngine?.snapshot()
            // batch101: a demo launch builds the engine eagerly,
            // so surface a failed build here (the lazy path in
            // advanceTrafficAtCurrentTick covers normal launches).
            // Before this, a scenario that failed to load or to
            // validate left the game with no AI trains and no
            // message anywhere — the exact silent failure behind
            // the user's repeated "no oncoming trains" reports.
            if trafficScenario == nil {
                storageNotice = "架空交通シナリオを読み込めなかったため、AI列車なしで運転を継続します。"
            } else if trafficEngine == nil {
                storageNotice = "架空交通AIを初期化できなかったため、AI列車なしで運転を継続します。"
            }
        }
        atsSystem = try? EducationalATSConfirmation(acknowledgementTimeoutSeconds: 5)
        recorder = DrivingSessionRecorder(metadata: Self.makeSessionMetadata(route: initialProfile))
        trainPhysicsTelemetry = loadedPhysics.telemetry
        stoppingDistanceEstimate = nil
        telemetry = TrainPhysicsProfileAdapter.projectTelemetry(
            loadedPhysics.telemetry,
            engine: loadedPhysics,
            route: initialProfile,
            stoppingDistance: nil
        )
        dataValidationIssues = initialIssues
        // batch93: prime the factory-trip memo with the trip
        // just built, so the rebuildStopScoringSession below
        // reuses it instead of regenerating the same route.
        if let trip {
            memoizedFactoryTrip = trip
            memoizedFactoryTripKey = Self.factoryTripKey(variant: .throughBranch, category: .local, direction: .up)
        }
        rebuildProtectionSession()
        rebuildStopScoringSession()
        rebuildDoorProcedureScoringSession()
        // batch60: init builds the default working directly
        // (no reset()), so place the train at the origin
        // platform here too.
        placeTrainAtOriginTarget()
        incidentMaintenanceEngine = Self.makeIncidentMaintenanceEngine(seed: 0x5241494C)
        refreshOperationsSnapshot()
        rebuildGameplayCoordinators()
        audio.start()
        audio.setTractionSoundProfile(selectedSoundProfile)
        updateAudio()
        refreshSaveSlots()
        // CI screenshot tours for the short lines (`-RMZooTour` /
        // `-RMParkTour` together with `-RMDemoDrive -RMTour`): start
        // on the requested shuttle so the tour photographs it.
        if tourEnabled {
            if ProcessInfo.processInfo.arguments.contains("-RMZooTour") {
                selectRoute(variant: .zooLine, category: .local, direction: .up)
            } else if ProcessInfo.processInfo.arguments.contains("-RMParkTour") {
                selectRoute(variant: .parkLine, category: .local, direction: .up)
            }
        }
    }

    /// batch78: 運転開始のキー音＋逆転器音（mec keyon /
    /// reverseron、どちらも同梱済みだが従来は再生箇所が無
    /// かった）。reset() が新セッションとして武装し、最初の
    /// ライブフレームで key_on → 約 0.45 秒後に reverser_on
    /// を 1 回だけ鳴らす。スナップショット復元は reset() を
    /// 通らないため武装されず、ポーズ再開でも消費済みで鳴ら
    /// ない。発火は advance のライブ区間（ポーズ中・ロード中
    /// は advance 自体が進まない）でのみ起きる。
    private func playSessionStartCuesIfArmed() {
        guard sessionStartCuesArmed else { return }
        sessionStartCuesArmed = false
        _ = audio.playBundledSampleOneShot(named: "key_on")
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 450_000_000)
            _ = self?.audio.playBundledSampleOneShot(named: "reverser_on")
        }
    }

    /// Frame time is only an input clock. All simulation systems advance together at 120 Hz.
    func advance(at time: TimeInterval) {
        guard let previous = lastFrameTime else {
            lastFrameTime = time
            return
        }
        lastFrameTime = time
        logDemoStateIfDue(wall: time)
        guard !isPaused, runPhase == .running else { return }
        let realDelta = min(max(time - previous, 0), 2.0)
        guard realDelta > 0 else { return }
        playSessionStartCuesIfArmed()
        driveDemoIfEnabled()
        fixedStepAccumulator += realDelta
        let fixedStep = TrainPhysics.PhysicsConstants.fixedTimeStepSeconds
        // Cap the catch-up work per frame (2026-11-12, CI #412):
        // every substep runs the whole simulation (traffic,
        // signals, coordinators), so after any stall the old
        // unbounded loop demanded more work than the frame that
        // triggered it and simulation time fell behind wall time
        // without limit. The backlog beyond the cap is dropped:
        // under overload the simulation degrades to slow motion
        // instead of spiralling, and the runloop keeps presenting
        // frames.
        // batch7 (2026-11-12, CI #413): the 24-substep cap was
        // itself the ceiling that pinned the CI tour — frames on
        // the runner took ~7.5 s of wall time while the cap
        // allowed only 0.2 s of simulation per frame, a hard
        // 1/37 speed limit no tick optimisation could lift. The
        // cap went to 120 substeps with a 1.0 s input clamp.
        // batch8 (2026-11-12, CI #414): the model is confirmed —
        // measured speed was ~1/6.1 with frames ~6 s apart, i.e.
        // exactly clamp / frame time (1.0 / 6). The clamp and
        // cap now double together: 2.0 s and 240 substeps, for
        // a ~1/3 ceiling at the same frame rate. The backlog
        // beyond the cap is still dropped, so if longer frames
        // make each frame slower the speed degrades gracefully
        // instead of spiralling. On a healthy 60 fps device
        // realDelta is ~0.017 s and none of this ever binds.
        // batch113 (2026-11-16, IPA #12 perf diagnosis): the
        // cap drops 240 -> 48. On the real device the 240 cap
        // was the spiral's second half: after any stall (a
        // heavy scene frame), the next frame tried to run up
        // to 2.0 s of full simulation — traffic, signals,
        // coordinators — in one go, guaranteeing another
        // stall. 48 substeps is 0.4 s of simulation: 24x the
        // healthy-frame need (2 substeps at 60 fps), so normal
        // hitches still catch up within a frame or two, while
        // a post-stall catch-up is bounded to a fifth of the
        // old work. The dropped backlog still just drops (the
        // min() below): position only ever advances through
        // simulationTick, so nothing teleports — the sim
        // degrades to slow motion under overload, as batch7
        // designed. The CI tour is teleport-based and needs
        // only ~4 s of sim per spot against a 420 s per-spot
        // READY cap, so the lower ceiling costs it nothing;
        // the app tests advance in <= 0.5 s steps and none pin
        // absolute sim time across a > 0.4 s single jump.
        let maxSubstepsPerFrame = 48
        fixedStepAccumulator = min(fixedStepAccumulator, Double(maxSubstepsPerFrame) * fixedStep)
        while fixedStepAccumulator + 1e-12 >= fixedStep, runPhase == .running {
            fixedStepAccumulator -= fixedStep
            simulationTime += fixedStep
            simulationTick(dt: fixedStep)
        }
        applyPendingDoorCloseIfDue()
        applyPendingDepartureBuzzerIfDue()
        updateAutomaticDoorCycle()
        refreshPublishedTelemetry()
        if let latestOperationsSnapshot { operationsSnapshot = latestOperationsSnapshot }
        // batch65: ダイヤ遅延による初発ホールド（力行0・ブレーキ7
        // の強制）は完全撤廃済み。ここで操作を差し替えるのは自動
        // ブレーキ作動時だけ。
        let effectiveControls: TrainControls
        if latestOperationsSnapshot?.automaticBrakeActive == true {
            effectiveControls = TrainControls(
                throttleNotch: 0,
                brakeNotch: max(appliedDrivingControls.brakeNotch, 7),
                emergencyBrake: appliedDrivingControls.emergencyBrake || latestOperationsSnapshot?.atsStatus?.automaticBrakeCommanded == true
            )
        } else if doorInterlockActive {
            // batch108: the audio snapshot follows the same
            // interlocked command as the physics tick, so the
            // motor sound stays silent while the doors are open
            // even though the driver's handle is notched up.
            effectiveControls = TrainControls(
                throttleNotch: 0,
                brakeNotch: max(appliedDrivingControls.brakeNotch, 4),
                emergencyBrake: appliedDrivingControls.emergencyBrake
            )
        } else {
            effectiveControls = controls
        }
        updateAudio(controlsOverride: effectiveControls)
    }

    private func refreshPublishedTelemetry() {
        let readings = engine.telemetry
        trainPhysicsTelemetry = readings
        telemetry = TrainPhysicsProfileAdapter.projectTelemetry(
            readings,
            engine: engine,
            route: route,
            stoppingDistance: stoppingDistanceEstimate
        )
    }

    func estimateFullServiceStoppingDistance() {
        stoppingDistanceEstimate = engine.estimateStoppingDistance(brake: .service(notch: 7))
        refreshPublishedTelemetry()
    }

    private func simulationTick(dt: Double) {
        pendingGameModeStationEvent = nil
        advanceIncidentMaintenanceForCurrentTick()
        let playerOccupant = try? BlockOccupant(
            trainID: "PLAYER",
            frontPositionM: engine.positionM,
            trainLengthM: train.estimatedTrainLengthM,
            trackID: "T1"
        )
        if var schedule = scheduleEngine {
            do {
                _ = try schedule.advance(timeStepSeconds: dt, externalOccupants: playerOccupant.map { [$0] } ?? [])
                scheduleEngine = schedule
            } catch {
                storageNotice = "列車運行状態を更新できませんでした: \(error.localizedDescription)"
            }
        }

        updatePassingWait()
        var signalContext = nextSignalContext()
        // Siding entry rule (2026-11-11, user specification): while
        // routed into the siding the home signal shows caution
        // （場内・注意）; while held at the platform the departure
        // side shows stop until the passer clears. Only ever
        // restricts a green / yellow-green reading, never relaxes.
        if let wait = passingWait, let reading = signalContext.reading,
           reading.aspect == .green || reading.aspect == .yellowGreen,
           let block = signalContext.block, abs(block.startM - wait.stationCenterM) < 1_900 {
            let overrideAspect: ThreeAspectSignal?
            if passingWaitHolding {
                overrideAspect = .red
            } else if engine.positionM < wait.stationCenterM - 30 {
                overrideAspect = .yellow
            } else {
                overrideAspect = nil
            }
            if let overrideAspect {
                signalContext = (
                    reading: BlockSignalReading(blockID: reading.blockID, aspect: overrideAspect, blockStartM: reading.blockStartM, label: reading.label),
                    block: signalContext.block
                )
            }
        }
        if let reading = signalContext.reading,
           reading.aspect != .green,
           lastATSProtectedBlockID != reading.blockID {
            do {
                try atsSystem?.trigger(at: simulationTime)
                // batch67: ベルは updateAudio のループが警報需要
                // （awaiting 状態）の続く間回し続ける。ここでの
                // ワンショットは廃止（二重発音の防止）。
                lastATSProtectedBlockID = reading.blockID
            } catch {
                storageNotice = "教材ATSの状態更新に失敗しました。"
            }
        } else if signalContext.reading?.aspect == .green {
            lastATSProtectedBlockID = nil
        }

        let atsStatus: EducationalATSStatus?
        if var system = atsSystem {
            if let updated = try? system.advance(to: simulationTime) {
                atsSystem = system
                atsStatus = updated
            } else {
                atsStatus = system.status()
            }
        } else {
            atsStatus = nil
        }
        let basePermittedSpeed = calculatePermittedSpeed(
            signal: signalContext.reading,
            signalBlock: signalContext.block,
            brakingMultiplier: maintenanceEffects.brakingMultiplier * activeIncidentEffects.brakingMultiplier
        )
        // Permitted-speed cap for the HUD limit and the ATS pattern
        // staging ONLY (see permittedSpeed below): the section
        // limit scaled by maintenance/incident multipliers, and
        // any explicit cap. This value must NOT be handed to the
        // physics engine as a hard cap — doing so (via the old
        // PhysicsModifiers.speedCapKmh wiring) made the displayed
        // limit a cruise control: under full notch the train
        // pinned at exactly the limit and could never overspeed,
        // so the staged ATS intervention below never engaged.
        let maintenanceSpeedCap = min(
            route.condition(at: engine.positionM).speedLimitKmh * max(maintenanceEffects.maximumSpeedMultiplier * activeIncidentEffects.speedMultiplier, 0),
            maintenanceEffects.speedCapKmh ?? Double.infinity
        )
        let permittedSpeed = min(basePermittedSpeed, maintenanceSpeedCap)
        let currentSpeedKmh = engine.speedMps * 3.6
        let exceededPattern = currentSpeedKmh > permittedSpeed + 0.25
        lastExceededPattern = exceededPattern
        // batch67: パターン超過はいきなり制動しない。実車ATSの
        // 段階動作に合わせ、(1) 警告段階: ベルが鳴り続けるだけ
        // (2) 運転士が確認したら、なお超過していれば常用制動で
        // パターン以下まで落とす (3) 確認しないまま猶予（5秒、
        // 教材ATSの確認期限と同値）を過ぎたら非常制動。速度が
        // パターン以下に戻れば全段階は解除される。従来の即時
        // 制動は、制限境界で速度が上下するたび自動ブレーキが
        // 点滅し、音響スナップショットのノッチ/ブレーキまで
        // 往復して見えてノッチ音・ブレーキ音が繰り返し鳴る
        // 原因にもなっていた。
        updatePatternWarning(exceeded: exceededPattern)
        let atsBrake = atsStatus?.automaticBrakeCommanded == true
        let automaticBrake = patternBrakeActive || atsBrake
        let nextStopPosition = activeStops.indices.contains(nextStopIndex) ? activeStops[nextStopIndex].positionM : route.stopMarkerM
        let stationHold = abs(engine.positionM - nextStopPosition) <= Self.arrivalToleranceM && currentSpeedKmh <= 0.5
        // batch65: ダイヤ遅延による初発ホールド（力行0・ブレーキ7
        // の強制）は完全撤廃済み。発車保留が残るのは駅停車・待避・
        // 保守/インシデントによる departureHeld の場合だけ。
        let effectiveControls: TrainControls
        if automaticBrake {
            effectiveControls = TrainControls(
                throttleNotch: 0,
                brakeNotch: 7,
                // batch67: 非常になるのは教材ATSの期限超過か、
                // パターン警告を未確認のまま猶予を過ぎた場合だけ。
                // 確認済みのパターン制動は常用（B7）のまま。
                emergencyBrake: atsBrake || patternBrakeEmergency
            )
        } else if doorInterlockActive {
            // batch108: door interlock (user directive,
            // 2026-11-16). While the doors are not fully closed
            // the train cannot depart: traction is zeroed in the
            // effective command — the same mechanism the
            // protection interventions use, so the motor sound,
            // which follows the applied command, stays silent —
            // and a brake hold with a B4 floor keeps the train
            // standing even if the driver releases the brake on
            // a grade (B4 ≈ 0.57 m/s² of the ~1.0 m/s² service
            // brake, against ≈ 0.25 m/s² for the steepest 25‰
            // grade on the network).
            effectiveControls = TrainControls(throttleNotch: 0, brakeNotch: max(4, controls.brakeNotch), emergencyBrake: false)
        } else if stationHold || passingWaitHolding || maintenanceEffects.departureHeld || activeIncidentEffects.departureHeld {
            effectiveControls = TrainControls(throttleNotch: 0, brakeNotch: max(1, controls.brakeNotch), emergencyBrake: false)
        } else {
            effectiveControls = controls
        }
        let commandedControls = protectionAdjustedControls(effectiveControls)

        let tickCount = engine.advance(
            realDeltaSeconds: dt,
            controls: TrainPhysics.SimulationControls(
                throttleNotch: commandedControls.throttleNotch,
                brakeNotch: commandedControls.brakeNotch,
                emergencyBrake: commandedControls.emergencyBrake,
                masterReversed: commandedControls.masterReversed
            ),
            track: TrainPhysicsProfileAdapter.trackCondition(route: route, positionM: engine.positionM, profile: engine.profile),
            surface: TrainPhysicsProfileAdapter.railSurface(for: weather),
            modifiers: TrainPhysics.PhysicsModifiers(
                tractionMultiplier: maintenanceEffects.tractionMultiplier * activeIncidentEffects.tractionMultiplier,
                brakingMultiplier: maintenanceEffects.brakingMultiplier * activeIncidentEffects.brakingMultiplier,
                // Only the explicit vehicle/game cap (e.g. a
                // maintenance fault limit) is a physical ceiling.
                // The section limit and event multipliers live in
                // permittedSpeed and are enforced by the ATS
                // pattern staging, never by clamping physics.
                speedCapKmh: maintenanceEffects.speedCapKmh,
                adhesionCoefficientOverride: weatherDrivingEffect.adhesionCoefficient,
                extraResistanceN: weatherDrivingEffect.extraResistanceN
            )
        )
        assert(tickCount == 1, "The host 120Hz tick must advance exactly one authoritative physics tick")
        advanceTrafficAtCurrentTick()
        advanceGameplayCoordinators()
        latestOperationsSnapshot = SimulatorOperationsSnapshot(
            signalReading: signalContext.reading,
            signalDistanceM: signalContext.block.map { max(0, $0.startM - engine.positionM) },
            permittedSpeedKmh: permittedSpeed,
            otherTrains: scheduleEngine?.frame().trains ?? [],
            atsStatus: atsStatus,
            automaticBrakeActive: automaticBrake || !protectionActingSystems.isEmpty,
            automaticBrakeReason: protectionBrakeReason(educationalATS: atsBrake, exceededPattern: exceededPattern),
            label: .fictionalEducational
        )
        recordCurrentState(atsStatus: atsStatus, automaticBrake: automaticBrake, signalReading: signalContext.reading)
        cueOperationalAudio(nextStopDistanceM: nextStopPosition - engine.positionM)
        cueWaysideAudio()
        updateRunPhase(dt: dt)
        advanceGameModeSessionFromHost()
        scheduleAutomaticApproachAnnouncement()
        advanceScheduledAudio(to: simulationTime)
    }

    /// Whether the passing wait is holding the player at the
    /// platform (stopped, passer not yet clear of the station).
    private var passingWaitHolding: Bool {
        guard let wait = passingWait else { return false }
        return abs(engine.positionM - wait.stationCenterM) <= Self.arrivalToleranceM && engine.speedMps <= 0.5
    }

    private func serviceTypeName(_ type: TrainServiceType) -> String {
        switch type {
        case .limitedExpress: return "特急"
        case .rapidExpress: return "快速急行"
        case .express: return "急行"
        case .rapid: return "快速"
        case .semiExpress: return "準急"
        case .local: return "各停"
        }
    }

    /// Passing-wait state machine, evaluated once per tick before
    /// the signal context: latch when a faster train is closing on
    /// a multi-track station the player is about to stop at, release
    /// when it has cleared the station (with fail-safes so the
    /// player can never be trapped).
    private func updatePassingWait() {
        let mainLength = (regionalPlan?.network.mainlineLengthKm ?? 60) * 1_000
        if let wait = passingWait {
            var release = simulationTime - wait.latchedAtSeconds > 420
            if let passer = trafficSnapshot?.trains.first(where: { $0.id == wait.passerID }) {
                let cleared = travelDirection == .up
                    ? passer.positionM - 80 > wait.stationPathM + 40
                    : passer.positionM + 80 < wait.stationPathM - 40
                if cleared { release = true }
            } else if trafficSnapshot != nil {
                release = true
            }
            let leftBehind = engine.positionM > wait.stationCenterM + PassingWaitPlanner.sidingHalfSpanM + 80
            let teleportedAway = engine.positionM < wait.stationCenterM - 3_400
            if release || leftBehind || teleportedAway {
                passingWait = nil
                passingWaitMessage = nil
            } else {
                passingWaitMessage = passingWaitHolding
                    ? "通過待ち：\(serviceTypeName(wait.passerType))の通過を待っています"
                    : "側線に進入します（分岐制限45km/h）"
            }
            return
        }
        guard !demoDriveEnabled else { return }
        guard routeVariant == .mainline || routeVariant == .throughBranch else { return }
        guard PassingWaitPlanner.priority(of: serviceCategory) >= 3 else { return }
        guard activeStops.indices.contains(nextStopIndex) else { return }
        let stop = activeStops[nextStopIndex]
        guard PassingWaitPlanner.stationIDs.contains(stop.stationID) else { return }
        let distance = stop.positionM - engine.positionM
        guard distance > -40, distance < 3_000 else { return }
        guard let snapshot = trafficSnapshot else { return }
        let stationPathM: Double
        if routeVariant == .mainline {
            stationPathM = travelDirection == .up ? stop.positionM : mainLength - stop.positionM
        } else if travelDirection == .up {
            guard stop.positionM < mainLength else { return }
            stationPathM = stop.positionM
        } else {
            let branchLength = (regionalPlan?.network.branchLengthKm ?? 8) * 1_000
            guard stop.positionM >= branchLength else { return }
            stationPathM = mainLength - (stop.positionM - branchLength)
        }
        let myTrack = travelDirection == .up ? "main-up" : "main-down"
        for train in snapshot.trains where train.trackID == myTrack && train.phase == .running {
            guard PassingWaitPlanner.shouldRoute(player: serviceCategory, passer: train.serviceType) else { continue }
            let gap = travelDirection == .up ? stationPathM - train.positionM : train.positionM - stationPathM
            guard gap > 100, gap < 3_400 else { continue }
            let eta = gap / max(train.speedMps, 6.0)
            guard eta < 260 else { continue }
            passingWait = PassingWaitState(
                stationID: stop.stationID,
                stationCenterM: stop.positionM,
                stationPathM: stationPathM,
                passerID: train.id,
                passerType: train.serviceType,
                latchedAtSeconds: simulationTime
            )
            passingWaitMessage = "側線に進入します（分岐制限45km/h）"
            return
        }
    }

    private func nextSignalContext() -> (reading: BlockSignalReading?, block: RailwayBlock?) {
        guard !blockSystem.blocks.isEmpty else { return (nil, nil) }
        let trackBlocks = blockSystem.blocks.filter { $0.trackID == "T1" }
        guard !trackBlocks.isEmpty else { return (nil, nil) }
        let position = engine.positionM
        let currentIndex = trackBlocks.firstIndex {
            position >= $0.startM && position < $0.endM
        } ?? max(0, trackBlocks.count - 1)
        // The next block is the one protected by the signal ahead of the current block.
        let protectedIndex = min(currentIndex + 1, trackBlocks.count - 1)
        let protectedBlock = trackBlocks[protectedIndex]
        let occupants = (scheduleEngine?.trains ?? []).compactMap {
            try? BlockOccupant(trainID: $0.id, frontPositionM: $0.positionM, trainLengthM: $0.lengthM, trackID: $0.trackID)
        }
        return (blockSystem.reading(for: protectedBlock.identifier, occupants: occupants), protectedBlock)
    }

    private func advanceTrafficAtCurrentTick() {
        // batch93: normal launches no longer build the traffic
        // engine in init (its first snapshot was always
        // discarded by the first route selection's reset()).
        // Build it on the first advance that needs it — the
        // same engine, from the same cached scenario — so a
        // model advanced without a prior reset (tests, a
        // restored session) behaves exactly as before.
        // (step/tick hoisted above the build: the latch below
        // needs the current tick; the values are unchanged.)
        let step = TrainPhysics.PhysicsConstants.fixedTimeStepSeconds
        let tick = UInt64(max(0, (simulationTime / step).rounded()))
        if trafficEngine == nil, let scenario = trafficScenario {
            // batch105: latch a failed build to the scenario
            // generation with a bounded backoff (see
            // trafficBuildFailedGeneration). Before this, a
            // deterministically invalid scenario re-ran the
            // full 798-train validation on every 120 Hz tick
            // for the whole session. The successful path is
            // unchanged: a build that succeeds leaves
            // trafficEngine non-nil and the latch state is
            // never read again.
            let generation = TrafficScenarioGeneration.current
            let latched = trafficBuildFailedGeneration == generation && trafficBuildFailureCount >= 3
            // Backoff between attempts: 0.5 s, 2 s, 8 s of
            // simulation time (60 / 240 / 960 ticks at 120 Hz),
            // at most 3 attempts per generation.
            let backoffTicks: UInt64 = [0, 60, 240, 960][min(trafficBuildFailureCount, 3)]
            let due = trafficBuildFailedGeneration != generation
                || tick >= trafficBuildLastFailureTick + backoffTicks
            if !latched && due {
                trafficEngine = Self.makeTrafficEngine(from: scenario)
                if trafficEngine == nil {
                    if trafficBuildFailedGeneration != generation {
                        trafficBuildFailedGeneration = generation
                        trafficBuildFailureCount = 0
                    }
                    trafficBuildFailureCount += 1
                    trafficBuildLastFailureTick = tick
                    // batch119: surface the latch's exhaustion
                    // in the pulled log (the latch's behaviour
                    // itself is unchanged — see batch105/109).
                    if trafficBuildFailureCount == 3 {
                        Self.noteTrafficLog("TRAFFIC_GEN_FAIL latched=1 attempts=3")
                    }
                } else {
                    trafficBuildFailedGeneration = nil
                    trafficBuildFailureCount = 0
                    trafficAdvanceFailureLogged = false
                }
            }
        }
        // batch101: if the build just failed (or the scenario
        // itself never loaded), say so once instead of returning
        // silently on every tick forever.
        if trafficEngine == nil { noteTrafficUnavailableIfNeeded() }
        guard var traffic = trafficEngine else { return }
        // The zoo and theme park shuttles run alone by design: the
        // regional traffic scenario has no zoo/park tracks, so
        // advancing it with the player on those lines throws on
        // every tick and pinned a permanent "AI sync failed"
        // warning on those routes (CI #412). Skip traffic there.
        guard routeVariant != .zooLine, routeVariant != .parkLine else { return }
        // Advance traffic at 30 Hz of simulation time rather than
        // on every 120 Hz physics tick (2026-11-12): the engine
        // catches up internally in one call, and snapshot
        // construction plus the downstream scene updates cost a
        // quarter as much.
        if let snapshot = trafficSnapshot, tick > snapshot.fixedTick, tick - snapshot.fixedTick < 4 {
            return
        }
        let clock = SharedSimulationClock(
            simulationTimeSeconds: Double(tick) * step,
            fixedTick: tick,
            fixedTimeStepSeconds: step
        )
        do {
            let snapshot = try traffic.advance(
                to: clock,
                route: traffic.scenario.sharedRouteReference,
                playerTrain: playerTrafficState()
            )
            trafficEngine = traffic
            trafficSnapshot = snapshot
        } catch {
            storageNotice = "架空交通AIの同期を継続できませんでした。路線ID・向き・キロ程を確認してください。"
            // batch119: this catch used to be the whole
            // record — a session whose advance threw on every
            // tick ran train-less with nothing in the pulled
            // log to distinguish it from an empty diagram.
            if !trafficAdvanceFailureLogged {
                trafficAdvanceFailureLogged = true
                Self.noteTrafficLog("TRAFFIC_ADVANCE_FAIL error=\(String(describing: error).prefix(160))")
            }
        }
    }

    private func makeRegionalGameModeTrainStates() -> [RegionalGameModeTrainState] {
        let playerTrackID = playerTrafficState()?.trackID ?? activeStops.first?.trackID ?? "T1"
        var states = [RegionalGameModeTrainState(
            id: "PLAYER",
            routeID: routeID,
            trackID: playerTrackID,
            positionM: max(0, engine.positionM),
            speedMps: max(0, engine.speedMps)
        )]
        var compatiblePaths: Set<String> = []
        switch routeVariant {
        case .mainline, .throughBranch: compatiblePaths.insert("mainline")
        case .branchShuttle: compatiblePaths.insert("branch")
        case .depotTransfer: compatiblePaths.insert("depotSpur")
        case .zooLine: break // The zoo shuttle runs alone; no AI traffic paths map onto it.
        case .parkLine: break // Same for the theme park shuttle.
        }
        for train in trafficSnapshot?.trains ?? [] where compatiblePaths.contains(train.routePathID) {
            states.append(RegionalGameModeTrainState(
                id: "AI-\(train.id)",
                routeID: routeID,
                trackID: train.trackID,
                positionM: max(0, train.positionM),
                speedMps: max(0, train.speedMps)
            ))
        }
        return states
    }

    private func gameModeVisibleLandmarkID() -> String? {
        let candidates = Array(activeStops.dropFirst().dropLast().prefix(2))
        for (index, stop) in candidates.enumerated()
        where abs(engine.positionM - stop.positionM) <= 120 && engine.speedMps <= 12 {
            return "PLACEHOLDER-landmark-\(String(format: "%02d", index + 1))"
        }
        return nil
    }

    private func advanceGameModeSessionFromHost() {
        guard var current = gameModeSession, !current.status.isTerminal else { return }
        let tick = UInt64(max(0, (simulationTime / TrainPhysics.PhysicsConstants.fixedTimeStepSeconds).rounded()))
        guard tick.isMultiple(of: 24) || pendingGameModeStationEvent != nil,
              let snapshot = gameModeSnapshot else { return }
        do {
            try current.update(with: snapshot)
        } catch {
            gameModeHostNotice = "架空ゲームモードの更新を継続できませんでした: \(error.localizedDescription)"
        }
        let effects = current.drainHostEffects()
        gameModeSession = current
        if !effects.isEmpty {
            handleGameModeHostEffects(effects)
        }
    }

    /// Bridges the already-completed host physics tick to the package coordinators.
    /// Maintenance consumes every tick; the score/motion recorder uses a 5 Hz subset
    /// to keep its UI and sample log bounded while preserving the monotonic host clock.
    private func advanceGameplayCoordinators() {
        let step = TrainPhysics.PhysicsConstants.fixedTimeStepSeconds
        let tick = UInt64(max(0, (simulationTime / step).rounded()))
        if let coordinator = maintenanceGameplayCoordinator {
            let input = makeMaintenanceHostInput(tick: tick)
            if let result = coordinator.advanceFixedTick(with: input) {
                maintenanceEffects = result.eventResult.effects(for: "PLAYER")
                let warning = maintenanceEffects.warningKinds.map(\.rawValue).joined(separator: "・")
                let nextWarning = warning.isEmpty ? nil : "架空イベント: \(warning)"
                if maintenanceWarning != nextWarning { maintenanceWarning = nextWarning }
            }
        }

        guard tick.isMultiple(of: 24),
              let coordinator = operationsGameplayCoordinator,
              let host = makeOperationsHostSnapshot(tick: tick) else { return }
        do {
            try coordinator.receiveFixedTick(host)
        } catch {
            coordinator.present(error: error)
        }
    }

    private func makeOperationsHostSnapshot(tick: UInt64) -> OperationsGameplayHostSnapshot? {
        guard let state = playerTrafficState(),
              let trainSnapshot = try? SharedTrainSnapshot(
                trainID: state.trainID,
                trackID: state.trackID,
                positionM: engine.positionM,
                speedMps: max(0, engine.speedMps),
                accelerationMps2: engine.accelerationMps2,
                lengthM: train.estimatedTrainLengthM
              ) else { return nil }
        return try? OperationsGameplayHostSnapshot(
            simulationTimeSeconds: Double(tick) * TrainPhysics.PhysicsConstants.fixedTimeStepSeconds,
            fixedTick: tick,
            fixedTimeStepSeconds: TrainPhysics.PhysicsConstants.fixedTimeStepSeconds,
            routeID: routeID,
            train: trainSnapshot
        )
    }

    private func makeMaintenanceHostInput(tick: UInt64) -> MaintenanceGameplayHostInput {
        let state = playerTrafficState()
        let trackID = state?.trackID ?? activeStops.first?.trackID ?? "main-up"
        let positionM = engine.positionM
        let stoppedStation = activeStops.first {
            abs($0.positionM - positionM) <= 8 && engine.speedMps <= 0.1
        }?.stationID
        let environment = environmentSelection.environment
        let weather = MaintenanceWeatherSnapshot(
            windSpeedMps: environment.windSpeedMps,
            rainRateMmPerHour: environment.precipitation == .rain ? 8 : 0,
            snowCoverM: environment.precipitation == .snow ? 0.08 : 0,
            visibilityM: environment.visibilityM
        )
        let train = MaintenanceTrainSnapshot(
            trainID: "PLAYER",
            trackID: trackID,
            positionM: state?.positionM ?? positionM,
            speedMps: max(0, engine.speedMps),
            direction: state?.direction == .decreasing ? .decreasingChainage : .increasingChainage,
            lengthM: train.estimatedTrainLengthM,
            stationID: stoppedStation
        )
        let scenarioTracks = trafficScenario?.tracks ?? []
        let crossings: [MaintenanceCrossingSnapshot] = [0.25, 0.55, 0.82].enumerated().map { index, fraction in
            MaintenanceCrossingSnapshot(
                crossingID: "fictional-crossing-\(routeID)-\(index)",
                trackID: trackID,
                chainageM: route.distanceM * fraction
            )
        }
        return MaintenanceGameplayHostInput(
            routeID: routeID,
            routeLengthM: route.distanceM,
            simulationTimeSeconds: Double(tick) * TrainPhysics.PhysicsConstants.fixedTimeStepSeconds,
            fixedTick: tick,
            fixedTimeStepSeconds: TrainPhysics.PhysicsConstants.fixedTimeStepSeconds,
            trackIDs: scenarioTracks.map(\.id) + ["T1", "T2"],
            stationIDs: activeStops.map(\.stationID),
            trains: [train],
            crossings: crossings,
            weather: weather
        )
    }

    private func rebuildGameplayCoordinators() {
        if let scenario = makeOperationsScenario() {
            let checkpoints: [PointingCallingDefinition] = [
                try? PointingCallingDefinition(id: "game-start", trigger: .beforeDuty, targetLabel: "架空ゲーム運転開始", acceptedCallouts: ["ゲーム開始", "準備よし"]),
                try? PointingCallingDefinition(id: "game-cab", trigger: .cabSetup, targetLabel: "架空ゲーム運転台", acceptedCallouts: ["運転台確認", "ゲーム確認"]),
                try? PointingCallingDefinition(id: "game-departure", trigger: .beforeDeparture, targetLabel: "架空ゲーム発車", acceptedCallouts: ["出発確認", "ゲーム発車"]),
                try? PointingCallingDefinition(id: "game-stop", trigger: .stopMarker, targetLabel: "架空ゲーム停止目標", acceptedCallouts: ["停止目標確認", "ゲーム目標"]),
                try? PointingCallingDefinition(id: "game-end", trigger: .endOfRun, targetLabel: "架空ゲーム運転終了", acceptedCallouts: ["終了確認", "ゲーム終了"])
            ].compactMap { $0 }
            let disruptions: [DisruptionEventDefinition] = trainingMode == .disruptionTraining
                ? [try? DisruptionEventDefinition(
                    id: "fictional-door-delay-01",
                    kind: .simulatedDoorDelay,
                    triggerTimeSeconds: 300,
                    availableChoices: [.acknowledgeGamePrompt, .requestGameHint, .holdGameSession, .resumeAfterPromptClears],
                    expectedGameChoice: .acknowledgeGamePrompt,
                    description: "架空ゲームイベント: 駅停車中にドア遅延の表示が出ました。実在の対応を示すものではありません。"
                )].compactMap { $0 }
                : []
            operationsGameplayCoordinator = try? OperationsGameplayCoordinator(
                scenario: scenario,
                mode: trainingMode,
                checkpoints: checkpoints,
                disruptionEvents: disruptions
            )
        } else {
            operationsGameplayCoordinator = nil
        }

        let input = makeMaintenanceHostInput(tick: 0)
        let trainState = input.trains.first
        let depot = DepotDefinition(
            id: "fictional-depot",
            routeID: routeID,
            accessTrackID: trainState?.trackID ?? "main-up",
            accessChainageM: trainState?.positionM ?? 0,
            entryTransferDurationSeconds: 20,
            exitTransferDurationSeconds: 20,
            tracks: [
                DepotTrackDefinition(id: "fictional-yard-A", capacity: 4),
                DepotTrackDefinition(id: "fictional-yard-B", capacity: 4)
            ]
        )
        let vehicle = MaintenanceVehicleRecord(
            id: "PLAYER",
            profileID: selectedVehicleProfile.rawValue,
            lengthM: train.estimatedTrainLengthM,
            location: .onRoute(trackID: trainState?.trackID ?? "main-up", chainageM: trainState?.positionM ?? 0)
        )
        maintenanceGameplayCoordinator = MaintenanceGameplayCoordinator(
            seed: 70_068,
            depots: [depot],
            vehicles: [vehicle],
            hostInput: input
        )
        maintenanceEffects = .neutral(trainID: "PLAYER")
        maintenanceWarning = nil
    }

    private func makeOperationsScenario() -> OperationsScenario? {
        guard activeStops.count >= 2,
              let service = regionalPlan?.services.first(where: { $0.category == serviceCategory }) else { return nil }
        // Passenger-plan timing scales with the selected variant's route length.
        // This keeps the 68 km through service unchanged while short shuttles and depot moves remain playable.
        let referenceDurationSeconds = Double(service.plannedDurationMinutes * 60)
        let durationSeconds = max(180, referenceDurationSeconds * route.distanceM / 68_000)
        let stops: [OperationsStopDefinition] = activeStops.dropFirst().compactMap { stop in
            let arrival = durationSeconds * stop.positionM / max(route.distanceM, 1)
            let isTerminal = stop.id == activeStops.last?.id
            return try? OperationsStopDefinition(
                id: stop.stationID,
                stationName: stop.name,
                targetPositionM: stop.positionM,
                scheduledArrivalSeconds: arrival,
                scheduledDepartureSeconds: arrival + (isTerminal ? 0 : 25),
                positionToleranceM: Self.arrivalToleranceM
            )
        }
        guard stops.count == activeStops.count - 1 else { return nil }
        return try? OperationsScenario(
            runID: "GAME-\(routeID)",
            routeID: routeID,
            routeLengthM: route.distanceM,
            originStationID: activeStops[0].stationID,
            originScheduledDepartureSeconds: 0,
            stops: stops
        )
    }

    private func playerTrafficState() -> SharedTrainState? {
        guard engine.positionM.isFinite else { return nil }
        let mainLength = (regionalPlan?.network.mainlineLengthKm ?? 60) * 1_000
        let branchLength = (regionalPlan?.network.branchLengthKm ?? 8) * 1_000
        let routePosition = min(max(engine.positionM, 0), route.distanceM)
        var trackID: String
        let position: Double
        let direction: TrafficDirection
        switch routeVariant {
        case .mainline:
            trackID = travelDirection == .up ? "main-up" : "main-down"
            position = travelDirection == .up ? routePosition : mainLength - routePosition
            direction = travelDirection == .up ? .increasing : .decreasing
        case .throughBranch:
            if travelDirection == .up {
                if routePosition < mainLength {
                    trackID = "main-up"; position = routePosition
                } else {
                    trackID = "branch-up"; position = routePosition - mainLength
                }
                direction = .increasing
            } else if routePosition < branchLength {
                trackID = "branch-down"; position = branchLength - routePosition
                direction = .decreasing
            } else {
                trackID = "main-down"; position = mainLength - (routePosition - branchLength)
                direction = .decreasing
            }
        case .branchShuttle:
            trackID = travelDirection == .up ? "branch-up" : "branch-down"
            position = travelDirection == .up ? routePosition : branchLength - routePosition
            direction = travelDirection == .up ? .increasing : .decreasing
        case .depotTransfer:
            trackID = travelDirection == .up ? "depot-in" : "depot-out"
            position = travelDirection == .up ? routePosition : 2_000 - routePosition
            direction = travelDirection == .up ? .increasing : .decreasing
        case .zooLine:
            trackID = travelDirection == .up ? "zoo-up" : "zoo-down"
            position = travelDirection == .up ? routePosition : 2_500 - routePosition
            direction = travelDirection == .up ? .increasing : .decreasing
        case .parkLine:
            trackID = travelDirection == .up ? "park-up" : "park-down"
            position = travelDirection == .up ? routePosition : 2_000 - routePosition
            direction = travelDirection == .up ? .increasing : .decreasing
        }
        // Passing wait: inside the siding span the player reports
        // the siding track, so the traffic engine's per-track
        // separation no longer holds the faster train behind.
        if let wait = passingWait,
           abs(routePosition - wait.stationCenterM) <= PassingWaitPlanner.sidingHalfSpanM {
            if trackID == "main-up" { trackID = "main-up-siding" }
            if trackID == "main-down" { trackID = "main-down-siding" }
        }
        guard position.isFinite, position >= 0 else { return nil }
        return SharedTrainState(
            trainID: "PLAYER",
            trackID: trackID,
            positionM: position,
            speedMps: max(0, engine.speedMps),
            direction: direction,
            lengthM: train.estimatedTrainLengthM
        )
    }

    private func calculatePermittedSpeed(
        signal: BlockSignalReading?,
        signalBlock: RailwayBlock?,
        brakingMultiplier: Double = 1
    ) -> Double {
        var currentLimit = max(route.condition(at: engine.positionM).speedLimitKmh, 0)
        // Turnout cap: while routed to the siding, the fan span is
        // a 45 km/h diverging restriction (see targets below for
        // the approach braking point).
        if let wait = passingWait,
           abs(engine.positionM - wait.stationCenterM) <= PassingWaitPlanner.sidingHalfSpanM {
            currentLimit = min(currentLimit, PassingWaitPlanner.turnoutLimitKmh)
        }
        var targets: [SafetyStopTarget] = []
        if activeStops.indices.contains(nextStopIndex) {
            let nextStop = activeStops[nextStopIndex]
            // Station stops carry no safety margin: the pattern margin
            // (18 m + brake-lag distance) is protection against signals
            // and limits, but applied to a station stop it drives the
            // permitted speed to zero a margin-length before the stop
            // position, so the train could never arrive (CI #213: the
            // demo stalled 18.3 m short of Matsubaramachi).
            if let stationTarget = try? SafetyStopTarget(identifier: "station-\(nextStop.stationID)", positionM: nextStop.positionM, targetSpeedKmh: 0, safetyMarginM: 0) {
                targets.append(stationTarget)
            }
        } else if let stationTarget = try? SafetyStopTarget(identifier: "destination-stop", positionM: route.stopMarkerM, targetSpeedKmh: 0, safetyMarginM: 0) {
            targets.append(stationTarget)
        }

        var previousLimit = route.condition(at: 0).speedLimitKmh
        for section in route.sections.sorted(by: { $0.startM < $1.startM }) where section.startM > engine.positionM {
            if section.speedLimitKmh < previousLimit,
               let restriction = try? SafetyStopTarget(identifier: "speed-limit-\(Int(section.startM))", positionM: section.startM, targetSpeedKmh: section.speedLimitKmh) {
                targets.append(restriction)
            }
            previousLimit = section.speedLimitKmh
        }

        if let wait = passingWait {
            let spanStart = wait.stationCenterM - PassingWaitPlanner.sidingHalfSpanM
            if engine.positionM < spanStart,
               let turnoutTarget = try? SafetyStopTarget(identifier: "turnout-\(wait.stationID)", positionM: spanStart, targetSpeedKmh: PassingWaitPlanner.turnoutLimitKmh) {
                targets.append(turnoutTarget)
            }
            // While held at the platform, a stop target just ahead
            // of the train keeps the ATS pattern at zero until the
            // passer clears (added only once stopped, so the
            // station approach pattern is never distorted).
            if passingWaitHolding,
               let holdTarget = try? SafetyStopTarget(identifier: "passing-wait-hold", positionM: wait.stationCenterM + 12, targetSpeedKmh: 0) {
                targets.append(holdTarget)
            }
        }

        if let signal, let block = signalBlock, let aspectCap = signal.aspect.speedLimitKmh {
            // Every restrictive aspect becomes a pattern target at the
            // block start: 停止 0 / 警戒 25 / 注意 55 / 減速 75 km/h
            // (TOO RAILWAY table, quality41). 進行 adds no target.
            let targetPosition = max(engine.positionM + 0.1, block.startM - 2)
            if targetPosition <= route.distanceM,
               let target = try? SafetyStopTarget(identifier: "signal-\(signal.aspect.rawValue)-\(block.identifier)", positionM: targetPosition, targetSpeedKmh: aspectCap) {
                targets.append(target)
            }
        }

        let serviceDeceleration = max(train.maximumServiceBrakeDecelerationMps2 * max(brakingMultiplier, 0), 0.2)
        guard let pattern = try? RailwaySafetySpeedPattern(
            route: route,
            targets: targets,
            serviceDecelerationMps2: serviceDeceleration,
            safetyMarginM: Self.safetyMarginM + engine.speedMps * train.serviceBrakeApplySeconds
        ) else { return currentLimit }
        return min(currentLimit, pattern.permittedSpeedKmh(atPositionM: engine.positionM))
    }

    private func updateRunPhase(dt: Double) {
        var events = pendingStopScoringEvents
        pendingStopScoringEvents.removeAll(keepingCapacity: true)

        if let stationID = gameModeCurrentStationID,
           let departedStop = activeStops.first(where: { $0.stationID == stationID }),
           engine.speedMps > 0.15 || abs(engine.positionM - departedStop.positionM) > Self.arrivalToleranceM {
            pendingGameModeStationEvent = (stationID, .departure)
            finalizeDoorProcedureStation(stationID)
            gameModeCurrentStationID = nil
        }

        if let stationID = pendingScoringDepartureStationID,
           let departedStop = activeStops.first(where: { $0.stationID == stationID }),
           engine.speedMps > 0.15 || abs(engine.positionM - departedStop.positionM) > Self.arrivalToleranceM {
            if let event = makeStopScoringEvent(stationID: stationID, kind: .departure) {
                events.append(event)
            }
            pendingScoringDepartureStationID = nil
            scoringStationID = nil
        }

        guard activeStops.indices.contains(nextStopIndex) else {
            updateStopScoring(events: events)
            return
        }
        let targetStop = activeStops[nextStopIndex]
        let offset = engine.positionM - targetStop.positionM
        if offset > Self.overshootToleranceM {
            updateStopScoring(events: events)
            // batch44 (2026-11-14): in screenshot-tour mode the
            // train is teleported to scenic positions, not to
            // stopping-pattern positions. The final main-tour spot
            // (67,980) sits 22 m PAST the terminal's adjusted stop
            // target (67,958 — the scoring adapter clamps the
            // leading-end target into the platform's safe window),
            // so this branch ended the run (.overshot) the moment
            // the tour arrived there: simulation time froze,
            // driveDemoIfEnabled (gated on .running) never ran
            // again, and spots 32+ never became READY — in the
            // original launch and in the script's relaunch alike
            // (demo log: TOUR spot=31 then t= frozen at
            // phase=overshot). A tour hold must never end the run;
            // the scoring update above still runs as before.
            guard !tourEnabled else { return }
            runPhase = .overshot
            finishDoorProcedureScoring()
            finishStopScoring()
            captureCompletedRun()
            persistCurrentSession()
            return
        }

        let isScoredStation = stopScoringEngine != nil &&
            stopScoringEvaluation?.stationEvaluations.contains(where: { $0.stationID == targetStop.stationID }) == true
        if gameModeCurrentStationID != targetStop.stationID,
           engine.positionM >= targetStop.positionM - Self.arrivalToleranceM {
            gameModeCurrentStationID = targetStop.stationID
            pendingGameModeStationEvent = (targetStop.stationID, .arrival)
        }
        if isScoredStation, scoringStationID == nil,
           engine.positionM >= targetStop.positionM - Self.arrivalToleranceM,
           let event = makeStopScoringEvent(stationID: targetStop.stationID, kind: .arrival) {
            events.append(event)
            scoringStationID = targetStop.stationID
        }

        let withinMarker = abs(offset) <= Self.arrivalToleranceM
        let stopped = engine.speedMps * 3.6 <= 0.5
        if withinMarker && stopped {
            arrivalDwellSeconds += dt
            if arrivalDwellSeconds >= Self.requiredArrivalDwellSeconds {
                if scoringStationID == targetStop.stationID,
                   let event = makeStopScoringEvent(stationID: targetStop.stationID, kind: .stopCompleted) {
                    events.append(event)
                }
                if nextStopIndex == activeStops.count - 1 {
                    updateStopScoring(events: events)
                    // batch44 (2026-11-14): same guard as the
                    // overshoot branch above — a tour hold at the
                    // terminal must not end the run mid-tour (and
                    // must not put the result sheet up via
                    // captureCompletedRun while the script is
                    // still photographing).
                    if !tourEnabled {
                        runPhase = .arrived
                        finishDoorProcedureScoring(finalizing: targetStop.stationID)
                        finishStopScoring()
                        captureCompletedRun()
                        persistCurrentSession()
                    }
                } else {
                    pendingConfirmations.append(DriveConfirmation(
                        actionID: "station-arrival-\(targetStop.stationID)",
                        label: "\(targetStop.name)の架空ゲーム停車"
                    ))
                    if scoringStationID == targetStop.stationID {
                        pendingScoringDepartureStationID = targetStop.stationID
                    }
                    nextStopIndex += 1
                    arrivalDwellSeconds = 0
                    updateStopScoring(events: events)
                }
            } else {
                updateStopScoring(events: events)
            }
        } else {
            arrivalDwellSeconds = 0
            updateStopScoring(events: events)
        }
    }

    private func makeStopScoringEvent(
        stationID: String,
        kind: StopScoring.StationEventKind
    ) -> StopScoring.StationEvent? {
        guard stopScoringEngine != nil else { return nil }
        stopScoringEventSequence += 1
        return try? StopScoring.StationEvent(
            eventID: "\(routeID)-score-\(stopScoringEventSequence)",
            stationID: stationID,
            kind: kind
        )
    }

    private func updateStopScoring(events: [StopScoring.StationEvent]) {
        guard let stopScoringEngine else { return }
        stopScoringTickSequence += 1
        guard let tick = try? StopScoring.SimulationTick(
            sequence: stopScoringTickSequence,
            simulationTimeSeconds: simulationTime,
            leadingEndChainageMeters: engine.positionM,
            speedMetersPerSecond: max(0, engine.speedMps)
        ) else { return }
        do {
            stopScoringEvaluation = try stopScoringEngine.process(tick: tick, events: events)
            stopScoringError = nil
        } catch {
            if stopScoringError == nil {
                stopScoringError = "架空の駅別停車スコアを更新できませんでした。停車記録は保存されていません。"
            }
        }
    }

    private func finishStopScoring() {
        guard let stopScoringEngine else { return }
        stopScoringEvaluation = stopScoringEngine.finish()
    }

    private func rebuildDoorProcedureScoringSession() {
        doorProcedureEventSequence = 0
        doorProcedureScoringError = nil
        if routeVariant == .depotTransfer || activeStops.count < 2 {
            doorProcedureScoringEngine = nil
            doorProcedureEvaluation = nil
            if routeVariant == .depotTransfer {
                doorProcedureScoringError = "車庫入出庫の疑似停車点は旅客駅ドア・手順採点の対象外です。"
            }
            return
        }
        do {
            let scorer = try DoorProcedureScoringRouteAdapter.makeEngine(routeID: routeID, stops: activeStops)
            doorProcedureScoringEngine = scorer
            doorProcedureEvaluation = scorer.evaluation()
        } catch {
            doorProcedureScoringEngine = nil
            doorProcedureEvaluation = nil
            doorProcedureScoringError = "架空ドア・手順評価を準備できませんでした: \(error.localizedDescription)"
        }
    }

    /// Called only after the game-mode action has been accepted by its session reducer.
    func recordDoorProcedureGameModeAction(_ action: GameModeAction) {
        guard let stationID = gameModeSession?.lastSnapshot.atStationID ?? gameModeCurrentStationID else { return }
        let kind: DoorProcedureScoring.ScoringEventKind
        switch action {
        case .conductorOpenDoors(let side):
            kind = .doorSideAcknowledged(side == .left ? .left : .right)
        case .conductorConfirmDoorClosure:
            kind = .procedureStep(
                stepID: "fictional.conductor-confirm-closure",
                role: .conductor,
                outcome: .completed
            )
        default:
            return
        }
        doorProcedureEventSequence += 1
        do {
            let event = try DoorProcedureScoring.ScoringEvent(
                eventID: "\(routeID)-door-procedure-\(doorProcedureEventSequence)",
                stationID: stationID,
                simulationTimeSeconds: simulationTime,
                kind: kind
            )
            doorProcedureEvaluation = try doorProcedureScoringEngine?.record(event)
            doorProcedureScoringError = nil
        } catch {
            doorProcedureScoringError = "架空ドア・手順イベントを記録できませんでした: \(error.localizedDescription)"
        }
    }

    private func finalizeDoorProcedureStation(_ stationID: String) {
        guard let current = doorProcedureEvaluation?.stationEvaluations.first(where: { $0.stationID == stationID }),
              !current.isFinalized, let doorProcedureScoringEngine else { return }
        do {
            doorProcedureEvaluation = try doorProcedureScoringEngine.finalizeStation(
                stationID: stationID,
                at: simulationTime
            )
        } catch {
            doorProcedureScoringError = "架空駅のドア・手順評価を確定できませんでした: \(error.localizedDescription)"
        }
    }

    private func finishDoorProcedureScoring(finalizing stationID: String? = nil) {
        if let stationID { finalizeDoorProcedureStation(stationID) }
        doorProcedureEvaluation = doorProcedureScoringEngine?.finish()
    }

    func recordStopScoringDoorOperation(side: StopScoring.DoorSide, action: StopScoring.DoorAction) {
        guard let scoringStationID,
              let event = makeStopScoringEvent(stationID: scoringStationID, kind: .doorOperation(side: side, action: action)) else { return }
        pendingStopScoringEvents.append(event)
    }

    func recordStopScoringProcedure(stepID: String, outcome: StopScoring.ProcedureOutcome) {
        guard let scoringStationID,
              let event = makeStopScoringEvent(stationID: scoringStationID, kind: .procedureStep(stepID: stepID, outcome: outcome)) else { return }
        pendingStopScoringEvents.append(event)
    }

    private func recordCurrentState(atsStatus: EducationalATSStatus?, automaticBrake: Bool, signalReading: BlockSignalReading?) {
        let signal = signalReading?.aspect.rawValue
        let protectionNote = protectionActingSystems.isEmpty ? nil : "架空保安 \(protectionActingSystems.joined(separator: "・"))"
        let currentWarning: String? = protectionNote ?? (automaticBrake
            ? (atsStatus?.automaticBrakeCommanded == true ? "ATS確認期限超過・自動制動" : "速度パターン超過")
            : nil)
        let applied = appliedDrivingControls
        let sample = DriveSample(
            simulationTimeSeconds: simulationTime,
            positionM: engine.positionM,
            speedKmh: engine.speedMps * 3.6,
            accelerationMps2: engine.accelerationMps2,
            powerNotch: applied.throttleNotch,
            brakeNotch: applied.brakeNotch,
            emergencyBrakeOn: applied.emergencyBrake,
            speedLimitKmh: route.condition(at: engine.positionM).speedLimitKmh,
            signalAspect: signal,
            warning: currentWarning,
            warningSeverity: automaticBrake ? .critical : .information,
            warningAcknowledged: atsStatus?.state == .acknowledged ? true : nil,
            confirmations: pendingConfirmations
        )
        if recorder.record(sample) == .recorded {
            pendingConfirmations.removeAll(keepingCapacity: true)
        }
    }

    private func updateAudio(controlsOverride: TrainControls? = nil) {
        let selected = controlsOverride ?? controls
        let speedKmh = max(0, engine.speedMps * 3.6)
        let condition = route.condition(at: engine.positionM)
        let brakeCommand = selected.emergencyBrake ? 1.0 : Double(selected.brakeNotch) / 7.0
        let fadeSpeed = min(1, speedKmh / max(train.regenerativeFadeSpeedKmh, 1))
        let regenerativeRatio = selected.emergencyBrake
            ? 0
            : brakeCommand * train.regenerativeBrakeShare * fadeSpeed
        let requestedTraction = train.availableTractionForce(atSpeedKmh: speedKmh) *
            train.tractionFraction(for: selected.throttleNotch)
        let tractionLoad = min(max(requestedTraction / max(train.maximumTractionForceN, 1), 0), 1)
        let weakeningRange = max(train.maximumSpeedKmh - 45, 1)
        let fieldWeakening = min(max((speedKmh - 45) / weakeningRange, 0), 1)

        // These fictional wheel/gear constants only drive the synthesized sound timbre;
        // they are not asserted as prototype-train specifications.
        let estimatedMotorRPM = engine.speedMps / (2 * Double.pi * 0.43) * 60 * 6.5
        let audioWeather: RailwayWeather
        switch weather {
        case .dry, .fog: audioWeather = .clear
        case .rain: audioWeather = .rain
        case .heavyRain: audioWeather = .heavyRain
        case .snow: audioWeather = .snow
        }
        let trainPosition = AudioVector3(x: 0, y: 0, z: Float(engine.positionM))
        let listenerPosition = AudioVector3(x: 0, y: 1.6, z: Float(engine.positionM))
        audio.update(snapshot: RailwaySimulationSnapshot(
            simulationTime: simulationTime,
            speedMetersPerSecond: Float(engine.speedMps),
            accelerationMetersPerSecondSquared: Float(engine.accelerationMps2),
            motorRPM: Float(min(max(estimatedMotorRPM, 0), 8_000)),
            tractionLoad: Float(tractionLoad),
            powerNotch: selected.throttleNotch,
            fieldWeakeningRatio: Float(fieldWeakening),
            brakeCommand: Float(brakeCommand),
            regenerativeBrakeRatio: Float(min(max(regenerativeRatio, 0), 1)),
            trackDistanceMeters: engine.positionM,
            curveRadiusMeters: condition.curveRadiusM.map { Float($0) },
            isInTunnel: condition.tunnelResistanceMultiplier > 1.05,
            isOnBridge: audioOnBridge,
            isOnJointedRail: audioOnJointedRail,
            isOnPoints: audioOnPoints,
            doorsOpen: gameModeDoorState.isOpen,
            isAtStation: gameModeCurrentStationID != nil,
            weather: audioWeather,
            windMetersPerSecond: Float(environmentSelection.environment.windSpeedMps),
            trainPosition: trainPosition,
            listenerPosition: listenerPosition
        ))
        updateCompressorSound(speedKmh: speedKmh, brakeCommand: brakeCommand, doorsOpen: gameModeDoorState.isOpen)
        updateATSBellLoop()
    }

    /// batch67: ATS警報ベルのループ駆動（毎フレーム呼ばれる）。
    /// ベル需要 = 教材ATSが確認待ち / 保護セッションのATS-Sが
    /// 確認待ち / パターン警告が未確認かつ未制動、のいずれか。
    /// 需要が続く間、ベルの長さの周期で ats_alert を回し続け、
    /// 確認された瞬間（需要が消えた瞬間）に止まる。実車ATSの
    /// 「警報ベルは条件が続く間鳴り続け、確認で止まる」挙動。
    /// 従来は各トリガー点でワンショット1回だけだったため、
    /// 「ベルが鳴らず勝手に非常ブレーキ」と体感されていた。
    private func updateATSBellLoop() {
        let educationalAwaiting = latestOperationsSnapshot?.atsStatus?.state == .awaitingAcknowledgement
        let patternWarning = patternWarningStartTime != nil && !patternWarningAcknowledged && !patternBrakeActive
        guard educationalAwaiting || protectionNeedsAcknowledgement || patternWarning else { return }
        guard simulationTime >= atsBellNextRingTime else { return }
        let duration = audio.playATSAlarm()
        atsBellNextRingTime = simulationTime + max(duration, 0.6)
    }

    /// batch67: 速度パターン超過の段階状態機械（simulationTick
    /// から毎tick呼ばれる）。警告の開始・確認済み制動・猶予
    /// 超過の非常制動・パターン復帰での全解除だけを行い、
    /// ベルの駆動は updateATSBellLoop が担う。
    private func updatePatternWarning(exceeded: Bool) {
        if !exceeded {
            patternWarningStartTime = nil
            patternWarningAcknowledged = false
            patternBrakeActive = false
            patternBrakeEmergency = false
            return
        }
        if patternWarningStartTime == nil {
            patternWarningStartTime = simulationTime
            patternWarningAcknowledged = false
            patternBrakeActive = false
            patternBrakeEmergency = false
            return
        }
        if patternBrakeActive { return }
        if patternWarningAcknowledged {
            // 確認済みでもなお超過していれば常用制動で落とす
            // （ATS-P の確認後パターン制動に相当）。
            patternBrakeActive = true
            patternBrakeEmergency = false
        } else if let start = patternWarningStartTime,
                  simulationTime - start >= Self.atsPatternGraceSeconds {
            patternBrakeActive = true
            patternBrakeEmergency = true
        }
    }

    /// batch63: コンプレッサー実録音の簡易トリガー（MAPPING v1 仕様）。
    /// 停車中（0.5km/h 未満）で、直近にブレーキ緩解かドア開閉があり、
    /// 前回再生から25秒以上空いていれば cp_start を鳴らす。発車時
    /// （ドア閉）に再生中なら cp_end で締める。
    private func updateCompressorSound(speedKmh: Double, brakeCommand: Double, doorsOpen: Bool) {
        if previousAudioBrakeCommand > 0.05, brakeCommand <= 0.05 {
            lastBrakeReleaseOrDoorEventTime = simulationTime
        }
        if doorsOpen != previousAudioDoorsOpen {
            lastBrakeReleaseOrDoorEventTime = simulationTime
            if !doorsOpen, simulationTime < compressorSoundEndsAt {
                _ = audio.playBundledSample(named: "cp_end")
                compressorSoundEndsAt = 0
            }
        }
        previousAudioBrakeCommand = brakeCommand
        previousAudioDoorsOpen = doorsOpen

        guard speedKmh < 0.5,
              simulationTime - lastCompressorStartTime >= 25,
              simulationTime - lastBrakeReleaseOrDoorEventTime <= 20,
              let duration = audio.playBundledSample(named: "cp_start") else { return }
        lastCompressorStartTime = simulationTime
        compressorSoundEndsAt = simulationTime + duration
    }

    private func refreshOperationsSnapshot() {
        let context = nextSignalContext()
        let permitted = calculatePermittedSpeed(signal: context.reading, signalBlock: context.block)
        let snapshot = SimulatorOperationsSnapshot(
            signalReading: context.reading,
            signalDistanceM: context.block.map { max(0, $0.startM - engine.positionM) },
            permittedSpeedKmh: permitted,
            otherTrains: scheduleEngine?.frame().trains ?? [],
            atsStatus: atsSystem?.status(),
            automaticBrakeActive: false,
            automaticBrakeReason: nil,
            label: .fictionalEducational
        )
        latestOperationsSnapshot = snapshot
        operationsSnapshot = snapshot
    }

    private static func makeBlocks(route: RailwayRouteProfile) -> ThreeAspectBlockSystem {
        var blocks: [RailwayBlock] = []
        for trackID in ["T1", "T2"] {
            var start = 0.0
            var index = 0
            while start < route.distanceM {
                let end = min(start + blockLengthM, route.distanceM)
                guard end > start else { break }
                if let block = try? RailwayBlock(identifier: "fictional-\(trackID)-block-\(index)", startM: start, endM: end, trackID: trackID) {
                    blocks.append(block)
                }
                start = end
                index += 1
            }
        }
        if let system = try? ThreeAspectBlockSystem(blocks: blocks) { return system }
        // batch101: the fallback used to feed route.distanceM
        // straight into the try! below. RailwayBlock rejects a
        // non-finite endM, so a corrupt route whose distanceM is
        // +inf (or NaN, if max propagated it) turned this recovery
        // path itself into a crash — the fallback exists precisely
        // for bad route data. Sanitize the end first: for every
        // finite distanceM the fallback block is identical to
        // before, and with the end finite and >= 1 the two try!
        // constructions satisfy the types' own validation by
        // construction (non-empty identifiers, endM > startM, and
        // a single block cannot duplicate an identifier or
        // overlap itself).
        let fallbackEndM = route.distanceM.isFinite ? max(route.distanceM, 1) : 1
        let fallback = try! RailwayBlock(identifier: "fictional-block-fallback", startM: 0, endM: fallbackEndM, trackID: "T1")
        return try! ThreeAspectBlockSystem(blocks: [fallback])
    }

    private static func makeSchedule(route: RailwayRouteProfile, train: TrainParameters, blocks: ThreeAspectBlockSystem) -> RailwayScheduleEngine? {
        let length = train.estimatedTrainLengthM
        guard route.distanceM > length * 2.4 + 100 else { return nil }
        let firstPosition = route.distanceM * 0.43
        let secondPosition = route.distanceM * 0.77
        guard secondPosition - length - firstPosition >= 30 else { return nil }
        let maximumSpeed = train.maximumSpeedKmh / 3.6
        let acceleration = max(train.maximumTractionForceN / max(train.effectiveMassKg(passengerLoadFactor: 0.7), 1), 0.1)
        guard let first = try? ScheduledTrain(
            id: "fictional-local-01",
            positionM: firstPosition,
            speedMps: maximumSpeed * 0.55,
            commandedSpeedMps: maximumSpeed * 0.62,
            maximumSpeedMps: maximumSpeed,
            maximumAccelerationMps2: acceleration,
            serviceDecelerationMps2: max(train.maximumServiceBrakeDecelerationMps2, 0.2),
            lengthM: length,
            trackID: "T2"
        ), let second = try? ScheduledTrain(
            id: "fictional-local-02",
            positionM: secondPosition,
            speedMps: maximumSpeed * 0.42,
            commandedSpeedMps: maximumSpeed * 0.55,
            maximumSpeedMps: maximumSpeed,
            maximumAccelerationMps2: acceleration,
            serviceDecelerationMps2: max(train.maximumServiceBrakeDecelerationMps2, 0.2),
            lengthM: length,
            trackID: "T2"
        ) else { return nil }
        return try? RailwayScheduleEngine(
            route: route,
            blocks: blocks,
            trains: [first, second],
            minimumSeparationM: max(25, length * 0.25),
            safetyMarginM: Self.safetyMarginM
        )
    }

    private static func makeSessionMetadata(route: RailwayRouteProfile) -> DrivingSessionMetadata {
        let states = DriveSystemStates(
            signalSystem: .simulated,
            safetyProtection: .simulated,
            confirmationTracking: .simulated,
            timetable: .simulated
        )
        let criteria = DriveEvaluationCriteria(
            stopMarkerM: route.stopMarkerM,
            stopPositionToleranceM: Self.arrivalToleranceM,
            overshootToleranceM: Self.overshootToleranceM,
            stopSpeedThresholdKmh: 0.5,
            requiredStopDwellSeconds: Self.requiredArrivalDwellSeconds
        )
        return DrivingSessionMetadata(
            routeName: route.lineName,
            routeDataStatus: DriveRouteDataStatus(rawValue: route.dataStatus.rawValue) ?? .unknown,
            isVirtualSimulation: true,
            systemStates: states,
            criteria: criteria,
            notes: "架空のゲーム内運転記録。実車技能・実路線・実設備の適合性は評価しません。"
        )
    }

    /// True only when the app was launched with `-RMDemoDrive`
    /// (the CI screenshots job). Normal launches and tests never pass
    /// the argument, so the scripted drive below stays inert.
    var demoDriveEnabled: Bool {
        ProcessInfo.processInfo.arguments.contains("-RMDemoDrive")
    }

    /// Screenshot-tour mode (`-RMTour` together with
    /// `-RMDemoDrive`): instead of driving, the train is teleported
    /// between scenic chainages and held still, so one CI launch
    /// photographs many different places along the line.
    var tourEnabled: Bool {
        ProcessInfo.processInfo.arguments.contains("-RMTour")
    }

    private var lastDemoAckSeconds: Double = -10
    private var demoServedStopIndex: Int = -1
    private var demoDoorsOpenedAt: Double = -1
    private var demoStuckSince: Double = -1
    private var demoCreepUntilM: Double = -1
    private var demoCreepStage2FromM: Double = -1
    private var demoLogHandle: FileHandle?
    private var demoLogStarted = false
    private var lastDemoLogWall: TimeInterval = -10

    /// Scripted drive for screenshot runs: close the doors, depart
    /// after the (shortened) origin wait, then run the service like a
    /// driver — obey the protection's permitted speed (which falls
    /// to zero at each scheduled stop), stop at stations, work the
    /// doors, and depart again. The fictional ATS is acknowledged
    /// once a second. Ignoring the stop pattern stopped the train
    /// mid-section in CI #169; ignoring the confirmation deadline
    /// stopped it in CI #166.
    /// Demo-mode diagnostics: one state line per second into
    /// Documents/demo-drive-log.txt, pulled by the CI screenshots
    /// job. Exists because the demo stall in CI #177/#179 could not
    /// be diagnosed from screenshots alone (several HUD values are
    /// mutually inconsistent in the stall, so the true holder of
    /// the brake must be read from the model's own state).
    private func logDemoStateIfDue(wall: TimeInterval) {
        guard demoDriveEnabled, wall - lastDemoLogWall >= 1 else { return }
        lastDemoLogWall = wall
        if !demoLogStarted {
            demoLogStarted = true
            if let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
                // CI #199: the cab relaunch overwrote the tour launch's
                // log (same file), hiding the tour teleports. Keep the
                // two launches apart so both stay readable.
                let fileName = tourEnabled ? "demo-drive-log.txt" : "demo-drive-log-cab.txt"
                let url = dir.appendingPathComponent(fileName)
                FileManager.default.createFile(atPath: url.path, contents: nil)
                demoLogHandle = try? FileHandle(forWritingTo: url)
                // Startup diagnostic (CI #199: the cab launch's scene
                // stayed black/void and its log stopped at t=55, so the
                // next check needs the launch configuration on record).
                let header = "LAUNCH tour=\(tourEnabled) cabView=\(ProcessInfo.processInfo.arguments.contains("-RMCabView")) camera=\(environmentSelection.cameraPreset.rawValue) quality=\(environmentSelection.renderQuality.rawValue) timeOfDay=\(environmentSelection.timeOfDayHours) runPhase=\(runPhase.rawValue)\n"
                if let data = header.data(using: .utf8) { demoLogHandle?.write(data) }
            }
        }
        guard let handle = demoLogHandle else { return }
        // batch58 (diagnosis §2): the scene view appends its
        // census / diagnostic lines (CENSUS, TRAFFIC_DIAG,
        // DEPOT_DIAG, DEPOT_BUILD, GLB_*) to this same file
        // through its own handle, seeking to the end first.
        // Every write through THIS handle must also seek to the
        // end first — batch56's per-second writes used the
        // handle's stale offset and overwrote the view's
        // appended lines, so no diagnostic ever reached the
        // pulled log.
        // quality25 READY emission (see tourAwaitingAckIndex): the
        // gate is simulation time at least 4 s past the teleport —
        // the model and the view share the main runloop, so sim
        // time advancing means frames at the new location have been
        // presented — with the train standing at the spot.
        // 2026-11-12: a 60 s wall-clock fallback joins the gate —
        // on a loaded CI runner simulation time can advance far
        // slower than wall time (CI #412), and 60 s of presented
        // frames is more than enough for the new location to be
        // on screen.
        if tourEnabled, tourReadyPendingIndex >= 0,
           simulationTime >= tourTeleportSimTime + 4 || wall - tourTeleportWallTime >= 60,
           abs(engine.positionM - tourSpots[tourReadyPendingIndex]) < 5 {
            let line = "READY spot=\(tourReadyPendingIndex) pos=\(Int(engine.positionM))\n"
            if let data = line.data(using: .utf8) { handle.seekToEndOfFile(); handle.write(data) }
            tourAwaitingAckIndex = tourReadyPendingIndex
            tourReadyWallTime = wall
            tourReadyPendingIndex = -1
        }
        let nextPos = activeStops.indices.contains(nextStopIndex) ? activeStops[nextStopIndex].positionM : -1
        let line = String(format: "t=%.0f wall=%.0f pos=%.1f spd=%.2f drv=%d/%d app=%d/%d prot=%@ auto=%d reason=%@ perm=%.1f nidx=%d npos=%.0f door=%@ phase=%@ stuck=%.0f creep=%.0f bc=%.0f dwell=%.1f\n",
                          simulationTime, wall, engine.positionM, engine.speedMps * 3.6,
                          controls.throttleNotch, controls.brakeNotch,
                          appliedDrivingControls.throttleNotch, appliedDrivingControls.brakeNotch,
                          protectionActingSystems.isEmpty ? "-" : protectionActingSystems.joined(separator: ","),
                          (latestOperationsSnapshot?.automaticBrakeActive ?? false) ? 1 : 0,
                          latestOperationsSnapshot?.automaticBrakeReason ?? "-",
                          latestOperationsSnapshot?.permittedSpeedKmh ?? -1,
                          nextStopIndex, nextPos,
                          String(describing: gameModeDoorState), runPhase.rawValue,
                          demoStuckSince, demoCreepUntilM,
                          trainPhysicsTelemetry.brakeCylinderPressureKPa, arrivalDwellSeconds)
        if let data = line.data(using: .utf8) { handle.seekToEndOfFile(); handle.write(data) }
        // batch62: 音響テレメトリを同じ1秒周期に相乗りさせる。
        // 実機で全音声が無音になる問題の切り分け用（エンジンの
        // 開始失敗・セッション状態・警笛の呼び出し回数）。状態行と
        // 同じく seekToEndOfFile してから書く（batch58 の教訓）。
        let audioLine = audio.statusLogLine + "\n"
        if let audioData = audioLine.data(using: .utf8) { handle.seekToEndOfFile(); handle.write(audioData) }
    }

    // quality23: spots sit at curve apexes (exit visible in frame)
    // instead of on long tangents, so the route's curvature is
    // actually visible in the tour photos: 1,654 R450 / 3,006 R467 /
    // 4,466 R324 (sharpest) / 6,522 R902 / 9,081 R1076 just before
    // the river bridge / 12,986 R693 / 17,650 tunnel portal (kept) /
    // 23,475 R789 / 45,327 R1326 sea / 58,557 R845 sea.
    // quality24: the seven showcase verification spots (spec P1-P7:
    // 100 / 500 / 1,000 / 1,300 / 1,654 apex / 1,800 / 1,856 stop
    // position) lead the list, ascending, ahead of the same ten
    // line-wide spots; the screenshot script maps indices to file
    // names, so this order is part of that contract.
    // quality40: station survey — every one of the 32 stations,
    // shot from 20 m before its centre (the user's choice), so the
    // platform faces, canopies and station cores fill the frame.
    private static let tourSpotsM: [Double] = [5, 1_819, 3_851, 5_980, 8_206, 10_335, 12_367, 14_593, 16_915, 19_141, 21_270, 24_174, 26_303, 28_432, 30_657, 32_883, 35_109, 37_335, 39_561, 41_786, 44_012, 46_238, 48_464, 50_690, 52_915, 55_141, 57_367, 59_980, 61_980, 63_980, 65_980, 67_980, 6_435, 7_910, 12_067, 8_292, 28_518, 44_098, 27_200, 28_432]
    // 2026-11-14 (batch37): the last three spots are stop-marker
    // close-ups. Station-approach spots (centre − 20 m) leave the
    // batch34 diamond markers ~80–100 m away (4–5 px, unverifiable),
    // so these sit 25 m before the far-end markers at S05 石神池
    // (centre 8,226; 8-car marker +78 m, 10-car +97.5 m), S14 津田池
    // (28,452) and S21 勝沼 (44,032): from centre + 53 m both markers
    // are in frame at 25 m / 44.5 m. S05 and S21 are island stations
    // (batch36), so these also prove the island-side marker placement.
    // batch46 (2026-11-14, batch45 photo verdict): at centre + 53 m
    // the S14 frame was filled by the station wall and the board
    // stayed unreadable — the camera sat mid-platform, past the
    // island's near end. The spots move to centre + 66 m: 12 m
    // before the 8-car board (10.4 m from the forward camera at
    // the nose), so the 0.55 m board spans ~96 px with its numeral
    // legible and the 10-car board (+97.5 m) still in frame behind
    // it. All three stations are islands: the target board stands
    // on the island at route lateral −2.05, 1.95 m right of the
    // spread running track the tour train stands on.
    // 2026-11-13 (Mac photo verdict): the old crossing spots
    // (17,905 / 3,545) match no crossing the world actually
    // places (rm-crossings.txt) — 36 photographed a tunnel
    // interior and 37 an empty curve. The new spots sit 60 m
    // before real world crossings (6,495 / 7,970).
    // batch47 (2026-11-14, user: the depot has never been
    // photographed and no opposing train has ever appeared):
    // the last two spots close both gaps. Spot 38 (27,470)
    // frames Touou depot from the main line: the yard tracks
    // (27,605-27,795) carry the stabled E231 10-car (nose
    // 27,797, body 27,602-27,797 at lateral 19.5) and 117
    // 8-car (nose 27,760, body 27,604-27,760 at lateral 24.5)
    // on the depot side, so from 27,470 both consists lie
    // 130-330 m ahead at only 4-12 degrees off the view axis,
    // with the shed and office behind them. Spot 39 (28,432,
    // the S14 Tsudaike approach, same framing as spot 16)
    // photographs the tour-only opposing local that
    // generatedDiagramTrains parks at S14's down platform
    // for the whole session (see there) — a guaranteed meet
    // across the island platform, not a timing lottery.
    // batch51 (2026-11-14, batch47-49 photo verdict): neither
    // spot proved anything. (a) The meet train existed in the
    // engine but the scene was fed the bundled placeholder
    // scenario (see ContentView), so it could never render —
    // fixed in ContentView/SimulatorModel (private(set)); spot
    // 39 is unchanged and should now show the 8-car local
    // standing at S14's down main (lateral +4.0 at the island).
    // (b) The depot yard did not appear at all from 27,470.
    // (The 27,640 move this paragraph originally announced
    // never landed in tourSpotsM, and its yard figures were
    // stale besides — batch58 diagnosis §3.)
    // batch58 (2026-11-15, diagnosis §3): spot 38 now sits at
    // 27,200. The rebuild camera is FOV 66° portrait, a
    // horizontal half-FOV of only ~16.6°: from 27,470 the shed
    // centre (27,710 at depth 82.5) bore ~19.0° — outside the
    // frame no matter what rendered — while the near consists
    // (depths 19.5-24.5, 270-350 m ahead) bore 4-13° and
    // WOULD have been in frame, so the missing yard is a
    // render-loss question, not only a framing one (the yard's
    // DEPOT_BUILD line now reaches the pulled log — see
    // buildDepotYard). From 27,200 the shed bears ~9.2°
    // (~55 px tall, identifiable) and the consists 2-5°.

    /// The active tour's spots: the short-line tours launched with
    /// `-RMZooTour` / `-RMParkTour` photograph their own routes
    /// (zoo: gate, each enclosure band, terminal; park: entrance,
    /// grounds, terminal).
    private var tourSpots: [Double] {
        if ProcessInfo.processInfo.arguments.contains("-RMZooTour") {
            // 2026-11-12: spots sit BEFORE each enclosure (penguins
            // 560, lion 990, tiger 1,490, elephant 1,710) so the
            // paddocks are inside the forward view. CI #412's spots
            // were just past each paddock, so the photographs showed
            // empty fields and no animals.
            // batch50 (2026-11-14, penguins still dots in batch46):
            // the animal panels are side-profile cards, so from
            // 46-55 m along the track they are seen nearly edge-on
            // (foreshortened to ~19 px for the penguin group). Each
            // spot now sits ~13-25 m before its enclosure's near
            // panel with the panels pulled to just inside the
            // 7.6 m fence, so the group reads ~40-50 px wide
            // (penguins 544, lion 967, tiger 1,465, elephant
            // 1,677 — the elephant was already ~55 px tall, so
            // its spot moves only to centre it).
            // batch51 (2026-11-14): the batch47-49 photos settle
            // that the panels DO render — the elephant panel is
            // identifiable in 44-zoo-elephant (a ~35 px washed-out
            // shape at the paddock's far end). The failure is pure
            // geometry: at the old spots the near panel sat 46-60 m
            // ahead and only ~11-13 m to the side, so the card was
            // seen at 74-82 degrees off its normal and foreshortened
            // to a sliver. batch50 halved the distance; batch51
            // finishes the job by putting each spot where the near
            // panel bears ~35 degrees (inside the frame, clear of
            // the mascon overlay) at ~55 degrees obliquity and
            // 10.6-12.1 m range: penguins 548 (panel 556.5 at
            // lateral 8.2, figure ~69 px tall), lion 971 and tiger
            // 1,471 (panels at centre-9, lateral 9.0, ~66-69 px),
            // elephant 1,691 (panel 1,701, figure ~166 px).
            return [80, 548, 971, 1_471, 1_691, 2_430]
        }
        if ProcessInfo.processInfo.arguments.contains("-RMParkTour") {
            // 2026-11-12: the ferris wheel (centre 1,280) is shot
            // from 1,080 so it stands ahead in the frame; from the
            // old 1,300 spot it was behind the camera (CI #412).
            return [120, 900, 1_080, 1_930]
        }
        return Self.tourSpotsM
    }
    private var tourSpotIndex = -1
    private var firstTourWallTime: TimeInterval = -1
    // quality24: after a teleport, the world rebuild can outlast the
    // screenshot script's old fixed wait, so captures drifted a spot
    // behind (CI #221: spots 3,006 and 9,081 never photographed).
    // The model knows when it is back: once simulation time has
    // advanced past the teleport with the train at the spot, frames
    // at the new location have been presented (model and view share
    // the main runloop), so it writes a READY line and the script
    // photographs on READY instead of on a timer.
    private var tourReadyPendingIndex = -1
    private var tourTeleportSimTime = 0.0
    private var tourTeleportWallTime: TimeInterval = -1
    // quality25 (E): READY alone did not fix the drift (CI #232:
    // only 7 of 16 spots photographed at their labelled positions,
    // three pure black, six the same stretch of coast). The app
    // advanced on its own 35 s wall schedule while simctl took
    // tens of seconds per screenshot, so by the time a capture
    // executed the train had teleported on. The tour is now a
    // two-way handshake: after READY the app HOLDS the spot until
    // the script writes Documents/tour-ack-<i>.txt (it writes the
    // ACK only after a successful screenshot), with a 900 s
    // timeout so a dead script can never stall the tour or the
    // job. 2026-11-11: the timeout was 150 s, but CI #409 showed
    // a single wedged simctl screenshot can block for 300-900 s —
    // the app timed out and teleported on mid-capture, so files
    // were labelled with the wrong stations (06-st03-oginuma.png
    // actually showed Akimizu). 900 s outlasts any single capture
    // the script will still retry, and the script's own recovery
    // (relaunch, then simulator reboot) releases the hold sooner
    // in practice.
    private var tourAwaitingAckIndex = -1
    private var tourReadyWallTime: TimeInterval = -1
    private var tourLastAckCheckWall: TimeInterval = -1

    private func driveTourIfEnabled() {
        let now = Date().timeIntervalSinceReferenceDate
        if firstTourWallTime < 0 { firstTourWallTime = now }
        let elapsed = now - firstTourWallTime
        if tourSpotIndex < 0 {
            // First teleport only once the world has had time to
            // build: wall 25 s AND simulation time 15 s (the
            // black frames in CI #232 were early spots photographed
            // while the first build was still presenting nothing).
            // 2026-11-12: the wall-150 s alternative keeps the tour
            // moving when simulation time advances far slower than
            // wall time on a loaded runner (CI #412 waited 422 s
            // for simulation time 15).
            if elapsed >= 25, simulationTime >= 15 || elapsed >= 150 {
                tourSpotIndex = 0
                teleportForTour(to: tourSpots[0])
                logTourTeleport(to: tourSpots[0], spotIndex: 0)
                tourReadyPendingIndex = 0
                tourTeleportSimTime = simulationTime
                tourTeleportWallTime = now
            }
        } else if tourAwaitingAckIndex == tourSpotIndex, tourReadyWallTime >= 0 {
            // READY is out for the current spot: wait for the
            // script's ACK (checked about twice a second), or time
            // out after 900 s and move on regardless.
            if now - tourLastAckCheckWall >= 0.5 {
                tourLastAckCheckWall = now
                let acknowledged = tourAckExists(for: tourSpotIndex)
                if acknowledged || now - tourReadyWallTime >= 900 {
                    if !acknowledged {
                        logTourLine("ACKTIMEOUT spot=\(tourSpotIndex)\n")
                    }
                    tourAwaitingAckIndex = -1
                    tourReadyWallTime = -1
                    let next = tourSpotIndex + 1
                    if next < tourSpots.count {
                        tourSpotIndex = next
                        teleportForTour(to: tourSpots[next])
                        logTourTeleport(to: tourSpots[next], spotIndex: next)
                        tourReadyPendingIndex = next
                        tourTeleportSimTime = simulationTime
                        tourTeleportWallTime = now
                    }
                }
            }
        }
        // Hold the train still for the photograph.
        controls = TrainControls(throttleNotch: 0, brakeNotch: 3, emergencyBrake: false)
    }

    private func tourAckExists(for index: Int) -> Bool {
        guard let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return false }
        return FileManager.default.fileExists(atPath: dir.appendingPathComponent("tour-ack-\(index).txt").path)
    }

    private func logTourLine(_ line: String) {
        guard let handle = demoLogHandle else { return }
        // batch58: seek first — see logDemoStateIfDue.
        if let data = line.data(using: .utf8) { handle.seekToEndOfFile(); handle.write(data) }
    }

    private func logTourTeleport(to position: Double, spotIndex: Int) {
        guard let handle = demoLogHandle else { return }
        let line = "TOUR spot=\(spotIndex) pos=\(Int(position)) wall=\(Int(Date().timeIntervalSinceReferenceDate))\n"
        // batch58: seek first — see logDemoStateIfDue.
        if let data = line.data(using: .utf8) { handle.seekToEndOfFile(); handle.write(data) }
    }

    private func teleportForTour(to position: Double) {
        engine.placeAt(positionM: position)
        if activeStops.isEmpty {
            nextStopIndex = 0
        } else if let idx = activeStops.firstIndex(where: { $0.positionM > position + 1 }) {
            nextStopIndex = idx
        } else {
            nextStopIndex = activeStops.count - 1
        }
        arrivalDwellSeconds = 0
        gameModeCurrentStationID = nil
        scoringStationID = nil
        pendingScoringDepartureStationID = nil
        rebuildProtectionSession()
    }

    /// Speed cap from the fictional protection layer's own devices
    /// (see driveDemoIfEnabled). Mirrors the layout constants in
    /// FictionalLiveProtectionLayout and the ATS-P pattern maths
    /// (0.8 m/s², 8 m margin), staying 3 km/h under the envelope.
    private func fictionalProtectionCapKmh(at position: Double) -> Double {
        var cap = Double.greatestFiniteMagnitude
        let period = 4_000.0
        var targetPosition = 1_400.0
        while targetPosition <= position { targetPosition += period }
        let distance = targetPosition - position
        if distance > 0 {
            let targetMps = 45.0 / 3.6
            let envelope = sqrt(targetMps * targetMps + 2 * 0.8 * max(0, distance - 8)) * 3.6
            cap = min(cap, envelope - 3)
        }
        // ATC command zones sit at 1,800-1,950 m of each period and
        // command 55 km/h; start slowing 300 m before the zone.
        let inPeriod = position.truncatingRemainder(dividingBy: period)
        if inPeriod >= 1_500 && inPeriod <= 2_000 {
            cap = min(cap, 52)
        }
        return cap
    }

    private func driveDemoIfEnabled() {
        guard demoDriveEnabled, runPhase == .running else { return }
        if tourEnabled {
            driveTourIfEnabled()
            return
        }
        let t = simulationTime
        if t >= 30, gameModeDoorState.isOpen, demoServedStopIndex < 0 {
            handleGameModeHostEffects([.setGameDoorState(.closed)])
        }
        guard t >= 50 else { return }
        if t - lastDemoAckSeconds >= 1 {
            lastDemoAckSeconds = t
            acknowledgeATS()
        }
        let speedKmh = max(0, engine.speedMps * 3.6)

        // Station stop: hold, open the doors once, close them after
        // 12 s, and depart once they are shut.
        if activeStops.indices.contains(nextStopIndex) {
            let stopPosition = activeStops[nextStopIndex].positionM
            let distanceToStop = stopPosition - engine.positionM
            if speedKmh <= 0.5 && abs(distanceToStop) <= Self.arrivalToleranceM {
                if demoServedStopIndex != nextStopIndex {
                    demoServedStopIndex = nextStopIndex
                    demoDoorsOpenedAt = t
                    if !gameModeDoorState.isOpen {
                        handleGameModeHostEffects([.setGameDoorState(travelDirection == .up ? .openRight : .openLeft)])
                    }
                } else if t - demoDoorsOpenedAt >= 12 && gameModeDoorState.isOpen {
                    handleGameModeHostEffects([.setGameDoorState(.closed)])
                }
                if gameModeDoorState.isOpen || t - demoDoorsOpenedAt < 14 {
                    setThrottle(0)
                    setBrake(3)
                    return
                }
            }
        }

        // The fictional protection layer has its own stop targets
        // (an ATS-P profile target every 4 km) that the operations
        // snapshot does not show. When it stops the train away from
        // a station, do what a driver does: wait for the reset (the
        // per-second acknowledgement above requests it), then creep
        // past the target — slowly at first, then at 40 km/h — so
        // the pattern is not exceeded again on the way out.
        let distanceToNextStop = activeStops.indices.contains(nextStopIndex)
            ? activeStops[nextStopIndex].positionM - engine.positionM
            : Double.greatestFiniteMagnitude
        if speedKmh <= 0.5 && distanceToNextStop > 10 && !gameModeDoorState.isOpen {
            if demoStuckSince < 0 { demoStuckSince = t }
        } else if speedKmh > 0.5 {
            demoStuckSince = -1
        }
        if demoStuckSince >= 0 && t - demoStuckSince >= 4 && demoCreepUntilM < engine.positionM {
            demoCreepStage2FromM = engine.positionM + 30
            demoCreepUntilM = engine.positionM + 200
            demoStuckSince = -1
        }

        // Cruise under the protection's permitted speed, with a
        // gentle final approach to the next scheduled stop.
        var target = min(65, (latestOperationsSnapshot?.permittedSpeedKmh ?? 65) - 2)
        // The fictional protection layer also supervises its own
        // repeating devices, which the snapshot does not show: an
        // ATS-P profile target (45 km/h) at 1,400 m + every 4 km,
        // and an ATC 55 km/h zone in each period. Exceeding one
        // latches a brake that only a full stop and reset clears,
        // so a driver who knows the route slows for them in time.
        target = min(target, fictionalProtectionCapKmh(at: engine.positionM))
        if engine.positionM < demoCreepUntilM {
            if engine.positionM < demoCreepStage2FromM {
                target = min(target, 10)
            } else {
                target = min(target, 40)
            }
        }
        if activeStops.indices.contains(nextStopIndex) {
            let distanceToStop = activeStops[nextStopIndex].positionM - engine.positionM
            if distanceToStop < 60 { target = min(target, 12) }
            if distanceToStop < 25 { target = min(target, 6) }
            if distanceToStop < 1.5 && speedKmh > 1 {
                setThrottle(0)
                setBrake(5)
                return
            }
        }
        target = max(0, target)
        if speedKmh > target + 3 {
            setThrottle(0)
            setBrake(3)
        } else if speedKmh > target + 0.5 {
            setThrottle(0)
            setBrake(1)
        } else if speedKmh < target - 3 {
            setBrake(0)
            setThrottle(3)
        } else if speedKmh < target {
            setBrake(0)
            setThrottle(1)
        } else {
            setThrottle(0)
            setBrake(0)
        }
    }

    // batch71: handle-cue coalescing (BVE's firing model: a
    // handle OPERATION is the unit — [Master Controller] fires
    // once per operation, [Brake] air sounds are BC-pressure
    // events). The lever reports every detent it crosses during
    // a drag, so an EB→N sweep used to fire the EB release pair
    // plus one brake-release sample per detent, and the samples
    // piled up audibly behind the operation. The setters now only
    // RECORD the burst: the first change of a burst captures the
    // pre-gesture controls and schedules one flush 120 ms later;
    // the flush voices at most one cue per family for the NET
    // change (EB pair, one brake-air cue at the final notch's
    // level / the single strongest release, one controller step
    // for the net throttle move). Physics controls still apply
    // immediately — only the sound is coalesced.
    private var handleCueBurstStart: TrainControls?
    private var handleCueFlushTask: Task<Void, Never>?

    private func noteHandleCueBurst(previousControls: TrainControls) {
        if handleCueBurstStart == nil { handleCueBurstStart = previousControls }
        if handleCueFlushTask == nil {
            handleCueFlushTask = Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 120_000_000)
                self?.flushHandleCues()
            }
        }
    }

    private func flushHandleCues() {
        handleCueFlushTask = nil
        guard let start = handleCueBurstStart else { return }
        handleCueBurstStart = nil
        let end = controls
        if end.emergencyBrake != start.emergencyBrake {
            if end.emergencyBrake {
                _ = audio.playBundledSample(named: "eb_on")
                _ = audio.playBundledSample(named: "eb_apply")
            } else {
                _ = audio.playBundledSample(named: "eb_off")
                _ = audio.playBundledSample(named: "eb_release")
            }
        }
        if end.brakeNotch > start.brakeNotch {
            let level = min(4, max(1, (end.brakeNotch + 1) / 2))
            _ = audio.playBrakeAirSample(named: "brake_apply_\(level)")
        } else if end.brakeNotch < start.brakeNotch {
            let bigRelease = start.brakeNotch - end.brakeNotch >= 3 || (start.brakeNotch >= 5 && end.brakeNotch == 0)
            _ = audio.playBrakeAirSample(named: bigRelease ? "brake_release_long" : "brake_release")
        }
        // batch78: B7 到達のハンドルクリック（mec B7on →
        // brake_max_click）。この flush へ来るのは setBrake 等の
        // 運転士操作バーストだけ（ATS 等の自動制動は setter を
        // 通らない）なので、B7 未満から B7 へ入ったバーストで
        // 1 回だけ鳴らせば「突入ごとに 1 回」になる。
        if end.brakeNotch == 7, start.brakeNotch < 7 {
            _ = audio.playBundledSampleOneShot(named: "brake_max_click")
        }
        if end.throttleNotch != start.throttleNotch {
            audio.playControllerStep(from: start.throttleNotch, to: end.throttleNotch)
        }
    }

    func setThrottle(_ notch: Int) {
        guard runPhase == .running else { return }
        let value = min(max(notch, 0), max(train.tractionNotchFractions.count - 1, 0))
        let previousControls = controls
        controls = TrainControls(
            throttleNotch: value,
            brakeNotch: value > 0 ? 0 : controls.brakeNotch,
            emergencyBrake: controls.emergencyBrake,
            masterReversed: value == 0 && controls.masterReversed
        )
        noteProtectionDriverActivity()
        // batch67→71: ノッチ操作音はハンドル操作イベント単位
        // （BVE sound.cfg [Master Controller]）。発火は
        // flushHandleCues へ集約（batch71 のコメント参照）。
        if controls != previousControls {
            noteHandleCueBurst(previousControls: previousControls)
        }
    }

    func setBrake(_ notch: Int) {
        guard runPhase == .running else { return }
        let value = min(max(notch, 0), 7)
        let previousControls = controls
        controls = TrainControls(
            throttleNotch: value > 0 ? 0 : controls.throttleNotch,
            brakeNotch: value,
            emergencyBrake: controls.emergencyBrake,
            masterReversed: controls.masterReversed && value == 0
        )
        noteProtectionDriverActivity()
        // batch63→71: ブレーキ空気音（実録・強さ連動）は
        // flushHandleCues が正味の段数変化に対して1回だけ発火
        // する（込めは最終段のレベル brake_apply_1..4、緩めは
        // brake_release／大きく緩める場合は brake_release_long）。
        // setBrake を通らない遷移（ATS 指令等）は DSP トグル側が担保する。
        if controls != previousControls {
            noteHandleCueBurst(previousControls: previousControls)
        }
    }

    func setEmergencyBrake(_ isOn: Bool) {
        guard runPhase == .running else { return }
        let previousControls = controls
        controls = TrainControls(
            throttleNotch: isOn ? 0 : controls.throttleNotch,
            brakeNotch: controls.brakeNotch,
            emergencyBrake: isOn,
            masterReversed: controls.masterReversed && !isOn
        )
        noteProtectionDriverActivity()
        // batch63→71: 非常の操作音＋空気音（実録）も
        // flushHandleCues へ集約。警報ブザー
        // （playEmergencyBrakeAlert）は従来どおり合成のまま。
        if controls != previousControls {
            noteHandleCueBurst(previousControls: previousControls)
        }
    }

    func setMasterReversed(_ isOn: Bool) {
        guard runPhase == .running else { return }
        let resistanceFormation = selectedVehicleProfile == .resistanceFormation8 || selectedVehicleProfile == .resistanceFormation10
        let reversed = isOn && resistanceFormation
        controls = TrainControls(
            throttleNotch: reversed ? 0 : controls.throttleNotch,
            brakeNotch: controls.brakeNotch,
            emergencyBrake: controls.emergencyBrake,
            masterReversed: reversed
        )
        noteProtectionDriverActivity()
    }

    func setTimetableOptions(
        calendar: RailwayTimetable.ServiceCalendar,
        daypart: RailwayTimetable.Daypart,
        initialDelayMinutes: Int
    ) {
        timetableCalendar = calendar
        timetableDaypart = daypart
        timetableInitialDelayMinutes = min(max(initialDelayMinutes, 0), 30)
        timetableSelection = makeTimetableSelection(originStationID: activeStops.first?.stationID)
        if simulationTime <= 0.000_1 && isAtOriginPosition && runPhase == .running {
            rebuildStopScoringSession()
        } else {
            timetableSettingsPendingRestart = true
        }
    }

    private func makeTimetableSelection(originStationID: String?) -> RegionalTimetableSelection? {
        guard routeVariant != .depotTransfer else {
            timetableSelectionError = "車庫入出庫は旅客時刻表・駅別停車採点の対象外です。"
            return nil
        }
        guard let network = timetableNetwork, let originStationID else {
            timetableSelectionError = "架空の正本時刻表を読み込めませんでした。"
            return nil
        }
        // batch93: selectRun is a deterministic function of
        // (network, category, direction, calendar, daypart,
        // delay, origin) — the network is fixed once loaded and
        // DisruptionSimulator carries no randomness — yet every
        // reset() re-ran its network-wide disruption simulation
        // for identical inputs (a plain route selection or
        // restart changes none of them). Reuse the last
        // selection when every input matches; the success
        // path's side effects (error cleared) are reproduced.
        let memoKey = "\(serviceCategory.rawValue)|\(travelDirection.rawValue)|\(timetableCalendar.rawValue)|\(timetableDaypart.rawValue)|\(timetableInitialDelayMinutes)|\(originStationID)"
        if memoizedTimetableSelectionKey == memoKey, let memoizedTimetableSelection {
            timetableSelectionError = nil
            return memoizedTimetableSelection
        }
        do {
            let selection = try RegionalTimetableAdapter.selectRun(
                network: network,
                category: serviceCategory,
                direction: travelDirection,
                calendar: timetableCalendar,
                daypart: timetableDaypart,
                initialDelayMinutes: timetableInitialDelayMinutes,
                routeOriginStationID: originStationID
            )
            timetableSelectionError = nil
            memoizedTimetableSelectionKey = memoKey
            memoizedTimetableSelection = selection
            return selection
        } catch {
            timetableSelectionError = "架空時刻表を現在の運転条件へ結び付けられませんでした: \(error.localizedDescription)"
            return nil
        }
    }

    /// batch93: memo key for factoryTrip — the (variant,
    /// category, direction) triple is the whole input space of
    /// RegionalRouteFactory.make at its fixed default geometry
    /// seed, for a given plan.
    private static func factoryTripKey(variant: RegionalRouteVariant, category: ServiceCategory, direction: RegionalTravelDirection) -> String {
        "\(variant.rawValue)|\(category.rawValue)|\(direction.rawValue)"
    }

    /// batch93: RegionalRouteFactory.make is a pure function of
    /// (plan, variant, category, direction) — same seed, same
    /// geometry, per the factory's own contract — yet one
    /// session build used to run it two or three times for
    /// identical inputs: init and selectRoute make the trip,
    /// then reset()'s rebuildStopScoringSession makes it again.
    /// This memo hands back the identical value instead. Only
    /// regionalPlan-driven session builds use it; the save
    /// restore path keeps its own direct make, because it
    /// validates the saved state against a fresh build.
    private func factoryTrip(plan: FictionalOperationsPlan, variant: RegionalRouteVariant, category: ServiceCategory, direction: RegionalTravelDirection) -> RegionalPlayableRoute? {
        let key = Self.factoryTripKey(variant: variant, category: category, direction: direction)
        if memoizedFactoryTripKey == key, let memoizedFactoryTrip {
            return memoizedFactoryTrip
        }
        let trip = try? RegionalRouteFactory.make(plan: plan, variant: variant, category: category, direction: direction)
        memoizedFactoryTripKey = key
        memoizedFactoryTrip = trip
        return trip
    }

    @discardableResult
    func selectRoute(variant: RegionalRouteVariant, category: ServiceCategory, direction: RegionalTravelDirection) -> Bool {
        guard let plan = regionalPlan,
              let trip = factoryTrip(plan: plan, variant: variant, category: category, direction: direction) else {
            storageNotice = "選択した架空路線・種別・方向を準備できませんでした。路線データを確認してください。"
            return false
        }
        storageNotice = nil
        applyFormationProfile(category: category, variant: variant)
        route = trip.profile
        activeStops = trip.stops
        routeID = trip.routeID
        dataValidationIssues = trip.profile.validateData()
        routeVariant = variant
        serviceCategory = category
        travelDirection = direction
        blockSystem = Self.makeBlocks(route: trip.profile)
        routeApplyProgressHandler?(1, "運行データを準備しています")
        reset()
        routeApplyProgressHandler?(3, "世界を構築しています")
        return true
    }

    /// Formation rules (user decision, 2026-11-11): the limited
    /// express is always the resistance-control 8-car formation
    /// (the 117 series, resistor control as specified); locals and
    /// the branch, zoo and park shuttles are always 8 cars; the
    /// other categories run 10 cars on the main line and 8 cars on
    /// through-branch services, whose 170 m platforms cannot take
    /// a 195 m 10-car train. The VVVF formations carry the E231
    /// exterior and the resistance formation the 117 (scene-side
    /// selection keys off profile car count and control family).
    private func applyFormationProfile(category: ServiceCategory, variant: RegionalRouteVariant) {
        if variant == .branchShuttle || variant == .zooLine || variant == .parkLine {
            selectVehicleProfile(.vvvfFormation8)
            return
        }
        switch category {
        case .limitedExpress:
            selectVehicleProfile(.resistanceFormation8)
        case .local:
            selectVehicleProfile(.vvvfFormation8)
        case .rapidExpress, .express, .rapid, .semiExpress:
            if variant == .throughBranch {
                selectVehicleProfile(.vvvfFormation8)
            } else {
                selectVehicleProfile(.vvvfFormation10)
            }
        }
    }

    private func rebuildStopScoringSession() {
        stopScoringEngine = nil
        stopScoringOriginTargetM = nil
        stopScoringEvaluation = nil
        stopScoringError = nil
        scoringStationID = nil
        pendingScoringDepartureStationID = nil
        stopScoringTickSequence = 0
        stopScoringEventSequence = 0
        pendingStopScoringEvents.removeAll(keepingCapacity: true)
        timetableSelection = nil
        timetableSelectionError = nil
        appliedTimetableDepartureDelaySeconds = 0
        timetableSettingsPendingRestart = false

        guard let plan = regionalPlan,
              let routePackage = canonicalRoutePackage,
              let trip = factoryTrip(plan: plan, variant: routeVariant, category: serviceCategory, direction: travelDirection) else {
            stopScoringError = "架空の正本路線・ホームデータを読み込めず、駅別停車スコアを準備できません。"
            return
        }
        timetableSelection = makeTimetableSelection(originStationID: trip.stops.first?.stationID)
        appliedTimetableDepartureDelaySeconds = timetableSelection?.routeOriginDelaySeconds ?? 0
        if demoDriveEnabled {
            // Screenshot runs cannot wait out the full origin delay.
            appliedTimetableDepartureDelaySeconds = min(appliedTimetableDepartureDelaySeconds, 45)
        }
        timetableSettingsPendingRestart = false
        let scheduleByStationID = timetableSelection.map {
            RegionalTimetableAdapter.stopSchedules(from: $0, activeStops: trip.stops)
        } ?? [:]
        do {
            let prepared = try StopScoringRouteAdapter.prepare(
                trip: trip,
                plan: plan,
                routePackage: routePackage,
                trainLengthMeters: train.estimatedTrainLengthM,
                scheduleByStationID: scheduleByStationID
            )
            activeStops = prepared.activeStops
            stopScoringEngine = prepared.engine
            stopScoringOriginTargetM = prepared.originTargetM
            stopScoringEvaluation = prepared.engine.evaluation()
        } catch {
            stopScoringError = "架空の駅別停車スコアを準備できませんでした: \(String(describing: error))"
        }
    }

    func setGameModeSession(_ session: GameModeSession?) {
        gameModeSession = session
        // batch108: a session change abandons any departure
        // sequence in flight (the auto cycle does not run while
        // a game-mode session is in charge).
        departureSequenceCloseAt = nil
        departureBuzzerArmed = false
        departureBuzzerAt = nil
        if session == nil {
            pendingDoorClose = nil
            gameModeDoorState = .closed
            gameModeHostNotice = nil
        }
    }

    /// Recorded door sound bundled for the selected control family.
    /// The resistance family shares the chopper recordings (project
    /// decision, 2026-11-07); VVVF families use the E231-series
    /// recordings (batch63). Nil means no recording is bundled for
    /// that family.
    private func bundledDoorSampleName(open: Bool, side: GameModeDoorState) -> String? {
        switch selectedVehicleProfile.soundProfile {
        case .fieldChopperDC, .rheostaticDC:
            if open { return "door_open_chopper" }
            return "door_close_chopper"
        case .vvvfGTO, .vvvfIGBT, .vvvfIGBTVariableCarrier, .vvvfSiC:
            // batch79: E231 のドア音は Primrose 更新車（Sound_R）
            // セットへ移行し、開扉側で _L / _R を選ぶ。側が
            // 特定できない場合は無印（中央ミックス）を使う。
            // open1 / close1 は予備テイクとして同梱のみ（BVE
            // 本体でも未参照のため、トリガーには載せない）。
            switch (open, side) {
            case (true, .openRight): return "door_open_prim_r_r"
            case (true, .openLeft): return "door_open_prim_r_l"
            case (true, _): return "door_open_prim_r"
            case (false, .openRight): return "door_close_prim_r_r"
            case (false, .openLeft): return "door_close_prim_r_l"
            case (false, _): return "door_close_prim_r"
            }
        }
    }

    /// batch79: Primrose セットが欠けた場合のフォールバック先
    /// （従来の LEYokohama kozu セット）。VVVF 系以外は nil。
    private func doorFallbackSampleName(open: Bool) -> String? {
        switch selectedVehicleProfile.soundProfile {
        case .fieldChopperDC, .rheostaticDC:
            return nil
        case .vvvfGTO, .vvvfIGBT, .vvvfIGBTVariableCarrier, .vvvfSiC:
            if open { return "door_open_e231" }
            return "door_close_e231"
        }
    }

    /// Plays the recorded door sound for the selected vehicle when one
    /// is bundled, falling back to the synthesized door cue.
    /// batch67: フォールバック判定は「実際に鳴ったか」。従来は
    /// playBundledSample の duration 返却（無音でも返る）を発音
    /// 成功とみなしていたため、ドア閉音が無音のまま合成にも
    /// 落ちず消えていた。
    /// batch79: 開扉側（GameModeDoorState）を音選択まで通す。
    /// 閉扉時は「開いていた側」を呼び出し側が渡す。Primrose が
    /// 鳴らなかった場合のみ kozu セットへ、それも駄目なら合成へ。
    /// batch108: 鳴った実録サンプルの長さ（秒）を返すよう変更
    /// （合成フォールバック時は 0）。batch109: 知らせブザーは
    /// 閉扉音の長さではなく閉まり切ってから 0.5〜5 秒のランダム
    /// 遅延で鳴るため、この戻り値はブザー予約には使わない。
    @discardableResult
    private func playDoorSound(open: Bool, side: GameModeDoorState = .unknown) -> TimeInterval {
        if let name = bundledDoorSampleName(open: open, side: side),
           let seconds = audio.playBundledSampleOneShotWithDuration(named: name) {
            return seconds
        }
        if let fallback = doorFallbackSampleName(open: open),
           let seconds = audio.playBundledSampleOneShotWithDuration(named: fallback) {
            return seconds
        }
        audio.playDoor(open: open)
        return 0
    }

    /// batch67: 発車メロディ（発車ベル）。停車中の駅でドアが
    /// 閉まった瞬間に、その駅キーで1回だけ鳴らす。従来は
    /// DepartureMelodyCatalog が設定シートのテストボタンにしか
    /// 繋がっておらず、発車シーケンスでは一度も鳴らなかった。
    /// batch108: メロディの長さを返すよう変更。自動ドアサイクルの
    /// 発車シーケンスは閉扉の前にこれを呼び、戻り値の長さだけ
    /// 待ってから閉扉する。閉扉側からの呼び出し（ゲームモード
    /// 駆動の閉扉など）は従来どおり閉扉時に鳴らし、シーケンスが
    /// 先に鳴らした停車ではフラグにより二重発音しない。
    @discardableResult
    private func playDepartureBellIfAtStation() -> Double {
        guard !departureBellPlayedForCurrentStop else { return 0 }
        guard engine.speedMps * 3.6 < 0.5 else { return 0 }
        guard let stop = activeStops.first(where: { abs($0.positionM - engine.positionM) <= Self.arrivalToleranceM }) else { return 0 }
        departureBellPlayedForCurrentStop = true
        return audio.playDepartureChime(stationID: stop.stationID)
    }

    /// Applies a door closure that was held back until the recorded door
    /// chime finished playing.
    private func applyPendingDoorCloseIfDue() {
        guard let pending = pendingDoorClose, simulationTime >= pending.applyAt else { return }
        pendingDoorClose = nil
        let wasOpen = gameModeDoorState.isOpen
        // batch79: 閉扉音の左右選択用に、開いていた側を上書き
        // 前に控える。
        let closingSide = gameModeDoorState
        gameModeDoorState = pending.state
        if wasOpen {
            // batch67: 従来は合成 playDoor 直呼びで実録の閉扉音を
            // 経由しなかった。playDoorSound に統一する。
            playDoorSound(open: false, side: closingSide)
            playDepartureBellIfAtStation()
            scheduleDepartureBuzzerIfArmed()
        }
        gameModeHostNotice = "架空ゲームのドア状態を「\(pending.state.rawValue)」に更新しました。物理モデルのドアではありません。"
    }

    // batch71: automatic door cycle for NORMAL driving. Door
    // open/close used to be driven only by the fictional
    // game-mode session's host effects (and by the demo script),
    // so on a plain route-selection drive — no game-mode sheet
    // opened — the doors never moved at all: no door sounds, no
    // departure bell, at any station, which the user reported on
    // device. The cycle below reuses the same host-effect path
    // (recorded door sounds + departure bell on close) whenever
    // no game-mode session is in charge: open on arrival at a
    // scheduled stop (the origin included, for boarding), close
    // after a 12 s dwell or as soon as the train moves off,
    // whichever comes first. The game-mode host notice is
    // cleared after each automatic operation — these are the
    // train's real doors now, not a game overlay state.
    //
    // batch108 (user directive, 2026-11-16): the close side of
    // the cycle is now a departure SEQUENCE, and the old
    // "close as soon as the train moves off" trigger is gone —
    // the door interlock (see simulationTick) makes moving off
    // with the doors open impossible, so closing is purely
    // sequence/timer-driven:
    //   1. Trigger: at the origin, the scheduled departure
    //      − 12 s (the session clock is anchored 30 s before
    //      the scheduled origin departure, so this is session
    //      t = 18); at later stops, the end of the 12 s dwell.
    //   2. The departure bell plays (playDepartureBellIfAtStation).
    //   3. When the bell has finished, the doors close through
    //      the existing host-effect path (resistance stock still
    //      waits out its recorded door chime first).
    //   4. When the doors land fully closed, the notification
    //      buzzer is scheduled (scheduleDepartureBuzzerIfArmed);
    //      batch109: it sounds 0.5–5.0 s later (random) and is
    //      not a departure condition — the player may already
    //      be moving when it sounds.
    // The player may depart as soon as the doors are closed;
    // nothing holds the train until the scheduled second.
    private var autoDoorServedStationID: String?
    /// batch108: the departure-sequence trigger time (session
    /// seconds) for the currently open doors — despite the name
    /// it no longer closes the doors directly; it starts the
    /// bell → close → buzzer sequence.
    private var autoDoorCloseAt: Double?
    /// batch108: session time at which the sequence issues the
    /// door close (set once the departure bell has been played;
    /// the close waits for the bell to finish).
    private var departureSequenceCloseAt: Double?
    /// batch108: the sequence has issued its close and the
    /// notification buzzer is owed once the doors land closed.
    private var departureBuzzerArmed = false
    /// batch108: session time at which the notification buzzer
    /// sounds. batch109: close landing + a random 0.5–5.0 s
    /// delay (see scheduleDepartureBuzzerIfArmed).
    private var departureBuzzerAt: Double?

    /// batch108: scheduled origin departure, in session seconds.
    /// The session clock is anchored so the chosen trip's
    /// (delay-adjusted) origin departure falls exactly here —
    /// the session starts 30 s before departure.
    private static let originDepartureSessionSeconds = 30.0

    /// batch108: true for the scheduled passenger services
    /// (mainline / through-branch / branch shuttle) with a
    /// timetable selection. Depot, zoo and park free running
    /// have no player schedule: no sequence anchor and no HUD
    /// station times.
    private var hasPlayerSchedule: Bool {
        switch routeVariant {
        case .mainline, .throughBranch, .branchShuttle:
            return timetableSelection != nil
        case .depotTransfer, .zooLine, .parkLine:
            return false
        }
    }

    /// batch108: the chosen trip's origin event in the simulated
    /// (delay-adjusted) timetable — the same diagram data the
    /// stop scoring and the AI traffic are built from
    /// (FictionalOperationsPlan via the canonical network).
    private var scheduledOriginEvent: RailwayTimetable.SimulatedStationEvent? {
        guard hasPlayerSchedule, let selection = timetableSelection else { return nil }
        return selection.simulatedTrip.stationEvents.first(where: { $0.stationID == selection.routeOriginStationID })
    }

    private var scheduledOriginDepartureDaySeconds: Int? {
        scheduledOriginEvent?.departureSeconds
    }

    private func scheduledEvent(forStationID stationID: String) -> RailwayTimetable.SimulatedStationEvent? {
        guard hasPlayerSchedule, let selection = timetableSelection else { return nil }
        return selection.simulatedTrip.stationEvents.first(where: { $0.stationID == stationID && $0.kind == .stop })
    }

    /// batch108: time of day (seconds after midnight) at
    /// simulationTime 0. Scheduled services anchor to the
    /// chosen trip's origin departure − 30 s; free-running
    /// modes keep the traffic clock's zero (05:30 = 19,800 s),
    /// the same zero the AI scenario runs on.
    var gameClockAnchorDaySeconds: Double {
        if let originDeparture = scheduledOriginDepartureDaySeconds {
            return Double(originDeparture) - Self.originDepartureSessionSeconds
        }
        return 19_800
    }

    /// batch108: formats seconds-after-midnight as HH:MM:SS.
    /// Hours are not wrapped at 24 — the timetable's own
    /// convention allows next-day times past 86,400 s, and the
    /// clock and the schedule lines share the same base.
    static func formatGameClock(daySeconds: Double) -> String {
        let total = max(0, Int(daySeconds.rounded()))
        return String(format: "%02d:%02d:%02d", total / 3_600, (total % 3_600) / 60, total % 60)
    }

    /// batch108: current game time for the driving HUD.
    var gameClockText: String {
        Self.formatGameClock(daySeconds: gameClockAnchorDaySeconds + simulationTime)
    }

    /// batch108: the timetable line for the driving HUD — while
    /// stopped at a station, that station's scheduled departure
    /// (発); while running, the next stop's scheduled arrival
    /// (着). Nil for modes without a schedule, and at the final
    /// stop (no departure remains).
    var hudScheduleLine: String? {
        guard hasPlayerSchedule else { return nil }
        if engine.speedMps * 3.6 <= 0.5,
           let stop = activeStops.first(where: { abs($0.positionM - engine.positionM) <= Self.arrivalToleranceM }),
           stop.stationID != activeStops.last?.stationID,
           let event = scheduledEvent(forStationID: stop.stationID) {
            return "\(stop.name) 発 \(Self.formatGameClock(daySeconds: Double(event.departureSeconds)))"
        }
        guard activeStops.indices.contains(nextStopIndex) else { return nil }
        let next = activeStops[nextStopIndex]
        guard let event = scheduledEvent(forStationID: next.stationID) else { return nil }
        return "\(next.name) 着 \(Self.formatGameClock(daySeconds: Double(event.arrivalSeconds)))"
    }

    /// batch108: arms the notification buzzer when a departure
    /// sequence's close lands. No dedicated buzzer recording exists
    /// anywhere in the sound libraries (the Primrose set's
    /// [Buzzer] section is empty and no buzzer-named file is
    /// bundled), so the sequence reuses the app's synthesized
    /// door-warning buzzer via playDoorChime — the closest
    /// existing bundled sound.
    /// batch109 (user correction, 2026-11-16): the buzzer is NOT
    /// a departure condition — traction already unlocks the
    /// moment the doors land closed (see doorInterlockActive).
    /// It exists only for the realism of a conductor being
    /// present, so it sounds once per stop at a random delay of
    /// 0.5–5.0 s after the doors finish closing, drawn once per
    /// close with the standard library randomness (the same
    /// pattern as the point-sound pick, Bool.random() in
    /// RailwayAudioEngine). The schedule runs on simulationTime,
    /// and firing depends on the time alone: departing before
    /// the buzzer sounds does not cancel it.
    private func scheduleDepartureBuzzerIfArmed() {
        guard departureBuzzerArmed else { return }
        departureBuzzerArmed = false
        departureBuzzerAt = simulationTime + Double.random(in: 0.5...5.0)
    }

    private func applyPendingDepartureBuzzerIfDue() {
        guard let buzzerAt = departureBuzzerAt, simulationTime >= buzzerAt else { return }
        departureBuzzerAt = nil
        audio.playDoorChime()
    }

    private func updateAutomaticDoorCycle() {
        guard !demoDriveEnabled, gameModeSession == nil else { return }
        guard runPhase == .running || runPhase == .arrived else { return }
        let speedKmh = engine.speedMps * 3.6
        if gameModeDoorState.isOpen {
            // batch108: the bell has played; issue the close
            // once it has finished.
            if let closeAt = departureSequenceCloseAt {
                if simulationTime >= closeAt {
                    departureSequenceCloseAt = nil
                    handleGameModeHostEffects([.setGameDoorState(.closed)])
                    gameModeHostNotice = nil
                }
                return
            }
            // batch108: sequence trigger — play the departure
            // bell first, then close when the bell ends and let
            // the buzzer sound on the close landing.
            let triggerReached = autoDoorCloseAt.map { simulationTime >= $0 } ?? false
            if triggerReached {
                autoDoorCloseAt = nil
                let bellSeconds = playDepartureBellIfAtStation()
                departureBuzzerArmed = true
                departureSequenceCloseAt = simulationTime + bellSeconds
            }
            return
        }
        guard speedKmh <= 0.5,
              let stop = activeStops.first(where: { abs($0.positionM - engine.positionM) <= Self.arrivalToleranceM }),
              stop.stationID != autoDoorServedStationID else { return }
        autoDoorServedStationID = stop.stationID
        if stop.stationID == activeStops.first?.stationID, scheduledOriginDepartureDaySeconds != nil {
            // batch108: at the origin the sequence is anchored
            // to the timetable: bell at departure − 12 s (the
            // doors opened at departure − 30 s, session start).
            autoDoorCloseAt = Self.originDepartureSessionSeconds - 12
        } else {
            autoDoorCloseAt = simulationTime + 12
        }
        handleGameModeHostEffects([.setGameDoorState(travelDirection == .up ? .openRight : .openLeft)])
        gameModeHostNotice = nil
    }

    func handleGameModeHostEffects(_ effects: [GameModeHostEffect]) {
        for effect in effects {
            switch effect {
            case .setGameDoorState(let state):
                let wasOpen = gameModeDoorState.isOpen
                // batch79: 閉扉音の左右選択用に、開いていた側を
                // 状態の上書き前に控える。
                let closingSide = gameModeDoorState
                if state.isOpen {
                    // Opening cancels any chime-timed closure in progress.
                    pendingDoorClose = nil
                    // batch108: 開扉は発車シーケンスの残りも取り消す
                    // （閉扉待ち・武装が開いたドアで発火しない）。
                    // batch109: 予約済みのブザーは取り消さない —
                    // 発車済みでも鳴るのが仕様（車掌の存在感）。
                    departureSequenceCloseAt = nil
                    departureBuzzerArmed = false
                    gameModeDoorState = state
                    if !wasOpen {
                        departureBellPlayedForCurrentStop = false
                        playDoorSound(open: true, side: state)
                    }
                    gameModeHostNotice = "架空ゲームのドア状態を「\(state.rawValue)」に更新しました。物理モデルのドアではありません。"
                } else if wasOpen, pendingDoorClose == nil,
                          selectedVehicleProfile.soundProfile == .rheostaticDC,
                          let chimeSeconds = audio.playBundledSample(named: "door_chime_resistance") {
                    // Resistance-control stock: the recorded door chime
                    // plays first and the doors close only after it ends
                    // (applied by applyPendingDoorCloseIfDue).
                    pendingDoorClose = PendingDoorClose(state: state, applyAt: simulationTime + chimeSeconds)
                    gameModeHostNotice = "ドアチャイム再生中です。鳴り終わってから扉が閉まります。"
                } else if pendingDoorClose == nil {
                    gameModeDoorState = state
                    if wasOpen {
                        playDoorSound(open: false, side: closingSide)
                        playDepartureBellIfAtStation()
                        scheduleDepartureBuzzerIfArmed()
                    }
                    gameModeHostNotice = "架空ゲームのドア状態を「\(state.rawValue)」に更新しました。物理モデルのドアではありません。"
                }
            case .playGameAnnouncement(let announcementID):
                if announcementID.localizedCaseInsensitiveContains("arrival") {
                    announceStop()
                } else {
                    announceNextStation()
                }
                gameModeHostNotice = "架空ゲーム案内を再生しました: \(announcementID)"
            case .presentGameHint(let text):
                gameModeHostNotice = "架空ゲームヒント: \(text)"
            case .requestPassengerLoad(let factor):
                setPassengerLoadFactor(factor)
                gameModeHostNotice = "架空ゲームの乗車率要求を \(Int((factor * 100).rounded()))% として適用しました。"
            case .requestWeather(let identifier):
                let rawValue = identifier.replacingOccurrences(of: "PLACEHOLDER-weather-", with: "")
                let requestedWeather: WeatherCondition?
                switch rawValue {
                case "dry": requestedWeather = .dry
                case "rain": requestedWeather = .rain
                case "snow": requestedWeather = .snow
                default: requestedWeather = nil
                }
                if let requestedWeather {
                    setWeather(requestedWeather)
                    gameModeHostNotice = "架空ゲームの天候要求を「\(requestedWeather.rawValue)」として適用しました。"
                } else {
                    gameModeHostNotice = "未対応の架空天候要求のため適用しませんでした: \(identifier)"
                }
            case .requestTimeOfDay(let identifier):
                let rawValue = identifier.replacingOccurrences(of: "PLACEHOLDER-time-", with: "")
                let dayPeriod: DayPeriod?
                switch rawValue {
                case "dawn", "morningRush": dayPeriod = .dawn
                case "day", "daytime": dayPeriod = .day
                case "dusk", "evening": dayPeriod = .dusk
                case "night": dayPeriod = .night
                default: dayPeriod = nil
                }
                if let dayPeriod {
                    applyGameModeEnvironment(dayPeriod: dayPeriod)
                    gameModeHostNotice = "架空ゲームの時刻帯要求を「\(dayPeriod.rawValue)」として適用しました。"
                } else {
                    gameModeHostNotice = "未対応の架空時刻帯要求のため適用しませんでした: \(identifier)"
                }
            case .requestSeason(let identifier):
                let rawValue = identifier.replacingOccurrences(of: "PLACEHOLDER-season-", with: "")
                if let season = Season(rawValue: rawValue) {
                    applyGameModeEnvironment(season: season)
                    gameModeHostNotice = "架空ゲームの季節要求を「\(season.rawValue)」として適用しました。"
                } else {
                    gameModeHostNotice = "未対応の架空季節要求のため適用しませんでした: \(identifier)"
                }
            case .requestVehicle(let identifier):
                let rawValue = identifier.replacingOccurrences(of: "PLACEHOLDER-vehicle-", with: "")
                if rawValue == selectedVehicleProfile.rawValue || rawValue == selectedVehicleProfile.physicsProfileIdentifier {
                    gameModeHostNotice = "要求された車両プロフィールはすでに選択されています。"
                } else {
                    gameModeHostNotice = "編成変更は走行をリセットするため、このセッション中は適用しません。次の運転前に車両プロファイルを選んでください。"
                }
            case .requestRoute(let identifier):
                if identifier == routeID {
                    gameModeHostNotice = "要求された架空路線はすでに選択されています。"
                } else {
                    gameModeHostNotice = "路線変更は走行をリセットするため、このセッション中は適用しません。次の運転前に路線を選んでください。"
                }
            }
        }
    }

    private func applyGameModeEnvironment(dayPeriod: DayPeriod? = nil, season: Season? = nil) {
        let current = environmentSelection
        let environment = current.environment
        let period = dayPeriod ?? environment.dayPeriod
        let timeHours: Double
        switch period {
        case .dawn: timeHours = 6.5
        case .day: timeHours = 13
        case .dusk: timeHours = 18.5
        case .night: timeHours = 22
        }
        let updated = EnvironmentConditions(
            precipitation: environment.precipitation,
            fogDensity: environment.fogDensity,
            windSpeedMps: environment.windSpeedMps,
            windDirectionDegrees: environment.windDirectionDegrees,
            visibilityM: environment.visibilityM,
            adhesionCoefficient: environment.adhesionCoefficient,
            ambientIlluminanceLux: environment.ambientIlluminanceLux,
            headlightIntensity: environment.headlightIntensity,
            wiperState: environment.wiperState,
            season: season ?? environment.season,
            dayPeriod: period
        )
        environmentSelection = EnvironmentQualitySelection(
            environment: updated,
            cameraPreset: current.cameraPreset,
            renderQuality: current.renderQuality,
            timeOfDayHours: dayPeriod == nil ? current.timeOfDayHours : timeHours
        )
        updateAudio()
    }

    private func rebuildProtectionSession() {
        protectionSession = try? FictionalLiveProtectionSession(routeLengthM: max(route.distanceM, 100))
        protectionTick = 0
        protectionActivityPulse = false
        protectionAcknowledge = false
        protectionReset = false
        protectionActingSystems = []
        protectionNeedsAcknowledgement = false
        appliedDrivingControls = controls
    }

    private func noteProtectionDriverActivity() {
        protectionActivityPulse = true
    }

    /// Applies fictional ATS-S / ATS-P / ATS-Ps / ATC / EB brake flags to the controls
    /// that the fixed physics tick will consume. ATO traction and deadman release are not driven.
    private func protectionAdjustedControls(_ driver: TrainControls) -> TrainControls {
        // batch71 (user directive, 2026-11-15): the fictional
        // PLACEHOLDER protection session (ProtectionSystems) is
        // DISCONNECTED from the player train. Its supervision
        // devices — the 12 s driver-inactivity EB latch above
        // all — emergency-braked the train in normal play (about
        // 12 s after the last handle operation, roughly 25 km/h
        // into a terminal departure, and likewise on the theme
        // park line), and its status surfaced in the driving UI
        // as the red 「架空保安 eb が制動 (PLACEHOLDER)」 warning.
        // The session is therefore never stepped here: the
        // driver's controls pass through unchanged, no acting
        // systems are ever reported (so the warning text and the
        // cab's fictional-system indicators stay dark, the
        // snapshot's automaticBrakeActive reflects only the real
        // systems, and the demo log's prot= field reads "-"), and
        // the ATS bell demand comes only from the educational ATS
        // and the safety-pattern warning. The ProtectionSystems
        // package itself is untouched (its tests keep passing);
        // the disconnect is at this app-side connection point
        // only. The real supervision — the block-signal safety
        // pattern and the educational ATS — is unaffected.
        if !protectionActingSystems.isEmpty { protectionActingSystems = [] }
        if protectionNeedsAcknowledgement { protectionNeedsAcknowledgement = false }
        appliedDrivingControls = driver
        return driver
    }

    private func cueProtectionSounds(previous: Set<String>, outcome: FictionalProtectionTickOutcome) {
        let acting = Set(outcome.command.actingSystems)
        let appeared = acting.subtracting(previous)
        let awaiting = outcome.states.contains {
            $0.trainID == FictionalLiveProtectionSession.playerTrainID
                && $0.system == ProtectionSystemKind.atsS.rawValue
                && $0.stateDescription.contains("awaiting")
        }
        // batch67: ATS-S 確認待ちのベルは updateATSBellLoop が
        // protectionNeedsAcknowledgement を見て回し続けるため、
        // ここでの立ち上がりワンショットは廃止（二重発音防止）。
        lastATSSAwaiting = awaiting
        let emergencyIDs: Set<String> = ["atsS", "eb", "deadman"]
        if !appeared.intersection(emergencyIDs).isEmpty && outcome.command.emergencyBrake {
            audio.playEmergencyBrakeAlert()
        } else if !appeared.isEmpty {
            audio.playATSAlarm()
        }
        lastProtectionActingSystems = acting
    }

    /// Station-stop alarm near 400 m and the chopper start buzzer follow page descriptions of when to sound, not copied tones.
    private func cueOperationalAudio(nextStopDistanceM: Double) {
        let family = FictionalCabAndSoundCatalog.family(forProfileID: selectedSoundProfile.rawValue)
        if !playedChopperStartBuzzer, family == .fieldChopper, simulationTime < 1.5, engine.speedMps < 1 {
            playedChopperStartBuzzer = true
            audio.playATSAlarm()
        }
        guard activeStops.indices.contains(nextStopIndex) else { return }
        let stop = activeStops[nextStopIndex]
        guard nextStopDistanceM >= 0, nextStopDistanceM <= 400, engine.speedMps > 1 else { return }
        if stationPatternAlarmStopID != stop.stationID {
            stationPatternAlarmStopID = stop.stationID
            audio.playATSAlarm()
        }
        if nextStopDistanceM <= 80, !gameModeDoorState.isOpen, doorWarningStopID != stop.stationID {
            doorWarningStopID = stop.stationID
            audio.playDoorChime()
        }
    }

    /// Unraised fictional crossings and bridges, plus chainage turnouts and rail joints.
    private func cueWaysideAudio() {
        let position = engine.positionM
        let window = SceneCorridorLandmarkSchedule.landmarks(from: position - 2, to: position + 2)
        let crossing = window.first { $0.kind == .levelCrossing && $0.contains(position) }
        let bridge = window.first { $0.kind == .riverBridge && $0.contains(position) }
        audioOnBridge = bridge != nil
        if engine.speedMps > 0.4 {
            if let crossing, crossing.id != lastCrossingLandmarkID {
                lastCrossingLandmarkID = crossing.id
                audio.playCrossingBell()
            } else if crossing == nil {
                lastCrossingLandmarkID = nil
            }
            if let bridge, bridge.id != lastBridgeLandmarkID {
                lastBridgeLandmarkID = bridge.id
                audio.playWayside(.bridgeRumble)
            } else if bridge == nil {
                lastBridgeLandmarkID = nil
            }
        }
        let impacts = trackImpactTracker.advance(
            routePositionM: position,
            speedMps: engine.speedMps,
            path: trackImpactPath,
            direction: travelDirection == .up ? .up : .down
        )
        audioOnPoints = impacts.insideTurnout
        // batch78: 走行ベッドの区間判定（Run3 / Run6 切替用）。
        // トラッカーと同じ locate を先頭位置で評価し、
        // FictionalTrackImpactSchedule の継目判定をそのまま使う
        // （audioOnBridge / audioOnPoints と同じ「wayside で
        // 計算して snapshot へ渡す」パターン）。
        if let located = FictionalTrackImpactSchedule.locate(
            path: trackImpactPath,
            direction: travelDirection == .up ? .up : .down,
            routePositionM: position
        ) {
            audioOnJointedRail = FictionalTrackImpactSchedule.isJointedRail(line: located.line, chainageM: located.chainageM)
        }
        for impact in impacts.impacts {
            if impact.kind == .pointClatter {
                audio.playTrackImpact(.pointClatter, intensity: impact.intensity)
            } else {
                // batch79: 継目音は代表イベントのみ発火する。
                // トラッカーは台車ごとに発火するため、全台車分を
                // 鳴らすと継目間隔と無関係な約0.40秒周期の多重
                // 発音になる（ハーネス測定で確認した合成
                // チャタリングと同じ構造）。Primrose [Joint]
                // の録音は列車1本分の通過が入った長さなので、
                // 先頭台車の通過で1回だけ鳴らすのが実物側の
                // 意味論に合う。
                // batch97: 低速域（RailwayAudioEngine
                // .lowSpeedJointClackMaxKmh 未満）だけは代表方式を
                // やめ、全台車イベントを転送する。この速度域では
                // エンジン側が p1 の代わりに台車1台分の打音
                // （joint_clack）を鳴らすため、台車ごとの発火が
                // 実物のカデンス（台車間隔 5.6 m / 13.9 m の
                // 距離真値）になる。分岐器スパン内の継目は全速度で
                // 従来どおり代表イベントのみ — p45 は分岐器通過
                // そのものの録音で多重打撃が物理的に正しく、
                // 台車ごとのカデンスは span 進入時の pointClatter
                // が別途担っている。
                let insideTurnout = isInsideTurnout(impact)
                if impact.bogieIndex != 0 {
                    if insideTurnout { continue }
                    if engine.speedMps * 3.6 >= RailwayAudioEngine.lowSpeedJointClackMaxKmh { continue }
                }
                audio.playTrackImpact(
                    .railJoint,
                    intensity: impact.intensity,
                    insideTurnout: insideTurnout
                )
            }
        }
    }

    /// batch79: 継目インパクトを打った台車が分岐器スパン内に
    /// いるか（Primrose [Joint] の p45 バリアント選択用）。
    /// トラッカー自身の locate / turnouts と同じ判定を、その
    /// 台車の位置で再評価する。
    private func isInsideTurnout(_ impact: FictionalTrackImpact) -> Bool {
        let offsets = FictionalTrackImpactSchedule.bogieOffsets(carCount: selectedVehicleProfile.carCount)
        guard offsets.indices.contains(impact.bogieIndex) else { return false }
        let bogieRoute = impact.routePositionM - offsets[impact.bogieIndex]
        guard let located = FictionalTrackImpactSchedule.locate(
            path: trackImpactPath,
            direction: travelDirection == .up ? .up : .down,
            routePositionM: bogieRoute
        ) else { return false }
        return !FictionalTrackImpactSchedule.turnouts(containing: located.line, chainageM: located.chainageM, path: trackImpactPath).isEmpty
    }

    private var trackImpactPath: FictionalPlayablePath {
        switch routeVariant {
        case .mainline: .mainline
        case .throughBranch: .throughBranch
        case .branchShuttle: .branchShuttle
        case .depotTransfer: .depotTransfer
        case .zooLine: .zooLine
        case .parkLine: .parkLine
        }
    }

    private func clearAudioCueEdges() {
        lastProtectionActingSystems = []
        lastATSSAwaiting = false
        lastExceededPattern = false
        playedChopperStartBuzzer = false
        stationPatternAlarmStopID = nil
        doorWarningStopID = nil
        trackImpactTracker = FictionalTrackImpactTracker(carCount: selectedVehicleProfile.carCount)
        lastCrossingLandmarkID = nil
        lastBridgeLandmarkID = nil
        audioOnBridge = false
        audioOnPoints = false
        audioOnJointedRail = false
    }

    private func protectionBrakeReason(educationalATS: Bool, exceededPattern: Bool) -> String? {
        var reasons: [String] = []
        if educationalATS { reasons.append("確認期限超過による架空教材用自動制動") }
        if exceededPattern { reasons.append("速度パターン超過") }
        if !protectionActingSystems.isEmpty {
            reasons.append("架空保安 \(protectionActingSystems.joined(separator: "・")) が制動（PLACEHOLDER）")
        }
        return reasons.isEmpty ? nil : reasons.joined(separator: " / ")
    }

    @discardableResult
    func acknowledgeATS() -> Bool {
        noteProtectionDriverActivity()
        protectionAcknowledge = true
        if engine.speedMps * 3.6 <= 0.1 { protectionReset = true }
        // batch67: パターン警告への確認も同じボタンで受ける。
        // 確認した瞬間にベル需要が消え（updateATSBellLoop）、
        // なお超過していれば次の tick から常用制動段階へ移る。
        var patternAccepted = false
        if patternWarningStartTime != nil, !patternWarningAcknowledged {
            patternWarningAcknowledged = true
            patternAccepted = true
        }
        guard var system = atsSystem else {
            if patternAccepted { audio.playATSConfirmation() }
            return patternAccepted || protectionAcknowledge
        }
        let accepted = (try? system.acknowledge(at: simulationTime)) ?? false
        if patternAccepted, !accepted { audio.playATSConfirmation() }
        if accepted {
            atsSystem = system
            pendingConfirmations.append(DriveConfirmation(actionID: "ats_ack", label: "架空教材ATS確認", wasPerformed: true))
            audio.playATSConfirmation()
            let current = operationsSnapshot
            if let current {
                let updated = SimulatorOperationsSnapshot(
                    signalReading: current.signalReading,
                    signalDistanceM: current.signalDistanceM,
                    permittedSpeedKmh: current.permittedSpeedKmh,
                    otherTrains: current.otherTrains,
                    atsStatus: system.status(),
                    automaticBrakeActive: current.automaticBrakeActive,
                    automaticBrakeReason: current.automaticBrakeReason,
                    label: current.label
                )
                latestOperationsSnapshot = updated
                operationsSnapshot = updated
            }
        }
        return accepted || patternAccepted
    }

    func playHorn(long: Bool = false) {
        noteProtectionDriverActivity()
        audio.playHorn(long: long)
    }
    func playBrakeAir() { audio.playBrakeAir() }
    func setAudioEnabled(_ enabled: Bool) {
        audioEnabled = enabled
        audio.setEnabled(enabled)
    }
    func setAudioVolume(_ value: Float) {
        guard value.isFinite else { return }
        audioVolume = min(max(Double(value), 0), 1)
        audio.setVolume(Float(audioVolume))
    }
    func setAnnouncementLocale(_ locale: AnnouncementLocale) { announcementLocale = locale }

    private func scheduleAnnouncement(
        _ template: AnnouncementTemplate,
        context: AnnouncementContext,
        deduplicationKey: String?,
        priority: Int
    ) {
        let request = AnnouncementRequest(
            template: template,
            locale: announcementLocale,
            context: context,
            channel: .onboardAutomated
        )
        guard AnnouncementRenderer.render(request) != nil else { return }
        enqueueScheduledAudio(
            bus: .onboardAnnouncement,
            payload: .announcement(request),
            deduplicationKey: deduplicationKey,
            priority: priority
        )
    }

    private func scheduleSpeakerTone(
        _ tone: SpeakerTone,
        bus: AudioBus,
        deduplicationKey: String?,
        priority: Int
    ) {
        enqueueScheduledAudio(
            bus: bus,
            payload: .speakerTone(tone),
            deduplicationKey: deduplicationKey,
            priority: priority
        )
    }

    private func enqueueScheduledAudio(
        bus: AudioBus,
        payload: AudioCuePayload,
        deduplicationKey: String?,
        priority: Int
    ) {
        let event = AudioScheduledEvent(
            id: "sim-audio-\(audioEventSequence)",
            scheduledTime: simulationTime,
            priority: priority,
            deduplicationKey: deduplicationKey,
            bus: bus,
            payload: payload
        )
        audioEventSequence &+= 1
        _ = audioEventScheduler.schedule(event)
        advanceScheduledAudio(to: simulationTime)
    }

    private func advanceScheduledAudio(to time: TimeInterval) {
        guard let dueEvents = try? audioEventScheduler.advance(to: time) else { return }
        for event in dueEvents { audio.playScheduledAudioEvent(event) }
    }

    private func scheduleAutomaticApproachAnnouncement() {
        guard activeStops.indices.contains(nextStopIndex) else { return }
        let stop = activeStops[nextStopIndex]
        let distance = stop.positionM - engine.positionM
        guard distance >= 0, distance <= 800,
              !automaticAnnouncedStopIDs.contains(stop.stationID) else { return }
        let key = "auto-approach:\(routeID):\(stop.stationID)"
        scheduleAnnouncement(
            .approachingStation,
            context: AnnouncementContext(stationName: stop.name),
            deduplicationKey: key,
            priority: 5
        )
        automaticAnnouncedStopIDs.insert(stop.stationID)
    }

    func announceNextStation() {
        let station = activeStops.indices.contains(nextStopIndex) ? activeStops[nextStopIndex].name : route.arrivalStation
        scheduleAnnouncement(.approachingStation, context: AnnouncementContext(stationName: station), deduplicationKey: nil, priority: 4)
    }
    func announceStop() {
        let station = activeStops.indices.contains(nextStopIndex) ? activeStops[nextStopIndex].name : route.arrivalStation
        scheduleAnnouncement(.nextStation, context: AnnouncementContext(stationName: station), deduplicationKey: nil, priority: 4)
    }
    func playDepartureChime() { audio.playDepartureChime() }
    func playDoorChime() { scheduleSpeakerTone(.doorWarning, bus: .onboardAnnouncement, deduplicationKey: nil, priority: 5) }
    func setTractionSoundProfile(_ profile: RailwayTractionSoundProfile) {
        selectedSoundProfile = profile
        audio.setTractionSoundProfile(profile)
    }

    private func advanceIncidentMaintenanceForCurrentTick() {
        guard var candidate = incidentMaintenanceEngine else { return }
        let input = TickInput(
            manualSignals: pendingIncidentManualSignals,
            metrics: [
                "speed_kmh": Int(max(0, engine.speedMps * 3.6).rounded()),
                "position_m": Int(max(0, engine.positionM).rounded())
            ],
            recoveryActionIDs: pendingIncidentRecoveryActionIDs
        )
        do {
            let result = try candidate.advanceOneTick(input: input)
            incidentMaintenanceEngine = candidate
            incidentTickResult = result
            pendingIncidentManualSignals.removeAll(keepingCapacity: true)
            pendingIncidentRecoveryActionIDs.removeAll(keepingCapacity: true)
            if !result.startedEvents.isEmpty {
                incidentNotice = "架空ゲームイベントを固定tickで記録しました。実際の故障・安全判断ではありません。"
            } else if !result.recoveredEvents.isEmpty {
                incidentNotice = "架空ゲームイベントを復旧状態へ進めました。"
            }
        } catch {
            incidentNotice = "架空ゲームイベントを更新できませんでした: \(error)"
        }
    }

    func completeCrewWorkflowPhase() {
        guard let phase = crewWorkflow.currentPhase else {
            incidentNotice = "20段階の架空ゲーム進行は完了しています。"
            return
        }
        var candidate = crewWorkflow
        do {
            try candidate.complete(
                phase: phase,
                at: Date(timeIntervalSinceReferenceDate: simulationTime),
                satisfiedRequirementIDs: phase.requiredRequirementIDs
            )
            crewWorkflow = candidate
            incidentNotice = "架空ゲーム段階「\(phase.displayName)」を記録しました。現実の業務・安全判断とは無関係です。"
        } catch {
            incidentNotice = "架空ゲーム進行を記録できませんでした: \(error.localizedDescription)"
        }
    }

    func queueFictionalIncident() {
        guard incidentMaintenanceEngine != nil else { incidentNotice = "架空ゲーム状態を準備できません。"; return }
        pendingIncidentManualSignals.insert(Self.manualIncidentTriggerID)
        incidentNotice = isPaused
            ? "架空ゲームイベントを予約しました。運転再開後の固定tickで判定します。"
            : "架空ゲームイベントを次の固定tickで判定します。"
    }

    func incidentMinimumTicks(for event: IncidentEventRecord) -> Int {
        incidentMaintenanceEngine?.state.eventDefinitions.first(where: { $0.id == event.definitionID })?.duration.minimumTicks ?? Int.max
    }

    func incidentRecoveryActionID(for event: IncidentEventRecord) -> String? {
        guard let definition = incidentMaintenanceEngine?.state.eventDefinitions.first(where: { $0.id == event.definitionID }) else { return nil }
        if case .actionRequired(let actionID) = definition.recoveryRule { return actionID }
        return nil
    }

    func queueFictionalIncidentRecovery(for event: IncidentEventRecord) {
        guard activeIncidentEvents.contains(where: { $0.id == event.id }),
              let actionID = incidentRecoveryActionID(for: event) else { return }
        pendingIncidentRecoveryActionIDs.insert(actionID)
        incidentNotice = "架空イベントの復旧選択を次の固定tickに予約しました。"
    }

    func applyFictionalDepotAction(_ action: DepotAction) {
        guard var candidate = incidentMaintenanceEngine else {
            incidentNotice = "架空基地ゲームを準備できません。"
            return
        }
        do {
            try candidate.applyDepotAction(action, at: candidate.state.simulationTick)
            incidentMaintenanceEngine = candidate
            incidentNotice = "架空基地のゲーム状態を更新しました。実車の点検・整備・出庫判断ではありません。"
        } catch {
            incidentNotice = "架空基地ゲームの状態遷移を適用できませんでした: \(error)"
        }
    }

    func selectVehicleProfile(_ profile: FictionalVehicleProfile) {
        guard selectedVehicleProfile != profile else { return }
        selectedVehicleProfile = profile
        selectedSoundProfile = profile.soundProfile
        train = profile.makeParameters()
        engine = TrainPhysicsProfileAdapter.makeEngine(for: profile, passengerLoadFactor: 0.7)
        audio.setTractionSoundProfile(profile.soundProfile)
        blockSystem = Self.makeBlocks(route: route)
        reset()
    }

    func selectTrainingMode(_ mode: TrainingMode) {
        guard trainingMode != mode else { return }
        trainingMode = mode
        reset()
    }

    func setEnvironmentSelection(_ selection: EnvironmentQualitySelection) {
        let driving = inferredDrivingWeather(selection.environment)
        weather = weatherCondition(for: driving)
        let effect = FictionalWeatherDrivingCoupling.resolve(
            weather: driving,
            windSpeedMps: selection.environment.windSpeedMps
        )
        let updated = EnvironmentConditions(
            precipitation: effect.precipitation,
            fogDensity: effect.fogDensity,
            windSpeedMps: selection.environment.windSpeedMps,
            windDirectionDegrees: selection.environment.windDirectionDegrees,
            visibilityM: effect.visibilityM,
            adhesionCoefficient: effect.adhesionCoefficient,
            ambientIlluminanceLux: selection.environment.ambientIlluminanceLux,
            headlightIntensity: selection.environment.headlightIntensity,
            wiperState: wiperState(for: weather),
            season: selection.environment.season,
            dayPeriod: selection.environment.dayPeriod
        )
        environmentSelection = EnvironmentQualitySelection(
            environment: updated,
            cameraPreset: selection.cameraPreset,
            renderQuality: selection.renderQuality,
            timeOfDayHours: selection.timeOfDayHours
        )
        refreshPublishedTelemetry()
        updateAudio()
    }

    private func inferredDrivingWeather(_ environment: EnvironmentConditions) -> FictionalDrivingWeather {
        switch environment.precipitation {
        case .snow: return .snow
        case .rain:
            return abs(environment.adhesionCoefficient - FictionalWeatherDrivingCoupling.heavyRainAdhesion) < 0.015
                ? .heavyRain : .rain
        case .none: return environment.fogDensity >= 0.5 ? .fog : .dry
        }
    }

    private func weatherCondition(for driving: FictionalDrivingWeather) -> WeatherCondition {
        switch driving {
        case .dry: return .dry
        case .rain: return .rain
        case .heavyRain: return .heavyRain
        case .snow: return .snow
        case .fog: return .fog
        }
    }

    func setWeather(_ value: WeatherCondition, updateEnvironment: Bool = true) {
        weather = value
        if updateEnvironment {
            let current = environmentSelection
            let effect = FictionalWeatherDrivingCoupling.resolve(
                weather: value.fictionalDrivingWeather,
                windSpeedMps: FictionalWeatherDrivingCoupling.presetWindSpeedMps(for: value.fictionalDrivingWeather)
            )
            let updatedEnvironment = EnvironmentConditions(
                precipitation: effect.precipitation,
                fogDensity: effect.fogDensity,
                windSpeedMps: FictionalWeatherDrivingCoupling.presetWindSpeedMps(for: value.fictionalDrivingWeather),
                windDirectionDegrees: current.environment.windDirectionDegrees,
                visibilityM: effect.visibilityM,
                adhesionCoefficient: effect.adhesionCoefficient,
                ambientIlluminanceLux: current.environment.ambientIlluminanceLux,
                headlightIntensity: value == .fog || value == .heavyRain ? max(current.environment.headlightIntensity, 0.8) : current.environment.headlightIntensity,
                wiperState: wiperState(for: value),
                season: current.environment.season,
                dayPeriod: current.environment.dayPeriod
            )
            environmentSelection = EnvironmentQualitySelection(
                environment: updatedEnvironment,
                cameraPreset: current.cameraPreset,
                renderQuality: current.renderQuality,
                timeOfDayHours: current.timeOfDayHours
            )
        }
        refreshPublishedTelemetry()
        updateAudio()
    }

    private var weatherDrivingEffect: FictionalWeatherDrivingEffect {
        FictionalWeatherDrivingCoupling.resolve(
            weather: weather.fictionalDrivingWeather,
            windSpeedMps: environmentSelection.environment.windSpeedMps
        )
    }

    private func wiperState(for value: WeatherCondition) -> WiperState {
        switch value {
        case .dry, .fog: return .off
        case .rain: return .low
        case .heavyRain: return .high
        case .snow: return .intermittent
        }
    }

    func cycleWeather() {
        let cases = WeatherCondition.allCases
        guard let index = cases.firstIndex(of: weather) else { return }
        setWeather(cases[(index + 1) % cases.count])
    }

    func setPassengerLoadFactor(_ value: Double) {
        engine.setPassengerLoadFactor(value)
        refreshPublishedTelemetry()
    }

    func togglePause() {
        guard runPhase == .running else { return }
        isPaused.toggle()
        lastFrameTime = nil
    }

    func saveCurrentSession() {
        persistCurrentSession()
        captureCompletedRun()
    }

    private func captureCompletedRun() {
        completedSummary = recorder.summary()
        let facts = (stopScoringEvaluation?.stationEvaluations ?? []).map { station in
            StationRunFact(
                stationID: station.stationID,
                displayName: station.displayName ?? station.stationID,
                arrivalDeviationSeconds: station.arrivalDeviationSeconds,
                stopErrorMeters: station.stopMeasurement?.signedErrorMeters
            )
        }
        completedReview = PostRunReviewBuilder.make(
            samples: recorder.samples.map { sample in
                RunTraceSample(
                    timeSeconds: sample.simulationTimeSeconds,
                    distanceM: sample.positionM,
                    speedKmh: sample.speedKmh,
                    brakeNotch: sample.brakeNotch,
                    emergencyBrake: sample.emergencyBrakeOn,
                    speedLimitKmh: sample.speedLimitKmh,
                    signalAspect: sample.signalAspect
                )
            },
            scheduledDurationSeconds: recorder.metadata.criteria.scheduledDurationSeconds,
            stopMarkerM: recorder.metadata.criteria.stopMarkerM,
            stopToleranceM: recorder.metadata.criteria.stopPositionToleranceM,
            stationFacts: facts
        )
    }

    @discardableResult
    func saveGame(saveName: String = "手動保存") -> Bool {
        guard let saveStore, runPhase == .running else {
            storageNotice = "走行中の運転状態だけをセーブできます。"
            return false
        }
        isPaused = true
        lastFrameTime = nil
        if !pendingStopScoringEvents.isEmpty {
            let pending = pendingStopScoringEvents
            pendingStopScoringEvents.removeAll(keepingCapacity: true)
            updateStopScoring(events: pending)
        }
        do {
            let state = try makeSimulationSaveState(saveName: saveName)
            let slotID = "save-\(UUID().uuidString.lowercased())"
            try saveStore.save(state, toSlot: slotID)
            refreshSaveSlots()
            storageNotice = "セーブを保存しました。再開時は一覧から選べます。"
            return true
        } catch {
            storageNotice = "セーブを作成できませんでした。走行状態と保存データを確認してください。"
            return false
        }
    }

    func refreshSaveSlots() {
        saveSlots = (try? saveStore?.listSlots()) ?? []
    }

    func prepareForSaveSheet() {
        isPaused = true
        lastFrameTime = nil
    }

    @discardableResult
    func loadGame(slotID: String) -> Bool {
        guard let saveStore else {
            storageNotice = "この端末でセーブ領域を準備できませんでした。"
            return false
        }
        do {
            let decoded = try saveStore.load(slot: slotID)
            try restoreSimulationSaveState(decoded.state)
            refreshSaveSlots()
            storageNotice = "セーブを再開しました。乗務ワークフロー・故障/基地ゲームは復元済み。別系統の運行/保守ミニゲーム進行は別保存です。"
            return true
        } catch {
            storageNotice = "セーブを再開できませんでした。版の互換性またはデータ整合性を確認してください。"
            return false
        }
    }

    private func makeSimulationSaveState(saveName: String) throws -> SimulationSaveState {
        let name = saveName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name.count <= 120,
              runPhase == .running,
              !timetableSettingsPendingRestart,
              let plan = regionalPlan,
              let routePackage = canonicalRoutePackage,
              let incidentRuntimeEngine = incidentMaintenanceEngine else {
            throw SimulationSaveStateError.invalidHostState
        }
        let physicsState = engine.stateSnapshot()
        let fixedStep = TrainPhysics.PhysicsConstants.fixedTimeStepSeconds
        guard fixedStepAccumulator.isFinite, fixedStepAccumulator >= -1e-9,
              fixedStepAccumulator < fixedStep + 1e-9 else {
            throw SimulationSaveStateError.invalidHostState
        }
        let savedRemainder = min(max(fixedStepAccumulator, 0), fixedStep.nextDown)
        let fixedTick = UInt64(max(0, (simulationTime / fixedStep).rounded()))
        let scheduleByStationID = timetableSelection.map {
            RegionalTimetableAdapter.stopSchedules(from: $0, activeStops: activeStops)
        } ?? [:]
        let timetableStops = activeStops.dropFirst().map { stop in
            let schedule = scheduleByStationID[stop.stationID]
            return TimetableStopSnapshot(
                id: "\(stop.stationID)-stop",
                stationID: stop.stationID,
                eventKindID: "stop",
                positionM: stop.positionM,
                scheduledArrivalSeconds: schedule?.scheduledArrivalSeconds,
                scheduledDepartureSeconds: schedule?.scheduledDepartureSeconds
            )
        }
        let modeState = gameModeSession?.stateSnapshot()
        let modeSnapshot: ModeSessionSnapshot?
        if let modeState {
            modeSnapshot = ModeSessionSnapshot(
                modeID: modeState.mode.rawValue,
                playStyleID: modeState.playStyle.rawValue,
                statusID: modeState.status.rawValue,
                startedAtSimulationSeconds: modeState.sessionStartTimeSeconds,
                hintCount: modeState.hintCount,
                failureReasonID: modeState.failureReason?.rawValue,
                progress: try SimulatorRuntimeSnapshot.encodeJSONValue(modeState.progress),
                evaluation: try modeState.evaluation.map { try SimulatorRuntimeSnapshot.encodeJSONValue($0) }
            )
        } else {
            modeSnapshot = nil
        }
        let runtime = SimulatorRuntimeSnapshot(
            revision: SimulatorRuntimeSnapshot.currentRevision,
            physics: physicsState,
            traffic: trafficEngine?.stateSnapshot(),
            scheduleEngine: scheduleEngine,
            ats: atsSystem,
            stopScoring: stopScoringEngine?.makeSnapshot(),
            doorScoring: doorProcedureScoringEngine?.snapshot(),
            gameMode: modeState,
            gameModeScenario: gameModeSession?.scenario,
            environmentSelection: environmentSelection,
            trainingMode: trainingMode,
            fixedStepAccumulator: savedRemainder,
            arrivalDwellSeconds: arrivalDwellSeconds,
            stopScoringTickSequence: stopScoringTickSequence,
            stopScoringEventSequence: stopScoringEventSequence,
            scoringStationID: scoringStationID,
            pendingScoringDepartureStationID: pendingScoringDepartureStationID,
            doorProcedureEventSequence: doorProcedureEventSequence,
            gameModeCurrentStationID: gameModeCurrentStationID,
            pendingGameModeStationEvent: pendingGameModeStationEvent.map {
                PendingGameModeStationSnapshot(stationID: $0.stationID, event: $0.event)
            },
            gameModeDoorState: gameModeDoorState,
            lastATSProtectedBlockID: lastATSProtectedBlockID,
            pendingConfirmations: pendingConfirmations,
            appliedTimetableDepartureDelaySeconds: appliedTimetableDepartureDelaySeconds,
            audioEnabled: audioEnabled,
            audioVolume: audioVolume,
            announcementLocale: announcementLocale,
            crewWorkflow: crewWorkflow.exportSave(),
            incidentMaintenance: incidentRuntimeEngine.exportSave(),
            pendingIncidentManualSignals: pendingIncidentManualSignals,
            pendingIncidentRecoveryActionIDs: pendingIncidentRecoveryActionIDs,
            automaticAnnouncedStopIDs: automaticAnnouncedStopIDs
        )
        let engineTelemetry = engine.telemetry
        let maximumCylinder = max(engine.profile.brakeSystem.maximumCylinderPressureKPa, 1)
        let state = SimulationSaveState(
            saveName: name,
            sessionID: recorder.metadata.sessionID,
            simulation: SimulationClockSnapshot(
                simulationTimeSeconds: simulationTime,
                fixedTick: fixedTick,
                fixedStepRemainderSeconds: savedRemainder,
                isPaused: true,
                runPhaseID: runPhase.rawValue,
                arrivalDwellSeconds: arrivalDwellSeconds
            ),
            route: RouteProgressSnapshot(
                routeID: routeID,
                routeRevision: "fictional-70km-network-v1",
                variantID: routeVariant.rawValue,
                directionID: travelDirection.rawValue,
                distanceM: route.distanceM,
                stopMarkerM: route.stopMarkerM,
                nextStopIndex: nextStopIndex,
                completedStopIDs: Array(activeStops.prefix(nextStopIndex).map(\.stationID))
            ),
            vehicle: PlayerVehicleSnapshot(
                profileID: selectedVehicleProfile.physicsProfileIdentifier,
                soundProfileID: selectedSoundProfile.rawValue,
                carCount: selectedVehicleProfile.carCount,
                directionID: travelDirection.rawValue
            ),
            controls: ControlStateSnapshot(
                throttleNotch: controls.throttleNotch,
                brakeNotch: controls.brakeNotch,
                emergencyBrake: controls.emergencyBrake
            ),
            physics: PhysicsStateSnapshot(
                modelID: physicsState.profileID,
                modelVersion: physicsState.modelVersion,
                physicsAccumulatorSeconds: physicsState.accumulatorSeconds,
                positionM: physicsState.positionM,
                speedMps: physicsState.speedMps,
                accelerationMps2: physicsState.accelerationMps2,
                passengerLoadFactor: physicsState.passengerLoadFactor,
                appliedBrakeFraction: min(max(Double(controls.brakeNotch) / 7, 0), 1),
                commandedTractionForceN: physicsState.commandedTractionForceN,
                antiSlipScale: physicsState.tractionAdhesionScale,
                brakePipePressureKPa: engineTelemetry.brakePipePressureKPa,
                brakeCylinderPressureKPa: engineTelemetry.brakeCylinderPressureKPa,
                mainReservoirPressureKPa: physicsState.mainReservoirPressureKPa,
                lastTractionForceN: physicsState.lastTractionForceN,
                lastBrakingForceN: physicsState.lastTotalBrakeForceN,
                lastRegenerativeBrakeForceN: physicsState.lastRegenerativeBrakeForceN,
                lastAirBrakeForceN: physicsState.lastFrictionBrakeForceN,
                lastRollingResistanceN: physicsState.lastRollingResistanceN,
                lastGradientForceN: physicsState.lastGradientForceN,
                lastCurveResistanceN: physicsState.lastCurveResistanceN,
                wheelSlipActive: physicsState.wheelSlipActive,
                brakeSlipActive: physicsState.brakeSlipActive
            ),
            mode: modeSnapshot,
            timetable: TimetableStateSnapshot(
                calendarID: timetableCalendar.rawValue,
                daypartID: timetableDaypart.rawValue,
                serviceCategoryID: serviceCategory.rawValue,
                directionID: travelDirection.rawValue,
                serviceID: timetableSelection?.plannedTrip.tripID,
                initialDelayMinutes: timetableInitialDelayMinutes,
                departureDelaySeconds: Double(appliedTimetableDepartureDelaySeconds),
                settingsPendingRestart: timetableSettingsPendingRestart,
                stops: timetableStops
            ),
            environment: EnvironmentStateSnapshot(
                weatherID: environmentSelection.environment.legacyWeatherCaseName,
                precipitationID: environmentSelection.environment.precipitation.rawValue,
                fogDensity: environmentSelection.environment.fogDensity,
                windSpeedMps: environmentSelection.environment.windSpeedMps,
                windDirectionDegrees: environmentSelection.environment.windDirectionDegrees,
                visibilityM: environmentSelection.environment.visibilityM,
                adhesionCoefficient: environmentSelection.environment.adhesionCoefficient,
                ambientIlluminanceLux: environmentSelection.environment.ambientIlluminanceLux,
                headlightIntensity: environmentSelection.environment.headlightIntensity,
                wiperStateID: environmentSelection.environment.wiperState.rawValue,
                seasonID: environmentSelection.environment.season.rawValue,
                dayPeriodID: environmentSelection.environment.dayPeriod.rawValue,
                timeOfDayHours: environmentSelection.timeOfDayHours
            ),
            preferences: UserPreferencesSnapshot(
                cameraPresetID: environmentSelection.cameraPreset.rawValue,
                renderQualityID: environmentSelection.renderQuality.rawValue,
                masterVolume: audioVolume,
                musicVolume: audioVolume,
                effectsVolume: audioVolume,
                voiceVolume: audioVolume,
                controlLayoutID: "default",
                hapticsEnabled: true
            ),
            drivingLog: try SimulatorRuntimeSnapshot.encodeJSONValue(recorder.stateSnapshot()),
            subsystemStates: ["railwayMaster": try SimulatorRuntimeSnapshot.encodeJSONValue(runtime)],
            compatibility: SaveCompatibilitySnapshot(
                appBuildID: "0.2.0",
                routeCatalogRevision: "fictional-70km-network-v1",
                vehicleCatalogRevision: "fictional-vehicle-catalog-v1",
                subsystemStateRevision: SimulatorRuntimeSnapshot.currentRevision
            )
        )
        try state.validate()
        _ = plan
        _ = routePackage
        return state
    }

    private func restoreSimulationSaveState(_ saved: SimulationSaveState) throws {
        try saved.validate()
        guard saved.compatibility.appBuildID == "0.2.0",
              saved.compatibility.routeCatalogRevision == "fictional-70km-network-v1",
              saved.compatibility.vehicleCatalogRevision == "fictional-vehicle-catalog-v1",
              saved.compatibility.subsystemStateRevision == SimulatorRuntimeSnapshot.currentRevision,
              saved.simulation.runPhaseID == SimulationRunPhase.running.rawValue,
              let runtimeValue = saved.subsystemStates["railwayMaster"],
              let variant = RegionalRouteVariant(rawValue: saved.route.variantID),
              let category = ServiceCategory(rawValue: saved.timetable.serviceCategoryID),
              let direction = RegionalTravelDirection(rawValue: saved.route.directionID),
              let profile = FictionalVehicleProfile.allCases.first(where: { $0.physicsProfileIdentifier == saved.vehicle.profileID }),
              saved.vehicle.carCount == profile.carCount,
              let soundProfile = RailwayTractionSoundProfile(rawValue: saved.vehicle.soundProfileID),
              let calendar = RailwayTimetable.ServiceCalendar(rawValue: saved.timetable.calendarID),
              let daypart = RailwayTimetable.Daypart(rawValue: saved.timetable.daypartID),
              let plan = regionalPlan,
              let routePackage = canonicalRoutePackage else {
            throw SimulationSaveStateError.incompatibleSave
        }
        let runtime = try SimulatorRuntimeSnapshot.decodeJSONValue(SimulatorRuntimeSnapshot.self, from: runtimeValue)
        let candidateCrewWorkflow = try CrewWorkflow.restore(from: runtime.crewWorkflow)
        let candidateIncidentMaintenance = try IncidentMaintenanceEngine.restore(from: runtime.incidentMaintenance)
        let savedFixedTick = saved.simulation.fixedTick
        let savedEnvironment = runtime.environmentSelection.environment
        let environmentMatchesDTO =
            saved.environment.precipitationID == savedEnvironment.precipitation.rawValue &&
            saved.environment.weatherID == savedEnvironment.legacyWeatherCaseName &&
            saved.environment.fogDensity == savedEnvironment.fogDensity &&
            saved.environment.windSpeedMps == savedEnvironment.windSpeedMps &&
            saved.environment.windDirectionDegrees == savedEnvironment.windDirectionDegrees &&
            saved.environment.visibilityM == savedEnvironment.visibilityM &&
            saved.environment.adhesionCoefficient == savedEnvironment.adhesionCoefficient &&
            saved.environment.ambientIlluminanceLux == savedEnvironment.ambientIlluminanceLux &&
            saved.environment.headlightIntensity == savedEnvironment.headlightIntensity &&
            saved.environment.wiperStateID == savedEnvironment.wiperState.rawValue &&
            saved.environment.seasonID == savedEnvironment.season.rawValue &&
            saved.environment.dayPeriodID == savedEnvironment.dayPeriod.rawValue
        guard runtime.revision == SimulatorRuntimeSnapshot.currentRevision,
              let camera = RailwayCameraPreset(rawValue: saved.preferences.cameraPresetID),
              let quality = EnvironmentRenderQuality(rawValue: saved.preferences.renderQualityID),
              runtime.environmentSelection.cameraPreset == camera,
              runtime.environmentSelection.renderQuality == quality,
              environmentMatchesDTO,
              runtime.environmentSelection.timeOfDayHours == saved.environment.timeOfDayHours,
              runtime.trainingMode.rawValue.isEmpty == false,
              runtime.audioVolume.isFinite, (0...1).contains(runtime.audioVolume),
              candidateIncidentMaintenance.state.simulationTick.value == savedFixedTick,
              candidateIncidentMaintenance.state.eventDefinitions == Self.makeIncidentDefinitions(),
              candidateIncidentMaintenance.state.depotRecord.vehicleID.rawValue == "PLAYER",
              candidateIncidentMaintenance.state.depotRecord.depotID.rawValue == "fictional-depot",
              runtime.pendingIncidentManualSignals.isSubset(of: Self.allowedIncidentManualSignals),
              runtime.pendingIncidentRecoveryActionIDs.isSubset(of: Self.allowedIncidentRecoveryActionIDs),
              candidateCrewWorkflow.lastSimulationTime.map({ $0.timeIntervalSinceReferenceDate <= saved.simulation.simulationTimeSeconds + 1e-6 }) ?? true,
              runtime.automaticAnnouncedStopIDs.allSatisfy({ !$0.isEmpty }),
              runtime.stopScoringTickSequence >= 0, runtime.stopScoringEventSequence >= 0,
              runtime.doorProcedureEventSequence >= 0,
              runtime.appliedTimetableDepartureDelaySeconds >= 0,
              Double(runtime.appliedTimetableDepartureDelaySeconds) == saved.timetable.departureDelaySeconds,
              runtime.fixedStepAccumulator.isFinite,
              (0..<TrainPhysics.PhysicsConstants.fixedTimeStepSeconds).contains(runtime.fixedStepAccumulator),
              abs(runtime.fixedStepAccumulator - saved.simulation.fixedStepRemainderSeconds) < 1e-9,
              abs(runtime.arrivalDwellSeconds - saved.simulation.arrivalDwellSeconds) < 1e-9,
              saved.timetable.initialDelayMinutes >= 0, saved.timetable.initialDelayMinutes <= 30,
              saved.route.distanceM > 0 else {
            throw SimulationSaveStateError.incompatibleSave
        }

        let trip = try RegionalRouteFactory.make(plan: plan, variant: variant, category: category, direction: direction)
        guard runtime.automaticAnnouncedStopIDs.isSubset(of: Set(trip.stops.map(\.stationID))),
              trip.routeID == saved.route.routeID,
              abs(trip.profile.distanceM - saved.route.distanceM) < 0.1,
              abs(trip.profile.stopMarkerM - saved.route.stopMarkerM) < 0.1 else {
            throw SimulationSaveStateError.incompatibleSave
        }
        var candidateEngine = TrainPhysicsProfileAdapter.makeEngine(
            for: profile,
            passengerLoadFactor: saved.physics.passengerLoadFactor
        )
        guard runtime.physics.profileID == saved.vehicle.profileID,
              abs(runtime.physics.positionM - saved.physics.positionM) < 1e-6,
              abs(runtime.physics.speedMps - saved.physics.speedMps) < 1e-6,
              abs(runtime.physics.simulationTimeSeconds - saved.simulation.simulationTimeSeconds) < 1e-6,
              abs(runtime.physics.accumulatorSeconds - saved.physics.physicsAccumulatorSeconds) < 1e-9 else {
            throw SimulationSaveStateError.incompatibleSave
        }
        try candidateEngine.restoreState(from: runtime.physics)
        let candidateTrain = profile.makeParameters()
        let candidateBlocks = Self.makeBlocks(route: trip.profile)
        let expectedSchedule = Self.makeSchedule(route: trip.profile, train: candidateTrain, blocks: candidateBlocks)
        guard (runtime.scheduleEngine == nil) == (expectedSchedule == nil) else {
            throw SimulationSaveStateError.incompatibleSave
        }
        let candidateSchedule = runtime.scheduleEngine
        if let schedule = candidateSchedule, let expected = expectedSchedule {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            let savedRouteDefinition = try encoder.encode(schedule.route)
            let trustedRouteDefinition = try encoder.encode(expected.route)
            let savedTrains = schedule.trains.sorted { $0.id < $1.id }
            let trustedTrains = expected.trains.sorted { $0.id < $1.id }
            let trainDefinitionsMatch = savedTrains.count == trustedTrains.count &&
                zip(savedTrains, trustedTrains).allSatisfy { pair in
                    let savedTrain = pair.0
                    let trustedTrain = pair.1
                    return savedTrain.id == trustedTrain.id &&
                    savedTrain.trackID == trustedTrain.trackID &&
                    savedTrain.maximumSpeedMps == trustedTrain.maximumSpeedMps &&
                    savedTrain.maximumAccelerationMps2 == trustedTrain.maximumAccelerationMps2 &&
                    savedTrain.serviceDecelerationMps2 == trustedTrain.serviceDecelerationMps2 &&
                    savedTrain.lengthM == trustedTrain.lengthM &&
                    savedTrain.positionM.isFinite && (0...trip.profile.distanceM).contains(savedTrain.positionM) &&
                    savedTrain.speedMps.isFinite && (0...savedTrain.maximumSpeedMps).contains(savedTrain.speedMps) &&
                    savedTrain.accelerationMps2.isFinite &&
                    savedTrain.accelerationMps2 >= -savedTrain.serviceDecelerationMps2 - 1e-6 &&
                    savedTrain.accelerationMps2 <= savedTrain.maximumAccelerationMps2 + 1e-6 &&
                    savedTrain.commandedSpeedMps.isFinite && (0...savedTrain.maximumSpeedMps).contains(savedTrain.commandedSpeedMps)
                }
            let separationIsValid = Dictionary(grouping: savedTrains, by: \.trackID).values.allSatisfy { trains in
                let ordered = trains.sorted { $0.positionM < $1.positionM }
                return zip(ordered, ordered.dropFirst()).allSatisfy { pair in
                    let follower = pair.0
                    let leader = pair.1
                    return leader.positionM - leader.lengthM - follower.positionM >= schedule.minimumSeparationM - 1e-6
                }
            }
            guard savedRouteDefinition == trustedRouteDefinition,
                  schedule.blocks == candidateBlocks,
                  schedule.minimumSeparationM == expected.minimumSeparationM,
                  schedule.safetyMarginM == expected.safetyMarginM,
                  schedule.label.rawValue == expected.label.rawValue,
                  schedule.elapsedSeconds.isFinite,
                  abs(schedule.elapsedSeconds - saved.simulation.simulationTimeSeconds) < 1e-6,
                  trainDefinitionsMatch, separationIsValid else {
                throw SimulationSaveStateError.incompatibleSave
            }
        }
        // batch119: the timetable candidate is built before
        // the traffic candidate (it used to be built after):
        // a restored session's traffic scenario is anchored
        // to its own timetable (see reset()), so the saved
        // engine state must be validated against the scenario
        // generated for THIS session's anchor, not whatever
        // scenario the previous session happened to install.
        let candidateTimetable: RegionalTimetableSelection?
        if variant == .depotTransfer {
            candidateTimetable = nil
            guard saved.timetable.serviceID == nil else { throw SimulationSaveStateError.incompatibleSave }
        } else {
            guard let network = timetableNetwork else { throw SimulationSaveStateError.incompatibleSave }
            candidateTimetable = try RegionalTimetableAdapter.selectRun(
                network: network,
                category: category,
                direction: direction,
                calendar: calendar,
                daypart: daypart,
                initialDelayMinutes: saved.timetable.initialDelayMinutes,
                routeOriginStationID: trip.stops.first?.stationID ?? ""
            )
            guard candidateTimetable?.plannedTrip.tripID == saved.timetable.serviceID,
                  abs(Double(candidateTimetable?.routeOriginDelaySeconds ?? 0) - saved.timetable.departureDelaySeconds) < 1e-6 else {
                throw SimulationSaveStateError.incompatibleSave
            }
        }
        /// The restored session's traffic clock zero, derived
        /// exactly as gameClockAnchorDaySeconds derives it
        /// live (origin departure − 30 s); the 05:30 zero for
        /// the schedule-less depot transfer.
        let restoredServiceDayStart: Double = candidateTimetable.flatMap { selection in
            selection.simulatedTrip.stationEvents.first(where: { $0.stationID == selection.routeOriginStationID })?.departureSeconds
        }.map { Double($0) - Self.originDepartureSessionSeconds } ?? Self.trafficServiceDayZero
        var candidateTraffic = try runtime.traffic.map { snapshot -> TrafficSimulationEngine in
            guard let scenario = Self.makeTrafficScenario(serviceDayStart: restoredServiceDayStart) else {
                throw SimulationSaveStateError.incompatibleSave
            }
            var engine = try TrafficSimulationEngine(scenario: scenario)
            try engine.restoreState(from: snapshot)
            // The traffic engine advances at 30 Hz (every 4th
            // physics tick), so its snapshot time legitimately
            // trails the host clock by up to 4 ticks. Demanding
            // 1e-6 here rejected every save taken between traffic
            // advances (CI #418: a 0.5 s save carried a 0.475 s
            // traffic snapshot and loadGame refused it).
            let trafficClockLag = saved.simulation.simulationTimeSeconds - snapshot.simulationTimeSeconds
            guard trafficClockLag >= -1e-9,
                  trafficClockLag <= 4 * TrainPhysics.PhysicsConstants.fixedTimeStepSeconds + 1e-9 else {
                throw SimulationSaveStateError.incompatibleSave
            }
            return engine
        }
        if saved.simulation.simulationTimeSeconds > 0, trafficEngine != nil, candidateTraffic == nil {
            throw SimulationSaveStateError.incompatibleSave
        }
        let candidateATS = runtime.ats
        if let ats = candidateATS {
            guard ats.acknowledgementTimeoutSeconds.isFinite, ats.acknowledgementTimeoutSeconds > 0,
                  ats.lastObservedTimeSeconds.isFinite, (0...saved.simulation.simulationTimeSeconds).contains(ats.lastObservedTimeSeconds),
                  ats.deadlineSeconds.map({ $0.isFinite && $0 >= 0 }) ?? true else {
                throw SimulationSaveStateError.incompatibleSave
            }
        }
        let schedules = candidateTimetable.map {
            RegionalTimetableAdapter.stopSchedules(from: $0, activeStops: trip.stops)
        } ?? [:]
        let preparedScoring = try StopScoringRouteAdapter.prepare(
            trip: trip,
            plan: plan,
            routePackage: routePackage,
            trainLengthMeters: candidateTrain.estimatedTrainLengthM,
            scheduleByStationID: schedules
        )
        guard preparedScoring.activeStops.indices.contains(saved.route.nextStopIndex),
              Array(preparedScoring.activeStops.prefix(saved.route.nextStopIndex).map(\.stationID)) == saved.route.completedStopIDs else {
            throw SimulationSaveStateError.incompatibleSave
        }
        if let snapshot = runtime.stopScoring {
            try preparedScoring.engine.restore(from: snapshot)
        } else if !preparedScoring.stationDefinitions.isEmpty {
            throw SimulationSaveStateError.incompatibleSave
        }
        let candidateDoorScoring: DoorProcedureScoring.DoorProcedureScoringEngine?
        if variant == .depotTransfer {
            candidateDoorScoring = nil
            guard runtime.doorScoring == nil else { throw SimulationSaveStateError.incompatibleSave }
        } else {
            let scorer = try DoorProcedureScoringRouteAdapter.makeEngine(routeID: trip.routeID, stops: preparedScoring.activeStops)
            if let snapshot = runtime.doorScoring {
                try scorer.restore(from: snapshot)
            } else {
                throw SimulationSaveStateError.incompatibleSave
            }
            candidateDoorScoring = scorer
        }
        var candidateMode: GameModeSession?
        if let modeState = runtime.gameMode {
            guard let scenario = runtime.gameModeScenario,
                  saved.mode?.modeID == modeState.mode.rawValue,
                  saved.mode?.playStyleID == modeState.playStyle.rawValue,
                  saved.mode?.statusID == modeState.status.rawValue,
                  modeState.lastSnapshot.routeID == trip.routeID,
                  scenario.routeID == trip.routeID else {
                throw SimulationSaveStateError.incompatibleSave
            }
            var session = try GameModeSession(mode: modeState.mode, snapshot: modeState.lastSnapshot, scenario: scenario)
            try session.restoreState(from: modeState)
            candidateMode = session
        } else if saved.mode != nil || runtime.gameModeScenario != nil {
            throw SimulationSaveStateError.incompatibleSave
        }
        guard let logValue = saved.drivingLog else { throw SimulationSaveStateError.incompatibleSave }
        var candidateRecorder = DrivingSessionRecorder(metadata: Self.makeSessionMetadata(route: trip.profile))
        let recorderSnapshot = try SimulatorRuntimeSnapshot.decodeJSONValue(DrivingSessionRecorderSnapshot.self, from: logValue)
        try candidateRecorder.restoreState(from: recorderSnapshot)
        guard candidateRecorder.metadata.sessionID == saved.sessionID,
              candidateRecorder.metadata.routeName == trip.profile.lineName else {
            throw SimulationSaveStateError.incompatibleSave
        }
        let validatedSoundProfile = soundProfile

        routeVariant = variant
        serviceCategory = category
        travelDirection = direction
        routeID = trip.routeID
        route = trip.profile
        activeStops = preparedScoring.activeStops
        selectedVehicleProfile = profile
        selectedSoundProfile = validatedSoundProfile
        train = candidateTrain
        engine = candidateEngine
        blockSystem = candidateBlocks
        scheduleEngine = candidateSchedule
        // batch119: install the restored session's own
        // anchored scenario (not whatever scenario the
        // previous session used), so a later lazy engine
        // rebuild advances the same world the restored
        // engine runs on.
        trafficScenario = Self.makeTrafficScenario(serviceDayStart: restoredServiceDayStart)
        // batch64: scenario installed by the restore —
        // advance the generation the pose caches key on.
        TrafficScenarioGeneration.advance()
        trafficEngine = candidateTraffic
        atsSystem = candidateATS
        rebuildProtectionSession()
        timetableCalendar = calendar
        timetableDaypart = daypart
        timetableInitialDelayMinutes = saved.timetable.initialDelayMinutes
        timetableSelection = candidateTimetable
        timetableSettingsPendingRestart = saved.timetable.settingsPendingRestart
        appliedTimetableDepartureDelaySeconds = runtime.appliedTimetableDepartureDelaySeconds
        stopScoringEngine = preparedScoring.engine
        stopScoringEvaluation = preparedScoring.engine.evaluation()
        stopScoringError = nil
        stopScoringTickSequence = runtime.stopScoringTickSequence
        stopScoringEventSequence = runtime.stopScoringEventSequence
        scoringStationID = runtime.scoringStationID
        pendingScoringDepartureStationID = runtime.pendingScoringDepartureStationID
        pendingStopScoringEvents.removeAll(keepingCapacity: true)
        doorProcedureScoringEngine = candidateDoorScoring
        doorProcedureEvaluation = candidateDoorScoring?.evaluation()
        doorProcedureScoringError = variant == .depotTransfer ? "車庫入出庫の疑似停車点は旅客駅ドア・手順採点の対象外です。" : nil
        doorProcedureEventSequence = runtime.doorProcedureEventSequence
        gameModeSession = candidateMode
        gameModeCurrentStationID = runtime.gameModeCurrentStationID
        pendingGameModeStationEvent = runtime.pendingGameModeStationEvent.map { ($0.stationID, $0.event) }
        gameModeDoorState = runtime.gameModeDoorState
        gameModeHostNotice = nil
        // batch108: a restored session starts with no departure
        // sequence in flight.
        departureSequenceCloseAt = nil
        departureBuzzerArmed = false
        departureBuzzerAt = nil
        crewWorkflow = candidateCrewWorkflow
        incidentMaintenanceEngine = candidateIncidentMaintenance
        incidentTickResult = nil
        incidentNotice = nil
        pendingIncidentManualSignals = runtime.pendingIncidentManualSignals
        pendingIncidentRecoveryActionIDs = runtime.pendingIncidentRecoveryActionIDs
        automaticAnnouncedStopIDs = runtime.automaticAnnouncedStopIDs
        lastATSProtectedBlockID = runtime.lastATSProtectedBlockID
        pendingConfirmations = runtime.pendingConfirmations
        environmentSelection = runtime.environmentSelection
        weather = weatherCondition(for: inferredDrivingWeather(environmentSelection.environment))
        trainingMode = runtime.trainingMode
        controls = TrainControls(
            throttleNotch: saved.controls.throttleNotch,
            brakeNotch: saved.controls.brakeNotch,
            emergencyBrake: saved.controls.emergencyBrake
        )
        nextStopIndex = saved.route.nextStopIndex
        simulationTime = saved.simulation.simulationTimeSeconds
        fixedStepAccumulator = runtime.fixedStepAccumulator
        arrivalDwellSeconds = runtime.arrivalDwellSeconds
        runPhase = .running
        isPaused = true
        recorder = candidateRecorder
        audioEnabled = runtime.audioEnabled
        audioVolume = runtime.audioVolume
        announcementLocale = runtime.announcementLocale
        audioEventScheduler.reset(to: simulationTime)
        audioEventSequence = 0
        audio.setTractionSoundProfile(selectedSoundProfile)
        audio.setEnabled(audioEnabled)
        audio.setVolume(Float(audioVolume))
        rebuildGameplayCoordinators()
        refreshPublishedTelemetry()
        trafficSnapshot = trafficEngine?.snapshot(playerTrain: playerTrafficState())
        lastFrameTime = nil
        completedSummary = nil
        completedReview = nil
        latestOperationsSnapshot = nil
        operationsSnapshot = nil
        refreshOperationsSnapshot()
        updateAudio()
    }

    private enum SimulationSaveStateError: Error {
        case invalidHostState
        case incompatibleSave
    }

    private func persistCurrentSession() {
        guard !recorder.samples.isEmpty,
              let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        let directory = documents.appendingPathComponent("DriveSessions", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let url = directory.appendingPathComponent("drive-\(recorder.metadata.sessionID.uuidString).json")
            try recorder.save(to: url)
            latestSessionURL = url
            storageNotice = nil
        } catch {
            storageNotice = "走行記録を保存できませんでした。空き容量とファイルアクセスを確認してください。"
        }
    }

    /// batch60: true while the train is still standing where
    /// reset() placed it at the run origin. Replaces the old
    /// `positionM <= 0.5` checks, which assumed every run starts
    /// with the consist front on the origin station centre.
    private var isAtOriginPosition: Bool {
        engine.positionM <= originStartPositionM + 0.5
    }

    /// batch60: place the train stopped at the origin platform.
    /// The scoring preparation computed the same platform-centred
    /// target for the origin that every later stop uses; without
    /// this the consist front sat on the station centre
    /// (chainage 0) and the train started mid-platform with its
    /// rear off the platform end. Called from reset() and from
    /// init (which builds the default working without reset()).
    private func placeTrainAtOriginTarget() {
        originStartPositionM = 0
        if let originTarget = stopScoringOriginTargetM, originTarget > 0 {
            engine.placeAt(positionM: originTarget)
            originStartPositionM = originTarget
        }
    }

    func reset() {
        if !recorder.samples.isEmpty { persistCurrentSession() }
        engine.reset()
        engine.setPassengerLoadFactor(0.7)
        controls = TrainControls()
        weather = weatherCondition(for: inferredDrivingWeather(environmentSelection.environment))
        simulationTime = 0
        fixedStepAccumulator = 0
        arrivalDwellSeconds = 0
        gameModeSession = nil
        gameModeHostNotice = nil
        gameModeDoorState = .closed
        autoDoorServedStationID = nil
        autoDoorCloseAt = nil
        departureSequenceCloseAt = nil
        departureBuzzerArmed = false
        departureBuzzerAt = nil
        crewWorkflow = CrewWorkflow()
        incidentMaintenanceEngine = Self.makeIncidentMaintenanceEngine(seed: 0x5241494C)
        incidentTickResult = nil
        incidentNotice = nil
        pendingIncidentManualSignals.removeAll(keepingCapacity: true)
        pendingIncidentRecoveryActionIDs.removeAll(keepingCapacity: true)
        audioEventScheduler.reset(to: 0)
        audioEventSequence = 0
        clearAudioCueEdges()
        // batch78: 新しい運転セッションの開始として、キー音＋
        // 逆転器音を最初のライブフレームで鳴らすよう武装する。
        sessionStartCuesArmed = true
        automaticAnnouncedStopIDs.removeAll(keepingCapacity: true)
        gameModeCurrentStationID = nil
        pendingGameModeStationEvent = nil
        nextStopIndex = min(1, max(0, activeStops.count - 1))
        lastATSProtectedBlockID = nil
        latestOperationsSnapshot = nil
        operationsSnapshot = nil
        pendingConfirmations.removeAll(keepingCapacity: true)
        runPhase = .running
        isPaused = false
        completedSummary = nil
        completedReview = nil
        latestSessionURL = nil
        storageNotice = nil
        rebuildStopScoringSession()
        rebuildDoorProcedureScoringSession()
        // batch60: start stopped AT the origin platform (see
        // placeTrainAtOriginTarget). placeAt re-resets the
        // physics state, so this runs before the schedule /
        // traffic / telemetry rebuilds below. The screenshot
        // tour teleports explicitly per spot, so it is unaffected.
        placeTrainAtOriginTarget()
        recorder = DrivingSessionRecorder(metadata: Self.makeSessionMetadata(route: route))
        atsSystem = try? EducationalATSConfirmation(acknowledgementTimeoutSeconds: 5)
        rebuildProtectionSession()
        scheduleEngine = Self.makeSchedule(route: route, train: train, blocks: blockSystem)
        // batch119: the scenario is generated on THIS
        // session's clock zero — the display anchor for a
        // scheduled service (rebuildStopScoringSession above
        // has already installed the timetable selection), the
        // 05:30 service-day zero for free-running modes,
        // which is what gameClockAnchorDaySeconds returns
        // there. Before this, the scenario always ran on
        // 05:30 while batch108 had moved only the DISPLAY
        // clock, so diagram trains moved off up to a full
        // service day later than the clock on screen implied
        // and early sessions were empty by construction.
        trafficScenario = Self.makeTrafficScenario(serviceDayStart: gameClockAnchorDaySeconds)
        trafficAdvanceFailureLogged = false
        // batch64: scenario (re)installed — advance the
        // generation the pose caches key on.
        TrafficScenarioGeneration.advance()
        trafficEngine = trafficScenario.flatMap(Self.makeTrafficEngine(from:))
        trafficSnapshot = trafficEngine?.snapshot()
        // batch101: reset() cleared storageNotice above, so a
        // traffic build failure is re-surfaced for the new
        // session instead of leaving it silently train-less.
        noteTrafficUnavailableIfNeeded()
        refreshPublishedTelemetry()
        lastFrameTime = nil
        refreshOperationsSnapshot()
        rebuildGameplayCoordinators()
        updateAudio()
    }

    private static let manualIncidentTriggerID = "game.incident.manual"
    private static let incidentRecoveryActionID = "game.incident.recover"
    private static let allowedIncidentManualSignals: Set<String> = [manualIncidentTriggerID]
    private static let allowedIncidentRecoveryActionIDs: Set<String> = [incidentRecoveryActionID]

    private static func makeIncidentMaintenanceEngine(seed: UInt64) -> IncidentMaintenanceEngine? {
        try? IncidentMaintenanceEngine(
            seed: seed,
            eventDefinitions: makeIncidentDefinitions(),
            depotRecord: DepotRecord(
                vehicleID: VehicleID("PLAYER"),
                depotID: DepotID("fictional-depot")
            )
        )
    }

    private static func makeIncidentDefinitions() -> [IncidentEventDefinition] {
        let disclaimer = incidentMaintenanceFictionDisclaimer
        return [
            IncidentEventDefinition(
                id: EventDefinitionID("fictional.player_vehicle_event"),
                kind: .vehicleFailure,
                trigger: .manualSignal(manualIncidentTriggerID),
                occurrenceChancePerEligibleTick: 1_000_000,
                duration: EventDurationRange(minimumTicks: 300, maximumTicks: 900),
                impactScope: .vehicle(VehicleID("PLAYER")),
                effects: GameEffects(tractionMultiplier: 0.88, speedMultiplier: 0.92),
                recoveryRule: .actionRequired(incidentRecoveryActionID),
                fictionalResponsePrompt: "\(disclaimer) — 架空ゲームの車両イベントです。画面上の選択肢のみを使用します。",
                fictionalRecoveryPrompt: "\(disclaimer) — 最低ゲームtick後に、架空イベントを復旧状態へ進められます。"
            )
        ]
    }

    private static func loadRoute() -> LoadedRailwayRoute {
        if let url = Bundle.main.url(forResource: "FictionalRegionalMainline", withExtension: "json"),
           let data = try? Data(contentsOf: url),
           let configuration = try? RailwayRoutePackageLoader.load(data: data) {
            return configuration
        }
        let fallback = RailwayRouteProfile.fictionalMainlineFallback
        let warning = RouteDataIssue(
            code: "route.package.fallback",
            severity: .warning,
            field: "routePackage",
            message: "60km架空本線fallbackへ切替えました。運行計画の読み込みを確認してください。"
        )
        return LoadedRailwayRoute(profile: fallback, blockSystem: makeBlocks(route: fallback), issues: [warning] + fallback.validateData())
    }

    /// The traffic clock zero for a session with no player
    /// timetable: the fictional service-day start, 05:30.
    /// batch119: scheduled sessions generate their scenario
    /// on their own anchor instead (see makeTrafficScenario).
    private static let trafficServiceDayZero = 19_800.0

    /// batch66: the assembled scenario is a pure function of
    /// the bundled resources and the (process-constant) launch
    /// arguments — and, since batch119, of the session's
    /// service-day start. A full read of the generation path
    /// (loadBundledRegionalNetwork, FictionalOperationsPlan.loadBundled,
    /// generatedDiagramTrains) shows no randomness, no clock
    /// and no UUID use; the only environment read is
    /// ProcessInfo's argument list (the -RMTour meet train),
    /// which cannot change during a process. reset() used to
    /// regenerate all 798 diagram trains on every route
    /// selection for an identical result, so the value is
    /// built once per process and reused. TrafficScenario is a
    /// struct, every caller receives the value (copy-on-write),
    /// nothing mutates a scenario in place, and the per-reset
    /// engine rebuild / validation still run as before. A nil
    /// result is not cached, so a transient load failure
    /// still retries.
    /// batch119: the cache is keyed by the service-day start.
    /// Free-running modes keep the 05:30 zero (19,800), so
    /// their scenario is byte-identical to the pre-batch119
    /// one; a scheduled session's scenario is generated on
    /// its display anchor (gameClockAnchorDaySeconds), with
    /// trains that departed before the anchor placed en
    /// route by generatedDiagramTrains. The alternative —
    /// pre-rolling a 05:30 engine to the anchor inside
    /// reset() — was costed and rejected for every anchor in
    /// the selectable range: the engine steps at 120 Hz with
    /// a full separation scan per tick (~806 trains × 8
    /// tracks), so even the earliest anchor (a 06:00
    /// departure, 212,400 ticks) costs tens of seconds of
    /// blocked reset time, a 09:00 departure 1.5M ticks, and
    /// an evening one ~5M ticks.
    private static var cachedTrafficScenarios: [Int: TrafficScenario] = [:]

    private static func makeTrafficScenario(serviceDayStart: Double = trafficServiceDayZero) -> TrafficScenario? {
        let key = Int(serviceDayStart.rounded())
        if let cached = cachedTrafficScenarios[key] { return cached }
        let scenario = buildTrafficScenario(serviceDayStart: Double(key))
        if let scenario {
            // Anchors vary by chosen trip, but sessions run
            // one at a time; keep the cache to a handful of
            // entries so trying many departures cannot grow
            // it without bound.
            if cachedTrafficScenarios.count >= 8 { cachedTrafficScenarios.removeAll() }
            cachedTrafficScenarios[key] = scenario
        }
        return scenario
    }

    private static func buildTrafficScenario(serviceDayStart: Double) -> TrafficScenario? {
        guard let source = try? TrafficScenarioLibrary.loadBundledRegionalNetwork() else {
            // batch119: a failed scenario build used to be a
            // silent nil — the session simply had no trains.
            noteTrafficLog("TRAFFIC_GEN_FAIL stage=scenario-load")
            return nil
        }
        // Game clock zero for this scenario: the session's
        // service-day start (05:30 for free-running modes,
        // the player's display anchor for scheduled ones).
        // All subsystems then share the same relative seconds
        // and fixed-tick count.
        return TrafficScenario(
            scenarioID: source.scenarioID,
            routeID: source.routeID,
            routeLengthM: source.routeLengthM,
            fixedTimeStepSeconds: source.fixedTimeStepSeconds,
            minimumTrainGapM: source.minimumTrainGapM,
            minimumRoadVehicleGapM: source.minimumRoadVehicleGapM,
            passingVisualizationDistanceM: source.passingVisualizationDistanceM,
            tracks: source.tracks + [
                // Siding tracks at the multi-track stations: same
                // path and direction as the mains, offset outboard
                // to the loop line beside the platform (9.64 m).
                TrafficTrackDefinition(id: "main-up-siding", routePathID: "mainline", parallelGroupID: "mainline", direction: .increasing, lateralOffsetM: -9.64),
                TrafficTrackDefinition(id: "main-down-siding", routePathID: "mainline", parallelGroupID: "mainline", direction: .decreasing, lateralOffsetM: 9.64)
            ],
            roads: source.roads,
            platforms: source.platforms,
            trains: Self.generatedDiagramTrains(serviceDayStart: serviceDayStart, sourceTrains: source.trains),
            roadVehicles: source.roadVehicles.map { plan in
                RoadVehiclePlan(
                    id: plan.id,
                    roadID: plan.roadID,
                    departureTimeSeconds: max(0, plan.departureTimeSeconds - serviceDayStart),
                    startPositionM: plan.startPositionM,
                    destinationPositionM: plan.destinationPositionM,
                    targetSpeedMps: plan.targetSpeedMps,
                    accelerationMps2: plan.accelerationMps2,
                    lengthM: plan.lengthM
                )
            },
            passengerTrips: source.passengerTrips.map { trip in
                PlatformPassengerTrip(
                    id: trip.id,
                    platformID: trip.platformID,
                    startTimeSeconds: max(0, trip.startTimeSeconds - serviceDayStart),
                    startOffsetM: trip.startOffsetM,
                    destinationOffsetM: trip.destinationOffsetM,
                    walkingSpeedMps: trip.walkingSpeedMps
                )
            },
            routePaths: source.routePaths,
            dataStatus: source.dataStatus
        )
    }

    /// Shifts a bundled sample plan onto the game clock (zero =
    /// 05:30), exactly as the pre-diagram scenario did.
    private static func shiftedTrain(_ plan: AITrainPlan, serviceDayStart: Double) -> AITrainPlan {
        AITrainPlan(
            id: plan.id,
            trackID: plan.trackID,
            departureTimeSeconds: max(0, plan.departureTimeSeconds - serviceDayStart),
            startPositionM: plan.startPositionM,
            destinationPositionM: plan.destinationPositionM,
            maximumSpeedMps: plan.maximumSpeedMps,
            accelerationMps2: plan.accelerationMps2,
            brakingDecelerationMps2: plan.brakingDecelerationMps2,
            lengthM: plan.lengthM,
            stops: plan.stops,
            serviceType: plan.serviceType,
            servicePeriod: plan.servicePeriod,
            operationKind: plan.operationKind,
            scheduledTripDurationSeconds: plan.scheduledTripDurationSeconds
        )
    }

    /// Diagram v4 phase offsets in minutes (8:00-base), solved on
    /// 2026-11-11 so the 9:00-12:00 window runs conflict-free at the
    /// 15 passing stations; see workspace/diagram/_diagram_v4_result.json.
    /// Applied as the offset of the first departure of each daytime
    /// pattern (every phase is smaller than its headway, so this
    /// reproduces the solver's departure series inside the window).
    private static func diagramV4PhaseMinutes(direction: ServiceDirection, category: ServiceCategory) -> Int {
        switch (direction, category) {
        case (.down, .limitedExpress): return 52
        case (.down, .rapidExpress): return 19
        case (.down, .express): return 17
        case (.down, .rapid): return 0
        case (.down, .semiExpress): return 7
        case (.down, .local): return 3
        case (.up, .limitedExpress): return 38
        case (.up, .rapidExpress): return 6
        case (.up, .express): return 23
        case (.up, .rapid): return 6
        case (.up, .semiExpress): return 8
        case (.up, .local): return 1
        }
    }

    /// Diagram v4 AI traffic (2026-11-11): the bundled scenario's
    /// ten sample trains are replaced by a full service day
    /// generated from the operations plan. Every timetable pattern
    /// contributes departures at its own first/last/interval; the
    /// daytime patterns already carry the v4 headways in the plan
    /// JSON and additionally get the v4 phase offset above. Plan
    /// directions are geographic: "down" departs the Kaibukuro end
    /// toward Kamogawa (increasing centre chainage, track main-up)
    /// and "up" runs back (track main-down) -- the same convention
    /// TimetableBuilder uses for the player's trips. Stops are the
    /// service's mainline stops with 30 s dwell (45 s at S12
    /// Chihara); the termini themselves are the run's endpoints,
    /// not stops. Plan durations describe the 68 km through run,
    /// so over the 60 km mainline the pace is conservative; each
    /// train's maximum speed is set from the cruise speed the plan
    /// implies (distance over duration minus dwell and an
    /// acceleration allowance), with 30 percent headroom, and the
    /// engine's schedule cap keeps the train near its planned
    /// whole-line time. Formations follow the user's consist
    /// rules: locals and limited expresses are 8 cars (156 m),
    /// the other mainline categories 10 cars (195 m). The plan's
    /// through services cannot switch route paths mid-run in the
    /// traffic engine, so the branch instead gets its own local
    /// shuttles on the branch tracks, and the bundled depot
    /// movements are carried over shifted. If the plan cannot be
    /// loaded, the bundled sample trains are kept (shifted) so
    /// traffic still runs.
    private static func generatedDiagramTrains(serviceDayStart: Double, sourceTrains: [AITrainPlan]) -> [AITrainPlan] {
        // batch119: every plan below is first expressed with
        // its ABSOLUTE day-second departure and then passed
        // through anchoredPlan, which shifts post-anchor
        // departures onto the session clock (the pre-batch119
        // behaviour) and places pre-anchor departures en
        // route at the anchor (or drops them if their run
        // already completed). In the 05:30 frame no departure
        // precedes the zero, so the output is unchanged there.
        let depotTrains = sourceTrains.filter { $0.operationKind != .passengerService }
            .compactMap { Self.anchoredPlan($0, departureDaySeconds: $0.departureTimeSeconds, serviceDayStart: serviceDayStart) }
        guard let plan = FictionalOperationsPlan.loadBundled() else {
            return sourceTrains.compactMap { Self.anchoredPlan($0, departureDaySeconds: $0.departureTimeSeconds, serviceDayStart: serviceDayStart) }
        }
        let mainlineLength = plan.network.mainlineLengthKm * 1_000
        let mainlineChainage: [String: Double] = Dictionary(
            uniqueKeysWithValues: plan.stations
                .filter { $0.lineId == plan.network.mainlineID }
                .map { ($0.stationId, $0.chainageKm * 1_000) }
        )
        let branchChainages: [Double] = plan.stations
            .filter { $0.lineId == plan.network.branchID }
            .map { $0.chainageKm * 1_000 }
            .filter { $0 > 0 && $0 < plan.network.branchLengthKm * 1_000 }
            .sorted()
        let chiharaChainage = mainlineChainage["S12"] ?? 24_194

        var trains: [AITrainPlan] = []
        // batch90: the local service's generated top speed and
        // ascending stop chainages, captured for the
        // session-start seed trains appended after the branch
        // shuttles (see the batch90 block below).
        var localSeedMaximumSpeedMps: Double?
        var localSeedStopsAscending: [Double] = []
        for service in plan.services {
            guard let serviceType = TrainServiceType(rawValue: service.category.rawValue) else { continue }
            let ascendingStops = service.stopStationIDs
                .compactMap { mainlineChainage[$0] }
                .sorted()
            let durationSeconds = Double(service.plannedDurationMinutes * 60)
            let lengthM: Double
            if service.category == .local || service.category == .limitedExpress {
                lengthM = 8 * 19.5
            } else {
                lengthM = 10 * 19.5
            }
            let acceleration: Double
            switch service.category {
            case .local: acceleration = 0.70
            case .semiExpress: acceleration = 0.75
            case .rapid: acceleration = 0.80
            case .express: acceleration = 0.85
            case .rapidExpress: acceleration = 0.90
            case .limitedExpress: acceleration = 0.95
            }
            let speedCap: Double
            switch service.category {
            case .local: speedCap = 27.8
            case .semiExpress, .rapid: speedCap = 30.6
            case .express: speedCap = 33.3
            case .rapidExpress: speedCap = 36.1
            case .limitedExpress: speedCap = 38.9
            }
            for pattern in plan.timetablePatterns where pattern.category == service.category {
                let isDown = pattern.direction == .down
                var orderedStops = ascendingStops.filter { $0 > 0 && $0 < mainlineLength }
                if !isDown { orderedStops.reverse() }
                let stops = orderedStops.map { chainage -> TrafficTrainStop in
                    let dwell: Double
                    if abs(chainage - chiharaChainage) < 0.5 {
                        dwell = 45
                    } else {
                        dwell = 30
                    }
                    return TrafficTrainStop(positionM: chainage, dwellSeconds: dwell)
                }
                let totalDwell = stops.reduce(0.0) { $0 + $1.dwellSeconds }
                let movingSeconds = max(600.0, durationSeconds - totalDwell - Double(stops.count) * 25.0 - 30.0)
                let cruise = mainlineLength / movingSeconds
                let maximumSpeed = min(speedCap, cruise * 1.3)
                if service.category == .local, localSeedMaximumSpeedMps == nil {
                    localSeedMaximumSpeedMps = maximumSpeed
                    localSeedStopsAscending = ascendingStops
                }
                guard let firstMinute = FictionalOperationsPlan.minutesSinceMidnight(pattern.firstDeparture),
                      let lastMinute = FictionalOperationsPlan.minutesSinceMidnight(pattern.lastDeparture),
                      pattern.intervalMinutes > 0 else { continue }
                var minute = firstMinute
                if pattern.daypart == .daytime {
                    minute += Self.diagramV4PhaseMinutes(direction: pattern.direction, category: pattern.category)
                }
                let period: TrafficServicePeriod
                switch pattern.daypart {
                case .morningRush: period = .morningRush
                case .daytime, .evening: period = .daytime
                case .night: period = .night
                }
                let trackID: String
                let startPosition: Double
                let destinationPosition: Double
                if isDown {
                    trackID = "main-up"
                    startPosition = 0
                    destinationPosition = mainlineLength
                } else {
                    trackID = "main-down"
                    startPosition = mainlineLength
                    destinationPosition = 0
                }
                while minute <= lastMinute {
                    let diagramPlan = AITrainPlan(
                        id: "v4-\(service.category.rawValue)-\(pattern.direction.rawValue)-\(pattern.daypart.rawValue)-\(minute)",
                        trackID: trackID,
                        departureTimeSeconds: Double(minute * 60),
                        startPositionM: startPosition,
                        destinationPositionM: destinationPosition,
                        maximumSpeedMps: maximumSpeed,
                        accelerationMps2: acceleration,
                        brakingDecelerationMps2: acceleration + 0.1,
                        lengthM: lengthM,
                        stops: stops,
                        serviceType: serviceType,
                        servicePeriod: period,
                        operationKind: .passengerService,
                        scheduledTripDurationSeconds: durationSeconds
                    )
                    if let anchored = Self.anchoredPlan(diagramPlan, departureDaySeconds: Double(minute * 60), serviceDayStart: serviceDayStart) {
                        trains.append(anchored)
                    }
                    minute += pattern.intervalMinutes
                }
            }
        }

        // Branch shuttles every 30 minutes, 06:00-23:30, on the
        // branch tracks (8 cars, like every branch formation).
        let branchLength = plan.network.branchLengthKm * 1_000
        for isUp in [true, false] {
            var orderedBranchStops = branchChainages
            if !isUp { orderedBranchStops.reverse() }
            let branchStops = orderedBranchStops.map { TrafficTrainStop(positionM: $0, dwellSeconds: 30) }
            let trackID: String
            let startPosition: Double
            let destinationPosition: Double
            if isUp {
                trackID = "branch-up"
                startPosition = 0
                destinationPosition = branchLength
            } else {
                trackID = "branch-down"
                startPosition = branchLength
                destinationPosition = 0
            }
            var minute = 6 * 60
            while minute <= 23 * 60 + 30 {
                let period: TrafficServicePeriod
                if minute < 9 * 60 {
                    period = .morningRush
                } else if minute < 22 * 60 {
                    period = .daytime
                } else {
                    period = .night
                }
                let branchPlan = AITrainPlan(
                    id: "v4-branch-\(isUp ? "up" : "down")-\(minute)",
                    trackID: trackID,
                    departureTimeSeconds: Double(minute * 60),
                    startPositionM: startPosition,
                    destinationPositionM: destinationPosition,
                    maximumSpeedMps: 13.9,
                    accelerationMps2: 0.70,
                    brakingDecelerationMps2: 0.80,
                    lengthM: 8 * 19.5,
                    stops: branchStops,
                    serviceType: .local,
                    servicePeriod: period,
                    operationKind: .passengerService,
                    scheduledTripDurationSeconds: nil
                )
                if let anchored = Self.anchoredPlan(branchPlan, departureDaySeconds: Double(minute * 60), serviceDayStart: serviceDayStart) {
                    trains.append(anchored)
                }
                minute += 30
            }
        }

        // batch90 (2026-11-16, user on IPA #10: "no oncoming
        // trains at all"): batch87 proved the cause is the
        // session clock, not rendering — the game clock starts
        // at the 05:30 service-day zero, every diagram pattern's
        // first departure is 06:00 from a terminus, and the
        // engine keeps trains .scheduled (unposed, unrendered)
        // until departure, so the first 30 minutes of every
        // session contain no AI trains at all and the first
        // possible meet is ~45 minutes in. Moving the session
        // start to 09:00 was rejected on the impact sweep:
        // shifting the zero alone still starts every train at a
        // terminus (pre-09:00 departures clamp to t=0 there, so
        // the first meet stays ~30 minutes away), while a true
        // 09:00 state needs a 12,600 s pre-roll of the traffic
        // engine — 1.5M ticks at the shared 120 Hz step —
        // inside reset(), which would also expire the batch47
        // tour-meet dwell below and break the t≈0 anchors
        // (timetable-settings gate, chopper start buzzer).
        // Instead, seed a small set of locals that are already
        // en route at t=0: the batch47 tour-meet mechanism
        // generalized to gameplay. Every seed is an ordinary
        // diagram local — the local service's own stops, dwells
        // (30 s, 45 s at Chihara), 8-car length, acceleration
        // and generated top speed — that simply starts mid-run
        // and completes a normal trip, so the seeds only bridge
        // the dead first half hour before the real 06:00
        // diagram flow has crossed the line. Tour sessions are
        // excluded so the photo tour keeps today's behaviour.
        // batch119: the seeds bridge a dead window that only
        // exists in the 05:30 frame. A scheduled session's
        // scenario is generated on its own anchor, where the
        // diagram itself already populates the line (see
        // anchoredPlan), so emitting the seeds there too
        // would double-populate it with unscheduled locals
        // whose fixed 05:30-frame positions can conflict with
        // converted diagram trains at platforms. The seeds
        // therefore stay exclusive to the default frame,
        // where free-running sessions still need the bridge.
        let seedTourArguments = ProcessInfo.processInfo.arguments
        if serviceDayStart == Self.trafficServiceDayZero,
           !seedTourArguments.contains("-RMTour"),
           !seedTourArguments.contains("-RMZooTour"),
           !seedTourArguments.contains("-RMParkTour"),
           let seedMaximumSpeed = localSeedMaximumSpeedMps {
            func seedStops(between lower: Double, and upper: Double, descending: Bool) -> [TrafficTrainStop] {
                var chainages = localSeedStopsAscending.filter { $0 > lower && $0 < upper }
                if descending { chainages.reverse() }
                return chainages.map { chainage in
                    let dwell: Double
                    if abs(chainage - chiharaChainage) < 0.5 {
                        dwell = 45
                    } else {
                        dwell = 30
                    }
                    return TrafficTrainStop(positionM: chainage, dwellSeconds: dwell)
                }
            }
            func seedTrain(id: String, trackID: String, start: Double, destination: Double, stops: [TrafficTrainStop], duration: Double?) -> AITrainPlan {
                AITrainPlan(
                    id: id,
                    trackID: trackID,
                    departureTimeSeconds: 0,
                    startPositionM: start,
                    destinationPositionM: destination,
                    maximumSpeedMps: seedMaximumSpeed,
                    accelerationMps2: 0.70,
                    brakingDecelerationMps2: 0.80,
                    lengthM: 8 * 19.5,
                    stops: stops,
                    serviceType: .local,
                    servicePeriod: .morningRush,
                    operationKind: .passengerService,
                    scheduledTripDurationSeconds: duration
                )
            }
            // Opposing locals already inside the first 10 km of
            // each terminus, so a departing player meets traffic
            // within the first minutes in either direction.
            // Their remaining runs are under 20 km, so the
            // scenario validator does not require a trip
            // duration; without the schedule cap their pace is
            // set by the same stop-to-stop braking curves a
            // diagram local obeys.
            trains.append(seedTrain(
                id: "seed-main-down-09000", trackID: "main-down",
                start: 9_000, destination: 0,
                stops: seedStops(between: 0, and: 9_000, descending: true),
                duration: nil
            ))
            trains.append(seedTrain(
                id: "seed-main-up-51000", trackID: "main-up",
                start: 51_000, destination: mainlineLength,
                stops: seedStops(between: 51_000, and: mainlineLength, descending: false),
                duration: nil
            ))
            // Mid-line locals, so the middle of the line is
            // alive from the first minute too (remaining runs
            // again just under the 20 km duration threshold).
            trains.append(seedTrain(
                id: "seed-main-down-19500", trackID: "main-down",
                start: 19_500, destination: 0,
                stops: seedStops(between: 0, and: 19_500, descending: true),
                duration: nil
            ))
            trains.append(seedTrain(
                id: "seed-main-up-40500", trackID: "main-up",
                start: 40_500, destination: mainlineLength,
                stops: seedStops(between: 40_500, and: mainlineLength, descending: false),
                duration: nil
            ))
            // Same-direction locals ahead of each terminus on
            // near-full-length runs. These carry an explicit
            // 3,600 s duration (the validator's minimum for a
            // 20 km+ passenger run), whose schedule cap holds
            // them at roughly the pace a diagram local runs
            // over the same ground.
            trains.append(seedTrain(
                id: "seed-main-up-12000", trackID: "main-up",
                start: 12_000, destination: mainlineLength,
                stops: seedStops(between: 12_000, and: mainlineLength, descending: false),
                duration: 3_600
            ))
            trains.append(seedTrain(
                id: "seed-main-down-48000", trackID: "main-down",
                start: 48_000, destination: 0,
                stops: seedStops(between: 0, and: 48_000, descending: true),
                duration: 3_600
            ))
            // Branch shuttles already mid-run, mirroring the
            // generated shuttles' own parameters, so a branch
            // session also starts with a shuttle on its way.
            trains.append(AITrainPlan(
                id: "seed-branch-up-03000",
                trackID: "branch-up",
                departureTimeSeconds: 0,
                startPositionM: 3_000,
                destinationPositionM: branchLength,
                maximumSpeedMps: 13.9,
                accelerationMps2: 0.70,
                brakingDecelerationMps2: 0.80,
                lengthM: 8 * 19.5,
                stops: branchChainages.filter { $0 > 3_000 }.map { TrafficTrainStop(positionM: $0, dwellSeconds: 30) },
                serviceType: .local,
                servicePeriod: .morningRush,
                operationKind: .passengerService,
                scheduledTripDurationSeconds: nil
            ))
            trains.append(AITrainPlan(
                id: "seed-branch-down-05000",
                trackID: "branch-down",
                departureTimeSeconds: 0,
                startPositionM: 5_000,
                destinationPositionM: 0,
                maximumSpeedMps: 13.9,
                accelerationMps2: 0.70,
                brakingDecelerationMps2: 0.80,
                lengthM: 8 * 19.5,
                stops: branchChainages.filter { $0 < 5_000 }.reversed().map { TrafficTrainStop(positionM: $0, dwellSeconds: 30) },
                serviceType: .local,
                servicePeriod: .morningRush,
                operationKind: .passengerService,
                scheduledTripDurationSeconds: nil
            ))
        }

        // batch47 (2026-11-14, user: why has no photograph ever
        // shown an opposing train?): the diagram itself explains
        // it — the session clock starts at the 05:30 service-day
        // zero and every pattern's first departure is 06:00 from
        // a terminus, so for the tour's first half hour the
        // opposing track is empty by construction, and after
        // that a 30 s dwell or a fast pass never lines up with a
        // held teleport spot. The cab session's meet hunt was a
        // lottery against those facts. In mainline TOUR sessions
        // only (-RMTour; never in gameplay, where this train
        // does not exist), add one up local that starts the day
        // already standing at S14 Tsudaike (28,452, a passing
        // station) on the opposing track main-down. Its first
        // stop is 1 m ahead of its start (the scenario validator
        // requires strictly increasing stop progress) with a
        // 7,200 s dwell, so the engine creeps 1 m, parks at the
        // down platform from the first seconds of the session
        // and stays there until long after any tour ends. The
        // final tour spot (28,432, the S14 approach) therefore
        // frames a guaranteed opposing train across the island
        // platform — a structural guarantee from the engine's
        // dwell semantics, not a timing coincidence. The plan
        // remains a valid up local throughout (remaining stops
        // below, 30 s dwells, 45 s at Chihara, the standard
        // 9,000 s local duration the validator requires for a
        // 20 km+ passenger run); no real session reaches its
        // departure.
        let tourArguments = ProcessInfo.processInfo.arguments
        if tourArguments.contains("-RMTour"),
           !tourArguments.contains("-RMZooTour"),
           !tourArguments.contains("-RMParkTour") {
            let meetStationM = mainlineChainage["S14"] ?? 28_452
            var meetStops = [TrafficTrainStop(positionM: meetStationM - 1, dwellSeconds: 7_200)]
            for chainage in mainlineChainage.values.sorted(by: >) where chainage > 0 && chainage < meetStationM - 1.5 {
                let dwell = abs(chainage - chiharaChainage) < 0.5 ? 45.0 : 30.0
                meetStops.append(TrafficTrainStop(positionM: chainage, dwellSeconds: dwell))
            }
            trains.append(AITrainPlan(
                id: "tour-meet-local-up-tsudaike",
                trackID: "main-down",
                departureTimeSeconds: 0,
                startPositionM: meetStationM,
                destinationPositionM: 0,
                maximumSpeedMps: 27.8,
                accelerationMps2: 0.70,
                brakingDecelerationMps2: 0.80,
                lengthM: 8 * 19.5,
                stops: meetStops,
                serviceType: .local,
                servicePeriod: .morningRush,
                operationKind: .passengerService,
                scheduledTripDurationSeconds: 9_000
            ))
        }

        trains.append(contentsOf: depotTrains)
        return trains
    }

    /// batch119: expresses one plan on the session clock.
    /// The plan's departureTimeSeconds and the
    /// departureDaySeconds argument both carry the plan's
    /// ABSOLUTE day-second departure (every call site builds
    /// plans that way since batch119). A departure at or
    /// after the service-day start is shifted exactly as
    /// before (shiftedTrain). An earlier departure is placed
    /// en route at the start — position, remaining stops
    /// and remaining schedule derived by enRoutePlacement —
    /// and the returned plan departs at t = 0 from that
    /// position: the batch90 seed form, generalised from
    /// eight hand-placed locals to every diagram train. A
    /// train whose run completed before the start returns
    /// nil; it is not in the world at the anchor, exactly
    /// as the engine would have completed and despawned it.
    private static func anchoredPlan(_ plan: AITrainPlan, departureDaySeconds: Double, serviceDayStart: Double) -> AITrainPlan? {
        if departureDaySeconds >= serviceDayStart {
            return shiftedTrain(plan, serviceDayStart: serviceDayStart)
        }
        let elapsed = serviceDayStart - departureDaySeconds
        guard let placement = enRoutePlacement(of: plan, elapsedSeconds: elapsed) else { return nil }
        let remainingRoute = abs(plan.destinationPositionM - placement.startPositionM)
        // Scenario validation (TrafficModels.validate): a
        // passenger run of 20 km or more must carry a
        // duration, and any passenger duration it carries
        // must be at least 3,600 s. Below 20 km remaining
        // the duration is dropped instead — the batch90
        // seeds established that an uncapped short remainder
        // runs at the same stop-to-stop braking-curve pace,
        // while stretching a short remainder up to a
        // 3,600 s cap would make the train visibly dawdle.
        var duration = placement.remainingDurationSeconds
        if plan.operationKind == .passengerService {
            if remainingRoute < 20_000 {
                duration = nil
            } else if let remaining = duration {
                duration = max(3_600, remaining)
            } else {
                duration = 3_600
            }
        }
        return AITrainPlan(
            id: plan.id,
            trackID: plan.trackID,
            departureTimeSeconds: 0,
            startPositionM: placement.startPositionM,
            destinationPositionM: plan.destinationPositionM,
            maximumSpeedMps: plan.maximumSpeedMps,
            accelerationMps2: plan.accelerationMps2,
            brakingDecelerationMps2: plan.brakingDecelerationMps2,
            lengthM: plan.lengthM,
            stops: placement.stops,
            serviceType: plan.serviceType,
            servicePeriod: plan.servicePeriod,
            operationKind: plan.operationKind,
            scheduledTripDurationSeconds: duration
        )
    }

    /// batch119: derives where a train is `elapsedSeconds`
    /// after its departure, in the engine's own terms. With
    /// a schedule duration, the engine's cap targets arrival
    /// at departure + duration, so moving time is budgeted
    /// pro-rata across segments at the cap's average pace;
    /// without one, each segment runs its acceleration /
    /// cruise / braking trapezoid at the plan's maximum
    /// speed. Dwells are exact in both models. The result
    /// feeds a seed-form plan, so a small placement error
    /// degrades gracefully: the engine's separation
    /// enforcement resolves any overlap on the first ticks,
    /// and the stop list is rebuilt as the stops strictly
    /// ahead of the placed position, so the train can never
    /// be sent back to a stop behind it. Returns nil when
    /// the run completed before the anchor instant.
    private static func enRoutePlacement(of plan: AITrainPlan, elapsedSeconds: Double) -> (startPositionM: Double, stops: [TrafficTrainStop], remainingDurationSeconds: Double?)? {
        let start = plan.startPositionM
        let destination = plan.destinationPositionM
        let sign = destination >= start ? 1.0 : -1.0
        let totalRoute = abs(destination - start)
        guard totalRoute > 0.35 else { return nil }
        let stops = plan.stops
        let totalDwell = stops.reduce(0.0) { $0 + $1.dwellSeconds }
        let duration = plan.scheduledTripDurationSeconds
        if let duration, elapsedSeconds >= duration { return nil }
        let movingTotal = duration.map { max(1, $0 - totalDwell) } ?? 0

        // Segment boundaries: start, each stop, destination.
        var points: [Double] = [start]
        points.append(contentsOf: stops.map(\.positionM))
        points.append(destination)

        func segmentTime(_ index: Int) -> Double {
            let segment = abs(points[index + 1] - points[index])
            if duration != nil { return movingTotal * segment / totalRoute }
            return trapezoid(segment: segment, tau: 0, plan: plan).time
        }
        func travelled(inSegment index: Int, tau: Double) -> Double {
            let segment = abs(points[index + 1] - points[index])
            if duration != nil { return min(segment, tau * (totalRoute / movingTotal)) }
            return trapezoid(segment: segment, tau: tau, plan: plan).distance
        }

        var clock = 0.0
        for index in 0..<(points.count - 1) {
            let from = points[index]
            if elapsedSeconds < clock + segmentTime(index) {
                // Running inside this segment, approaching
                // stops[index] (or the destination on the
                // final segment).
                let position = from + sign * travelled(inSegment: index, tau: elapsedSeconds - clock)
                guard abs(destination - position) > 0.35 else { return nil }
                let remainingStops = stops.enumerated().filter { entry in
                    entry.offset >= index && (entry.element.positionM - position) * sign > 0.5
                }.map(\.element)
                return (position, remainingStops, duration.map { $0 - elapsedSeconds })
            }
            clock += segmentTime(index)
            // Dwell at the stop just reached (the final
            // point is the destination: no dwell, run over).
            if index < stops.count {
                let dwell = stops[index].dwellSeconds
                if elapsedSeconds < clock + dwell {
                    // Dwelling at stops[index]: re-express
                    // the remaining dwell as a first stop 1 m
                    // ahead — the batch47 tour-meet form, so
                    // the engine creeps forward and holds for
                    // exactly the time left at the anchor.
                    let stopPosition = stops[index].positionM
                    let synthetic = stopPosition + sign * 1
                    let remainingStops = stops.enumerated().filter { entry in
                        entry.offset > index && (entry.element.positionM - stopPosition) * sign > 1.5
                    }.map(\.element)
                    if (destination - synthetic) * sign >= 0 {
                        let dwellStop = TrafficTrainStop(positionM: synthetic, dwellSeconds: clock + dwell - elapsedSeconds)
                        return (stopPosition, [dwellStop] + remainingStops, duration.map { $0 - elapsedSeconds })
                    }
                    return (stopPosition, remainingStops, duration.map { $0 - elapsedSeconds })
                }
                clock += dwell
            }
        }
        return nil
    }

    /// Acceleration / cruise / braking trapezoid for one
    /// segment at the plan's maximum speed: the total time
    /// to traverse it, and the distance covered `tau`
    /// seconds in. Mirrors the braking-curve pace the
    /// engine's advanceTrain follows between stops.
    private static func trapezoid(segment: Double, tau: Double, plan: AITrainPlan) -> (time: Double, distance: Double) {
        let vmax = plan.maximumSpeedMps
        let accel = plan.accelerationMps2
        let brake = plan.brakingDecelerationMps2
        let accelDistance = vmax * vmax / (2 * accel)
        let brakeDistance = vmax * vmax / (2 * brake)
        if segment >= accelDistance + brakeDistance {
            let time = vmax / accel + vmax / brake + (segment - accelDistance - brakeDistance) / vmax
            let distance: Double
            if tau <= vmax / accel {
                distance = 0.5 * accel * tau * tau
            } else if tau >= time - vmax / brake {
                let remaining = max(0, time - tau)
                distance = segment - 0.5 * brake * remaining * remaining
            } else {
                distance = accelDistance + vmax * (tau - vmax / accel)
            }
            return (time, min(segment, distance))
        }
        let peak = (2 * segment / (1 / accel + 1 / brake)).squareRoot()
        let time = peak / accel + peak / brake
        let distance: Double
        if tau <= peak / accel {
            distance = 0.5 * accel * tau * tau
        } else {
            let remaining = max(0, time - tau)
            distance = segment - 0.5 * brake * remaining * remaining
        }
        return (time, min(segment, distance))
    }

    /// batch119: traffic failure lines for the pulled demo
    /// log. The scene drains this queue in
    /// flushPulledLogIfNeeded, the same channel the asset
    /// loader's diagnostics ride (batch58), so a failure
    /// reaches demo-drive-log.txt instead of dying inside a
    /// try? or a transient on-screen notice.
    private static var pendingTrafficLogLines: [String] = []

    private static func noteTrafficLog(_ line: String) {
        pendingTrafficLogLines.append(line)
    }

    static func drainTrafficLogLines() -> [String] {
        defer { pendingTrafficLogLines.removeAll() }
        return pendingTrafficLogLines
    }

    private static func makeTrafficEngine(from scenario: TrafficScenario) -> TrafficSimulationEngine? {
        do {
            return try TrafficSimulationEngine(scenario: scenario)
        } catch {
            // batch119: was a bare try? — an invalid scenario
            // silently meant a train-less session (see
            // noteTrafficUnavailableIfNeeded, which only
            // reaches the screen).
            noteTrafficLog("TRAFFIC_GEN_FAIL error=\(String(describing: error).prefix(160))")
            return nil
        }
    }

    /// batch101: makeTrafficEngine swallows the engine's
    /// validation error (try?), and buildTrafficScenario returns
    /// nil when the bundled regional network fails to load. Both
    /// used to be completely silent: the session simply had no AI
    /// trains, indistinguishable from the batch51/87 "no
    /// oncoming trains" defects the user reported. Surface the
    /// state through the existing notice channel. Only fills an
    /// empty notice, so a more specific message already on screen
    /// is never overwritten; reset() clears the notice before its
    /// rebuild, so a persistent failure is reported once per
    /// session rather than never.
    private func noteTrafficUnavailableIfNeeded() {
        guard trafficEngine == nil, storageNotice == nil else { return }
        if trafficScenario == nil {
            storageNotice = "架空交通シナリオを読み込めなかったため、AI列車なしで運転を継続します。"
        } else {
            storageNotice = "架空交通AIを初期化できなかったため、AI列車なしで運転を継続します。"
        }
    }
}
