import Foundation
import EnvironmentConditions

/// 運転台から入力される操作。ノッチ数値はこの架空通勤車プロフィールの設定です。
public struct TrainControls: Equatable, Sendable {
    public var throttleNotch: Int
    public var brakeNotch: Int
    public var emergencyBrake: Bool
    /// Resistance formation only. Reversing the master asks the physics tick for holding brake.
    public var masterReversed: Bool

    public init(throttleNotch: Int = 0, brakeNotch: Int = 0, emergencyBrake: Bool = false, masterReversed: Bool = false) {
        self.throttleNotch = min(max(throttleNotch, 0), 5)
        self.brakeNotch = min(max(brakeNotch, 0), 7)
        self.emergencyBrake = emergencyBrake
        self.masterReversed = masterReversed
    }
}

public struct TractionPoint: Codable, Sendable {
    public let speedKmh: Double
    public let forceN: Double

    public init(speedKmh: Double, forceN: Double) {
        self.speedKmh = speedKmh
        self.forceN = forceN
    }
}

/// JSONから読み込む車両設定。数値は全て架空のゲーム内設定で、実車諸元ではありません。
public struct TrainParameters: Codable, Sendable {
    public let displayName: String
    public let carCount: Int
    public let tareMassPerCarKg: Double
    public let passengerCapacityPerCar: Int
    public let rotationalInertiaFactor: Double
    public let drivenMassFraction: Double
    public let brakedMassFraction: Double
    public let maximumServiceBrakeDecelerationMps2: Double
    public let maximumEmergencyBrakeDecelerationMps2: Double
    public let maximumSpeedKmh: Double
    public let davisA: Double
    public let davisBPerMps: Double
    public let davisC: Double
    public let curveResistanceCoefficient: Double
    public let maximumTractionForceN: Double
    public let maximumTractionPowerW: Double
    public let tractionJerkMps3: Double
    public let serviceBrakeApplySeconds: Double
    public let emergencyBrakeApplySeconds: Double
    public let brakeReleaseSeconds: Double
    public let regenerativeBrakeShare: Double
    public let regenerativeFadeSpeedKmh: Double
    public let tractionNotchFractions: [Double]
    public let tractionCurve: [TractionPoint]

    /// 架空3D車両モデルの1両19.5 mと共通の、閉そく・表示用編成長 [m]。
    /// 実車寸法ではなく、車両モデルとゲーム内占有計算を揃えるための規約値。
    public var estimatedTrainLengthM: Double { Double(carCount) * 19.5 }

    /// Rejects malformed decoded configuration before it reaches the physics loop.
    public var isValidForSimulation: Bool {
        guard !displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              (1...16).contains(carCount),
              tareMassPerCarKg.isFinite, tareMassPerCarKg > 0,
              (0...600).contains(passengerCapacityPerCar),
              rotationalInertiaFactor.isFinite, rotationalInertiaFactor >= 1,
              drivenMassFraction.isFinite, (0...1).contains(drivenMassFraction),
              brakedMassFraction.isFinite, (0...1).contains(brakedMassFraction),
              maximumServiceBrakeDecelerationMps2.isFinite, maximumServiceBrakeDecelerationMps2 > 0,
              maximumEmergencyBrakeDecelerationMps2.isFinite, maximumEmergencyBrakeDecelerationMps2 >= maximumServiceBrakeDecelerationMps2,
              maximumSpeedKmh.isFinite, maximumSpeedKmh > 0,
              [davisA, davisBPerMps, davisC, curveResistanceCoefficient].allSatisfy({ $0.isFinite && $0 >= 0 }),
              maximumTractionForceN.isFinite, maximumTractionForceN > 0,
              maximumTractionPowerW.isFinite, maximumTractionPowerW > 0,
              tractionJerkMps3.isFinite, tractionJerkMps3 > 0,
              serviceBrakeApplySeconds.isFinite, serviceBrakeApplySeconds > 0,
              emergencyBrakeApplySeconds.isFinite, emergencyBrakeApplySeconds > 0,
              brakeReleaseSeconds.isFinite, brakeReleaseSeconds > 0,
              regenerativeBrakeShare.isFinite, (0...1).contains(regenerativeBrakeShare),
              regenerativeFadeSpeedKmh.isFinite, regenerativeFadeSpeedKmh > 0,
              tractionNotchFractions.count >= 2,
              tractionCurve.count >= 2 else { return false }
        guard tractionNotchFractions.allSatisfy({ $0.isFinite && (0...1).contains($0) }),
              tractionNotchFractions.first == 0,
              zip(tractionNotchFractions, tractionNotchFractions.dropFirst()).allSatisfy({ pair in pair.0 <= pair.1 }),
              tractionCurve.allSatisfy({ $0.speedKmh.isFinite && $0.speedKmh >= 0 && $0.forceN.isFinite && $0.forceN >= 0 }),
              zip(tractionCurve, tractionCurve.dropFirst()).allSatisfy({ pair in pair.0.speedKmh < pair.1.speedKmh }) else { return false }
        return true
    }

