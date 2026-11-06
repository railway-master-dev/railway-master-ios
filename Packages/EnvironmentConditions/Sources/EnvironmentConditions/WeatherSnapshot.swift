import Foundation

/// 降水の種類。レール面の状態とは独立しているため、雨と落ち葉などを同時に表現できます。
public enum WeatherPrecipitationKind: String, Codable, CaseIterable, Hashable, Sendable {
    case none
    case rain
    case snow
    case sleet
    case freezingRain
}

/// レール面の基礎状態。付着物は `RailSurfaceContaminant` として別に指定します。
public enum RailSurfaceCondition: String, Codable, CaseIterable, Hashable, Sendable {
    case dry
    case damp
    case wet
    case standingWater
    case looseSnow
    case compactedSnow
    case ice
}

/// レール面に残る付着物。基礎状態と組み合わせて指定できます。
public enum RailSurfaceContaminant: String, Codable, CaseIterable, Hashable, Sendable {
    case leafResidue
    case mud
    case sand
    case oil
    case other
}

/// 降水の観測・シナリオ状態。量が不明な場合は nil にします。
public struct PrecipitationState: Codable, Hashable, Sendable {
    public let kind: WeatherPrecipitationKind
    /// 降水強度（mm/h）。雪を含む水量換算は上流側のデータ仕様に従います。
    public let rateMillimetersPerHour: Float?
    /// 地表の積雪深（m）。降水中の雪だけでなく、残雪の状態も表現できます。
    public let snowCoverDepthMeters: Float?

    public init(
        kind: WeatherPrecipitationKind,
        rateMillimetersPerHour: Float? = nil,
        snowCoverDepthMeters: Float? = nil
    ) {
        self.kind = kind
        self.rateMillimetersPerHour = WeatherValue.nonnegativeOrNil(rateMillimetersPerHour)
        self.snowCoverDepthMeters = WeatherValue.nonnegativeOrNil(snowCoverDepthMeters)
    }

    private enum CodingKeys: String, CodingKey {
        case kind
        case rateMillimetersPerHour
        case snowCoverDepthMeters
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            kind: try values.decode(WeatherPrecipitationKind.self, forKey: .kind),
            rateMillimetersPerHour: try values.decodeIfPresent(Float.self, forKey: .rateMillimetersPerHour),
            snowCoverDepthMeters: try values.decodeIfPresent(Float.self, forKey: .snowCoverDepthMeters)
        )
    }
}

/// レール面状態とゲーム内の物理倍率。
public struct RailSurfaceState: Codable, Hashable, Sendable {
    public let condition: RailSurfaceCondition
    public let contaminants: Set<RailSurfaceContaminant>

    /// ゲーム物理用の表面摩擦倍率。0...1、1はシナリオの乾燥基準。
    /// 実車の摩擦係数や実測法則ではなく、ゲーム用に調整する仮想パラメーターです。
    public let surfaceFrictionMultiplier: Float

    /// ゲーム物理用の車輪・レール粘着倍率。0...1、1はシナリオの乾燥基準。
    /// 実車の粘着係数や実測法則ではなく、ゲーム用に調整する仮想パラメーターです。
    public let railAdhesionMultiplier: Float

    public init(
        condition: RailSurfaceCondition,
        contaminants: Set<RailSurfaceContaminant> = [],
        surfaceFrictionMultiplier: Float,
        railAdhesionMultiplier: Float
    ) {
        self.condition = condition
        self.contaminants = contaminants
        self.surfaceFrictionMultiplier = WeatherValue.unitInterval(surfaceFrictionMultiplier)
        self.railAdhesionMultiplier = WeatherValue.unitInterval(railAdhesionMultiplier)
    }

    private enum CodingKeys: String, CodingKey {
        case condition
        case contaminants
        case surfaceFrictionMultiplier
        case railAdhesionMultiplier
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            condition: try values.decode(RailSurfaceCondition.self, forKey: .condition),
            contaminants: try values.decodeIfPresent(Set<RailSurfaceContaminant>.self, forKey: .contaminants) ?? [],
            surfaceFrictionMultiplier: try values.decode(Float.self, forKey: .surfaceFrictionMultiplier),
            railAdhesionMultiplier: try values.decode(Float.self, forKey: .railAdhesionMultiplier)
        )
    }
}

/// 風の状態。方位は「北から時計回り」の度数で、風が吹いてくる向きを示します。
public struct WindState: Codable, Hashable, Sendable {
    public let speedMetersPerSecond: Float
    public let gustSpeedMetersPerSecond: Float?
    public let directionDegreesFromNorth: Float?

