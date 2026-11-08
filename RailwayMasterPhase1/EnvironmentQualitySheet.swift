import EnvironmentConditions
import RailwayRendering
import SwiftUI

/// Serializable UI-level camera choice. Maps to the rendering package's real camera API.
public enum RailwayCameraPreset: String, Codable, CaseIterable, Equatable, Sendable, Identifiable {
    case cab
    case forward
    case chase

    public var id: String { rawValue }

    public var cameraViewMode: CameraViewMode {
        switch self {
        case .cab: return .cab
        case .forward: return .forward
        case .chase: return .chase
        }
    }

    fileprivate var title: String {
        switch self {
        case .cab: return "運転台"
        case .forward: return "前方展望"
        case .chase: return "後方追従"
        }
    }

    fileprivate var detail: String {
        switch self {
        case .cab: return "運転台内から前方を見る視点"
        case .forward: return "車両前方寄りから線路を見る視点"
        case .chase: return "車両後方から追従する視点"
        }
    }
}

/// Three user-facing choices mapped onto RailwayRendering's platform-neutral profiles.
public enum EnvironmentRenderQuality: String, Codable, CaseIterable, Equatable, Sendable, Identifiable {
    case low
    case medium
    case high

    public var id: String { rawValue }

    public var profile: RenderQualityProfile {
        switch self {
        case .low: return .performance
        case .medium: return .balanced
        case .high: return .high
        }
    }

    fileprivate var title: String {
        switch self {
        case .low: return "低"
        case .medium: return "中"
        case .high: return "高"
        }
    }

    fileprivate var batteryDescription: String {
        switch self {
        case .low: return "描画負荷・電池消費を抑える方向の設定です。"
        case .medium: return "画質と描画負荷の中間を狙う設定です。"
        case .high: return "細部・影・表示量を増やすため、負荷や電池消費が大きくなる傾向があります。"
        }
    }
}

/// Complete, platform-neutral choice returned to the host app for explicit integration.
/// It contains fictional EnvironmentConditions plus the user's camera, time and quality choices.
public struct EnvironmentQualitySelection: Codable, Equatable, Sendable {
    public let environment: EnvironmentConditions
    public let cameraPreset: RailwayCameraPreset
    public let renderQuality: EnvironmentRenderQuality
    /// Fictional local scenario time in hours, normalized to 0..<24.
    public let timeOfDayHours: Double

    public var cameraViewMode: CameraViewMode { cameraPreset.cameraViewMode }

    /// Settings resolved from RailwayRendering's actual profile API at nominal thermal condition.
    /// This is a profile starting point, not a device-performance or battery guarantee.
    public var renderQualitySettings: RenderQualitySettings {
        RenderQualityResolver.resolve(profile: renderQuality.profile, thermalCondition: .nominal)
    }

    public init(
        environment: EnvironmentConditions,
        cameraPreset: RailwayCameraPreset,
        renderQuality: EnvironmentRenderQuality,
        timeOfDayHours: Double
    ) {
        self.environment = environment
        self.cameraPreset = cameraPreset
        self.renderQuality = renderQuality
        if timeOfDayHours.isFinite {
            let wrapped = timeOfDayHours.truncatingRemainder(dividingBy: 24)
            self.timeOfDayHours = wrapped < 0 ? wrapped + 24 : wrapped
        } else {
            self.timeOfDayHours = 12
        }
    }

    public static let `default` = EnvironmentQualitySelection(
        environment: .clearDay,
        cameraPreset: .forward,
        renderQuality: .medium,
        timeOfDayHours: 12
    )
}

