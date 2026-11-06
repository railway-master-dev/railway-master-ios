# RAILWAY MASTER — iOSビルド・試遊受け入れチェックリスト

## 現在の検証状態

### このSandboxでの静的検証

2026-11-06の今回更新後に`Scripts/validate_project.py`がPASSしました。Swift文法203ファイル、Xcode project parser 218 object ID、app sources 45、20 app/13 XCTest package products、JSON 26件、BVE台帳69路線/68車両（カテゴリ間共有hash10、全体127ユニークhash）、静的テキスト設定541件、60+8+2 km・32駅、48 route組合せ、43件のアプリホストXCTestメソッドのソース数を確認しています。3D検査は13 GLB/935 colored triangle primitives/外部URI 0/32駅。`PACKAGE_INVENTORY.md`は357ファイル行、最終ZIPは358 memberでCRC・サイズ・SHA-256照合済みです。この静的検査はSwiftコンパイラやテストランナーを起動しないため、XCTestやiOSビルドの成功を意味しません。

### 公式Swift 6.4.2 Linux SwiftPMテストbaseline（別環境・後続編集前）

以下は完了済みの公式Linuxテストタスクが別環境で記録した、後続編集前の歴史的baselineです。現行ソースの判定には、その下の凍結後実行結果を参照してください。今回の静的PASSとは別の検証です。

| Package | 公式baseline結果 |
|---|---|
| `RailwayGameModes` | 16 tests passed |
| `RailwayMaintenance` | 16 tests passed |
| `RailwayOperations` | 6 tests passed |
| `RailwayRendering` | 6 tests passed |
| `RailwaySessionPersistence` | 13 tests passed |
| **上記5 Package合計** | **57 tests passed** |
| `EnvironmentConditions` | 9件中7件pass、2件fail。同じ`WeatherSnapshotTests.testValuesAreNormalizedAtConstruction`の2 assertionsで、`WeatherSnapshotTests.swift:47`は`precipitation.rateMillimetersPerHour`に`nil`を期待したが`0.0`、`:52`は`wind.gustSpeedMetersPerSecond`に`nil`を期待したが`0.0`（どちらも`XCTAssertNil` failure）。 |
| `DoorProcedureScoring` | Package build failure。XCTestは実行されていない。 |
| `RailwayTimetable` | build failure。public default argumentがinternalな`Bundle.module`を参照。XCTestは実行されていない。 |
| `StopScoring` | test target compile failure: `tick:` label missing。テスト実行には至っていない。 |
| `TrainPhysics` | compile failure: closure argument/order。後続テストは実行されていない。 |
| `RailwayRouteData` | build failure。public default argumentがinternalな`Bundle.module`を参照。XCTestは実行されていない。 |
| `RailwaySignalling`、`TrafficSimulation` | Package builds passed。テストpass件数はこのbaselineでは報告されていない。 |
| `RailwayVehicleCab` | LinuxではUIKit依存のためskip。build/test passとは扱わない。 |

このbaselineに含まれないPackageは、この表からpassを推定しないでください。失敗に関する後続の変更・修正も、再実行記録がない限りpassしたとは扱いません。

### 今回の追加統合前に凍結した全Package SwiftPM実行（2026-11-06、履歴）

これは今回の移動Actor、実路線拡張、HF-01候補を追加する前の履歴結果です。最新版の判定は以下の「今回の追加統合後」節を参照してください。過去の個別実行ログは検証環境にのみ保存され、配布対象ではありません。

集計: `swift test`対象17 Packageのうち15件は終了コード0で、合計159件pass・2件skip・0件fail。`RailwayVehicleCab`と`RailwayVehicleHighFidelity`は終了コード1で、Linuxに`RealityKit`がなくビルドできず、XCTestは未実行です。残り3 Packageは`swift build`がすべて終了コード0でした。全体は20 Package中18コマンド成功、2件はLinux環境のframework不足で実行不能です。

