import RealityKit

/// 屋根板・空調機と集電装置を別Entityグループとして構成する。
enum VehicleRoofEquipmentBuilder {
    static func buildRoof(in group: Entity) {
        VehicleGeometryFactory.box("RoofShell", size: SIMD3(2.62, 0.18, 19.05), at: SIMD3(0, 3.58, 0), material: VehicleMaterialPalette.body, in: group)
        let hvacPositions: [Float] = [-5.4, -2.7, 2.7, 5.4]
        for (index, z) in hvacPositions.enumerated() {
            VehicleGeometryFactory.box("HVACUnit_\(index)", size: SIMD3(1.45, 0.42, 1.72), at: SIMD3(0, 3.91, z), material: VehicleMaterialPalette.darkMetal, in: group)
            VehicleGeometryFactory.box("HVACGrille_\(index)", size: SIMD3(1.12, 0.035, 0.62), at: SIMD3(0, 4.14, z), material: VehicleMaterialPalette.trim, in: group)
        }
    }

    static func buildPantograph(in group: Entity) {
        let pivot = Entity()
        pivot.name = "PantographPivot"
        pivot.position = SIMD3(0, 3.72, 0)
        group.addChild(pivot)
        VehicleGeometryFactory.box("PantographInsulatorBase", size: SIMD3(0.88, 0.11, 1.05), at: SIMD3(0, 0.12, 0), material: VehicleMaterialPalette.warning, in: pivot)
        VehicleGeometryFactory.box("PantographLowerFrame", size: SIMD3(0.07, 1.08, 0.09), at: SIMD3(-0.32, 0.68, 0), material: VehicleMaterialPalette.darkMetal, in: pivot)
        VehicleGeometryFactory.box("PantographUpperFrame", size: SIMD3(0.07, 1.08, 0.09), at: SIMD3(0.32, 0.68, 0), material: VehicleMaterialPalette.darkMetal, in: pivot)
        VehicleGeometryFactory.box("PantographCollectorHead", size: SIMD3(1.42, 0.07, 0.12), at: SIMD3(0, 1.28, 0), material: VehicleMaterialPalette.trim, in: pivot)
        VehicleGeometryFactory.box("PantographContactStrip", size: SIMD3(1.18, 0.045, 0.08), at: SIMD3(0, 1.34, 0), material: VehicleMaterialPalette.darkMetal, in: pivot)
    }
}
