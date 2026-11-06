import Foundation
import RealityKit
import UIKit
import simd

/// X=車幅、Y=上、Z=車長。前面は-Z。寸法はメートル。
enum VehicleGeometry {
    @discardableResult
    static func box(
        _ name: String,
        size: SIMD3<Float>,
        at position: SIMD3<Float>,
        material: any Material,
        in parent: Entity
    ) -> ModelEntity {
        let entity = ModelEntity(mesh: SharedPrimitiveMeshes.box(size), materials: [material])
        entity.name = name
        entity.position = position
        parent.addChild(entity)
        return entity
    }

    @discardableResult
    static func cylinder(
        _ name: String,
        radius: Float,
        length: Float,
        at position: SIMD3<Float>,
        axis: SIMD3<Float> = SIMD3<Float>(0, 1, 0),
        material: any Material,
        in parent: Entity
    ) -> ModelEntity {
        let entity = ModelEntity(mesh: SharedPrimitiveMeshes.cylinder(radius: radius, length: length), materials: [material])
        entity.name = name
        entity.position = position
        let unitY = SIMD3<Float>(0, 1, 0)
        let normalized = simd_normalize(axis)
        if simd_dot(unitY, normalized) < -0.9999 {
            entity.orientation = simd_quatf(angle: .pi, axis: SIMD3<Float>(1, 0, 0))
        } else if simd_dot(unitY, normalized) < 0.9999 {
            entity.orientation = simd_quatf(from: unitY, to: normalized)
        }
        parent.addChild(entity)
        return entity
    }

    @discardableResult
    static func sphere(
        _ name: String,
        radius: Float,
        at position: SIMD3<Float>,
        material: any Material,
        in parent: Entity
    ) -> ModelEntity {
        let entity = ModelEntity(mesh: SharedPrimitiveMeshes.sphere(radius), materials: [material])
        entity.name = name
        entity.position = position
        parent.addChild(entity)
        return entity
    }

    @discardableResult
    static func rod(
        _ name: String,
        from start: SIMD3<Float>,
        to end: SIMD3<Float>,
        radius: Float,
        material: any Material,
        in parent: Entity
    ) -> ModelEntity {
        let delta = end - start
        let length = simd_length(delta)
        return cylinder(name, radius: radius, length: max(length, 0.001), at: (start + end) * 0.5, axis: simd_normalize(delta), material: material, in: parent)
    }

    static func group(_ name: String, in parent: Entity) -> Entity {
        let entity = Entity()
        entity.name = name
        parent.addChild(entity)
        return entity
    }
}

/// Shares immutable primitive meshes between entities with identical dimensions.
/// This lowers repeated mesh allocation; it does not reduce entity/draw-call count or replace LOD.
private enum SharedPrimitiveMeshes {
    private struct Key: Hashable {
        let shape: UInt8
        let a: UInt32
        let b: UInt32
        let c: UInt32
    }

    private static let lock = NSLock()
    private static var cache: [Key: MeshResource] = [:]

    static func box(_ size: SIMD3<Float>) -> MeshResource {
        getOrCreate(Key(shape: 0, a: size.x.bitPattern, b: size.y.bitPattern, c: size.z.bitPattern)) {
            .generateBox(size: size)
        }
    }

    static func cylinder(radius: Float, length: Float) -> MeshResource {
        getOrCreate(Key(shape: 1, a: radius.bitPattern, b: length.bitPattern, c: 0)) {
            .generateCylinder(height: length, radius: radius)
        }
    }

    static func sphere(_ radius: Float) -> MeshResource {
        getOrCreate(Key(shape: 2, a: radius.bitPattern, b: 0, c: 0)) {
            .generateSphere(radius: radius)
        }
    }

    private static func getOrCreate(_ key: Key, create: () -> MeshResource) -> MeshResource {
        lock.lock()
        defer { lock.unlock() }
        if let existing = cache[key] { return existing }
        let mesh = create()
        cache[key] = mesh
        return mesh
    }
}

enum VehicleMaterialPalette {
    static func pbr(_ color: UIColor, roughness: Float, metallic: Float = 0, emission: Float = 0) -> PhysicallyBasedMaterial {
        var material = PhysicallyBasedMaterial()
        material.baseColor = .init(tint: color)
        material.roughness = .init(floatLiteral: min(max(roughness, 0.02), 1))
        material.metallic = .init(floatLiteral: min(max(metallic, 0), 1))
        if emission > 0 {
            material.emissiveColor = .init(color: color)
            material.emissiveIntensity = emission
        }
        return material
    }

    static let body = pbr(UIColor(red: 0.79, green: 0.81, blue: 0.78, alpha: 1), roughness: 0.30, metallic: 0.72)
    static let bodyShade = pbr(UIColor(red: 0.62, green: 0.66, blue: 0.64, alpha: 1), roughness: 0.38, metallic: 0.62)
    static let accent = pbr(UIColor(red: 0.045, green: 0.30, blue: 0.32, alpha: 1), roughness: 0.28, metallic: 0.54)
    static let roof = pbr(UIColor(red: 0.20, green: 0.23, blue: 0.24, alpha: 1), roughness: 0.70, metallic: 0.30)
    static let glass: PhysicallyBasedMaterial = {
        var material = pbr(UIColor(red: 0.11, green: 0.17, blue: 0.19, alpha: 1), roughness: 0.08, metallic: 0.02)
        material.blending = .transparent(opacity: .init(floatLiteral: 0.28))
        return material
    }()
    static let glassEdge = pbr(UIColor(red: 0.045, green: 0.055, blue: 0.06, alpha: 1), roughness: 0.60, metallic: 0.30)
    static let rubber = pbr(UIColor(red: 0.055, green: 0.061, blue: 0.063, alpha: 1), roughness: 0.90)
    static let steel = pbr(UIColor(red: 0.37, green: 0.39, blue: 0.39, alpha: 1), roughness: 0.30, metallic: 0.88)
    static let darkSteel = pbr(UIColor(red: 0.105, green: 0.12, blue: 0.125, alpha: 1), roughness: 0.58, metallic: 0.82)
    static let undercoat = pbr(UIColor(red: 0.17, green: 0.18, blue: 0.18, alpha: 1), roughness: 0.76, metallic: 0.25)
    static let interior = pbr(UIColor(red: 0.16, green: 0.18, blue: 0.18, alpha: 1), roughness: 0.76, metallic: 0.12)
    static let panel = pbr(UIColor(red: 0.085, green: 0.095, blue: 0.10, alpha: 1), roughness: 0.68, metallic: 0.20)
    static let seat = pbr(UIColor(red: 0.17, green: 0.29, blue: 0.27, alpha: 1), roughness: 0.88)
    static let amber = pbr(UIColor(red: 0.92, green: 0.47, blue: 0.08, alpha: 1), roughness: 0.30, metallic: 0.22)
    static let lamp = pbr(UIColor(red: 1.0, green: 0.82, blue: 0.52, alpha: 1), roughness: 0.17, emission: 0.7)
    static let redLamp = pbr(UIColor(red: 0.91, green: 0.065, blue: 0.035, alpha: 1), roughness: 0.18, emission: 0.45)
    static let display = pbr(UIColor(red: 0.025, green: 0.105, blue: 0.09, alpha: 1), roughness: 0.20, metallic: 0.08, emission: 0.20)
    static let markings = pbr(UIColor(red: 0.80, green: 0.82, blue: 0.78, alpha: 1), roughness: 0.60)
}
