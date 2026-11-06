# RailwayRendering

Native iOS鉄道シミュレーター向けの独立Swift Packageです。路線シーン、車両メッシュ、粒子、RealityKit Entityは生成しません。描画に必要な状態・ポリシーだけを返し、RealityKitの実オブジェクトはアプリ側のadapterが所有します。

## 分担は3区分で十分

この範囲は **カメラ / 環境描画 / 品質制御** の3責務がちょうどよい分割です。入力と出力が分かれている一方、最終的には同じ描画境界へ統合されます。昼夜・雨・雪・霧まで別々に分割すると、視認性と品質設定を共有する手渡しが増える割に、独立性はあまり高まりません。実装は3つのSwift targetに分け、共通値型だけを小さなCore targetに置き、1フレーム単位の統合用Facadeを用意します。新しい責務は独立した所有者・ライフサイクル・テスト契約が生まれた場合に追加します。

## Swift modules

- `RailwayCameraRendering`: 前方展望・運転台・後方追従の視点、滑らかな切替、加減速と曲線に応じた控えめなカメラ動作。
- `RailwayEnvironmentRendering`: 昼夜、相対照明、雨雪、霧・視程の描画状態。粒子やシーン資産は作りません。
- `RailwayQualityRendering`: ULTRA / HIGH / BALANCED / PERFORMANCEのリソース上限と、端末の熱状態を入力にした段階的なプロファイル制限。
- `RailwayRenderingCore`: シミュレーション側と描画側の間で渡すプラットフォーム非依存の値型。
- `RailwayRendering`: 3モジュールを再公開するFacade、`RenderingStateApplying`契約、`RailwayRenderingCoordinator`。

アプリ側は3つの専門targetを直接利用することも、`RailwayRendering` facadeだけをimportすることもできます。

## ホスト統合

このPackageはXcode app targetへリンク済みです。`RailwaySceneView.swift`の`RailwaySceneWorld`が`RenderingStateApplying`を実装し、`RailwayRenderingCoordinator`の各描画フレーム出力をRealityKitへ適用します。濡れ/雪の表面ブレンド値は既存の手続き生成材へ反映します。次のコードは別ホストでも利用できるadapter契約例であり、現在のアプリへ追加する未完了手順ではありません。

```swift
@MainActor
final class SceneAdapter: RenderingStateApplying {
    func apply(camera: CameraPose, environment: EnvironmentRenderState, quality: RenderQualitySettings) {
        // 既存のPerspectiveCamera、ライト、マテリアル、表示数を更新する。
        // Entityや路線シーンを毎フレーム作り直さない。
    }
}

let adapter = SceneAdapter()
let renderer = RailwayRenderingCoordinator(applier: adapter)
renderer.cameraController.viewMode = .forward
renderer.qualityController.selectedProfile = .balanced

renderer.update(
    motion: TrainMotionSample(
        simulationTimeSeconds: simulationTime,
        speedMetersPerSecond: speedKmh / 3.6,
        longitudinalAccelerationMetersPerSecondSquared: accelerationMps2,
        curveRadiusMeters: curveRadiusMeters,
        curveDirection: curveDirection
    ),
    environment: EnvironmentInput(
        timeOfDayHours: localHour,
        weather: mappedRenderingWeather,
        precipitationIntensity: precipitationIntensity,
        visibilityMeters: visibilityMeters
    ),
    deltaTime: renderedFrameDelta
)
```

`simulationTime`、速度、加速度、曲線、天候、視程はホストアプリの型から明示的に変換します。カメラ姿勢は列車ローカル座標（`+Z`が前方）なので、adapterがその位置の線路接線と座標枠を使ってワールド座標へ変換します。既存シーンで前方を`-Z`に取る場合も、この変換境界で吸収し、Core側の型や路線モデルを結び付けません。

物理エンジンの固定刻み更新は変更せず、描画更新はdeltaをクランプして呼びます。照明やマテリアルは変更時に更新し、フレームごとのシーン再構築を避けます。既定プロファイルはBALANCEDです。シミュレーターの天候型から`RenderingWeather`への変換はアプリadapter側で行います。

## 検証上の注意

凍結後のSwift 6.4.2 Linux matrixでは、このPackageの6/6 testsがpassしました。iOS/RealityKitビルドと実機描画・性能・熱・電池は未検証です。品質値とカメラ振幅は設計上の初期値であり、FPS・フレーム時間・バッテリー・発熱の実測値や保証ではありません。代表的なiPhoneでXcode Instrumentsを使い、線路の視認性、連続負荷、熱状態遷移を測ってから調整してください。全体結果は[`../../TEST_CHECKLIST.md`](../../TEST_CHECKLIST.md)を参照してください。
