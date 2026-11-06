import XCTest
@testable import ProtectionSystems

final class ProtectionPhysicsCouplerTests: XCTestCase {
    private func state(_ system: String, brake: Bool, trainID: String = "PLAYER") -> SystemProtectionState {
        SystemProtectionState(trainID: trainID, system: system, permittedSpeedKmh: nil, brakeCommanded: brake, stateDescription: "test")
    }

    func testCouplerLeavesDriverControlsAloneWhenNoDeviceCommandsBrake() {
        let driver = FictionalDriverControls(throttleNotch: 3, brakeNotch: 2, emergencyBrake: false)
        let command = FictionalProtectionPhysicsCoupler.apply(
            driver: driver,
            states: [state("atsP", brake: false), state("other-train", brake: true, trainID: "AI"), state("unknown", brake: true)],
            trainID: "PLAYER"
        )
        XCTAssertEqual(command.intervention, .none)
        XCTAssertEqual(command.actingSystems, [])
        XCTAssertEqual(command.throttleNotch, 3)
        XCTAssertEqual(command.brakeNotch, 2)
        XCTAssertFalse(command.emergencyBrake)
        XCTAssertEqual(command.dataStatus, "PLACEHOLDER")
    }

    func testSpeedSupervisionCutsTractionAndAppliesServiceBrakeWithoutEmergency() {
        let driver = FictionalDriverControls(throttleNotch: 4, brakeNotch: 0, emergencyBrake: false)
        let command = FictionalProtectionPhysicsCoupler.apply(
            driver: driver,
            states: [state("atsP", brake: true), state("atc", brake: true), state("atsPs", brake: false)],
            trainID: "PLAYER"
        )
        XCTAssertEqual(command.intervention, .serviceBrakeCutTraction)
        XCTAssertEqual(command.actingSystems, ["atc", "atsP"])
        XCTAssertEqual(command.throttleNotch, 0)
        XCTAssertEqual(command.brakeNotch, 7)
        XCTAssertFalse(command.emergencyBrake)
    }

    func testAcknowledgementAndVigilanceLatchesRequestEmergencyAndCutTraction() {
        let driver = FictionalDriverControls(throttleNotch: 5, brakeNotch: 1, emergencyBrake: false)
        let command = FictionalProtectionPhysicsCoupler.apply(
            driver: driver,
            states: [state("atsS", brake: true), state("eb", brake: true), state("atsP", brake: true)],
            trainID: "PLAYER"
        )
        XCTAssertEqual(command.intervention, .emergencyBrakeCutTraction)
        XCTAssertEqual(command.actingSystems, ["atsP", "atsS", "eb"])
        XCTAssertEqual(command.throttleNotch, 0)
        XCTAssertEqual(command.brakeNotch, 7)
        XCTAssertTrue(command.emergencyBrake)
    }

    func testDeadmanBrakeIsEmergencyAndDriverEmergencyIsKeptDuringServiceBrake() {
        let deadman = FictionalProtectionPhysicsCoupler.apply(
            driver: FictionalDriverControls(throttleNotch: 1, brakeNotch: 0, emergencyBrake: false),
            states: [state("deadman", brake: true)],
            trainID: "PLAYER"
        )
        XCTAssertEqual(deadman.intervention, .emergencyBrakeCutTraction)
        XCTAssertTrue(deadman.emergencyBrake)

        let service = FictionalProtectionPhysicsCoupler.apply(
            driver: FictionalDriverControls(throttleNotch: 2, brakeNotch: 0, emergencyBrake: true),
            states: [state("ato", brake: true)],
            trainID: "PLAYER"
        )
        XCTAssertEqual(service.intervention, .serviceBrakeCutTraction)
        XCTAssertEqual(service.throttleNotch, 0)
        XCTAssertTrue(service.emergencyBrake)
    }

    func testLiveSessionATSProfileOverspeedCutsThrottleOnTheNextFixedStep() throws {
        var session = try FictionalLiveProtectionSession(routeLengthM: 4_000)
        let outcome = try session.step(FictionalLiveProtectionSession.Input(
            fixedTick: 1,
            timeSeconds: 1,
            frontPositionM: 1_200,
            speedKmh: 160,
            trainLengthM: 80,
            driver: FictionalDriverControls(throttleNotch: 4, brakeNotch: 0, emergencyBrake: false)
        ))
        XCTAssertEqual(outcome.command.intervention, .serviceBrakeCutTraction)
        XCTAssertTrue(outcome.command.actingSystems.contains("atsP"))
        XCTAssertEqual(outcome.command.throttleNotch, 0)
        XCTAssertEqual(outcome.command.brakeNotch, 7)
        XCTAssertFalse(outcome.command.emergencyBrake)
        XCTAssertFalse(outcome.states.contains { $0.system == "ato" })
        XCTAssertFalse(outcome.states.contains { $0.system == "deadman" })
    }