    public init(
        displayName: String,
        carCount: Int,
        tareMassPerCarKg: Double,
        passengerCapacityPerCar: Int,
        rotationalInertiaFactor: Double,
        drivenMassFraction: Double,
        brakedMassFraction: Double,
        maximumServiceBrakeDecelerationMps2: Double,
        maximumEmergencyBrakeDecelerationMps2: Double,
        maximumSpeedKmh: Double,
        davisA: Double,
        davisBPerMps: Double,
        davisC: Double,
        curveResistanceCoefficient: Double,
        maximumTractionForceN: Double,
        maximumTractionPowerW: Double,
        tractionJerkMps3: Double,
        serviceBrakeApplySeconds: Double,
        emergencyBrakeApplySeconds: Double,
        brakeReleaseSeconds: Double,
        regenerativeBrakeShare: Double,
        regenerativeFadeSpeedKmh: Double,
        tractionNotchFractions: [Double],
        tractionCurve: [TractionPoint]
    ) {
        self.displayName = displayName
        self.carCount = max(carCount, 1)
        self.tareMassPerCarKg = max(tareMassPerCarKg, 1)
        self.passengerCapacityPerCar = max(passengerCapacityPerCar, 0)
        self.rotationalInertiaFactor = max(rotationalInertiaFactor, 1)
        self.drivenMassFraction = min(max(drivenMassFraction, 0), 1)
        self.brakedMassFraction = min(max(brakedMassFraction, 0), 1)
        self.maximumServiceBrakeDecelerationMps2 = max(maximumServiceBrakeDecelerationMps2, 0)
        self.maximumEmergencyBrakeDecelerationMps2 = max(maximumEmergencyBrakeDecelerationMps2, 0)
        self.maximumSpeedKmh = max(maximumSpeedKmh, 0)
        self.davisA = max(davisA, 0)
        self.davisBPerMps = max(davisBPerMps, 0)
        self.davisC = max(davisC, 0)
        self.curveResistanceCoefficient = max(curveResistanceCoefficient, 0)
        self.maximumTractionForceN = max(maximumTractionForceN, 0)
        self.maximumTractionPowerW = max(maximumTractionPowerW, 0)
        self.tractionJerkMps3 = max(tractionJerkMps3, 0.01)
        self.serviceBrakeApplySeconds = max(serviceBrakeApplySeconds, 0.05)
        self.emergencyBrakeApplySeconds = max(emergencyBrakeApplySeconds, 0.05)
        self.brakeReleaseSeconds = max(brakeReleaseSeconds, 0.05)
        self.regenerativeBrakeShare = min(max(regenerativeBrakeShare, 0), 1)
        self.regenerativeFadeSpeedKmh = max(regenerativeFadeSpeedKmh, 0.1)
        self.tractionNotchFractions = tractionNotchFractions.isEmpty ? [0, 1] : tractionNotchFractions
        self.tractionCurve = tractionCurve.sorted { $0.speedKmh < $1.speedKmh }
    }

    public func totalMassKg(passengerLoadFactor: Double) -> Double {
        let passengerCount = Double(carCount * passengerCapacityPerCar) * min(max(passengerLoadFactor, 0), 2)
        return Double(carCount) * tareMassPerCarKg + passengerCount * 60.0
    }

    public func effectiveMassKg(passengerLoadFactor: Double) -> Double {
        totalMassKg(passengerLoadFactor: passengerLoadFactor) * rotationalInertiaFactor
    }

    public func tractionFraction(for notch: Int) -> Double {
        guard !tractionNotchFractions.isEmpty else { return notch > 0 ? 1 : 0 }
        let index = min(max(notch, 0), tractionNotchFractions.count - 1)
        return min(max(tractionNotchFractions[index], 0), 1)
    }

