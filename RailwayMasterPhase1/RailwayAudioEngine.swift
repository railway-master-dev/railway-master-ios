#if canImport(AVFoundation) && canImport(UIKit)
import AVFoundation
import AudioToolbox
import Foundation
import RailwayAudioEnhancements
import UIKit

/// 架空路線シミュレーター用の手続き合成音響アダプター。
/// 基本は独自合成。同梱サンプルは利用許諾を確認済みのものだけを使う
/// （抵抗制御車のドアチャイムはプロジェクト提供の録音）。
@MainActor
public final class RailwayAudioEngine: NSObject, AVSpeechSynthesizerDelegate {
    public static let shared = RailwayAudioEngine()

    public private(set) var settings = RailwayAudioSettings(masterVolume: 0.65)
    public var usesVoiceOverAnnouncements = true
    public var enabled: Bool { isEnabled }
    public var volume: Float { outputVolume }
    public var isAudioRunning: Bool { engine.isRunning }

    private let engine = AVAudioEngine()
    private let reverb = AVAudioUnitReverb()
    private let licensedSampleMixer = AVAudioMixerNode()
    private let synthesizer = AVSpeechSynthesizer()
    private let dsp: ProceduralAudioDSP
    private let format: AVAudioFormat
    private let sourceNode: AVAudioSourceNode
    private var isEnabled = true
    private var outputVolume: Float = 0.65
    private var latestSnapshot = RailwaySimulationSnapshot()
    private let melodyCatalog = DepartureMelodyCatalog()
    private let sampledMotor = SampledMotorSound()

    public override init() {
        let dsp = ProceduralAudioDSP()
        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 48_000, channels: 2, interleaved: false)!
        self.dsp = dsp
        self.format = format
        self.sourceNode = AVAudioSourceNode(format: format) { isSilence, _, frameCount, audioBufferList in
            let buffers = UnsafeMutableAudioBufferListPointer(audioBufferList)
            guard buffers.count >= 2,
                  let leftData = buffers[0].mData,
                  let rightData = buffers[1].mData else {
                for buffer in buffers {
                    if let data = buffer.mData { memset(data, 0, Int(buffer.mDataByteSize)) }
                }
                return noErr
            }
            dsp.render(
                frameCount: Int(frameCount),
                sampleRate: Float(format.sampleRate),
                left: leftData.assumingMemoryBound(to: Float.self),
                right: rightData.assumingMemoryBound(to: Float.self)
            )
            isSilence.pointee = ObjCBool(false)
            return noErr
        }
        super.init()

