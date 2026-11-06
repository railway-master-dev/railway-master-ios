import Foundation

/// JSON value used for app-owned mode and subsystem state. Stable core fields remain typed;
/// this extension point lets newer app modules preserve their state without coupling packages.
public indirect enum SaveJSONValue: Codable, Equatable, Sendable {
    case null
    case bool(Bool)
    case integer(Int64)
    case number(Double)
    case string(String)
    case array([SaveJSONValue])
    case object([String: SaveJSONValue])

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { self = .null; return }
        if let value = try? container.decode(Bool.self) { self = .bool(value); return }
        if let value = try? container.decode(Int64.self) { self = .integer(value); return }
        if let value = try? container.decode(Double.self) { self = .number(value); return }
        if let value = try? container.decode(String.self) { self = .string(value); return }
        if let value = try? container.decode([SaveJSONValue].self) { self = .array(value); return }
        if let value = try? container.decode([String: SaveJSONValue].self) { self = .object(value); return }
        throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported JSON value")
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null: try container.encodeNil()
        case .bool(let value): try container.encode(value)
        case .integer(let value): try container.encode(value)
        case .number(let value):
            guard value.isFinite else {
                throw EncodingError.invalidValue(value, .init(codingPath: encoder.codingPath, debugDescription: "JSON numbers must be finite"))
            }
            try container.encode(value)
        case .string(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        }
    }
}

public struct SimulationClockSnapshot: Codable, Equatable, Sendable {
    public var simulationTimeSeconds: Double
    public var fixedTick: UInt64
    /// Fractional fixed-step time retained by the host accumulator; should normally be < 1/120 s.
    public var fixedStepRemainderSeconds: Double
    public var isPaused: Bool
    public var runPhaseID: String
    public var arrivalDwellSeconds: Double

    public init(simulationTimeSeconds: Double, fixedTick: UInt64, fixedStepRemainderSeconds: Double = 0, isPaused: Bool = false, runPhaseID: String = "running", arrivalDwellSeconds: Double = 0) {
        self.simulationTimeSeconds = simulationTimeSeconds
        self.fixedTick = fixedTick
        self.fixedStepRemainderSeconds = fixedStepRemainderSeconds
        self.isPaused = isPaused
        self.runPhaseID = runPhaseID
        self.arrivalDwellSeconds = arrivalDwellSeconds
    }
}

public struct RouteProgressSnapshot: Codable, Equatable, Sendable {
    public var routeID: String
    public var routeRevision: String
    public var variantID: String
    public var directionID: String
    public var distanceM: Double
    public var stopMarkerM: Double
    public var nextStopIndex: Int
    public var completedStopIDs: [String]

    public init(routeID: String, routeRevision: String, variantID: String = "", directionID: String = "", distanceM: Double, stopMarkerM: Double, nextStopIndex: Int = 0, completedStopIDs: [String] = []) {
        self.routeID = routeID
        self.routeRevision = routeRevision
        self.variantID = variantID
        self.directionID = directionID
        self.distanceM = distanceM
        self.stopMarkerM = stopMarkerM
        self.nextStopIndex = nextStopIndex
        self.completedStopIDs = completedStopIDs
    }
}

/// A position for a non-player train, traffic participant, or other moving vehicle.
public struct VehiclePositionSnapshot: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var routeID: String
    public var trackID: String
    public var vehicleProfileID: String
    public var directionID: String
    public var positionM: Double
    public var speedMps: Double
    public var lengthM: Double

    public init(id: String, routeID: String, trackID: String, vehicleProfileID: String = "", directionID: String = "forward", positionM: Double, speedMps: Double, lengthM: Double) {
        self.id = id
        self.routeID = routeID
        self.trackID = trackID
        self.vehicleProfileID = vehicleProfileID
        self.directionID = directionID
        self.positionM = positionM
        self.speedMps = speedMps
        self.lengthM = lengthM
    }
}

public struct PlayerVehicleSnapshot: Codable, Equatable, Sendable {
    public var vehicleID: String
    public var profileID: String
    public var soundProfileID: String
    public var carCount: Int
    public var directionID: String
    /// Optional per-car reference positions, when the host simulation exposes them.
    public var carPositionsM: [Double]

