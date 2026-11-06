import Foundation

enum ServiceCategory: String, Codable, CaseIterable, Hashable, Identifiable, Sendable {
    case local
    case rapid
    case semiExpress
    case express
    case rapidExpress
    case limitedExpress

    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .local: return "各駅停車"
        case .rapid: return "快速"
        case .semiExpress: return "準急"
        case .express: return "急行"
        case .rapidExpress: return "快速急行"
        case .limitedExpress: return "特急"
        }
    }
}

enum ServiceDirection: String, Codable, CaseIterable, Hashable, Identifiable, Sendable {
    case up
    case down

    var id: String { rawValue }
    var displayName: String { self == .up ? "上り" : "下り" }
}

enum TimetableDaypart: String, Codable, CaseIterable, Hashable, Identifiable, Sendable {
    case morningRush
    case daytime
    case evening
    case night

    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .morningRush: return "朝ラッシュ"
        case .daytime: return "昼間"
        case .evening: return "夕方"
        case .night: return "夜間"
        }
    }
}

enum DepotProcedureKind: String, Codable {
    case exitDepot
    case enterDepot

    var displayName: String { self == .exitDepot ? "出庫" : "入庫" }
}

struct FictionalOperationsPlan: Decodable {
    struct Network: Decodable {
        let identifier: String
        let name: String
        let dataStatus: String
        let totalRouteLengthKm: Double
        let mainlineLengthKm: Double
        let branchLengthKm: Double
        let depotSpurLengthKm: Double
        let mainlineID: String
        let branchID: String
        let depotSpurID: String
        let depotStationID: String
        let canonicalTopologyID: String
        let reconciliationNote: String
        let branchJunctionStationID: String
        let mainlineTermini: [String]
        let branchTerminalStationID: String
    }

    struct Station: Decodable {
        let stationId: String
        let name: String
        let lineId: String
        let chainageKm: Double
        let dataStatus: String
    }

    struct Service: Decodable, Identifiable {
        let category: ServiceCategory
        let routeDistanceKm: Double
        let plannedDurationMinutes: Int
        let stopStationIDs: [String]
        let dataStatus: String

        var id: String { category.rawValue }
        var isWithinTarget: Bool { (60...150).contains(plannedDurationMinutes) }
    }

    struct TimetablePattern: Decodable, Identifiable {
        let category: ServiceCategory
        let direction: ServiceDirection
        let daypart: TimetableDaypart
        let firstDeparture: String
        let lastDeparture: String
        let intervalMinutes: Int
        let plannedDurationMinutes: Int
        let calendar: String
        let dataStatus: String

        var id: String { "\(category.rawValue)-\(direction.rawValue)-\(daypart.rawValue)" }
    }

    struct DepotProcedure: Decodable, Identifiable {
        let procedureId: String
        let kind: DepotProcedureKind
        let depotId: String
        let relatedServiceCategory: ServiceCategory
        let direction: ServiceDirection
        let timeOffsetMinutesFromPassengerDeparture: Int
        let dataStatus: String

        var id: String { procedureId }
    }

    let disclaimer: String
    let network: Network
    let stations: [Station]
    let services: [Service]
    let timetablePatterns: [TimetablePattern]
    let depotProcedures: [DepotProcedure]

