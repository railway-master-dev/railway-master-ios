#if canImport(RealityKit) && canImport(UIKit)
import RealityKit
import UIKit
import simd

/// Converts portable assembly plans into RealityKit meshes on the main actor.
/// Box/cylinder/sphere pieces are batched by material within each assembly to limit entity count.
@MainActor
public final class RailwayRealityKitSceneAdapter {
    public let root = Entity()
    public private(set) var needsSceneRebuild = false
    public private(set) var pendingLODAssemblyIDs = Set<String>()
    public private(set) var lastBuildErrors: [String] = []
    public private(set) var surfaceWeather = SceneSurfaceWeather.dry

    private struct WeatherMaterialTarget {
        let assemblyID: String
        let model: ModelEntity
        let style: SceneMaterialStyle
    }

    private var currentPlan: SceneBuildPlan?
    private var assemblyEntities: [String: Entity] = [:]
    private var builtLODByID: [String: SceneLODLevel] = [:]
    private var materialTargets: [WeatherMaterialTarget] = []

    public init() {
        root.name = "RailwaySceneFidelity-SyntheticCorridor"
    }

    /// Replaces the currently materialised view-dependent region. Attach `root` once to an existing scene anchor.
    public func build(plan: SceneBuildPlan, camera: SceneCameraState, surfaceWeather: SceneSurfaceWeather = .dry) {
        root.children.forEach { $0.removeFromParent() }
        assemblyEntities.removeAll(keepingCapacity: true)
        builtLODByID.removeAll(keepingCapacity: true)
        materialTargets.removeAll(keepingCapacity: true)
        pendingLODAssemblyIDs.removeAll(keepingCapacity: true)
        lastBuildErrors.removeAll(keepingCapacity: true)
        needsSceneRebuild = false
        currentPlan = plan
        self.surfaceWeather = surfaceWeather

        let visibleIDs = Set(plan.visibleAssemblies(for: camera).map(\.id))
        for assembly in plan.assemblies where visibleIDs.contains(assembly.id) {
            let distance = (assembly.position - camera.position).length
            let lod = SceneCullingPolicy.levelOfDetail(distanceM: distance, controls: plan.density)
            if let entity = makeEntity(for: assembly, lod: lod) {
                root.addChild(entity)
                assemblyEntities[assembly.id] = entity
                builtLODByID[assembly.id] = lod
            }
        }
    }

    /// Cheap per-frame sphere/frustum visibility update. It flags missing/new or LOD-crossing chunks for streamed rebuild.
    public func updateCamera(_ camera: SceneCameraState) {
        guard let plan = currentPlan else { return }
        let visible = plan.visibleAssemblies(for: camera)
        let visibleIDs = Set(visible.map(\.id))
        for (id, entity) in assemblyEntities {
            entity.isEnabled = visibleIDs.contains(id)
        }
        for assembly in visible {
            guard let builtLOD = builtLODByID[assembly.id] else {
                needsSceneRebuild = true
                continue
            }
            let distance = (assembly.position - camera.position).length
            let wantedLOD = SceneCullingPolicy.levelOfDetail(distanceM: distance, controls: plan.density)
            if wantedLOD != builtLOD { pendingLODAssemblyIDs.insert(assembly.id) }
        }
        if visibleIDs.contains(where: { assemblyEntities[$0] == nil }) {
            needsSceneRebuild = true
        }
    }

    /// Applies bounded weather material hints in place; small blend changes are coalesced to avoid per-frame material churn.
    public func updateSurfaceWeather(_ weather: SceneSurfaceWeather) {
        let delta = max(abs(weather.wetness - surfaceWeather.wetness), abs(weather.snowCoverage - surfaceWeather.snowCoverage))
        guard delta >= 0.05 else { return }
        surfaceWeather = weather
        for target in materialTargets {
            let material = makeMaterial(for: target.style, weather: weather)
            guard var component = target.model.model else { continue }
            component.materials = [material]
            target.model.model = component
        }
    }

