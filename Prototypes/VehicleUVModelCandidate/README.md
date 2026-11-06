# Railway component modeling candidate

このフォルダーは、`RailwayVehicleHighFidelity` に追加するRealityKit用の車両部品モデリング候補です。並行中のPBR整理と別作業のシーン移動プロトタイプは変更していません。対象は架空の通勤車両 HF-01 で、実在車両の形状・寸法・性能やフォトリアル品質を示すものではありません。

## 部品の分け方

`VehicleComponentModelBuilder.build(_:)` は、以下20項目をそれぞれ独立した `Entity` グループとして `VehicleComponentModel.parts` に公開します。

1. 前面形状
2. 側面形状
3. 屋根
4. 前面ガラス
5. 側面窓
6. ドア
7. ドアガラス
8. 台車
9. 車輪
10. 軸箱
11. 空気ばね
12. 床下機器
13. モーター関連機器
14. パンタグラフ
15. 連結器
16. 標識灯
17. 前照灯
18. 尾灯
19. 行先表示器
20. 車体表面の細部

各グループ内にも名前付きの部品Entityを作ります。前面ノーズ・屋根クラウン・台車側梁・軸箱・床下機器ケース・主電動機ケース・連結器シャンクには、位置・法線・UVを明示した候補メッシュを使用します。窓ガラスも別メッシュとし、ドアガラスは左右の扉葉ごとに分離して窓部分の背後を塞がない構成です。その他の細部は既存の箱・円柱・球・ロッド生成ヘルパーを利用します。

## 接線フレームと法線マップの扱い

`VehicleMeshData` は三角形とUVから面ごとの接線・従接線を面積加重で集計し、法線に対してGram–Schmidt直交化した単位フレームを生成します。退化した三角形やUVでは決定的な直交fallbackを作って有限・直交性を保ちますが、`supportsNormalMapping` は `false` にします。その場合RealityKitアダプターは接線・従接線バッファを設定しません。`roundedLoft`は周方向シームを重複頂点で分け、前後キャップにも個別UVを割り当てています。

AppleのRealityKit APIには接線・従接線のバッファ属性があります。[`MeshBufferContainer.tangents`](https://developer.apple.com/documentation/realitykit/meshbuffercontainer/tangents) と [`MeshBufferContainer.bitangents`](https://developer.apple.com/documentation/realitykit/meshbuffercontainer/bitangents) は `MeshBuffers.Tangents?` を受け取り、[`MeshBuffers.Tangents`](https://developer.apple.com/documentation/realitykit/meshbuffers/tangents-swift.typealias) は `MeshBuffer<SIMD3<Float>>` です。いずれもAppleの資料ではiOS 15以降に対応するため、候補アダプターは対応する `MeshDescriptor` プロパティへ両方の配列を渡します。したがって、この候補で作るフレームの整合性はテストしますが、元のPBR画像のUV/接線適合や見た目まで保証するものではありません。

接線非対応面は法線マップにも使いません。現在、プロトタイプではどのテクスチャもマテリアルへ結び付けず、既存の色・粗さ・金属度パレットだけを使います。既存のPBRマップはUV/接線互換性と描画結果が未検証のため、別途確認するまで未接続です。

## iOSパッケージへの組み込み候補

`GeometryUV/` はRealityKitを使わないSwiftPMライブラリで、Package.swift・全source・XCTestをこの配布プロジェクト内に同梱しています。候補はアプリ本体へ未統合です。将来`RailwayVehicleHighFidelity`へ組み込む場合は、`VehicleGeometryUV`をローカルSwift Package依存として追加し、候補ソース `VehicleComponentModel.swift` と `VehicleAuthoredMesh.swift` を同ターゲットに、`VehicleComponentModelTests.swift` をテストターゲットに追加します。依存パス `../../Prototypes/VehicleUVModelCandidate/GeometryUV` は既存Package.swiftからこのZIP内へ解決し、外部作業領域には依存しません。SwiftPM package identityは `geometryuv` です。

```swift
.package(path: "../../Prototypes/VehicleUVModelCandidate/GeometryUV")
// RailwayVehicleHighFidelity target:
.product(name: "VehicleGeometryUV", package: "geometryuv")
```

既存の `VehicleGeometry`、`VehicleMaterialPalette`、`VehicleDetailLevel`、`RailwayVehicleHighFidelitySpecification` は既存モジュールの実装を再利用します。生成例:

```swift
let componentModel = VehicleComponentModelBuilder.build(.fictionalPrototype)
anchor.addChild(componentModel.root)
componentModel.parts[.wheels]?.isEnabled = false
```

このビルダーは既存の `RailwayVehicleHighFidelityBuilder` を置き換えません。切り替え前に、前・側・屋根・床下の見え方と既存アニメーション/操作APIとの統合をXcode Simulatorで確認してください。

## AIコーチへの任意利用

別作業のシーン移動プロトタイプでは、対向するAIコーチの外観に単純な箱primitiveを使うRealityKitアダプター案があります。将来、車両パッケージを組み込む際は、そのアダプターからこのビルダーをコーチごとに呼び、返された`root`を各コーチの既存アンカーへ追加できます。各コーチの`identifier`を一意にし、返されたモデル参照を保持します。進行方向や反対向きの配置はアンカー側の姿勢で扱います（車両モデルの前面は-Z方向です）。

```swift
func makeCoach(id: String, anchor: Entity) -> VehicleComponentModel {
    var spec = RailwayVehicleHighFidelitySpecification.fictionalPrototype
    spec.identifier = "ai-coach-\(id)"
    let coach = VehicleComponentModelBuilder.build(spec)
    anchor.addChild(coach.root)
    return coach  // 呼び出し元で保持
}
```

これは後日の統合案であり、シーン移動ファイルは変更しておらず、現状のアプリにも接続されていません。高詳細モデルは多数の部品Entityを生成するため、AIコーチ全台に使う場合は同時表示数、描画負荷、メモリをSimulatorと対象端末で測定し、必要なら低詳細モデルやインスタンス/LOD方式を設計してください。

## 検証状況と留意点

RealityKit非依存の `GeometryUV` パッケージは、Swift 6.4.2/Linuxでビルドし、法線・UV・三角形index・単位接線フレーム・法線との直交性・退化UV fallbackなど7件のXCTestが通過しました。候補RealityKitソースとテストも同バージョンのSwift parserで構文確認しました。これは幾何データ生成コアとSwift構文の確認に限られ、RealityKitアダプターの意味解析・iOSパッケージビルド・Simulator描画の検証ではありません。この環境にXcode、iOS SDK、RealityKit、Simulatorはないため、採用前にMac/Xcodeでクリーンビルドと付属XCTestを実行し、接線/法線表示、窓の透明度・表裏・重なり、車輪/軸箱の干渉、屋根と機器のクリッピング、灯具をSimulatorと対象iPhoneで確認してください。部品数が多いため描画負荷とメモリも計測してください。

RealityKit側のメッシュ生成はAppleの[MeshDescriptor](https://developer.apple.com/documentation/realitykit/meshdescriptor)、[MeshResource.generate(from:)](https://developer.apple.com/documentation/realitykit/meshresource/generate%28from%3A%29-4aahn)、[`MeshDescriptor.Primitives.triangles`](https://developer.apple.com/documentation/realitykit/meshdescriptor/primitives-swift.enum/triangles%28_%3A%29) APIに基づきます。Appleの資料では該当APIはiOS 15以降で利用可能とされ、元パッケージのiOS 17要件を満たします。