    /// Speed-dependent tractive effort interpolates the motor curve and obeys its power ceiling.
    public func availableTractionForce(atSpeedKmh speedKmh: Double) -> Double {
        guard maximumSpeedKmh > 0, speedKmh < maximumSpeedKmh,
              let first = tractionCurve.first, let last = tractionCurve.last else { return 0 }

        let curveForce: Double
        if speedKmh <= first.speedKmh {
            curveForce = first.forceN
        } else if speedKmh >= last.speedKmh {
            curveForce = last.forceN
        } else {
            var interpolated = last.forceN
            for index in 0..<(tractionCurve.count - 1) {
                let lower = tractionCurve[index]
                let upper = tractionCurve[index + 1]
                if speedKmh <= upper.speedKmh {
                    let span = max(upper.speedKmh - lower.speedKmh, 0.0001)
                    let fraction = (speedKmh - lower.speedKmh) / span
                    interpolated = lower.forceN + (upper.forceN - lower.forceN) * fraction
                    break
                }
            }
            curveForce = interpolated
        }

        // At standstill the power limit is undefined; use the low-speed force curve.
        let speedMps = speedKmh / 3.6
        let powerLimitedForce = speedMps > 0.5 ? maximumTractionPowerW / speedMps : maximumTractionForceN
        return min(min(max(curveForce, 0), maximumTractionForceN), powerLimitedForce)
    }

    /// 架空デモ用の予備設定。通常はアプリ同梱JSONから同じ車両を読み込みます。
    public static let fictionalPrototype = TrainParameters(
        displayName: "架空通勤車 T-01",
        carCount: 6,
        tareMassPerCarKg: 30_000,
        passengerCapacityPerCar: 110,
        rotationalInertiaFactor: 1.08,
        drivenMassFraction: 0.62,
        brakedMassFraction: 1.0,
        maximumServiceBrakeDecelerationMps2: 3.5 / 3.6,
        maximumEmergencyBrakeDecelerationMps2: 4.5 / 3.6,
        maximumSpeedKmh: 100,
        davisA: 1.3,
        davisBPerMps: 0.03,
        davisC: 2.2,
        curveResistanceCoefficient: 600,
        maximumTractionForceN: 210_000,
        maximumTractionPowerW: 2_400_000,
        tractionJerkMps3: 0.65,
        serviceBrakeApplySeconds: 1.1,
        emergencyBrakeApplySeconds: 0.35,
        brakeReleaseSeconds: 1.2,
        regenerativeBrakeShare: 0.58,
        regenerativeFadeSpeedKmh: 12,
        tractionNotchFractions: [0, 0.18, 0.36, 0.62, 0.82, 1.0],
        tractionCurve: [
            TractionPoint(speedKmh: 0, forceN: 210_000),
            TractionPoint(speedKmh: 10, forceN: 210_000),
            TractionPoint(speedKmh: 30, forceN: 195_000),
            TractionPoint(speedKmh: 50, forceN: 160_000),
            TractionPoint(speedKmh: 75, forceN: 120_000),
            TractionPoint(speedKmh: 100, forceN: 75_000),
            TractionPoint(speedKmh: 120, forceN: 0)
        ]
    )
}

public struct RouteSection: Codable, Equatable, Sendable {
    public let startM: Double
    public let endM: Double
    public let gradientPermille: Double
    public let curveRadiusM: Double?
    /// Signed curve direction: +1 right, -1 left. Nil means unspecified.
    public let curveDirection: Int?
    /// Positive cant in millimetres. Values remain fictional until sourced.
    public let cantMm: Double?
    /// Complete curve-run bounds, shared by each intersecting 250 m physics section.
    public let curveTransition: RouteCurveTransition?
    public let speedLimitKmh: Double
    public let tunnelResistanceMultiplier: Double

