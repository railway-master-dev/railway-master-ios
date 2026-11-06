import Foundation

/// Synthesized one-shot and bed characters. PLACEHOLDER timbres inspired by publicly
/// described cab behavior, not manufacturer audio specs and not copied recordings.
///
/// Pages used only as qualitative notes:
/// - https://moribayashi80.tsuyushiba.com/Entry/15/ describes an early high induction tone
///   and a later lower one. This catalog keeps both as placeholders. The default VVVF
///   profile uses the lower tone. No pack audio is included.
/// - https://sigf.sakura.ne.jp/bve_sb2000.html describes when Seibu ATS buzzers fire
///   (start, pattern overspeed with emergency, a station-stop alarm, a speed-restriction alarm).
///   Those are timing notes. The buzzers here are original synthesis.
/// - https://sigf.sakura.ne.jp/bve_sb4000.html describes an early low-tone motor. Pitch stays
///   synthesized. https://sigf.sakura.ne.jp/bve.html allows naming the addon; other secondary
///   use of those addons needs prior consultation. No addon file is shipped.
public enum FictionalSynthesizedCue: String, CaseIterable, Equatable, Sendable {
    case departureMelodyNote
    case controllerStep
    case doorOpen
    case doorClose
    case doorWarning
    case whistleShort
    case whistleLong
    case atsAlert
    case atsConfirm
    case emergencyBrakeAlert
    case crossingBell
    case pneumaticBrakeRelease
    case brakeSqueal
    case pointClatter
    case railJoint
    case bridgeRumble
    case stationChime
    case inductionHigh
    case inductionLow
}

public enum FictionalCueWaveform: String, Equatable, Sendable {
    case electricHorn
    case buzzer
    case bell
    case click
    case air
    case squeal
}

public struct FictionalCueRecipe: Equatable, Sendable {
    public var cue: FictionalSynthesizedCue
    public var family: FictionalControlFamily
    public var dataStatus: String
    public var fundamentalHertz: Double
    public var partialRatio: Double
    public var durationSeconds: Double
    public var attackSeconds: Double
    public var releaseSeconds: Double
    public var pulseHertz: Double
    public var pulseDuty: Double
    public var noiseMix: Double
    public var waveform: FictionalCueWaveform

    public func replacingFundamental(_ hertz: Double) -> FictionalCueRecipe {
        var copy = self
        copy.fundamentalHertz = min(8_000, max(40, hertz))
        return copy
    }
}

/// Continuous beds already mixed by the host DSP. Numbers are PLACEHOLDER.
public struct FictionalContinuousLayers: Equatable, Sendable {
    public var family: FictionalControlFamily
    public var dataStatus: String
    public var motorPitchScale: Double
    public var inverterCarrierHertz: Double
    public var chopperHertz: Double
    public var compressorHertz: Double
    public var rollingBrightness: Double
    public var tunnelDamp: Double
    public var rainBedGain: Double
}

