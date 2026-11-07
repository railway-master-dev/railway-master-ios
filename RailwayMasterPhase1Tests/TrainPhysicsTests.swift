import XCTest
@testable import RailwayMasterPhase1

final class TrainPhysicsTests: XCTestCase {
    private let route = RailwayRouteProfile.fictionalMainlineFallback

    func testCurveTransitionInterpolatesCurvatureAndCantAndReversesExactly() {
        let transition = RouteCurveTransition(startM: 10, circularStartM: 20, circularEndM: 40, endM: 50)
        XCTAssertTrue(transition.isValid)
        XCTAssertEqual(transition.fraction(at: 10), 0, accuracy: 1e-12)
        XCTAssertEqual(transition.fraction(at: 15), 0.5, accuracy: 1e-12)
        XCTAssertEqual(transition.fraction(at: 25), 1, accuracy: 1e-12)
        XCTAssertEqual(transition.fraction(at: 45), 0.5, accuracy: 1e-12)
        XCTAssertEqual(transition.fraction(at: 50), 0, accuracy: 1e-12)

        let profile = RailwayRouteProfile(
            lineName: "緩和曲線検査（架空）", departureStation: "甲", arrivalStation: "乙",
            distanceM: 60, stopMarkerM: 55,
            sections: [RouteSection(
                startM: 0, endM: 60, curveRadiusM: 900, curveDirection: 1, cantMm: 80,
                curveTransition: transition, speedLimitKmh: 40
            )]
        )
        XCTAssertNil(profile.condition(at: 10).curveRadiusM)
        XCTAssertEqual(profile.condition(at: 15).curveRadiusM ?? 0, 1_800, accuracy: 1e-9)
        XCTAssertEqual(profile.condition(at: 15).cantMm ?? 0, 40, accuracy: 1e-9)
        XCTAssertEqual(profile.condition(at: 25).curveRadiusM ?? 0, 900, accuracy: 1e-9)
        XCTAssertEqual(profile.condition(at: 25).cantMm ?? 0, 80, accuracy: 1e-9)
        XCTAssertEqual(profile.condition(at: 45).curveRadiusM ?? 0, 1_800, accuracy: 1e-9)

        let reversed = transition.reversed(over: 100)
        XCTAssertTrue(reversed.isValid)
        for chainage in stride(from: 0.0, through: 100.0, by: 1.0) {
            XCTAssertEqual(transition.fraction(at: chainage), reversed.fraction(at: 100 - chainage), accuracy: 1e-12)
        }
        let invalidProfile = RailwayRouteProfile(
            lineName: "不正な緩和曲線（検査用）", departureStation: "甲", arrivalStation: "乙",
            distanceM: 100, stopMarkerM: 90,
            sections: [RouteSection(
                startM: 0, endM: 100, curveRadiusM: 900,
                curveTransition: RouteCurveTransition(startM: 50, circularStartM: 40, circularEndM: 60, endM: 70),
                speedLimitKmh: 40
            )]
        )
        XCTAssertTrue(invalidProfile.validateData().contains { $0.code == "route.curveTransition.invalid" })
    }

    func testFixedStepAcceleratesTrainAndAdvancesPosition() {
        var engine = TrainPhysicsEngine()
        tick(&engine, count: 600, controls: TrainControls(throttleNotch: 4), route: route, weather: .dry)
        XCTAssertGreaterThan(engine.speedMps, 0)
        XCTAssertGreaterThan(engine.positionM, 0)
        XCTAssertGreaterThan(engine.accelerationMps2, 0)
        XCTAssertEqual(TrainPhysicsEngine.fixedTimeStep, 1.0 / 120.0, accuracy: 1e-12)
    }

