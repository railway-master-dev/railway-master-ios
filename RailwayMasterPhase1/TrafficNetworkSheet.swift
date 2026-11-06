import SwiftUI
import TrafficSimulation

struct TrafficNetworkSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var previewEngine: TrafficSimulationEngine?
    @State private var previewSnapshot: TrafficSnapshot?
    @State private var previewError: String?
    let scenario: TrafficScenario?
    let activeSegmentName: String
    let activeSegmentDistanceM: Double

    private var orderedPathKinds: [TrafficRoutePathKind] {
        [.mainline, .branch, .depotSpur]
    }

    var body: some View {
        NavigationStack {
            Group {
                if let scenario {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 14) {
                            activeSegmentCard
                            disclaimerCard
                            networkCard(scenario)
                            previewCard
                            countCard(scenario)
                            serviceTypeCard(scenario)
                            servicePeriodCard(scenario)
                            operationKindCard(scenario)
                        }
                        .padding(16)
                    }
                    .background(Color(red: 0.035, green: 0.055, blue: 0.075))
                } else {
                    ContentUnavailableView(
                        "交通ネットワークを読み込めません",
                        systemImage: "exclamationmark.triangle",
                        description: Text("TrafficScenario が nil のため、ネットワーク・列車・道路車両・乗客の情報を表示できません。データを確認して再度お試しください。")
                    )
                    .background(Color(red: 0.035, green: 0.055, blue: 0.075))
                }
            }
            .navigationTitle("交通ネットワーク")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("閉じる") { dismiss() }
                }
            }
            .preferredColorScheme(.dark)
        }
        .onAppear(perform: preparePreview)
    }

    private var activeSegmentCard: some View {
        VStack(alignment: .leading, spacing: 9) {
            Label("現行ルート · 選択中の区間", systemImage: "point.topleft.down.to.point.bottomright.curvepath")
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(.cyan)
            Text(activeSegmentName.isEmpty ? "区間名未設定" : activeSegmentName)
                .font(.system(size: 18, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)
            Text("約70 km地域ネットワーク上の選択区間 · \(distanceText(activeSegmentDistanceM))")
                .font(.system(size: 12, weight: .semibold, design: .rounded).monospacedDigit())
                .foregroundStyle(.white.opacity(0.72))
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.cyan.opacity(0.10), in: RoundedRectangle(cornerRadius: 15))
        .overlay(RoundedRectangle(cornerRadius: 15).stroke(Color.cyan.opacity(0.24), lineWidth: 1))
    }

    private var disclaimerCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("架空データ · PLACEHOLDER", systemImage: "exclamationmark.shield.fill")
                .font(.system(size: 12, weight: .heavy, design: .rounded))
                .foregroundStyle(.orange)
            Text("本線60 km＋支線8 km＋車庫引込線2 km＝70 kmの架空PLACEHOLDER正本に接続しています。運転ルート選択から本線・支線・支線経由・車庫移動を開始できます。実在線・実運用・安全確認・信号制御には使用できません。")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.82))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.11), in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.orange.opacity(0.28), lineWidth: 1))
    }

    private func networkCard(_ scenario: TrafficScenario) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            cardHeading("正本PLACEHOLDER · 70 km", subtitle: "TrafficScenario.routePaths：本線60 + 支線8 + 車庫引込線2 km")
            ForEach(orderedPathKinds, id: \.self) { kind in
                let paths = scenario.routePaths.filter { $0.kind == kind }
                HStack(spacing: 8) {
                    Text(pathKindName(kind))
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                    Spacer(minLength: 8)
                    Text(paths.isEmpty ? "データなし" : distanceText(paths.reduce(0) { $0 + $1.lengthM }))
                        .font(.system(size: 12, weight: .bold, design: .rounded).monospacedDigit())
                        .foregroundStyle(paths.isEmpty ? Color.white.opacity(0.45) : Color.white)
                    Text("\(paths.count)経路")
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.55))
                        .frame(minWidth: 42, alignment: .trailing)
                }
                .padding(.vertical, 2)
            }
            Rectangle().fill(Color.white.opacity(0.10)).frame(height: 1)
            HStack {
                Text("ネットワーク合計")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                Spacer()
                Text(distanceText(scenario.routePaths.reduce(0) { $0 + $1.lengthM }))
                    .font(.system(size: 15, weight: .heavy, design: .rounded).monospacedDigit())
                    .foregroundStyle(.cyan)
            }
            Text("線路の共有ルート長（\(distanceText(scenario.routeLengthM))）とは別に、分岐線・車庫引込線を含む経路長の合計です。")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.white.opacity(0.55))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 14))
    }

    private func countCard(_ scenario: TrafficScenario) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            cardHeading("サンプル件数", subtitle: "シナリオに登録された計画・移動の数")
            HStack(spacing: 8) {
                metric("列車計画", value: scenario.trains.count)
                metric("道路車両", value: scenario.roadVehicles.count)
                metric("乗客移動", value: scenario.passengerTrips.count)
            }
            Text("乗客数は個人の実人数ではなく、ホーム上の乗客移動（passengerTrips）の登録件数です。")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.white.opacity(0.55))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(13)
        .background(Color.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 14))
    }

    private var previewCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            cardHeading("地域交通を手動プレビュー", subtitle: "再生時間はシミュレーション秒。現行のプレイ区間とは独立")
            if let snapshot = previewSnapshot {
                HStack(spacing: 8) {
                    metric("経過秒", value: Int(snapshot.simulationTimeSeconds.rounded()))
                    metric("走行列車", value: snapshot.trains.filter { $0.phase == .running }.count)
                    metric("道路車両", value: snapshot.roadVehicles.filter { $0.phase == .moving }.count)
                }
                Text("乗客歩行 \(snapshot.passengers.filter { $0.phase == .walking }.count)件 · 固定tick \(snapshot.fixedTick.formatted()) · 全値PLACEHOLDER")
                    .font(.system(size: 10, weight: .medium, design: .rounded).monospacedDigit())
                    .foregroundStyle(.white.opacity(0.68))
                HStack(spacing: 8) {
                    Button {
                        advancePreview(by: 10)
                    } label: {
                        Label("+10秒", systemImage: "forward.end.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.cyan)
                    Button {
                        advancePreview(by: 60)
                    } label: {
                        Label("+1分", systemImage: "forward.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    Button {
                        resetPreview()
                    } label: {
                        Image(systemName: "arrow.counterclockwise")
                    }
                    .buttonStyle(.bordered)
                    .accessibilityLabel("交通プレビューを最初から")
                }
                if let previewError {
                    Text("プレビュー更新エラー: \(previewError)")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.orange)
                }
            } else {
                Text(previewError ?? "交通エンジンを初期化できませんでした。")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.orange)
            }
            Text("この操作は70kmの架空交通サンプルだけを進めます。運転台の車両・信号・停止目標とは接続していません。")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.orange.opacity(0.84))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(13)
        .background(Color.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 14))
    }

    private func preparePreview() {
        guard previewEngine == nil else { return }
        guard let scenario else {
            previewError = "TrafficScenario がありません。"
            return
        }
        do {
            let engine = try TrafficSimulationEngine(scenario: scenario)
            previewSnapshot = engine.snapshot()
            previewEngine = engine
            previewError = nil
        } catch {
            previewError = String(describing: error)
        }
    }

    private func advancePreview(by seconds: Double) {
        guard var engine = previewEngine else { return }
        do {
            previewSnapshot = try engine.advance(realDeltaSeconds: seconds)
            previewEngine = engine
            previewError = nil
        } catch {
            previewError = String(describing: error)
        }
    }

    private func resetPreview() {
        previewEngine = nil
        previewSnapshot = nil
        previewError = nil
        preparePreview()
    }

    private func serviceTypeCard(_ scenario: TrafficScenario) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            cardHeading("列車種別", subtitle: "計画列車数")
            ForEach(TrainServiceType.allCases, id: \.self) { serviceType in
                breakdownRow(
                    title: serviceTypeName(serviceType),
                    count: scenario.trains.filter { $0.serviceType == serviceType }.count
                )
            }
        }
        .padding(13)
        .background(Color.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 14))
    }

    private func servicePeriodCard(_ scenario: TrafficScenario) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            cardHeading("運転時間帯", subtitle: "時間帯別の列車計画数")
            ForEach(TrafficServicePeriod.allCases, id: \.self) { period in
                breakdownRow(
                    title: servicePeriodName(period),
                    count: scenario.trains.filter { $0.servicePeriod == period }.count
                )
            }
        }
        .padding(13)
        .background(Color.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 14))
    }

    private func operationKindCard(_ scenario: TrafficScenario) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            cardHeading("入出庫・運転作業", subtitle: "計画に記録された作業種別")
            ForEach(TrafficOperationKind.allCases, id: \.self) { kind in
                breakdownRow(
                    title: operationKindName(kind),
                    count: scenario.trains.filter { $0.operationKind == kind }.count
                )
            }
            Text("件数は列車計画の operationKind に基づきます。")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.white.opacity(0.55))
        }
        .padding(13)
        .background(Color.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 14))
    }

    private func cardHeading(_ title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
            Text(subtitle)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.white.opacity(0.52))
        }
        .padding(.bottom, 2)
    }

    private func metric(_ title: String, value: Int) -> some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.white.opacity(0.55))
            Text(value.formatted())
                .font(.system(size: 18, weight: .heavy, design: .rounded).monospacedDigit())
                .foregroundStyle(.white)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(Color.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 10))
    }

    private func breakdownRow(title: String, count: Int) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
            Spacer()
            Text("\(count)件")
                .font(.system(size: 11, weight: .bold, design: .rounded).monospacedDigit())
                .foregroundStyle(.white.opacity(0.78))
        }
        .padding(.vertical, 2)
    }

    private func distanceText(_ meters: Double) -> String {
        guard meters.isFinite else { return "—" }
        return "\((meters / 1_000).formatted(.number.precision(.fractionLength(1)))) km"
    }

    private func pathKindName(_ kind: TrafficRoutePathKind) -> String {
        switch kind {
        case .mainline: "本線"
        case .branch: "支線"
        case .depotSpur: "車庫引込線"
        }
    }

    private func serviceTypeName(_ type: TrainServiceType) -> String {
        switch type {
        case .local: "各駅停車"
        case .rapid: "快速"
        case .semiExpress: "準急"
        case .express: "急行"
        case .rapidExpress: "快速急行"
        case .limitedExpress: "特急"
        }
    }

    private func servicePeriodName(_ period: TrafficServicePeriod) -> String {
        switch period {
        case .morningRush: "朝ラッシュ"
        case .daytime: "昼間"
        case .night: "夜"
        }
    }

    private func operationKindName(_ kind: TrafficOperationKind) -> String {
        switch kind {
        case .passengerService: "旅客運転"
        case .depotEntry: "入庫"
        case .depotExit: "出庫"
        case .depotShunting: "車庫内入換"
        }
    }
}
