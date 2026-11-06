import Foundation

/// Maps generated scenery surfaces to original tileable images.
/// The pixels are produced in-repo. They are not photographs and not a photoreal claim.
public struct SceneSurfaceTextureRecord: Equatable, Sendable {
    public var style: SceneMaterialStyle
    public var resourceName: String
    public var originNote: String
}

public enum SceneSurfaceTextureCatalog {
    public static let originNote =
        "ORIGINAL procedural pixels generated in this repository. No downloaded photograph, cab reference photo, BVE image, or Street View frame. Commercial use is allowed because the pixels are original. Not photoreal."

    private static let names: [SceneMaterialStyle: String] = [
        .ballast: "scenery_ballast",
        .subBallast: "scenery_ballast",
        .concrete: "scenery_concrete",
        .platformConcrete: "scenery_concrete",
        .grassSlope: "scenery_grass",
        .foliageDeep: "scenery_foliage",
        .foliageLight: "scenery_foliage",
        .roadAsphalt: "scenery_asphalt",
        .buildingWarm: "scenery_brick_warm",
        .buildingCool: "scenery_brick_cool",
        .darkSteel: "scenery_steel",
        .galvanizedSteel: "scenery_steel",
        .polishedRailSteel: "scenery_steel",
        .canopyMetal: "scenery_steel",
        .wood: "scenery_timber",
        .bark: "scenery_timber"
    ]

    public static func record(for style: SceneMaterialStyle) -> SceneSurfaceTextureRecord? {
        guard let name = names[style] else { return nil }
        return SceneSurfaceTextureRecord(style: style, resourceName: name, originNote: originNote)
    }

    public static var resourceNames: [String] {
        Array(Set(names.values)).sorted()
    }
}
