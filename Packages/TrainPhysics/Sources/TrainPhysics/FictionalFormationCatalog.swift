import Foundation

/// 8-car and 10-car gameplay profiles for the three referenced control types.
///
/// Mass, tractive effort, and brake response are PLACEHOLDER / fictionalized.
/// Handle behavior follows the public page descriptions cited in `FictionalPageDescribedControl`.
/// Those pages are fan-made BVE notes, not manufacturer data, and none of their files are included.
/// They are not official tare weights, motor ratings, or brake tables for
/// 東武50000系, 西武2000系, or 西武4000系.
public enum FictionalFormationCatalog {
    public static let fictionalNotice =
        "PLACEHOLDER / fictionalized。公開ページに書かれたファン制作BVEの制御の扱いを参考にした架空値で、公式メーカー諸元でもアドオンの複製でもない。実車安全計算・運行判断・訓練には使用不可。"
    private static let vvvfNotice =
        fictionalNotice + " 定速は https://moribayashi80.tsuyushiba.com/Entry/15/ （つきさぶ５条１６丁目、2022-02-11、TJ51001F / TJ51002F / TJ50090-C）の記述。1ノッチを数秒保持してから2ノッチで20km/h、20km/h以上の2ノッチはその速度。音・パネル・ats.dll等は不使用。"
    private static let chopperNotice =
        fictionalNotice + " 界磁チョッパは https://sigf.sakura.ne.jp/bve_sb2000.html （循環車線 / shallow-field、2026-10-01）の記述。並列最終段後の0Aで中高速の再力行が速く、その状態でのみ回生。カム未達か速度低下で回生しない。灯名は直列・並列・最終・界磁弱メ・回生制動。ページ上の8両が本編で、6両と10両はおまけ。https://sigf.sakura.ne.jp/bve.html はスクショ・運転動画・アドオン指定以外の二次利用に事前相談を求めており、ファイルは入れてない。"
    private static let resistance8Notice =
        fictionalNotice + " 抵抗制御は https://sigf.sakura.ne.jp/bve_sb4000.html （同作者、2016-12-21）の記述。1ノッチで進段停止、マスコン逆回しで抑速。前期型の低音は合成のみ。ページの編成は4両ワンマンと8両車掌乗務。同じ二次利用条件。ファイルは不使用。"
    private static let resistance10Notice =
        fictionalNotice + " 追加PLACEHOLDER。西武4000系の公開ページは4両と8両だけで、この10両はそのパックの編成ではない。進段停止と抑速だけを8両と同じ架空則にした。"

    public static var all: [TrainsetProfile] {
        [vvvf8, vvvf10, fieldChopper8, fieldChopper10, resistance8, resistance10]
    }

    public static let vvvf8 = make(
        kind: .vvvf, cars: 8, identifier: "fictional-vvvf-form-8",
        displayName: "VVVF 8両（東武50000系の制御を参考・PLACEHOLDER）",
        notice: vvvfNotice
    )
    public static let vvvf10 = make(
        kind: .vvvf, cars: 10, identifier: "fictional-vvvf-form-10",
        displayName: "VVVF 10両（東武50000系の制御を参考・PLACEHOLDER）",
        notice: vvvfNotice
    )
    public static let fieldChopper8 = make(
        kind: .fieldChopper, cars: 8, identifier: "fictional-chopper-form-8",
        displayName: "界磁チョッパ 8両（西武2000系の制御を参考・PLACEHOLDER）",
        notice: chopperNotice
    )
    public static let fieldChopper10 = make(
        kind: .fieldChopper, cars: 10, identifier: "fictional-chopper-form-10",
        displayName: "界磁チョッパ 10両（ページ上はおまけ・PLACEHOLDER）",
        notice: chopperNotice
    )
    public static let resistance8 = make(
        kind: .resistance, cars: 8, identifier: "fictional-resistance-form-8",
        displayName: "抵抗制御 8両（西武4000系の制御を参考・PLACEHOLDER）",
        notice: resistance8Notice
    )
    public static let resistance10 = make(
        kind: .resistance, cars: 10, identifier: "fictional-resistance-form-10",
        displayName: "抵抗制御 10両（ページ外の追加PLACEHOLDER）",
        notice: resistance10Notice
    )

    private enum Kind {
        case vvvf
        case fieldChopper
        case resistance

        var mode: TractionMode {
            switch self {
            case .vvvf: .vvvfIGBT
            case .fieldChopper: .fieldChopperDC
            case .resistance: .rheostaticDC
            }
        }