| Package | 実行 | 終了 | 結果 |
|---|---|---:|---|
| `CrewWorkflow` | `swift test` | 0 | 6 pass、0 fail |
| `DoorProcedureScoring` | `swift test` | 0 | 13 pass、0 fail |
| `EnvironmentConditions` | `swift test` | 0 | 9 pass、0 fail |
| `IncidentMaintenance` | `swift test` | 0 | 6 pass、0 fail |
| `ProtectionSystems` | `swift test` | 0 | 13 pass、0 fail |
| `RailwayAudioEnhancements` | `swift test` | 0 | 11 pass、0 fail |
| `RailwayGameModes` | `swift test` | 0 | 16 pass、0 fail |
| `RailwayMaintenance` | `swift test` | 0 | 16 pass、0 fail |
| `RailwayOperations` | `swift test` | 0 | 6 pass、0 fail |
| `RailwayRendering` | `swift test` | 0 | 6 pass、0 fail |
| `RailwaySceneFidelity` | `swift test` | 0 | 7 pass、0 fail |
| `RailwaySessionPersistence` | `swift test` | 0 | 13 pass、0 fail |
| `RailwayTimetable` | `swift test` | 0 | 3 pass、2 skip、0 fail |
| `RailwayVehicleCab` | `swift test` | 1 | Linuxに`RealityKit`がなくbuild failure。テスト未実行。 |
| `RailwayVehicleHighFidelity` | `swift test` | 1 | Linuxに`RealityKit`がなくbuild failure。テスト未実行。 |
| `StopScoring` | `swift test` | 0 | 15 pass、0 fail |
| `TrainPhysics` | `swift test` | 0 | 19 pass、0 fail |
| `RailwayRouteData` | `swift build` | 0 | build-only pass |
| `RailwaySignalling` | `swift build` | 0 | build-only pass |
| `TrafficSimulation` | `swift build` | 0 | build-only pass |

この表は上記時点での履歴記録で、今回の追加統合後の結果ではありません。

### 前回の追加統合後 SwiftPM実行（2026-11-06、最終metadata/packaging update前の履歴）

指定されたSwift 6.4.2（`swift-6.4.2-RELEASE`、Ubuntu 24.04 x86_64 Linux）でアプリの20 local Packageを再実行した、最終BVE台帳・HF-01配布内依存の見直しより前の履歴です。最終snapshotの結果はこの後に別途記録します。過去の個別ログは配布対象外です。

追加統合と関連する個別結果は以下です。

| 対象 | 結果 |
|---|---|
| `TrafficSimulation` | 4 XCTest pass、0 fail（対向列車・道路車両・歩行者、固定時刻補間、save/restore/replay再現性、シナリオID拒否を確認） |
| `RailwaySceneFidelity` | 9 XCTest pass、0 fail（既存7件にActor route投影2件を追加） |
| `Prototypes/VehicleUVModelCandidate/GeometryUV` | 7 XCTest pass、0 fail。アプリ20 Packageの外にあるGeometryUVコアのみ。RealityKit車両候補テストは未実行。 |
| `Research/RealRouteExpansion` | 決定論的route package validatorはPASSを報告（52 route features、26駅、466頂点、35,140.556 mの参照線形）。運転可能データではなく、未知値を明記した調査参照のみ。 |

この履歴結果はRealityKit依存コードの意味解析・iOSビルド成功を示しません。XcodeアプリホストXCTest 37件、iOS型チェック/クリーンビルド、Simulator/実機表示、署名、性能・発熱・音響は未実施です。したがってiOSビルド成功やプレイテスト可能とは扱いません。

### 最終スナップショットのSwiftPM matrix（2026-11-06）

確定69/68 BVE台帳、HF-01候補のZIP内GeometryUV、最終コードを含む状態で、Swift 6.4.2 Linuxから20アプリPackageと同梱prototypeのGeometryUV（計21 package directories）を実行しました。アプリ側16 XCTest Packageは163件pass・2件skip・0件fail、2 Packageは`swift build`のみでpass、2 RealityKit/iOS依存PackageはLinuxに必要なApple frameworkがなく未実行でした。アプリmatrix内の`Packages/RailwaySceneFidelity`はプロジェクト内のsuite 7件と追加Actor suite 2件、計9件passです。隔離workstreamのログはこのmatrixへ含めていません。別置きGeometryUVは7 XCTest passです。合計では17 XCTest Packageの170件pass・2件skip・0件fail、2 build-only pass、2件は環境制約で未実行です。個別ログは一時検証環境に保存し、配布ZIPには含みません。

