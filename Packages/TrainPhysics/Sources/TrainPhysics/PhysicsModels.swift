import Foundation

/// Every value in the bundled profiles is a fictional gameplay parameter, not a real-train specification.
public enum TractionMode: String, Codable, CaseIterable, Equatable, Sendable {
    case rheostaticDC
    case fieldChopperDC
    case vvvfGTO
    case vvvfIGBT
    case vvvfSiC
}

public enum RailSurface: String, Codable, CaseIterable, Equatable, Sendable {
    case dry
    case wet
    case snow
    case leafContaminated

    /// Fictional game coefficients. These are not adhesion data for any real route or vehicle.
    public var fictionalAdhesionCoefficient: Double {
        switch self {
        case .dry: 0.27
        case .wet: 0.17
        case .snow: 0.10
        case .leafContaminated: 0.09
        }
    }
}

public enum BrakeDemand: Equatable, Sendable {
    case service(notch: Int)
    case emergency
}

public struct SimulationControls: Equatable, Sendable {
    public var throttleNotch: Int
    public var brakeNotch: Int
    public var emergencyBrake: Bool
    /// Resistance-control master reversed for the page-described holding brake. Other profiles ignore it.
    public var masterReversed: Bool

    public init(throttleNotch: Int = 0, brakeNotch: Int = 0, emergencyBrake: Bool = false, masterReversed: Bool = false) {
        self.throttleNotch = throttleNotch
        self.brakeNotch = brakeNotch
        self.emergencyBrake = emergencyBrake
        self.masterReversed = masterReversed
    }
}

/// Davis-style coefficients with explicit units:
/// R[N] = mass[tonne] * (a[N/tonne] + b[N·s/(m·tonne)] * speed[m/s]) + c[N·s²/m²] * speed².
public struct DavisResistanceProfile: Codable, Equatable, Sendable {
    public var aNPerTonne: Double
    public var bNSecondPerMeterPerTonne: Double
    public var cNSecondSquaredPerMeterSquared: Double

    public init(aNPerTonne: Double, bNSecondPerMeterPerTonne: Double, cNSecondSquaredPerMeterSquared: Double) {
        self.aNPerTonne = aNPerTonne
        self.bNSecondPerMeterPerTonne = bNSecondPerMeterPerTonne
        self.cNSecondSquaredPerMeterSquared = cNSecondSquaredPerMeterSquared
    }

    public func resistanceN(massKg: Double, speedMps: Double) -> Double {
        guard massKg.isFinite, massKg >= 0, speedMps.isFinite else { return 0 }
        let speed = max(speedMps, 0)
        let tonnes = massKg / 1_000
        let result = tonnes * (aNPerTonne + bNSecondPerMeterPerTonne * speed)
            + cNSecondSquaredPerMeterSquared * speed * speed
        return result.isFinite ? max(result, 0) : 0
    }
}

/// One physical car in the fictional consist. Brake force, thermal capacity, and tare mass are per car.
public struct TrainCarProfile: Codable, Equatable, Sendable {
    public var identifier: String
    public var tareMassKg: Double
    public var passengerCapacity: Int
    public var drivenMassFraction: Double
    public var brakedMassFraction: Double
    public var maximumServiceBrakeForceN: Double
    public var maximumEmergencyBrakeForceN: Double
    public var brakeApplySeconds: Double
    public var brakeReleaseSeconds: Double
    public var brakeThermalCapacityJPerC: Double
    public var brakeCoolingWPerC: Double
    public var brakeFadeStartC: Double
    public var brakeFadeFullC: Double
    public var minimumBrakeFadeFactor: Double