    public init(vehicleID: String = "PLAYER", profileID: String, soundProfileID: String = "", carCount: Int, directionID: String = "forward", carPositionsM: [Double] = []) {
        self.vehicleID = vehicleID
        self.profileID = profileID
        self.soundProfileID = soundProfileID
        self.carCount = carCount
        self.directionID = directionID
        self.carPositionsM = carPositionsM
    }
}

/// Dynamic engine state, including internal response/adhesion values needed for close resumption.
/// Values and model identifiers are fictional game state, not real vehicle measurements.
public struct PhysicsStateSnapshot: Codable, Equatable, Sendable {
    public var modelID: String
    public var modelVersion: Int
    /// Physics engine's own residual accumulator, distinct from the host simulation clock.
    public var physicsAccumulatorSeconds: Double
    public var positionM: Double
    public var speedMps: Double
    public var accelerationMps2: Double
    public var passengerLoadFactor: Double
    public var appliedBrakeFraction: Double
    public var commandedTractionForceN: Double
    public var antiSlipScale: Double
    public var brakePipePressureKPa: Double
    public var brakeCylinderPressureKPa: Double
    public var mainReservoirPressureKPa: Double
    public var lastTractionForceN: Double
    public var lastBrakingForceN: Double
    public var lastRegenerativeBrakeForceN: Double
    public var lastAirBrakeForceN: Double
    public var lastRollingResistanceN: Double
    public var lastGradientForceN: Double
    public var lastCurveResistanceN: Double
    public var wheelSlipActive: Bool
    public var brakeSlipActive: Bool

    public init(modelID: String, modelVersion: Int = 1, physicsAccumulatorSeconds: Double = 0, positionM: Double, speedMps: Double, accelerationMps2: Double = 0, passengerLoadFactor: Double = 0.7, appliedBrakeFraction: Double = 0, commandedTractionForceN: Double = 0, antiSlipScale: Double = 1, brakePipePressureKPa: Double = 500, brakeCylinderPressureKPa: Double = 0, mainReservoirPressureKPa: Double = 780, lastTractionForceN: Double = 0, lastBrakingForceN: Double = 0, lastRegenerativeBrakeForceN: Double = 0, lastAirBrakeForceN: Double = 0, lastRollingResistanceN: Double = 0, lastGradientForceN: Double = 0, lastCurveResistanceN: Double = 0, wheelSlipActive: Bool = false, brakeSlipActive: Bool = false) {
        self.modelID = modelID
        self.modelVersion = modelVersion
        self.physicsAccumulatorSeconds = physicsAccumulatorSeconds
        self.positionM = positionM
        self.speedMps = speedMps
        self.accelerationMps2 = accelerationMps2
        self.passengerLoadFactor = passengerLoadFactor
        self.appliedBrakeFraction = appliedBrakeFraction
        self.commandedTractionForceN = commandedTractionForceN
        self.antiSlipScale = antiSlipScale
        self.brakePipePressureKPa = brakePipePressureKPa
        self.brakeCylinderPressureKPa = brakeCylinderPressureKPa
        self.mainReservoirPressureKPa = mainReservoirPressureKPa
        self.lastTractionForceN = lastTractionForceN
        self.lastBrakingForceN = lastBrakingForceN
        self.lastRegenerativeBrakeForceN = lastRegenerativeBrakeForceN
        self.lastAirBrakeForceN = lastAirBrakeForceN
        self.lastRollingResistanceN = lastRollingResistanceN
        self.lastGradientForceN = lastGradientForceN
        self.lastCurveResistanceN = lastCurveResistanceN
        self.wheelSlipActive = wheelSlipActive
        self.brakeSlipActive = brakeSlipActive
    }
}

public struct ControlStateSnapshot: Codable, Equatable, Sendable {
    public var throttleNotch: Int
    public var brakeNotch: Int
    public var emergencyBrake: Bool

    public init(throttleNotch: Int = 0, brakeNotch: Int = 0, emergencyBrake: Bool = false) {
        self.throttleNotch = throttleNotch
        self.brakeNotch = brakeNotch
        self.emergencyBrake = emergencyBrake
    }
}

