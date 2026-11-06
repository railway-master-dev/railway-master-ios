import RealityKit
import simd
import VehicleGeometryUV

/// Fine-grained, independently addressable assemblies for the fictional HF-01 visual model.
public enum VehicleComponentPart: String, CaseIterable, Codable, Hashable, Sendable {
    case frontShape
    case sideShape
    case roof
    case frontGlass
    case sideWindows
    case doors
    case doorGlass
    case bogies
    case wheels
    case axleBoxes
    case airSprings
    case underfloorEquipment
    case motorEquipment
    case pantograph
    case couplers
    case markerLights
    case headlights
    case tailLights
    case destinationDisplay
    case surfaceDetails
}

/// Component-oriented alternative builder. Each `parts` entry is its own RealityKit group.
public struct VehicleComponentModel {
    public let root: Entity
    public let parts: [VehicleComponentPart: Entity]
    public let specification: RailwayVehicleHighFidelitySpecification

    public init(root: Entity, parts: [VehicleComponentPart: Entity], specification: RailwayVehicleHighFidelitySpecification = .fictionalPrototype) {
        self.root = root
        self.parts = parts
        self.specification = specification
    }
}

/// Generates a fictional commuter-car assembly from individually named meshes and groups.
/// Coordinates are metres: X=width, Y=up, Z=length; front is -Z.
public enum VehicleComponentModelBuilder {
    private static let doorCenters: [Float] = [-7.1, -2.37, 2.37, 7.1]
    private static let windowCenters: [Float] = [-8.55, -5.65, -3.55, -1.0, 1.0, 3.55, 5.65, 8.55]
    private static let bogieCenters: [Float] = [-6.25, 6.25]

    public static func build(
        _ specification: RailwayVehicleHighFidelitySpecification = .fictionalPrototype,
        detail: VehicleDetailLevel? = nil
    ) -> VehicleComponentModel {
        let detailLevel = detail ?? specification.detailLevel
        let root = Entity()
        root.name = specification.identifier + "_componentModel"
        root.scale = specification.modelScale
        let groups = Dictionary(uniqueKeysWithValues: VehicleComponentPart.allCases.map { part in
            let group = Entity()
            group.name = "VehicleComponent_\(part.rawValue)"
            root.addChild(group)
            return (part, group)
        })
        func group(_ part: VehicleComponentPart) -> Entity {
            guard let result = groups[part] else { preconditionFailure("Missing component group: \(part.rawValue)") }
            return result
        }

        buildFrontShape(in: group(.frontShape))
        buildSideShape(in: group(.sideShape))
        buildRoof(in: group(.roof), detail: detailLevel)
        buildFrontGlass(in: group(.frontGlass))
        buildSideWindows(in: group(.sideWindows))
        buildDoors(in: group(.doors))
        buildDoorGlass(in: group(.doorGlass))
        buildBogies(in: group(.bogies))
        buildWheels(in: group(.wheels))
        buildAxleBoxes(in: group(.axleBoxes))
        buildAirSprings(in: group(.airSprings))
        buildUnderfloorEquipment(in: group(.underfloorEquipment), detail: detailLevel)
        buildMotorEquipment(in: group(.motorEquipment))
        buildPantograph(in: group(.pantograph))
        buildCouplers(in: group(.couplers))
        buildMarkerLights(in: group(.markerLights))
        buildHeadlights(in: group(.headlights))
        buildTailLights(in: group(.tailLights))
        buildDestinationDisplay(in: group(.destinationDisplay))
        buildSurfaceDetails(in: group(.surfaceDetails), detail: detailLevel)

        return VehicleComponentModel(root: root, parts: groups, specification: specification)
    }

    private static func buildFrontShape(in group: Entity) {
        // Rounded lower nose and upper brow are separate, tapered lofted shells around glazing openings.
        VehicleAuthoredMesh.roundedLoft("FrontNoseLowerShell", sections: [
            VehicleLoftSection(z: -9.76, centerX: 0, centerY: 1.46, width: 2.55, height: 0.58, radius: 0.16),
            VehicleLoftSection(z: -9.50, centerX: 0, centerY: 1.46, width: 2.68, height: 0.62, radius: 0.18),
            VehicleLoftSection(z: -9.16, centerX: 0, centerY: 1.48, width: 2.74, height: 0.66, radius: 0.20)
        ], material: VehicleMaterialPalette.accent, in: group)
        VehicleAuthoredMesh.roundedLoft("FrontWindshieldBrow", sections: [
            VehicleLoftSection(z: -9.74, centerX: 0, centerY: 3.22, width: 2.56, height: 0.22, radius: 0.08),
            VehicleLoftSection(z: -9.47, centerX: 0, centerY: 3.24, width: 2.72, height: 0.24, radius: 0.08),
            VehicleLoftSection(z: -9.18, centerX: 0, centerY: 3.24, width: 2.76, height: 0.26, radius: 0.08)
        ], material: VehicleMaterialPalette.body, in: group)
        for side: Float in [-1, 1] {
            VehicleAuthoredMesh.roundedLoft("FrontApost_\(Int(side))", sections: [
                VehicleLoftSection(z: -9.72, centerX: side * 1.20, centerY: 2.36, width: 0.16, height: 1.48, radius: 0.055),
                VehicleLoftSection(z: -9.46, centerX: side * 1.27, centerY: 2.36, width: 0.17, height: 1.48, radius: 0.06),
                VehicleLoftSection(z: -9.16, centerX: side * 1.34, centerY: 2.36, width: 0.18, height: 1.46, radius: 0.06)
            ], material: VehicleMaterialPalette.body, in: group)
            VehicleAuthoredMesh.roundedLoft("FrontSideReturn_\(Int(side))", sections: [
                VehicleLoftSection(z: -9.25, centerX: side * 1.34, centerY: 2.38, width: 0.12, height: 1.28, radius: 0.04),
                VehicleLoftSection(z: -8.94, centerX: side * 1.37, centerY: 2.38, width: 0.12, height: 1.28, radius: 0.04)
            ], material: VehicleMaterialPalette.bodyShade, in: group)
        }
        VehicleGeometry.box("FrontSkirtCenter", size: SIMD3<Float>(2.36, 0.24, 0.17), at: SIMD3(0, 1.08, -9.52), material: VehicleMaterialPalette.bodyShade, in: group)
        VehicleGeometry.box("FrontLowerGrilleRecess", size: SIMD3<Float>(0.68, 0.19, 0.026), at: SIMD3(0, 1.46, -9.79), material: VehicleMaterialPalette.darkSteel, in: group)
        for slat in 0..<5 {
            VehicleGeometry.box("FrontGrilleSlat_\(slat)", size: SIMD3<Float>(0.56, 0.012, 0.018), at: SIMD3(0, 1.40 + Float(slat) * 0.03, -9.81), material: VehicleMaterialPalette.steel, in: group)
        }
        VehicleGeometry.box("FrontImpactStrip", size: SIMD3<Float>(2.38, 0.055, 0.035), at: SIMD3(0, 1.20, -9.80), material: VehicleMaterialPalette.darkSteel, in: group)
    }

