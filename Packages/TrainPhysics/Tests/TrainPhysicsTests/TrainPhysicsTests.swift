import XCTest
@testable import TrainPhysics

final class TrainPhysicsTests: XCTestCase {
    private var profiles: [TrainsetProfile] { try! FictionalProfileCatalog.loadBundled() }
    private var dt: Double { TrainPhysicsEngine.fixedTimeStepSeconds }

    private func profile(_ mode: TractionMode) throws -> TrainsetProfile {
        guard let result = profiles.first(where: { $0.traction.mode == mode }) else {
            throw TrainPhysicsError.bundledProfilesUnavailable
        }
        return result
    }

    private func makeEngine(_ mode: TractionMode = .fieldChopperDC, load: Double = 0.5) throws -> TrainPhysicsEngine {
        try TrainPhysicsEngine(profile: profile(mode), passengerLoadFactor: load)
    }

    private func runTicks(
        _ engine: inout TrainPhysicsEngine,
        _ ticks: Int,
        controls: SimulationControls,
        track: TrackCondition = .level,
        surface: RailSurface = .dry,
        modifiers: PhysicsModifiers = PhysicsModifiers()
    ) {
        guard ticks > 0 else { return }
        for _ in 0..<ticks {
            _ = engine.advance(realDeltaSeconds: dt, controls: controls, track: track, surface: surface, modifiers: modifiers)
        }
    }

    func testBundledProfilesCoverAllFiveFictionalDriveTypesAndIndividualCars() throws {
        let loaded = try FictionalProfileCatalog.loadBundled()
        let originalIDs = [
            "fictional-rheostatic-t02",
            "fictional-field-chopper-t01",
            "fictional-vvvf-gto-t03",
            "fictional-vvvf-igbt-t04",
            "fictional-vvvf-sic-t05",
        ]
        XCTAssertEqual(loaded.count, 11)
        XCTAssertEqual(Set(loaded.map { $0.traction.mode.rawValue }), Set(TractionMode.allCases.map(\.rawValue)))
        let original = loaded.filter { originalIDs.contains($0.identifier) }
        XCTAssertEqual(original.map(\.carCount).sorted(), [4, 6, 6, 8, 8])
        XCTAssertEqual(Set(FictionalFormationCatalog.all.map(\.identifier)).count, 6)
        XCTAssertTrue(loaded.allSatisfy { $0.fictionalNotice.contains("実車安全計算") })
        XCTAssertTrue(loaded.allSatisfy { $0.validationIssues().isEmpty })
        XCTAssertTrue(loaded.allSatisfy { Set($0.cars.map(\.identifier)).count == $0.cars.count })
    }

    func testPerCarMassAndPassengerLoadAreIncludedInPhysicalAndEffectiveMass() throws {
        let selected = try profile(.vvvfIGBT)
        var engine = try TrainPhysicsEngine(profile: selected, passengerLoadFactor: 0.75)
        let expectedMass = selected.cars.reduce(0.0) {
            $0 + $1.tareMassKg + Double($1.passengerCapacity) * 0.75 * PhysicsConstants.passengerMassKg
        }
        XCTAssertEqual(engine.telemetry.physicalMassKg, expectedMass, accuracy: 1e-8)
        XCTAssertEqual(engine.telemetry.effectiveMassKg, expectedMass * selected.rotationalInertiaFactor, accuracy: 1e-8)
        XCTAssertEqual(engine.telemetry.cars.count, 8)
        XCTAssertTrue(engine.telemetry.cars.allSatisfy { $0.loadedMassKg >= $0.tareMassKg })
        engine.setPassengerLoadFactor(3)
        XCTAssertEqual(engine.passengerLoadFactor, 2)
        engine.setPassengerLoadFactor(.nan)
        XCTAssertEqual(engine.passengerLoadFactor, 2, "Non-finite load input must not poison state")
    }

