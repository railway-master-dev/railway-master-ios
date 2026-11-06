import RailwayAudioEnhancements
import RealityKit
import UIKit
import simd

enum VehicleCabBuilder {
    static func buildCab(in cab: Entity, instruments: Entity, desk: FictionalCabDesk = FictionalCabAndSoundCatalog.fieldChopper) -> [String: Entity] {
        // Driver-space coordinates remain in the same metre-scale car coordinate system.
        VehicleGeometry.box("CabFloor", size: SIMD3(2.48, 0.14, 3.00), at: SIMD3(0, 1.21, -8.10), material: VehicleMaterialPalette.interior, in: cab)
        VehicleGeometry.box("CabRearBulkhead", size: SIMD3(2.44, 2.18, 0.12), at: SIMD3(0, 2.22, -6.62), material: VehicleMaterialPalette.interior, in: cab)
        for side: Float in [-1, 1] {
            VehicleGeometry.box("CabSideLiner_\(Int(side))", size: SIMD3(0.08, 2.02, 2.66), at: SIMD3(side * 1.18, 2.24, -8.18), material: VehicleMaterialPalette.interior, in: cab)
            VehicleGeometry.box("CabGrabRail_\(Int(side))", size: SIMD3(0.035, 1.18, 0.035), at: SIMD3(side * 1.07, 2.27, -8.65), material: VehicleMaterialPalette.steel, in: cab)
            VehicleGeometry.box("CabSunshadeSideTrack_\(Int(side))", size: SIMD3(0.035, 0.035, 0.94), at: SIMD3(side * 1.11, 3.18, -9.05), material: VehicleMaterialPalette.darkSteel, in: cab)
        }
        VehicleGeometry.box("CabGlareShield", size: SIMD3(2.52, 0.16, 0.46), at: SIMD3(0, 2.46, -8.38), material: VehicleMaterialPalette.panel, in: cab)
        let deskMaterial = SimpleMaterial(color: UIColor(red: desk.deskRed, green: desk.deskGreen, blue: desk.deskBlue, alpha: 1), roughness: 0.7, isMetallic: false)
        VehicleGeometry.box("DashboardLowerHousing", size: SIMD3(2.38, 0.36, 0.53), at: SIMD3(0, 1.91, -8.39), material: deskMaterial, in: cab)
        VehicleGeometry.box("DashboardInstrumentFace", size: SIMD3(2.25, 0.58, 0.09), at: SIMD3(0, 2.24, -8.55), material: deskMaterial, in: cab)
        VehicleGeometry.box("ConsoleTop", size: SIMD3(2.36, 0.10, 0.72), at: SIMD3(0, 1.72, -8.34), material: deskMaterial, in: cab)
        VehicleGeometry.box("DriverSeatPedestal", size: SIMD3(0.48, 0.42, 0.48), at: SIMD3(0, 1.31, -7.42), material: VehicleMaterialPalette.darkSteel, in: cab)
        VehicleGeometry.box("DriverSeatCushion", size: SIMD3(0.61, 0.17, 0.58), at: SIMD3(0, 1.57, -7.42), material: VehicleMaterialPalette.seat, in: cab)
        VehicleGeometry.box("DriverSeatBack", size: SIMD3(0.62, 0.78, 0.16), at: SIMD3(0, 1.96, -7.67), material: VehicleMaterialPalette.seat, in: cab)
        VehicleGeometry.box("SeatHeadrest", size: SIMD3(0.42, 0.19, 0.16), at: SIMD3(0, 2.40, -7.67), material: VehicleMaterialPalette.seat, in: cab)
        VehicleGeometry.box("SeatLumbarTrim", size: SIMD3(0.48, 0.07, 0.18), at: SIMD3(0, 1.88, -7.77), material: VehicleMaterialPalette.bodyShade, in: cab)
        VehicleGeometry.cylinder("SeatHeightAdjuster", radius: 0.045, length: 0.43, at: SIMD3(-0.36, 1.52, -7.42), material: VehicleMaterialPalette.steel, in: cab)

        let speedNeedle = buildGauge(name: "Speedometer", center: SIMD3(-0.77, 2.24, -8.62), radius: desk.oneHandleMasterBrake ? 0.18 : 0.235, in: instruments)
        let pressureNeedle = buildGauge(name: "BrakePipeGauge", center: SIMD3(desk.oneHandleMasterBrake ? -0.38 : -0.20, 2.24, -8.62), radius: 0.16, in: instruments)
        if desk.analogGaugeCount >= 3 {
            _ = buildGauge(name: "SecondPressureGauge", center: SIMD3(0.08, 2.08, -8.62), radius: 0.13, in: instruments)
        }
        buildDisplayCluster(in: instruments, desk: desk)
        buildIndicatorRows(in: instruments, desk: desk)
        buildConsoleMarkings(in: instruments, desk: desk)
        return ["speed": speedNeedle, "pressure": pressureNeedle]
    }