        synthesizer.delegate = self
        engine.attach(sourceNode)
        engine.attach(reverb)
        engine.attach(licensedSampleMixer)
        reverb.loadFactoryPreset(.mediumRoom)
        reverb.wetDryMix = 0
        engine.connect(sourceNode, to: reverb, format: format)
        engine.connect(licensedSampleMixer, to: reverb, format: nil)
        engine.connect(reverb, to: engine.mainMixerNode, format: format)
        engine.mainMixerNode.outputVolume = 1
        engine.prepare()
        applyCurrentSnapshot()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAudioSessionInterruption(_:)),
            name: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance()
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAudioSessionRouteChange(_:)),
            name: AVAudioSession.routeChangeNotification,
            object: AVAudioSession.sharedInstance()
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    /// 音声はベストエフォートで開始し、利用できない環境でもシミュレーションを止めません。
    public func start() {
        guard isEnabled, !engine.isRunning else { return }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .spokenAudio, options: [.mixWithOthers, .duckOthers])
            try session.setActive(true)
            engine.prepare()
            try engine.start()
        } catch {
            // Simulator、割り込み、音声出力制限時も運転シミュレーションは継続します。
        }
    }

    public func stop() {
        if engine.isRunning { engine.stop() }
        synthesizer.stopSpeaking(at: .immediate)
        dsp.setSpeechActive(false)
    }

    public func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
        if enabled {
            applyCurrentSnapshot()
            start()
        } else {
            stop()
        }
    }

    public func setVolume(_ volume: Float) {
        outputVolume = volume.isFinite ? min(max(volume, 0), 1) : 0
        settings.masterVolume = outputVolume
        applyCurrentSnapshot()
    }

    public func setTractionSoundProfile(_ profile: RailwayTractionSoundProfile) {
        settings.tractionSoundProfile = profile
        applyCurrentSnapshot()
    }

    public func setAudioProfile(_ profile: RailwayAudioProfile) {
        let chosen = RailwayAudioSettings.defaults(for: profile)
        settings.profile = chosen.profile
        settings.effectsVolume = chosen.effectsVolume
        settings.ambienceVolume = chosen.ambienceVolume
        settings.announcementVolume = chosen.announcementVolume
        settings.tunnelReverbMix = chosen.tunnelReverbMix
        settings.enableCabInteriorSounds = chosen.enableCabInteriorSounds
        settings.enableExteriorSounds = chosen.enableExteriorSounds
        settings.masterVolume = outputVolume
        applyCurrentSnapshot()
    }

    /// Updates the complete audio-facing simulator state. All positions and distances are in metres.
    public func update(snapshot: RailwaySimulationSnapshot) {
        latestSnapshot = snapshot
        applyCurrentSnapshot()
    }

    /// ATS/door/signal trigger conditions belong to the host simulation; only confirmed events are queued here.
    @discardableResult
    public func enqueue(_ event: RailwayAudioEvent) -> Bool {
        dsp.enqueue(event)
    }

    public func setSpeechActive(_ active: Bool) {
        dsp.setSpeechActive(active)
    }

    /// Optional authorized vehicle audio can be attached here.
    /// Callers must attach only while the engine is running, and must
    /// connect with the exact format of the buffers the player will
    /// play: scheduling a buffer whose format differs from the node's
    /// connection format raises a CoreAudio error (CI #147), and
    /// connecting before the engine runs aborts the process
    /// (CI #138/#141).
    public func attachLicensedSamplePlayer(_ playerNode: AVAudioPlayerNode, format: AVAudioFormat) {
        engine.attach(playerNode)
        engine.connect(playerNode, to: licensedSampleMixer, format: format)
    }

    private var bundledSamplePlayer: AVAudioPlayerNode?
    private var bundledSampleFormat: AVAudioFormat?
    private var bundledSampleBuffers: [String: AVAudioPCMBuffer] = [:]

    /// Plays a bundled WAV sample through the licensed-sample mixer and
    /// returns its duration in seconds so callers can sequence actions
    /// (for example closing the doors only after a door chime ends).
    /// Returns nil when the sample is missing or audio is disabled.
    @discardableResult
    public func playBundledSample(named name: String) -> TimeInterval? {
        guard isEnabled else { return nil }
        let buffer: AVAudioPCMBuffer
        if let cached = bundledSampleBuffers[name] {
            buffer = cached
        } else {
            guard let url = Bundle.main.url(forResource: name, withExtension: "wav"),
                  let file = try? AVAudioFile(forReading: url),
                  let loaded = AVAudioPCMBuffer(pcmFormat: file.processingFormat,
                                                frameCapacity: AVAudioFrameCount(file.length)) else {
                return nil
            }
            do {
                try file.read(into: loaded)
            } catch {
                return nil
            }
            bundledSampleBuffers[name] = loaded
            buffer = loaded
        }
        let player: AVAudioPlayerNode
        if let existing = bundledSamplePlayer, bundledSampleFormat == buffer.format {
            player = existing
        } else {
            // Door samples come in both mono and stereo; the shared
            // player must be re-attached when the format changes, or
            // scheduling the buffer raises a CoreAudio error.
            if let old = bundledSamplePlayer {
                old.stop()
                engine.detach(old)
            }
            let created = AVAudioPlayerNode()
            attachLicensedSamplePlayer(created, format: buffer.format)
            bundledSamplePlayer = created
            bundledSampleFormat = buffer.format
            player = created
        }
        if !engine.isRunning { try? engine.start() }
        player.volume = outputVolume
        player.scheduleBuffer(buffer, at: nil, options: [])
        player.play()
        return Double(buffer.frameLength) / buffer.format.sampleRate
    }

    public func playHorn(long: Bool = false) {
        let recipe = FictionalCueCatalog.recipe(long ? .whistleLong : .whistleShort, family: cueFamily)
        enqueueAtCurrentTime(.whistle, duration: recipe.durationSeconds, intensity: 0.9, priority: 8)
    }

    public func playBrakeAir() {
        let recipe = FictionalCueCatalog.recipe(.pneumaticBrakeRelease, family: cueFamily)
        enqueueAtCurrentTime(.pneumaticBrakeRelease, duration: recipe.durationSeconds, intensity: 0.72, priority: 6)
    }

    public func playATSAlarm() {
        let recipe = FictionalCueCatalog.recipe(.atsAlert, family: cueFamily)
        enqueueAtCurrentTime(.atsAlert, duration: recipe.durationSeconds, intensity: 0.92, priority: 10)
    }

    public func playEmergencyBrakeAlert() {
        let recipe = FictionalCueCatalog.recipe(.emergencyBrakeAlert, family: cueFamily)
        enqueueAtCurrentTime(.emergencyBrakeAlert, duration: recipe.durationSeconds, intensity: 0.96, priority: 10)
    }

    public func playATSConfirmation() {
        let recipe = FictionalCueCatalog.recipe(.atsConfirm, family: cueFamily)
        enqueueAtCurrentTime(.atsConfirm, duration: recipe.durationSeconds, intensity: 0.55, priority: 8)
    }

    public func playATSConfirm() { playATSConfirmation() }

    public func playCrossingBell() {
        let recipe = FictionalCueCatalog.recipe(.crossingBell, family: cueFamily)
        enqueueAtCurrentTime(.crossingBell, duration: recipe.durationSeconds, intensity: 0.62, priority: 6)
    }

    public func playTrackImpact(_ kind: RailwayAudioEventKind, intensity: Float) {
        let cue: FictionalSynthesizedCue = kind == .pointClatter ? .pointClatter : .railJoint
        let recipe = FictionalCueCatalog.recipe(cue, family: cueFamily)
        let gain = min(1, max(0, intensity.isFinite ? intensity : 0))
        guard gain > 0.02 else { return }
        enqueueAtCurrentTime(kind, duration: recipe.durationSeconds, intensity: gain, priority: kind == .pointClatter ? 5 : 3)
    }

    public func playWayside(_ kind: RailwayAudioEventKind) {
        let cue = waysideCue(kind)
        let recipe = FictionalCueCatalog.recipe(cue, family: cueFamily)
        enqueueAtCurrentTime(kind, duration: recipe.durationSeconds, intensity: 0.5, priority: 4)
    }

    public func playDoor(open: Bool) {
        let family = cueFamily
        let warning = FictionalCueCatalog.recipe(.doorWarning, family: family)
        if open {
            enqueueAtCurrentTime(.doorWarning, duration: warning.durationSeconds, intensity: 0.4, priority: 5)
            let tone = FictionalCueCatalog.recipe(.doorOpen, family: family)
            enqueueAtCurrentTime(.doorOpen, duration: tone.durationSeconds, intensity: 0.42, priority: 4)
        } else {
            let tone = FictionalCueCatalog.recipe(.doorClose, family: family)
            enqueueAtCurrentTime(.doorClose, duration: tone.durationSeconds, intensity: 0.4, priority: 4)
        }
    }

    public func playDepartureChime() {
        let key = DepartureMelodyKey(stationID: "fictional-arrival", directionID: "up", platformID: "platform-1")
        melodyCatalog.events(for: key, startingAt: latestSnapshot.simulationTime, position: latestSnapshot.trainPosition)
            .forEach { _ = dsp.enqueue($0) }
    }

    public func playDoorChime() {
        let recipe = FictionalCueCatalog.recipe(.doorWarning, family: cueFamily)
        enqueueAtCurrentTime(.doorWarning, duration: recipe.durationSeconds, intensity: 0.45, priority: 5)
    }

    /// Consumes a scheduler result on the main actor. The scheduler owns timing/deduplication;
    /// this adapter only routes supported cues into the existing AVAudioEngine/TTS path.
    public func playScheduledAudioEvent(_ event: AudioScheduledEvent) {
        guard isEnabled else { return }
        switch event.payload {
        case .announcement(let request):
            guard let instruction = AnnouncementRenderer.render(request) else { return }
            let mix = AudioMixMatrix.parameters(
                for: instruction.audioBus,
                in: .cabInterior,
                masterGain: 1
            )
            speak(instruction.text, languageTag: instruction.languageTag, mixGain: mix.gain)
        case .speakerTone(let tone):
            switch tone {
            case .attentionChime:
                playATSAlarm()
            case .atsConfirm:
                playATSConfirmation()
            case .stationBell:
                let recipe = FictionalCueCatalog.recipe(.stationChime, family: cueFamily)
                enqueueAtCurrentTime(.stationChime, duration: recipe.durationSeconds, intensity: 0.48, priority: 5)
            case .doorWarning:
                playDoorChime()
            }
        case .controlModeSignature:
            // The existing DSP remains authoritative for traction audio; avoid layering
            // a second conceptual signature over the same controller state.
            break
        }
    }

    public func announceNextStation(_ station: String) {
        speak("まもなく、\(safeStationName(station))、\(safeStationName(station))です。")
    }

    public func announceStop(at station: String) {
        speak("\(safeStationName(station))、\(safeStationName(station))に停車いたします。")
    }

    public func announceDeparture(from station: String) {
        speak("\(safeStationName(station))を発車いたします。")
    }

    public func announceNextStation(_ station: String, withDoorChime: Bool) {
        if withDoorChime { playDoorChime() }
        announceNextStation(station)
    }

    @objc private func handleAudioSessionInterruption(_ notification: Notification) {
        guard let rawValue = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: rawValue) else { return }
        if type == .ended, isEnabled {
            start()
        } else if type == .began {
            if engine.isRunning { engine.stop() }
        }
    }

    @objc private func handleAudioSessionRouteChange(_ notification: Notification) {
        guard isEnabled else { return }
        if !engine.isRunning { start() }
    }

    public func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        dsp.setSpeechActive(false)
    }

    public func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        dsp.setSpeechActive(false)
    }

    private var cueFamily: FictionalControlFamily {
        FictionalCabAndSoundCatalog.family(forProfileID: settings.tractionSoundProfile.rawValue)
    }

    private func waysideCue(_ kind: RailwayAudioEventKind) -> FictionalSynthesizedCue {
        switch kind {
        case .pointClatter: return .pointClatter
        case .railJoint: return .railJoint
        case .bridgeRumble: return .bridgeRumble
        case .crossingBell: return .crossingBell
        case .stationChime: return .stationChime
        default: return .railJoint
        }
    }

    private func enqueueAtCurrentTime(
        _ kind: RailwayAudioEventKind,
        duration: TimeInterval,
        intensity: Float,
        frequencyHz: Float? = nil,
        priority: Int
    ) {
        guard isEnabled else { return }
        start()
        let event = RailwayAudioEvent(
            kind: kind,
            scheduledTime: latestSnapshot.simulationTime,
            duration: duration,
            intensity: intensity,
            frequencyHz: frequencyHz,
            priority: priority,
            position: latestSnapshot.trainPosition
        )
        _ = dsp.enqueue(event)
    }

    private func applyCurrentSnapshot() {
        var effective = settings
        effective.masterVolume = isEnabled ? outputVolume : 0
        if sampledMotor.attachHandler == nil {
            sampledMotor.attachHandler = { [weak self] node, format in self?.attachLicensedSamplePlayer(node, format: format) }
            sampledMotor.startHandler = { [weak self] in self?.start() }
        }
        sampledMotor.update(snapshot: latestSnapshot, settings: effective, isEnabled: isEnabled, engineRunning: engine.isRunning)
        dsp.setSampledTractionActive(isEnabled && sampledMotor.isActive)
        dsp.update(snapshot: latestSnapshot, settings: effective)
        reverb.wetDryMix = latestSnapshot.isInTunnel ? min(1, max(0, effective.tunnelReverbMix)) * 100 : 0
    }

    private func speak(_ text: String, languageTag: String = "ja-JP", mixGain: Float = 1) {
        guard isEnabled, !text.isEmpty else { return }
        start()
        if usesVoiceOverAnnouncements && UIAccessibility.isVoiceOverRunning {
            UIAccessibility.post(notification: .announcement, argument: text)
            return
        }
        dsp.setSpeechActive(true)
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: languageTag)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        utterance.volume = min(1, max(0, outputVolume * settings.announcementVolume * mixGain))
        synthesizer.speak(utterance)
    }

    private func safeStationName(_ name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return String((trimmed.isEmpty ? "次の駅" : trimmed).prefix(48))
    }
}
#endif
