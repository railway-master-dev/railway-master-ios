import RailwayAudioEnhancements
import RealityKit
import UIKit

/// 前面窓の後ろに置く簡易運転台。内装とコントロールを別の親Entityへ組み立てる。
/// 机の色とレバー配置は架空の手続き形状で、参考写真のテクスチャではない。
enum VehicleCabInteriorBuilder {
    static func build(
        interior: Entity,
        controls: Entity,
        desk: FictionalCabDesk = FictionalCabAndSoundCatalog.fieldChopper
    ) -> VehicleCabControlRig {
        let dark = deskPaint(desk)
        let trim = VehicleMaterialPalette.darkMetal
        let seat = VehicleMaterialPalette.seat
        VehicleGeometryFactory.box("CabDashboard", size: SIMD3(2.24, 0.28, 0.78), at: SIMD3(0, 1.72, -8.28), material: dark, in: interior)
        VehicleGeometryFactory.box("CabConsole", size: SIMD3(2.05, 0.16, 0.42), at: SIMD3(0, 1.92, -8.36), material: trim, in: interior)
        VehicleGeometryFactory.box("DriverSeatBase", size: SIMD3(0.48, 0.42, 0.48), at: SIMD3(0, 1.15, -7.45), material: trim, in: interior)
        VehicleGeometryFactory.box("DriverSeatCushion", size: SIMD3(0.62, 0.18, 0.58), at: SIMD3(0, 1.46, -7.45), material: seat, in: interior)
        VehicleGeometryFactory.box("DriverSeatBack", size: SIMD3(0.62, 0.78, 0.16), at: SIMD3(0, 1.88, -7.70), material: seat, in: interior)

        if desk.hasCenterMonitor {
            VehicleGeometryFactory.box("InstrumentDisplayFrame", size: SIMD3(0.78, 0.42, 0.08), at: SIMD3(-0.66, 2.14, -8.31), material: trim, in: interior)
            VehicleGeometryFactory.box("InstrumentDisplayGlass", size: SIMD3(0.68, 0.31, 0.035), at: SIMD3(-0.66, 2.15, -8.36), material: VehicleMaterialPalette.glass, in: interior)
        }
        VehicleGeometryFactory.box("SwitchPanel", size: SIMD3(0.52, 0.23, 0.10), at: SIMD3(0.76, 2.12, -8.32), material: trim, in: interior)

        var nodes: [VehicleCabControlKind: ModelEntity] = [:]
        let masterX: Float = desk.oneHandleMasterBrake ? -0.55 : -0.78
        let brakeX: Float = desk.oneHandleMasterBrake ? -0.55 : -0.28
        let grip = gripPaint(desk.masterGrip)
        nodes[.masterController] = makeControl(kind: .masterController, name: "MasterControllerHandle", size: SIMD3(0.10, 0.48, 0.10), at: SIMD3(masterX, 2.17, -8.02), minimum: 0, maximum: 5, neutral: 0, axis: SIMD3(0, 0, 1), scale: 0.12, in: controls, tint: grip)
        if desk.oneHandleMasterBrake {
            nodes[.brakeLever] = makeControl(kind: .brakeLever, name: "CombinedBrakeCollar", size: SIMD3(0.14, 0.06, 0.14), at: SIMD3(masterX, 2.02, -8.02), minimum: 0, maximum: 1, neutral: 0, axis: SIMD3(0, 0, 1), scale: 0.2, in: controls, tint: grip)
        } else if desk.brakeGrip == .sphere {
            nodes[.brakeLever] = makeSphereControl(kind: .brakeLever, name: "BrakeLeverHandle", at: SIMD3(brakeX, 2.10, -8.02), in: controls)
        } else {
            nodes[.brakeLever] = makeControl(kind: .brakeLever, name: "BrakeLeverHandle", size: SIMD3(0.08, 0.22, 0.08), at: SIMD3(brakeX, 2.05, -8.02), minimum: 0, maximum: 1, neutral: 0, axis: SIMD3(0, 0, 1), scale: 0.35, in: controls, tint: grip)
        }
        appendDeskFurniture(desk, in: interior)
        nodes[.reverser] = makeControl(kind: .reverser, name: "ReverserKey", size: SIMD3(0.11, 0.19, 0.11), at: SIMD3(0.25, 2.15, -8.03), minimum: -1, maximum: 1, neutral: 0, axis: SIMD3(0, 1, 0), scale: 0.55, in: controls)
        nodes[.hornButton] = makeControl(kind: .hornButton, name: "HornButton", size: SIMD3(0.13, 0.10, 0.13), at: SIMD3(0.56, 2.15, -8.03), minimum: 0, maximum: 1, neutral: 0, axis: SIMD3(0, -1, 0), scale: 0.045, in: controls, motion: .translation)
        nodes[.wiperSwitch] = makeControl(kind: .wiperSwitch, name: "WiperSwitch", size: SIMD3(0.09, 0.16, 0.09), at: SIMD3(0.82, 2.15, -8.03), minimum: 0, maximum: 3, neutral: 0, axis: SIMD3(0, 1, 0), scale: 0.20, in: controls)
        nodes[.headlightSwitch] = makeControl(kind: .headlightSwitch, name: "HeadlightSwitch", size: SIMD3(0.09, 0.16, 0.09), at: SIMD3(0.98, 2.15, -8.03), minimum: 0, maximum: 1, neutral: 0, axis: SIMD3(0, 1, 0), scale: 0.32, in: controls)
        return VehicleCabControlRig(nodes: nodes)
    }

