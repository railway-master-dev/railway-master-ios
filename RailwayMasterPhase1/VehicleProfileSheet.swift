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

/// Attribution for the third-party models bundled with the app.
/// The two player-train exteriors are CC BY 4.0 works by
/// own.guest (Sketchfab), repainted into the fictional TOO
/// RAILWAY livery with the original operator marks removed; the
/// licence requires this credit to travel with the work.
struct CreditsSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("車両モデル") {
                    Text("プレイヤー車両の外観モデルは、own.guest 氏の作品を CC BY 4.0 ライセンスのもとで使用し、架空の東央電鉄カラーに改変したものです（原作の運営者ロゴ等は除去済み）。")
                        .font(.footnote)
                    Text("This work is based on \"JR東日本E231系電車\" (https://sketchfab.com/3d-models/jre231-98d47a9e4aca454d9c02eb2c690fdaee) by own.guest (https://sketchfab.com/own.guest) licensed under CC-BY-4.0 (http://creativecommons.org/licenses/by/4.0/)")
                        .font(.footnote)
                    Text("This work is based on \"117系 サンライナー | 117 series『Sun Liner』\" (https://sketchfab.com/3d-models/117-117-seriessun-liner-6434932c06974d10927c2fe36c2c7f8e) by own.guest (https://sketchfab.com/own.guest) licensed under CC-BY-4.0 (http://creativecommons.org/licenses/by/4.0/)")
                        .font(.footnote)
                }
            }
            .navigationTitle("クレジット")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("閉じる") { dismiss() } }
            }
        }
    }
}
