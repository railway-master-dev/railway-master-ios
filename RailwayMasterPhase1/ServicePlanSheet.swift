import SwiftUI

struct ServicePlanSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var selectedCategory: ServiceCategory = .local
    @State private var selectedDirection: ServiceDirection = .down
    @State private var selectedDaypart: TimetableDaypart = .morningRush
    private let plan = FictionalOperationsPlan.loadBundled()

    private var selectedService: FictionalOperationsPlan.Service? {
        plan?.services.first { $0.category == selectedCategory }
    }

    private var selectedPattern: FictionalOperationsPlan.TimetablePattern? {
        plan?.timetablePatterns.first {
            $0.category == selectedCategory && $0.direction == selectedDirection && $0.daypart == selectedDaypart
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if let plan {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            disclaimerCard(plan.disclaimer)
                            networkCard(plan)
                            servicePicker
                            if let service = selectedService {
                                serviceCard(service, plan: plan)
                            }
                            scheduleCard
                            depotCard
                        }
                        .padding(16)
                    }
                    .background(Color(red: 0.035, green: 0.055, blue: 0.075))
                } else {
                    ContentUnavailableView("運行計画を読み込めません", systemImage: "calendar.badge.exclamationmark", description: Text("正本ネットワークと架空ダイヤJSONの整合を確認してください。"))
                }
            }
            .navigationTitle("運行計画")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("閉じる") { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private func disclaimerCard(_ disclaimer: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("架空・PLACEHOLDER", systemImage: "info.circle.fill")
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(.orange)
            Text(disclaimer)
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.72))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.09), in: RoundedRectangle(cornerRadius: 14))
    }

    private func networkCard(_ plan: FictionalOperationsPlan) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(plan.network.name).font(.system(size: 15, weight: .bold, design: .rounded))
            HStack(spacing: 8) {
                metric("本線", value: "\(Int(plan.network.mainlineLengthKm)) km")
                metric("支線", value: "\(Int(plan.network.branchLengthKm)) km")
            }
            HStack(spacing: 8) {
                metric("車庫線", value: "\(Int(plan.network.depotSpurLengthKm)) km")
                metric("総線路", value: "\(Int(plan.network.totalRouteLengthKm)) km")
            }
            Text("駅数 \(plan.stations.count) · 本線 \(plan.network.mainlineTermini.joined(separator: " ↔ ")) · \(plan.network.branchJunctionStationID)で支線接続")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.white.opacity(0.58))
            Text("支線経由の旅客ルートは68 km。車庫引込線2 kmは旅客距離に含めません。")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.cyan.opacity(0.88))
        }
        .padding(13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 14))
    }

    private var servicePicker: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("列車種別").font(.system(size: 12, weight: .bold, design: .rounded))
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 7) {
                    ForEach(ServiceCategory.allCases) { category in
                        Button {
                            selectedCategory = category
                        } label: {
                            Text(category.displayName)
                                .font(.system(size: 11, weight: .bold, design: .rounded))
                                .foregroundStyle(selectedCategory == category ? Color.black : Color.white.opacity(0.86))
                                .padding(.horizontal, 11)
                                .padding(.vertical, 8)
                                .background(selectedCategory == category ? Color.cyan : Color.white.opacity(0.08), in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func serviceCard(_ service: FictionalOperationsPlan.Service, plan: FictionalOperationsPlan) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .firstTextBaseline) {
                Text(service.category.displayName).font(.system(size: 17, weight: .heavy, design: .rounded))
                Spacer()
                Text("\(service.plannedDurationMinutes / 60)時間\(service.plannedDurationMinutes % 60)分")
                    .font(.system(size: 14, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(.cyan)
            }
            Text("\(Int(service.routeDistanceKm)) km旅客経路 · 停車 \(service.stopStationIDs.count) 駅 · \(service.category.rawValue)")
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.57))
            let names = service.stopStationIDs.compactMap { id in plan.stations.first(where: { $0.stationId == id })?.name }
            Text(names.joined(separator: "  →  "))
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.white.opacity(0.78))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.cyan.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
    }

    private var scheduleCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("運転方向・時間帯").font(.system(size: 12, weight: .bold, design: .rounded))
            Picker("方向", selection: $selectedDirection) {
                ForEach(ServiceDirection.allCases) { direction in
                    Text(direction.displayName).tag(direction)
                }
            }
            .pickerStyle(.segmented)
            Picker("時間帯", selection: $selectedDaypart) {
                ForEach(TimetableDaypart.allCases) { daypart in
                    Text(daypart.displayName).tag(daypart)
                }
            }
            .pickerStyle(.segmented)
            if let pattern = selectedPattern {
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("運転時間").font(.system(size: 9)).foregroundStyle(.white.opacity(0.5))
                        Text("\(pattern.firstDeparture)–\(pattern.lastDeparture)").font(.system(size: 13, weight: .bold, design: .rounded).monospacedDigit())
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 3) {
                        Text("計画間隔").font(.system(size: 9)).foregroundStyle(.white.opacity(0.5))
                        Text("約\(pattern.intervalMinutes)分毎").font(.system(size: 13, weight: .bold, design: .rounded))
                    }
                }
                .padding(10)
                .background(Color.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 10))
                Text("所要 \(pattern.plannedDurationMinutes)分 · \(pattern.calendar)")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white.opacity(0.58))
            } else {
                Text("該当する計画ダイヤがありません。")
                    .font(.system(size: 10))
                    .foregroundStyle(.orange)
            }
        }
        .padding(13)
        .background(Color.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 14))
    }

    private var depotCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("入出庫作業（計画値・車庫引込線2 km）").font(.system(size: 12, weight: .bold, design: .rounded))
            let procedures = plan?.depotProcedures.filter {
                $0.relatedServiceCategory == selectedCategory && $0.direction == selectedDirection
            } ?? []
            ForEach(procedures) { procedure in
                HStack {
                    Text(procedure.kind.displayName).font(.system(size: 11, weight: .bold))
                    Text(procedure.depotId).font(.system(size: 10, weight: .medium)).foregroundStyle(.white.opacity(0.58))
                    Spacer()
                    let offset = procedure.timeOffsetMinutesFromPassengerDeparture
                    Text(offset < 0 ? "発車 \(abs(offset))分前" : "到着 \(offset)分後")
                        .font(.system(size: 10, weight: .semibold, design: .rounded).monospacedDigit())
                        .foregroundStyle(.white.opacity(0.75))
                }
                .padding(.vertical, 2)
            }
        }
        .padding(13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 14))
    }

    private func metric(_ title: String, value: String) -> some View {
        VStack(spacing: 3) {
            Text(title).font(.system(size: 9, weight: .medium)).foregroundStyle(.white.opacity(0.52))
            Text(value).font(.system(size: 13, weight: .heavy, design: .rounded).monospacedDigit()).foregroundStyle(.white)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(Color.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 10))
    }
}
