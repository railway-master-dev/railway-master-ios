# RAILWAY MASTER — ネイティブiOS鉄道シミュレーション

SwiftUIとRealityKitで作るiOS専用プロジェクトです。正本は架空の70 kmネットワーク（本線60 km＋支線8 km＋車庫線2 km、32駅）です。運転、編成別物理、運行・交通、停車採点、ゲームモード、駅別ドア/手順イベント評価、日英の固定時計音声案内、乗務ワークフロー、架空故障/基地ゲーム、高品質手続きシーン、端末内セーブ/復元をソース統合しています。高品質設定の先頭車には手続き生成の架空車両を使用し、保安装置は既存信号系と独立した架空デモとして同梱しています。

**アプリの運行路線・駅・車両特性・信号・時刻・イベント・風景は架空の `PLACEHOLDER` データです。** 別フォルダの実路線線形は参照専用の調査データで、アプリの運転路線ではありません。実運転、安全判断、資格訓練には使用できません。

BVEの調査は**メタデータのみ**を収録し、配布アーカイブ・コード・プラグイン・画像・音声は含みません。確定台帳はSHA-256カテゴリ内重複排除後の**路線69 / 車両68パッケージ**で、100件ずつの目標まで31 / 32件不足です。BVEデータやアセットはアプリへコピーしていません。最終[調査要約](Research/BVE_RESEARCH_SUMMARY.md)、[CSV台帳](Research/BVE/inventory_final.csv)、[JSON台帳](Research/BVE/inventory_final.json)、[集計](Research/BVE/summary_final.json)、[Round 3/4報告と権利・検査記録](Research/BVE/additional/report.md)、[出典と制限](Research/BVE_RESEARCH_SOURCES_AND_LIMITATIONS.md)を参照してください。以前の63/58基準CSVは履歴として保持しています。

## 全線ネットワークと運行

正本は本線60 km＋支線8 km＋車庫引込線2 km＝物理ネットワーク70 km、32駅（本線28・支線4）です。旅客列車の本線・支線経由は68 km。上下方向と、本線・支線・直通・車庫移動の各ルートを組み合わせます。運行種別は各駅停車、快速、準急、急行、快速急行、特急の6種類です。

駅名は日本の鉄道駅として自然に見える創作名称へ統一しています。快速は11駅、急行は9駅に停車し、同じ本線・支線直通経路を走ります。全駅名と停車順は[今回の駅名・運行改訂ノート](STATION_AND_SERVICE_REVISION_2026-11-06.md)を参照してください。2026-11-07に種別階層（特急5駅・快速急行7駅・急行9駅・快速11駅・準急17駅・各駅停車32駅、所要時間も同じ順に単調増加）へ揃える修正を行いました。詳細は[種別階層の修正ノート](SERVICE_HIERARCHY_FIX_2026-11-07.md)を参照してください。さらに2026-11-07に沿線風景・駅の質感アップ版（テクスチャ256px化と素材別模様、駅・沿線GLBへの家具追加501メッシュ）を作成しました。詳細は[沿線風景・駅の質感アップノート](SCENERY_STATION_QUALITY_2026-11-07.md)を参照してください。さらに2026-11-07に、Macなしでビルド検証を行うための GitHub Actions ワークフローを追加しました。手順は[CIビルド検証ガイド](CI_BUILD_GUIDE_2026-11-07.md)を参照してください（CI自体は未実行）。

運行計画には6種別×上下方向×4時間帯の48基本パターンがあります。時刻表パッケージは平日・土曜・休日の3カレンダーへ展開し、144パターンを扱います。遅延分を出発待ちと各停車駅の計画時刻へ反映し、車庫入出庫移動も含みます。カレンダーと時刻はサンプル値で、実在する営業ダイヤではありません。

## ゲームモードと駅別採点

専用画面から運転士、ダイヤ、フリー、車掌、異常対応、教習、全線、観光、会社運行の9モードを選べます。練習・標準・異常対応訓練・フリー走行の4スタイルは別軸です。モードはシミュレーター本体の固定tickと駅イベントを受け取り、画面を閉じてもモデル側で進みます。モード途中状態はセーブに含めます。

停車採点は駅ごとの停止誤差（m・cm）、到着時刻差、編成が架空ホーム範囲に収まるかを評価します。現在のゲーム配点は停車精度75・時刻25です。走行終了後の結果画面は、その駅別結果に加え、定時性・停止精度・速度遵守・信号遵守と、距離に対する速度とブレーキの間引き曲線を出します。未記録の項目は0点にせず未採点です。配点はゲーム用PLACEHOLDERです。別のドア/手順評価はゲーム内で受理されたドア開扉・閉扉確認を駅別に記録します。既知の架空要件だけを採点し、`unknown`/`missing` は未評価として得点対象から外します。これらの配点・許容値・手順データはすべて架空のゲーム用です。