    public init(
        speedMetersPerSecond: Float,
        gustSpeedMetersPerSecond: Float? = nil,
        directionDegreesFromNorth: Float? = nil
    ) {
        self.speedMetersPerSecond = WeatherValue.nonnegative(speedMetersPerSecond)
        self.gustSpeedMetersPerSecond = WeatherValue.nonnegativeOrNil(gustSpeedMetersPerSecond)
        self.directionDegreesFromNorth = WeatherValue.wrapDegrees(directionDegreesFromNorth)
    }

    private enum CodingKeys: String, CodingKey {
        case speedMetersPerSecond
        case gustSpeedMetersPerSecond
        case directionDegreesFromNorth
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            speedMetersPerSecond: try values.decode(Float.self, forKey: .speedMetersPerSecond),
            gustSpeedMetersPerSecond: try values.decodeIfPresent(Float.self, forKey: .gustSpeedMetersPerSecond),
            directionDegreesFromNorth: try values.decodeIfPresent(Float.self, forKey: .directionDegreesFromNorth)
        )
    }
}

/// 物理・描画・音響が同じ更新tickで参照する不変の天候スナップショット。
/// 気象の分類軸は排他的な三択ではなく、降水・レール面・付着物・風・視程・時刻を独立させています。
public struct WeatherSnapshot: Codable, Hashable, Sendable {
    /// シミュレーション開始からの経過秒。巻き戻しを許容します。
    public let simulationTimeSeconds: TimeInterval
    /// シナリオ現地時刻の0時からの秒数。0...86,399に正規化されます。
    public let timeOfDaySeconds: TimeInterval
    public let precipitation: PrecipitationState
    public let railSurface: RailSurfaceState
    public let wind: WindState
    /// 視程（m）。不明な場合は nil。
    public let visibilityMeters: Float?
    /// 気温（℃）。不明な場合は nil。
    public let airTemperatureCelsius: Float?

    public init(
        simulationTimeSeconds: TimeInterval,
        timeOfDaySeconds: TimeInterval,
        precipitation: PrecipitationState,
        railSurface: RailSurfaceState,
        wind: WindState,
        visibilityMeters: Float? = nil,
        airTemperatureCelsius: Float? = nil
    ) {
        self.simulationTimeSeconds = WeatherValue.finiteOrZero(simulationTimeSeconds)
        self.timeOfDaySeconds = WeatherValue.wrapDaySeconds(timeOfDaySeconds)
        self.precipitation = precipitation
        self.railSurface = railSurface
        self.wind = wind
        self.visibilityMeters = WeatherValue.clampedNonnegativeOrNil(visibilityMeters)
        self.airTemperatureCelsius = WeatherValue.finiteOrNil(airTemperatureCelsius)
    }

    private enum CodingKeys: String, CodingKey {
        case simulationTimeSeconds
        case timeOfDaySeconds
        case precipitation
        case railSurface
        case wind
        case visibilityMeters
        case airTemperatureCelsius
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            simulationTimeSeconds: try values.decode(TimeInterval.self, forKey: .simulationTimeSeconds),
            timeOfDaySeconds: try values.decode(TimeInterval.self, forKey: .timeOfDaySeconds),
            precipitation: try values.decode(PrecipitationState.self, forKey: .precipitation),
            railSurface: try values.decode(RailSurfaceState.self, forKey: .railSurface),
            wind: try values.decode(WindState.self, forKey: .wind),
            visibilityMeters: try values.decodeIfPresent(Float.self, forKey: .visibilityMeters),
            airTemperatureCelsius: try values.decodeIfPresent(Float.self, forKey: .airTemperatureCelsius)
        )
    }
}

private enum WeatherValue {
    static func finiteOrZero(_ value: Double) -> Double {
        value.isFinite ? value : 0
    }

    static func wrapDaySeconds(_ value: Double) -> Double {
        guard value.isFinite else { return 0 }
        let remainder = value.truncatingRemainder(dividingBy: 86_400)
        return remainder >= 0 ? remainder : remainder + 86_400
    }

    static func nonnegative(_ value: Float) -> Float {
        value.isFinite ? max(0, value) : 0
    }

    static func nonnegativeOrNil(_ value: Float?) -> Float? {
        guard let value, value.isFinite, value >= 0 else { return nil }
        return value
    }

    static func clampedNonnegativeOrNil(_ value: Float?) -> Float? {
        guard let value, value.isFinite else { return nil }
        return max(0, value)
    }

    static func finiteOrNil(_ value: Float?) -> Float? {
        guard let value, value.isFinite else { return nil }
        return value
    }

    static func unitInterval(_ value: Float) -> Float {
        value.isFinite ? min(1, max(0, value)) : 0
    }

    static func wrapDegrees(_ value: Float?) -> Float? {
        guard let value, value.isFinite else { return nil }
        let remainder = value.truncatingRemainder(dividingBy: 360)
        return remainder >= 0 ? remainder : remainder + 360
    }
}