    func testPassengerLoadChangesEffectiveMass() {
        var engine = TrainPhysicsEngine(passengerLoadFactor: 0)
        let emptyMass = engine.telemetry(route: route).effectiveMassKg
        engine.setPassengerLoadFactor(2)
        let fullyLoadedMass = engine.telemetry(route: route).effectiveMassKg
        XCTAssertEqual(emptyMass, 194_400, accuracy: 0.1)
        XCTAssertEqual(fullyLoadedMass, 279_936, accuracy: 0.1)
        XCTAssertGreaterThan(fullyLoadedMass, emptyMass)
    }

    func testTractionCurveObeysPowerAndMaximumSpeed() {
        let train = TrainParameters.fictionalPrototype
        let lowSpeedForce = train.availableTractionForce(atSpeedKmh: 10)
        let highSpeedForce = train.availableTractionForce(atSpeedKmh: 80)
        XCTAssertEqual(lowSpeedForce, train.maximumTractionForceN, accuracy: 0.1)
        XCTAssertLessThan(highSpeedForce, lowSpeedForce)
        XCTAssertEqual(train.availableTractionForce(atSpeedKmh: train.maximumSpeedKmh), 0)
    }

    func testDirectPhysicsStepAppliesRouteSpeedLimitWithoutExternalCap() {
        let unrestricted = RailwayRouteProfile(
            lineName: "架空高速区間", departureStation: "甲", arrivalStation: "乙",
            distanceM: 100_000, stopMarkerM: 99_000,
            sections: [RouteSection(startM: 0, endM: 100_000, speedLimitKmh: 100)]
        )
        let restricted = RailwayRouteProfile(
            lineName: "架空低速区間", departureStation: "甲", arrivalStation: "乙",
            distanceM: 100_000, stopMarkerM: 99_000,
            sections: [RouteSection(startM: 0, endM: 100_000, speedLimitKmh: 18)]
        )
        var engine = TrainPhysicsEngine()
        tick(&engine, count: 5_000, controls: TrainControls(throttleNotch: 5), route: unrestricted, weather: .dry)
        XCTAssertGreaterThan(engine.speedMps * 3.6, 18)
        engine.step(dt: TrainPhysicsEngine.fixedTimeStep, controls: TrainControls(), route: restricted, weather: .dry)
        XCTAssertLessThanOrEqual(engine.speedMps * 3.6, 18 + 1e-6)
    }

    func testFixedStepAdvanceAppliesRouteSpeedLimitWithoutExternalCap() {
        let restricted = RailwayRouteProfile(
            lineName: "架空速度制限区間", departureStation: "甲", arrivalStation: "乙",
            distanceM: 100_000, stopMarkerM: 99_000,
            sections: [RouteSection(startM: 0, endM: 100_000, speedLimitKmh: 22)]
        )
        var engine = TrainPhysicsEngine()
        for _ in 0..<80 {
            engine.advance(realDelta: 0.5, controls: TrainControls(throttleNotch: 5), route: restricted, weather: .dry)
        }
        XCTAssertLessThanOrEqual(engine.speedMps * 3.6, 22 + 1e-6)
    }

    func testTractionJerkIsBoundedAtTheStartOfPowering() {
        var engine = TrainPhysicsEngine()
        tick(&engine, count: 1, controls: TrainControls(throttleNotch: 5), route: route, weather: .dry)
        let telemetry = engine.telemetry(route: route)
        let allowedAccelerationChange = TrainParameters.fictionalPrototype.tractionJerkMps3 * TrainPhysicsEngine.fixedTimeStep
        XCTAssertLessThanOrEqual(telemetry.tractionForceN / telemetry.effectiveMassKg, allowedAccelerationChange + 1e-5)
    }

