import Foundation

public struct VersionedSaveEnvelope: Codable, Equatable, Sendable {
    public static let schemaIdentifier = "jp.railwaymaster.session-save"
    public static let currentSchemaVersion = 2

    public let schema: String
    public let schemaVersion: Int
    public let savedAt: Date
    public let payload: SimulationSaveState

    public init(payload: SimulationSaveState, savedAt: Date = Date()) {
        self.schema = Self.schemaIdentifier
        self.schemaVersion = Self.currentSchemaVersion
        self.savedAt = savedAt
        self.payload = payload
    }
}

public struct DecodedSimulationSave: Equatable, Sendable {
    public let state: SimulationSaveState
    public let savedAt: Date
    /// Set when an older supported schema was migrated in memory.
    public let migratedFromVersion: Int?
    public let migrationMessages: [String]

    public init(state: SimulationSaveState, savedAt: Date, migratedFromVersion: Int? = nil, migrationMessages: [String] = []) {
        self.state = state
        self.savedAt = savedAt
        self.migratedFromVersion = migratedFromVersion
        self.migrationMessages = migrationMessages
    }
}

public enum SessionSaveCodecError: Error, Equatable, Sendable, CustomStringConvertible {
    case unsupportedSchema(String)
    case unsupportedVersion(Int)
    case malformedEnvelope
    case dataTooLarge
    case invalidState(SaveValidationError)

    public var description: String {
        switch self {
        case .unsupportedSchema(let schema): return "Unsupported save schema: \(schema)"
        case .unsupportedVersion(let version): return "Unsupported save version: \(version)"
        case .malformedEnvelope: return "The save envelope is malformed."
        case .dataTooLarge: return "The save exceeds the 8 MiB size limit."
        case .invalidState(let error): return error.description
        }
    }
}

/// Pure codec: no app models, global state, clock, or platform UI dependencies.
public enum SessionSaveCodec {
    public static let maximumEncodedBytes = 8 * 1_024 * 1_024

    public static func encode(_ state: SimulationSaveState, savedAt: Date = Date()) throws -> Data {
        do { try state.validate() }
        catch let error as SaveValidationError { throw SessionSaveCodecError.invalidState(error) }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(VersionedSaveEnvelope(payload: state, savedAt: savedAt))
        guard data.count <= maximumEncodedBytes else { throw SessionSaveCodecError.dataTooLarge }
        return data
    }

    public static func decode(_ data: Data) throws -> DecodedSimulationSave {
        guard data.count <= maximumEncodedBytes else { throw SessionSaveCodecError.dataTooLarge }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let header: EnvelopeHeader
        do { header = try decoder.decode(EnvelopeHeader.self, from: data) }
        catch { throw SessionSaveCodecError.malformedEnvelope }
        guard header.schema == VersionedSaveEnvelope.schemaIdentifier else {
            throw SessionSaveCodecError.unsupportedSchema(header.schema)
        }

        switch header.schemaVersion {
        case VersionedSaveEnvelope.currentSchemaVersion:
            let envelope: VersionedSaveEnvelope
            do { envelope = try decoder.decode(VersionedSaveEnvelope.self, from: data) }
            catch { throw SessionSaveCodecError.malformedEnvelope }
            do { try envelope.payload.validate() }
            catch let error as SaveValidationError { throw SessionSaveCodecError.invalidState(error) }
            return DecodedSimulationSave(state: envelope.payload, savedAt: envelope.savedAt)
        case 1:
            let envelope: LegacyEnvelopeV1
            do { envelope = try decoder.decode(LegacyEnvelopeV1.self, from: data) }
            catch { throw SessionSaveCodecError.malformedEnvelope }
            let migrated = try migrate(envelope.payload)
            do { try migrated.validate() }
            catch let error as SaveValidationError { throw SessionSaveCodecError.invalidState(error) }
            return DecodedSimulationSave(
                state: migrated,
                savedAt: envelope.savedAt,
                migratedFromVersion: 1,
                migrationMessages: [
                    "Migrated schema v1 to v2.",
                    "Settings, detailed physics internals, timetable stops, and subsystem progress absent from v1 were initialized to explicit defaults."
                ]
            )
        default:
            throw SessionSaveCodecError.unsupportedVersion(header.schemaVersion)
        }
    }