    public init(
        startM: Double,
        endM: Double,
        gradientPermille: Double = 0,
        curveRadiusM: Double? = nil,
        curveDirection: Int? = nil,
        cantMm: Double? = nil,
        curveTransition: RouteCurveTransition? = nil,
        speedLimitKmh: Double,
        tunnelResistanceMultiplier: Double = 1
    ) {
        self.startM = startM
        self.endM = endM
        self.gradientPermille = gradientPermille
        self.curveRadiusM = curveRadiusM
        self.curveDirection = curveDirection == 1 || curveDirection == -1 ? curveDirection : nil
        self.cantMm = cantMm?.isFinite == true ? cantMm : nil
        self.curveTransition = curveTransition
        self.speedLimitKmh = speedLimitKmh
        self.tunnelResistanceMultiplier = max(tunnelResistanceMultiplier, 1)
    }
}

/// Linear-curvature entry and exit lengths around a constant-radius arc. All values are chainage metres.
public struct RouteCurveTransition: Codable, Equatable, Sendable {
    public let startM: Double
    public let circularStartM: Double
    public let circularEndM: Double
    public let endM: Double

    public init(startM: Double, circularStartM: Double, circularEndM: Double, endM: Double) {
        self.startM = startM
        self.circularStartM = circularStartM
        self.circularEndM = circularEndM
        self.endM = endM
    }

    public var isValid: Bool {
        [startM, circularStartM, circularEndM, endM].allSatisfy(\.isFinite)
            && startM < circularStartM && circularStartM <= circularEndM && circularEndM < endM
    }

    /// Curvature and cant rise linearly through the transitions, as a simplified game-only clothoid profile.
    public func fraction(at chainageM: Double) -> Double {
        guard isValid, chainageM.isFinite, chainageM > startM, chainageM < endM else { return 0 }
        if chainageM < circularStartM {
            return min(max((chainageM - startM) / (circularStartM - startM), 0), 1)
        }
        if chainageM <= circularEndM { return 1 }
        return min(max((endM - chainageM) / (endM - circularEndM), 0), 1)
    }

    public func reversed(over totalLengthM: Double) -> RouteCurveTransition {
        RouteCurveTransition(
            startM: totalLengthM - endM,
            circularStartM: totalLengthM - circularEndM,
            circularEndM: totalLengthM - circularStartM,
            endM: totalLengthM - startM
        )
    }
}

public struct RouteCondition: Sendable {
    public let gradientPermille: Double
    public let curveRadiusM: Double?
    public let curveDirection: Int?
    public let cantMm: Double?
    public let speedLimitKmh: Double
    public let tunnelResistanceMultiplier: Double
}

/// 架空の1駅間。勾配・曲線・速度制限・トンネル抵抗をJSONの区間データで定義します。
public struct RailwayRouteProfile: Codable, Equatable, Sendable {
    public let lineName: String
    public let departureStation: String
    public let arrivalStation: String
    public let distanceM: Double
    public let stopMarkerM: Double
    public let trackGaugeMm: Double
    public let sections: [RouteSection]
    public let dataStatus: RouteDataStatus
    public let dataProvenance: [RouteDataProvenance]

    public init(lineName: String, departureStation: String, arrivalStation: String, distanceM: Double, stopMarkerM: Double, sections: [RouteSection], trackGaugeMm: Double = 1_067, dataStatus: RouteDataStatus = .placeholder, dataProvenance: [RouteDataProvenance] = []) {
        self.lineName = lineName
        self.departureStation = departureStation
        self.arrivalStation = arrivalStation
        self.distanceM = max(distanceM, 1)
        self.stopMarkerM = min(max(stopMarkerM, 0), max(distanceM, 1))
        self.trackGaugeMm = trackGaugeMm.isFinite && trackGaugeMm > 0 ? trackGaugeMm : 1_067
        self.sections = sections.sorted { $0.startM < $1.startM }
        self.dataStatus = dataStatus
        self.dataProvenance = dataProvenance
    }

    public func condition(at positionM: Double) -> RouteCondition {
        let section = sections.first(where: { positionM >= $0.startM && positionM < $0.endM }) ?? sections.last
        let fraction = section?.curveTransition?.fraction(at: positionM) ?? (section?.curveRadiusM == nil ? 0 : 1)
        let effectiveRadius = section?.curveRadiusM.flatMap { fraction > 1e-9 ? $0 / fraction : nil }
        return RouteCondition(
            gradientPermille: section?.gradientPermille ?? 0,
            curveRadiusM: effectiveRadius,
            curveDirection: fraction > 1e-9 ? section?.curveDirection : nil,
            cantMm: section?.cantMm.map { $0 * fraction },
            speedLimitKmh: section?.speedLimitKmh ?? 40,
            tunnelResistanceMultiplier: section?.tunnelResistanceMultiplier ?? 1
        )
    }