        var tractionName: String {
            switch self {
            case .vvvf: "VVVF・連続出力（架空PLACEHOLDER）"
            case .fieldChopper: "界磁チョッパ・段階出力（架空PLACEHOLDER）"
            case .resistance: "抵抗制御・段階出力（架空PLACEHOLDER）"
            }
        }

        /// Shared by both formation lengths so a longer set is heavier, not stronger.
        var maximumForceN: Double {
            switch self {
            case .vvvf: 260_000
            case .fieldChopper: 200_000
            case .resistance: 155_000
            }
        }

        var maximumPowerW: Double {
            switch self {
            case .vvvf: 3_400_000
            case .fieldChopper: 2_200_000
            case .resistance: 1_450_000
            }
        }

        var maximumSpeedKmh: Double {
            switch self {
            case .vvvf: 110
            case .fieldChopper: 105
            case .resistance: 100
            }
        }

        var baseSpeedKmh: Double {
            switch self {
            case .vvvf: 42
            case .fieldChopper: 38
            case .resistance: 32
            }
        }

        var voltageLimitedStartKmh: Double {
            switch self {
            case .vvvf: 78
            case .fieldChopper: 70
            case .resistance: 62
            }
        }

        var highSpeedPowerRatio: Double {
            switch self {
            case .vvvf: 0.72
            case .fieldChopper: 0.62
            case .resistance: 0.50
            }
        }

        var regenerativeShare: Double {
            switch self {
            case .vvvf: 0.72
            case .fieldChopper: 0.42
            case .resistance: 0.08
            }
        }

        var maximumRegenerativeForceN: Double {
            switch self {
            case .vvvf: 180_000
            case .fieldChopper: 90_000
            case .resistance: 22_000
            }
        }

        var maximumRegenerativePowerW: Double {
            switch self {
            case .vvvf: 2_200_000
            case .fieldChopper: 900_000
            case .resistance: 180_000
            }
        }

        var regenerativeCutInSpeedKmh: Double {
            switch self {
            case .vvvf: 5
            case .fieldChopper: 8
            case .resistance: 12
            }
        }

        var regenerativeFullSpeedKmh: Double {
            switch self {
            case .vvvf: 18
            case .fieldChopper: 16
            case .resistance: 22
            }
        }

        var tractionJerkMps3: Double {
            switch self {
            case .vvvf: 0.85
            case .fieldChopper: 0.70
            case .resistance: 0.55
            }
        }

        var tractionEfficiency: Double {
            switch self {
            case .vvvf: 0.90
            case .fieldChopper: 0.84
            case .resistance: 0.80
            }
        }

        var currentLimitA: Double {
            switch self {
            case .vvvf: 1_800
            case .fieldChopper: 1_400
            case .resistance: 1_100
            }
        }

        var standstillCurrentA: Double {
            switch self {
            case .vvvf: 520
            case .fieldChopper: 480
            case .resistance: 420
            }
        }

        var notchFractions: [Double] {
            switch self {
            case .vvvf: [0, 0.18, 0.38, 0.58, 0.80, 1]
            case .fieldChopper: [0, 0.18, 0.36, 0.62, 0.82, 1]
            case .resistance: [0, 0.20, 0.40, 0.64, 0.82, 1]
            }
        }

        var propagationSecondsPerCar: Double {
            switch self {
            case .vvvf: 0.045
            case .fieldChopper: 0.070
            case .resistance: 0.120
            }
        }

        var brakeApplySeconds: Double {
            switch self {
            case .vvvf: 0.85
            case .fieldChopper: 1.35
            case .resistance: 2.10
            }
        }

        var brakeReleaseSeconds: Double {
            switch self {
            case .vvvf: 1.05
            case .fieldChopper: 1.60
            case .resistance: 2.40
            }
        }

        var motorTareKg: Double {
            switch self {
            case .vvvf: 33_500
            case .fieldChopper: 32_800
            case .resistance: 34_200
            }
        }

        var trailerTareKg: Double {
            switch self {
            case .vvvf: 29_800
            case .fieldChopper: 29_200
            case .resistance: 30_500
            }
        }

        var serviceBrakeN: Double {
            switch self {
            case .vvvf: 54_000
            case .fieldChopper: 48_000
            case .resistance: 44_000
            }
        }

