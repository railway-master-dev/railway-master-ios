import Foundation
import XCTest
@testable import RailwayTimetable

final class CanonicalIntegrationTests: XCTestCase {
    private func makeCanonicalTimetable() throws -> TimetableNetwork {
        let packageRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let workspaceRoot = packageRoot.deletingLastPathComponent().deletingLastPathComponent()
        let routeURL = workspaceRoot
            .appendingPathComponent("RAILWAY_MASTER_iOS_FullPackage/Packages/RailwayRouteData/Data/fictional_70km_network.json")
        let operationsURL = workspaceRoot
            .appendingPathComponent("RAILWAY_MASTER_iOS_FullPackage/RailwayMasterPhase1/Resources/FictionalOperationsPlan.json")
        guard FileManager.default.fileExists(atPath: routeURL.path),
              FileManager.default.fileExists(atPath: operationsURL.path) else {
            throw XCTSkip("Workspace canonical route/operations JSON is not present; integration test is optional outside the source workspace.")
        }
        let imported = try CanonicalNetworkAdapter.importInputs(
            routePackageJSON: Data(contentsOf: routeURL),
            operationsPlanJSON: Data(contentsOf: operationsURL)
        )
        return try TimetableBuilder.build(inputs: imported, weekendPlan: TimetablePlanLoader.loadBundled())
    }

    func testCanonicalIntegrationBuildsAllCalendarsWithoutInventingStations() throws {
        let timetable = try makeCanonicalTimetable()
        XCTAssertEqual(timetable.stations.count, 32)
        XCTAssertEqual(Set(timetable.stations.map(\.stationID)).count, 32)
        XCTAssertEqual(timetable.routePathStationIDs.first, "S01")
        XCTAssertEqual(timetable.routePathStationIDs.last, "B04")
        XCTAssertEqual(timetable.physicalNetworkLengthM, 70_000, accuracy: 0.001)
        XCTAssertEqual(timetable.passengerRouteLengthM, 68_000, accuracy: 0.001)
        XCTAssertEqual(timetable.services.count, 6)
        XCTAssertEqual(timetable.patterns.count, 144)
        XCTAssertEqual(Set(timetable.patterns.map(\.calendar)), Set(ServiceCalendar.allCases))
        XCTAssertEqual(Set(timetable.patterns.map(\.direction)), Set(ServiceDirection.allCases))
        XCTAssertEqual(Set(timetable.patterns.map(\.daypart)), Set(Daypart.allCases))
        XCTAssertTrue(timetable.trips.count > 0)
        XCTAssertTrue(timetable.trips.allSatisfy { $0.dataStatus == .placeholder })
        XCTAssertTrue(timetable.services.allSatisfy { (60...150).contains($0.plannedRuntimeMinutes) })
        XCTAssertEqual(timetable.services.first(where: { $0.category == .local })?.plannedRuntimeMinutes, 150)
        XCTAssertEqual(timetable.services.first(where: { $0.category == .limitedExpress })?.plannedRuntimeMinutes, 60)
        for trip in timetable.trips {
            XCTAssertEqual(trip.arrivalSeconds - trip.departureSeconds, trip.plannedRuntimeSeconds)
            XCTAssertEqual(trip.stationEvents.count, 32)
            XCTAssertEqual(trip.stationEvents.first?.stationID, trip.direction == .down ? "S01" : "B04")
            XCTAssertEqual(trip.stationEvents.last?.stationID, trip.direction == .down ? "B04" : "S01")
            for event in trip.stationEvents where event.kind == .passThrough {
                XCTAssertEqual(event.dwellSeconds, 0)
                XCTAssertEqual(event.arrivalSeconds, event.departureSeconds)
            }
        }
        XCTAssertTrue(timetable.depotMovements.contains { $0.kind == .outbound })
        XCTAssertTrue(timetable.depotMovements.contains { $0.kind == .inbound })
        XCTAssertTrue(timetable.depotMovements.allSatisfy { $0.depotID == timetable.depot.depotID && $0.distanceM == 2_000 })
        XCTAssertTrue(timetable.interactionCandidates.contains { $0.kind == .opposingDirectionMeet })
        XCTAssertTrue(timetable.interactionCandidates.contains { $0.kind == .overtake })
        XCTAssertTrue(timetable.interactionCandidates.allSatisfy(\.requiresScenarioTrackCapacity))
        XCTAssertEqual(timetable.dataStatus, .placeholder)
        let encoded = try JSONEncoder().encode(timetable)
        let decoded = try JSONDecoder().decode(TimetableNetwork.self, from: encoded)
        XCTAssertEqual(decoded.trips.count, timetable.trips.count)
        XCTAssertEqual(decoded.stations.map(\.stationID), timetable.stations.map(\.stationID))
    }

