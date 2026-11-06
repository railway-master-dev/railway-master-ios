import Foundation

/// Codable representation of one per-car pneumatic brake state.
public struct TrainPhysicsCarBrakeSnapshot: Codable, Equatable, Sendable {
    public var carID: String
    public var brakePipePressureKPa: Double
    public var cylinderPressureKPa: Double
    public var temperatureC: Double
}

/// Codable track input used by the engine's next-tick continuation.
public struct TrainPhysicsTrackSnapshot: Codable, Equatable, Sendable {
    public var gradientPermille: Double
    public var curveRadiusM: Double?
    public var speedLimitKmh: Double
    public var tunnelResistanceMultiplier: Double
    public var supplyVoltageV: Double?

    public func trackCondition() -> TrackCondition {
        TrackCondition(
            gradientPermille: gradientPermille,
            curveRadiusM: curveRadiusM,
            speedLimitKmh: speedLimitKmh,
            tunnelResistanceMultiplier: tunnelResistanceMultiplier,
            supplyVoltageV: supplyVoltageV
        )
    }

    public init(_ value: TrackCondition) {
        gradientPermille = value.gradientPermille
        curveRadiusM = value.curveRadiusM
        speedLimitKmh = value.speedLimitKmh
        tunnelResistanceMultiplier = value.tunnelResistanceMultiplier
        supplyVoltageV = value.supplyVoltageV
    }
}

/// Codable version of optional simulation multipliers for deterministic continuation.
public struct TrainPhysicsModifiersSnapshot: Codable, Equatable, Sendable {
    public var tractionMultiplier: Double
    public var brakingMultiplier: Double
    public var speedCapKmh: Double?
    public var adhesionCoefficientOverride: Double?
    /// Older saves omit this and resume with no extra resistance.
    public var extraResistanceN: Double

    public func modifiers() -> PhysicsModifiers {
        PhysicsModifiers(
            tractionMultiplier: tractionMultiplier,
            brakingMultiplier: brakingMultiplier,
            speedCapKmh: speedCapKmh,
            adhesionCoefficientOverride: adhesionCoefficientOverride,
            extraResistanceN: extraResistanceN
        )
    }

    public init(_ value: PhysicsModifiers) {
        tractionMultiplier = value.tractionMultiplier
        brakingMultiplier = value.brakingMultiplier
        speedCapKmh = value.speedCapKmh
        adhesionCoefficientOverride = value.adhesionCoefficientOverride
        extraResistanceN = value.extraResistanceN
    }

    private enum CodingKeys: String, CodingKey {
        case tractionMultiplier, brakingMultiplier, speedCapKmh, adhesionCoefficientOverride, extraResistanceN
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        tractionMultiplier = try values.decode(Double.self, forKey: .tractionMultiplier)
        brakingMultiplier = try values.decode(Double.self, forKey: .brakingMultiplier)
        speedCapKmh = try values.decodeIfPresent(Double.self, forKey: .speedCapKmh)
        adhesionCoefficientOverride = try values.decodeIfPresent(Double.self, forKey: .adhesionCoefficientOverride)
        extraResistanceN = try values.decodeIfPresent(Double.self, forKey: .extraResistanceN) ?? 0
    }

    public func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(tractionMultiplier, forKey: .tractionMultiplier)
        try values.encode(brakingMultiplier, forKey: .brakingMultiplier)
        try values.encodeIfPresent(speedCapKmh, forKey: .speedCapKmh)
        try values.encodeIfPresent(adhesionCoefficientOverride, forKey: .adhesionCoefficientOverride)
        try values.encode(extraResistanceN, forKey: .extraResistanceN)
    }
}

/// Versioned engine-owned state needed to continue fixed-tick physics without silently
/// resetting per-car brakes, temperatures, adhesion memory, or fractional time.
public struct TrainPhysicsEngineStateSnapshot: Codable, Equatable, Sendable {
    public static let currentModelVersion = 1

    public var profileID: String
    public var modelVersion: Int
    public var positionM: Double
    public var speedMps: Double
    public var accelerationMps2: Double
    public var simulationTimeSeconds: Double
    public var passengerLoadFactor: Double
    public var accumulatorSeconds: Double
    public var carBrakes: [TrainPhysicsCarBrakeSnapshot]
    public var mainReservoirPressureKPa: Double
    public var tractionAdhesionScale: Double
    public var commandedTractionForceN: Double
    public var brakeAdhesionScale: Double
    public var wheelSlipActive: Bool
    public var brakeSlipActive: Bool
    public var lastTrack: TrainPhysicsTrackSnapshot
    public var lastSurface: RailSurface
    public var lastModifiers: TrainPhysicsModifiersSnapshot
    public var lastTractionForceN: Double
    public var lastTotalBrakeForceN: Double
    public var lastRegenerativeBrakeForceN: Double
    public var lastFrictionBrakeForceN: Double
    public var lastRollingResistanceN: Double
    public var lastGradientForceN: Double
    public var lastCurveResistanceN: Double
    public var lastLineCurrentA: Double
    public var lastLineVoltageV: Double
    public var lastCarFrictionForcesN: [Double]
}

public enum TrainPhysicsStateRestoreError: Error, Equatable, LocalizedError, Sendable {
    case profileMismatch
    case unsupportedVersion(Int)
    case invalidState(String)

    public var errorDescription: String? {
        switch self {
        case .profileMismatch: "Saved physics state belongs to a different train profile."
        case .unsupportedVersion(let version): "Unsupported train-physics snapshot version: \(version)."
        case .invalidState(let detail): "Invalid train-physics snapshot: \(detail)"
        }
    }
}
