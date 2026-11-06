import Foundation
import RailwayAudioEnhancements
import TrainPhysics

/// Original, wholly fictional rolling-stock archetypes. These values are playable placeholders,
/// not copied or inferred specifications for any real train.
/// The six formation cases reuse the TrainPhysics catalog. Their mass, force, and brake
/// numbers are PLACEHOLDER values inspired by control type and 8-car / 10-car length.
enum FictionalVehicleProfile: String, CaseIterable, Identifiable, Sendable {
    case vvvfFormation8
    case vvvfFormation10
    case fieldChopperFormation8
    case fieldChopperFormation10
    case resistanceFormation8
    case resistanceFormation10
    case rheostaticDC
    case fieldChopperDC
    case vvvfGTO
    case vvvfIGBT
    case vvvfSiC

    var id: String { rawValue }

    var physicsProfileIdentifier: String {
        switch self {
        case .vvvfFormation8: "fictional-vvvf-form-8"
        case .vvvfFormation10: "fictional-vvvf-form-10"
        case .fieldChopperFormation8: "fictional-chopper-form-8"
        case .fieldChopperFormation10: "fictional-chopper-form-10"
        case .resistanceFormation8: "fictional-resistance-form-8"
        case .resistanceFormation10: "fictional-resistance-form-10"
        case .rheostaticDC: "fictional-rheostatic-t02"
        case .fieldChopperDC: "fictional-field-chopper-t01"
        case .vvvfGTO: "fictional-vvvf-gto-t03"
        case .vvvfIGBT: "fictional-vvvf-igbt-t04"
        case .vvvfSiC: "fictional-vvvf-sic-t05"
        }
    }

    var title: String {
        switch self {
        case .vvvfFormation8: "VVVF 8両（東武50000系の制御を参考）"
        case .vvvfFormation10: "VVVF 10両（東武50000系の制御を参考）"
        case .fieldChopperFormation8: "界磁チョッパ 8両（西武2000系の制御を参考）"
        case .fieldChopperFormation10: "界磁チョッパ 10両（西武2000系の制御を参考）"
        case .resistanceFormation8: "抵抗制御 8両（西武4000系の制御を参考）"
        case .resistanceFormation10: "抵抗制御 10両（西武4000系の制御を参考）"
        case .rheostaticDC: "T-02 抵抗制御（架空）"
        case .fieldChopperDC: "T-01 界磁チョッパ（架空）"
        case .vvvfGTO: "T-03 VVVF GTO（架空）"
        case .vvvfIGBT: "T-04 VVVF IGBT（架空）"
        case .vvvfSiC: "T-05 VVVF SiC（架空）"
        }
    }

    var description: String {
        switch self {
        case .vvvfFormation8: "8両 · PLACEHOLDER · 1ノッチ保持後の2ノッチで20km/h定速"
        case .vvvfFormation10: "10両 · PLACEHOLDER · 20km/h以上の2ノッチはその速度で定速"
        case .fieldChopperFormation8: "8両 · PLACEHOLDER · 並列最終後に回生と速い再力行"
        case .fieldChopperFormation10: "10両 · ページ上はおまけ · PLACEHOLDER"
        case .resistanceFormation8: "8両 · PLACEHOLDER · 1ノッチで進段停止、逆回しで抑速"
        case .resistanceFormation10: "10両 · ページに無い追加PLACEHOLDER"
        case .rheostaticDC: "4両 · 80 km/h · 段階制御のゲーム物理プロファイル"
        case .fieldChopperDC: "6両 · 100 km/h · 標準ゲーム物理プロファイル"
        case .vvvfGTO: "6両 · 110 km/h · GTO近似のゲーム物理プロファイル"
        case .vvvfIGBT: "8両 · 120 km/h · IGBT近似のゲーム物理プロファイル"
        case .vvvfSiC: "8両 · 130 km/h · 汎用SiC近似のゲーム物理プロファイル"
        }
    }

    var cabFamily: FictionalControlFamily {
        FictionalCabAndSoundCatalog.family(forProfileID: soundProfile.rawValue)
    }

    var cabDesk: FictionalCabDesk {
        FictionalCabAndSoundCatalog.desk(for: cabFamily)
    }

