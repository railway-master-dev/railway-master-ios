// AudioHarnessTests.swift
//
// OFFLINE AUDIO VERIFICATION HARNESS — a diagnostic tool, not a unit
// test of record. Built after IPA #8 and IPA #9 both shipped blind
// audio fixes that the device falsified (sampled motor silent, a
// periodic noise from loading onward, joint clicks never heard).
// Static audits kept concluding "healthy"; this harness exists so the
// next fix is proven by a rendered recording and per-phase numbers
// BEFORE an IPA is built. See AUDIO_HARNESS_RUNBOOK.md in the goal
// workspace (hidden_files) for how to run it on the Mac and what to
// bring back.
//
// WHAT IT WIRES (all production code, no reimplementation):
//   - ProceduralAudioDSP, driven through an AVAudioSourceNode whose
//     render block is the identical block RailwayAudioEngine.init
//     installs, so the DSP bed + event voices render exactly as in
//     the app.
//   - SampledMotorSound, through its designed host interface
//     (attachHandler / startHandler / preattachIfNeeded / update),
//     with the harness AVAudioEngine standing in for the host engine
//     exactly as RailwayAudioEngine does.
//   - The production graph topology: source -> mixer -> reverb ->
//     main mixer, sample players fanning into the same mixer (the
//     batch74 lesson: topology is where the last silence lived).
//   - FictionalTrackImpactTracker (RailwayAudioEnhancements) for the
//     impact schedule: 25 m jointed rail near stations, 800 m CWR
//     elsewhere, point clatter over turnouts — the same tracker and
//     the same advance() call SimulatorModel.cueWaysideAudio makes.
//   - RailwayAudioEngine.playTrackImpact's control flow, mirrored
//     line for line (batch79): point_pass one-shot for points;
//     for rail joints, the representative event only (leading
//     bogie — production filters in SimulatorModel
//     .cueWaysideAudio) plays a Primrose [Joint] recording on
//     the one-shot pool: joint_prim_p1 on plain rail, the p45
//     variants in rotation inside a turnout span. batch97: below
//     RailwayAudioEngine.lowSpeedJointClackMaxKmh, plain joints
//     instead fire joint_clack (a single-bogie cut from p1) for
//     EVERY bogie — the mirror below follows the same split and
//     counts them separately (jointClacks / jointClackPlays);
//     the script starts from standstill, so the first joint
//     marks exercise the clack branch. NO synthesized
//     impact exists any more: batch79 removed the DSP voice and
//     the bed pulse after the first harness run measured them
//     firing per bogie unit (245 + 245 over 498 m, ~0.40 s
//     period — the device ザッザッ).
//
// WHAT IT CANNOT WIRE, AND WHY (ciAudioDisabled):
//   RailwayAudioEngine.ciAudioDisabled is a cached static let that
//   is TRUE under every XCTest host run (it keys on
//   XCTestConfigurationFilePath, which XCTest always sets), and the
//   production engine init then builds NO graph at all. Its
//   AVAudioEngine is also private and is started through
//   AVAudioSession in real-time mode, so the full engine class
//   cannot be switched into AVAudioEngine manual (offline)
//   rendering without changing production code — which this harness
//   deliberately does not do. Instead the harness instantiates the
//   real RailwayAudioEngine as a PROBE and prints its statusLogLine:
//   under XCTest it shows ciDisabled=1 / enabled=0, which is itself
//   the evidence for why component-level rendering is the only
//   offline route. The one production mechanism NOT exercised here
//   is the bundled one-shot POOL bookkeeping inside
//   RailwayAudioEngine (round-robin voices); the harness substitutes
//   a minimal pool (HarnessOneShotPool) that reproduces the pool's
//   mechanism — buffers loaded raw from Bundle.main in their own
//   file format, player stopped before scheduling — for the horn
//   reference, point_pass and the DSP's brake-air cue handler. The
//   DSP brake-transition logic itself (which names it requests and
//   when) is production code and IS exercised via cueSampleHandler.
//
// BATCH78 NOTE (superseded in part by batch79): the harness
// originally installed only SampledMotorSound's attachHandler,
// leaving the production AVAudioUnitVarispeed seam unproven.
// BATCH79: the harness now ALSO installs runAttachHandler,
// mirroring RailwayAudioEngine.attachLicensedRunPlayer's exact
// operations (attach player + varispeed, connect player ->
// varispeed -> mixer) on the harness engine, so the run-bed
// selection AND the BVE-style pitch driving render here.
// BATCH83: the bed selection no longer switches by section
// (Run6 everywhere; the Run3 bed's baked-in joint clatter
// clashed with the distance-fired [Joint] one-shots on device)
// and the runner now verifies the leading bogie's joint
// events against the 25 m grid (JOINT_GRID lines below).
// The production method itself cannot be the render path (the
// probe engine is ci-disabled and never renders), so the
// mirror is the feasible route — the operations are identical.
// The per-step notch table, the B7 click and the key/reverser
// session cues live in RailwayAudioEngine / SimulatorModel,
// which this harness cannot instantiate (see ciAudioDisabled
// above); their samples are preloaded here only as a bundle
// load check.
// BATCH79 also: the default VVVF profile now resolves to the
// Primrose motor family inside SampledMotorSound, so this
// render exercises the primrose curves and motor_prim_*
// samples (mono, bundled); and the cooling-fan ambience loop
// is EXPECTED in the standstill phases at low level — a steady
// hum around the fan's level, not a periodic pulse. Read the
// 0.25 s standstill rows with that in mind: uniform low rows
// are the fan; repeating bursts above them would be a defect.
//
// OPT-IN: the test SKIPS unless RM_AUDIO_HARNESS=1 is in the test
// host's environment, so the normal suite and CI never pay the
// render cost. Do NOT run it with RM_DISABLE_AUDIO set and do NOT
// run it through ci_run.sh (which exports
// SIMCTL_CHILD_RM_DISABLE_AUDIO=1 for its own builds).
//
// OUTPUTS (host app's Documents/audio_harness/, also printed to the
// test log):
//   - audio_harness_drive.wav    16-bit PCM, 48 kHz stereo mix
//   - audio_harness_report.txt   status lines + per-second levels +
//                                phase summaries + standstill detail
// Assertions are limited to harness infrastructure (engine started,
// render completed, horn reference audible, motor curves loaded).
// Whether the motor / joints / standstill bed are audible is
// REPORTED as HARNESS_VERDICT lines, never asserted — measuring
// that is the entire point.

