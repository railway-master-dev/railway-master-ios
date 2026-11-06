# RailwayTimetable — 架空時刻表モジュール

Swift/JSONの独立packageです。既存の架空70 km networkを複製せず、canonical `RailwayRouteData` JSONから駅ID・駅名・線路上キロ程・線路ID・車庫を取り込み、既存 `FictionalOperationsPlan.json` から6種別・停車駅・平日運転間隔・車庫時分を取り込みます。package自身のJSONは土曜・休日の追加間隔とゲーム用遅延モデルだけを持ちます。

**収録する値はすべてゲーム設計用のPLACEHOLDERです。実在の運行情報・設備・安全基準・運転指示ではありません。** 待避・追越し候補は停車パターン由来のシナリオ候補で、待避線、複線、信号・進路や運転容量の存在を表しません。

## 統合API

`CanonicalNetworkAdapter.importInputs(routePackageJSON:operationsPlanJSON:)` が両方のJSONをIDで突合します。駅名・駅キロ程・線路長・旅客ルート長が一致しない場合は取り込みを失敗させ、正本の値を別名や重複データで上書きしません。OperationsPlan側の駅名とキロ程は照合にだけ使い、出力する駅マスターはRouteData側です。route packageの表示用路線名（例: 65/5 km表記）ではなく、区間チェーン距離と運行計画の整合する60 km本線＋8 km支線＋2 km車庫線を確認します。

```swift
import Foundation
import RailwayTimetable

let inputs = try CanonicalNetworkAdapter.importInputs(
    routePackageJSON: Data(contentsOf: routeJSONURL),
    operationsPlanJSON: Data(contentsOf: operationsPlanURL)
)
let weekendRules = try TimetablePlanLoader.loadBundled()
let timetable = try TimetableBuilder.build(inputs: inputs, weekendPlan: weekendRules)

// timetable.trips: 全便。各trip.stationEventsには32駅すべての着発・停車/通過を含む。
let firstTrip = timetable.trips[0]
let firstEvent = firstTrip.stationEvents[0]
let result = try DisruptionSimulator.simulate(
    network: timetable,
    scenario: DelayScenario(
        calendar: firstTrip.calendar,
        direction: firstTrip.direction,
        initialTripID: firstTrip.tripID,
        initialDelayMinutes: 8,
        actions: []
    )
)
```

生成するpatternは平日・土曜・休日それぞれ6種別×上り/下り×朝ラッシュ/日中/夕方/夜間の計144組です。平日は既存JSONの48組を使い、土曜・休日は `Sources/RailwayTimetable/Resources/WeekendTimetableRules.json` に別カレンダーとして明記しています。各便は駅ごとの到着・出発秒、停車秒、通過扱いを持ちます。所要時間は正本の各種別値（60〜150分）に固定し、停車時分を控除した残りを区間距離に比例配分して合計を一致させます。日跨ぎはサービス日からの秒数で保持します。

車庫線はRouteDataの車庫ID・接続駅・2 km区間長を用います。出庫は車庫接続駅（正本上のS01）から始まる下り便の前、入庫は同駅に到着する上り便の後に、既存の車庫時分ルールからイベントを作ります。車庫名・IDは運行計画側の別名を流用しません。

## ゲーム用運転整理

`DisruptionSimulator.simulate` は初期遅延、同方向始発時刻の仮想最小間隔、停車時分による遅延吸収、停車省略、抑止（取消）を扱います。単純なシナリオ処理であり、閉そく・列車位置・信号・進路・対向列車や現実の運転整理／安全性はモデル化しません。

## 検証

```sh
cd Packages/RailwayTimetable
swift test
```

正本sourceが同じworkspaceにある場合、統合テストが実際の32駅データを読み、距離、6種別、144 pattern、各駅着発、停車/通過、時間制約、入出庫、候補、遅延整理を検査します。canonical source JSONを持たない別環境ではその統合テストをskipし、他のユニットテストは実行されます。

凍結後のSwift 6.4.2 Linux matrixでは3 testsがpassし、2 testsはskip、failureはありませんでした。全体結果と未実施のiOS/Xcode検証は[`../../TEST_CHECKLIST.md`](../../TEST_CHECKLIST.md)を参照してください。