    var soundProfile: RailwayTractionSoundProfile {
        switch self {
        case .resistanceFormation8, .resistanceFormation10, .rheostaticDC: .rheostaticDC
        case .fieldChopperFormation8, .fieldChopperFormation10, .fieldChopperDC: .fieldChopperDC
        case .vvvfGTO: .vvvfGTO
        case .vvvfFormation8, .vvvfFormation10, .vvvfIGBT: .vvvfIGBT
        case .vvvfSiC: .vvvfSiC
        }
    }

    var carCount: Int {
        switch self {
        case .vvvfFormation8, .fieldChopperFormation8, .resistanceFormation8: 8
        case .vvvfFormation10, .fieldChopperFormation10, .resistanceFormation10: 10
        case .rheostaticDC: 4
        case .fieldChopperDC, .vvvfGTO: 6
        case .vvvfIGBT, .vvvfSiC: 8
        }
    }

    private var usesFormationCatalog: Bool {
        switch self {
        case .vvvfFormation8, .vvvfFormation10, .fieldChopperFormation8, .fieldChopperFormation10, .resistanceFormation8, .resistanceFormation10:
            true
        default:
            false
        }
    }

    var passengerCapacityPerCar: Int {
        switch self {
        case .rheostaticDC: 100
        case .vvvfFormation8, .vvvfFormation10, .fieldChopperFormation8, .fieldChopperFormation10, .resistanceFormation8, .resistanceFormation10: 144
        default: 110
        }
    }
    var maximumSpeedKmh: Double {
        switch self {
        case .vvvfFormation8, .vvvfFormation10, .vvvfGTO: 110
        case .fieldChopperFormation8, .fieldChopperFormation10: 105
        case .resistanceFormation8, .resistanceFormation10: 100
        case .rheostaticDC: 80
        case .fieldChopperDC: 100
        case .vvvfIGBT: 120
        case .vvvfSiC: 130
        }
    }

    /// Constructs a validated, deterministic gameplay profile; all constants are intentionally fictional.
    func makeParameters() -> TrainParameters {
        if usesFormationCatalog {
            return parametersFromFormationCatalog()
        }
        let base = TrainParameters.fictionalPrototype
        let forceScale: Double
        let powerScale: Double
        let regen: Double
        let tareMass: Double
        let serviceBrake: Double
        switch self {
        case .rheostaticDC:
            forceScale = 0.78; powerScale = 0.75; regen = 0.10; tareMass = 29_000; serviceBrake = 0.88
        case .fieldChopperDC:
            forceScale = 1.00; powerScale = 1.00; regen = 0.58; tareMass = 30_000; serviceBrake = 0.9722222222
        case .vvvfGTO:
            forceScale = 1.08; powerScale = 1.22; regen = 0.66; tareMass = 31_000; serviceBrake = 1.00
        case .vvvfIGBT:
            forceScale = 1.28; powerScale = 1.55; regen = 0.74; tareMass = 32_000; serviceBrake = 1.08
        case .vvvfSiC:
            forceScale = 1.40; powerScale = 1.85; regen = 0.78; tareMass = 31_500; serviceBrake = 1.10
        case .vvvfFormation8, .vvvfFormation10, .fieldChopperFormation8, .fieldChopperFormation10, .resistanceFormation8, .resistanceFormation10:
            forceScale = 1; powerScale = 1; regen = 0; tareMass = 30_000; serviceBrake = 1
        }
        let maximumForce = 210_000 * forceScale
        let maximumPower = 2_400_000 * powerScale
        let speedScale = maximumSpeedKmh / 100
        let curve = base.tractionCurve.map {
            TractionPoint(speedKmh: $0.speedKmh * speedScale, forceN: min(maximumForce, $0.forceN * forceScale))
        }
        let notches: [Double]
        switch self {
        case .rheostaticDC, .resistanceFormation8, .resistanceFormation10: notches = [0, 0.20, 0.40, 0.64, 0.82, 1]
        case .fieldChopperDC, .fieldChopperFormation8, .fieldChopperFormation10: notches = [0, 0.18, 0.36, 0.62, 0.82, 1]
        case .vvvfGTO: notches = [0, 0.22, 0.46, 0.72, 1]
        case .vvvfIGBT, .vvvfFormation8, .vvvfFormation10: notches = [0, 0.18, 0.38, 0.58, 0.80, 1]
        case .vvvfSiC: notches = [0, 0.25, 0.50, 0.75, 1]
        }
        return TrainParameters(
            displayName: title,
            carCount: carCount,
            tareMassPerCarKg: tareMass,
            passengerCapacityPerCar: passengerCapacityPerCar,
            rotationalInertiaFactor: base.rotationalInertiaFactor,
            drivenMassFraction: base.drivenMassFraction,
            brakedMassFraction: base.brakedMassFraction,
            maximumServiceBrakeDecelerationMps2: serviceBrake,
            maximumEmergencyBrakeDecelerationMps2: max(serviceBrake, base.maximumEmergencyBrakeDecelerationMps2),
            maximumSpeedKmh: maximumSpeedKmh,
            davisA: base.davisA,
            davisBPerMps: base.davisBPerMps,
            davisC: base.davisC,
            curveResistanceCoefficient: base.curveResistanceCoefficient,
            maximumTractionForceN: maximumForce,
            maximumTractionPowerW: maximumPower,
            tractionJerkMps3: base.tractionJerkMps3,
            serviceBrakeApplySeconds: base.serviceBrakeApplySeconds,
            emergencyBrakeApplySeconds: base.emergencyBrakeApplySeconds,
            brakeReleaseSeconds: base.brakeReleaseSeconds,
            regenerativeBrakeShare: regen,
            regenerativeFadeSpeedKmh: base.regenerativeFadeSpeedKmh,
            tractionNotchFractions: notches,
            tractionCurve: curve
        )
    }