    func testTractionModesHaveFiniteThreeRegionEnvelopesAndPowerCeiling() throws {
        for selected in profiles {
            let traction = selected.traction
            XCTAssertGreaterThan(traction.availableTractionForceN(speedKmh: -5, notch: 99), 0)
            XCTAssertEqual(traction.availableTractionForceN(speedKmh: traction.maximumSpeedKmh, notch: 99), 0, accuracy: 1e-9)
            XCTAssertEqual(traction.availableTractionForceN(speedKmh: .nan, notch: -1), 0, accuracy: 1e-9)
            let speedKmh = (traction.baseSpeedKmh + traction.voltageLimitedStartKmh) / 2
            let force = traction.availableTractionForceN(speedKmh: speedKmh, notch: selected.maximumTractionNotch)
            XCTAssertGreaterThan(force, 0)
            XCTAssertLessThanOrEqual(force * speedKmh / 3.6, traction.maximumPowerW + 1)
            let highForce = traction.availableTractionForceN(speedKmh: (traction.voltageLimitedStartKmh + traction.maximumSpeedKmh) / 2,
                                                             notch: selected.maximumTractionNotch)
            XCTAssertGreaterThanOrEqual(highForce, 0)
            XCTAssertLessThanOrEqual(highForce, traction.maximumForceN + 1)
        }
    }

    func testInvalidProfileIsRejectedBeforeSimulation() throws {
        var invalid = try profile(.fieldChopperDC)
        invalid.traction.maximumSpeedKmh = .nan
        XCTAssertThrowsError(try TrainPhysicsEngine(profile: invalid)) { error in
            guard let physicsError = error as? TrainPhysicsError else {
                return XCTFail("Expected TrainPhysicsError, got \(error)")
            }
            guard case .invalidProfile = physicsError else {
                return XCTFail("Expected an invalid-profile validation error, got \(error)")
            }
        }
    }

    func testTractionJerkLimitConstrainsNotchForceChangeAndBrakeInterlockCutsPower() throws {
        let selected = try profile(.fieldChopperDC)
        var engine = try TrainPhysicsEngine(profile: selected)
        runTicks(&engine, 1, controls: SimulationControls(throttleNotch: selected.maximumTractionNotch))
        let firstForce = engine.telemetry.tractionForceN
        let maximumFirstTickForce = engine.telemetry.effectiveMassKg * selected.traction.tractionJerkMps3 * dt
        XCTAssertGreaterThan(firstForce, 0)
        XCTAssertLessThanOrEqual(firstForce, maximumFirstTickForce + 1e-8)
        runTicks(&engine, 1, controls: SimulationControls(throttleNotch: selected.maximumTractionNotch))
        XCTAssertGreaterThan(engine.telemetry.tractionForceN, firstForce)
        runTicks(&engine, 1, controls: SimulationControls(throttleNotch: selected.maximumTractionNotch, brakeNotch: 1))
        XCTAssertEqual(engine.telemetry.tractionForceN, 0, accuracy: 1e-9)
    }

    func testFixed120HzAccumulatorUsesWholeTicksAndRejectsInvalidDeltas() throws {
        var engine = try makeEngine()
        XCTAssertEqual(engine.advance(realDeltaSeconds: .nan, controls: SimulationControls(throttleNotch: 5)), 0)
        XCTAssertEqual(engine.advance(realDeltaSeconds: .infinity, controls: SimulationControls(throttleNotch: 5)), 0)
        XCTAssertEqual(engine.advance(realDeltaSeconds: -dt, controls: SimulationControls(throttleNotch: 5)), 0)
        XCTAssertEqual(engine.advance(realDeltaSeconds: dt * 0.75, controls: SimulationControls(throttleNotch: 5)), 0)
        XCTAssertEqual(engine.telemetry.simulationTimeSeconds, 0, accuracy: 1e-12)
        XCTAssertEqual(engine.advance(realDeltaSeconds: dt * 0.25, controls: SimulationControls(throttleNotch: 5)), 1)
        XCTAssertEqual(engine.telemetry.simulationTimeSeconds, dt, accuracy: 1e-12)
        XCTAssertGreaterThan(engine.telemetry.tractionForceN, 0,
                             "A tick applies jerk-limited traction even before it overcomes rolling resistance")
    }

