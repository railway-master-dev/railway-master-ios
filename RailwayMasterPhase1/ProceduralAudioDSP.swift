import Foundation
import RailwayAudioEnhancements

private struct AudioControlState {
    var snapshot = RailwaySimulationSnapshot()
    var settings = RailwayAudioSettings()
    var speechActive = false
}

private struct ProceduralVoice {
    var active = false
    var priority = 0
    var pan: Float = 0
    var amplitude: Float = 0.2
    var recipe = FictionalCueCatalog.recipe(.stationChime, family: .vvvf)
    var renderer = FictionalCueRenderer(seed: 1)
}

/// 手続き生成のステレオ音源。固定長ボイス／イベント領域を使い、PCMバッファごとに制御値を一度だけ取得します。
/// 実際の車両録音を含まず、生成音はVVVF様・軌道様の演出音です。
public final class ProceduralAudioDSP: @unchecked Sendable {
    private let controlLock = NSLock()
    private var control = AudioControlState()
    private var pendingEvents = [RailwayAudioEvent?](repeating: nil, count: 128)
    private var droppedEvents = 0
    private var previousPowerNotch: Int?
    private var previousTractionProfile: RailwayTractionSoundProfile?
    private var previousBrakeState: Bool?
    private var voices = [ProceduralVoice](repeating: ProceduralVoice(), count: 32)

    private var enginePhase: Float = 0
    private var enginePhase2: Float = 0
    private var inverterPhase: Float = 0
    private var inverterModulationPhase: Float = 0
    private var chopperPhase: Float = 0
    private var regenPhase: Float = 0
    private var curvePhase: Float = 0
    private var railLowPass: Float = 0
    private var windLowPass: Float = 0
    private var occlusionLowPass: Float = 0
    private var jointPulse: Float = 0
    private var compressorPhase: Float = 0
    private var randomState: UInt32 = 0xC001_D00D
    private var renderDistanceMeters: Double?

    public init() {}

    public var droppedEventCount: Int {
        controlLock.lock()
        defer { controlLock.unlock() }
        return droppedEvents
    }

    public func update(snapshot: RailwaySimulationSnapshot, settings: RailwayAudioSettings) {
        controlLock.lock()
        let profile = settings.tractionSoundProfile
        let notch = min(12, max(0, snapshot.powerNotch))
        if previousTractionProfile == profile,
           profile.generatesControllerStepSounds,
           let previousPowerNotch,
           previousPowerNotch != notch {
            let delta = abs(notch - previousPowerNotch)
            let stepsToRender = min(6, delta)
            let eventTime = snapshot.simulationTime.isFinite ? snapshot.simulationTime : 0
            let family = FictionalCabAndSoundCatalog.family(forProfileID: profile.rawValue)
            let click = FictionalCueCatalog.recipe(.controllerStep, family: family)
            for step in 0..<stepsToRender {
                let event = RailwayAudioEvent(
                    id: "controller-step-\(Int(eventTime * 1_000))-\(previousPowerNotch)-\(notch)-\(step)",
                    kind: .controllerStep,
                    scheduledTime: eventTime + Double(step) * 0.02,
                    duration: click.durationSeconds,
                    intensity: 0.36 + Float(min(4, delta)) * 0.035,
                    frequencyHz: Float(click.fundamentalHertz * (1 + 0.03 * Double(step))),
                    priority: 4,
                    position: snapshot.trainPosition
                )
                _ = enqueueLocked(event)
            }
            if previousPowerNotch == 0, notch > 0, family == .vvvf {
                let event = RailwayAudioEvent(
                    id: "induction-\(Int(eventTime * 1_000))-\(notch)",
                    kind: .inductionTone,
                    scheduledTime: eventTime,
                    duration: 0.4,
                    intensity: 0.34,
                    frequencyHz: nil,
                    priority: 5,
                    position: snapshot.trainPosition
                )
                _ = enqueueLocked(event)
            }
        }
        let brakeCommand = snapshot.brakeCommand.isFinite ? min(1, max(0, snapshot.brakeCommand)) : 0
        let braking = previousBrakeState.map { $0 ? brakeCommand > 0.08 : brakeCommand >= 0.18 } ?? (brakeCommand >= 0.18)
        if let wasBraking = previousBrakeState, wasBraking != braking {
            let eventTime = snapshot.simulationTime.isFinite ? snapshot.simulationTime : 0
            let family = FictionalCabAndSoundCatalog.family(forProfileID: profile.rawValue)
            let brakeCue = FictionalCueCatalog.recipe(braking ? .brakeSqueal : .pneumaticBrakeRelease, family: family)
            let event = RailwayAudioEvent(
                id: "brake-transition-\(Int(eventTime * 1_000))-\(braking ? "engage" : "release")",
                kind: braking ? .brakeSqueal : .pneumaticBrakeRelease,
                scheduledTime: eventTime,
                duration: brakeCue.durationSeconds,
                intensity: braking ? min(0.62, 0.28 + brakeCommand * 0.34) : 0.38,
                frequencyHz: nil,
                priority: 4,
                position: snapshot.trainPosition
            )
            _ = enqueueLocked(event)
        }
        previousBrakeState = braking
        previousPowerNotch = notch
        previousTractionProfile = profile
        control.snapshot = snapshot
        control.settings = settings
        controlLock.unlock()
    }