    /// HUD and length estimates follow the same catalog the fixed-step engine loads.
    private func parametersFromFormationCatalog() -> TrainParameters {
        let physics = try! TrainPhysics.FictionalProfileCatalog.profile(identifier: physicsProfileIdentifier)
        let tare = physics.cars.map(\.tareMassKg).reduce(0, +) / Double(physics.cars.count)
        let totalTare = physics.totalMassKg(passengerLoadFactor: 0)
        let driven = physics.cars.reduce(0.0) { $0 + $1.tareMassKg * $1.drivenMassFraction } / max(totalTare, 1)
        let serviceForce = physics.cars.map(\.maximumServiceBrakeForceN).reduce(0, +)
        let emergencyForce = physics.cars.map(\.maximumEmergencyBrakeForceN).reduce(0, +)
        let effective = max(totalTare * physics.rotationalInertiaFactor, 1)
        let serviceDecel = serviceForce / effective
        let emergencyDecel = max(emergencyForce / effective, serviceDecel)
        let apply = physics.cars.map(\.brakeApplySeconds).reduce(0, +) / Double(physics.cars.count)
        let release = physics.cars.map(\.brakeReleaseSeconds).reduce(0, +) / Double(physics.cars.count)
        let force = physics.traction.maximumForceN
        return TrainParameters(
            displayName: title,
            carCount: physics.carCount,
            tareMassPerCarKg: tare,
            passengerCapacityPerCar: physics.cars.first?.passengerCapacity ?? 144,
            rotationalInertiaFactor: physics.rotationalInertiaFactor,
            drivenMassFraction: driven,
            brakedMassFraction: 1,
            maximumServiceBrakeDecelerationMps2: serviceDecel,
            maximumEmergencyBrakeDecelerationMps2: emergencyDecel,
            maximumSpeedKmh: physics.traction.maximumSpeedKmh,
            davisA: physics.davisResistance.aNPerTonne,
            davisBPerMps: physics.davisResistance.bNSecondPerMeterPerTonne,
            davisC: physics.davisResistance.cNSecondSquaredPerMeterSquared,
            curveResistanceCoefficient: physics.curveResistanceNPerKNAtOnePerM,
            maximumTractionForceN: force,
            maximumTractionPowerW: physics.traction.maximumPowerW,
            tractionJerkMps3: physics.traction.tractionJerkMps3,
            serviceBrakeApplySeconds: apply,
            emergencyBrakeApplySeconds: max(apply * 0.72, 0.05),
            brakeReleaseSeconds: release,
            regenerativeBrakeShare: physics.traction.maximumRegenerativeShare,
            regenerativeFadeSpeedKmh: physics.traction.regenerativeFullSpeedKmh,
            tractionNotchFractions: physics.traction.notchFractions,
            tractionCurve: [
                TractionPoint(speedKmh: 0, forceN: force),
                TractionPoint(speedKmh: physics.traction.baseSpeedKmh, forceN: force),
                TractionPoint(speedKmh: physics.traction.maximumSpeedKmh, forceN: 0),
            ]
        )
    }
}