    static func loadBundled() -> FictionalOperationsPlan? {
        guard let url = Bundle.main.url(forResource: "FictionalOperationsPlan", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let plan = try? JSONDecoder().decode(FictionalOperationsPlan.self, from: data),
              plan.validationIssues.isEmpty else { return nil }
        return plan
    }

    var validationIssues: [String] {
        var issues: [String] = []
        if network.dataStatus != "PLACEHOLDER" { issues.append("network must remain explicitly PLACEHOLDER") }
        if network.canonicalTopologyID != "fictional-mainline-placeholder" {
            issues.append("network canonical topology ID does not match the app adapter")
        }
        let physicalLength = network.mainlineLengthKm + network.branchLengthKm + network.depotSpurLengthKm
        if abs(network.totalRouteLengthKm - physicalLength) > 0.01 {
            issues.append("network length must equal mainline plus branch plus depot spur")
        }
        if abs(network.totalRouteLengthKm - 70.0) > 0.1 ||
            abs(network.mainlineLengthKm - 60.0) > 0.1 ||
            abs(network.branchLengthKm - 8.0) > 0.1 ||
            abs(network.depotSpurLengthKm - 2.0) > 0.1 {
            issues.append("canonical PLACEHOLDER topology must be 60 km + 8 km + 2 km = 70 km")
        }
        if network.mainlineID.isEmpty || network.branchID.isEmpty || network.depotSpurID.isEmpty ||
            network.depotStationID.isEmpty || network.reconciliationNote.isEmpty {
            issues.append("canonical network IDs and reconciliation note are required")
        }
        if Set(stations.map(\.stationId)).count != stations.count { issues.append("station IDs must be unique") }
        if !stations.contains(where: { $0.stationId == network.branchJunctionStationID && $0.lineId == network.mainlineID }) {
            issues.append("branch junction station is missing from the mainline")
        }
        if !stations.contains(where: { $0.stationId == network.branchTerminalStationID && $0.lineId == network.branchID }) {
            issues.append("branch terminal station is missing from the branch")
        }
        for station in stations {
            if station.dataStatus != "PLACEHOLDER" { issues.append("station \(station.stationId) must remain PLACEHOLDER") }
            if !station.chainageKm.isFinite || station.chainageKm < 0 { issues.append("station \(station.stationId) has invalid chainage") }
            if station.lineId == network.mainlineID && station.chainageKm > network.mainlineLengthKm + 0.001 {
                issues.append("mainline station \(station.stationId) is outside canonical chainage")
            }
            if station.lineId == network.branchID && station.chainageKm > network.branchLengthKm + 0.001 {
                issues.append("branch station \(station.stationId) is outside local branch chainage")
            }
        }

        var serviceByCategory: [ServiceCategory: Service] = [:]
        for service in services {
            if serviceByCategory[service.category] != nil {
                issues.append("service categories must not be duplicated")
            } else {
                serviceByCategory[service.category] = service
            }
        }
        if ServiceCategory.allCases.contains(where: { serviceByCategory[$0] == nil }) {
            issues.append("all six passenger service categories are required")
        }
        let stationIDs = Set(stations.map(\.stationId))
        for service in services {
            if !service.isWithinTarget { issues.append("\(service.category.rawValue) duration must be 60–150 minutes") }
            let servesBranch = service.stopStationIDs.contains(network.branchTerminalStationID)
            let expectedRouteLength = network.mainlineLengthKm + (servesBranch ? network.branchLengthKm : 0)
            if abs(service.routeDistanceKm - expectedRouteLength) > 0.01 {
                issues.append("\(service.category.rawValue) route distance must exclude the depot spur and match its stops")
            }
            if service.dataStatus != "PLACEHOLDER" { issues.append("service \(service.category.rawValue) must remain PLACEHOLDER") }
            if service.stopStationIDs.count < 2 || service.stopStationIDs.first == nil || service.stopStationIDs.last == nil {
                issues.append("\(service.category.rawValue) needs an origin and destination")
            }
            if service.stopStationIDs.contains(where: { !stationIDs.contains($0) }) {
                issues.append("\(service.category.rawValue) references an unknown station")
            }
        }
        if serviceByCategory[.local]?.plannedDurationMinutes != 150 {
            issues.append("all-stops local target should be 150 minutes")
        }

        let expectedPatternCount = ServiceCategory.allCases.count * ServiceDirection.allCases.count * TimetableDaypart.allCases.count
        if timetablePatterns.count != expectedPatternCount || Set(timetablePatterns.map(\.id)).count != expectedPatternCount {
            issues.append("timetable must define each category/direction/daypart combination")
        }
        for pattern in timetablePatterns {
            guard let service = serviceByCategory[pattern.category] else {
                issues.append("timetable references an undefined service")
                continue
            }
            if pattern.dataStatus != "PLACEHOLDER" { issues.append("timetable pattern \(pattern.id) must remain PLACEHOLDER") }
            if pattern.intervalMinutes <= 0 || pattern.plannedDurationMinutes != service.plannedDurationMinutes {
                issues.append("timetable interval or journey duration is invalid")
            }
            guard let first = Self.minutesSinceMidnight(pattern.firstDeparture),
                  let last = Self.minutesSinceMidnight(pattern.lastDeparture) else {
                issues.append("timetable departure time must use HH:MM")
                continue
            }
            if first > last { issues.append("timetable departure window is reversed") }
        }
        if !depotProcedures.contains(where: { $0.kind == .exitDepot }) || !depotProcedures.contains(where: { $0.kind == .enterDepot }) {
            issues.append("both depot exit and entry procedures are required")
        }
        if depotProcedures.contains(where: { $0.dataStatus != "PLACEHOLDER" }) {
            issues.append("depot procedures must remain PLACEHOLDER")
        }
        if depotProcedures.contains(where: { $0.depotId != "DEPOT-NORTH" }) {
            issues.append("depot procedure references a non-canonical depot ID")
        }
        return issues
    }

    static func minutesSinceMidnight(_ text: String) -> Int? {
        let parts = text.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2, let hour = Int(parts[0]), let minute = Int(parts[1]),
              (0...24).contains(hour), (0...59).contains(minute), !(hour == 24 && minute != 0) else { return nil }
        return hour * 60 + minute
    }
}
