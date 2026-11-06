import RealityKit

/// 灯具レンズと枠の配置。レンズは色付きメッシュのみで、照射光・点滅制御は未接続。
enum VehicleLightingBuilder {
    static func build(in group: Entity) {
        for side: Float in [-1, 1] {
            VehicleGeometryFactory.box("FrontHeadlampHousing_\(side)", size: SIMD3(0.34, 0.24, 0.13), at: SIMD3(side * 0.94, 2.05, -9.73), material: VehicleMaterialPalette.darkMetal, in: group)
            VehicleGeometryFactory.box("FrontHeadlampLens_\(side)", size: SIMD3(0.26, 0.16, 0.035), at: SIMD3(side * 0.94, 2.05, -9.81), material: VehicleMaterialPalette.lamp, in: group)
            VehicleGeometryFactory.box("FrontMarkerLamp_\(side)", size: SIMD3(0.20, 0.13, 0.04), at: SIMD3(side * 1.18, 3.18, -9.72), material: VehicleMaterialPalette.lamp, in: group)
            VehicleGeometryFactory.box("RearTailLamp_\(side)", size: SIMD3(0.26, 0.18, 0.035), at: SIMD3(side * 0.98, 2.02, 9.72), material: VehicleMaterialPalette.tailLamp, in: group)
        }
        VehicleGeometryFactory.box("FrontDestinationPanelTrim", size: SIMD3(1.02, 0.29, 0.07), at: SIMD3(0, 3.47, -9.70), material: VehicleMaterialPalette.darkMetal, in: group)
    }
}