## 車両物理・運行システム

編成別物理エンジンは1/120秒刻みで進み、車両ごとの質量、制動圧力の伝播、摩擦ブレーキ温度と熱フェード、粘着上限・滑走/再粘着、牽引・回生・電気量を扱います。停止距離推定は架空ゲーム計算で、安全保証ではありません。収録プロフィールは抵抗制御4両、界磁チョッパ6両、VVVF GTO 6両、IGBT 8両、SiC 8両に加え、VVVF・界磁チョッパ・抵抗制御それぞれの8両と10両です。8両/10両の質量・引張力・ブレーキはPLACEHOLDERです。操作の扱いは、つきさぶ５条１６丁目の東武50000系列ページ、循環車線の西武2000系・西武4000系ページに書かれた定速・界磁チョッパ・抵抗制御の説明を定性的に参考にしています。公式諸元ではなく、それらのアドオンファイルは入れていません。西武4000系の10両はページに無い追加PLACEHOLDERです。

閉そく・3現示信号・速度保護・教材用ATS、時刻表列車、道路車両、ホーム上の人々、車庫移動、故障・保守イベントも同じシミュレーション時計へ接続します。架空のATS-S / ATS-P / ATS-Ps / ATC / EBがブレーキを要求したtickでは、牽引を切り、サービスブレーキまたは非常ブレーキを物理更新へ渡します。ATOの牽引指令とデッドマン開放は未接続です。信号・ATS・運行整理は簡略化された架空ゲーム機能で、実設備や運行管理の代替ではありません。

## セーブと復元

運転メニューの「セーブ / 再開」から、走行状態を端末内のJSONスロットへ保存し、選んだスロットから再開できます。再開時は一時停止状態になり、利用者が運転を再開します。物理エンジン内部状態、固定tick時計、路線/次停車、車両・操作、環境と音量設定、時刻表、ATS、交通AI、運行列車、駅別停車/ドア採点、9モード進行、運転記録を保存します。互換性のない版・route・vehicle・scoring stateは復元を拒否します。

新しい乗務ワークフローと架空故障/基地ゲームの進行DTOは保存対象です。一方、既存の`OperationsGameplayCoordinator`/`MaintenanceGameplayCoordinator`の別進行、バックグラウンド中の自動保存、iCloud/端末間同期は未対応です。ダイヤ設定が適用待ちの状態では不整合防止のため保存できません。保存機能はソース統合と静的検査までで、iOS上の実動作は未確認です。

## 3D・環境・音

RealityKitのスタイライズされたシーンに、選択編成、先頭車運転台、走行装置、線路・枕木・架線・駅・道路・建物・植生・踏切、AI列車・道路車両・歩行者を配置します。低/中品質では既存生成器を使い、高品質では`RailwaySceneFidelity`でチェーン数に沿う線路・沿線領域を生成し、先頭車には`RailwayVehicleHighFidelity`の架空手続き車両モデルを使います。高品質シーンにも環境描画側のwetness/snow blendを渡し、生成材の色・roughnessへ反映します。値は正規化され、小さな変化は更新を間引きます。高品質先頭車は車輪と曲線接線に沿うボギー角を更新し、ワイパーは選択モードと仮想時刻に応じて往復します。前方ビューの背景色も仮想時刻に沿って夜明け・日中・夕暮れ・夜へ遷移し、霧/視程と雨雪の色味を控えめに反映します。

高品質シーンと低/中品質シーンには、1,600 m 周期の架空の橋・切取・築堤・踏切をチェーン数で置いています。踏切は上げた遮断かんの静的な `PLACEHOLDER` で、連動や列車の停止にはつながりません。状態は測量データではありません。

