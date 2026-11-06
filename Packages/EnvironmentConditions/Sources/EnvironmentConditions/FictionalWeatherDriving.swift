import Foundation

/// Driving weather the host can select. These are game categories, not meteorological observations.
public enum FictionalDrivingWeather: String, Codable, CaseIterable, Equatable, Sendable {
    case dry
    case rain
    case heavyRain
    case snow
    case fog
}

/// Adhesion, visibility, fog, and wind resistance produced for one fixed physics tick.
/// Every number is a PLACEHOLDER game value, not a measured adhesion table or a drag coefficient.
public struct FictionalWeatherDrivingEffect: Equatable, Sendable {
    public let adhesionCoefficient: Double
    public let visibilityM: Double
    public let fogDensity: Double
    public let precipitation: PrecipitationKind
    /// Added to rolling resistance. `coefficient * windSpeed²`, capped. Not aerodynamic data.
    public let extraResistanceN: Double
    public let dataStatus: String

    public init(adhesionCoefficient: Double, visibilityM: Double, fogDensity: Double, precipitation: PrecipitationKind, extraResistanceN: Double) {
        self.adhesionCoefficient = adhesionCoefficient
        self.visibilityM = visibilityM
        self.fogDensity = fogDensity
        self.precipitation = precipitation
        self.extraResistanceN = extraResistanceN
        self.dataStatus = "PLACEHOLDER"
    }
}

public enum FictionalWeatherDrivingCoupling {
    public static let dryAdhesion = 0.27
    public static let rainAdhesion = 0.17
    public static let heavyRainAdhesion = 0.12
    public static let snowAdhesion = 0.10
    /// PLACEHOLDER N / (m/s)². Not a vehicle drag area or a measured wind load.
    public static let windResistanceCoefficientNPerSquareMeterPerSecond = 18.0
    public static let maximumExtraResistanceN = 25_000.0

    public static func resolve(weather: FictionalDrivingWeather, windSpeedMps: Double) -> FictionalWeatherDrivingEffect {
        let wind = windSpeedMps.isFinite ? min(max(windSpeedMps, 0), 60) : 0
        let rawResistance = windResistanceCoefficientNPerSquareMeterPerSecond * wind * wind
        let extraResistance = min(max(rawResistance.isFinite ? rawResistance : 0, 0), maximumExtraResistanceN)
        switch weather {
        case .dry:
            return FictionalWeatherDrivingEffect(
                adhesionCoefficient: dryAdhesion, visibilityM: 20_000, fogDensity: 0,
                precipitation: .none, extraResistanceN: extraResistance
            )
        case .rain:
            return FictionalWeatherDrivingEffect(
                adhesionCoefficient: rainAdhesion, visibilityM: 4_000, fogDensity: 0.16,
                precipitation: .rain, extraResistanceN: extraResistance
            )
        case .heavyRain:
            return FictionalWeatherDrivingEffect(
                adhesionCoefficient: heavyRainAdhesion, visibilityM: 700, fogDensity: 0.46,
                precipitation: .rain, extraResistanceN: extraResistance
            )
        case .snow:
            return FictionalWeatherDrivingEffect(
                adhesionCoefficient: snowAdhesion, visibilityM: 1_200, fogDensity: 0.24,
                precipitation: .snow, extraResistanceN: extraResistance
            )
        case .fog:
            return FictionalWeatherDrivingEffect(
                adhesionCoefficient: dryAdhesion, visibilityM: 180, fogDensity: 0.85,
                precipitation: .none, extraResistanceN: extraResistance
            )
        }
    }

    /// Suggested game wind for a weather preset. The live wind slider can replace this.
    public static func presetWindSpeedMps(for weather: FictionalDrivingWeather) -> Double {
        switch weather {
        case .dry: return 2
        case .rain: return 6
        case .heavyRain: return 12
        case .snow: return 8
        case .fog: return 1
        }
    }
}
