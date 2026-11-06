import XCTest
import RailwayAudioEnhancements
import RealityKit
import simd
@testable import RailwayVehicleHighFidelity

final class VehicleHighFidelityTests: XCTestCase {
    func testDefaultFictionalSpecificationIsValidAndScaled() {
        let spec = RailwayVehicleHighFidelitySpecification.fictionalPrototype
        XCTAssertTrue(spec.validationIssues().isEmpty)
        XCTAssertEqual(spec.modelScale.x, 1, accuracy: 0.0001)
        XCTAssertEqual(spec.modelScale.y, 1, accuracy: 0.0001)
        XCTAssertEqual(spec.modelScale.z, 1, accuracy: 0.0001)
        var enlarged = spec
        enlarged.carLengthMeters = 21
        enlarged.carWidthMeters = 3.0
        enlarged.carHeightMeters = 4.0
        XCTAssertEqual(enlarged.modelScale.x, 3.0 / 2.8, accuracy: 0.0001)
        XCTAssertEqual(enlarged.modelScale.y, 4.0 / 3.65, accuracy: 0.0001)
        XCTAssertEqual(enlarged.modelScale.z, 21.0 / 19.5, accuracy: 0.0001)
    }

    func testInvalidOrNonFiniteDimensionsAreReported() {
        var spec = RailwayVehicleHighFidelitySpecification.fictionalPrototype
        spec.identifier = "  "
        spec.carLengthMeters = .infinity
        spec.carWidthMeters = 1.0
        spec.carHeightMeters = .nan
        XCTAssertEqual(spec.validationIssues().count, 4)
    }

    func testBuildCreatesAllIndependentVehicleSubsystems() {
        let model = RailwayVehicleHighFidelityBuilder.build()
        XCTAssertEqual(model.parts.count, HighFidelityVehiclePart.allCases.count)
        XCTAssertEqual(Set(model.parts.keys), Set(HighFidelityVehiclePart.allCases))
        XCTAssertEqual(model.controls.nodes.count, CabControlKind.allCases.count)
        XCTAssertGreaterThan(countEntities(model.root), 300)
        let names = entityNames(model.root)
        for expected in ["FrontWindshieldGlass_0", "DoorLeafWindow_1_0", "BogieAssembly_0", "BrakePipe", "HVACAssembly_0", "PantographMovingLinkage", "WindshieldWiperPivot_1", "Speedometer_Bezel", "GaugeNeedle_BrakePipeGauge"] {
            XCTAssertTrue(names.contains(expected), "Missing generated detail: \(expected)")
        }
    }

    func testControlValuesClampToDeclaredRangesAndMoveNodes() throws {
        let model = RailwayVehicleHighFidelityBuilder.build()
        let master = try XCTUnwrap(model.controls.nodes[.masterController])
        let initialRotation = master.orientation.vector
        _ = model.controls.setValue(99, for: .masterController)
        XCTAssertEqual(model.controls.value(for: .masterController), 5)
        XCTAssertNotEqual(master.orientation.vector, initialRotation)
        _ = model.controls.setValue(-99, for: .brakeLever)
        XCTAssertEqual(model.controls.value(for: .brakeLever), 0)
        _ = model.controls.setValue(0.5, for: .reverser)
        XCTAssertEqual(model.controls.value(for: .reverser), 0.5, accuracy: 0.0001)
        _ = model.controls.setValue(.nan, for: .masterController)
        XCTAssertEqual(model.controls.value(for: .masterController), 0)
    }

    func testDoorAndWiperVisualHandlesRespondToState() throws {
        let model = RailwayVehicleHighFidelityBuilder.build()
        let door = try XCTUnwrap(findEntity(named: "AnimatedDoorPanel_-1_0_-1", in: model.root))
        let closedZ = door.position.z
        model.animatedParts.setDoorOpenFraction(1)
        XCTAssertNotEqual(door.position.z, closedZ)
        model.animatedParts.setDoorOpenFraction(0)
        XCTAssertEqual(door.position.z, closedZ, accuracy: 0.0001)
        let wiper = try XCTUnwrap(findEntity(named: "WindshieldWiperPivot_-1", in: model.root))
        let initialWiperRotation = wiper.orientation.vector
        model.animatedParts.setWiperSweep(20)
        XCTAssertNotEqual(wiper.orientation.vector, initialWiperRotation)
    }

