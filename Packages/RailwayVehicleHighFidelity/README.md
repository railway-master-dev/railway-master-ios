# Railway Vehicle High Fidelity (procedural prototype)

独自の手続き生成GeometryとRealityKitのPBR材質で、完全に架空の都市通勤車両1両と運転台を組み立てるiOS向けSwift Packageです。第三者の車両モデル、BVE素材、実在事業者のロゴ・塗装・図面は含めません。

## 実装範囲

車体の分割外板と前面、側窓・前面窓、ドア窓・シール・取手・戸袋縁、前照灯・標識灯・行先表示板、連結器・貫通幌、2台車の枠・輪軸・車輪・軸箱・ブレーキディスク・キャリパ・ばね・ダンパ、床下インバータ等の機器箱・冷却スリット・配管、空調ユニット・屋根格子、分節パンタグラフを独立したEntity群に分けています。運転台にはシート、ダッシュボード、速度計・ブレーキ管圧力計の針、表示器、状態灯、スイッチ群と15種の操作ノードを配置します。

操作器は値域を制限してEntity姿勢に反映します。独立したビジュアル更新APIでドア開度、ワイパー、パンタグラフ、車輪回転、速度計/圧力計の針、前照灯を更新できます。`setWiperState`はシミュレーション時計から断続/低速/高速の往復角を計算し、`setBogieYaw`は高品質先頭車の前後台車を路線接線へ向けます（どちらも表示用）。さらに`VehicleCabIndicatorState`を渡すと、ATSP・ATC・EB・DOOR・POWER・REGEN・FAULTの7つの表示灯を一括更新できます。統合済みアプリは高品質の先頭車に非常ブレーキ・ドア開・引張・回生を表示します。元になるlive ATSP/ATC/故障状態がないため、その3灯は消灯固定です。これらは表示モデルの更新だけで、運転物理・実際の車両制御・保安装置を代替しません。

## 呼び出し例

```swift
import RealityKit
import RailwayVehicleHighFidelity

let vehicle = RailwayVehicleHighFidelityBuilder.build(.fictionalPrototype)
anchor.addChild(vehicle.root)

vehicle.controls.setValue(3, for: .masterController)
vehicle.controls.setValue(4, for: .brakeLever)
vehicle.animatedParts.setDoorOpenFraction(1)          // 0...1
vehicle.animatedParts.setWiperSweep(0.35)             // radians, internally clamped
vehicle.animatedParts.setWiperState(.high, simulationTimeSeconds: 12.5)
vehicle.animatedParts.setBogieYaw(frontRadians: 0.04, rearRadians: -0.03)
vehicle.animatedParts.setPantographExtension(1)       // 0...1 visual state
vehicle.animatedParts.advanceWheels(distanceMeters: 2.4)
vehicle.animatedParts.setTelemetry(speedKmh: 42, brakePipePressureKPa: 490)
vehicle.animatedParts.setHeadlightsEnabled(true)
vehicle.animatedParts.setCabIndicatorState(
    VehicleCabIndicatorState(atcActive: true, doorsOpen: false, tractionPowerActive: true)
)

vehicle.parts[.bogies]?.isEnabled = true
```

Coordinates are metres: X across the car, Y up, Z along the car, front toward -Z. Default dimensions scale from 19.5 m x 2.8 m x 3.65 m. The optional camera is intentionally left to the app, which should place it at its driver eye point and own camera switching.

## Control values

`VehicleCabControlRig.nodes` exposes entities by `CabControlKind`; `setValue(_:for:)` clamps each to its configured range and updates the corresponding visual lever/button. Master controller is 0...5, brake lever 0...8, reverser -1...1, wiper selector 0...3, and remaining switches/buttons 0...1. The host maps simulator state into the controls and `VehicleCabIndicatorState`; this integrated app supplies only states already present in its fictional simulator. The package does not infer or implement control, traction, braking, or protection behavior.

## Validation status

`Tests/RailwayVehicleHighFidelityTests` contains XCTest coverage for dimensions, named subsystems, control bounds, bogie yaw, time-driven wiper motion, and other animated-state updates. The frozen Swift 6.4.2 Linux matrix attempted `swift test`, but package compilation stopped at `no such module 'RealityKit'`; XCTest did not run. The Linux result does not establish an iOS build failure or success. Xcode, iOS SDK, Simulator, and an iPhone are unavailable here, so iOS compilation, rendered appearance, performance, heat, and battery use remain unverified. The aggregate result is in [`../../TEST_CHECKLIST.md`](../../TEST_CHECKLIST.md).

This is a detailed procedural prototype with per-part geometry and PBR scalar/color parameters, not a photogrammetry asset, sculpted production mesh, or photoreal real train. It has no integrated high-resolution color/normal/roughness maps, custom UV unwrap, measured vehicle reference, rain-on-glass simulation, physically accurate pantograph linkage, or tuned iPhone lighting/LOD. `ArtPrototype/ProceduralPBR/` is a separate original texture experiment and is not loaded by this package. A final commercial-quality pass needs licensed reference material, artist-authored or measured geometry, texture baking, close-up visual review, and target-device profiling.

### PBR texture integration status

The 12 prototype maps pass their 512 × 512, channel, opacity, and wrap-seam checks, but remain outside this package's resources and are not applied to the vehicle. `VehicleGeometry` delegates to RealityKit's generated box, cylinder, and sphere meshes; this package does not author or verify their UV layout or tangent basis for these particular surface maps, and no iOS render was available to confirm scale, orientation, normal-map green-channel convention, or visual seams. That leaves compatibility unproven, so applying the maps now could produce stretched or incorrectly lit surfaces. The smoked-glass maps are opaque (no alpha); any future use must preserve the current glass material's transparent blending and opacity rather than replacing it with an opaque surface.

If the mapping is validated later, load bundle textures asynchronously before building the textured model and retain the current scalar/color palette whenever loading fails. Apple's [`TextureResource`](https://developer.apple.com/documentation/realitykit/textureresource) documentation distinguishes its asynchronous bundle initializer from the synchronous `load(named:in:)` method; avoid synchronous loading in the scene-setup path. Apple documents [`MeshResource.generateBox`](https://developer.apple.com/documentation/realitykit/meshresource/generatebox(size:cornerradius:)-2ovma) as creating a box, but this package does not currently define a project-specific UV mapping contract for its generated meshes.

Windshield and side glazing use a tinted RealityKit transparent-blending PBR material so the driver view can see through it; transparency/reflection ordering and appearance still require an on-device visual review. API references and the reference-material policy are recorded in [REFERENCES.md](REFERENCES.md).
