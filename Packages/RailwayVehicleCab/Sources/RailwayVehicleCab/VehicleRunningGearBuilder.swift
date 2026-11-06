import RealityKit

/// 台車枠、車輪、車軸、軸箱。左右車輪は車軸方向Xの円柱で簡易表現する。
enum VehicleRunningGearBuilder {
    static func build(in group: Entity) {
        let frame = VehicleMaterialPalette.darkMetal
        let wheel = VehicleMaterialPalette.rubber
        let steel = VehicleMaterialPalette.trim
        let bogieCenters: [Float] = [-6.25, 6.25]

        for (bogieIndex, centerZ) in bogieCenters.enumerated() {
            VehicleGeometryFactory.box("BogieFrame_\(bogieIndex)", size: SIMD3(2.12, 0.24, 3.15), at: SIMD3(0, 0.82, centerZ), material: frame, in: group)
            VehicleGeometryFactory.box("BogieCrossBeam_\(bogieIndex)", size: SIMD3(2.32, 0.20, 0.32), at: SIMD3(0, 0.96, centerZ), material: frame, in: group)
            for axleOffset: Float in [-1.05, 1.05] {
                let axleZ = centerZ + axleOffset
                VehicleGeometryFactory.cylinder("Axle_\(bogieIndex)_\(axleOffset)", radius: 0.105, length: 2.05, at: SIMD3(0, 0.43, axleZ), axis: SIMD3(1, 0, 0), material: steel, in: group)
                for side: Float in [-1, 1] {
                    VehicleGeometryFactory.cylinder("Wheel_\(bogieIndex)_\(axleOffset)_\(side)", radius: 0.43, length: 0.16, at: SIMD3(side * 1.02, 0.43, axleZ), axis: SIMD3(1, 0, 0), material: wheel, in: group)
                    VehicleGeometryFactory.cylinder("WheelHub_\(bogieIndex)_\(axleOffset)_\(side)", radius: 0.17, length: 0.18, at: SIMD3(side * 1.13, 0.43, axleZ), axis: SIMD3(1, 0, 0), material: steel, in: group)
                    VehicleGeometryFactory.box("AxleBox_\(bogieIndex)_\(axleOffset)_\(side)", size: SIMD3(0.30, 0.34, 0.36), at: SIMD3(side * 1.02, 0.78, axleZ), material: frame, in: group)
                }
            }
            VehicleGeometryFactory.box("PrimarySuspension_\(bogieIndex)", size: SIMD3(1.85, 0.24, 0.42), at: SIMD3(0, 1.00, centerZ), material: VehicleMaterialPalette.warning, in: group)
        }
    }
}

/// 主抵抗器・コンプレッサ・蓄電池箱など、名称のある外観用床下部品。
enum VehicleUnderfloorEquipmentBuilder {
    static func build(in group: Entity) {
        let dark = VehicleMaterialPalette.darkMetal
        let gray = VehicleMaterialPalette.trim
        let equipment: [(String, Float, Float, Float)] = [
            ("TractionInverter", -4.4, 0.68, 1.45),
            ("AuxiliaryPowerUnit", -1.9, 0.65, 1.10),
            ("AirCompressor", 0.7, 0.66, 0.92),
            ("BrakeResistor", 3.0, 0.70, 1.28),
            ("BatteryBox", 5.0, 0.70, 1.10)
        ]
        for (name, z, y, length) in equipment {
            VehicleGeometryFactory.box(name, size: SIMD3(1.12, 0.48, length), at: SIMD3(0, y, z), material: dark, in: group)
            VehicleGeometryFactory.box("\(name)_Cover", size: SIMD3(1.16, 0.06, length * 0.82), at: SIMD3(0, y + 0.27, z), material: gray, in: group)
        }
        for index in 0..<6 {
            let z = -4.7 + Float(index) * 1.72
            VehicleGeometryFactory.box("UnderframeCrossMember_\(index)", size: SIMD3(2.25, 0.12, 0.12), at: SIMD3(0, 0.88, z), material: dark, in: group)
        }
    }
}
