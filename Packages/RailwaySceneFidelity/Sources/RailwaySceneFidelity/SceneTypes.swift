import Foundation

public enum SceneAssemblyRole: String, Codable, CaseIterable, Sendable {
    case trackBed
    case rail
    case sleeper
    case trackFastener
    case catenarySupport
    case overheadWire
    case platform
    case stationFurniture
    case building
    case roadSurface
    case roadVehicle
    case pedestrian
    case vegetation
    /// Fictional bridge deck, girders, parapets, and piers. Not a surveyed structure.
    case bridgeStructure
    case cuttingWall
    case embankment
    /// Static scenic crossing. It does not interlock, close barriers, or stop the train.
    case levelCrossing
    /// Lineside kilometre post or marker board. Static furniture only.
    case tracksideSign
}

public enum ScenePieceShape: String, Codable, Sendable {
    case box
    case cylinder
    case sphere
}

public enum SceneMaterialStyle: String, Codable, CaseIterable, Sendable {
    case ballast
    case subBallast
    case concrete
    case wood
    case darkSteel
    case polishedRailSteel
    case galvanizedSteel
    case ceramicInsulator
    case tactileAmber
    case platformConcrete
    case canopyMetal
    case buildingWarm
    case buildingCool
    case windowGlass
    case roadAsphalt
    case roadPaint
    case vehicleBlue
    case vehicleRed
    case vehicleSilver
    case tireRubber
    case foliageDeep
    case foliageLight
    case bark
    case personJacket
    case personTrousers
    case skinTone
    /// Stylized water tint. Not a simulated river or reflected environment.
    case riverWater
    /// Stylized slope color. Not surveyed turf or a layered PBR material.
    case grassSlope
}

/// A box/cylinder/sphere placed in assembly-local coordinates (x lateral, y up, z forward).
public struct ScenePiece: Codable, Hashable, Sendable {
    public let name: String
    public let shape: ScenePieceShape
    public let localPosition: SceneVector3
    public let dimensions: SceneVector3
    /// Euler radians in local X/Y/Z order; used for rail-length beams and vehicle wheels.
    public let localRotationRadians: SceneVector3
    public let material: SceneMaterialStyle
    public let minimumLOD: SceneLODLevel

    public init(
        name: String,
        shape: ScenePieceShape = .box,
        localPosition: SceneVector3,
        dimensions: SceneVector3,
        localRotationRadians: SceneVector3 = .zero,
        material: SceneMaterialStyle,
        minimumLOD: SceneLODLevel = .far
    ) {
        self.name = name
        self.shape = shape
        self.localPosition = localPosition
        self.dimensions = dimensions
        self.localRotationRadians = localRotationRadians
        self.material = material
        self.minimumLOD = minimumLOD
    }
}

public enum SceneLODLevel: Int, Codable, Comparable, Sendable {
    case high = 0
    case medium = 1
    case far = 2

    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
}

public struct SceneAssembly: Codable, Hashable, Sendable, Identifiable {
    public let id: String
    public let role: SceneAssemblyRole
    public let chainageM: Double
    public let position: SceneVector3
    public let forward: SceneVector3
    public let right: SceneVector3
    public let up: SceneVector3
    public let boundingRadiusM: Double
    public let pieces: [ScenePiece]
    /// Human-readable provenance marker; these generated forms are not measured or authored photoreal assets.
    public let syntheticPlaceholderLabel: String?

    public init(
        id: String,
        role: SceneAssemblyRole,
        chainageM: Double,
        position: SceneVector3,
        forward: SceneVector3,
        right: SceneVector3,
        up: SceneVector3,
        boundingRadiusM: Double,
        pieces: [ScenePiece],
        syntheticPlaceholderLabel: String? = nil
    ) {
        self.id = id
        self.role = role
        self.chainageM = chainageM
        self.position = position
        self.forward = forward
        self.right = right
        self.up = up
        self.boundingRadiusM = max(0.1, boundingRadiusM)
        self.pieces = pieces
        self.syntheticPlaceholderLabel = syntheticPlaceholderLabel
    }
}

public struct ScenePlatformSpecification: Codable, Hashable, Sendable, Identifiable {
    public let id: String
    public let startChainageM: Double
    public let endChainageM: Double
    /// -1 = left, +1 = right, in the local route frame.
    public let side: Int
    public let offsetFromTrackCenterM: Double
    public let widthM: Double
    public let hasCanopy: Bool

    public init(
        id: String,
        startChainageM: Double,
        endChainageM: Double,
        side: Int,
        offsetFromTrackCenterM: Double = 4.8,
        widthM: Double = 3.6,
        hasCanopy: Bool = true
    ) {
        self.id = id
        self.startChainageM = startChainageM
        self.endChainageM = endChainageM
        self.side = side < 0 ? -1 : 1
        self.offsetFromTrackCenterM = max(3.0, offsetFromTrackCenterM)
        self.widthM = max(1.5, widthM)
        self.hasCanopy = hasCanopy
    }
}

public struct SceneCorridorSpecification: Codable, Hashable, Sendable {
    public var trackGaugeM: Double
    public var sleeperSpacingM: Double
    public var catenarySpacingM: Double
    public var overheadContactWireHeightM: Double
    public var platforms: [ScenePlatformSpecification]
    public var generateUrbanScenery: Bool

