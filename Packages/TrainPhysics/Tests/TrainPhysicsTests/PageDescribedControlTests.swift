import XCTest
@testable import TrainPhysics

/// Behaviors named on the public BVE pages. Timings other than the published 20 km/h cruise are PLACEHOLDER.
final class PageDescribedControlTests: XCTestCase {
    private var dt: Double { TrainPhysicsEngine.fixedTimeStepSeconds }

    private func ticks(_ seconds: Double) -> Int { Int((seconds / dt).rounded()) }

    private func run(_ engine: inout TrainPhysicsEngine, seconds: Double, controls: SimulationControls, track: TrackCondition = .level) {
        for _ in 0..<ticks(seconds) {
            _ = engine.advance(realDeltaSeconds: dt, controls: controls, track: track)
        }
    }

    func testSourcesStayQualitativeAndTheTenCar4000IsAnExtraPlaceholder() {
        XCTAssertEqual(FictionalPageDescribedControl.kind(forProfileIdentifier: "fictional-field-chopper-t01"), .none)
        XCTAssertEqual(FictionalPageDescribedControl.kind(forProfileIdentifier: FictionalFormationCatalog.vvvf8.identifier), .vvvfCruise)
        XCTAssertEqual(FictionalPageDescribedControl.kind(forProfileIdentifier: FictionalFormationCatalog.fieldChopper8.identifier), .fieldChopperCam)
        XCTAssertEqual(FictionalPageDescribedControl.kind(forProfileIdentifier: FictionalFormationCatalog.resistance8.identifier), .resistanceCam)
        XCTAssertTrue(FictionalFormationCatalog.vvvf8.fictionalNotice.contains("20km/h"))
        XCTAssertTrue(FictionalFormationCatalog.vvvf8.fictionalNotice.contains("moribayashi80.tsuyushiba.com/Entry/15"))
        XCTAssertTrue(FictionalFormationCatalog.fieldChopper8.fictionalNotice.contains("bve_sb2000"))
        XCTAssertTrue(FictionalFormationCatalog.resistance8.fictionalNotice.contains("bve_sb4000"))
        XCTAssertTrue(FictionalFormationCatalog.resistance8.fictionalNotice.contains("4両"))
        XCTAssertFalse(FictionalFormationCatalog.resistance8.fictionalNotice.contains("追加PLACEHOLDER"))
        XCTAssertTrue(FictionalFormationCatalog.resistance10.fictionalNotice.contains("追加PLACEHOLDER"))
        XCTAssertTrue(FictionalFormationCatalog.resistance10.displayName.contains("追加PLACEHOLDER"))
        for profile in FictionalFormationCatalog.all {
            XCTAssertTrue(profile.fictionalNotice.contains("PLACEHOLDER"))
            XCTAssertTrue(profile.fictionalNotice.contains("実車安全計算"))
        }
    }

    func testVvvfCruiseHolds20AfterALongNotch1AndHoldsCurrentSpeedAbove20() throws {
        var shortHold = try TrainPhysicsEngine(profile: FictionalFormationCatalog.vvvf8, passengerLoadFactor: 0)
        run(&shortHold, seconds: 1.5, controls: SimulationControls(throttleNotch: 1))
        run(&shortHold, seconds: 25, controls: SimulationControls(throttleNotch: 2))
        XCTAssertNil(shortHold.telemetry.controlIndicators.cruiseTargetKmh)
        XCTAssertGreaterThan(shortHold.speedMps * 3.6, 25)

        var armed = try TrainPhysicsEngine(profile: FictionalFormationCatalog.vvvf8, passengerLoadFactor: 0)
        run(&armed, seconds: 2.5, controls: SimulationControls(throttleNotch: 1))
        run(&armed, seconds: 30, controls: SimulationControls(throttleNotch: 2))
        XCTAssertEqual(armed.telemetry.controlIndicators.cruiseTargetKmh ?? 0, 20, accuracy: 0.01)
        XCTAssertEqual(armed.speedMps * 3.6, 20, accuracy: 1.5)
        let held = armed.speedMps
        run(&armed, seconds: 8, controls: SimulationControls(throttleNotch: 2))
        XCTAssertEqual(armed.speedMps, held, accuracy: 0.4)

        var fast = try TrainPhysicsEngine(profile: FictionalFormationCatalog.vvvf10, passengerLoadFactor: 0)
        let full = fast.profile.maximumTractionNotch
        var guardTicks = 0
        while fast.speedMps * 3.6 < 50, guardTicks < ticks(60) {
            _ = fast.advance(realDeltaSeconds: dt, controls: SimulationControls(throttleNotch: full))
            guardTicks += 1
        }
        XCTAssertGreaterThanOrEqual(fast.speedMps * 3.6, 50)
        run(&fast, seconds: 0.05, controls: SimulationControls(throttleNotch: 2))
        let captured = fast.telemetry.controlIndicators.cruiseTargetKmh ?? 0
        XCTAssertGreaterThan(captured, 35)
        run(&fast, seconds: 8, controls: SimulationControls(throttleNotch: 2))
        XCTAssertEqual(fast.speedMps * 3.6, captured, accuracy: 2)
        XCTAssertGreaterThan(fast.speedMps * 3.6, 35)
    }