    static func buildControls(in group: Entity, desk: FictionalCabDesk = FictionalCabAndSoundCatalog.fieldChopper) -> VehicleCabControlRig {
        let masterX: Float = desk.oneHandleMasterBrake ? -0.62 : -0.82
        let brakeX: Float = desk.oneHandleMasterBrake ? -0.62 : -0.40
        let positions: [CabControlKind: SIMD3<Float>] = [
            .masterController: SIMD3(masterX, 1.91, -8.02),
            .brakeLever: SIMD3(brakeX, 1.91, -8.02),
            .reverser: SIMD3(0.02, 1.91, -8.02),
            .hornButton: SIMD3(0.45, 1.90, -8.02),
            .wiperSwitch: SIMD3(0.78, 1.90, -8.02),
            .headlightSwitch: SIMD3(1.00, 1.90, -8.02),
            .interiorLightSwitch: SIMD3(0.90, 1.92, -8.42),
            .pantographSwitch: SIMD3(0.62, 1.92, -8.42),
            .mainCircuitBreaker: SIMD3(0.34, 1.92, -8.42),
            .doorCloseButton: SIMD3(0.05, 1.92, -8.42),
            .publicAddressSwitch: SIMD3(-0.22, 1.92, -8.42),
            .atsAcknowledgement: SIMD3(-0.48, 1.92, -8.42),
            .instrumentSelector: SIMD3(-0.75, 1.92, -8.42),
            .displaySelector: SIMD3(-0.98, 1.92, -8.42),
            .emergencyBrake: SIMD3(1.02, 1.89, -8.00)
        ]
        var nodes: [CabControlKind: ModelEntity] = [:]
        var ranges: [CabControlKind: CabControlRange] = [:]
        for kind in CabControlKind.allCases {
            guard let position = positions[kind] else { continue }
            let isButton = [.hornButton, .doorCloseButton, .atsAcknowledgement, .emergencyBrake].contains(kind)
            let isRotary = [.reverser, .wiperSwitch, .headlightSwitch, .interiorLightSwitch, .pantographSwitch, .mainCircuitBreaker, .publicAddressSwitch, .instrumentSelector, .displaySelector].contains(kind)
            let minValue: Float = kind == .reverser ? -1 : 0
            let maxValue: Float = (kind == .masterController ? 5 : kind == .brakeLever ? 8 : kind == .wiperSwitch ? 3 : 1)
            let range = CabControlRange(minimum: minValue, maximum: maxValue, neutral: 0, maximumTravelRadians: isRotary ? 0.72 : 0.60, rotates: !isButton)
            ranges[kind] = range
            let grip: any Material
            if kind == .masterController {
                switch desk.masterGrip {
                case .woodBrown:
                    grip = SimpleMaterial(color: UIColor(red: 0.45, green: 0.24, blue: 0.12, alpha: 1), roughness: 0.62, isMetallic: false)
                case .markedReverseAndOff:
                    grip = SimpleMaterial(color: UIColor(red: 0.62, green: 0.64, blue: 0.66, alpha: 1), roughness: 0.4, isMetallic: true)
                case .darkCombined:
                    grip = VehicleMaterialPalette.darkSteel
                }
            } else if kind == .brakeLever, desk.brakeGrip == .sphere {
                grip = VehicleMaterialPalette.steel
            } else if kind == .emergencyBrake {
                grip = VehicleMaterialPalette.redLamp
            } else {
                grip = VehicleMaterialPalette.steel
            }
            let material = grip
            VehicleGeometry.cylinder("\(kind.rawValue)_Pedestal", radius: isButton ? 0.075 : 0.095, length: 0.075, at: SIMD3(position.x, position.y - 0.12, position.z), material: VehicleMaterialPalette.darkSteel, in: group)
            let handle: ModelEntity
            if desk.oneHandleMasterBrake && kind == .brakeLever {
                handle = VehicleGeometry.cylinder("CabControl_CombinedBrakeCollar", radius: 0.07, length: 0.06, at: SIMD3(position.x, position.y + 0.08, position.z), material: material, in: group)
            } else if isButton || (kind == .brakeLever && desk.brakeGrip == .sphere) {
                let radius: Float = kind == .emergencyBrake ? 0.095 : (kind == .brakeLever ? 0.085 : 0.062)
                handle = VehicleGeometry.sphere("CabControl_\(kind.rawValue)", radius: radius, at: position, material: material, in: group)
            } else {
                let height: Float = (kind == .masterController || kind == .brakeLever) ? 0.39 : (isRotary ? 0.18 : 0.25)
                handle = VehicleGeometry.cylinder("CabControl_\(kind.rawValue)", radius: kind == .masterController || kind == .brakeLever ? 0.045 : 0.055, length: height, at: SIMD3(position.x, position.y + height * 0.34, position.z), material: material, in: group)
                if kind == .masterController || kind == .brakeLever {
                    VehicleGeometry.sphere("CabControl_\(kind.rawValue)_Grip", radius: 0.073, at: SIMD3(position.x, position.y + height * 0.72, position.z), material: material, in: group)
                }
            }
            if !range.rotates {
                handle.components[VehicleControlHomeComponent.self] = VehicleControlHomeComponent(homeY: handle.position.y)
            }
            handle.components[CabControlComponent.self] = CabControlComponent(kind: kind, minimumValue: minValue, maximumValue: maxValue, neutralValue: 0)
            nodes[kind] = handle
        }
        return VehicleCabControlRig(nodes: nodes, ranges: ranges)
    }