    public init(
        identifier: String,
        tareMassKg: Double,
        passengerCapacity: Int,
        drivenMassFraction: Double,
        brakedMassFraction: Double,
        maximumServiceBrakeForceN: Double,
        maximumEmergencyBrakeForceN: Double,
        brakeApplySeconds: Double,
        brakeReleaseSeconds: Double,
        brakeThermalCapacityJPerC: Double,
        brakeCoolingWPerC: Double,
        brakeFadeStartC: Double,
        brakeFadeFullC: Double,
        minimumBrakeFadeFactor: Double
    ) {
        self.identifier = identifier
        self.tareMassKg = tareMassKg
        self.passengerCapacity = passengerCapacity
        self.drivenMassFraction = drivenMassFraction
        self.brakedMassFraction = brakedMassFraction
        self.maximumServiceBrakeForceN = maximumServiceBrakeForceN
        self.maximumEmergencyBrakeForceN = maximumEmergencyBrakeForceN
        self.brakeApplySeconds = brakeApplySeconds
        self.brakeReleaseSeconds = brakeReleaseSeconds
        self.brakeThermalCapacityJPerC = brakeThermalCapacityJPerC
        self.brakeCoolingWPerC = brakeCoolingWPerC
        self.brakeFadeStartC = brakeFadeStartC
        self.brakeFadeFullC = brakeFadeFullC
        self.minimumBrakeFadeFactor = minimumBrakeFadeFactor
    }

    public func validationIssues() -> [String] {
        var issues: [String] = []
        if identifier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { issues.append("car identifier is empty") }
        if !tareMassKg.isFinite || !(1...250_000).contains(tareMassKg) { issues.append("tareMassKg must be finite and in 1...250000 kg") }
        if !(0...600).contains(passengerCapacity) { issues.append("passengerCapacity must be in 0...600") }
        if !drivenMassFraction.isFinite || !(0...1).contains(drivenMassFraction) { issues.append("drivenMassFraction must be in 0...1") }
        if !brakedMassFraction.isFinite || !(0...1).contains(brakedMassFraction) { issues.append("brakedMassFraction must be in 0...1") }
        if !maximumServiceBrakeForceN.isFinite || !(0...10_000_000).contains(maximumServiceBrakeForceN) { issues.append("maximumServiceBrakeForceN must be in 0...10000000 N") }
        if !maximumEmergencyBrakeForceN.isFinite || maximumEmergencyBrakeForceN < maximumServiceBrakeForceN || maximumEmergencyBrakeForceN > 10_000_000 { issues.append("maximumEmergencyBrakeForceN must be >= service force and <= 10000000 N") }
        if !brakeApplySeconds.isFinite || !(0.001...120).contains(brakeApplySeconds) { issues.append("brakeApplySeconds must be in 0.001...120 s") }
        if !brakeReleaseSeconds.isFinite || !(0.001...120).contains(brakeReleaseSeconds) { issues.append("brakeReleaseSeconds must be in 0.001...120 s") }
        if !brakeThermalCapacityJPerC.isFinite || !(1...1_000_000_000).contains(brakeThermalCapacityJPerC) { issues.append("brakeThermalCapacityJPerC must be in 1...1000000000 J/C") }
        if !brakeCoolingWPerC.isFinite || !(0...10_000_000).contains(brakeCoolingWPerC) { issues.append("brakeCoolingWPerC must be in 0...10000000 W/C") }
        if !brakeFadeStartC.isFinite || !brakeFadeFullC.isFinite || abs(brakeFadeStartC) > 2_000 || abs(brakeFadeFullC) > 2_000 || brakeFadeFullC <= brakeFadeStartC { issues.append("brake fade temperatures must be finite, bounded, and increasing") }
        if !minimumBrakeFadeFactor.isFinite || !(0...1).contains(minimumBrakeFadeFactor) { issues.append("minimumBrakeFadeFactor must be in 0...1") }
        return issues
    }

    public func fadeFactor(at temperatureC: Double) -> Double {
        guard temperatureC.isFinite else { return minimumBrakeFadeFactor }
        let progress = min(max((temperatureC - brakeFadeStartC) / max(brakeFadeFullC - brakeFadeStartC, 1e-9), 0), 1)
        return 1 - (1 - minimumBrakeFadeFactor) * progress
    }
}

/// Train-pipe/reservoir game model. Pressures are kPa; propagationSecondsPerCar is a first-order per-car lag.
public struct BrakeSystemProfile: Codable, Equatable, Sendable {
    public var chargePressureKPa: Double
    public var maximumServicePipeReductionKPa: Double
    public var maximumCylinderPressureKPa: Double
    public var maximumReservoirPressureKPa: Double
    public var minimumReservoirPressureKPa: Double
    public var reservoirRecoveryKPaPerSecond: Double
    public var propagationSecondsPerCar: Double
    public var ambientTemperatureC: Double