    /// Full-length fictional baseline used only if the canonical JSON route cannot be loaded.
    public static let fictionalMainlineFallback = RailwayRouteProfile(
        lineName: "東央本線（架空PLACEHOLDER）",
        departureStation: "海袋",
        arrivalStation: "鴨河",
        distanceM: 60_000,
        stopMarkerM: 60_000,
        sections: [
            RouteSection(startM: 0, endM: 20_000, gradientPermille: 2, curveRadiusM: 850, speedLimitKmh: 90),
            RouteSection(startM: 20_000, endM: 40_000, gradientPermille: -3, curveRadiusM: 680, speedLimitKmh: 120),
            RouteSection(startM: 40_000, endM: 60_000, gradientPermille: 1, curveRadiusM: 920, speedLimitKmh: 100)
        ],
        trackGaugeMm: 1_067
    )
}

public enum WeatherCondition: String, CaseIterable, Codable, Hashable, Sendable {
    case dry = "乾燥"
    case rain = "雨"
    case heavyRain = "強い雨"
    case snow = "雪"
    case fog = "霧"

    /// Game adhesion copied from `FictionalWeatherDrivingCoupling`. Not a measured μ.
    public var adhesionCoefficient: Double {
        FictionalWeatherDrivingCoupling.resolve(weather: fictionalDrivingWeather, windSpeedMps: 0).adhesionCoefficient
    }

    public var fictionalDrivingWeather: FictionalDrivingWeather {
        switch self {
        case .dry: return .dry
        case .rain: return .rain
        case .heavyRain: return .heavyRain
        case .snow: return .snow
        case .fog: return .fog
        }
    }

    public var symbolName: String {
        switch self {
        case .dry: return "sun.max.fill"
        case .rain: return "cloud.rain.fill"
        case .heavyRain: return "cloud.heavyrain.fill"
        case .snow: return "snowflake"
        case .fog: return "cloud.fog.fill"
        }
    }
}

public struct TrainTelemetry: Equatable, Sendable {
    public let positionM: Double
    public let speedMps: Double
    public let accelerationMps2: Double
    public let tractionForceN: Double
    public let brakingForceN: Double
    public let regenerativeBrakeForceN: Double
    public let airBrakeForceN: Double
    public let rollingResistanceN: Double
    public let gradientForceN: Double
    public let curveResistanceN: Double
    public let appliedBrakeFraction: Double
    public let brakePipePressureKPa: Double
    public let brakeCylinderPressureKPa: Double
    public let mainReservoirPressureKPa: Double
    public let effectiveMassKg: Double
    public let passengerLoadFactor: Double
    public let currentGradientPermille: Double
    public let currentCantMm: Double
    public let lateralAccelerationMps2: Double
    public let currentSpeedLimitKmh: Double
    public let distanceToStopMarkerM: Double
    public let predictedStoppingDistanceM: Double
    public let isStoppedAtMarker: Bool
    public let isWheelSlipActive: Bool
    public let isBrakeSlipActive: Bool
}

/// 120 Hz固定刻みの簡易縦運動モデル。実車訓練・安全判断用ではありません。
public struct TrainPhysicsEngine: Sendable {
    public static let fixedTimeStep: Double = 1.0 / 120.0

    public let parameters: TrainParameters
    public private(set) var positionM: Double = 0
    public private(set) var speedMps: Double = 0
    public private(set) var accelerationMps2: Double = 0
    public private(set) var appliedBrakeFraction: Double = 0
    public private(set) var passengerLoadFactor: Double
    private var accumulator: Double = 0
    private var commandedTractionForceN: Double = 0
    private var antiSlipScale: Double = 1
    private var brakePipePressureKPa: Double = 500
    private var brakeCylinderPressureKPa: Double = 0
    private var mainReservoirPressureKPa: Double = 780
    private var lastTractionForceN: Double = 0
    private var lastBrakingForceN: Double = 0
    private var lastRegenerativeBrakeForceN: Double = 0
    private var lastAirBrakeForceN: Double = 0
    private var lastRollingResistanceN: Double = 0
    private var lastGradientForceN: Double = 0
    private var lastCurveResistanceN: Double = 0
    private var wheelSlipActive = false
    private var brakeSlipActive = false