    public init(
        trackGaugeM: Double = 1.435,
        sleeperSpacingM: Double = 0.60,
        catenarySpacingM: Double = 45.0,
        overheadContactWireHeightM: Double = 5.2,
        platforms: [ScenePlatformSpecification] = [],
        generateUrbanScenery: Bool = true
    ) {
        self.trackGaugeM = max(0.8, trackGaugeM)
        self.sleeperSpacingM = max(0.25, sleeperSpacingM)
        self.catenarySpacingM = max(12, catenarySpacingM)
        self.overheadContactWireHeightM = max(4.0, overheadContactWireHeightM)
        self.platforms = platforms
        self.generateUrbanScenery = generateUrbanScenery
    }
}

public enum SceneDensityPreset: String, Codable, CaseIterable, Sendable {
    case performance
    case balanced
    case highDetail
}

/// Lightweight material response hints for generated surfaces; these are not weather simulation or layered PBR maps.
public struct SceneSurfaceWeather: Codable, Hashable, Sendable {
    public let wetness: Double
    public let snowCoverage: Double

    public init(wetness: Double = 0, snowCoverage: Double = 0) {
        self.wetness = Self.unit(wetness)
        self.snowCoverage = Self.unit(snowCoverage)
    }

    public static let dry = SceneSurfaceWeather()

    private static func unit(_ value: Double) -> Double {
        value.isFinite ? min(max(value, 0), 1) : 0
    }
}

/// Tunable world/build budget. Track core remains present in every preset; decorative micro-detail scales down.
public struct SceneDensityControls: Codable, Hashable, Sendable {
    public var visibleDistanceM: Double
    public var railChunkLengthM: Double
    public var scenerySpacingM: Double
    public var maxSceneryAssemblies: Int
    public var detailLevel: Int
    public var includeRoadVehicles: Bool
    public var includePeople: Bool
    public var includeVegetation: Bool

    public init(
        visibleDistanceM: Double = 900,
        railChunkLengthM: Double = 3.0,
        scenerySpacingM: Double = 12,
        maxSceneryAssemblies: Int = 3_200,
        detailLevel: Int = 2,
        includeRoadVehicles: Bool = true,
        includePeople: Bool = true,
        includeVegetation: Bool = true
    ) {
        self.visibleDistanceM = max(30, visibleDistanceM)
        self.railChunkLengthM = max(0.75, railChunkLengthM)
        self.scenerySpacingM = max(6, scenerySpacingM)
        self.maxSceneryAssemblies = max(0, maxSceneryAssemblies)
        self.detailLevel = min(2, max(0, detailLevel))
        self.includeRoadVehicles = includeRoadVehicles
        self.includePeople = includePeople
        self.includeVegetation = includeVegetation
    }

    public static func preset(_ preset: SceneDensityPreset) -> SceneDensityControls {
        switch preset {
        case .performance:
            return SceneDensityControls(
                visibleDistanceM: 420, railChunkLengthM: 4.5,
                scenerySpacingM: 28, maxSceneryAssemblies: 420,
                detailLevel: 0, includePeople: false
            )
        case .balanced:
            return SceneDensityControls()
        case .highDetail:
            return SceneDensityControls(
                visibleDistanceM: 1_200, railChunkLengthM: 2.0,
                scenerySpacingM: 9, maxSceneryAssemblies: 4_500,
                detailLevel: 2
            )
        }
    }
}

public struct SceneBuildDiagnostics: Codable, Hashable, Sendable {
    public let generatedAssemblyCount: Int
    public let generatedPieceCount: Int
    public let visibleAssemblyCountAtBuild: Int
    public let countsByRole: [String: Int]
    public let warnings: [String]
}

public struct SceneBuildPlan: Sendable {
    public let assemblies: [SceneAssembly]
    public let cameraAtBuild: SceneCameraState
    public let density: SceneDensityControls
    public let diagnostics: SceneBuildDiagnostics

    public func visibleAssemblies(for camera: SceneCameraState) -> [SceneAssembly] {
        assemblies.filter { SceneCullingPolicy.isVisible($0, camera: camera, maxDistanceM: density.visibleDistanceM) }
    }
}

public enum SceneCullingPolicy {
    public static func levelOfDetail(distanceM: Double, controls: SceneDensityControls) -> SceneLODLevel {
        if controls.detailLevel == 0 { return .far }
        if distanceM <= min(90, controls.visibleDistanceM * 0.12) { return .high }
        if distanceM <= min(330, controls.visibleDistanceM * 0.42) { return .medium }
        return .far
    }

    /// Bounding-sphere frustum test plus a finite visibility range. No occlusion data is inferred.
    public static func isVisible(
        _ assembly: SceneAssembly,
        camera: SceneCameraState,
        maxDistanceM: Double
    ) -> Bool {
        let offset = assembly.position - camera.position
        let distance = offset.length
        let radius = assembly.boundingRadiusM
        guard distance - radius <= min(maxDistanceM, camera.farDistanceM),
              distance + radius >= camera.nearDistanceM else { return false }
        let depth = offset.dot(camera.forward)
        guard depth + radius >= camera.nearDistanceM else { return false }
        let safeDepth = max(camera.nearDistanceM, depth)
        let verticalHalfExtent = safeDepth * tan(camera.verticalFieldOfViewRadians * 0.5)
        let horizontalHalfExtent = verticalHalfExtent * camera.aspectRatio
        return abs(offset.dot(camera.right)) <= horizontalHalfExtent + radius
            && abs(offset.dot(camera.up)) <= verticalHalfExtent + radius
    }
}
