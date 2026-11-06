import Foundation

/// Coarse precipitation category. It deliberately does not imply visibility, adhesion, or wiper state.
public enum PrecipitationKind: String, Codable, CaseIterable, Hashable, Sendable {
    case none
    case rain
    case snow
}

public enum Season: String, Codable, CaseIterable, Hashable, Sendable {
    case spring
    case summer
    case autumn
    case winter
}

public enum DayPeriod: String, Codable, CaseIterable, Hashable, Sendable {
    case dawn
    case day
    case dusk
    case night
}

public enum WiperState: String, Codable, CaseIterable, Hashable, Sendable {
    case off
    case intermittent
    case low
    case high
}

/// One deterministic, wholly fictional snapshot for a game simulation.
/// All continuous values are sanitized at initialization; no clock, random source, or network is read.
public struct EnvironmentConditions: Codable, Equatable, Sendable {
    public let precipitation: PrecipitationKind
    /// Fog density, dimensionless, 0...1 (0 = none, 1 = dense fog).
    public let fogDensity: Double
    /// Wind speed, metres per second, 0...60.
    public let windSpeedMps: Double
    /// Wind direction in degrees clockwise from north, normalized to [0, 360).
    public let windDirectionDegrees: Double
    /// Visibility range, metres, 1...100_000. A game-world value, not a measured observation.
    public let visibilityM: Double
    /// Wheel/rail adhesion coefficient μ, dimensionless, 0...1.
    public let adhesionCoefficient: Double
    /// Ambient illuminance, lux, 0...120_000. Virtual rendering input, not a photometric measurement.
    public let ambientIlluminanceLux: Double
    /// Headlight output command, normalized 0...1; not electrical power or measured luminous flux.
    public let headlightIntensity: Double
    /// Wiper mode is a discrete state independent of precipitation.
    public let wiperState: WiperState
    public let season: Season
    public let dayPeriod: DayPeriod

    public init(
        precipitation: PrecipitationKind,
        fogDensity: Double,
        windSpeedMps: Double,
        windDirectionDegrees: Double,
        visibilityM: Double,
        adhesionCoefficient: Double,
        ambientIlluminanceLux: Double,
        headlightIntensity: Double,
        wiperState: WiperState,
        season: Season,
        dayPeriod: DayPeriod
    ) {
        self.precipitation = precipitation
        self.fogDensity = Self.clamp(fogDensity, to: 0...1, fallback: 0)
        self.windSpeedMps = Self.clamp(windSpeedMps, to: 0...60, fallback: 0)
        self.windDirectionDegrees = Self.normalizedDegrees(windDirectionDegrees)
        self.visibilityM = Self.clamp(visibilityM, to: 1...100_000, fallback: 100_000)
        self.adhesionCoefficient = Self.clamp(adhesionCoefficient, to: 0...1, fallback: 0.27)
        self.ambientIlluminanceLux = Self.clamp(ambientIlluminanceLux, to: 0...120_000, fallback: 0)
        self.headlightIntensity = Self.clamp(headlightIntensity, to: 0...1, fallback: 0)
        self.wiperState = wiperState
        self.season = season
        self.dayPeriod = dayPeriod
    }

    /// Named game fixtures are stable constants, not forecasts or claims about real weather.
    public static let clearDay = EnvironmentConditions(
        precipitation: .none, fogDensity: 0, windSpeedMps: 2, windDirectionDegrees: 180,
        visibilityM: 30_000, adhesionCoefficient: 0.27, ambientIlluminanceLux: 20_000,
        headlightIntensity: 0, wiperState: .off, season: .spring, dayPeriod: .day
    )

    public static let rainyDusk = EnvironmentConditions(
        precipitation: .rain, fogDensity: 0.12, windSpeedMps: 5, windDirectionDegrees: 225,
        visibilityM: 4_000, adhesionCoefficient: 0.17, ambientIlluminanceLux: 300,
        headlightIntensity: 0.65, wiperState: .low, season: .autumn, dayPeriod: .dusk
    )

    public static let foggyNight = EnvironmentConditions(
        precipitation: .none, fogDensity: 0.85, windSpeedMps: 1, windDirectionDegrees: 0,
        visibilityM: 250, adhesionCoefficient: 0.24, ambientIlluminanceLux: 2,
        headlightIntensity: 1, wiperState: .off, season: .winter, dayPeriod: .night
    )

    public static let snowyWinter = EnvironmentConditions(
        precipitation: .snow, fogDensity: 0.2, windSpeedMps: 8, windDirectionDegrees: 315,
        visibilityM: 1_200, adhesionCoefficient: 0.10, ambientIlluminanceLux: 800,
        headlightIntensity: 0.8, wiperState: .intermittent, season: .winter, dayPeriod: .day
    )

    /// Lossy projection for the existing three-case WeatherCondition API.
    /// Fog/wind/time/season/light/wiper are omitted, and the target type's fixed adhesion value wins.
    public var legacyWeatherCaseName: String {
        switch precipitation {
        case .none: return "dry"
        case .rain: return "rain"
        case .snow: return "snow"
        }
    }

    private static func clamp(_ value: Double, to range: ClosedRange<Double>, fallback: Double) -> Double {
        guard value.isFinite else { return fallback }
        return min(max(value, range.lowerBound), range.upperBound)
    }

    private static func normalizedDegrees(_ value: Double) -> Double {
        guard value.isFinite else { return 0 }
        let remainder = value.truncatingRemainder(dividingBy: 360)
        return remainder >= 0 ? remainder : remainder + 360
    }
}
