import RailwayTimetable
import SwiftUI

struct TimetableControlSheet: View {
    @ObservedObject var model: SimulatorModel
    @Environment(\.dismiss) private var dismiss
    @State private var calendar: RailwayTimetable.ServiceCalendar
    @State private var daypart: RailwayTimetable.Daypart
    @State private var initialDelayMinutes: Double

    init(model: SimulatorModel) {
        self.model = model
        _calendar = State(initialValue: model.timetableCalendar)
        _daypart = State(initialValue: model.timetableDaypart)
        _initialDelayMinutes = State(initialValue: Double(model.timetableInitialDelayMinutes))
    }

    private var actualEventsByID: [String: RailwayTimetable.SimulatedStationEvent] {
        Dictionary(
            (model.timetableSelection?.simulatedTrip.stationEvents ?? []).map { ($0.stationID, $0) },
            uniquingKeysWith: { first, _ in first }
        )
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("運転条件")
                            .font(.headline)
                        Picker("曜日", selection: $calendar) {
                            Text("平日").tag(RailwayTimetable.ServiceCalendar.weekday)
                            Text("土曜").tag(RailwayTimetable.ServiceCalendar.saturday)
                            Text("休日").tag(RailwayTimetable.ServiceCalendar.holiday)
                        }
                        .pickerStyle(.segmented)
                        Picker("時間帯", selection: $daypart) {
                            Text("朝ラッシュ").tag(RailwayTimetable.Daypart.morningRush)
                            Text("昼間").tag(RailwayTimetable.Daypart.daytime)
                            Text("夕方").tag(RailwayTimetable.Daypart.evening)
                            Text("夜間").tag(RailwayTimetable.Daypart.night)
                        }
                        .pickerStyle(.menu)
                        VStack(alignment: .leading, spacing: 5) {
                            HStack {
                                Text("初期遅延")
                                Spacer()
                                Text("\(Int(initialDelayMinutes)) 分")
                                    .monospacedDigit()
                                    .fontWeight(.bold)
                            }
                            Slider(value: $initialDelayMinutes, in: 0...30, step: 1)
                            Text("選択した架空列車の始発駅で遅延分だけ出発を待ち、到着時刻へ引き継ぎます。")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Button {
                            model.setTimetableOptions(
                                calendar: calendar,
                                daypart: daypart,
                                initialDelayMinutes: Int(initialDelayMinutes)
                            )
                        } label: {
                            Label("この条件を運転へ適用", systemImage: "checkmark.circle.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .padding(14)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))

                    if model.timetableSettingsPendingRestart {
                        Label("運転中の条件は変えていません。新しい時刻表は次のリセットから適用されます。", systemImage: "arrow.counterclockwise")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.orange)
                    }
                    if let error = model.timetableSelectionError {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .font(.subheadline)
                            .foregroundStyle(.orange)
                    }

                    if let selection = model.timetableSelection {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("選択列車")
                                .font(.headline)
                            Text("\(selection.plannedTrip.category.displayNameJa) · \(selection.plannedTrip.direction == .down ? "上り" : "下り") · \(selection.plannedTrip.tripID)")
                                .font(.subheadline.weight(.semibold))
                            Text("始発駅のゲーム内出発待ち: \(selection.routeOriginDelaySeconds) 秒")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                            Text("駅別時刻（予定 → 遅延シミュレーション）")
                                .font(.subheadline.weight(.semibold))
                            ForEach(Array(selection.plannedTrip.stationEvents.enumerated()), id: \.offset) { entry in
                                let event = entry.element
                                let actual = actualEventsByID[event.stationID]
                                HStack(alignment: .firstTextBaseline, spacing: 6) {
                                    Text(event.stationName)
                                        .lineLimit(1)
                                    Text(event.kind == .stop ? "停" : "通過")
                                        .font(.caption2.weight(.bold))
                                        .foregroundStyle(event.kind == .stop ? .cyan : .secondary)
                                    Spacer(minLength: 4)
                                    Text("\(RailwayTimetable.TimetableClock.display(event.arrivalSeconds)) → \(RailwayTimetable.TimetableClock.display(actual?.arrivalSeconds ?? event.arrivalSeconds))")
                                        .font(.caption.monospacedDigit())
                                        .foregroundStyle(.secondary)
                                }
                                .font(.caption)
                                if event.stationID != selection.plannedTrip.stationEvents.last?.stationID {
                                    Divider().opacity(0.45)
                                }
                            }
                        }
                        .padding(14)
                        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
                    }

                    Text("全駅・時刻・遅延・運転整理値は架空のPLACEHOLDERゲームデータです。実在の運行情報や運転指示ではありません。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 4)
                }
                .padding(16)
            }
            .navigationTitle("ダイヤ・遅延")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("閉じる") { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}
