import SwiftUI

struct RegionalRouteSelectionSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var variant: RegionalRouteVariant
    @State private var category: ServiceCategory
    @State private var direction: RegionalTravelDirection
    let onStart: (RegionalRouteVariant, ServiceCategory, RegionalTravelDirection) -> Void

    init(
        initialVariant: RegionalRouteVariant,
        initialCategory: ServiceCategory,
        initialDirection: RegionalTravelDirection,
        onStart: @escaping (RegionalRouteVariant, ServiceCategory, RegionalTravelDirection) -> Void
    ) {
        _variant = State(initialValue: initialVariant)
        _category = State(initialValue: initialCategory)
        _direction = State(initialValue: initialDirection)
        self.onStart = onStart
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("架空ルート") {
                    Picker("行程", selection: $variant) {
                        ForEach(RegionalRouteVariant.allCases) { route in
                            Text("\(route.title) · \(route.distanceDescription)").tag(route)
                        }
                    }
                    Picker("運行種別", selection: $category) {
                        ForEach(ServiceCategory.allCases) { service in
                            Text(service.displayName).tag(service)
                        }
                    }
                    Picker("方向", selection: $direction) {
                        ForEach(RegionalTravelDirection.allCases) { item in
                            Text(item.title).tag(item)
                        }
                    }
                    Text("この選択から停車駅・目標位置・速度制限・信号閉そく・交通AIを同じPLACEHOLDER行程に再構成します。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("運行体系") {
                    Label("本線 60 km · 支線 8 km · 車庫線 2 km", systemImage: "point.3.connected.trianglepath.dotted")
                    Label("6種別 × 上下2方向 × 4時間帯 = 48時刻表パターン", systemImage: "calendar.badge.clock")
                    Label("駅・キロ程・所要時間は架空のPLACEHOLDERデータ", systemImage: "info.circle")
                }

                Section {
                    Text("行程構造と駅数を統合したゲームネットワークです。線形、勾配、曲線、信号位置、所要時間は実測・公式データではなく、実在路線の再現ではありません。")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .navigationTitle("運転ルート選択")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("キャンセル") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("この条件で運転") {
                        onStart(variant, category, direction)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }
}