    /// Rebuilds only requested visible chunks after an LOD threshold crossing; call at a controlled streaming boundary.
    public func rebuildLODAssemblies(_ ids: Set<String>, camera: SceneCameraState) {
        guard let plan = currentPlan else { return }
        let wanted = Set(plan.visibleAssemblies(for: camera).map(\.id))
        for assembly in plan.assemblies where ids.contains(assembly.id) && wanted.contains(assembly.id) {
            materialTargets.removeAll { $0.assemblyID == assembly.id }
            assemblyEntities[assembly.id]?.removeFromParent()
            assemblyEntities[assembly.id] = nil
            builtLODByID[assembly.id] = nil
            let distance = (assembly.position - camera.position).length
            let lod = SceneCullingPolicy.levelOfDetail(distanceM: distance, controls: plan.density)
            if let entity = makeEntity(for: assembly, lod: lod) {
                root.addChild(entity)
                assemblyEntities[assembly.id] = entity
                builtLODByID[assembly.id] = lod
            }
            pendingLODAssemblyIDs.remove(assembly.id)
        }
        updateCamera(camera)
    }

    public func placeholderLabel(forAssemblyID id: String) -> String? {
        currentPlan?.assemblies.first(where: { $0.id == id })?.syntheticPlaceholderLabel
    }

    private func makeEntity(for assembly: SceneAssembly, lod: SceneLODLevel) -> Entity? {
        let entity = Entity()
        entity.name = assembly.syntheticPlaceholderLabel.map { "\(assembly.id) [\($0)]" } ?? assembly.id
        entity.position = SIMD3<Float>(Float(assembly.position.x), Float(assembly.position.y), Float(assembly.position.z))
        let x = SIMD3<Float>(Float(assembly.right.x), Float(assembly.right.y), Float(assembly.right.z))
        let y = SIMD3<Float>(Float(assembly.up.x), Float(assembly.up.y), Float(assembly.up.z))
        let z = SIMD3<Float>(Float(assembly.forward.x), Float(assembly.forward.y), Float(assembly.forward.z))
        entity.orientation = simd_quatf(simd_float3x3(columns: (x, y, z)))

        var buckets: [SceneMaterialStyle: SceneMeshAccumulator] = [:]
        for piece in assembly.pieces where piece.minimumLOD.rawValue >= lod.rawValue {
            var bucket = buckets[piece.material, default: SceneMeshAccumulator()]
            bucket.append(piece)
            buckets[piece.material] = bucket
        }
        for style in buckets.keys.sorted(by: { $0.rawValue < $1.rawValue }) {
            guard let bucket = buckets[style], !bucket.positions.isEmpty else { continue }
            do {
                let mesh = try bucket.makeMesh()
                let material = makeMaterial(for: style, weather: surfaceWeather)
                let model = ModelEntity(mesh: mesh, materials: [material])
                model.name = "\(assembly.id)-\(style.rawValue)-batch"
                entity.addChild(model)
                materialTargets.append(WeatherMaterialTarget(assemblyID: assembly.id, model: model, style: style))
            } catch {
                lastBuildErrors.append("\(assembly.id)/\(style.rawValue): \(error.localizedDescription)")
            }
        }
        return entity.children.isEmpty ? nil : entity
    }

    private var albedoTextures: [String: TextureResource] = [:]

    private func makeMaterial(for style: SceneMaterialStyle, weather: SceneSurfaceWeather) -> SimpleMaterial {
        let (color, roughness, metallic) = materialParameters(for: style, weather: weather)
        var material = SimpleMaterial(color: color, roughness: .init(floatLiteral: roughness), isMetallic: metallic)
        if let texture = albedoTexture(for: style) {
            // SimpleMaterial has no tint+texture color parameter; the tint is
            // applied through tintColor, which multiplies the base texture.
            material.baseColor = .texture(texture)
            material.tintColor = color
        }
        return material
    }

    private func albedoTexture(for style: SceneMaterialStyle) -> TextureResource? {
        guard let record = SceneSurfaceTextureCatalog.record(for: style) else { return nil }
        if let cached = albedoTextures[record.resourceName] { return cached }
        guard let url = Bundle.module.url(forResource: record.resourceName, withExtension: "png"),
              let texture = try? TextureResource.load(contentsOf: url) else { return nil }
        albedoTextures[record.resourceName] = texture
        return texture
    }

