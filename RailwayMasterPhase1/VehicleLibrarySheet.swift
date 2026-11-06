import SwiftUI

/// 実在車両は出典確認用の参考ラベルであり、ゲーム内の架空プロキシとは別物です。
/// 選択結果はIDのみを親へ返し、SimulatorModelや物理設定を変更しません。
struct VehicleLibrarySheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding private var selectedVehicleID: String

    init(selectedVehicleID: Binding<String>) {
        self._selectedVehicleID = selectedVehicleID
    }

    private var selectedVehicle: VehicleReference? {
        VehicleReference.catalog.first { $0.id == selectedVehicleID }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 15) {
                    disclaimerCard
                    fictionalProxyCard

                    VStack(alignment: .leading, spacing: 9) {
                        Text("参考車種")
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                        Text("選択は参考車種IDの返却のみです。ゲーム内物理や車両外観は切り替わりません。")
                            .font(.system(size: 11))
                            .foregroundStyle(.white.opacity(0.62))

                        ForEach(VehicleReference.catalog) { vehicle in
                            vehicleCard(vehicle)
                        }
                    }

                    if let selectedVehicle {
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.cyan)
                            Text("選択中 ID: \(selectedVehicle.id)")
                                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                .foregroundStyle(.white.opacity(0.84))
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 12))
                    }
                }
                .padding(16)
            }
            .background(Color(red: 0.035, green: 0.055, blue: 0.075))
            .navigationTitle("車両ライブラリ")
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
        VStack(alignment: .leading, spacing: 7) {
            Label("実在形式の再現ではありません", systemImage: "info.circle.fill")
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(.orange)
            Text("実在車種は公式資料に記載された事実を参照するためだけのラベルです。実車の画像・ロゴ・車体形状・音声は含まず、車両の外観や性能を忠実に再現するものではありません。")
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.75))
                .fixedSize(horizontal: false, vertical: true)
            Text("再利用条件: 事実参照のみ・派生アセット不可・ライセンス要確認")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.orange.opacity(0.9))
        }
        .padding(13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.09), in: RoundedRectangle(cornerRadius: 14))
    }

    private var fictionalProxyCard: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(alignment: .firstTextBaseline) {
                Text("ゲーム内プロキシ")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                Spacer()
                statusBadge(.estimated)
            }
            Text("界磁チョッパ T-01（架空） — 実在車種とは独立したゲーム物理プロフィール")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.74))
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                proxyMetric("編成", value: "6両")
                proxyMetric("上限速度", value: "100 km/h")
                proxyMetric("最大引張力", value: "210 kN")
            }
            HStack(spacing: 8) {
                proxyMetric("最大出力", value: "2.4 MW")
                proxyMetric("常用減速度", value: "0.972 m/s²")
                proxyMetric("非常減速度", value: "1.25 m/s²")
            }
            Text("すべて架空プロフィールの設定値です。実車諸元から推定・転記した値ではなく、参考車種ごとの切替にも使用しません。")
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.6))
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 6) {
                statusBadge(.verified)
                Text("出典に書かれた事実のみ")
                statusBadge(.placeholder)
                Text("未確認の実車物理・詳細属性")
            }
            .font(.system(size: 9, weight: .medium))
            .foregroundStyle(.white.opacity(0.62))
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.cyan.opacity(0.075), in: RoundedRectangle(cornerRadius: 14))
    }

    private func vehicleCard(_ vehicle: VehicleReference) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                selectedVehicleID = vehicle.id
            } label: {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(vehicle.name)
                                .font(.system(size: 14, weight: .bold, design: .rounded))
                                .foregroundStyle(.white)
                            Text(vehicle.operatorName)
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(.white.opacity(0.58))
                        }
                        Spacer(minLength: 5)
                        statusBadge(.verified)
                        Image(systemName: selectedVehicleID == vehicle.id ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(selectedVehicleID == vehicle.id ? Color.cyan : Color.white.opacity(0.35))
                    }

                    Text("出典で確認: \(vehicle.verifiedSummary)")
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.78))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(vehicle.name)、参考車種ID \(vehicle.id)を選択")
            .accessibilityAddTraits(selectedVehicleID == vehicle.id ? .isSelected : [])

            if let url = URL(string: vehicle.sourceURL) {
                Link(destination: url) {
                    Label("\(vehicle.sourceName) — \(vehicle.sourceTitle)", systemImage: "arrow.up.right.square")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.cyan.opacity(0.9))
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
            }

            Text("物理・外観: PLACEHOLDER（実車データ未設定） · 権利: 事実参照のみ・派生アセット不可・ライセンス要確認")
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.white.opacity(0.52))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(selectedVehicleID == vehicle.id ? Color.cyan.opacity(0.12) : Color.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(selectedVehicleID == vehicle.id ? Color.cyan.opacity(0.52) : Color.white.opacity(0.07), lineWidth: 1)
        }
    }

    private func proxyMetric(_ title: String, value: String) -> some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.system(size: 8, weight: .medium))
                .foregroundStyle(.white.opacity(0.53))
            Text(value)
                .font(.system(size: 10, weight: .bold, design: .rounded).monospacedDigit())
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(Color.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 9))
    }

    private func statusBadge(_ status: VehicleDataStatus) -> some View {
        Text(status.rawValue)
            .font(.system(size: 8, weight: .heavy, design: .rounded))
            .foregroundStyle(status.tint)
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(status.tint.opacity(0.12), in: Capsule())
            .accessibilityLabel("データ状態 \(status.rawValue)")
    }
}

