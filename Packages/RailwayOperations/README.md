# RailwayOperations — 運転業務ゲームモジュール

運転前のゲーム内チェックから運転台起動、出庫、出発、信号確認、駅停車、終業処理までを管理する、iOS 17+向けの純Swiftパッケージです。SwiftUI、RealityKit、物理エンジン、音声認識には依存せず、ホストアプリからコマンドとシミュレーション時刻を受け取ります。

> **重要:** チェック項目、信号判定、選択肢、採点閾値はすべて「架空のゲーム規則」です。実際の鉄道事業者の手順・規程を表すものではなく、本モジュールは鉄道安全訓練・資格訓練・実務判断の代替ではありません。

## 3モードか、もっと細かく分けるか

プレイモードは依頼どおり **練習・標準・トラブル訓練の3つ** に保ちます。利用者に見せるモードを増やし過ぎず、ヒント量・採点許容幅・イベント有効化で違いを出します。一方、評価は3項目にまとめず、**ダイヤ、停止精度、滑らかさ、ゲーム規則スキル**の4区分に分け、それぞれを到着/出発差、停止ずれ/通過量、ジャーク/強い加減速、信号/速度/手順/指差喚呼/イベント対応へ細分化します。モード分類と評価軸を分ける方が、プレイ選択は簡単なまま結果を具体的に改善できます。

## 含まれるもの

- 順序制約付きワークフロー: 乗務前ゲームチェック → 運転台セットアップ → 出庫 → 出発準備 → 運転 → 各駅の停車・ドア操作 → 終業チェック。
- ゲーム内ポイント／喚呼チェックポイントの有効化、正誤・未実施記録、スナップショットでの保留ID共有。
- 到着・出発の時刻差、停止位置のずれ・通過、加速度サンプルからのジャーク、強い加減速、ゲーム規則の結果による説明可能な採点。
- 3モード。トラブル訓練のイベントと正解選択肢も架空のゲーム状態に限り、現実の対処手順は含みません。
- `SharedRailwaySnapshot` プロトコルと `OperationsSnapshot` DTO。シミュレーション時刻、固定tick、刻み幅、路線ID、列車位置・速度・加速度などを、UI/描画/音響/交通側へ渡す中立的な境界として提供します。

## 使い方

```swift
import RailwayOperations

let stop = try OperationsStopDefinition(
    id: "station-1",
    stationName: "水鏡台",
    targetPositionM: 1_620,
    scheduledArrivalSeconds: 180,
    scheduledDepartureSeconds: 210
)
let scenario = try OperationsScenario(
    runID: "demo-run",
    routeID: "fictional-test-line",
    routeLengthM: 1_800,
    originStationID: "aoba-hill",
    stops: [stop]
)
var workflow = OperationsWorkflow(scenario: scenario, mode: .practice)
try workflow.apply(.completePreDutyCheck(.gameBriefing), at: 0)

// チェックごとに進行を記録します。物理・実際の信号システムはホスト側が所有します。
let train = try SharedTrainSnapshot(
    trainID: "player-1", trackID: "track-1", positionM: 0,
    speedMps: 0, accelerationMps2: 0, lengthM: 100
)
let snapshot = try OperationsSnapshot.make(
    workflow: workflow,
    train: train,
    simulationTimeSeconds: 0,
    fixedTick: 0,
    fixedTimeStepSeconds: 1.0 / 120.0
)
```

実際のチェック項目は`PreDutyCheck.allCases`、`CabSetupCheck.allCases`、`DepartureCheck.allCases`、`PostRunCheck.allCases`で参照できます。チェック文言を画面に出す場合は、必ずゲーム内プロンプトとして表示してください。

## 統合契約

- 毎フレームの運動計算は既存の物理エンジンに残します。`OperationsWorkflow.apply`はプレイヤー操作・ゲームイベント時に呼び、物理値を直接変更しません。
- `OperationsSnapshot.make(...)`に同じtickの列車サンプルを渡してください。全モジュールで距離m、速度m/s、加速度m/s²、シミュレーション秒を統一します。`fixedTick`はホストの固定物理tickです。
- `OperationsSnapshot.train`は交通モジュールの`SharedTrainState`、音響モジュールの`RailwaySimulationSnapshot`、描画更新の路線キロ程へフィールド単位で変換できます。このパッケージは他ワークストリームをimportせず、既存ディレクトリを変更しません。
- `OperationsWorkflow.scheduleObservations`と`stopAssessments`、`PointingCallingTracker.records`を`OperationsScoringInput`へ渡して終了時に採点します。トラブル訓練記録は型が別なので、`DisruptionTrainingSession.records`から`DisruptionResponseOutcome(id:matchedGameChoice:)`へ写像して`disruptionResponses`に渡します。未観測のカテゴリーは0点にせず`nil`とします。
- 本パッケージのスナップショット型と音響側に既存する型は、依存関係の循環・名前衝突を避けるため同一型とは主張しません。ホストアプリが共通の値を各アダプターに投影してください。

## テスト

```sh
cd Packages/RailwayOperations
swift test
```

現環境ではSwift/Xcodeが見つからないため、ソースとテストは用意していますが、ここではコンパイル・実行結果を確認できていません。iOS実機上の表示・入力・音声認識もこの純Swiftモジュールの対象外です。
