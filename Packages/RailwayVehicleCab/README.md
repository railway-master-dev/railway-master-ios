# RailwayVehicleCab

Swift + RealityKitで、完全に架空の通勤車両1両と簡易運転台を手続き生成する独立モジュールです。既存ゲームのモデル・名称・ロゴ・画像・無許諾データは使っていません。

## 3区分ではなく、10個の交換単位に分割

車体・走行・運転台の3分類だけでは、外観調整や別車種への交換で変更範囲が大きくなります。このモジュールでは、RealityKitのEntityを次の**10個の独立グループ**に分けています。窓とドア、屋根機器とパンタグラフ、運転台内装と操作器も別の親Entityなので、個別に差し替え・表示切替・調整できます。

1. 車体シェル・床・妻面
2. 乗降ドア・ステップ
3. 側面窓・前後窓・行先表示
4. 運転台内装・計器盤
5. 可動操作部（主幹制御器、ブレーキ、逆転器、警笛、ワイパー、前照灯スイッチ）
6. 台車・車輪・軸箱
7. 床下機器
8. 屋根・空調機
9. パンタグラフ
10. 前照灯・標識灯・尾灯

部品生成処理、材質、仕様/組立ても別Swiftファイルに分けています。6つの操作器にはそれぞれRealityKit Componentが付き、入力値から回転または平行移動を反映できます。

## 含まれるもの

- 1両の外形と前面・側面・屋根・窓・ドア・台車・車輪・床下機器・パンタグラフ・灯具
- 運転台の座席・簡易計器盤と、値で動かせる6つの操作ノード
- 差し替え可能な10個のRealityKit Entityグループと `VehiclePartGroupComponent`
- 架空車両の寸法・定員・設計速度を持つ `VehicleSpecification` と基本入力検査
- iOS 17以降を対象にしたSwift Package構成

## 座標系・寸法

単位はメートル、Yが上、Xが左右、Zが車両長手方向です。車両前面/運転台はZ負側、レール面はY=0、標準寸法は長さ19.5m・幅2.8m・高さ3.65mです。生成物は基準形状を一括スケールし、長さ15〜25m、幅2.4〜3.4m、高さ3.0〜4.5mを基本検査範囲としています。内部部品寸法は試作値です。

## 統合

### Swift Packageとして追加

`RailwayVehicleCab` はこのプロジェクトのapp targetへリンク済みで、`RailwayVehicleSceneAdapter`が生成モデルをRealityKitシーンへ配置します。`Package.swift` はiOS 17以上です。別ホストへ移植する場合は、以下のLocal Package追加例を使えます。

### RealityKitシーンへ追加

```swift
import RailwayVehicleCab
import RealityKit

let vehicle = RailwayVehicleModelBuilder.build(.fictionalPrototype)
// 既存シーンで車両を置くAnchorEntityへ追加する
existingAnchor.addChild(vehicle.root)

// 運転ロジックから各フレーム/固定刻みに値を反映する例
vehicle.cabControls.setValue(3, for: .masterController) // 0...5
vehicle.cabControls.setValue(0.4, for: .brakeLever)     // 0...1
vehicle.cabControls.setValue(1, for: .reverser)         // -1...1
vehicle.cabControls.setValue(1, for: .hornButton)       // 0...1
vehicle.cabControls.setValue(2, for: .wiperSwitch)      // 0...3
vehicle.cabControls.setValue(1, for: .headlightSwitch)  // 0...1
```

`groups` は `VehiclePartGroup` をキーにした10個の子Entity一覧です。別車両へ差し替える場合はビルダー/仕様を拡張し、アプリ側の物理状態とのマッピングは統合側で定義します。

## 検証

この実行環境にはSwift/Xcode/iOS SDKがなく、コンパイル・RealityKit表示・iOSシミュレーター・実機での描画/性能検証はできていません。MacのXcodeでこのPackageを開き、iOS Simulatorをテスト先に選んで `Product > Test` を実行し、モデルの座標・見た目・フレーム時間を確認してください。

## 未実装・注意

- 実在車両の寸法・機器配置・意匠を再現していません。現状の寸法・部品位置は架空のゲーム用プレースホルダーです。
- 窓は色付き不透明メッシュで、透過/反射/車内との実際の開口整合は未実装です。ドアもスライド機構の外観表現のみで、開閉アニメーション/当たり判定はありません。
- 車輪回転、台車の首振り/上下動、サスペンション、パンタグラフ昇降・架線接触、ヘッドライト照射、灯火切替、ワイパー動作、表示器更新、乗客・内装の詳細は未実装です。
- 連結編成、LOD/instancing、衝突形状、物理/運転系への自動接続、実機最適化は未実装です。
- これは視覚的試作です。現実の鉄道運転・安全判断・訓練に使用できません。