このmatrixはSwift Packageのビルド・テストだけを示します。Xcodeのアプリターゲット型検査、iOS Simulator/実機での描画・操作、RealityKit候補モデルの実行、署名、性能・発熱・音響は確認していません。iPhoneで試遊できる、またはiOSアプリのビルドが成功したとは主張しません。

再実行:

```sh
python3 -m pip install -r Scripts/requirements.txt
python3 Scripts/generate_package_inventory.py --check
python3 Scripts/validate_project.py
python3 Scripts/verify_package_zip.py ../RAILWAY_MASTER_iOS_FullPackage.zip
```

### 沿線の表面と配置（2026-11-06）

オリジナルのタイル表面をバラスト、コンクリート、草、舗装、壁、鋼、木材へ割り当てました。写真の取り込みはありません。建物4種、生垣、木の集まり、踏切の草地を足し、1.6 kmの地物間隔は変えていません。RealityKitの見た目とMacビルドは未確認です。

```sh
cd Packages/RailwaySceneFidelity && swift test --filter 'SceneryVarietyTests|SceneCorridorLandmarkTests'
```

### 運転台の手続き生成（2026-11-06）

3種の机の色、レバー、計器、灯、銘板の部品計画を分けました。写真はテクスチャにしていません。抵抗制御に直列・並列・最終灯はありません。RealityKitのメッシュはLinuxではコンパイルしていません。景観作業はこの回では始めていません。

```sh
cd Packages/RailwayAudioEnhancements && swift test --filter FictionalCabAndSoundTests
```

### 転轍機とレール継目（2026-11-06）

架空ネットワークの分岐・車庫・待避駅に、幅のあるPLACEHOLDER転轍機を置き、台車が入ったときだけ `pointClatter` を鳴らします。定尺区間は25 m、本線の駅間はロングレールです。止まっているときは鳴らしません。録音は入れていません。iOS再生は未確認です。

Swift 6.4.2 Linux で `RailwayAudioEnhancements` は 22 件 pass、0 fail（既存 17 件に転轍機と継目の 5 件を追加）。アプリの再生は未確認です。

```sh
cd Packages/RailwayAudioEnhancements && swift test
```

### 手続き合成の全キュー（2026-11-06）

ATS、警笛、ベル、ドア、ハンドル、ブレーキ、踏切、継目、橋、出発メロディを、種類ごとに別の合成音にしました。駆動・ATS・警笛・ドア・ハンドルは制御方式でも分けます。ATS確認は駅チャイムを使いません。録音とBVE音源は入れていません。音色はPLACEHOLDERです。iOSでの再生は未確認です。

Swift 6.4.2 Linux で `RailwayAudioEnhancements` は 17 件 pass、0 fail（既存 13 件にキュー特性 4 件を追加）。アプリのAVAudioEngine経路は実行していません。

```sh
cd Packages/RailwayAudioEnhancements && swift test
```

### 公開ページに書かれた制御の扱い（2026-11-06）

VVVFの定速、界磁チョッパの並列最終段まで回生を出さないことと0Aの再力行、抵抗制御の1ノッチ進段停止とマスコン逆回しの抑速を、固定tickへ足しました。出典はファン制作BVEの公開ページで、メーカー諸元ではなく、アーカイブや音やvehicle.txtは入れていません。西武4000系の10両はページに無い追加PLACEHOLDERです。20 km/h以外の時間や速度の閾値はPLACEHOLDERです。iOSでの操作確認は未実施です。

Swift 6.4.2 Linux で `TrainPhysics` は 28 件 pass、0 fail（既存 23 件にページ記述の 5 件を追加）。`RailwayAudioEnhancements` は 13 件 pass、0 fail（既存テストに灯名と低音ピッチの確認を追加）。アプリ画面は型検査していません。

```sh
cd Packages/TrainPhysics && swift test
cd Packages/RailwayAudioEnhancements && swift test
```

### 8両と10両の編成物理（2026-11-06）

VVVF・界磁チョッパ・抵抗制御の8両と10両を、既存の固定tickローダへ追加しました。質量・引張力・ブレーキ応答はPLACEHOLDER / fictionalizedで、東武50000系・西武2000系・西武4000系の公式諸元ではありません。同じノッチ時間では8両の方が速く、同じ速度から常用ブレーキをかけると10両の停止距離が長くなります。iOSでの加速体感は未確認です。