    /// 外部シミュレーションの発報条件で作られた効果音要求を投入します。
    /// 満杯時はより優先度の低い保留イベントを置き換え、高優先度イベントを優先します。
    @discardableResult
    public func enqueue(_ event: RailwayAudioEvent) -> Bool {
        controlLock.lock()
        defer { controlLock.unlock() }
        return enqueueLocked(event)
    }

    private func enqueueLocked(_ event: RailwayAudioEvent) -> Bool {
        if let free = pendingEvents.firstIndex(where: { $0 == nil }) {
            pendingEvents[free] = event
            return true
        }
        guard let lowest = pendingEvents.indices.min(by: {
            (pendingEvents[$0]?.priority ?? Int.max) < (pendingEvents[$1]?.priority ?? Int.max)
        }), let queued = pendingEvents[lowest], event.priority > queued.priority else {
            droppedEvents += 1
            return false
        }
        pendingEvents[lowest] = event
        droppedEvents += 1
        return true
    }

    public func setSpeechActive(_ active: Bool) {
        controlLock.lock()
        control.speechActive = active
        controlLock.unlock()
    }

    /// AVAudioSourceNode向けのリアルタイムPCM描画。left/rightはframeCount以上の領域であること。
    public func render(
        frameCount: Int,
        sampleRate: Float,
        left: UnsafeMutablePointer<Float>,
        right: UnsafeMutablePointer<Float>
    ) {
        guard frameCount > 0, sampleRate > 0 else { return }
        controlLock.lock()
        let current = control
        let now = current.snapshot.simulationTime.isFinite ? current.snapshot.simulationTime : 0
        for index in pendingEvents.indices {
            guard let event = pendingEvents[index], event.scheduledTime <= now else { continue }
            pendingEvents[index] = nil
            startVoice(for: event, snapshot: current.snapshot, settings: current.settings)
        }
        controlLock.unlock()

        let snapshot = current.snapshot
        let settings = current.settings
        let speed = max(0, min(120, snapshot.speedMetersPerSecond.isFinite ? snapshot.speedMetersPerSecond : 0))
        let load = clamp(snapshot.tractionLoad)
        let brake = clamp(snapshot.brakeCommand)
        let regen = clamp(snapshot.regenerativeBrakeRatio)
        let rpm = max(0, min(12_000, snapshot.motorRPM.isFinite ? snapshot.motorRPM : 0))
        let powerNotch = min(12, max(0, snapshot.powerNotch))
        let fieldWeakening = clamp(snapshot.fieldWeakeningRatio)
        let acceleration = max(-8, min(8, snapshot.accelerationMetersPerSecondSquared.isFinite ? snapshot.accelerationMetersPerSecondSquared : 0))
        let windSpeed = max(0, min(80, snapshot.windMetersPerSecond.isFinite ? snapshot.windMetersPerSecond : 0))
        let trackDistance = snapshot.trackDistanceMeters.isFinite ? max(-1_000_000_000, min(1_000_000_000, snapshot.trackDistanceMeters)) : 0
        let speedFactor = min(1, speed / 34)
        let speechDuck: Float = current.speechActive ? 0.34 : 1
        let cabinGain: Float = settings.enableCabInteriorSounds ? 1 : 0
        let exteriorGain: Float = settings.enableExteriorSounds ? 1 : 0
        let masterGain = clamp(settings.masterVolume) * speechDuck
        let effectsGain = masterGain * clamp(settings.effectsVolume)

        let profile = settings.tractionSoundProfile
        let family = FictionalCabAndSoundCatalog.family(forProfileID: profile.rawValue)
        let layers = FictionalCueCatalog.continuousLayers(for: family)
        let driveDemand = max(load, brake * regen)
        let acMotorFrequency = max(24, min(1_400, 28 + rpm * 0.115 + abs(acceleration) * 9))
        let dcMotorFrequency = max(22, min(700, 24 + speed * 3.5 + rpm * 0.045 + Float(powerNotch) * 4 + fieldWeakening * 38))
        var motorFrequency = acMotorFrequency
        var secondHarmonicRatio: Float = 1.52
        var switchingFrequency: Float = 0
        var switchingGain: Float = 0
        var carrierModulation: Float = 0
        var chopperFrequency: Float = 0
        var chopperGain: Float = 0
        let tone = FictionalCabAndSoundCatalog.tractionTone(for: FictionalCabAndSoundCatalog.family(forProfileID: profile.rawValue))
        switch profile {
        case .rheostaticDC:
            motorFrequency = dcMotorFrequency * Float(tone.motorPitchScale)
            secondHarmonicRatio = Float(tone.secondHarmonicRatio)
        case .fieldChopperDC:
            motorFrequency = min(760, dcMotorFrequency + fieldWeakening * 85)
            secondHarmonicRatio = Float(tone.secondHarmonicRatio)
            chopperFrequency = Float(tone.chopperHertz) + fieldWeakening * 240
            chopperGain = (0.009 + fieldWeakening * 0.028) * driveDemand
        case .vvvfGTO:
            let pulseStage: Float = speed < 12 ? 2 : (speed < 28 ? 3 : (speed < 50 ? 4 : 5))
            switchingFrequency = speed < 12 ? Float(tone.carrierHertz) * 0.33 + speed * 5 : min(3_200, motorFrequency * 6 * pulseStage)
            switchingGain = 0.042
        case .vvvfIGBT:
            switchingFrequency = min(5_000, 2_750 + speed * 17)
            switchingGain = 0.032
        case .vvvfIGBTVariableCarrier:
            switchingFrequency = min(4_600, 2_500 + speed * 15)
            switchingGain = 0.030
            carrierModulation = 0.16
        case .vvvfSiC:
            switchingFrequency = min(8_000, 4_200 + speed * 20)
            switchingGain = 0.022
        }
        let motorAmplitude = cabinGain * (0.014 + 0.075 * driveDemand + 0.045 * speedFactor) * (0.65 + 0.35 * min(1, rpm / 3_000))
        let regenFrequency = max(55, min(1_600, 70 + speed * 10.5 + rpm * 0.018))
        let curveRadius = snapshot.curveRadiusMeters.flatMap { $0.isFinite ? max(40, $0) : nil } ?? 10_000
        let curvature = snapshot.curveRadiusMeters.map { $0.isFinite ? min(1, 250 / curveRadius) : 0 } ?? 0
        let tunnelMix = snapshot.isInTunnel ? clamp(settings.tunnelReverbMix) : 0
        if renderDistanceMeters == nil || abs(trackDistance - (renderDistanceMeters ?? trackDistance)) > 2 {
            renderDistanceMeters = trackDistance
        }

        for frame in 0..<frameCount {
            enginePhase = wrap(enginePhase + tau * motorFrequency / sampleRate)
            enginePhase2 = wrap(enginePhase2 + tau * min(2_800, motorFrequency * (secondHarmonicRatio + 0.18 * driveDemand)) / sampleRate)
            regenPhase = wrap(regenPhase + tau * regenFrequency / sampleRate)
            curvePhase = wrap(curvePhase + tau * (1_100 + speed * 34) / sampleRate)
            inverterModulationPhase = wrap(inverterModulationPhase + tau * (0.7 + speed * 0.018) / sampleRate)
            let carrierOffset = carrierModulation * sinf(inverterModulationPhase)
            inverterPhase = wrap(inverterPhase + tau * switchingFrequency * (1 + carrierOffset) / sampleRate)
            chopperPhase = wrap(chopperPhase + tau * chopperFrequency / sampleRate)

            let motor: Float
            switch profile {
            case .rheostaticDC:
                let commutator = sinf(enginePhase) * 0.62 + sinf(enginePhase2) * 0.25 + sinf(enginePhase * 3.35) * 0.13
                motor = commutator * motorAmplitude * (0.88 + Float(powerNotch) * 0.01)
            case .fieldChopperDC:
                let dcMotor = sinf(enginePhase) * 0.64 + sinf(enginePhase2) * 0.25 + sinf(enginePhase * 3.2) * 0.11
                let fieldRipple = sinf(chopperPhase) * chopperGain
                motor = dcMotor * motorAmplitude * (0.9 + fieldWeakening * 0.1) + fieldRipple
            case .vvvfGTO, .vvvfIGBT, .vvvfIGBTVariableCarrier, .vvvfSiC:
                let vvvfMotor = sinf(enginePhase) * 0.68 + sinf(enginePhase2) * 0.32
                let loadPulse = 0.72 + 0.28 * sinf(enginePhase * (2.2 + driveDemand * 0.7))
                let inverterTone = sinf(inverterPhase) * switchingGain * driveDemand
                let inverterSideband = sinf(inverterPhase * 0.5 + enginePhase * 0.08) * switchingGain * driveDemand * 0.18
                motor = vvvfMotor * motorAmplitude * loadPulse + inverterTone + inverterSideband
            }
            let tractionSound = motor
            let regenSound = sinf(regenPhase) * regen * brake * speedFactor * 0.042 * cabinGain

            let white = nextNoise()
            railLowPass += (white - railLowPass) * 0.12
            let railRumble = (railLowPass * 0.68 + white * 0.32) * speedFactor * exteriorGain * (snapshot.isOnBridge ? 0.11 : 0.085) * Float(layers.rollingBrightness)
            let weatherScale: Float
            switch snapshot.weather {
            case .clear: weatherScale = 0.10
            case .rain: weatherScale = 0.20
            case .heavyRain: weatherScale = 0.32
            case .snow: weatherScale = 0.14
            case .wind: weatherScale = 0.25
            }
            let windLevel = min(1, max(0, (windSpeed + speed * 0.08) / 30))
            windLowPass += (white - windLowPass) * 0.035
            let airflow = (white * 0.55 + windLowPass * 0.45) * windLevel * weatherScale * exteriorGain
            let brakeNoise = white * brake * (1 - regen * 0.72) * 0.095 * exteriorGain
            let brakeFrictionTone = sinf(curvePhase * 1.13) * brake * speedFactor * 0.022 * exteriorGain
            let curveSqueal = sinf(curvePhase) * curvature * speedFactor * 0.055 * exteriorGain
            let pointRattle = snapshot.isOnPoints ? white * speedFactor * 0.075 * exteriorGain : 0
            let ambientRain: Float = (snapshot.weather == .rain || snapshot.weather == .heavyRain) ? white * (snapshot.weather == .heavyRain ? 0.055 : 0.028) * exteriorGain * Float(layers.rainBedGain) : 0
            let compressor: Float
            if speed < 8 {
                compressorPhase = wrap(compressorPhase + tau * Float(layers.compressorHertz) / sampleRate)
                compressor = (sinf(compressorPhase) > 0.35 ? white * 0.018 : 0) * cabinGain * Float(layers.compressorHertz > 0 ? 1 : 0)
            } else {
                compressor = 0
            }
            let jointClick = sinf(enginePhase2) * jointPulse * speedFactor * 0.13 * exteriorGain
            jointPulse *= exp(-5.5 / sampleRate)
            let cabinBed = (tractionSound + regenSound + brakeNoise + brakeFrictionTone + compressor) * cabinGain * clamp(settings.effectsVolume)
            let exteriorBed = (railRumble + airflow + curveSqueal + pointRattle + ambientRain + jointClick) * exteriorGain * clamp(settings.ambienceVolume)
            let rawBed = cabinBed + exteriorBed

            // 距離に応じた簡易トンネル遮蔽。自然な反射音はAVAudioUnitReverbでも加える。
            let cutoff: Float = snapshot.isInTunnel ? Float(layers.tunnelDamp) * 0.35 : 0.72
            occlusionLowPass += (rawBed - occlusionLowPass) * cutoff
            let tunnelBed = rawBed * (1 - tunnelMix * 0.35) + occlusionLowPass * (tunnelMix * 0.35)
            let busPan = max(-1, min(1, (snapshot.trainPosition.x - snapshot.listenerPosition.x) / 40))
            let busAttenuation: Float = 1 / (1 + snapshot.trainPosition.distance(to: snapshot.listenerPosition) / 180)
            let bed = tunnelBed * masterGain * busAttenuation
            let bedLeft = bed * ((1 - busPan) * 0.5).squareRoot()
            let bedRight = bed * ((1 + busPan) * 0.5).squareRoot()
            var leftMix = bedLeft
            var rightMix = bedRight

            for voiceIndex in voices.indices where voices[voiceIndex].active {
                let voiceSample = renderVoice(at: voiceIndex, sampleRate: sampleRate)
                let voice = voices[voiceIndex]
                let leftPan = ((1 - voice.pan) * 0.5).squareRoot()
                let rightPan = ((1 + voice.pan) * 0.5).squareRoot()
                leftMix += voiceSample * leftPan * effectsGain
                rightMix += voiceSample * rightPan * effectsGain
            }

            left[frame] = softLimit(leftMix)
            right[frame] = softLimit(rightMix)

            renderDistanceMeters = (renderDistanceMeters ?? trackDistance) + Double(speed / sampleRate)
        }
    }

