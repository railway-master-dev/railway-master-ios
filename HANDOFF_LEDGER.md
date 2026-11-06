# 引き渡し台帳 — Railway Master iOS

更新日: 2026-11-06  
正本プロジェクト: `RAILWAY_MASTER_iOS/`  
配布形式: プロジェクト全体を単一ルートのZIPとして配布

この台帳は、次の担当エージェントがプロジェクトの実装範囲・検証状況・残作業を誤解しないための引き継ぎ要約です。ZIPのSHA-256は自己参照を避けるためこのファイルには埋め込まず、アーカイブ生成後に別途渡される転送記録に記載します。

## 2026-11-06 追加 — 架空の沿線ビート

高品質 `RailwaySceneFidelity` と低/中品質のホストシーンに、チェーン数決定の架空の橋・切取・築堤・踏切を追加しました。踏切は静的 `PLACEHOLDER`（遮断かんは上げた描画）で、連動・物理・保安装置には未接続です。HF-01、実路線の運転化、音声監査、Mac/Xcode/実機確認はこの作業に含めていません。プレイ可能・iPhone試験済みとは扱いません。テスト結果は [`TEST_CHECKLIST.md`](TEST_CHECKLIST.md) のこの日付の追記を正にしてください。

## 完了・同梱済み

- 固定刻みの`TrafficSnapshot`から列車・道路車両・ホーム歩行者の描画ポーズを補間し、route frameへ投影してRealityKit adapterへ送る接続を追加しました。描画側はシミュレーション時刻を進めず、安定actor IDを保ちます。これはLinuxでのポーズ/投影テストと静的接続確認までで、RealityKit実表示を確認したものではありません。
- 実路線参照資料を出典・ライセンス・品質制限・`UNKNOWN`項目を分けて同梱しました。広域参照線形は52区間・26駅・466頂点、35,140.556 mの`ESTIMATED`な地図線形です。別の京都—東寺参照は16頂点・2駅線形・801.5 mの`ESTIMATED`値です。いずれもアプリの運転路線・物理・信号・景観には接続していません。
- BVE調査の最終メタデータ台帳は、同一カテゴリ内SHA-256重複排除後で路線69・車両68、目標100件まで31・32件不足です。カテゴリ間共有hashは10、全体のユニークarchive hashは127です。最新の13アーカイブ由来の541テキスト設定を静的に確認しました。BVEの実行ファイル・コード・プラグイン・画像・音声・車両モデルをZIPやアプリには含めていません。追加レコードには非商用などの権利制限があり、アプリ利用許諾を得たことを意味しません。以前の音声サンプルレビューには別手順の逸脱が報告されており、今回の調査はその是正・再監査ではありません。
- HF-01架空車両部品候補は`Prototypes/VehicleUVModelCandidate/`に独立prototypeとして同梱しました。`GeometryUV/`のPackage manifest・source・testsも同じプロジェクト内に含み、候補READMEの相対依存pathはZIP内へ解決します。HF-01は`RailwayVehicleHighFidelity`/Xcode app target/`RailwaySceneView`へ未統合で、既存builder・操作・telemetry APIを置換していません。フォトリアル品質や実車寸法を主張しません。
- `PACKAGE_INVENTORY.md`に全配布ファイルのサイズとSHA-256を記録し、`Scripts/validate_project.py`はSwift構文、Xcode project参照、JSON、路線/BVE metadata、HF-01の同梱とrelative pathを静的検査します。`Scripts/verify_package_zip.py`でZIPメンバー・CRC・サイズ・ハッシュを検査します。

## 過去のLinux SwiftPM baseline（今回の線形/3D統合前）

以下は今回の決定論的線形・GLB統合より前の履歴結果であり、現行ZIPに対するビルド/テスト結果ではありません。現在の検証状況は本台帳末尾と`TEST_CHECKLIST.md`の最新節を参照してください。

Swift 6.4.2 / Ubuntu Linuxで、ZIP内の20 app Packageと別置きprototypeの`GeometryUV`、計21 package directoriesを対象にしました。アプリmatrixの16 XCTest Packageは163 tests pass・2 skip・0 fail、2 Packageは`swift build`のみpass、`RailwayVehicleCab`と`RailwayVehicleHighFidelity`はLinuxにiOS/RealityKit系Apple frameworkがないため未実行です。別PackageのGeometryUVは7 tests passでした。全17 XCTest Packageの合計は170 pass・2 skip・0 failです。

アプリmatrix内の`Packages/RailwaySceneFidelity`は、最終プロジェクト内で実行した`RailwaySceneFidelityTests` 7件と`SceneTrafficActorTests` 2件の計9件passで、そのうち7件は従来suite、2件はActor投影の追加suiteです。隔離workstreamだけで実行した結果はこのアプリmatrixへ数えていません。