    private static func buildSideShape(in group: Entity) {
        VehicleGeometry.box("UnderframeSideSill", size: SIMD3<Float>(0.16, 0.28, 18.96), at: SIMD3(1.36, 1.20, 0), material: VehicleMaterialPalette.bodyShade, in: group)
        VehicleGeometry.box("UnderframeSideSillOpposite", size: SIMD3<Float>(0.16, 0.28, 18.96), at: SIMD3(-1.36, 1.20, 0), material: VehicleMaterialPalette.bodyShade, in: group)
        for side: Float in [-1, 1] {
            let x = side * 1.37
            VehicleGeometry.box("SideLowerBelt_\(Int(side))", size: SIMD3<Float>(0.13, 0.55, 18.85), at: SIMD3(x, 1.63, 0), material: VehicleMaterialPalette.body, in: group)
            VehicleGeometry.box("SideUpperBelt_\(Int(side))", size: SIMD3<Float>(0.13, 0.30, 18.85), at: SIMD3(x, 3.12, 0), material: VehicleMaterialPalette.body, in: group)
            VehicleGeometry.box("SideWaistBand_\(Int(side))", size: SIMD3<Float>(0.045, 0.18, 18.70), at: SIMD3(side * 1.45, 1.96, 0), material: VehicleMaterialPalette.accent, in: group)
            VehicleGeometry.box("SideFinePinstripe_\(Int(side))", size: SIMD3<Float>(0.025, 0.032, 18.65), at: SIMD3(side * 1.45, 2.11, 0), material: VehicleMaterialPalette.amber, in: group)
            let openings = windowCenters + doorCenters
            for (index, centerZ) in openings.enumerated() {
                let openingWidth: Float = doorCenters.contains(centerZ) ? 1.47 : 1.10
                let postOffset = openingWidth * 0.5 + 0.085
                for edge: Float in [-1, 1] {
                    VehicleGeometry.box("SideWindowPier_\(Int(side))_\(index)_\(Int(edge))", size: SIMD3<Float>(0.13, 1.16, 0.17), at: SIMD3(x, 2.55, centerZ + edge * postOffset), material: VehicleMaterialPalette.body, in: group)
                }
            }
            for (index, centerZ) in doorCenters.enumerated() {
                VehicleGeometry.box("DoorHeader_\(Int(side))_\(index)", size: SIMD3<Float>(0.14, 0.12, 1.52), at: SIMD3(x, 3.18, centerZ), material: VehicleMaterialPalette.bodyShade, in: group)
                VehicleGeometry.box("DoorSill_\(Int(side))_\(index)", size: SIMD3<Float>(0.14, 0.095, 1.52), at: SIMD3(side * 1.45, 1.91, centerZ), material: VehicleMaterialPalette.darkSteel, in: group)
                VehicleGeometry.box("DoorThreshold_\(Int(side))_\(index)", size: SIMD3<Float>(0.34, 0.045, 1.38), at: SIMD3(side * 1.48, 1.84, centerZ), material: VehicleMaterialPalette.steel, in: group)
            }
        }
    }

    private static func buildRoof(in group: Entity, detail: VehicleDetailLevel) {
        VehicleAuthoredMesh.roofCrown("CurvedRoofCrown", length: 19.1, width: 2.68, centerY: 3.43, rise: 0.20, zStart: -9.55, widthSegments: 24, lengthSegments: detail == .high ? 24 : 12, material: VehicleMaterialPalette.roof, in: group)
        VehicleAuthoredMesh.roundedLoft("RoofLongitudinalInnerShell", sections: [
            VehicleLoftSection(z: -9.42, centerX: 0, centerY: 3.39, width: 2.50, height: 0.16, radius: 0.08),
            VehicleLoftSection(z: 0, centerX: 0, centerY: 3.39, width: 2.50, height: 0.16, radius: 0.08),
            VehicleLoftSection(z: 9.42, centerX: 0, centerY: 3.39, width: 2.50, height: 0.16, radius: 0.08)
        ], material: VehicleMaterialPalette.darkSteel, in: group)
        for side: Float in [-1, 1] {
            VehicleAuthoredMesh.roundedLoft("RoofDripRail_\(Int(side))", sections: [
                VehicleLoftSection(z: -9.43, centerX: side * 1.32, centerY: 3.49, width: 0.06, height: 0.075, radius: 0.025),
                VehicleLoftSection(z: 0, centerX: side * 1.32, centerY: 3.49, width: 0.06, height: 0.075, radius: 0.025),
                VehicleLoftSection(z: 9.43, centerX: side * 1.32, centerY: 3.49, width: 0.06, height: 0.075, radius: 0.025)
            ], material: VehicleMaterialPalette.steel, in: group)
        }
        for index in 0..<3 {
            let z = Float(index - 1) * 5.8
            VehicleAuthoredMesh.roundedLoft("RoofHVACBase_\(index)", sections: [
                VehicleLoftSection(z: z - 1.27, centerX: 0, centerY: 3.61, width: 1.55, height: 0.12, radius: 0.09),
                VehicleLoftSection(z: z + 1.27, centerX: 0, centerY: 3.61, width: 1.55, height: 0.12, radius: 0.09)
            ], material: VehicleMaterialPalette.darkSteel, in: group)
            VehicleAuthoredMesh.roundedLoft("RoofHVACCover_\(index)", sections: [
                VehicleLoftSection(z: z - 1.18, centerX: 0, centerY: 3.76, width: 1.42, height: 0.20, radius: 0.14),
                VehicleLoftSection(z: z + 1.18, centerX: 0, centerY: 3.76, width: 1.42, height: 0.20, radius: 0.14)
            ], material: VehicleMaterialPalette.bodyShade, in: group)
            for side: Float in [-1, 1] {
                for slat in 0..<detail.grilleSlats {
                    let x = side * (0.30 + Float(slat) * 0.065)
                    VehicleGeometry.box("RoofHVACLouver_\(index)_\(Int(side))_\(slat)", size: SIMD3<Float>(0.025, 0.022, 1.58), at: SIMD3(x, 3.875, z), material: VehicleMaterialPalette.steel, in: group)
                }
            }
        }
        VehicleGeometry.box("RoofCableTray", size: SIMD3<Float>(0.17, 0.08, 16.8), at: SIMD3(0.98, 3.49, 0), material: VehicleMaterialPalette.darkSteel, in: group)
        VehicleGeometry.box("RoofCenterLongitudinalSeam", size: SIMD3<Float>(0.018, 0.018, 18.1), at: SIMD3(0, 3.625, 0), material: VehicleMaterialPalette.bodyShade, in: group)
    }

