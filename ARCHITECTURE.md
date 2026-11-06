# RAILWAY MASTER — ネイティブiOSアーキテクチャ

## 正本ネットワーク

SwiftUI + RealityKitのiOSアプリです。正本は架空の**本線60 km＋支線8 km＋車庫引込線2 km＝70 km**、32駅（本線28・支線4）です。本線と支線をつなぐ旅客経路は68 km。`FictionalOperationsPlan.json`を基準に`RegionalRouteFactory`が本線、支線、支線直通、車庫移動のroute profileと停車順を生成し、時刻表は6種別×2方向×4時間帯の48基本パターンを平日・土曜・休日へ展開します。

アプリの地理、駅、線形、設備、車両、信号、時刻、ドア手順、音響プロフィールは架空の`PLACEHOLDER`ゲーム値です。`Research/RealRouteReference/`の実路線参照線形は出典/CC BY 4.0/品質状態付きで別添し、アプリの運転路線へ接続していません。測量済み線路、公式ダイヤ、実車諸元、鉄道規程の実装ではありません。

## ランタイムの所有権と更新順

`ContentView`はフレーム時刻を`SimulatorModel.advance(at:)`へ渡します。表示フレーム率とは独立してモデルが1/120秒の固定tickを唯一の物理更新主体として進めます。各tickは編成物理、信号・教材ATS、運行列車/交通AI、駅到着・停車・発車、停車採点、ドア/手順採点、9モード状態、乗務/incident状態、運転記録、HUD/合成音を更新します。音声イベントは固定シミュレーション時刻で予約・重複抑止し、同時刻のイベントは即時排出するため、一時停止中のUI試聴も実時間タイマーには依存しません。画面シートを閉じてもモデル側の進行は続きます。

遅延した時刻表選択は始発で待機し、発車予定までのゲーム内残り時間を表示します。停止中や終着時は物理・運行状態を不必要に先へ進めません。

## 運行・時刻表・駅別採点

- **RouteData / Operations**：RouteData package、運行計画、fallbackを共通の駅ID・名称・キロ程で照合します。上下方向の停車列をroute-relative chainageへ正規化します。
- **Timetable**：`RailwayTimetable`は3つの架空カレンダー、4時間帯、6種別、上下方向を扱い、遅延・駅別時刻・車庫移動を計算します。
- **StopScoring**：`StopScoringRouteAdapter`が選択路線の実停車駅と編成長を渡し、到着/停車完了/発車イベントを固定tickに沿って採点します。アプリ得点は停車精度75・時刻25で、架空ホーム範囲も確認します。
- **DoorProcedureScoring**：`FictionalDoorProcedureScoring.json`から架空の既知/unknown/missingデータを読み、ゲーム中に受理されたドア操作・閉扉確認を駅別評価へ送ります。既知項目を評価し、不明/欠損は未評価として得点分母から除外します。ドア評価はStopScoringに合算しません。
- **Signals / Operations / Traffic / Maintenance / IncidentMaintenance**：教材用の閉そく、3現示、簡易速度保護、ATS、交通、保守イベント、架空ゲームincidentを同じtickで扱います。`FictionalLiveProtectionSession`は同じ固定tickで架空ATS-S / ATS-P / ATS-Ps / ATC / EBを評価し、ブレーキ要求をそのtickの物理操作へ上書きします。実設備や実運行管理を制御しません。
- **CrewWorkflow**：20段階の架空乗務ゲーム状態とイベントをシナリオ画面から進めます。実務チェックリストではありません。

## 9モードのゲーム状態機械

`RailwayGameModes`は状態遷移と評価を担当し、物理や描画を直接書き換えません。ネイティブ`GameModeSessionSheet`から運転士・ダイヤ・フリー・車掌・異常対応・教習・全線・観光・会社運行の9モードと、練習・標準・異常対応訓練・フリー走行の4スタイルを選べます。モデルは固定tick・route・信号・交通・環境・駅イベントを渡し、許可されるゲーム要求だけを適用します。必要データが不足するモードはブロック/判定不能になります。

## 車両物理・運転台

`TrainPhysics`は5種類の架空プロフィール（抵抗制御、界磁チョッパ、VVVF GTO、IGBT、SiC）を持ち、編成各車の質量・ブレーキ圧・摩擦仕事/温度・粘着を計算します。ノッチ、牽引、回生、空気制動、電流/電圧、停止距離推定をテレメトリーへ出します。全値が架空のゲーム用で、実車照合や制動保証はありません。

`RailwayVehicleCab`の手続き生成モデルと高品質のgeneric lead-car assetをRealityKit sceneへ接続します。高品質選択では`RailwaySceneFidelity`がseeded chainage付き線形を使い、線路・設備・沿線を局所範囲で生成/更新します。追加GLB importerは車両・運転台・駅・線路・設備・沿線の合成meshをロードし、32駅の最寄り駅モデルを運行中に切り替えます。実車の窓・ドア機構、測量地形、LOD、実機描画/性能評価は未確認です。

## 3D・環境・音響

`RailwaySceneView`は`RailwayRenderingCoordinator`のカメラ、環境、品質情報をRealityKitへ適用します。高品質の沿線生成は、チェーン数上の架空の橋・切取・築堤・静的踏切を含みます。低/中品質は同じスケジュールを粗い箱で描きます。踏切は連動や物理停止ではなく `PLACEHOLDER` です。環境render stateの濡れ/雪表面ブレンド値は既存の手続き生成線路・地面材とSceneFidelity生成材へ渡します。さらに前方ビュー背景色を仮想時刻・霧/視程・降水に応じて更新します。blendは単色材質の色/roughnessヒントであり、重ね貼りPBR、積雪形状、摩擦物理、実素材variantを追加するものではありません。