    public init(
        chargePressureKPa: Double,
        maximumServicePipeReductionKPa: Double,
        maximumCylinderPressureKPa: Double,
        maximumReservoirPressureKPa: Double,
        minimumReservoirPressureKPa: Double,
        reservoirRecoveryKPaPerSecond: Double,
        propagationSecondsPerCar: Double,
        ambientTemperatureC: Double
    ) {
        self.chargePressureKPa = chargePressureKPa
        self.maximumServicePipeReductionKPa = maximumServicePipeReductionKPa
        self.maximumCylinderPressureKPa = maximumCylinderPressureKPa
        self.maximumReservoirPressureKPa = maximumReservoirPressureKPa
        self.minimumReservoirPressureKPa = minimumReservoirPressureKPa
        self.reservoirRecoveryKPaPerSecond = reservoirRecoveryKPaPerSecond
        self.propagationSecondsPerCar = propagationSecondsPerCar
        self.ambientTemperatureC = ambientTemperatureC
    }

    public func validationIssues() -> [String] {
        var issues: [String] = []
        let positive = [chargePressureKPa, maximumServicePipeReductionKPa, maximumCylinderPressureKPa,
                        maximumReservoirPressureKPa, propagationSecondsPerCar]
        if !positive.allSatisfy({ $0.isFinite && $0 > 0 && $0 <= 20_000 }) { issues.append("brake pressures must be <= 20000 kPa and propagation time must be positive and <= 20000 s") }
        if maximumServicePipeReductionKPa >= chargePressureKPa { issues.append("service pipe reduction must be below charge pressure") }
        if !minimumReservoirPressureKPa.isFinite || minimumReservoirPressureKPa < 0 || minimumReservoirPressureKPa >= maximumReservoirPressureKPa { issues.append("reservoir pressure bounds are invalid") }
        if !reservoirRecoveryKPaPerSecond.isFinite || !(0...100_000).contains(reservoirRecoveryKPaPerSecond) { issues.append("reservoir recovery must be in 0...100000 kPa/s") }
        if !ambientTemperatureC.isFinite || abs(ambientTemperatureC) > 500 { issues.append("ambientTemperatureC must be finite and within +/-500 C") }
        return issues
    }
}

/// The traction curve intentionally provides a stable coupling boundary for drive and regenerative braking.
public struct TractionProfile: Codable, Equatable, Sendable {
    public var mode: TractionMode
    public var displayName: String
    public var notchFractions: [Double]
    public var maximumSpeedKmh: Double
    public var maximumForceN: Double
    public var maximumPowerW: Double
    public var tractionJerkMps3: Double
    public var baseSpeedKmh: Double
    public var voltageLimitedStartKmh: Double
    public var highSpeedPowerRatio: Double
    public var nominalLineVoltageV: Double
    public var motorCount: Int
    public var currentLimitA: Double
    public var standstillCurrentA: Double
    public var tractionEfficiency: Double
    public var maximumRegenerativeForceN: Double
    public var maximumRegenerativePowerW: Double
    public var maximumRegenerativeShare: Double
    public var regenerativeCutInSpeedKmh: Double
    public var regenerativeFullSpeedKmh: Double

    public init(
        mode: TractionMode,
        displayName: String,
        notchFractions: [Double],
        maximumSpeedKmh: Double,
        maximumForceN: Double,
        maximumPowerW: Double,
        tractionJerkMps3: Double,
        baseSpeedKmh: Double,
        voltageLimitedStartKmh: Double,
        highSpeedPowerRatio: Double,
        nominalLineVoltageV: Double,
        motorCount: Int,
        currentLimitA: Double,
        standstillCurrentA: Double,
        tractionEfficiency: Double,
        maximumRegenerativeForceN: Double,
        maximumRegenerativePowerW: Double,
        maximumRegenerativeShare: Double,
        regenerativeCutInSpeedKmh: Double,
        regenerativeFullSpeedKmh: Double
    ) {
        self.mode = mode
        self.displayName = displayName
        self.notchFractions = notchFractions
        self.maximumSpeedKmh = maximumSpeedKmh
        self.maximumForceN = maximumForceN
        self.maximumPowerW = maximumPowerW
        self.tractionJerkMps3 = tractionJerkMps3
        self.baseSpeedKmh = baseSpeedKmh
        self.voltageLimitedStartKmh = voltageLimitedStartKmh
        self.highSpeedPowerRatio = highSpeedPowerRatio
        self.nominalLineVoltageV = nominalLineVoltageV
        self.motorCount = motorCount
        self.currentLimitA = currentLimitA
        self.standstillCurrentA = standstillCurrentA
        self.tractionEfficiency = tractionEfficiency
        self.maximumRegenerativeForceN = maximumRegenerativeForceN
        self.maximumRegenerativePowerW = maximumRegenerativePowerW
        self.maximumRegenerativeShare = maximumRegenerativeShare
        self.regenerativeCutInSpeedKmh = regenerativeCutInSpeedKmh
        self.regenerativeFullSpeedKmh = regenerativeFullSpeedKmh
    }

