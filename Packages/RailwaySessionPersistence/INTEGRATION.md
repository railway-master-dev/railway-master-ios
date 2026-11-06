# RailwaySessionPersistence — 現在のアプリ統合

このPackageは`Packages/RailwaySessionPersistence`としてXcode projectへローカル参照され、アプリtargetとXCTest targetにリンク済みです。`SimulatorModel`のsave/restore adapterは`SimulatorRuntimeSnapshot`でパッケージ固有DTOとアプリ内部stateをつなぎ、`SessionSaveSheet`が端末内の保存スロットを操作します。ここに残していた独立作業の提案ではなく、現在のホスト実装の要約です。

## 保存される主運転状態

Save envelopeには版付きDTOとしてsimulation clock/tick、route・次停車、vehicle/controls、physics metrics、game mode、timetable stops、environment/preferences、driving log、compatibility revisionsを保持します。アプリ側runtime snapshotは物理エンジン内部値、固定tick残余、schedule/traffic、ATS、停車採点、駅別ドア/手順採点、GameModeSession進行、保留中駅イベント、運転ログrecorder stateなどを保持します。読み込み時は保存JSONを検証し、信頼済みroute/vehicle/catalogと各package snapshotの互換性を照合した後、再開モデルへ適用します。復帰は一時停止状態です。

走行中の明示保存だけを許可し、ダイヤ変更が適用待ちなら保存を拒否します。アプリの`Application Support`領域にローカルスロットを保存し、slot writesはpackageのatomic storeを使います。UIからは各保存を選んで再開できます。

## 現在の非対応境界

運行業務・保守の別ゲーム内コーディネーター進行、バックグラウンド自動保存、iCloud/端末間同期、Files共有UIは未対応です。Packageのexport/import APIがあることはUIや同期を実装済みという意味ではありません。バージョン移行、破損セーブ、互換性不一致をMac/Xcodeと実機でテストする必要があります。

## Xcodeでの受け入れ確認（未実施）

- `swift test`をPackageのルートで実行し、codec/slot/error/atomic write/validation testsを確認する。
- XcodeでiOS Simulator向けクリーンビルド、既存アプリXCTest、14個のapp package依存解決を行う。
- 走行中セーブ/ロード後の物理、交通、ATS、時刻表、stop/door scoring、モード進行と運転ログの連続性を検証する。
- 不正/非互換版、壊れたJSON、書き込み中断、pending timetable configurationの保存拒否を確認し、失敗時に部分変更がないことを確認する。
- 実機でsave容量、書込時間、長時間セッション、画面離脱/再開を試験する。

この実行環境にはSwift/Xcode/iOS SDKがなく、Packageテスト・型チェック・アプリビルド・端末試験は未実施です。実行成功を主張しません。