    private static func buildGauge(name: String, center: SIMD3<Float>, radius: Float, in group: Entity) -> Entity {
        VehicleGeometry.cylinder("\(name)_Bezel", radius: radius, length: 0.045, at: center, axis: SIMD3(0, 0, 1), material: VehicleMaterialPalette.steel, in: group)
        VehicleGeometry.cylinder("\(name)_Face", radius: radius * 0.86, length: 0.020, at: SIMD3(center.x, center.y, center.z - 0.030), axis: SIMD3(0, 0, 1), material: VehicleMaterialPalette.interior, in: group)
        for tick in 0..<13 {
            let theta = Float(tick) / 12 * .pi * 1.5 - .pi * 0.75
            let x = center.x + cos(theta) * radius * 0.68
            let y = center.y + sin(theta) * radius * 0.68
            VehicleGeometry.box("\(name)_ScaleTick_\(tick)", size: SIMD3(0.025, 0.008, 0.012), at: SIMD3(x, y, center.z - 0.046), material: VehicleMaterialPalette.markings, in: group)
        }
        let pivot = Entity()
        pivot.name = "GaugeNeedle_\(name)"
        pivot.position = SIMD3(center.x, center.y, center.z - 0.055)
        group.addChild(pivot)
        VehicleGeometry.box("\(name)_Needle", size: SIMD3(0.014, radius * 0.68, 0.012), at: SIMD3(0, radius * 0.30, 0), material: VehicleMaterialPalette.amber, in: pivot)
        VehicleGeometry.sphere("\(name)_NeedleHub", radius: 0.032, at: SIMD3(0, 0, -0.004), material: VehicleMaterialPalette.steel, in: pivot)
        return pivot
    }