    private static func buildFrontGlass(in group: Entity) {
        for index in 0..<2 {
            let side: Float = index == 0 ? -1 : 1
            let centerX = side * 0.59
            let xLow = centerX - 0.53
            let xHigh = centerX + 0.53
            let yBottom: Float = 2.16
            let yTop: Float = 3.04
            let gasketZ: Float = -9.675
            let glassZ: Float = -9.704
            VehicleGeometry.box("FrontWindshieldGasket_\(index)", size: SIMD3<Float>(1.14, 0.94, 0.025), at: SIMD3(centerX, 2.60, gasketZ), material: VehicleMaterialPalette.glassEdge, in: group)
            VehicleAuthoredMesh.quad("FrontWindshieldGlass_\(index)", corners: [
                SIMD3<Float>(xLow, yBottom, glassZ), SIMD3<Float>(xHigh, yBottom, glassZ),
                SIMD3<Float>(xHigh, yTop, glassZ), SIMD3<Float>(xLow, yTop, glassZ)
            ], material: VehicleMaterialPalette.glass, reverseWinding: true, in: group)
            VehicleGeometry.box("FrontWindshieldLowerSeal_\(index)", size: SIMD3<Float>(1.08, 0.025, 0.035), at: SIMD3(centerX, yBottom, glassZ - 0.006), material: VehicleMaterialPalette.darkSteel, in: group)
        }
        VehicleGeometry.box("WindshieldCenterMullion", size: SIMD3<Float>(0.065, 0.94, 0.10), at: SIMD3(0, 2.60, -9.66), material: VehicleMaterialPalette.bodyShade, in: group)
    }

    private static func buildSideWindows(in group: Entity) {
        for side: Float in [-1, 1] {
            for (index, centerZ) in windowCenters.enumerated() {
                let x: Float = side * 1.438
                VehicleGeometry.box("PassengerWindowGasket_\(Int(side))_\(index)", size: SIMD3<Float>(0.035, 0.91, 1.12), at: SIMD3(x, 2.61, centerZ), material: VehicleMaterialPalette.glassEdge, in: group)
                let glassX = side * 1.461
                VehicleAuthoredMesh.quad("PassengerWindowGlass_\(Int(side))_\(index)", corners: [
                    SIMD3<Float>(glassX, 2.20, centerZ - 0.515), SIMD3<Float>(glassX, 3.02, centerZ - 0.515),
                    SIMD3<Float>(glassX, 3.02, centerZ + 0.515), SIMD3<Float>(glassX, 2.20, centerZ + 0.515)
                ], material: VehicleMaterialPalette.glass, reverseWinding: side < 0, in: group)
                VehicleGeometry.box("PassengerWindowLowerRail_\(Int(side))_\(index)", size: SIMD3<Float>(0.026, 0.035, 1.04), at: SIMD3(side * 1.474, 2.18, centerZ), material: VehicleMaterialPalette.steel, in: group)
                if index % 2 == 0 {
                    VehicleGeometry.box("PassengerVentLight_\(Int(side))_\(index)", size: SIMD3<Float>(0.02, 0.09, 0.90), at: SIMD3(side * 1.473, 2.96, centerZ), material: VehicleMaterialPalette.glassEdge, in: group)
                }
            }
        }
    }

    private static func buildDoors(in group: Entity) {
        for side: Float in [-1, 1] {
            for (index, centerZ) in doorCenters.enumerated() {
                for leaf: Float in [-1, 1] {
                    let leafCenter = centerZ + leaf * 0.36
                    let leafGroup = VehicleGeometry.group("DoorLeaf_\(Int(side))_\(index)_\(Int(leaf))", in: group)
                    VehicleGeometry.box("DoorLeafLowerPanel_\(Int(side))_\(index)_\(Int(leaf))", size: SIMD3<Float>(0.05, 0.44, 0.70), at: SIMD3(side * 1.433, 2.12, leafCenter), material: VehicleMaterialPalette.body, in: leafGroup)
                    VehicleGeometry.box("DoorLeafHeader_\(Int(side))_\(index)_\(Int(leaf))", size: SIMD3<Float>(0.05, 0.12, 0.70), at: SIMD3(side * 1.433, 3.075, leafCenter), material: VehicleMaterialPalette.body, in: leafGroup)
                    VehicleGeometry.box("DoorLeafKickPlate_\(Int(side))_\(index)_\(Int(leaf))", size: SIMD3<Float>(0.018, 0.18, 0.62), at: SIMD3(side * 1.463, 2.06, leafCenter), material: VehicleMaterialPalette.bodyShade, in: leafGroup)
                    for edge: Float in [-1, 1] {
                        VehicleGeometry.box("DoorLeafWindowRail_\(Int(side))_\(index)_\(Int(leaf))_\(Int(edge))", size: SIMD3<Float>(0.05, 0.70, 0.045), at: SIMD3(side * 1.433, 2.67, leafCenter + edge * 0.322), material: VehicleMaterialPalette.body, in: leafGroup)
                    }
                    VehicleGeometry.box("DoorLeafOuterSeal_\(Int(side))_\(index)_\(Int(leaf))", size: SIMD3<Float>(0.022, 1.40, 0.024), at: SIMD3(side * 1.465, 2.50, leafCenter + leaf * 0.343), material: VehicleMaterialPalette.rubber, in: leafGroup)
                    VehicleGeometry.box("DoorHandle_\(Int(side))_\(index)_\(Int(leaf))", size: SIMD3<Float>(0.02, 0.16, 0.032), at: SIMD3(side * 1.475, 2.28, leafCenter - leaf * 0.19), material: VehicleMaterialPalette.steel, in: leafGroup)
                }
                VehicleGeometry.box("DoorCenterSeal_\(Int(side))_\(index)", size: SIMD3<Float>(0.027, 1.42, 0.035), at: SIMD3(side * 1.466, 2.50, centerZ), material: VehicleMaterialPalette.rubber, in: group)
                VehicleGeometry.box("DoorHeaderIndicator_\(Int(side))_\(index)", size: SIMD3<Float>(0.04, 0.05, 0.11), at: SIMD3(side * 1.47, 3.24, centerZ), material: VehicleMaterialPalette.amber, in: group)
            }
        }
    }

