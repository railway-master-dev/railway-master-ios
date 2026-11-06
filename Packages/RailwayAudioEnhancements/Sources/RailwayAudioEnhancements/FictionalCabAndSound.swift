import Foundation

/// Three fictional control families. Named series below are appearance notes only.
/// They are not licensed reproductions and do not carry verified performance data.
public enum FictionalControlFamily: String, Codable, CaseIterable, Equatable, Sendable {
    case vvvf
    case fieldChopper
    case resistance
}

public enum FictionalMasterGrip: String, Codable, Equatable, Sendable {
    case darkCombined
    case woodBrown
    case markedReverseAndOff
}

public enum FictionalBrakeGrip: String, Codable, Equatable, Sendable {
    case combinedWithMaster
    case sphere
}

/// Layout, color, and control-shape data for a procedural cab. No photographs.
public struct FictionalCabDesk: Equatable, Sendable {
    public let family: FictionalControlFamily
    public let dataStatus: String
    public let inspirationNote: String
    public let deskRed: Double
    public let deskGreen: Double
    public let deskBlue: Double
    public let oneHandleMasterBrake: Bool
    public let masterGrip: FictionalMasterGrip
    public let brakeGrip: FictionalBrakeGrip
    public let analogGaugeCount: Int
    public let hasCenterMonitor: Bool
    public let hasRightStatusScreen: Bool
    public let hasRightKeypad: Bool
    public let hasRightHandset: Bool
    public let verticalAmberIndicators: Bool
    public let blueSwitchLabels: Bool
    public let centerSwitchBank: Bool
    public let fictionalCarNumber: String
    public let dashboardCaption: String?
    public let doorLampCaption: String?
    public let masterMarkings: [String]
    /// Names only. The chopper page lists these lamps. Empty means that desk does not claim them.
    public let indicatorCaptions: [String]

    public init(
        family: FictionalControlFamily,
        inspirationNote: String,
        deskRed: Double,
        deskGreen: Double,
        deskBlue: Double,
        oneHandleMasterBrake: Bool,
        masterGrip: FictionalMasterGrip,
        brakeGrip: FictionalBrakeGrip,
        analogGaugeCount: Int,
        hasCenterMonitor: Bool,
        hasRightStatusScreen: Bool,
        hasRightKeypad: Bool,
        hasRightHandset: Bool,
        verticalAmberIndicators: Bool,
        blueSwitchLabels: Bool,
        centerSwitchBank: Bool,
        fictionalCarNumber: String,
        dashboardCaption: String?,
        doorLampCaption: String?,
        masterMarkings: [String],
        indicatorCaptions: [String] = []
    ) {
        self.family = family
        self.dataStatus = "PLACEHOLDER"
        self.inspirationNote = inspirationNote
        self.deskRed = deskRed
        self.deskGreen = deskGreen
        self.deskBlue = deskBlue
        self.oneHandleMasterBrake = oneHandleMasterBrake
        self.masterGrip = masterGrip
        self.brakeGrip = brakeGrip
        self.analogGaugeCount = analogGaugeCount
        self.hasCenterMonitor = hasCenterMonitor
        self.hasRightStatusScreen = hasRightStatusScreen
        self.hasRightKeypad = hasRightKeypad
        self.hasRightHandset = hasRightHandset
        self.verticalAmberIndicators = verticalAmberIndicators
        self.blueSwitchLabels = blueSwitchLabels
        self.centerSwitchBank = centerSwitchBank
        self.fictionalCarNumber = fictionalCarNumber
        self.dashboardCaption = dashboardCaption
        self.doorLampCaption = doorLampCaption
        self.masterMarkings = masterMarkings
        self.indicatorCaptions = indicatorCaptions
    }
}

/// Original synthesized motor character. Not a recording of any real train.
public struct FictionalTractionTone: Equatable, Sendable {
    public let family: FictionalControlFamily
    public let usesInverterCarrier: Bool
    public let usesChopperRipple: Bool
    public let usesCamshaftSteps: Bool
    public let carrierHertz: Double
    public let chopperHertz: Double
    public let secondHarmonicRatio: Double
    /// Scales the synthesized motor pitch. Resistance uses a lower value for the page's early low tone.
    public let motorPitchScale: Double
    public let dataStatus: String

    public init(family: FictionalControlFamily, usesInverterCarrier: Bool, usesChopperRipple: Bool, usesCamshaftSteps: Bool, carrierHertz: Double, chopperHertz: Double, secondHarmonicRatio: Double, motorPitchScale: Double = 1) {
        self.family = family
        self.usesInverterCarrier = usesInverterCarrier
        self.usesChopperRipple = usesChopperRipple
        self.usesCamshaftSteps = usesCamshaftSteps
        self.carrierHertz = carrierHertz
        self.chopperHertz = chopperHertz
        self.secondHarmonicRatio = secondHarmonicRatio
        self.motorPitchScale = motorPitchScale
        self.dataStatus = "PLACEHOLDER"
    }
}

/// Original door-motor character. Not a recording of a real door engine.
public struct FictionalDoorTone: Equatable, Sendable {
    public let family: FictionalControlFamily
    public let openHertz: Double
    public let closeHertz: Double
    public let durationSeconds: Double
    public let motorWhirMix: Double
    public let dataStatus: String