import AudioToolbox
import AVFoundation
import Foundation
import RailwayAudioEnhancements
import XCTest
@testable import RailwayMasterPhase1

final class AudioHarnessTests: XCTestCase {
    func testOfflineAudioHarnessRender() async throws {
        let env = ProcessInfo.processInfo.environment
        try XCTSkipUnless(
            env["RM_AUDIO_HARNESS"] == "1",
            "Audio harness is opt-in: set RM_AUDIO_HARNESS=1 (see AUDIO_HARNESS_RUNBOOK.md)."
        )
        let failures = await MainActor.run { AudioHarnessRunner().run() }
        for failure in failures {
            XCTFail(failure)
        }
    }
}

/// Minimal stand-in for RailwayAudioEngine's bundled one-shot pool.
/// NOT production code: it reproduces the pool's mechanism (raw
/// Bundle.main buffers in their own processingFormat, a player
/// stopped before each schedule) so the horn reference, point_pass
/// and the DSP's brake-air sample requests can sound inside the
/// harness graph. Two voices per format; production uses four and
/// adds a 0.15 s proximity suppression for brake names, which the
/// script never triggers (brake transitions are seconds apart).
private final class HarnessOneShotPool {
    private struct Pool {
        var format: AVAudioFormat
        var players: [AVAudioPlayerNode]
        var cursor: Int
    }

    private var pools: [Pool] = []
    private var buffers: [String: AVAudioPCMBuffer] = [:]
    private var missingNames: [String] = []
    private let volume: Float

    init(volume: Float) {
        self.volume = volume
    }