    func testFixedStepResultsAreStableAcrossRenderDeltaPartitioningAndFrameCap() throws {
        var singleCall = try makeEngine()
        var splitCalls = try makeEngine()
        _ = singleCall.advance(realDeltaSeconds: dt * 60, controls: SimulationControls(throttleNotch: 4))
        runTicks(&splitCalls, 60, controls: SimulationControls(throttleNotch: 4))
        XCTAssertEqual(singleCall.positionM, splitCalls.positionM, accuracy: 1e-10)
        XCTAssertEqual(singleCall.speedMps, splitCalls.speedMps, accuracy: 1e-10)
        XCTAssertEqual(singleCall.simulationTimeSeconds, 0.5, accuracy: 1e-10)

        var oneSecond = try makeEngine()
        var halfSecond = try makeEngine()
        XCTAssertEqual(oneSecond.advance(realDeltaSeconds: 1, controls: SimulationControls(throttleNotch: 3)), 60)
        XCTAssertEqual(halfSecond.advance(realDeltaSeconds: 0.5, controls: SimulationControls(throttleNotch: 3)), 60)
        XCTAssertEqual(oneSecond.speedMps, halfSecond.speedMps, accuracy: 1e-12)
        XCTAssertEqual(oneSecond.positionM, halfSecond.positionM, accuracy: 1e-12)
    }

    func testBrakePipePressureWaveAndCylinderResponseArePerCarAndDelayed() throws {
        let selected = try profile(.vvvfIGBT)
        var engine = try TrainPhysicsEngine(profile: selected)
        runTicks(&engine, 1, controls: SimulationControls(emergencyBrake: true))
        let afterOneTick = engine.telemetry.cars
        XCTAssertLessThan(afterOneTick[0].brakePipePressureKPa, afterOneTick[1].brakePipePressureKPa)
        XCTAssertGreaterThan(afterOneTick[0].brakeCylinderPressureKPa, 0)
        XCTAssertLessThan(afterOneTick[0].brakeCylinderPressureKPa, selected.brakeSystem.maximumCylinderPressureKPa)
        XCTAssertEqual(afterOneTick[1].brakePipePressureKPa, selected.brakeSystem.chargePressureKPa, accuracy: 1e-12)

        runTicks(&engine, 720, controls: SimulationControls(emergencyBrake: true))
        XCTAssertLessThan(engine.telemetry.cars.last!.brakePipePressureKPa, selected.brakeSystem.chargePressureKPa)
        XCTAssertGreaterThan(engine.telemetry.cars.last!.brakeCylinderPressureKPa, 0)
        XCTAssertGreaterThan(engine.telemetry.mainReservoirPressureKPa, 0)
        XCTAssertLessThanOrEqual(engine.telemetry.mainReservoirPressureKPa, selected.brakeSystem.maximumReservoirPressureKPa)
    }

    func testBrakeApplyAndReleaseResponseAreBoundedAndMonotonic() throws {
        let selected = try profile(.fieldChopperDC)
        var engine = try TrainPhysicsEngine(profile: selected)
        runTicks(&engine, 240, controls: SimulationControls(brakeNotch: 7))
        let applied = engine.telemetry.cars.map(\.brakeCylinderPressureKPa)
        XCTAssertTrue(applied.allSatisfy { $0 > 0 && $0 <= selected.brakeSystem.maximumCylinderPressureKPa })
        runTicks(&engine, 240, controls: SimulationControls())
        let released = engine.telemetry.cars.map(\.brakeCylinderPressureKPa)
        XCTAssertTrue(zip(released, applied).allSatisfy { $0.0 < $0.1 })
        XCTAssertTrue(released.allSatisfy { $0 >= 0 })
    }

    func testRegenerativeAndFrictionBrakeBoundaryAndLowSpeedFade() throws {
        var engine = try makeEngine(.fieldChopperDC)
        runTicks(&engine, 1_200, controls: SimulationControls(throttleNotch: 5))
        XCTAssertGreaterThan(engine.speedMps, 2)
        runTicks(&engine, 1, controls: SimulationControls(brakeNotch: 7))
        let braking = engine.telemetry
        XCTAssertGreaterThan(braking.regenerativeBrakeForceN, 0)
        XCTAssertGreaterThanOrEqual(braking.frictionBrakeForceN, 0)
        XCTAssertEqual(braking.totalBrakeForceN,
                       braking.regenerativeBrakeForceN + braking.frictionBrakeForceN,
                       accuracy: 1e-7)
        XCTAssertLessThanOrEqual(braking.lineCurrentA, 0, "Regeneration should return, not draw, current when traction is cut")

        let traction = try profile(.fieldChopperDC).traction
        XCTAssertEqual(traction.regenerativeForceRequestN(brakeDemandN: 100_000, speedKmh: 8), 0, accuracy: 1e-9)
        XCTAssertGreaterThan(traction.regenerativeForceRequestN(brakeDemandN: 100_000, speedKmh: 15), 0)
        XCTAssertLessThanOrEqual(traction.regenerativeForceRequestN(brakeDemandN: 10_000_000, speedKmh: 90),
                                 traction.maximumRegenerativeForceN + 1e-9)
    }

