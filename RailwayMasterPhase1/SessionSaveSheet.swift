import SwiftUI
import RailwaySessionPersistence

struct SessionSaveSheet: View {
    @ObservedObject var model: SimulatorModel
    @Environment(\.dismiss) private var dismiss
    @State private var saveName = "手動保存"

    var body: some View {
        NavigationStack {
            List {
                Section("現在の運転") {
                    TextField("セーブ名", text: $saveName)
                        .textInputAutocapitalization(.never)
                    Button {
                        if model.saveGame(saveName: saveName) {
                            model.refreshSaveSlots()
                        }
                    } label: {
                        Label("現在の状態を保存", systemImage: "square.and.arrow.down")
                    }
                    .disabled(model.runPhase != .running)
                    LabeledContent("走行位置", value: "\(model.route.lineName) · \(Int(model.telemetry.positionM.rounded())) m")
                    Text("この端末内に保存します。物理状態、交通AI、ATS、時刻表、駅別採点、運転ログ、ゲームモードは引き継ぎます。保守・業務フローの別ゲーム進行は含まれません。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                if let notice = model.storageNotice, !notice.isEmpty {
                    Section("状態") {
                        Text(notice)
                            .font(.footnote)
                    }
                }

                Section("保存済み · \(model.saveSlots.count)") {
                    if model.saveSlots.isEmpty {
                        ContentUnavailableView("セーブはありません", systemImage: "tray", description: Text("現在の状態を保存すると、ここから再開できます。"))
                    } else {
                        ForEach(model.saveSlots) { slot in
                            Button {
                                if model.loadGame(slotID: slot.id) {
                                    dismiss()
                                }
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack {
                                        Text(slot.saveName).font(.headline)
                                        Spacer()
                                        Text("再開")
                                            .font(.caption.weight(.semibold))
                                            .foregroundStyle(.tint)
                                    }
                                    Text(slot.routeID)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                    Text("\(slot.vehicleProfileID) · 運転時間 \(Int(slot.simulationTimeSeconds / 60)) 分 · \(slot.savedAt.formatted(date: .numeric, time: .shortened))")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .navigationTitle("セーブ / 再開")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("閉じる") { dismiss() }
                }
            }
            .onAppear {
                model.prepareForSaveSheet()
                model.refreshSaveSlots()
            }
        }
    }
}