    /// Loads each named buffer and pre-attaches two players per
    /// distinct format, mirroring preattachBundledPlayers. Returns
    /// human-readable log lines (loaded / MISSING per name).
    func prepare(names: [String], engine: AVAudioEngine, mixer: AVAudioMixerNode) -> [String] {
        var lines: [String] = []
        for name in names {
            guard let url = Bundle.main.url(forResource: name, withExtension: "wav"),
                  let file = try? AVAudioFile(forReading: url),
                  let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat,
                                                frameCapacity: AVAudioFrameCount(file.length)),
                  (try? file.read(into: buffer)) != nil else {
                missingNames.append(name)
                lines.append("oneshot MISSING \(name).wav (not in Bundle.main)")
                continue
            }
            buffers[name] = buffer
            if pools.firstIndex(where: { $0.format == buffer.format }) == nil {
                var players: [AVAudioPlayerNode] = []
                for _ in 0..<2 {
                    let player = AVAudioPlayerNode()
                    engine.attach(player)
                    engine.connect(player, to: mixer, format: buffer.format)
                    players.append(player)
                }
                pools.append(Pool(format: buffer.format, players: players, cursor: 0))
            }
            lines.append("oneshot loaded \(name).wav format=\(Int(buffer.format.sampleRate))Hz/\(buffer.format.channelCount)ch frames=\(buffer.frameLength)")
        }
        return lines
    }

    /// Production semantics: false means "nothing sounded" so the
    /// caller falls back to synthesis, exactly like
    /// playBundledSampleOneShot.
    @discardableResult
    func play(named name: String) -> Bool {
        guard let buffer = buffers[name],
              let poolIndex = pools.firstIndex(where: { $0.format == buffer.format }) else {
            return false
        }
        let cursor = pools[poolIndex].cursor
        pools[poolIndex].cursor = cursor + 1
        let player = pools[poolIndex].players[cursor % pools[poolIndex].players.count]
        player.stop()
        player.volume = volume
        player.scheduleBuffer(buffer, at: nil, options: [])
        player.play()
        return true
    }
}

@MainActor
private final class AudioHarnessRunner {
    private var lines: [String] = []
    private var failures: [String] = []

    private func log(_ line: String) {
        lines.append(line)
        print(line)
    }

    private func fail(_ line: String) {
        failures.append(line)
        log("HARNESS_FAILURE " + line)
    }

    private func dbfs(_ value: Float) -> Float {
        value > 0 ? 20 * log10f(value) : -120
    }

    /// RMS / peak over both channels for a frame range.
    private func stats(left: [Float], right: [Float], from: Int, to: Int) -> (rms: Float, peak: Float) {
        let lo = max(0, from)
        let hi = min(to, left.count)
        guard hi > lo else { return (0, 0) }
        var sumSq: Double = 0
        var peak: Float = 0
        for index in lo..<hi {
            let l = left[index]
            let r = right[index]
            sumSq += Double(l * l) + Double(r * r)
            peak = max(peak, max(abs(l), abs(r)))
        }
        let rms = Float(sqrt(sumSq / Double(2 * (hi - lo))))
        return (rms, peak)
    }

