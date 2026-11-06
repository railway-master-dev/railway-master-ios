# 更新台帳 — Railway Master iOS

更新日: 2026-11-06

入力元`RAILWAY_MASTER_iOS_BuildHandoff.zip`は別置きで保持しています。今回確認した入力ZIPのSHA-256: `43a4f624ab648d3b165f7b01bda26b727af6789e3a4d6a497072a01bb09fdf04`。

## 今回の変更

- 60 km本線、8 km支線、2 km車庫線の線形を、固定の3 km反復からseed付き手続き生成へ置き換えました。同じseedなら同じ線形になり、呼び出し側でseedを変えれば別の線形を再現できます。アプリの既定seedは固定です。
- 曲率・カントは入口/出口の緩和区間で0から円曲線値まで連続的に変化します。仮データの範囲は本線半径900–1,850 m/カント55–105 mm/遷移300–500 m、支線450–900 m/45–90 mm/130–260 m、車庫線450–650 m/35–70 mm/90–150 mです。現実の測量・設計値ではありません。
- 3D線形を作るサンプラーを画面側とテストから共有し、曲線に沿って位置・向き・バンクを積分するようにしました。
- 32駅の配置データを相対式・島式・待避/通過・主要駅・終端・4面ホーム等の構内トポロジーに割り当てました。32件すべてに駅別の線路/ホーム数とモデル参照があります。建築外観を32駅分すべて個別に作ったわけではなく、構内形式ごとのオリジナル3Dアーキタイプを共有します。
- 車両、運転台、線路、設備、駅、沿線のオリジナル/合成モデルを既存RealityKitシーンへ接続しました。高品質表示では、追加提供パックから選別した詳細車両と運転台を使い、読み込み失敗時には従来モデルへ戻ります。沿線駅は近傍モデルを切り替えます。
- 追加パックからは詳細車両・運転台の2 GLBだけを採用しました。追加パック内の27 GLB/21 PNGのうち、他の15個の異なる詳細GLB、10個の重複GLB、全PNGは同梱していません。提供元READMEの「14モデル」と実フォルダー内の17個の異なる詳細モデルには数の不一致がありました。
- 権利情報は提供者の説明（ChatGPT生成）として記録し、独立した著作権・商用利用・独占性の確認とは区別しました。第三者ロゴ・外部画像・外部GLB参照は追加していません。商用配布前の利用条件確認は残っています。

## 主要な変更ファイル

- `RailwayMasterPhase1/RegionalRouteFactory.swift` — 決定論的な線形/曲線生成、支線・車庫線の別範囲、共有3Dポリラインサンプラー
- `RailwayMasterPhase1/TrainPhysics.swift`、`RouteData.swift` — 緩和曲線・カント補間とデータ検査
- `RailwayMasterPhase1/RailwaySceneView.swift`、`ContentView.swift` — 3D線形・駅レイアウト・追加車両/運転台のシーン接続
- `RailwayMasterPhase1Tests/RegionalIntegrationTests.swift`、`TrainPhysicsTests.swift` — 同一seed再現、曲線/半径/遷移/カント、上下方向の鏡像、線形サンプル連続性
- `Packages/RailwaySceneFidelity/.../GeneratedRailwayAssetCatalog.swift`、`GeneratedRailwayAssetLoader.swift`、`Resources/Generated3D/` — カタログ、GLB読み込み、駅/線路/設備/沿線/車両データ
- `Packages/RailwaySceneFidelity/Tests/.../GeneratedRailwayAssetCatalogTests.swift` — GLB構造/駅割当/カタログ検査
- `Scripts/validate_generated_3d_assets.py`、`Packages/RailwaySceneFidelity/Scripts/validate_scene_fidelity.py` — 再実行可能な静的検証
- `ARCHITECTURE.md`、`HANDOFF_LEDGER.md`、`TEST_CHECKLIST.md`、`ACCEPTANCE_CHECKLIST.md` — 更新内容と確認事項

## 検証結果

| 検査 | 結果 |
|---|---|
| `Scripts/validate_generated_3d_assets.py` | PASS — 13個のユニークなGLB 2.0、935個の着色三角形primitive、外部URI 0、32駅（本線28/支線4）、5線4面駅の対応を確認 |
| `Packages/RailwaySceneFidelity/Scripts/validate_scene_fidelity.py` | PASS — 15 Swiftソース/テストを構文解析し、GLB/駅/RealityKit接続の静的条件を確認。Swift型検査やXCTestではありません |
| 変更Swift全体のTree-sitter文法解析 | PASS — プロジェクト203 Swiftファイル。Swiftコンパイラによる意味解析ではありません |
| Python検証スクリプトの`py_compile` | PASS |
| `Scripts/validate_project.py` | PASS — 203 Swift文法、Xcode project 218 object IDs、全45 app sources接続、20 app/13 test package products、JSON 26件、60+8+2 km/32駅、48 route組合せ、42件のホストXCTestソース数を確認 |
| `Scripts/generate_package_inventory.py --check` | PASS — 356ファイルのサイズ/SHA-256台帳一致 |
| 42件のアプリホストXCTest | ソースに存在することを確認。未実行（この環境にSwift/Xcodeがありません） |
| iOSアプリビルド、Simulator/実機表示・操作 | 未実施。ビルド済み/実機確認済みとは扱いません |
| `Scripts/verify_package_zip.py` | PASS — 最終ZIPのメンバー構成、CRC、各ファイルサイズ/SHA-256が作業コピーと一致 |

