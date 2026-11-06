# CIビルド検証ガイド（Macなしでビルド確認する手順）— 2026-11-07

Macを持っていないため、GitHub Actions の macOS ランナーでビルド検証を行う。
ワークフロー本体は `.github/workflows/ios-ci.yml`。

## CIで分かること・分からないこと

分かること:

- 静的検証（プロジェクト同梱の Python バリデータ3本）
- Xcode クリーンビルドが通るか（型エラー・actor isolation エラーの検出）
- アプリホスト XCTest 43件の合否
- ローカル Swift Package 20本すべてのテスト合否（RealityKit 依存の2本含む）
- 失敗した場合の完全なビルド／テストログ（Artifacts からダウンロード可能）

分からないこと:

- Simulator／実機での見た目（駅の小物の配置、車両の向き・尺度など目視確認）
- 実機の fps・メモリ・発熱
- TestFlight 配布や実機インストール（Apple Developer Program 登録と署名が別途必要）

## リポジトリの作り方（重要）

- リポジトリのルートは、このプロジェクトフォルダの「中身」にする。
  つまり `RailwayMasterPhase1.xcodeproj` と `.github/` がリポジトリ直下に来る形。
  フォルダごと入れ子にするとワークフローが見つからない。
- 公開（Public）か非公開（Private）か:
  - Public: GitHub Actions の標準ランナーは無料で使える（分数制限なし）。
    ただしコードが誰でも見られる状態になる。本プロジェクトは全データ架空だが、
    未公開の個人プロジェクトを晒すことにはなる。
  - Private: 無料枠は月 2,000 分だが、macOS ランナーは10倍カウントされるため
    実質 約200 分/月。フル実行1回で数十分（macOS実時間）消費するため、
    月に数回が限度。push のたびに自動実行されるので、頻繁に push すると枠を食う。
    手動実行（workflow_dispatch）中心の運用が現実的。

## iPhone だけでアップロードする場合

- 一番現実的なのは iOS の Git クライアント（Working Copy 等）で
  ZIPを展開したフォルダをリポジトリに push する方法。
  アプリによっては push 機能が有料プランの場合がある。
- PC を一度だけ借りられるなら、初回 push だけ PC で行うのが最も確実。
  以後の CI 実行・結果確認は iPhone だけでも可能。
- GitHub の Web アップロードはファイル数やフォルダ構造の制約が大きく、
  本プロジェクト（約360ファイル）には非推奨。

## 実行と結果の見方

1. push（main ブランチ）または Actions タブ → 「iOS CI Build Check」→
   「Run workflow」で手動実行。
2. 3つのジョブ（Static validation / Xcode build + app-host tests /
   Local package tests）がすべて緑になればビルド検証は第一関門クリア。
3. 失敗したら、ジョブ画面下部 Artifacts のログ ZIP をダウンロードして
   Muse に渡すこと。ログをもとにエラーを修正した新版を作れる。

## 技術メモ

- ランナー: `macos-15`（同梱 Xcode を使用）。対象は iOS 17 / Swift 5.0
  モード / swift-tools 5.9 のため互換あり。
- 署名: チーム未設定のため `CODE_SIGNING_ALLOWED=NO` で Simulator 向けに
  ビルド／テストする。署名が要る配布系の検証は対象外。
- シミュレータ: ハードコードせず、ランナー上で利用可能な iPhone
  シミュレータをスクリプトで自動選択する。
- Package テストのスキーム名はディレクトリ名ではなく Package.swift の
  パッケージ名から取得する（TrainPhysics → RailwayTrainPhysics 等の
  不一致が2件あるため）。

Created 2026-11-07, together with `.github/workflows/ios-ci.yml`.
CI has not been executed yet at the time of writing: the first run happens
when the user pushes this tree to GitHub.
