import Foundation
import ProtectionSystems
import RailwayRouteData
import RailwaySignalling
import TrafficSimulation

/// App-level adapter for the one canonical 70 km fictional topology.
/// All network values remain PLACEHOLDER and are not operational railway data.
struct RegionalNetworkIntegrationReport {
    let plan: FictionalOperationsPlan?
    let trafficScenario: TrafficSimulation.TrafficScenario?
    let trafficValidationIssues: [TrafficDataIssue]
    let sourceRoutePackage: RailwayRouteData.RoutePackage?
    let sourceRouteValidation: RailwayRouteData.ValidationReport?
    let sourceRoutePosition: RailwayRouteData.RoutePosition?
    let canonicalSignallingNetwork: RailwaySignalling.FictionalRailwayNetwork?
    let canonicalTimetable: RailwaySignalling.RailwayServiceTimetable?
    let canonicalMainlineTopology: RailwaySignalling.RailwayTopology?
    let sampleSignal: RailwaySignalling.SignalReading?
    let protectionSystemsDemoResult: ProtectionSystems.SimulationResult?
    let issues: [String]

    var canonicalTrackLengthKm: Double? {
        canonicalSignallingNetwork.map { $0.totalTrackLengthM / 1_000 }
    }

    var canonicalServiceCount: Int { canonicalTimetable?.services.count ?? 0 }
}

enum RegionalNetworkIntegration {
    static func load() -> RegionalNetworkIntegrationReport {
        var issues: [String] = []
        let plan = FictionalOperationsPlan.loadBundled()
        if plan == nil {
            issues.append("Canonical operations JSON failed validation or could not be loaded.")
        }
        let protectionSystemsDemoResult = try? makeProtectionSystemsDemo()
        if protectionSystemsDemoResult == nil {
            issues.append("The separate fictional protection-systems demo could not be run.")
        }

        let trafficScenario = try? TrafficScenarioLibrary.loadBundledRegionalNetwork()
        let trafficValidationIssues = trafficScenario?.validate() ?? []
        if trafficScenario == nil {
            issues.append("Regional traffic scenario resource could not be loaded.")
        } else if !trafficValidationIssues.isEmpty {
            issues.append("Regional traffic scenario has \(trafficValidationIssues.count) validation issue(s).")
        }

        let sourceRoutePackage = try? RailwayRouteData.RoutePackageLoader.loadResource(named: "fictional_70km_network")
        let sourceRouteValidation = sourceRoutePackage.map { RailwayRouteData.RouteValidator.validate($0) }
        let sourceRoutePosition = sourceRoutePackage.flatMap { package in
            RailwayRouteData.RouteQuery.position(
                at: 0,
                trackID: package.route.mainTrackID,
                in: package
            )
        }
        if sourceRoutePackage == nil {
            issues.append("Synthetic route-data source package could not be loaded.")
        }

        var canonicalNetwork: RailwaySignalling.FictionalRailwayNetwork?
        var canonicalTimetable: RailwaySignalling.RailwayServiceTimetable?
        var topology: RailwaySignalling.RailwayTopology?
        var sampleSignal: RailwaySignalling.SignalReading?

        if let plan {
            if let sourceRoutePackage {
                let sourceRoute = sourceRoutePackage.route
                if abs((sourceRoute.totalLengthM.value ?? -1) / 1_000 - plan.network.mainlineLengthKm) > 0.001
                    || abs((sourceRoute.networkLengthM.value ?? -1) / 1_000 - plan.network.totalRouteLengthKm) > 0.001 {
                    issues.append("RouteData and the canonical operations plan disagree on 60+8+2 km network lengths.")
                }
                if sourceRoute.stations.count != plan.stations.count {
                    issues.append("RouteData and the canonical operations plan disagree on the station inventory.")
                }
                let requiredTrackIDs: Set<String> = ["main_line", "branch_line", "depot_spur"]
                if !requiredTrackIDs.isSubset(of: Set(sourceRoute.tracks.map(\.trackID))) {
                    issues.append("RouteData is missing a track from the canonical main/branch/depot topology.")
                }
            }
            do {
                let network = try makeCanonicalSignallingNetwork(from: plan)
                canonicalNetwork = network
                canonicalTimetable = try makeCanonicalTimetable(from: plan, network: network)
                let lineTopology = try makeCanonicalMainlineTopology(lengthKm: plan.network.mainlineLengthKm)
                topology = lineTopology
                sampleSignal = try makeSampleSignal(topology: lineTopology)
                if abs(network.totalTrackLengthM - plan.network.totalRouteLengthKm * 1_000) > 1 {
                    issues.append("Signalling adapter total differs from the canonical operations plan.")
                }
                if let trafficScenario,
                   abs(trafficScenario.totalNetworkLengthM - network.totalTrackLengthM) > 1 {
                    issues.append("Traffic and signalling adapters do not agree on total physical track length.")
                }
            } catch {
                issues.append("Canonical signalling adapter failed: \(error)")
            }
        }

        return RegionalNetworkIntegrationReport(
            plan: plan,
            trafficScenario: trafficScenario,
            trafficValidationIssues: trafficValidationIssues,
            sourceRoutePackage: sourceRoutePackage,
            sourceRouteValidation: sourceRouteValidation,
            sourceRoutePosition: sourceRoutePosition,
            canonicalSignallingNetwork: canonicalNetwork,
            canonicalTimetable: canonicalTimetable,
            canonicalMainlineTopology: topology,
            sampleSignal: sampleSignal,
            protectionSystemsDemoResult: protectionSystemsDemoResult,
            issues: issues
        )
    }

