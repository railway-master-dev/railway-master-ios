# ホストアプリ連携契約

## 1. Package導入

Xcodeでは配布プロジェクト内の`Packages/RailwayAudioEnhancements/`をローカルSwift Package依存に追加し、`RailwayAudioEnhancements`をリンクします。モジュールはFoundationのみを使い、AVFoundation/iOS固有処理はホスト側へ残します。既存の`RailwayAudio`とは独立しており、既存APIの変更・自動置換は行いません。

## 2. 時刻とイベントライフサイクル

- ホストの固定シミュレーションtickから、単位秒の同一`simulationTime`を`AudioEventScheduler.advance(to:)`へ渡します。壁時計や描画フレーム時刻を混ぜません。
- 将来イベントは`AudioScheduledEvent`として予約します。スケジューラーは`scheduledTime`昇順、同時刻は`priority`降順、最後に`id`辞書順で返します。到着・ドア閉め・ATS等の成立条件判定はホストの各システムが担当します。
- `id`はイベント発生インスタンスごとに一意、`deduplicationKey`は意味上同じイベントの再送を束ねる一意キーにします。キーは`reset`まで保持されるので、反復放送は便・駅・発生回数を含めて新しいキーを付けます。
- 時刻は単調増加を前提とし、過去の予約は拒否します。シーク／リプレイでは`reset(to:)`を呼び、復元状態から必要な将来イベントを再投入します。時計の巻き戻しを自動で推測して再生し直す動作はありません。
- tickを大きく飛ばした場合、期限切れのイベントもdueとして返ります。古い案内を再生するか破棄／要約するかは、ホストがイベント時刻と現在時刻を比較して判断してください。

## 3. 放送・話者

`AnnouncementRenderer.render(_:)`は`SpeechInstruction`（文章、`ja-JP`/`en-GB`、チャンネル、対応バス）を返します。ホストは`AVSpeechSynthesizer`等で読み上げます。テンプレートに必要な駅名・行先がない場合は`nil`で、未完成の文章を返しません。個別駅名の読み、アクセント、放送速度、音量、発話キュー、再生中のダッキングはホストで設定します。

`AnnouncementChannel`と`AudioBus`の組合せは原則一致させます。駅放送は`.stationPublicAddress`、車内自動放送／車掌文は`.onboardAnnouncement`です。スケジューラーはテンプレート文を音声再生せず、スピーカーも選択しません。

## 4. 音響バスと制御シグネチャ

ホストは実際の出力ノードを`AudioBus`単位に分け、現在の`AcousticScene`と`AudioMixMatrix.parameters(for:in:masterGain:)`を使ってバスごとのゲイン・残響・帯域・幅を適用します。この行列は推奨値であり、AVAudioEngineグラフ、定位、ドップラー、遮蔽、端末スピーカー特性を実装したものではありません。

既存`RailwayAudio`の駆動プロファイルとの名前対応は、次の同名raw valueを使ってホストで明示的に写像できます。

| 拡張API | 既存`RailwayTractionSoundProfile` |
|---|---|
| `rheostaticDC` | `.rheostaticDC` |
| `fieldChopperDC` | `.fieldChopperDC` |
| `vvvfGTO` | `.vvvfGTO` |
| `vvvfIGBT` | `.vvvfIGBT` |
| `vvvfIGBTVariableCarrier` | `.vvvfIGBTVariableCarrier` |
| `vvvfSiC` | `.vvvfSiC` |

型は別モジュールに属するため暗黙変換はありません。既存エンジンで音を鳴らす場合は既存エンジンだけを使い、追加レンダラーと重ねて同一駆動音を二重再生しないでください。`ControlModeSignatureRenderer`は試聴・独立検査・置換候補用の仮想合成です。形式・事業者・メーカー別の実車校正ではありません。

## 5. 権利・安全・未検証事項

- 本パッケージは無許可録音、BVEの音声、既存駅メロディ、ユーザー提供音声、第三者音声を含みません。波形は手続き合成です。
- 放送例は汎用テンプレートで、鉄道事業者の公式文面・運行指示・実務教育用の認証文ではありません。実運行、安全装置の判断、資格訓練に利用しません。
- 環境にSwift/Xcodeがないため、Swiftビルド・XCTestを未実行です。TTSの音質、端末遅延、割り込み、AVAudioSession、バッテリー、実機ミックスは未検証です。統合後はiOS Simulatorと実機で音響QAが必要です。