    public func validationIssues() -> [String] {
        var issues: [String] = []
        if displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { issues.append("traction displayName is empty") }
        let positive = [maximumSpeedKmh, maximumForceN, maximumPowerW, baseSpeedKmh, nominalLineVoltageV,
                        tractionJerkMps3, currentLimitA, standstillCurrentA, maximumRegenerativeForceN, maximumRegenerativePowerW]
        if !positive.allSatisfy({ $0.isFinite && $0 > 0 }) { issues.append("traction limits must be finite and > 0") }
        if tractionJerkMps3 > 5 { issues.append("tractionJerkMps3 must be <= 5 m/s^3") }
        if maximumSpeedKmh > 500 || maximumForceN > 10_000_000 || maximumPowerW > 10_000_000_000
            || nominalLineVoltageV > 100_000 || currentLimitA > 10_000_000 || standstillCurrentA > currentLimitA
            || maximumRegenerativeForceN > 10_000_000 || maximumRegenerativePowerW > 10_000_000_000 {
            issues.append("traction, electrical, and regenerative limits exceed bounded game ranges")
        }
        if !voltageLimitedStartKmh.isFinite || voltageLimitedStartKmh < baseSpeedKmh || voltageLimitedStartKmh > maximumSpeedKmh { issues.append("voltage-limited start must be between base and maximum speed") }
        if baseSpeedKmh >= maximumSpeedKmh { issues.append("base speed must be below maximum speed") }
        if !highSpeedPowerRatio.isFinite || !(0...1).contains(highSpeedPowerRatio) { issues.append("highSpeedPowerRatio must be in 0...1") }
        if !(1...1_000).contains(motorCount) { issues.append("motorCount must be in 1...1000") }
        if !tractionEfficiency.isFinite || !(0.1...1).contains(tractionEfficiency) { issues.append("tractionEfficiency must be in 0.1...1") }
        if !maximumRegenerativeShare.isFinite || !(0...1).contains(maximumRegenerativeShare) { issues.append("maximumRegenerativeShare must be in 0...1") }
        if !regenerativeCutInSpeedKmh.isFinite || regenerativeCutInSpeedKmh < 0 { issues.append("regenerativeCutInSpeedKmh must be finite and >= 0") }
        if !regenerativeFullSpeedKmh.isFinite || regenerativeFullSpeedKmh <= regenerativeCutInSpeedKmh || regenerativeFullSpeedKmh > maximumSpeedKmh { issues.append("regenerativeFullSpeedKmh must be above cut-in and at or below maximum speed") }
        if !notchFractions.allSatisfy({ $0.isFinite && (0...1).contains($0) }) || !(2...16).contains(notchFractions.count) { issues.append("notchFractions need 2...16 finite values in 0...1") }
        if notchFractions.first != 0 || zip(notchFractions, notchFractions.dropFirst()).contains(where: { $0.0 > $0.1 }) { issues.append("notchFractions must start at zero and be nondecreasing") }
        return issues
    }