    func run() -> [String] {
        log("=== AUDIO HARNESS: offline render of production audio components ===")
        let env = ProcessInfo.processInfo.environment
        log("env RM_AUDIO_HARNESS=\(env["RM_AUDIO_HARNESS"] ?? "-") RM_DISABLE_AUDIO=\(env["RM_DISABLE_AUDIO"] ?? "-")")
        log("RailwayAudioEngine.ciAudioDisabled=\(RailwayAudioEngine.ciAudioDisabled ? 1 : 0)")

        // Production-engine probe: under XCTest this documents, with
        // the engine's own status line, that the full engine is
        // disabled by design in a test host (see header).
        let probe = RailwayAudioEngine()
        log("PROBE RailwayAudioEngine: " + probe.statusLogLine)

        // --- Graph (production topology, harness-owned engine) ---
        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 48_000, channels: 2, interleaved: false)!
        let dsp = ProceduralAudioDSP()
        let engine = AVAudioEngine()
        let reverb = AVAudioUnitReverb()
        let mixer = AVAudioMixerNode()
        // The render block below is the identical block
        // RailwayAudioEngine.init installs on its source node.
        let sourceNode = AVAudioSourceNode(format: format) { isSilence, _, frameCount, audioBufferList in
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
        engine.attach(sourceNode)
        engine.attach(reverb)
        engine.attach(mixer)
        reverb.loadFactoryPreset(.mediumRoom)
        reverb.wetDryMix = 0
        engine.connect(sourceNode, to: mixer, format: format)
        engine.connect(mixer, to: reverb, format: format)
        engine.connect(reverb, to: engine.mainMixerNode, format: format)
        engine.mainMixerNode.outputVolume = 1

        // --- Sampled motor through its designed host interface ---
        let motor = SampledMotorSound()
        motor.attachHandler = { node, nodeFormat in
            engine.attach(node)
            engine.connect(node, to: mixer, format: nodeFormat)
        }
        // batch79: mirror the production run attach
        // (attachLicensedRunPlayer) so the varispeed seam is
        // part of the proven graph — see the batch79 note in
        // the header.
        motor.runAttachHandler = { node, varispeed, nodeFormat in
            engine.attach(node)
            engine.attach(varispeed)
            engine.connect(node, to: varispeed, format: nodeFormat)
            engine.connect(varispeed, to: mixer, format: nodeFormat)
        }
        motor.startHandler = {
            // The harness starts the engine itself before the script;
            // production's handler calls RailwayAudioEngine.start().
        }
        motor.preattachIfNeeded()

        // --- Reference one-shots + the DSP's sample cue handler ---
        let settings = RailwayAudioSettings(masterVolume: 0.65)
        let pool = HarnessOneShotPool(volume: 0.65)
        for line in pool.prepare(
            names: ["horn_e231_short", "point_pass",
                    "brake_apply_1", "brake_apply_2", "brake_apply_3", "brake_apply_4",
                    "brake_release",
                    // batch78: the newly wired samples — preloading
                    // them here makes a missing/misregistered bundle
                    // resource show up as a MISSING line in the
                    // harness report instead of silence on device.
                    // The beds are also loaded by SampledMotorSound
                    // itself; listing them doubles as a load check.
                    "notch_on_2", "notch_on_3", "notch_on_4",
                    "notch_off_2", "notch_off_3",
                    "brake_max_click", "key_on", "reverser_on",
                    "run_e231_run3", "run_e231_run6",
                    // batch79: the Primrose joint recordings the
                    // impact router below actually plays.
                    // batch97: the low-speed single-bogie clack.
                    "joint_prim_p1", "joint_clack",
                    "joint_prim_p45_0_0", "joint_prim_p45_0_1",
                    "joint_prim_p45_1_0", "joint_prim_p45_1_1"],
            engine: engine, mixer: mixer
        ) {
            log(line)
        }
        dsp.cueSampleHandler = { name in pool.play(named: name) }

        // --- Offline (manual) rendering ---
        do {
            try engine.enableManualRenderingMode(.offline, format: format, maximumFrameCount: 4096)
            engine.prepare()
            try engine.start()
        } catch {
            fail("engine failed to start in manual rendering mode: \(error.localizedDescription)")
            return failures
        }
        log("engine running=\(engine.isRunning ? 1 : 0) manualFormat=\(Int(engine.manualRenderingFormat.sampleRate))Hz/\(engine.manualRenderingFormat.channelCount)ch")

        // --- Outputs ---
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let outDir = documents.appendingPathComponent("audio_harness", isDirectory: true)
        try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
        let wavURL = outDir.appendingPathComponent("audio_harness_drive.wav")
        try? FileManager.default.removeItem(at: wavURL)
        let wavSettings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatLinearPCM),
            AVSampleRateKey: 48_000,
            AVNumberOfChannelsKey: 2,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
        ]
        let wavFile = try? AVAudioFile(forWriting: wavURL, settings: wavSettings, commonFormat: .pcmFormatFloat32, interleaved: false)
        if wavFile == nil {
            fail("could not create WAV file at \(wavURL.path)")
        }
        log("output directory: \(outDir.path)")

        // --- Scripted drive ---
        // A: 0-10 s standstill at the origin platform (doors open,
        //    brake held) — the phase where the device hears the
        //    periodic noise even on the loading screen's tail.
        // B: 10-40 s power: notch steps P1..P5 at 2 s intervals,
        //    accelerating to the 60 km/h script cap.
        // C: 40-50 s coast (notch off, no brake).
        // D: 50 s- braking in three steps (0.40 / 0.65 / 0.90, then
        //    1.00 after 78 s as a schedule safety) down to a stop.
        // E: standstill again until 84 s (doors reopen).
        // Snapshots are fed at 20 Hz — production feeds per model
        // tick; SampledMotorSound's per-call volume approach makes
        // the exact cadence audible in ramp shapes, so it is fixed
        // and documented here rather than left to the render loop.
        let dt = 0.05
        let stepFrames = 2400
        let totalSeconds = 84.0
        let renderBuffer = AVAudioPCMBuffer(pcmFormat: engine.manualRenderingFormat, frameCapacity: 4096)!
        var leftAll: [Float] = []
        var rightAll: [Float] = []
        leftAll.reserveCapacity(4_100_000)
        rightAll.reserveCapacity(4_100_000)

        var tracker = FictionalTrackImpactTracker(carCount: 8)
        // Mirror of SimulatorModel.isInsideTurnout for this
        // script's fixed path/direction/consist (mainline, up,
        // 8 cars): re-evaluates the schedule's locate/turnouts
        // at the firing bogie's own position.
        func harnessInsideTurnout(_ impact: FictionalTrackImpact) -> Bool {
            let offsets = FictionalTrackImpactSchedule.bogieOffsets(carCount: 8)
            guard offsets.indices.contains(impact.bogieIndex) else { return false }
            let bogieRoute = impact.routePositionM - offsets[impact.bogieIndex]
            guard let located = FictionalTrackImpactSchedule.locate(path: .mainline, direction: .up, routePositionM: bogieRoute) else { return false }
            return !FictionalTrackImpactSchedule.turnouts(containing: located.line, chainageM: located.chainageM).isEmpty
        }
        var time = 0.0
        var speed = 0.0
        var position = 0.0
        var stepIndex = 0
        var hornFired = false
        var stopTime: Double?
        var jointImpacts = 0
        var pointImpacts = 0
        var jointPlays = 0
        var pointPlays = 0
        // batch97: low-speed per-bogie clack events and plays,
        // counted apart from the representative p1/p45 events.
        var jointClackImpacts = 0
        var jointClackPlays = 0
        // batch83: joint-grid verification. The fired side is
        // collected from the tracker's raw impacts (leading
        // bogie only); the expected side is computed
        // independently below from the schedule's own locate /
        // isRailJoint over the leading bogie's chainage interval
        // each step — the same (previous, current] interval
        // semantics and 0.35 m/s audible gate the tracker uses,
        // re-derived here so a tracker regression (dropped,
        // duplicated or off-grid events) shows up as a mismatch
        // instead of passing silently. Scoped to this script's
        // fixed path (mainline, up): marks are the 25 m grid.
        var firedJointChainages: [Double] = []
        var expectedJointChainages: [Double] = []
        var previousBogieChainage: Double?
        var jointVariantCursor = 0
        var badRenderCount = 0
        var phaseMarks: [(name: String, start: Double, end: Double)] = []
        var currentPhase = ""
        var phaseStart = 0.0
        var peakSpeedKmh = 0.0

        func scriptPhase(at t: Double, stopped: Bool) -> (name: String, notch: Int, brake: Float) {
            if t < 10 { return ("A-standstill", 0, 0.6) }
            if t < 40 {
                var notch = 1
                if t >= 18 { notch = 5 }
                else if t >= 16 { notch = 4 }
                else if t >= 14 { notch = 3 }
                else if t >= 12 { notch = 2 }
                return ("B-power", notch, 0)
            }
            if t < 50 { return ("C-coast", 0, 0) }
            if !stopped {
                var brake: Float = 0.4
                if t >= 78 { brake = 1.0 }
                else if t >= 58 { brake = 0.9 }
                else if t >= 54 { brake = 0.65 }
                return ("D-brake", 0, brake)
            }
            return ("E-standstill", 0, 0.6)
        }

        while time < totalSeconds - 1e-9 {
            let ph = scriptPhase(at: time, stopped: stopTime != nil)
            if ph.name != currentPhase {
                if !currentPhase.isEmpty {
                    phaseMarks.append((currentPhase, phaseStart, time))
                }
                currentPhase = ph.name
                phaseStart = time
                log(String(format: "t=%5.1f phase %@ begins", time, ph.name))
            }

            // Script physics (deterministic; NOT the app's physics
            // engine — only the audio-facing snapshot is scripted).
            var powerAccel = 0.0
            if ph.notch > 0 {
                powerAccel = Double(ph.notch) * 0.20 * max(0.30, 1.0 - speed / 20.0)
            }
            let brakeDecel = Double(ph.brake) * 1.15
            let resistanceDecel = 0.012 + 0.00012 * speed * speed
            var accel = powerAccel - brakeDecel - resistanceDecel
            if speed == 0, accel < 0 { accel = 0 }
            var newSpeed = max(0.0, speed + accel * dt)
            if ph.name == "B-power", newSpeed > 16.67 { newSpeed = 16.67 }
            let stepAccel = (newSpeed - speed) / dt
            speed = newSpeed
            position += speed * dt
            peakSpeedKmh = max(peakSpeedKmh, speed * 3.6)
            if ph.name == "D-brake", speed == 0, stopTime == nil {
                stopTime = time
                log(String(format: "t=%5.1f train stopped at %.0f m", time, position))
            }

            // batch83: independent expected-grid computation for
            // the leading bogie (see the declarations above).
            // Mirrors the tracker's first-advance behaviour: the
            // first step only establishes the previous chainage.
            let bogieOffsets = FictionalTrackImpactSchedule.bogieOffsets(carCount: 8)
            if let located = FictionalTrackImpactSchedule.locate(
                path: .mainline, direction: .up,
                routePositionM: position - bogieOffsets[0]
            ) {
                if let previous = previousBogieChainage,
                   speed >= FictionalTrackImpactSchedule.stoppedSpeedMps {
                    let spacing = FictionalTrackImpactSchedule.jointedSpacingM
                    var mark = (previous / spacing).rounded(.down) * spacing + spacing
                    while mark <= located.chainageM + 0.001 {
                        if mark > previous + 0.001,
                           FictionalTrackImpactSchedule.isRailJoint(line: located.line, chainageM: mark) {
                            expectedJointChainages.append(mark)
                        }
                        mark += spacing
                    }
                }
                previousBogieChainage = located.chainageM
            }

            // Track impacts: the production tracker, fired exactly
            // as SimulatorModel.cueWaysideAudio fires them, then
            // routed with playTrackImpact's batch79 control flow:
            // real one-shot recordings only, no synthesis.
            let frame = tracker.advance(routePositionM: position, speedMps: speed, path: .mainline, direction: .up)
            for impact in frame.impacts where impact.kind == .railJoint && impact.bogieIndex == 0 {
                firedJointChainages.append(impact.lineChainageM)
            }
            for impact in frame.impacts {
                let gain = min(1, max(0, impact.intensity))
                if gain <= 0.02 { continue }
                // Production engine-side speed gate (>= 1 km/h);
                // the script's speed is the same value production
                // holds in its latestSnapshot.
                if speed * 3.6 < 1 { continue }
                if impact.kind == .pointClatter {
                    pointImpacts += 1
                    if pool.play(named: "point_pass") { pointPlays += 1 }
                } else {
                    // batch97 mirror of the production cadence:
                    // below the clack threshold, plain joints fire
                    // for EVERY bogie with joint_clack (falling
                    // back to joint_prim_p1 if the clack does not
                    // sound, as playTrackImpact does); turnout
                    // joints and at-speed plain joints keep the
                    // representative-event rule (leading bogie
                    // only), exactly as SimulatorModel
                    // .cueWaysideAudio filters before calling
                    // playTrackImpact.
                    let inside = harnessInsideTurnout(impact)
                    if !inside, speed * 3.6 < RailwayAudioEngine.lowSpeedJointClackMaxKmh {
                        jointClackImpacts += 1
                        if pool.play(named: "joint_clack") || pool.play(named: "joint_prim_p1") {
                            jointClackPlays += 1
                        }
                    } else {
                        guard impact.bogieIndex == 0 else { continue }
                        jointImpacts += 1
                        let name: String
                        if inside {
                            let variants = ["joint_prim_p45_0_0", "joint_prim_p45_0_1", "joint_prim_p45_1_0", "joint_prim_p45_1_1"]
                            name = variants[jointVariantCursor % variants.count]
                            jointVariantCursor += 1
                        } else {
                            name = "joint_prim_p1"
                        }
                        if pool.play(named: name) { jointPlays += 1 }
                    }
                }
            }

            // Horn reference one-shot, mid-run at ~40 km/h.
            if !hornFired, time >= 25.0 {
                hornFired = true
                let played = pool.play(named: "horn_e231_short")
                log(String(format: "t=%5.1f HORN reference fired played=%d speed=%.1f km/h", time, played ? 1 : 0, speed * 3.6))
                if !played {
                    fail("horn_e231_short did not schedule on the reference pool")
                }
            }

            // Snapshot -> production update order (applyCurrentSnapshot):
            // sampled motor first, then the DSP mute flag, then DSP.
            let speedKmh = speed * 3.6
            var regen: Float = 0
            if ph.brake > 0 {
                regen = ph.brake * (speed > 2.5 ? 0.8 : 0.15)
            }
            var tractionLoad: Float = 0
            if ph.notch > 0 {
                tractionLoad = Float(ph.notch) / 5 * 0.85
            } else if ph.brake > 0 {
                tractionLoad = regen * 0.5
            }
            var doorsOpen = false
            if ph.name == "A-standstill" {
                doorsOpen = true
            }
            if let stoppedAt = stopTime, time >= stoppedAt + 0.8 {
                doorsOpen = true
            }
            var fieldWeakening: Float = 0
            if speedKmh >= 38 {
                fieldWeakening = Float(min(0.7, (speedKmh - 38) / 30))
            }
            let snapshot = RailwaySimulationSnapshot(
                simulationTime: time,
                speedMetersPerSecond: Float(speed),
                accelerationMetersPerSecondSquared: Float(stepAccel),
                motorRPM: Float(min(8_000, speedKmh * 52)),
                tractionLoad: tractionLoad,
                powerNotch: ph.notch,
                fieldWeakeningRatio: fieldWeakening,
                brakeCommand: ph.brake,
                regenerativeBrakeRatio: regen,
                trackDistanceMeters: position,
                curveRadiusMeters: nil,
                isInTunnel: false,
                isOnBridge: false,
                // batch78: feed the jointed-rail flag the same
                // way production does (schedule locate on the
                // front position). batch83: the bed no longer
                // switches on this flag (Run6 on every section —
                // joints are carried by the distance-fired
                // one-shots only), but the flag is still fed so
                // the snapshot matches production exactly.
                isOnJointedRail: FictionalTrackImpactSchedule.isJointedRail(line: .main, chainageM: position),
                isOnPoints: frame.insideTurnout,
                doorsOpen: doorsOpen,
                weather: .clear,
                windMetersPerSecond: 2,
                trainPosition: AudioVector3(x: 0, y: 0, z: Float(position)),
                listenerPosition: AudioVector3(x: 0, y: 1.6, z: Float(position))
            )
            motor.update(snapshot: snapshot, settings: settings, isEnabled: true, engineRunning: engine.isRunning)
            dsp.setSampledTractionActive(motor.isActive)
            dsp.update(snapshot: snapshot, settings: settings)

            if stepIndex % 400 == 0 {
                log("STATUS t=\(String(format: "%.1f", time)) " + motor.statusDescription + " dspDropped=\(dsp.droppedEventCount)")
            }

            // Render this step's frames offline.
            var renderedThisStep = 0
            while renderedThisStep < stepFrames {
                let want = min(stepFrames - renderedThisStep, 4096)
                var status: AVAudioEngineManualRenderingStatus = .error
                do {
                    status = try engine.renderOffline(AVAudioFrameCount(want), to: renderBuffer)
                } catch {
                    status = .error
                }
                if status == .success, let channels = renderBuffer.floatChannelData {
                    let frames = Int(renderBuffer.frameLength)
                    if frames > 0 {
                        leftAll.append(contentsOf: UnsafeBufferPointer(start: channels[0], count: frames))
                        rightAll.append(contentsOf: UnsafeBufferPointer(start: channels[1], count: frames))
                        if let wavFile {
                            try? wavFile.write(from: renderBuffer)
                        }
                    }
                    renderedThisStep += frames
                    if frames == 0 {
                        leftAll.append(contentsOf: [Float](repeating: 0, count: want))
                        rightAll.append(contentsOf: [Float](repeating: 0, count: want))
                        renderedThisStep += want
                        badRenderCount += 1
                    }
                } else {
                    // Any non-success status: pad silence so the
                    // timeline stays aligned, and count it — a
                    // non-zero count here is harness evidence, not
                    // something to hide.
                    leftAll.append(contentsOf: [Float](repeating: 0, count: want))
                    rightAll.append(contentsOf: [Float](repeating: 0, count: want))
                    renderedThisStep += want
                    badRenderCount += 1
                }
            }

            stepIndex += 1
            time += dt
        }
        if !currentPhase.isEmpty {
            phaseMarks.append((currentPhase, phaseStart, totalSeconds))
        }
        engine.stop()

        // --- Measurements ---
        let totalFrames = leftAll.count
        log(String(format: "rendered %.2f s (%d frames) peakSpeed=%.1f km/h distance=%.0f m badRenderBlocks=%d",
                   Double(totalFrames) / 48_000, totalFrames, peakSpeedKmh, position, badRenderCount))
        log("impacts fired: joints=\(jointImpacts) jointPlays=\(jointPlays) jointClacks=\(jointClackImpacts) jointClackPlays=\(jointClackPlays) points=\(pointImpacts) pointPlays=\(pointPlays)")
        // batch83: joint-grid verdict (see the declarations and
        // the per-step computation above). The scripted drive
        // runs the jointed zone around the origin station, so
        // the expected set is the 25 m grid marks the leading
        // bogie crossed while audible: 25...400 m.
        let firedGrid = firedJointChainages.sorted()
        let expectedGrid = expectedJointChainages.sorted()
        log("JOINT_GRID fired=\(firedGrid.count) expected=\(expectedGrid.count)")
        log("JOINT_GRID firedChainages=\(firedGrid)")
        log("JOINT_GRID expectedChainages=\(expectedGrid)")
        let gridMatch = firedGrid.count == expectedGrid.count
            && zip(firedGrid, expectedGrid).allSatisfy { pair in abs(pair.0 - pair.1) < 0.01 }
        log("HARNESS_VERDICT joint_grid_match=\(gridMatch ? 1 : 0) (leading-bogie joint events vs the 25 m grid)")
        if !gridMatch {
            fail("joint events do not land on the expected 25 m grid: fired \(firedGrid) vs expected \(expectedGrid)")
        }
        log("FINAL " + motor.statusDescription + " dspDropped=\(dsp.droppedEventCount)")
        log("PROBE-AT-END RailwayAudioEngine: " + probe.statusLogLine)

        if abs(Double(totalFrames) - totalSeconds * 48_000) > 24_000 {
            fail("rendered frame count \(totalFrames) does not match script length \(totalSeconds) s")
        }
        if badRenderCount > 0 {
            fail("renderOffline produced \(badRenderCount) non-success/empty blocks")
        }
        if motor.statusDescription.contains("curves= slots=") {
            fail("SampledMotorSound loaded NO motor curves (motor_curves.json unreachable from Bundle.main?)")
        }
        if !motor.isActive {
            log("HARNESS_VERDICT sampledMotor.isActive=0 at end of run (DSP synth fail-over state)")
        }

        log("--- per-second levels (RMS dBFS / peak dBFS, both channels) ---")
        let wholeSeconds = totalFrames / 48_000
        for second in 0..<wholeSeconds {
            let window = stats(left: leftAll, right: rightAll, from: second * 48_000, to: (second + 1) * 48_000)
            log(String(format: "sec %3d  rms %8.2f  peak %8.2f", second, dbfs(window.rms), dbfs(window.peak)))
        }

        log("--- phase summary ---")
        var standstillPeakDb: Float = -120
        var standstillQuarterMaxDb: Float = -120
        var powerPeakDb: Float = -120
        for mark in phaseMarks {
            let from = Int(mark.start * 48_000)
            let to = Int(mark.end * 48_000)
            let window = stats(left: leftAll, right: rightAll, from: from, to: to)
            log(String(format: "phase %@  %5.1f-%5.1f s  rms %8.2f  peak %8.2f",
                       mark.name, mark.start, mark.end, dbfs(window.rms), dbfs(window.peak)))
            if mark.name == "B-power" {
                powerPeakDb = dbfs(window.peak)
            }
            if mark.name.hasSuffix("standstill") {
                standstillPeakDb = max(standstillPeakDb, dbfs(window.peak))
                // 0.25 s detail: a periodic standstill noise shows
                // up as repeating non-silent windows here.
                var bursts = 0
                var windows = 0
                var row: [String] = []
                var t = mark.start
                while t < mark.end - 1e-9 {
                    let w = stats(left: leftAll, right: rightAll, from: Int(t * 48_000), to: Int((t + 0.25) * 48_000))
                    let level = dbfs(w.rms)
                    standstillQuarterMaxDb = max(standstillQuarterMaxDb, level)
                    if level > -50 { bursts += 1 }
                    windows += 1
                    row.append(String(format: "%6.1f", level))
                    if row.count == 8 {
                        log("  \(mark.name) rms/0.25s: " + row.joined(separator: " "))
                        row = []
                    }
                    t += 0.25
                }
                if !row.isEmpty {
                    log("  \(mark.name) rms/0.25s: " + row.joined(separator: " "))
                }
                log("  \(mark.name): \(bursts)/\(windows) quarter-second windows above -50 dBFS")
            }
        }

        let hornWindow = stats(left: leftAll, right: rightAll, from: 25 * 48_000, to: 27 * 48_000)
        log(String(format: "HARNESS_VERDICT horn_peak_dB=%.2f (window 25-27 s, reference one-shot)", dbfs(hornWindow.peak)))
        if dbfs(hornWindow.peak) <= -20 {
            fail("horn reference is inaudible in the rendered mix — the capture chain itself is broken")
        }
        log(String(format: "HARNESS_VERDICT standstill_peak_dB=%.2f standstill_max_quarter_rms_dB=%.2f", standstillPeakDb, standstillQuarterMaxDb))
        log(String(format: "HARNESS_VERDICT power_phase_peak_dB=%.2f", powerPeakDb))
        log("=== AUDIO HARNESS END ===")

        let reportURL = outDir.appendingPathComponent("audio_harness_report.txt")
        lines.append("wav file: \(wavURL.path)")
        lines.append("report file: \(reportURL.path)")
        try? lines.joined(separator: "\n").write(to: reportURL, atomically: true, encoding: .utf8)
        print("wav file: \(wavURL.path)")
        print("report file: \(reportURL.path)")
        return failures
    }
}
