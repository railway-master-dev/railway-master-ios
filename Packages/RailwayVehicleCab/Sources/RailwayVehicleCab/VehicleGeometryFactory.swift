import RealityKit
import UIKit
import simd

/// シンプルな低ポリゴン部品を組む内部ヘルパー。単位はメートル、Yが上、Zが車両長手方向。
enum VehicleGeometryFactory {
    @discardableResult
    static func box(
        _ name: String,
        size: SIMD3<Float>,
        at position: SIMD3<Float>,
        material: SimpleMaterial,
        in parent: Entity
    ) -> ModelEntity {
        let entity = ModelEntity(mesh: .generateBox(size: size), materials: [material])
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
        axis: SIMD3<Float> = SIMD3(0, 1, 0),
        material: SimpleMaterial,
        in parent: Entity
    ) -> ModelEntity {
        let mesh: MeshResource
        if #available(iOS 18.0, *) {
            mesh = .generateCylinder(height: length, radius: radius)
        } else {
            mesh = FallbackCylinderMesh.make(height: length, radius: radius)
        }
        let entity = ModelEntity(mesh: mesh, materials: [material])
        entity.name = name
        entity.position = position
        let yAxis = SIMD3<Float>(0, 1, 0)
        let normalizedAxis = simd_normalize(axis)
        let dot = simd_dot(yAxis, normalizedAxis)
        if dot < -0.9999 {
            entity.orientation = simd_quatf(angle: .pi, axis: SIMD3(1, 0, 0))
        } else if dot < 0.9999 {
            entity.orientation = simd_quatf(from: yAxis, to: normalizedAxis)
        }
        parent.addChild(entity)
        return entity
    }

    @discardableResult
    static func sphere(
        _ name: String,
        radius: Float,
        at position: SIMD3<Float>,
        material: SimpleMaterial,
        in parent: Entity
    ) -> ModelEntity {
        let entity = ModelEntity(mesh: .generateSphere(radius: radius), materials: [material])
        entity.name = name
        entity.position = position
        parent.addChild(entity)
        return entity
    }

    static func group(_ name: String, kind: VehiclePartGroup) -> Entity {
        let entity = Entity()
        entity.name = name
        entity.components[VehiclePartGroupComponent.self] = VehiclePartGroupComponent(group: kind)
        return entity
    }
}

/// Cylinder mesh built with a MeshDescriptor for iOS 17, where
/// `MeshResource.generateCylinder(height:radius:)` is unavailable.
/// Matches generateCylinder's placement: height along the Y axis, centered at the origin.
enum FallbackCylinderMesh {
    static func make(height: Float, radius: Float, radialSegments: Int = 24) -> MeshResource {
        let halfHeight = height / 2
        var positions: [SIMD3<Float>] = []
        var normals: [SIMD3<Float>] = []
        var indices: [UInt32] = []

        // Side wall with smooth radial normals.
        for step in 0...radialSegments {
            let theta = Float(step) / Float(radialSegments) * 2 * .pi
            let direction = SIMD3<Float>(cos(theta), 0, sin(theta))
            positions.append(SIMD3<Float>(direction.x * radius, -halfHeight, direction.z * radius))
            normals.append(direction)
            positions.append(SIMD3<Float>(direction.x * radius, halfHeight, direction.z * radius))
            normals.append(direction)
        }
        for step in 0..<radialSegments {
            let bottom0 = UInt32(step * 2)
            let top0 = bottom0 + 1
            let bottom1 = bottom0 + 2
            let top1 = bottom0 + 3
            indices.append(contentsOf: [bottom0, top0, bottom1, top0, top1, bottom1])
        }

        // End caps with flat normals: one center vertex plus a dedicated ring each.
        for (sign, y) in [(Float(1), halfHeight), (Float(-1), -halfHeight)] {
            let centerIndex = UInt32(positions.count)
            positions.append(SIMD3<Float>(0, y, 0))
            normals.append(SIMD3<Float>(0, sign, 0))
            let ringStart = UInt32(positions.count)
            for step in 0...radialSegments {
                let theta = Float(step) / Float(radialSegments) * 2 * .pi
                positions.append(SIMD3<Float>(radius * cos(theta), y, radius * sin(theta)))
                normals.append(SIMD3<Float>(0, sign, 0))
            }
            for step in 0..<radialSegments {
                let a = ringStart + UInt32(step)
                let b = a + 1
                if sign > 0 {
                    indices.append(contentsOf: [centerIndex, b, a])
                } else {
                    indices.append(contentsOf: [centerIndex, a, b])
                }
            }
        }

        var descriptor = MeshDescriptor(name: "fallback-cylinder")
        descriptor.positions = MeshBuffers.Positions(positions)
        descriptor.normals = MeshBuffers.Normals(normals)
        descriptor.primitives = .triangles(indices)
        // The descriptor is built entirely from the values above, so generation cannot fail.
        return try! MeshResource.generate(from: [descriptor])
    }
}

enum VehicleMaterialPalette {
    static func paint(_ color: UIColor, roughness: Float = 0.48, metallic: Bool = false) -> SimpleMaterial {
        SimpleMaterial(color: color, roughness: .init(floatLiteral: roughness), isMetallic: metallic)
    }

    static let body = paint(UIColor(red: 0.78, green: 0.80, blue: 0.78, alpha: 1), roughness: 0.38, metallic: true)
    static let accent = paint(UIColor(red: 0.10, green: 0.43, blue: 0.48, alpha: 1), roughness: 0.36, metallic: true)
    static let darkMetal = paint(UIColor(red: 0.16, green: 0.18, blue: 0.19, alpha: 1), roughness: 0.72, metallic: true)
    static let rubber = paint(UIColor(red: 0.075, green: 0.08, blue: 0.085, alpha: 1), roughness: 0.92)
    static let glass = paint(UIColor(red: 0.08, green: 0.16, blue: 0.20, alpha: 1), roughness: 0.16, metallic: true)
    /// Front windshield only: a real transparency so the driver can
    /// actually see the line through it.
    static let cabGlass = paint(UIColor(red: 0.35, green: 0.50, blue: 0.55, alpha: 0.30), roughness: 0.08, metallic: false)
    static let trim = paint(UIColor(red: 0.75, green: 0.76, blue: 0.72, alpha: 1), roughness: 0.3, metallic: true)
    static let interior = paint(UIColor(red: 0.22, green: 0.24, blue: 0.23, alpha: 1), roughness: 0.78)
    static let seat = paint(UIColor(red: 0.20, green: 0.37, blue: 0.34, alpha: 1), roughness: 0.82)
    static let warning = paint(UIColor(red: 0.84, green: 0.56, blue: 0.12, alpha: 1), roughness: 0.5)
    static let lamp = paint(UIColor(red: 0.96, green: 0.87, blue: 0.61, alpha: 1), roughness: 0.22)
    static let tailLamp = paint(UIColor(red: 0.72, green: 0.08, blue: 0.06, alpha: 1), roughness: 0.24)
}