Swift 6.4.2 Linux で `TrainPhysics` は 23 件 pass、0 fail でした（既存 20 件に編成長の 3 件を追加）。アプリの車両シートは型検査していません。

```sh
cd Packages/TrainPhysics && swift test
```

### 制御方式別の運転台と合成音（2026-11-06）

VVVF・界磁チョッパ・抵抗制御で、机の色、レバーの数と形、計器の置き方、合成した主電動機音、ドアモーター音を分けます。系列名は公開されている見た目へのPLACEHOLDER言及で、ライセンス再現でも実録音でもありません。iOSでの表示と再生は未確認です。

Swift 6.4.2 Linux で `RailwayAudioEnhancements` は 13 件 pass、0 fail でした（既存 11 件に運転台配置と合成音の 2 件を追加）。RealityKit の運転台パッケージは Linux ではコンパイルできないため、机のメッシュ自体は未実行です。

```sh
cd Packages/RailwayAudioEnhancements && swift test
```

### 天候と走行（2026-11-06）

乾燥・雨・強い雨・雪・霧は `FictionalWeatherDrivingCoupling` の PLACEHOLDER 値で粘着と視程を決め、固定tickの物理へ渡します。風速の二乗に比例する抵抗も同じtickで走行抵抗に加わります。霧は粘着を下げません。iOSでの見た目と加速の体感は未確認です。

Swift 6.4.2 Linux では `EnvironmentConditions` が 11 件 pass、`TrainPhysics` が 20 件 pass、どちらも 0 fail でした。前者は天候結合 2 件を追加し、後者は抵抗 1 件を追加しています。アプリの天候切替と画面の霧は Linux では型検査・表示確認していません。

```sh
cd Packages/EnvironmentConditions && swift test
cd Packages/TrainPhysics && swift test
```

### 走行後レビュー（2026-11-06）

終了時の結果画面は、既存の総合スコアに加えて定時性・停止精度・速度遵守・信号遵守と、距離軸の速度/ブレーキ曲線を出します。曲線と集計は固定tickの間引きサンプルから作り、物理tickの刻み自体は変えていません。未記録の項目は0点にせず未採点です。配点はゲーム用PLACEHOLDERです。iOSでの画面確認は未実施です。

Swift 6.4.2 Linux で `Packages/RailwaySessionPersistence` の `swift test` は 17 件 pass、0 fail でした（既存 13 件に、曲線間引きと採点集計 4 件を追加）。結果画面の SwiftUI は Linux では型検査・表示確認していません。

```sh
cd Packages/RailwaySessionPersistence && swift test
```

### 架空保安装置と物理tickの接続（2026-11-06）

`ProtectionSystems`のブレーキ要求を`FictionalProtectionPhysicsCoupler`でサービス/非常ブレーキと牽引遮断に変換し、ホストの固定tickが`FictionalLiveProtectionSession`を進めてから物理を1 tick進めます。対象はATS-S、ATS-P、ATS-Ps、ATC、EBです。ATO牽引とデッドマン開放は未接続です。値はPLACEHOLDERです。iOSビルドと実機の制動体感は未確認です。

Swift 6.4.2 Linux で `Packages/ProtectionSystems` の `swift test` は 21 件 pass、0 fail でした（既存 13 件に、物理結合 8 件を追加）。ホストの `SimulatorModel` はこの Package を固定tickから呼びますが、そのアプリターゲットは Linux では型検査していません。他 Package の全行列は再実行していません。

```sh
cd Packages/ProtectionSystems && swift test
```

### 沿線ビート追加後の確認（2026-11-06、この作業）

`RailwaySceneFidelity` に架空の橋・切取・築堤・静的踏切のスケジュールとメッシュを追加し、低/中品質ホストは同じスケジュールの粗い箱を置きます。踏切は連動・物理停止ではありません。iOSビルド、アプリホストXCTest、実機表示は未実施です。低/中品質の `RailwaySceneView` 変更は Linux では型検査できません（RealityKit / UIKit）。

