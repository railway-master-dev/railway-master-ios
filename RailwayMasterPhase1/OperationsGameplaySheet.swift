import RailwayOperations
import SwiftUI

/// Game-only controls for RailwayOperations. The host app supplies fixed-tick samples
/// to `coordinator.receiveFixedTick(_:)`; this view never reaches into SimulatorModel.
struct OperationsGameplaySheet: View {
    @ObservedObject var coordinator: OperationsGameplayCoordinator

    @State private var selectedSignal: GameSignalAspect = .proceed
    @State private var selectedCheckpointTrigger: GameCheckpointTrigger = .beforeDuty
    @State private var checkpointContextID = ""
    @State private var calloutText = ""
    @State private var selectedRuleKind: GameRuleKind = .signalCompliance
    @State private var ruleExplanation = ""

    private var host: OperationsGameplayHostSnapshot? { coordinator.latestHostSnapshot }

    var body: some View {
        VStack(spacing: 0) {
            disclaimer
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    runSummary
                    if let message = coordinator.lastErrorMessage {
                        errorBanner(message)
                    }
                    workflowSection
                    checkpointSection
                    gameRulesSection
                    disruptionSection
                    scoreSection
                }
                .padding()
            }
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle("運転ゲーム")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var disclaimer: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("架空のゲーム規則 — 実在する鉄道の運転手順ではありません")
                .font(.footnote.weight(.bold))
            Text("ゲーム専用であり、鉄道の安全訓練・資格訓練・実務判断の代替ではありません。")
                .font(.caption)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .foregroundStyle(.white)
        .background(Color.red.opacity(0.9))
        .accessibilityElement(children: .combine)
    }

    private var runSummary: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(coordinator.scenario.runID).font(.headline)
            Text("モード: \(modeTitle(coordinator.mode))  ・  路線: \(coordinator.scenario.routeID)")
                .font(.subheadline)
            if let host {
                Text("固定tick \(host.fixedTick)  ・  \(host.simulationTimeSeconds, specifier: "%.2f") 秒  ・  \(host.train.positionM, specifier: "%.1f") m  ・  \(host.train.speedMps, specifier: "%.2f") m/s")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            } else {
                Text("ホストから固定tick snapshotを受信するまで操作できません。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text("状態: \(phaseTitle(coordinator.workflow.phase))")
                .font(.subheadline.weight(.semibold))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.background, in: RoundedRectangle(cornerRadius: 12))
    }

    private var workflowSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("ゲーム進行・駅停車・ドア・発車")
            Text("画面の項目はすべてゲーム内プロンプトです。シミュレーションの物理状態はこのUIから変更しません。")
                .font(.caption)
                .foregroundStyle(.secondary)

            switch coordinator.workflow.phase {
            case .preDutyChecks:
                ForEach(PreDutyCheck.allCases, id: \.self) { check in
                    checkButton(title: preDutyTitle(check), isDone: coordinator.workflow.completedPreDutyChecks.contains(check)) {
                        submit(.completePreDutyCheck(check))
                    }
                }
            case .cabSetup:
                actionButton("ゲーム運転台を開始", systemImage: "power") { submit(.startCab) }
                    .disabled(coordinator.workflow.cabStarted || host == nil)
                ForEach(CabSetupCheck.allCases, id: \.self) { check in
                    checkButton(title: cabTitle(check), isDone: coordinator.workflow.completedCabChecks.contains(check)) {
                        submit(.completeCabCheck(check))
                    }
                    .disabled(!coordinator.workflow.cabStarted)
                }
            case .depotExit:
                actionButton("ゲーム出庫ステップを完了", systemImage: "arrow.up.right") { submit(.completeDepotExit) }
            case .departurePreparation, .stationStop:
                if coordinator.workflow.phase == .stationStop, !coordinator.workflow.doorsClosed {
                    actionButton("ゲーム内ドアを閉じる", systemImage: "door.left.hand.closed") { submit(.closeDoors) }
                }
                if coordinator.workflow.phase == .stationStop, coordinator.workflow.doorsClosed {
                    actionButton("ゲーム内ドアを開く", systemImage: "door.left.hand.open") { submit(.openDoors) }
                }
                ForEach(DepartureCheck.allCases, id: \.self) { check in
                    checkButton(
                        title: departureTitle(check),
                        isDone: coordinator.workflow.completedDepartureChecks.contains(check)
                    ) { submit(.completeDepartureCheck(check)) }
                    .disabled(check == .doorsClosedPrompt && !coordinator.workflow.doorsClosed ||
                              check == .gameSignalPrompt && coordinator.workflow.latestGameSignal != .proceed)
                }
                Picker("ゲーム内信号表示", selection: $selectedSignal) {
                    ForEach(GameSignalAspect.allCases, id: \.self) { aspect in
                        Text(signalTitle(aspect)).tag(aspect)
                    }
                }
                .pickerStyle(.segmented)
                actionButton("ゲーム内信号表示を記録", systemImage: "light.beacon.max") {
                    submit(.observeGameSignal(selectedSignal))
                }
                if coordinator.workflow.phase == .departurePreparation || coordinator.workflow.currentStopIndex < coordinator.scenario.stops.count - 1 {
                    actionButton("ゲーム発車を記録", systemImage: "tram.fill") { submit(.depart) }
                        .disabled(!canDepart)
                }
                if coordinator.workflow.phase == .stationStop,
                   coordinator.workflow.currentStopIndex == coordinator.scenario.stops.count - 1 {
                    actionButton("ゲーム運転を終了", systemImage: "flag.checkered") { submit(.finishRun) }
                        .disabled(!coordinator.workflow.doorsClosed)
                }
            case .enRoute:
                if let stop = coordinator.workflow.currentStop {
                    Text("次のゲーム停車地点: \(stop.stationName)（\(stop.id)）")
                        .font(.subheadline)
                    actionButton("現在位置でゲーム到着を記録", systemImage: "mappin.and.ellipse") {
                        guard let host else { return }
                        submit(.arrive(stationID: stop.id, positionM: host.train.positionM, speedMps: host.train.speedMps))
                    }
                    .disabled(host.map { $0.train.speedMps > OperationsWorkflow.stoppedSpeedThresholdMps } ?? true)
                }
            case .endOfRun:
                ForEach(PostRunCheck.allCases, id: \.self) { check in
                    checkButton(title: postRunTitle(check), isDone: coordinator.workflow.completedPostRunChecks.contains(check)) {
                        submit(.completePostRunCheck(check))
                    }
                }
                actionButton("ゲーム記録を閉じる", systemImage: "checkmark.seal") { submit(.closeOut) }
                    .disabled(!coordinator.workflow.completedPostRunChecks.isSuperset(of: OperationsWorkflow.requiredPostRunChecks))
            case .completed:
                Label("ゲームセッション完了", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            }
        }
        .padding()
        .background(.background, in: RoundedRectangle(cornerRadius: 12))
    }

    private var checkpointSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("喚呼チェックポイント（ゲーム内）")
            Picker("チェックポイント起動条件", selection: $selectedCheckpointTrigger) {
                ForEach(GameCheckpointTrigger.allCases, id: \.self) { trigger in
                    Text(triggerTitle(trigger)).tag(trigger)
                }
            }
            TextField("任意のゲーム文脈ID", text: $checkpointContextID)
                .textFieldStyle(.roundedBorder)
                .textInputAutocapitalization(.never)
            actionButton("選択したゲームチェックポイントを有効化", systemImage: "scope") {
                guard let host else { return }
                run { _ = try coordinator.activateCheckpoint(selectedCheckpointTrigger, contextID: checkpointContextID.isEmpty ? nil : checkpointContextID, using: host) }
            }
            .disabled(host == nil)

            if coordinator.pointingCalling.definitions.isEmpty {
                Text("チェックポイント定義はホスト側でCoordinator初期化時に渡してください。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ForEach(coordinator.pointingCalling.definitions) { definition in
                let status = coordinator.pointingCalling.statusByCheckpointID[definition.id] ?? .notDue
                VStack(alignment: .leading, spacing: 6) {
                    Text("\(definition.targetLabel)  ·  \(checkpointStatusTitle(status))")
                        .font(.subheadline.weight(.medium))
                    if status == .due {
                        TextField("ゲーム内コールを入力", text: $calloutText)
                            .textFieldStyle(.roundedBorder)
                        HStack {
                            actionButton("ゲーム判定", systemImage: "checkmark.bubble") {
                                guard let host else { return }
                                run { try coordinator.recordCallout(calloutText, for: definition.id, using: host) }
                            }
                            .disabled(host == nil || calloutText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            actionButton("未実施で記録", systemImage: "xmark.bubble") {
                                guard let host else { return }
                                run { try coordinator.markCheckpointMissed(definition.id, using: host) }
                            }
                            .disabled(host == nil)
                        }
                        Text("受理されるゲーム文言: \(definition.acceptedCallouts.joined(separator: " / "))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }
            if !coordinator.pointingCalling.records.isEmpty {
                Text("ゲーム記録: 正答 \(coordinator.pointingCalling.correctCount) / \(coordinator.pointingCalling.resolvedCount)")
                    .font(.caption.monospacedDigit())
            }
        }
        .padding()
        .background(.background, in: RoundedRectangle(cornerRadius: 12))
    }

    private var gameRulesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("架空の規則イベント記録")
            Picker("ゲーム規則カテゴリ", selection: $selectedRuleKind) {
                ForEach(GameRuleKind.allCases, id: \.self) { kind in
                    Text(ruleKindTitle(kind)).tag(kind)
                }
            }
            TextField("ゲームイベントの説明（任意）", text: $ruleExplanation)
                .textFieldStyle(.roundedBorder)
            HStack {
                actionButton("ゲーム判定: 達成", systemImage: "checkmark.circle") { recordRule(passed: true) }
                actionButton("ゲーム判定: 未達", systemImage: "xmark.circle") { recordRule(passed: false) }
            }
            .disabled(host == nil)
            Text("記録件数: \(coordinator.gameRuleOutcomes.count)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
        .background(.background, in: RoundedRectangle(cornerRadius: 12))
    }

    private var disruptionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("架空イベント（トラブル訓練モード専用）")
            if coordinator.mode != .disruptionTraining {
                Text("このモードでは架空イベントを有効化しません。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if coordinator.disruptionSession.definitions.isEmpty {
                Text("イベント定義はホスト側でCoordinator初期化時に渡してください。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(coordinator.disruptionSession.definitions) { event in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(event.description).font(.subheadline)
                        Text("\(event.id)  ·  \(disruptionStatusTitle(coordinator.disruptionSession.statusByEventID[event.id] ?? .scheduled))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if coordinator.disruptionSession.statusByEventID[event.id] == .active {
                            ForEach(event.availableChoices, id: \.self) { choice in
                                actionButton(disruptionChoiceTitle(choice), systemImage: "hand.tap") {
                                    guard let host else { return }
                                    run { try coordinator.respondToDisruption(eventID: event.id, choice: choice, using: host) }
                                }
                                .disabled(host == nil)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
                Text("イベントの選択肢は架空のゲーム状態のみを表し、実際の異常時対応を示しません。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(.background, in: RoundedRectangle(cornerRadius: 12))
    }

    private var scoreSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("ゲーム得点（4カテゴリ）")
            ForEach(coordinator.scorecard.categories) { category in
                HStack(alignment: .firstTextBaseline) {
                    Text(scoreCategoryTitle(category.category))
                    Spacer()
                    if let value = category.score {
                        Text("\(value, specifier: "%.0f") / 100")
                            .font(.headline.monospacedDigit())
                    } else {
                        Text("未評価").foregroundStyle(.secondary)
                    }
                }
                if !category.metrics.isEmpty {
                    Text(category.metrics.map { metric in
                        let value = metric.score.map { String(format: "%.0f", $0) } ?? "—"
                        return "\(metric.explanation): \(value)"
                    }.joined(separator: "\n"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                Divider()
            }
            HStack {
                Text("総合ゲーム得点")
                Spacer()
                Text(coordinator.scorecard.overallScore.map { String(format: "%.0f / 100", $0) } ?? "未評価")
                    .font(.headline.monospacedDigit())
            }
            Text("この採点は架空ゲーム内の評価であり、実務能力・安全性を評価するものではありません。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
        .background(.background, in: RoundedRectangle(cornerRadius: 12))
    }

    private var canDepart: Bool {
        guard coordinator.workflow.doorsClosed,
              coordinator.workflow.latestGameSignal == .proceed,
              coordinator.workflow.completedDepartureChecks.isSuperset(of: OperationsWorkflow.requiredDepartureChecks) else { return false }
        return host != nil
    }

    private func submit(_ command: OperationsWorkflowCommand) {
        guard let host else { return }
        run { try coordinator.apply(command, using: host) }
    }

    private func recordRule(passed: Bool) {
        guard let host else { return }
        run { try coordinator.recordGameRule(selectedRuleKind, passed: passed, explanation: ruleExplanation, using: host) }
    }

    private func run(_ action: () throws -> Void) {
        coordinator.clearError()
        do { try action() } catch { coordinator.present(error: error) }
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title).font(.headline)
    }

    private func actionButton(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.bordered)
    }

    private func checkButton(title: String, isDone: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: isDone ? "checkmark.circle.fill" : "circle")
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.bordered)
        .disabled(isDone || host == nil)
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(alignment: .top) {
            Text(message).font(.footnote)
            Spacer()
            Button("閉じる") { coordinator.clearError() }.font(.caption)
        }
        .padding(10)
        .foregroundStyle(.red)
        .background(Color.red.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
    }

    private func phaseTitle(_ phase: WorkflowPhase) -> String {
        switch phase {
        case .preDutyChecks: "ゲーム開始前"
        case .cabSetup: "ゲーム運転台セットアップ"
        case .depotExit: "ゲーム出庫"
        case .departurePreparation: "ゲーム発車準備"
        case .enRoute: "ゲーム運転中"
        case .stationStop: "ゲーム駅停車"
        case .endOfRun: "ゲーム終了処理"
        case .completed: "完了"
        }
    }

    private func modeTitle(_ mode: TrainingMode) -> String {
        switch mode {
        case .practice: "練習"
        case .standard: "標準"
        case .disruptionTraining: "トラブル訓練ゲーム"
        }
    }

    private func preDutyTitle(_ check: PreDutyCheck) -> String {
        switch check {
        case .gameBriefing: "架空ゲーム概要を確認"
        case .vehicleConditionPrompt: "架空車両状態プロンプト"
        case .routeAndTimetablePrompt: "架空路線・時刻表プロンプト"
        case .cabEquipmentPrompt: "架空運転台設備プロンプト"
        }
    }

    private func cabTitle(_ check: CabSetupCheck) -> String {
        switch check {
        case .controllerNeutralPrompt: "架空コントローラープロンプト"
        case .brakeGaugePrompt: "架空ブレーキ表示プロンプト"
        case .statusDisplayPrompt: "架空状態表示プロンプト"
        }
    }

    private func departureTitle(_ check: DepartureCheck) -> String {
        switch check {
        case .routeMarkerPrompt: "架空ルートマーカープロンプト"
        case .doorsClosedPrompt: "ゲーム内ドア状態プロンプト"
        case .gameSignalPrompt: "架空ゲーム信号プロンプト"
        }
    }

    private func postRunTitle(_ check: PostRunCheck) -> String {
        switch check {
        case .reviewRunLogPrompt: "架空ゲーム記録プロンプト"
        case .secureCabPrompt: "ゲーム運転台終了プロンプト"
        case .closeOutPrompt: "ゲーム終了プロンプト"
        }
    }

    private func signalTitle(_ aspect: GameSignalAspect) -> String {
        switch aspect {
        case .proceed: "ゲーム進行"
        case .caution: "ゲーム注意"
        case .stop: "ゲーム停止"
        }
    }

    private func triggerTitle(_ trigger: GameCheckpointTrigger) -> String {
        switch trigger {
        case .beforeDuty: "ゲーム開始前"
        case .cabSetup: "ゲーム運転台"
        case .depotExit: "ゲーム出庫"
        case .beforeDeparture: "ゲーム発車前"
        case .signalEncounter: "架空信号イベント"
        case .speedRestrictionEncounter: "架空速度イベント"
        case .stationApproach: "ゲーム駅接近"
        case .stopMarker: "ゲーム停車標"
        case .doorsClosed: "ゲーム内ドア状態"
        case .endOfRun: "ゲーム終了"
        case .disruptionPrompt: "架空イベント"
        }
    }

    private func checkpointStatusTitle(_ status: PointingCallingStatus) -> String {
        switch status {
        case .notDue: "未有効"
        case .due: "入力待ち"
        case .resolved: "記録済み"
        }
    }

    private func ruleKindTitle(_ kind: GameRuleKind) -> String {
        switch kind {
        case .signalCompliance: "架空信号ゲーム規則"
        case .speedLimitCompliance: "架空速度ゲーム規則"
        case .workflowSequence: "ゲーム手順順序"
        case .pointingCalling: "ゲーム内喚呼"
        case .disruptionResponse: "架空イベント選択"
        }
    }

    private func disruptionStatusTitle(_ status: DisruptionEventStatus) -> String {
        switch status {
        case .scheduled: "時刻待ち"
        case .active: "選択待ち"
        case .resolved: "記録済み"
        }
    }

    private func disruptionChoiceTitle(_ choice: DisruptionGameChoice) -> String {
        switch choice {
        case .acknowledgeGamePrompt: "ゲームプロンプトを確認"
        case .requestGameHint: "ゲームヒントを要求"
        case .holdGameSession: "ゲームセッションを保留"
        case .resumeAfterPromptClears: "ゲームプロンプト終了後に再開"
        }
    }

    private func scoreCategoryTitle(_ category: OperationsScoreCategory) -> String {
        switch category {
        case .schedule: "ダイヤ"
        case .stoppingAccuracy: "停車精度"
        case .smoothness: "滑らかさ"
        case .ruleBasedSkills: "ゲーム規則スキル"
        }
    }
}