public enum FictionalCueCatalog {
    public static func recipe(_ cue: FictionalSynthesizedCue, family: FictionalControlFamily) -> FictionalCueRecipe {
        let door = FictionalCabAndSoundCatalog.doorTone(for: family)
        switch cue {
        case .departureMelodyNote:
            return make(cue, family, 740, 1.5, 0.24, 0.012, 0.08, 0, 0.5, 0.04, .bell)
        case .controllerStep:
            switch family {
            case .vvvf: return make(cue, family, 460, 2.4, 0.07, 0.002, 0.04, 0, 0.5, 0.35, .click)
            case .fieldChopper: return make(cue, family, 230, 1.8, 0.11, 0.003, 0.06, 0, 0.5, 0.52, .click)
            case .resistance: return make(cue, family, 155, 1.4, 0.15, 0.004, 0.08, 0, 0.5, 0.68, .click)
            }
        case .doorOpen:
            return make(cue, family, door.openHertz, 0.72, door.durationSeconds, 0.05, 0.18, 0, 0.5, 1 - door.motorWhirMix, .air)
        case .doorClose:
            return make(cue, family, door.closeHertz, 0.64, max(0.4, door.durationSeconds * 0.55), 0.04, 0.16, 0, 0.5, 1 - door.motorWhirMix, .air)
        case .doorWarning:
            switch family {
            case .vvvf: return make(cue, family, 1_280, 1.25, 0.42, 0.008, 0.06, 5.5, 0.42, 0.02, .bell)
            case .fieldChopper: return make(cue, family, 880, 1.2, 0.55, 0.01, 0.08, 4.2, 0.4, 0.04, .bell)
            case .resistance: return make(cue, family, 620, 1.15, 0.7, 0.012, 0.1, 3.1, 0.38, 0.06, .bell)
            }
        case .whistleShort:
            switch family {
            case .vvvf: return make(cue, family, 760, 0.84, 0.38, 0.02, 0.08, 0, 0.5, 0.02, .electricHorn)
            case .fieldChopper: return make(cue, family, 580, 0.81, 0.46, 0.025, 0.09, 0, 0.5, 0.03, .electricHorn)
            case .resistance: return make(cue, family, 470, 0.79, 0.52, 0.03, 0.1, 0, 0.5, 0.04, .electricHorn)
            }
        case .whistleLong:
            switch family {
            case .vvvf: return make(cue, family, 760, 0.84, 1.25, 0.03, 0.12, 0, 0.5, 0.02, .electricHorn)
            case .fieldChopper: return make(cue, family, 580, 0.81, 1.45, 0.035, 0.14, 0, 0.5, 0.03, .electricHorn)
            case .resistance: return make(cue, family, 470, 0.79, 1.6, 0.04, 0.16, 0, 0.5, 0.04, .electricHorn)
            }
        case .atsAlert:
            switch family {
            case .vvvf: return make(cue, family, 1_480, 1.51, 0.85, 0.004, 0.04, 6.4, 0.46, 0.08, .buzzer)
            case .fieldChopper: return make(cue, family, 420, 1.9, 1.15, 0.006, 0.05, 4.4, 0.5, 0.12, .buzzer)
            case .resistance: return make(cue, family, 300, 1.7, 1.05, 0.008, 0.06, 3.2, 0.48, 0.16, .buzzer)
            }
        case .atsConfirm:
            switch family {
            case .vvvf: return make(cue, family, 990, 1.33, 0.2, 0.004, 0.06, 0, 0.5, 0.02, .bell)
            case .fieldChopper: return make(cue, family, 510, 1.5, 0.16, 0.003, 0.05, 0, 0.5, 0.1, .buzzer)
            case .resistance: return make(cue, family, 340, 1.4, 0.22, 0.004, 0.07, 0, 0.5, 0.18, .bell)
            }
        case .emergencyBrakeAlert:
            switch family {
            case .vvvf: return make(cue, family, 1_760, 1.62, 1.55, 0.003, 0.05, 9.0, 0.4, 0.1, .buzzer)
            case .fieldChopper: return make(cue, family, 360, 2.05, 1.75, 0.004, 0.06, 7.5, 0.45, 0.14, .buzzer)
            case .resistance: return make(cue, family, 240, 1.85, 1.65, 0.005, 0.07, 6.0, 0.42, 0.18, .buzzer)
            }
        case .crossingBell:
            return make(cue, family, 1_680, 2.02, 1.35, 0.006, 0.08, 2.6, 0.35, 0.05, .bell)
        case .pneumaticBrakeRelease:
            switch family {
            case .vvvf: return make(cue, family, 190, 0.5, 0.42, 0.01, 0.22, 0, 0.5, 0.82, .air)
            case .fieldChopper: return make(cue, family, 140, 0.45, 0.58, 0.015, 0.28, 0, 0.5, 0.86, .air)
            case .resistance: return make(cue, family, 105, 0.4, 0.74, 0.02, 0.34, 0, 0.5, 0.9, .air)
            }
        case .brakeSqueal:
            switch family {
            case .vvvf: return make(cue, family, 2_150, 1.07, 0.36, 0.02, 0.1, 0, 0.5, 0.22, .squeal)
            case .fieldChopper: return make(cue, family, 1_820, 1.05, 0.48, 0.03, 0.12, 0, 0.5, 0.28, .squeal)
            case .resistance: return make(cue, family, 1_460, 1.04, 0.62, 0.04, 0.16, 0, 0.5, 0.34, .squeal)
            }
        case .pointClatter:
            // Frog hit plus a short points rumble. Longer and rougher than a rail joint.
            return make(cue, family, 210, 2.7, 0.46, 0.003, 0.14, 13, 0.22, 0.84, .air)
        case .railJoint:
            return make(cue, family, 1_720, 2.4, 0.046, 0.001, 0.02, 0, 0.5, 0.48, .click)
        case .bridgeRumble:
            return make(cue, family, 78, 1.9, 0.9, 0.04, 0.35, 0, 0.5, 0.92, .air)
        case .stationChime:
            return make(cue, family, 1_240, 1.26, 0.62, 0.01, 0.2, 0, 0.5, 0.03, .bell)
        case .inductionHigh:
            return make(cue, family, 2_480, 2.0, 0.32, 0.01, 0.08, 0, 0.5, 0.01, .bell)
        case .inductionLow:
            return make(cue, family, 860, 2.0, 0.4, 0.015, 0.1, 0, 0.5, 0.01, .bell)
        }
    }

