#if canImport(AVFoundation)
import AVFoundation
import Foundation

/// BVE-style sampled traction sound (audio2 / quality6).
///
/// Plays the licensed BVE Workshop motor samples with the volume-curve
/// method of the BVE MotorNoise tables: an offline step
/// (Scripts/build_motor_curves.py) sampled each family's volume table
/// into motor_curves.json, and at runtime up to three samples crossfade
/// by speed, one set for powering and one for braking. A fourth player
/// loops the running (rail) noise for the current section: the user's
/// own VVVF recording for VVVF stock, otherwise the BVE Workshop
/// 9300-series loops (ballast / bridge / tunnel).
///
/// When this player is active for the selected profile, the procedural
/// DSP's synthesized traction tone is muted via
/// ProceduralAudioDSP.setSampledTractionActive so the two never layer.
@MainActor
final class SampledMotorSound {
    /// Set by the host engine: attaches a player to the licensed mixer.
    var attachHandler: ((AVAudioPlayerNode, AVAudioFormat) -> Void)?
    /// batch78: set by the host engine: attaches the RUN player
    /// through an AVAudioUnitVarispeed (player -> varispeed ->
    /// licensed mixer) so the E231 section beds can be pitch-
    /// driven BVE-style. Optional: when nil, preattachIfNeeded
    /// falls back to attachHandler for the run player and the
    /// varispeed stays out of the graph (rate writes are inert).
    /// The AudioHarness installs only attachHandler and relies
    /// on this fallback.
    var runAttachHandler: ((AVAudioPlayerNode, AVAudioUnitVarispeed, AVAudioFormat) -> Void)?
    /// Set by the host engine: best-effort engine start.
    var startHandler: (() -> Void)?

    private struct CurveStep {
        var speedKmh: Float
        var gains: [String: Float]
    }

    private var curves: [String: [String: [CurveStep]]] = [:]
    private var curvesLoaded = false
    private var buffers: [String: AVAudioPCMBuffer] = [:]

    private var motorPlayers: [AVAudioPlayerNode] = []
    private var motorSlotSample: [String?] = [nil, nil, nil]
    private var runPlayer: AVAudioPlayerNode?
    /// batch78: varispeed inserted in the run player's chain
    /// when the host installs runAttachHandler (see above).
    private var runVarispeed: AVAudioUnitVarispeed?
    private var runSample: String?
    /// batch79: independent loop player for the Primrose motor
    /// cooling-fan recording (ambient_fan_prim). The jus volume
    /// tables carry the fan as a "band" (MParameter FanIndex),
    /// but a cooling fan is not a crossfade band — it runs while
    /// the train is stopped or crawling, which is exactly the
    /// user's standing "ambience while stopped" request. It is
    /// therefore stripped from the merged primrose curves and
    /// driven here as its own loop on the (stereo) run format.
    private var ambientPlayer: AVAudioPlayerNode?
    private var ambientSample: String?
    /// batch94: dedicated loop player for the recorded flange
    /// squeal (flange_0 / flange_1, LEYokohama E231 takes,
    /// loop-baked at bundling — see MAPPING.md §12). Replaces
    /// the DSP's synthesized curveSqueal, which is removed.
    /// Like the fan it is driven independently of the band
    /// crossfade: flange contact is a running noise, not a
    /// traction band, and it must not die with a latched motor
    /// path. Its connection format is resolved from the
    /// flange_0 probe file itself (batch74 scheme), because
    /// the takes are mono while the run/ambient role is stereo.
    private var flangePlayer: AVAudioPlayerNode?
    private var flangeSample: String?
    private var flangeConnectionFormat: AVAudioFormat?
    /// Curve-entry counter: successive entries alternate the
    /// take (flange_0, flange_1, flange_0, ...) for variety.
    private var flangeEntryCount = 0
    private var flangeWasInZone = false
    /// batch106: dedicated loop player for the station
    /// ambience bed (ambient_station, a CC0 platform
    /// recording — see MAPPING.md §14). Like the fan it is
    /// driven independently of the band crossfade, gated on
    /// the train being at a station. Unlike the fan file
    /// (44.1 kHz stereo, carried on the run role's format),
    /// the bed is mono, so its connection format is resolved
    /// from its own probe file in preattachIfNeeded — the
    /// batch94 flange scheme. Attaching it on the stereo run
    /// format would make playLoop's format guard reject the
    /// mono buffer and the bed would never sound.
    private var stationPlayer: AVAudioPlayerNode?
    private var stationSample: String?
    private var stationConnectionFormat: AVAudioFormat?
    private var currentFamily: String?
    /// Format each player was connected with (CI #147: scheduling a
    /// buffer whose format differs from the connection raises a
    /// CoreAudio error, so buffers are converted to the connection
    /// format at load time — see buffer(named:)).
    private var attachedFormats: [ObjectIdentifier: AVAudioFormat] = [:]