    func testUphillReducesAccelerationComparedWithDownhill() {
        var uphill = TrainPhysicsEngine()
        var downhill = TrainPhysicsEngine()
        let uphillRoute = RailwayRouteProfile(lineName: "架空上り", departureStation: "甲", arrivalStation: "乙", distanceM: 100, stopMarkerM: 90,
                                              sections: [RouteSection(startM: 0, endM: 100, gradientPermille: 10, speedLimitKmh: 40)])
        let downhillRoute = RailwayRouteProfile(lineName: "架空下り", departureStation: "甲", arrivalStation: "乙", distanceM: 100, stopMarkerM: 90,
                                                sections: [RouteSection(startM: 0, endM: 100, gradientPermille: -10, speedLimitKmh: 40)])
        tick(&uphill, count: 1, controls: TrainControls(throttleNotch: 4), route: uphillRoute, weather: .dry)
        tick(&downhill, count: 1, controls: TrainControls(throttleNotch: 4), route: downhillRoute, weather: .dry)
        XCTAssertLessThan(uphill.accelerationMps2, downhill.accelerationMps2)
    }

    func testCurveResistanceReducesAcceleration() {
        var straight = TrainPhysicsEngine()
        var curved = TrainPhysicsEngine()
        let straightRoute = RailwayRouteProfile(lineName: "直線（架空）", departureStation: "甲", arrivalStation: "乙", distanceM: 100, stopMarkerM: 90,
                                                sections: [RouteSection(startM: 0, endM: 100, speedLimitKmh: 40)])
        let curvedRoute = RailwayRouteProfile(lineName: "曲線（架空）", departureStation: "甲", arrivalStation: "乙", distanceM: 100, stopMarkerM: 90,
                                              sections: [RouteSection(startM: 0, endM: 100, curveRadiusM: 400, speedLimitKmh: 40)])
        tick(&straight, count: 60, controls: TrainControls(throttleNotch: 5), route: straightRoute, weather: .dry)
        tick(&curved, count: 60, controls: TrainControls(throttleNotch: 5), route: curvedRoute, weather: .dry)
        XCTAssertGreaterThan(curved.telemetry(route: curvedRoute).curveResistanceN, 0)
        XCTAssertLessThan(curved.accelerationMps2, straight.accelerationMps2)
    }

    func testSnowAdhesionLimitsTractionComparedWithDryRail() {
        var dryEngine = TrainPhysicsEngine()
        var snowEngine = TrainPhysicsEngine()
        tick(&dryEngine, count: 600, controls: TrainControls(throttleNotch: 5), route: route, weather: .dry)
        tick(&snowEngine, count: 600, controls: TrainControls(throttleNotch: 5), route: route, weather: .snow)
        XCTAssertLessThan(snowEngine.telemetry(route: route, weather: .snow).tractionForceN, dryEngine.telemetry(route: route, weather: .dry).tractionForceN)
        XCTAssertTrue(snowEngine.telemetry(route: route, weather: .snow).isWheelSlipActive)
    }

    func testServiceBrakeRespondsAndTrainNeverReverses() {
        var engine = TrainPhysicsEngine()
        tick(&engine, count: 600, controls: TrainControls(throttleNotch: 4), route: route, weather: .dry)
        let speedBeforeBrake = engine.speedMps
        tick(&engine, count: 1, controls: TrainControls(brakeNotch: 7), route: route, weather: .dry)
        XCTAssertGreaterThan(engine.speedMps, 0)
        XCTAssertLessThan(engine.speedMps, speedBeforeBrake)
        tick(&engine, count: 2_000, controls: TrainControls(brakeNotch: 7), route: route, weather: .dry)
        XCTAssertGreaterThanOrEqual(engine.speedMps, 0)
    }

    func testEmergencyBrakeBuildsForceFasterThanServiceBrake() {
        var service = TrainPhysicsEngine()
        var emergency = TrainPhysicsEngine()
        tick(&service, count: 24, controls: TrainControls(brakeNotch: 7), route: route, weather: .dry)
        tick(&emergency, count: 24, controls: TrainControls(emergencyBrake: true), route: route, weather: .dry)
        XCTAssertGreaterThan(emergency.telemetry(route: route).brakingForceN, service.telemetry(route: route).brakingForceN)
    }

