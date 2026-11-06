import Foundation

/// Imports canonical station identity and chainage from RailwayRouteData JSON, while taking
/// service patterns from FictionalOperationsPlan.json. No route or station is synthesized here.
public enum CanonicalNetworkAdapter {
    public static func importInputs(
        routePackageJSON: Data,
        operationsPlanJSON: Data,
        decoder: JSONDecoder = JSONDecoder()
    ) throws -> ImportedTimetableInputs {
        let routePackage = try decoder.decode(RoutePackageDTO.self, from: routePackageJSON)
        let operations = try decoder.decode(OperationsPlanDTO.self, from: operationsPlanJSON)
        let route = routePackage.route

        guard route.datasetKind == "FICTIONAL" else {
            throw TimetableError.unsupportedPlaceholderInput("route.datasetKind=\(route.datasetKind)")
        }
        guard route.networkLengthM.status == "PLACEHOLDER",
              route.totalLengthM.status == "PLACEHOLDER",
              operations.network.dataStatus == "PLACEHOLDER" else {
            throw TimetableError.unsupportedPlaceholderInput("network metadata must be PLACEHOLDER")
        }
        guard !routePackage.packageID.isEmpty,
              !route.routeID.isEmpty,
              let physicalLengthM = route.networkLengthM.value,
              let mainlineLengthM = route.totalLengthM.value else {
            throw TimetableError.inconsistentSources("missing canonical route IDs or route length values")
        }

        guard Set(route.tracks.map(\.trackID)).count == route.tracks.count,
              route.depots.count == 1,
              route.depots[0].chainageM.status == "PLACEHOLDER",
              route.depots[0].chainageM.value != nil else {
            throw TimetableError.inconsistentSources("canonical track IDs or depot PLACEHOLDER definition is invalid")
        }
        let tracksByID = Dictionary(uniqueKeysWithValues: route.tracks.map { ($0.trackID, $0) })
        guard let mainTrack = tracksByID[route.mainTrackID],
              let depotRecord = route.depots.first,
              let depotTrack = tracksByID[depotRecord.trackID] else {
            throw TimetableError.inconsistentSources("canonical main track or depot track is missing")
        }
        let canonicalMainlineExtentM = try mainTrack.extentM()
        guard canonicalMainlineExtentM == mainlineLengthM else {
            throw TimetableError.inconsistentSources("main track segment extent does not match route.totalLengthM")
        }
        let depotSpurLengthM = try depotTrack.extentM()
        let branchTracks = route.tracks.filter { $0.trackID != route.mainTrackID && $0.trackID != depotRecord.trackID }
        guard branchTracks.count == 1, let branchTrack = branchTracks.first else {
            throw TimetableError.inconsistentSources("expected one branch track apart from main and depot tracks")
        }
        let branchLengthM = try branchTrack.extentM()

        let opsNetwork = operations.network
        guard approximatelyEqual(physicalLengthM, opsNetwork.totalRouteLengthKm * 1_000),
              approximatelyEqual(mainlineLengthM, opsNetwork.mainlineLengthKm * 1_000),
              approximatelyEqual(branchLengthM, opsNetwork.branchLengthKm * 1_000),
              approximatelyEqual(depotSpurLengthM, opsNetwork.depotSpurLengthKm * 1_000) else {
            throw TimetableError.inconsistentSources("route segment extents and operations-plan 60+8+2 km summary differ")
        }

        var stationsByID: [String: TimetableStation] = [:]
        for source in route.stations {
            guard source.name.status == "PLACEHOLDER",
                  source.chainageM.status == "PLACEHOLDER",
                  let name = source.name.value,
                  let chainageM = source.chainageM.value,
                  !source.trackIDs.isEmpty else {
                throw TimetableError.unsupportedPlaceholderInput("station \(source.stationID) lacks PLACEHOLDER name/chainage")
            }
            guard source.trackIDs.allSatisfy({ tracksByID[$0] != nil }) else {
                throw TimetableError.inconsistentSources("station \(source.stationID) refers to an unknown canonical track")
            }
            guard stationsByID[source.stationID] == nil else {
                throw TimetableError.inconsistentSources("duplicate canonical station ID \(source.stationID)")
            }
            stationsByID[source.stationID] = TimetableStation(
                stationID: source.stationID,
                name: name,
                chainageM: chainageM,
                trackIDs: source.trackIDs,
                routeProgressM: 0,
                dataStatus: .placeholder
            )
        }
        guard !stationsByID.isEmpty else {
            throw TimetableError.inconsistentSources("canonical route has no stations")
        }

        // OperationsPlan is a schedule source, not a second station master. Its duplicate
        // station fields are only reconciliation checks; exported values always come from RouteData.
        var operationStations: [String: OperationsStationDTO] = [:]
        for source in operations.stations {
            guard operationStations[source.stationId] == nil else {
                throw TimetableError.inconsistentSources("duplicate operations-plan station ID \(source.stationId)")
            }
            operationStations[source.stationId] = source
        }
        guard Set(operationStations.keys) == Set(stationsByID.keys) else {
            throw TimetableError.inconsistentSources("route-data and operations-plan station ID sets differ")
        }
        for (stationID, source) in operationStations {
            guard source.dataStatus == "PLACEHOLDER" else {
                throw TimetableError.unsupportedPlaceholderInput("operations station \(stationID) is not PLACEHOLDER")
            }
            let canonical = stationsByID[stationID]!
            guard source.name == canonical.name,
                  approximatelyEqual(source.chainageKm * 1_000, canonical.chainageM, toleranceM: 0.1) else {
                throw TimetableError.inconsistentSources("station \(stationID) name or chainage differs; canonical RouteData value was not replaced")
            }
        }

        let services = try operations.services.map { source -> ServiceDefinition in
            guard source.dataStatus == "PLACEHOLDER" else {
                throw TimetableError.unsupportedPlaceholderInput("service \(source.category) is not PLACEHOLDER")
            }
            guard let category = ServiceCategory(rawValue: source.category),
                  source.plannedDurationMinutes >= 60,
                  source.plannedDurationMinutes <= 150,
                  source.routeDistanceKm > 0 else {
                throw TimetableError.inconsistentSources("unknown service class or runtime/distance outside the 60–150 minute policy")
            }
            return ServiceDefinition(
                category: category,
                routeDistanceKm: source.routeDistanceKm,
                plannedRuntimeMinutes: source.plannedDurationMinutes,
                stopStationIDs: source.stopStationIDs,
                dataStatus: .placeholder
            )
        }
        guard Set(services.map(\.category)) == Set(ServiceCategory.allCases),
              services.count == ServiceCategory.allCases.count else {
            throw TimetableError.inconsistentSources("operations plan must define exactly the six supported service categories")
        }
        guard let localService = services.first(where: { $0.category == .local }),
              localService.stopStationIDs.count == stationsByID.count,
              Set(localService.stopStationIDs) == Set(stationsByID.keys) else {
            throw TimetableError.inconsistentSources("all canonical stations must appear once in the local through route")
        }

        let pathIDs = localService.stopStationIDs
        var progressByID: [String: Double] = [:]
        var progress = 0.0
        if let firstID = pathIDs.first { progressByID[firstID] = 0 }
        if pathIDs.count > 1 {
            for index in 1..<pathIDs.count {
                let previous = stationsByID[pathIDs[index - 1]]!
                let current = stationsByID[pathIDs[index]]!
                if !Set(previous.trackIDs).isDisjoint(with: current.trackIDs) {
                    progress += abs(current.chainageM - previous.chainageM)
                } else {
                    // A line transition is measured from that track's canonical zero. In this
                    // network the branch starts at the S28 junction; no station is added or moved.
                    progress += current.chainageM
                }
                progressByID[current.stationID] = progress
            }
        }
        let passengerRouteLengthM = progress
        guard passengerRouteLengthM > 0 else {
            throw TimetableError.inconsistentSources("could not derive passenger route distance from canonical chainages")
        }
        for service in services {
            guard approximatelyEqual(service.routeDistanceKm * 1_000, passengerRouteLengthM, toleranceM: 1) else {
                throw TimetableError.inconsistentSources("\(service.category.rawValue) route distance differs from imported station chainages")
            }
            let positions = service.stopStationIDs.compactMap { pathIDs.firstIndex(of: $0) }
            guard positions.count == service.stopStationIDs.count,
                  zip(positions, positions.dropFirst()).allSatisfy({ pair in pair.0 < pair.1 }) else {
                throw TimetableError.inconsistentSources("\(service.category.rawValue) stop IDs are not an ordered subset of the canonical route")
            }
            guard service.stopStationIDs.first == pathIDs.first,
                  service.stopStationIDs.last == pathIDs.last else {
                throw TimetableError.inconsistentSources("\(service.category.rawValue) must serve both canonical passenger terminals")
            }
        }

        let canonicalStations = pathIDs.map { id -> TimetableStation in
            let station = stationsByID[id]!
            return TimetableStation(
                stationID: station.stationID,
                name: station.name,
                chainageM: station.chainageM,
                trackIDs: station.trackIDs,
                routeProgressM: progressByID[id]!,
                dataStatus: .placeholder
            )
        }

        let serviceByCategory = Dictionary(uniqueKeysWithValues: services.map { ($0.category, $0) })
        var weekdayPatterns: [TimetablePattern] = []
        for source in operations.timetablePatterns {
            guard source.dataStatus == "PLACEHOLDER", source.calendar == ServiceCalendar.weekday.rawValue else {
                throw TimetableError.unsupportedPlaceholderInput("weekday source pattern \(source.category)/\(source.direction) is not a WEEKDAY_PLACEHOLDER")
            }
            guard let category = ServiceCategory(rawValue: source.category),
                  let direction = ServiceDirection(rawValue: source.direction),
                  let daypart = Daypart(rawValue: source.daypart),
                  let service = serviceByCategory[category],
                  service.plannedRuntimeMinutes == source.plannedDurationMinutes,
                  source.intervalMinutes > 0 else {
                throw TimetableError.inconsistentSources("invalid weekday pattern \(source.category)/\(source.direction)/\(source.daypart)")
            }
            let start = try TimetableClock.parse(source.firstDeparture)
            let end = try TimetableClock.parse(source.lastDeparture)
            guard start < end else {
                throw TimetableError.inconsistentSources("weekday pattern has an empty or reversed window")
            }
            weekdayPatterns.append(TimetablePattern(
                category: category,
                direction: direction,
                daypart: daypart,
                calendar: .weekday,
                startMinute: start,
                endMinute: end,
                headwayMinutes: source.intervalMinutes,
                dataStatus: .placeholder
            ))
        }
        let expectedWeekdayKeys = Set(ServiceCategory.allCases.flatMap { category in
            ServiceDirection.allCases.flatMap { direction in
                Daypart.allCases.map { "\(category.rawValue)|\(direction.rawValue)|\($0.rawValue)" }
            }
        })
        let actualWeekdayKeys = Set(weekdayPatterns.map { "\($0.category.rawValue)|\($0.direction.rawValue)|\($0.daypart.rawValue)" })
        guard weekdayPatterns.count == expectedWeekdayKeys.count, actualWeekdayKeys == expectedWeekdayKeys else {
            throw TimetableError.inconsistentSources("weekday plan must contain one window per service, direction and daypart")
        }

        let depotConnectedTracks = Set(depotRecord.connectedTrackIDs.filter { $0 != depotRecord.trackID })
        guard let connection = canonicalStations
            .filter({ !Set($0.trackIDs).isDisjoint(with: depotConnectedTracks) })
            .min(by: { $0.chainageM < $1.chainageM }) else {
            throw TimetableError.inconsistentSources("depot has no canonical station connection")
        }
        let depot = DepotDefinition(
            depotID: depotRecord.depotID,
            trackID: depotRecord.trackID,
            connectedStationID: connection.stationID,
            spurLengthM: depotSpurLengthM,
            dataStatus: .placeholder
        )
        let depotProcedures = try operations.depotProcedures.map { source -> DepotProcedure in
            guard source.dataStatus == "PLACEHOLDER",
                  let category = ServiceCategory(rawValue: source.relatedServiceCategory),
                  let direction = ServiceDirection(rawValue: source.direction) else {
                throw TimetableError.unsupportedPlaceholderInput("unrecognized or non-PLACEHOLDER depot procedure")
            }
            let kind: DepotMovementKind
            switch source.kind {
            case "exitDepot": kind = .outbound
            case "enterDepot": kind = .inbound
            default: throw TimetableError.inconsistentSources("unknown depot procedure kind \(source.kind)")
            }
            return DepotProcedure(
                category: category,
                direction: direction,
                kind: kind,
                timeOffsetMinutesFromPassengerDeparture: source.timeOffsetMinutesFromPassengerDeparture,
                dataStatus: .placeholder
            )
        }
        guard !depotProcedures.isEmpty else {
            throw TimetableError.inconsistentSources("operations plan contains no depot procedure rules")
        }

        return ImportedTimetableInputs(
            routeID: route.routeID,
            routePackageID: routePackage.packageID,
            sourceNetworkIdentifier: opsNetwork.identifier,
            timezone: route.timezone ?? "Asia/Tokyo",
            physicalNetworkLengthM: physicalLengthM,
            passengerRouteLengthM: passengerRouteLengthM,
            routePathStationIDs: pathIDs,
            stations: canonicalStations,
            services: services,
            weekdayPatterns: weekdayPatterns,
            depot: depot,
            depotProcedures: depotProcedures
        )
    }
}