この作業で再実行したのは `Packages/RailwaySceneFidelity` だけです。Swift 6.4.2 Linux で `swift test` は 13 件 pass、0 fail です（既存 7 + Actor 投影 2 + 追加 `SceneCorridorLandmarkTests` 4）。以前の全 Package 行列 163 pass に、未再実行の Package を足して新しい合計にしてはいけません。

```sh
cd Packages/RailwaySceneFidelity && swift test
```

## Mac/Xcodeで最初に行う作業

- [ ] `PACKAGE_INVENTORY.md`のファイル数/サイズ/SHA-256とZIPのCRC・メンバー・ハッシュ検証結果を確認し、ZIPを展開して`Packages/`を含むプロジェクト一式を同じフォルダ構造のまま配置する。
- [ ] `RailwayMasterPhase1.xcodeproj`を開き、app targetのローカル20 package productsとXCTest targetの13 package productsが解決することを確認する。
- [ ] scheme `RailwayMasterPhase1`でiOS Simulator向けクリーンビルドを行い、Swift型/actor isolation/package/resource参照/警告を確認する。
- [ ] アプリホストXCTest 42件を実行し、結果を保存する。静的スクリプトに数えられたテストメソッドは実行済みを意味しない。
- [ ] Mac/Xcode上で`Packages/*`を再実行し、LinuxでRealityKit不足により実行できなかった2 Packageを含め、失敗・build-only・実行不能を区別して記録する。
- [ ] 失敗、フレーク、クラッシュ、コンソール警告を修正し、クリーンビルドと全テストを再実行する。
- [ ] Simulatorで起動し、短距離デモではなく70 km架空ネットワークのルート選択と運転画面が表示されることを確認する。

## 運行・時刻表・交通

- [ ] 本線60 km＋支線8 km＋車庫線2 km、32駅、6種別を画面とデータで照合する。
- [ ] 本線・支線・直通・車庫移動の4 variantを上下方向で試し、48 route variant×service×directionの始終点・停車順を確認する。
- [ ] 平日・土曜・休日、朝ラッシュ・日中・夕方・夜間、144生成時刻表パターンで駅時刻・停車/通過を確認する。
- [ ] 初期遅延、出発待ち、駅別計画時刻/遅延、ダイヤ設定変更を確認する。適用待ち設定ではsaveが拒否されること、リセット後に新設定が有効になることも確認する。
- [ ] AI列車、道路車両、ホーム歩行者、閉そく・3現示・速度保護・教材ATS、車庫移動、保守イベントが同じsimulation timeで整合するか確認する。地域監査画面のProtectionSystems表示は別の架空デモであり、ライブ物理や実運転規則へ接続されていないことも確認する。

## ゲームモードと駅別採点

- [ ] 運転士・ダイヤ・フリー・車掌・異常対応・教習・全線・観光・会社運行の9モードを個別に選択する。
- [ ] 練習・標準・異常対応訓練・フリー走行の4スタイルが許可されるモードにだけ現れることを確認する。
- [ ] モード画面を閉じてもモデル側の固定tickで進み、再度開いて同じ状態/評価が見えることを確認する。
- [ ] 到着/発車、信号/教習prompt、交通列車不足、ダイヤ不足、始発条件など、モード別の受入/ブロック/判定不能を試す。
- [ ] 停車採点で誤差m/cm、到着/発車時刻、編成の架空ホーム範囲、停車順、累積評価を確認する。ゲーム配点は停車精度75・時刻25。
- [ ] 車掌ゲームの受理済みドア開扉/閉扉確認が該当駅の別採点へ記録され、誤った側/未実施/重複イベントを確認する。
- [ ] `unknown`/`missing` な期待側・手順は0点や誤操作と混同せず、未採点/対象外で表示されることを確認する。全て架空データであり実手順評価ではない。
- [ ] 20段階の架空乗務ワークフローを進め、再表示・保存/復元後もphaseとevent履歴が保たれることを確認する。業務手順・資格訓練として表示しない。
- [ ] 手動の架空incident発生、固定tick遅延、復旧選択、基地状態遷移を確認する。実故障診断/整備/出庫判断として表示せず、保存/復元後のstateと境界を確認する。

## セーブ・再開