        var emergencyBrakeN: Double {
            switch self {
            case .vvvf: 72_000
            case .fieldChopper: 64_000
            case .resistance: 58_000
            }
        }

        /// Extra trailers in the 10-car set. Same mass class, less brake force, so length is not free.
        var weakTrailerServiceBrakeN: Double { serviceBrakeN * 0.56 }
        var weakTrailerEmergencyBrakeN: Double { emergencyBrakeN * 0.58 }

        var aerodynamicCN: Double {
            switch self {
            case .vvvf: 2.3
            case .fieldChopper: 2.6
            case .resistance: 3.1
            }
        }
    }

    /// 4M on both lengths. The 10-car set inserts two lighter-braked trailers.
    private static func motorIndices(carCount: Int) -> Set<Int> {
        carCount == 10 ? [0, 3, 5, 8] : [0, 2, 4, 6]
    }

    private static func weakTrailerIndices(carCount: Int) -> Set<Int> {
        carCount == 10 ? [2, 7] : []
    }

    private static func make(kind: Kind, cars: Int, identifier: String, displayName: String, notice: String) -> TrainsetProfile {
        let motors = motorIndices(carCount: cars)
        let weak = weakTrailerIndices(carCount: cars)
        let builtCars: [TrainCarProfile] = (0..<cars).map { index in
            let driven = motors.contains(index)
            let weakBrake = weak.contains(index)
            return TrainCarProfile(
                identifier: "\(identifier)-\(index + 1)",
                tareMassKg: driven ? kind.motorTareKg : kind.trailerTareKg,
                passengerCapacity: 144,
                drivenMassFraction: driven ? 1 : 0,
                brakedMassFraction: 1,
                maximumServiceBrakeForceN: weakBrake ? kind.weakTrailerServiceBrakeN : kind.serviceBrakeN,
                maximumEmergencyBrakeForceN: weakBrake ? kind.weakTrailerEmergencyBrakeN : kind.emergencyBrakeN,
                brakeApplySeconds: kind.brakeApplySeconds,
                brakeReleaseSeconds: kind.brakeReleaseSeconds,
                brakeThermalCapacityJPerC: 90_000,
                brakeCoolingWPerC: 400,
                brakeFadeStartC: 120,
                brakeFadeFullC: 250,
                minimumBrakeFadeFactor: 0.55
            )
        }
        return TrainsetProfile(
            identifier: identifier,
            displayName: displayName,
            fictionalNotice: notice,
            rotationalInertiaFactor: 1.06,
            davisResistance: DavisResistanceProfile(
                aNPerTonne: 18,
                bNSecondPerMeterPerTonne: 0.32,
                cNSecondSquaredPerMeterSquared: kind.aerodynamicCN
            ),
            curveResistanceNPerKNAtOnePerM: 600,
            brakeSystem: BrakeSystemProfile(
                chargePressureKPa: 500,
                maximumServicePipeReductionKPa: 150,
                maximumCylinderPressureKPa: 380,
                maximumReservoirPressureKPa: 780,
                minimumReservoirPressureKPa: 650,
                reservoirRecoveryKPaPerSecond: 20,
                propagationSecondsPerCar: kind.propagationSecondsPerCar,
                ambientTemperatureC: 20
            ),
            traction: TractionProfile(
                mode: kind.mode,
                displayName: kind.tractionName,
                notchFractions: kind.notchFractions,
                maximumSpeedKmh: kind.maximumSpeedKmh,
                maximumForceN: kind.maximumForceN,
                maximumPowerW: kind.maximumPowerW,
                tractionJerkMps3: kind.tractionJerkMps3,
                baseSpeedKmh: kind.baseSpeedKmh,
                voltageLimitedStartKmh: kind.voltageLimitedStartKmh,
                highSpeedPowerRatio: kind.highSpeedPowerRatio,
                nominalLineVoltageV: 1_500,
                motorCount: 16,
                currentLimitA: kind.currentLimitA,
                standstillCurrentA: kind.standstillCurrentA,
                tractionEfficiency: kind.tractionEfficiency,
                maximumRegenerativeForceN: kind.maximumRegenerativeForceN,
                maximumRegenerativePowerW: kind.maximumRegenerativePowerW,
                maximumRegenerativeShare: kind.regenerativeShare,
                regenerativeCutInSpeedKmh: kind.regenerativeCutInSpeedKmh,
                regenerativeFullSpeedKmh: kind.regenerativeFullSpeedKmh
            ),
            cars: builtCars
        )
    }
}
