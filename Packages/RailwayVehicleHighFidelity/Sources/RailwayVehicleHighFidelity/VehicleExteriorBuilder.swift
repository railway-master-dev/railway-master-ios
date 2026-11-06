import RealityKit
import simd

struct DoorLeafHandle {
    let entity: Entity
    let direction: Float
    let closedZ: Float
}

struct WheelHandle {
    let entity: Entity
    let radius: Float
    let baseOrientation: simd_quatf
}

struct BogieHandle {
    let entity: Entity
}

struct BogieBuildResult {
    let wheels: [WheelHandle]
    let bogies: [BogieHandle]
}

struct WiperHandle {
    let pivot: Entity
    let side: Float
}

struct PantographHandle {
    let movingAssembly: Entity
    let baseY: Float
}

enum VehicleExteriorBuilder {
    static let doorCenters: [Float] = [-7.1, -2.37, 2.37, 7.1]
    static let windowCenters: [Float] = [-8.55, -5.65, -3.55, -1.0, 1.0, 3.55, 5.65, 8.55]

    static func buildBody(in group: Entity) {
        let steel = VehicleMaterialPalette.undercoat
        VehicleGeometry.box("ContinuousUnderframe", size: SIMD3(2.62, 0.22, 19.15), at: SIMD3(0, 1.02, 0), material: steel, in: group)
        VehicleGeometry.box("PassengerFloorSlab", size: SIMD3(2.56, 0.11, 18.85), at: SIMD3(0, 1.22, 0), material: VehicleMaterialPalette.bodyShade, in: group)
        VehicleGeometry.box("RoofCrown", size: SIMD3(2.56, 0.18, 18.98), at: SIMD3(0, 3.48, 0), material: VehicleMaterialPalette.roof, in: group)
        VehicleGeometry.box("RoofDripRailLeft", size: SIMD3(0.055, 0.045, 18.86), at: SIMD3(-1.39, 3.36, 0), material: VehicleMaterialPalette.steel, in: group)
        VehicleGeometry.box("RoofDripRailRight", size: SIMD3(0.055, 0.045, 18.86), at: SIMD3(1.39, 3.36, 0), material: VehicleMaterialPalette.steel, in: group)

        for side: Float in [-1, 1] {
            let x = side * 1.38
            // Window openings are left as gaps between lower/upper panels and structural piers.
            VehicleGeometry.box("SideLowerBelt_\(Int(side))", size: SIMD3(0.12, 0.62, 18.9), at: SIMD3(x, 1.65, 0), material: VehicleMaterialPalette.body, in: group)
            VehicleGeometry.box("SideUpperBelt_\(Int(side))", size: SIMD3(0.12, 0.34, 18.9), at: SIMD3(x, 3.12, 0), material: VehicleMaterialPalette.body, in: group)
            VehicleGeometry.box("LowerTealWaistBand_\(Int(side))", size: SIMD3(0.045, 0.18, 18.7), at: SIMD3(side * 1.45, 1.98, 0), material: VehicleMaterialPalette.accent, in: group)
            VehicleGeometry.box("UpperFinePinstripe_\(Int(side))", size: SIMD3(0.025, 0.035, 18.7), at: SIMD3(side * 1.45, 2.12, 0), material: VehicleMaterialPalette.amber, in: group)
            let openingCenters = windowCenters + doorCenters
            for (index, z) in openingCenters.enumerated() {
                let width: Float = doorCenters.contains(z) ? 1.48 : 1.10
                let pierWidth: Float = 0.15
                for edge: Float in [-1, 1] {
                    let pierZ = z + edge * (width * 0.5 + pierWidth * 0.5)
                    VehicleGeometry.box("WindowPier_\(Int(side))_\(index)_\(Int(edge))", size: SIMD3(0.12, 1.18, pierWidth), at: SIMD3(x, 2.55, pierZ), material: VehicleMaterialPalette.body, in: group)
                }
            }
            for (index, z) in doorCenters.enumerated() {
                VehicleGeometry.box("DoorHeader_\(Int(side))_\(index)", size: SIMD3(0.13, 0.12, 1.50), at: SIMD3(x, 3.16, z), material: VehicleMaterialPalette.bodyShade, in: group)
                VehicleGeometry.box("DoorSill_\(Int(side))_\(index)", size: SIMD3(0.15, 0.10, 1.50), at: SIMD3(side * 1.45, 1.99, z), material: VehicleMaterialPalette.darkSteel, in: group)
                VehicleGeometry.box("DoorThreshold_\(Int(side))_\(index)", size: SIMD3(0.40, 0.055, 1.38), at: SIMD3(side * 1.50, 1.93, z), material: VehicleMaterialPalette.steel, in: group)
            }
        }

        // Cab end: independent front fascia, corner posts, center mullion and split destination panel.
        VehicleGeometry.box("FrontLowerFascia", size: SIMD3(2.68, 0.54, 0.19), at: SIMD3(0, 1.48, -9.62), material: VehicleMaterialPalette.accent, in: group)
        VehicleGeometry.box("FrontWindshieldHeader", size: SIMD3(2.72, 0.26, 0.18), at: SIMD3(0, 3.36, -9.62), material: VehicleMaterialPalette.body, in: group)
        for side: Float in [-1, 1] {
            VehicleGeometry.box("FrontCornerPillar_\(Int(side))", size: SIMD3(0.18, 1.55, 0.18), at: SIMD3(side * 1.29, 2.57, -9.62), material: VehicleMaterialPalette.body, in: group)
            VehicleGeometry.box("CabSideReturn_\(Int(side))", size: SIMD3(0.13, 1.24, 0.64), at: SIMD3(side * 1.32, 2.62, -9.28), material: VehicleMaterialPalette.bodyShade, in: group)
        }
        VehicleGeometry.box("WindshieldCenterPost", size: SIMD3(0.075, 1.38, 0.13), at: SIMD3(0, 2.58, -9.66), material: VehicleMaterialPalette.bodyShade, in: group)
        VehicleGeometry.box("FrontSkirt", size: SIMD3(2.66, 0.24, 0.22), at: SIMD3(0, 1.12, -9.56), material: VehicleMaterialPalette.bodyShade, in: group)
        VehicleGeometry.box("DestinationBoardHousing", size: SIMD3(1.00, 0.23, 0.13), at: SIMD3(0, 3.17, -9.70), material: VehicleMaterialPalette.darkSteel, in: group)
        VehicleGeometry.box("DestinationBoardFace", size: SIMD3(0.86, 0.13, 0.035), at: SIMD3(0, 3.17, -9.78), material: VehicleMaterialPalette.display, in: group)
        for dot in -5...5 {
            VehicleGeometry.sphere("DestinationPixel_\(dot)", radius: 0.012, at: SIMD3(Float(dot) * 0.065, 3.17, -9.805), material: VehicleMaterialPalette.amber, in: group)
        }
        VehicleGeometry.box("RearEndPanel", size: SIMD3(2.70, 2.10, 0.12), at: SIMD3(0, 2.40, 9.61), material: VehicleMaterialPalette.body, in: group)
        VehicleGeometry.box("FrontGangwayCollar", size: SIMD3(0.84, 1.66, 0.14), at: SIMD3(0, 2.18, -9.72), material: VehicleMaterialPalette.rubber, in: group)
        VehicleGeometry.box("RearGangwayCollar", size: SIMD3(0.84, 1.66, 0.14), at: SIMD3(0, 2.18, 9.72), material: VehicleMaterialPalette.rubber, in: group)
        for end: Float in [-1, 1] {
            VehicleGeometry.box("CouplerDraftGear_\(Int(end))", size: SIMD3(0.46, 0.30, 0.46), at: SIMD3(0, 0.74, end * 9.78), material: VehicleMaterialPalette.darkSteel, in: group)
            VehicleGeometry.box("CouplerShank_\(Int(end))", size: SIMD3(0.19, 0.17, 0.46), at: SIMD3(0, 0.69, end * 10.02), material: VehicleMaterialPalette.steel, in: group)
            VehicleGeometry.box("CouplerHead_\(Int(end))", size: SIMD3(0.38, 0.28, 0.30), at: SIMD3(0, 0.64, end * 10.24), material: VehicleMaterialPalette.darkSteel, in: group)
        }
    }

