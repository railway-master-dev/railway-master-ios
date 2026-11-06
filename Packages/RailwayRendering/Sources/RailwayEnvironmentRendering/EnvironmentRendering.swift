import Foundation
import RailwayRenderingCore

/// A normalized, renderer-facing description of the surrounding environment.
///
/// Values are relative scales and multipliers rather than physical light units.
/// An app adapter may use them for its background, lights, materials, fog, and
/// optional precipitation effects without coupling this package to a renderer.
public struct EnvironmentRenderState: Sendable, Equatable {
    /// Normalized local hour in `[0, 24)`. Non-finite input resolves to noon.
    public let localHour: Double
    /// Daylight blend in `[0, 1]`, including smooth dawn and dusk transitions.
    public let dayNightBlend: Double
    /// Relative ambient illumination scale; always positive and bounded.
    public let ambientLightScale: Double
    /// Relative directional/sun illumination scale; zero at night.
    public let sunLightScale: Double
    /// RGB multipliers describing a subtle warm/cool environmental tint.
    public let warmCoolTint: RenderVector3
    /// Conservative fog contribution in `[0, 0.4]`; higher values mean more fog.
    public let fogStrength: Double
    /// Effective visibility in meters, bounded to a useful renderer-facing range.
    public let visibilityMeters: Double
    /// Normalized visual rain effect strength in `[0, 1]`.
    public let rainVisualIntensity: Double
    /// Normalized visual snow effect strength in `[0, 1]`.
    public let snowVisualIntensity: Double
    /// Material-blend hint for wet track and ground in `[0, 1]`; cosmetic only.
    public let surfaceWetnessBlend: Double
    /// Material-blend hint for snow-covered surfaces in `[0, 1]`; cosmetic only.
    public let snowSurfaceCoverageBlend: Double

    /// Creates a normalized environment state.
    ///
    /// This initializer clamps renderer-facing values to the same conservative
    /// ranges used by the resolver, so manually constructed states stay bounded.
    public init(
        localHour: Double,
        dayNightBlend: Double,
        ambientLightScale: Double,
        sunLightScale: Double,
        warmCoolTint: RenderVector3,
        fogStrength: Double,
        visibilityMeters: Double,
        rainVisualIntensity: Double,
        snowVisualIntensity: Double,
        surfaceWetnessBlend: Double = 0,
        snowSurfaceCoverageBlend: Double = 0
    ) {
        self.localHour = Self.finiteClamp(localHour, lower: 0, upper: 24, fallback: 12)
        self.dayNightBlend = Self.finiteClamp(dayNightBlend, lower: 0, upper: 1, fallback: 0)
        self.ambientLightScale = Self.finiteClamp(ambientLightScale, lower: 0.15, upper: 1.2, fallback: 0.5)
        self.sunLightScale = Self.finiteClamp(sunLightScale, lower: 0, upper: 1, fallback: 0)
        self.warmCoolTint = RenderVector3(
            x: Self.finiteClamp(warmCoolTint.x, lower: 0.7, upper: 1.2, fallback: 1),
            y: Self.finiteClamp(warmCoolTint.y, lower: 0.7, upper: 1.2, fallback: 1),
            z: Self.finiteClamp(warmCoolTint.z, lower: 0.7, upper: 1.2, fallback: 1)
        )
        self.fogStrength = Self.finiteClamp(fogStrength, lower: 0, upper: 0.4, fallback: 0)
        self.visibilityMeters = Self.finiteClamp(visibilityMeters, lower: 100, upper: 20_000, fallback: 20_000)
        self.rainVisualIntensity = Self.finiteClamp(rainVisualIntensity, lower: 0, upper: 1, fallback: 0)
        self.snowVisualIntensity = Self.finiteClamp(snowVisualIntensity, lower: 0, upper: 1, fallback: 0)
        self.surfaceWetnessBlend = Self.finiteClamp(surfaceWetnessBlend, lower: 0, upper: 1, fallback: 0)
        self.snowSurfaceCoverageBlend = Self.finiteClamp(snowSurfaceCoverageBlend, lower: 0, upper: 1, fallback: 0)
    }

    private static func finiteClamp(_ value: Double, lower: Double, upper: Double, fallback: Double) -> Double {
        guard value.isFinite else { return fallback }
        return min(max(value, lower), upper)
    }
}

/// Resolves simulation-facing time and weather into conservative visual controls.
public enum EnvironmentRenderResolver {
    private static let minimumVisibilityMeters = 100.0
    private static let maximumVisibilityMeters = 20_000.0

