import CrewWorkflow
import IncidentMaintenance
import SwiftUI

struct ScenarioProgressSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var model: SimulatorModel

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    disclaimerCard
                    crewWorkflowCard
                    incidentCard
                    depotCard
                }
                .padding(14)
            }
            .background(Color(red: 0.035, green: 0.055, blue: 0.075))
            .navigationTitle("架空ゲーム進行")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("閉じる") { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private var disclaimerCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("架空ゲーム専用", systemImage: "exclamationmark.triangle.fill")
                .font(.system(size: 12, weight: .black, design: .rounded))
                .foregroundStyle(.orange)
            Text(CrewWorkflowContent.disclaimer)
                .font(.system(size: 10, weight: .heavy, design: .rounded))
                .foregroundStyle(.orange)
            Text(incidentMaintenanceFictionDisclaimer)
                .font(.system(size: 10, weight: .heavy, design: .rounded))
                .foregroundStyle(.orange)
            Text("表示・入力・評価・故障・復旧・基地状態はすべてゲーム内の架空データです。現実の鉄道業務、点検、保守、運転、安全訓練には使用できません。")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.78))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.11), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.orange.opacity(0.35), lineWidth: 1))
    }

    private var crewWorkflowCard: some View {
        VStack(alignment: .leading, spacing: 9) {
            heading("乗務ワークフロー", subtitle: "20段階の架空ゲーム進行 · 保存・再開対応")
            Text("進行: \(model.crewWorkflow.events.count) / \(CrewWorkflowPhase.allCases.count)")
                .font(.system(size: 11, weight: .bold, design: .rounded).monospacedDigit())
                .foregroundStyle(.cyan)
            if let phase = model.crewWorkflow.currentPhase {
                Text("現在のゲーム段階: \(phase.displayName)")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                Text(CrewWorkflowContent.prompt(for: phase))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.75))
                    .fixedSize(horizontal: false, vertical: true)
                Button {
                    model.completeCrewWorkflowPhase()
                } label: {
                    Label("この架空ゲーム段階を完了", systemImage: "checkmark.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.cyan)
            } else {
                Text("20段階の架空ゲーム進行が完了しました。")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.green)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 12))
    }

    private var incidentCard: some View {
        VStack(alignment: .leading, spacing: 9) {
            heading("故障・イベントゲーム", subtitle: "シミュレーション固定tickに同期 · 状態と乱数を保存")
            Text("ゲームtick: \(model.incidentTick.value) · 発生中: \(model.activeIncidentEvents.count)件")
                .font(.system(size: 10, weight: .bold, design: .rounded).monospacedDigit())
                .foregroundStyle(.cyan)
            if model.activeIncidentEvents.isEmpty {
                Text("発生中の架空イベントはありません。")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.62))
            } else {
                ForEach(model.activeIncidentEvents) { event in
                    VStack(alignment: .leading, spacing: 7) {
                        Text("\(event.kind.rawValue) · \(event.id.rawValue)")
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundStyle(.yellow)
                        Text(event.fictionalResponsePrompt)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.white.opacity(0.78))
                            .fixedSize(horizontal: false, vertical: true)
                        Text("ゲーム効果: 牽引 \(event.effects.tractionMultiplier, specifier: "%.2f")× · 速度 \(event.effects.speedMultiplier, specifier: "%.2f")×")
                            .font(.system(size: 9, weight: .medium, design: .rounded).monospacedDigit())
                            .foregroundStyle(.white.opacity(0.62))
                        Text(event.fictionalRecoveryPrompt)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.white.opacity(0.78))
                            .fixedSize(horizontal: false, vertical: true)
                        let elapsed = model.incidentTick.value - event.startedAt.value
                        let minimum = model.incidentMinimumTicks(for: event)
                        if model.incidentRecoveryActionID(for: event) != nil && elapsed >= UInt64(minimum) {
                            Button("架空ゲームイベントを復旧済みにする") {
                                model.queueFictionalIncidentRecovery(for: event)
                            }
                            .buttonStyle(.bordered)
                            .tint(.green)
                        } else if elapsed < UInt64(minimum) {
                            Text("ゲーム内の復旧選択は最低継続tick後に可能です。")
                                .font(.system(size: 9, weight: .medium))
                                .foregroundStyle(.orange)
                        }
                    }
                    .padding(10)
                    .background(Color.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 10))
                }
            }
            Button {
                model.queueFictionalIncident()
            } label: {
                Label(model.isPaused ? "運転再開後に架空イベントを予約" : "架空イベントを予約", systemImage: "bolt.trianglebadge.exclamationmark.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .tint(.orange)
            if let notice = model.incidentNotice {
                Text(notice)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 12))
    }

    private var depotCard: some View {
        VStack(alignment: .leading, spacing: 9) {
            heading("架空基地ゲーム", subtitle: "ゲーム状態遷移のみ · 履歴はセーブに含まれます")
            if let record = model.incidentDepotRecord {
                Text("車両: \(record.vehicleID.rawValue) · 基地: \(record.depotID.rawValue)")
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.65))
                Text("現在状態: \(depotStateName(record.state))")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(.cyan)
                Text("履歴: \(record.history.count)件 · tick \(record.lastTransitionAt?.value ?? 0)")
                    .font(.system(size: 9, weight: .medium, design: .rounded).monospacedDigit())
                    .foregroundStyle(.white.opacity(0.55))
                depotActions(for: record.state)
            } else {
                Text("架空基地データを準備できません。")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.orange)
            }
            Text("この基地状態はゲーム内の架空記録であり、実車の点検・整備・入出庫許可を示しません。")
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.white.opacity(0.55))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    private func depotActions(for state: DepotVehicleState) -> some View {
        switch state {
        case .stabled:
            actionButton("ゲーム上の確認工程を開始") { model.applyFictionalDepotAction(.beginInspection) }
        case .inspectionInProgress:
            actionButton("架空判定: ゲーム上で完了") { model.applyFictionalDepotAction(.completeInspection(.passed)) }
            actionButton("架空判定: 保守ゲームへ") { model.applyFictionalDepotAction(.completeInspection(.needsMaintenance)) }
        case .needsMaintenance:
            actionButton("ゲーム上の整備工程を開始") { model.applyFictionalDepotAction(.beginMaintenance) }
        case .maintenanceInProgress:
            actionButton("ゲーム上の整備工程を完了") { model.applyFictionalDepotAction(.completeMaintenance) }
        case .reinspectionRequired:
            actionButton("ゲーム上の再確認工程を開始") { model.applyFictionalDepotAction(.beginReinspection) }
        case .reinspectionInProgress:
            actionButton("架空判定: ゲーム上で完了") { model.applyFictionalDepotAction(.completeReinspection(.passed)) }
            actionButton("架空判定: 追加の保守ゲームへ") { model.applyFictionalDepotAction(.completeReinspection(.needsMaintenance)) }
        case .ready:
            actionButton("架空ゲーム内で出庫状態へ") { model.applyFictionalDepotAction(.dispatch) }
        case .dispatchable:
            Text("ゲーム内状態: dispatchable")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.green)
        }
    }

    private func actionButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.bordered)
        .tint(.cyan)
    }

    private func heading(_ title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 13, weight: .black, design: .rounded))
                .foregroundStyle(.white)
            Text(subtitle)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.white.opacity(0.52))
        }
    }

    private func depotStateName(_ state: DepotVehicleState) -> String {
        switch state {
        case .stabled: "ゲーム待機"
        case .inspectionInProgress: "ゲーム確認中"
        case .needsMaintenance: "保守ゲーム待ち"
        case .ready: "ゲーム上完了"
        case .maintenanceInProgress: "保守ゲーム中"
        case .reinspectionRequired: "再確認ゲーム待ち"
        case .reinspectionInProgress: "再確認ゲーム中"
        case .dispatchable: "ゲーム上の出庫状態"
        }
    }
}
