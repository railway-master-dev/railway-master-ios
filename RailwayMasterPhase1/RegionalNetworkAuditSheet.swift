import RailwayRouteData
import RailwaySignalling
import SwiftUI

struct RegionalNetworkAuditSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var report = RegionalNetworkIntegration.load()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if let plan = report.plan {
                        canonicalCard(plan)
                    }
                    reconciliationCard
                    sourceRouteCard
                    timetableCard
                    signallingCard
                    protectionSystemsCard
                    activeSliceCard
                    if !report.issues.isEmpty {
                        issueCard(report.issues)
                    }
                }
                .padding(16)
            }
            .background(Color(red: 0.035, green: 0.055, blue: 0.075))
            .navigationTitle("地域ネットワーク監査")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("閉じる") { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private func canonicalCard(_ plan: FictionalOperationsPlan) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("正本 · PLACEHOLDER", systemImage: "checkmark.seal.fill")
                .font(.system(size: 12, weight: .heavy, design: .rounded))
                .foregroundStyle(.cyan)
            Text(plan.network.name)
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 7) {
                metric("本線", "60 km")
                metric("支線", "8 km")
                metric("車庫線", "2 km")
                metric("総線路", "70 km")
            }
            Text("旅客列車の支線経由ルートは68 km。車庫線は総線路長に含み、旅客距離には加えません。駅\(plan.stations.count)駅・全値PLACEHOLDER。")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.white.opacity(0.68))
                .fixedSize(horizontal: false, vertical: true)
            Text(plan.network.reconciliationNote)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.cyan.opacity(0.78))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.cyan.opacity(0.09), in: RoundedRectangle(cornerRadius: 15))
        .overlay(RoundedRectangle(cornerRadius: 15).stroke(Color.cyan.opacity(0.25), lineWidth: 1))
    }

    private var reconciliationCard: some View {
        VStack(alignment: .leading, spacing: 9) {
            heading("統一ネットワーク", subtitle: "運行・RouteData・信号・交通を共通の架空正本へ接続")
            reconciliationRow("本線", value: "60 km", tint: .green)
            reconciliationRow("支線", value: "8 km", tint: .green)
            reconciliationRow("車庫引込線", value: "2 km", tint: .green)
            reconciliationRow("物理線路計 / 旅客支線経由", value: "70 km / 68 km", tint: .green)
            Text("32駅の名称・キロ程はFictionalOperationsPlan.jsonを正本としてRouteDataと信号・運行アダプターへ接続しています。全地理・線形・設備値は架空PLACEHOLDERで、実在線の測量値ではありません。")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.white.opacity(0.62))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 14))
    }

    private var sourceRouteCard: some View {
        VStack(alignment: .leading, spacing: 9) {
            heading("RouteDataパッケージ", subtitle: "キロ程照会・データ品質検証を同梱")
            if let package = report.sourceRoutePackage {
                Text(package.route.name.value ?? package.route.routeID)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                Text("状態 \(package.route.name.status.rawValue) · 本線\(distanceKm(package.route.totalLengthM.value)) km · 線路合計\(distanceKm(package.route.networkLengthM.value)) km · 駅\(package.route.stations.count)駅 · 支線・車庫線\(package.route.tracks.filter { $0.trackID != package.route.mainTrackID }.count)線")
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.72))
                    .fixedSize(horizontal: false, vertical: true)
                if let position = report.sourceRoutePosition {
                    Text("キロ程0m照会: \(position.segmentID ?? "区間データなし") · 次駅 \(position.nextStation?.entity.name.value ?? "未設定")")
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(.cyan.opacity(0.9))
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let validation = report.sourceRouteValidation {
                    HStack(spacing: 8) {
                        Label(validation.isStructurallyValid ? "構造検査OK" : "構造要確認", systemImage: validation.isStructurallyValid ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        Spacer()
                        Text("error \(validation.errorCount) · warning \(validation.warningCount)")
                            .monospacedDigit()
                    }
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(validation.isStructurallyValid ? Color.green : Color.orange)
                }
                Text("本線60km・支線8km・車庫線2km、32駅のPLACEHOLDER route fixtureです。品質検査・キロ程照会に使用し、運行計画と同じ駅ID/キロ程を参照します。")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white.opacity(0.68))
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("架空ルートfixtureを読み込めませんでした。")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.orange)
            }
        }
        .padding(13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 14))
    }

    private var timetableCard: some View {
        VStack(alignment: .leading, spacing: 9) {
            heading("Signallingパッケージ", subtitle: "運行種別・方向・入出庫を正本から組み直す")
            if let network = report.canonicalSignallingNetwork,
               let timetable = report.canonicalTimetable {
                HStack(spacing: 8) {
                    metric("構築線路", "\(distanceKm(network.totalTrackLengthM)) km")
                    metric("代表便", "\(timetable.services.count)本")
                    metric("車庫作業", "\(timetable.depotMovements.count)件")
                }
                Text("6種別を本線・支線の32駅モデルへ接続。支線経由の代表便は68km、車庫引込線2kmは別の線路区間として保持しています。時刻はAsia/Tokyoのゲーム用PLACEHOLDERです。")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white.opacity(0.68))
                    .fixedSize(horizontal: false, vertical: true)
                Text("Signallingパッケージsampleとアプリadapterは60km本線・8km支線・2km車庫線に統一。時刻表・信号値は架空PLACEHOLDERです。")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white.opacity(0.68))
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("正本からの信号・時刻表モデル構築に失敗しました。")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.orange)
            }
        }
        .padding(13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 14))
    }

    private var signallingCard: some View {
        VStack(alignment: .leading, spacing: 9) {
            heading("信号サンプル", subtitle: "本線・支線・車庫線の共通架空ネットワーク")
            if let signal = report.sampleSignal {
                HStack {
                    Label(aspectName(signal.aspect), systemImage: "trafficlight.fill")
                        .font(.system(size: 12, weight: .heavy, design: .rounded))
                        .foregroundStyle(aspectColor(signal.aspect))
                    Spacer()
                    Text(signal.blockID).font(.system(size: 10, weight: .semibold, design: .rounded).monospacedDigit())
                        .foregroundStyle(.white.opacity(0.6))
                }
                Text(signal.explanation)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white.opacity(0.7))
                Text("信号値はプレイ中の位置・閉そく・運転方向に応じて更新されるゲームモデルです。実ATS/ATC規格や運転保安を表すものではありません。")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.orange.opacity(0.86))
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("教材用信号のサンプルを生成できませんでした。")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.orange)
            }
        }
        .padding(13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 14))
    }

    private var activeSliceCard: some View {
        VStack(alignment: .leading, spacing: 7) {
            heading("運転可能ネットワーク", subtitle: "全線・支線・車庫移動を同じ架空正本から選択")
            Text("運転ルート選択から60km本線、8km支線、68km支線経由、2km車庫線の各variantを開始できます。32駅、上下方向、6種別、朝ラッシュ・日中・夜間と入出庫のPLACEHOLDER計画を使用します。")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.75))
                .fixedSize(horizontal: false, vertical: true)
            Text("全線の地理形状・線形・駅設備・信号は架空PLACEHOLDERです。実在路線候補、実測、実運転規則として扱わないでください。")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.orange.opacity(0.86))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 14))
    }

    private var protectionSystemsCard: some View {
        VStack(alignment: .leading, spacing: 9) {
            heading("保安装置パッケージ", subtitle: "既存信号モデルとは別モジュールの架空デモ")
            if let result = report.protectionSystemsDemoResult {
                Text("架空シミュレーション専用 · tick \(result.fixedTick) · 状態 \(result.protectionStates.count) · イベント \(result.events.count)")
                    .font(.system(size: 10, weight: .semibold, design: .rounded).monospacedDigit())
                    .foregroundStyle(.cyan)
                ForEach(result.protectionStates.prefix(7), id: \.id) { state in
                    HStack(alignment: .top, spacing: 8) {
                        Text(state.system.uppercased())
                            .font(.system(size: 9, weight: .heavy, design: .rounded))
                            .foregroundStyle(.white.opacity(0.78))
                        Spacer(minLength: 6)
                        Text(state.brakeCommanded ? "制動要求" : state.stateDescription)
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(state.brakeCommanded ? Color.orange : Color.white.opacity(0.72))
                            .multilineTextAlignment(.trailing)
                    }
                }
                Text("架空の試験ネットワークだけで計算し、走行物理・実機・実運転規則・訓練判断には接続していません。")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.orange.opacity(0.88))
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("架空の保安装置デモを生成できませんでした。")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.orange)
            }
        }
        .padding(13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 14))
    }

    private func issueCard(_ issues: [String]) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Label("統合時の確認事項", systemImage: "exclamationmark.triangle.fill")
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(.orange)
            ForEach(Array(issues.enumerated()), id: \.offset) { _, issue in
                Text("• \(issue)")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white.opacity(0.75))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
    }

    private func heading(_ title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.system(size: 13, weight: .bold, design: .rounded)).foregroundStyle(.white)
            Text(subtitle).font(.system(size: 10, weight: .medium)).foregroundStyle(.white.opacity(0.52))
        }
    }

    private func metric(_ title: String, _ value: String) -> some View {
        VStack(spacing: 4) {
            Text(title).font(.system(size: 8, weight: .medium)).foregroundStyle(.white.opacity(0.52))
            Text(value).font(.system(size: 12, weight: .heavy, design: .rounded).monospacedDigit()).foregroundStyle(.white)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(Color.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 10))
    }

    private func reconciliationRow(_ title: String, value: String, tint: Color) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(title).font(.system(size: 10, weight: .semibold))
            Spacer(minLength: 6)
            Text(value).font(.system(size: 10, weight: .bold, design: .rounded).monospacedDigit())
                .multilineTextAlignment(.trailing)
                .foregroundStyle(tint)
        }
    }

    private func distanceKm(_ meters: Double?) -> String {
        guard let meters, meters.isFinite else { return "—" }
        return (meters / 1_000).formatted(.number.precision(.fractionLength(0...1)))
    }

    private func distanceKm(_ meters: Double) -> String {
        guard meters.isFinite else { return "—" }
        return (meters / 1_000).formatted(.number.precision(.fractionLength(0...1)))
    }

    private func aspectName(_ aspect: RailwaySignalling.SignalAspect) -> String {
        switch aspect {
        case .stop: return "停止"
        case .caution: return "注意"
        case .proceed: return "進行"
        }
    }

    private func aspectColor(_ aspect: RailwaySignalling.SignalAspect) -> Color {
        switch aspect {
        case .stop: return .red
        case .caution: return .orange
        case .proceed: return .green
        }
    }
}
