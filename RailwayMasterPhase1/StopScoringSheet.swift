import Foundation
import StopScoring
import SwiftUI

struct StopScoringSheet: View {
    let evaluation: JourneyEvaluation?
    let routeName: String
    let consistLengthM: Double

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    headerCard
                    if let evaluation {
                        StopScoringResultsView(evaluation: evaluation)
                    } else {
                        ContentUnavailableView(
                            "駅別スコアを準備できません",
                            systemImage: "point.topleft.down.to.point.bottomright.curvepath",
                            description: Text("架空の全線データと停車位置の構成を確認してください。")
                        )
                    }
                    Text("この表示はPLACEHOLDERの架空ゲーム規則による参考値です。実在路線・運転技能・安全性の評価ではありません。時刻表、ドア、業務手順の採点は対応データがある場合のみ表示します。")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(16)
            }
            .background(Color(red: 0.035, green: 0.055, blue: 0.075))
            .navigationTitle("駅別停車スコア")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("閉じる") { }
                        .disabled(true)
                        .hidden()
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(routeName)
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Label("編成 \(Int(consistLengthM.rounded())) m", systemImage: "tram.fill")
                Spacer()
                if let evaluation {
                    Text("\(Int(evaluation.averageScore.rounded())) / 100 · \(evaluation.grade.rawValue)")
                        .fontWeight(.heavy)
                        .foregroundStyle(.cyan)
                } else {
                    Text("未評価").foregroundStyle(.white.opacity(0.6))
                }
            }
            .font(.system(size: 11, weight: .semibold, design: .rounded).monospacedDigit())
            Text(evaluation.map { "\($0.stationEvaluations.filter { $0.stopMeasurement != nil }.count) / \($0.stationEvaluations.count) 駅で停車を記録" } ?? "駅別停車記録を待っています")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.white.opacity(0.62))
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.cyan.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.cyan.opacity(0.22), lineWidth: 1))
    }
}

struct StopScoringResultsView: View {
    let evaluation: JourneyEvaluation

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Text("停車駅ごとの記録")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                Spacer()
                Text(evaluation.isComplete ? "完了" : "進行中")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(evaluation.isComplete ? .green : .cyan)
            }
            ForEach(evaluation.stationEvaluations, id: \.stationID) { station in
                stationRow(station)
                if station.stationID != evaluation.stationEvaluations.last?.stationID {
                    Divider().overlay(Color.white.opacity(0.08))
                }
            }
        }
        .padding(13)
        .background(Color.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 13))
    }

    @ViewBuilder
    private func stationRow(_ station: StationEvaluation) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(station.displayName ?? station.stationID)
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                    Text(progressName(station.progress))
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.white.opacity(0.56))
                }
                Spacer(minLength: 8)
                if let measurement = station.stopMeasurement {
                    VStack(alignment: .trailing, spacing: 1) {
                        Text(String(format: "%+.2f m", measurement.signedErrorMeters))
                            .font(.system(size: 12, weight: .bold, design: .rounded).monospacedDigit())
                            .foregroundStyle(measurement.insidePermittedWindow ? .cyan : .orange)
                        Text(String(format: "誤差 %.0f cm · 停車 %.0f点", measurement.absoluteErrorCentimeters, station.componentScores.stop))
                            .font(.system(size: 9, weight: .medium, design: .rounded).monospacedDigit())
                            .foregroundStyle(.white.opacity(0.58))
                    }
                } else {
                    Text("—")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.42))
                }
            }
            if let arrival = station.arrivalDeviationSeconds {
                Text("到着時刻差 \(String(format: "%+.0f", arrival)) 秒（+遅れ / −早着）")
                    .font(.system(size: 9, weight: .medium, design: .rounded).monospacedDigit())
                    .foregroundStyle(.white.opacity(0.55))
            }
        }
        .padding(.vertical, 3)
    }

    private func progressName(_ progress: StationProgress) -> String {
        switch progress {
        case .notStarted: "未到着"
        case .arrived: "到着・停車中"
        case .stopped: "停車記録済み"
        case .departed: "発車記録済み"
        }
    }
}
