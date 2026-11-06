import XCTest
@testable import RailwayAudioEnhancements

final class FictionalCueCatalogTests: XCTestCase {
    private let vehicleCues: [FictionalSynthesizedCue] = [
        .controllerStep, .doorOpen, .doorClose, .doorWarning,
        .whistleShort, .whistleLong, .atsAlert, .atsConfirm, .emergencyBrakeAlert
    ]

    func testEveryCueIsADistinctPlaceholderAndConfirmIsNotTheStationChime() {
        for family in FictionalControlFamily.allCases {
            var signatures = Set<String>()
            for cue in FictionalSynthesizedCue.allCases {
                let recipe = FictionalCueCatalog.recipe(cue, family: family)
                XCTAssertEqual(recipe.dataStatus, "PLACEHOLDER")
                XCTAssertGreaterThan(recipe.fundamentalHertz, 40)
                XCTAssertGreaterThan(recipe.durationSeconds, 0.04)
                XCTAssertLessThan(recipe.durationSeconds, 3)
                let signature = "\(recipe.waveform.rawValue)|\(Int(recipe.fundamentalHertz))|\(Int(recipe.durationSeconds * 100))|\(Int(recipe.pulseHertz * 10))"
                XCTAssertTrue(signatures.insert(signature).inserted, "\(family.rawValue) \(cue.rawValue) repeats \(signature)")
            }
            let confirm = FictionalCueCatalog.recipe(.atsConfirm, family: family)
            let station = FictionalCueCatalog.recipe(.stationChime, family: family)
            XCTAssertNotEqual(confirm.fundamentalHertz, station.fundamentalHertz)
            XCTAssertNotEqual(confirm.durationSeconds, station.durationSeconds)
            XCTAssertNotEqual(confirm.fundamentalHertz, 880)
            XCTAssertNotEqual(station.fundamentalHertz, 880)
            let alert = FictionalCueCatalog.recipe(.atsAlert, family: family)
            let emergency = FictionalCueCatalog.recipe(.emergencyBrakeAlert, family: family)
            XCTAssertNotEqual(alert.fundamentalHertz, emergency.fundamentalHertz)
            XCTAssertGreaterThan(emergency.pulseHertz, alert.pulseHertz)
        }
    }

    func testVehicleAwareCuesAndHornsDifferByControlType() {
        let families = FictionalControlFamily.allCases
        for cue in vehicleCues {
            let recipes = families.map { FictionalCueCatalog.recipe(cue, family: $0) }
            XCTAssertEqual(Set(recipes.map(\.fundamentalHertz)).count, 3, cue.rawValue)
            XCTAssertEqual(Set(recipes.map(\.durationSeconds)).count, 3, cue.rawValue)
        }
        for family in families {
            let short = FictionalCueCatalog.recipe(.whistleShort, family: family)
            let long = FictionalCueCatalog.recipe(.whistleLong, family: family)
            XCTAssertEqual(short.waveform, .electricHorn)
            XCTAssertEqual(long.waveform, .electricHorn)
            XCTAssertGreaterThan(short.fundamentalHertz, 300, "Electric horn, not a low steam whistle")
            XCTAssertEqual(short.fundamentalHertz, long.fundamentalHertz)
            XCTAssertGreaterThan(long.durationSeconds, short.durationSeconds + 0.6)
        }
        let high = FictionalCueCatalog.recipe(.inductionHigh, family: .vvvf)
        let low = FictionalCueCatalog.recipe(.inductionLow, family: .vvvf)
        XCTAssertGreaterThan(high.fundamentalHertz, low.fundamentalHertz + 1_000)
        XCTAssertEqual(high.dataStatus, "PLACEHOLDER")
    }

    func testRenderedFamiliesDoNotShareOneEnvelope() {
        let buzzer = FictionalCueCatalog.renderPreview(FictionalCueCatalog.recipe(.atsAlert, family: .fieldChopper))
        let confirm = FictionalCueCatalog.renderPreview(FictionalCueCatalog.recipe(.atsConfirm, family: .fieldChopper))
        let chime = FictionalCueCatalog.renderPreview(FictionalCueCatalog.recipe(.stationChime, family: .fieldChopper))
        let horn = FictionalCueCatalog.renderPreview(FictionalCueCatalog.recipe(.whistleShort, family: .vvvf))
        let click = FictionalCueCatalog.renderPreview(FictionalCueCatalog.recipe(.controllerStep, family: .resistance))
        let door = FictionalCueCatalog.renderPreview(FictionalCueCatalog.recipe(.doorOpen, family: .vvvf))
        XCTAssertGreaterThan(buzzer.count, confirm.count)
        XCTAssertNotEqual(signChanges(buzzer), signChanges(chime))
        XCTAssertNotEqual(signChanges(horn), signChanges(click))
        XCTAssertGreaterThan(door.count, click.count)
        XCTAssertGreaterThan(energy(buzzer), 0)
        XCTAssertGreaterThan(abs(energy(confirm) - energy(chime)), max(energy(chime), 0.001) * 0.05)

        let vvvfClick = FictionalCueCatalog.renderPreview(FictionalCueCatalog.recipe(.controllerStep, family: .vvvf))
        XCTAssertNotEqual(signChanges(vvvfClick), signChanges(click))
        let chopperDoor = FictionalCueCatalog.renderPreview(FictionalCueCatalog.recipe(.doorClose, family: .fieldChopper))
        let resistanceDoor = FictionalCueCatalog.renderPreview(FictionalCueCatalog.recipe(.doorClose, family: .resistance))
        XCTAssertGreaterThan(resistanceDoor.count, chopperDoor.count)
    }

    func testContinuousLayersKeepTheThreeMotorCharactersAndACompressor() {
        let vvvf = FictionalCueCatalog.continuousLayers(for: .vvvf)
        let chopper = FictionalCueCatalog.continuousLayers(for: .fieldChopper)
        let resistance = FictionalCueCatalog.continuousLayers(for: .resistance)
        XCTAssertGreaterThan(vvvf.inverterCarrierHertz, 1_000)
        XCTAssertEqual(vvvf.chopperHertz, 0)
        XCTAssertGreaterThan(chopper.chopperHertz, 0)
        XCTAssertEqual(chopper.inverterCarrierHertz, 0)
        XCTAssertLessThan(resistance.motorPitchScale, 1)
        XCTAssertEqual(resistance.inverterCarrierHertz, 0)
        XCTAssertEqual(resistance.chopperHertz, 0)
        XCTAssertEqual(Set([vvvf.compressorHertz, chopper.compressorHertz, resistance.compressorHertz]).count, 3)
        XCTAssertTrue([vvvf, chopper, resistance].allSatisfy { $0.dataStatus == "PLACEHOLDER" && $0.rainBedGain > 0 && $0.tunnelDamp > 0 })
    }

    private func signChanges(_ samples: [Float]) -> Int {
        var count = 0
        for index in 1..<samples.count where samples[index - 1] * samples[index] < 0 {
            count += 1
        }
        return count
    }

    private func energy(_ samples: [Float]) -> Float {
        samples.reduce(0) { $0 + $1 * $1 }
    }
}
