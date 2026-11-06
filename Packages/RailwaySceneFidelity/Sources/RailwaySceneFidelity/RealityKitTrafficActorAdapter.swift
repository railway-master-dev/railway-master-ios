#if canImport(RealityKit) && canImport(UIKit)
import RealityKit
import UIKit
import simd

/// Optional visual adapter. It never advances time: every transform and limb/wheel pose comes from a sampled simulation frame.
@MainActor
public final class RailwayTrafficActorRealityKitAdapter {
    public let root = Entity()

    private var entities: [String: Entity] = [:]
    private var roadWheels: [String: [Entity]] = [:]
    private var passengerLegs: [String: (left: Entity, right: Entity)] = [:]

    public init() {
        root.name = "RailwayTrafficActors-SnapshotDriven"
    }

    /// Updates existing actors in place, creates only new stable IDs, and disables absent IDs rather than destroying them.
    /// This keeps entity identity through pause, save/restore, temporary culling, and replay of the same scenario.
    public func update(poses: [SceneTrafficActorPose]) {
        let presentIDs = Set(poses.map(\.id))
        for (id, entity) in entities {
            entity.isEnabled = presentIDs.contains(id)
        }

        for pose in poses {
            let entity: Entity
            if let existing = entities[pose.id] {
                entity = existing
            } else {
                let created = makeActor(for: pose)
                entities[pose.id] = created
                root.addChild(created)
                entity = created
            }

            entity.position = SIMD3<Float>(Float(pose.position.x), Float(pose.position.y), Float(pose.position.z))
            let x = SIMD3<Float>(Float(pose.right.x), Float(pose.right.y), Float(pose.right.z))
            let y = SIMD3<Float>(Float(pose.up.x), Float(pose.up.y), Float(pose.up.z))
            let z = SIMD3<Float>(Float(pose.forward.x), Float(pose.forward.y), Float(pose.forward.z))
            entity.orientation = simd_quatf(simd_float3x3(columns: (x, y, z)))
            entity.isEnabled = pose.isVisible

            if pose.kind == .roadVehicle {
                let angle = Float(pose.wheelRotationRadians)
                for (index, wheel) in (roadWheels[pose.id] ?? []).enumerated() {
                    let sign: Float = index < 2 ? 1 : -1
                    wheel.orientation = simd_quatf(angle: angle * sign, axis: SIMD3<Float>(1, 0, 0))
                }
            }
            if pose.kind == .platformPassenger, let legs = passengerLegs[pose.id] {
                let swing = pose.isWalking ? sin(Float(pose.walkCycleRadians)) * 0.38 : 0
                legs.left.orientation = simd_quatf(angle: swing, axis: SIMD3<Float>(1, 0, 0))
                legs.right.orientation = simd_quatf(angle: -swing, axis: SIMD3<Float>(1, 0, 0))
            }
        }
    }

    private func makeActor(for pose: SceneTrafficActorPose) -> Entity {
        let actor = Entity()
        actor.name = "traffic-actor-\(pose.id)"
        switch pose.kind {
        case .train:
            makeTrain(in: actor, lengthM: pose.lengthM, seed: pose.id)
        case .roadVehicle:
            roadWheels[pose.id] = makeRoadVehicle(in: actor, seed: pose.id)
        case .platformPassenger:
            passengerLegs[pose.id] = makePassenger(in: actor, seed: pose.id)
        }
        return actor
    }

    private func makeTrain(in parent: Entity, lengthM: Double, seed: String) {
        let totalLength = Float(min(max(lengthM, 8), 240))
        let coachLength: Float = 19
        let coachCount = min(12, max(1, Int(ceil(totalLength / coachLength))))
        let spacing = totalLength / Float(coachCount)
        let body = material(for: seed, palette: [
            UIColor(red: 0.78, green: 0.81, blue: 0.78, alpha: 1),
            UIColor(red: 0.72, green: 0.78, blue: 0.80, alpha: 1),
            UIColor(red: 0.84, green: 0.82, blue: 0.74, alpha: 1)
        ])
        let stripe = material(for: seed + "-stripe", palette: [
            UIColor(red: 0.10, green: 0.48, blue: 0.57, alpha: 1),
            UIColor(red: 0.69, green: 0.34, blue: 0.20, alpha: 1),
            UIColor(red: 0.32, green: 0.40, blue: 0.65, alpha: 1)
        ])
        let glass = SimpleMaterial(color: UIColor(red: 0.11, green: 0.23, blue: 0.27, alpha: 1), roughness: 0.22, isMetallic: false)
        for index in 0..<coachCount {
            let centerZ = -totalLength * 0.5 + (Float(index) + 0.5) * spacing
            addBox(parent, name: "coach-body-\(index)", size: SIMD3(2.85, 3.15, max(8, spacing - 0.45)),
                   position: SIMD3(0, 1.78, centerZ), material: body)
            addBox(parent, name: "coach-livery-\(index)", size: SIMD3(2.89, 0.30, max(8, spacing - 0.40)),
                   position: SIMD3(0, 1.78, centerZ), material: stripe)
            addBox(parent, name: "coach-roof-\(index)", size: SIMD3(2.55, 0.18, max(7.5, spacing - 0.9)),
                   position: SIMD3(0, 3.42, centerZ), material: steelMaterial)
            for side: Float in [-1, 1] {
                addBox(parent, name: "coach-window-\(index)-\(Int(side))",
                       size: SIMD3(0.035, 0.62, max(4, spacing * 0.62)),
                       position: SIMD3(side * 1.44, 2.45, centerZ), material: glass)
            }
        }
    }

