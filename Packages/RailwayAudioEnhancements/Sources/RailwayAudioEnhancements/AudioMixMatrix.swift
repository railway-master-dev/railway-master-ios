import Foundation

public enum AcousticScene: String, CaseIterable, Codable, Hashable, Sendable {
    case cabInterior
    case exterior
    case station
    case tunnel
}

/// 各バスの出力ゲインと簡易空間処理の推奨値。実際の処理はホストのオーディオグラフで行います。
public struct AudioMixParameters: Equatable, Sendable {
    public var gain: Float
    public var reverbSend: Float
    public var lowPassCutoffHz: Float
    public var stereoWidth: Float

    public init(gain: Float, reverbSend: Float, lowPassCutoffHz: Float, stereoWidth: Float) {
        self.gain = gain
        self.reverbSend = reverbSend
        self.lowPassCutoffHz = lowPassCutoffHz
        self.stereoWidth = stereoWidth
    }
}

public enum AudioMixMatrix {
    /// 0...1のmaster gainとシーン／バスから、ホストのミキサー用係数を返します。
    public static func parameters(for bus: AudioBus, in scene: AcousticScene, masterGain: Float = 1) -> AudioMixParameters {
        let master = masterGain.isFinite ? min(1, max(0, masterGain)) : 0
        let sceneGain: Float
        switch (scene, bus) {
        case (.cabInterior, .cabInterior): sceneGain = 0.86
        case (.cabInterior, .onboardAnnouncement): sceneGain = 1.00
        case (.cabInterior, .stationPublicAddress): sceneGain = 0.04
        case (.cabInterior, .exterior): sceneGain = 0.30
        case (.cabInterior, .tunnelReflection): sceneGain = 0.10
        case (.cabInterior, .effects): sceneGain = 0.76

        case (.exterior, .cabInterior): sceneGain = 0.12
        case (.exterior, .onboardAnnouncement): sceneGain = 0.08
        case (.exterior, .stationPublicAddress): sceneGain = 0.48
        case (.exterior, .exterior): sceneGain = 0.92
        case (.exterior, .tunnelReflection): sceneGain = 0.05
        case (.exterior, .effects): sceneGain = 0.78

        case (.station, .cabInterior): sceneGain = 0.05
        case (.station, .onboardAnnouncement): sceneGain = 0.28
        case (.station, .stationPublicAddress): sceneGain = 1.00
        case (.station, .exterior): sceneGain = 0.38
        case (.station, .tunnelReflection): sceneGain = 0.02
        case (.station, .effects): sceneGain = 0.82

        case (.tunnel, .cabInterior): sceneGain = 0.74
        case (.tunnel, .onboardAnnouncement): sceneGain = 0.84
        case (.tunnel, .stationPublicAddress): sceneGain = 0.03
        case (.tunnel, .exterior): sceneGain = 0.64
        case (.tunnel, .tunnelReflection): sceneGain = 0.58
        case (.tunnel, .effects): sceneGain = 0.72
        }

        let reverb: Float
        let cutoff: Float
        switch scene {
        case .cabInterior:
            reverb = bus == .onboardAnnouncement ? 0.04 : 0.08
            cutoff = 16_000
        case .exterior:
            reverb = bus == .exterior ? 0.18 : 0.06
            cutoff = 18_000
        case .station:
            reverb = bus == .stationPublicAddress ? 0.22 : 0.12
            cutoff = 10_000
        case .tunnel:
            reverb = bus == .tunnelReflection ? 0.62 : 0.38
            cutoff = 4_800
        }
        let width: Float = (bus == .cabInterior || bus == .onboardAnnouncement) ? 0.45 : 1.0
        return AudioMixParameters(
            gain: min(1, max(0, sceneGain * master)),
            reverbSend: reverb,
            lowPassCutoffHz: cutoff,
            stereoWidth: width
        )
    }
}
