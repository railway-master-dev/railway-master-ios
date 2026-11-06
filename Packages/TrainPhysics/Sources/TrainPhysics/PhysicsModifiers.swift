import Foundation

/// Optional gameplay modifiers that replace the legacy engine's event and maintenance multipliers.
/// Invalid values are ignored or clamped at the simulation boundary.
public struct PhysicsModifiers: Equatable, Sendable {
    public var tractionMultiplier: Double
    public var brakingMultiplier: Double
    public var speedCapKmh: Double?
    public var adhesionCoefficientOverride: Double?
    /// PLACEHOLDER newtons added to resistance this tick. Not a wind-tunnel load.
    public var extraResistanceN: Double

    public init(
        tractionMultiplier: Double = 1,
        brakingMultiplier: Double = 1,
        speedCapKmh: Double? = nil,
        adhesionCoefficientOverride: Double? = nil,
        extraResistanceN: Double = 0
    ) {
        self.tractionMultiplier = tractionMultiplier
        self.brakingMultiplier = brakingMultiplier
        self.speedCapKmh = speedCapKmh
        self.adhesionCoefficientOverride = adhesionCoefficientOverride
        self.extraResistanceN = extraResistanceN
    }

    func sanitized() -> PhysicsModifiers {
        PhysicsModifiers(
            tractionMultiplier: tractionMultiplier.isFinite ? min(max(tractionMultiplier, 0), 2) : 1,
            brakingMultiplier: brakingMultiplier.isFinite ? min(max(brakingMultiplier, 0), 2) : 1,
            speedCapKmh: speedCapKmh.flatMap { $0.isFinite ? min(max($0, 0), 500) : nil },
            adhesionCoefficientOverride: adhesionCoefficientOverride.flatMap { $0.isFinite ? min(max($0, 0.01), 1) : nil },
            extraResistanceN: extraResistanceN.isFinite ? min(max(extraResistanceN, 0), 40_000) : 0
        )
    }
}