    private static func buildDoorGlass(in group: Entity) {
        for side: Float in [-1, 1] {
            for (index, centerZ) in doorCenters.enumerated() {
                for leaf: Float in [-1, 1] {
                    let leafCenter = centerZ + leaf * 0.36
                    let x = side * 1.466
                    VehicleGeometry.box("DoorGlassSeal_\(Int(side))_\(index)_\(Int(leaf))", size: SIMD3<Float>(0.025, 0.74, 0.62), at: SIMD3(x, 2.68, leafCenter), material: VehicleMaterialPalette.glassEdge, in: group)
                    let glassX = side * 1.485
                    VehicleAuthoredMesh.quad("DoorLeafGlass_\(Int(side))_\(index)_\(Int(leaf))", corners: [
                        SIMD3<Float>(glassX, 2.34, leafCenter - 0.285), SIMD3<Float>(glassX, 3.01, leafCenter - 0.285),
                        SIMD3<Float>(glassX, 3.01, leafCenter + 0.285), SIMD3<Float>(glassX, 2.34, leafCenter + 0.285)
                    ], material: VehicleMaterialPalette.glass, reverseWinding: side < 0, in: group)
                    for edge: Float in [-1, 1] {
                        VehicleGeometry.box("DoorGlassVerticalTrim_\(Int(side))_\(index)_\(Int(leaf))_\(Int(edge))", size: SIMD3<Float>(0.02, 0.70, 0.023), at: SIMD3(side * 1.49, 2.68, leafCenter + edge * 0.30), material: VehicleMaterialPalette.darkSteel, in: group)
                    }
                    VehicleGeometry.cylinder("DoorEmergencyRelease_\(Int(side))_\(index)_\(Int(leaf))", radius: 0.02, length: 0.08, at: SIMD3(side * 1.50, 2.08, leafCenter + leaf * 0.16), axis: SIMD3<Float>(1, 0, 0), material: VehicleMaterialPalette.amber, in: group)
                }
            }
        }
    }

    private static func buildBogies(in group: Entity) {
        for (index, centerZ) in bogieCenters.enumerated() {
            VehicleGeometry.box("BogieCenterPlate_\(index)", size: SIMD3<Float>(1.10, 0.15, 1.05), at: SIMD3(0, 1.04, centerZ), material: VehicleMaterialPalette.steel, in: group)
            for side: Float in [-1, 1] {
                VehicleAuthoredMesh.roundedLoft("BogieSideFrame_\(Int(side))_\(index)", sections: [
                    VehicleLoftSection(z: centerZ - 1.58, centerX: side * 1.00, centerY: 0.77, width: 0.24, height: 0.31, radius: 0.08),
                    VehicleLoftSection(z: centerZ - 0.55, centerX: side * 1.00, centerY: 0.78, width: 0.25, height: 0.35, radius: 0.085),
                    VehicleLoftSection(z: centerZ + 0.55, centerX: side * 1.00, centerY: 0.78, width: 0.25, height: 0.35, radius: 0.085),
                    VehicleLoftSection(z: centerZ + 1.58, centerX: side * 1.00, centerY: 0.77, width: 0.24, height: 0.31, radius: 0.08)
                ], material: VehicleMaterialPalette.darkSteel, in: group)
                VehicleGeometry.box("BogieSideFrameRib_\(Int(side))_\(index)", size: SIMD3<Float>(0.035, 0.12, 2.35), at: SIMD3(side * 1.132, 0.80, centerZ), material: VehicleMaterialPalette.steel, in: group)
            }
            for offset: Float in [-1.05, 1.05] {
                let axleZ = centerZ + offset
                VehicleGeometry.cylinder("BogieAxle_\(index)_\(Int(offset * 100))", radius: 0.105, length: 2.02, at: SIMD3(0, 0.43, axleZ), axis: SIMD3<Float>(1, 0, 0), material: VehicleMaterialPalette.steel, in: group)
            }
            for side: Float in [-1, 1] {
                VehicleGeometry.box("BogieCrossBeam_\(index)_\(Int(side))", size: SIMD3<Float>(2.08, 0.22, 0.24), at: SIMD3(0, 0.84, centerZ + side * 1.34), material: VehicleMaterialPalette.undercoat, in: group)
                VehicleGeometry.rod("BogieYawDamper_\(index)_\(Int(side))", from: SIMD3(side * 0.68, 0.88, centerZ - 0.60), to: SIMD3(side * 0.89, 1.03, centerZ + 0.64), radius: 0.033, material: VehicleMaterialPalette.steel, in: group)
            }
        }
    }