    static func buildGlazing(in group: Entity) {
        for side: Float in [-1, 1] {
            for (index, z) in windowCenters.enumerated() {
                let x = side * 1.448
                VehicleGeometry.box("PassengerWindowGasket_\(Int(side))_\(index)", size: SIMD3(0.035, 0.91, 1.12), at: SIMD3(x, 2.62, z), material: VehicleMaterialPalette.glassEdge, in: group)
                VehicleGeometry.box("PassengerWindowGlass_\(Int(side))_\(index)", size: SIMD3(0.021, 0.82, 1.03), at: SIMD3(side * 1.470, 2.62, z), material: VehicleMaterialPalette.glass, in: group)
                VehicleGeometry.box("PassengerWindowLowerRail_\(Int(side))_\(index)", size: SIMD3(0.027, 0.035, 1.04), at: SIMD3(side * 1.485, 2.20, z), material: VehicleMaterialPalette.steel, in: group)
                if index % 2 == 0 {
                    VehicleGeometry.box("VentLight_\(Int(side))_\(index)", size: SIMD3(0.018, 0.10, 0.92), at: SIMD3(side * 1.486, 2.96, z), material: VehicleMaterialPalette.glassEdge, in: group)
                }
            }
            for (index, z) in doorCenters.enumerated() {
                let x = side * 1.468
                VehicleGeometry.box("DoorLeafWindowSeal_\(Int(side))_\(index)", size: SIMD3(0.028, 0.76, 0.66), at: SIMD3(x, 2.63, z), material: VehicleMaterialPalette.glassEdge, in: group)
                VehicleGeometry.box("DoorLeafWindow_\(Int(side))_\(index)", size: SIMD3(0.018, 0.67, 0.57), at: SIMD3(side * 1.488, 2.63, z), material: VehicleMaterialPalette.glass, in: group)
                for edge: Float in [-1, 1] {
                    VehicleGeometry.box("DoorVerticalSeal_\(Int(side))_\(index)_\(Int(edge))", size: SIMD3(0.025, 1.38, 0.028), at: SIMD3(side * 1.487, 2.47, z + edge * 0.34), material: VehicleMaterialPalette.darkSteel, in: group)
                }
                VehicleGeometry.cylinder("DoorEmergencyRelease_\(Int(side))_\(index)", radius: 0.022, length: 0.12, at: SIMD3(side * 1.505, 2.08, z + 0.48), axis: SIMD3(1, 0, 0), material: VehicleMaterialPalette.amber, in: group)
            }
        }
        for index in 0..<2 {
            let x: Float = index == 0 ? -0.60 : 0.60
            VehicleGeometry.box("FrontWindshieldGasket_\(index)", size: SIMD3(1.18, 0.91, 0.055), at: SIMD3(x, 2.72, -9.69), material: VehicleMaterialPalette.glassEdge, in: group)
            VehicleGeometry.box("FrontWindshieldGlass_\(index)", size: SIMD3(1.08, 0.81, 0.025), at: SIMD3(x, 2.72, -9.727), material: VehicleMaterialPalette.glass, in: group)
            VehicleGeometry.box("RearEndWindow_\(index)", size: SIMD3(0.92, 0.62, 0.04), at: SIMD3(x * 0.78, 2.76, 9.68), material: VehicleMaterialPalette.glass, in: group)
        }
    }

