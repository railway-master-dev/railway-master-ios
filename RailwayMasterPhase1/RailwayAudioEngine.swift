#if canImport(AVFoundation) && canImport(UIKit)
import AVFoundation
import AudioToolbox
import Foundation
import os
import RailwayAudioEnhancements
import UIKit

/// 架空路線シミュレーター用の手続き合成音響アダプター。
/// 基本は独自合成。同梱サンプルは利用許諾を確認済みのものだけを使う
/// （抵抗制御車のドアチャイムはプロジェクト提供の録音）。
@MainActor
public final class RailwayAudioEngine: NSObject, AVSpeechSynthesizerDelegate {
    public static let shared = RailwayAudioEngine()

    /// batch60: start() の失敗記録用。従来は catch がコメントだけ
    /// で、実機でセッション有効化に失敗すると全合成音が無音に
    /// なるのに証拠が一切残らなかった。
    private static let log = Logger(subsystem: "jp.railwaymaster.phase1", category: "audio")
    /// 連続した start() 失敗回数。成功したら 0 に戻す。
    private var startFailureCount = 0
    /// batch62: 最後に失敗した start() のエラーの localizedDescription。
    /// 成功しても消さない（「最後に何が起きたか」をテレメトリへ残す）。
    private var lastStartErrorDescription: String?
    /// batch62: playHorn が呼ばれた回数（音響テレメトリ用）。
    private var hornCallCount = 0
    /// batch63: ブレーキ空気音サンプルの最終再生時刻（systemUptime）。
    /// 運転士操作（SimulatorModel.setBrake）と DSP トグル側の担保が
    /// 同じ遷移で二重に鳴るのを防ぐ近接抑止に使う。
    private var lastBrakeAirSampleAt: TimeInterval = -1_000
    /// batch79: 電気笛（Primrose / Miso_yk）の press 専用
    /// プレイヤー。press 素材は 27 秒の「押下中」録音なので、
    /// プールの一発再生（止める手段が無い）には載せず、解放
    /// タイミングで stop できる専用プレイヤーに分ける。
    /// init の構成フェーズでのみアタッチする。
    private var electricHornPlayer: AVAudioPlayerNode?
    private var electricHornTask: Task<Void, Never>?

    /// CI 実行時だけ音響を丸ごと無効化するスイッチ。Codemagic の仮想 Mac
    /// では CoreAudio の初期化がデッドロックし、カーネル側の watchdog が
    /// プロセスごと abort する（実測ログ: "Initialize: RPC timeout.
    /// Apparently deadlocked. Aborting now."）。同じ iOS 26.2 でも発生し、
    /// quality25 でも再現したため、アプリの変更ではなく CI 環境側の問題。
    /// 実機・通常利用では環境変数も引数も無いので常に false。
    ///
    /// quality30: テストホスト（xcodebuild test）へは SIMCTL_CHILD_ 経由
    /// でも共有スキームの TestAction 環境変数経由でもフラグが届かず、
    /// ios-verify が起動時 abort し続けた（quality28 で実測）。そのため
    /// XCTest がテストホストの環境に必ず入れる
    /// XCTestConfigurationFilePath の有無でも判定する。単体テストは
    /// 音響を検証しないので、テスト実行時に音響が無効でも意味は変わ
    /// らない。通常起動ではこの変数は存在しない。
    public nonisolated static let ciAudioDisabled: Bool = {
        let info = ProcessInfo.processInfo
        return info.environment["RM_DISABLE_AUDIO"] == "1"
            || info.arguments.contains("-RMNoAudio")
            || info.environment["XCTestConfigurationFilePath"] != nil
    }()

    public private(set) var settings = RailwayAudioSettings(masterVolume: 0.65)
    public var usesVoiceOverAnnouncements = true
    public var enabled: Bool { isEnabled }
    public var volume: Float { outputVolume }
    public var isAudioRunning: Bool { engine.isRunning }

    /// batch62: ファイルベース音響テレメトリ用の状態1行。
    /// SimulatorModel のデモドライブログへ毎秒相乗りさせる。
    /// 実機で全音声が無音になる問題の切り分けが目的で、開始失敗の
    /// 有無・セッション状態・警笛の呼び出し回数をファイルに残す。
    /// ciAudioDisabled 時は AVAudioSession に一切触らない（CI の
    /// CoreAudio デッドロック回避策を新規に踏まないため）。
    public var statusLogLine: String {
        let sessionRate: Double
        let route: String
        if Self.ciAudioDisabled {
            sessionRate = 0
            route = "-"
        } else {
            let session = AVAudioSession.sharedInstance()
            sessionRate = session.sampleRate
            let ports = session.currentRoute.outputs.map(\.portName).joined(separator: "+")
            route = ports.isEmpty ? "-" : ports
        }
        return "audio enabled=\(isEnabled ? 1 : 0) ciDisabled=\(Self.ciAudioDisabled ? 1 : 0) running=\(engine.isRunning ? 1 : 0) startFail=\(startFailureCount) lastErr=\(lastStartErrorDescription ?? "-") sessionRate=\(sessionRate) route=\(route) horn=\(hornCallCount) \(sampledMotor.statusDescription)"
    }

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
    /// 撮影チェーンの音声確認用レコーダー。環境変数 RM_RECORD_AUDIO=1
    /// のときだけ生成され、それ以外（通常利用・通常のCI撮影）では nil
    /// で一切作動しない。
    private let driveAudioRecorder: DriveAudioRecorder?

    public override init() {
        let dsp = ProceduralAudioDSP()
        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 48_000, channels: 2, interleaved: false)!
        self.dsp = dsp
        self.format = format
        if ProcessInfo.processInfo.environment["RM_RECORD_AUDIO"] == "1" {
            self.driveAudioRecorder = DriveAudioRecorder()
        } else {
            self.driveAudioRecorder = nil
        }
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

        if Self.ciAudioDisabled {
            // CI ではグラフを一切構築しない。prepare() が CoreAudio の
            // 初期化を引き起こし、上記のデッドロックで abort するため。
            // この先の公開メソッドはすべて isEnabled == false で
            // 無音の no-op になる（applyCurrentSnapshot も入口で弾く）。
            isEnabled = false
            return
        }

