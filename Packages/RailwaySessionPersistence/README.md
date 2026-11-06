# RailwaySessionPersistence

架空鉄道シミュレーションのセッションを、版管理されたJSONとして保存・検証・復元する独立Swift Packageです。アプリ内部の型や他Packageには依存せず、保存DTO、v1からv2への移行、端末内ファイルストア、端末間移行用のJSONエクスポート／インポートを提供します。

全データはゲーム用の架空値です。実車の挙動、実時刻表、鉄道運転、安全判断、資格訓練には使えません。このPackageはアプリtargetへリンクされ、`SimulatorModel`と端末内save UIから利用されています。別ゲーム進行やbackground/端末間自動同期は保存対象外です。

## 保存する状態

`SimulationSaveState`には次の状態を含められます。

- シミュレーション時刻、固定tick、残り固定刻み時間、一時停止、走行フェーズ、停車滞留時間
- 路線ID／データ改訂、路線バリアント、方向、距離、停車位置、次駅、完了駅
- 選択編成・音プロフィール・両数・任意の各車位置、他の列車／移動体のID・線路・位置・速度
- 操作ノッチ、物理モデルIDと版、物理エンジン／ホスト双方の固定刻み残時間、位置・速度・加速度・乗車率・制動応答・空気圧・粘着／滑走フラグ・力の状態
- モード、プレイスタイル、状態、ヒント数、進行データ、評価データ
- カレンダー・時間帯・種別・方向・遅延・駅別の予定／実績時刻表イベント
- 天候・降水・霧・風・視程・粘着係数・照度・前照灯・ワイパー・季節・時刻
- カメラ、描画品質、音量、操作レイアウト、触覚設定
- 運転記録、および信号・運行・ATS・交通・保守・採点などの名前空間付きサブシステム状態
- アプリ／路線／車両カタログの互換性情報

モード固有状態やアプリ内サブシステムの実データをどのようにDTOへ投影するかはホストアプリの責任です。このPackageは既存 `SimulatorModel` のprivate状態を読み取ったり、アプリへ自動接続したりしません。統合時の対応表は [`INTEGRATION.md`](INTEGRATION.md) を参照してください。

## 形式と移行

- JSONエンベロープのschemaは `jp.railwaymaster.session-save`、現在の `schemaVersion` は `2` です。
- v2は厳密な範囲検証後にのみ読み込みます。不正な数値、範囲外の位置や設定、サイズ超過、未対応のschema／版は復元前に拒否します。
- v1は明示的な移行処理でv2 DTOへ変換します。v1に含まれなかった設定、詳細物理状態、時刻表停車列、サブシステム進行は安全側の明示的初期値になります。読み込み結果には移行元版と注意メッセージが付きます。
- 拡張状態には型付き `SaveJSONValue` を使い、将来の未知識別子も文字列として保持できます。永続ファイルは8 MiBまで、JSON拡張値は深さ64までです。
- `FileSaveStore` はスロット名を英数字・`-`・`_`に制限し、同じディレクトリ内のatomic writeで保存します。`exportData`／`importData` は検証済みJSONを返すため、アプリ側でAirDrop、Files、クラウドストレージ等の転送方法を選べます。このPackage自体はクラウド同期や暗号化を実装しません。

## 使用例

```swift
import RailwaySessionPersistence

let store = try FileSaveStore(directoryURL: appSupportURL.appendingPathComponent("SessionSaves"))
try store.save(saveState, toSlot: "autosave")

let restored = try store.load(slot: "autosave")
// restored.state を互換性確認・ユーザー確認後にアプリモデルへ適用する。

let portableJSON = try store.exportData(fromSlot: "autosave")
let imported = try store.importData(portableJSON, toSlot: "device-transfer")
// imported.migratedFromVersion があれば移行をUIで説明できる。
```

復元は**検証後に一括適用**してください。路線／車両カタログの不一致時に部分適用したり、物理状態を黙ってリセットしたりしないでください。アプリの状態を更新する処理はメインスレッド／モデルの所有者に残し、この同期的なファイル操作中に物理tickが進まないよう統合側で制御します。

## 対象プラットフォームと検証

Swift tools 5.9、iOS 17、macOS 13を宣言しています。実行可能なXCTestは [`Tests/RailwaySessionPersistenceTests/SessionSaveTests.swift`](Tests/RailwaySessionPersistenceTests/SessionSaveTests.swift) にあります。round trip、v1移行、将来版／schema拒否、数値と環境の範囲検証、未知拡張データ、atomic file store、エクスポート／インポート、スロット名のパストラバーサル拒否、サイズ上限を対象にします。

凍結後のSwift 6.4.2 Linux matrixでは、このPackageの13/13 testsがpassしました。Xcodeクリーンビルド、アプリホスト統合、バックグラウンド復帰、iCloud/端末間自動転送、Simulator／実機テストは未確認です。全体結果は[`../../TEST_CHECKLIST.md`](../../TEST_CHECKLIST.md)、ホスト接続は[`INTEGRATION.md`](INTEGRATION.md)を参照してください。
