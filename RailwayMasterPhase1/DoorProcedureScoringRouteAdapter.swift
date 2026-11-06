import Foundation
import DoorProcedureScoring
import RailwayGameModes

/// Loads only authored fictional door/procedure data. Stops absent from the source remain `.missing`.
enum DoorProcedureScoringRouteAdapter {
    private struct Dataset: Decodable {
        let fictionalDatasetNotice: String
        let schemaVersion: Int
        let routeScenarios: [String: [StationScoringDefinition]]
    }

    enum AdapterError: Error, LocalizedError {
        case missingResource
        case unsupportedSchema(Int)

        var errorDescription: String? {
            switch self {
            case .missingResource:
                "FictionalDoorProcedureScoring.json がアプリ内にありません。"
            case .unsupportedSchema(let version):
                "ドア・手順データのスキーマ v\(version) は未対応です。"
            }
        }
    }

    static func makeEngine(routeID: String, stops: [RegionalRouteStop]) throws -> DoorProcedureScoringEngine {
        guard stops.count >= 2 else {
            throw DoorProcedureScoringError.invalidConfiguration("At least one post-origin stop is required.")
        }
        let dataset = try loadDataset()
        guard dataset.schemaVersion == 1 else { throw AdapterError.unsupportedSchema(dataset.schemaVersion) }
        let sourceByID = Dictionary(
            (dataset.routeScenarios[routeID] ?? []).map { ($0.stationID, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let definitions = try stops.dropFirst().map { stop in
            if let supplied = sourceByID[stop.stationID] { return supplied }
            return try StationScoringDefinition(
                stationID: stop.stationID,
                displayName: stop.name,
                expectedDoorSide: .missing,
                procedureRequirements: .missing
            )
        }
        return try DoorProcedureScoringEngine(stations: definitions)
    }

    /// The conductor game uses explicit authored sides when supplied. Its legacy
    /// alternation remains only a visibly fictional fallback and is never scoring data.
    static func gameModePlatformSide(routeID: String, stationID: String) -> GameModePlatformSide? {
        guard let dataset = try? loadDataset(), dataset.schemaVersion == 1,
              let definition = dataset.routeScenarios[routeID]?.first(where: { $0.stationID == stationID }),
              case .known(let side) = definition.expectedDoorSide else { return nil }
        switch side {
        case .left: return .left
        case .right: return .right
        case .both, .noDoorSide: return nil
        }
    }

    private static func loadDataset() throws -> Dataset {
        guard let url = Bundle.main.url(forResource: "FictionalDoorProcedureScoring", withExtension: "json") else {
            throw AdapterError.missingResource
        }
        return try JSONDecoder().decode(Dataset.self, from: Data(contentsOf: url))
    }
}