    func testLiveSessionExpiredATSSAcknowledgementRequestsEmergencyBrake() throws {
        var session = try FictionalLiveProtectionSession(routeLengthM: 4_000)
        let coasting = FictionalDriverControls(throttleNotch: 2, brakeNotch: 0, emergencyBrake: false)
        let before = try session.step(FictionalLiveProtectionSession.Input(
            fixedTick: 1, timeSeconds: 1, frontPositionM: 640, speedKmh: 70, trainLengthM: 80, driver: coasting
        ))
        XCTAssertFalse(before.command.actingSystems.contains("atsS"))
        let crossed = try session.step(FictionalLiveProtectionSession.Input(
            fixedTick: 2, timeSeconds: 2, frontPositionM: 670, speedKmh: 70, trainLengthM: 80, driver: coasting
        ))
        XCTAssertTrue(crossed.states.contains { $0.system == "atsS" && $0.stateDescription.contains("awaiting") })
        XCTAssertNotEqual(crossed.command.intervention, .emergencyBrakeCutTraction)
        let expired = try session.step(FictionalLiveProtectionSession.Input(
            fixedTick: 3, timeSeconds: 7, frontPositionM: 690, speedKmh: 70, trainLengthM: 80, driver: coasting
        ))
        XCTAssertEqual(expired.command.intervention, .emergencyBrakeCutTraction)
        XCTAssertTrue(expired.command.actingSystems.contains("atsS"))
        XCTAssertEqual(expired.command.throttleNotch, 0)
        XCTAssertTrue(expired.command.emergencyBrake)
    }

    func testLiveSessionEBInactivityAppliesEmergencyWithoutADriverInput() throws {
        var session = try FictionalLiveProtectionSession(routeLengthM: 4_000)
        let power = FictionalDriverControls(throttleNotch: 3, brakeNotch: 0, emergencyBrake: false)
        _ = try session.step(FictionalLiveProtectionSession.Input(
            fixedTick: 1, timeSeconds: 1, frontPositionM: 100, speedKmh: 40, trainLengthM: 80, driver: power
        ))
        let latched = try session.step(FictionalLiveProtectionSession.Input(
            fixedTick: 2, timeSeconds: 14, frontPositionM: 180, speedKmh: 40, trainLengthM: 80, driver: power
        ))
        XCTAssertTrue(latched.command.actingSystems.contains("eb"))
        XCTAssertEqual(latched.command.intervention, .emergencyBrakeCutTraction)
        XCTAssertEqual(latched.command.throttleNotch, 0)
        XCTAssertTrue(latched.command.emergencyBrake)
    }

    func testLiveSessionActivityPulseAvoidsEBAndAcknowledgementClearsPendingATSS() throws {
        var session = try FictionalLiveProtectionSession(routeLengthM: 4_000)
        let driver = FictionalDriverControls(throttleNotch: 1, brakeNotch: 0, emergencyBrake: false)
        _ = try session.step(FictionalLiveProtectionSession.Input(
            fixedTick: 1, timeSeconds: 1, frontPositionM: 640, speedKmh: 60, trainLengthM: 80, driver: driver
        ))
        _ = try session.step(FictionalLiveProtectionSession.Input(
            fixedTick: 2, timeSeconds: 2, frontPositionM: 670, speedKmh: 60, trainLengthM: 80, driver: driver
        ))
        let acknowledged = try session.step(FictionalLiveProtectionSession.Input(
            fixedTick: 3, timeSeconds: 6, frontPositionM: 700, speedKmh: 60, trainLengthM: 80,
            acknowledgeATSS: true, driverActivityPulse: true, driver: driver
        ))
        XCTAssertFalse(acknowledged.states.contains { $0.system == "atsS" && $0.brakeCommanded })
        XCTAssertFalse(acknowledged.command.actingSystems.contains("eb"))
        XCTAssertEqual(acknowledged.command.throttleNotch, 1)
    }
}
