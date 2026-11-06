import RealityKit
import simd

public enum VehicleCabControlKind: String, Codable, Hashable, Sendable {
    case masterController
    case brakeLever
    case reverser
    case hornButton
    case wiperSwitch
    case headlightSwitch
}

public enum VehicleCabControlMotion: String, Codable, Sendable {
    case rotation
    case translation
}

/// 操作ノードの識別子・値域・動かし方を保持するRealityKitコンポーネント。
public struct VehicleCabControlComponent: Component {
    public var kind: VehicleCabControlKind
    public var motion: VehicleCabControlMotion
    public var axis: SIMD3<Float>
    public var minimumValue: Float
    public var maximumValue: Float
    public var neutralValue: Float
    public var motionScale: Float
    public var value: Float

    public init(
        kind: VehicleCabControlKind,
        motion: VehicleCabControlMotion,
        axis: SIMD3<Float>,
        minimumValue: Float,
        maximumValue: Float,
        neutralValue: Float,
        motionScale: Float,
        value: Float
    ) {
        self.kind = kind
        self.motion = motion
        self.axis = axis
        self.minimumValue = minimumValue
        self.maximumValue = maximumValue
        self.neutralValue = neutralValue
        self.motionScale = motionScale
        self.value = value
    }
}

/// 運転状態をノード変換へ反映するアダプター。呼出側が入力値を渡して更新する。
public final class VehicleCabControlRig {
    public let nodes: [VehicleCabControlKind: ModelEntity]
    private let initialTransforms: [VehicleCabControlKind: Transform]

    init(nodes: [VehicleCabControlKind: ModelEntity]) {
        self.nodes = nodes
        self.initialTransforms = nodes.mapValues { $0.transform }
    }

    public func setValue(_ rawValue: Float, for kind: VehicleCabControlKind) {
        guard let node = nodes[kind],
              var component = node.components[VehicleCabControlComponent.self],
              let initial = initialTransforms[kind] else { return }
        let value = min(max(rawValue, component.minimumValue), component.maximumValue)
        let delta = value - component.neutralValue
        var transform = initial
        let axis = simd_normalize(component.axis)
        switch component.motion {
        case .rotation:
            transform.rotation = simd_mul(initial.rotation, simd_quatf(angle: delta * component.motionScale, axis: axis))
        case .translation:
            transform.translation = initial.translation + axis * (delta * component.motionScale)
        }
        node.transform = transform
        component.value = value
        node.components[VehicleCabControlComponent.self] = component
    }

    public func value(for kind: VehicleCabControlKind) -> Float? {
        nodes[kind]?.components[VehicleCabControlComponent.self]?.value
    }
}
