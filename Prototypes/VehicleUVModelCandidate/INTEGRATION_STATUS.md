# HF-01 車両部品候補 — 統合状態

この架空HF-01部品候補はプロジェクトへ独立したprototypeとして同梱しましたが、iOSアプリのXcodeターゲット、既存の`RailwayVehicleHighFidelity` Package、または`RailwaySceneView`からは参照していません。既存の`RailwayVehicleHighFidelityBuilder`、`VehicleAnimatedPartsComponent`、運転台操作・テレメトリAPIは変更・置換していません。GeometryUV依存も候補prototype内に全ソース・テスト付きで含めており、配布ZIP外の作業領域を参照しません。

## APIと依存

候補の`VehicleComponentModelBuilder.build(_:)`は`VehicleComponentModel`を返し、`root`と20種類の名前付き`parts`を公開する想定です。候補実装は既存モジュールの`VehicleGeometry`、`VehicleMaterialPalette`、`VehicleDetailLevel`、`RailwayVehicleHighFidelitySpecification`を再利用します。そのため`VehicleComponentModel.swift`と`VehicleAuthoredMesh.swift`は、単独の新規RealityKit Packageではなく、将来は既存`RailwayVehicleHighFidelity`ターゲット内へ置く設計です。

RealityKit非依存の幾何コアは`Prototypes/VehicleUVModelCandidate/GeometryUV/`内の完全なSwiftPMパッケージです。`Package.swift`、`Sources/VehicleGeometryUV/VehicleMeshData.swift`、`Tests/VehicleGeometryUVTests/VehicleMeshDataTests.swift`を配布物に含みます。Product/Module名は`VehicleGeometryUV`、公開メッシュ型は`VehicleMeshData`です。`Packages/RailwayVehicleHighFidelity/Package.swift`から依存を追加する場合も、次の相対パスは配布プロジェクト内に解決します。

```swift
.package(path: "../../Prototypes/VehicleUVModelCandidate/GeometryUV")
.product(name: "VehicleGeometryUV", package: "geometryuv")
```

候補ソースは既存Packageの`Sources/RailwayVehicleHighFidelity/`へ追加し、`VehicleComponentModelTests.swift`はそのPackageのテストターゲットへ追加する想定です。統合作業前にXcodeでPackage依存解決とRealityKit APIの型検査を行う必要があります。

## 検証・制限

`GeometryUV`コアのSwift 6.4.2/Linux XCTestは7件pass・0件failでした。候補RealityKitソースは静的Swift構文確認に含まれますが、iOS/RealityKitビルド、候補モデルテスト実行、メッシュ生成、描画、既存車両アニメーションとの併用は未確認です。したがって現在のアプリ車両として使用可能とは扱いません。

候補は全て架空の手続き形状であり、実在車両・実寸・フォトリアル品質を示すものではありません。PBRテクスチャは候補からマテリアルへ結び付けていません。既存の車輪、ボギー、ワイパー、計器、灯火、操作・テレメトリAPIを維持したうえで統合するかどうかを、Xcode Simulatorと対象iPhoneで確認して判断してください。
