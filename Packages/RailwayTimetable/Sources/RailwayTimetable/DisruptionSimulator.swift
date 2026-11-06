import Foundation

public enum DispatchAction: Hashable, Sendable {
    /// Delay a selected trip's departure in the game model.
    case hold(tripID: String, minutes: Int)
    /// Convert a non-terminal stop to a pass-through and permit configured recovery.
    case skipStop(tripID: String, stationID: String)
    /// Cancel a selected trip for this simulation run.
    case cancel(tripID: String)
}

public struct DelayScenario: Sendable {
    public let calendar: ServiceCalendar
    public let direction: ServiceDirection
    public let initialTripID: String
    public let initialDelayMinutes: Int
    public let actions: [DispatchAction]

    public init(
        calendar: ServiceCalendar,
        direction: ServiceDirection,
        initialTripID: String,
        initialDelayMinutes: Int,
        actions: [DispatchAction] = []
    ) {
        self.calendar = calendar
        self.direction = direction
        self.initialTripID = initialTripID
        self.initialDelayMinutes = initialDelayMinutes
        self.actions = actions
    }
}

public struct SimulatedStationEvent: Codable, Hashable, Sendable {
    public let stationID: String
    public let stationName: String
    public let kind: StopEventKind
    public let arrivalSeconds: Int
    public let departureSeconds: Int
    public let dwellSeconds: Int
    public let arrivalDelaySeconds: Int
}

public struct SimulatedTrip: Codable, Hashable, Sendable, Identifiable {
    public var id: String { tripID }

    public let tripID: String
    public let category: ServiceCategory
    public let calendar: ServiceCalendar
    public let direction: ServiceDirection
    public let isCancelled: Bool
    public let departureDelaySeconds: Int
    public let arrivalDelaySeconds: Int
    public let actualDepartureSeconds: Int?
    public let actualArrivalSeconds: Int?
    public let stationEvents: [SimulatedStationEvent]
}

public struct DisruptionSimulationResult: Codable, Sendable {
    public let affectedTrips: [SimulatedTrip]
    public let note: String
    public let dataStatus: TimetableDataStatus
}

/// A deliberately simple game model; it is not a signalling, block-occupancy or safety model.
public enum DisruptionSimulator {
    public static func simulate(
        network: TimetableNetwork,
        scenario: DelayScenario
    ) throws -> DisruptionSimulationResult {
        guard scenario.initialDelayMinutes >= 0 else {
            throw TimetableError.invalidDisruption("initial delay cannot be negative")
        }
        let eligibleTrips = network.trips.filter {
            $0.calendar == scenario.calendar && $0.direction == scenario.direction
        }
        let tripByID = Dictionary(uniqueKeysWithValues: eligibleTrips.map { ($0.tripID, $0) })
        guard tripByID[scenario.initialTripID] != nil else {
            throw TimetableError.invalidDisruption("initial trip is not in the selected calendar/direction")
        }

        var heldMinutes: [String: Int] = [:]
        var skippedStops: [String: Set<String>] = [:]
        var cancelledTripIDs = Set<String>()
        for action in scenario.actions {
            switch action {
            case .hold(let tripID, let minutes):
                guard tripByID[tripID] != nil, minutes >= 0 else {
                    throw TimetableError.invalidDisruption("hold action references a missing trip or negative duration")
                }
                heldMinutes[tripID, default: 0] += minutes
            case .skipStop(let tripID, let stationID):
                guard let trip = tripByID[tripID],
                      let index = trip.stationEvents.firstIndex(where: { $0.stationID == stationID }),
                      index > 0, index < trip.stationEvents.count - 1,
                      trip.stationEvents[index].kind == .stop else {
                    throw TimetableError.invalidDisruption("skip-stop action must target an intermediate scheduled stop")
                }
                skippedStops[tripID, default: []].insert(stationID)
            case .cancel(let tripID):
                guard tripByID[tripID] != nil else {
                    throw TimetableError.invalidDisruption("cancel action references a missing trip")
                }
                cancelledTripIDs.insert(tripID)
            }
        }

        let sortedTrips = eligibleTrips.sorted {
            if $0.departureSeconds != $1.departureSeconds { return $0.departureSeconds < $1.departureSeconds }
            return $0.tripID < $1.tripID
        }
        var simulated: [SimulatedTrip] = []
        var previousActualDeparture: Int?
        let minimumHeadway = network.operationsModel.virtualMinimumSameDirectionHeadwaySeconds
        for trip in sortedTrips {
            if cancelledTripIDs.contains(trip.tripID) {
                simulated.append(SimulatedTrip(
                    tripID: trip.tripID,
                    category: trip.category,
                    calendar: trip.calendar,
                    direction: trip.direction,
                    isCancelled: true,
                    departureDelaySeconds: 0,
                    arrivalDelaySeconds: 0,
                    actualDepartureSeconds: nil,
                    actualArrivalSeconds: nil,
                    stationEvents: []
                ))
                continue
            }
            let requestedDelay = (trip.tripID == scenario.initialTripID ? scenario.initialDelayMinutes * 60 : 0)
                + (heldMinutes[trip.tripID, default: 0] * 60)
            let headwayDelay = previousActualDeparture.map {
                max(0, $0 + minimumHeadway - trip.departureSeconds)
            } ?? 0
            let startDelay = max(requestedDelay, headwayDelay)
            let actualDeparture = trip.departureSeconds + startDelay
            var carriedDelay = startDelay
            var actualEvents: [SimulatedStationEvent] = []
            for event in trip.stationEvents {
                let arrival = event.arrivalSeconds + carriedDelay
                let skipped = skippedStops[trip.tripID, default: []].contains(event.stationID)
                let effectiveKind: StopEventKind = skipped ? .passThrough : event.kind
                let recovery: Int
                let actualDwell: Int
                if skipped {
                    actualDwell = 0
                    recovery = min(carriedDelay, network.operationsModel.recoverySecondsWhenSkippingStop)
                } else if event.kind == .stop, event.dwellSeconds > 0 {
                    recovery = min(carriedDelay, min(network.operationsModel.recoverySecondsAtDwell, event.dwellSeconds))
                    actualDwell = event.dwellSeconds - recovery
                } else {
                    recovery = 0
                    actualDwell = 0
                }
                let departure = arrival + actualDwell
                actualEvents.append(SimulatedStationEvent(
                    stationID: event.stationID,
                    stationName: event.stationName,
                    kind: effectiveKind,
                    arrivalSeconds: arrival,
                    departureSeconds: departure,
                    dwellSeconds: actualDwell,
                    arrivalDelaySeconds: carriedDelay
                ))
                carriedDelay = max(0, carriedDelay - recovery)
            }
            let actualArrival = trip.arrivalSeconds + carriedDelay
            simulated.append(SimulatedTrip(
                tripID: trip.tripID,
                category: trip.category,
                calendar: trip.calendar,
                direction: trip.direction,
                isCancelled: false,
                departureDelaySeconds: startDelay,
                arrivalDelaySeconds: carriedDelay,
                actualDepartureSeconds: actualDeparture,
                actualArrivalSeconds: actualArrival,
                stationEvents: actualEvents
            ))
            previousActualDeparture = actualDeparture
        }
        return DisruptionSimulationResult(
            affectedTrips: simulated,
            note: "PLACEHOLDERの簡易ゲームモデルです。同方向列車の始発時刻差と停車時分による遅延吸収のみ扱い、駅間の列車位置・閉そく・信号・対向列車・待避設備・現実の安全や運転整理を扱いません。",
            dataStatus: .placeholder
        )
    }
}
