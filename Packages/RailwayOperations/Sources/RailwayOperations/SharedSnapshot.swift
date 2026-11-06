import Foundation

/// Minimal, engine-neutral train state shared across operations, traffic, audio, and rendering adapters.
public struct SharedTrainSnapshot: Codable, Equatable, Sendable {
    public let trainID: String
    public let trackID: String
    public let positionM: Double
    public let speedMps: Double
    public let accelerationMps2: Double
    public let lengthM: Double

    public init(trainID: String, trackID: String, positionM: Double, speedMps: Double, accelerationMps2: Double, lengthM: Double) throws {
        guard !trainID.isEmpty, !trackID.isEmpty,
              positionM.isFinite, positionM >= 0,
              speedMps.isFinite, speedMps >= 0,
              accelerationMps2.isFinite,
              lengthM.isFinite, lengthM > 0 else {
            throw OperationsError.invalidValue("shared train snapshot")
        }
        self.trainID = trainID
        self.trackID = trackID
        self.positionM = positionM
        self.speedMps = speedMps
        self.accelerationMps2 = accelerationMps2
        self.lengthM = lengthM
    }
}

/// The stable read-only contract other workstreams can consume without importing UI or engine objects.
public protocol SharedRailwaySnapshot: Sendable {
    var simulationTimeSeconds: Double { get }
    var fixedTick: UInt64 { get }
    var fixedTimeStepSeconds: Double { get }
    var routeID: String { get }
    var train: SharedTrainSnapshot { get }
}

public struct OperationsSnapshot: Codable, Equatable, Sendable, SharedRailwaySnapshot {
    public static let currentSchemaVersion = 1

    public let schemaVersion: Int
    public let simulationTimeSeconds: Double
    public let fixedTick: UInt64
    public let fixedTimeStepSeconds: Double
    public let routeID: String
    public let runID: String
    public let train: SharedTrainSnapshot
    public let mode: TrainingMode
    public let workflowPhase: WorkflowPhase
    public let currentStationID: String?
    public let nextStationID: String?
    public let latestGameSignal: GameSignalAspect?
    public let doorsClosed: Bool
    public let scheduleOffsetSeconds: Double?
    public let pendingPointingCallingIDs: [String]
    public let activeDisruptionIDs: [String]
    public let overallScore: Double?
    public let contentLabel: OperationsContentLabel

    public init(
        schemaVersion: Int = OperationsSnapshot.currentSchemaVersion,
        simulationTimeSeconds: Double,
        fixedTick: UInt64,
        fixedTimeStepSeconds: Double,
        routeID: String,
        runID: String,
        train: SharedTrainSnapshot,
        mode: TrainingMode,
        workflowPhase: WorkflowPhase,
        currentStationID: String? = nil,
        nextStationID: String? = nil,
        latestGameSignal: GameSignalAspect? = nil,
        doorsClosed: Bool,
        scheduleOffsetSeconds: Double? = nil,
        pendingPointingCallingIDs: [String] = [],
        activeDisruptionIDs: [String] = [],
        overallScore: Double? = nil
    ) throws {
        guard schemaVersion == Self.currentSchemaVersion,
              simulationTimeSeconds.isFinite, simulationTimeSeconds >= 0,
              fixedTimeStepSeconds.isFinite, fixedTimeStepSeconds > 0,
              !routeID.isEmpty, !runID.isEmpty,
              scheduleOffsetSeconds.map(\.isFinite) ?? true,
              overallScore.map({ $0.isFinite && (0...100).contains($0) }) ?? true,
              !pendingPointingCallingIDs.contains(where: \.isEmpty),
              !activeDisruptionIDs.contains(where: \.isEmpty) else {
            throw OperationsError.invalidValue("operations snapshot")
        }
        self.schemaVersion = schemaVersion
        self.simulationTimeSeconds = simulationTimeSeconds
        self.fixedTick = fixedTick
        self.fixedTimeStepSeconds = fixedTimeStepSeconds
        self.routeID = routeID
        self.runID = runID
        self.train = train
        self.mode = mode
        self.workflowPhase = workflowPhase
        self.currentStationID = currentStationID
        self.nextStationID = nextStationID
        self.latestGameSignal = latestGameSignal
        self.doorsClosed = doorsClosed
        self.scheduleOffsetSeconds = scheduleOffsetSeconds
        self.pendingPointingCallingIDs = pendingPointingCallingIDs
        self.activeDisruptionIDs = activeDisruptionIDs
        self.overallScore = overallScore
        self.contentLabel = .gameOnlyNotSafetyTraining
    }

    public static func make(
        workflow: OperationsWorkflow,
        train: SharedTrainSnapshot,
        simulationTimeSeconds: Double,
        fixedTick: UInt64,
        fixedTimeStepSeconds: Double,
        pointingCalling: PointingCallingTracker? = nil,
        activeDisruptionIDs: [String] = [],
        scorecard: OperationsScorecard? = nil
    ) throws -> OperationsSnapshot {
        let currentStationID = workflow.phase == .stationStop ? workflow.currentStop?.id : nil
        let isEnRouteToNextStop = workflow.phase == .departurePreparation || workflow.phase == .enRoute
        let nextStationID = isEnRouteToNextStop ? workflow.currentStop?.id : nil
        let latestSchedule = workflow.scheduleObservations.last
        return try OperationsSnapshot(
            simulationTimeSeconds: simulationTimeSeconds,
            fixedTick: fixedTick,
            fixedTimeStepSeconds: fixedTimeStepSeconds,
            routeID: workflow.scenario.routeID,
            runID: workflow.scenario.runID,
            train: train,
            mode: workflow.mode,
            workflowPhase: workflow.phase,
            currentStationID: currentStationID,
            nextStationID: nextStationID,
            latestGameSignal: workflow.latestGameSignal,
            doorsClosed: workflow.doorsClosed,
            scheduleOffsetSeconds: latestSchedule?.deviationSeconds,
            pendingPointingCallingIDs: pointingCalling?.dueCheckpointIDs ?? [],
            activeDisruptionIDs: activeDisruptionIDs,
            overallScore: scorecard?.overallScore
        )
    }
}