    func testBrakePneumaticIndicatorsChangeWithBrakeCommand() {
        var engine = TrainPhysicsEngine()
        tick(&engine, count: 120, controls: TrainControls(brakeNotch: 5), route: route, weather: .dry)
        let telemetry = engine.telemetry(route: route)
        XCTAssertGreaterThan(telemetry.brakeCylinderPressureKPa, 0)
        XCTAssertLessThan(telemetry.brakePipePressureKPa, 500)
        XCTAssertGreaterThan(telemetry.mainReservoirPressureKPa, 700)
    }

    func testFixedStepAdvanceMatchesAcrossRenderCadences() {
        var at30Hz = TrainPhysicsEngine()
        var at60Hz = TrainPhysicsEngine()
        for _ in 0..<30 {
            at30Hz.advance(realDelta: 1.0 / 30.0, controls: TrainControls(throttleNotch: 3), route: route, weather: .dry)
        }
        for _ in 0..<60 {
            at60Hz.advance(realDelta: 1.0 / 60.0, controls: TrainControls(throttleNotch: 3), route: route, weather: .dry)
        }
        XCTAssertEqual(at30Hz.speedMps, at60Hz.speedMps, accuracy: 0.03)
        XCTAssertEqual(at30Hz.positionM, at60Hz.positionM, accuracy: 0.08)
    }

    func testInvalidOrZeroDeltaDoesNotAdvanceSimulation() {
        var engine = TrainPhysicsEngine()
        engine.advance(realDelta: 0, controls: TrainControls(throttleNotch: 4), route: route, weather: .dry)
        XCTAssertEqual(engine.positionM, 0)
        XCTAssertEqual(engine.speedMps, 0)
    }

    func testFictionalRouteIsExplicitlyPlaceholderAndStructurallyValid() {
        XCTAssertEqual(route.dataStatus, .placeholder)
        let issues = route.validateData()
        XCTAssertFalse(issues.contains { $0.severity == .error })
        XCTAssertTrue(issues.contains { $0.code == "route.data.placeholder" })
    }

    func testRouteValidatorFindsChainageGapAndUnsubstantiatedVerifiedData() {
        let unsupportedSource = RouteDataProvenance(field: "gradient", status: .verified)
        let invalidRoute = RailwayRouteProfile(
            lineName: "検査用（架空）", departureStation: "甲", arrivalStation: "乙",
            distanceM: 100, stopMarkerM: 90,
            sections: [
                RouteSection(startM: 0, endM: 40, speedLimitKmh: 40),
                RouteSection(startM: 60, endM: 100, speedLimitKmh: 40)
            ],
            dataStatus: .verified,
            dataProvenance: [unsupportedSource]
        )
        let codes = Set(invalidRoute.validateData().map(\.code))
        XCTAssertTrue(codes.contains("route.chainage.gap"))
        XCTAssertTrue(codes.contains("route.provenance.verifiedIncomplete"))
    }

    func testEstimatedRouteValueRequiresBasisAndUncertaintyRange() {
        let estimate = RouteDataProvenance(field: "curveRadiusM", status: .estimated)
        let estimatedRoute = RailwayRouteProfile(
            lineName: "検査用（架空）", departureStation: "甲", arrivalStation: "乙",
            distanceM: 100, stopMarkerM: 90,
            sections: [RouteSection(startM: 0, endM: 100, curveRadiusM: 400, speedLimitKmh: 40)],
            dataStatus: .estimated,
            dataProvenance: [estimate]
        )
        XCTAssertTrue(estimatedRoute.validateData().contains { $0.code == "route.provenance.estimateIncomplete" })
    }

    private func tick(
        _ engine: inout TrainPhysicsEngine,
        count: Int,
        controls: TrainControls,
        route: RailwayRouteProfile,
        weather: WeatherCondition
    ) {
        for _ in 0..<count {
            engine.advance(realDelta: TrainPhysicsEngine.fixedTimeStep, controls: controls, route: route, weather: weather)
        }
    }
}