    public init(parameters: TrainParameters = .fictionalPrototype, passengerLoadFactor: Double = 0.7) {
        self.parameters = parameters
        self.passengerLoadFactor = min(max(passengerLoadFactor, 0), 2)
    }

    public mutating func setPassengerLoadFactor(_ value: Double) {
        passengerLoadFactor = min(max(value, 0), 2)
    }

    /// Screenshot-tour support: place the train, stopped with the
    /// brakes released, at a given chainage. Not part of normal
    /// driving; used by the -RMTour capture mode.
    public mutating func placeAt(positionM newPositionM: Double) {
        reset()
        positionM = max(0, newPositionM)
    }

    public mutating func reset() {
        positionM = 0
        speedMps = 0
        accelerationMps2 = 0
        appliedBrakeFraction = 0
        accumulator = 0
        commandedTractionForceN = 0
        antiSlipScale = 1
        brakePipePressureKPa = 500
        brakeCylinderPressureKPa = 0
        mainReservoirPressureKPa = 780
        lastTractionForceN = 0
        lastBrakingForceN = 0
        lastRegenerativeBrakeForceN = 0
        lastAirBrakeForceN = 0
        lastRollingResistanceN = 0
        lastGradientForceN = 0
        lastCurveResistanceN = 0
        wheelSlipActive = false
        brakeSlipActive = false
    }

    /// Physics time remains fixed at 1/120 s regardless of render cadence.
    /// A long app suspension is intentionally bounded to 0.5 s; normal frames catch up without changing dt.
    public mutating func advance(realDelta: Double, controls: TrainControls, route: RailwayRouteProfile, weather: WeatherCondition) {
        guard realDelta.isFinite, realDelta > 0 else { return }
        accumulator += min(realDelta, 0.5)
        while accumulator + 1e-12 >= Self.fixedTimeStep {
            step(dt: Self.fixedTimeStep, controls: controls, route: route, weather: weather)
            accumulator -= Self.fixedTimeStep
        }
    }

