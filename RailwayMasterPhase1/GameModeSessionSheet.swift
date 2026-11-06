import RailwayGameModes
import SwiftUI

/// Native SwiftUI surface for selecting and running one fictional game mode.
/// The bound session is owned by the host; emitted host effects are requests only and are never
/// applied to simulator physics, controls, doors, environment, or routing inside this view.
struct GameModeSessionSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding private var session: GameModeSession?
    @State private var selectedMode: GameModeID = .driver
    @State private var selectedPlayStyle: GameModePlayStyle = .standard
    @State private var freeGoal = ""
    @State private var freeRequestID = ""
    @State private var passengerLoadFactor = 0.7
    @State private var lastMessage: String?

    let context: RegionalGameModeContext
    let snapshot: GameModeSimulationSnapshot
    let hostNotice: String?
    let onHostEffects: (GameModeID, [GameModeHostEffect]) -> Void
    let onSessionLifecycleChange: (GameModeSession?) -> Void
    let onAcceptedAction: (GameModeAction) -> Void

    private let playStyles: [GameModePlayStyle] = [.practice, .standard, .disruptionTraining, .freeRun]

    init(
        session: Binding<GameModeSession?>,
        context: RegionalGameModeContext,
        snapshot: GameModeSimulationSnapshot,
        hostNotice: String? = nil,
        onHostEffects: @escaping (GameModeID, [GameModeHostEffect]) -> Void = { _, _ in },
        onSessionLifecycleChange: @escaping (GameModeSession?) -> Void = { _ in },
        onAcceptedAction: @escaping (GameModeAction) -> Void = { _ in }
    ) {
        _session = session
        let existingSession = session.wrappedValue
        _selectedMode = State(initialValue: existingSession?.mode ?? .driver)
        _selectedPlayStyle = State(initialValue: existingSession?.playStyle ?? .standard)
        self.context = context
        self.snapshot = snapshot
        self.hostNotice = hostNotice
        self.onHostEffects = onHostEffects
        self.onSessionLifecycleChange = onSessionLifecycleChange
        self.onAcceptedAction = onAcceptedAction
    }

    private var buildResult: RegionalGameModeScenarioBuildResult {
        RegionalGameModeAdapter.build(
            mode: selectedMode,
            playStyle: selectedPlayStyle,
            context: context,
            snapshot: snapshot
        )
    }

    private var selectedDefinition: GameModeDefinition {
        GameModeCatalog.definition(for: selectedMode)
    }

    private var sessionMatchesSelection: Bool {
        session?.mode == selectedMode && session?.playStyle == selectedPlayStyle
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Label {
                        Text("架空ゲーム専用。PLACEHOLDERの路線・駅・時刻・イベントを使います。実在の鉄道運転、運行整理、安全判断、資格訓練には使用できません。")
                            .font(.subheadline.weight(.semibold))
                    } icon: {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                    }
                    Text("ゲーム内要求はホストへの明示的なコールバックに渡すだけです。この画面はシミュレーター値や物理を直接変更しません。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } header: {
                    Text("重要な注意")
                }

                Section("ゲームモード") {
                    Picker("モード", selection: $selectedMode) {
                        ForEach(GameModeID.allCases) { mode in
                            Text(GameModeCatalog.definition(for: mode).title).tag(mode)
                        }
                    }
                    .disabled(session.map { !$0.status.isTerminal } ?? false)
                    Text(selectedDefinition.objective)
                        .font(.subheadline)
                    Text(selectedDefinition.dataLabel.rawValue)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.orange)
                }

                Section("プレイスタイル") {
                    Picker("スタイル", selection: $selectedPlayStyle) {
                        ForEach(playStyles, id: \.self) { style in
                            Text(styleTitle(style)).tag(style)
                        }
                    }
                    .pickerStyle(.segmented)
                    Text(styleDescription(selectedPlayStyle))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if selectedPlayStyle == .freeRun && selectedMode != .free {
                        Text("フリー走行スタイルはフリーモード専用です。")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.orange)
                    } else if selectedPlayStyle == .disruptionTraining && selectedMode != .disruption {
                        Text("異常対応訓練スタイルは異常対応モード専用です。")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.orange)
                    }
                }

                Section("選択状態") {
                    statusLabel
                    Text("路線: \(context.routeID) · \(context.route.distanceM.formatted()) m")
                        .font(.caption.monospaced())
                    if let existing = session, !existing.status.isTerminal, !sessionMatchesSelection {
                        Text("実行中のセッションがあるため、別モードは終了または放棄後に選べます。")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                    ForEach(buildResult.blockingMessages, id: \.self) { message in
                        Label(message, systemImage: "hand.raised.fill")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                    if let reason = buildResult.blockingReason {
                        Text("ブロック理由: \(blockingReasonTitle(reason))")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.orange)
                    }
                    if session == nil || session?.status.isTerminal == true {
                        Button {
                            startOrShowBlockedSession()
                        } label: {
                            Label(buildResult.isPlayable ? "セッション開始" : "ブロック状態を確認", systemImage: buildResult.isPlayable ? "play.fill" : "info.circle")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(buildResult.scenario == nil || !sessionMatchesSelection && session.map { !$0.status.isTerminal } == true)
                    } else if sessionMatchesSelection && session?.status == .ready {
                        Button("セッション開始") { apply(.start) }
                            .buttonStyle(.borderedProminent)
                    }
                }

                if let current = session, sessionMatchesSelection {
                    Section("ライブセッション") {
                        Text("状態: \(statusTitle(current.status))")
                            .font(.headline)
                        if let failure = current.failureReason {
                            Text("失敗理由: \(failure.rawValue)")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.red)
                        }
                        Text("進捗: \(progressDescription(current.progress))")
                            .font(.subheadline)
                        if let hostNotice, !hostNotice.isEmpty {
                            Label(hostNotice, systemImage: "info.circle")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        if let evaluation = current.evaluation {
                            evaluationView(evaluation)
                        }
                        if let error = lastMessage {
                            Text(error).font(.caption).foregroundStyle(.orange)
                        }
                        if current.status == .active {
                            modeActions(for: current)
                            HStack {
                                Button("終了・評価") { apply(.finish) }
                                    .buttonStyle(.borderedProminent)
                                Button("放棄") { apply(.abandon) }
                                    .buttonStyle(.bordered)
                                    .tint(.red)
                            }
                        }
                        if current.status.isTerminal {
                            Button("別のモードを選ぶ") {
                                session = nil
                                lastMessage = nil
                                onSessionLifecycleChange(nil)
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                }
            }
            .navigationTitle("ゲームモード")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("閉じる") { dismiss() }
                }
            }
            .onChange(of: selectedMode) { _, newMode in
                guard session?.status.isTerminal != false else { return }
                if selectedPlayStyle == .freeRun && newMode != .free { selectedPlayStyle = .standard }
                if selectedPlayStyle == .disruptionTraining && newMode != .disruption { selectedPlayStyle = .standard }
                lastMessage = nil
            }
            .onChange(of: selectedPlayStyle) { _, style in
                if style == .freeRun && selectedMode != .free { selectedMode = .free }
                if style == .disruptionTraining && selectedMode != .disruption { selectedMode = .disruption }
            }
        }
        .preferredColorScheme(.dark)
        .presentationDetents([.medium, .large])
        .presentationBackgroundInteraction(.enabled(upThrough: .medium))
    }

    @ViewBuilder
    private var statusLabel: some View {
        if let current = session, sessionMatchesSelection {
            Label(statusTitle(current.status), systemImage: statusSymbol(current.status))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(statusColor(current.status))
        } else if buildResult.isPlayable {
            Label("開始可能 · 現在のホスト入力を確認済み", systemImage: "checkmark.circle.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.green)
        } else {
            Label("ブロック / 必須入力不足", systemImage: "hand.raised.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.orange)
        }
    }

    @ViewBuilder
    private func evaluationView(_ evaluation: GameModeEvaluation) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(outcomeTitle(evaluation.outcome), systemImage: outcomeSymbol(evaluation.outcome))
                .font(.subheadline.weight(.bold))
                .foregroundStyle(outcomeColor(evaluation.outcome))
            Text(evaluation.summary).font(.caption)
            if let score = evaluation.scorePercent {
                Text("ゲーム評価: \(score.formatted(.number.precision(.fractionLength(0))))%")
                    .font(.caption.weight(.semibold))
            } else if evaluation.outcome == .selfDirected {
                Text("合否・点数なし（自己設定プレイ）")
                    .font(.caption.weight(.semibold))
            }
            if let reason = evaluation.blockingReason {
                Text("ブロック理由: \(blockingReasonTitle(reason))")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.orange)
            }
            ForEach(evaluation.metrics.keys.sorted(), id: \.self) { key in
                if let value = evaluation.metrics[key] {
                    Text("\(metricTitle(key)): \(value.formatted(.number.precision(.fractionLength(0...2))))")
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func modeActions(for current: GameModeSession) -> some View {
        switch current.progress {
        case .driver(let state):
            let next = current.scenario.driverDutyStepIDs.dropFirst(state.completedDutyStepIDs.count).first
            if let next {
                if next == current.scenario.driverDepartureCheckStepID {
                    Button("PLACEHOLDER・出発確認を記録") { apply(.driverConfirmDeparture) }
                        .disabled(current.lastSnapshot.speedMps > 0.1 || current.lastSnapshot.doors != .closed)
                } else {
                    Button("次の乗務項目を記録: \(next)") { apply(.driverCompleteDutyStep(next)) }
                }
            }

        case .timetable(let state):
            ForEach(current.scenario.stops.filter { $0.positionM > 0.1 }) { stop in
                let delay = [state.arrivalDelayByStop[stop.id], state.departureDelayByStop[stop.id]]
                    .compactMap { $0 }.max(by: { abs($0) < abs($1) })
                if let delay, abs(delay) > stop.arrivalToleranceSeconds,
                   state.recoveryCreditCount > 0,
                   !state.recoveryUsedForStopIDs.contains(stop.id) {
                    Button("PLACEHOLDER・回復判断を記録: \(stop.id)") {
                        apply(.timetableUseRecoveryCredit(stationID: stop.id))
                    }
                }
            }

        case .free:
            freeModeActions

        case .conductor(let state):
            conductorActions(current: current, state: state)

        case .disruption(let state):
            Text("\(current.scenario.incident.displayText)")
                .font(.caption).foregroundStyle(.orange)
            Text("イベント状態: \(state.state.rawValue) · ヒント数: \(state.hintCount)")
                .font(.caption)
            if state.state == .active {
                ForEach(GameModeIncidentChoice.allCases, id: \.self) { choice in
                    Button(incidentChoiceTitle(choice)) { apply(.disruptionRespond(choice)) }
                }
            }

        case .training(let state):
            Text("教材ステップ \(state.completedStepIDs.count)/\(current.scenario.trainingSteps.count) · 誤り \(state.mistakes) · ヒント \(state.hintCount)")
                .font(.caption)
            if let next = current.scenario.trainingSteps.dropFirst(state.completedStepIDs.count).first {
                Text("次: \(next.title)").font(.subheadline)
                if next.requirement == .promptVisible {
                    Text("必要な架空プロンプト: \(next.requiredPromptID ?? "未設定")")
                        .font(.caption.monospaced()).foregroundStyle(.secondary)
                }
                Button("PLACEHOLDER・この教材ステップを確認") { apply(.trainingCompleteStep(next.id)) }
                Button("PLACEHOLDER・教習ヒントを要求") { apply(.trainingRequestHint) }
            }

        case .fullLine(let state):
            Text("通過駅 \(state.visitedStopIDs.count)/\(current.scenario.stops.filter { $0.positionM > 0.1 }.count) · \(state.routeProgressM.formatted()) / \(current.scenario.routeLengthM.formatted()) m")
                .font(.caption.monospaced())

        case .tourism(let state):
            Text("観察済み景観 \(state.observedLandmarkIDs.count) · 進捗 \(state.routeProgressM.formatted()) m")
                .font(.caption)
            ForEach(current.scenario.landmarks) { landmark in
                if current.lastSnapshot.visibleLandmarkID == landmark.id {
                    Button("PLACEHOLDER・景観を観察: \(landmark.displayName)") {
                        apply(.tourismObserve(landmark.id))
                    }
                }
            }
            if current.lastSnapshot.visibleLandmarkID == nil {
                Text("表示中の景観ポイントはホストから供給されていません。")
                    .font(.caption).foregroundStyle(.secondary)
            }

        case .companyOperations(let state):
            Text("割当 \(state.assignmentsByTaskID.count)/\(current.scenario.dispatchTasks.count) · 競合 \(state.conflictPairs.count) · 期限超過 \(state.overdueTaskIDs.count)")
                .font(.caption)
            ForEach(current.scenario.dispatchTasks) { task in
                if state.assignmentsByTaskID[task.id] == nil {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(task.id) → \(task.trainID)").font(.caption.weight(.semibold))
                        ForEach(task.allowedSlotIDs, id: \.self) { slotID in
                            Button("PLACEHOLDER・時間枠を割当: \(slotID)") {
                                apply(.companyAssign(taskID: task.id, slotID: slotID))
                            }
                        }
                    }
                }
            }
        }

        if (selectedPlayStyle == .practice || selectedPlayStyle == .disruptionTraining), current.mode != .training, current.mode != .disruption {
            Button("PLACEHOLDER・ゲームヒントを要求") { apply(.modeRequestHint) }
        }
    }

    private var freeModeActions: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("PLACEHOLDER・自己目標", text: $freeGoal)
                .textFieldStyle(.roundedBorder)
            Button("自己目標を保存") { apply(.freeSetGoal(freeGoal)) }
                .disabled(freeGoal.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            Button("PLACEHOLDER・通過地点を記録") {
                apply(.freeRecordWaypoint(freeRequestID))
            }
            .disabled(!freeRequestID.hasPrefix("PLACEHOLDER-") || freeRequestID.isEmpty)
            TextField("PLACEHOLDER-で始まる要求ID", text: $freeRequestID)
                .textFieldStyle(.roundedBorder)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            HStack {
                Button("車両要求") { apply(.freeRequestVehicle(freeRequestID)) }
                    .disabled(!freeRequestID.hasPrefix("PLACEHOLDER-") || freeRequestID.isEmpty)
                Button("天候要求") { apply(.freeRequestWeather(freeRequestID)) }
                    .disabled(!freeRequestID.hasPrefix("PLACEHOLDER-") || freeRequestID.isEmpty)
            }
            HStack {
                Button("時刻要求") { apply(.freeRequestTimeOfDay(freeRequestID)) }
                    .disabled(!freeRequestID.hasPrefix("PLACEHOLDER-") || freeRequestID.isEmpty)
                Button("季節要求") { apply(.freeRequestSeason(freeRequestID)) }
                    .disabled(!freeRequestID.hasPrefix("PLACEHOLDER-") || freeRequestID.isEmpty)
            }
            Button("路線要求") { apply(.freeRequestRoute(freeRequestID)) }
                .disabled(!freeRequestID.hasPrefix("PLACEHOLDER-") || freeRequestID.isEmpty)
            HStack {
                Slider(value: $passengerLoadFactor, in: 0...2, step: 0.1)
                Text(passengerLoadFactor.formatted(.number.precision(.fractionLength(1))))
                    .font(.caption.monospacedDigit())
            }
            Button("乗車率要求") { apply(.freeRequestPassengerLoad(passengerLoadFactor)) }
            Text("選択要求は親ホストへのコールバックに渡します。ホストが受理した値を後続スナップショットで返すまで適用済みと表示しません。")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func conductorActions(current: GameModeSession, state: ConductorModeProgress) -> some View {
        if let stationID = current.lastSnapshot.atStationID,
           let stop = current.scenario.stops.first(where: { $0.id == stationID }),
           current.lastSnapshot.speedMps <= 0.1 {
            Text("停車中: \(stop.id) · ホーム側: \(stop.expectedPlatformSide.rawValue) (PLACEHOLDER)")
                .font(.caption)
            if state.doors == .closed {
                Button("PLACEHOLDER・ゲーム内ドアを開く") {
                    apply(.conductorOpenDoors(stop.expectedPlatformSide))
                }
                .disabled(current.lastSnapshot.doors != .closed)
            } else if state.doors.isOpen {
                Button("PLACEHOLDER・ゲーム内ドアを閉じる") { apply(.conductorCloseDoors) }
                Button("閉扉確認を記録") { apply(.conductorConfirmDoorClosure) }
                    .disabled(current.lastSnapshot.doors != .closed)
            }
            if let announcementID = stop.stationNameAnnouncementID {
                Button("PLACEHOLDER・駅名案内を再生") { apply(.conductorPlayAnnouncement(announcementID)) }
            }
        } else {
            Text("停車中の対象駅がありません。ドア操作は有効化していません。")
                .font(.caption).foregroundStyle(.secondary)
        }
        ForEach(current.scenario.requiredAnnouncementIDs, id: \.self) { announcementID in
            Button("PLACEHOLDER・車内案内を再生") {
                apply(.conductorPlayAnnouncement(announcementID))
            }
        }
    }

    private func startOrShowBlockedSession() {
        do {
            var created = try RegionalGameModeAdapter.makeSession(
                mode: selectedMode,
                playStyle: selectedPlayStyle,
                context: context,
                snapshot: snapshot
            )
            if created.status == .ready {
                try created.apply(.start)
            }
            session = created
            lastMessage = nil
            onSessionLifecycleChange(created)
        } catch {
            lastMessage = error.localizedDescription
        }
    }

    private func apply(_ action: GameModeAction) {
        guard var current = session else { return }
        do {
            try current.apply(action)
            let effects = current.drainHostEffects()
            session = current
            lastMessage = nil
            onAcceptedAction(action)
            if !effects.isEmpty { onHostEffects(current.mode, effects) }
            onSessionLifecycleChange(current)
        } catch {
            lastMessage = error.localizedDescription
        }
    }

    private func styleTitle(_ style: GameModePlayStyle) -> String {
        switch style {
        case .practice: "練習"
        case .standard: "標準"
        case .disruptionTraining: "異常対応訓練"
        case .freeRun: "フリー走行"
        }
    }

    private func styleDescription(_ style: GameModePlayStyle) -> String {
        switch style {
        case .practice: "練習用の架空ゲーム設定。対応モードではヒント要求が使えます。"
        case .standard: "標準の架空ゲーム設定。"
        case .disruptionTraining: "異常対応の架空選択訓練。異常対応モード専用です。"
        case .freeRun: "自由終了時は自己設定プレイとして記録し、合否評価を行いません。フリーモード専用です。"
        }
    }

    private func statusTitle(_ status: GameModeSessionStatus) -> String {
        switch status {
        case .ready: "準備完了"
        case .active: "進行中"
        case .succeeded: "成功"
        case .failed: "失敗"
        case .blocked: "ブロック / 判定不能"
        case .completed: "自己設定で終了"
        case .abandoned: "放棄"
        }
    }

    private func statusSymbol(_ status: GameModeSessionStatus) -> String {
        switch status {
        case .ready: "circle.dashed"
        case .active: "play.circle.fill"
        case .succeeded: "checkmark.seal.fill"
        case .failed: "xmark.seal.fill"
        case .blocked: "hand.raised.fill"
        case .completed: "flag.checkered"
        case .abandoned: "rectangle.portrait.and.arrow.right"
        }
    }

    private func statusColor(_ status: GameModeSessionStatus) -> Color {
        switch status {
        case .ready, .active: .cyan
        case .succeeded: .green
        case .failed: .red
        case .blocked: .orange
        case .completed, .abandoned: .secondary
        }
    }

    private func outcomeTitle(_ outcome: GameModeOutcome) -> String {
        switch outcome {
        case .success: "ゲーム成功"
        case .failure: "ゲーム失敗"
        case .blocked: "ブロック・判定不能（失敗ではありません）"
        case .selfDirected: "自己設定プレイ終了（合否なし）"
        case .abandoned: "セッション放棄"
        }
    }

    private func outcomeSymbol(_ outcome: GameModeOutcome) -> String {
        switch outcome {
        case .success: "checkmark.circle.fill"
        case .failure: "xmark.circle.fill"
        case .blocked: "hand.raised.fill"
        case .selfDirected: "flag.checkered"
        case .abandoned: "rectangle.portrait.and.arrow.right"
        }
    }

    private func outcomeColor(_ outcome: GameModeOutcome) -> Color {
        switch outcome {
        case .success: .green
        case .failure: .red
        case .blocked: .orange
        case .selfDirected, .abandoned: .secondary
        }
    }

    private func blockingReasonTitle(_ reason: GameModeBlockingReason) -> String {
        switch reason {
        case .missingDriverChecklist: "乗務チェックリストなし"
        case .missingStops: "停車駅入力なし"
        case .missingTrainingSteps: "教習ステップ/プロンプトなし"
        case .missingLandmarks: "景観ポイントなし"
        case .missingDispatchPlan: "会社運行計画なし"
        case .missingTrainSnapshots: "列車ライブ状態なし"
        case .missingStationAnnouncements: "駅名案内IDなし"
        case .unknownInitialDoorState: "初期ドア状態不明"
        case .mustStartAtRouteOrigin: "路線始発位置から開始が必要"
        }
    }

    private func progressDescription(_ progress: GameModeProgress) -> String {
        switch progress {
        case .driver(let state): "乗務項目 \(state.completedDutyStepIDs.count)/\(session?.scenario.driverDutyStepIDs.count ?? 0) · 停車 \(state.visitedStopIDs.count) · 進捗 \(state.routeProgressM.formatted()) m"
        case .timetable(let state): "観測駅 \(state.observedStopIDs.count) · 回復判断枠 \(state.recoveryCreditCount) · 進捗 \(state.routeProgressM.formatted()) m"
        case .free(let state): "経過 \(state.elapsedSeconds.formatted(.number.precision(.fractionLength(0)))) 秒 · 地点 \(state.waypointIDs.count) · 環境要求 \(state.environmentRequestCount)"
        case .conductor(let state): "ドア \(state.doors.rawValue) · 完了駅 \(state.closureConfirmedStopIDs.count) · 案内 \(state.playedAnnouncementIDs.count) · 手順エラー \(state.sequenceErrors)"
        case .disruption(let state): "イベント \(state.state.rawValue) · ヒント \(state.hintCount)"
        case .training(let state): "教材 \(state.completedStepIDs.count) · ヒント \(state.hintCount) · 誤り \(state.mistakes)"
        case .fullLine(let state): "通過駅 \(state.visitedStopIDs.count) · 順序違反 \(state.orderViolations) · 進捗 \(state.routeProgressM.formatted()) m"
        case .tourism(let state): "観察景観 \(state.observedLandmarkIDs.count) · 進捗 \(state.routeProgressM.formatted()) m"
        case .companyOperations(let state): "割当 \(state.assignmentsByTaskID.count) · 競合 \(state.conflictPairs.count) · 期限超過 \(state.overdueTaskIDs.count)"
        }
    }

    private func metricTitle(_ key: String) -> String {
        key.replacingOccurrences(of: "Mps", with: " m/s").replacingOccurrences(of: "M", with: " m")
    }

    private func incidentChoiceTitle(_ choice: GameModeIncidentChoice) -> String {
        switch choice {
        case .acknowledgeGamePrompt: "PLACEHOLDER・ゲーム表示を確認"
        case .requestGameHint: "PLACEHOLDER・ゲームヒントを要求"
        case .waitForGameUpdate: "PLACEHOLDER・ゲーム内更新を待つ"
        }
    }
}
