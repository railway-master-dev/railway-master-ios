import Foundation

/// Synthetic source models supplied in the user-provided ZIP plus original procedural models generated in this project.
public enum RailwayGenerated3DAsset: String, CaseIterable, Codable, Sendable {
    case commuterCarGeneric = "commuter_car_generic"
    case commuterCarDetailed = "commuter_train_car_detailed"
    case driverCabInterior = "driver_cab_interior"
    case driverCabInteriorDetailed = "driver_cab_interior_detailed"
    case trackPanel20m = "track_panel_20m"
    case railwayEquipmentModule = "railway_equipment_module"
    case stationSidePlatform = "station_side_platform"
    case stationIslandPlatform = "station_island_platform"
    case station3TrackPassing = "station_3track_passing"
    case station4TrackMajor = "station_4track_major"
    case station5Track4Platform = "station_5track_4platform"
    case stationTerminal = "station_terminal"
    case suburbanCorridorModules = "suburban_corridor_modules"
    /// own.guest E231 (CC BY 4.0), repainted as the TOO RAILWAY
    /// commuter train; nodes car_1...car_10, see the integration
    /// notes in workspace/models/e231_sketchfab/.
    case tooE231 = "too_e231_10car"
    /// own.guest 117 series "Sun Liner" (CC BY 4.0), repainted as
    /// the TOO RAILWAY limited-express train; nodes car_1...car_8.
    case too117 = "too_117_8car"
}

public struct RailwayGeneratedStationLayout: Codable, Hashable, Sendable, Identifiable {
    public let stationId: String
    public let name: String
    public let lineId: String
    /// Line-local chainage from the source station-layout manifest. The app places the model using the route's canonical stop chainage.
    public let chainageM: Double
    public let archetype: String
    public let stationRole: String
    public let trackCount: Int
    public let platformCount: Int

    public var id: String { stationId }

    public var modelAsset: RailwayGenerated3DAsset {
        switch archetype {
        case "terminal_3platform", "branch_terminal": return .stationTerminal
        case "major_5track_4platform": return .station5Track4Platform
        case "major_4track_3platform", "junction_3platform": return .station4TrackMajor
        case "passing_3track_2platform": return .station3TrackPassing
        case "island_platform": return .stationIslandPlatform
        default: return .stationSidePlatform
        }
    }
}

public struct RailwayGeneratedStationLayoutManifest: Codable, Sendable {
    public let schemaVersion: String
    public let datasetKind: String
    public let description: String
    public let stationCount: Int
    public let source: String
    public let stations: [RailwayGeneratedStationLayout]
}

/// A route-positioned visual station model. `chainageM` comes from the active route stop list,
/// while platform/track topology comes from the 32-station placeholder manifest.
public struct RailwayGeneratedStationPlacement: Codable, Hashable, Sendable, Identifiable {
    public let stationId: String
    public let name: String
    public let chainageM: Double
    public let archetype: String
    public let trackCount: Int
    public let platformCount: Int
    public let asset: RailwayGenerated3DAsset

    public var id: String { stationId }

    public init(layout: RailwayGeneratedStationLayout, routeChainageM: Double) {
        stationId = layout.stationId
        name = layout.name
        chainageM = routeChainageM
        archetype = layout.archetype
        trackCount = layout.trackCount
        platformCount = layout.platformCount
        asset = layout.modelAsset
    }
}

public enum RailwayGeneratedAssetCatalog {
    private static func resourceURL(_ name: String, extension fileExtension: String) -> URL? {
        Bundle.module.url(forResource: name, withExtension: fileExtension, subdirectory: "Generated3D")
            ?? Bundle.module.url(forResource: name, withExtension: fileExtension)
    }

    public static func sourceModelURL(for asset: RailwayGenerated3DAsset) -> URL? {
        switch asset {
        case .commuterCarDetailed, .driverCabInteriorDetailed:
            return Bundle.module.url(
                forResource: asset.rawValue,
                withExtension: "glb",
                subdirectory: "Generated3D/HighFidelityAssets"
            )
        default:
            return resourceURL(asset.rawValue, extension: "glb")
        }
    }

    public static var stationLayoutsURL: URL? {
        resourceURL("station_layouts_32", extension: "json")
    }

    public static var manifestURL: URL? {
        resourceURL("asset_manifest", extension: "json")
    }

    public static var routeGeometrySpecificationURL: URL? {
        resourceURL("randomized_route_geometry_spec", extension: "json")
    }

    public static func stationLayoutsData() throws -> Data {
        guard let url = stationLayoutsURL else { throw CocoaError(.fileNoSuchFile) }
        return try Data(contentsOf: url)
    }

    public static func stationLayoutManifest() throws -> RailwayGeneratedStationLayoutManifest {
        try JSONDecoder().decode(RailwayGeneratedStationLayoutManifest.self, from: stationLayoutsData())
    }
}
