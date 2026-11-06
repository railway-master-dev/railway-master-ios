import SwiftUI

struct TrainPhysicsDetailsSheet: View {
    @ObservedObject var model: SimulatorModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("架空の走行モデル") {
                    metric("位置 / 速度", String(format: "%.1f m · %.1f km/h", model.trainPhysicsTelemetry.positionM, model.trainPhysicsTelemetry.speedKmh))
                    metric("牽引力", String(format: "%.1f kN", model.trainPhysicsTelemetry.tractionForceN / 1_000))
                    if let cruise = model.trainPhysicsTelemetry.controlIndicators.cruiseTargetKmh {
                        metric("定速", String(format: "%.0f km/h", cruise))
                    }
                    metric("カム進段", String(format: "%.0f %%", model.trainPhysicsTelemetry.controlIndicators.camProgress * 100))
                    metric("回生 / 空気ブレーキ", String(format: "%.1f / %.1f kN", model.trainPhysicsTelemetry.regenerativeBrakeForceN / 1_000, model.trainPhysicsTelemetry.frictionBrakeForceN / 1_000))
                    metric("電圧 / 電流", String(format: "%.0f V · %+.1f A", model.trainPhysicsTelemetry.lineVoltageV, model.trainPhysicsTelemetry.lineCurrentA))
                    metric("編成実効質量", String(format: "%.1f t", model.trainPhysicsTelemetry.effectiveMassKg / 1_000))
                    LabeledContent("滑走状態") {
                        Text(model.trainPhysicsTelemetry.wheelSlipActive ? "空転" : model.trainPhysicsTelemetry.brakeSlipActive ? "滑走" : "通常")
                            .foregroundStyle(model.trainPhysicsTelemetry.wheelSlipActive || model.trainPhysicsTelemetry.brakeSlipActive ? .orange : .green)
                    }
                    metric("粘着係数スケール", String(format: "牽引 %.2f · 制動 %.2f", model.trainPhysicsTelemetry.tractionAdhesionScale, model.trainPhysicsTelemetry.brakeAdhesionScale))
                }

                Section("編成別ブレーキ・熱") {
                    ForEach(model.trainPhysicsTelemetry.cars, id: \.identifier) { car in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(car.identifier)
                                .font(.headline)
                            metric("質量", String(format: "%.1f t / 乗客込み", car.loadedMassKg / 1_000))
                            metric("管圧 / シリンダ圧", String(format: "%.0f / %.0f kPa", car.brakePipePressureKPa, car.brakeCylinderPressureKPa))
                            metric("摩擦制動力", String(format: "%.1f kN", car.frictionBrakeForceN / 1_000))
                            metric("ブレーキ温度 / 効力", String(format: "%.1f °C · %.0f%%", car.brakeTemperatureC, car.brakeFadeFactor * 100))
                        }
                        .padding(.vertical, 4)
                    }
                }

                Section("停止距離のゲーム内試算") {
                    if let estimate = model.stoppingDistanceEstimate {
                        metric("距離 / 時間", String(format: "%.1f m · %.1f s", estimate.distanceM, estimate.durationSeconds))
                        Text(estimate.reachedRest ? "仮想モデル上で停止まで計算しました。" : "計算上限までに停止しませんでした。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("現在の速度・勾配・天候・制動状態から、停止距離をゲーム内試算できます。")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Button {
                        model.estimateFullServiceStoppingDistance()
                    } label: {
                        Label("常用最大制動で試算", systemImage: "brakesignal")
                    }
                    Text("これは架空物理による参考表示で、安全限界・制動曲線・実車の運転判断には使用できません。")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }

                Section("適用プロフィール") {
                    Text(model.selectedVehicleProfile.title)
                    Text("車両形式・性能・温度・圧力・電流はすべてオリジナルの架空ゲーム設定です。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("車両物理・編成状態")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("閉じる") { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private func metric(_ title: String, _ value: String) -> some View {
        LabeledContent(title, value: value)
            .font(.caption.monospacedDigit())
    }
}
