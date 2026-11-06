# 車両キャブ — アプリ統合メモ

このSwift PackageはネイティブiOSアプリの12個のローカルpackage依存の一つです。`RailwayVehicleSceneAdapter`と`RailwaySceneView`から`RailwayVehicleModelBuilder`を呼び、選択プロフィールの車両編成をRealityKitへ配置します。車両仕様・寸法・ノッチ・材質は架空のゲーム用データです。

## 現在の接続

- `RailwayVehicleSceneAdapter`は車両モデルを1回生成し、運転台カメラ、速度/速度制限/ブレーキ圧表示、滑走/非常ブレーキ表示を初期化します。
- フレーム更新で物理テレメトリーと運転制御を受け、主幹制御器、ブレーキ、逆転器、警笛、ワイパー、前照灯をキャブ操作器へ反映します。
- 車両プロフィールに合わせて4/6/8両の架空編成を生成します。先頭車へキャブ内装/操作器を付け、各車の走行装置は編成位置と速度に応じて表示します。
- 共有のRealityKit sceneはカメラ、線路/駅/環境、列車表示、描画品質を管理し、Cabモデルはそのscene graph配下で更新します。

## モデル境界

主な公開契約は`RailwayVehicleModelBuilder.build(_:) -> RailwayVehicleModel`、`model.root`、`model.groups[VehiclePartGroup]`、`model.cabControls.setValue(_:for:)`です。制御の値域は主幹制御器0...5、ブレーキ0...1、逆転器-1...1、警笛0...1、ワイパー0...3、前照灯スイッチ0...1です。プロフィールごとの有効ノッチ数はアプリ側の車両データで制限します。

## 未検証

凍結後のSwift 6.4.2 Linux matrixでは`swift test`を実行しましたが、`no such module 'RealityKit'`でbuild failureとなりXCTestは未実行です。これはiOS/Xcode上の成否を示しません。Xcode型チェック、RealityKit描画、Simulator/iPhoneの配置・見た目・スケール・フレームレートも未確認です。手続き生成の低ポリゴン表現であり、フォトリアル素材や実在車両仕様ではありません。Mac/Xcode上でビルド後、対象端末で全プロフィールを確認してください。全体結果は[`../../TEST_CHECKLIST.md`](../../TEST_CHECKLIST.md)を参照してください。
