# 統合API

## 独立性

このモジュールは`Packages/RailwaySceneFidelity/`にローカルSwift Packageとして同梱され、アプリの高品質RealityKitシーンから利用されています。Package自体はアプリ型や外部Packageに依存せず、ホストの`EnvironmentRenderState`からwetness/snow blendを受け取ります。

## 最小セットアップ

Xcodeで `scene-fidelity` をLocal Swift Packageとして追加し、iOSアプリターゲットから `RailwaySceneFidelity` をimportします。ホストの路線型から、メートル単位の `SceneRouteControlPoint` をチェーン数の昇順で作成します。曲線制御点の接線は `d(position)/d(chainage)`（m/m）として渡します。適切な接線がない場合は省略でき、その場合は隣接制御点から接線を推定します。

```swift
import RailwaySceneFidelity
import RealityKit

let route = try SceneChainageRoute(controlPoints: [
    SceneRouteControlPoint(
        chainageM: 0,
        position: SceneVector3(0, 0, 0),
        tangentPerMeter: SceneVector3(0, 0, 1)
    ),
    SceneRouteControlPoint(
        chainageM: 450,
        position: SceneVector3(38, 1.2, 447),
        tangentPerMeter: SceneVector3(0.20, 0, 0.98),
        bankRadians: 0.025
    )
])

let corridor = SceneCorridorSpecification(
    trackGaugeM: 1.435,
    sleeperSpacingM: 0.60,
    catenarySpacingM: 45,
    overheadContactWireHeightM: 5.2,
    platforms: [
        ScenePlatformSpecification(
            id: "synthetic-platform-a",
            startChainageM: 180,
            endChainageM: 320,
            side: 1,
            offsetFromTrackCenterM: 4.8,
            widthM: 3.6,
            hasCanopy: true
        )
    ]
)

let cameraState = SceneCameraState(
    position: SceneVector3(cameraX, cameraY, cameraZ),
    forward: SceneVector3(forwardX, forwardY, forwardZ),
    chainageM: trainChainageM,
    verticalFieldOfViewRadians: 66 * .pi / 180,
    aspectRatio: viewWidth / viewHeight,
    farDistanceM: 1_200,
    towardIncreasingChainage: true
)

let density = SceneDensityControls.preset(.balanced)
// 0...1の描画ヒント。実際の天候・環境値はホスト側で対応付けます。
let surfaceWeather = SceneSurfaceWeather(wetness: 0.45, snowCoverage: 0)
let plan = RailwaySceneFidelityBuilder.build(
    route: route, corridor: corridor, camera: cameraState, density: density
)
let adapter = RailwayRealityKitSceneAdapter()
adapter.build(plan: plan, camera: cameraState, surfaceWeather: surfaceWeather)
existingWorldAnchor.addChild(adapter.root)
```

例の座標・寸法・間隔は統合APIの説明値です。実在路線の測量結果や設備仕様ではありません。実在データを結ぶ場合は、路線側のデータ品質・ライセンス・位置精度を別に確認してください。

## 毎フレーム更新とチャンク更新

毎フレームは列車の固定刻み物理を変えず、描画カメラ位置・向き・チェーン数・FOVだけを更新します。

```swift
adapter.updateCamera(updatedCameraState)

if !adapter.pendingLODAssemblyIDs.isEmpty {
    adapter.rebuildLODAssemblies(adapter.pendingLODAssemblyIDs, camera: updatedCameraState)
}

if adapter.needsSceneRebuild {
    let nextPlan = RailwaySceneFidelityBuilder.build(
        route: route, corridor: corridor,
        camera: updatedCameraState, density: density
    )
    adapter.build(plan: nextPlan, camera: updatedCameraState, surfaceWeather: surfaceWeather)
}
```

`updateCamera` は現在実体化済みのEntityを距離・視錐台で有効/無効にし、LOD閾値をまたいだassembly IDを記録します。LOD差し替えはカメラが閾値を越えた時だけ `rebuildLODAssemblies` で行います。ビルダーはカメラのチェーン数から前方の可視距離と短い後方余白に限定した計画を返すため、進行に合わせてルートチャンク単位で再構築してください。全経路のEntityを各フレーム作り直さないでください。

`SceneSurfaceWeather` は湿潤と積雪の0...1ヒントを材質色・roughnessへ反映します。統合済みアプリは`RailwaySceneWorld.apply`で環境rendererのblendを渡し、`updateSurfaceWeather(_:)`が0.05以上の変化を既存材質へ反映します。これは単色材質の外観応答だけで、雨粒・積雪メッシュ・濡れ層・摩擦や視程の物理を実装するものではありません。

`adapter.placeholderLabel(forAssemblyID:)` から合成ラベルを取得できます。Entity名にも `SYNTHETIC PLACEHOLDER` が入ります。ゲーム内UIやデバッグ表示でそのラベルを表示・保持してください。

## スケール・座標と責務

- 単位はメートルで、RealityKitのワールド単位へ1:1で渡します。
- 右手系ローカル座標は `+X`=路線右、`+Y`=上、`+Z`=進行方向です。ホストが `-Z` 前方などを使う場合、変換を統合境界で行います。
- チェーン数曲線の方向とバンクは全ての線路・路盤・架線・構造物・沿線要素の配置フレームに反映されます。
- `SceneCorridorSpecification.sleeperSpacingM` と `catenarySpacingM` は物理配置側の入力です。`SceneDensityControls` は描画距離・線路メッシュ分割・景観密度・上限・装飾詳細を調整し、プリセット変更で枕木や架線支持間隔を変えません。
- アセンブリー内は材料ごとにメッシュをまとめ、RealityKit Entity数をプリミティブ個数に比例して増やさないようにしています。
- カリングは境界球とカメラ視錐台による保守的な判定で、遮蔽判定ではありません。`.high/.medium/.far` は距離ヒューリスティックです。

## Xcodeで確認する項目

1. `swift test` とiOS 17+向けパッケージビルド。
2. カメラ方向、ローカル座標、カント、交差する急曲線や制御点付近の接続・重なり。
3. `MeshDescriptor` 法線、材質、配線細線、バンクした曲線上の柱と架線、カリング境界のちらつき。
4. 代表iPhoneでGPU/CPUフレーム時間、Entity数、メモリ、長時間熱状態をXcode Instrumentsで計測し、密度値・チャンク長・LOD境界を調整。

このサンドボックスではSwift/Xcode/iOS SDKが利用できないため、上記ビルド・RealityKit描画確認・iPhone計測は実施していません。