    private static func makeCanonicalSignallingNetwork(
        from plan: FictionalOperationsPlan
    ) throws -> RailwaySignalling.FictionalRailwayNetwork {
        let mainStations = plan.stations
            .filter { $0.lineId == plan.network.mainlineID }
            .sorted { $0.chainageKm < $1.chainageKm }
        let branchStations = plan.stations
            .filter { $0.lineId == plan.network.branchID }
            .sorted { $0.chainageKm < $1.chainageKm }
        guard mainStations.count >= 2,
              branchStations.count >= 1,
              mainStations.first?.chainageKm == 0,
              abs((mainStations.last?.chainageKm ?? 0) - plan.network.mainlineLengthKm) < 0.001,
              abs((branchStations.last?.chainageKm ?? 0) - plan.network.branchLengthKm) < 0.001,
              let junction = mainStations.first(where: { $0.stationId == plan.network.branchJunctionStationID }) else {
            throw RailwaySignalling.RailwaySignallingError.invalidValue("canonical station chainage")
        }

        let passingLoopIDs: Set<String> = ["S05", "S10", "S15", "S20", "S25", "B02"]
        var stations = try plan.stations.map { station in
            let hasLoop = passingLoopIDs.contains(station.stationId)
            return try RailwaySignalling.FictionalRailwayStation(
                id: station.stationId,
                name: station.name,
                hasPassingLoop: hasLoop,
                passingLoopLengthM: hasLoop ? 500 : nil
            )
        }
        let depotStationID = "DEPOT_END"
        stations.append(try RailwaySignalling.FictionalRailwayStation(
            id: depotStationID,
            name: "東央車両基地（架空）"
        ))

        var segments: [RailwaySignalling.FictionalRailwaySegment] = []
        var mainSegmentIDs: [String] = []
        for index in 0..<(mainStations.count - 1) {
            let from = mainStations[index]
            let to = mainStations[index + 1]
            let lengthM = (to.chainageKm - from.chainageKm) * 1_000
            let segmentID = "M_\(from.stationId)_\(to.stationId)"
            guard lengthM.isFinite, lengthM > 0 else {
                throw RailwaySignalling.RailwaySignallingError.invalidValue("mainline segment length")
            }
            segments.append(try RailwaySignalling.FictionalRailwaySegment(
                id: segmentID,
                fromStationID: from.stationId,
                toStationID: to.stationId,
                lengthM: lengthM,
                trackStartChainageM: from.chainageKm * 1_000,
                upTrackID: "MAIN_UP",
                downTrackID: "MAIN_DOWN"
            ))
            mainSegmentIDs.append(segmentID)
        }

        let branchPoints: [(id: String, chainageKm: Double)] =
            [(junction.stationId, 0)] + branchStations.map { ($0.stationId, $0.chainageKm) }
        var branchSegmentIDs: [String] = []
        for index in 0..<(branchPoints.count - 1) {
            let from = branchPoints[index]
            let to = branchPoints[index + 1]
            let lengthM = (to.chainageKm - from.chainageKm) * 1_000
            let segmentID = "B_\(from.id)_\(to.id)"
            guard lengthM.isFinite, lengthM > 0 else {
                throw RailwaySignalling.RailwaySignallingError.invalidValue("branch segment length")
            }
            segments.append(try RailwaySignalling.FictionalRailwaySegment(
                id: segmentID,
                fromStationID: from.id,
                toStationID: to.id,
                lengthM: lengthM,
                trackStartChainageM: from.chainageKm * 1_000,
                upTrackID: "BRANCH_UP",
                downTrackID: "BRANCH_DOWN",
                branchID: "BRANCH"
            ))
            branchSegmentIDs.append(segmentID)
        }

        let depot = try RailwaySignalling.FictionalRailwaySegment(
            id: "D_\(plan.network.depotStationID)_\(depotStationID)",
            fromStationID: plan.network.depotStationID,
            toStationID: depotStationID,
            lengthM: plan.network.depotSpurLengthKm * 1_000,
            trackStartChainageM: 0,
            upTrackID: "DEPOT_SPUR",
            downTrackID: "DEPOT_SPUR",
            branchID: plan.network.depotSpurID
        )
        segments.append(depot)

        let mainUp = try RailwaySignalling.FictionalServiceRoute(
            id: "main-up", originStationID: mainStations[0].stationId,
            destinationStationID: mainStations[mainStations.count - 1].stationId,
            direction: .up, segmentIDs: mainSegmentIDs
        )
        let mainDown = try RailwaySignalling.FictionalServiceRoute(
            id: "main-down", originStationID: mainStations[mainStations.count - 1].stationId,
            destinationStationID: mainStations[0].stationId,
            direction: .down, segmentIDs: Array(mainSegmentIDs.reversed())
        )
        let branchUp = try RailwaySignalling.FictionalServiceRoute(
            id: "branch-up", originStationID: mainStations[0].stationId,
            destinationStationID: branchStations[branchStations.count - 1].stationId,
            direction: .up, segmentIDs: mainSegmentIDs + branchSegmentIDs
        )
        let branchDown = try RailwaySignalling.FictionalServiceRoute(
            id: "branch-down", originStationID: branchStations[branchStations.count - 1].stationId,
            destinationStationID: mainStations[0].stationId,
            direction: .down, segmentIDs: Array(branchSegmentIDs.reversed()) + Array(mainSegmentIDs.reversed())
        )
        return try RailwaySignalling.FictionalRailwayNetwork(
            networkID: plan.network.canonicalTopologyID,
            stations: stations,
            segments: segments,
            routes: [mainUp, mainDown, branchUp, branchDown]
        )
    }

