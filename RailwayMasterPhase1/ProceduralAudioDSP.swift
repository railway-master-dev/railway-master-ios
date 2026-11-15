import Foundation
import RailwayAudioEnhancements

private struct AudioControlState {
    var snapshot = RailwaySimulationSnapshot()
    var settings = RailwayAudioSettings()
    var speechActive = false
    var sampledTractionActive = false
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
    private var previousBrakeState: Bool?
    /// batch79: alternates the two staged kishimi (brake-shoe
    /// squeal) takes on successive low-speed brake applications.
    private var kishimiToggle = false
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
    private var compressorPhase: Float = 0
    private var randomState: UInt32 = 0xC001_D00D
    private var renderDistanceMeters: Double?

    public init() {}

    /// batch63: 実録サンプルのワンショット再生ハンドラ。
    /// RailwayAudioEngine が init で playBundledSample へ接続する。
    /// true が返った場合はサンプル側で発音済みなので、呼び出し側は
    /// 対応する合成イベントを積まない（重なり防止）。
    public var cueSampleHandler: ((String) -> Bool)?

    public var droppedEventCount: Int {
        controlLock.lock()
        defer { controlLock.unlock() }
        return droppedEvents
    }

    public func update(snapshot: RailwaySimulationSnapshot, settings: RailwayAudioSettings) {
        controlLock.lock()
        let profile = settings.tractionSoundProfile
        // batch67: ノッチ操作音の発火はここ（スナップショットの
        // ノッチ変化の推測）から撤去し、実際の運転士操作イベント
        // （SimulatorModel.setThrottle → RailwayAudioEngine
        // .playControllerStep）へ移した。音響スナップショットの
        // ノッチは自動ブレーキ時に差し替わるため、制限境界で
        // 自動ブレーキが点滅すると「操作していないのにノッチ音が
        // 何度も鳴る」事故になっていた（BVE sound.cfg の
        // [Master Controller] はハンドルイベントで単発が原則）。
        let brakeCommand = snapshot.brakeCommand.isFinite ? min(1, max(0, snapshot.brakeCommand)) : 0
        let braking = previousBrakeState.map { $0 ? brakeCommand > 0.08 : brakeCommand >= 0.18 } ?? (brakeCommand >= 0.18)
        // batch81: 実録サンプルキュー（cueSampleHandler）は
        // controlLock の外で発火する。ハンドラの先は
        // RailwayAudioEngine のワンショット再生で、エンジン
        // 未起動時には batch79 以降 AVAudioSession の設定と
        // engine.start() まで行う重い処理になる。それを
        // ロック保持中に呼ぶと、描画スレッド（render の冒頭で
        // 同じロックを取る）がセッション再構成の間ずっと
        // ブロックされるうえ、ATS 非常制動の込め遷移
        // （brake_apply_4＋きしみ）という最も負荷の集中する
        // 瞬間にその重い処理が重なる。ここでは鳴らす名前と
        // 緩め側の合成フォールバックだけを控えておき、
        // unlock 後にまとめて発火する（順序と内容は従来どおり）。
        var pendingSampleCues: [String] = []
        var pendingReleaseFallback: RailwayAudioEvent?
        if let wasBraking = previousBrakeState, wasBraking != braking {
            let eventTime = snapshot.simulationTime.isFinite ? snapshot.simulationTime : 0
            let family = FictionalCabAndSoundCatalog.family(forProfileID: profile.rawValue)
            if braking {
                // batch63: 込め側の空気音は実録サンプルで担保する。
                // 運転士の setBrake を通らない ATS 指令ブレーキ等が
                // 対象で、運転士操作時はエンジン側の近接抑止により
                // 二重発音を避ける。合成 brakeSqueal は速度域の
                // 擦過音として従来どおり積む。
                let quartile = min(4, max(1, Int((brakeCommand / 0.25).rounded(.up))))
                pendingSampleCues.append("brake_apply_\(quartile)")
                // batch79: 制輪子きしみ（Primrose [Others] Shoe）。
                // 低速でブレーキが掛かった瞬間にだけ鳴る実録で、
                // 停車寸前の擦過音に当たる。停車中（速度ゼロ）と
                // 高速域では鳴らさない。2テイクを交互に使う。
                let speedMps = snapshot.speedMetersPerSecond.isFinite ? snapshot.speedMetersPerSecond : 0
                if speedMps > 0.3, speedMps < 5 {
                    kishimiToggle.toggle()
                    pendingSampleCues.append(kishimiToggle ? "kishimi_prim" : "kishimi_prim_2")
                }
                let brakeCue = FictionalCueCatalog.recipe(.brakeSqueal, family: family)
                let event = RailwayAudioEvent(
                    id: "brake-transition-\(Int(eventTime * 1_000))-engage",
                    kind: .brakeSqueal,
                    scheduledTime: eventTime,
                    duration: brakeCue.durationSeconds,
                    intensity: min(0.62, 0.28 + brakeCommand * 0.34),
                    frequencyHz: nil,
                    priority: 4,
                    position: snapshot.trainPosition
                )
                _ = enqueueLocked(event)
            } else {
                // batch63: 緩め側は実録 brake_release を優先し、
                // 鳴った場合は合成 pneumaticBrakeRelease を積まない。
                // batch81: 実録の成否は unlock 後の発火で決まる
                // ため、合成イベントはここでは組み立てだけを行い、
                // 実録が鳴らなかった場合にだけ後段で積む。
                pendingSampleCues.append("brake_release")
                let brakeCue = FictionalCueCatalog.recipe(.pneumaticBrakeRelease, family: family)
                pendingReleaseFallback = RailwayAudioEvent(
                    id: "brake-transition-\(Int(eventTime * 1_000))-release",
                    kind: .pneumaticBrakeRelease,
                    scheduledTime: eventTime,
                    duration: brakeCue.durationSeconds,
                    intensity: 0.38,
                    frequencyHz: nil,
                    priority: 4,
                    position: snapshot.trainPosition
                )
            }
        }
        previousBrakeState = braking
        control.snapshot = snapshot
        control.settings = settings
        controlLock.unlock()
        // batch81: 控えておいた実録キューをロックの外で発火する
        // （cueSampleHandler の宛先と batch79 の start() 経路に
        // ついては上記のコメント参照）。緩め側は実録が鳴らな
        // かった場合に限り、従来どおり合成フォールバックを積む。
        if !pendingSampleCues.isEmpty {
            var releasePlayed = false
            for cue in pendingSampleCues {
                let played = cueSampleHandler?(cue) ?? false
                if cue == "brake_release" { releasePlayed = played }
            }
            if let pendingReleaseFallback, !releasePlayed {
                _ = enqueue(pendingReleaseFallback)
            }
        }
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

    /// While sampled traction sound (BVE-style motor samples) is active
    /// for the selected profile, the synthesized motor/regen tones are
    /// muted so the two never layer over each other.
    public func setSampledTractionActive(_ active: Bool) {
        controlLock.lock()
        control.sampledTractionActive = active
        controlLock.unlock()
    }

    // batch79: the batch77 bed-layer impact pulse
    // (noteTrackImpact) is REMOVED, together with the DSP event
    // voices for rail joints / point clatter. The harness
    // measurement (2026-11-15) showed the synthesized impacts
    // firing for every bogie unit (245 voice events + 245 bed
    // pulses over one 498 m scripted drive) — a ~0.40 s period
    // chatter unrelated to the 25 m joint spacing, and the
    // device-side ザッザッ the user rejected. Track impacts are
    // now real recordings on the bundled one-shot pool, fired
    // by RailwayAudioEngine.playTrackImpact; nothing in this
    // DSP renders a synthesized joint or point sound any more.

    /// AVAudioSourceNode向けのリアルタイムPCM描画。left/rightはframeCount以上の領域であること。
    public func render(
        frameCount: Int,
        sampleRate: Float,
        left: UnsafeMutablePointer<Float>,
        right: UnsafeMutablePointer<Float>
    ) {
        guard frameCount > 0, sampleRate > 0 else { return }
        // batch63: ロック内では期限到来イベントの取り出しと nil 化
        // だけを行い、startVoice（レシピ解決やボイス確保などの
        // 重い処理）はロックの外で呼ぶ。制御スレッドがロックを
        // 保持する時間を短くし、描画スレッドとの競合を減らす。
        controlLock.lock()
        let current = control
        let now = current.snapshot.simulationTime.isFinite ? current.snapshot.simulationTime : 0
        var dueEvents: [RailwayAudioEvent] = []
        for index in pendingEvents.indices {
            guard let event = pendingEvents[index], event.scheduledTime <= now else { continue }
            pendingEvents[index] = nil
            dueEvents.append(event)
        }
        controlLock.unlock()
        for event in dueEvents {
            startVoice(for: event, snapshot: current.snapshot, settings: current.settings)
        }

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
        // batch65: 合成モーター系の速度ゲート。0.3 m/s 未満で 0、
        // 1.5 m/s で 1 へ線形ランプする。sampledTractionActive が
        // false の経路では、停車中（ブレーキ保持・回生率 > 0）でも
        // motorAmplitude の基礎項 0.014 と driveDemand 項によって
        // 合成モーター音が鳴り続け得たため、牽引音と回生音の全体
        // にこのゲートを掛けて停車中は完全に無音にする。発車と
        // 同時に自然に立ち上がる。
        let speedGate: Float
        if speed < 0.3 {
            speedGate = 0
        } else if speed >= 1.5 {
            speedGate = 1
        } else {
            speedGate = (speed - 0.3) / 1.2
        }
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
            let tractionScale: Float = current.sampledTractionActive ? 0 : 1
            // batch65: motor にはインバータ音（inverterTone /
            // inverterSideband）とチョッパのリップルも含まれる。
            // speedGate を tractionSound と regenSound の両方に
            // 掛けることで、停車中は合成モーター系が全て無音に
            // なる（高音のインバータ音も含む）。
            let tractionSound = motor * tractionScale * speedGate
            let regenSound = sinf(regenPhase) * regen * brake * speedFactor * 0.042 * cabinGain * tractionScale * speedGate

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
            // batch77 (device fix): brake friction noise is now
            // speed-gated by speedFactor. It used to be proportional
            // to brake command alone, so holding the brake at a
            // standstill (loading screen, station stop) produced a
            // continuous white-noise hiss — friction noise needs
            // motion, and brake AIR sounds at standstill are the
            // one-shot samples' job (brake_apply / brake_release).
            let brakeNoise = white * brake * (1 - regen * 0.72) * 0.095 * exteriorGain * speedFactor
            let brakeFrictionTone = sinf(curvePhase * 1.13) * brake * speedFactor * 0.022 * exteriorGain
            // batch94: the synthesized curve squeal is REMOVED.
            // It was a bare sine at 1,100 + speed x 34 Hz scaled
            // by curvature — the last synthesized running noise
            // the user could single out as fake. Flange squeal
            // is now the recorded LEYokohama takes on a
            // dedicated loop player in SampledMotorSound
            // (flange_0 / flange_1, keyed on the same
            // snapshot.curveRadiusMeters), following the
            // batch79 precedent that deleted the synthesized
            // joint once the real recording was wired. There is
            // deliberately no synth fallback: the takes are
            // bundled, probe-formatted and pre-warmed with the
            // beds, so the recorded path fails only with a
            // broken bundle, where a fake sine is not a
            // meaningful degradation. curvePhase itself stays:
            // brakeFrictionTone above still rides it.
            let pointRattle = snapshot.isOnPoints ? white * speedFactor * 0.075 * exteriorGain : 0
            let ambientRain: Float = (snapshot.weather == .rain || snapshot.weather == .heavyRain) ? white * (snapshot.weather == .heavyRain ? 0.055 : 0.028) * exteriorGain * Float(layers.rainBedGain) : 0
            // batch77 (device fix): the synthesized compressor bed
            // is REMOVED. It was a white-noise burst train gated by
            // a sine at compressorHertz (2.4 Hz for VVVF) that ran
            // whenever speed < 8 m/s — including standstill from
            // the loading screen onward — and the user heard it as
            // a continuous periodic "za-za-za" chopping noise
            // (IPA #8, the first build with the DSP connected).
            // A real compressor runs only on air demand; actual
            // compressor events are already covered by the recorded
            // cp_start / cp_end samples the host triggers
            // (SimulatorModel.updateCompressorSound), so the DSP
            // bed contributes nothing here.
            let compressor: Float = 0
            // batch79: no synthesized joint click remains in
            // the bed (see the note above noteTrackImpact's
            // removal). Rail-joint and point sounds are real
            // recordings on the one-shot pool now.
            let cabinBed = (tractionSound + regenSound + brakeNoise + brakeFrictionTone + compressor) * cabinGain * clamp(settings.effectsVolume)
            let exteriorBed = (railRumble + airflow + pointRattle + ambientRain) * exteriorGain * clamp(settings.ambienceVolume)
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
        // batch60: 警笛だけボイスゲインを倍にする。従来は全キュー
        // 一律の 0.17 で、警笛（intensity 0.9）でも effectsGain
        // 込みのピークが約 0.077 しかなく実機で聞き取れなかった。
        // 他のキューのバランスは変えない。
        // batch67: 軌道音（ジョイント/分岐器）も増幅する。ジョイント
        // クリックは 46ms の単発で、0.17 では駅付近の低速域
        // （intensity 0.1〜0.3）でピーク約 0.01〜0.03 となり走行
        // ループに埋もれて実質無音だった（実機指摘）。BVE では
        // 継目音は Run 音そのものの一部として速度連動で聞こえる
        // 音量域にあるため、軌道音だけ 0.5 へ引き上げる。
        let voiceGain: Float
        if event.kind == .whistle {
            voiceGain = 0.34
        } else if event.kind == .railJoint || event.kind == .pointClatter {
            voiceGain = 0.5
        } else {
            voiceGain = 0.17
        }
        voices[index] = ProceduralVoice(
            active: true,
            priority: event.priority,
            pan: pan,
            amplitude: event.intensity * voiceGain * attenuation,
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
        // batch63: ボイス寿命のハードキャップ。レシピ上の終端
        // （durationSeconds + 0.5 秒）を過ぎても renderer が
        // active のまま残る異常ケースへの保険で、警笛が鳴り
        // 続けるような事故を構造的に防ぐ。
        if voice.renderer.age > Float(voice.recipe.durationSeconds) + 0.5 {
            voice.active = false
        }
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
