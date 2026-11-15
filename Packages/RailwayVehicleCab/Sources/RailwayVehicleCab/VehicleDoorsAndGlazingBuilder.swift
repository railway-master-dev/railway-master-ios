import RealityKit

/// ドアと窓を別Entityグループへ作成し、車種差分で個別に差し替えられるようにする。
enum VehicleDoorsAndGlazingBuilder {
    static func buildDoors(in group: Entity) {
        let doorCenters: [Float] = [-7.1, -2.37, 2.37, 7.1]
        for side: Float in [-1, 1] {
            for (index, z) in doorCenters.enumerated() {
                VehicleGeometryFactory.box("SlidingDoor_\(index)_\(side)", size: SIMD3(0.055, 1.40, 1.38), at: SIMD3(side * 1.414, 2.38, z), material: VehicleMaterialPalette.body, in: group)
                VehicleGeometryFactory.box("DoorCenterSeam_\(index)_\(side)", size: SIMD3(0.018, 0.025, 1.34), at: SIMD3(side * 1.45, 2.38, z), material: VehicleMaterialPalette.trim, in: group)
                VehicleGeometryFactory.box("DoorStep_\(index)_\(side)", size: SIMD3(0.34, 0.07, 1.28), at: SIMD3(side * 1.48, 1.64, z), material: VehicleMaterialPalette.darkMetal, in: group)
            }
        }
    }

    static func buildGlazing(in group: Entity) {
        let glass = VehicleMaterialPalette.glass
        let windowCenters: [Float] = [-8.35, -5.55, -3.45, -1.1, 1.1, 3.45, 5.55, 8.35]
        let doorCenters: [Float] = [-7.1, -2.37, 2.37, 7.1]

        for side: Float in [-1, 1] {
            for (index, z) in doorCenters.enumerated() {
                VehicleGeometryFactory.box("DoorWindow_\(index)_\(side)", size: SIMD3(0.035, 0.59, 0.56), at: SIMD3(side * 1.449, 2.60, z), material: glass, in: group)
            }
            for (index, z) in windowCenters.enumerated() {
                VehicleGeometryFactory.box("PassengerWindow_\(index)_\(side)", size: SIMD3(0.035, 0.79, 0.98), at: SIMD3(side * 1.412, 2.68, z), material: glass, in: group)
                VehicleGeometryFactory.box("WindowLowerRail_\(index)_\(side)", size: SIMD3(0.02, 0.035, 1.00), at: SIMD3(side * 1.435, 2.27, z), material: VehicleMaterialPalette.trim, in: group)
            }
        }

        for index in 0..<2 {
            let x: Float = index == 0 ? -0.60 : 0.60
            // batch45 (2026-11-14, cab photo verdict): the panes
            // were 0.72 tall at y 2.98 (band 2.62..3.34), leaving
            // the front face open from the fascia (top 1.67) to
            // 2.62 — through that slot the driver saw the front
            // gangway and the headlamp housings instead of glass.
            // The panes are now 1.00 tall at y 2.80 (band
            // 2.30..3.30), meeting the new lower panel, so the
            // windshield covers the full view band like the real
            // E231's two front windows.
            // batch46 (2026-11-14, user: 「全然視野が広くない」):
            // the band grows downward to 2.05 — panes 1.25 tall
            // at y 2.675, meeting the lowered cab panel — so the
            // glass share of the cab frame's centre column rises
            // from 0.44 to 0.61 (projection model in the batch46
            // report). The centre pillar gap (0.10 m between the
            // panes) and the top edge stay as they were.
            VehicleGeometryFactory.box("FrontWindshield_\(index)", size: SIMD3(1.10, 1.25, 0.035), at: SIMD3(x, 2.675, -9.715), material: VehicleMaterialPalette.cabGlass, in: group)
            VehicleGeometryFactory.box("RearWindow_\(index)", size: SIMD3(1.10, 0.72, 0.035), at: SIMD3(x, 2.98, 9.715), material: glass, in: group)
        }
        VehicleGeometryFactory.box("DestinationDisplay", size: SIMD3(0.90, 0.20, 0.04), at: SIMD3(0, 3.47, -9.72), material: VehicleMaterialPalette.darkMetal, in: group)
    }
}