    private static func migrate(_ old: LegacySavePayloadV1) throws -> SimulationSaveState {
        let step = 1.0 / 120.0
        let ticksValue = floor(old.simulationTimeSeconds / step)
        guard ticksValue.isFinite, ticksValue >= 0, ticksValue < Double(UInt64.max) else {
            throw SessionSaveCodecError.malformedEnvelope
        }
        let sessionID = old.sessionID ?? UUID()
        let mode = old.modeID.map {
            ModeSessionSnapshot(
                modeID: $0,
                playStyleID: "standard",
                statusID: "active",
                startedAtSimulationSeconds: 0,
                progress: .object([:])
            )
        }
        return SimulationSaveState(
            saveName: old.saveName ?? "Migrated session",
            sessionID: sessionID,
            simulation: SimulationClockSnapshot(
                simulationTimeSeconds: old.simulationTimeSeconds,
                fixedTick: UInt64(ticksValue),
                fixedStepRemainderSeconds: 0,
                isPaused: true,
                runPhaseID: "running"
            ),
            route: RouteProgressSnapshot(
                routeID: old.routeID,
                routeRevision: "legacy-v1",
                variantID: "",
                directionID: "",
                distanceM: old.routeLengthM,
                stopMarkerM: old.routeLengthM,
                nextStopIndex: 0
            ),
            vehicle: PlayerVehicleSnapshot(
                vehicleID: "PLAYER",
                profileID: old.vehicleProfileID,
                soundProfileID: "",
                carCount: old.carCount ?? 1,
                directionID: "forward"
            ),
            controls: ControlStateSnapshot(),
            physics: PhysicsStateSnapshot(
                modelID: "legacy-v1",
                modelVersion: 1,
                physicsAccumulatorSeconds: 0,
                positionM: old.positionM,
                speedMps: old.speedMps,
                passengerLoadFactor: old.passengerLoadFactor ?? 0.7
            ),
            mode: mode,
            timetable: TimetableStateSnapshot(
                calendarID: old.calendarID ?? "WEEKDAY_PLACEHOLDER",
                daypartID: "daytime",
                serviceCategoryID: "local",
                directionID: "up",
                initialDelayMinutes: old.initialDelayMinutes ?? 0
            ),
            environment: EnvironmentStateSnapshot(
                weatherID: "dry",
                precipitationID: "none",
                fogDensity: 0,
                windSpeedMps: 0,
                windDirectionDegrees: 0,
                visibilityM: 100_000,
                adhesionCoefficient: 0.27,
                ambientIlluminanceLux: 20_000,
                headlightIntensity: 0,
                wiperStateID: "off",
                seasonID: "spring",
                dayPeriodID: "day",
                timeOfDayHours: 12
            ),
            preferences: UserPreferencesSnapshot(),
            subsystemStates: [:],
            compatibility: SaveCompatibilitySnapshot(routeCatalogRevision: "legacy-v1", vehicleCatalogRevision: "legacy-v1")
        )
    }
}

private struct EnvelopeHeader: Decodable {
    let schema: String
    let schemaVersion: Int
}

private struct LegacyEnvelopeV1: Decodable {
    let schema: String
    let schemaVersion: Int
    let savedAt: Date
    let payload: LegacySavePayloadV1
}

/// The exact v1 contract intentionally stays private; its decoder is retained as a migration boundary.
private struct LegacySavePayloadV1: Decodable {
    let saveName: String?
    let sessionID: UUID?
    let routeID: String
    let routeLengthM: Double
    let vehicleProfileID: String
    let carCount: Int?
    let positionM: Double
    let speedMps: Double
    let simulationTimeSeconds: Double
    let passengerLoadFactor: Double?
    let modeID: String?
    let calendarID: String?
    let initialDelayMinutes: Int?
}
