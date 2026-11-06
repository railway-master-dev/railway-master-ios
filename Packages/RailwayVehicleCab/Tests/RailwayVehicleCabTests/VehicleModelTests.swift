import XCTest
import RealityKit
@testable import RailwayVehicleCab

final class VehicleModelTests: XCTestCase {
    func testDefaultSpecificationIsValid() {
        XCTAssertTrue(VehicleSpecification.fictionalPrototype.validationIssues().isEmpty)
    }

    func testInvalidDimensionsAreReported() {
        var specification = VehicleSpecification.fictionalPrototype
        specification.carLengthMeters = 30
        specification.passengerCapacity = 0
        XCTAssertEqual(specification.validationIssues().count, 2)
    }

    func testBuildCreatesTenIndependentSubsystems() {
        let model = RailwayVehicleModelBuilder.build()
        XCTAssertEqual(model.groups.count, 10)
        for group: VehiclePartGroup in [
            .carBody, .doors, .glazing, .cabInterior, .cabControls,
            .runningGear, .underfloorEquipment, .roofEquipment, .pantograph, .lighting
        ] {
            XCTAssertNotNil(model.groups[group], "Missing group: \(group)")
        }
        XCTAssertEqual(model.cabControls.nodes.count, 6)
    }

    func testControlValueIsClampedAndApplied() {
        let model = RailwayVehicleModelBuilder.build()
        model.cabControls.setValue(99, for: .masterController)
        XCTAssertEqual(model.cabControls.value(for: .masterController), 5)
        model.cabControls.setValue(-99, for: .brakeLever)
        XCTAssertEqual(model.cabControls.value(for: .brakeLever), 0)
    }

    func testControlNodeHasComponent() {
        let model = RailwayVehicleModelBuilder.build()
        let handle = try! XCTUnwrap(model.cabControls.nodes[.brakeLever])
        XCTAssertEqual(handle.components[VehicleCabControlComponent.self]?.kind, .brakeLever)
    }
}