    public init(family: FictionalControlFamily, openHertz: Double, closeHertz: Double, durationSeconds: Double, motorWhirMix: Double) {
        self.family = family
        self.openHertz = openHertz
        self.closeHertz = closeHertz
        self.durationSeconds = durationSeconds
        self.motorWhirMix = motorWhirMix
        self.dataStatus = "PLACEHOLDER"
    }
}

public enum FictionalCabAndSoundCatalog {
    public static let vvvf = FictionalCabDesk(
        family: .vvvf,
        inspirationNote: "PLACEHOLDER fictional desk inspired by the public appearance of a modern one-handle VVVF cab (東武50000系の見た目を参考)。ライセンス再現ではない。",
        deskRed: 0.30, deskGreen: 0.32, deskBlue: 0.34,
        oneHandleMasterBrake: true,
        masterGrip: .darkCombined,
        brakeGrip: .combinedWithMaster,
        analogGaugeCount: 2,
        hasCenterMonitor: true,
        hasRightStatusScreen: true,
        hasRightKeypad: false,
        hasRightHandset: true,
        verticalAmberIndicators: false,
        blueSwitchLabels: false,
        centerSwitchBank: false,
        fictionalCarNumber: "T-VVVF",
        dashboardCaption: nil,
        doorLampCaption: nil,
        masterMarkings: []
    )

    public static let fieldChopper = FictionalCabDesk(
        family: .fieldChopper,
        inspirationNote: "PLACEHOLDER fictional desk. 灯の名前だけ https://sigf.sakura.ne.jp/bve_sb2000.html の記述（直列/並列/最終/界磁弱メ/回生制動）。パネル画像やプラグインは不使用。車号2007の複製ではない。",
        deskRed: 0.56, deskGreen: 0.74, deskBlue: 0.64,
        oneHandleMasterBrake: false,
        masterGrip: .woodBrown,
        brakeGrip: .sphere,
        analogGaugeCount: 2,
        hasCenterMonitor: false,
        hasRightStatusScreen: true,
        hasRightKeypad: true,
        hasRightHandset: false,
        verticalAmberIndicators: true,
        blueSwitchLabels: true,
        centerSwitchBank: false,
        fictionalCarNumber: "T-01",
        dashboardCaption: nil,
        doorLampCaption: nil,
        masterMarkings: [],
        indicatorCaptions: ["直列", "並列", "最終", "界磁弱メ", "回生制動"]
    )

    public static let resistance = FictionalCabDesk(
        family: .resistance,
        inspirationNote: "PLACEHOLDER fictional desk. https://sigf.sakura.ne.jp/bve_sb4000.html は直列/並列/最終灯の再現を見送り、前期型を低音と書いている。灯は置かず、低音は合成のみ。車号4001の複製ではない。",
        deskRed: 0.58, deskGreen: 0.73, deskBlue: 0.60,
        oneHandleMasterBrake: false,
        masterGrip: .markedReverseAndOff,
        brakeGrip: .sphere,
        analogGaugeCount: 3,
        hasCenterMonitor: false,
        hasRightStatusScreen: false,
        hasRightKeypad: false,
        hasRightHandset: false,
        verticalAmberIndicators: false,
        blueSwitchLabels: true,
        centerSwitchBank: true,
        fictionalCarNumber: "T-02",
        dashboardCaption: "SIV",
        doorLampCaption: "戸閉",
        masterMarkings: ["後", "切"]
    )

    public static func desk(for family: FictionalControlFamily) -> FictionalCabDesk {
        switch family {
        case .vvvf: return vvvf
        case .fieldChopper: return fieldChopper
        case .resistance: return resistance
        }
    }

    public static func family(forProfileID profileID: String) -> FictionalControlFamily {
        switch profileID {
        case "rheostaticDC": return .resistance
        case "fieldChopperDC": return .fieldChopper
        default: return .vvvf
        }
    }

    public static func tractionTone(for family: FictionalControlFamily) -> FictionalTractionTone {
        switch family {
        case .vvvf:
            return FictionalTractionTone(family: family, usesInverterCarrier: true, usesChopperRipple: false, usesCamshaftSteps: false, carrierHertz: 2_800, chopperHertz: 0, secondHarmonicRatio: 1.52, motorPitchScale: 1)
        case .fieldChopper:
            return FictionalTractionTone(family: family, usesInverterCarrier: false, usesChopperRipple: true, usesCamshaftSteps: false, carrierHertz: 0, chopperHertz: 220, secondHarmonicRatio: 2.28, motorPitchScale: 1)
        case .resistance:
            return FictionalTractionTone(family: family, usesInverterCarrier: false, usesChopperRipple: false, usesCamshaftSteps: true, carrierHertz: 0, chopperHertz: 0, secondHarmonicRatio: 2.05, motorPitchScale: 0.62)
        }
    }

    public static func doorTone(for family: FictionalControlFamily) -> FictionalDoorTone {
        switch family {
        case .vvvf:
            return FictionalDoorTone(family: family, openHertz: 460, closeHertz: 390, durationSeconds: 1.05, motorWhirMix: 0.72)
        case .fieldChopper:
            return FictionalDoorTone(family: family, openHertz: 280, closeHertz: 240, durationSeconds: 1.55, motorWhirMix: 0.48)
        case .resistance:
            return FictionalDoorTone(family: family, openHertz: 170, closeHertz: 140, durationSeconds: 2.15, motorWhirMix: 0.28)
        }
    }
}