    /// One semi-implicit Euler step. Forces are evaluated in newtons and positions in metres.
    /// Optional environment/event modifiers are fictional gameplay inputs; defaults preserve the legacy API.
    public mutating func step(
        dt: Double,
        controls: TrainControls,
        route: RailwayRouteProfile,
        weather: WeatherCondition,
        adhesionCoefficientOverride: Double? = nil,
        tractionMultiplier: Double = 1,
        brakingMultiplier: Double = 1,
        speedCapKmh: Double? = nil
    ) {
        guard dt.isFinite, dt > 0 else { return }

        let condition = route.condition(at: positionM)
        let physicalMass = parameters.totalMassKg(passengerLoadFactor: passengerLoadFactor)
        let effectiveMass = max(parameters.effectiveMassKg(passengerLoadFactor: passengerLoadFactor), 1)
        let gravity = 9.80665
        let speed = max(speedMps, 0)
        let speedKmh = speed * 3.6
        let gradientAngle = atan(condition.gradientPermille / 1_000.0)
        let normalForce = physicalMass * gravity * cos(gradientAngle)
        let speedAdhesionFactor = 1.0 / (1.0 + speedKmh / 2_000.0)
        let baseAdhesion = adhesionCoefficientOverride.map { min(max($0.isFinite ? $0 : weather.adhesionCoefficient, 0.01), 1) }
            ?? weather.adhesionCoefficient
        let adhesion = baseAdhesion * speedAdhesionFactor

        let throttleNotch = min(max(controls.throttleNotch, 0), parameters.tractionNotchFractions.count - 1)
        let brakeNotch = min(max(controls.brakeNotch, 0), 7)
        let emergency = controls.emergencyBrake
        let brakeCommand = emergency ? 1.0 : Double(brakeNotch) / 7.0

        // Apply and release responses have separate time constants. 4.6τ approximates 99% of a full command.
        let applying = brakeCommand > appliedBrakeFraction
        let responseSeconds = applying
            ? (emergency ? parameters.emergencyBrakeApplySeconds : parameters.serviceBrakeApplySeconds)
            : parameters.brakeReleaseSeconds
        let responseAlpha = 1.0 - exp(-4.6 * dt / max(responseSeconds, 0.05))
        appliedBrakeFraction += (brakeCommand - appliedBrakeFraction) * responseAlpha

        let eventTractionScale = min(max(tractionMultiplier.isFinite ? tractionMultiplier : 1, 0), 2)
        let eventBrakingScale = min(max(brakingMultiplier.isFinite ? brakingMultiplier : 1, 0), 2)
        let requestedTraction = (emergency || brakeNotch > 0)
            ? 0
            : parameters.availableTractionForce(atSpeedKmh: speedKmh) * parameters.tractionFraction(for: throttleNotch) * eventTractionScale
        let tractionAdhesionLimit = max(0, adhesion * normalForce * parameters.drivenMassFraction)
        wheelSlipActive = requestedTraction > tractionAdhesionLimit + 500
        if wheelSlipActive {
            antiSlipScale = max(0.52, antiSlipScale - dt * 1.5)
        } else {
            antiSlipScale = min(1, antiSlipScale + dt * 0.45)
        }
        let antiSlipTarget = requestedTraction * antiSlipScale
        let maximumForceChange = effectiveMass * parameters.tractionJerkMps3 * dt
        if emergency || brakeNotch > 0 {
            // A brake command cuts motor traction immediately; the jerk limiter governs power changes, not brake interlocks.
            commandedTractionForceN = 0
        } else {
            commandedTractionForceN = moveTowards(commandedTractionForceN, antiSlipTarget, maximumForceChange)
        }
        let traction = min(max(commandedTractionForceN, 0), tractionAdhesionLimit)

        let requestedBrakeDeceleration = (emergency
            ? parameters.maximumEmergencyBrakeDecelerationMps2
            : parameters.maximumServiceBrakeDecelerationMps2) * eventBrakingScale
        let requestedBraking = effectiveMass * requestedBrakeDeceleration * appliedBrakeFraction
        let brakeAdhesionLimit = max(0, adhesion * normalForce * parameters.brakedMassFraction)
        brakeSlipActive = requestedBraking > brakeAdhesionLimit + 500
        let braking = min(requestedBraking, brakeAdhesionLimit)
        let regenFade = min(max(speedKmh / parameters.regenerativeFadeSpeedKmh, 0), 1)
        let regenerative = min(braking, braking * parameters.regenerativeBrakeShare * regenFade)
        let airBrake = max(braking - regenerative, 0)

        // Davis resistance: m·g·(A+Bv)/1000 + C·v², with A/B/C in the fictional JSON profile.
        let davis = physicalMass * gravity * (parameters.davisA + parameters.davisBPerMps * speed) / 1_000
            + parameters.davisC * speed * speed
        let rolling = davis * condition.tunnelResistanceMultiplier
        let gradientForce = physicalMass * gravity * sin(gradientAngle)
        let curveResistance: Double
        if let radius = condition.curveRadiusM, radius > 0 {
            // Simplified railway curve resistance: (weight in kN) × (600/R) N per kN.
            curveResistance = physicalMass * gravity / 1_000 * parameters.curveResistanceCoefficient / max(radius, 1)
        } else {
            curveResistance = 0
        }

        let netForce = traction - braking - rolling - gradientForce - curveResistance
        let rawAcceleration = netForce / effectiveMass
        let unconstrainedSpeed = speed + rawAcceleration * dt
        let routeSpeedLimit = condition.speedLimitKmh.isFinite ? max(condition.speedLimitKmh, 0) : parameters.maximumSpeedKmh
        let externalSpeedLimit = speedCapKmh.map { $0.isFinite ? max($0, 0) : parameters.maximumSpeedKmh } ?? parameters.maximumSpeedKmh
        let configuredSpeedLimit = min(parameters.maximumSpeedKmh, routeSpeedLimit, externalSpeedLimit)
        let newSpeed = min(max(unconstrainedSpeed, 0), configuredSpeedLimit / 3.6)
        if (speed <= 0 && rawAcceleration < 0) || (speed >= configuredSpeedLimit / 3.6 && rawAcceleration > 0) {
            accelerationMps2 = 0
        } else {
            accelerationMps2 = (newSpeed - speed) / dt
        }
        speedMps = newSpeed
        positionM += newSpeed * dt

        // Train-pipe/cylinder/reservoir indications are simulated states, not decorative labels.
        let bpTarget = emergency ? 0 : 500 - 150 * appliedBrakeFraction
        brakePipePressureKPa = moveTowards(brakePipePressureKPa, bpTarget, 500 * dt / max(responseSeconds, 0.05))
        let bcTarget = 380 * appliedBrakeFraction
        brakeCylinderPressureKPa = moveTowards(brakeCylinderPressureKPa, bcTarget, 380 * dt / max(responseSeconds, 0.05))
        let mrTarget = 780 - min(brakeCylinderPressureKPa * 0.08, 55)
        mainReservoirPressureKPa = moveTowards(mainReservoirPressureKPa, mrTarget, 20 * dt)

        lastTractionForceN = traction
        lastBrakingForceN = braking
        lastRegenerativeBrakeForceN = regenerative
        lastAirBrakeForceN = airBrake
        lastRollingResistanceN = rolling
        lastGradientForceN = gradientForce
        lastCurveResistanceN = curveResistance
    }

