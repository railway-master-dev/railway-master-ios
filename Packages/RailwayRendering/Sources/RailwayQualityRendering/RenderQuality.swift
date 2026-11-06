import Foundation
import RailwayRenderingCore

/// User-selectable starting points for scene rendering quality.
///
/// These profiles describe visual budgets, not frame-rate or device-temperature guarantees.
public enum RenderQualityProfile: String, CaseIterable, Sendable {
    /// Highest starting-point budgets for scenery, shadows, fog, and precipitation.
    case ultra
    /// High visual detail with somewhat lower scene budgets than ``ultra``.
    case high
    /// The default profile, designed to retain clear track and route visibility on iPhone.
    case balanced
    /// Lowest starting-point scene budgets, while retaining the same track-visibility priority.
    case performance
}

/// Scene-facing limits and feature toggles resolved from a quality profile.
///
/// Values are platform-neutral starting points only. Profile budgets must be validated and tuned
/// with real-device profiling in the adopting renderer; they do not promise a target frame rate,
/// acceptable heat, or equivalent performance across devices.
public struct RenderQualitySettings: Sendable, Equatable {
    /// Maximum scene visibility distance in meters. Track and route legibility should take priority
    /// over decorative content when adapting this budget.
    public let visibleDistanceMeters: Double
    /// Maximum number of foliage instances the scene adapter should consider visible.
    public let foliageInstanceLimit: Int
    /// Maximum number of non-foliage scenery instances the scene adapter should consider visible.
    public let sceneryInstanceLimit: Int
    /// Relative shadow-map/detail scale in the inclusive range 0...1.
    public let shadowScale: Double
    /// Maximum number of shadow-casting lights to use.
    public let shadowLightCount: Int
    /// Whether the scene may render volumetric fog effects.
    public let volumetricFogEnabled: Bool
    /// Maximum visual precipitation particle count; this is a rendering budget, not weather intensity.
    public let precipitationParticleBudget: Int

    /// Creates settings with values normalized to safe, platform-neutral ranges.
    ///
    /// This initializer does not imply that the supplied values are performant on any particular device.
    public init(
        visibleDistanceMeters: Double,
        foliageInstanceLimit: Int,
        sceneryInstanceLimit: Int,
        shadowScale: Double,
        shadowLightCount: Int,
        volumetricFogEnabled: Bool,
        precipitationParticleBudget: Int
    ) {
        self.visibleDistanceMeters = visibleDistanceMeters.isFinite ? max(0, visibleDistanceMeters) : 0
        self.foliageInstanceLimit = max(0, foliageInstanceLimit)
        self.sceneryInstanceLimit = max(0, sceneryInstanceLimit)
        self.shadowScale = shadowScale.isFinite ? min(1, max(0, shadowScale)) : 0
        self.shadowLightCount = max(0, shadowLightCount)
        self.volumetricFogEnabled = volumetricFogEnabled
        self.precipitationParticleBudget = max(0, precipitationParticleBudget)
    }
}

/// Resolves profile settings while applying a thermal-condition downgrade ceiling.
public enum RenderQualityResolver {
    /// Returns the settings for the requested profile, capped by the device's current thermal condition.
    ///
    /// Thermal ceilings are deliberately conservative design rules, not assurances about device heat
    /// or rendering performance. Adopting applications should measure and tune them on real hardware.
    public static func resolve(
        profile: RenderQualityProfile,
        thermalCondition: DeviceThermalCondition
    ) -> RenderQualitySettings {
        let effectiveProfile = min(profile, thermalCeiling(for: thermalCondition))
        return settings(for: effectiveProfile)
    }

    private static func thermalCeiling(for condition: DeviceThermalCondition) -> RenderQualityProfile {
        switch condition {
        case .nominal:
            return .ultra
        case .fair:
            return .high
        case .serious:
            return .balanced
        case .critical:
            return .performance
        }
    }

    private static func settings(for profile: RenderQualityProfile) -> RenderQualitySettings {
        switch profile {
        case .ultra:
            return RenderQualitySettings(
                visibleDistanceMeters: 2_000,
                foliageInstanceLimit: 6_000,
                sceneryInstanceLimit: 3_000,
                shadowScale: 1.0,
                shadowLightCount: 4,
                volumetricFogEnabled: true,
                precipitationParticleBudget: 2_400
            )
        case .high:
            return RenderQualitySettings(
                visibleDistanceMeters: 1_700,
                foliageInstanceLimit: 4_500,
                sceneryInstanceLimit: 2_400,
                shadowScale: 0.8,
                shadowLightCount: 3,
                volumetricFogEnabled: true,
                precipitationParticleBudget: 1_600
            )
        case .balanced:
            return RenderQualitySettings(
                visibleDistanceMeters: 1_400,
                foliageInstanceLimit: 2_800,
                sceneryInstanceLimit: 1_600,
                shadowScale: 0.6,
                shadowLightCount: 2,
                volumetricFogEnabled: true,
                precipitationParticleBudget: 900
            )
        case .performance:
            return RenderQualitySettings(
                visibleDistanceMeters: 1_100,
                foliageInstanceLimit: 1_400,
                sceneryInstanceLimit: 900,
                shadowScale: 0.4,
                shadowLightCount: 1,
                volumetricFogEnabled: false,
                precipitationParticleBudget: 450
            )
        }
    }
}

extension RenderQualityProfile: Comparable {
    public static func < (lhs: RenderQualityProfile, rhs: RenderQualityProfile) -> Bool {
        lhs.rank < rhs.rank
    }

    private var rank: Int {
        switch self {
        case .performance: return 0
        case .balanced: return 1
        case .high: return 2
        case .ultra: return 3
        }
    }
}

/// Holds the user's selected profile and current thermal condition and exposes resolved settings.
///
/// The controller is a lightweight value type; the application is responsible for supplying updated
/// thermal conditions and applying the resulting settings to its scene adapter.
public struct RenderQualityController: Sendable, Equatable {
    /// The profile selected by the user before thermal limits are applied.
    public var selectedProfile: RenderQualityProfile
    /// The latest thermal condition supplied by the host application.
    public var thermalCondition: DeviceThermalCondition

    /// Creates a controller using balanced quality and nominal thermal condition by default.
    public init(
        selectedProfile: RenderQualityProfile = .balanced,
        thermalCondition: DeviceThermalCondition = .nominal
    ) {
        self.selectedProfile = selectedProfile
        self.thermalCondition = thermalCondition
    }

    /// Current effective settings after applying the thermal downgrade ceiling.
    public var settings: RenderQualitySettings {
        RenderQualityResolver.resolve(profile: selectedProfile, thermalCondition: thermalCondition)
    }
}