    func testWheelAndGaugeUpdatesAreFiniteAndIdempotentForSameTelemetry() throws {
        let model = RailwayVehicleHighFidelityBuilder.build()
        let needle = try XCTUnwrap(findEntity(named: "GaugeNeedle_Speedometer", in: model.root))
        model.animatedParts.setTelemetry(speedKmh: 60, brakePipePressureKPa: 500)
        let first = needle.orientation.vector
        model.animatedParts.setTelemetry(speedKmh: 60, brakePipePressureKPa: 500)
        XCTAssertEqual(needle.orientation.vector, first)
        model.animatedParts.advanceWheels(distanceMeters: 1)
        model.animatedParts.advanceWheels(distanceMeters: .infinity)
        model.animatedParts.setPantographExtension(1)
        model.animatedParts.setHeadlightsEnabled(false)
        XCTAssertFalse(findEntity(named: "FrontHeadlamp_-1", in: model.root)?.isEnabled ?? true)
    }

    func testBogieYawAndTimeDrivenWiperMotionAreBoundedAndRepeatable() throws {
        let model = RailwayVehicleHighFidelityBuilder.build()
        let frontBogie = try XCTUnwrap(findEntity(named: "BogieAssembly_0", in: model.root))
        let frontWiper = try XCTUnwrap(findEntity(named: "WindshieldWiperPivot_-1", in: model.root))
        let originalBogie = frontBogie.orientation.vector
        let originalWiper = frontWiper.orientation.vector

        model.animatedParts.setBogieYaw(frontRadians: 4, rearRadians: -4)
        let curvedBogie = frontBogie.orientation.vector
        XCTAssertNotEqual(curvedBogie, originalBogie)
        model.animatedParts.setBogieYaw(frontRadians: 4, rearRadians: -4)
        XCTAssertEqual(frontBogie.orientation.vector, curvedBogie)

        model.animatedParts.setWiperState(.high, simulationTimeSeconds: 0.25)
        let movingWiper = frontWiper.orientation.vector
        XCTAssertNotEqual(movingWiper, originalWiper)
        model.animatedParts.setWiperState(.high, simulationTimeSeconds: 0.25)
        XCTAssertEqual(frontWiper.orientation.vector, movingWiper)
        model.animatedParts.setWiperState(.off, simulationTimeSeconds: .infinity)
        XCTAssertEqual(frontWiper.orientation.vector, originalWiper)
    }

    func testCabIndicatorStateControlsAllFictionalAnnunciatorLenses() throws {
        // Annunciator lenses (IndicatorLens_*) are only emitted for center-monitor
        // desks; the default fieldChopper desk uses its ChopperLamp row instead.
        let model = RailwayVehicleHighFidelityBuilder.build(desk: FictionalCabAndSoundCatalog.vvvf)
        let atc = try XCTUnwrap(findEntity(named: "IndicatorLens_ATC", in: model.root))
        let door = try XCTUnwrap(findEntity(named: "IndicatorLens_DOOR", in: model.root))
        let fault = try XCTUnwrap(findEntity(named: "IndicatorLens_FAULT", in: model.root))
        XCTAssertFalse(atc.isEnabled)
        XCTAssertFalse(door.isEnabled)
        XCTAssertFalse(fault.isEnabled)

        model.animatedParts.setCabIndicatorState(VehicleCabIndicatorState(atcActive: true, doorsOpen: true))
        XCTAssertTrue(atc.isEnabled)
        XCTAssertTrue(door.isEnabled)
        XCTAssertFalse(fault.isEnabled)

        model.animatedParts.setCabIndicatorState(VehicleCabIndicatorState())
        XCTAssertFalse(atc.isEnabled)
        XCTAssertFalse(door.isEnabled)
    }

    private func entityNames(_ root: Entity) -> Set<String> {
        var names: Set<String> = [root.name]
        for child in root.children { names.formUnion(entityNames(child)) }
        return names
    }

    private func countEntities(_ root: Entity) -> Int {
        1 + root.children.reduce(0) { $0 + countEntities($1) }
    }

    private func findEntity(named name: String, in root: Entity) -> Entity? {
        if root.name == name { return root }
        for child in root.children {
            if let match = findEntity(named: name, in: child) { return match }
        }
        return nil
    }
}