    private static func buildWheels(in group: Entity) {
        for (bogieIndex, centerZ) in bogieCenters.enumerated() {
            for axleOffset: Float in [-1.05, 1.05] {
                let axleZ = centerZ + axleOffset
                for side: Float in [-1, 1] {
                    let x = side * 1.00
                    VehicleGeometry.cylinder("WheelTread_\(bogieIndex)_\(Int(axleOffset * 100))_\(Int(side))", radius: 0.425, length: 0.18, at: SIMD3(x, 0.43, axleZ), axis: SIMD3<Float>(1, 0, 0), material: VehicleMaterialPalette.darkSteel, in: group)
                    VehicleGeometry.cylinder("WheelFlange_\(bogieIndex)_\(Int(axleOffset * 100))_\(Int(side))", radius: 0.455, length: 0.045, at: SIMD3(side * 1.098, 0.43, axleZ), axis: SIMD3<Float>(1, 0, 0), material: VehicleMaterialPalette.steel, in: group)
                    VehicleGeometry.cylinder("WheelWeb_\(bogieIndex)_\(Int(axleOffset * 100))_\(Int(side))", radius: 0.31, length: 0.11, at: SIMD3(side * 1.12, 0.43, axleZ), axis: SIMD3<Float>(1, 0, 0), material: VehicleMaterialPalette.bodyShade, in: group)
                    VehicleGeometry.cylinder("WheelHub_\(bogieIndex)_\(Int(axleOffset * 100))_\(Int(side))", radius: 0.16, length: 0.20, at: SIMD3(side * 1.18, 0.43, axleZ), axis: SIMD3<Float>(1, 0, 0), material: VehicleMaterialPalette.steel, in: group)
                    VehicleGeometry.cylinder("BrakeDisc_\(bogieIndex)_\(Int(axleOffset * 100))_\(Int(side))", radius: 0.285, length: 0.07, at: SIMD3(side * 0.87, 0.43, axleZ), axis: SIMD3<Float>(1, 0, 0), material: VehicleMaterialPalette.bodyShade, in: group)
                    for bolt in 0..<8 {
                        let angle = Float(bolt) * 2 * .pi / 8
                        VehicleGeometry.sphere("WheelStud_\(bogieIndex)_\(Int(axleOffset * 100))_\(Int(side))_\(bolt)", radius: 0.018, at: SIMD3(side * 1.294, 0.43 + sin(angle) * 0.205, axleZ + cos(angle) * 0.205), material: VehicleMaterialPalette.darkSteel, in: group)
                    }
                }
            }
        }
    }

    private static func buildAxleBoxes(in group: Entity) {
        for (bogieIndex, centerZ) in bogieCenters.enumerated() {
            for axleOffset: Float in [-1.05, 1.05] {
                for side: Float in [-1, 1] {
                    let x = side * 1.00
                    let z = centerZ + axleOffset
                    VehicleAuthoredMesh.roundedLoft("AxleBoxHousing_\(bogieIndex)_\(Int(axleOffset * 100))_\(Int(side))", sections: [
                        VehicleLoftSection(z: z - 0.19, centerX: x, centerY: 0.82, width: 0.36, height: 0.38, radius: 0.09),
                        VehicleLoftSection(z: z, centerX: x, centerY: 0.82, width: 0.38, height: 0.40, radius: 0.10),
                        VehicleLoftSection(z: z + 0.19, centerX: x, centerY: 0.82, width: 0.36, height: 0.38, radius: 0.09)
                    ], material: VehicleMaterialPalette.darkSteel, in: group)
                    VehicleGeometry.cylinder("AxleBoxBearingCap_\(bogieIndex)_\(Int(axleOffset * 100))_\(Int(side))", radius: 0.115, length: 0.06, at: SIMD3(side * 1.21, 0.82, z), axis: SIMD3<Float>(1, 0, 0), material: VehicleMaterialPalette.steel, in: group)
                    VehicleGeometry.box("AxleBoxInspectionPlate_\(bogieIndex)_\(Int(axleOffset * 100))_\(Int(side))", size: SIMD3<Float>(0.025, 0.16, 0.20), at: SIMD3(side * 1.204, 0.82, z), material: VehicleMaterialPalette.bodyShade, in: group)
                }
            }
        }
    }

    private static func buildAirSprings(in group: Entity) {
        for (bogieIndex, centerZ) in bogieCenters.enumerated() {
            for side: Float in [-1, 1] {
                let x = side * 0.65
                let z = centerZ
                VehicleGeometry.cylinder("AirSpringLowerSeat_\(bogieIndex)_\(Int(side))", radius: 0.29, length: 0.10, at: SIMD3(x, 0.98, z), material: VehicleMaterialPalette.steel, in: group)
                for fold in 0..<4 {
                    let radius: Float = fold % 2 == 0 ? 0.265 : 0.238
                    let y = 1.055 + Float(fold) * 0.075
                    VehicleGeometry.cylinder("AirSpringBellowsFold_\(bogieIndex)_\(Int(side))_\(fold)", radius: radius, length: 0.07, at: SIMD3(x, y, z), material: VehicleMaterialPalette.rubber, in: group)
                }
                VehicleGeometry.cylinder("AirSpringUpperSeat_\(bogieIndex)_\(Int(side))", radius: 0.30, length: 0.105, at: SIMD3(x, 1.37, z), material: VehicleMaterialPalette.steel, in: group)
                VehicleGeometry.cylinder("AirSpringRetainer_\(bogieIndex)_\(Int(side))", radius: 0.11, length: 0.14, at: SIMD3(x, 1.46, z), material: VehicleMaterialPalette.darkSteel, in: group)
                VehicleGeometry.rod("AirSpringAirLine_\(bogieIndex)_\(Int(side))", from: SIMD3(x, 1.05, z + side * 0.25), to: SIMD3(x, 1.33, z + side * 0.39), radius: 0.018, material: VehicleMaterialPalette.amber, in: group)
            }
        }
    }