    public func telemetry(route: RailwayRouteProfile, weather: WeatherCondition = .dry) -> TrainTelemetry {
        let condition = route.condition(at: positionM)
        let physicalMass = parameters.totalMassKg(passengerLoadFactor: passengerLoadFactor)
        let effectiveMass = parameters.effectiveMassKg(passengerLoadFactor: passengerLoadFactor)
        let gradientAngle = atan(condition.gradientPermille / 1_000.0)
        let normalForce = physicalMass * 9.80665 * cos(gradientAngle)
        let speedKmh = speedMps * 3.6
        let adhesionLimit = weather.adhesionCoefficient / (1 + speedKmh / 2_000) *
            normalForce * parameters.brakedMassFraction
        let serviceBrake = min(effectiveMass * parameters.maximumServiceBrakeDecelerationMps2, adhesionLimit)
        let rolling = lastRollingResistanceN
        let uphillAssistance = lastGradientForceN + lastCurveResistanceN + rolling
        let netBrakeForce = serviceBrake + uphillAssistance
        let expectedDeceleration = netBrakeForce / max(effectiveMass, 1)
        let responseDistance = speedMps * parameters.serviceBrakeApplySeconds
        let brakingDistance = speedMps * speedMps / (2 * max(expectedDeceleration, 0.05))
        let distanceToStop = route.stopMarkerM - positionM
        let lateralAcceleration: Double
        if let radius = condition.curveRadiusM, radius > 0 {
            let curveAcceleration = speedMps * speedMps / radius
            let cantAcceleration = 9.80665 * ((condition.cantMm ?? 0) / route.trackGaugeMm)
            lateralAcceleration = Double(condition.curveDirection ?? 1) * (curveAcceleration - cantAcceleration)
        } else {
            lateralAcceleration = 0
        }

        return TrainTelemetry(
            positionM: positionM,
            speedMps: speedMps,
            accelerationMps2: accelerationMps2,
            tractionForceN: lastTractionForceN,
            brakingForceN: lastBrakingForceN,
            regenerativeBrakeForceN: lastRegenerativeBrakeForceN,
            airBrakeForceN: lastAirBrakeForceN,
            rollingResistanceN: lastRollingResistanceN,
            gradientForceN: lastGradientForceN,
            curveResistanceN: lastCurveResistanceN,
            appliedBrakeFraction: appliedBrakeFraction,
            brakePipePressureKPa: brakePipePressureKPa,
            brakeCylinderPressureKPa: brakeCylinderPressureKPa,
            mainReservoirPressureKPa: mainReservoirPressureKPa,
            effectiveMassKg: effectiveMass,
            passengerLoadFactor: passengerLoadFactor,
            currentGradientPermille: condition.gradientPermille,
            currentCantMm: condition.cantMm ?? 0,
            lateralAccelerationMps2: lateralAcceleration,
            currentSpeedLimitKmh: condition.speedLimitKmh,
            distanceToStopMarkerM: distanceToStop,
            predictedStoppingDistanceM: speedMps <= 0.05 ? 0 : responseDistance + brakingDistance,
            isStoppedAtMarker: abs(distanceToStop) <= 0.5 && speedMps <= 0.2,
            isWheelSlipActive: wheelSlipActive,
            isBrakeSlipActive: brakeSlipActive
        )
    }

    private func moveTowards(_ value: Double, _ target: Double, _ maxDelta: Double) -> Double {
        if value < target { return min(value + maxDelta, target) }
        return max(value - maxDelta, target)
    }
}
