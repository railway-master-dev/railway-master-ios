import XCTest
import RealityKit
@testable import RailwayVehicleHighFidelity

final class VehicleComponentModelTests: XCTestCase {
    func testAllRequestedAssembliesHaveIndependentGroups() {
        let model = VehicleComponentModelBuilder.build()
        XCTAssertEqual(model.parts.count, VehicleComponentPart.allCases.count)
        XCTAssertEqual(Set(model.parts.keys), Set(VehicleComponentPart.allCases))
        XCTAssertEqual(Set(model.parts.values.map { ObjectIdentifier($0) }).count, VehicleComponentPart.allCases.count)

        for part in VehicleComponentPart.allCases {
            XCTAssertEqual(model.parts[part]?.name, "VehicleComponent_\(part.rawValue)")
        }
    }

    func testAuthoredSurfaceAndDetailedPartsArePresent() {
        let model = VehicleComponentModelBuilder.build()
        let names = entityNames(model.root)
        let expected = [
            "FrontNoseLowerShell",
            "FrontApost_-1",
            "CurvedRoofCrown",
            "FrontWindshieldGlass_0",
            "PassengerWindowGlass_-1_0",
            "DoorLeaf_-1_0_-1",
            "DoorLeafGlass_1_0_1",
            "BogieSideFrame_-1_0",
            "TractionInverter_BeveledCasing",
            "TractionMotorCasing_0_-1_-1",
            "AirSpringBellowsFold_0_-1_0",
            "PantographContactStrip",
            "CouplerHead_-1",
            "SideMarkerLens_1_-1",
            "FrontHeadlight_1",
            "RearTailLight_1",
            "DestinationDisplayFace",
            "SideAccessPanel_1_0"
        ]
        for name in expected {
            XCTAssertTrue(names.contains(name), "Missing modeled component: \(name)")
        }
    }

    func testSpecificationAndDetailLevelAreApplied() {
        var specification = RailwayVehicleHighFidelitySpecification.fictionalPrototype
        specification.identifier = "HF01-test"
        specification.carLengthMeters = 21
        specification.carWidthMeters = 3
        specification.carHeightMeters = 4
        specification.detailLevel = .balanced

        let model = VehicleComponentModelBuilder.build(specification)
        XCTAssertEqual(model.root.name, "HF01-test_componentModel")
        XCTAssertEqual(model.root.scale.x, specification.modelScale.x, accuracy: 0.0001)
        XCTAssertEqual(model.root.scale.y, specification.modelScale.y, accuracy: 0.0001)
        XCTAssertEqual(model.root.scale.z, specification.modelScale.z, accuracy: 0.0001)
        XCTAssertEqual(model.specification.identifier, specification.identifier)
    }

    private func entityNames(_ root: Entity) -> Set<String> {
        var names: Set<String> = [root.name]
        for child in root.children {
            names.formUnion(entityNames(child))
        }
        return names
    }
}