private func approximatelyEqual(_ lhs: Double, _ rhs: Double, toleranceM: Double = 1) -> Bool {
    abs(lhs - rhs) <= toleranceM
}

private struct EvidenceDTO<Value: Decodable>: Decodable {
    let value: Value?
    let status: String
}

private struct RoutePackageDTO: Decodable {
    let packageID: String
    let route: CanonicalRouteDTO
}

private struct CanonicalRouteDTO: Decodable {
    let routeID: String
    let datasetKind: String
    let timezone: String?
    let totalLengthM: EvidenceDTO<Double>
    let mainTrackID: String
    let networkLengthM: EvidenceDTO<Double>
    let tracks: [RouteTrackDTO]
    let stations: [RouteStationDTO]
    let depots: [RouteDepotDTO]
}

private struct RouteTrackDTO: Decodable {
    let trackID: String
    let segments: [RouteSegmentDTO]

    func extentM() throws -> Double {
        guard !segments.isEmpty,
              segments.allSatisfy({
                  $0.startChainageM.status == "PLACEHOLDER" && $0.startChainageM.value != nil &&
                  $0.endChainageM.status == "PLACEHOLDER" && $0.endChainageM.value != nil
              }) else {
            throw TimetableError.unsupportedPlaceholderInput("track \(trackID) segment extent is not PLACEHOLDER")
        }
        let endpoints = segments.flatMap { segment in
            [segment.startChainageM.value, segment.endChainageM.value].compactMap { $0 }
        }
        guard let low = endpoints.min(), let high = endpoints.max(), high >= low else {
            throw TimetableError.inconsistentSources("track \(trackID) lacks valid segment chainages")
        }
        return high - low
    }
}