public struct ModeSessionSnapshot: Codable, Equatable, Sendable {
    public var modeID: String
    public var playStyleID: String
    public var statusID: String
    public var startedAtSimulationSeconds: Double
    public var hintCount: Int
    public var failureReasonID: String?
    /// JSON object/array from the host adapter; preserve each mode's complete progress and evaluation.
    public var progress: SaveJSONValue
    public var evaluation: SaveJSONValue?

    public init(modeID: String, playStyleID: String, statusID: String, startedAtSimulationSeconds: Double, hintCount: Int = 0, failureReasonID: String? = nil, progress: SaveJSONValue = .object([:]), evaluation: SaveJSONValue? = nil) {
        self.modeID = modeID
        self.playStyleID = playStyleID
        self.statusID = statusID
        self.startedAtSimulationSeconds = startedAtSimulationSeconds
        self.hintCount = hintCount
        self.failureReasonID = failureReasonID
        self.progress = progress
        self.evaluation = evaluation
    }
}

public struct TimetableStopSnapshot: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var stationID: String
    public var eventKindID: String
    public var positionM: Double
    public var scheduledArrivalSeconds: Double?
    public var scheduledDepartureSeconds: Double?
    public var actualArrivalSeconds: Double?
    public var actualDepartureSeconds: Double?
    public var arrivalDelaySeconds: Double?
    public var departureDelaySeconds: Double?

    public init(id: String, stationID: String, eventKindID: String = "stop", positionM: Double, scheduledArrivalSeconds: Double? = nil, scheduledDepartureSeconds: Double? = nil, actualArrivalSeconds: Double? = nil, actualDepartureSeconds: Double? = nil, arrivalDelaySeconds: Double? = nil, departureDelaySeconds: Double? = nil) {
        self.id = id
        self.stationID = stationID
        self.eventKindID = eventKindID
        self.positionM = positionM
        self.scheduledArrivalSeconds = scheduledArrivalSeconds
        self.scheduledDepartureSeconds = scheduledDepartureSeconds
        self.actualArrivalSeconds = actualArrivalSeconds
        self.actualDepartureSeconds = actualDepartureSeconds
        self.arrivalDelaySeconds = arrivalDelaySeconds
        self.departureDelaySeconds = departureDelaySeconds
    }
}

public struct TimetableStateSnapshot: Codable, Equatable, Sendable {
    public var calendarID: String
    public var daypartID: String
    public var serviceCategoryID: String
    public var directionID: String
    public var serviceID: String?
    public var initialDelayMinutes: Int
    public var departureDelaySeconds: Double
    public var settingsPendingRestart: Bool
    public var stops: [TimetableStopSnapshot]

    public init(calendarID: String, daypartID: String, serviceCategoryID: String, directionID: String, serviceID: String? = nil, initialDelayMinutes: Int = 0, departureDelaySeconds: Double = 0, settingsPendingRestart: Bool = false, stops: [TimetableStopSnapshot] = []) {
        self.calendarID = calendarID
        self.daypartID = daypartID
        self.serviceCategoryID = serviceCategoryID
        self.directionID = directionID
        self.serviceID = serviceID
        self.initialDelayMinutes = initialDelayMinutes
        self.departureDelaySeconds = departureDelaySeconds
        self.settingsPendingRestart = settingsPendingRestart
        self.stops = stops
    }
}

public struct EnvironmentStateSnapshot: Codable, Equatable, Sendable {
    public var weatherID: String
    public var precipitationID: String
    public var fogDensity: Double
    public var windSpeedMps: Double
    public var windDirectionDegrees: Double
    public var visibilityM: Double
    public var adhesionCoefficient: Double
    public var ambientIlluminanceLux: Double
    public var headlightIntensity: Double
    public var wiperStateID: String
    public var seasonID: String
    public var dayPeriodID: String
    public var timeOfDayHours: Double

    public init(weatherID: String, precipitationID: String, fogDensity: Double, windSpeedMps: Double, windDirectionDegrees: Double, visibilityM: Double, adhesionCoefficient: Double, ambientIlluminanceLux: Double, headlightIntensity: Double, wiperStateID: String, seasonID: String, dayPeriodID: String, timeOfDayHours: Double) {
        self.weatherID = weatherID
        self.precipitationID = precipitationID
        self.fogDensity = fogDensity
        self.windSpeedMps = windSpeedMps
        self.windDirectionDegrees = windDirectionDegrees
        self.visibilityM = visibilityM
        self.adhesionCoefficient = adhesionCoefficient
        self.ambientIlluminanceLux = ambientIlluminanceLux
        self.headlightIntensity = headlightIntensity
        self.wiperStateID = wiperStateID
        self.seasonID = seasonID
        self.dayPeriodID = dayPeriodID
        self.timeOfDayHours = timeOfDayHours
    }
}