/// A standalone form that reports the selected values to its caller without depending on SimulatorModel.
public struct EnvironmentQualitySheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var draft: EnvironmentQualityDraft

    private let onSelection: (EnvironmentQualitySelection) -> Void

    public init(
        initialSelection: EnvironmentQualitySelection = .default,
        onSelection: @escaping (EnvironmentQualitySelection) -> Void
    ) {
        _draft = State(initialValue: EnvironmentQualityDraft(selection: initialSelection))
        self.onSelection = onSelection
    }

    public var body: some View {
        NavigationStack {
            Form {
                Section("天候") {
                    Picker("降水", selection: $draft.precipitation) {
                        ForEach(PrecipitationKind.allCases, id: \.self) { kind in
                            Text(kind.displayName).tag(kind)
                        }
                    }
                    Picker("季節", selection: $draft.season) {
                        ForEach(Season.allCases, id: \.self) { season in
                            Text(season.displayName).tag(season)
                        }
                    }
                    Picker("時間帯", selection: $draft.dayPeriod) {
                        ForEach(DayPeriod.allCases, id: \.self) { period in
                            Text(period.displayName).tag(period)
                        }
                    }
                    sliderRow("シナリオ時刻", value: $draft.timeOfDayHours, range: 0...23.9, step: 0.1, valueText: "\(draft.timeOfDayHours.formatted(.number.precision(.fractionLength(1)))) 時")
                    Text("時間帯区分とは別に、描画へ渡す仮想時刻を指定します。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("霧・風・視程・粘着") {
                    sliderRow("霧の濃さ", value: $draft.fogDensity, range: 0...1, step: 0.01, valueText: "\(Int((draft.fogDensity * 100).rounded()))%")
                    sliderRow("風速", value: $draft.windSpeedMps, range: 0...60, step: 0.5, valueText: "\(draft.windSpeedMps.formatted(.number.precision(.fractionLength(1)))) m/s")
                    sliderRow("風向", value: $draft.windDirectionDegrees, range: 0...359, step: 1, valueText: "\(Int(draft.windDirectionDegrees.rounded()))°")
                    sliderRow("視程", value: $draft.visibilityM, range: 1...100_000, step: 100, valueText: "\(draft.visibilityM.formatted(.number.precision(.fractionLength(0)))) m")
                    sliderRow("粘着係数 μ", value: $draft.adhesionCoefficient, range: 0...1, step: 0.01, valueText: draft.adhesionCoefficient.formatted(.number.precision(.fractionLength(2))))
                    Text("強い雨と霧は運転画面の天候切替でも選べます。適用時、降水と霧から視程・粘着のゲーム値（PLACEHOLDER）を置き換えます。風速は走行抵抗に別のPLACEHOLDER係数で入ります。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("照明・ワイパー") {
                    sliderRow("仮想周囲照度", value: $draft.ambientIlluminanceLux, range: 0...120_000, step: 100, valueText: "\(draft.ambientIlluminanceLux.formatted(.number.precision(.fractionLength(0)))) lx")
                    sliderRow("前照灯出力", value: $draft.headlightIntensity, range: 0...1, step: 0.01, valueText: "\(Int((draft.headlightIntensity * 100).rounded()))%")
                    Picker("ワイパー", selection: $draft.wiperState) {
                        ForEach(WiperState.allCases, id: \.self) { state in
                            Text(state.displayName).tag(state)
                        }
                    }
                    Text("前照灯は正規化されたゲーム内出力指令で、実測光束や電力ではありません。ワイパーは降水とは独立した選択です。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("カメラ") {
                    Picker("視点", selection: $draft.cameraPreset) {
                        ForEach(RailwayCameraPreset.allCases) { preset in
                            Text(preset.title).tag(preset)
                        }
                    }
                    Text(draft.cameraPreset.detail)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("描画品質") {
                    Picker("品質", selection: $draft.renderQuality) {
                        ForEach(EnvironmentRenderQuality.allCases) { quality in
                            Text(quality.title).tag(quality)
                        }
                    }
                    .pickerStyle(.segmented)

                    Text(draft.renderQuality.batteryDescription)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    qualityBudgetDescription
                    Text("高品質ではチェーン数ベースの手続き生成シーンを使用します。線路・沿線・ホームは架空プレースホルダーで、実地形・測量・フォトリアル素材ではありません。iPhone性能は未検証です。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Text("実際の電池消費・発熱・フレームレートは端末や描画adapterに依存し、この品質選択は性能を保証しません。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section {
                    Label("全値は架空ゲーム設定です。実観測値ではなく、実運転・安全判断・現実の気象や粘着状態の評価には使用できません。", systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .navigationTitle("環境・描画品質")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("キャンセル") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("選択を返す") {
                        onSelection(draft.selection)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }

    private var qualityBudgetDescription: some View {
        let settings = draft.selection.renderQualitySettings
        let distanceKm = settings.visibleDistanceMeters / 1_000
        return VStack(alignment: .leading, spacing: 3) {
            Text("このプロファイルの描画予算（開始値）")
                .font(.caption.weight(.semibold))
            Text("表示距離 \(distanceKm.formatted(.number.precision(.fractionLength(1)))) km · 植生 \(settings.foliageInstanceLimit) · 景観 \(settings.sceneryInstanceLimit)")
            Text("影スケール \(settings.shadowScale.formatted(.number.precision(.fractionLength(1)))) · 影付きライト \(settings.shadowLightCount) · 降水粒子上限 \(settings.precipitationParticleBudget) · ボリューム霧 \(settings.volumetricFogEnabled ? "有効" : "無効")")
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func sliderRow(
        _ title: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        step: Double,
        valueText: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                Spacer()
                Text(valueText)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            Slider(value: value, in: range, step: step)
        }
        .padding(.vertical, 3)
    }
}

private struct EnvironmentQualityDraft {
    var precipitation: PrecipitationKind
    var fogDensity: Double
    var windSpeedMps: Double
    var windDirectionDegrees: Double
    var visibilityM: Double
    var adhesionCoefficient: Double
    var ambientIlluminanceLux: Double
    var headlightIntensity: Double
    var wiperState: WiperState
    var season: Season
    var dayPeriod: DayPeriod
    var timeOfDayHours: Double
    var cameraPreset: RailwayCameraPreset
    var renderQuality: EnvironmentRenderQuality

    init(selection: EnvironmentQualitySelection) {
        let environment = selection.environment
        precipitation = environment.precipitation
        fogDensity = environment.fogDensity
        windSpeedMps = environment.windSpeedMps
        windDirectionDegrees = environment.windDirectionDegrees
        visibilityM = environment.visibilityM
        adhesionCoefficient = environment.adhesionCoefficient
        ambientIlluminanceLux = environment.ambientIlluminanceLux
        headlightIntensity = environment.headlightIntensity
        wiperState = environment.wiperState
        season = environment.season
        dayPeriod = environment.dayPeriod
        timeOfDayHours = selection.timeOfDayHours
        cameraPreset = selection.cameraPreset
        renderQuality = selection.renderQuality
    }

    var selection: EnvironmentQualitySelection {
        EnvironmentQualitySelection(
            environment: EnvironmentConditions(
                precipitation: precipitation,
                fogDensity: fogDensity,
                windSpeedMps: windSpeedMps,
                windDirectionDegrees: windDirectionDegrees,
                visibilityM: visibilityM,
                adhesionCoefficient: adhesionCoefficient,
                ambientIlluminanceLux: ambientIlluminanceLux,
                headlightIntensity: headlightIntensity,
                wiperState: wiperState,
                season: season,
                dayPeriod: dayPeriod
            ),
            cameraPreset: cameraPreset,
            renderQuality: renderQuality,
            timeOfDayHours: timeOfDayHours
        )
    }
}

private extension PrecipitationKind {
    var displayName: String {
        switch self {
        case .none: return "なし"
        case .rain: return "雨"
        case .snow: return "雪"
        }
    }
}

private extension Season {
    var displayName: String {
        switch self {
        case .spring: return "春"
        case .summer: return "夏"
        case .autumn: return "秋"
        case .winter: return "冬"
        }
    }
}

private extension DayPeriod {
    var displayName: String {
        switch self {
        case .dawn: return "夜明け"
        case .day: return "昼"
        case .dusk: return "夕暮れ"
        case .night: return "夜"
        }
    }
}

private extension WiperState {
    var displayName: String {
        switch self {
        case .off: return "停止"
        case .intermittent: return "間欠"
        case .low: return "低速"
        case .high: return "高速"
        }
    }
}
