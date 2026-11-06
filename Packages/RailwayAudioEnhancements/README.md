# RailwayAudioEnhancements

音響イベント予約、駅・車内放送文、シーン別バスミックス、制御方式別の仮想合成シグネチャをまとめた独立Swift Packageです。既存の車両音響エンジンやアプリ本体のAPIは変更・置換していません。

## 含まれるもの

- **決定的なシミュレーション時計スケジューラー**：実時間タイマーを使わず、イベントを時刻・優先度・ID順で確定的に排出します。ID／意味キーによる重複排除、予約の取消、シーク時のリセットを備えます。
- **日英放送テンプレート**：駅到着・次駅・ドア閉め・ホーム安全・遅延・乗換の日本語／英語文を作り、ホストTTS向けに`ja-JP`または`en-GB`の指示を返します。音声ファイルや録音は同梱しません。
- **ミックス行列**：運転室、車外、駅、トンネルのシーンごとに各バスのゲイン、リバーブ送り、ローパス上限、ステレオ幅を返します。処理を実行するのはホスト側のAVAudioEngineです。
- **6種類の合成シグネチャ**：抵抗制御、界磁チョッパ、VVVF GTO、IGBT、可変キャリアIGBT、SiC向けに、純粋関数で決定的なモノラルFloat PCMを生成します。

すべての波形は**CONCEPTUAL / VIRTUAL（概念的な仮想合成）**です。実車録音、特定車種の音、メーカー固有の制御波形、実測スペクトルとは主張しません。サンプル音源は生成・収録・再配布していません。

## 使い方の概略

```swift
import RailwayAudioEnhancements

let scheduler = AudioEventScheduler(startTime: simulationTime)
let request = AnnouncementRequest(
    template: .nextStation,
    locale: .japanese,
    context: .init(stationName: "青葉台"),
    channel: .onboardAutomated
)
let event = AudioScheduledEvent(
    id: "trip-42:next:station-7",
    scheduledTime: simulationTime + 30,
    priority: 3,
    deduplicationKey: "trip-42:next:station-7",
    bus: .onboardAnnouncement,
    payload: .announcement(request)
)
_ = scheduler.schedule(event)

// 固定シミュレーションtickごとに、ホストが持つ同一の秒時計を渡す
let dueEvents = try scheduler.advance(to: simulationTime)
for cue in dueEvents {
    if case let .announcement(request) = cue.payload,
       let speech = AnnouncementRenderer.render(request) {
        // ホスト側: AVSpeechUtterance(speech.text) を生成し、speech.languageTagを選択。
        // cue.bus / speech.audioBusに対応する駅・車内の出力バスへルーティングする。
        _ = speech
    }
}
```

スケジューラーは車両状態や路線条件から放送の発報条件を推測しません。駅接近・ドア閉め・ATS成立などの判定はホストが行い、十分先のシミュレーション時刻でイベントを予約します。実時間の音声開始遅延、発話中断、AVAudioSession、ルート変更はホストの責任です。

## 制御音シグネチャ

`ControlModeSignatureRenderer.render(mode:state:frameCount:sampleRate:sampleOffset:)`は、状態と絶対サンプル位置が同じなら同じPCMを返します。chunk継ぎ目を保つ場合は、次chunkの`sampleOffset`に前chunkまでの累積frame数を指定します。既存`RailwayAudioEngine`も駆動音を生成するため、本パッケージのレンダラーを使う場合は同じ駆動音の二重再生を避け、どちらか一方を選択してください。

## 検証

`Tests/RailwayAudioEnhancementsTests/AudioEnhancementTests.swift`に時刻順序、重複排除、取消／リセット、日英放送、シーン差、全シグネチャの決定性・有限値・相互差分のテストがあります。SwiftPMが利用できる環境では、フォルダ内で`swift test`を実行してください。この作業環境にはSwift/Xcodeツールチェーンがなく、今回テストを実行できていません。実機音響、AVSpeechSynthesizer出力、AVAudioEngineへの統合、遅延・性能は未検証です。

## ライセンス・素材

このパッケージに音声サンプル素材はありません。コードから生成する波形・短い定型文以外の第三者音声は使用していません。将来、録音音声や駅固有素材を追加する場合は、権利者の明示的な許諾と利用条件の記録を別途必須とします。