    func testChopperRegenStaysOffUntilParallelFinalAndDropsWhenSpeedFalls() throws {
        let downhill = TrackCondition(gradientPermille: -60, speedLimitKmh: 120)
        var unlatched = try TrainPhysicsEngine(profile: FictionalFormationCatalog.fieldChopper8, passengerLoadFactor: 0)
        run(&unlatched, seconds: 22, controls: SimulationControls(), track: downhill)
        XCTAssertFalse(unlatched.telemetry.controlIndicators.parallelFinalReached)
        XCTAssertGreaterThan(unlatched.speedMps * 3.6, 35)
        run(&unlatched, seconds: 1.5, controls: SimulationControls(brakeNotch: 7), track: downhill)
        XCTAssertEqual(unlatched.telemetry.regenerativeBrakeForceN, 0, accuracy: 1)
        XCTAssertFalse(unlatched.telemetry.controlIndicators.regenerativeLamp)

        var latched = try TrainPhysicsEngine(profile: FictionalFormationCatalog.fieldChopper8, passengerLoadFactor: 0)
        let full = latched.profile.maximumTractionNotch
        run(&latched, seconds: 18, controls: SimulationControls(throttleNotch: full))
        XCTAssertTrue(latched.telemetry.controlIndicators.parallelFinalReached)
        XCTAssertTrue(latched.telemetry.controlIndicators.finalStageLamp)
        XCTAssertGreaterThan(latched.speedMps * 3.6, SelfChopper.regenFloor)
        run(&latched, seconds: 1.2, controls: SimulationControls(brakeNotch: 7))
        XCTAssertGreaterThan(latched.telemetry.regenerativeBrakeForceN, 100)
        XCTAssertTrue(latched.telemetry.controlIndicators.regenerativeLamp)

        var guardTicks = 0
        while latched.speedMps * 3.6 > 22, guardTicks < ticks(40) {
            _ = latched.advance(realDeltaSeconds: dt, controls: SimulationControls(brakeNotch: 7))
            guardTicks += 1
        }
        XCTAssertLessThan(latched.speedMps * 3.6, SelfChopper.regenFloor)
        XCTAssertTrue(latched.telemetry.controlIndicators.parallelFinalReached)
        XCTAssertEqual(latched.telemetry.regenerativeBrakeForceN, 0, accuracy: 1)
    }

    func testParallelFinalAllowsQuickerReaccelerationInTheMidSpeedBand() throws {
        var latched = try TrainPhysicsEngine(profile: FictionalFormationCatalog.fieldChopper10, passengerLoadFactor: 0)
        let full = latched.profile.maximumTractionNotch
        run(&latched, seconds: 20, controls: SimulationControls(throttleNotch: full))
        XCTAssertTrue(latched.telemetry.controlIndicators.parallelFinalReached)
        XCTAssertGreaterThan(latched.speedMps * 3.6, 40)
        _ = latched.advance(realDeltaSeconds: dt, controls: SimulationControls(brakeNotch: 1))
        XCTAssertEqual(latched.telemetry.tractionForceN, 0, accuracy: 1)

        var plain = try TrainPhysicsEngine(profile: FictionalFormationCatalog.fieldChopper10, passengerLoadFactor: 0)
        let downhill = TrackCondition(gradientPermille: -70, speedLimitKmh: 120)
        run(&plain, seconds: 18, controls: SimulationControls(), track: downhill)
        XCTAssertFalse(plain.telemetry.controlIndicators.parallelFinalReached)
        XCTAssertGreaterThan(plain.speedMps * 3.6, 40)
        _ = plain.advance(realDeltaSeconds: dt, controls: SimulationControls(brakeNotch: 1))

        run(&latched, seconds: 0.05, controls: SimulationControls(throttleNotch: full))
        run(&plain, seconds: 0.05, controls: SimulationControls(throttleNotch: full))
        XCTAssertGreaterThan(latched.telemetry.tractionForceN, plain.telemetry.tractionForceN + 1_000)
        XCTAssertTrue(latched.telemetry.controlIndicators.fieldWeakeningLamp)
        XCTAssertTrue(latched.telemetry.controlIndicators.seriesLamp || latched.telemetry.controlIndicators.parallelLamp || latched.telemetry.controlIndicators.finalStageLamp)
    }

    func testResistanceNotch1HoldsCamAndReverseMasterAddsHoldingBrake() throws {
        var engine = try TrainPhysicsEngine(profile: FictionalFormationCatalog.resistance8, passengerLoadFactor: 0)
        run(&engine, seconds: 2, controls: SimulationControls(throttleNotch: 4))
        let heldCam = engine.telemetry.controlIndicators.camProgress
        XCTAssertGreaterThan(heldCam, 0.2)
        XCTAssertLessThan(heldCam, 1)
        run(&engine, seconds: 3, controls: SimulationControls(throttleNotch: 1))
        XCTAssertEqual(engine.telemetry.controlIndicators.camProgress, heldCam, accuracy: 1e-9)
        XCTAssertTrue(engine.telemetry.controlIndicators.notchProgressHeld)
        XCTAssertFalse(engine.telemetry.controlIndicators.seriesLamp, "The 4000 page postponed these lamps")
        run(&engine, seconds: 1.5, controls: SimulationControls(throttleNotch: 4))
        XCTAssertGreaterThan(engine.telemetry.controlIndicators.camProgress, heldCam + 0.2)

        let grade = TrackCondition(gradientPermille: -40, speedLimitKmh: 120)
        var freeCoast = try TrainPhysicsEngine(profile: FictionalFormationCatalog.resistance8, passengerLoadFactor: 0)
        var holding = try TrainPhysicsEngine(profile: FictionalFormationCatalog.resistance8, passengerLoadFactor: 0)
        run(&freeCoast, seconds: 20, controls: SimulationControls(), track: grade)
        run(&holding, seconds: 20, controls: SimulationControls(masterReversed: true), track: grade)
        XCTAssertLessThan(holding.speedMps, freeCoast.speedMps - 1.5)
        XCTAssertGreaterThan(holding.telemetry.totalBrakeForceN, 1_000)
        XCTAssertEqual(holding.telemetry.tractionForceN, 0, accuracy: 1)
    }
}

private enum SelfChopper {
    static let regenFloor = 30.0
}