    private static func makeControl(
        kind: VehicleCabControlKind,
        name: String,
        size: SIMD3<Float>,
        at position: SIMD3<Float>,
        minimum: Float,
        maximum: Float,
        neutral: Float,
        axis: SIMD3<Float>,
        scale: Float,
        in parent: Entity,
        motion: VehicleCabControlMotion = .rotation,
        tint: SimpleMaterial? = nil
    ) -> ModelEntity {
        VehicleGeometryFactory.cylinder("\(name)_Pedestal", radius: 0.10, length: 0.08, at: SIMD3(position.x, position.y - 0.14, position.z), material: VehicleMaterialPalette.darkMetal, in: parent)
        let entity = VehicleGeometryFactory.box(name, size: size, at: position, material: tint ?? VehicleMaterialPalette.warning, in: parent)
        entity.components[VehicleCabControlComponent.self] = VehicleCabControlComponent(
            kind: kind, motion: motion, axis: axis,
            minimumValue: minimum, maximumValue: maximum, neutralValue: neutral,
            motionScale: scale, value: neutral
        )
        return entity
    }

    private static func makeSphereControl(kind: VehicleCabControlKind, name: String, at position: SIMD3<Float>, in parent: Entity) -> ModelEntity {
        VehicleGeometryFactory.cylinder("\(name)_Pedestal", radius: 0.11, length: 0.06, at: SIMD3(position.x, position.y - 0.08, position.z), material: VehicleMaterialPalette.darkMetal, in: parent)
        let entity = VehicleGeometryFactory.sphere(name, radius: 0.09, at: position, material: VehicleMaterialPalette.darkMetal, in: parent)
        entity.components[VehicleCabControlComponent.self] = VehicleCabControlComponent(
            kind: kind, motion: .rotation, axis: SIMD3(0, 0, 1),
            minimumValue: 0, maximumValue: 8, neutralValue: 0, motionScale: 0.08, value: 0
        )
        return entity
    }

