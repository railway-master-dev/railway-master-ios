# iOSホストへの接続

`RailwayGameModes` は状態機械だけを担当します。列車の物理演算、描画、永続化、実路線データは持ちません。ホストのシミュレーションから一貫した時刻／tickのスナップショットを渡し、ユーザー操作を `GameModeAction` として渡してください。

## 最小例

```swift
import RailwayGameModes

struct HostSnapshotSource: GameModeSimulationSource {
    let gameModeSnapshot: GameModeSimulationSnapshot
}

let snapshot = try GameModeSimulationSnapshot(
    simulationTimeSeconds: 0,
    fixedTick: 0,
    routeID: "PLACEHOLDER-fictional-route",
    routeLengthM: 1_200,
    positionM: 0,
    speedMps: 0,
    speedLimitKmh: 80,
    doors: .closed
)
let host = HostSnapshotSource(gameModeSnapshot: snapshot)
let scenario = try GameModeScenario.placeholder()
var session = try GameModeSession(mode: .driver, source: host, scenario: scenario)

try session.apply(.start)
try session.apply(.driverCompleteDutyStep(scenario.driverDutyStepIDs[0]))
try session.update(from: host)

let uiContract = session.definition
let currentStatus = session.status
let currentProgress = session.progress
let actionsForHost = session.drainHostEffects()
_ = (uiContract, currentStatus, currentProgress, actionsForHost)
```

例のID・距離・上限速度は全て **PLACEHOLDER** です。アプリでは既存のホスト値を変換して入力し、fixtureを製品データとして利用しないでください。

## ランタイム契約

1. モード開始時に `GameModeScenario` と `GameModeSimulationSnapshot` を揃え、`GameModeSession(mode:snapshot:scenario:)` または `GameModeSession(mode:source:scenario:)` を生成します。路線ID／長さが一致しない場合は初期化エラーです。
2. UIの開始・終了・モード固有ボタンを `session.apply(_:)` で送ります。モード固有操作は開始後のみ有効です。
3. ホストの更新ごとに `session.update(with:)` または `update(from:)` を呼びます。シミュレーション時刻・固定tickは後退できません。同一時刻での異なるtickは許可します。
4. `.blocked` は必須入力がない、または全線の始発位置などで判定できない状態です。成功・失敗とは別にUIで説明してください。`GameModeEvaluation.blockingReason` に理由があります。
5. `drainHostEffects()` でゲーム内要求を取得します。ホスト側で許可値を検証して適用し、結果を後続のスナップショットで返してください。効果は実設備や現実の安全・運転操作に接続しないでください。
6. `session.progress` は各モードで型の違う表示状態です。`switch` で列挙し、`session.status`・`failureReason`・`evaluation` を合わせて表示します。正常な自由運転終了は `status == .completed`、`evaluation.outcome == .selfDirected` で、合否点はありません。

## ホスト入力の意味

`positionM` はメートル、`speedMps` はm/s、`accelerationMps2` はm/s²、`speedLimitKmh` はkm/hです。ダイヤは `simulationTimeSeconds` と `fixedTick` の組、駅イベントは `atStationID` と `stationEvent` で渡します。ゲーム内ドア状態は `doors`、教材UIの架空プロンプトは `trainingPromptID`、表示中景観は `visibleLandmarkID` で表します。

フリー選択を要求した後も、`selectedRouteID`／`selectedWeatherID`などはホストが新値を返すまで従前値または `nil` のままです。分からない値を推測せず `nil`／`.unknown` のままにします。会社運行では、`GameModeTrainSnapshot` にタスク対象の列車ID、路線、線路、位置、速度を渡します。列車が不足する場合は失敗ではなく `.blocked` です。

## テスト

凍結後のSwift 6.4.2 Linux matrixでは`Tests/RailwayGameModesTests/GameModeSessionTests.swift`を含む16/16 testsがpassしました。Xcode統合・iOSビルドは別途未確認です。全体結果は[`../../TEST_CHECKLIST.md`](../../TEST_CHECKLIST.md)を参照してください。
