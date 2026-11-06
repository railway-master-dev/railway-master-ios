import SwiftUI

struct VehicleProfileSheet: View {
    @Environment(\.dismiss) private var dismiss
    let selected: FictionalVehicleProfile
    let onSelect: (FictionalVehicleProfile) -> Void

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Label {
                        Text("すべて架空のゲーム用プロファイルです。8両と10両は制御方式と編成長だけを参考にしたPLACEHOLDERで、東武50000系・西武2000系・西武4000系の公式諸元ではありません。")
                            .fixedSize(horizontal: false, vertical: true)
                    } icon: {
                        Image(systemName: "exclamationmark.triangle.fill")
                    }
                    .foregroundStyle(.orange)
                }
                ForEach(FictionalVehicleProfile.allCases) { profile in
                    Button {
                        onSelect(profile)
                        dismiss()
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: selected == profile ? "checkmark.circle.fill" : "tram.fill")
                                .font(.title3)
                                .foregroundStyle(selected == profile ? .cyan : .secondary)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(profile.title).font(.headline)
                                Text(profile.description)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text("音響: \(profile.soundProfile.displayName) · 引張力 \(Int(profile.makeParameters().maximumTractionForceN / 1_000)) kN · 出力 \(profile.makeParameters().maximumTractionPowerW / 1_000_000, specifier: "%.1f") MW")
                                    .font(.caption2.monospacedDigit())
                                    .foregroundStyle(.secondary)
                                Text("PHYSICS PLACEHOLDER · PROCEDURAL SOUND")
                                    .font(.system(size: 9, weight: .bold, design: .rounded))
                                    .foregroundStyle(.orange)
                            }
                            Spacer(minLength: 2)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selected == profile ? .isSelected : [])
                }
            }
            .navigationTitle("ゲーム車両プロファイル")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("閉じる") { dismiss() } }
            }
        }
    }
}