- [ ] 「セーブ / 再開」画面を開くと走行が止まり、画面を閉じても時間が飛ばないことを確認する。
- [ ] 走行中に保存し、セーブ名/slot/運転時刻を表示し、別の状態へ移った後にロードすると、車両位置・速度・各車ブレーキ状態・固定tick・車両・操作が一致することを確認する。
- [ ] 遅延を含む時刻表、AI交通・運行列車・ATS、環境/カメラ/描画品質/音量、停車とドアイベント履歴、9モード進行、乗務ワークフロー/incident state、運転ログが続くことを確認する。
- [ ] 再開時に一時停止で開き、利用者が明示的に再開することを確認する。
- [ ] 同じセーブを複数回ロードした場合に重複イベントや時刻巻き戻りが起きないことを確認する。
- [ ] 誤ったroute/vehicle/build/subsystem versionまたは破損JSONは拒否され、部分的な状態変更を起こさないことを確認する。
- [ ] 既存`OperationsGameplayCoordinator`/`MaintenanceGameplayCoordinator`の別ゲーム内進行はrestore対象外であることを確認する。新しいCrewWorkflow/IncidentMaintenance DTOとは区別する。バックグラウンド自動保存・iCloud/端末間同期は未対応として扱う。

## 編成物理・環境・3D・音

- [ ] 抵抗制御4両、界磁チョッパ6両、VVVF GTO 6両、IGBT 8両、SiC 8両で編成・ノッチ・物理/音設定を確認する。
- [ ] 1/120秒tick、車両ごとの制動圧力、温度/フェード、粘着/滑走、牽引・回生・空気制動、電流/電圧、停止距離表示を確認する。値を実車安全値として扱わない。
- [ ] 運転台/前方/追従カメラ、昼夜、霧/視程、雨/雪、風、前照灯、ワイパー、低/中/高品質を切り替え、前方ビューの空背景が仮想時刻・霧/視程・降水に沿って変化することを実機で確認する。
- [ ] 環境rendererのwetness/snowSurfaceCoverageがSceneSurfaceWeatherへ渡り、高品質生成材の色・roughnessが値の変化に応じて更新されることを確認する。これは単色材質の見た目だけで、積雪ジオメトリ・重ね貼りPBR・濡れ/粘着の物理はありません。
- [ ] 高品質を選び、SceneFidelityのチェーン数変換、線路/架線/ホーム/沿線の表示範囲、走行時の再生成、カメラ/LOD/重なりに加え、先頭車の架空手続きモデル・計器・車輪・曲線接線に沿うボギー角・選択速度に応じるワイパー往復を確認する。残車両は既存生成器であり、実車形状・フォトリアル高精細資産ではない。
- [ ] 先頭車の表示灯が非常ブレーキ・ドア開・引張・回生の既存値に追従し、元となるライブ状態がないATSP/ATC/故障灯は消灯したままであることを確認する。低/中品質切替、ルート/車両再構築、iPhone fps/発熱・メモリも別途測る。
- [ ] 合成走行/牽引/制動音、警笛、空気音、チャイム、日英テンプレート/音声合成、音量/無音/一時停止、シミュレーション停止中の操作音を確認する。
- [ ] 案内の固定時計・駅別重複抑止、reset/restore後の重複・取りこぼし、英語音声のvoice fallbackを確認する。英語文面も駅表示名は日本語のままで、ローマ字/英語別名は未整備。実車録音や実列車音ではないことを表示する。

## 実路線参照データ（アプリ運転路線ではない）

- [ ] `Research/RealRouteReference/README.md`、`QUALITY_REPORT.md`、`LICENSES.md`を確認し、CC BY 4.0の出典/加工表示が保たれていることを確認する。
- [ ] 16頂点・2駅線形・801.5 mの`ESTIMATED`計算と、物理ネットワーク長/営業キロ/軌間/信号/勾配/ホーム/停止位置が`UNKNOWN`であることを照合する。アプリの走行路線や距離へ取り込まない。
- [ ] このデータは`Research/`だけに置かれ、許諾未確認BVE素材・元ZIPを含まないことを確認する。

## iPhone品質と配信前

- [ ] 対象iPhone/iOSを記録し、クラッシュ、メモリ、CPU/GPU、fps、発熱、電池、音切れ、長時間運転を測る。
- [ ] 回転、Dynamic Island/ノッチ、バックグラウンド/フォアグラウンド復帰、通知/割込み、長時間セッションを確認する。
- [ ] Apple Developer署名、TestFlight/App Store Connect、メタデータ/価格/契約を現時点のApple情報で確認する。登録・購入・提出・公開は別途承認を得る。