public struct UserPreferencesSnapshot: Codable, Equatable, Sendable {
    public var cameraPresetID: String
    public var renderQualityID: String
    public var masterVolume: Double
    public var musicVolume: Double
    public var effectsVolume: Double
    public var voiceVolume: Double
    public var controlLayoutID: String
    public var hapticsEnabled: Bool

    public init(cameraPresetID: String = "cab", renderQualityID: String = "medium", masterVolume: Double = 1, musicVolume: Double = 1, effectsVolume: Double = 1, voiceVolume: Double = 1, controlLayoutID: String = "default", hapticsEnabled: Bool = true) {
        self.cameraPresetID = cameraPresetID
        self.renderQualityID = renderQualityID
        self.masterVolume = masterVolume
        self.musicVolume = musicVolume
        self.effectsVolume = effectsVolume
        self.voiceVolume = voiceVolume
        self.controlLayoutID = controlLayoutID
        self.hapticsEnabled = hapticsEnabled
    }
}

public struct SaveCompatibilitySnapshot: Codable, Equatable, Sendable {
    public var appBuildID: String
    public var routeCatalogRevision: String
    public var vehicleCatalogRevision: String
    public var subsystemStateRevision: Int

    public init(appBuildID: String = "", routeCatalogRevision: String = "", vehicleCatalogRevision: String = "", subsystemStateRevision: Int = 1) {
        self.appBuildID = appBuildID
        self.routeCatalogRevision = routeCatalogRevision
        self.vehicleCatalogRevision = vehicleCatalogRevision
        self.subsystemStateRevision = subsystemStateRevision
    }
}

public struct SimulationSaveState: Codable, Equatable, Sendable {
    public var saveName: String
    public var sessionID: UUID
    public var simulation: SimulationClockSnapshot
    public var route: RouteProgressSnapshot
    public var vehicle: PlayerVehicleSnapshot
    public var otherVehicles: [VehiclePositionSnapshot]
    public var controls: ControlStateSnapshot
    public var physics: PhysicsStateSnapshot
    public var mode: ModeSessionSnapshot?
    public var timetable: TimetableStateSnapshot
    public var environment: EnvironmentStateSnapshot
    public var preferences: UserPreferencesSnapshot
    /// Optional driving-log state (for example recorder metadata and retained samples).
    public var drivingLog: SaveJSONValue?
    /// Namespaced host states such as signalling, traffic, ATS, operations, maintenance, and scoring.
    public var subsystemStates: [String: SaveJSONValue]
    public var compatibility: SaveCompatibilitySnapshot

    public init(saveName: String, sessionID: UUID = UUID(), simulation: SimulationClockSnapshot, route: RouteProgressSnapshot, vehicle: PlayerVehicleSnapshot, otherVehicles: [VehiclePositionSnapshot] = [], controls: ControlStateSnapshot = ControlStateSnapshot(), physics: PhysicsStateSnapshot, mode: ModeSessionSnapshot? = nil, timetable: TimetableStateSnapshot, environment: EnvironmentStateSnapshot, preferences: UserPreferencesSnapshot = UserPreferencesSnapshot(), drivingLog: SaveJSONValue? = nil, subsystemStates: [String: SaveJSONValue] = [:], compatibility: SaveCompatibilitySnapshot = SaveCompatibilitySnapshot()) {
        self.saveName = saveName
        self.sessionID = sessionID
        self.simulation = simulation
        self.route = route
        self.vehicle = vehicle
        self.otherVehicles = otherVehicles
        self.controls = controls
        self.physics = physics
        self.mode = mode
        self.timetable = timetable
        self.environment = environment
        self.preferences = preferences
        self.drivingLog = drivingLog
        self.subsystemStates = subsystemStates
        self.compatibility = compatibility
    }

