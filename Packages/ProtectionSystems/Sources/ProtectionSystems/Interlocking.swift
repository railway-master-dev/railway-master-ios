import Foundation

public struct InterlockingEvaluation: Equatable, Sendable {
    public let blockOccupancy: [BlockOccupancy]
    public let routeGrants: [RouteGrant]
    public let signals: [SignalState]
    let occupiedTrainIDsByBlock: [String: Set<String>]
}

/// Deterministic fictional interlocking model. It is not a railway interlocking implementation.
public struct InterlockingEvaluator: Sendable {
    public let network: RailwayNetwork

    public init(network: RailwayNetwork) {
        self.network = network
    }

    public func evaluate(_ frame: SimulationFrame) throws -> InterlockingEvaluation {
        try validate(frame)
        let trainsByID = Dictionary(uniqueKeysWithValues: frame.trains.map { ($0.id, $0) })
        var occupants: [String: Set<String>] = [:]
        for track in network.tracks {
            for block in track.blocks {
                for train in frame.trains where train.trackID == track.id {
                    let range = train.occupiedRangeM
                    if range.lowerBound < block.endM && range.upperBound > block.startM {
                        occupants[block.id, default: []].insert(train.id)
                    }
                }
            }
        }

        var grants: [RouteGrant] = []
        var grantedRoutes: [(trainID: String, route: RouteDefinition)] = []
        for (trainID, routeID) in frame.routeRequests.sorted(by: { $0.key < $1.key }) {
            guard let train = trainsByID[trainID], let route = network.route(routeID) else {
                throw ProtectionPackageError.unknownIdentifier("route request \(trainID):\(routeID)")
            }
            var denial: String?
            if train.trackID != route.trackID {
                denial = "Requested route is not on the train's current track (fictional simulation rule)."
            }
            if denial == nil {
                for (switchID, requiredPosition) in route.requiredSwitchPositions.sorted(by: { $0.key < $1.key }) {
                    if frame.switchPositions[switchID] != requiredPosition {
                        denial = "Required switch \(switchID) is not at \(requiredPosition)."
                        break
                    }
                }
            }
            if denial == nil {
                for blockID in route.protectedBlockIDs {
                    let otherOccupants = (occupants[blockID] ?? []).subtracting([trainID])
                    if !otherOccupants.isEmpty {
                        denial = "Protected block \(blockID) is occupied by another train."
                        break
                    }
                }
            }
            if denial == nil {
                for prior in grantedRoutes {
                    let sharesBlocks = !Set(route.protectedBlockIDs).isDisjoint(with: prior.route.protectedBlockIDs)
                    let sharesSwitch = route.requiredSwitchPositions.contains { entry in
                        prior.route.requiredSwitchPositions[entry.key] != nil && prior.route.requiredSwitchPositions[entry.key] != entry.value
                    }
                    let declaredConflict = route.conflictsWithRouteIDs.contains(prior.route.id) || prior.route.conflictsWithRouteIDs.contains(route.id)
                    if sharesBlocks || sharesSwitch || declaredConflict {
                        denial = "Route conflicts with already granted route \(prior.route.id)."
                        break
                    }
                }
            }
            let granted = denial == nil
            grants.append(RouteGrant(trainID: trainID, routeID: routeID, granted: granted, denialReason: denial))
            if granted { grantedRoutes.append((trainID, route)) }
        }

        let occupancy = network.tracks.flatMap(\.blocks).map { block in
            BlockOccupancy(id: block.id, trainIDs: (occupants[block.id] ?? []).sorted())
        }
        let grantByRoute = Dictionary(grouping: grants, by: \.routeID)
        let signalStates = network.signals.map { signal -> SignalState in
            let protectedOccupied = !(occupants[signal.protectedBlockID] ?? []).isEmpty
            if protectedOccupied {
                return SignalState(id: signal.id, aspect: .stop, reason: "Protected block is occupied.")
            }
            if let routeID = signal.governingRouteID {
            let isGranted = grantByRoute[routeID]?.contains(where: { $0.granted }) == true
                if !isGranted {
                    return SignalState(id: signal.id, aspect: .stop, reason: "Governing route is not granted.")
                }
            }
            guard let track = network.track(signal.trackID),
                  let index = track.blocks.firstIndex(where: { $0.id == signal.protectedBlockID }) else {
                return SignalState(id: signal.id, aspect: .stop, reason: "Signal has no valid protected block.")
            }
            if index + 1 < track.blocks.count,
               !(occupants[track.blocks[index + 1].id] ?? []).isEmpty {
                return SignalState(id: signal.id, aspect: .caution, reason: "The next block is occupied.")
            }
            return SignalState(id: signal.id, aspect: .proceed, reason: "Protected and following blocks are clear.")
        }.sorted { $0.id < $1.id }

        return InterlockingEvaluation(
            blockOccupancy: occupancy,
            routeGrants: grants.sorted { $0.id < $1.id },
            signals: signalStates,
            occupiedTrainIDsByBlock: occupants
        )
    }

