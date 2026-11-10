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

@MainActor
final class SimulatorModel: ObservableObject {
    private static let blockLengthM = 500.0
    private static let yellowSignalSpeedKmh = 45.0
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
    @Published private(set) var dataValidationIssues: [RouteDataIssue] = []
    @Published private(set) var gameModeSession: GameModeSession?
    @Published private(set) var gameModeHostNotice: String?
    @Published private(set) var gameModeDoorState: GameModeDoorState = .closed
    @Published private(set) var saveSlots: [SaveSlotSummary] = []

    var gameModeContext: RegionalGameModeContext {
        let promptIDs: Set<String> = blockSystem.blocks.isEmpty || atsSystem == nil
            ? []
            : ["PLACEHOLDER-training-signal-display", "PLACEHOLDER-training-protection-display"]
        return RegionalGameModeContext(
            routeID: routeID,
            route: route,
            stops: activeStops,
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
            telemetry: projected,
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
        max(0, Double(appliedTimetableDepartureDelaySeconds) - simulationTime)
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
    private var appliedTimetableDepartureDelaySeconds = 0
    private var trafficEngine: TrafficSimulationEngine?
    private var trafficScenario: TrafficScenario?
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
    @Published private(set) var protectionNeedsAcknowledgement = false
    private var recorder: DrivingSessionRecorder
    private var latestOperationsSnapshot: SimulatorOperationsSnapshot?
    private let audio = RailwayAudioEngine.shared
    private var lastFrameTime: TimeInterval?
    private var fixedStepAccumulator = 0.0
    private var arrivalDwellSeconds = 0.0
    private var stopScoringEngine: StopScoring.StopScoringEngine?
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
        let loadedRoute = Self.loadRoute()
        train = loadedTrain
        selectedVehicleProfile = profile
        selectedSoundProfile = profile.soundProfile
        route = trip?.profile ?? loadedRoute.profile
        routeID = trip?.routeID ?? "fictional-legacy-route"
        regionalPlan = plan
        canonicalRoutePackage = routePackage
        timetableNetwork = try? RegionalTimetableAdapter.loadCanonicalNetwork()
        activeStops = trip?.stops ?? [
            RegionalRouteStop(stationID: "LEGACY_START", name: loadedRoute.profile.departureStation, positionM: 0, trackID: "main-up"),
            RegionalRouteStop(stationID: "LEGACY_END", name: loadedRoute.profile.arrivalStation, positionM: loadedRoute.profile.stopMarkerM, trackID: "main-up")
        ]
        engine = loadedPhysics
        blockSystem = Self.makeBlocks(route: trip?.profile ?? loadedRoute.profile)
        scheduleEngine = Self.makeSchedule(route: trip?.profile ?? loadedRoute.profile, train: loadedTrain, blocks: blockSystem)
        trafficScenario = Self.makeTrafficScenario()
        trafficEngine = trafficScenario.flatMap(Self.makeTrafficEngine(from:))
        trafficSnapshot = trafficEngine?.snapshot()
        atsSystem = try? EducationalATSConfirmation(acknowledgementTimeoutSeconds: 5)
        recorder = DrivingSessionRecorder(metadata: Self.makeSessionMetadata(route: trip?.profile ?? loadedRoute.profile))
        trainPhysicsTelemetry = loadedPhysics.telemetry
        stoppingDistanceEstimate = nil
        telemetry = TrainPhysicsProfileAdapter.projectTelemetry(
            loadedPhysics.telemetry,
            engine: loadedPhysics,
            route: trip?.profile ?? loadedRoute.profile,
            stoppingDistance: nil
        )
        dataValidationIssues = trip?.profile.validateData() ?? loadedRoute.issues
        rebuildProtectionSession()
        rebuildStopScoringSession()
        rebuildDoorProcedureScoringSession()
        incidentMaintenanceEngine = Self.makeIncidentMaintenanceEngine(seed: 0x5241494C)
        refreshOperationsSnapshot()
        rebuildGameplayCoordinators()
        audio.start()
        audio.setTractionSoundProfile(selectedSoundProfile)
        updateAudio()
        refreshSaveSlots()
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
        let realDelta = min(max(time - previous, 0), 0.5)
        guard realDelta > 0 else { return }
        driveDemoIfEnabled()
        fixedStepAccumulator += realDelta
        let fixedStep = TrainPhysics.PhysicsConstants.fixedTimeStepSeconds
        while fixedStepAccumulator + 1e-12 >= fixedStep, runPhase == .running {
            fixedStepAccumulator -= fixedStep
            simulationTime += fixedStep
            simulationTick(dt: fixedStep)
        }
        applyPendingDoorCloseIfDue()
        refreshPublishedTelemetry()
        if let latestOperationsSnapshot { operationsSnapshot = latestOperationsSnapshot }
        let waitingForScheduledDeparture = timetableDepartureRemainingSeconds > 0 && engine.positionM <= 0.5
        let effectiveControls: TrainControls
        if latestOperationsSnapshot?.automaticBrakeActive == true {
            effectiveControls = TrainControls(
                throttleNotch: 0,
                brakeNotch: max(appliedDrivingControls.brakeNotch, 7),
                emergencyBrake: appliedDrivingControls.emergencyBrake || latestOperationsSnapshot?.atsStatus?.automaticBrakeCommanded == true
            )
        } else if waitingForScheduledDeparture {
            effectiveControls = TrainControls(throttleNotch: 0, brakeNotch: 7)
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

        let signalContext = nextSignalContext()
        if let reading = signalContext.reading,
           reading.aspect != .green,
           lastATSProtectedBlockID != reading.blockID {
            do {
                try atsSystem?.trigger(at: simulationTime)
                audio.playATSAlarm()
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
        let maintenanceSpeedCap = min(
            route.condition(at: engine.positionM).speedLimitKmh * max(maintenanceEffects.maximumSpeedMultiplier * activeIncidentEffects.speedMultiplier, 0),
            maintenanceEffects.speedCapKmh ?? Double.infinity
        )
        let permittedSpeed = min(basePermittedSpeed, maintenanceSpeedCap)
        let currentSpeedKmh = engine.speedMps * 3.6
        let exceededPattern = currentSpeedKmh > permittedSpeed + 0.25
        if exceededPattern && !lastExceededPattern {
            audio.playATSAlarm()
        }
        lastExceededPattern = exceededPattern
        let atsBrake = atsStatus?.automaticBrakeCommanded == true
        let automaticBrake = exceededPattern || atsBrake
        let nextStopPosition = activeStops.indices.contains(nextStopIndex) ? activeStops[nextStopIndex].positionM : route.stopMarkerM
        let stationHold = abs(engine.positionM - nextStopPosition) <= Self.arrivalToleranceM && currentSpeedKmh <= 0.5
        let waitingForScheduledDeparture = timetableDepartureRemainingSeconds > 0 && engine.positionM <= 0.5
        let effectiveControls: TrainControls
        if automaticBrake {
            effectiveControls = TrainControls(
                throttleNotch: 0,
                brakeNotch: 7,
                emergencyBrake: atsBrake
            )
        } else if waitingForScheduledDeparture {
            effectiveControls = TrainControls(throttleNotch: 0, brakeNotch: 7)
        } else if stationHold || maintenanceEffects.departureHeld || activeIncidentEffects.departureHeld {
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
                speedCapKmh: maintenanceSpeedCap,
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
        guard var traffic = trafficEngine else { return }
        let step = TrainPhysics.PhysicsConstants.fixedTimeStepSeconds
        let tick = UInt64(max(0, (simulationTime / step).rounded()))
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
        let trackID: String
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
        let currentLimit = max(route.condition(at: engine.positionM).speedLimitKmh, 0)
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

        if let signal, let block = signalBlock {
            switch signal.aspect {
            case .red:
                let stopPosition = max(engine.positionM + 0.1, block.startM - 2)
                if stopPosition <= route.distanceM,
                   let target = try? SafetyStopTarget(identifier: "red-signal-\(block.identifier)", positionM: stopPosition, targetSpeedKmh: 0) {
                    targets.append(target)
                }
            case .yellow:
                let targetPosition = max(engine.positionM + 0.1, block.startM - 2)
                if targetPosition <= route.distanceM,
                   let target = try? SafetyStopTarget(identifier: "yellow-signal-\(block.identifier)", positionM: targetPosition, targetSpeedKmh: Self.yellowSignalSpeedKmh) {
                    targets.append(target)
                }
            case .green:
                break
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
                    runPhase = .arrived
                    finishDoorProcedureScoring(finalizing: targetStop.stationID)
                    finishStopScoring()
                    captureCompletedRun()
                    persistCurrentSession()
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
            isOnPoints: audioOnPoints,
            doorsOpen: gameModeDoorState.isOpen,
            weather: audioWeather,
            windMetersPerSecond: Float(environmentSelection.environment.windSpeedMps),
            trainPosition: trainPosition,
            listenerPosition: listenerPosition
        ))
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
        let fallback = try! RailwayBlock(identifier: "fictional-block-fallback", startM: 0, endM: max(route.distanceM, 1), trackID: "T1")
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
        // quality25 READY emission (see tourAwaitingAckIndex): the
        // gate is simulation time at least 4 s past the teleport —
        // the model and the view share the main runloop, so sim
        // time advancing means frames at the new location have been
        // presented — with the train standing at the spot.
        if tourEnabled, tourReadyPendingIndex >= 0,
           simulationTime >= tourTeleportSimTime + 4,
           abs(engine.positionM - Self.tourSpotsM[tourReadyPendingIndex]) < 5 {
            let line = "READY spot=\(tourReadyPendingIndex) pos=\(Int(engine.positionM))\n"
            if let data = line.data(using: .utf8) { handle.write(data) }
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
        if let data = line.data(using: .utf8) { handle.write(data) }
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
    private static let tourSpotsM: [Double] = [100, 500, 1_000, 1_300, 1_654, 1_800, 1_856, 58_150, 4_466, 5_545, 6_522, 35_050, 17_650, 23_980, 45_327, 59_955]
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
    // quality25 (E): READY alone did not fix the drift (CI #232:
    // only 7 of 16 spots photographed at their labelled positions,
    // three pure black, six the same stretch of coast). The app
    // advanced on its own 35 s wall schedule while simctl took
    // tens of seconds per screenshot, so by the time a capture
    // executed the train had teleported on. The tour is now a
    // two-way handshake: after READY the app HOLDS the spot until
    // the script writes Documents/tour-ack-<i>.txt (it writes the
    // ACK right after each screenshot), with a 150 s timeout so a
    // dead script can never stall the tour or the job.
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
            if elapsed >= 25, simulationTime >= 15 {
                tourSpotIndex = 0
                teleportForTour(to: Self.tourSpotsM[0])
                logTourTeleport(to: Self.tourSpotsM[0], spotIndex: 0)
                tourReadyPendingIndex = 0
                tourTeleportSimTime = simulationTime
            }
        } else if tourAwaitingAckIndex == tourSpotIndex, tourReadyWallTime >= 0 {
            // READY is out for the current spot: wait for the
            // script's ACK (checked about twice a second), or time
            // out after 150 s and move on regardless.
            if now - tourLastAckCheckWall >= 0.5 {
                tourLastAckCheckWall = now
                let acknowledged = tourAckExists(for: tourSpotIndex)
                if acknowledged || now - tourReadyWallTime >= 150 {
                    if !acknowledged {
                        logTourLine("ACKTIMEOUT spot=\(tourSpotIndex)\n")
                    }
                    tourAwaitingAckIndex = -1
                    tourReadyWallTime = -1
                    let next = tourSpotIndex + 1
                    if next < Self.tourSpotsM.count {
                        tourSpotIndex = next
                        teleportForTour(to: Self.tourSpotsM[next])
                        logTourTeleport(to: Self.tourSpotsM[next], spotIndex: next)
                        tourReadyPendingIndex = next
                        tourTeleportSimTime = simulationTime
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
        if let data = line.data(using: .utf8) { handle.write(data) }
    }

    private func logTourTeleport(to position: Double, spotIndex: Int) {
        guard let handle = demoLogHandle else { return }
        let line = "TOUR spot=\(spotIndex) pos=\(Int(position)) wall=\(Int(Date().timeIntervalSinceReferenceDate))\n"
        if let data = line.data(using: .utf8) { handle.write(data) }
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

    func setThrottle(_ notch: Int) {
        guard runPhase == .running else { return }
        let value = min(max(notch, 0), max(train.tractionNotchFractions.count - 1, 0))
        controls = TrainControls(
            throttleNotch: value,
            brakeNotch: value > 0 ? 0 : controls.brakeNotch,
            emergencyBrake: controls.emergencyBrake,
            masterReversed: value == 0 && controls.masterReversed
        )
        noteProtectionDriverActivity()
    }

    func setBrake(_ notch: Int) {
        guard runPhase == .running else { return }
        let value = min(max(notch, 0), 7)
        controls = TrainControls(
            throttleNotch: value > 0 ? 0 : controls.throttleNotch,
            brakeNotch: value,
            emergencyBrake: controls.emergencyBrake,
            masterReversed: controls.masterReversed && value == 0
        )
        noteProtectionDriverActivity()
    }

    func setEmergencyBrake(_ isOn: Bool) {
        guard runPhase == .running else { return }
        controls = TrainControls(
            throttleNotch: isOn ? 0 : controls.throttleNotch,
            brakeNotch: controls.brakeNotch,
            emergencyBrake: isOn,
            masterReversed: controls.masterReversed && !isOn
        )
        noteProtectionDriverActivity()
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
        if simulationTime <= 0.000_1 && engine.positionM <= 0.5 && runPhase == .running {
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
            return selection
        } catch {
            timetableSelectionError = "架空時刻表を現在の運転条件へ結び付けられませんでした: \(error.localizedDescription)"
            return nil
        }
    }

    @discardableResult
    func selectRoute(variant: RegionalRouteVariant, category: ServiceCategory, direction: RegionalTravelDirection) -> Bool {
        guard let plan = regionalPlan,
              let trip = try? RegionalRouteFactory.make(plan: plan, variant: variant, category: category, direction: direction) else {
            storageNotice = "選択した架空路線・種別・方向を準備できませんでした。路線データを確認してください。"
            return false
        }
        storageNotice = nil
        route = trip.profile
        activeStops = trip.stops
        routeID = trip.routeID
        dataValidationIssues = trip.profile.validateData()
        routeVariant = variant
        serviceCategory = category
        travelDirection = direction
        blockSystem = Self.makeBlocks(route: trip.profile)
        reset()
        return true
    }

    private func rebuildStopScoringSession() {
        stopScoringEngine = nil
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
              let trip = try? RegionalRouteFactory.make(
                plan: plan,
                variant: routeVariant,
                category: serviceCategory,
                direction: travelDirection
              ) else {
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
            stopScoringEvaluation = prepared.engine.evaluation()
        } catch {
            stopScoringError = "架空の駅別停車スコアを準備できませんでした: \(String(describing: error))"
        }
    }

    func setGameModeSession(_ session: GameModeSession?) {
        gameModeSession = session
        if session == nil {
            pendingDoorClose = nil
            gameModeDoorState = .closed
            gameModeHostNotice = nil
        }
    }

    /// Recorded door sound bundled for the selected control family.
    /// The resistance family shares the chopper recordings (project
    /// decision, 2026-11-07); VVVF families use the 223-series
    /// recordings. Nil means no recording is bundled for that family.
    private func bundledDoorSampleName(open: Bool) -> String? {
        switch selectedVehicleProfile.soundProfile {
        case .fieldChopperDC, .rheostaticDC:
            if open { return "door_open_chopper" }
            return "door_close_chopper"
        case .vvvfGTO, .vvvfIGBT, .vvvfIGBTVariableCarrier, .vvvfSiC:
            if open { return "door_open_vvvf" }
            return "door_close_vvvf"
        }
    }

    /// Plays the recorded door sound for the selected vehicle when one
    /// is bundled, falling back to the synthesized door cue.
    private func playDoorSound(open: Bool) {
        if let name = bundledDoorSampleName(open: open),
           audio.playBundledSample(named: name) != nil {
            return
        }
        audio.playDoor(open: open)
    }

    /// Applies a door closure that was held back until the recorded door
    /// chime finished playing.
    private func applyPendingDoorCloseIfDue() {
        guard let pending = pendingDoorClose, simulationTime >= pending.applyAt else { return }
        pendingDoorClose = nil
        let wasOpen = gameModeDoorState.isOpen
        gameModeDoorState = pending.state
        if wasOpen {
            audio.playDoor(open: false)
        }
        gameModeHostNotice = "架空ゲームのドア状態を「\(pending.state.rawValue)」に更新しました。物理モデルのドアではありません。"
    }

    func handleGameModeHostEffects(_ effects: [GameModeHostEffect]) {
        for effect in effects {
            switch effect {
            case .setGameDoorState(let state):
                let wasOpen = gameModeDoorState.isOpen
                if state.isOpen {
                    // Opening cancels any chime-timed closure in progress.
                    pendingDoorClose = nil
                    gameModeDoorState = state
                    if !wasOpen {
                        playDoorSound(open: true)
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
                        playDoorSound(open: false)
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
        guard var session = protectionSession else {
            appliedDrivingControls = driver
            return driver
        }
        protectionTick &+= 1
        let speedKmh = max(0, engine.speedMps * 3.6)
        let input = FictionalLiveProtectionSession.Input(
            fixedTick: protectionTick,
            timeSeconds: max(simulationTime, 0),
            frontPositionM: min(max(engine.positionM, 0), session.routeLengthM),
            speedKmh: speedKmh,
            trainLengthM: max(1, train.estimatedTrainLengthM),
            acknowledgeATSS: protectionAcknowledge,
            driverActivityPulse: protectionActivityPulse,
            resetAfterStop: protectionReset,
            driver: FictionalDriverControls(
                throttleNotch: driver.throttleNotch,
                brakeNotch: driver.brakeNotch,
                emergencyBrake: driver.emergencyBrake
            )
        )
        protectionAcknowledge = false
        protectionActivityPulse = false
        protectionReset = false
        do {
            let outcome = try session.step(input)
            protectionSession = session
            let previousActing = lastProtectionActingSystems
            protectionActingSystems = outcome.command.actingSystems
            cueProtectionSounds(previous: previousActing, outcome: outcome)
            protectionNeedsAcknowledgement = outcome.states.contains {
                $0.trainID == FictionalLiveProtectionSession.playerTrainID
                    && $0.system == ProtectionSystemKind.atsS.rawValue
                    && $0.stateDescription.contains("awaiting")
            }
            let applied = TrainControls(
                throttleNotch: outcome.command.throttleNotch,
                brakeNotch: outcome.command.brakeNotch,
                emergencyBrake: outcome.command.emergencyBrake
            )
            appliedDrivingControls = applied
            return applied
        } catch {
            protectionSession = session
            protectionActingSystems = []
            lastProtectionActingSystems = []
            lastATSSAwaiting = false
            protectionNeedsAcknowledgement = false
            appliedDrivingControls = driver
            return driver
        }
    }

    private func cueProtectionSounds(previous: Set<String>, outcome: FictionalProtectionTickOutcome) {
        let acting = Set(outcome.command.actingSystems)
        let appeared = acting.subtracting(previous)
        let awaiting = outcome.states.contains {
            $0.trainID == FictionalLiveProtectionSession.playerTrainID
                && $0.system == ProtectionSystemKind.atsS.rawValue
                && $0.stateDescription.contains("awaiting")
        }
        if awaiting && !lastATSSAwaiting {
            audio.playATSAlarm()
        }
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
        for impact in impacts.impacts {
            let kind: RailwayAudioEventKind = impact.kind == .pointClatter ? .pointClatter : .railJoint
            audio.playTrackImpact(kind, intensity: impact.intensity)
        }
    }

    private var trackImpactPath: FictionalPlayablePath {
        switch routeVariant {
        case .mainline: .mainline
        case .throughBranch: .throughBranch
        case .branchShuttle: .branchShuttle
        case .depotTransfer: .depotTransfer
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
        guard var system = atsSystem else { return protectionAcknowledge }
        let accepted = (try? system.acknowledge(at: simulationTime)) ?? false
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
        return accepted
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
        var candidateTraffic = try runtime.traffic.map { snapshot -> TrafficSimulationEngine in
            guard let scenario = trafficScenario ?? Self.makeTrafficScenario() else {
                throw SimulationSaveStateError.incompatibleSave
            }
            var engine = try TrafficSimulationEngine(scenario: scenario)
            try engine.restoreState(from: snapshot)
            guard abs(snapshot.simulationTimeSeconds - saved.simulation.simulationTimeSeconds) < 1e-6 else {
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
        trafficScenario = trafficScenario ?? Self.makeTrafficScenario()
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
        crewWorkflow = CrewWorkflow()
        incidentMaintenanceEngine = Self.makeIncidentMaintenanceEngine(seed: 0x5241494C)
        incidentTickResult = nil
        incidentNotice = nil
        pendingIncidentManualSignals.removeAll(keepingCapacity: true)
        pendingIncidentRecoveryActionIDs.removeAll(keepingCapacity: true)
        audioEventScheduler.reset(to: 0)
        audioEventSequence = 0
        clearAudioCueEdges()
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
        recorder = DrivingSessionRecorder(metadata: Self.makeSessionMetadata(route: route))
        atsSystem = try? EducationalATSConfirmation(acknowledgementTimeoutSeconds: 5)
        rebuildProtectionSession()
        scheduleEngine = Self.makeSchedule(route: route, train: train, blocks: blockSystem)
        trafficScenario = Self.makeTrafficScenario()
        trafficEngine = trafficScenario.flatMap(Self.makeTrafficEngine(from:))
        trafficSnapshot = trafficEngine?.snapshot()
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

    private static func makeTrafficScenario() -> TrafficScenario? {
        guard let source = try? TrafficScenarioLibrary.loadBundledRegionalNetwork() else { return nil }
        // Game clock zero represents the fictional service-day first departure (05:30).
        // All subsystems then share the same relative seconds and fixed-tick count.
        let serviceDayStart = 19_800.0
        return TrafficScenario(
            scenarioID: source.scenarioID,
            routeID: source.routeID,
            routeLengthM: source.routeLengthM,
            fixedTimeStepSeconds: source.fixedTimeStepSeconds,
            minimumTrainGapM: source.minimumTrainGapM,
            minimumRoadVehicleGapM: source.minimumRoadVehicleGapM,
            passingVisualizationDistanceM: source.passingVisualizationDistanceM,
            tracks: source.tracks,
            roads: source.roads,
            platforms: source.platforms,
            trains: source.trains.map { plan in
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
            },
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

    private static func makeTrafficEngine(from scenario: TrafficScenario) -> TrafficSimulationEngine? {
        try? TrafficSimulationEngine(scenario: scenario)
    }
}
