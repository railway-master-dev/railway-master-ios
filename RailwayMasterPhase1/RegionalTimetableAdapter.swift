import Foundation
import RailwayRouteData
import RailwayTimetable
import StopScoring

struct RegionalTimetableSelection {
    let plannedTrip: RailwayTimetable.ScheduledTrip
    let simulatedTrip: RailwayTimetable.SimulatedTrip
    let note: String
    let routeOriginStationID: String
    let routeOriginDelaySeconds: Int
}

enum RegionalTimetableAdapter {
    static func loadCanonicalNetwork() throws -> RailwayTimetable.TimetableNetwork {
        let routeJSON = try RailwayRouteData.RoutePackageLoader.loadResourceData(named: "fictional_70km_network")
        guard let operationsURL = Bundle.main.url(forResource: "FictionalOperationsPlan", withExtension: "json") else {
            throw RailwayTimetable.TimetableError.missingResource("FictionalOperationsPlan.json in the app bundle")
        }
        let operationsJSON = try Data(contentsOf: operationsURL)
        let inputs = try RailwayTimetable.CanonicalNetworkAdapter.importInputs(
            routePackageJSON: routeJSON,
            operationsPlanJSON: operationsJSON
        )
        let weekendPlan = try RailwayTimetable.TimetablePlanLoader.loadBundled()
        return try RailwayTimetable.TimetableBuilder.build(inputs: inputs, weekendPlan: weekendPlan)
    }

    static func selectRun(
        network: RailwayTimetable.TimetableNetwork,
        category: ServiceCategory,
        direction: RegionalTravelDirection,
        calendar: RailwayTimetable.ServiceCalendar,
        daypart: RailwayTimetable.Daypart,
        initialDelayMinutes: Int,
        routeOriginStationID: String
    ) throws -> RegionalTimetableSelection {
        let packageDirection: RailwayTimetable.ServiceDirection = direction == .up ? .down : .up
        let packageCategory = RailwayTimetable.ServiceCategory(rawValue: category.rawValue)!
        guard initialDelayMinutes >= 0,
              let plannedTrip = network.trips
                .filter({
                    $0.category == packageCategory &&
                    $0.direction == packageDirection &&
                    $0.calendar == calendar &&
                    $0.daypart == daypart
                })
                .min(by: { $0.departureSeconds < $1.departureSeconds }) else {
            throw RailwayTimetable.TimetableError.invalidTimetable("選択した曜日・時間帯・種別・方向の列車がありません。")
        }

        let simulation = try RailwayTimetable.DisruptionSimulator.simulate(
            network: network,
            scenario: RailwayTimetable.DelayScenario(
                calendar: calendar,
                direction: packageDirection,
                initialTripID: plannedTrip.tripID,
                initialDelayMinutes: initialDelayMinutes
            )
        )
        guard let simulatedTrip = simulation.affectedTrips.first(where: { $0.tripID == plannedTrip.tripID }),
              !simulatedTrip.isCancelled,
              let plannedOrigin = plannedTrip.stationEvents.first(where: { $0.stationID == routeOriginStationID }),
              let simulatedOrigin = simulatedTrip.stationEvents.first(where: { $0.stationID == routeOriginStationID }) else {
            throw RailwayTimetable.TimetableError.invalidTimetable("選択した列車に現在の架空ルート始発駅がありません。")
        }
        let originDelay = max(0, simulatedOrigin.departureSeconds - plannedOrigin.departureSeconds)
        return RegionalTimetableSelection(
            plannedTrip: plannedTrip,
            simulatedTrip: simulatedTrip,
            note: simulation.note,
            routeOriginStationID: routeOriginStationID,
            routeOriginDelaySeconds: originDelay
        )
    }

    static func stopSchedules(
        from selection: RegionalTimetableSelection,
        activeStops: [RegionalRouteStop]
    ) -> [String: StopScoring.StopSchedule] {
        guard activeStops.count > 1,
              let plannedOrigin = selection.plannedTrip.stationEvents.first(where: {
                  $0.stationID == selection.routeOriginStationID
              }) else { return [:] }
        let actualEventsByID = Dictionary(
            selection.simulatedTrip.stationEvents.map { ($0.stationID, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        var schedules: [String: StopScoring.StopSchedule] = [:]
        for stop in activeStops.dropFirst() {
            guard let plannedEvent = selection.plannedTrip.stationEvents.first(where: {
                      $0.stationID == stop.stationID && $0.kind == .stop
                  }),
                  let actualEvent = actualEventsByID[stop.stationID],
                  actualEvent.kind == .stop else { continue }
            let arrival = Double(actualEvent.arrivalSeconds - plannedOrigin.departureSeconds)
            let departure = Double(actualEvent.departureSeconds - plannedOrigin.departureSeconds)
            guard arrival >= 0, departure >= arrival,
                  let schedule = try? StopScoring.StopSchedule(
                      scheduledArrivalSeconds: arrival,
                      scheduledDepartureSeconds: departure
                  ) else { continue }
            schedules[stop.stationID] = schedule
        }
        return schedules
    }
}