    private static func buildUnderfloorEquipment(in group: Entity, detail: VehicleDetailLevel) {
        let equipment: [(String, Float, Float, Float)] = [
            ("TractionInverter", -4.25, 0.67, 1.45),
            ("AuxiliaryConverter", -1.75, 0.66, 1.12),
            ("AirCompressor", 0.80, 0.68, 0.92),
            ("BrakeResistor", 3.00, 0.70, 1.28),
            ("BatteryBox", 5.05, 0.66, 1.08)
        ]
        for (name, z, y, length) in equipment {
            VehicleAuthoredMesh.roundedLoft("\(name)_BeveledCasing", sections: [
                VehicleLoftSection(z: z - length * 0.5, centerX: 0, centerY: y, width: 1.08, height: 0.46, radius: 0.09),
                VehicleLoftSection(z: z, centerX: 0, centerY: y, width: 1.12, height: 0.49, radius: 0.10),
                VehicleLoftSection(z: z + length * 0.5, centerX: 0, centerY: y, width: 1.08, height: 0.46, radius: 0.09)
            ], material: VehicleMaterialPalette.undercoat, in: group)
            VehicleGeometry.box("\(name)_ServiceCover", size: SIMD3<Float>(0.92, 0.055, length * 0.70), at: SIMD3(0, y + 0.26, z), material: VehicleMaterialPalette.darkSteel, in: group)
            for side: Float in [-1, 1] {
                VehicleGeometry.box("\(name)_Mount_\(Int(side))", size: SIMD3<Float>(0.08, 0.17, 0.12), at: SIMD3(side * 0.49, y + 0.30, z), material: VehicleMaterialPalette.steel, in: group)
            }
            for slat in 0..<detail.grilleSlats {
                let offset = -length * 0.32 + Float(slat) * (length * 0.64 / Float(max(detail.grilleSlats - 1, 1)))
                VehicleGeometry.box("\(name)_CoolingFin_\(slat)", size: SIMD3<Float>(0.72, 0.018, 0.032), at: SIMD3(0, y + 0.04, z + offset), material: VehicleMaterialPalette.steel, in: group)
            }
        }
        for index in 0..<7 {
            let z = -5.4 + Float(index) * 1.8
            VehicleGeometry.box("UnderframeCrossmember_\(index)", size: SIMD3<Float>(2.32, 0.13, 0.14), at: SIMD3(0, 0.91, z), material: VehicleMaterialPalette.darkSteel, in: group)
        }
        VehicleGeometry.rod("BrakePipe", from: SIMD3(-0.72, 0.50, -8.7), to: SIMD3(-0.72, 0.50, 8.7), radius: 0.034, material: VehicleMaterialPalette.steel, in: group)
        VehicleGeometry.rod("MainAirPipe", from: SIMD3(0.72, 0.46, -8.7), to: SIMD3(0.72, 0.46, 8.7), radius: 0.034, material: VehicleMaterialPalette.amber, in: group)
        VehicleGeometry.rod("EquipmentCableTrunk", from: SIMD3(0, 0.47, -8.2), to: SIMD3(0, 0.47, 8.2), radius: 0.045, material: VehicleMaterialPalette.darkSteel, in: group)
    }

    private static func buildMotorEquipment(in group: Entity) {
        for (bogieIndex, centerZ) in bogieCenters.enumerated() {
            for side: Float in [-1, 1] {
                for axleSide: Float in [-1, 1] {
                    let z = centerZ + axleSide * 0.70
                    let x = side * 0.56
                    VehicleAuthoredMesh.roundedLoft("TractionMotorCasing_\(bogieIndex)_\(Int(side))_\(Int(axleSide))", sections: [
                        VehicleLoftSection(z: z - 0.40, centerX: x, centerY: 0.54, width: 0.52, height: 0.38, radius: 0.14),
                        VehicleLoftSection(z: z, centerX: x, centerY: 0.54, width: 0.57, height: 0.41, radius: 0.15),
                        VehicleLoftSection(z: z + 0.40, centerX: x, centerY: 0.54, width: 0.52, height: 0.38, radius: 0.14)
                    ], material: VehicleMaterialPalette.undercoat, in: group)
                    VehicleGeometry.cylinder("MotorEndBell_\(bogieIndex)_\(Int(side))_\(Int(axleSide))", radius: 0.17, length: 0.08, at: SIMD3(side * 0.87, 0.54, z), axis: SIMD3<Float>(1, 0, 0), material: VehicleMaterialPalette.steel, in: group)
                    VehicleGeometry.cylinder("MotorFanCover_\(bogieIndex)_\(Int(side))_\(Int(axleSide))", radius: 0.12, length: 0.035, at: SIMD3(side * 0.92, 0.54, z), axis: SIMD3<Float>(1, 0, 0), material: VehicleMaterialPalette.darkSteel, in: group)
                    VehicleGeometry.box("MotorMount_\(bogieIndex)_\(Int(side))_\(Int(axleSide))", size: SIMD3<Float>(0.16, 0.10, 0.23), at: SIMD3(x, 0.77, z), material: VehicleMaterialPalette.steel, in: group)
                    VehicleGeometry.box("GearCase_\(bogieIndex)_\(Int(side))_\(Int(axleSide))", size: SIMD3<Float>(0.30, 0.28, 0.34), at: SIMD3(side * 0.88, 0.45, z + axleSide * 0.28), material: VehicleMaterialPalette.darkSteel, in: group)
                    VehicleGeometry.rod("MotorPowerLead_\(bogieIndex)_\(Int(side))_\(Int(axleSide))", from: SIMD3(x, 0.62, z), to: SIMD3(side * 0.36, 0.75, z + axleSide * 0.38), radius: 0.028, material: VehicleMaterialPalette.amber, in: group)
                }
            }
        }
    }