    private static func makeCanonicalTimetable(
        from plan: FictionalOperationsPlan,
        network: RailwaySignalling.FictionalRailwayNetwork
    ) throws -> RailwaySignalling.RailwayServiceTimetable {
        let directionByCategory: [ServiceCategory: RailwaySignalling.ServiceDirection] = [
            .local: .down,
            .rapid: .up,
            .semiExpress: .down,
            .express: .up,
            .rapidExpress: .down,
            .limitedExpress: .up
        ]
        var trips: [RailwaySignalling.RailwayServiceTrip] = []
        for service in plan.services {
            guard let type = RailwaySignalling.RailwayServiceType(rawValue: service.category.rawValue),
                  let direction = directionByCategory[service.category],
                  let pattern = plan.timetablePatterns.first(where: {
                      $0.category == service.category && $0.direction.rawValue == direction.rawValue && $0.daypart == .morningRush
                  }),
                  let departureMinutes = FictionalOperationsPlan.minutesSinceMidnight(pattern.firstDeparture) else {
                throw RailwaySignalling.RailwaySignallingError.invalidValue("missing representative timetable pattern")
            }
            let categoryOffsetSeconds = (ServiceCategory.allCases.firstIndex(of: service.category) ?? 0) * 5 * 60
            let departureSeconds = departureMinutes * 60 + categoryOffsetSeconds
            let durationSeconds = service.plannedDurationMinutes * 60
            let stationIDs = direction == .up ? service.stopStationIDs : Array(service.stopStationIDs.reversed())
            let routeID = direction == .up ? "branch-up" : "branch-down"
            let trainID = "EMU-\(service.category.rawValue)-\(direction.rawValue)"
            trips.append(try RailwaySignalling.RailwayServiceTrip(
                id: "regional-\(service.category.rawValue)-\(direction.rawValue)-am",
                trainID: trainID,
                serviceType: type,
                direction: direction,
                routeID: routeID,
                period: .morningRush,
                scheduledDepartureSeconds: departureSeconds,
                scheduledArrivalSeconds: departureSeconds + durationSeconds,
                consistLengthM: 120,
                stops: makeScheduledStops(stationIDs: stationIDs, durationSeconds: durationSeconds)
            ))
        }

        let depot = try RailwaySignalling.FictionalDepot(
            id: "DEPOT-NORTH",
            stationID: plan.network.depotStationID,
            leadTrackID: plan.network.depotSpurID
        )
        guard let expressUp = trips.first(where: { $0.serviceType == .express && $0.direction == .up }),
              let localDown = trips.first(where: { $0.serviceType == .local && $0.direction == .down }) else {
            throw RailwaySignalling.RailwaySignallingError.invalidValue("representative depot services")
        }
        let exitStart = max(0, expressUp.scheduledDepartureSeconds - 600)
        let entryStart = localDown.scheduledArrivalSeconds + 300
        let movements = try [
            RailwaySignalling.DepotMovement(
                id: "regional-express-depot-exit", trainID: expressUp.trainID, depotID: depot.id,
                kind: .exitDepot, scheduledStartSeconds: exitStart, durationSeconds: 300
            ),
            RailwaySignalling.DepotMovement(
                id: "regional-local-depot-entry", trainID: localDown.trainID, depotID: depot.id,
                kind: .enterDepot, scheduledStartSeconds: entryStart, durationSeconds: 300
            )
        ]
        return try RailwaySignalling.RailwayServiceTimetable(
            network: network, services: trips, depots: [depot], depotMovements: movements,
            timeZoneIdentifier: "Asia/Tokyo"
        )
    }

