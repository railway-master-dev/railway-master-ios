# StopScoring 統合メモ

> **規則の位置づけ:** ここに記載する得点、停止許容、秒猶予、ドア/手順の判定、グレードはすべてゲーム向けの架空ルールです。現実の鉄道運転規程・安全基準・教育採点の表現や代替として扱わないこと。

## 変更範囲

独立Swift PackageとしてiOSアプリの別モジュール境界を保ちます。このプロジェクトでは`StopScoringRouteAdapter`と`SimulatorModel`から接続し、駅別の到着・停止・発車イベントを渡しています。package境界は `String` の駅/イベントID、`Double` の秒/メートル、公開enumと値型です。

## 入力アダプター

1. シナリオ開始時、対象サービスの停車駅を走行順に `StationStopDefinition` 配列へ変換します。駅ID、駅チェーン位置、目標停止位置、ホーム両端、許容停止位置窓、任意の時刻表、任意の想定ドア側、必須ゲーム手順を渡します。急行等で通過する駅は配列に含めません。
2. `StopScoringEngine(trainLengthMeters:direction:stations:policy:)` を生成します。列車長は1編成全長メートル、方向は共通の物理チェーン座標が増加/減少する向きです。
3. シミュレーション更新ごとに `SimulationTick(sequence:simulationTimeSeconds:leadingEndChainageMeters:speedMetersPerSecond:)` を作り、同一tickで発生した駅イベントを `StationEvent(eventID:stationID:kind:)` として `process(tick:events:)` に渡します。
4. `.arrival` は到着時刻を記録します。停車位置を確定したtickで `.stopCompleted` を送り、そのtickの先頭部位置と速度が採点されます。ドア操作には `.doorOperation(side:action:)`、手順には `.procedureStep(stepID:outcome:)`、発車時には `.departure` を送ります。
5. 画面表示には返却された `JourneyEvaluation` の駅別結果と累積値を使用し、旅程終了時に `finish()` を呼びます。`finish()` 後の新規tickは拒否されます。

## 座標・時計の契約

- chainageはルート内で一貫するメートル座標。60 km本線、8 km支線、2 km車庫線のどの系統かを呼び出し側が選び、駅定義とtickで同じ座標系を使います。モジュールは線区最大距離を仮定しません。
- 位置値は列車の「進行方向先頭端」。正方向では列車本体がより小さいチェーン位置側へ伸び、逆方向ではより大きい側へ伸びます。物理的に全編成をホーム範囲内へ収める許容窓であることを初期化時に確認します。
- シミュレーション時刻は、シナリオ開始を任意の0秒とした単調増加秒。tick順序は厳密増加、時刻は後戻り不可。同時刻の複数イベントは配列順に処理されます。
- `stationChainageMeters` はアプリの駅位置参照を保持する入力値です。停車誤差は `targetStopChainageMeters` と実停止位置の差から求めます。

## 採点と完走

- 各駅を独立に採点し、結果配列は定義時の走行順です。駅ごとの `cumulativeEarnedPointsThroughStation` と `cumulativeAverageScoreThroughStation` により、その駅までの累積点・平均を表示できます。
- 誤差の符号は「実停止位置−目標位置」。cm値はm値の絶対値×100。
- 早着は負、遅延は正の `actual−scheduled` 秒で返ります。時刻表未設定のチェックポイントは採点対象外。予定時刻を設定したのにイベントがないチェックポイントは0点。
- 終着は配列最後のサービス停車駅です。最終駅の到着と停止完了で `terminalReachedAndStopped`、全停車駅の到着/停止と最終駅以外の発車記録で `isComplete` が成立します。終着駅の発車イベントは完走条件にしません。
- 呼び出し側は、停車サービスのシナリオデータを正しい駅順・方向で渡す責任があります。通過駅、運転整理、折返しやイベント取消しをこのモジュールは推測しません。

## エラーと運用上の注意

不正な設定、tick逆行、未知駅、状態遷移不正、イベントID重複は `StopScoringError` で返ります。tickとイベントの一括処理はトランザクションではありません。イベント配列の途中でエラーになった場合、tickとそれ以前に受理されたイベントは残るため、再送する前に `evaluation()` で現状態を確認してください。エンジンは単一のシミュレーションスレッドから使用してください。

## 構成・検証

- `Sources/StopScoring/StopScoringModels.swift`: 入力/出力型、ゲーム規則ポリシー。
- `Sources/StopScoring/StopScoringEngine.swift`: 駅イベント状態遷移、採点、累積・終着評価。
- `Tests/StopScoringTests/StopScoringEngineTests.swift`: XCTest境界/回帰テスト。
- `Package.swift`: iOS 16+ Swift Package。

凍結後のSwift 6.4.2 Linux matrixでは、このPackageの15/15 testsがpassしました。Packageはapp targetへリンク済みですが、iOSホスト統合テストは未実施です。全体結果は[`../../TEST_CHECKLIST.md`](../../TEST_CHECKLIST.md)を参照してください。