    private static func buildDisplayCluster(in group: Entity, desk: FictionalCabDesk) {
        let plan = FictionalCabAndSoundCatalog.generationPlan(for: desk.family)
        if plan.monitorNames.contains("CenterMonitor") {
            VehicleGeometry.box("CenterMonitor", size: SIMD3(0.42, 0.28, 0.04), at: SIMD3(0.05, 2.28, -8.64), material: VehicleMaterialPalette.display, in: group)
            VehicleGeometry.box("DigitalDisplayBezel", size: SIMD3(0.50, 0.34, 0.05), at: SIMD3(0.05, 2.28, -8.61), material: VehicleMaterialPalette.darkSteel, in: group)
            for row in 0..<3 {
                VehicleGeometry.box("DisplayStatusBar_\(row)", size: SIMD3(0.28, 0.016, 0.008), at: SIMD3(0.05, 2.36 - Float(row) * 0.06, -8.665), material: VehicleMaterialPalette.display, in: group)
            }
        }
        if plan.monitorNames.contains("RightStatusScreen") {
            VehicleGeometry.box("RightStatusScreen", size: SIMD3(0.32, 0.24, 0.04), at: SIMD3(0.72, 2.22, -8.64), material: VehicleMaterialPalette.display, in: group)
        }
        if plan.monitorNames.contains("RightKeypad") {
            VehicleGeometry.box("RightKeypad", size: SIMD3(0.24, 0.18, 0.04), at: SIMD3(0.86, 2.02, -8.58), material: VehicleMaterialPalette.darkSteel, in: group)
            for column in 0..<3 {
                for row in 0..<3 {
                    VehicleGeometry.box("KeypadKey_\(column)_\(row)", size: SIMD3(0.045, 0.035, 0.012), at: SIMD3(0.78 + Float(column) * 0.07, 1.96 + Float(row) * 0.05, -8.61), material: VehicleMaterialPalette.panel, in: group)
                }
            }
        }
        if plan.monitorNames.contains("Handset") {
            VehicleGeometry.box("RightHandset", size: SIMD3(0.08, 0.20, 0.05), at: SIMD3(1.08, 1.95, -8.15), material: VehicleMaterialPalette.darkSteel, in: group)
        }
        if desk.centerSwitchBank {
            VehicleGeometry.box("CenterSwitchBank", size: SIMD3(0.62, 0.18, 0.04), at: SIMD3(0.22, 1.98, -8.22), material: VehicleMaterialPalette.panel, in: group)
            for index in 0..<5 {
                VehicleGeometry.box("CenterSwitch_\(index)", size: SIMD3(0.06, 0.08, 0.02), at: SIMD3(-0.02 + Float(index) * 0.12, 2.02, -8.25), material: index == 2 ? VehicleMaterialPalette.amber : VehicleMaterialPalette.steel, in: group)
            }
        }
        if let door = desk.doorLampCaption {
            VehicleGeometry.box("DoorClosedLamp_\(door)", size: SIMD3(0.09, 0.05, 0.02), at: SIMD3(-1.02, 2.42, -8.62), material: VehicleMaterialPalette.amber, in: group)
        }
        if let caption = desk.dashboardCaption {
            VehicleGeometry.box("DashboardCaption_\(caption)", size: SIMD3(0.16, 0.06, 0.02), at: SIMD3(0.55, 2.42, -8.62), material: VehicleMaterialPalette.display, in: group)
        }
        VehicleGeometry.box("FictionalCarNumberPlate_\(desk.fictionalCarNumber)", size: SIMD3(0.20, 0.07, 0.016), at: SIMD3(0.42, 2.52, -8.64), material: VehicleMaterialPalette.markings, in: group)
        for (index, mark) in desk.masterMarkings.enumerated() {
            VehicleGeometry.box("MasterMark_\(mark)", size: SIMD3(0.05, 0.035, 0.012), at: SIMD3(-0.95 + Float(index) * 0.08, 1.78, -8.08), material: VehicleMaterialPalette.markings, in: group)
        }
        if desk.blueSwitchLabels {
            let blue = SimpleMaterial(color: UIColor(red: 0.20, green: 0.38, blue: 0.72, alpha: 1), roughness: 0.45, isMetallic: false)
            VehicleGeometry.box("BlueLabelStrip", size: SIMD3(0.72, 0.028, 0.016), at: SIMD3(0.15, 1.86, -8.18), material: blue, in: group)
        }
    }

