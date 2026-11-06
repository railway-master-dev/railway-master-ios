# RailwayOperations — 現在のホスト統合

`RailwayOperations`は`Packages/RailwayOperations`からXcode app targetへリンク済みです。`OperationsGameplayCoordinator`がpackageの`OperationsWorkflow`、`OperationsSnapshot`、`PointingCallingTracker`、`DisruptionTrainingSession`、`OperationsScoringInput`を利用し、`OperationsGameplaySheet`が架空のゲーム操作を渡します。`SimulatorModel`/`SimulatorRuntimeSnapshot`はmain driving modelの信号・ATSなどに必要なpackage型を参照しています。

## 更新とイベントの境界

物理状態はホストの1/120秒固定tickが所有し、Operationsは位置・速度や実設備を直接変更しません。ホスト側で同じtickのsnapshotを作り、乗務確認・喚呼・異常訓練などの入力時に workflow commandを渡します。運転終了時のscoring inputへ観測済みデータを写し、未観測カテゴリーは0点にせず未評価として扱います。単位はm、m/s、m/s²、simulation secondsで統一します。

本Packageの`OperationsSnapshot`と他のシステムDTOは別型です。ホストadapterでフィールド単位に変換し、Package間の循環依存を作りません。画面・結果共有には`FICTIONAL GAME RULES — NOT A RAILWAY OPERATING PROCEDURE`および`GAME ONLY — NOT RAILWAY SAFETY TRAINING`の注意を残してください。

運行業務/保守シート内の途中ゲーム進行は、現行の主運転save stateへ含まれません。Package XCTest、Swift型チェック、iOS build、Simulator/実機確認は未実施です。受入手順は[`../../TEST_CHECKLIST.md`](../../TEST_CHECKLIST.md)を参照してください。
