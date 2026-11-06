import Foundation

/// RailwayAudioの制御プロファイルと対応する、説明用の仮想合成モード。
/// 特定車両の録音・実測スペクトル・メーカー固有PWM波形を意味しません。
public enum TractionControlMode: String, CaseIterable, Codable, Hashable, Sendable {
    case rheostaticDC
    case fieldChopperDC
    case vvvfGTO
    case vvvfIGBT
    case vvvfIGBTVariableCarrier
    case vvvfSiC

    public var representationLabel: String {
        "CONCEPTUAL / VIRTUAL — synthesized signature, not an authentic train sound"
    }
}

/// 合成制御シグネチャ用の正規化された状態。
public struct ControlSignalState: Codable, Hashable, Sendable {
    public var speedMetersPerSecond: Double
    public var motorRPM: Double
    public var tractionLoad: Double
    public var accelerationMetersPerSecondSquared: Double
    public var powerNotch: Int
    public var fieldWeakeningRatio: Double
    public var regenerativeBrakeRatio: Double

    public init(
        speedMetersPerSecond: Double = 0,
        motorRPM: Double = 0,
        tractionLoad: Double = 0,
        accelerationMetersPerSecondSquared: Double = 0,
        powerNotch: Int = 0,
        fieldWeakeningRatio: Double = 0,
        regenerativeBrakeRatio: Double = 0
    ) {
        self.speedMetersPerSecond = Self.clamp(speedMetersPerSecond, 0, 120)
        self.motorRPM = Self.clamp(motorRPM, 0, 12_000)
        self.tractionLoad = Self.clamp(tractionLoad, 0, 1)
        self.accelerationMetersPerSecondSquared = Self.clamp(accelerationMetersPerSecondSquared, -8, 8)
        self.powerNotch = min(12, max(0, powerNotch))
        self.fieldWeakeningRatio = Self.clamp(fieldWeakeningRatio, 0, 1)
        self.regenerativeBrakeRatio = Self.clamp(regenerativeBrakeRatio, 0, 1)
    }

    private static func clamp(_ value: Double, _ lower: Double, _ upper: Double) -> Double {
        guard value.isFinite else { return 0 }
        return min(upper, max(lower, value))
    }
}

/// 純粋・決定的なモノラルFloat PCMシンセサイザー。サンプル再生素材は使いません。
public enum ControlModeSignatureRenderer {
    /// sampleOffsetを指定すれば、同じ状態・範囲の再描画結果はビット単位で再現可能です。
    public static func render(
        mode: TractionControlMode,
        state: ControlSignalState,
        frameCount: Int,
        sampleRate: Double,
        sampleOffset: UInt64 = 0
    ) -> [Float] {
        guard frameCount > 0, sampleRate.isFinite, sampleRate > 0 else { return [] }

        // Codable入力や後から変更された値も、合成に入る直前に必ず再正規化します。
        let safeState = ControlSignalState(
            speedMetersPerSecond: state.speedMetersPerSecond,
            motorRPM: state.motorRPM,
            tractionLoad: state.tractionLoad,
            accelerationMetersPerSecondSquared: state.accelerationMetersPerSecondSquared,
            powerNotch: state.powerNotch,
            fieldWeakeningRatio: state.fieldWeakeningRatio,
            regenerativeBrakeRatio: state.regenerativeBrakeRatio
        )
        let speed = safeState.speedMetersPerSecond
        let load = max(safeState.tractionLoad, safeState.regenerativeBrakeRatio * 0.55)
        let motorFrequency: Double
        switch mode {
        case .rheostaticDC, .fieldChopperDC:
            motorFrequency = min(700, max(22, 24 + speed * 3.5 + safeState.motorRPM * 0.045 + Double(safeState.powerNotch) * 4 + safeState.fieldWeakeningRatio * 38))
        case .vvvfGTO, .vvvfIGBT, .vvvfIGBTVariableCarrier, .vvvfSiC:
            motorFrequency = min(1_400, max(24, 28 + safeState.motorRPM * 0.115 + abs(safeState.accelerationMetersPerSecondSquared) * 9))
        }

        let carrierFrequency: Double
        switch mode {
        case .rheostaticDC, .fieldChopperDC:
            carrierFrequency = 0
        case .vvvfGTO:
            let pulseStage = speed < 12 ? 2.0 : (speed < 28 ? 3.0 : (speed < 50 ? 4.0 : 5.0))
            carrierFrequency = speed < 12 ? 930 + speed * 5 : min(3_200, motorFrequency * 6 * pulseStage)
        case .vvvfIGBT:
            carrierFrequency = min(5_000, 2_750 + speed * 17)
        case .vvvfIGBTVariableCarrier:
            carrierFrequency = min(4_600, 2_500 + speed * 15)
        case .vvvfSiC:
            carrierFrequency = min(8_000, 4_200 + speed * 20)
        }

        let baseAmplitude = 0.012 + 0.052 * load + 0.018 * min(1, speed / 34)
        var output = [Float](repeating: 0, count: frameCount)
        for index in 0..<frameCount {
            let absoluteSample = sampleOffset &+ UInt64(index)
            let time = Double(absoluteSample) / sampleRate
            let motorPhase = 2 * Double.pi * motorFrequency * time
            let motor: Double
            switch mode {
            case .rheostaticDC:
                motor = sin(motorPhase) * 0.62 + sin(motorPhase * 2.05) * 0.25 + sin(motorPhase * 3.35) * 0.13
            case .fieldChopperDC:
                let dc = sin(motorPhase) * 0.64 + sin(motorPhase * 2.28) * 0.25 + sin(motorPhase * 3.2) * 0.11
                let chop = sin(2 * Double.pi * (180 + safeState.fieldWeakeningRatio * 240) * time)
                motor = dc + chop * (0.10 + safeState.fieldWeakeningRatio * 0.22)
            case .vvvfGTO:
                let pulse = sin(2 * Double.pi * carrierFrequency * time)
                let quantizedPulse = pulse >= 0 ? 1.0 : -1.0
                motor = (sin(motorPhase) * 0.68 + sin(motorPhase * 1.52) * 0.32) + quantizedPulse * 0.14 * load
            case .vvvfIGBT:
                let carrier = sin(2 * Double.pi * carrierFrequency * time)
                motor = (sin(motorPhase) * 0.68 + sin(motorPhase * 1.52) * 0.32) + carrier * 0.10 * load
            case .vvvfIGBTVariableCarrier:
                let modulationRate = 0.7 + speed * 0.018
                let modulationIndex = 0.16
                let phase = 2 * Double.pi * (carrierFrequency * time + modulationIndex * sin(2 * Double.pi * modulationRate * time))
                let carrier = sin(phase)
                motor = (sin(motorPhase) * 0.68 + sin(motorPhase * 1.52) * 0.32) + carrier * 0.10 * load
            case .vvvfSiC:
                let carrier = sin(2 * Double.pi * carrierFrequency * time)
                let sideband = sin(2 * Double.pi * (carrierFrequency * 0.5) * time + motorPhase * 0.08)
                motor = (sin(motorPhase) * 0.70 + sin(motorPhase * 1.48) * 0.30) + carrier * 0.075 * load + sideband * 0.012 * load
            }
            let regen = sin(2 * Double.pi * min(1_600, max(55, 70 + speed * 10.5 + safeState.motorRPM * 0.018)) * time) * safeState.regenerativeBrakeRatio * 0.035
            let sample = (motor * baseAmplitude) + regen
            output[index] = Float(min(0.90, max(-0.90, sample)))
        }
        return output
    }
}