    private func materialParameters(for style: SceneMaterialStyle) -> (UIColor, Float, Bool) {
        switch style {
        case .ballast: return (UIColor(red: 0.37, green: 0.36, blue: 0.34, alpha: 1), 0.93, false)
        case .subBallast: return (UIColor(red: 0.31, green: 0.30, blue: 0.29, alpha: 1), 0.94, false)
        case .concrete: return (UIColor(red: 0.52, green: 0.53, blue: 0.51, alpha: 1), 0.82, false)
        case .wood: return (UIColor(red: 0.39, green: 0.29, blue: 0.20, alpha: 1), 0.80, false)
        case .darkSteel: return (UIColor(red: 0.16, green: 0.18, blue: 0.19, alpha: 1), 0.55, true)
        case .polishedRailSteel: return (UIColor(red: 0.43, green: 0.47, blue: 0.49, alpha: 1), 0.24, true)
        case .galvanizedSteel: return (UIColor(red: 0.42, green: 0.45, blue: 0.45, alpha: 1), 0.38, true)
        case .ceramicInsulator: return (UIColor(red: 0.25, green: 0.42, blue: 0.47, alpha: 1), 0.27, false)
        case .tactileAmber: return (UIColor(red: 0.93, green: 0.67, blue: 0.20, alpha: 1), 0.66, false)
        case .platformConcrete: return (UIColor(red: 0.63, green: 0.62, blue: 0.57, alpha: 1), 0.78, false)
        case .canopyMetal: return (UIColor(red: 0.18, green: 0.26, blue: 0.27, alpha: 1), 0.52, true)
        case .buildingWarm: return (UIColor(red: 0.69, green: 0.58, blue: 0.44, alpha: 1), 0.82, false)
        case .buildingCool: return (UIColor(red: 0.48, green: 0.56, blue: 0.56, alpha: 1), 0.79, false)
        case .windowGlass: return (UIColor(red: 0.12, green: 0.25, blue: 0.29, alpha: 1), 0.20, false)
        case .roadAsphalt: return (UIColor(red: 0.20, green: 0.22, blue: 0.23, alpha: 1), 0.90, false)
        case .roadPaint: return (UIColor(red: 0.83, green: 0.77, blue: 0.56, alpha: 1), 0.68, false)
        case .vehicleBlue: return (UIColor(red: 0.12, green: 0.36, blue: 0.48, alpha: 1), 0.31, false)
        case .vehicleRed: return (UIColor(red: 0.62, green: 0.23, blue: 0.16, alpha: 1), 0.32, false)
        case .vehicleSilver: return (UIColor(red: 0.63, green: 0.66, blue: 0.63, alpha: 1), 0.29, true)
        case .tireRubber: return (UIColor(red: 0.08, green: 0.09, blue: 0.10, alpha: 1), 0.91, false)
        case .foliageDeep: return (UIColor(red: 0.13, green: 0.29, blue: 0.19, alpha: 1), 0.88, false)
        case .foliageLight: return (UIColor(red: 0.27, green: 0.43, blue: 0.25, alpha: 1), 0.87, false)
        case .bark: return (UIColor(red: 0.29, green: 0.20, blue: 0.14, alpha: 1), 0.91, false)
        case .personJacket: return (UIColor(red: 0.30, green: 0.28, blue: 0.40, alpha: 1), 0.76, false)
        case .personTrousers: return (UIColor(red: 0.20, green: 0.24, blue: 0.31, alpha: 1), 0.82, false)
        case .skinTone: return (UIColor(red: 0.68, green: 0.49, blue: 0.38, alpha: 1), 0.72, false)
        case .riverWater: return (UIColor(red: 0.13, green: 0.30, blue: 0.38, alpha: 1), 0.16, false)
        case .grassSlope: return (UIColor(red: 0.24, green: 0.40, blue: 0.20, alpha: 1), 0.94, false)
        }
    }

    private func materialParameters(for style: SceneMaterialStyle, weather: SceneSurfaceWeather) -> (UIColor, Float, Bool) {
        let (baseColor, baseRoughness, metallic) = materialParameters(for: style)
        let snow = supportsSnowCover(style) ? CGFloat(weather.snowCoverage) : 0
        let wetness = CGFloat(weather.wetness)
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 1
        baseColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha)