    private static func buildIndicatorRows(in group: Entity, desk: FictionalCabDesk) {
        let plan = FictionalCabAndSoundCatalog.generationPlan(for: desk.family)
        if plan.includesSeriesParallelFinalLamps {
            for (index, name) in plan.lampNames.enumerated() {
                let y = 2.34 - Float(index) * 0.07
                VehicleGeometry.box("ChopperLamp_\(name)", size: SIMD3(0.045, 0.05, 0.016), at: SIMD3(-0.08, y, -8.63), material: VehicleMaterialPalette.amber, in: group)
            }
        } else if desk.hasCenterMonitor {
            let labels = ["ATSP", "ATC", "EB", "DOOR", "POWER", "REGEN", "FAULT"]
            for (index, label) in labels.enumerated() {
                let x = -1.05 + Float(index) * 0.30
                VehicleGeometry.box("IndicatorLens_\(label)", size: SIMD3(0.07, 0.04, 0.016), at: SIMD3(x, 2.58, -8.63), material: label == "FAULT" ? VehicleMaterialPalette.redLamp : VehicleMaterialPalette.display, in: group)
            }
        }
        let pressureNames = ["MR", "BP", "BC"].prefix(desk.analogGaugeCount)
        for (index, name) in pressureNames.enumerated() {
            let x = -0.55 + Float(index) * 0.22
            VehicleGeometry.cylinder("PressureGauge_\(name)_Bezel", radius: 0.05, length: 0.02, at: SIMD3(x, 1.98, -8.58), axis: SIMD3(0, 0, 1), material: VehicleMaterialPalette.steel, in: group)
            VehicleGeometry.cylinder("PressureGauge_\(name)_Face", radius: 0.036, length: 0.01, at: SIMD3(x, 1.98, -8.596), axis: SIMD3(0, 0, 1), material: VehicleMaterialPalette.display, in: group)
        }
    }

    private static func buildConsoleMarkings(in group: Entity, desk: FictionalCabDesk) {
        let slots = desk.oneHandleMasterBrake ? 6 : 11
        for index in 0..<slots {
            let x = (desk.oneHandleMasterBrake ? -0.78 : -0.96) + Float(index) * (desk.oneHandleMasterBrake ? 0.08 : 0.19)
            VehicleGeometry.box("ConsoleDetent_\(index)", size: SIMD3(0.016, 0.014, 0.016), at: SIMD3(x, 1.78, -8.05), material: VehicleMaterialPalette.markings, in: group)
        }
        for index in 0..<6 {
            let x = 0.22 + Float(index) * 0.13
            VehicleGeometry.sphere("ConsolePushbutton_\(index)", radius: 0.036, at: SIMD3(x, 1.81, -8.28), material: index == 5 ? VehicleMaterialPalette.amber : VehicleMaterialPalette.steel, in: group)
        }
    }
}

public struct CabControlComponent: Component {
    public var kind: CabControlKind
    public var minimumValue: Float
    public var maximumValue: Float
    public var neutralValue: Float

    public init(kind: CabControlKind, minimumValue: Float, maximumValue: Float, neutralValue: Float) {
        self.kind = kind
        self.minimumValue = minimumValue
        self.maximumValue = maximumValue
        self.neutralValue = neutralValue
    }
}