## 残作業・未検証

- Mac/XcodeでのiOS 17+ clean build、型/actor-isolation検査、Package解決、署名は未確認です。
- 当時のアプリホストXCTestソース37件はiOS/Xcode上で実行していません。今回の更新後は42件です（本台帳末尾参照）。LinuxでRealityKitに依存する2 Packageの意味解析・実行結果もありません。
- iOS Simulator/実機での起動、操作、画面・車両・天候・時間帯・交通actorの描画、実機プレイ、フレームレート、メモリ、発熱、音響、クラッシュ/ログは未確認です。プレイ可能・iPhone-testedとは扱いません。
- HF-01 RealityKit候補のメッシュ生成・材質・透明窓・法線/接線・部品干渉・描画負荷・既存車両との共存は未確認で、候補をアプリへ統合していません。
- 実路線線形は調査参照だけです。運転可能なネットワーク、物理・信号・速度制限・ホーム・停車位置、景観への統合は未実施です。
- BVE raw archives・assetsは含めず、アプリ利用権も確認・取得していません。音声サンプルレビューの既報手順逸脱は別途監査が必要です。

## ZIPに含まれない別成果物

- 別置きのscene-motion・vehicle-uv-model作業用ディレクトリそのものはZIPに含みません。最終projectへコピーされたソース/テストと、独立prototypeとして明記したGeometryUVが引き渡し対象です。配布Packageのローカル依存pathはプロジェクト外へ向きません。
- BVEの元アーカイブやダウンロードした第三者assetは含みません。
- 個別SwiftPM実行ログは一時検証環境に別置きで、ZIP内には入りません。検証概要はこの台帳と`TEST_CHECKLIST.md`に記載しています。

## 次の推奨アクション

1. ZIPを展開し、`PACKAGE_INVENTORY.md`と外部転送記録のZIP SHA-256を照合する。
2. Mac/Xcodeでクリーンビルド、20 app Packageを再検証し、RealityKit依存PackageとアプリホストXCTestを実行する。
3. Simulatorと対象iPhoneで短いテスト走行を行い、列車・道路車両・歩行者、天候/時間帯、車両表示、画面遷移、クラッシュ・性能を記録する。
4. HF-01統合の可否、実路線データのアプリ接続、BVE素材の権利処理・追加音声監査は別判断・別作業として扱う。


## 2026-11-06追加 — 決定論的ランダム線形・駅トポロジー・3D統合

元の`RAILWAY_MASTER_iOS_BuildHandoff.zip`を作業元として別コピーを更新しました。入力ZIPは保持しています。今回の線形は同じseedで再現可能で、本線/支線/車庫線それぞれにランダムな直線・緩和・円曲線の長さ、半径、カント範囲を設定しました。上下方向は同じ線形の鏡像です。RealityKit画面が使うポリライン生成を共有関数化し、chainage、位置、向き、バンクの連続性を検査するXCTestを追加しました。

32駅（本線28/支線4）にホーム数と構内形式を設定し、側式・島式・待避・主要駅・終端・5線4面等の共有アーキタイプを割り当てました。車両・運転台・線路・設備・駅・沿線の3D素材をアプリのシーンへ接続し、詳細車両と運転台の読込失敗時は既存車両モデルへ戻ります。32駅ごとのトポロジーは個別ですが、駅舎外観が32種類すべて固有という意味ではありません。

`validate_project.py`はPASS（Swift 203ファイルの文法、Xcode project 218 object ID、45 app source、20 app/13 test package products、JSON 26件、48 route組合せ、アプリホストXCTestソース42件）。3D検証はPASS（13 GLB、935 colored triangle primitives、外部URIなし、32駅、S12 5線4面）。`validate_scene_fidelity.py`もPASS（15 Swiftソース/テストの静的検査）。これらはSwift型検査やXcodeビルドではありません。42件のアプリホストXCTest、iOSビルド、Simulator/実機の視覚・性能確認は未実施です。この環境にSwift/Xcodeはありません。

3D追加パックは提供者がChatGPT生成と説明したものとして記録し、内容を監査して詳細車両/運転台の2 GLBのみ採用しました。27 GLB/21 PNGの残りは同梱していません。提供者READMEの14モデルという説明に対し、実フォルダーには17個の異なる詳細GLBがありました。商用利用・独占権は独立確認していません。Google Driveへのアップロードは依頼者が行うため実施していません。

最終配布ZIPは`../RAILWAY_MASTER_iOS.zip`です。ZIP自己参照を避けるため、配布物全体のSHA-256はZIP外の`../RAILWAY_MASTER_iOS.zip.sha256`に記録します。`Scripts/verify_package_zip.py`でメンバー構成・CRC・各ファイルサイズ/SHA-256を検証済みです。