    func testRuntimeApportionmentIsExactAndTimeFormattingSupportsNextDay() throws {
        XCTAssertEqual(try RuntimeAllocator.allocate(totalSeconds: 101, distances: [2, 3, 5]), [20, 30, 51])
        XCTAssertEqual(try TimetableClock.parse("24:00"), 1_440)
        XCTAssertEqual(TimetableClock.display(90_000), "翌日01:00")
        XCTAssertThrowsError(try TimetableClock.parse("24:01"))
    }

    func testDelayPropagationAndGameDispatchActions() throws {
        let timetable = try makeCanonicalTimetable()
        let sameDirection = timetable.trips
            .filter { $0.calendar == .weekday && $0.direction == .down }
            .sorted { $0.departureSeconds == $1.departureSeconds ? $0.tripID < $1.tripID : $0.departureSeconds < $1.departureSeconds }
        let first = try XCTUnwrap(sameDirection.first)
        let second = try XCTUnwrap(sameDirection.dropFirst().first)
        let scenario = DelayScenario(
            calendar: .weekday,
            direction: .down,
            initialTripID: first.tripID,
            initialDelayMinutes: 15
        )
        let propagated = try DisruptionSimulator.simulate(network: timetable, scenario: scenario)
        let affectedSecond = try XCTUnwrap(propagated.affectedTrips.first(where: { $0.tripID == second.tripID }))
        XCTAssertGreaterThan(affectedSecond.departureDelaySeconds, 0)
        XCTAssertEqual(propagated.dataStatus, .placeholder)

        let intermediateStop = try XCTUnwrap(first.stationEvents.dropFirst().dropLast().first(where: { $0.kind == .stop }))
        let cancellationTarget = try XCTUnwrap(sameDirection.dropFirst(2).first)
        let holdTarget = try XCTUnwrap(sameDirection.last)
        let actionScenario = DelayScenario(
            calendar: .weekday,
            direction: .down,
            initialTripID: first.tripID,
            initialDelayMinutes: 8,
            actions: [
                .skipStop(tripID: first.tripID, stationID: intermediateStop.stationID),
                .cancel(tripID: cancellationTarget.tripID),
                .hold(tripID: holdTarget.tripID, minutes: 2)
            ]
        )
        let adjusted = try DisruptionSimulator.simulate(network: timetable, scenario: actionScenario)
        let adjustedFirst = try XCTUnwrap(adjusted.affectedTrips.first(where: { $0.tripID == first.tripID }))
        XCTAssertEqual(adjustedFirst.stationEvents.first(where: { $0.stationID == intermediateStop.stationID })?.kind, .passThrough)
        XCTAssertTrue(adjusted.affectedTrips.first(where: { $0.tripID == cancellationTarget.tripID })?.isCancelled == true)
        let held = try XCTUnwrap(adjusted.affectedTrips.first(where: { $0.tripID == holdTarget.tripID }))
        XCTAssertGreaterThanOrEqual(held.departureDelaySeconds, 120)
    }
}
