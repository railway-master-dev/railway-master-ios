# DoorProcedureScoring

架空 `PLACEHOLDER` 駅の期待ドア側と、ゲーム内の役割／手順イベントを採点する独立Swift Packageです。既存アプリや他workstreamへの依存はありません。

> **重要:** このパッケージ内の駅、役割、イベント、配点はすべて架空のゲーム用データ／ルールです。現実の鉄道運転、ドア扱い、安全判断、資格訓練、実務評価には使用できません。実在駅のドア側や実務手順を推測する機能ではありません。

## 含まれるもの

- `Sources/DoorProcedureScoring/`: 公開値型、欠損・未知値モデル、採点エンジン。
- `Tests/DoorProcedureScoringTests/`: 採点、状態確定、イベント重複、JSON欠損、役割不一致などのXCTest。
- `Examples/PLACEHOLDERStations.json`: 既知・明示的不明・フィールド欠落を示す架空データ。
- `INTEGRATION.md`: アプリ adapter 契約と接続例。

## 採点の要点

- 駅ごとに、明示されたドア側の一致を1項目、既知の各手順IDと役割の一致を1項目として採点します。既定点は各1点で、`DoorProcedureScoringPolicy` から変更できます。これは拡張用の独立スコアで、既存の停車／時刻配点には混ぜません。
- 既知項目の未実施は、`finalizeStation` 後に未獲得点になります。確定前は結果を保留します。
- `.missing` と `.unknown(reason)` は分母にも加点にも含めません。`known([])` は「要件なし」と明示された既知データです。
- 分母が0点の場合や駅が未確定の場合、`scorePercent` は `nil` です。0点と判定不能を区別します。
- イベントは一意な `eventID` で重複を拒否します。イベント時刻はセッション内で単調非減少にします。

## 検証

XCTestを用意しています。凍結後のSwift 6.4.2 Linux matrixでは13/13 testsがpassしました。iOS/Xcode上のホスト統合結果は未確認です。全体結果は[`../../TEST_CHECKLIST.md`](../../TEST_CHECKLIST.md)を参照してください。