    private static func buildPantograph(in group: Entity) {
        VehicleGeometry.box("PantographMountingPlinth", size: SIMD3<Float>(1.18, 0.10, 0.50), at: SIMD3(0, 3.59, 2.70), material: VehicleMaterialPalette.bodyShade, in: group)
        for side: Float in [-1, 1] {
            VehicleGeometry.cylinder("PantographInsulatorBase_\(Int(side))", radius: 0.14, length: 0.08, at: SIMD3(side * 0.40, 3.69, 2.70), material: VehicleMaterialPalette.steel, in: group)
            VehicleGeometry.cylinder("PantographInsulator_\(Int(side))", radius: 0.09, length: 0.34, at: SIMD3(side * 0.40, 3.89, 2.70), material: VehicleMaterialPalette.glassEdge, in: group)
            for rib in 0..<3 {
                VehicleGeometry.cylinder("PantographInsulatorRib_\(Int(side))_\(rib)", radius: 0.125, length: 0.025, at: SIMD3(side * 0.40, 3.80 + Float(rib) * 0.09, 2.70), material: VehicleMaterialPalette.bodyShade, in: group)
            }
        }
        let moving = VehicleGeometry.group("PantographArticulatedFrame", in: group)
        moving.position = SIMD3(0, 3.98, 2.70)
        VehicleGeometry.rod("PantographLowerArmLeft", from: SIMD3(-0.38, 0, -0.16), to: SIMD3(0.02, 0.38, -0.16), radius: 0.042, material: VehicleMaterialPalette.steel, in: moving)
        VehicleGeometry.rod("PantographLowerArmRight", from: SIMD3(0.38, 0, 0.16), to: SIMD3(-0.02, 0.38, 0.16), radius: 0.042, material: VehicleMaterialPalette.steel, in: moving)
        VehicleGeometry.rod("PantographUpperArmLeft", from: SIMD3(0.02, 0.38, -0.16), to: SIMD3(0.32, 0.76, -0.16), radius: 0.036, material: VehicleMaterialPalette.steel, in: moving)
        VehicleGeometry.rod("PantographUpperArmRight", from: SIMD3(-0.02, 0.38, 0.16), to: SIMD3(-0.32, 0.76, 0.16), radius: 0.036, material: VehicleMaterialPalette.steel, in: moving)
        for side: Float in [-1, 1] {
            VehicleGeometry.cylinder("PantographPivot_\(Int(side))", radius: 0.065, length: 0.40, at: SIMD3(0, 0.38, side * 0.16), axis: SIMD3<Float>(0, 0, 1), material: VehicleMaterialPalette.darkSteel, in: moving)
        }
        VehicleGeometry.box("PantographContactStrip", size: SIMD3<Float>(0.96, 0.065, 0.13), at: SIMD3(0, 0.81, 0), material: VehicleMaterialPalette.darkSteel, in: moving)
        for side: Float in [-1, 1] {
            VehicleGeometry.box("PantographContactHorn_\(Int(side))", size: SIMD3<Float>(0.08, 0.11, 0.13), at: SIMD3(side * 0.49, 0.77, 0), material: VehicleMaterialPalette.steel, in: moving)
        }
    }

    private static func buildCouplers(in group: Entity) {
        for end: Float in [-1, 1] {
            let front = end < 0
            let z = end * 9.72
            VehicleGeometry.box("GangwayMount_\(Int(end))", size: SIMD3<Float>(1.02, 1.62, 0.16), at: SIMD3(0, 2.18, z), material: VehicleMaterialPalette.darkSteel, in: group)
            VehicleGeometry.box("GangwayRubberBellows_\(Int(end))", size: SIMD3<Float>(0.88, 1.49, 0.13), at: SIMD3(0, 2.18, z + end * 0.06), material: VehicleMaterialPalette.rubber, in: group)
            VehicleGeometry.box("CouplerDraftGear_\(Int(end))", size: SIMD3<Float>(0.48, 0.32, 0.52), at: SIMD3(0, 0.72, end * 9.80), material: VehicleMaterialPalette.darkSteel, in: group)
            VehicleAuthoredMesh.roundedLoft("CouplerShank_\(Int(end))", sections: [
                VehicleLoftSection(z: end * 9.93, centerX: 0, centerY: 0.70, width: 0.22, height: 0.19, radius: 0.055),
                VehicleLoftSection(z: end * 10.12, centerX: 0, centerY: 0.70, width: 0.22, height: 0.19, radius: 0.055),
                VehicleLoftSection(z: end * 10.30, centerX: 0, centerY: 0.70, width: 0.20, height: 0.17, radius: 0.05)
            ], material: VehicleMaterialPalette.steel, in: group)
            VehicleGeometry.cylinder("CouplerHeadCollar_\(Int(end))", radius: 0.23, length: 0.12, at: SIMD3(0, 0.70, end * 10.28), axis: SIMD3<Float>(0, 0, 1), material: VehicleMaterialPalette.darkSteel, in: group)
            VehicleGeometry.box("CouplerHead_\(Int(end))", size: SIMD3<Float>(0.40, 0.27, 0.34), at: SIMD3(0, 0.67, end * 10.43), material: VehicleMaterialPalette.steel, in: group)
            VehicleGeometry.box("CouplerJawOpening_\(Int(end))", size: SIMD3<Float>(0.21, 0.095, 0.018), at: SIMD3(0, 0.70, end * 10.61), material: VehicleMaterialPalette.darkSteel, in: group)
            VehicleGeometry.cylinder("CouplerPin_\(Int(end))", radius: 0.035, length: 0.18, at: SIMD3(0, 0.84, end * 10.47), material: VehicleMaterialPalette.amber, in: group)
            if front {
                VehicleGeometry.box("FrontCouplerGuard", size: SIMD3<Float>(0.66, 0.12, 0.08), at: SIMD3(0, 1.00, -9.98), material: VehicleMaterialPalette.bodyShade, in: group)
            }
        }
    }

    private static func buildMarkerLights(in group: Entity) {
        for side: Float in [-1, 1] {
            VehicleGeometry.sphere("FrontMarkerLamp_\(Int(side))", radius: 0.048, at: SIMD3(side * 1.10, 2.18, -9.78), material: VehicleMaterialPalette.lamp, in: group)
            for end: Float in [-1, 1] {
                let z = end * 8.96
                VehicleGeometry.box("SideMarkerGasket_\(Int(side))_\(Int(end))", size: SIMD3<Float>(0.035, 0.13, 0.18), at: SIMD3(side * 1.445, 2.28, z), material: VehicleMaterialPalette.darkSteel, in: group)
                VehicleGeometry.box("SideMarkerLens_\(Int(side))_\(Int(end))", size: SIMD3<Float>(0.018, 0.075, 0.12), at: SIMD3(side * 1.468, 2.28, z), material: VehicleMaterialPalette.amber, in: group)
            }
        }
    }

    private static func buildHeadlights(in group: Entity) {
        for side: Float in [-1, 1] {
            VehicleGeometry.cylinder("HeadlightBezel_\(Int(side))", radius: 0.135, length: 0.075, at: SIMD3(side * 0.91, 1.79, -9.75), axis: SIMD3<Float>(0, 0, 1), material: VehicleMaterialPalette.darkSteel, in: group)
            VehicleGeometry.cylinder("HeadlightReflector_\(Int(side))", radius: 0.105, length: 0.035, at: SIMD3(side * 0.91, 1.79, -9.80), axis: SIMD3<Float>(0, 0, 1), material: VehicleMaterialPalette.steel, in: group)
            let lens = VehicleGeometry.sphere("FrontHeadlight_\(Int(side))", radius: 0.082, at: SIMD3(side * 0.91, 1.79, -9.825), material: VehicleMaterialPalette.lamp, in: group)
            lens.name = "FrontHeadlight_\(Int(side))"
        }
    }