これは寸法を意識した架空の手続き表現で、写真測量やフォトリアルな高精細アセットではありません。独自のPBRテクスチャ試作は`ArtPrototype/ProceduralPBR/`に別置きし、現アプリモデルはUV/テクスチャ読込に接続していません。wet/snowの見た目は単色材質の色・roughnessヒントで、重ね貼りPBRや雪ジオメトリではありません。同じ天候は固定tickの粘着と視程も変えます。雨・強い雨・雪は架空の粘着係数を下げ、霧は視程を短くします。風はPLACEHOLDERの速度二乗抵抗として走行抵抗に加わります。実測の粘着表ではありません。ボギー角とワイパーは見た目の更新のみで、軌道接触・懸架・実車操作を再現しません。先頭車の灯火は表示専用で、非常ブレーキ・ドア開・引張・回生の既存ゲーム状態を受け取ります。ATSP/ATC灯は架空のライブ制動要求に追従し、故障灯は消灯固定です。実機表示・視覚品質・フレームレート・発熱も未検証です。音声イベントは固定シミュレーション時計で日英テンプレート/TTSと既存の合成音へ渡しますが、英語文面にも日本語の駅表示名をそのまま渡すため駅名ローマ字/英語別名は未整備です。実車録音・実列車音・BVE音源は同梱しない。警笛、ATS、ドア、踏切、ブレーキ、駆動、コンプレッサー、走行音は手続き合成のPLACEHOLDERで、保安の固定tick、ドア状態、警笛操作、架空踏切から鳴らす。概念的な制御器シグネチャの二重再生はしていない。iOSでの再生は未確認。

列車・道路車両・ホーム上の人々の描画ポーズは固定刻み`TrafficSnapshot`からシミュレーション時刻に沿って補間し、曲線route frameへ投影してRealityKit Actorへ渡します。描画側は時間を進めず、安定IDを保ちます。Linux上のポーズ/投影テストは実行済みですが、RealityKit AdapterのiOSビルド・表示・性能は未確認です。HF-01の20部品・UV/接線候補は[`Prototypes/VehicleUVModelCandidate/`](Prototypes/VehicleUVModelCandidate/INTEGRATION_STATUS.md)に別置きし、既存車両ビルダー・アニメーション/操作APIからはまだ分離しています。

## 実路線参照データ

`Research/RealRouteReference/`には近鉄京都線の京都—東寺間に相当する国土数値情報の線形（16頂点、測地線計算801.5 m）を、CC BY 4.0の出典表示と品質報告付きで収録しています。この距離は測量済みの線路長や営業キロではありません。物理ネットワーク、信号、勾配、カント、ホーム、停止位置は`UNKNOWN`で、アプリへ統合・プレイ可能化していません。README、[`QUALITY_REPORT.md`](Research/RealRouteReference/QUALITY_REPORT.md)、[`LICENSES.md`](Research/RealRouteReference/LICENSES.md)を参照してください。

より広い参照線形として、[`Research/RealRouteExpansion/`](Research/RealRouteExpansion/README.md)に近鉄京都線・京都—大和西大寺の2025年度国土数値情報から抽出した52区間・26駅・466頂点を別途収録しています。35,140.556 mは一般化地図線形から計算した`ESTIMATED`な参照長で、測量線路長・営業キロではありません。軌間・線路本数・勾配・信号・速度制限・ホーム・停止位置などは`UNKNOWN`のままです。このデータも運転路線、物理、信号、描画へは接続していません。出典/加工表示、品質限界、再生成/検証方法は同フォルダにあります。

## 検証状況と次の工程

前回版で実施した2026-11-06時点のSwift 6.4.2 Linux matrixは20 app PackageとZIP内の独立GeometryUV prototypeを確認しました。アプリ16 XCTest Packageは163 pass・2 skip・0 fail、2 Packageはbuild-only pass、2 RealityKit/iOS依存PackageはLinux framework不足で未実行です。GeometryUVは別Packageで7 pass。合計は17 XCTest Packageで170 pass・2 skip・0 failです。app matrix内の`Packages/RailwaySceneFidelity` 9件（7既存+2 actor tests）は最終project pathで実行し、隔離workstreamのログは数えていません。これはiOS buildやplay-testの成功を意味しません。

また `python3 Scripts/validate_project.py` でSwift構文、Xcode project参照、JSON/路線データ、BVE在庫、材質/表示灯/移動actorのソース接続、HF-01のZIP内GeometryUV dependency、アプリホストXCTestソース43件を静的確認します。`PACKAGE_INVENTORY.md`と最終配布ZIPのメンバー、CRC、サイズ、SHA-256を照合します。引き渡し内容と未検証項目は[`HANDOFF_LEDGER.md`](HANDOFF_LEDGER.md)に記録しています。静的検査とLinux SwiftPM結果は、iOSアプリの型チェック・ビルド・実行成功を意味しません。

```sh
python3 -m pip install -r Scripts/requirements.txt
python3 Scripts/generate_package_inventory.py --check
python3 Scripts/validate_project.py
python3 Scripts/verify_package_zip.py ../RAILWAY_MASTER_iOS_FullPackage.zip
```