private struct RouteSegmentDTO: Decodable {
    let startChainageM: EvidenceDTO<Double>
    let endChainageM: EvidenceDTO<Double>
}

private struct RouteStationDTO: Decodable {
    let stationID: String
    let name: EvidenceDTO<String>
    let chainageM: EvidenceDTO<Double>
    let trackIDs: [String]
}

private struct RouteDepotDTO: Decodable {
    let depotID: String
    let trackID: String
    let chainageM: EvidenceDTO<Double>
    let connectedTrackIDs: [String]
}

private struct OperationsPlanDTO: Decodable {
    let network: OperationsNetworkDTO
    let stations: [OperationsStationDTO]
    let services: [OperationsServiceDTO]
    let timetablePatterns: [OperationsPatternDTO]
    let depotProcedures: [OperationsDepotProcedureDTO]
}

private struct OperationsNetworkDTO: Decodable {
    let identifier: String
    let dataStatus: String
    let totalRouteLengthKm: Double
    let mainlineLengthKm: Double
    let branchLengthKm: Double
    let depotSpurLengthKm: Double
}

private struct OperationsStationDTO: Decodable {
    let stationId: String
    let name: String
    let chainageKm: Double
    let dataStatus: String
}

private struct OperationsServiceDTO: Decodable {
    let category: String
    let routeDistanceKm: Double
    let plannedDurationMinutes: Int
    let stopStationIDs: [String]
    let dataStatus: String
}

private struct OperationsPatternDTO: Decodable {
    let category: String
    let direction: String
    let daypart: String
    let firstDeparture: String
    let lastDeparture: String
    let intervalMinutes: Int
    let plannedDurationMinutes: Int
    let calendar: String
    let dataStatus: String
}

private struct OperationsDepotProcedureDTO: Decodable {
    let kind: String
    let relatedServiceCategory: String
    let direction: String
    let timeOffsetMinutesFromPassengerDeparture: Int
    let dataStatus: String
}
