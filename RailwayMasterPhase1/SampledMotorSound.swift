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
    var attachHandler: ((AVAudioPlayerNode) -> Void)?
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
    private var runSample: String?
    private var currentFamily: String?

    /// True when sampled curves exist for the current profile family.
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

    private func buffer(named name: String) -> AVAudioPCMBuffer? {
        if let cached = buffers[name] { return cached }
        guard let url = Bundle.main.url(forResource: name, withExtension: "wav"),
              let file = try? AVAudioFile(forReading: url),
              let loaded = AVAudioPCMBuffer(pcmFormat: file.processingFormat,
                                            frameCapacity: AVAudioFrameCount(file.length)) else { return nil }
        do {
            try file.read(into: loaded)
        } catch {
            return nil
        }
        buffers[name] = loaded
        return loaded
    }

    private func ensurePlayers() {
        if motorPlayers.isEmpty {
            for _ in 0..<3 {
                let player = AVAudioPlayerNode()
                attachHandler?(player)
                motorPlayers.append(player)
            }
        }
        if runPlayer == nil {
            let player = AVAudioPlayerNode()
            attachHandler?(player)
            runPlayer = player
        }
    }

    private func playLoop(_ player: AVAudioPlayerNode, sample: String) -> Bool {
        guard let buffer = buffer(named: sample) else { return false }
        player.stop()
        player.scheduleBuffer(buffer, at: nil, options: .loops)
        player.play()
        return true
    }

    private func approach(_ current: Float, _ target: Float) -> Float {
        current + (target - current) * 0.4
    }

    func update(snapshot: RailwaySimulationSnapshot, settings: RailwayAudioSettings, isEnabled: Bool, engineRunning: Bool) {
        loadCurvesIfNeeded()
        let family = familyKey(for: settings.tractionSoundProfile)
        isActive = curves[family] != nil
        guard isActive, attachHandler != nil else {
            if motorPlayers.contains(where: { $0.isPlaying }) {
                motorPlayers.forEach { $0.stop() }
                runPlayer?.stop()
            }
            return
        }
        // Decide what should sound before touching the audio graph.
        // Player nodes are attached only while the engine is actually
        // running: attaching one earlier leaves it without a valid
        // output format and the connect aborts the process (the launch
        // crash bisected in CI #138/#141/#144). Braking at a standstill
        // (holding brakes at a station) must not count as wanting motor
        // sound, or the attach would still happen during startup.
        let speedKmhNow = max(0, snapshot.speedMetersPerSecond) * 3.6
        let wantsMotor = snapshot.powerNotch > 0
            || ((snapshot.brakeCommand > 0.03 || snapshot.regenerativeBrakeRatio > 0.03) && speedKmhNow > 0.5)
        let wantsRun = speedKmhNow >= 2 && !snapshot.doorsOpen
        if motorPlayers.isEmpty {
            guard wantsMotor || wantsRun else { return }
            if !engineRunning {
                startHandler?()
                return
            }
            ensurePlayers()
        }
        if family != currentFamily {
            currentFamily = family
            for index in motorPlayers.indices {
                motorPlayers[index].stop()
                motorSlotSample[index] = nil
                motorPlayers[index].volume = 0
            }
            runPlayer?.stop()
            runSample = nil
            runPlayer?.volume = 0
        }

        let master = isEnabled ? settings.masterVolume : 0
        let speedKmh = max(0, snapshot.speedMetersPerSecond) * 3.6
        let motoring = snapshot.powerNotch > 0
        let braking = snapshot.brakeCommand > 0.03 || snapshot.regenerativeBrakeRatio > 0.03
        var desired: [String: Float] = [:]
        if motoring {
            desired = interpolatedGains(family: family, mode: "power", speedKmh: speedKmh)
        } else if braking {
            desired = interpolatedGains(family: family, mode: "brake", speedKmh: speedKmh)
        }
        if snapshot.doorsOpen { desired = [:] }
        let desiredSorted = desired.sorted { $0.value > $1.value }.prefix(3)

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
                    if playLoop(player, sample: target.name) {
                        motorSlotSample[slot] = target.name
                        player.volume = 0
                    } else {
                        motorSlotSample[slot] = nil
                        continue
                    }
                } else if engineRunning, !player.isPlaying, buffer(named: target.name) != nil {
                    playLoop(player, sample: target.name)
                }
                let targetVolume = min(1, target.volume) * master * 0.85
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
            if snapshot.isInTunnel {
                desiredRun = "run_tunnel"
            } else if snapshot.isOnBridge {
                desiredRun = "run_bridge"
            } else if family == "vvvf" {
                desiredRun = "vvvf_run_loop_9301"
            } else {
                desiredRun = "run_ballast"
            }
            let speedFactor = min(1, speedKmh / 70)
            let targetVolume = speedKmh < 2 ? 0 : speedFactor * master * 0.35
            if targetVolume > 0.01 {
                wantsSound = true
                if runSample != desiredRun {
                    if playLoop(player, sample: desiredRun) {
                        runSample = desiredRun
                        player.volume = 0
                    }
                } else if engineRunning, !player.isPlaying {
                    playLoop(player, sample: desiredRun)
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