    static func buildDoors(in group: Entity) -> [DoorLeafHandle] {
        var handles: [DoorLeafHandle] = []
        for side: Float in [-1, 1] {
            for (index, center) in doorCenters.enumerated() {
                for leaf: Float in [-1, 1] {
                    let z = center + leaf * 0.36
                    let moving = VehicleGeometry.box("AnimatedDoorPanel_\(Int(side))_\(index)_\(Int(leaf))", size: SIMD3(0.035, 1.48, 0.66), at: SIMD3(side * 1.444, 2.45, z), material: VehicleMaterialPalette.body, in: group)
                    VehicleGeometry.box("DoorRubberEdge_\(Int(side))_\(index)_\(Int(leaf))", size: SIMD3(0.018, 1.40, 0.025), at: SIMD3(side * 1.465, 2.45, center + leaf * 0.018), material: VehicleMaterialPalette.rubber, in: group)
                    VehicleGeometry.box("DoorHandle_\(Int(side))_\(index)_\(Int(leaf))", size: SIMD3(0.018, 0.20, 0.035), at: SIMD3(side * 1.47, 2.20, center + leaf * 0.20), material: VehicleMaterialPalette.steel, in: group)
                    handles.append(DoorLeafHandle(entity: moving, direction: leaf, closedZ: z))
                }
                VehicleGeometry.box("DoorIndicator_\(Int(side))_\(index)", size: SIMD3(0.04, 0.055, 0.12), at: SIMD3(side * 1.47, 3.25, center), material: VehicleMaterialPalette.amber, in: group)
            }
        }
        return handles
    }

