import XCTest
@testable import RailwaySessionPersistence

final class PostRunReviewTests: XCTestCase {
    func testTraceDropsInvalidSamplesAndKeepsEndpointsWhenDecimated() {
        var samples = [
            sample(time: .nan, distance: 0, speed: 10),
            sample(time: 0, distance: 0, speed: 0),
            sample(time: 1, distance: 10, speed: 20, brake: 2),
            sample(time: 0.5, distance: 8, speed: 15),
            sample(time: 1, distance: 11, speed: 21)
        ]
        for index in 2..<12 {
            let emergency = index == 11
            samples.append(sample(time: Double(index), distance: Double(index) * 10, speed: Double(index), brake: emergency ? 7 : 0, emergency: emergency))
        }
        let trace = RunTraceSeriesBuilder.make(samples: samples, maximumPoints: 5)
        XCTAssertEqual(trace.dataStatus, "PLACEHOLDER")
        XCTAssertEqual(trace.rejectedSampleCount, 3)
        XCTAssertLessThanOrEqual(trace.points.count, 5)
        XCTAssertEqual(trace.points.first?.timeSeconds, 0)
        XCTAssertEqual(trace.points.last?.timeSeconds, 11)
        XCTAssertEqual(trace.points.last?.brakeFraction ?? 0, 1, accuracy: 0.0001)
        let full = RunTraceSeriesBuilder.make(samples: samples, maximumPoints: 50)
        let notch = full.points.first { $0.timeSeconds == 1 }?.brakeFraction ?? 0
        XCTAssertEqual(notch, 2.0 / 7.0, accuracy: 0.0001)
    }

    func testPunctualityUsesStationDeviationAndDoesNotScoreMissingDataAsZero() {
        let onTime = PostRunReviewBuilder.make(
            samples: [sample(time: 0, distance: 0, speed: 0), sample(time: 40, distance: 100, speed: 0)],
            stationFacts: [StationRunFact(stationID: "a", displayName: "A", arrivalDeviationSeconds: 10, stopErrorMeters: 1)]
        )
        let late = PostRunReviewBuilder.make(
            samples: [sample(time: 0, distance: 0, speed: 0), sample(time: 40, distance: 100, speed: 0)],
            stationFacts: [StationRunFact(stationID: "a", displayName: "A", arrivalDeviationSeconds: 90, stopErrorMeters: 1)]
        )
        let missing = PostRunReviewBuilder.make(samples: [sample(time: 0, distance: 0, speed: 0)])
        XCTAssertEqual(onTime.lines.first { $0.id == "punctuality" }?.score, 100)
        XCTAssertLessThan(late.lines.first { $0.id == "punctuality" }?.score ?? 100, 100)
        XCTAssertNil(missing.lines.first { $0.id == "punctuality" }?.score)
        XCTAssertNil(missing.overallScore)
        XCTAssertTrue(onTime.notes.contains { $0.contains("PLACEHOLDER") })
    }

    func testStoppingSpeedAndSignalAggregateOnlyRecordedFacts() {
        let samples = [
            sample(time: 0, distance: 0, speed: 0, limit: 80, aspect: "green"),
            sample(time: 10, distance: 200, speed: 90, limit: 80, aspect: "yellow"),
            sample(time: 20, distance: 400, speed: 40, limit: 80, aspect: "red"),
            sample(time: 30, distance: 500, speed: 4, limit: 80, aspect: "stop")
        ]
        let review = PostRunReviewBuilder.make(
            samples: samples,
            stopMarkerM: 500,
            stationFacts: [StationRunFact(stationID: "end", displayName: "終端", stopErrorMeters: 2)]
        )
        let stopping = review.lines.first { $0.id == "stopping" }
        let speed = review.lines.first { $0.id == "speed" }
        let signal = review.lines.first { $0.id == "signal" }
        XCTAssertEqual(stopping?.score ?? 0, 60, accuracy: 0.001)
        XCTAssertLessThan(speed?.score ?? 100, 100)
        XCTAssertEqual(signal?.score ?? 0, 50, accuracy: 0.001)
        XCTAssertTrue(signal?.detail.contains("停止現示") == true)
        XCTAssertEqual(review.trace.points.count, 4)
        XCTAssertTrue(review.trace.points.contains { $0.restrictiveSignal && $0.speedKmh == 40 })
    }

    func testSpeedAndSignalStayUnscoredWhenTheRunHasNoLimitsOrStopAspects() {
        let review = PostRunReviewBuilder.make(samples: [
            sample(time: 0, distance: 0, speed: 30, aspect: "green"),
            sample(time: 5, distance: 40, speed: 0, aspect: "yellow")
        ], stopMarkerM: 40)
        XCTAssertNil(review.lines.first { $0.id == "speed" }?.score)
        XCTAssertNil(review.lines.first { $0.id == "signal" }?.score)
        XCTAssertNotNil(review.lines.first { $0.id == "stopping" }?.score)
        XCTAssertEqual(review.lines.first { $0.id == "punctuality" }?.dataStatus, "PLACEHOLDER")
    }

    private func sample(
        time: Double,
        distance: Double,
        speed: Double,
        brake: Int = 0,
        emergency: Bool = false,
        limit: Double? = nil,
        aspect: String? = nil
    ) -> RunTraceSample {
        RunTraceSample(
            timeSeconds: time,
            distanceM: distance,
            speedKmh: speed,
            brakeNotch: brake,
            emergencyBrake: emergency,
            speedLimitKmh: limit,
            signalAspect: aspect
        )
    }
}