    private static func buildTailLights(in group: Entity) {
        for side: Float in [-1, 1] {
            VehicleGeometry.cylinder("TailLightBezel_\(Int(side))", radius: 0.105, length: 0.06, at: SIMD3(side * 0.92, 1.82, 9.72), axis: SIMD3<Float>(0, 0, 1), material: VehicleMaterialPalette.darkSteel, in: group)
            VehicleGeometry.cylinder("TailLightReflector_\(Int(side))", radius: 0.078, length: 0.028, at: SIMD3(side * 0.92, 1.82, 9.76), axis: SIMD3<Float>(0, 0, 1), material: VehicleMaterialPalette.steel, in: group)
            VehicleGeometry.sphere("RearTailLight_\(Int(side))", radius: 0.062, at: SIMD3(side * 0.92, 1.82, 9.79), material: VehicleMaterialPalette.redLamp, in: group)
        }
    }

    private static func buildDestinationDisplay(in group: Entity) {
        VehicleGeometry.box("DestinationDisplayHousing", size: SIMD3<Float>(1.12, 0.34, 0.14), at: SIMD3(0, 3.16, -9.77), material: VehicleMaterialPalette.darkSteel, in: group)
        VehicleGeometry.box("DestinationDisplayBezel", size: SIMD3<Float>(1.00, 0.25, 0.035), at: SIMD3(0, 3.16, -9.856), material: VehicleMaterialPalette.steel, in: group)
        VehicleAuthoredMesh.quad("DestinationDisplayFace", corners: [
            SIMD3<Float>(-0.47, 3.045, -9.88), SIMD3<Float>(0.47, 3.045, -9.88),
            SIMD3<Float>(0.47, 3.275, -9.88), SIMD3<Float>(-0.47, 3.275, -9.88)
        ], material: VehicleMaterialPalette.display, reverseWinding: true, in: group)
        let glyphs: [[String]] = [
            ["10001", "10001", "10001", "11111", "10001", "10001", "10001"], // H
            ["11110", "10001", "10001", "11110", "10100", "10010", "10001"], // R-like route mark
            ["01110", "10001", "10011", "10101", "11001", "10001", "01110"], // 0
            ["00100", "01100", "00100", "00100", "00100", "00100", "01110"]  // 1
        ]
        let columnsPerGlyph = 5
        let pixelX: Float = 0.037
        let pixelY: Float = 0.024
        let totalColumns = glyphs.count * columnsPerGlyph + glyphs.count - 1
        let startX = -Float(totalColumns - 1) * pixelX * 0.5
        let startY: Float = 3.16 + Float(glyphs[0].count - 1) * pixelY * 0.5
        for (glyphIndex, rows) in glyphs.enumerated() {
            for (row, pattern) in rows.enumerated() {
                for (column, bit) in pattern.enumerated() where bit == "1" {
                    let x = startX + Float(glyphIndex * 6 + column) * pixelX
                    let y = startY - Float(row) * pixelY
                    VehicleGeometry.box("DestinationPixel_\(glyphIndex)_\(row)_\(column)", size: SIMD3<Float>(0.021, 0.014, 0.009), at: SIMD3(x, y, -9.895), material: VehicleMaterialPalette.amber, in: group)
                }
            }
        }
    }

    private static func buildSurfaceDetails(in group: Entity, detail: VehicleDetailLevel) {
        let rivetsPerSide = detail == .high ? 16 : 8
        for side: Float in [-1, 1] {
            for index in 0..<rivetsPerSide {
                let z = -8.55 + Float(index) * 17.1 / Float(max(rivetsPerSide - 1, 1))
                for y: Float in [1.34, 3.28] {
                    VehicleGeometry.sphere("BodySeamRivet_\(Int(side))_\(index)_\(Int(y * 100))", radius: 0.018, at: SIMD3(side * 1.455, y, z), material: VehicleMaterialPalette.steel, in: group)
                }
            }
            for index in 0..<5 {
                let z = -8.0 + Float(index) * 4.0
                VehicleGeometry.box("SideAccessPanel_\(Int(side))_\(index)", size: SIMD3<Float>(0.02, 0.31, 0.55), at: SIMD3(side * 1.455, 1.62, z), material: VehicleMaterialPalette.bodyShade, in: group)
                VehicleGeometry.box("SideAccessPanelSeam_\(Int(side))_\(index)", size: SIMD3<Float>(0.012, 0.012, 0.43), at: SIMD3(side * 1.47, 1.62, z), material: VehicleMaterialPalette.darkSteel, in: group)
            }
        }
        let roofSeams = detail == .high ? 17 : 9
        for index in 0..<roofSeams {
            let z = -8.5 + Float(index) * 17.0 / Float(max(roofSeams - 1, 1))
            VehicleGeometry.box("RoofTransverseSeam_\(index)", size: SIMD3<Float>(2.42, 0.012, 0.018), at: SIMD3(0, 3.54, z), material: VehicleMaterialPalette.bodyShade, in: group)
        }
        for index in 0..<12 {
            let z = -7.7 + Float(index) * 1.4
            VehicleGeometry.box("UnderframeInspectionRib_\(index)", size: SIMD3<Float>(0.08, 0.14, 0.13), at: SIMD3(index % 2 == 0 ? -0.96 : 0.96, 0.64, z), material: VehicleMaterialPalette.steel, in: group)
        }
        for side: Float in [-1, 1] {
            VehicleGeometry.box("RoofAntennaFoot_\(Int(side))", size: SIMD3<Float>(0.22, 0.045, 0.28), at: SIMD3(side * 0.85, 3.58, -7.9), material: VehicleMaterialPalette.darkSteel, in: group)
            VehicleGeometry.cylinder("RoofAntenna_\(Int(side))", radius: 0.027, length: 0.24, at: SIMD3(side * 0.85, 3.72, -7.9), material: VehicleMaterialPalette.steel, in: group)
        }
    }
}
