import XCTest
@testable import EnvironmentConditions

final class FictionalWeatherDrivingTests: XCTestCase {
    func testRainSnowAndFogChangeAdhesionOrVisibilityWithoutUsingARealTable() {
        let dry = FictionalWeatherDrivingCoupling.resolve(weather: .dry, windSpeedMps: 0)
        let rain = FictionalWeatherDrivingCoupling.resolve(weather: .rain, windSpeedMps: 0)
        let heavy = FictionalWeatherDrivingCoupling.resolve(weather: .heavyRain, windSpeedMps: 0)
        let snow = FictionalWeatherDrivingCoupling.resolve(weather: .snow, windSpeedMps: 0)
        let fog = FictionalWeatherDrivingCoupling.resolve(weather: .fog, windSpeedMps: 0)

        XCTAssertEqual(dry.dataStatus, "PLACEHOLDER")
        XCTAssertGreaterThan(dry.adhesionCoefficient, rain.adhesionCoefficient)
        XCTAssertGreaterThan(rain.adhesionCoefficient, heavy.adhesionCoefficient)
        XCTAssertGreaterThan(heavy.adhesionCoefficient, snow.adhesionCoefficient)
        XCTAssertEqual(fog.adhesionCoefficient, dry.adhesionCoefficient)
        XCTAssertLessThan(heavy.visibilityM, rain.visibilityM)
        XCTAssertLessThan(rain.visibilityM, dry.visibilityM)
        XCTAssertLessThan(snow.visibilityM, dry.visibilityM)
        XCTAssertLessThan(fog.visibilityM, snow.visibilityM)
        XCTAssertGreaterThan(fog.fogDensity, heavy.fogDensity)
        XCTAssertGreaterThan(heavy.fogDensity, rain.fogDensity)
        XCTAssertEqual(heavy.precipitation, .rain)
        XCTAssertEqual(fog.precipitation, .none)
        XCTAssertEqual(dry.extraResistanceN, 0)
    }

    func testWindAddsPlaceholderResistanceFromSpeedSquaredAndRejectsNonFiniteInput() {
        let calm = FictionalWeatherDrivingCoupling.resolve(weather: .rain, windSpeedMps: 0)
        let breeze = FictionalWeatherDrivingCoupling.resolve(weather: .rain, windSpeedMps: 10)
        let gale = FictionalWeatherDrivingCoupling.resolve(weather: .rain, windSpeedMps: 20)
        let nonsense = FictionalWeatherDrivingCoupling.resolve(weather: .snow, windSpeedMps: .nan)
        let capped = FictionalWeatherDrivingCoupling.resolve(weather: .dry, windSpeedMps: 1_000)

        XCTAssertEqual(breeze.extraResistanceN, 18 * 100, accuracy: 0.001)
        XCTAssertEqual(gale.extraResistanceN, 18 * 400, accuracy: 0.001)
        XCTAssertGreaterThan(gale.extraResistanceN, breeze.extraResistanceN)
        XCTAssertEqual(calm.adhesionCoefficient, breeze.adhesionCoefficient)
        XCTAssertEqual(nonsense.extraResistanceN, 0)
        XCTAssertEqual(capped.extraResistanceN, FictionalWeatherDrivingCoupling.maximumExtraResistanceN)
        XCTAssertEqual(breeze.adhesionCoefficient, FictionalWeatherDrivingCoupling.rainAdhesion)
    }
}
