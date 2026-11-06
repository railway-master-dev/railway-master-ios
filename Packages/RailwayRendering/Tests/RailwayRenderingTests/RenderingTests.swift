import XCTest
import RailwayRendering

final class RenderingTests: XCTestCase {
    func testCameraViewSwitchUsesSmoothTransition() {
        let camera = CameraController(viewMode: .cab)
        let cabStart = camera.update(deltaTime: 0)
        camera.viewMode = .chase

        let transitionStart = camera.update(deltaTime: 0)
        let midTransition = camera.update(deltaTime: 0.325)
        let transitionEnd = camera.update(deltaTime: 0.325)

        XCTAssertEqual(transitionStart.position.z, cabStart.position.z, accuracy: 0.0001)
        XCTAssertGreaterThan(midTransition.position.y, transitionStart.position.y)
        XCTAssertLessThan(midTransition.position.y, transitionEnd.position.y)
        let chaseBaseline = CameraController(viewMode: .chase).update(deltaTime: 0)
        XCTAssertEqual(transitionEnd.position.y, chaseBaseline.position.y, accuracy: 0.0001)
    }

    func testCameraMotionRespondsToAccelerationAndCurveWithinSmallBounds() {
        let controller = CameraController()
        let still = controller.update(deltaTime: 0)
        controller.setMotion(TrainMotionSample(
            simulationTimeSeconds: 1.25,
            speedMetersPerSecond: 30,
            longitudinalAccelerationMetersPerSecondSquared: 4,
            curveRadiusMeters: 250,
            curveDirection: .left
        ))
        let moving = controller.update(deltaTime: 1.0 / 60.0)

        XCTAssertLessThan(abs(moving.position.x - still.position.x), 0.06)
        XCTAssertLessThan(abs(moving.position.z - still.position.z), 0.09)
        XCTAssertLessThan(abs(moving.rollRadians), 0.03)
    }

    func testCameraSanitizesInvalidMotionAndDelta() {
        let controller = CameraController()
        controller.setMotion(TrainMotionSample(
            simulationTimeSeconds: .nan,
            speedMetersPerSecond: .infinity,
            longitudinalAccelerationMetersPerSecondSquared: .nan,
            curveRadiusMeters: .nan,
            curveDirection: .right
        ))
        let pose = controller.update(deltaTime: .nan)

        XCTAssertTrue(pose.position.x.isFinite)
        XCTAssertTrue(pose.position.y.isFinite)
        XCTAssertTrue(pose.position.z.isFinite)
        XCTAssertTrue(pose.target.x.isFinite)
        XCTAssertTrue(pose.target.y.isFinite)
        XCTAssertTrue(pose.target.z.isFinite)
        XCTAssertTrue(pose.fieldOfViewDegrees.isFinite)
        XCTAssertTrue(pose.rollRadians.isFinite)
    }

    func testEnvironmentResolvesDayNightFogAndRain() {
        let day = EnvironmentRenderResolver.resolve(EnvironmentInput(timeOfDayHours: 12, weather: .dry))
        let night = EnvironmentRenderResolver.resolve(EnvironmentInput(timeOfDayHours: 0, weather: .dry))
        let fog = EnvironmentRenderResolver.resolve(EnvironmentInput(timeOfDayHours: 12, weather: .fog, visibilityMeters: 50))
        let rain = EnvironmentRenderResolver.resolve(EnvironmentInput(timeOfDayHours: 12, weather: .rain, precipitationIntensity: 0.7))
        let snow = EnvironmentRenderResolver.resolve(EnvironmentInput(timeOfDayHours: 12, weather: .snow, precipitationIntensity: 0.35))

        XCTAssertEqual(day.dayNightBlend, 1, accuracy: 0.0001)
        XCTAssertEqual(night.dayNightBlend, 0, accuracy: 0.0001)
        XCTAssertGreaterThan(day.sunLightScale, night.sunLightScale)
        XCTAssertEqual(fog.visibilityMeters, 100, accuracy: 0.0001)
        XCTAssertLessThanOrEqual(fog.fogStrength, 0.4)
        XCTAssertEqual(rain.rainVisualIntensity, 0.7, accuracy: 0.0001)
        XCTAssertEqual(rain.snowVisualIntensity, 0, accuracy: 0.0001)
        XCTAssertEqual(rain.surfaceWetnessBlend, 0.7, accuracy: 0.0001)
        XCTAssertEqual(rain.snowSurfaceCoverageBlend, 0, accuracy: 0.0001)
        XCTAssertEqual(snow.surfaceWetnessBlend, 0, accuracy: 0.0001)
        XCTAssertEqual(snow.snowSurfaceCoverageBlend, 0.35, accuracy: 0.0001)
        XCTAssertEqual(day.surfaceWetnessBlend, 0, accuracy: 0.0001)
        XCTAssertEqual(day.snowSurfaceCoverageBlend, 0, accuracy: 0.0001)
    }

    func testEnvironmentNormalizesInvalidValues() {
        let state = EnvironmentRenderResolver.resolve(EnvironmentInput(
            timeOfDayHours: .infinity,
            weather: .snow,
            precipitationIntensity: .nan,
            visibilityMeters: -.infinity
        ))

        XCTAssertEqual(state.localHour, 12, accuracy: 0.0001)
        XCTAssertEqual(state.snowVisualIntensity, 0, accuracy: 0.0001)
        XCTAssertEqual(state.visibilityMeters, 7_000, accuracy: 0.0001)
        XCTAssertTrue(state.fogStrength.isFinite)
    }

    func testQualityDefaultsToBalancedAndThermalStateCapsRequestedProfile() {
        let controller = RenderQualityController()
        XCTAssertEqual(controller.selectedProfile, .balanced)

        let nominalUltra = RenderQualityResolver.resolve(profile: .ultra, thermalCondition: .nominal)
        let criticalUltra = RenderQualityResolver.resolve(profile: .ultra, thermalCondition: .critical)
        let performance = RenderQualityResolver.resolve(profile: .performance, thermalCondition: .nominal)

        XCTAssertGreaterThan(nominalUltra.visibleDistanceMeters, criticalUltra.visibleDistanceMeters)
        XCTAssertEqual(criticalUltra, performance)
    }
}