    public static func continuousLayers(for family: FictionalControlFamily) -> FictionalContinuousLayers {
        let tone = FictionalCabAndSoundCatalog.tractionTone(for: family)
        switch family {
        case .vvvf:
            return FictionalContinuousLayers(family: family, dataStatus: "PLACEHOLDER", motorPitchScale: tone.motorPitchScale, inverterCarrierHertz: tone.carrierHertz, chopperHertz: 0, compressorHertz: 2.4, rollingBrightness: 0.85, tunnelDamp: 0.62, rainBedGain: 1)
        case .fieldChopper:
            return FictionalContinuousLayers(family: family, dataStatus: "PLACEHOLDER", motorPitchScale: tone.motorPitchScale, inverterCarrierHertz: 0, chopperHertz: tone.chopperHertz, compressorHertz: 1.5, rollingBrightness: 1, tunnelDamp: 0.7, rainBedGain: 1.05)
        case .resistance:
            return FictionalContinuousLayers(family: family, dataStatus: "PLACEHOLDER", motorPitchScale: tone.motorPitchScale, inverterCarrierHertz: 0, chopperHertz: 0, compressorHertz: 0.85, rollingBrightness: 1.15, tunnelDamp: 0.78, rainBedGain: 1.1)
        }
    }

    /// Renders one cue without AVAudioEngine. Used to prove the families differ.
    public static func renderPreview(_ recipe: FictionalCueRecipe, sampleRate: Float = 8_000, maxSeconds: Float = 2) -> [Float] {
        var renderer = FictionalCueRenderer(seed: 0xA11D)
        var samples: [Float] = []
        let limit = Int(max(sampleRate, 1) * min(maxSeconds, Float(recipe.durationSeconds) + 0.05))
        samples.reserveCapacity(limit)
        for _ in 0..<limit {
            let sample = renderer.sample(recipe: recipe, sampleRate: sampleRate)
            samples.append(sample)
            if !renderer.active { break }
        }
        return samples
    }

    private static func make(
        _ cue: FictionalSynthesizedCue,
        _ family: FictionalControlFamily,
        _ fundamental: Double,
        _ partial: Double,
        _ duration: Double,
        _ attack: Double,
        _ release: Double,
        _ pulse: Double,
        _ duty: Double,
        _ noise: Double,
        _ waveform: FictionalCueWaveform
    ) -> FictionalCueRecipe {
        FictionalCueRecipe(
            cue: cue,
            family: family,
            dataStatus: "PLACEHOLDER",
            fundamentalHertz: fundamental,
            partialRatio: partial,
            durationSeconds: duration,
            attackSeconds: attack,
            releaseSeconds: release,
            pulseHertz: pulse,
            pulseDuty: duty,
            noiseMix: noise,
            waveform: waveform
        )
    }
}

public struct FictionalCueRenderer: Equatable, Sendable {
    public var phase: Float = 0
    public var phase2: Float = 0
    public var age: Float = 0
    public var noise: UInt32
    public var active = true

    public init(seed: UInt32) {
        noise = seed == 0 ? 1 : seed
    }

    public mutating func sample(recipe: FictionalCueRecipe, sampleRate: Float) -> Float {
        guard active, sampleRate > 1 else { return 0 }
        let duration = max(0.02, Float(recipe.durationSeconds))
        let attack = min(1, age / max(0.001, Float(recipe.attackSeconds)))
        let releaseWindow = max(0.001, Float(recipe.releaseSeconds))
        let releaseStart = max(0, duration - releaseWindow)
        let release = age < releaseStart ? 1 : max(0, 1 - (age - releaseStart) / releaseWindow)
        var gate: Float = 1
        if recipe.pulseHertz > 0.05 {
            let cycle = age * Float(recipe.pulseHertz)
            let fraction = cycle - floor(cycle)
            gate = fraction < Float(recipe.pulseDuty) ? 1 : 0.12
        }
        let fundamental = sin(phase)
        let partial = sin(phase2)
        let hashed = nextNoise()
        let tone: Float
        switch recipe.waveform {
        case .electricHorn:
            tone = fundamental * 0.58 + partial * 0.42
        case .buzzer:
            let square: Float = fundamental >= 0 ? 0.85 : -0.85
            tone = square * 0.72 + partial * 0.28
        case .bell:
            tone = fundamental * 0.74 + partial * 0.26
        case .click:
            tone = hashed * 0.7 + fundamental * 0.3
        case .air:
            tone = hashed * 0.82 + fundamental * 0.18
        case .squeal:
            tone = fundamental * 0.78 + hashed * 0.22
        }
        let mix = Float(min(1, max(0, recipe.noiseMix)))
        let value = tone * (1 - mix) + hashed * mix
        let tau: Float = 6.283185307179586
        let step = tau / sampleRate
        phase = wrap(phase + step * Float(recipe.fundamentalHertz), tau: tau)
        phase2 = wrap(phase2 + step * Float(recipe.fundamentalHertz * recipe.partialRatio), tau: tau)
        age += 1 / sampleRate
        if age >= duration { active = false }
        return value * attack * release * gate
    }

    private mutating func nextNoise() -> Float {
        noise = 1_664_525 &* noise &+ 1_013_904_223
        let unit = Float(noise >> 8) / Float(0x00FF_FFFF)
        return unit * 2 - 1
    }

    private func wrap(_ phase: Float, tau: Float) -> Float {
        var value = phase
        if value > tau { value -= tau }
        if value < 0 { value += tau }
        return value
    }
}
