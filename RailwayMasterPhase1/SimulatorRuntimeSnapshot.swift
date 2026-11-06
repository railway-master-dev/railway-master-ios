import CrewWorkflow
import DoorProcedureScoring
import EnvironmentConditions
import Foundation
import IncidentMaintenance
import RailwayAudioEnhancements
import RailwayGameModes
import RailwayOperations
import RailwaySessionPersistence
import StopScoring
import TrafficSimulation
import TrainPhysics

struct PendingGameModeStationSnapshot: Codable, Equatable {
    var stationID: String
    var event: GameModeStationEvent
}

/// App-owned state not represented by the stable, cross-version save DTO fields.
/// Existing Operations/RailwayMaintenance mini-game coordinator state remains separate.
struct SimulatorRuntimeSnapshot: Codable {
    static let currentRevision = 2

    var revision: Int
    var physics: TrainPhysicsEngineStateSnapshot
    var traffic: TrafficSimulationStateSnapshot?
    var scheduleEngine: RailwayScheduleEngine?
    var ats: EducationalATSConfirmation?
    var stopScoring: StopScoringSnapshot?
    var doorScoring: DoorProcedureScoringEngineSnapshot?
    var gameMode: GameModeSessionStateSnapshot?
    var gameModeScenario: GameModeScenario?
    var environmentSelection: EnvironmentQualitySelection
    var trainingMode: TrainingMode
    var fixedStepAccumulator: Double
    var arrivalDwellSeconds: Double
    var stopScoringTickSequence: Int
    var stopScoringEventSequence: Int
    var scoringStationID: String?
    var pendingScoringDepartureStationID: String?
    var doorProcedureEventSequence: Int
    var gameModeCurrentStationID: String?
    var pendingGameModeStationEvent: PendingGameModeStationSnapshot?
    var gameModeDoorState: GameModeDoorState
    var lastATSProtectedBlockID: String?
    var pendingConfirmations: [DriveConfirmation]
    var appliedTimetableDepartureDelaySeconds: Int
    var audioEnabled: Bool
    var audioVolume: Double
    var announcementLocale: AnnouncementLocale
    var crewWorkflow: CrewWorkflowSaveDTO
    var incidentMaintenance: IncidentMaintenanceSaveDTO
    var pendingIncidentManualSignals: Set<String>
    var pendingIncidentRecoveryActionIDs: Set<String>
    var automaticAnnouncedStopIDs: Set<String>

    static func encodeJSONValue<T: Encodable>(_ value: T) throws -> SaveJSONValue {
        let data = try JSONEncoder().encode(value)
        return try JSONDecoder().decode(SaveJSONValue.self, from: data)
    }

    static func decodeJSONValue<T: Decodable>(_ type: T.Type, from value: SaveJSONValue) throws -> T {
        let data = try JSONEncoder().encode(value)
        return try JSONDecoder().decode(type, from: data)
    }
}