    /// Throws the first invalid field so corrupt or incompatible saves are never partially restored.
    public func validate() throws {
        try Self.require(!saveName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && saveName.count <= 120, "saveName")
        try Self.requireFinite(simulation.simulationTimeSeconds, range: 0...1_000_000_000, "simulation.simulationTimeSeconds")
        try Self.requireFinite(simulation.fixedStepRemainderSeconds, range: 0..<0.008333334, "simulation.fixedStepRemainderSeconds")
        try Self.requireFinite(simulation.arrivalDwellSeconds, range: 0...86_400, "simulation.arrivalDwellSeconds")
        try Self.requireIdentifier(simulation.runPhaseID, "simulation.runPhaseID")

        try Self.requireIdentifier(route.routeID, "route.routeID")
        try Self.require(route.routeRevision.count <= 128 && route.variantID.count <= 128 && route.directionID.count <= 128, "route identifiers")
        try Self.requireFinite(route.distanceM, range: 1...20_000_000, "route.distanceM")
        try Self.requireFinite(route.stopMarkerM, range: 0...route.distanceM, "route.stopMarkerM")
        try Self.require(route.nextStopIndex >= 0 && route.nextStopIndex <= 100_000, "route.nextStopIndex")
        try Self.require(route.completedStopIDs.count <= 100_000 && route.completedStopIDs.allSatisfy(Self.isValidIdentifier), "route.completedStopIDs")

        try Self.requireIdentifier(vehicle.vehicleID, "vehicle.vehicleID")
        try Self.requireIdentifier(vehicle.profileID, "vehicle.profileID")
        try Self.require(vehicle.soundProfileID.count <= 128 && Self.isValidIdentifier(vehicle.directionID), "vehicle identifiers")
        try Self.require((1...100).contains(vehicle.carCount), "vehicle.carCount")
        try Self.require(vehicle.carPositionsM.isEmpty || vehicle.carPositionsM.count == vehicle.carCount, "vehicle.carPositionsM.count")
        try Self.require(vehicle.carPositionsM.allSatisfy { $0.isFinite && abs($0) <= 20_000_000 }, "vehicle.carPositionsM")

        try Self.require(otherVehicles.count <= 10_000, "otherVehicles.count")
        var vehicleIDs = Set<String>()
        for (index, other) in otherVehicles.enumerated() {
            let prefix = "otherVehicles[\(index)]"
            try Self.requireIdentifier(other.id, "\(prefix).id")
            try Self.requireIdentifier(other.routeID, "\(prefix).routeID")
            try Self.require(other.trackID.count <= 128 && other.vehicleProfileID.count <= 128 && Self.isValidIdentifier(other.directionID), "\(prefix).identifiers")
            try Self.require(vehicleIDs.insert(other.id).inserted && other.id != vehicle.vehicleID, "\(prefix).id.duplicate")
            try Self.requireFinite(other.positionM, range: -20_000_000...20_000_000, "\(prefix).positionM")
            try Self.requireFinite(other.speedMps, range: 0...500, "\(prefix).speedMps")
            try Self.requireFinite(other.lengthM, range: 0...10_000, "\(prefix).lengthM")
        }

        try Self.require((0...5).contains(controls.throttleNotch), "controls.throttleNotch")
        try Self.require((0...7).contains(controls.brakeNotch), "controls.brakeNotch")
        try Self.requireIdentifier(physics.modelID, "physics.modelID")
        try Self.require(physics.modelVersion > 0 && physics.modelVersion <= 10_000, "physics.modelVersion")
        try Self.requireFinite(physics.physicsAccumulatorSeconds, range: 0..<0.008333334, "physics.physicsAccumulatorSeconds")
        // Preserve small terminal overshoots; the app may allow a train to pass the end marker before stopping.
        try Self.requireFinite(physics.positionM, range: 0...(route.distanceM + 1_000), "physics.positionM")
        try Self.requireFinite(physics.speedMps, range: 0...500, "physics.speedMps")
        try Self.requireFinite(physics.accelerationMps2, range: -100...100, "physics.accelerationMps2")
        try Self.requireFinite(physics.passengerLoadFactor, range: 0...2, "physics.passengerLoadFactor")
        try Self.requireFinite(physics.appliedBrakeFraction, range: 0...1, "physics.appliedBrakeFraction")
        try Self.requireFinite(physics.commandedTractionForceN, range: 0...1_000_000_000, "physics.commandedTractionForceN")
        try Self.requireFinite(physics.antiSlipScale, range: 0...1, "physics.antiSlipScale")
        for (field, value) in [
            ("brakePipePressureKPa", physics.brakePipePressureKPa),
            ("brakeCylinderPressureKPa", physics.brakeCylinderPressureKPa),
            ("mainReservoirPressureKPa", physics.mainReservoirPressureKPa)
        ] { try Self.requireFinite(value, range: 0...100_000, "physics.\(field)") }
        for (field, value) in [
            ("lastTractionForceN", physics.lastTractionForceN),
            ("lastBrakingForceN", physics.lastBrakingForceN),
            ("lastRegenerativeBrakeForceN", physics.lastRegenerativeBrakeForceN),
            ("lastAirBrakeForceN", physics.lastAirBrakeForceN),
            ("lastRollingResistanceN", physics.lastRollingResistanceN),
            ("lastGradientForceN", physics.lastGradientForceN),
            ("lastCurveResistanceN", physics.lastCurveResistanceN)
        ] { try Self.requireFinite(value, range: -1_000_000_000...1_000_000_000, "physics.\(field)") }

        if let mode {
            try Self.requireIdentifier(mode.modeID, "mode.modeID")
            try Self.requireIdentifier(mode.playStyleID, "mode.playStyleID")
            try Self.requireIdentifier(mode.statusID, "mode.statusID")
            try Self.requireFinite(mode.startedAtSimulationSeconds, range: 0...simulation.simulationTimeSeconds, "mode.startedAtSimulationSeconds")
            try Self.require(mode.hintCount >= 0 && mode.hintCount <= 1_000_000, "mode.hintCount")
            try Self.require(mode.failureReasonID.map(Self.isValidIdentifier) ?? true, "mode.failureReasonID")
            try Self.validateJSON(mode.progress, field: "mode.progress", depth: 0)
            if let evaluation = mode.evaluation { try Self.validateJSON(evaluation, field: "mode.evaluation", depth: 0) }
        }

        try Self.requireIdentifier(timetable.calendarID, "timetable.calendarID")
        try Self.requireIdentifier(timetable.daypartID, "timetable.daypartID")
        try Self.requireIdentifier(timetable.serviceCategoryID, "timetable.serviceCategoryID")
        try Self.requireIdentifier(timetable.directionID, "timetable.directionID")
        try Self.require(timetable.serviceID.map(Self.isValidIdentifier) ?? true, "timetable.serviceID")
        try Self.require((-10_080...10_080).contains(timetable.initialDelayMinutes), "timetable.initialDelayMinutes")
        try Self.requireFinite(timetable.departureDelaySeconds, range: -604_800...604_800, "timetable.departureDelaySeconds")
        try Self.require(timetable.stops.count <= 100_000, "timetable.stops.count")
        for (index, stop) in timetable.stops.enumerated() {
            let prefix = "timetable.stops[\(index)]"
            try Self.requireIdentifier(stop.id, "\(prefix).id")
            try Self.requireIdentifier(stop.stationID, "\(prefix).stationID")
            try Self.requireIdentifier(stop.eventKindID, "\(prefix).eventKindID")
            try Self.requireFinite(stop.positionM, range: 0...route.distanceM, "\(prefix).positionM")
            for (field, value) in [
                ("scheduledArrivalSeconds", stop.scheduledArrivalSeconds),
                ("scheduledDepartureSeconds", stop.scheduledDepartureSeconds),
                ("actualArrivalSeconds", stop.actualArrivalSeconds),
                ("actualDepartureSeconds", stop.actualDepartureSeconds)
            ] { try Self.requireOptionalFinite(value, range: 0...1_000_000_000, "\(prefix).\(field)") }
            try Self.requireOptionalFinite(stop.arrivalDelaySeconds, range: -604_800...604_800, "\(prefix).arrivalDelaySeconds")
            try Self.requireOptionalFinite(stop.departureDelaySeconds, range: -604_800...604_800, "\(prefix).departureDelaySeconds")
        }

        try Self.requireIdentifier(environment.weatherID, "environment.weatherID")
        try Self.requireIdentifier(environment.precipitationID, "environment.precipitationID")
        try Self.requireFinite(environment.fogDensity, range: 0...1, "environment.fogDensity")
        try Self.requireFinite(environment.windSpeedMps, range: 0...60, "environment.windSpeedMps")
        try Self.requireFinite(environment.windDirectionDegrees, range: 0..<360, "environment.windDirectionDegrees")
        try Self.requireFinite(environment.visibilityM, range: 1...100_000, "environment.visibilityM")
        try Self.requireFinite(environment.adhesionCoefficient, range: 0...1, "environment.adhesionCoefficient")
        try Self.requireFinite(environment.ambientIlluminanceLux, range: 0...120_000, "environment.ambientIlluminanceLux")
        try Self.requireFinite(environment.headlightIntensity, range: 0...1, "environment.headlightIntensity")
        for (field, value) in [("wiperStateID", environment.wiperStateID), ("seasonID", environment.seasonID), ("dayPeriodID", environment.dayPeriodID)] {
            try Self.requireIdentifier(value, "environment.\(field)")
        }
        try Self.requireFinite(environment.timeOfDayHours, range: 0..<24, "environment.timeOfDayHours")

        for (field, value) in [("cameraPresetID", preferences.cameraPresetID), ("renderQualityID", preferences.renderQualityID), ("controlLayoutID", preferences.controlLayoutID)] {
            try Self.requireIdentifier(value, "preferences.\(field)")
        }
        for (field, value) in [("masterVolume", preferences.masterVolume), ("musicVolume", preferences.musicVolume), ("effectsVolume", preferences.effectsVolume), ("voiceVolume", preferences.voiceVolume)] {
            try Self.requireFinite(value, range: 0...1, "preferences.\(field)")
        }

        try Self.require(compatibility.appBuildID.count <= 128 && compatibility.routeCatalogRevision.count <= 128 && compatibility.vehicleCatalogRevision.count <= 128, "compatibility identifiers")
        try Self.require(compatibility.subsystemStateRevision > 0 && compatibility.subsystemStateRevision <= 10_000, "compatibility.subsystemStateRevision")
        try Self.require(subsystemStates.count <= 256, "subsystemStates.count")
        for (key, value) in subsystemStates {
            try Self.requireIdentifier(key, "subsystemStates.key")
            try Self.validateJSON(value, field: "subsystemStates.\(key)", depth: 0)
        }
        if let drivingLog { try Self.validateJSON(drivingLog, field: "drivingLog", depth: 0) }
    }