    private static func makeScheduledStops(
        stationIDs: [String],
        durationSeconds: Int
    ) -> [RailwaySignalling.ScheduledServiceStop] {
        guard stationIDs.count >= 2 else { return [] }
        var result: [RailwaySignalling.ScheduledServiceStop] = []
        var previousDeparture = 0
        for index in stationIDs.indices {
            if index == stationIDs.startIndex {
                result.append(.init(stationID: stationIDs[index], arrivalOffsetSeconds: 0, departureOffsetSeconds: 0))
                continue
            }
            if index == stationIDs.index(before: stationIDs.endIndex) {
                result.append(.init(stationID: stationIDs[index], arrivalOffsetSeconds: durationSeconds, departureOffsetSeconds: durationSeconds))
                continue
            }
            let fraction = Double(index) / Double(stationIDs.count - 1)
            let nextFraction = Double(index + 1) / Double(stationIDs.count - 1)
            let targetArrival = Int((Double(durationSeconds) * fraction).rounded(.down))
            let nextArrival = Int((Double(durationSeconds) * nextFraction).rounded(.down))
            let arrival = max(previousDeparture, targetArrival)
            let departure = min(arrival + 30, max(arrival, nextArrival - 1))
            result.append(.init(stationID: stationIDs[index], arrivalOffsetSeconds: arrival, departureOffsetSeconds: departure))
            previousDeparture = departure
        }
        return result
    }

    private static func makeCanonicalMainlineTopology(
        lengthKm: Double
    ) throws -> RailwaySignalling.RailwayTopology {
        let lengthM = lengthKm * 1_000
        var blocks: [RailwaySignalling.TrackBlock] = []
        var start = 0.0
        var index = 0
        while start < lengthM - 1e-9 {
            let end = min(start + 500, lengthM)
            blocks.append(try RailwaySignalling.TrackBlock(id: "REGIONAL-B\(index)", startM: start, endM: end))
            start = end
            index += 1
        }
        return try RailwaySignalling.RailwayTopology(
            lineID: "REGIONAL_MAINLINE_PLACEHOLDER",
            lengthM: lengthM,
            defaultSpeedLimitKmh: 80,
            blocks: blocks
        )
    }