    static func buildBogie(in group: Entity, detail: VehicleDetailLevel) -> BogieBuildResult {
        var wheels: [WheelHandle] = []
        var bogies: [BogieHandle] = []
        let centers: [Float] = [-6.35, 6.35]
        for (bogieIndex, centerZ) in centers.enumerated() {
            let bogie = VehicleGeometry.group("BogieAssembly_\(bogieIndex)", in: group)
            bogie.position = SIMD3(0, 0, centerZ)
            bogies.append(BogieHandle(entity: bogie))
            VehicleGeometry.box("BogieSideFrame_L_\(bogieIndex)", size: SIMD3(0.22, 0.30, 3.14), at: SIMD3(-1.02, 0.78, 0), material: VehicleMaterialPalette.darkSteel, in: bogie)
            VehicleGeometry.box("BogieSideFrame_R_\(bogieIndex)", size: SIMD3(0.22, 0.30, 3.14), at: SIMD3(1.02, 0.78, 0), material: VehicleMaterialPalette.darkSteel, in: bogie)
            VehicleGeometry.box("BogieCrossBeam_F_\(bogieIndex)", size: SIMD3(2.10, 0.25, 0.22), at: SIMD3(0, 0.83, -1.34), material: VehicleMaterialPalette.undercoat, in: bogie)
            VehicleGeometry.box("BogieCrossBeam_R_\(bogieIndex)", size: SIMD3(2.10, 0.25, 0.22), at: SIMD3(0, 0.83, 1.34), material: VehicleMaterialPalette.undercoat, in: bogie)
            for axle: Float in [-1.05, 1.05] {
                let axleZ = axle
                VehicleGeometry.cylinder("Axle_\(bogieIndex)_\(Int(axle * 100))", radius: 0.105, length: 2.05, at: SIMD3(0, 0.43, axleZ), axis: SIMD3(1, 0, 0), material: VehicleMaterialPalette.steel, in: bogie)
                for side: Float in [-1, 1] {
                    let wheel = VehicleGeometry.cylinder("Wheel_\(bogieIndex)_\(Int(axle * 100))_\(Int(side))", radius: 0.43, length: 0.17, at: SIMD3(side * 0.98, 0.43, axleZ), axis: SIMD3(1, 0, 0), material: VehicleMaterialPalette.rubber, in: bogie)
                    wheels.append(WheelHandle(entity: wheel, radius: 0.43, baseOrientation: wheel.orientation))
                    VehicleGeometry.cylinder("WheelHub_\(bogieIndex)_\(Int(axle * 100))_\(Int(side))", radius: 0.18, length: 0.19, at: SIMD3(side * 1.09, 0.43, axleZ), axis: SIMD3(1, 0, 0), material: VehicleMaterialPalette.steel, in: bogie)
                    VehicleGeometry.cylinder("BrakeDisc_\(bogieIndex)_\(Int(axle * 100))_\(Int(side))", radius: 0.29, length: 0.09, at: SIMD3(side * 0.85, 0.43, axleZ), axis: SIMD3(1, 0, 0), material: VehicleMaterialPalette.bodyShade, in: bogie)
                    VehicleGeometry.box("Axlebox_\(bogieIndex)_\(Int(axle * 100))_\(Int(side))", size: SIMD3(0.30, 0.38, 0.36), at: SIMD3(side * 1.00, 0.80, axleZ), material: VehicleMaterialPalette.darkSteel, in: bogie)
                    VehicleGeometry.rod("BrakeCaliper_\(bogieIndex)_\(Int(axle * 100))_\(Int(side))", from: SIMD3(side * 0.76, 0.55, axleZ - 0.31), to: SIMD3(side * 0.76, 0.55, axleZ + 0.31), radius: 0.035, material: VehicleMaterialPalette.steel, in: bogie)
                }
                for side: Float in [-1, 1] {
                    let x = side * 0.93
                    VehicleGeometry.cylinder("PrimarySpringLower_\(bogieIndex)_\(Int(axle * 100))_\(Int(side))", radius: 0.095, length: 0.23, at: SIMD3(x, 0.65, axleZ), material: VehicleMaterialPalette.amber, in: bogie)
                    VehicleGeometry.cylinder("PrimarySpringUpper_\(bogieIndex)_\(Int(axle * 100))_\(Int(side))", radius: 0.12, length: 0.10, at: SIMD3(x, 0.96, axleZ), material: VehicleMaterialPalette.steel, in: bogie)
                }
            }
            for side: Float in [-1, 1] {
                VehicleGeometry.rod("YawDamper_\(bogieIndex)_\(Int(side))", from: SIMD3(side * 0.70, 0.80, -0.68), to: SIMD3(side * 0.92, 1.03, 0.68), radius: 0.035, material: VehicleMaterialPalette.steel, in: bogie)
            }
            for index in 0..<detail.fastenerRows {
                let z = -1.25 + Float(index) * 2.5 / Float(max(detail.fastenerRows - 1, 1))
                for side: Float in [-1, 1] {
                    VehicleGeometry.sphere("FrameFastener_\(bogieIndex)_\(index)_\(Int(side))", radius: 0.025, at: SIMD3(side * 1.138, 0.91, z), material: VehicleMaterialPalette.steel, in: bogie)
                }
            }
        }
        return BogieBuildResult(wheels: wheels, bogies: bogies)
    }

