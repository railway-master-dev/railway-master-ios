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
        let entity = ModelEntity(mesh: .generateCylinder(height: length, radius: radius), materials: [material])
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

enum VehicleMaterialPalette {
    static func paint(_ color: UIColor, roughness: Float = 0.48, metallic: Bool = false) -> SimpleMaterial {
        SimpleMaterial(color: color, roughness: roughness, isMetallic: metallic)
    }

    static let body = paint(UIColor(red: 0.78, green: 0.80, blue: 0.78, alpha: 1), roughness: 0.38, metallic: true)
    static let accent = paint(UIColor(red: 0.10, green: 0.43, blue: 0.48, alpha: 1), roughness: 0.36, metallic: true)
    static let darkMetal = paint(UIColor(red: 0.16, green: 0.18, blue: 0.19, alpha: 1), roughness: 0.72, metallic: true)
    static let rubber = paint(UIColor(red: 0.075, green: 0.08, blue: 0.085, alpha: 1), roughness: 0.92)
    static let glass = paint(UIColor(red: 0.08, green: 0.16, blue: 0.20, alpha: 1), roughness: 0.16, metallic: true)
    static let trim = paint(UIColor(red: 0.75, green: 0.76, blue: 0.72, alpha: 1), roughness: 0.3, metallic: true)
    static let interior = paint(UIColor(red: 0.22, green: 0.24, blue: 0.23, alpha: 1), roughness: 0.78)
    static let seat = paint(UIColor(red: 0.20, green: 0.37, blue: 0.34, alpha: 1), roughness: 0.82)
    static let warning = paint(UIColor(red: 0.84, green: 0.56, blue: 0.12, alpha: 1), roughness: 0.5)
    static let lamp = paint(UIColor(red: 0.96, green: 0.87, blue: 0.61, alpha: 1), roughness: 0.22)
    static let tailLamp = paint(UIColor(red: 0.72, green: 0.08, blue: 0.06, alpha: 1), roughness: 0.24)
}