    func testMotorVoltageCurrentAndPowerTelemetryAreFiniteAndBounded() throws {
        let selected = try profile(.vvvfSiC)
        var engine = try TrainPhysicsEngine(profile: selected)
        runTicks(&engine, 300, controls: SimulationControls(throttleNotch: 4),
                 track: TrackCondition(supplyVoltageV: 1_500))
        let meter = engine.telemetry
        XCTAssertEqual(meter.lineVoltageV, 1_500, accuracy: 1e-9)
        XCTAssertGreaterThan(meter.lineCurrentA, 0)
        XCTAssertLessThanOrEqual(meter.lineCurrentA, selected.traction.currentLimitA + 1e-9)
        XCTAssertTrue(meter.electricalPowerW.isFinite)
        XCTAssertTrue(meter.tractionForceN.isFinite)
        XCTAssertTrue(meter.speedMps.isFinite)

        var capped = try makeEngine(.vvvfSiC)
        runTicks(&capped, 600, controls: SimulationControls(throttleNotch: 4),
                 modifiers: PhysicsModifiers(tractionMultiplier: 2, speedCapKmh: 1))
        XCTAssertLessThanOrEqual(capped.telemetry.speedKmh, 1 + 1e-9)
    }

    func testBrakeTemperatureAccumulatesAndReducesFrictionCapacity() throws {
        var hotProfile = try profile(.rheostaticDC)
        hotProfile.cars = hotProfile.cars.map { original in
            var car = original
            car.brakeThermalCapacityJPerC = 12_000
            car.brakeCoolingWPerC = 0
            car.brakeFadeStartC = 22
            car.brakeFadeFullC = 35
            car.minimumBrakeFadeFactor = 0.40
            return car
        }
        var engine = try TrainPhysicsEngine(profile: hotProfile, passengerLoadFactor: 0.5)
        runTicks(&engine, 2_400, controls: SimulationControls(throttleNotch: 5))
        runTicks(&engine, 900, controls: SimulationControls(emergencyBrake: true))
        let cars = engine.telemetry.cars
        XCTAssertTrue(cars.contains { $0.brakeTemperatureC > 22 })
        XCTAssertTrue(cars.contains { $0.brakeFadeFactor < 1 })
        XCTAssertTrue(cars.allSatisfy { $0.brakeTemperatureC.isFinite && (0.40...1).contains($0.brakeFadeFactor) })
    }

    func testSnowSlipIsLimitedAndAdhesionControllerReacquiresGrip() throws {
        var engine = try makeEngine(.fieldChopperDC)
        runTicks(&engine, 300, controls: SimulationControls(throttleNotch: 5), surface: .snow)
        let slipping = engine.telemetry
        XCTAssertTrue(slipping.wheelSlipActive)
        XCTAssertLessThan(slipping.tractionAdhesionScale, 1)
        let drivenMass = zip(slipping.cars, try profile(.fieldChopperDC).cars).reduce(0.0) {
            $0 + $1.0.loadedMassKg * $1.1.drivenMassFraction
        }
        let limit = RailSurface.snow.fictionalAdhesionCoefficient * PhysicsConstants.gravityMps2 * drivenMass
        XCTAssertLessThanOrEqual(slipping.tractionForceN, limit + 1)

        runTicks(&engine, 720, controls: SimulationControls(), surface: .dry)
        XCTAssertFalse(engine.telemetry.wheelSlipActive)
        XCTAssertGreaterThan(engine.telemetry.tractionAdhesionScale, slipping.tractionAdhesionScale)
    }

