import RealityKit
import simd

/// 車体外板と基本床。ドア・ガラス・灯具は別の交換可能なグループで構成する。
enum VehicleBodyBuilder {
    static func build(in group: Entity) {
        let metal = VehicleMaterialPalette.body
        let accent = VehicleMaterialPalette.accent
        let dark = VehicleMaterialPalette.darkMetal

        VehicleGeometryFactory.box("UnderframeDeck", size: SIMD3(2.56, 0.24, 19.2), at: SIMD3(0, 1.08, 0), material: dark, in: group)
        VehicleGeometryFactory.box("PassengerFloor", size: SIMD3(2.48, 0.12, 18.9), at: SIMD3(0, 1.29, 0), material: metal, in: group)

        // 両側の外板。窓やドアは上に重ねる独立部品とし、低コストの試作形状とする。
        for side: Float in [-1, 1] {
            VehicleGeometryFactory.box("SideShell_\(side)", size: SIMD3(0.09, 1.98, 18.95), at: SIMD3(side * 1.355, 2.48, 0), material: metal, in: group)
            VehicleGeometryFactory.box("LowerAccent_\(side)", size: SIMD3(0.035, 0.16, 18.9), at: SIMD3(side * 1.405, 1.62, 0), material: accent, in: group)
            VehicleGeometryFactory.box("RoofLineTrim_\(side)", size: SIMD3(0.035, 0.07, 18.85), at: SIMD3(side * 1.405, 3.42, 0), material: accent, in: group)
        }

        // Z負側が運転台側。前面はガラス開口を残し、運転台カメラの視界を遮らない。
        VehicleGeometryFactory.box("FrontCabLeftPillar", size: SIMD3(0.22, 1.16, 0.12), at: SIMD3(-1.24, 2.91, -9.64), material: metal, in: group)
        VehicleGeometryFactory.box("FrontCabRightPillar", size: SIMD3(0.22, 1.16, 0.12), at: SIMD3(1.24, 2.91, -9.64), material: metal, in: group)
        VehicleGeometryFactory.box("FrontCabHeader", size: SIMD3(2.70, 0.38, 0.12), at: SIMD3(0, 3.42, -9.64), material: metal, in: group)
        VehicleGeometryFactory.box("FrontCabCenterPillar", size: SIMD3(0.10, 0.82, 0.12), at: SIMD3(0, 2.91, -9.64), material: metal, in: group)
        VehicleGeometryFactory.box("FrontLowerFascia", size: SIMD3(2.72, 0.48, 0.16), at: SIMD3(0, 1.43, -9.69), material: accent, in: group)
        VehicleGeometryFactory.box("RearEndFace", size: SIMD3(2.70, 2.18, 0.12), at: SIMD3(0, 2.43, 9.64), material: metal, in: group)
        VehicleGeometryFactory.box("RearLowerFascia", size: SIMD3(2.72, 0.48, 0.16), at: SIMD3(0, 1.43, 9.69), material: accent, in: group)

        // 前後の貫通幌・連結器の基本形状。
        VehicleGeometryFactory.box("FrontCoupler", size: SIMD3(0.34, 0.24, 0.42), at: SIMD3(0, 0.78, -9.82), material: dark, in: group)
        VehicleGeometryFactory.box("RearCoupler", size: SIMD3(0.34, 0.24, 0.42), at: SIMD3(0, 0.78, 9.82), material: dark, in: group)
        VehicleGeometryFactory.box("FrontGangway", size: SIMD3(0.82, 1.65, 0.10), at: SIMD3(0, 2.05, -9.73), material: dark, in: group)
        VehicleGeometryFactory.box("RearGangway", size: SIMD3(0.82, 1.65, 0.10), at: SIMD3(0, 2.05, 9.73), material: dark, in: group)
    }
}