private enum VehicleDataStatus: String {
    case verified = "VERIFIED"
    case estimated = "ESTIMATED"
    case placeholder = "PLACEHOLDER"

    var tint: Color {
        switch self {
        case .verified: .green
        case .estimated: .orange
        case .placeholder: .gray
        }
    }
}

private struct VehicleReference: Identifiable {
    let id: String
    let name: String
    let operatorName: String
    let verifiedSummary: String
    let sourceName: String
    let sourceTitle: String
    let sourceURL: String

    static let catalog: [VehicleReference] = [
        VehicleReference(
            id: "jr-east-e233",
            name: "E233系",
            operatorName: "JR東日本",
            verifiedSummary: "デビュー2006年12月、最高速度120 km/h（公式紹介ページ記載）。",
            sourceName: "JR東日本",
            sourceTitle: "E233系",
            sourceURL: "https://www.jreast.co.jp/train/local/e233.html"
        ),
        VehicleReference(
            id: "jr-east-e235",
            name: "E235系",
            operatorName: "JR東日本",
            verifiedSummary: "デビュー2016年3月、最高速度120 km/h（公式紹介ページ記載）。",
            sourceName: "JR東日本",
            sourceTitle: "E235系",
            sourceURL: "https://www.jreast.co.jp/train/local/e235.html"
        ),
        VehicleReference(
            id: "jr-east-e231",
            name: "E231系",
            operatorName: "JR東日本",
            verifiedSummary: "デビュー2000年3月、最高速度120 km/h。TIMS導入等を公式紹介に記載。",
            sourceName: "JR東日本",
            sourceTitle: "E231系",
            sourceURL: "https://www.jreast.co.jp/train/local/e231.html"
        ),
        VehicleReference(
            id: "jr-east-209",
            name: "209系",
            operatorName: "JR東日本",
            verifiedSummary: "デビュー1993年、最高速度110 km/h（公式紹介ページ記載）。",
            sourceName: "JR東日本",
            sourceTitle: "209系",
            sourceURL: "https://www.jreast.co.jp/train/local/209.html"
        ),
        VehicleReference(
            id: "jr-east-205",
            name: "205系",
            operatorName: "国鉄・JR東日本（出典: JR東日本）",
            verifiedSummary: "デビュー1985年、最高速度100 km/h。軽量ステンレス車体、界磁添加励磁制御（公式紹介）。",
            sourceName: "JR東日本",
            sourceTitle: "205系",
            sourceURL: "https://www.jreast.co.jp/train/local/205.html"
        ),
        VehicleReference(
            id: "jr-103",
            name: "103系",
            operatorName: "国鉄・JR（出典: JR西日本登録鉄道文化財）",
            verifiedSummary: "1963–1984年に増備、総製造3,447両。クハ103形1号は1964年製造（保存車の例）。",
            sourceName: "JR西日本",
            sourceTitle: "クハ103形電車1号",
            sourceURL: "https://www.westjr.co.jp/railway-cultural-property/pages/00027.html"
        ),
        VehicleReference(
            id: "tobu-50000",
            name: "50000型",
            operatorName: "東武鉄道",
            verifiedSummary: "製造初年2004年10月、アルミ合金車体、VVVF、最高速度120 km/h（50000型欄）。",
            sourceName: "東武鉄道",
            sourceTitle: "車両紹介 — 50000型",
            sourceURL: "https://www.tobu.co.jp/corporation/rail/vehicles/"
        ),
        VehicleReference(
            id: "seibu-40000",
            name: "40000系",
            operatorName: "西武鉄道",
            verifiedSummary: "製造初年2017年、固定編成8・10両。主電動機190 kW、VVVF、空気・回生ブレーキ（公式諸元）。",
            sourceName: "西武鉄道",
            sourceTitle: "40000系（主要諸元、2026年10月1日現在）",
            sourceURL: "https://www.seiburailway.jp/railway/encyclopedia/40000/"
        ),
        VehicleReference(
            id: "odakyu-3000",
            name: "3000形（通勤車両）",
            operatorName: "小田急電鉄",
            verifiedSummary: "2002年就役、オールステンレス、小田急初の純電気ブレーキ（公式紹介）。",
            sourceName: "小田急電鉄",
            sourceTitle: "鉄道部門：車両紹介 — 3000形",
            sourceURL: "https://www.odakyu.jp/company/railroad/train/"
        ),
        VehicleReference(
            id: "kintetsu-series-21",
            name: "シリーズ21",
            operatorName: "近畿日本鉄道",
            verifiedSummary: "3220・5820・9020・9820・6820系。2000年3月に奈良線・京都線で運行開始、アルミ車体・VVVF（公式紹介）。",
            sourceName: "近畿日本鉄道",
            sourceTitle: "3220・5820・9020・9820・6820系 シリーズ21",
            sourceURL: "https://www.kintetsu.jp/kouhou/Train/B18.html"
        )
    ]
}