## 完了判定の境界

全路線・駅・車両特性・信号・時刻・シナリオは架空の`PLACEHOLDER`です。現実の鉄道運行、安全判断、資格訓練、実車性能の再現ではありません。上記の過去Linux matrixはその当時の履歴であり、今回のseed付き線形・GLB統合後のテスト結果ではありません。今回追加分のアプリホストXCTest 42件、iOS build、Simulator/実機試験は未実施です。これらが完了するまでは現行ソースをプレイテスト可能と表現しないでください。残差分は[`GAP_REGISTER.md`](GAP_REGISTER.md)を参照してください。


## 決定論的線形・駅3D統合（2026-11-06、このパッケージ更新）

この節は上のSwiftPM baselineとは別の最新編集結果です。利用可能な検証はすべて静的で、アプリをビルドまたは実行した結果ではありません。

| 確認 | 結果 |
|---|---|
| `Scripts/validate_project.py` | PASS — 203 Swift filesのTree-sitter文法、Xcode project 218 object IDs、45 app sources、20 app/13 test package products、JSON 26件、48 route組合せ、42件のホストXCTestソースを確認 |
| `Scripts/validate_generated_3d_assets.py` | PASS — 13 unique GLB 2.0、935 colored triangle primitives、外部URI 0、32駅（本線28/支線4）、S12 5線4面 |
| `Packages/RailwaySceneFidelity/Scripts/validate_scene_fidelity.py` | PASS — 15 Swiftソース/テストの構文と静的統合条件 |
| `PACKAGE_INVENTORY.md --check` | PASS — 356ファイルのサイズ/SHA-256と一致 |
| `Scripts/verify_package_zip.py` | PASS — 最終ZIPの完全なメンバー構成、CRC、全ファイルサイズ/SHA-256一致 |
| `RailwayMasterPhase1Tests` 42 XCTest methods | ソース数だけ確認。Swift/Xcodeがないため未実行 |
| iOSアプリ build / Simulator / 実機 | 未実施。実機表示、性能、フレームレート、メモリ確認も未実施 |

同じseedの線形再現、曲率/半径/緩和区間/カント、上下方向の反転、共有アプリポリライン上の位置・向き・バンク連続性を検査するXCTestソースを追加しました。試験結果をPASSとして数えるのは、Xcodeで実行した後です。


## 駅名・快速／急行の改訂（2026-11-06、今回の作業コピー）

この節は、前回版とは別の`RAILWAY_MASTER_iOS_station_service_revision/`に対する今回の差分です。XCTestソース数は43メソッドです。Swift/Xcodeが利用できないため、追加テストを含めXCTestは実行していません。iOSアプリビルド、Simulator、実機確認も行っていません。前回に記録されたSwiftPMの結果はこの改訂差分を検証したものではありません。

| 確認 | 結果 |
|---|---|
| 駅名32件 | PASS — 運行計画・本線fallback・RouteData・3D駅レイアウト・駅別手順評価を駅ID基準で同期 |
| 駅ID・キロ程・路線・設備/ホーム構成 | PASS — 前回プロジェクトとのデータ比較で不変を確認 |
| 快速・急行 | PASS — 11駅/6駅、共通経路、停車ID参照、分岐・支線中間駅・終点、上下順とチェーン数増加を静的検証 |
| 各駅停車ほか4種別・48時刻表パターン | PASS — 前回プロジェクトとの比較で変更なしを確認 |
| `RegionalIntegrationTests` 新規テスト | ソース追加済み。43件を数えたが、XCTest未実行 |
| iOS build / Simulator / 実機 | 未実施 |
| ZIP / SHA-256 | 新しい作業コピーから別パスへ作成・検証。前回ZIPは保持 |


## 種別階層の修正（2026-11-07、この作業コピー）

この節は `RAILWAY_MASTER_iOS_service_hierarchy_fix/` に対する差分です。前版で快速急行8駅・急行6駅と逆転していた停車駅数を、快速急行7駅・急行9駅へ修正しました。XCTestソース数は43メソッドのまま（既存メソッドへアサーション追加）です。Swift/XcodeがないためXCTestは実行していません。iOSビルド・Simulator・実機確認も未実施です。