    func testEmergencyBrakeSlipAndReAdhesionScaleStayFinite() throws {
        var engine = try makeEngine(.rheostaticDC)
        runTicks(&engine, 900, controls: SimulationControls(throttleNotch: 5), surface: .snow)
        runTicks(&engine, 240, controls: SimulationControls(emergencyBrake: true), surface: .snow)
        let meter = engine.telemetry
        XCTAssertTrue(meter.brakeSlipActive)
        XCTAssertLessThan(meter.brakeAdhesionScale, 1)
        XCTAssertTrue(meter.totalBrakeForceN.isFinite && meter.brakeAdhesionScale.isFinite)
    }

    func testStoppingDistanceUsesSameTickModelWithoutMutatingLiveEngine() throws {
        var engine = try makeEngine(.vvvfIGBT)
        runTicks(&engine, 720, controls: SimulationControls(throttleNotch: 5))
        XCTAssertGreaterThan(engine.speedMps, 1)
        let before = engine.telemetry
        let service = engine.estimateStoppingDistance(brake: .service(notch: 7))
        let emergency = engine.estimateStoppingDistance(brake: .emergency)
        XCTAssertTrue(service.reachedRest)
        XCTAssertTrue(emergency.reachedRest)
        XCTAssertGreaterThan(service.distanceM, 0)
        XCTAssertLessThan(emergency.distanceM, service.distanceM)
        XCTAssertEqual(engine.positionM, before.positionM, accuracy: 1e-12)
        XCTAssertEqual(engine.speedMps, before.speedMps, accuracy: 1e-12)
    }

    func testExtraResistanceLowersSpeedOnTheFixedTickAndNonFiniteResistanceIsIgnored() throws {
        var calm = try makeEngine()
        var headwind = try makeEngine()
        let controls = SimulationControls(throttleNotch: 4)
        runTicks(&calm, 180, controls: controls, modifiers: PhysicsModifiers(extraResistanceN: 0))
        runTicks(&headwind, 180, controls: controls, modifiers: PhysicsModifiers(extraResistanceN: 20_000))
        XCTAssertGreaterThan(calm.speedMps, headwind.speedMps)
        XCTAssertGreaterThan(headwind.telemetry.rollingResistanceN, calm.telemetry.rollingResistanceN)

        var invalid = try makeEngine()
        runTicks(&invalid, 30, controls: controls, modifiers: PhysicsModifiers(extraResistanceN: .nan))
        var zero = try makeEngine()
        runTicks(&zero, 30, controls: controls, modifiers: PhysicsModifiers(extraResistanceN: 0))
        XCTAssertEqual(invalid.speedMps, zero.speedMps, accuracy: 1e-9)
        XCTAssertTrue(invalid.telemetry.rollingResistanceN.isFinite)
    }

    func testGradientCurveAndDavisForcesUseDocumentedSignsAndUnits() throws {
        let selected = try profile(.fieldChopperDC)
        var uphillEngine = try TrainPhysicsEngine(profile: selected)
        let uphill = TrackCondition(gradientPermille: 10, curveRadiusM: 400, speedLimitKmh: 120)
        runTicks(&uphillEngine, 1, controls: SimulationControls(), track: uphill)
        let expectedGrade = uphillEngine.telemetry.physicalMassKg * PhysicsConstants.gravityMps2 * sin(atan(0.01))
        let massTonnes = uphillEngine.telemetry.physicalMassKg / 1_000
        let expectedDavis = massTonnes * (selected.davisResistance.aNPerTonne
            + selected.davisResistance.bNSecondPerMeterPerTonne * uphillEngine.telemetry.speedMps)
            + selected.davisResistance.cNSecondSquaredPerMeterSquared * pow(uphillEngine.telemetry.speedMps, 2)
        let expectedCurve = uphillEngine.telemetry.physicalMassKg * PhysicsConstants.gravityMps2 / 1_000 *
            selected.curveResistanceNPerKNAtOnePerM / 400
        XCTAssertEqual(uphillEngine.telemetry.gradientForceN, expectedGrade, accuracy: 1e-6)
        XCTAssertEqual(uphillEngine.telemetry.rollingResistanceN, expectedDavis, accuracy: 1e-6)
        XCTAssertEqual(uphillEngine.telemetry.curveResistanceN, expectedCurve, accuracy: 1e-6)
        XCTAssertGreaterThanOrEqual(uphillEngine.speedMps, 0)

        var downhillEngine = try makeEngine()
        runTicks(&downhillEngine, 1, controls: SimulationControls(), track: TrackCondition(gradientPermille: -10))
        XCTAssertLessThan(downhillEngine.telemetry.gradientForceN, 0)
        XCTAssertGreaterThanOrEqual(downhillEngine.positionM, 0)
    }