    static func buildUnderfloor(in group: Entity, detail: VehicleDetailLevel) {
        let equipment: [(String, Float, Float, Float)] = [
            ("TractionInverter", -4.25, 0.67, 1.45),
            ("AuxiliaryConverter", -1.75, 0.66, 1.12),
            ("AirCompressor", 0.80, 0.68, 0.92),
            ("BrakeResistor", 3.00, 0.70, 1.28),
            ("BatteryBox", 5.05, 0.66, 1.08)
        ]
        for (name, z, y, length) in equipment {
            VehicleGeometry.box("\(name)_Casing", size: SIMD3(1.10, 0.48, length), at: SIMD3(0, y, z), material: VehicleMaterialPalette.undercoat, in: group)
            VehicleGeometry.box("\(name)_Cover", size: SIMD3(1.14, 0.065, length * 0.85), at: SIMD3(0, y + 0.27, z), material: VehicleMaterialPalette.darkSteel, in: group)
            VehicleGeometry.box("\(name)_MountLeft", size: SIMD3(0.08, 0.24, 0.12), at: SIMD3(-0.50, y + 0.36, z), material: VehicleMaterialPalette.steel, in: group)
            VehicleGeometry.box("\(name)_MountRight", size: SIMD3(0.08, 0.24, 0.12), at: SIMD3(0.50, y + 0.36, z), material: VehicleMaterialPalette.steel, in: group)
            for slat in 0..<detail.grilleSlats {
                let zOffset = -length * 0.33 + Float(slat) * (length * 0.66 / Float(max(detail.grilleSlats - 1, 1)))
                VehicleGeometry.box("\(name)_CoolingSlat_\(slat)", size: SIMD3(0.72, 0.018, 0.035), at: SIMD3(0, y + 0.04, z + zOffset), material: VehicleMaterialPalette.steel, in: group)
            }
        }
        for index in 0..<7 {
            let z = -5.4 + Float(index) * 1.8
            VehicleGeometry.box("UnderframeCrossmember_\(index)", size: SIMD3(2.34, 0.13, 0.14), at: SIMD3(0, 0.91, z), material: VehicleMaterialPalette.darkSteel, in: group)
        }
        VehicleGeometry.rod("BrakePipe", from: SIMD3(-0.72, 0.53, -8.7), to: SIMD3(-0.72, 0.53, 8.7), radius: 0.035, material: VehicleMaterialPalette.steel, in: group)
        VehicleGeometry.rod("MainAirPipe", from: SIMD3(0.72, 0.48, -8.7), to: SIMD3(0.72, 0.48, 8.7), radius: 0.035, material: VehicleMaterialPalette.amber, in: group)
    }