    /// Piecewise fictional envelope: constant force, constant power, then natural-voltage power reduction.
    public func availableTractionForceN(speedKmh: Double, notch: Int) -> Double {
        guard maximumSpeedKmh.isFinite, maximumSpeedKmh > 0 else { return 0 }
        let speed = speedKmh.isFinite ? max(speedKmh, 0) : 0
        guard speed < maximumSpeedKmh, !notchFractions.isEmpty else { return 0 }
        let index = min(max(notch, 0), notchFractions.count - 1)
        let notchFraction = notchFractions[index].isFinite ? min(max(notchFractions[index], 0), 1) : 0
        guard notchFraction > 0 else { return 0 }

        let speedMps = speed / 3.6
        let envelope: Double
        if speed <= baseSpeedKmh {
            envelope = maximumForceN
        } else {
            let voltageRatio: Double
            if speed <= voltageLimitedStartKmh {
                voltageRatio = 1
            } else {
                let span = max(maximumSpeedKmh - voltageLimitedStartKmh, 1e-9)
                let fraction = min(max((speed - voltageLimitedStartKmh) / span, 0), 1)
                voltageRatio = 1 + (highSpeedPowerRatio - 1) * fraction
            }
            envelope = min(maximumForceN, maximumPowerW * voltageRatio / max(speedMps, 0.05))
        }
        let result = envelope * notchFraction
        return result.isFinite ? max(result, 0) : 0
    }

    /// Signed line-current estimate [A]: positive draws power, negative returns it. Game instrumentation only.
    public func lineCurrentA(forceN: Double, speedMps: Double, lineVoltageV: Double, regenerative: Bool = false) -> Double {
        guard forceN.isFinite, speedMps.isFinite, lineVoltageV.isFinite, lineVoltageV > 0,
              maximumForceN > 0, currentLimitA > 0 else { return 0 }
        let force = max(forceN, 0)
        let voltage = max(lineVoltageV, 1)
        let mechanicalPower = force * max(speedMps, 0)
        let lowSpeedEstimate = force / maximumForceN * standstillCurrentA
        let powerEstimate = mechanicalPower / max(voltage * tractionEfficiency, 1)
        let magnitude = min(currentLimitA, max(lowSpeedEstimate, powerEstimate))
        return regenerative ? -magnitude : magnitude
    }

    /// Regenerative-force request before axle adhesion limiting and pneumatic blending.
    public func regenerativeForceRequestN(brakeDemandN: Double, speedKmh: Double) -> Double {
        guard brakeDemandN.isFinite, speedKmh.isFinite, speedKmh > regenerativeCutInSpeedKmh else { return 0 }
        let speed = max(speedKmh, 0)
        let fade = min(max((speed - regenerativeCutInSpeedKmh) / max(regenerativeFullSpeedKmh - regenerativeCutInSpeedKmh, 1e-9), 0), 1)
        let powerLimit = maximumRegenerativePowerW / max(speed / 3.6, 0.1)
        return min(max(brakeDemandN, 0) * maximumRegenerativeShare * fade,
                   maximumRegenerativeForceN, powerLimit)
    }
}

public struct TrainsetProfile: Codable, Equatable, Sendable {
    public var identifier: String
    public var displayName: String
    public var fictionalNotice: String
    public var rotationalInertiaFactor: Double
    public var davisResistance: DavisResistanceProfile
    public var curveResistanceNPerKNAtOnePerM: Double
    public var brakeSystem: BrakeSystemProfile
    public var traction: TractionProfile
    public var cars: [TrainCarProfile]

    public init(
        identifier: String,
        displayName: String,
        fictionalNotice: String,
        rotationalInertiaFactor: Double,
        davisResistance: DavisResistanceProfile,
        curveResistanceNPerKNAtOnePerM: Double,
        brakeSystem: BrakeSystemProfile,
        traction: TractionProfile,
        cars: [TrainCarProfile]
    ) {
        self.identifier = identifier
        self.displayName = displayName
        self.fictionalNotice = fictionalNotice
        self.rotationalInertiaFactor = rotationalInertiaFactor
        self.davisResistance = davisResistance
        self.curveResistanceNPerKNAtOnePerM = curveResistanceNPerKNAtOnePerM
        self.brakeSystem = brakeSystem
        self.traction = traction
        self.cars = cars
    }

    public var carCount: Int { cars.count }
    public var maximumTractionNotch: Int { max(traction.notchFractions.count - 1, 0) }