    private func validate(_ frame: SimulationFrame) throws {
        let trainIDs = Set(frame.trains.map(\.id))
        let switchIDs = Set(network.switches.map(\.id))
        let routeIDs = Set(network.routes.map(\.id))
        guard frame.switchPositions.keys.allSatisfy(switchIDs.contains),
              frame.routeRequests.values.allSatisfy(routeIDs.contains) else {
            throw ProtectionPackageError.unknownIdentifier("switch or route in frame")
        }
        for train in frame.trains {
            guard let track = network.track(train.trackID), train.frontPositionM <= track.lengthM else {
                throw ProtectionPackageError.inconsistentReference("train \(train.id) outside known track")
            }
        }
        guard frame.routeRequests.keys.allSatisfy(trainIDs.contains) else {
            throw ProtectionPackageError.inconsistentReference("route request for missing train")
        }
    }
}

/// CTC-style read-only supervisory summary: it observes, but does not authorize a route.
public struct CTCController: Sendable {
    public init() {}

    public func summaries(frame: SimulationFrame, routeGrants: [RouteGrant]) -> [CTCTrainSummary] {
        let grantsByTrain = Dictionary(uniqueKeysWithValues: routeGrants.map { ($0.trainID, $0.granted) })
        let assignmentByTrain = Dictionary(grouping: frame.timetableAssignments, by: \.trainID)
        return frame.trains.sorted { $0.id < $1.id }.map { train in
            let assignment = assignmentByTrain[train.id]?.min { $0.plannedDepartureTimeSeconds < $1.plannedDepartureTimeSeconds }
            return CTCTrainSummary(
                id: train.id,
                trackID: train.trackID,
                frontPositionM: train.frontPositionM,
                speedKmh: train.speedKmh,
                requestedRouteID: frame.routeRequests[train.id],
                routeGranted: grantsByTrain[train.id],
                timetableDelaySeconds: assignment.map { frame.timeSeconds - $0.plannedDepartureTimeSeconds }
            )
        }
    }
}

/// PRC-style timetable adapter that proposes requests only; the interlocking remains the gatekeeper.
public struct PRCController: Sendable {
    public let dispatchLeadSeconds: Double

    public init(dispatchLeadSeconds: Double = 45) throws {
        guard dispatchLeadSeconds.isFinite, dispatchLeadSeconds >= 0 else {
            throw ProtectionPackageError.invalidValue("dispatch lead")
        }
        self.dispatchLeadSeconds = dispatchLeadSeconds
    }

    public func proposedRouteRequests(frame: SimulationFrame, network: RailwayNetwork) -> [String: String] {
        let trainIDs = Set(frame.trains.map(\.id))
        var proposals: [String: String] = [:]
        for assignment in frame.timetableAssignments.sorted(by: {
            $0.plannedDepartureTimeSeconds == $1.plannedDepartureTimeSeconds
                ? $0.id < $1.id
                : $0.plannedDepartureTimeSeconds < $1.plannedDepartureTimeSeconds
        }) {
            guard trainIDs.contains(assignment.trainID), network.route(assignment.nextRouteID) != nil,
                  frame.routeRequests[assignment.trainID] == nil,
                  frame.timeSeconds >= assignment.plannedDepartureTimeSeconds - dispatchLeadSeconds else { continue }
            proposals[assignment.trainID] = assignment.nextRouteID
        }
        return proposals
    }
}
