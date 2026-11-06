import DoorProcedureScoring
import RailwaySessionPersistence
import StopScoring
import SwiftUI

struct SessionResultSheet: View {
    @Environment(\.dismiss) private var dismiss
    let summary: DrivingSessionSummary
    let review: PostRunReview?
    let savedURL: URL?
    let stopEvaluation: JourneyEvaluation?
    let doorProcedureEvaluation: JourneyScoringEvaluation?
    let onRestart: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    scoreCard
                    if let review { reviewCard(review) }
                    traceCard
                    stoppingCard
                    if let stopEvaluation { stationStopCard(stopEvaluation) }
                    scoreBreakdown
                    if let doorProcedureEvaluation { doorProcedureSummary(doorProcedureEvaluation) }
                    dataCard
                    if !summary.interpretationNotes.isEmpty {
                        VStack(alignment: .leading, spacing: 7) {
                            Text("評価メモ")
                                .font(.system(size: 13, weight: .bold, design: .rounded))
                            ForEach(Array(summary.interpretationNotes.enumerated()), id: \.offset) { _, note in
                                Text("• \(note)")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(.white.opacity(0.72))
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .padding(13)
                        .background(Color.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 13))
                    }
                    if let savedURL {
                        ShareLink(item: savedURL) {
                            Label("走行ログ JSON を共有", systemImage: "square.and.arrow.up")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                    }
                    Text("この採点は架空データによるゲーム試作の参考値です。鉄道運転の技能評価・教育・安全判断には使用できません。")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(16)
            }
            .background(Color(red: 0.035, green: 0.055, blue: 0.075))
            .navigationTitle("試走結果")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("閉じる") { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                Button {
                    onRestart()
                    dismiss()
                } label: {
                    Label("もう一度運転する", systemImage: "arrow.counterclockwise")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.borderedProminent)
                .tint(.cyan)
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .background(.ultraThinMaterial)
            }
        }
        .preferredColorScheme(.dark)
    }

    private var scoreCard: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle().fill(Color.cyan.opacity(0.12))
                Circle().stroke(Color.cyan.opacity(0.35), lineWidth: 2)
                if let score = summary.overallScore {
                    Text("\(Int(score.rounded()))")
                        .font(.system(size: 30, weight: .black, design: .rounded).monospacedDigit())
                        .foregroundStyle(.cyan)
                } else {
                    Image(systemName: "minus")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(.white.opacity(0.6))
                }
            }
            .frame(width: 72, height: 72)
            VStack(alignment: .leading, spacing: 5) {
                Text(summary.overallScore == nil ? "評価できる記録が不足" : "総合スコア（参考）")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                Text("\(summary.sampleCount) サンプル · \(elapsedText)")
                    .font(.system(size: 10, weight: .medium, design: .rounded).monospacedDigit())
                    .foregroundStyle(.white.opacity(0.62))
                if let outcome = summary.overallScore {
                    Text("\(Int(outcome.rounded())) / 100")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundStyle(.cyan.opacity(0.9))
                }
            }
            Spacer(minLength: 0)
        }
        .padding(15)
        .background(Color.cyan.opacity(0.075), in: RoundedRectangle(cornerRadius: 15))
        .overlay(RoundedRectangle(cornerRadius: 15).stroke(Color.cyan.opacity(0.22), lineWidth: 1))
    }

    private var stoppingCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("停止位置")
                .font(.system(size: 13, weight: .bold, design: .rounded))
            HStack {
                Text(stopOutcomeName)
                    .font(.system(size: 14, weight: .heavy, design: .rounded))
                    .foregroundStyle(stopTint)
                Spacer()
                if let offset = summary.stopOffsetM {
                    Text(String(format: "%+.1f m", offset))
                        .font(.system(size: 15, weight: .bold, design: .rounded).monospacedDigit())
                        .foregroundStyle(.white)
                }
            }
            Text("停止目標からの距離差。+は目標を越えた側、−は手前です。")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.white.opacity(0.58))
        }
        .padding(13)
        .background(Color.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 13))
    }

    private var scoreBreakdown: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("項目別")
                .font(.system(size: 13, weight: .bold, design: .rounded))
            ForEach(Array(summary.scoreItems.enumerated()), id: \.offset) { _, item in
                HStack(alignment: .top, spacing: 8) {
                    Text(item.category.japaneseTitle)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.84))
                    Spacer(minLength: 6)
                    Text(item.score.map { "\(Int($0.rounded()))" } ?? "—")
                        .font(.system(size: 12, weight: .bold, design: .rounded).monospacedDigit())
                        .foregroundStyle(item.score == nil ? .white.opacity(0.5) : .cyan)
                }
                if !item.reasons.isEmpty {
                    Text(item.reasons.joined(separator: "・"))
                        .font(.system(size: 9, weight: .regular))
                        .foregroundStyle(.white.opacity(0.5))
                        .fixedSize(horizontal: false, vertical: true)
                }
                if item.category != summary.scoreItems.last?.category {
                    Divider().overlay(Color.white.opacity(0.08))
                }
            }
        }
        .padding(13)
        .background(Color.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 13))
    }

    private func doorProcedureSummary(_ evaluation: JourneyScoringEvaluation) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("ドア・手順イベント（架空ゲーム）")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                Spacer()
                if let score = evaluation.scorePercent {
                    Text("\(Int(score.rounded())) / 100")
                        .font(.system(size: 14, weight: .heavy, design: .rounded).monospacedDigit())
                        .foregroundStyle(.cyan)
                } else {
                    Text("採点可能な既知データなし")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.62))
                }
            }
            Text("確定 \(evaluation.finalizedStationCount) 駅 · 未訪問/未確定 \(evaluation.unfinalizedStationIDs.count) 駅は未採点")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.62))
            Text("不明・未提供の値は推測せず、点数の分母にも含めません。")
                .font(.caption2)
                .foregroundStyle(.orange.opacity(0.85))
        }
        .padding(13)
        .background(Color.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 13))
    }

    private var dataCard: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("評価に使った条件")
                .font(.system(size: 12, weight: .bold, design: .rounded))
            Text("路線データ: \(summary.routeDataStatus.rawValue) · シミュレーション: \(summary.isVirtualSimulation ? "仮想" : "未確認")")
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.7))
            Text("信号・保安装置・時刻表の状態も試作シミュレーション内の機能です。")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.white.opacity(0.58))
        }
        .padding(13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 13))
    }

    private func reviewCard(_ review: PostRunReview) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("走行の読み取り")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                Spacer()
                Text(review.trace.dataStatus)
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .foregroundStyle(.orange)
            }
            ForEach(review.lines) { line in
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(line.title)
                            .font(.system(size: 12, weight: .semibold))
                        Spacer()
                        Text(line.score.map { "\(Int($0.rounded()))" } ?? "未採点")
                            .font(.system(size: 12, weight: .bold, design: .rounded).monospacedDigit())
                            .foregroundStyle(line.score == nil ? .white.opacity(0.45) : .cyan)
                    }
                    Text(line.detail)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.white.opacity(0.62))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(13)
        .background(Color.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 13))
    }

    private var traceCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("速度・距離・ブレーキ")
                .font(.system(size: 13, weight: .bold, design: .rounded))
            if let points = review?.trace.points, points.count >= 2 {
                tracePlot(points: points, value: { $0.speedKmh }, limit: { $0.speedLimitKmh }, tint: .cyan, title: "速度 km/h")
                tracePlot(points: points, value: { $0.brakeFraction }, limit: { _ in nil }, tint: .orange, title: "ブレーキ 0–1")
                Text("横軸は距離です。橙の破線は記録された速度制限です。非常ブレーキは1として描きます。")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white.opacity(0.55))
            } else {
                Text("曲線を描くには、時刻の異なる有効サンプルが2件以上必要です。")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.62))
            }
        }
        .padding(13)
        .background(Color.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 13))
    }

    private func tracePlot(
        points: [RunTracePoint],
        value: @escaping (RunTracePoint) -> Double,
        limit: @escaping (RunTracePoint) -> Double?,
        tint: Color,
        title: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundStyle(tint)
            GeometryReader { geometry in
                let size = geometry.size
                let distances = points.map(\.distanceM)
                let minX = distances.min() ?? 0
                let maxX = distances.max() ?? 1
                let spanX = max(maxX - minX, 0.001)
                let series = points.map(value)
                let limits = points.compactMap(limit)
                let peak = max(series.max() ?? 1, limits.max() ?? 0, 0.001)
                ZStack {
                    Path { path in
                        guard let first = points.first else { return }
                        path.move(to: CGPoint(x: x(first.distanceM, minX: minX, spanX: spanX, width: size.width), y: y(value(first), peak: peak, height: size.height)))
                        for point in points.dropFirst() {
                            path.addLine(to: CGPoint(x: x(point.distanceM, minX: minX, spanX: spanX, width: size.width), y: y(value(point), peak: peak, height: size.height)))
                        }
                    }
                    .stroke(tint, style: StrokeStyle(lineWidth: 2, lineJoin: .round))
                    if limits.count >= 2 {
                        Path { path in
                            var started = false
                            for point in points {
                                guard let limitValue = limit(point) else { continue }
                                let pointX = x(point.distanceM, minX: minX, spanX: spanX, width: size.width)
                                let pointY = y(limitValue, peak: peak, height: size.height)
                                if started {
                                    path.addLine(to: CGPoint(x: pointX, y: pointY))
                                } else {
                                    path.move(to: CGPoint(x: pointX, y: pointY))
                                    started = true
                                }
                            }
                        }
                        .stroke(Color.orange.opacity(0.85), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    }
                }
            }
            .frame(height: 92)
            .background(Color.black.opacity(0.25), in: RoundedRectangle(cornerRadius: 8))
        }
    }

    private func x(_ distance: Double, minX: Double, spanX: Double, width: CGFloat) -> CGFloat {
        CGFloat((distance - minX) / spanX) * max(width - 8, 1) + 4
    }

    private func y(_ value: Double, peak: Double, height: CGFloat) -> CGFloat {
        let clamped = min(max(value, 0), peak)
        return height - 6 - CGFloat(clamped / peak) * max(height - 12, 1)
    }

    private func stationStopCard(_ evaluation: JourneyEvaluation) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("駅別の停止・時刻（架空ゲーム）")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                Spacer()
                Text("\(Int(evaluation.averageScore.rounded())) / 100")
                    .font(.system(size: 14, weight: .heavy, design: .rounded).monospacedDigit())
                    .foregroundStyle(.cyan)
            }
            ForEach(evaluation.stationEvaluations, id: \.stationID) { station in
                HStack(alignment: .firstTextBaseline) {
                    Text(station.displayName ?? station.stationID)
                        .font(.system(size: 11, weight: .semibold))
                        .lineLimit(1)
                    Spacer()
                    Text(station.stopMeasurement.map { String(format: "%+.1f m", $0.signedErrorMeters) } ?? "—")
                        .font(.system(size: 11, weight: .bold, design: .rounded).monospacedDigit())
                    Text(station.arrivalDeviationSeconds.map { String(format: "%+.0f s", $0) } ?? "時刻なし")
                        .font(.system(size: 10, weight: .medium, design: .rounded).monospacedDigit())
                        .foregroundStyle(.white.opacity(0.6))
                }
            }
            Text("配点は停車精度75・時刻25のゲーム値です。実停車標や公式遅延ではありません。")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.orange.opacity(0.85))
        }
        .padding(13)
        .background(Color.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 13))
    }

    private var elapsedText: String {
        guard let seconds = summary.elapsedSeconds else { return "時間未算出" }
        return String(format: "%.0f 秒", seconds)
    }

    private var stopOutcomeName: String {
        switch summary.stopOutcome {
        case .notEvaluated: "未評価"
        case .completed: "目標範囲内で停車"
        case .stoppedShort: "目標手前で停車"
        case .passedMarker: "目標を通過"
        case .notStopped: "停車できず"
        case .insufficientSamples: "記録不足"
        }
    }

    private var stopTint: Color {
        summary.stopOutcome == .completed ? .green : .orange
    }
}