    private static func makeSampleSignal(
        topology: RailwaySignalling.RailwayTopology
    ) throws -> RailwaySignalling.SignalReading {
        guard topology.blocks.count > 1 else {
            throw RailwaySignalling.RailwaySignallingError.emptyCollection("sample signal blocks")
        }
        let train = try RailwaySignalling.TrainPositionSnapshot(
            id: "PLACEHOLDER-AI", lineID: topology.lineID,
            frontPositionM: topology.blocks[1].startM + 250,
            speedMps: 8, trainLengthM: 120
        )
        let snapshot = try RailwaySignalling.RailwaySignallingSnapshot(
            simulationTimeSeconds: 0, fixedTick: 0, fixedTimeStepSeconds: 1.0 / 120.0,
            trains: [train]
        )
        return try RailwaySignalling.RailwayInterlocking(topology: topology)
            .signal(for: topology.blocks[0].id, in: snapshot)
    }

    /// Separate, fictional sample only; it is not connected to the live train physics or real safety logic.
    private static func makeProtectionSystemsDemo() throws -> ProtectionSystems.SimulationResult {
        let trackID = "fictional-demo-main"
        let blocks = try [
            ProtectionSystems.BlockSection(id: "demo-b0", trackID: trackID, startM: 0, endM: 500),
            ProtectionSystems.BlockSection(id: "demo-b1", trackID: trackID, startM: 500, endM: 1_000),
            ProtectionSystems.BlockSection(id: "demo-b2", trackID: trackID, startM: 1_000, endM: 1_500)
        ]
        let track = try ProtectionSystems.RailwayTrack(id: trackID, lengthM: 1_500, blocks: blocks)
        let route = try ProtectionSystems.RouteDefinition(
            id: "demo-through", trackID: trackID, protectedBlockIDs: ["demo-b0"]
        )
        let equipment = try [
            ProtectionSystems.RouteEquipment(id: "demo-ats-s", trackID: trackID, kind: .atsSBeacon, positionM: 300),
            ProtectionSystems.RouteEquipment(
                id: "demo-ats-p", trackID: trackID, kind: .atsPProfileTarget,
                positionM: 800, targetPositionM: 1_200, targetSpeedKmh: 0
            ),
            ProtectionSystems.RouteEquipment(
                id: "demo-ats-ps", trackID: trackID, kind: .atsPsSpeedBeacon,
                positionM: 500, targetSpeedKmh: 45, supervisionDistanceM: 200
            ),
            ProtectionSystems.RouteEquipment(
                id: "demo-atc", trackID: trackID, kind: .atcCommandZone,
                positionM: 300, targetSpeedKmh: 25, zoneStartM: 250, zoneEndM: 350
            ),
            ProtectionSystems.RouteEquipment(
                id: "demo-ato", trackID: trackID, kind: .atoTarget,
                positionM: 900, targetPositionM: 1_400, targetSpeedKmh: 0
            )
        ]
        let signal = try ProtectionSystems.SignalDefinition(
            id: "demo-signal", trackID: trackID, positionM: 0,
            protectedBlockID: "demo-b0", governingRouteID: route.id
        )
        let network = try ProtectionSystems.RailwayNetwork(
            id: "fictional-protection-demo", tracks: [track], equipment: equipment,
            routes: [route], signals: [signal]
        )
        let systems: Set<ProtectionSystems.ProtectionSystemKind> = [
            .atsS, .atsP, .atsPs, .atc, .ato, .eb, .deadman
        ]
        var engine = ProtectionSystems.ProtectionSystemEngine(
            network: network, systemsByTrain: ["PLAYER": systems]
        )
        func frame(tick: UInt64, time: Double, playerPositionM: Double) throws -> ProtectionSystems.SimulationFrame {
            let player = try ProtectionSystems.TrainState(
                id: "PLAYER", trackID: trackID, frontPositionM: playerPositionM,
                speedKmh: 40, lengthM: 80
            )
            let otherTrain = try ProtectionSystems.TrainState(
                id: "FICTIONAL-AI", trackID: trackID, frontPositionM: 900,
                speedKmh: 0, lengthM: 80
            )
            return try ProtectionSystems.SimulationFrame(
                fixedTick: tick, timeSeconds: time, trains: [player, otherTrain],
                routeRequests: ["PLAYER": route.id],
                operatorInputs: ["PLAYER": ProtectionSystems.OperatorInput(driverActivityPulse: true)]
            )
        }
        _ = try engine.step(frame(tick: 0, time: 0, playerPositionM: 290))
        return try engine.step(frame(tick: 1, time: 1.0 / 60.0, playerPositionM: 310))
    }
}