    func testInvalidTrackAndExtremeModifiersCannotCreateNonFiniteState() throws {
        let selected = try profile(.vvvfSiC)
        var engine = try TrainPhysicsEngine(profile: selected)
        let invalidTrack = TrackCondition(gradientPermille: .nan, curveRadiusM: 0, speedLimitKmh: .infinity,
                                          tunnelResistanceMultiplier: .infinity, supplyVoltageV: .nan)
        runTicks(&engine, 600, controls: SimulationControls(throttleNotch: Int.max), track: invalidTrack,
                 modifiers: PhysicsModifiers(tractionMultiplier: .infinity, brakingMultiplier: .nan,
                                             speedCapKmh: .infinity, adhesionCoefficientOverride: .nan))
        let meter = engine.telemetry
        let values = [meter.positionM, meter.speedMps, meter.accelerationMps2, meter.physicalMassKg,
                      meter.tractionForceN, meter.totalBrakeForceN, meter.rollingResistanceN,
                      meter.gradientForceN, meter.curveResistanceN, meter.lineVoltageV, meter.lineCurrentA,
                      meter.electricalPowerW, meter.brakePipePressureKPa, meter.brakeCylinderPressureKPa,
                      meter.mainReservoirPressureKPa]
        XCTAssertTrue(values.allSatisfy { $0.isFinite })
        XCTAssertGreaterThanOrEqual(meter.speedMps, 0)
        XCTAssertGreaterThanOrEqual(meter.positionM, 0)
        XCTAssertEqual(meter.lineVoltageV, selected.traction.nominalLineVoltageV, accuracy: 1e-9)
    }

    func testVersionedEngineSnapshotRoundTripsAndContinuesIdentically() throws {
        var original = try makeEngine(.vvvfIGBT, load: 0.83)
        runTicks(&original, 720, controls: SimulationControls(throttleNotch: 5),
                 track: TrackCondition(gradientPermille: 8, curveRadiusM: 520, speedLimitKmh: 90, supplyVoltageV: 1_500),
                 surface: .wet, modifiers: PhysicsModifiers(tractionMultiplier: 0.91, brakingMultiplier: 1.07,
                                                             speedCapKmh: 88, adhesionCoefficientOverride: 0.16))
        runTicks(&original, 90, controls: SimulationControls(brakeNotch: 3), surface: .wet)
        let json = try JSONEncoder().encode(original.stateSnapshot())
        let decoded = try JSONDecoder().decode(TrainPhysicsEngineStateSnapshot.self, from: json)
        var restored = try makeEngine(.vvvfIGBT, load: 0.1)
        try restored.restoreState(from: decoded)

        XCTAssertEqual(restored.stateSnapshot(), original.stateSnapshot())
        XCTAssertEqual(restored.telemetry, original.telemetry)
        runTicks(&original, 24, controls: SimulationControls(throttleNotch: 2),
                 track: TrackCondition(gradientPermille: -4, speedLimitKmh: 80), surface: .wet)
        runTicks(&restored, 24, controls: SimulationControls(throttleNotch: 2),
                 track: TrackCondition(gradientPermille: -4, speedLimitKmh: 80), surface: .wet)
        XCTAssertEqual(restored.telemetry, original.telemetry)
    }

    func testEngineSnapshotRejectsProfileMismatchAndNonFiniteValues() throws {
        let engine = try makeEngine(.fieldChopperDC)
        var mismatch = engine.stateSnapshot()
        mismatch.profileID = "another-fictional-profile"
        var restored = try makeEngine(.fieldChopperDC)
        XCTAssertThrowsError(try restored.restoreState(from: mismatch))

        var invalid = engine.stateSnapshot()
        invalid.positionM = .nan
        XCTAssertThrowsError(try restored.restoreState(from: invalid))
    }
}
