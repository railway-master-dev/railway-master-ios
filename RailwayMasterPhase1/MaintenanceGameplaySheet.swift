import RailwayMaintenance
import SwiftUI

struct MaintenanceGameplaySheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var coordinator: MaintenanceGameplayCoordinator
    @State private var selectedVehicleID = ""
    @State private var selectedDepotID = ""
    @State private var serviceID = "GAME-SERVICE-01"

    private let scenarioKinds: [MaintenanceEventKind] = [
        .vehicleTractionFault, .vehicleBrakeFault, .vehicleDoorFault,
        .precedingTrainDelay, .heavyRainScenario, .strongWindScenario,
        .heavySnowScenario, .trackObstruction, .levelCrossingObstruction,
        .signalFailure, .earthquakeScenario
    ]

    init(coordinator: MaintenanceGameplayCoordinator) {
        self.coordinator = coordinator
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                safetyNotice
                    .padding(.horizontal, 14)
                    .padding(.top, 10)
                    .padding(.bottom, 4)
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        scenarioCard
                        activeEventsCard
                        depotCard
                        if let message = coordinator.message {
                            messageCard(message)
                        }
                        previewTickCard
                    }
                    .padding(14)
                }
            }
            .background(Color(red: 0.035, green: 0.055, blue: 0.075))
            .navigationTitle("保守・運行イベント")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("閉じる") { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            if selectedVehicleID.isEmpty { selectedVehicleID = coordinator.depotState.vehicles.first?.id ?? "" }
            if selectedDepotID.isEmpty { selectedDepotID = coordinator.depotState.depots.first?.id ?? "" }
        }
    }

    private var safetyNotice: some View {
        Label {
            Text("ゲーム専用の架空シミュレーションです。表示される故障・復旧・点検・整備・基地操作は実車の取扱手順、保安指示、点検方法ではありません。現実の運行・作業には使用しないでください。")
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: "exclamationmark.triangle.fill")
        }
        .font(.system(size: 11, weight: .bold, design: .rounded))
        .foregroundStyle(.orange)
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.orange.opacity(0.35), lineWidth: 1))
        .accessibilityAddTraits(.isHeader)
    }

    private var scenarioCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            heading("シナリオイベント", subtitle: "固定シナリオを選んでゲーム内に注入")
            Text("現在の架空ルート: \(coordinator.currentSnapshot.routeID) · tick \(coordinator.currentSnapshot.fixedTick) · \(Int(coordinator.currentSnapshot.simulationTimeSeconds))秒")
                .font(.system(size: 10, weight: .medium, design: .rounded).monospacedDigit())
                .foregroundStyle(.white.opacity(0.58))
                .lineLimit(2)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 7) {
                ForEach(scenarioKinds, id: \.self) { kind in
                    Button {
                        start(kind)
                    } label: {
                        Label(scenarioTitle(kind), systemImage: scenarioSymbol(kind))
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .frame(maxWidth: .infinity, minHeight: 34)
                    }
                    .buttonStyle(.bordered)
                    .tint(.cyan)
                    .disabled(scope(for: kind) == nil)
                }
            }
            Text("固定シナリオは乱数条件を通さず開始します。速度・遅延などの影響はホストの同一tickスナップショットに対するゲーム効果です。")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.white.opacity(0.58))
                .fixedSize(horizontal: false, vertical: true)
        }
        .cardStyle()
    }

    private var activeEventsCard: some View {
        VStack(alignment: .leading, spacing: 9) {
            heading("発生中イベント", subtitle: "対応選択は次の固定tickで記録。時間・天候条件も反映")
            if coordinator.activeEvents.isEmpty {
                Text("現在、発生中のイベントはありません。")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.58))
            } else {
                ForEach(coordinator.activeEvents) { event in
                    VStack(alignment: .leading, spacing: 7) {
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: scenarioSymbol(event.kind))
                                .foregroundStyle(event.kind.family == .disaster ? .orange : .yellow)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(scenarioTitle(event.kind))
                                    .font(.system(size: 12, weight: .bold, design: .rounded))
                                    .foregroundStyle(.white)
                                Text("ID \(event.id) · \(scopeTitle(event.scope))")
                                    .font(.system(size: 9, weight: .medium, design: .rounded).monospacedDigit())
                                    .foregroundStyle(.white.opacity(0.55))
                            }
                            Spacer(minLength: 2)
                            Text(event.isFixedScenario ? "固定" : "自動")
                                .font(.system(size: 9, weight: .bold, design: .rounded))
                                .foregroundStyle(.cyan)
                        }
                        if let actionID = requiredAction(in: event.recoveryRule) {
                            Button {
                                coordinator.chooseRecoveryAction(eventInstanceID: event.id, actionID: actionID)
                            } label: {
                                Label("\(actionTitle(actionID))を選択", systemImage: "checkmark.circle")
                                    .font(.system(size: 10, weight: .bold, design: .rounded))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .buttonStyle(.bordered)
                            .tint(.green)
                            .disabled(!depotRepairReady(for: event))
                            if !depotRepairReady(for: event) {
                                Text("車両故障は、対応する基地ゲーム内整備で故障状態を解消してから復旧対応を選べます。")
                                    .font(.system(size: 9, weight: .medium))
                                    .foregroundStyle(.orange.opacity(0.88))
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        } else {
                            Text("プレイヤー操作不要 · 継続時間または天候条件で自動復旧")
                                .font(.system(size: 9, weight: .medium))
                                .foregroundStyle(.white.opacity(0.58))
                        }
                        Text("影響: \(impactSummary(event.impact))")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(.white.opacity(0.65))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(10)
                    .background(Color.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 10))
                }
            }
            Text("車両状態: \(coordinator.depotState.vehicles.count)件 · 基地ゲームイベント: \(coordinator.latestDepotEvents.count)件")
                .font(.system(size: 9, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.48))
        }
        .cardStyle()
    }

    private var depotCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            heading("架空基地・車両", subtitle: "入出庫、点検、ゲーム内整備、運用割当")
            if coordinator.depotState.vehicles.isEmpty || coordinator.depotState.depots.isEmpty {
                Text("ホストから架空基地と車両レコードを渡すと操作できます。")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.6))
            } else {
                Picker("車両", selection: $selectedVehicleID) {
                    ForEach(coordinator.depotState.vehicles) { vehicle in
                        Text("\(vehicle.id) · \(vehicle.operationalState.rawValue)").tag(vehicle.id)
                    }
                }
                .pickerStyle(.menu)
                .tint(.cyan)
                Picker("基地", selection: $selectedDepotID) {
                    ForEach(coordinator.depotState.depots) { depot in
                        Text(depot.id).tag(depot.id)
                    }
                }
                .pickerStyle(.menu)
                .tint(.cyan)

                if let vehicle = selectedVehicle {
                    vehicleStatus(vehicle)
                    depotActions(vehicle)
                }
                Divider().overlay(Color.white.opacity(0.12))
                TextField("架空運用ID", text: $serviceID)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .textFieldStyle(.roundedBorder)
                    .textInputAutocapitalization(.never)
                Text("運用ID・基地名・車両形式・所要時間はすべてゲーム用の架空値です。入庫条件はホストスナップショット上の車両位置と停止状態で検査されます。")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.white.opacity(0.52))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .cardStyle()
    }

    private func vehicleStatus(_ vehicle: MaintenanceVehicleRecord) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Label(vehicle.operationalState.rawValue, systemImage: "tram.fill")
                Spacer()
                Text(vehicle.inspectionClearance.rawValue)
            }
            .font(.system(size: 10, weight: .bold, design: .rounded))
            .foregroundStyle(vehicle.activeScenarioFaultEventIDs.isEmpty ? .cyan : .orange)
            Text("形式 \(vehicle.profileID) · 故障リンク \(vehicle.activeScenarioFaultEventIDs.count)件 · 割当 \(vehicle.assignedServiceID ?? "なし")")
                .font(.system(size: 9, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.57))
            Text(locationTitle(vehicle.location))
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.white.opacity(0.57))
        }
        .padding(9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.cyan.opacity(0.07), in: RoundedRectangle(cornerRadius: 9))
    }

    @ViewBuilder
    private func depotActions(_ vehicle: MaintenanceVehicleRecord) -> some View {
        switch vehicle.location {
        case .onRoute:
            if let depot = selectedDepot,
               let track = depot.tracks.first {
                actionButton("架空基地へ入庫を要求（\(track.id)）", symbol: "arrow.down.to.line", tint: .cyan) {
                    coordinator.performDepotCommand(.requestEntry(vehicleID: vehicle.id, depotID: depot.id, depotTrackID: track.id))
                }
            }
        case .inTransit:
            Text("架空の基地移動中です。固定tickを進めると状態が更新されます。")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.cyan)
        case .inDepot:
            depotResidentActions(vehicle)
        }
    }

    @ViewBuilder
    private func depotResidentActions(_ vehicle: MaintenanceVehicleRecord) -> some View {
        let pendingInspection = coordinator.depotState.inspections.first {
            $0.vehicleID == vehicle.id && $0.status == .awaitingResult
        }
        let activeInspection = coordinator.depotState.inspections.first {
            $0.vehicleID == vehicle.id && $0.status == .inProgress
        }
        let openTask = coordinator.depotState.maintenanceTasks.first {
            $0.vehicleID == vehicle.id && ($0.status == .planned || $0.status == .inProgress)
        }

        if vehicle.operationalState == .allocated, let assigned = vehicle.assignedServiceID {
            VStack(alignment: .leading, spacing: 6) {
                actionButton("\(assigned) へ架空出庫", symbol: "arrow.up.to.line", tint: .green) {
                    coordinator.performDepotCommand(.requestExit(vehicleID: vehicle.id, serviceID: assigned))
                }
                actionButton("運用割当を解除", symbol: "xmark.circle", tint: .secondary) {
                    coordinator.performDepotCommand(.releaseAllocation(vehicleID: vehicle.id))
                }
            }
        } else if let pendingInspection {
            VStack(alignment: .leading, spacing: 6) {
                Text("架空点検レビュー待ち · \(pendingInspection.id)")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.orange)
                actionButton("ゲーム結果: 点検クリア", symbol: "checkmark.seal", tint: .green) {
                    coordinator.performDepotCommand(.submitInspectionResult(inspectionID: pendingInspection.id, result: .passed(findings: [])))
                }
                actionButton("ゲーム結果: 再整備が必要", symbol: "wrench.adjustable", tint: .orange) {
                    let finding = InspectionFinding(id: "fictional-finding", category: .minorGameplayFault, scenarioNote: "架空シナリオ上のゲーム結果")
                    coordinator.performDepotCommand(.submitInspectionResult(inspectionID: pendingInspection.id, result: .repairRequired(findings: [finding])))
                }
            }
        } else if let activeInspection {
            Text("架空点検中 · \(activeInspection.id) · tickで進行")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.cyan)
        } else if let openTask, openTask.status == .planned {
            VStack(alignment: .leading, spacing: 6) {
                Text("整備タスク待機 · \(openTask.id) · \(openTask.kind.rawValue)")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.orange)
                actionButton("架空整備タスクを開始", symbol: "play.fill", tint: .orange) {
                    coordinator.performDepotCommand(.beginMaintenance(taskID: openTask.id))
                }
            }
        } else if let openTask {
            Text("架空整備中 · \(openTask.id) · tickで進行")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.orange)
        } else {
            HStack(spacing: 7) {
                actionButton("ゲーム点検を開始", symbol: "checkmark.shield", tint: .cyan) {
                    let kind: InspectionKind = vehicle.activeScenarioFaultEventIDs.isEmpty ? .scheduledGameCheck : .faultFollowUpScenario
                    coordinator.performDepotCommand(.beginInspection(vehicleID: vehicle.id, kind: kind, durationSeconds: 3))
                }
                actionButton(vehicle.activeScenarioFaultEventIDs.isEmpty ? "通常整備を登録" : "シナリオ修理を登録", symbol: "wrench", tint: .orange) {
                    let kind: GameplayMaintenanceTaskKind = vehicle.activeScenarioFaultEventIDs.isEmpty ? .scheduledGameplayService : .correctiveScenarioRepair
                    coordinator.performDepotCommand(.scheduleMaintenance(vehicleID: vehicle.id, kind: kind, durationSeconds: 5, requiresReinspection: true))
                }
            }
            HStack(spacing: 7) {
                actionButton("架空運用に割当", symbol: "calendar.badge.checkmark", tint: .green) {
                    coordinator.performDepotCommand(.allocate(vehicleID: vehicle.id, serviceID: serviceID))
                }
                .disabled(serviceID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }

    private var previewTickCard: some View {
        VStack(alignment: .leading, spacing: 7) {
            heading("固定tick", subtitle: "画面更新とは独立したシミュレーション刻み")
            HStack {
                Text("最終結果: \(coordinator.latestTickResult.map { "tick \($0.eventResult.fixedTick)" } ?? "未処理")")
                    .font(.system(size: 10, weight: .medium, design: .rounded).monospacedDigit())
                    .foregroundStyle(.white.opacity(0.65))
                Spacer()
                Button {
                    coordinator.advanceFictionalPreviewOneTick()
                } label: {
                    Label("プレビューを1 tick進める", systemImage: "forward.frame.fill")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                }
                .buttonStyle(.borderedProminent)
                .tint(.cyan)
            }
            Text("このボタンは独立した架空プレビュー用です。本番統合ではホストの固定物理tickから advanceFixedTick(with:) を1回呼びます。")
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.white.opacity(0.52))
                .fixedSize(horizontal: false, vertical: true)
        }
        .cardStyle()
    }

    private func messageCard(_ message: String) -> some View {
        Text(message)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.cyan)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(Color.cyan.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
    }

    private func heading(_ title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.system(size: 13, weight: .bold, design: .rounded)).foregroundStyle(.white)
            Text(subtitle).font(.system(size: 9, weight: .medium)).foregroundStyle(.white.opacity(0.52))
        }
    }

    private func actionButton(_ title: String, symbol: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .frame(maxWidth: .infinity, minHeight: 30)
        }
        .buttonStyle(.bordered)
        .tint(tint)
    }

    private var selectedVehicle: MaintenanceVehicleRecord? {
        coordinator.depotState.vehicles.first { $0.id == selectedVehicleID }
    }

    private var selectedDepot: DepotDefinition? {
        coordinator.depotState.depots.first { $0.id == selectedDepotID }
    }

    private func start(_ kind: MaintenanceEventKind) {
        guard let scope = scope(for: kind) else { return }
        coordinator.startScenario(kind: kind, scope: scope)
    }

    private func scope(for kind: MaintenanceEventKind) -> MaintenanceEventScope? {
        let snapshot = coordinator.currentSnapshot
        switch kind {
        case .vehicleTractionFault, .vehicleBrakeFault, .vehicleDoorFault:
            guard let train = snapshot.trains.first(where: { $0.isInService }) else { return nil }
            return .train(trainID: train.trainID)
        case .levelCrossingObstruction:
            guard let crossing = snapshot.crossings.first else { return nil }
            return .crossing(crossingID: crossing.crossingID, trackID: crossing.trackID, chainageM: crossing.chainageM)
        case .trackObstruction:
            guard let trackID = snapshot.trackIDs.first else { return nil }
            return .track(trackID: trackID, startChainageM: 0, endChainageM: snapshot.routeLengthM)
        default:
            return .route(routeID: snapshot.routeID)
        }
    }

    private func requiredAction(in rule: MaintenanceRecoveryRule) -> String? {
        switch rule {
        case .actionRequired(let actionID): return actionID
        case .all(let rules), .any(let rules): return rules.compactMap(requiredAction(in:)).first
        case .eventDurationElapsed, .elapsedAtLeast, .weatherMetricAtMost: return nil
        }
    }

    private func depotRepairReady(for event: MaintenanceEventInstance) -> Bool {
        guard event.domain == .rollingStock,
              case .train(let vehicleID) = event.scope,
              let vehicle = coordinator.depotState.vehicles.first(where: { $0.id == vehicleID }) else { return true }
        return !vehicle.activeScenarioFaultEventIDs.contains(event.id) && vehicle.inspectionClearance == .cleared
    }

    private func scopeTitle(_ scope: MaintenanceEventScope) -> String {
        switch scope {
        case .train(let id): "車両 \(id)"
        case .station(let id): "駅 \(id)"
        case .track(let id, let start, let end): "線路 \(id) · \(Int(start))–\(Int(end))m"
        case .crossing(let id, _, let chainage): "踏切 \(id) · \(Int(chainage))m"
        case .route(let id): "路線 \(id)"
        case .network: "ネットワーク"
        }
    }

    private func locationTitle(_ location: DepotVehicleLocation) -> String {
        switch location {
        case .onRoute(let trackID, let chainage): "路線上 · \(trackID) · \(Int(chainage))m"
        case .inDepot(let depotID, let trackID): "基地内 · \(depotID) / \(trackID)"
        case .inTransit(let movementID): "基地移動中 · \(movementID)"
        }
    }

    private func impactSummary(_ impact: MaintenanceEventImpact) -> String {
        var parts: [String] = []
        if impact.tractionMultiplier != 1 { parts.append("牽引×\(impact.tractionMultiplier.formatted(.number.precision(.fractionLength(0...2))))") }
        if impact.brakingMultiplier != 1 { parts.append("制動×\(impact.brakingMultiplier.formatted(.number.precision(.fractionLength(0...2))))") }
        if impact.maximumSpeedMultiplier != 1 { parts.append("ゲーム速度係数×\(impact.maximumSpeedMultiplier.formatted(.number.precision(.fractionLength(0...2))))") }
        if let cap = impact.speedCapKmh { parts.append("ゲーム上限 \(Int(cap))km/h") }
        if impact.additionalDwellSeconds > 0 { parts.append("追加停車 \(Int(impact.additionalDwellSeconds))秒") }
        if impact.holdsDeparture { parts.append("出発保留フラグ") }
        return parts.isEmpty ? "表示・シナリオ状態のみ" : parts.joined(separator: " · ")
    }

    private func actionTitle(_ actionID: String) -> String {
        switch actionID {
        case "gameplay_recovery": "ゲーム内修復対応"
        case "complete_scenario_recovery": "シナリオ復旧対応"
        case "clear_scenario_obstruction": "架空障害物クリア対応"
        case "complete_incident_scenario": "イベント対応完了"
        case "power_scenario_recovered": "架空電力シナリオ復旧"
        case "earthquake_scenario_cleared": "地震シナリオ完了"
        case "lightning_scenario_cleared": "落雷シナリオ完了"
        default: actionID
        }
    }

    private func scenarioTitle(_ kind: MaintenanceEventKind) -> String {
        switch kind {
        case .vehicleTractionFault: "車両・牽引故障"
        case .vehicleBrakeFault: "車両・ブレーキ故障"
        case .vehicleDoorFault: "車両・ドア故障"
        case .stationPlatformSystemFault: "駅設備異常"
        case .passengerMedicalIncident: "旅客イベント"
        case .onboardDisruption: "車内イベント"
        case .levelCrossingObstruction: "踏切障害物"
        case .trackObstruction: "線路障害物"
        case .signalFailure: "信号イベント"
        case .tractionPowerInterruption: "電力イベント"
        case .precedingTrainDelay: "先行列車遅延"
        case .heavyRainScenario: "豪雨シナリオ"
        case .strongWindScenario: "強風シナリオ"
        case .heavySnowScenario: "大雪シナリオ"
        case .earthquakeScenario: "地震シナリオ"
        case .lightningScenario: "落雷シナリオ"
        }
    }

    private func scenarioSymbol(_ kind: MaintenanceEventKind) -> String {
        switch kind {
        case .vehicleTractionFault, .vehicleBrakeFault, .vehicleDoorFault: "tram.fill.tunnel"
        case .precedingTrainDelay: "clock.badge.exclamationmark"
        case .heavyRainScenario, .heavySnowScenario: "cloud.rain.fill"
        case .strongWindScenario: "wind"
        case .trackObstruction, .levelCrossingObstruction: "exclamationmark.triangle.fill"
        case .signalFailure: "trafficlight.fill"
        case .earthquakeScenario: "waveform.path.ecg"
        case .stationPlatformSystemFault: "building.2.crop.circle"
        case .passengerMedicalIncident: "cross.case.fill"
        case .onboardDisruption: "person.fill.questionmark"
        case .tractionPowerInterruption: "bolt.fill"
        case .lightningScenario: "cloud.bolt.fill"
        }
    }
}

private extension View {
    func cardStyle() -> some View {
        self
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 13))
            .overlay(RoundedRectangle(cornerRadius: 13).stroke(Color.white.opacity(0.07), lineWidth: 1))
    }
}