        synthesizer.delegate = self
        engine.attach(sourceNode)
        engine.attach(reverb)
        engine.attach(licensedSampleMixer)
        reverb.loadFactoryPreset(.mediumRoom)
        reverb.wetDryMix = 0
        // batch74 (urgent device fix): the DSP source node must fan
        // into the mixer, NOT connect straight to the reverb.
        // AVAudioUnitReverb has a SINGLE input bus, and an input bus
        // of a non-mixer node accepts exactly one connection: the
        // connect(licensedSampleMixer, to: reverb) below silently
        // REPLACED this source node's connection, leaving the DSP
        // attached but connected nowhere — the engine never pulled
        // it, so the whole synthesized path (continuous bed AND
        // event voices, rail joints included) produced nothing on
        // device while the bundled samples through the mixer
        // played. That is the exact device symptom across every
        // IPA: no DSP-originated sound has ever been heard, with
        // no error and no telemetry trace. A mixer destination is
        // the only node type that accepts multiple inputs (the
        // sample players already fan into this same mixer and play
        // on device), so the source node takes an input bus there
        // and shares the mixer → reverb → main path.
        engine.connect(sourceNode, to: licensedSampleMixer, format: format)
        // batch62: format: nil だとミキサーの出力形式が入力側
        // （44.1kHz の同梱WAVを再生するプレイヤー接続）に引きず
        // られ、リバーブの入力バスで 48kHz 固定の sourceNode 側と
        // 形式が競合して start() が失敗しうる。全音声無音の主嫌疑
        // として、ミキサー出力も固定 48kHz Float32 に統一する。
        // プレイヤー→ミキサー間は従来どおりバッファ形式のまま
        // （ミキサーが出力形式へ変換する）。
        engine.connect(licensedSampleMixer, to: reverb, format: format)
        engine.connect(reverb, to: engine.mainMixerNode, format: format)
        engine.mainMixerNode.outputVolume = 1
        // Attach every sample player NOW, while the graph is still in
        // its configuration phase. Attaching or connecting a node after
        // the engine has been prepared/started forces a graph
        // reconfiguration that can fail inside AVAudioEngine (the
        // -10868 exception behind the CI #138/#163 crashes). After this
        // point the graph never changes shape; playback only schedules
        // buffers on the pre-attached players.
        sampledMotor.attachHandler = { [weak self] node, format in self?.attachLicensedSamplePlayer(node, format: format) }
        sampledMotor.runAttachHandler = { [weak self] node, varispeed, format in self?.attachLicensedRunPlayer(node, varispeed: varispeed, format: format) }
        sampledMotor.startHandler = { [weak self] in self?.start() }
        sampledMotor.preattachIfNeeded()
        preattachBundledPlayers()
        // batch84: ブレーキ系ワンショットを構成フェーズで
        // キャッシュへ温める（prewarmBrakeSamples 参照）。
        prewarmBrakeSamples()
        // batch97: 低速継目の打音（joint_clack）も同じ理由で
        // 構成フェーズに温める。発車直後の最初の継目（低速域＝
        // 打音の初回発火タイミング）で同期ロードを踏ませない。
        _ = loadBundledBuffer(named: "joint_clack")
        // batch79: 電気笛 press 専用プレイヤーを構成フェーズで
        // アタッチする（形式は press バッファ自身の形式）。
        if let pressBuffer = loadBundledBuffer(named: "horn_elec_prim_press") {
            let player = AVAudioPlayerNode()
            attachLicensedSamplePlayer(player, format: pressBuffer.format)
            electricHornPlayer = player
        }
        // batch63: DSP のキュー発火（ノッチ操作音・ブレーキ空気音）を
        // 実録サンプルへ橋渡しする。ブレーキ空気音は近接抑止つきの
        // 専用経路を通し、それ以外は素通しで再生可否を返す。
        dsp.cueSampleHandler = { [weak self] name in
            guard let self else { return false }
            if name.hasPrefix("brake_apply") || name.hasPrefix("brake_release") {
                return self.playBrakeAirSample(named: name)
            }
            // batch67: 「鳴ったか」を正直に返す。従来は duration が
            // 返れば発音済み扱いだったため、プレイヤー形式不一致で
            // 無音でも合成フォールバックが抑止されていた。
            return self.playBundledSampleOneShot(named: name)
        }
        engine.prepare()
        // RM_RECORD_AUDIO=1 のときだけ、メインミキサーのタップ録音を
        // 開始する。録音先は Documents/rm_drive_audio.caf。
        // batch41: この時点ではミキサーの出力フォーマットが未確定
        // （sampleRate 0 等）のことがあり、その場合はレコーダーが
        // 状況をステータスファイルに残して見送り、エンジン start()
        // 成功後とレコーダー内部のリトライで改めて開始する。
        driveAudioRecorder?.start(on: engine.mainMixerNode)
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
        if engine.isRunning {
            // batch41: 既に走っている場合も、録音タップがまだ
            // 立っていなければ再試行する（レコーダー側で多重
            // 開始は弾かれる）。init 直後の試行はミキサーの
            // 出力フォーマット未確定で見送られることがあるため、
            // 実際に音が出る状態になってからが本命の開始点。
            driveAudioRecorder?.start(on: engine.mainMixerNode)
            return
        }
        guard isEnabled else { return }
        do {
            try activateSessionAndStartEngine()
            if startFailureCount > 0 {
                Self.log.info("audio engine started after \(self.startFailureCount, privacy: .public) failed attempt(s)")
                startFailureCount = 0
            }
            // batch41: エンジンが実際に start した直後が、ミキサー
            // の出力フォーマットが確定している最初の時点。ここで
            // 録音タップの開始を（再）試行する。
            driveAudioRecorder?.start(on: engine.mainMixerNode)
        } catch {
            // Simulator、割り込み、音声出力制限時も運転シミュレーションは継続します。
            noteStartFailure(error)
            // batch62: 割り込み復帰などでセッションが壊れたまま
            // 残っているケース向けに、1回だけセッションを落として
            // から再設定・再 start を試す。多重リトライはしない
            // （恒常的な失敗はテレメトリに残して切り分ける）。
            try? AVAudioSession.sharedInstance().setActive(false)
            do {
                try activateSessionAndStartEngine()
                Self.log.info("audio engine started on session-reset retry (failures before retry: \(self.startFailureCount, privacy: .public))")
                startFailureCount = 0
                driveAudioRecorder?.start(on: engine.mainMixerNode)
            } catch {
                noteStartFailure(error)
            }
        }
    }

    /// セッション設定＋エンジン開始の1試行。失敗は throw する。
    private func activateSessionAndStartEngine() throws {
        let session = AVAudioSession.sharedInstance()
        // batch60: モードは .default。.spokenAudio は読み上げ
        // 用途のモードで、合成音の再生には素のモードが無難。
        // カテゴリ .playback と options は従来どおり維持する。
        try session.setCategory(.playback, mode: .default, options: [.mixWithOthers, .duckOthers])
        try session.setActive(true)
        engine.prepare()
        try engine.start()
    }

    /// batch60: 失敗を無言で捨てない。ログに残し、batch62 では
    /// テレメトリ用に最後のエラー内容も保持する。未起動のまま
    /// なら次のキュー投入時に再試行する（enqueue /
    /// playDepartureChime 側で start() を呼ぶ）。
    private func noteStartFailure(_ error: Error) {
        startFailureCount += 1
        lastStartErrorDescription = error.localizedDescription
        Self.log.error("audio engine start failed (failure \(self.startFailureCount, privacy: .public)): \(error.localizedDescription, privacy: .public)")
    }

    public func stop() {
        if engine.isRunning { engine.stop() }
        synthesizer.stopSpeaking(at: .immediate)
        dsp.setSpeechActive(false)
    }

    public func setEnabled(_ enabled: Bool) {
        isEnabled = enabled && !Self.ciAudioDisabled
        if isEnabled {
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
        // batch60: エンジンが未起動なら、投入の前に開始を再試行
        // する。start() の失敗が無言で消えていた頃は、一度の
        // 失敗で以後のキューが全て無音のまま描画されていた。
        if isEnabled, !engine.isRunning { start() }
        return dsp.enqueue(event)
    }

    public func setSpeechActive(_ active: Bool) {
        dsp.setSpeechActive(active)
    }

    /// Optional authorized vehicle audio can be attached here.
    /// Call ONLY during engine configuration (init, before prepare):
    /// attaching or connecting after the graph is prepared forces a
    /// reconfiguration that can throw inside AVAudioEngine (CI #138,
    /// #163). The connection format must equal the format of the
    /// buffers the player will play (CI #147).
    public func attachLicensedSamplePlayer(_ playerNode: AVAudioPlayerNode, format: AVAudioFormat) {
        engine.attach(playerNode)
        engine.connect(playerNode, to: licensedSampleMixer, format: format)
    }

    /// batch78: RUN プレイヤー専用のアタッチ。プレイヤーと
    /// licensedSampleMixer の間に AVAudioUnitVarispeed を挟み、
    /// E231 実録ベッド（Run3 / Run6）を BVE 式に速度ピッチで
    /// 駆動できるようにする。接続形式の扱いは
    /// attachLicensedSamplePlayer と同一（両接続ともアタッチ
    /// 時に渡された形式）。これも init の構成フェーズでのみ
    /// 呼ばれる（グラフ再構成の制約は通常アタッチと同じ）。
    public func attachLicensedRunPlayer(_ playerNode: AVAudioPlayerNode, varispeed: AVAudioUnitVarispeed, format: AVAudioFormat) {
        engine.attach(playerNode)
        engine.attach(varispeed)
        engine.connect(playerNode, to: varispeed, format: format)
        engine.connect(varispeed, to: licensedSampleMixer, format: format)
    }

    /// One-shot players, POOLED per bundled format (mono chopper
    /// and stereo VVVF), attached during init — see the note there.
    /// batch71: a pool, not a single player. scheduleBuffer on an
    /// AVAudioPlayerNode APPENDS to that node's queue, so the
    /// batch67 single shared player per format serialized every
    /// one-shot of that format: a 4.4 s brake-release, a 3.0 s EB
    /// release, a 2.6 s point-pass and a 2.3 s ATS alert queued up
    /// and played out seconds late, one after another — the
    /// EB→N handle burst "piled up", the door-close cue was lost
    /// behind whatever was queued at departure, and the ATS bell
    /// rang long after (or long past) the event it belonged to.
    /// Each pool voice is stopped before it is scheduled
    /// (interrupt semantics), and the round-robin cursor caps
    /// simultaneous one-shot voices per format at the pool size.
    private var bundledPools: [(format: AVAudioFormat, players: [AVAudioPlayerNode])] = []
    private var bundledPoolCursors: [Int] = []
    private let bundledPoolSize = 4
    private var bundledSampleBuffers: [String: AVAudioPCMBuffer] = [:]

    private func loadBundledBuffer(named name: String) -> AVAudioPCMBuffer? {
        if let cached = bundledSampleBuffers[name] { return cached }
        guard let url = Bundle.main.url(forResource: name, withExtension: "wav"),
              let file = try? AVAudioFile(forReading: url) else {
            return nil
        }
        // batch101: file.length is header-derived, and the
        // AVAudioFrameCount (UInt32) conversion below traps on a
        // declared length above UInt32.max — a corrupt WAV header
        // would crash the first cue that touched the sample
        // instead of degrading to silence. Treat such a file as
        // unloadable; nil is the designed degradation for every
        // caller of this loader.
        guard file.length >= 0, file.length <= Int64(UInt32.max),
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
        return loaded
    }

    /// batch84 (device crash hunt, load hypothesis): warm the
    /// brake one-shot set into the buffer cache during engine
    /// configuration instead of lazily on first use.
    /// loadBundledBuffer is a synchronous disk read + Float32
    /// decode on the main actor, and before this change the
    /// first ordinary brake application of a run paid it for
    /// brake_apply_* (the first low-speed application for the
    /// kishimi takes, the first big release for
    /// brake_release_long, the first B7 / EB for the click and
    /// the EB pair) — in the same frames that also carry the
    /// deceleration slot churn in SampledMotorSound and the
    /// station-approach scene work. The set is small (13 files,
    /// ~6 MB decoded), the cache only ever grows anyway, and
    /// warming changes no cue selection, timing or levels.
    private func prewarmBrakeSamples() {
        for name in [
            "brake_apply_1", "brake_apply_2", "brake_apply_3", "brake_apply_4",
            "brake_release", "brake_release_long", "brake_max_click",
            "kishimi_prim", "kishimi_prim_2",
            "eb_on", "eb_off", "eb_apply", "eb_release",
        ] {
            _ = loadBundledBuffer(named: name)
        }
    }

    private func preattachBundledPlayers() {
        // batch79: the probe list also names a Primrose door
        // sample. The pools are keyed by buffer format and are
        // created ONLY for the probe files' formats, so the set
        // of playable one-shot formats is exactly the probe set;
        // naming the Primrose stereo file guarantees a pool for
        // its format even if it ever diverges from door_open_vvvf
        // (today both are 44.1 kHz stereo and dedupe to one pool).
        for name in ["door_open_chopper", "door_open_vvvf", "door_open_prim_r"] {
            guard let buffer = loadBundledBuffer(named: name),
                  !bundledPools.contains(where: { $0.format == buffer.format }) else { continue }
            var players: [AVAudioPlayerNode] = []
            for _ in 0..<bundledPoolSize {
                let player = AVAudioPlayerNode()
                attachLicensedSamplePlayer(player, format: buffer.format)
                players.append(player)
            }
            bundledPools.append((format: buffer.format, players: players))
            bundledPoolCursors.append(0)
        }
    }
    /// Schedules a bundled WAV sample on a pre-attached player and
    /// reports BOTH its duration and whether anything was actually
    /// scheduled. batch67: the played flag is the honest half of the
    /// pair — before batch67, playBundledSample returned the duration
    /// even when no player matched the sample's format and nothing
    /// sounded, and every caller treated that as "played", which
    /// suppressed the synthesized fallbacks and left the door-close
    /// and point-passage cues silent on device.
    @discardableResult
    public func scheduleBundledSample(named name: String) -> (duration: TimeInterval, played: Bool)? {
        guard isEnabled else { return nil }
        guard let buffer = loadBundledBuffer(named: name) else { return nil }
        let duration = Double(buffer.frameLength) / buffer.format.sampleRate
        guard let poolIndex = bundledPools.firstIndex(where: { $0.format == buffer.format }) else { return (duration, false) }
        // batch79 (production divergence fix): do NOT start the
        // engine bare here. A bare engine.start() skips the
        // AVAudioSession configuration in start(), and once the
        // engine is running that way, start() early-returns
        // forever after — the session is never configured by the
        // engine at all. The harness (the proven path) always
        // starts its engine properly before any playback. Route
        // through start() so both paths configure identically.
        if !engine.isRunning { start() }
        // batch81 (device crash hardening, IPA #10: the app died
        // at an ATS intervention): if the start attempt did NOT
        // leave the engine running — session activation threw,
        // e.g. an interruption / route-change race on device —
        // do not touch the pool player at all. stop /
        // scheduleBuffer / play against an engine in a
        // failed-start state was the one unguarded AVAudio
        // operation left in the cue path, and the ATS bell loop
        // is the first caller to drive it repeatedly (one ring
        // every ~0.6–2.3 s for the whole warning, joined at the
        // brake application by the DSP brake-air cues). Report
        // "not played" instead: every caller already handles it
        // (synth fallback for the bell / confirmation cues,
        // silence for plain one-shots). When the engine IS
        // running — the normal case — nothing changes.
        guard engine.isRunning else { return (duration, false) }
        // batch71: take the next pool voice round-robin and STOP
        // it before scheduling — a voice never carries a queue, so
        // a cue sounds when it is fired, not after every earlier
        // same-format cue has finished.
        let cursor = bundledPoolCursors[poolIndex]
        bundledPoolCursors[poolIndex] = cursor + 1
        let player = bundledPools[poolIndex].players[cursor % bundledPools[poolIndex].players.count]
        player.stop()
        player.volume = outputVolume
        player.scheduleBuffer(buffer, at: nil, options: [])
        player.play()
        return (duration, true)
    }

    /// Plays a bundled WAV sample through the licensed-sample mixer and
    /// returns its duration in seconds so callers can sequence actions
    /// (for example closing the doors only after a door chime ends).
    /// Returns nil when the sample is missing or audio is disabled.
    /// Playback uses the players pre-attached during init; if no player
    /// matches the sample's format, the duration is still returned so
    /// callers can keep their sequencing, just without sound. Callers
    /// that need to know whether anything sounded use
    /// playBundledSampleOneShot / scheduleBundledSample instead.
    @discardableResult
    public func playBundledSample(named name: String) -> TimeInterval? {
        scheduleBundledSample(named: name)?.duration
    }

    /// One-shot playback that reports whether the sample actually
    /// sounded (a player matched its format and the buffer was
    /// scheduled). Sound-first callers use this so a silent sample
    /// can fall back to synthesis instead of swallowing the cue.
    @discardableResult
    public func playBundledSampleOneShot(named name: String) -> Bool {
        scheduleBundledSample(named: name)?.played ?? false
    }

    /// One-shot playback that also reports the sample's duration
    /// when it actually sounded (nil otherwise). Callers that
    /// sequence a follow-up cue after the sample ends use this
    /// (batch108: the departure buzzer waits for the door-close
    /// sample to finish).
    @discardableResult
    public func playBundledSampleOneShotWithDuration(named name: String) -> TimeInterval? {
        guard let result = scheduleBundledSample(named: name), result.played else { return nil }
        return result.duration
    }

    /// batch63: ブレーキ空気音の実録サンプル再生。直近 0.15 秒以内に
    /// 同系統のサンプルが鳴っていれば二重発音として抑止し、その場合も
    /// 「発音済み」として true を返す（呼び出し側が合成フォールバック
    /// を積まないようにするため）。ファイルが無い場合だけ false を
    /// 返し、合成フォールバックを許可する。
    /// batch67: 判定は「実際に鳴ったか」（playBundledSampleOneShot）
    /// に変更。無音だった場合は false を返して合成へ落とす。
    @discardableResult
    public func playBrakeAirSample(named name: String) -> Bool {
        let now = ProcessInfo.processInfo.systemUptime
        if now - lastBrakeAirSampleAt < 0.15 { return true }
        guard playBundledSampleOneShot(named: name) else { return false }
        lastBrakeAirSampleAt = now
        return true
    }

    public func playHorn(long: Bool = false) {
        // batch62: 呼び出し自体が届いているかをテレメトリで
        // 数える（無音時に「要求が来ていない」のか「開始できて
        // いない」のかを切り分けるため）。
        hornCallCount += 1
        // batch63: 警笛は実録サンプルのワンショット再生を正とする。
        // 合成ボイス経由では「鳴り続ける」事故が起きたため、長さの
        // 決まったサンプル再生に替えて構造的に解消する。サンプルが
        // 無い場合のみ従来の DSP 合成へフォールバックする。
        if long, cueFamily == .vvvf, playElectricHorn() {
            // batch79: E231 系の長吹鳴は電気笛（Primrose）を
            // 優先する。空気笛は削除せず、電気笛が無い場合と
            // 他ファミリーのフォールバックとして残す。
            return
        }
        if long {
            if let press = scheduleBundledSample(named: "horn_air_press"), press.played {
                // 空気警笛は吹鳴の約85%時点で解放音を続ける。
                let releaseDelay = press.duration * 0.85
                Task { [weak self] in
                    try? await Task.sleep(for: .seconds(releaseDelay))
                    _ = self?.playBundledSample(named: "horn_air_release")
                }
                return
            }
        } else if playBundledSampleOneShot(named: "horn_e231_short") {
            return
        }
        let recipe = FictionalCueCatalog.recipe(long ? .whistleLong : .whistleShort, family: cueFamily)
        enqueueAtCurrentTime(.whistle, duration: recipe.durationSeconds, intensity: 0.9, priority: 8)
    }

    /// batch79: 電気笛の press/release 再生。press 素材は
    /// 27.06 秒の保持録音だが、ゲームの長吹鳴は空気笛と同じ
    /// 「press の約 85% で解放」の形に揃える: 空気笛 press の
    /// 長さ × 0.85 で専用プレイヤーを止め、解放音を続ける。
    /// 鳴らなかった場合のみ false を返し、空気笛へ落とす。
    @discardableResult
    private func playElectricHorn() -> Bool {
        guard isEnabled,
              let player = electricHornPlayer,
              let buffer = loadBundledBuffer(named: "horn_elec_prim_press") else { return false }
        if !engine.isRunning { start() }
        // batch81: same failed-start guard as
        // scheduleBundledSample — never stop / schedule / play
        // against an engine whose start just failed; returning
        // false hands the caller its air-horn fallback.
        guard engine.isRunning else { return false }
        electricHornTask?.cancel()
        player.stop()
        player.volume = outputVolume
        player.scheduleBuffer(buffer, at: nil, options: [])
        player.play()
        let airPressDuration = loadBundledBuffer(named: "horn_air_press")
            .map { Double($0.frameLength) / $0.format.sampleRate } ?? 6.75
        let blastSeconds = airPressDuration * 0.85
        electricHornTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(blastSeconds))
            guard let self, !Task.isCancelled else { return }
            self.electricHornPlayer?.stop()
            _ = self.playBundledSample(named: "horn_elec_prim_release")
        }
        return true
    }

    public func playBrakeAir() {
        // batch63: 実録 brake_release を優先し、無い場合のみ合成へ。
        if playBrakeAirSample(named: "brake_release") { return }
        let recipe = FictionalCueCatalog.recipe(.pneumaticBrakeRelease, family: cueFamily)
        enqueueAtCurrentTime(.pneumaticBrakeRelease, duration: recipe.durationSeconds, intensity: 0.72, priority: 6)
    }

    /// ATS 警報ベル1回分を鳴らし、その長さ（秒）を返す。batch67:
    /// ベルのループ再生は SimulatorModel 側が「警報需要が続く間」
    /// この戻り値の周期で繰り返し呼ぶことで行う（BVE/実車ATSの
    /// 「条件が続く間ジリジリ鳴り続ける」挙動）。実録 ats_alert を
    /// 優先し、実際に鳴らなかった場合のみ合成へフォールバックする。
    @discardableResult
    public func playATSAlarm() -> TimeInterval {
        // batch63: 実録 ATS ベルを優先し、無い場合のみ合成へ。
        if let alert = scheduleBundledSample(named: "ats_alert"), alert.played {
            return alert.duration
        }
        let recipe = FictionalCueCatalog.recipe(.atsAlert, family: cueFamily)
        enqueueAtCurrentTime(.atsAlert, duration: recipe.durationSeconds, intensity: 0.92, priority: 10)
        return recipe.durationSeconds
    }

    public func playEmergencyBrakeAlert() {
        let recipe = FictionalCueCatalog.recipe(.emergencyBrakeAlert, family: cueFamily)
        enqueueAtCurrentTime(.emergencyBrakeAlert, duration: recipe.durationSeconds, intensity: 0.96, priority: 10)
    }

    public func playATSConfirmation() {
        // batch63: 実録 ATS 確認音を優先し、無い場合のみ合成へ。
        // batch67: 判定は「実際に鳴ったか」に変更（無音時は合成へ）。
        if playBundledSampleOneShot(named: "ats_confirm") { return }
        let recipe = FictionalCueCatalog.recipe(.atsConfirm, family: cueFamily)
        enqueueAtCurrentTime(.atsConfirm, duration: recipe.durationSeconds, intensity: 0.55, priority: 8)
    }

    public func playATSConfirm() { playATSConfirmation() }

    public func playCrossingBell() {
        let recipe = FictionalCueCatalog.recipe(.crossingBell, family: cueFamily)
        enqueueAtCurrentTime(.crossingBell, duration: recipe.durationSeconds, intensity: 0.62, priority: 6)
    }

    /// batch79: rotation cursor for the Primrose [Joint]
    /// turnout variants (p45 series). Plain joints use
    /// joint_prim_p1 at speed and joint_clack below
    /// lowSpeedJointClackMaxKmh (batch97); joints inside a
    /// turnout span rotate the four p45 takes, mirroring the
    /// index semantics of the Primrose Sound.txt [Joint] table
    /// (0 = plain joint, 2–5 = turnout variants, 6 = yokodori
    /// — no game context exists for a track-removal device,
    /// so index 6 is not wired).
    private var jointVariantCursor = 0

    /// batch97: 低速継目カデンスの境界（km/h）。これ未満では
    /// SimulatorModel が全台車イベントを転送し、playTrackImpact
    /// は joint_prim_p1（95 km/h 録音・列車1本分の通過、約5秒）
    /// の代わりに台車1台分の打音 joint_clack（p1 末尾の最終
    /// 台車イベントから 0.45 秒を切り出し）を台車ごとに鳴らす。
    /// 根拠: 台車中心の最小間隔は 5.6 m（車両長 19.5 m・台車
    /// inset 2.8 m、FictionalTrackImpactSchedule.bogieOffsets）。
    /// 40 km/h では台車イベント間隔が 0.50 秒となり 0.45 秒の
    /// 打音が重ならずに分離する。これ以上では打音同士が重なって
    /// 潰れるため、連続した通過テクスチャである p1 が正しい。
    /// 継目ゾーン自体が駅前後 400 m と全線定尺の動物園線＝
    /// 低速で走る場所にあり、欠陥（1発の内部リズムが実速度より
    /// 速い）が聞こえる速度域はこの境界の下に収まる。
    public static let lowSpeedJointClackMaxKmh: Double = 40

    public func playTrackImpact(_ kind: RailwayAudioEventKind, intensity: Float, insideTurnout: Bool = false) {
        let gain = min(1, max(0, intensity.isFinite ? intensity : 0))
        guard gain > 0.02 else { return }
        // batch79: 全軌道インパクトの速度ゲート。1 km/h 未満では
        // 一切鳴らさない（トラッカー側の 0.35 m/s ゲートに加えた
        // エンジン側の担保）。停車中のインパクト音は構造的に無い。
        guard latestSnapshot.speedMetersPerSecond * 3.6 >= 1 else { return }
        // batch79: 合成インパクト（DSP ボイス＋ベッドパルス）は
        // 全廃。ハーネス測定で「台車ユニット毎に発火する約
        // 0.40 秒周期の合成チャタリング」が実機のザッザッの
        // 正体と分かったためで、実録のみを実績のあるワン
        // ショットプールで鳴らす。サンプルが無い場合は無音
        // （合成へは落とさない）。
        if kind == .pointClatter {
            // ポイント通過音は継目音より優先（従来ルール）。
            // 2026-11-15 ユーザー要望：素材2種（point_pass /
            // point_pass_2）をバラバラに流す。発火ごとにランダム
            // 選択し、選んだ方が鳴らなければもう一方へ落とす。
            let pointName = Bool.random() ? "point_pass_2" : "point_pass"
            if !playBundledSampleOneShot(named: pointName) {
                _ = playBundledSampleOneShot(named: pointName == "point_pass" ? "point_pass_2" : "point_pass")
            }
            return
        }
        if insideTurnout {
            let variants = ["joint_prim_p45_0_0", "joint_prim_p45_0_1", "joint_prim_p45_1_0", "joint_prim_p45_1_1"]
            let name = variants[jointVariantCursor % variants.count]
            jointVariantCursor += 1
            _ = playBundledSampleOneShot(named: name)
        } else if Double(latestSnapshot.speedMetersPerSecond) * 3.6 < Self.lowSpeedJointClackMaxKmh {
            // batch97: 低速域は台車1台分の打音を台車ごとに鳴らす
            // （転送側の全台車化は SimulatorModel 側）。打音が
            // 鳴らなければ従来の p1 へ落とす（素材欠落時に
            // 継目が完全無音になるのを避けるための実録同士の
            // フォールバックで、合成へは落とさない）。
            if !playBundledSampleOneShot(named: "joint_clack") {
                _ = playBundledSampleOneShot(named: "joint_prim_p1")
            }
        } else {
            _ = playBundledSampleOneShot(named: "joint_prim_p1")
        }
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
        playDepartureChime(stationID: "fictional-arrival")
    }

    /// batch67: 発車メロディを駅キーで鳴らす。従来は SoundControlSheet
    /// のテストボタンからしか呼ばれておらず、発車シーケンスには
    /// 一度も接続されていなかった（実機で発車ベルが鳴らない原因）。
    /// SimulatorModel が「停車駅でドアが閉まった瞬間」に呼ぶ。
    /// batch108: メロディ全体の長さ（最後の音の終端までの秒数）を
    /// 返すよう変更。発車シーケンスはベルが鳴り終わってからドアを
    /// 閉めるため、その長さを必要とする。
    @discardableResult
    public func playDepartureChime(stationID: String) -> TimeInterval {
        // batch60: dsp へ直接投入する経路も、enqueue と同じく
        // 未起動なら開始を再試行してから入れる。
        if isEnabled, !engine.isRunning { start() }
        let key = DepartureMelodyKey(stationID: stationID, directionID: "up", platformID: "platform-1")
        let definition = melodyCatalog.definition(for: key)
        melodyCatalog.events(for: key, startingAt: latestSnapshot.simulationTime, position: latestSnapshot.trainPosition)
            .forEach { _ = dsp.enqueue($0) }
        return definition.notes.map { $0.offset + $0.duration }.max() ?? 0
    }

    /// batch67: マスコンのノッチ操作音（BVE sound.cfg の
    /// [Master Controller] と同じ「ハンドルが動いたイベントで単発」
    /// の発火モデル）。従来は DSP.update がスナップショットの
    /// ノッチ変化から推測して発火していたが、音響スナップショット
    /// 側の controls は自動ブレーキ時に差し替えられるため、制限
    /// 境界で自動ブレーキが点滅するとノッチが往復して見え、
    /// 操作していないのに何度も鳴っていた。発火点を
    /// SimulatorModel.setThrottle（実際の運転士操作）へ移し、
    /// 実録サンプル優先・無音時は合成クリックへフォールバックする。
    public func playControllerStep(from previous: Int, to notch: Int) {
        guard isEnabled, previous != notch else { return }
        guard settings.tractionSoundProfile.generatesControllerStepSounds else { return }
        let delta = abs(notch - previous)
        // batch78: 着地デテント別の実録テーブル（mec 一式）。
        // 上げは notchon1〜4＋P5on、下げは notchrelease1〜3＋
        // ニュートラル。従来は上げ下げ各1音で全段共通だった。
        // P5 到達はジャンプ幅によらず notch_full（P5on）。
        let sampleName: String
        if previous == 0, notch > 0 {
            sampleName = "notch_on_neutral"
        } else if notch == 0 {
            sampleName = "notch_neutral"
        } else if notch > previous {
            switch notch {
            case 2: sampleName = "notch_on_2"
            case 3: sampleName = "notch_on_3"
            case 4: sampleName = "notch_on_4"
            case 5: sampleName = "notch_full"
            default: sampleName = "notch_on"
            }
        } else {
            switch notch {
            case 2: sampleName = "notch_off_2"
            case 3: sampleName = "notch_off_3"
            default: sampleName = "notch_off"
            }
        }
        if playBundledSampleOneShot(named: sampleName) { return }
        let family = cueFamily
        let click = FictionalCueCatalog.recipe(.controllerStep, family: family)
        let eventTime = latestSnapshot.simulationTime
        let stepsToRender = min(6, delta)
        for step in 0..<stepsToRender {
            let event = RailwayAudioEvent(
                id: "controller-step-\(Int(eventTime * 1_000))-\(previous)-\(notch)-\(step)",
                kind: .controllerStep,
                scheduledTime: eventTime + Double(step) * 0.02,
                duration: click.durationSeconds,
                intensity: 0.36 + Float(min(4, delta)) * 0.035,
                frequencyHz: Float(click.fundamentalHertz * (1 + 0.03 * Double(step))),
                priority: 4,
                position: latestSnapshot.trainPosition
            )
            _ = dsp.enqueue(event)
        }
        if previous == 0, notch > 0, family == .vvvf {
            let event = RailwayAudioEvent(
                id: "induction-\(Int(eventTime * 1_000))-\(notch)",
                kind: .inductionTone,
                scheduledTime: eventTime,
                duration: 0.4,
                intensity: 0.34,
                frequencyHz: nil,
                priority: 5,
                position: latestSnapshot.trainPosition
            )
            _ = dsp.enqueue(event)
        }
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

    // batch84: 両ハンドラとも、本体は MainActor へホップしてから
    // 実行する。@objc セレクタはこのクラスの @MainActor 分離を
    // ObjC ディスパッチ経由では強制できず、AVAudioSession の通知が
    // メインキューで届く保証もない。ホップしないと、割り込み開始
    // 時の engine.stop() や経路変更時の start() が、メイン側で進行
    // 中のキュー再生（pool プレイヤーへの stop / scheduleBuffer /
    // play。最も頻繁なのはブレーキ操作の brake_apply 群）と並行に
    // エンジン状態を書き換える競合になりうる。条件と動作は従来
    // どおりで、実行場所だけを他の全てのエンジン操作と同じ
    // MainActor へ揃える。
    @objc private func handleAudioSessionInterruption(_ notification: Notification) {
        guard let rawValue = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: rawValue) else { return }
        Task { @MainActor [weak self] in
            guard let self else { return }
            if type == .ended, self.isEnabled {
                self.start()
            } else if type == .began {
                if self.engine.isRunning { self.engine.stop() }
            }
        }
    }

    @objc private func handleAudioSessionRouteChange(_ notification: Notification) {
        Task { @MainActor [weak self] in
            guard let self, self.isEnabled else { return }
            if !self.engine.isRunning { self.start() }
        }
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
        guard !Self.ciAudioDisabled else { return }
        var effective = settings
        effective.masterVolume = isEnabled ? outputVolume : 0
        if sampledMotor.attachHandler == nil {
            sampledMotor.attachHandler = { [weak self] node, format in self?.attachLicensedSamplePlayer(node, format: format) }
            sampledMotor.runAttachHandler = { [weak self] node, varispeed, format in self?.attachLicensedRunPlayer(node, varispeed: varispeed, format: format) }
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

/// 撮影チェーン専用の走行音レコーダー（RM_RECORD_AUDIO=1 のときだけ
/// 生成される）。AVAudioEngine のメインミキサーをタップし、合成音と
/// 同梱サンプルのミックスを Documents/rm_drive_audio.caf へ 16bit PCM
/// で書き出す。タップ開始から400秒で自動停止し、ファイル確定後に
/// rm_drive_audio.done（中身はバイト数）を書く。ci_run.sh はこの
/// マーカーを見てファイルを回収する。TTS の駅アナウンスは
/// AVSpeechSynthesizer がミキサーを通らないため、この録音には
/// 含まれない。
///
/// batch41 (2026-11-14): 旧実装は開始失敗が全て無言で、3チェーン
/// 連続で「ファイルが無い」以外の証拠が残らなかった。対策は2つ。
/// (1) 開始を堅牢にする: init 直後はミキサーの出力フォーマットが
/// 未確定（sampleRate 0 等）でファイル生成に失敗しうるため、開始
/// 試行はフォーマット検証つきにし、無効なら見送って、エンジンの
/// start() 成功後の再試行＋レコーダー内部の段階的リトライで
/// 実際に音が出る状態になってからタップを立てる。(2) 診断を残す:
/// 生成・試行ごとのフォーマット値・ファイル生成の成否とエラー・
/// 最初の書き込み・停止時のバイト数を、逐次
/// Documents/rm_drive_audio_status.txt へ追記する（ci_run.sh が
/// screenshots/rm-drive-audio-status.txt として回収する）。
final class DriveAudioRecorder: @unchecked Sendable {
    private let queue = DispatchQueue(label: "jp.railwaymaster.audio-capture")
    private let statusLock = NSLock()
    /// 状態変数は全て queue 上でのみ触る（statusLock はステータス
    /// ファイル追記専用で、呼び出しスレッドを問わない）。
    private var targetMixer: AVAudioMixerNode?
    private var file: AVAudioFile?
    private var tapInstalled = false
    private var stopped = false
    private var framesWritten: AVAudioFramePosition = 0
    private var loggedFirstBuffer = false
    private var loggedFirstWriteError = false
    private var deferredRetries = 0
    private let retryDelays: [Double] = [2, 5, 10, 20, 40, 60]

    private var documentsURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }
    private var audioURL: URL { documentsURL.appendingPathComponent("rm_drive_audio.caf") }
    private var doneURL: URL { documentsURL.appendingPathComponent("rm_drive_audio.done") }
    private var statusURL: URL { documentsURL.appendingPathComponent("rm_drive_audio_status.txt") }

    init() {
        logStatus("recorder created (RM_RECORD_AUDIO=1)")
    }

    /// ステータスファイルへの1行追記。失敗しても残るよう、生成
    /// 直後から全段階で呼ぶ。ベストエフォート（録音自体は止めない）。
    private func logStatus(_ message: String) {
        let line = "[\(Date().timeIntervalSince1970)] \(message)\n"
        guard let data = line.data(using: .utf8) else { return }
        statusLock.lock()
        defer { statusLock.unlock() }
        if let handle = try? FileHandle(forWritingTo: statusURL) {
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
            try? handle.close()
        } else {
            _ = FileManager.default.createFile(atPath: statusURL.path, contents: data)
        }
    }

    private func describe(_ error: Error) -> String {
        let nsError = error as NSError
        return "domain=\(nsError.domain) code=\(nsError.code) \(nsError.localizedDescription)"
    }

    /// 開始要求。何度呼ばれてもよい（タップ設置済み・停止済みなら
    /// 何もしない）。実際の試行は queue 上で行う。
    func start(on mixer: AVAudioMixerNode) {
        queue.async { [weak self] in
            guard let self else { return }
            self.targetMixer = mixer
            self.attemptStart()
        }
    }

    /// queue 上下文。フォーマットが有効なときだけファイルを作って
    /// タップを立てる。無効なら理由を残し、段階的リトライを予約する
    /// （エンジン start() 側からの再試行と二重に効く）。
    private func attemptStart() {
        guard !stopped, !tapInstalled, let mixer = targetMixer else { return }
        let tapFormat = mixer.outputFormat(forBus: 0)
        logStatus("tap start attempt: sampleRate=\(tapFormat.sampleRate) channels=\(tapFormat.channelCount)")
        guard tapFormat.sampleRate > 0, tapFormat.channelCount > 0 else {
            logStatus("tap start deferred: mixer output format not ready (sampleRate=\(tapFormat.sampleRate) channels=\(tapFormat.channelCount))")
            scheduleRetry()
            return
        }
        try? FileManager.default.removeItem(at: audioURL)
        try? FileManager.default.removeItem(at: doneURL)
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatLinearPCM),
            AVSampleRateKey: tapFormat.sampleRate,
            AVNumberOfChannelsKey: Int(tapFormat.channelCount),
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
        ]
        let audioFile: AVAudioFile
        do {
            audioFile = try AVAudioFile(forWriting: audioURL, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: false)
        } catch {
            logStatus("audio file creation FAILED: \(describe(error))")
            scheduleRetry()
            return
        }
        file = audioFile
        logStatus("audio file created: \(audioURL.lastPathComponent) (16bit PCM, sampleRate=\(tapFormat.sampleRate), channels=\(tapFormat.channelCount))")
        mixer.installTap(onBus: 0, bufferSize: 4096, format: tapFormat) { [weak self] buffer, _ in
            guard let self else { return }
            // タップはオーディオスレッドで呼ばれるため、バッファを
            // 複写してから書き込み専用キューへ渡す。
            guard let copy = AVAudioPCMBuffer(pcmFormat: buffer.format, frameCapacity: buffer.frameLength) else { return }
            copy.frameLength = buffer.frameLength
            if let src = buffer.floatChannelData, let dst = copy.floatChannelData {
                let frames = Int(buffer.frameLength)
                if buffer.format.isInterleaved {
                    memcpy(dst[0], src[0], frames * Int(buffer.format.channelCount) * MemoryLayout<Float>.size)
                } else {
                    let channels = Int(buffer.format.channelCount)
                    for channel in 0..<channels {
                        memcpy(dst[channel], src[channel], frames * MemoryLayout<Float>.size)
                    }
                }
            }
            self.queue.async { [weak self] in
                guard let self, !self.stopped, let file = self.file else { return }
                if !self.loggedFirstBuffer {
                    self.loggedFirstBuffer = true
                    self.logStatus("first buffer received: frames=\(copy.frameLength) sampleRate=\(copy.format.sampleRate) channels=\(copy.format.channelCount)")
                }
                do {
                    try file.write(from: copy)
                    self.framesWritten += AVAudioFramePosition(copy.frameLength)
                } catch {
                    if !self.loggedFirstWriteError {
                        self.loggedFirstWriteError = true
                        self.logStatus("buffer write FAILED: \(self.describe(error))")
                    }
                }
            }
        }
        tapInstalled = true
        logStatus("tap installed on main mixer (bufferSize 4096); auto-stop in 400 s")
        queue.asyncAfter(deadline: .now() + 400) { [weak self] in
            self?.stop()
        }
    }

    /// queue 上下文。フォーマット未確定・ファイル生成失敗のときの
    /// 段階的リトライ（上限あり）。タップが立つか上限に達したら止まる。
    private func scheduleRetry() {
        guard !stopped, !tapInstalled, deferredRetries < retryDelays.count else {
            if !stopped, !tapInstalled {
                logStatus("tap start gave up after \(deferredRetries) retries; recording will not happen in this launch")
            }
            return
        }
        let delay = retryDelays[deferredRetries]
        deferredRetries += 1
        logStatus("tap start retry \(deferredRetries)/\(retryDelays.count) scheduled in \(delay) s")
        queue.asyncAfter(deadline: .now() + delay) { [weak self] in
            self?.attemptStart()
        }
    }

    /// queue 上下文（asyncAfter 経由）。タップを外し、ファイルを
    /// 確定させて .done マーカー（バイト数）を書く。
    private func stop() {
        guard !stopped else { return }
        stopped = true
        if tapInstalled {
            targetMixer?.removeTap(onBus: 0)
            tapInstalled = false
        }
        // AVAudioFile を解放するとヘッダが確定する。
        file = nil
        let attributes = try? FileManager.default.attributesOfItem(atPath: audioURL.path)
        let size = attributes?[.size] as? Int ?? 0
        logStatus("stopped: framesWritten=\(framesWritten) fileBytes=\(size)")
        try? "\(size)".write(to: doneURL, atomically: true, encoding: .utf8)
        logStatus("done marker written (\(size) bytes)")
    }
}
#endif
