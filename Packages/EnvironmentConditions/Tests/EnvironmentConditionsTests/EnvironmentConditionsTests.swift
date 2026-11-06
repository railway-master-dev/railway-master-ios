import XCTest
@testable import EnvironmentConditions

final class EnvironmentConditionsTests: XCTestCase {
    func testNamedFixturesAreDeterministicAndInternallyStable() {
        XCTAssertEqual(EnvironmentConditions.rainyDusk, EnvironmentConditions.rainyDusk)
        XCTAssertEqual(EnvironmentConditions.rainyDusk.precipitation, .rain)
        XCTAssertEqual(EnvironmentConditions.rainyDusk.wiperState, .low)
        XCTAssertEqual(EnvironmentConditions.rainyDusk.dayPeriod, .dusk)
        XCTAssertEqual(EnvironmentConditions.foggyNight.fogDensity, 0.85)
        XCTAssertEqual(EnvironmentConditions.foggyNight.precipitation, .none)
        XCTAssertEqual(EnvironmentConditions.snowyWinter.season, .winter)
    }

    func testFogWindVisibilityLightingAndWiperRemainIndependent() {
        let clearFog = EnvironmentConditions(
            precipitation: .none, fogDensity: 0.9, windSpeedMps: 12, windDirectionDegrees: 30,
            visibilityM: 180, adhesionCoefficient: 0.25, ambientIlluminanceLux: 0,
            headlightIntensity: 1, wiperState: .off, season: .summer, dayPeriod: .night
        )
        XCTAssertEqual(clearFog.precipitation, .none)
        XCTAssertEqual(clearFog.fogDensity, 0.9)
        XCTAssertEqual(clearFog.visibilityM, 180)
        XCTAssertEqual(clearFog.windSpeedMps, 12)
        XCTAssertEqual(clearFog.wiperState, .off)
        XCTAssertEqual(clearFog.legacyWeatherCaseName, "dry")
    }

    func testNumericInputsAreClampedAndNonFiniteValuesUseSafeFallbacks() {
        let value = EnvironmentConditions(
            precipitation: .rain, fogDensity: .infinity, windSpeedMps: -2,
            windDirectionDegrees: .nan, visibilityM: 200_000, adhesionCoefficient: 4,
            ambientIlluminanceLux: -.infinity, headlightIntensity: 2,
            wiperState: .high, season: .spring, dayPeriod: .dawn
        )
        XCTAssertEqual(value.fogDensity, 0)
        XCTAssertEqual(value.windSpeedMps, 0)
        XCTAssertEqual(value.windDirectionDegrees, 0)
        XCTAssertEqual(value.visibilityM, 100_000)
        XCTAssertEqual(value.adhesionCoefficient, 1)
        XCTAssertEqual(value.ambientIlluminanceLux, 0)
        XCTAssertEqual(value.headlightIntensity, 1)

        let lowerBounds = EnvironmentConditions(
            precipitation: .snow, fogDensity: -1, windSpeedMps: 100,
            windDirectionDegrees: -450, visibilityM: -10, adhesionCoefficient: -1,
            ambientIlluminanceLux: 150_000, headlightIntensity: -1,
            wiperState: .intermittent, season: .winter, dayPeriod: .night
        )
        XCTAssertEqual(lowerBounds.windSpeedMps, 60)
        XCTAssertEqual(lowerBounds.windDirectionDegrees, 270)
        XCTAssertEqual(lowerBounds.visibilityM, 1)
        XCTAssertEqual(lowerBounds.adhesionCoefficient, 0)
        XCTAssertEqual(lowerBounds.ambientIlluminanceLux, 120_000)
    }

    func testLegacyProjectionIsExplicitlyThreeWayAndLossy() {
        XCTAssertEqual(EnvironmentConditions.clearDay.legacyWeatherCaseName, "dry")
        XCTAssertEqual(EnvironmentConditions.rainyDusk.legacyWeatherCaseName, "rain")
        XCTAssertEqual(EnvironmentConditions.snowyWinter.legacyWeatherCaseName, "snow")
        XCTAssertEqual(EnvironmentConditions.foggyNight.legacyWeatherCaseName, "dry")
        XCTAssertNotEqual(EnvironmentConditions.foggyNight.adhesionCoefficient, 0.27)
    }

    func testCodableRoundTrip() throws {
        let original = EnvironmentConditions.snowyWinter
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(EnvironmentConditions.self, from: data)
        XCTAssertEqual(decoded, original)
    }
}
