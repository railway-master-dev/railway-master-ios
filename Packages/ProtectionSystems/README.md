# Fictional Railway Protection Systems

> **架空のシミュレーション／ゲーム用パッケージです。** 実在のATS・ATC・ATO・EB・連動装置を再現、認証、代替するものではありません。実運転、安全判断、運転士の資格・技能訓練、実設備との接続には使用しないでください。既存アプリへの統合も、このパッケージ単独のテスト結果だけでは許可・保証されません。

このSwift Packageは、保安装置を一つの「3現示＋速度保護」処理へまとめず、架空モデルとして別々に試せる構成を提供します。設備は路線のtrack IDとchainage（m）に設置し、列車位置、編成長、閉そく占有、分岐器位置、進路要求、ダイヤを同じtickの入力として扱います。

## 実装したモデル

| モジュール | このパッケージ内の架空挙動 | 公開資料で確認できた一般原則との境界 |
|---|---|---|
| ATS-S相当 | route-mounted beaconを通過すると警報し、設定期限までの確認入力がなければシミュレーション用ブレーキ状態をラッチ | 公開解説には地上子・警報・確認の限定的な説明がある。確認期限・操作条件は型式ごとに異なるため、この既定値は架空設定 |
| ATS-P相当 | 停止目標までの距離と架空の減速度から連続速度包絡を算出し、超過時にラッチ | 公開資料には停止目標までの距離等に基づく速度照査パターンの説明がある。数式・減速度・余裕値は実型式の仕様ではない |
| ATS-Ps相当 | 離散beacon通過で架空の速度制限を受け取り、設定距離だけ有効な一時監視窓を開始 | 公開資料にはATS-Psの機能概要があるが、この一時窓のモデルは本パッケージ独自で、実ATS-Psの仕様を示さない |
| ATC相当 | 他列車の閉そく占有から架空の連続速度指令を選び、任意のroute-mounted zone制限と比較 | ATCの速度照査・自動ブレーキの概要は公開されている。区間数と速度の対応表は架空のゲーム値 |
| ATO相当 | 停止目標に対する速度・牽引・ブレーキ指令を出力。進路不許可または停止現示なら保持・制動指令 | 自動加減速・定位置停止は公開説明にある機能例。出力は実車制御ではなく、ホスト物理エンジンへ渡すゲーム上の指令 |
| EB相当 | 操作イベントが一定時間ないと警報し、モデル設定時間後にブレーキ状態をラッチ | 公開例の時間値を共通仕様に流用せず、本モデル独自に設定 |
| デッドマン相当 | 入力が解放された状態の継続時間を独立監視し、警報・ブレーキ状態へ遷移 | EBと同一方式とは扱わない。時間値・入力条件は全て架空 |
| 信号・閉そく・連動・分岐器 | 列車長を含めたblock占有、switch positionの照合、競合routeの排他、stop/caution/proceedのサンプル現示 | 閉そく・在線検知・連動の一般的役割は公的資料で確認できる。実際の区間・現示・鎖錠・解放条件を再現しない |
| CTC / PRC相当 | PRCがダイヤに沿ったroute要求を提案し、連動モデルが独立に許否判定。CTCは同一tickの列車・進路・遅延を読み取り専用表示 | 遠隔運行管理・ダイヤに基づく進路制御の公開定義を参考にした抽象モデル。事業者固有の制御手順ではない |

モデルは設定可能で、既定のタイムアウト、減速度、速度指令、余裕距離はすべて**説明・テスト用の架空値**です。実際の装置仕様だと表示しないでください。

## ルート・列車とイベント

`RailwayNetwork`には複数track、trackごとの隙間・重複のないblock、chainageに載る`RouteEquipment`、signal、switch、routeを定義できます。route要求は必要なswitch position、保護blockの占有、他routeとの競合を確認してから許可します。各tickの結果にはblock占有、route grant/denial、signal、ATO指令、装置状態とイベントが含まれます。

接近イベントは設備位置と列車の前端位置から発火します。前方列車の位置はblock占有、ATC相当速度指令、route許可に反映します。ATS-S/Psの地上設備イベントと、ATS-Pの停止目標包絡は別の状態機械です。

## ホストアプリ統合契約