| 確認 | 結果 |
|---|---|
| 種別階層 | PASS — 停車駅数 5（特急）< 7（快速急行）< 9（急行）< 11（快速）< 17（準急）< 32（各駅停車）、所要時間 60 < 80 < 100 < 125 < 140 < 150 が種別の格の順に単調増加することを静的検証 |
| 快速急行 | PASS — S01, S11, S16, S21, S26, S28, B04（港南町 S06 を通過へ） |
| 急行 | PASS — S01, S07, S12, S16, S20, S24, S28, B02, B04（東野・緑町・川西町を追加）。引き続き快速の部分集合で、支線の S28・B02・B04 を保持 |
| `Scripts/validate_project.py` | PASS — 上記の階層チェックを含む全項目。Swift文法203ファイル、48 route組合せ、43件のホストXCTestソース数を確認 |
| `Scripts/validate_generated_3d_assets.py` | PASS — 13 GLB / 935 colored triangle primitives / 外部URI 0 / 32駅 |
| iOS build / Simulator / 実機 | 未実施 |


## 沿線風景・駅の質感アップ（2026-11-07、この作業コピー）

この節は `RAILWAY_MASTER_iOS_scenery_station_quality/` に対する差分です。種別階層の修正（快速急行7駅・急行9駅ほか）は維持されています。Swift/XcodeがないためXCTestは実行していません。iOSビルド・Simulator・実機確認も未実施です。

| 確認 | 結果 |
|---|---|
| 沿線テクスチャ | PASS — `scenery_*.png` 9枚すべて256×256（IHDR確認）。レンガ積み・目地・石粒など素材別模様入り、タイリングはラップ描画で維持 |
| 駅GLBの詳細化 | PASS — 5アーキタイプへ `bench_` / `platform_sign_` / `canopy_fixture_` / `vending_` / `bin_` / `white_line_` / `end_fence_` の各接頭辞メッシュが存在。既存メッシュは enhance スクリプトの自己検証で無変更を確認 |
| 沿線モジュールの詳細化 | PASS — `road_marking_` / `street_light_` / `utility_pole_` / `hedge_` / `extra_tree_` が存在。追加は合計501メッシュ |
| 5線4面駅 | PASS — 生成器経由の追加で素材グループ `fictional_vending` / `fictional_vendinglass` / `fictional_bin` が存在（primitive 11→14） |
| `Scripts/validate_generated_3d_assets.py` | PASS — 13 GLB / 1,439 colored triangle primitives / 外部URI 0 / 32駅、＋上記の新規チェック3行 |
| `Scripts/validate_project.py` | PASS — 種別階層チェックを含む全項目 |
| iOS build / Simulator / 実機 | 未実施（追加した家具の見え方は初回ビルド時の目視確認が必要） |


## CIビルド検証の準備（2026-11-07、この作業コピー）

この節は `RAILWAY_MASTER_iOS_ci_build_check/` に対する差分です。アプリ本体のコード・データは質感アップ版から無変更で、種別階層の修正と質感アップは維持されています。

| 確認 | 結果 |
|---|---|
| 追加ファイル | `.github/workflows/ios-ci.yml`（3ジョブ: 静的検証 / Xcodeビルド＋アプリホストXCTest / ローカルPackageテスト）と `CI_BUILD_GUIDE_2026-11-07.md` |
| YAML妥当性 | PASS — パース可能、ジョブ構成とトリガー（push: main / pull_request / workflow_dispatch）を確認 |
| プロジェクト設定との整合 | PASS — 共有スキーム `RailwayMasterPhase1`、iOS 17、Swift 5.0、swift-tools 5.9、リモートPackage依存なし（全てローカル）を確認。Package 2件のパッケージ名とディレクトリ名の不一致はワークフロー側で吸収 |
| `Scripts/validate_project.py` | PASS — 種別階層チェックを含む全項目 |
| `Scripts/validate_generated_3d_assets.py` | PASS — 13 GLB / 1,439 primitives |
| CI実行 | 未実施 — 初回実行は利用者が GitHub へ push した時点。以後のビルド／XCTest結果はCIログで判定する |
