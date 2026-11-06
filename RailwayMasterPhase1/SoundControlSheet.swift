import SwiftUI
import RailwayAudioEnhancements

struct SoundControlSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var isEnabled: Bool
    @Binding var volume: Double
    @Binding var selectedProfile: RailwayTractionSoundProfile
    @Binding var announcementLocale: AnnouncementLocale

    let playShortHorn: () -> Void
    let playLongHorn: () -> Void
    let playBrakeAir: () -> Void
    let playDepartureChime: () -> Void
    let playDoorChime: () -> Void
    let announceNextStation: () -> Void
    let announceStop: () -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section("合成音響") {
                    Toggle("音声を有効にする", isOn: $isEnabled)
                    Picker("駆動音プロファイル", selection: $selectedProfile) {
                        ForEach(RailwayTractionSoundProfile.allCases, id: \.self) { profile in
                            Text(profile.displayName).tag(profile)
                        }
                    }
                    Picker("車内案内の言語", selection: $announcementLocale) {
                        Text("日本語").tag(AnnouncementLocale.japanese)
                        Text("英語（英国）").tag(AnnouncementLocale.english)
                    }
                    .disabled(!isEnabled)
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("出力音量")
                            Spacer()
                            Text("\(Int((volume * 100).rounded()))%")
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                        Slider(value: $volume, in: 0...1)
                            .disabled(!isEnabled)
                    }
                    Text("録音素材・BVE音源・実在の車両音・駅メロディは含みません。警笛、ATSブザー、ドア、踏切、ブレーキ、駆動、コンプレッサー、走行音は手続き合成のPLACEHOLDERです。日英の車内案内は固定時計イベントとiOS音声合成です。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Text("駆動方式プリセットは音色のゲーム用近似です。実車の音響測定・再現ではありません。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("試聴") {
                    Button(action: playShortHorn) { Label("警笛（短）", systemImage: "speaker.wave.2.fill") }
                    Button(action: playLongHorn) { Label("警笛（長）", systemImage: "speaker.wave.2.fill") }
                    Button(action: playBrakeAir) { Label("ブレーキ排気音", systemImage: "wind") }
                    Button(action: playDepartureChime) { Label("出発チャイム", systemImage: "music.note") }
                    Button(action: playDoorChime) { Label("ドア注意音", systemImage: "door.left.hand.open") }
                    Button(action: announceNextStation) { Label("次駅案内", systemImage: "megaphone.fill") }
                    Button(action: announceStop) { Label("停車案内", systemImage: "megaphone") }
                }
                .disabled(!isEnabled)

                Section {
                    Text("すべて架空のゲーム内設定です。実在する車両・駅・運転保安の音や手順を再現するものではありません。")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                }
            }
            .navigationTitle("サウンド")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("閉じる") { dismiss() }
                }
            }
            .preferredColorScheme(.dark)
        }
    }
}