        let wetDarkening = 1 - wetness * 0.10
        let snowTint = min(snow * 0.82, 0.82)
        let snowColor: CGFloat = 0.91
        let color = UIColor(
            red: min(max(red * wetDarkening * (1 - snowTint) + snowColor * snowTint, 0), 1),
            green: min(max(green * wetDarkening * (1 - snowTint) + snowColor * snowTint, 0), 1),
            blue: min(max(blue * wetDarkening * (1 - snowTint) + snowColor * snowTint, 0), 1),
            alpha: alpha
        )
        let dryRoughness = baseRoughness * (1 - Float(wetness) * 0.72)
        let roughness = min(max(dryRoughness * (1 - Float(snowTint)) + 0.94 * Float(snowTint), 0.04), 1)
        return (color, roughness, metallic)
    }

    private func supportsSnowCover(_ style: SceneMaterialStyle) -> Bool {
        switch style {
        case .ballast, .subBallast, .concrete, .wood, .darkSteel, .galvanizedSteel,
             .tactileAmber, .platformConcrete, .canopyMetal, .buildingWarm, .buildingCool,
             .roadAsphalt, .roadPaint, .vehicleBlue, .vehicleRed, .vehicleSilver,
             .tireRubber, .foliageDeep, .foliageLight, .bark, .grassSlope:
            return true
        case .polishedRailSteel, .ceramicInsulator, .windowGlass, .personJacket,
             .personTrousers, .skinTone, .riverWater:
            return false
        }
    }
}

private struct SceneMeshAccumulator {
        var positions: [SIMD3<Float>] = []
        var normals: [SIMD3<Float>] = []
        var textureCoordinates: [SIMD2<Float>] = []
        var indices: [UInt32] = []

    mutating func append(_ piece: ScenePiece) {
        switch piece.shape {
        case .box: appendBox(piece)
        case .cylinder: appendCylinder(piece, radialSegments: 12)
        case .sphere: appendSphere(piece, rings: 8, segments: 12)
        }
    }

    mutating func appendBox(_ piece: ScenePiece) {
        let x = Float(piece.dimensions.x * 0.5)
        let y = Float(piece.dimensions.y * 0.5)
        let z = Float(piece.dimensions.z * 0.5)
        let corners: [SIMD3<Float>] = [
            SIMD3(-x, -y, -z), SIMD3(x, -y, -z), SIMD3(x, y, -z), SIMD3(-x, y, -z),
            SIMD3(-x, -y, z), SIMD3(x, -y, z), SIMD3(x, y, z), SIMD3(-x, y, z)
        ]
        let faces: [[Int]] = [[0, 3, 2, 1], [4, 5, 6, 7], [0, 4, 7, 3],
                              [1, 2, 6, 5], [0, 1, 5, 4], [3, 7, 6, 2]]
        for face in faces {
            appendTriangle(transformed(corners[face[0]], piece), transformed(corners[face[1]], piece), transformed(corners[face[2]], piece))
            appendTriangle(transformed(corners[face[0]], piece), transformed(corners[face[2]], piece), transformed(corners[face[3]], piece))
        }
    }

    mutating func appendCylinder(_ piece: ScenePiece, radialSegments: Int) {
        let rx = Float(piece.dimensions.x * 0.5)
        let rz = Float(piece.dimensions.z * 0.5)
        let halfHeight = Float(piece.dimensions.y * 0.5)
        for segment in 0..<radialSegments {
            let a0 = Float(segment) * 2 * .pi / Float(radialSegments)
            let a1 = Float(segment + 1) * 2 * .pi / Float(radialSegments)
            let p0 = SIMD3<Float>(rx * cos(a0), -halfHeight, rz * sin(a0))
            let p1 = SIMD3<Float>(rx * cos(a1), -halfHeight, rz * sin(a1))
            let p2 = SIMD3<Float>(rx * cos(a1), halfHeight, rz * sin(a1))
            let p3 = SIMD3<Float>(rx * cos(a0), halfHeight, rz * sin(a0))
            appendTriangle(transformed(p0, piece), transformed(p2, piece), transformed(p1, piece))
            appendTriangle(transformed(p0, piece), transformed(p3, piece), transformed(p2, piece))
            appendTriangle(transformed(SIMD3<Float>(0, halfHeight, 0), piece), transformed(p2, piece), transformed(p3, piece))
            appendTriangle(transformed(SIMD3<Float>(0, -halfHeight, 0), piece), transformed(p0, piece), transformed(p1, piece))
        }
    }