1. ホストが架空路線データと車両に搭載するシミュレーション機能を選び、`ProtectionSystemEngine`を作成します。
2. 各固定tickで、ホストが同じ時刻の全列車のtrack・前端chainage・速度・編成長・進行方向、分岐器状態、運転士入力、ダイヤ割当を`SimulationFrame`へ渡します。時間とtickは単調増加させます。
3. エンジンはPRC相当の要求を必要に応じて提案し、連動モデルを通して評価します。PRCの提案自体は進路許可ではありません。
4. ホストは`SimulationResult`のイベントをUI・音響・スコア表示に利用できます。`FictionalProtectionPhysicsCoupler`はATS-S / EB / デッドマンのブレーキ要求を非常ブレーキ、ATS-P / ATS-Ps / ATC / ATOのブレーキ要求をサービスブレーキノッチへ変換し、牽引を切ります。ATOの牽引割合は適用しません。アプリの固定tickは`FictionalLiveProtectionSession`でATS-S、ATS-P、ATS-Ps、ATC、EBを評価します。デッドマンは入力を押下固定のままなので、開放監視は動きません。いずれも架空のPLACEHOLDERで、実車ブレーキAPIではありません。iOS上の動作は未確認です。
5. `SimulationResult.label`および画面・ログに「架空シミュレーション専用」を保持し、実運転・訓練機能として提示しないでください。

例:

```swift
let options = try ProtectionEngineConfiguration(
    atssAcknowledgementTimeoutSeconds: 4, // 架空のゲーム設定
    atspVirtualDecelerationMps2: 0.8,     // 架空のゲーム設定
    atcSpeedCommandsByClearBlocks: [0: 0, 1: 25, 2: 50, 3: 80]
)
var engine = ProtectionSystemEngine(
    network: fictionalNetwork,
    systemsByTrain: ["player": [.atsS, .atsP, .atsPs, .atc, .ato, .eb, .deadman]],
    configuration: options
)
let frame = try SimulationFrame(
    fixedTick: hostTick,
    timeSeconds: simulationTimeSeconds,
    trains: allTrainStates,
    switchPositions: currentSwitchPositions,
    routeRequests: dispatchRequests,
    operatorInputs: playerInputs,
    timetableAssignments: plannedRoutes
)
// resetProtectionAtStop=trueは速度0.1 km/h以下でのみ受理される架空モデルの明示操作。
let result = try engine.step(frame)
let brakeRequests = result.protectionStates.filter(\.brakeCommanded)
// brakeRequestsはシミュレーション表示用。実車ブレーキを制御するAPIではない。
```

## 例とテスト

- `Examples/approach-scenario.json` — 架空の3閉そく区間、信号・転てつ器・競合route・5種の路線機器、2列車、ダイヤ要求を含むシナリオ。先行列車によりrouteが拒否される一方、設備接近、ATS相当の警報、速度イベント、ATO指令、CTC要約を観察できます。
- `Tests/ProtectionSystemsTests/ProtectionSystemsTests.swift` — 警報確認期限、ATS-P包絡、ATS-Psの地点・有効窓、他列車占有に応じるATC指令、進路拒否・競合、ATO保持、EB/デッドマン差、PRC提案とCTC表示、例JSONの読込、単調tick、停車後のみの明示リセットを検査する13ケースです。

Swift 5.9以降の環境で、このディレクトリから次を実行します。

```sh
swift test
```

2026-11-06 に Swift 6.4.2 Linux で `swift test` を実行し、21 件 pass / 0 fail でした（既存 13 件と、ブレーキ要求を物理ノッチへ変換する 8 件）。これは iOS アプリの型検査や実機の制動確認ではありません。

## 公開資料と限界

公開資料が裏付けるのは、各装置の一般的な役割や特定の事業者・型式・事故調査資料に記された限定例です。ATS-Ps、ATC、EB、CTC/PRC等について、内部の制動曲線、タイマー、解除条件、競合処理や全車種共通値を示す公開仕様一式は確認できませんでした。そこで実装は一切の実機パラメータを名乗らず、架空モデルと非実機連携契約に限定しています。出典の題名、発行元、対象範囲は[`SOURCES.md`](SOURCES.md)を参照してください。