    /// batch67: canonical connection formats. Players are attached
    /// with these unconditionally during engine init, and every
    /// loaded buffer is converted to the matching one before it is
    /// cached. Before batch67 the players were attached with the
    /// format of whichever probe buffer happened to load first, and
    /// playLoop silently skipped any buffer whose format differed —
    /// a failure mode with no audible fallback and no trace, which
    /// is the prime suspect for the device report "no motor sound
    /// at all" (batch64+65 IPA): curves existed, so the DSP synth
    /// was muted via setSampledTractionActive, while the sampled
    /// side produced nothing.
    ///
    /// batch74 (urgent device fix): the connection formats are no
    /// longer the code-generated constants below. They are resolved
    /// in preattachIfNeeded from the probe files themselves
    /// (motor_vvvf_00 / run_ballast), i.e. the format object is the
    /// file's own processingFormat — the same self-consistent
    /// scheme the one-shot bundled pool uses, which is the one
    /// sample path proven to sound on device (horn / brake / door
    /// on IPA #6, while the motor stayed silent). A code-generated
    /// AVAudioFormat can differ from a file-derived one in stream
    /// description details (e.g. channel layout) even at identical
    /// sample rate / channel count, and any conversion or equality
    /// failure on that seam degrades to total silence via
    /// buffer(named:) returning nil. The constants remain only as
    /// a fallback for when a probe file cannot be loaded at all.
    private var motorConnectionFormat: AVAudioFormat?
    private var runConnectionFormat: AVAudioFormat?
    private static let codeGeneratedMotorFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 44_100, channels: 1, interleaved: false)!
    private static let codeGeneratedRunFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 44_100, channels: 2, interleaved: false)!

    /// batch67 diagnostics, surfaced through the engine's audio
    /// status log line so a silent sampled path leaves evidence.
    private var conversionCount = 0
    private var playFailureCount = 0
    private var lastDesiredSummary = "-"
    /// batch77: fail-over latch state (see notePlayFailure).
    private var consecutivePlayFailures = 0
    private var playbackBroken = false

    var statusDescription: String {
        let slots = motorSlotSample.map { $0 ?? "-" }.joined(separator: ",")
        return "sampled active=\(isActive ? 1 : 0) players=\(motorPlayers.count) curves=\(curves.keys.sorted().joined(separator: "+")) slots=\(slots) want=\(lastDesiredSummary) conv=\(conversionCount) playFail=\(playFailureCount) broken=\(playbackBroken ? 1 : 0) flange=\(flangeSample ?? "-") station=\(stationSample ?? "-")"
    }

    /// True only when the sampled path can actually sound: curves
    /// exist for the family AND the players were attached. Before
    /// batch67 this was curves alone, so a dead sampled path still
    /// muted the synthesized traction in the DSP and the cab went
    /// completely silent. Now a non-viable sampled path reports
    /// false and the DSP synth (speed-gated since batch65) takes
    /// over instead of silence.
    private(set) var isActive = false

    private func familyKey(for profile: RailwayTractionSoundProfile) -> String {
        switch profile {
        case .rheostaticDC: return "resistance"
        case .fieldChopperDC: return "chopper"
        case .vvvfGTO, .vvvfIGBT, .vvvfIGBTVariableCarrier, .vvvfSiC: return "vvvf"
        }
    }

    private func loadCurvesIfNeeded() {
        guard !curvesLoaded else { return }
        curvesLoaded = true
        guard let url = Bundle.main.url(forResource: "motor_curves", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        var parsed: [String: [String: [CurveStep]]] = [:]
        for (family, modesValue) in root {
            guard let modes = modesValue as? [String: Any] else { continue }
            var familyCurves: [String: [CurveStep]] = [:]
            for (mode, stepsValue) in modes {
                guard let steps = stepsValue as? [[Any]] else { continue }
                familyCurves[mode] = steps.compactMap { raw in
                    guard raw.count == 2,
                          let speed = (raw[0] as? NSNumber)?.floatValue,
                          let pairs = raw[1] as? [[Any]] else { return nil }
                    var gains: [String: Float] = [:]
                    for pair in pairs where pair.count == 2 {
                        if let name = pair[0] as? String, let volume = (pair[1] as? NSNumber)?.floatValue {
                            gains[name] = volume
                        }
                    }
                    return CurveStep(speedKmh: speed, gains: gains)
                }.sorted { $0.speedKmh < $1.speedKmh }
            }
            parsed[family] = familyCurves
        }
        curves = parsed
    }

    private func interpolatedGains(family: String, mode: String, speedKmh: Float) -> [String: Float] {
        guard let steps = curves[family]?[mode], let first = steps.first else { return [:] }
        if speedKmh <= first.speedKmh { return first.gains }
        if let last = steps.last, speedKmh >= last.speedKmh { return last.gains }
        for index in 0..<(steps.count - 1) {
            let a = steps[index]
            let b = steps[index + 1]
            guard speedKmh >= a.speedKmh, speedKmh <= b.speedKmh else { continue }
            let span = max(0.001, b.speedKmh - a.speedKmh)
            let t = (speedKmh - a.speedKmh) / span
            var result: [String: Float] = [:]
            for (name, volume) in a.gains { result[name] = volume * (1 - t) }
            for (name, volume) in b.gains { result[name] = (result[name] ?? 0) + volume * t }
            return result
        }
        return [:]
    }

    /// Raw file load with no format normalization. Also used by
    /// preattachIfNeeded to read the probe files whose own format
    /// becomes the role's connection format (batch74).
    private func loadFileBuffer(named name: String) -> AVAudioPCMBuffer? {
        guard let url = Bundle.main.url(forResource: name, withExtension: "wav"),
              let file = try? AVAudioFile(forReading: url) else { return nil }
        // batch101: same trapping conversion as the engine's
        // one-shot loader — file.length is header-derived and
        // AVAudioFrameCount (UInt32) traps above UInt32.max, so a
        // corrupt WAV header would crash the first update that
        // touched the sample. Out-of-range means unloadable;
        // nil is the designed degradation for every caller.
        guard file.length >= 0, file.length <= Int64(UInt32.max),
              let loaded = AVAudioPCMBuffer(pcmFormat: file.processingFormat,
                                            frameCapacity: AVAudioFrameCount(file.length)) else { return nil }
        do {
            try file.read(into: loaded)
        } catch {
            return nil
        }
        return loaded
    }

    private func buffer(named name: String) -> AVAudioPCMBuffer? {
        if let cached = buffers[name] { return cached }
        // batch77 (device fix): buffers are now scheduled RAW, in
        // their own file processingFormat — exactly the mechanism
        // of the one-shot bundled pool, the one sample path proven
        // audible on device (horn / brake / door). The batch67
        // AVAudioConverter normalization (kept by batch74 in
        // file-derived form) is removed entirely: it was the last
        // remaining seam unique to this path, and the motor stayed
        // silent on IPA #8 with it in place. All bundled motor
        // files are uniformly 44.1 kHz mono and all run files
        // uniformly 44.1 kHz stereo (verified on disk), identical
        // to the probe files the players are attached with, so
        // playLoop's format guard passes on the raw buffers just
        // as the pool's does.
        guard let loaded = loadFileBuffer(named: name) else { return nil }
        buffers[name] = loaded
        return loaded
    }

    /// Creates and attaches all players up front. The engine calls
    /// this during its own init, before the graph is prepared: runtime
    /// attach/connect forces an AVAudioEngine graph reconfiguration
    /// that can throw (CI #138/#163), so it never happens afterwards.
    /// batch67: the players always exist and a missing or odd-format
    /// sample degrades to "that sample stays silent" (with the DSP
    /// fail-over via isActive), never to a dead subsystem with no
    /// trace. batch74: the connection formats are first resolved
    /// from the probe files (motor_vvvf_00 for the motor role,
    /// run_ballast for the running-noise role) so they are
    /// file-derived like the proven one-shot pool; the players are
    /// still attached unconditionally, falling back to the
    /// code-generated constants only if a probe cannot be loaded.
    func preattachIfNeeded() {
        guard motorPlayers.isEmpty, let attachHandler else { return }
        if motorConnectionFormat == nil, let probe = loadFileBuffer(named: "motor_vvvf_00") {
            motorConnectionFormat = probe.format
        }
        if runConnectionFormat == nil, let probe = loadFileBuffer(named: "run_ballast") {
            runConnectionFormat = probe.format
        }
        if flangeConnectionFormat == nil, let probe = loadFileBuffer(named: "flange_0") {
            flangeConnectionFormat = probe.format
        }
        if stationConnectionFormat == nil, let probe = loadFileBuffer(named: "ambient_station") {
            stationConnectionFormat = probe.format
        }
        let motorFormat = motorConnectionFormat ?? Self.codeGeneratedMotorFormat
        let runFormat = runConnectionFormat ?? Self.codeGeneratedRunFormat
        for _ in 0..<3 {
            let player = AVAudioPlayerNode()
            attachHandler(player, motorFormat)
            attachedFormats[ObjectIdentifier(player)] = motorFormat
            motorPlayers.append(player)
        }
        let run = AVAudioPlayerNode()
        let varispeed = AVAudioUnitVarispeed()
        if let runAttachHandler {
            runAttachHandler(run, varispeed, runFormat)
        } else {
            attachHandler(run, runFormat)
        }
        attachedFormats[ObjectIdentifier(run)] = runFormat
        runPlayer = run
        runVarispeed = varispeed
        // batch79: fan ambience player on the same stereo format
        // as the run player (ambient_fan_prim is 44.1 kHz stereo).
        let ambient = AVAudioPlayerNode()
        attachHandler(ambient, runFormat)
        attachedFormats[ObjectIdentifier(ambient)] = runFormat
        ambientPlayer = ambient
        // batch94: flange-squeal player on the mono format
        // resolved from its own probe (flange_0), falling back
        // to the motor role's format if the probe cannot load.
        let flangeFormat = flangeConnectionFormat ?? motorFormat
        let flange = AVAudioPlayerNode()
        attachHandler(flange, flangeFormat)
        attachedFormats[ObjectIdentifier(flange)] = flangeFormat
        flangePlayer = flange
        // batch106: station ambience player on the mono format
        // resolved from its own probe (see the property note),
        // falling back to the run role's format if the probe
        // cannot load (in which case the bed stays silent via
        // buffer(named:) returning nil, like every other role).
        let stationFormat = stationConnectionFormat ?? runFormat
        let station = AVAudioPlayerNode()
        attachHandler(station, stationFormat)
        attachedFormats[ObjectIdentifier(station)] = stationFormat
        stationPlayer = station
    }

    /// batch84 (device crash hunt, load hypothesis): warm this
    /// family's curve-referenced bands and the running beds
    /// into the buffer cache at family resolution (route start,
    /// at a standstill) instead of letting each buffer's first
    /// load land mid-drive. buffer(named:) is a synchronous
    /// disk read + Float32 decode on the main actor, and before
    /// this change the brake band set loaded progressively
    /// DURING the first decelerations — inside update(), in
    /// the same frames as the slot churn it feeds — while the
    /// power bands loaded the same way during the first
    /// acceleration and the 36 s tunnel bed (~12 MB decoded,
    /// the largest single buffer) on first tunnel entry. The
    /// cache only ever grows, so warming changes WHEN the cost
    /// is paid, not how much memory a session ends up holding;
    /// no gains, curves or playback behavior change.
    private func warmBuffers(for family: String) {
        var names = Set<String>()
        for mode in ["power", "brake"] {
            for step in curves[family]?[mode] ?? [] {
                names.formUnion(step.gains.keys)
            }
        }
        for name in names { _ = buffer(named: name) }
        for bed in ["run_e231_run6", "run_ballast", "run_tunnel", "run_bridge", "run_prim_tunnel", "run_prim_bridge", "ambient_fan_prim", "flange_0", "flange_1", "ambient_station"] {
            _ = buffer(named: bed)
        }
    }

    private func playLoop(_ player: AVAudioPlayerNode, sample: String) -> Bool {
        guard let buffer = buffer(named: sample) else {
            notePlayFailure()
            return false
        }
        // Players are pre-attached with the probe file's format and
        // buffers are scheduled raw in the same file format (see
        // buffer(named:)), so this guard is a safety net rather
        // than a silent-skip path (CI #147), and no attach is
        // attempted at runtime (CI #163).
        guard let connected = attachedFormats[ObjectIdentifier(player)],
              connected == buffer.format else {
            notePlayFailure()
            return false
        }
        player.stop()
        player.scheduleBuffer(buffer, at: nil, options: .loops)
        player.play()
        consecutivePlayFailures = 0
        return true
    }

    /// batch77: fail-over latch. If loop playback keeps failing
    /// (missing buffer / format mismatch), the sampled path
    /// eventually declares itself broken so isActive goes false
    /// and the host un-mutes the synthesized DSP traction instead
    /// of leaving the cab completely silent — the IPA #4–#8
    /// failure mode, where a dead sampled path muted the synth
    /// and nothing sounded at all.
    private func notePlayFailure() {
        playFailureCount += 1
        consecutivePlayFailures += 1
        if consecutivePlayFailures >= 8 {
            playbackBroken = true
        }
    }

    private func approach(_ current: Float, _ target: Float) -> Float {
        current + (target - current) * 0.4
    }

    /// batch79: cooling-fan ambience (the user's standing
    /// "ambience while stopped" request). The fan recording
    /// loops at low gain while the train is stopped or crawling
    /// (< 5 km/h) on the VVVF-derived families whose stock
    /// carries this fan; it fades out as soon as the train is
    /// properly moving, where the run bed takes over the
    /// soundscape. Driven independently of the band crossfade
    /// so a broken/latched motor path cannot silence it, and
    /// silenced through master == 0 when audio is disabled.
    private func updateAmbientFan(family: String, snapshot: RailwaySimulationSnapshot, master: Float, engineRunning: Bool) {
        guard let player = ambientPlayer else { return }
        let fanFamily = family == "vvvf" || family == "primrose" || family == "primrose_r"
        let speedKmh = max(0, snapshot.speedMetersPerSecond) * 3.6
        let target: Float = fanFamily && speedKmh < 5 ? master * 0.22 : 0
        if target > 0.01 {
            if ambientSample == nil {
                if engineRunning, playLoop(player, sample: "ambient_fan_prim") {
                    ambientSample = "ambient_fan_prim"
                    player.volume = 0
                }
            } else if engineRunning, !player.isPlaying {
                _ = playLoop(player, sample: "ambient_fan_prim")
            }
            player.volume = approach(player.volume, target)
            if !engineRunning { startHandler?() }
        } else {
            player.volume = approach(player.volume, 0)
            if player.volume < 0.005, ambientSample != nil {
                player.stop()
                ambientSample = nil
                player.volume = 0
            }
        }
    }

    /// batch106: station ambience bed (the user's standing
    /// "ambience while stopped" request, platform side — the
    /// batch102 audit found no usable recording in any bundled
    /// library, so this bed is a CC0 platform recording sourced
    /// externally; provenance and loop treatment in
    /// MAPPING.md §14). It follows the fan's drive pattern
    /// exactly: an independent loop, started/stopped through
    /// the approach() gain ramp so there are no clicks, and
    /// silenced through master == 0 when audio is disabled.
    ///
    /// Gate signal: snapshot.isAtStation, plumbed in batch106
    /// from SimulatorModel's gameModeCurrentStationID (set on
    /// arrival at a stop, cleared on departure) through the
    /// existing snapshot/update path — no new channel. The
    /// alternatives already on the snapshot cannot express
    /// "at a station": doorsOpen drops 12 s after arrival when
    /// the door cycle closes, while the train may still be
    /// dwelling at the platform, and speed < 5 km/h alone (the
    /// fan's gate) is also true at signals and other mid-line
    /// stops where a platform bed would be wrong. The speed
    /// term is kept as a belt-and-braces condition so a stale
    /// at-station flag can never leak the bed into a run.
    /// Gain is master × 0.15, deliberately below the fan's
    /// 0.22: the bed sits under the fan and the cab sounds.
    private func updateStationAmbience(snapshot: RailwaySimulationSnapshot, master: Float, engineRunning: Bool) {
        guard let player = stationPlayer else { return }
        let speedKmh = max(0, snapshot.speedMetersPerSecond) * 3.6
        let target: Float = snapshot.isAtStation && speedKmh < 5 ? master * 0.15 : 0
        if target > 0.01 {
            if stationSample == nil {
                if engineRunning, playLoop(player, sample: "ambient_station") {
                    stationSample = "ambient_station"
                    player.volume = 0
                }
            } else if engineRunning, !player.isPlaying {
                _ = playLoop(player, sample: "ambient_station")
            }
            player.volume = approach(player.volume, target)
            if !engineRunning { startHandler?() }
        } else {
            player.volume = approach(player.volume, 0)
            if player.volume < 0.005, stationSample != nil {
                player.stop()
                stationSample = nil
                player.volume = 0
            }
        }
    }

    /// batch94: recorded flange squeal on curves, replacing
    /// the DSP's synthesized curveSqueal (removed — the
    /// batch79 precedent: once a real recording is wired, the
    /// synth goes). The trigger signal is the same one the
    /// synth keyed on, snapshot.curveRadiusMeters (physics
    /// effective radius), supplied on every snapshot.
    ///
    /// Zone and gain law: the batch63 design note specified
    /// radius < 250 m, but the game's measured geometry has
    /// NO curve that tight — the factory's tightest zone
    /// range bottoms at 300 m, the pinned curves are
    /// 450–1,100 m and the zoo line's curve is R373 — so a
    /// literal 250 m gate would be dead code on every route
    /// (the bundled-but-dead failure mode). The zone is
    /// therefore radius < 620 m with a tightness ramp that
    /// reaches full gain at 280 m and fades to zero at the
    /// boundary: tightness = clamp((620 − r) / 340, 0, 1).
    /// Speed: silent at and below 15 km/h (the design note's
    /// floor), ramping to full at 40 km/h. Target volume is
    /// master × 0.22 × tightness × speedRamp, which lands the
    /// loop (RMS ≈ −15 dBFS after the −3 dBFS peak
    /// normalization) at about the level the synth occupied.
    /// Successive curve entries alternate flange_0 / flange_1.
    private func updateFlangeSqueal(snapshot: RailwaySimulationSnapshot, master: Float, engineRunning: Bool) {
        guard let player = flangePlayer else { return }
        let speedKmh = max(0, snapshot.speedMetersPerSecond) * 3.6
        var tightness: Float = 0
        if let radius = snapshot.curveRadiusMeters, radius.isFinite, radius > 0, radius < 620 {
            tightness = min(1, max(0, (620 - radius) / 340))
        }
        let speedRamp = min(1, max(0, (speedKmh - 15) / 25))
        let target = master * 0.22 * tightness * speedRamp
        let inZone = target > 0.01
        if inZone {
            if !flangeWasInZone {
                flangeEntryCount += 1
            }
            let takes = ["flange_0", "flange_1"]
            let desired = takes[(flangeEntryCount - 1) % takes.count]
            if flangeSample != desired {
                if engineRunning, playLoop(player, sample: desired) {
                    flangeSample = desired
                    player.volume = 0
                } else {
                    flangeSample = nil
                }
            } else if engineRunning, !player.isPlaying {
                _ = playLoop(player, sample: desired)
            }
            player.volume = approach(player.volume, target)
            if !engineRunning { startHandler?() }
        } else {
            player.volume = approach(player.volume, 0)
            if player.volume < 0.005, flangeSample != nil {
                player.stop()
                flangeSample = nil
                player.volume = 0
            }
        }
        flangeWasInZone = inZone
    }

    func update(snapshot: RailwaySimulationSnapshot, settings: RailwayAudioSettings, isEnabled: Bool, engineRunning: Bool) {
        loadCurvesIfNeeded()
        // batch79: VVVF profiles (the E231 services) default to
        // the Primrose family when its curves are bundled; the
        // LEYokohama "vvvf" family remains the fallback for a
        // build without the Primrose set. primrose_r curves are
        // merged into motor_curves.json as well, but no vehicle-
        // variant selection exists in the game today, so no
        // profile resolves to primrose_r yet (see MAPPING.md).
        var family = familyKey(for: settings.tractionSoundProfile)
        if family == "vvvf", curves["primrose"] != nil {
            family = "primrose"
        }
        let master = isEnabled ? settings.masterVolume : 0
        // batch79: the cooling-fan ambience loop is independent
        // of the band crossfade's active state, so it is driven
        // before the guard below (and silenced through the same
        // path when audio is disabled).
        updateAmbientFan(family: family, snapshot: snapshot, master: master, engineRunning: engineRunning)
        // batch94: the flange-squeal loop is likewise driven
        // before the guard, independent of the band path.
        updateFlangeSqueal(snapshot: snapshot, master: master, engineRunning: engineRunning)
        // batch106: the station ambience bed is likewise driven
        // before the guard, independent of the band path.
        updateStationAmbience(snapshot: snapshot, master: master, engineRunning: engineRunning)
        // batch67: "active" must mean audible (see isActive note).
        // batch77: a latched-broken playback path (notePlayFailure)
        // also reports inactive, so the DSP synth takes over.
        isActive = curves[family] != nil && !motorPlayers.isEmpty && !playbackBroken
        guard isActive, attachHandler != nil else {
            if motorPlayers.contains(where: { $0.isPlaying }) {
                motorPlayers.forEach { $0.stop() }
                runPlayer?.stop()
            }
            return
        }
        // Players were pre-attached during engine init; if that did
        // not happen (missing buffers), the subsystem stays inert
        // rather than touching the graph at runtime.
        guard !motorPlayers.isEmpty else {
            if snapshot.powerNotch > 0, !engineRunning { startHandler?() }
            return
        }
        if family != currentFamily {
            currentFamily = family
            warmBuffers(for: family)
            for index in motorPlayers.indices {
                motorPlayers[index].stop()
                motorSlotSample[index] = nil
                motorPlayers[index].volume = 0
            }
            runPlayer?.stop()
            runSample = nil
            runPlayer?.volume = 0
        }

        let speedKmh = max(0, snapshot.speedMetersPerSecond) * 3.6
        let motoring = snapshot.powerNotch > 0
        let braking = snapshot.brakeCommand > 0.03 || snapshot.regenerativeBrakeRatio > 0.03
        var desired: [String: Float] = [:]
        if motoring {
            desired = interpolatedGains(family: family, mode: "power", speedKmh: speedKmh)
        } else if braking {
            desired = interpolatedGains(family: family, mode: "brake", speedKmh: speedKmh)
        }
        // batch73-audit insurance: the door gate must not kill the
        // motor sound while moving — if a close transition is ever
        // missed, doorsOpen would otherwise silence motoring for
        // the whole run. At standstill the speed gate below already
        // empties desired, so this stays a standstill-only gate.
        if snapshot.doorsOpen && speedKmh < 0.5 { desired = [:] }
        // batch63（追加指示・実機指摘）: 停車中はモーター音ゼロ。
        // カーブの 0km/h ステップには帯域音量が残っている
        // （力行 motor_vvvf_09: 0.787、制動 motor_vvvf_15: 0.787）
        // ため、速度がほぼ 0 の間はノッチ・ブレーキによらず
        // desired を空にする。これがないと、発車前にモーター音
        // だけが先行して鳴り、停車中も制動帯域が鳴り続ける。
        // 惰行（ノッチOFF・無制動）は従来どおり desired が空で無音。
        if speedKmh < 0.5 { desired = [:] }
        let desiredSorted = desired.sorted { $0.value > $1.value }.prefix(3)
        if let top = desiredSorted.first {
            lastDesiredSummary = "\(top.key)@\(String(format: "%.2f", top.value))"
        } else {
            lastDesiredSummary = "-"
        }

        var wantsSound = false
        // Keep samples already playing in their slots where possible.
        var assignment: [Int: (name: String, volume: Float)] = [:]
        var usedNames = Set<String>()
        for (slot, current) in motorSlotSample.enumerated() {
            if let current, let volume = desired[current] {
                assignment[slot] = (current, volume)
                usedNames.insert(current)
            }
        }
        for entry in desiredSorted where !usedNames.contains(entry.key) {
            if let free = motorSlotSample.indices.first(where: { assignment[$0] == nil && motorSlotSample[$0] == nil })
                ?? motorSlotSample.indices.first(where: { assignment[$0] == nil }) {
                assignment[free] = (entry.key, entry.value)
                usedNames.insert(entry.key)
            }
        }
        for slot in motorPlayers.indices {
            let player = motorPlayers[slot]
            if let target = assignment[slot] {
                if motorSlotSample[slot] != target.name {
                    if engineRunning, playLoop(player, sample: target.name) {
                        motorSlotSample[slot] = target.name
                        player.volume = 0
                    } else {
                        motorSlotSample[slot] = nil
                        continue
                    }
                } else if engineRunning, !player.isPlaying, buffer(named: target.name) != nil {
                    _ = playLoop(player, sample: target.name)
                }
                // batch83: family staging. The legacy families
                // keep the long-standing 0.85. The Primrose
                // families get 1.35: their bundled band WAVs are
                // RMS-normalized to -18 dBFS (batch83, see
                // MAPPING.md §9 — the raw conversions spanned
                // -56..-20 dBFS across bands, which is why the
                // low-speed bands were inaudible on IPA #10 even
                // at curve gain 1.0), and 1.35 is the staging
                // that lands the harness power phase at about
                // -19 dBFS with the loudest band's peak about
                // -5 dBFS in the mix (player volume stays below
                // 1.0: max is 1.0 x master x 1.35).
                let staging: Float = (family == "primrose" || family == "primrose_r") ? 1.35 : 0.85
                let targetVolume = min(1, target.volume) * master * staging
                player.volume = approach(player.volume, targetVolume)
                if targetVolume > 0.02 { wantsSound = true }
            } else {
                player.volume = approach(player.volume, 0)
                if player.volume < 0.005, motorSlotSample[slot] != nil {
                    player.stop()
                    motorSlotSample[slot] = nil
                    player.volume = 0
                }
            }
        }

        // Running (rail) noise loop, chosen by section type.
        if let player = runPlayer {
            let desiredRun: String
            // batch79: the Primrose [Run] variants take over the
            // two surfaces the snapshot already knows (tunnel /
            // bridge) for the Primrose families; the LEYokohama
            // beds remain the fallback and stay in charge for
            // the other families. The slab / speno / harasco /
            // 120long variants have no determinable surface flag
            // in the snapshot, so they stay staged-only.
            let isPrimroseFamily = family == "primrose" || family == "primrose_r"
            if snapshot.isInTunnel {
                if isPrimroseFamily, buffer(named: "run_prim_tunnel") != nil {
                    desiredRun = "run_prim_tunnel"
                } else {
                    desiredRun = "run_tunnel"
                }
            } else if snapshot.isOnBridge {
                if isPrimroseFamily, buffer(named: "run_prim_bridge") != nil {
                    desiredRun = "run_prim_bridge"
                } else {
                    desiredRun = "run_bridge"
                }
            } else if family == "vvvf" || isPrimroseFamily {
                // batch83: 継目区間でもベッドは継目ニュートラルな
                // Run6 に統一する。batch78 は継目区間に Run3（継目
                // の打音が録音自体に入っている）を敷いたが、batch79
                // で Primrose [Joint] の距離発火ワンショットが入り、
                // ベッド内蔵の継目とワンショットの継目が独立した
                // 位相で重なって「リズムが速度に合わない」実機指摘
                // （IPA #10）になった。継目のリズムは距離ベースで
                // 発火するワンショットだけが担い、ベッドは全区間
                // Run6（継目なし）とする単一音源化。run_e231_run3
                // は同梱のまま残すが、ベッドとしては選ばない。
                // （21:31 の Run3 採用決定は、ワンショット継目音が
                // 無かった時点での最善手であり、Primrose 専用音の
                // 到着で前提が変わった。）
                // バッファが無い環境では run_ballast へフォール
                // バックする（従来の Run6 側フォールバックと同じ）。
                if buffer(named: "run_e231_run6") != nil {
                    desiredRun = "run_e231_run6"
                } else {
                    desiredRun = "run_ballast"
                }
            } else {
                desiredRun = "run_ballast"
            }
            // batch78: BVE 式ピッチ。Run6 は 90 km/h 基準の録音
            // なので、バリスピードを速度比で駆動して走行音の
            // ピッチを速度に追随させる。他のベッドは等速（1.0）。
            // batch83: 継目の周期はベッドではなく距離発火の
            // ワンショットが担う（上記のベッド選択を参照）。
            // ハーネスのように runAttachHandler が無い構成では
            // varispeed がグラフ外なので、この書き込みは無害。
            if let runVarispeed {
                // batch79: reference speeds — Run6 and the
                // Primrose bridge bed follow the BVE 90 km/h
                // recording convention; the Primrose tunnel bed
                // is the "tunel110" recording, referenced to
                // 110 km/h (from its source file name). batch83:
                // run_e231_run3 keeps its 90 km/h entry for
                // compatibility but is no longer selected as a
                // bed (see the bed selection above).
                let referenceKmh: Float?
                switch desiredRun {
                case "run_e231_run3", "run_e231_run6", "run_prim_bridge":
                    referenceKmh = 90
                case "run_prim_tunnel":
                    referenceKmh = 110
                default:
                    referenceKmh = nil
                }
                if let referenceKmh {
                    runVarispeed.rate = Float(min(1.5, max(0.35, speedKmh / referenceKmh)))
                } else {
                    runVarispeed.rate = 1
                }
            }
            // batch63（追加指示・実機指摘）: 転動音は速度比例に
            // 限定する。3km/h 未満は無音、以降は速度比の二乗で
            // 立ち上げて低速域をほぼ無音に保ち、上限（master×0.45）
            // もモーター音の上限（master×0.85）より十分低く抑える。
            // 録音ループを速度と無関係に丸ごと流すことはしない。
            let rollFactor = min(1, speedKmh / 75)
            let targetVolume = speedKmh < 3 ? 0 : rollFactor * rollFactor * master * 0.45
            if targetVolume > 0.01 {
                wantsSound = true
                if runSample != desiredRun {
                    if engineRunning, playLoop(player, sample: desiredRun) {
                        runSample = desiredRun
                        player.volume = 0
                    }
                } else if engineRunning, !player.isPlaying {
                    _ = playLoop(player, sample: desiredRun)
                }
                player.volume = approach(player.volume, targetVolume)
            } else {
                player.volume = approach(player.volume, 0)
                if player.volume < 0.005, runSample != nil {
                    player.stop()
                    runSample = nil
                    player.volume = 0
                }
            }
        }

        if wantsSound { startHandler?() }
    }
}
#endif