    @discardableResult
    private func makeRoadVehicle(in parent: Entity, seed: String) -> [Entity] {
        let paint = material(for: seed, palette: [
            UIColor(red: 0.65, green: 0.25, blue: 0.18, alpha: 1),
            UIColor(red: 0.15, green: 0.36, blue: 0.49, alpha: 1),
            UIColor(red: 0.63, green: 0.65, blue: 0.62, alpha: 1)
        ])
        let glass = SimpleMaterial(color: UIColor(red: 0.12, green: 0.24, blue: 0.28, alpha: 1), roughness: 0.2, isMetallic: false)
        let rubber = SimpleMaterial(color: UIColor(white: 0.075, alpha: 1), roughness: 0.9, isMetallic: false)
        addBox(parent, name: "car-body", size: SIMD3(1.78, 0.58, 4.05), position: SIMD3(0, 0.52, 0), material: paint)
        addBox(parent, name: "car-cabin", size: SIMD3(1.45, 0.52, 2.0), position: SIMD3(0, 1.04, 0.10), material: glass)
        var wheels: [Entity] = []
        for x: Float in [-0.79, 0.79] {
            for z: Float in [-1.25, 1.25] {
                let pivot = Entity()
                pivot.position = SIMD3(x, 0.23, z)
                let model = ModelEntity(mesh: .generateBox(size: SIMD3(0.18, 0.44, 0.44)), materials: [rubber])
                pivot.addChild(model)
                parent.addChild(pivot)
                wheels.append(pivot)
            }
        }
        return wheels
    }

    private func makePassenger(in parent: Entity, seed: String) -> (left: Entity, right: Entity) {
        let jacket = material(for: seed, palette: [
            UIColor(red: 0.23, green: 0.38, blue: 0.52, alpha: 1),
            UIColor(red: 0.51, green: 0.25, blue: 0.22, alpha: 1),
            UIColor(red: 0.28, green: 0.42, blue: 0.31, alpha: 1)
        ])
        let trousers = SimpleMaterial(color: UIColor(red: 0.18, green: 0.21, blue: 0.27, alpha: 1), roughness: 0.86, isMetallic: false)
        let skin = SimpleMaterial(color: UIColor(red: 0.67, green: 0.47, blue: 0.35, alpha: 1), roughness: 0.78, isMetallic: false)
        addBox(parent, name: "person-torso", size: SIMD3(0.40, 0.70, 0.24), position: SIMD3(0, 0.96, 0), material: jacket)
        let head = ModelEntity(mesh: .generateSphere(radius: 0.15), materials: [skin])
        head.position = SIMD3(0, 1.43, 0)
        parent.addChild(head)
        func leg(_ name: String, x: Float) -> Entity {
            let pivot = Entity()
            pivot.name = name
            pivot.position = SIMD3(x, 0.59, 0)
            let model = ModelEntity(mesh: .generateBox(size: SIMD3(0.15, 0.52, 0.18)), materials: [trousers])
            model.position = SIMD3(0, -0.26, 0)
            pivot.addChild(model)
            parent.addChild(pivot)
            return pivot
        }
        return (leg("left-leg", x: -0.11), leg("right-leg", x: 0.11))
    }

    private func addBox(
        _ parent: Entity,
        name: String,
        size: SIMD3<Float>,
        position: SIMD3<Float>,
        material: SimpleMaterial
    ) {
        let model = ModelEntity(mesh: .generateBox(size: size), materials: [material])
        model.name = name
        model.position = position
        parent.addChild(model)
    }

    private func material(for key: String, palette: [UIColor]) -> SimpleMaterial {
        SimpleMaterial(color: palette[stableIndex(key, count: palette.count)], roughness: 0.48, isMetallic: false)
    }

    private func stableIndex(_ key: String, count: Int) -> Int {
        guard count > 0 else { return 0 }
        let hash = key.utf8.reduce(UInt64(14_695_981_039_346_656_037)) { value, byte in
            (value ^ UInt64(byte)) &* 1_099_511_628_211
        }
        return Int(hash % UInt64(count))
    }

    private var steelMaterial: SimpleMaterial {
        SimpleMaterial(color: UIColor(red: 0.29, green: 0.31, blue: 0.32, alpha: 1), roughness: 0.46, isMetallic: true)
    }
}
#endif