    private static func isValidIdentifier(_ value: String) -> Bool {
        !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && value.count <= 256
    }

    private static func requireIdentifier(_ value: String, _ field: String) throws {
        try require(isValidIdentifier(value), field)
    }

    private static func require(_ condition: Bool, _ field: String) throws {
        guard condition else { throw SaveValidationError.invalidField(field) }
    }

    private static func requireFinite(_ value: Double, range: ClosedRange<Double>, _ field: String) throws {
        try require(value.isFinite && range.contains(value), field)
    }

    private static func requireFinite(_ value: Double, range: Range<Double>, _ field: String) throws {
        try require(value.isFinite && range.contains(value), field)
    }

    private static func requireOptionalFinite(_ value: Double?, range: ClosedRange<Double>, _ field: String) throws {
        if let value { try requireFinite(value, range: range, field) }
    }

    private static func validateJSON(_ value: SaveJSONValue, field: String, depth: Int) throws {
        try require(depth <= 64, "\(field).depth")
        switch value {
        case .null, .bool(_), .integer(_), .string(_): return
        case .number(let number): try require(number.isFinite, "\(field).number")
        case .array(let values):
            try require(values.count <= 100_000, "\(field).count")
            for (index, item) in values.enumerated() { try validateJSON(item, field: "\(field)[\(index)]", depth: depth + 1) }
        case .object(let values):
            try require(values.count <= 100_000, "\(field).count")
            for (key, item) in values {
                try require(key.count <= 256, "\(field).key")
                try validateJSON(item, field: "\(field).\(key)", depth: depth + 1)
            }
        }
    }
}

public enum SaveValidationError: Error, Equatable, Sendable, CustomStringConvertible {
    case invalidField(String)

    public var description: String {
        switch self {
        case .invalidField(let field): return "Invalid save field: \(field)"
        }
    }
}