    mutating func appendSphere(_ piece: ScenePiece, rings: Int, segments: Int) {
        let rx = Float(piece.dimensions.x * 0.5)
        let ry = Float(piece.dimensions.y * 0.5)
        let rz = Float(piece.dimensions.z * 0.5)
        func point(_ ring: Int, _ segment: Int) -> SIMD3<Float> {
            let latitude = -.pi / 2 + .pi * Float(ring) / Float(rings)
            let longitude = 2 * .pi * Float(segment) / Float(segments)
            return SIMD3(rx * cos(latitude) * cos(longitude), ry * sin(latitude), rz * cos(latitude) * sin(longitude))
        }
        for ring in 0..<rings {
            for segment in 0..<segments {
                let a = transformed(point(ring, segment), piece)
                let b = transformed(point(ring + 1, segment), piece)
                let c = transformed(point(ring + 1, segment + 1), piece)
                let d = transformed(point(ring, segment + 1), piece)
                appendTriangle(a, b, c)
                appendTriangle(a, c, d)
            }
        }
    }

    mutating func appendTriangle(_ a: SIMD3<Float>, _ b: SIMD3<Float>, _ c: SIMD3<Float>) {
        let cross = simd_cross(b - a, c - a)
        let normal = simd_length_squared(cross) > 1e-12 ? simd_normalize(cross) : SIMD3<Float>(0, 1, 0)
        let start = UInt32(positions.count)
        positions.append(contentsOf: [a, b, c])
        normals.append(contentsOf: [normal, normal, normal])
        textureCoordinates.append(contentsOf: [tile(a), tile(b), tile(c)])
        indices.append(contentsOf: [start, start + 1, start + 2])
    }

    private func tile(_ point: SIMD3<Float>) -> SIMD2<Float> {
        SIMD2(point.x * 0.22, point.z * 0.22)
    }

    func makeMesh() throws -> MeshResource {
        var descriptor = MeshDescriptor()
        descriptor.positions = MeshBuffers.Positions(positions)
        descriptor.normals = MeshBuffers.Normals(normals)
        descriptor.textureCoordinates = MeshBuffers.TextureCoordinates(textureCoordinates)
        descriptor.primitives = .triangles(indices)
        return try MeshResource.generate(from: [descriptor])
    }

    private func transformed(_ input: SIMD3<Float>, _ piece: ScenePiece) -> SIMD3<Float> {
        let angles = piece.localRotationRadians
        let cx = Float(cos(angles.x)), sx = Float(sin(angles.x))
        let cy = Float(cos(angles.y)), sy = Float(sin(angles.y))
        let cz = Float(cos(angles.z)), sz = Float(sin(angles.z))
        let scaled = SIMD3<Float>(input.x, input.y, input.z)
        let afterX = SIMD3(scaled.x, cx * scaled.y - sx * scaled.z, sx * scaled.y + cx * scaled.z)
        let afterY = SIMD3(cy * afterX.x + sy * afterX.z, afterX.y, -sy * afterX.x + cy * afterX.z)
        let afterZ = SIMD3(cz * afterY.x - sz * afterY.y, sz * afterY.x + cz * afterY.y, afterY.z)
        let translation = SIMD3<Float>(Float(piece.localPosition.x), Float(piece.localPosition.y), Float(piece.localPosition.z))
        // Primitive vertices are already emitted at half-extents for boxes and parametric dimensions for round meshes.
        return afterZ + translation
    }
}
#endif

/// Shared access to the bundled scenery textures so that app-side scene
/// builders can apply the same photographic surfaces as this adapter
/// instead of flat colors. Textures are loaded once and cached. Callers
/// load during scene construction on the main actor, mirroring the
/// adapter's own texture cache.
public enum SceneTextureProvider {
    private static var cache: [String: TextureResource] = [:]

    public static func texture(named name: String) -> TextureResource? {
        if let cached = cache[name] { return cached }
        guard let url = Bundle.module.url(forResource: name, withExtension: "png"),
              let texture = try? TextureResource.load(contentsOf: url) else { return nil }
        cache[name] = texture
        return texture
    }
}
