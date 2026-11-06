import Foundation
import XCTest
@testable import EnvironmentConditions

final class WeatherSnapshotTests: XCTestCase {
    func testIndependentAxesAllowRainAndLeafResidueTogether() {
        let snapshot = makeSnapshot(
            timeOfDaySeconds: 45_000,
            precipitation: PrecipitationState(kind: .rain, rateMillimetersPerHour: 4.5),
            railSurface: RailSurfaceState(
                condition: .wet,
                contaminants: [.leafResidue],
                surfaceFrictionMultiplier: 0.72,
                railAdhesionMultiplier: 0.58
            ),
            wind: WindState(speedMetersPerSecond: 8, directionDegreesFromNorth: 250),
            visibilityMeters: 1_200
        )

        XCTAssertEqual(snapshot.precipitation.kind, .rain)
        XCTAssertEqual(snapshot.railSurface.condition, .wet)
        XCTAssertTrue(snapshot.railSurface.contaminants.contains(.leafResidue))
        XCTAssertEqual(snapshot.wind.speedMetersPerSecond, 8)
        XCTAssertEqual(snapshot.visibilityMeters, 1_200)
        XCTAssertEqual(snapshot.timeOfDaySeconds, 45_000)
    }

    func testValuesAreNormalizedAtConstruction() {
        let snapshot = makeSnapshot(
            timeOfDaySeconds: -60,
            precipitation: PrecipitationState(kind: .snow, rateMillimetersPerHour: -2, snowCoverDepthMeters: .infinity),
            railSurface: RailSurfaceState(
                condition: .ice,
                surfaceFrictionMultiplier: 1.5,
                railAdhesionMultiplier: -.infinity
            ),
            wind: WindState(
                speedMetersPerSecond: -.infinity,
                gustSpeedMetersPerSecond: -1,
                directionDegreesFromNorth: -10
            ),
            visibilityMeters: -5,
            airTemperatureCelsius: .nan
        )

        XCTAssertEqual(snapshot.timeOfDaySeconds, 86_340)
        XCTAssertNil(snapshot.precipitation.rateMillimetersPerHour)
        XCTAssertNil(snapshot.precipitation.snowCoverDepthMeters)
        XCTAssertEqual(snapshot.railSurface.surfaceFrictionMultiplier, 1)
        XCTAssertEqual(snapshot.railSurface.railAdhesionMultiplier, 0)
        XCTAssertEqual(snapshot.wind.speedMetersPerSecond, 0)
        XCTAssertNil(snapshot.wind.gustSpeedMetersPerSecond)
        XCTAssertEqual(snapshot.wind.directionDegreesFromNorth, 350)
        XCTAssertEqual(snapshot.visibilityMeters, 0)
        XCTAssertNil(snapshot.airTemperatureCelsius)
    }

    func testCodableRoundTrip() throws {
        let original = makeSnapshot(
            timeOfDaySeconds: 27_000,
            precipitation: PrecipitationState(kind: .freezingRain, rateMillimetersPerHour: 0.8),
            railSurface: RailSurfaceState(
                condition: .wet,
                contaminants: [.leafResidue, .mud],
                surfaceFrictionMultiplier: 0.6,
                railAdhesionMultiplier: 0.4
            ),
            wind: WindState(
                speedMetersPerSecond: 3.2,
                gustSpeedMetersPerSecond: 5.1,
                directionDegreesFromNorth: 15
            ),
            visibilityMeters: 800,
            airTemperatureCelsius: 2.5
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(WeatherSnapshot.self, from: data)
        XCTAssertEqual(decoded, original)
    }

    func testDecodedGameMultipliersAreAlsoClamped() throws {
        let json = """
        {
          "simulationTimeSeconds": 3,
          "timeOfDaySeconds": 86401,
          "precipitation": { "kind": "rain", "rateMillimetersPerHour": 2 },
          "railSurface": {
            "condition": "wet",
            "contaminants": ["leafResidue"],
            "surfaceFrictionMultiplier": 1.25,
            "railAdhesionMultiplier": -0.2
          },
          "wind": { "speedMetersPerSecond": 4 },
          "visibilityMeters": 500
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(WeatherSnapshot.self, from: json)
        XCTAssertEqual(decoded.timeOfDaySeconds, 1)
        XCTAssertEqual(decoded.railSurface.surfaceFrictionMultiplier, 1)
        XCTAssertEqual(decoded.railSurface.railAdhesionMultiplier, 0)
        XCTAssertNil(decoded.airTemperatureCelsius)
    }

    private func makeSnapshot(
        simulationTimeSeconds: TimeInterval = 12.5,
        timeOfDaySeconds: TimeInterval = 43_200,
        precipitation: PrecipitationState = PrecipitationState(kind: .none),
        railSurface: RailSurfaceState = RailSurfaceState(
            condition: .dry,
            surfaceFrictionMultiplier: 1,
            railAdhesionMultiplier: 1
        ),
        wind: WindState = WindState(speedMetersPerSecond: 0),
        visibilityMeters: Float? = nil,
        airTemperatureCelsius: Float? = nil
    ) -> WeatherSnapshot {
        WeatherSnapshot(
            simulationTimeSeconds: simulationTimeSeconds,
            timeOfDaySeconds: timeOfDaySeconds,
            precipitation: precipitation,
            railSurface: railSurface,
            wind: wind,
            visibilityMeters: visibilityMeters,
            airTemperatureCelsius: airTemperatureCelsius
        )
    }
}