    private static func appendDeskFurniture(_ desk: FictionalCabDesk, in interior: Entity) {
        let bezel = VehicleMaterialPalette.darkMetal
        let glass = VehicleMaterialPalette.glass
        let blue = VehicleMaterialPalette.paint(UIColor(red: 0.20, green: 0.38, blue: 0.72, alpha: 1), roughness: 0.45)
        let amber = VehicleMaterialPalette.warning
        if desk.analogGaugeCount >= 2 {
            VehicleGeometryFactory.cylinder("DeskSpeedGauge", radius: 0.11, length: 0.04, at: SIMD3(-0.72, 2.16, -8.34), axis: SIMD3(0, 0, 1), material: bezel, in: interior)
            VehicleGeometryFactory.cylinder("DeskPressureGauge", radius: 0.09, length: 0.04, at: SIMD3(-0.46, 2.10, -8.34), axis: SIMD3(0, 0, 1), material: bezel, in: interior)
        }
        if desk.analogGaugeCount >= 3 {
            VehicleGeometryFactory.cylinder("DeskSecondPressureGauge", radius: 0.09, length: 0.04, at: SIMD3(-0.24, 2.10, -8.34), axis: SIMD3(0, 0, 1), material: bezel, in: interior)
        }
        if desk.hasCenterMonitor {
            VehicleGeometryFactory.box("CenterMonitor", size: SIMD3(0.34, 0.24, 0.04), at: SIMD3(0.05, 2.16, -8.36), material: glass, in: interior)
        }
        if desk.hasRightStatusScreen {
            VehicleGeometryFactory.box("RightStatusScreen", size: SIMD3(0.32, 0.22, 0.04), at: SIMD3(0.72, 2.16, -8.36), material: glass, in: interior)
        }
        if desk.hasRightKeypad {
            VehicleGeometryFactory.box("RightKeypad", size: SIMD3(0.22, 0.16, 0.04), at: SIMD3(0.95, 2.08, -8.34), material: bezel, in: interior)
        }
        if desk.hasRightHandset {
            VehicleGeometryFactory.box("RightHandset", size: SIMD3(0.08, 0.18, 0.05), at: SIMD3(1.05, 1.95, -8.10), material: bezel, in: interior)
        }
        let plan = FictionalCabAndSoundCatalog.generationPlan(for: desk.family)
        if plan.includesSeriesParallelFinalLamps {
            for (index, name) in plan.lampNames.enumerated() {
                VehicleGeometryFactory.box("ChopperLamp_\(name)", size: SIMD3(0.04, 0.055, 0.018), at: SIMD3(-0.02, 2.30 - Float(index) * 0.06, -8.36), material: amber, in: interior)
            }
        }
        if desk.centerSwitchBank {
            VehicleGeometryFactory.box("CenterSwitchBank", size: SIMD3(0.55, 0.16, 0.04), at: SIMD3(0.15, 1.98, -8.20), material: deskPaint(desk), in: interior)
        }
        if desk.blueSwitchLabels {
            VehicleGeometryFactory.box("BlueLabelStrip", size: SIMD3(0.7, 0.03, 0.02), at: SIMD3(0.2, 1.90, -8.18), material: blue, in: interior)
        }
        if let door = desk.doorLampCaption {
            VehicleGeometryFactory.box("DoorClosedLamp_\(door)", size: SIMD3(0.07, 0.04, 0.02), at: SIMD3(-0.95, 2.28, -8.36), material: amber, in: interior)
        }
        if let caption = desk.dashboardCaption {
            VehicleGeometryFactory.box("DashboardCaption_\(caption)", size: SIMD3(0.14, 0.05, 0.016), at: SIMD3(0.48, 2.28, -8.36), material: glass, in: interior)
        }
        for (index, mark) in desk.masterMarkings.enumerated() {
            VehicleGeometryFactory.box("MasterMark_\(mark)", size: SIMD3(0.045, 0.03, 0.012), at: SIMD3(-0.92 + Float(index) * 0.07, 1.84, -8.05), material: VehicleMaterialPalette.trim, in: interior)
        }
        VehicleGeometryFactory.box("FictionalCarNumberPlate_\(desk.fictionalCarNumber)", size: SIMD3(0.16, 0.06, 0.015), at: SIMD3(0.35, 2.30, -8.37), material: VehicleMaterialPalette.trim, in: interior)
    }

    private static func deskPaint(_ desk: FictionalCabDesk) -> SimpleMaterial {
        VehicleMaterialPalette.paint(UIColor(red: desk.deskRed, green: desk.deskGreen, blue: desk.deskBlue, alpha: 1), roughness: 0.72)
    }

    private static func gripPaint(_ grip: FictionalMasterGrip) -> SimpleMaterial {
        switch grip {
        case .darkCombined:
            return VehicleMaterialPalette.darkMetal
        case .woodBrown:
            return VehicleMaterialPalette.paint(UIColor(red: 0.45, green: 0.24, blue: 0.12, alpha: 1), roughness: 0.62)
        case .markedReverseAndOff:
            return VehicleMaterialPalette.paint(UIColor(red: 0.62, green: 0.64, blue: 0.66, alpha: 1), roughness: 0.4, metallic: true)
        }
    }
}
