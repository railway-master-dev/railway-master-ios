import XCTest
@testable import TrainPhysics

/// 8-car and 10-car sets share a control-type traction character.
/// The longer set is heavier and its brake pipe is longer, so the same fixed ticks
/// produce less acceleration and a longer stop. Figures are PLACEHOLDER.
final class FormationLengthPhysicsTests: XCTestCase {
    private var dt: Double { TrainPhysicsEngine.fixedTimeStepSeconds }

    private func pair(_ kind: String) -> (TrainsetProfile, TrainsetProfile) {
        switch kind {
        case "vvvf": (FictionalFormationCatalog.vvvf8, FictionalFormationCatalog.vvvf10)
        case "chopper": (FictionalFormationCatalog.fieldChopper8, FictionalFormationCatalog.fieldChopper10)
        default: (FictionalFormationCatalog.resistance8, FictionalFormationCatalog.resistance10)
        }
    }

    func testFormationProfilesArePlaceholderAndKeepFourMotorsOnBothLengths() {
        let loadedIDs = Set(try! FictionalProfileCatalog.loadBundled().map(\.identifier))
        for profile in FictionalFormationCatalog.all {
            XCTAssertTrue(loadedIDs.contains(profile.identifier))
            XCTAssertTrue(profile.fictionalNotice.contains("PLACEHOLDER"))
            XCTAssertTrue(profile.fictionalNotice.contains("実車安全計算"))
            XCTAssertTrue(profile.validationIssues().isEmpty, profile.identifier)
            XCTAssertEqual(profile.traction.motorCount, 16)
            XCTAssertEqual(profile.cars.filter { $0.drivenMassFraction > 0 }.count, 4)
            XCTAssertTrue(profile.carCount == 8 || profile.carCount == 10)
        }
        for kind in ["vvvf", "chopper", "resistance"] {
            let (eight, ten) = pair(kind)
            XCTAssertEqual(eight.traction.maximumForceN, ten.traction.maximumForceN)
            XCTAssertEqual(eight.traction.mode, ten.traction.mode)
            XCTAssertGreaterThan(ten.totalMassKg(passengerLoadFactor: 0), eight.totalMassKg(passengerLoadFactor: 0))
            XCTAssertEqual(ten.brakeSystem.propagationSecondsPerCar, eight.brakeSystem.propagationSecondsPerCar)
            XCTAssertGreaterThan(
                ten.cars.map(\.maximumServiceBrakeForceN).reduce(0, +),
                eight.cars.map(\.maximumServiceBrakeForceN).reduce(0, +)
            )
            let eightSpecific = eight.cars.map(\.maximumServiceBrakeForceN).reduce(0, +) / eight.totalMassKg(passengerLoadFactor: 0)
            let tenSpecific = ten.cars.map(\.maximumServiceBrakeForceN).reduce(0, +) / ten.totalMassKg(passengerLoadFactor: 0)
            XCTAssertLessThan(tenSpecific, eightSpecific, "\(kind) 10-car brake force per kilogram is lower")
        }
        XCTAssertGreaterThan(FictionalFormationCatalog.vvvf8.traction.maximumForceN, FictionalFormationCatalog.fieldChopper8.traction.maximumForceN)
        XCTAssertGreaterThan(FictionalFormationCatalog.fieldChopper8.traction.maximumForceN, FictionalFormationCatalog.resistance8.traction.maximumForceN)
        XCTAssertGreaterThan(FictionalFormationCatalog.vvvf8.traction.maximumRegenerativeShare, FictionalFormationCatalog.resistance8.traction.maximumRegenerativeShare)
        XCTAssertGreaterThan(FictionalFormationCatalog.resistance8.brakeSystem.propagationSecondsPerCar, FictionalFormationCatalog.vvvf8.brakeSystem.propagationSecondsPerCar)
    }