`RailwayAudioEnhancements`はシミュレーション時計による予約/重複抑止、日英のアナウンステンプレート、バスミックス指示を提供し、`RailwayAudioEngine`/`ProceduralAudioDSP`はiOS TTSと既存の合成牽引・走行・制動・警笛・空気音・チャイムへ接続します。英語文面にも日本語の駅表示名を渡すため、駅名ローマ字/英語別名は未整備です。実録音、実車音、BVE素材は含まず、概念的な制御器シグネチャAPIはまだホストで再生していません。全設備音・実機音響・音声認識は未確認または未実装です。

## 保存と復元

`RailwaySessionPersistence`の版管理save DTOとatomic file slot storeを端末内の「セーブ / 再開」画面から利用します。`SimulatorRuntimeSnapshot`とアプリadapterは物理エンジン内部状態、固定tick、route/vehicle/controls、時刻表、環境/音量/案内言語、schedule/traffic、ATS、停車/ドア採点、ゲームモード、`CrewWorkflow`、`IncidentMaintenance`状態、運転ログを保存し、trusted route/catalog/subsystem revisionへ照合してからモデルを更新します。音声イベントキューは保存せず、restore時はシミュレーション時計を再基準化します。復帰は一時停止状態です。

既存の`OperationsGameplayCoordinator`/`MaintenanceGameplayCoordinator`別進行、バックグラウンド自動保存、iCloud/端末間同期は未対応です。新規`CrewWorkflow`/`IncidentMaintenance`のDTOとは別です。save/restoreはソース接続と静的構造検査までで、iOS動作は未確認です。

## Historical verification snapshot (superseded)

この記述は後続のpackage統合・ファイル追加より前の古い検証スナップショットです。件数とbaseline結果は現在のプロジェクト状態を表しません。現行の確認結果は次の節と[`TEST_CHECKLIST.md`](TEST_CHECKLIST.md)を参照してください。

## Incremental update — seeded geometry and generated 3D models

`RegionalRouteFactory` now uses a `UInt64` seed and SplitMix64 to generate separate mainline, branch, and depot alignments. The default seed is stable; a caller can provide another seed and the route carries it for reproduction. Entry/exit clothoid-like transitions linearly ramp curvature and cant. Placeholder radius/cant ranges are mainline 900–1,850 m / 55–105 mm, branch 450–900 m / 45–90 mm, and depot 450–650 m / 35–70 mm. These are game values, not surveyed railway data. Route sampling averages endpoint curvature and passes interpolated cant into the train, track, and SceneFidelity frames.

The 32-station manifest now selects side, island, passing, major, terminal, and five-track/four-platform station assets by the active route’s canonical stop IDs and chainages. Generic vehicle/cab, track, equipment, station, and corridor models are loaded from embedded GLBs with a native RealityKit mesh adapter; existing procedural geometry remains a fallback. From the latest owner-provided add-on pack, only the detailed fictional car and cab were selected: both have metre-scale Z-up coordinates and uniform per-primitive `COLOR_0`, so the scene applies a documented Z-up→Y-up rotation and retains the authored colors. The other 25 GLBs and all 21 PNGs were not added; the duplicate base models, fixed-radius track visual, and modular station/scenery pieces did not improve the current route/station integration safely. Model-origin statements and commercial-license caveats are in `Resources/Generated3D/README.md` and `asset_manifest.json`.

`RegionalRouteGeometrySampler` is now the single polyline integrator used by `RailwaySceneView` and its continuity test. `RegionalIntegrationTests`, `TrainPhysicsTests`, and `GeneratedRailwayAssetCatalogTests` also contain seed, radius, transition, cant, direction, topology, and asset-container assertions. For the current update, Swift/Xcode XCTest, iOS build, Simulator and device rendering have not been run in this environment; see `UPDATE_LEDGER.md` and `ACCEPTANCE_CHECKLIST.md`.

## Previous verification snapshot — 2026-11-06 (before this update)

最終スナップショットのSwift 6.4.2 Linux matrixは20アプリPackageと同梱prototype GeometryUV（計21 Package）を対象にしました。アプリ16 XCTest Packageは163 pass・2 skip・0 fail、2 Packageはbuild-only pass、`RailwayVehicleCab`と`RailwayVehicleHighFidelity`はApple iOS/RealityKit framework不足で未実行です。別置きGeometryUV prototypeは7 passです。全17 XCTest Package合計で170 pass・2 skip・0 fail。アプリmatrix内の`Packages/RailwaySceneFidelity`は実際にこのproject pathで9 pass（既存suite 7 + Actor suite 2）で、隔離workstreamのログは数えていません。BVE metadataは69/68、共有hash10・全体127ユニークhash、541設定を静的確認しました。静的検証はSwift文法179ファイル、Xcode project parser 218 object ID、45 app sources、20/13 app/test package products、JSON22件（app resource 9件）、実路線参照52区間/26駅/466頂点、app host XCTest source 37件を確認します。Xcode/iOS build、アプリホストXCTest、Simulator/実機、署名、性能・発熱・音響は未確認です。詳細は[`TEST_CHECKLIST.md`](TEST_CHECKLIST.md)と[`GAP_REGISTER.md`](GAP_REGISTER.md)を参照してください。
