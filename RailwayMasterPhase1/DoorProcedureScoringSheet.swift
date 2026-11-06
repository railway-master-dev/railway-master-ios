import DoorProcedureScoring
import SwiftUI

struct DoorProcedureScoringSheet: View {
    @Environment(\.dismiss) private var dismiss
    let evaluation: JourneyScoringEvaluation?
    let errorMessage: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text("この画面は架空ゲーム用のデータとイベントだけを表示します。実在の駅のホーム側・運転取扱い・教育手順を示すものではありません。")
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))

                    if let errorMessage {
                        Label(errorMessage, systemImage: "exclamationmark.triangle")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                    if let evaluation {
                        summaryCard(evaluation)
                        ForEach(evaluation.stationEvaluations, id: \.stationID) { station in
                            stationCard(station)
                        }
                    } else {
                        ContentUnavailableView(
                            "駅別評価を準備できません",
                            systemImage: "door.left.hand.open",
                            description: Text("架空の駅データとルート構成を確認してください。")
                        )
                    }
                    Text("明示されたゲーム用データだけを採点します。値が不明または未提供の項目は推測せず、採点対象から外します。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(14)
            }
            .background(Color(red: 0.035, green: 0.055, blue: 0.075))
            .navigationTitle("ドア・手順のゲーム評価")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("閉じる") { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private func summaryCard(_ evaluation: JourneyScoringEvaluation) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text("駅別イベント")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                Spacer()
                if let score = evaluation.scorePercent {
                    Text("\(Int(score.rounded())) / 100")
                        .font(.system(size: 15, weight: .heavy, design: .rounded).monospacedDigit())
                        .foregroundStyle(.cyan)
                } else {
                    Text("採点可能な既知データなし")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.62))
                }
            }
            Text("確定 \(evaluation.finalizedStationCount) 駅 · 未確定 \(evaluation.unfinalizedStationIDs.count) 駅")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.white.opacity(0.68))
            Text(evaluation.isFinished ? "走行評価は確定済みです。未訪問駅は未採点です。" : "現在の停車・操作イベントを表示中です。駅を発車するとその駅の評価が確定します。")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.58))
        }
        .padding(13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.cyan.opacity(0.08), in: RoundedRectangle(cornerRadius: 13))
    }

    private func stationCard(_ station: StationScoringEvaluation) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline) {
                Text(station.displayName ?? station.stationID)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                Spacer()
                Text(station.isFinalized ? "確定" : "進行中")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(station.isFinalized ? .green : .cyan)
            }
            Label("ドア側: \(doorText(station.doorSideAssessment))", systemImage: "door.left.hand.open")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.82))
            procedureLines(station.procedureAssessment)
            if !station.unmatchedProcedureEventIDs.isEmpty {
                Text("この駅の既知要件にない手順イベント \(station.unmatchedProcedureEventIDs.count) 件（採点なし）")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            HStack {
                Text("獲得 \(station.earnedPoints.formatted(.number.precision(.fractionLength(0...1)))) / \(station.possiblePoints.formatted(.number.precision(.fractionLength(0...1)))) 点")
                Spacer()
                if let score = station.scorePercent {
                    Text("\(Int(score.rounded()))%")
                        .fontWeight(.bold)
                } else {
                    Text("—")
                }
            }
            .font(.caption.monospacedDigit())
            .foregroundStyle(.white.opacity(0.7))
        }
        .padding(13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    private func procedureLines(_ assessment: ProcedureSetAssessment) -> some View {
        switch assessment {
        case .requirementsUnavailable(let issue):
            Label("手順要件: \(dataIssueText(issue)) — 採点対象外", systemImage: "info.circle")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .knownNoRequirements:
            Label("既知の手順要件なし（違反扱い・減点なし）", systemImage: "checkmark.circle")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .requirements(let requirements):
            ForEach(requirements, id: \.stepID) { item in
                HStack(alignment: .top) {
                    Image(systemName: item.result == .completed ? "checkmark.circle.fill" : "circle")
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.title ?? item.stepID)
                        Text("担当: \(roleText(item.expectedRole)) · \(stepText(item.result))")
                            .foregroundStyle(.secondary)
                    }
                }
                .font(.caption)
                .foregroundStyle(.white.opacity(0.82))
            }
        }
    }

    private func doorText(_ assessment: DoorSideAssessment) -> String {
        switch assessment {
        case .pending(let expected): "待機（期待値: \(sideText(expected))）"
        case .earned(let expected, let observed): "一致（\(sideText(observed))）"
        case .incorrect(let expected, let observed): "不一致（期待 \(sideText(expected)) / 操作 \(sideText(observed))）"
        case .notPerformed(let expected): "未実施（期待値: \(sideText(expected))）"
        case .notEvaluable(let issue): "\(dataIssueText(issue)) — 採点対象外"
        }
    }

    private func dataIssueText(_ issue: DataIssue) -> String {
        switch issue {
        case .missing: "データ未提供"
        case .unknown(let reason): "不明（\(reason.rawValue)）"
        }
    }

    private func sideText(_ side: DoorSide) -> String {
        switch side {
        case .left: "左"
        case .right: "右"
        case .both: "両側"
        case .noDoorSide: "対象なし"
        }
    }

    private func roleText(_ role: ScoringRole) -> String {
        switch role {
        case .driver: "運転士（架空ラベル）"
        case .conductor: "車掌（架空ラベル）"
        case .stationStaff: "駅員（架空ラベル）"
        }
    }

    private func stepText(_ result: ProcedureStepResult) -> String {
        switch result {
        case .pending: "未確定"
        case .completed: "記録済み"
        case .notPerformed: "未実施"
        case .wrongRole: "担当ラベル不一致"
        case .notCompleted(let outcome): "未完了: \(outcome.rawValue)"
        }
    }
}