この作業環境にはSwift toolchainとmacOS/Xcode、iOS SDK、Simulator、実機がありません。したがって`xcodebuild`、アプリホストXCTest 43件、署名、実機表示/操作・性能/発熱/電池・音響は未検証です。高品質3Dは架空の手続きモデルのままで、フォトリアルな実車アセットではありません。現行ZIPをプレイテスト可能・機能動作確認済み・公開可能とは扱わず、Mac/XcodeでクリーンビルドとXCTestを行った後、対象iPhoneで全ルート・全モード・セーブ/復元・環境・性能を確認してください。詳細は [`GAP_REGISTER.md`](GAP_REGISTER.md) と [`TEST_CHECKLIST.md`](TEST_CHECKLIST.md) を参照してください。

## 主な構成

```text
RailwayMasterPhase1.xcodeproj/                 iOS app / XCTest targets
RailwayMasterPhase1/                           SwiftUI、RealityKit、運転・運行モデル
  Resources/FictionalOperationsPlan.json       架空ネットワーク・運行計画
  Resources/FictionalDoorProcedureScoring.json 架空駅別ドア/手順採点データ
Packages/
  RailwayRouteData/ RailwaySignalling/          路線品質検査・信号
  TrafficSimulation/                            地域列車・道路交通・人流
  EnvironmentConditions/ RailwayRendering/      環境・カメラ・表面ブレンド
  RailwayMaintenance/ RailwayOperations/        故障・運行業務教材
  RailwayVehicleCab/ TrainPhysics/              車両・編成物理
  RailwayTimetable/ StopScoring/                架空時刻表・停車採点
  RailwayGameModes/                              9モード状態機械
  DoorProcedureScoring/                          駅別ドア/手順イベント評価
  RailwaySessionPersistence/                     版管理save DTO・atomic slot store
  RailwayAudioEnhancements/                       日英案内・固定時計イベント
  CrewWorkflow/ IncidentMaintenance/              架空乗務・事故/基地進行
  RailwaySceneFidelity/                           高品質の架空線路・沿線生成
  RailwayVehicleHighFidelity/ ProtectionSystems/  架空の先頭車モデル・独立保安装置デモ
RailwayMasterPhase1Tests/                        アプリホスト統合XCTest 43メソッド（未実行）
Scripts/                                         静的検証、ZIP台帳生成/照合/検証
Research/RealRouteReference/                     CC BY 4.0 route reference（アプリ未接続）
PACKAGE_INVENTORY.md                             file/hash inventory
```

[PACKAGE_INVENTORY.md](PACKAGE_INVENTORY.md)は、配布ZIPに含める各ファイルのサイズとSHA-256を列挙した再生成可能な台帳です。内容更新後は`python3 Scripts/generate_package_inventory.py`で作り直し、`python3 Scripts/generate_package_inventory.py --check`で照合します。

## 配信・調査・ライセンス資料

- [日本向けApp Store配信条件・価格点・リリース確認](RESEARCH_PLATFORM_DISTRIBUTION.md)
- [BVE路線・車両調査の結論（最終台帳は路線69・車両68、各100件の目標に未達）](Research/BVE_RESEARCH_SUMMARY.md)
- [BVE調査の出典・除外基準・制限](Research/BVE_RESEARCH_SOURCES_AND_LIMITATIONS.md)
- [3D/PBR素材のライセンス調査（素材は未取得・未統合）](ASSET_LICENSE_RESEARCH.md)
- [参考車両データ・ライセンスインベントリ](VEHICLE_DATA_AND_LICENSE_INVENTORY.md)

BVEの実行ファイル、プラグイン、コード、スクリプト、音声、画像、モデルは実行・同梱・アプリへコピーしていません。確定した路線69/車両68の詳細インベントリと利用条件の**メタデータ**は `Research/BVE/` に同梱し、アーカイブ本体は含めていません。


## 今回の駅名・停車駅改訂

この作業コピーでは、全32駅の表示名を日本の鉄道駅らしい自然な創作名称へ見直しました。快速と急行は同じ本線・支線直通経路を走り、停車駅数は当初の11駅と6駅から、2026-11-07の種別階層修正で11駅と9駅になっています。駅名一覧、停車順、保持したデータ範囲と検証限界は[改訂ノート](STATION_AND_SERVICE_REVISION_2026-11-06.md)と[種別階層の修正ノート](SERVICE_HIERARCHY_FIX_2026-11-07.md)を参照してください。名称も路線・駅・ダイヤも架空の`PLACEHOLDER`データであり、実在駅として提示するものではありません。