    public func validationIssues() -> [String] {
        var issues: [String] = []
        if identifier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { issues.append("profile identifier is empty") }
        if displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { issues.append("profile displayName is empty") }
        if fictionalNotice.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { issues.append("fictional notice is required") }
        if !(1...16).contains(cars.count) { issues.append("car count must be in 1...16") }
        if !rotationalInertiaFactor.isFinite || !(1...10).contains(rotationalInertiaFactor) { issues.append("rotationalInertiaFactor must be in 1...10") }
        if !curveResistanceNPerKNAtOnePerM.isFinite || !(0...1_000_000).contains(curveResistanceNPerKNAtOnePerM) { issues.append("curve resistance coefficient must be in 0...1000000") }
        if !davisResistance.aNPerTonne.isFinite || !(0...1_000_000).contains(davisResistance.aNPerTonne)
            || !davisResistance.bNSecondPerMeterPerTonne.isFinite || !(0...1_000_000).contains(davisResistance.bNSecondPerMeterPerTonne)
            || !davisResistance.cNSecondSquaredPerMeterSquared.isFinite || !(0...1_000_000).contains(davisResistance.cNSecondSquaredPerMeterSquared) {
            issues.append("Davis coefficients must be finite and in 0...1000000")
        }
        issues += brakeSystem.validationIssues()
        issues += traction.validationIssues()
        if Set(cars.map(\.identifier)).count != cars.count { issues.append("car identifiers must be unique") }
        for (index, car) in cars.enumerated() {
            issues += car.validationIssues().map { "car[\(index)]: \($0)" }
        }
        return issues
    }

    public func totalMassKg(passengerLoadFactor: Double) -> Double {
        guard passengerLoadFactor.isFinite else { return cars.reduce(0) { $0 + $1.tareMassKg } }
        let load = min(max(passengerLoadFactor, 0), 2)
        return cars.reduce(0) { $0 + $1.tareMassKg + Double($1.passengerCapacity) * load * 60 }
    }

    public func effectiveMassKg(passengerLoadFactor: Double) -> Double {
        totalMassKg(passengerLoadFactor: passengerLoadFactor) * rotationalInertiaFactor
    }
}

public enum TrainPhysicsError: Error, Equatable, LocalizedError, Sendable {
    case invalidProfile([String])
    case bundledProfilesUnavailable

    public var errorDescription: String? {
        switch self {
        case .invalidProfile(let issues): "Invalid fictional train profile: " + issues.joined(separator: "; ")
        case .bundledProfilesUnavailable: "Bundled fictional train profiles could not be loaded."
        }
    }
}

/// A track sample is constant over one tick. Positive gradient means uphill in the train's direction.
public struct TrackCondition: Equatable, Sendable {
    public var gradientPermille: Double
    public var curveRadiusM: Double?
    public var speedLimitKmh: Double
    public var tunnelResistanceMultiplier: Double
    public var supplyVoltageV: Double?

    public init(
        gradientPermille: Double = 0,
        curveRadiusM: Double? = nil,
        speedLimitKmh: Double = 160,
        tunnelResistanceMultiplier: Double = 1,
        supplyVoltageV: Double? = nil
    ) {
        self.gradientPermille = gradientPermille
        self.curveRadiusM = curveRadiusM
        self.speedLimitKmh = speedLimitKmh
        self.tunnelResistanceMultiplier = tunnelResistanceMultiplier
        self.supplyVoltageV = supplyVoltageV
    }

    public static let level = TrackCondition()

    public var isValid: Bool {
        gradientPermille.isFinite && abs(gradientPermille) <= 250
            && (curveRadiusM == nil || (curveRadiusM!.isFinite && curveRadiusM! > 0))
            && speedLimitKmh.isFinite && speedLimitKmh >= 0 && speedLimitKmh <= 500
            && tunnelResistanceMultiplier.isFinite && tunnelResistanceMultiplier >= 1 && tunnelResistanceMultiplier <= 4
            && (supplyVoltageV == nil || (supplyVoltageV!.isFinite && supplyVoltageV! > 0 && supplyVoltageV! <= 100_000))
    }
}

public enum PhysicsConstants {
    public static let fixedTimeStepSeconds = 1.0 / 120.0
    public static let maximumFrameDeltaSeconds = 0.5
    public static let gravityMps2 = 9.80665
    public static let passengerMassKg = 60.0
    public static let stopSpeedThresholdMps = 0.01
}
