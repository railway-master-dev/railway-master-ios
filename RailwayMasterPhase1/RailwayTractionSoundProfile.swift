import Foundation

/// 駆動方式ごとに手続き合成の音色・変調則を切り替えるプロファイル。
/// 全プリセットはオリジナルの近似合成で、特定形式・車両の実測音を意味しません。
public enum RailwayTractionSoundProfile: String, CaseIterable, Codable, Sendable, Equatable {
    /// 直流電動機＋抵抗器・カム接触器を想定した段階的な近似音。
    case rheostaticDC
    /// 直流電動機＋界磁制御チョッパのリップルを加えた近似音。
    case fieldChopperDC
    /// GTOインバーターの低めのキャリア／速度連動パルス段を想定。
    case vvvfGTO
    /// IGBTインバーターの高めのキャリア音を想定。
    case vvvfIGBT
    /// IGBTの周期的キャリア変調を想定した、揺らぎと粗さのある近似音。
    case vvvfIGBTVariableCarrier
    /// SiCインバーターの高域寄りで滑らかな音色を想定した汎用近似。
    case vvvfSiC

    public var displayName: String {
        switch self {
        case .rheostaticDC: return "抵抗制御 DC（合成近似）"
        case .fieldChopperDC: return "界磁チョッパ DC（合成近似）"
        case .vvvfGTO: return "VVVF GTO（合成近似）"
        case .vvvfIGBT: return "VVVF IGBT（合成近似）"
        case .vvvfIGBTVariableCarrier: return "VVVF IGBT 可変キャリア（合成近似）"
        case .vvvfSiC: return "VVVF SiC（汎用合成近似）"
        }
    }

    public var isDCControl: Bool {
        self == .rheostaticDC || self == .fieldChopperDC
    }

    /// One-handle and two-handle masters both click. The cue catalog picks the timbre.
    var generatesControllerStepSounds: Bool { true }
}
