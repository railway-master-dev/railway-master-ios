# ローカルシミュレーションパッケージ

本iOSアプリは`Packages/`内の20個のローカルSwift PackageをXcode projectから相対パス参照します。app targetは20 product、XCTest targetは13 productを参照します。2026-11-06の凍結Linux実行では、15 Packageのテスト159件がpass・2件skip・0件fail、3 Packageはbuild-only passでした。`RailwayVehicleCab`と`RailwayVehicleHighFidelity`はLinuxにRealityKitがないためbuildできず、Xcode/iOS上の成否は未確認です。Xcode依存解決・iOSビルド・アプリホストテストは別途必要です。詳しい内訳は[`TEST_CHECKLIST.md`](../TEST_CHECKLIST.md)を参照してください。架空ゲーム向けの値・表示は実運転、安全判断、資格訓練には使用できません。

## 地域ネットワーク正本

- `RailwayMasterPhase1/Resources/FictionalOperationsPlan.json`がアプリの運行計画正本です。物理ネットワークは本線60 km＋支線8 km＋車庫引込線2 km＝70 km、32駅、旅客列車の支線経由は68 kmです。
- `RailwayRouteData`、`RailwaySignalling`、`TrafficSimulation/Resources/FictionalRegionalNetwork.json`は同じ60+8+2 km規模と駅識別子に照合されています。
- `TrafficSimulation`のfixtureには架空AI列車、道路車両、ホーム歩行者を含みます。可視化/ゲーム用の固定刻み交通で、実ダイヤ運行・安全制御を保証しません。
- `TrafficActorPoseSampler`は固定tick snapshotから描画用poseを作り、隣接snapshot間をsimulation timeで補間します。描画処理はシミュレーション状態を進めず、安定Actor IDと決定論的な車輪/歩行位相を保ちます。`RailwaySceneWorld`はposeを同じ架空route frameへ投影し、`RailwayTrafficActorRealityKitAdapter`へ渡します。Linux SwiftPMでSampler 4件・SceneFidelity/投影9件がpassしましたが、RealityKit AdapterのiOS build/renderと端末性能は未確認です。
- 運行計画JSONの48パターンは3つの架空カレンダーへ展開するダイヤ表です。全列車の実時刻表発着、待避、進路、CTC/PRCを再現する完成運行管理システムではありません。
- `Research/RealRouteReference/`には近鉄京都線・京都—東寺の公開線形参考データを分離して同梱しています。CC BY 4.0の表示と品質限界は同フォルダ内に記載し、アプリ選択路線、物理、信号、運転可能経路としては使っていません。測地線由来801.5 mは`ESTIMATED`で、物理ネットワーク長・営業キロ・設備は`UNKNOWN`です。

## Packageとホストの接続

- `RailwayRouteData`：路線/線路/駅/ホームモデル、キロ程、出典状態、構造検証。
- `RailwaySignalling`、`RailwayOperations`：架空教材用閉そく/3現示/速度包絡/ATS、運行・乗務フロー。
- `TrafficSimulation`：固定刻みAI列車、道路交通、ホーム上の人流。
- `RailwayVehicleCab`、`TrainPhysics`：架空車両/運転台と編成別物理。
- `EnvironmentConditions`、`RailwayRendering`：天候・環境とカメラ/描画品質/濡れ・雪の表面ブレンド値。
- `RailwaySceneFidelity`：高品質選択時に既存の線形サンプルをチェーン数中心線へ変換し、選択route profileの軌間をメートルへ換算して渡したうえで、カメラ前方の架空線路・架線・ホーム・沿線を生成します。同じスケジュールで架空の橋・切取・築堤・静的踏切を置きます。低/中品質のホストシーンは同じチェーン数の粗い箱を使います。踏切は連動せず、列車物理を止めません。範囲は走行中に定期再生成し、交通packageの動的AI列車/道路車両/歩行者は既存host actorで更新します。すべて手続き生成プレースホルダーで、実地形・写真測量・フォトリアル資産ではありません。新シーン材質への雨/雪ブレンド、実機性能は未確認です。
- `Prototypes/VehicleUVModelCandidate/`：架空HF-01の20部品候補と`VehicleGeometryUV`コアを資料として分離同梱しています。GeometryUV Linux XCTest 7件はpassですが、RealityKitモデル候補は既存`RailwayVehicleHighFidelityBuilder`やanimation/control APIへ未統合です。Exact API・dependency path・未検証境界は同フォルダの`INTEGRATION_STATUS.md`を参照してください。
- `RailwayMaintenance`：既存の故障/保守ゲームイベント。別ゲーム進行はsave対象外です。
- `RailwayTimetable`、`StopScoring`、`RailwayGameModes`：架空時刻表、停車採点、9モード状態機械。
- `DoorProcedureScoring`：アプリの架空駅別ドア/手順イベント採点。unknown/missingは未評価です。
- `RailwaySessionPersistence`：版管理save DTOとatomic slot store。アプリの「セーブ / 再開」画面・SimulatorModel adapterに接続しています。
- `RailwayAudioEnhancements`：SimulatorModelの固定シミュレーション時計で日英アナウンス/話者音を重複排除し、ホストのAVAudioEngine/TTS経路へ配送します。実録音や実列車音はなく、仮想制御音シグネチャAPIもホストで鳴らしていません。
- `CrewWorkflow`：20段階の架空ゲーム進行とイベントDTOをシナリオ進行画面へ接続し、版付きセーブに保存します。実務手順・業務訓練ではありません。
- `IncidentMaintenance`：架空の手動ゲームイベントを固定tickで進行し、復旧選択・架空基地操作・状態DTOをシナリオ画面/セーブへ接続します。実故障診断、整備、出庫判断ではありません。

## 制限・権利・検証

路線の曲線・勾配・停止位置・速度・信号・時刻表・高品質シーンは架空のゲーム設定です。写真、録音、車両モデル、BVE実行ファイル、許諾未確認のBVE素材はアプリに同梱していません。実路線参照データは別途CC BY 4.0の出典表示と品質・欠落値を明記し、アプリ本体から切り離しています。BVEの調査件数と再利用条件は[`Research/BVE_RESEARCH_SUMMARY.md`](../Research/BVE_RESEARCH_SUMMARY.md)と[`VEHICLE_DATA_AND_LICENSE_INVENTORY.md`](../VEHICLE_DATA_AND_LICENSE_INVENTORY.md)を参照してください。

Linuxの静的検証はSwift文法、Xcode project参照、JSON、ネットワーク数値、48経路の停車順序、BVEメタデータ、実路線参照データのライセンス/UNKNOWN状態を確認します。加えて、Swift 6.4.2 Linuxで凍結後20 Package matrixを実行し、15 Packageの159件pass・2件skip・0件fail、3 build-only passを確認しました。RealityKit依存Package2件はLinuxでbuildできませんでした。この静的スクリプトはSwift型チェックやiOSテストを代替しません。現行ソースのiOS/Xcodeビルド、アプリホストXCTest、Simulator/実機QA、性能・発熱・音響評価、署名は未実施です。検証手順と残存ギャップは[`TEST_CHECKLIST.md`](../TEST_CHECKLIST.md)と[`GAP_REGISTER.md`](../GAP_REGISTER.md)を参照してください。