    static func buildRoof(in group: Entity, detail: VehicleDetailLevel) {
        for (index, z) in [Float]([-5.9, 0.0, 5.9]).enumerated() {
            let ac = VehicleGeometry.group("HVACAssembly_\(index)", in: group)
            VehicleGeometry.box("HVACBase_\(index)", size: SIMD3(1.55, 0.12, 2.55), at: SIMD3(0, 3.60, z), material: VehicleMaterialPalette.darkSteel, in: ac)
            VehicleGeometry.box("HVACCover_\(index)", size: SIMD3(1.42, 0.20, 2.38), at: SIMD3(0, 3.75, z), material: VehicleMaterialPalette.roof, in: ac)
            for side: Float in [-1, 1] {
                for slat in 0..<detail.grilleSlats {
                    let x = side * (0.35 + Float(slat) * 0.055)
                    VehicleGeometry.box("HVACGrille_\(index)_\(Int(side))_\(slat)", size: SIMD3(0.025, 0.025, 1.65), at: SIMD3(x, 3.865, z), material: VehicleMaterialPalette.steel, in: ac)
                }
            }
            for side: Float in [-1, 1] {
                VehicleGeometry.box("HVACEndLouver_\(index)_\(Int(side))", size: SIMD3(1.20, 0.14, 0.025), at: SIMD3(0, 3.77, z + side * 1.10), material: VehicleMaterialPalette.undercoat, in: ac)
            }
        }
    }

    static func buildPantograph(in group: Entity) -> PantographHandle {
        VehicleGeometry.box("PantographInsulatorBase", size: SIMD3(1.15, 0.10, 0.42), at: SIMD3(0, 3.60, 2.7), material: VehicleMaterialPalette.bodyShade, in: group)
        VehicleGeometry.cylinder("PantographInsulator_L", radius: 0.09, length: 0.34, at: SIMD3(-0.40, 3.82, 2.7), material: VehicleMaterialPalette.glassEdge, in: group)
        VehicleGeometry.cylinder("PantographInsulator_R", radius: 0.09, length: 0.34, at: SIMD3(0.40, 3.82, 2.7), material: VehicleMaterialPalette.glassEdge, in: group)
        let moving = VehicleGeometry.group("PantographMovingLinkage", in: group)
        moving.position = SIMD3(0, 3.93, 2.7)
        VehicleGeometry.rod("PantographLowerLeft", from: SIMD3(-0.38, 0, -0.16), to: SIMD3(0.02, 0.39, -0.16), radius: 0.035, material: VehicleMaterialPalette.steel, in: moving)
        VehicleGeometry.rod("PantographLowerRight", from: SIMD3(0.38, 0, 0.16), to: SIMD3(-0.02, 0.39, 0.16), radius: 0.035, material: VehicleMaterialPalette.steel, in: moving)
        VehicleGeometry.rod("PantographUpperLeft", from: SIMD3(0.02, 0.39, -0.16), to: SIMD3(0.32, 0.76, -0.16), radius: 0.032, material: VehicleMaterialPalette.steel, in: moving)
        VehicleGeometry.rod("PantographUpperRight", from: SIMD3(-0.02, 0.39, 0.16), to: SIMD3(-0.32, 0.76, 0.16), radius: 0.032, material: VehicleMaterialPalette.steel, in: moving)
        VehicleGeometry.box("PantographContactStrip", size: SIMD3(0.96, 0.07, 0.13), at: SIMD3(0, 0.80, 0), material: VehicleMaterialPalette.darkSteel, in: moving)
        VehicleGeometry.box("PantographHornLeft", size: SIMD3(0.08, 0.11, 0.13), at: SIMD3(-0.49, 0.77, 0), material: VehicleMaterialPalette.steel, in: moving)
        VehicleGeometry.box("PantographHornRight", size: SIMD3(0.08, 0.11, 0.13), at: SIMD3(0.49, 0.77, 0), material: VehicleMaterialPalette.steel, in: moving)
        return PantographHandle(movingAssembly: moving, baseY: 3.93)
    }