すべての線路・駅・車両データは架空のPLACEHOLDERです。実運行、土木・軌道設計、安全判断には使えません。Google Driveへのアップロードは依頼者が行うため、この作業では実施していません。

元ZIPとのファイル比較: 14ファイル変更、26ファイル追加、削除0件。


## 2026-11-06追加 — 駅名・快速／急行の見直し

前回統合版の別コピーで32駅の名称を自然な日本語の駅名形式へ置き換え、運行計画、本線fallback、RouteData、3D駅レイアウト、手順評価表示名へ同期しました。全駅名は架空のままで、既存の `PLACEHOLDER` 表示・免責を保持しています。駅ID・位置・路線構成・分岐/終点・プラットホーム情報は変更していません。

快速は11駅、急行は6駅に停車する、同じ68 kmの本線・支線直通パターンにしました。急行は快速停車駅の部分集合です。各駅停車・準急・快速急行・特急の停車パターン、48件の時刻表データはそのままです。詳細は[`STATION_AND_SERVICE_REVISION_2026-11-06.md`](STATION_AND_SERVICE_REVISION_2026-11-06.md)を参照してください。

追加した統合XCTestソースによりソース上のメソッド数は43件です。Swift/XcodeがないためXCTestとiOSビルドは未実行です。今回の静的検査、パッケージ台帳、ZIP照合の結果は`TEST_CHECKLIST.md`に記録しています。新ZIPとSHA-256はプロジェクト外の`../RAILWAY_MASTER_iOS_station_service_revision.zip`および同名`.sha256`へ作成し、前回配布物には触れていません。Google Driveへのアップロードは行っていません。


## 2026-11-07追加 — 種別階層の修正（快速急行／急行）

前版の別コピー `RAILWAY_MASTER_iOS_service_hierarchy_fix/` で、停車駅数が種別の格と逆転していた快速急行（8駅）と急行（6駅）を修正しました。快速急行は港南町（S06）を外して7駅、急行は東野（S07）・緑町（S16）・川西町（S24）を追加して9駅です。所要時間・他の4種別・48件の時刻表パターンは変更していません。修正後は停車駅数 5（特急）< 7（快速急行）< 9（急行）< 11（快速）< 17（準急）< 32（各駅停車）、所要時間 60 < 80 < 100 < 125 < 140 < 150 と単調です。

検証スクリプトへ全6種別の階層チェックを追加し、統合テスト内の既存メソッドにも同じ単調増加アサーションを追加しました（メソッド数は43のまま）。詳細は [`SERVICE_HIERARCHY_FIX_2026-11-07.md`](SERVICE_HIERARCHY_FIX_2026-11-07.md) を参照してください。XCTest・iOSビルド・Simulator・実機確認は未実施です。


## 2026-11-07追加 — 沿線風景・駅の質感アップ

種別階層修正版の別コピー `RAILWAY_MASTER_iOS_scenery_station_quality/` で、沿線テクスチャと駅／沿線GLBの詳細化を行いました。沿線テクスチャ9種は `Scripts/build_original_scenery_textures.py` を書き換えて128pxから256pxへ再生成し、レンガ積み・目地・石粒など素材ごとの模様を入れました（基本色とファイル名は維持、全て自作手続き生成）。駅GLB 5種と沿線モジュールには新規 `Scripts/enhance_station_glbs.py` でベンチ・吊り下げ駅名標・キャノピー照明・自販機・ゴミ箱・白線・ホーム端フェンス、道路センターライン・街路灯・電柱・生垣・追加の木を合計501メッシュ追加し、既存メッシュは無変更で保持しました。5線4面駅は生成器 `Scripts/generate_4platform_station_glb.py` 経由で同種の追加を行いました。全GLBの primitive 合計は935から1,439へ増えました。

検証スクリプトにテクスチャ寸法と enhancement メッシュ存在のチェックを追加し、`validate_project.py` を含め PASS しています。種別階層の修正は維持しています。詳細は [`SCENERY_STATION_QUALITY_2026-11-07.md`](SCENERY_STATION_QUALITY_2026-11-07.md) を参照してください。XCTest・iOSビルド・Simulator・実機確認は未実施です。


## 2026-11-07追加 — CIビルド検証の準備（GitHub Actions）

利用者に Mac がないため、質感アップ版の別コピー `RAILWAY_MASTER_iOS_ci_build_check/` に GitHub Actions ワークフロー `.github/workflows/ios-ci.yml` を追加しました。静的検証（Linux）→ Xcode ビルド＋アプリホスト XCTest 43件（macos-15、Simulator、署名無効）→ ローカル Package 20本のテスト、の3ジョブ構成です。シミュレータは利用可能な iPhone を自動選択し、Package テストのスキーム名は Package.swift のパッケージ名から取得します（ディレクトリ名と異なる2件に対応）。手順と制約（公開／非公開と Actions 分数、iPhone のみでのアップロード方法、CIで分からない範囲）は [`CI_BUILD_GUIDE_2026-11-07.md`](CI_BUILD_GUIDE_2026-11-07.md) にまとめました。アプリケーション本体のコード・データは前版から無変更で、種別階層修正と質感アップは維持しています。

CI 自体は未実行です。初回実行は利用者が本ツリーを GitHub に push した時点で行われます。XCTest・iOSビルド・Simulator・実機確認は引き続き未実施として扱ってください。
