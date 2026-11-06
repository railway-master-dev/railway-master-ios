# Railway Maintenance Simulation

## 分類設計：3つは画面上位、シミュレーションは多軸

「異常・事故・災害」の3区分は、ユーザー向けメニューやフィルターの大分類としては分かりやすく、そのまま使えます。ただし、実行条件、影響範囲、復旧方法が違うものを3箱だけに押し込むと処理が曖昧になります。そのため、このモジュールは `MaintenanceEventFamily` の3分類を残しながら、10個の `MaintenanceEventDomain` と16種類の `MaintenanceEventKind` に細分化します。

例として「車両故障」は異常／車両、「急病人」は事故／旅客・車内、「踏切支障」は事故／踏切、「地震」は災害／自然災害です。種類ごとに発生条件、決定論的な乱数発生率、影響範囲、継続時間、ゲーム内影響、復旧条件を持ちます。実際の発生率や復旧所要時間を示すものではなく、ゲーム用の調整値です。

## 含まれる機能

- 車両の牽引・ブレーキ・ドア故障、急病人、車内トラブル、踏切／線路支障、信号故障、電力中断、先行列車遅延、豪雨・強風・大雪・地震・落雷の条件付き・乱数イベント。
- 固定シナリオの明示起動、列車・駅・踏切・線路区間・路線・ネットワーク単位の影響範囲、時間またはプレイヤー操作・天候条件を組み合わせる復旧判定。
- 走行性能係数、ゲーム速度上限、追加停車時間、出発保留を `MaintenanceTrainEffects` として公開し、物理・交通・表示側が同じイベント状態を参照できる。
- 車両基地への入出庫移動、留置線容量、仮想車両形式ごとの割当、乗務・運用への車両割当、点検進捗と結果、整備タスク、整備後の再点検状態。
- シリアライズ可能なイベント・基地・車両状態。イベント乱数状態と履歴を保存して同じseedから再現できます。

## 共有シミュレーションとの接続契約

このパッケージは Foundation のみを使用し、他のワークストリームへ依存しません。ホストは各固定物理tickで `MaintenanceSimulationSnapshot` を作り、`RailwayMaintenanceModule.step(snapshot:eventActions:)` を一度呼びます。対応するホスト項目は `routeID`, `routeLengthM`, `simulationTimeSeconds`, `fixedTick`, `fixedTimeStepSeconds`, `trackIDs`, `stationIDs`, `trains`, `crossings`, `weather`, `scenarioFlags` です。距離はm、速度はm/s、時間はsimulation secondsです。レール位置は各モジュール間で同じroute/track/train/station/crossing IDを使います。

返る `MaintenanceTickResult.effects(for:)` は列車ごとの合成されたゲーム効果です。車両物理は牽引／制動倍率と任意のkm/h上限、交通・駅側は `departureHeld` と追加停車時間、UI・音響は `warningKinds` / `activeEventIDs` を利用できます。効果をどのように信号・保安・物理へ反映するかはホスト側の責務であり、本モジュールは実車の制御仕様を定義しません。新規車両故障イベントは、同IDの `MaintenanceVehicleRecord` があれば自動で故障記録に橋渡しされます。

固定シナリオは `module.startScenario(kind:scope:snapshot:)` で開始します。ゲーム内の応答は `MaintenanceEventAction(eventInstanceID:actionID:)` で渡します。操作IDはイベント状態に保持され、時間・天候などの条件が後続tickで満たされた時も復旧できます。車庫操作は `handleDepotCommand(_:at:snapshot:)` に渡します。入庫要求には、ホストスナップショット上で設定した速度しきい値以下で、架空の車庫アクセス位置にいる情報が必要です。`DepotOperationEngine.state` と `MaintenanceEventEngine.state` を保存し、復帰時は `RailwayMaintenanceModule(restoring:depotState:eventDefinitions:maximumConcurrentEvents:)` で復元します。

## 仕様の境界と未検証事項

これはフィクションのゲームシミュレーションです。異常時の現実の運転取扱、保安手順、車両点検・修繕方法、避難・救護の助言を含まず、鉄道事業者の手順や実車性能を主張しません。災害への対応はシナリオ状態とゲーム効果に限ります。車庫位置、収容数、移動時間、故障頻度、継続時間、性能倍率は設定可能な仮想値です。

Swift PackageはXcode app targetへリンク済みです。`MaintenanceGameplayCoordinator`がホスト状態をpackageの`MaintenanceSimulationSnapshot`へ写し、ゲームシートからイベント/車庫操作を渡します。保守コーディネーターの途中進行はアプリsave stateの対象外です。凍結後のSwift 6.4.2 Linux matrixでは16/16 testsがpassしました。現行ソースのiOS/Xcodeビルドと実機確認は未確認です。全体結果は[`../../TEST_CHECKLIST.md`](../../TEST_CHECKLIST.md)を参照してください。

## 提供仕様との対応

要件の根拠として、ユーザー提供の `Pasted_content_01.txt`・`Pasted_content_02.txt`・`Pasted_content_03.txt` を読みました。異常・事故・災害のシナリオと発生条件、影響・復旧、車両基地・入出庫・割当、点検・整備状態、共有シミュレーションとの連携をこの独立パッケージに落としています。鉄道事業者の実際の運転取扱・保安手順を推測して追加することはしていません。

## ビルド・テスト

```sh
cd Packages/RailwayMaintenance
swift test
```

統合時の最小呼び出し例:

```swift
var maintenance = RailwayMaintenanceModule(
    seed: 42,
    depots: depotDefinitions,
    vehicles: vehicleRecords
)
let result = maintenance.step(snapshot: hostSnapshot, eventActions: playerActions)
let effects = result.eventResult.effects(for: playerTrainID)
```

`hostSnapshot` はそのtickの共有状態から `MaintenanceSimulationSnapshot` に変換します。上記はAPI例であり、ホストアプリのビルド成功を意味しません。
