# CrewWorkflow

独立した純Swiftの乗務ワークフロー状態機械です。**iOS 17 / macOS 13以降**を対象にし、実装ターゲットはFoundationのみです。ホストアプリや他workstreamの型・ファイルには依存しません。

> **FICTIONAL GAME CONTENT — NOT REAL RAILWAY PROCEDURE OR SAFETY TRAINING**
>
> このパッケージは架空ゲームの順序制御だけを行います。鉄道の現実の業務手順、運転指示、安全訓練、判断支援を提供しません。プロンプトや評価を表示するときは、必ずこの免責文も同じ画面に明瞭に表示してください。

## 工程と状態制御

全工程を安定したraw string IDで定義し、以下の順序から外れた完了イベントを拒否します。

`attendance_roll_call` → `pre_trip_vehicle_check` → `cab_startup` → `instrument_check` → `depot_exit` → `shunting` → `pre_departure_check` → `door_closing` → `departure` → `signal_check` → `speed_check` → `speed_limit_compliance` → `station_approach` → `precise_stop` → `post_stop_check` → `crew_communication` → `abnormal_response` → `terminal_arrival` → `depot_entry` → `duty_end`

各工程のゲーム内入力要件IDは `phase.requiredRequirementIDs` から取得します。要件が不足すると `CrewWorkflowError.missingRequirements(phase:ids:)` が理由付きで返され、イベントも状態遷移も発生しません。

## API利用例

```swift
import CrewWorkflow

var workflow = CrewWorkflow(runID: "session-123")
let phase = workflow.currentPhase! // attendance_roll_call
let prompt = CrewWorkflowContent.prompt(for: phase)
// promptを表示するUIは、含まれる免責文を省略せず表示する。

let gameInputs = phase.requiredRequirementIDs // ゲームUIが実際の入力結果から構成する
let simulationTime = Date(timeIntervalSinceReferenceDate: 12_345) // ホストのsim clock
let event = try workflow.complete(
    phase: phase,
    at: simulationTime,
    satisfiedRequirementIDs: gameInputs
)
// event: eventID, runID, timestamp, eventType, phaseBefore/phaseAfter, satisfiedRequirementIDs

let dto: CrewWorkflowSaveDTO = workflow.exportSave()
let data = try JSONEncoder().encode(dto) // ホストが選んだ永続化先へ保存
let restoredDTO = try JSONDecoder().decode(CrewWorkflowSaveDTO.self, from: data)
var resumed = try CrewWorkflow.restore(from: restoredDTO)
```

`complete(phase:at:satisfiedRequirementIDs:)` は順序、必要要件、シミュレーション時刻の単調性を検証します。時刻は常にホストから明示的に渡し、パッケージは壁時計を読みません。イベントIDは `runID:phase:<1始まりの工程番号>` で決まり、保存・再生時も同じ工程イベントを識別できます。最後の工程完了後は `currentPhase == nil` になります。

評価コンテンツは `CrewWorkflowContent.evaluations` にあります。これはゲーム用のラベル/説明に限り、実際の運転や安全の評価に利用できません。

## 統合境界

- ホストは操作入力を受け取り、ゲーム内要件IDと**シミュレーション時計**をパッケージに渡します。
- ホストは `CrewWorkflowSaveDTO` をJSON等へ符号化し、既存の運転セッションや他のアプリ状態とは**別個の保存領域**に格納します。
- 復元時はDTOをデコードして `CrewWorkflow.restore(from:)` を呼びます。復元はイベント列、順序、run ID、時刻、現在段階の整合性も検証します。
- このパッケージはUI、実機連携、車両/信号モデル、ダイヤ計算、走行グラフ、速度・制動曲線、得点計算、現実の安全判断を実装しません。ゲーム要件IDの意味を現実の手順へ結びつけないでください。

## テスト例

```swift
var workflow = CrewWorkflow(runID: "test-run")
let phase = workflow.currentPhase!
let event = try workflow.complete(
    phase: phase,
    at: Date(timeIntervalSinceReferenceDate: 1),
    satisfiedRequirementIDs: phase.requiredRequirementIDs
)
XCTAssertEqual(event.phaseBefore, .attendanceRollCall)
XCTAssertEqual(workflow.currentPhase, .preTripVehicleCheck)
```

XCTestは全工程の完走、順序拒否、不足要件の理由、時刻逆行、イベント契約と固定ID、Codable export/restore、中断後の再開、破損DTO拒否を検証します。

```sh
swift test
```