    private func startVoice(for event: RailwayAudioEvent, snapshot: RailwaySimulationSnapshot, settings: RailwayAudioSettings) {
        var selected = voices.firstIndex(where: { !$0.active })
        if selected == nil,
           let lowest = voices.indices.min(by: { voices[$0].priority < voices[$1].priority }),
           voices[lowest].priority < event.priority {
            selected = lowest
        }
        guard let index = selected else { return }
        let source = event.position ?? snapshot.trainPosition
        let dx = source.x - snapshot.listenerPosition.x
        let distance = source.distance(to: snapshot.listenerPosition)
        let pan = max(-1, min(1, dx / 35))
        let attenuation = 1 / (1 + distance / 40)
        let family = FictionalCabAndSoundCatalog.family(forProfileID: settings.tractionSoundProfile.rawValue)
        var recipe = FictionalCueCatalog.recipe(cue(for: event, profile: settings.tractionSoundProfile), family: family)
        if let frequency = event.frequencyHz {
            recipe = recipe.replacingFundamental(Double(frequency))
        }
        voices[index] = ProceduralVoice(
            active: true,
            priority: event.priority,
            pan: pan,
            amplitude: event.intensity * 0.17 * attenuation,
            recipe: recipe,
            renderer: FictionalCueRenderer(seed: UInt32(truncatingIfNeeded: event.id.hashValue) | 1)
        )
    }

