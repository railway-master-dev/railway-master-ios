# EnvironmentConditions — conditions model and shared snapshot API

This is an isolated, Foundation-only Swift package candidate. It creates deterministic, fictional in-game snapshots; it does not read a clock, use random numbers, call a weather API, or claim measured/real-world data. The package intentionally does not edit the Railway Master project.

## Fields and units / ranges

| Field | Unit / range | Meaning |
|---|---|---|
| `precipitation` | enum: `none`, `rain`, `snow` | Precipitation category only; it does not determine other fields. |
| `fogDensity` | dimensionless, 0...1 | 0 none; 1 dense fog. |
| `windSpeedMps` | m/s, 0...60 | Fictional wind speed. |
| `windDirectionDegrees` | degrees clockwise from north, [0, 360) | Non-finite input becomes 0; finite input wraps modulo 360. |
| `visibilityM` | m, 1...100,000 | Game visibility range (not measured meteorological visibility). |
| `adhesionCoefficient` | dimensionless μ, 0...1 | Explicit virtual wheel/rail adhesion coefficient. |
| `ambientIlluminanceLux` | lux, 0...120,000 | Virtual ambient-light/rendering input (not a measurement). |
| `headlightIntensity` | normalized command, 0...1 | Output command, not wattage or measured luminous flux. |
| `wiperState` | enum: `off`, `intermittent`, `low`, `high` | Independent discrete control state; no inferred behavior. |
| `season` | enum: `spring`, `summer`, `autumn`, `winter` | Independent seasonal context. |
| `dayPeriod` | enum: `dawn`, `day`, `dusk`, `night` | Independent time-of-day context. |

The initializer clamps finite values to the ranges above. Non-finite fallbacks are 0 for fog/wind/direction/illumination/headlight, 100,000 m for visibility, and 0.27 for adhesion. These are safe simulation defaults, not measured values. The named `clearDay`, `rainyDusk`, `foggyNight`, and `snowyWinter` fixtures are stable fictional presets.

## Legacy `WeatherCondition` bridge

The existing app enum has only `.dry`, `.rain`, and `.snow`; its adhesion coefficient is fixed (0.27, 0.17, and 0.10 respectively). This candidate's `legacyWeatherCaseName` gives the case name for a simple switch in the app, without importing that app type:

```swift
let legacy: WeatherCondition
switch conditions.legacyWeatherCaseName {
case "rain": legacy = .rain
case "snow": legacy = .snow
default: legacy = .dry
}
```

This is intentionally lossy: fog-only maps to `.dry`; wind, visibility, illumination, wiper, season, and day-period are dropped. The existing `TrainPhysicsEngine.step/advance(... weather:)` then uses the legacy enum's fixed adhesion value, **not** `EnvironmentConditions.adhesionCoefficient`. To preserve the new coefficient in a future integration, add an environment-aware physics entry point that accepts the validated μ (or extract a shared adhesion input) while keeping the existing `WeatherCondition` overload as a backwards-compatible adapter. Do not silently imply that the current conversion applies visibility, fog, or wind effects.

## Integration status / intentionally unconnected effects

The `EnvironmentConditions` model is linked and used by the app's environment-selection UI and SimulatorModel. The newer `WeatherSnapshot` contract is present in this package but is not yet the single shared input across all consumers. Physics still receives the legacy `WeatherCondition` enum, while `RailwaySceneView` uses a separate rendering state with rain/snow and wet/snow surface hints. Wind loads, contaminant-based adhesion, visibility effects on physics, precipitation particles, glass droplets, and full weather-to-audio integration are not implemented. Do not infer those effects from the presence of a snapshot field.

## Test

From this directory, run `swift test`. Tests use XCTest and Foundation only; there is no iOS, SwiftUI, RealityKit, or third-party dependency.


## 共有 `WeatherSnapshot` API（追加）

画面上の表示を大きく3分類にまとめるのは構いませんが、シミュレーション内部は3択に閉じない方が安全です。雨と落ち葉、雪と強風、霧と雨のように状態は同時に起きるためです。`WeatherSnapshot` は、降水、レール面状態、付着物、風、視程、シナリオ時刻を独立した軸として保持します。既存の `EnvironmentConditions` 型と既存テストは互換のため残し、新しい共通契約は同じ `EnvironmentConditions` moduleに追加しています。

```swift
import EnvironmentConditions

let weather = WeatherSnapshot(
    simulationTimeSeconds: simulationClock.elapsedSeconds,
    timeOfDaySeconds: scenarioClock.secondsSinceMidnight,
    precipitation: PrecipitationState(
        kind: .rain,
        rateMillimetersPerHour: weatherSource.rainRate,
        snowCoverDepthMeters: 0
    ),
    railSurface: RailSurfaceState(
        condition: .wet,
        contaminants: [.leafResidue],
        surfaceFrictionMultiplier: gameTuning.surfaceFriction,
        railAdhesionMultiplier: gameTuning.railAdhesion
    ),
    wind: WindState(
        speedMetersPerSecond: weatherSource.windSpeed,
        gustSpeedMetersPerSecond: weatherSource.gustSpeed,
        directionDegreesFromNorth: weatherSource.windDirection
    ),
    visibilityMeters: weatherSource.visibilityMeters,
    airTemperatureCelsius: weatherSource.temperatureCelsius
)

physics.update(weather: weather)
visuals.update(weather: weather)
audio.updateAmbience(weather: weather)
```

実際の統合先の関数名は例です。生成側が1回のsimulation tickにつき1つの値を作り、物理・描画・音響へ同じ値を渡してください。`surfaceFrictionMultiplier` と `railAdhesionMultiplier` は0...1のゲーム用仮想倍率で、1はそのシナリオの乾燥基準です。実車の摩擦・粘着法則を表す値ではなく、天候から値を自動推定もしません。ゲーム側で調整した値を渡します。視程・気温など不明な実数値は `nil` にできます。

この追加型は Foundation のみを使い、`Codable`, `Hashable`, `Sendable` に対応します。package rootから `swift test` でテストを実行できます。


### 既存workstreamとの接続時の注意

現行の物理・描画・音響入力は`WeatherSnapshot`へ完全統一されていません。`physics.update` / `visuals.update` / `audio.updateAmbience` は将来の接続例であり、実際のホスト関数名ではありません。旧enumへ単純変換すると、落ち葉・粘着倍率・視程・降水強度などが失われるため、将来共有する場合は各 consumer の入力契約と許可されたゲーム効果を明示してください。

## 公式Linux baseline

凍結後のSwift 6.4.2 Linux matrixでは9/9 testsがpassしました。iOS/Xcode統合と実機の環境反映は別途未確認です。全Packageの終了コードと最新検証境界は[`../../TEST_CHECKLIST.md`](../../TEST_CHECKLIST.md)を参照してください。