    /// Converts an environment input into bounded scales suitable for a scene adapter.
    ///
    /// Time wraps into `[0, 24)`, with non-finite values treated as noon. Invalid,
    /// non-positive, or absent visibility uses a weather-specific default. Explicit
    /// visibility is clamped to a practical range. Fog is deliberately capped so
    /// the environment does not unnecessarily obscure the track. Precipitation is
    /// represented only as an abstract intensity and material blend hint; this
    /// method creates no effects or physically accumulated surface state.
    public static func resolve(_ input: EnvironmentInput) -> EnvironmentRenderState {
        let hour = normalizedHour(input.timeOfDayHours)
        let daylight = daylightBlend(at: hour)
        let precipitation = normalizedUnit(input.precipitationIntensity)
        let visibility = resolvedVisibility(input.visibilityMeters, weather: input.weather)

        let weatherLightFactor: Double
        let weatherFogLimit: Double
        switch input.weather {
        case .dry:
            weatherLightFactor = 1
            weatherFogLimit = 0.08
        case .rain:
            weatherLightFactor = 0.88
            weatherFogLimit = 0.16
        case .snow:
            weatherLightFactor = 0.92
            weatherFogLimit = 0.14
        case .fog:
            weatherLightFactor = 0.82
            weatherFogLimit = 0.4
        }

        let visibilityLoss = 1 - visibility / maximumVisibilityMeters
        let fogStrength = min(weatherFogLimit, max(0, visibilityLoss) * 0.4)
        let ambient = min(0.95, max(0.24, 0.28 + daylight * 0.62))
        let sun = daylight * weatherLightFactor * (1 - min(0.35, fogStrength * 0.5))
        let tint = tintFor(hour: hour, daylight: daylight, weather: input.weather)

        let rainIntensity: Double
        let snowIntensity: Double
        switch input.weather {
        case .rain:
            rainIntensity = precipitation
            snowIntensity = 0
        case .snow:
            rainIntensity = 0
            snowIntensity = precipitation
        case .dry, .fog:
            rainIntensity = 0
            snowIntensity = 0
        }

        return EnvironmentRenderState(
            localHour: hour,
            dayNightBlend: daylight,
            ambientLightScale: ambient,
            sunLightScale: sun,
            warmCoolTint: tint,
            fogStrength: fogStrength,
            visibilityMeters: visibility,
            rainVisualIntensity: rainIntensity,
            snowVisualIntensity: snowIntensity,
            surfaceWetnessBlend: rainIntensity,
            snowSurfaceCoverageBlend: snowIntensity
        )
    }

    private static func normalizedHour(_ hour: Double) -> Double {
        guard hour.isFinite else { return 12 }
        let wrapped = hour.truncatingRemainder(dividingBy: 24)
        return wrapped < 0 ? wrapped + 24 : wrapped
    }

    private static func normalizedUnit(_ value: Double) -> Double {
        guard value.isFinite else { return 0 }
        return min(max(value, 0), 1)
    }

    private static func resolvedVisibility(_ supplied: Double?, weather: RenderingWeather) -> Double {
        let defaultVisibility: Double
        switch weather {
        case .dry: defaultVisibility = 20_000
        case .rain: defaultVisibility = 8_000
        case .snow: defaultVisibility = 7_000
        case .fog: defaultVisibility = 1_500
        }
        guard let supplied, supplied.isFinite, supplied > 0 else { return defaultVisibility }
        return min(max(supplied, minimumVisibilityMeters), maximumVisibilityMeters)
    }

    /// Full daylight spans 07:00–17:00; dawn and dusk each transition smoothly
    /// over two hours, avoiding abrupt changes around the horizon.
    private static func daylightBlend(at hour: Double) -> Double {
        if hour < 5 || hour >= 19 { return 0 }
        if hour < 7 { return smoothStep((hour - 5) / 2) }
        if hour < 17 { return 1 }
        return 1 - smoothStep((hour - 17) / 2)
    }

    private static func smoothStep(_ value: Double) -> Double {
        let t = min(max(value, 0), 1)
        return t * t * (3 - 2 * t)
    }

    private static func tintFor(hour: Double, daylight: Double, weather: RenderingWeather) -> RenderVector3 {
        // Blend from a restrained cool night tint toward neutral daytime light.
        let dawnDuskWarmth = max(
            smoothStep((hour - 5) / 2) - smoothStep((hour - 7) / 2),
            smoothStep((hour - 17) / 2) - smoothStep((hour - 19) / 2)
        )
        let night = 1 - daylight
        let weatherCool: Double
        switch weather {
        case .dry: weatherCool = 0
        case .rain: weatherCool = 0.025
        case .snow: weatherCool = 0.015
        case .fog: weatherCool = 0.02
        }
        let warm = min(0.1, dawnDuskWarmth * 0.08)
        let cool = min(0.08, night * 0.055 + weatherCool)
        return RenderVector3(
            x: 1 + warm - cool * 0.25,
            y: 1 - warm * 0.45,
            z: 1 - warm * 0.9 + cool
        )
    }
}