## 2026-11-06追加 — 架空駅名・快速／急行停車駅の改訂

前回配布版を変更せず、`RAILWAY_MASTER_iOS_station_service_revision/` に分離したコピーで32駅すべての表示名を日本の鉄道駅として自然に見える創作名称へ改訂しました。運行計画、本線fallback、RouteData、3D駅レイアウト、駅別手順評価の名称を駅ID基準で同期し、アプリ側表示は正本の運行計画から取得します。明示的な `PLACEHOLDER` 免責は維持しています。全駅名は[`STATION_AND_SERVICE_REVISION_2026-11-06.md`](STATION_AND_SERVICE_REVISION_2026-11-06.md)に記載しました。

快速は11駅（S01, S04, S07, S10, S12, S16, S20, S24, S28, B02, B04）、急行は6駅（S01, S12, S20, S28, B02, B04）です。急行は快速停車駅の部分集合で、両方とも同じ68 km旅客経路を走り、東浜（S28）の分岐と山里（B04）の支線終点を保ちます。各駅停車・準急・快速急行・特急の停車ID、48件の時刻表パターン、所要時間・運転間隔・方向・時間帯・曜日カレンダーは変更していません。上り/下り反転と支線・本線・終端の処理も既存実装を維持しています。

駅ID、駅キロ程、路線所属、線形、プラットホーム配置、設備トポロジーは元プロジェクトと照合し、変更なしを確認しました。新しいXCTestソースを1件加え、アプリホストXCTestソース数は43メソッドです。ただしSwift/Xcodeがこの環境にないため、XCTest、iOSビルド、Simulator、実機は実行していません。静的検査の結果は[`TEST_CHECKLIST.md`](TEST_CHECKLIST.md)を参照してください。静的PASSをビルド・XCTest PASSと読み替えないでください。

新しい配布物は `../RAILWAY_MASTER_iOS_station_service_revision.zip`、SHA-256記録は `../RAILWAY_MASTER_iOS_station_service_revision.zip.sha256` です。元の `../RAILWAY_MASTER_iOS.zip` とそのSHA-256は保持し、この作業ではGoogle Driveへアップロードしていません。


## 2026-11-07追加 — 種別階層の修正

別コピー `RAILWAY_MASTER_iOS_service_hierarchy_fix/` で快速急行を7駅（S01, S11, S16, S21, S26, S28, B04）、急行を9駅（S01, S07, S12, S16, S20, S24, S28, B02, B04）へ変更しました。急行は引き続き快速の部分集合です。全6種別の停車駅数と所要時間が種別の格の順に単調増加することを、`Scripts/validate_project.py` と既存の統合テストメソッドで検査するようにしました。新しい配布物は `../RAILWAY_MASTER_iOS_service_hierarchy_fix.zip` です（SHA-256はZIP外の転送記録に記載）。iOSビルド・XCTest実行・実機確認は未実施のままです。詳細は [`SERVICE_HIERARCHY_FIX_2026-11-07.md`](SERVICE_HIERARCHY_FIX_2026-11-07.md) を参照してください。


## 2026-11-07追加 — 沿線風景・駅の質感アップ

別コピー `RAILWAY_MASTER_iOS_scenery_station_quality/` で沿線・駅の質感アップを行いました。テクスチャ9種を256px化し素材ごとの模様を追加、駅GLB 5種と沿線モジュールへ家具・設備501メッシュを追加（既存メッシュは無変更）、5線4面駅は生成器経由で同種の追加をしました。新しい配布物は `../RAILWAY_MASTER_iOS_scenery_station_quality.zip` です（SHA-256はZIP外の転送記録に記載）。検証は静的チェックまでで、iOSビルド・XCTest実行・RealityKit表示・実機の見た目／性能確認は未実施のままです。詳細は [`SCENERY_STATION_QUALITY_2026-11-07.md`](SCENERY_STATION_QUALITY_2026-11-07.md) を参照してください。


## 2026-11-07追加 — CIビルド検証の準備

別コピー `RAILWAY_MASTER_iOS_ci_build_check/` に GitHub Actions によるビルド検証一式を追加しました（ワークフロー `.github/workflows/ios-ci.yml` とガイド `CI_BUILD_GUIDE_2026-11-07.md`）。新しい配布物は `../RAILWAY_MASTER_iOS_ci_build_check.zip` です（SHA-256はZIP外の転送記録に記載）。CI は未実行で、結果が出るまでは iOSビルド・XCTest実行・実機確認は未実施のままです。失敗時は Actions の Artifacts ログをもとに次版で修正します。リポジトリのルートはプロジェクトフォルダの中身である点に注意してください。