    static func buildLighting(in group: Entity) {
        for side: Float in [-1, 1] {
            VehicleGeometry.cylinder("HeadlampBezel_\(Int(side))", radius: 0.12, length: 0.06, at: SIMD3(side * 0.92, 1.78, -9.73), axis: SIMD3(0, 0, 1), material: VehicleMaterialPalette.darkSteel, in: group)
            let lamp = VehicleGeometry.sphere("FrontHeadlamp_\(Int(side))", radius: 0.083, at: SIMD3(side * 0.92, 1.78, -9.79), material: VehicleMaterialPalette.lamp, in: group)
            lamp.name = "FrontHeadlamp_\(Int(side))"
            VehicleGeometry.cylinder("MarkerLampBezel_\(Int(side))", radius: 0.07, length: 0.045, at: SIMD3(side * 1.13, 2.18, -9.72), axis: SIMD3(0, 0, 1), material: VehicleMaterialPalette.darkSteel, in: group)
            VehicleGeometry.sphere("FrontMarkerLamp_\(Int(side))", radius: 0.047, at: SIMD3(side * 1.13, 2.18, -9.77), material: VehicleMaterialPalette.lamp, in: group)
            VehicleGeometry.cylinder("TailLampBezel_\(Int(side))", radius: 0.08, length: 0.04, at: SIMD3(side * 0.91, 1.80, 9.70), axis: SIMD3(0, 0, 1), material: VehicleMaterialPalette.darkSteel, in: group)
            VehicleGeometry.sphere("RearTailLamp_\(Int(side))", radius: 0.06, at: SIMD3(side * 0.91, 1.80, 9.74), material: VehicleMaterialPalette.redLamp, in: group)
        }
        for side: Float in [-1, 1] {
            for z: Float in [-7.1, -2.37, 2.37, 7.1] {
                VehicleGeometry.box("SideDoorStatusLamp_\(Int(side))_\(Int(z * 10))", size: SIMD3(0.04, 0.04, 0.09), at: SIMD3(side * 1.48, 3.22, z), material: VehicleMaterialPalette.amber, in: group)
            }
        }
    }

    static func buildWipers(in group: Entity) -> [WiperHandle] {
        var handles: [WiperHandle] = []
        for side: Float in [-1, 1] {
            let pivot = Entity()
            pivot.name = "WindshieldWiperPivot_\(Int(side))"
            pivot.position = SIMD3(side * 0.40, 2.34, -9.78)
            group.addChild(pivot)
            let endpoint = SIMD3(-side * 0.32, 0.62, 0)
            VehicleGeometry.rod("WiperArm_\(Int(side))", from: .zero, to: endpoint, radius: 0.025, material: VehicleMaterialPalette.darkSteel, in: pivot)
            VehicleGeometry.box("WiperBlade_\(Int(side))", size: SIMD3(0.045, 0.46, 0.035), at: SIMD3(-side * 0.32, 0.64, -0.005), material: VehicleMaterialPalette.rubber, in: pivot)
            VehicleGeometry.cylinder("WiperPivotCap_\(Int(side))", radius: 0.065, length: 0.06, at: SIMD3(0, 0, 0), axis: SIMD3(0, 0, 1), material: VehicleMaterialPalette.steel, in: pivot)
            handles.append(WiperHandle(pivot: pivot, side: side))
        }
        return handles
    }
}
