# StopScoring

**これは鉄道運転の現実の採点規定ではありません。** このSwiftモジュールの点数、許容値、手順判定、ドア判定は、シミュレーター向けに調整可能な架空のゲーム規則です。実際の運転・安全・教育・資格判定に利用しないでください。

## できること

- 駅ごとの目標停止位置、列車長、ホーム範囲、許容停止範囲を使った停止評価。
- 停止誤差を符号付き/絶対値のメートルとセンチメートルで記録。列車全長が進行方向に応じたホーム内の範囲に収まるかも評価。
- 到着/出発それぞれの早着・遅延を秒で記録し、猶予時間を超えた分を採点。
- 駅ごとのドア側・開閉操作、手順ステップと結果を記録し、設定されたゲーム要件に照らして採点。
- 駅別スコア、各駅までの累積点/平均、全駅の最終評価、終着到達・停車、完走状態を計算。
- サービスごとに停車駅だけを指定可能。通過駅を停車対象として渡さない構成にできる。

## Swift Package

`Package.swift` はiOS 16以降を宣言しています。Xcodeプロジェクトに取り込む場合は、`Sources/StopScoring/` をターゲットへ追加するかSwift Packageとして参照してください。XCTestは `Tests/StopScoringTests/` にあります。

## 最小の使い方

```swift
import StopScoring

let allowed = try StopPositionWindow(lowerBoundMeters: 1_240, upperBoundMeters: 1_250)
let schedule = try StopSchedule(scheduledArrivalSeconds: 300, scheduledDepartureSeconds: 330)
let station = try StationStopDefinition(
    stationID: "ST-012", displayName: "Example",
    stationChainageMeters: 1_245, targetStopChainageMeters: 1_246,
    platformStartChainageMeters: 1_160, platformEndChainageMeters: 1_300,
    permittedStopWindow: allowed, schedule: schedule,
    expectedDoorSide: .left, requiredProcedureSteps: ["arrival-check", "dispatch-check"]
)
let scorer = try StopScoringEngine(
    trainLengthMeters: 80, direction: .increasingChainage,
    stations: [station], policy: GameScoringPolicy()
)

let tick = try SimulationTick(sequence: 1, simulationTimeSeconds: 300,
                              leadingEndChainageMeters: 1_246, speedMetersPerSecond: 0)
let events = [
    try StationEvent(eventID: "evt-1", stationID: "ST-012", kind: .arrival),
    try StationEvent(eventID: "evt-2", stationID: "ST-012", kind: .stopCompleted),
    try StationEvent(eventID: "evt-3", stationID: "ST-012", kind: .doorOperation(side: .left, action: .open)),
    try StationEvent(eventID: "evt-4", stationID: "ST-012", kind: .procedureStep(stepID: "arrival-check", outcome: .completed))
]
let snapshot = try scorer.process(tick: tick, events: events)
let dwellTick = try SimulationTick(sequence: 2, simulationTimeSeconds: 310,
                                   leadingEndChainageMeters: 1_246, speedMetersPerSecond: 0)
_ = try scorer.process(tick: dwellTick, events: [
    StationEvent(eventID: "evt-5", stationID: "ST-012", kind: .doorOperation(side: .left, action: .close)),
    StationEvent(eventID: "evt-6", stationID: "ST-012", kind: .procedureStep(stepID: "dispatch-check", outcome: .completed))
])
let departureTick = try SimulationTick(sequence: 3, simulationTimeSeconds: 330,
                                      leadingEndChainageMeters: 1_246, speedMetersPerSecond: 0)
_ = try scorer.process(tick: departureTick, events: [
    StationEvent(eventID: "evt-7", stationID: "ST-012", kind: .departure)
])
let finalResult = scorer.finish() // freezes input; safe to call more than once
```

Pass `SimulationTick` values in strictly increasing sequence order with non-decreasing scenario time. `stopCompleted` captures the tick's leading-end position and requires speed no greater than the configured fictional stop threshold. Events in one call use that tick's time and position; array order is significant. A tick/event batch is sequential, not transactional: if an event throws, the tick and earlier accepted events in that batch remain applied.

## Scoring defaults (fictional)

Each station is normalized to 100 points with weights: stop 55, timetable 20, doors 15, procedures 10. Stop error within 0.25 m scores full stop points; an error outside the permitted window or a consist not fitting the platform scores zero for stopping. Other in-window stop errors decline linearly toward the farthest permitted edge. Timetable scoring gives 30 seconds of early/late grace and subtracts 2 points per excess minute at each configured arrival/departure checkpoint. Door-side, open/close, sequence, and required-step/order penalties are configurable in `GameScoringPolicy`.

Missing scheduled checkpoints are not scored; if no timetable checkpoint is configured, the timetable component is 100. A configured-but-missing checkpoint scores zero. A station with no expected door side or no required procedure steps receives 100 for that component. Incomplete stops score zero for stopping. These are game design defaults, not advice about railway practice.

## Output meanings

- `StopMeasurement.signedErrorMeters`: actual leading-end chainage minus target; negative means before the target on the route's physical axis, positive means beyond it. Absolute error is also returned in metres and centimetres.
- `StationEvaluation.componentScores`: component scores (0...100) and weighted total (0...100), plus event logs and running cumulative score through that station in the supplied route order.
- `JourneyEvaluation.cumulativeEarnedPoints`: sum of station totals; maximum is 100 times configured service-stop count. `averageScore` is normalized to 0...100.
- `terminalReachedAndStopped`: the last configured service stop has an arrival and a completed stop. `isComplete`: every configured stop has arrival+stop and every non-terminal configured stop has a departure; no real-world operational meaning is implied.
- Grades are fictional bands: A >= 90, B >= 80, C >= 70, D >= 60, otherwise F.

See [`INTEGRATION.md`](INTEGRATION.md) for the app-independent integration contract and compatibility notes.
