# アプリ adapter 契約

> **架空ルールの限定:** 本パッケージと以下の例に含まれる駅、期待ドア側、役割、手順ID、イベント、配点はすべて架空の `PLACEHOLDER` ゲームデータです。現実の鉄道設備・運転取扱・安全基準・資格訓練・実務評価を表したり、代用したりしません。プロダクション画面でも「ゲーム用／架空」と明示してください。

## 境界と責務

- `DoorProcedureScoring` は `StopScoring`、アプリの駅型、路線JSON、UI、ドア制御、運行イベントに依存しません。別のプロダクトターゲットとして追加できます。
- 独立Packageとして作成した後、ホストアプリ側に`DoorProcedureScoringRouteAdapter`、架空データresource、SimulatorModelイベント接続、採点/結果UIが追加されています。Package自身はアプリ型へ依存しません。
- 既存 `StopScoring` の停車75点・時刻25点の評価はそのまま維持してください。このPackageのポイントと百分率は独立の拡張指標であり、StopScoringの100点へ自動合算・置換しません。アプリ表示で並べる場合も別カード／別フィールドとして表示します。
- アプリ adapter が、シナリオで採用するサービス停車駅、駅ID、架空入力データ、実際に発生したゲームイベント、確定時刻を明示的に渡します。通過駅や期待値をこのモジュールが推測することはありません。

## 未知・欠損の厳密な扱い

`StationScoringDefinition` の各フィールドは `FieldData<Value>` です。

- `.known(value)`: シナリオデータが明示的に供給した値だけを採点対象にします。
- `.unknown(reason)`: 値は対象だが不明／未収集などの事情がある状態。採点対象外で、理由を結果に残します。
- `.missing`: 元データに項目がない状態。採点対象外で、未知値として保持します。
- `.known([])` の手順配列: 要件が存在しないとシナリオが明示した状態。欠落／不明とは違います。

Codable JSON上、フィールド自体を省略すると `.missing`、フィールドを `null` にすると `.unknown(.explicitNull)`、状態ラッパーを `{"status":"unknown","reason":"sourceDoesNotSpecify"}` とすると理由付き不明、`{"status":"known","value":...}` とすると既知値になります。`PLACEHOLDERStations.json` にサンプルがあります。未知値を既定の左右どちらか、空配列、成功イベントへ変換しないでください。

既知の条件に対する未実施は駅確定前には `.pending`、`finalizeStation` 後には `.notPerformed` となり、0点です。不明／欠落値は駅確定後も `.notEvaluable` のままで、分母から除外されます。確定済み既知項目があるのに未獲得ならスコア率は0%です。既知の採点項目が0ならスコア率は `nil` で、0%ではありません。

## アプリからの接続手順

1. シナリオ開始時に、サービスが停車する駅だけを走行順で `StationScoringDefinition` に変換します。route/stationデータに値が実際にある場合のみ `.known(...)` を使い、欠落は `.missing`、収集済みだが不明なら理由付き `.unknown(...)` にします。実在駅情報で架空PLACEHOLDERの値を埋めないでください。
2. シナリオ中に出たUI／ゲームイベントを `ScoringEvent` として渡します。`eventID` はセッション全体で一意なIDを使い、駅IDとシミュレーション時計を既存スコア系と同じ表現に揃えます。
3. 呼び出し側のゲーム状態機械が、その駅の採点イベント受付を終えたと判断した時だけ `finalizeStation(stationID:at:)` を一度呼びます。このメソッドは駅イベントの欠落を既知条件に限って0点として確定します。評価器はイベント発生時刻や駅滞在状態を推測しません。
4. 表示には `JourneyScoringEvaluation` / `StationScoringEvaluation` を使います。`scorePercent == nil` を0%に変換せず、「採点対象なし／未確定」として表示してください。`finish()` は未確定駅を未訪問のまま残し、その駅のスコアを計算に含めず、新規イベントを拒否します。

## 最小コード例

```swift
import DoorProcedureScoring

let demoStation = try StationScoringDefinition(
    stationID: "PLACEHOLDER-01",
    displayName: "PLACEHOLDER Station One",
    expectedDoorSide: .known(.left),
    procedureRequirements: .known([
        try ProcedureRequirement(
            stepID: "fictional.prompt-choice",
            role: .conductor,
            title: "Fictional prompt selection"
        )
    ])
)
let scorer = try DoorProcedureScoringEngine(stations: [demoStation])

try scorer.record(ScoringEvent(
    eventID: "session-1-event-1",
    stationID: "PLACEHOLDER-01",
    simulationTimeSeconds: 12.0,
    kind: .doorSideAcknowledged(.left)
))
try scorer.record(ScoringEvent(
    eventID: "session-1-event-2",
    stationID: "PLACEHOLDER-01",
    simulationTimeSeconds: 12.5,
    kind: .procedureStep(
        stepID: "fictional.prompt-choice",
        role: .conductor,
        outcome: .completed
    )
))
let finalEvaluation = try scorer.finalizeStation(stationID: "PLACEHOLDER-01", at: 13.0)
// これは架空ゲーム用の独立スコア。StopScoringの評価へ加算しない。
let stationPercent = finalEvaluation.stationEvaluations[0].scorePercent
```

## 入出力ルール

- ポイント既定値は期待ドア側1点、既知の手順要件ごとに1点です。すべて架空ゲーム用で、`DoorProcedureScoringPolicy` で変更できます。
- ドア側は最後に受理されたacknowledgementが期待値と一致する場合に獲得します。`.noDoorSide` は明示的な架空ゲーム値であり、欠落値ではありません。
- 手順は同じstep IDかつ期待roleのイベントのうち最後の試行を使います。最後が `.completed` の場合だけ獲得し、別roleからのイベントは得点しません。step IDが要件一覧にないイベントは記録に残し、`unmatchedProcedureEventIDs` に出しますが、採点・推測には使いません。
- イベントIDは重複拒否です。同時刻イベントは受理し、時刻逆行、未知駅、確定済み駅へのイベント、セッション終了後のイベントはエラーです。エンジンは単一スレッドから使用してください。
- `finish()` は冪等でセッションを凍結します。各駅を先に確定するかは呼び出し側の責務です。未確定／未訪問駅を失点扱いにしません。

## この環境での検証状況

凍結後のSwift 6.4.2 Linux matrixでは`DoorProcedureScoringTests`の13/13 testsがpassしました。Packageはアプリtargetへリンク済みですが、iOSホスト統合テストは未実施です。全体結果は[`../../TEST_CHECKLIST.md`](../../TEST_CHECKLIST.md)を参照してください。
