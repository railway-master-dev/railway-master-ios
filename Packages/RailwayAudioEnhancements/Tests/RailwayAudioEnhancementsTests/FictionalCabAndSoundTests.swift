import XCTest
@testable import RailwayAudioEnhancements

final class FictionalCabAndSoundTests: XCTestCase {
    func testThreeDesksFollowTheReferenceArrangementsWithoutCopiedPhotographs() {
        let vvvf = FictionalCabAndSoundCatalog.vvvf
        let chopper = FictionalCabAndSoundCatalog.fieldChopper
        let resistance = FictionalCabAndSoundCatalog.resistance

        XCTAssertTrue(vvvf.oneHandleMasterBrake)
        XCTAssertEqual(vvvf.brakeGrip, .combinedWithMaster)
        XCTAssertTrue(vvvf.hasCenterMonitor)
        XCTAssertTrue(vvvf.hasRightStatusScreen)
        XCTAssertTrue(vvvf.hasRightHandset)
        XCTAssertFalse(vvvf.hasRightKeypad)
        XCTAssertLessThan(vvvf.deskRed, 0.4)

        XCTAssertFalse(chopper.oneHandleMasterBrake)
        XCTAssertEqual(chopper.masterGrip, .woodBrown)
        XCTAssertEqual(chopper.brakeGrip, .sphere)
        XCTAssertTrue(chopper.verticalAmberIndicators)
        XCTAssertTrue(chopper.blueSwitchLabels)
        XCTAssertTrue(chopper.hasRightKeypad)
        XCTAssertGreaterThan(chopper.deskGreen, chopper.deskRed)

        XCTAssertFalse(resistance.oneHandleMasterBrake)
        XCTAssertEqual(resistance.masterGrip, .markedReverseAndOff)
        XCTAssertEqual(resistance.masterMarkings, ["後", "切"])
        XCTAssertEqual(resistance.brakeGrip, .sphere)
        XCTAssertEqual(resistance.analogGaugeCount, 3)
        XCTAssertEqual(resistance.dashboardCaption, "SIV")
        XCTAssertEqual(resistance.doorLampCaption, "戸閉")
        XCTAssertTrue(resistance.centerSwitchBank)
        XCTAssertTrue(resistance.blueSwitchLabels)

        for desk in [vvvf, chopper, resistance] {
            XCTAssertEqual(desk.dataStatus, "PLACEHOLDER")
            XCTAssertTrue(desk.inspirationNote.contains("PLACEHOLDER"))
            XCTAssertFalse(desk.fictionalCarNumber == "2007" || desk.fictionalCarNumber == "4001")
            XCTAssertFalse(desk.inspirationNote.contains("HOT Tokyo"))
        }
    }

    func testProfilesMapOntoTheThreeFamiliesAndSoundsStaySynthesized() {
        XCTAssertEqual(FictionalCabAndSoundCatalog.family(forProfileID: "rheostaticDC"), .resistance)
        XCTAssertEqual(FictionalCabAndSoundCatalog.family(forProfileID: "fieldChopperDC"), .fieldChopper)
        XCTAssertEqual(FictionalCabAndSoundCatalog.family(forProfileID: "vvvfIGBT"), .vvvf)
        XCTAssertEqual(FictionalCabAndSoundCatalog.family(forProfileID: "vvvfSiC"), .vvvf)

        let vvvf = FictionalCabAndSoundCatalog.tractionTone(for: .vvvf)
        let chopper = FictionalCabAndSoundCatalog.tractionTone(for: .fieldChopper)
        let resistance = FictionalCabAndSoundCatalog.tractionTone(for: .resistance)
        XCTAssertTrue(vvvf.usesInverterCarrier)
        XCTAssertGreaterThan(vvvf.carrierHertz, 1_000)
        XCTAssertFalse(vvvf.usesCamshaftSteps)
        XCTAssertTrue(chopper.usesChopperRipple)
        XCTAssertGreaterThan(chopper.chopperHertz, 0)
        XCTAssertFalse(chopper.usesInverterCarrier)
        XCTAssertTrue(resistance.usesCamshaftSteps)
        XCTAssertEqual(resistance.carrierHertz, 0)
        XCTAssertEqual(resistance.chopperHertz, 0)
        XCTAssertEqual(vvvf.dataStatus, "PLACEHOLDER")
        XCTAssertEqual(FictionalCabAndSoundCatalog.fieldChopper.indicatorCaptions, ["直列", "並列", "最終", "界磁弱メ", "回生制動"])
        XCTAssertTrue(FictionalCabAndSoundCatalog.resistance.indicatorCaptions.isEmpty)

        let vvvfPlan = FictionalCabAndSoundCatalog.generationPlan(for: .vvvf)
        let chopperPlan = FictionalCabAndSoundCatalog.generationPlan(for: .fieldChopper)
        let resistancePlan = FictionalCabAndSoundCatalog.generationPlan(for: .resistance)
        XCTAssertEqual(vvvfPlan.deskColorName, "grey")
        XCTAssertTrue(vvvfPlan.combinedMasterBrake)
        XCTAssertFalse(vvvfPlan.separateBrakeSphere)
        XCTAssertEqual(vvvfPlan.monitorNames, ["CenterMonitor", "RightStatusScreen", "Handset"])
        XCTAssertFalse(vvvfPlan.includesSeriesParallelFinalLamps)
        XCTAssertEqual(vvvfPlan.fictionalCarNumber, "T-VVVF")
        XCTAssertEqual(chopperPlan.deskColorName, "mint")
        XCTAssertTrue(chopperPlan.woodMasterGrip)
        XCTAssertTrue(chopperPlan.separateBrakeSphere)
        XCTAssertEqual(chopperPlan.lampNames, ["直列", "並列", "最終", "界磁弱メ", "回生制動"])
        XCTAssertFalse(chopperPlan.fictionalCarNumber.contains("2007"))
        XCTAssertEqual(resistancePlan.gaugeCount, 3)
        XCTAssertEqual(resistancePlan.captionPanels, ["SIV", "戸閉"])
        XCTAssertEqual(resistancePlan.masterMarkings, ["後", "切"])
        XCTAssertFalse(resistancePlan.includesSeriesParallelFinalLamps)
        XCTAssertFalse(resistancePlan.lampNames.contains("直列"))
        XCTAssertFalse(resistancePlan.fictionalCarNumber.contains("4001"))
        XCTAssertNotEqual(Set(vvvfPlan.partNames), Set(chopperPlan.partNames))
        XCTAssertNotEqual(Set(chopperPlan.partNames), Set(resistancePlan.partNames))
        XCTAssertTrue([vvvfPlan, chopperPlan, resistancePlan].allSatisfy { $0.dataStatus == "PLACEHOLDER" })
        XCTAssertLessThan(resistance.motorPitchScale, chopper.motorPitchScale)
        XCTAssertLessThan(resistance.motorPitchScale, 1)
        XCTAssertEqual(resistance.dataStatus, "PLACEHOLDER")

        let doors = FictionalControlFamily.allCases.map(FictionalCabAndSoundCatalog.doorTone(for:))
        XCTAssertEqual(Set(doors.map(\.openHertz)).count, 3)
        XCTAssertGreaterThan(doors.first { $0.family == .resistance }!.durationSeconds, doors.first { $0.family == .vvvf }!.durationSeconds)
        XCTAssertTrue(doors.allSatisfy { $0.dataStatus == "PLACEHOLDER" && $0.durationSeconds > 0 && $0.motorWhirMix > 0 && $0.motorWhirMix < 1 })
    }
}