    func testTenCarAcceleratesSlowerAndStopsLongerThanEightCar() throws {
        for kind in ["vvvf", "chopper", "resistance"] {
            let (eightProfile, tenProfile) = pair(kind)
            var eight = try TrainPhysicsEngine(profile: eightProfile, passengerLoadFactor: 0)
            var ten = try TrainPhysicsEngine(profile: tenProfile, passengerLoadFactor: 0)
            let power = SimulationControls(throttleNotch: eightProfile.maximumTractionNotch)
            let ticks = 8 * 120
            for _ in 0..<ticks {
                _ = eight.advance(realDeltaSeconds: dt, controls: power)
                _ = ten.advance(realDeltaSeconds: dt, controls: power)
            }
            XCTAssertGreaterThan(eight.speedMps, ten.speedMps + 0.4, "\(kind) 8-car should be faster after the same power ticks")
            XCTAssertGreaterThan(eight.telemetry.physicalMassKg, 0)
            XCTAssertGreaterThan(ten.telemetry.physicalMassKg, eight.telemetry.physicalMassKg)

            let target = 12.0
            var eightBrake = try TrainPhysicsEngine(profile: eightProfile, passengerLoadFactor: 0)
            var tenBrake = try TrainPhysicsEngine(profile: tenProfile, passengerLoadFactor: 0)
            accelerate(&eightBrake, to: target, notch: eightProfile.maximumTractionNotch)
            accelerate(&tenBrake, to: target, notch: tenProfile.maximumTractionNotch)
            XCTAssertGreaterThanOrEqual(eightBrake.speedMps, target)
            XCTAssertGreaterThanOrEqual(tenBrake.speedMps, target)
            XCTAssertEqual(eightBrake.speedMps, tenBrake.speedMps, accuracy: 0.5)

            let brake = SimulationControls(throttleNotch: 0, brakeNotch: 7)
            let eightStop = stoppingDistance(from: &eightBrake, controls: brake)
            let tenStop = stoppingDistance(from: &tenBrake, controls: brake)
            XCTAssertTrue(eightStop.reachedRest, "\(kind) 8-car should stop")
            XCTAssertTrue(tenStop.reachedRest, "\(kind) 10-car should stop")
            XCTAssertGreaterThan(tenStop.distanceM, eightStop.distanceM + 1, "\(kind) 10-car stopping distance")
        }
    }

    func testLongerConsistBuildsRearCylinderPressureLater() throws {
        let eight = FictionalFormationCatalog.resistance8
        let ten = FictionalFormationCatalog.resistance10
        var eightEngine = try TrainPhysicsEngine(profile: eight, passengerLoadFactor: 0)
        var tenEngine = try TrainPhysicsEngine(profile: ten, passengerLoadFactor: 0)
        accelerate(&eightEngine, to: 8, notch: eight.maximumTractionNotch)
        accelerate(&tenEngine, to: 8, notch: ten.maximumTractionNotch)
        let brake = SimulationControls(throttleNotch: 0, brakeNotch: 7)
        for _ in 0..<180 {
            _ = eightEngine.advance(realDeltaSeconds: dt, controls: brake)
            _ = tenEngine.advance(realDeltaSeconds: dt, controls: brake)
        }
        let eightRear = eightEngine.telemetry.cars.last?.brakeCylinderPressureKPa ?? 0
        let tenRear = tenEngine.telemetry.cars.last?.brakeCylinderPressureKPa ?? 0
        XCTAssertGreaterThan(eightRear, tenRear)
        XCTAssertGreaterThan(eightRear, 0)
    }

    private func accelerate(_ engine: inout TrainPhysicsEngine, to speedMps: Double, notch: Int) {
        let power = SimulationControls(throttleNotch: notch)
        var ticks = 0
        while engine.speedMps < speedMps, ticks < 120 * 40 {
            _ = engine.advance(realDeltaSeconds: dt, controls: power)
            ticks += 1
        }
    }

    private func stoppingDistance(
        from engine: inout TrainPhysicsEngine,
        controls: SimulationControls
    ) -> (distanceM: Double, reachedRest: Bool) {
        let start = engine.positionM
        var ticks = 0
        while engine.speedMps > PhysicsConstants.stopSpeedThresholdMps, ticks < 120 * 90 {
            _ = engine.advance(realDeltaSeconds: dt, controls: controls)
            ticks += 1
        }
        return (engine.positionM - start, engine.speedMps <= PhysicsConstants.stopSpeedThresholdMps)
    }
}