    private func cue(for event: RailwayAudioEvent, profile: RailwayTractionSoundProfile) -> FictionalSynthesizedCue {
        switch event.kind {
        case .departureMelodyNote: return .departureMelodyNote
        case .controllerStep: return .controllerStep
        case .doorOpen: return .doorOpen
        case .doorClose: return .doorClose
        case .doorWarning: return .doorWarning
        case .whistle: return event.duration >= 1 ? .whistleLong : .whistleShort
        case .atsAlert: return .atsAlert
        case .atsConfirm: return .atsConfirm
        case .emergencyBrakeAlert: return .emergencyBrakeAlert
        case .crossingBell: return .crossingBell
        case .pneumaticBrakeRelease: return .pneumaticBrakeRelease
        case .brakeSqueal: return .brakeSqueal
        case .pointClatter: return .pointClatter
        case .railJoint: return .railJoint
        case .bridgeRumble: return .bridgeRumble
        case .stationChime: return .stationChime
        case .inductionTone: return profile == .vvvfGTO ? .inductionHigh : .inductionLow
        }
    }

    private func renderVoice(at index: Int, sampleRate: Float) -> Float {
        var voice = voices[index]
        guard voice.active else { return 0 }
        let value = voice.renderer.sample(recipe: voice.recipe, sampleRate: sampleRate)
        voice.active = voice.renderer.active
        voices[index] = voice
        return value * voice.amplitude
    }

    private func nextNoise() -> Float {
        randomState = 1_664_525 &* randomState &+ 1_013_904_223
        let unit = Float(randomState >> 8) / Float(0x00FF_FFFF)
        return unit * 2 - 1
    }

    private func clamp(_ value: Float) -> Float {
        min(1, max(0, value.isFinite ? value : 0))
    }

    private func wrap(_ phase: Float) -> Float {
        phase >= tau ? phase - tau : phase
    }

    private func softLimit(_ sample: Float) -> Float {
        let finite = sample.isFinite ? sample : 0
        return max(-0.98, min(0.98, finite / (1 + abs(finite) * 0.35)))
    }
}

private let tau: Float = 6.283185307179586
