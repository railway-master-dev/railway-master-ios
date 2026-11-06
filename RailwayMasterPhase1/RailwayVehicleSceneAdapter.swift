import RealityKit
import UIKit
import RailwayVehicleCab

/// Builds the vehicle once and keeps stable entity references for subsequent frame updates.
/// All train data is from the app's fictional/educational simulation model.
@MainActor
final class RailwayVehicleSceneAdapter {
    struct AuxiliaryControls {
        var reverser: Float = 0
        var horn: Float = 0
        var wiperMode: Float = 0
        var headlightsOn: Bool = true

        static let neutral = AuxiliaryControls()
    }

    let vehicle: RailwayVehicleModel
    let camera: PerspectiveCamera

    var root: Entity { vehicle.root }

    private let speedDigits: [SevenSegmentDigit]
    private let speedLimitBar: ReadoutBar
    private let brakePipeBar: ReadoutBar
    private let wheelSlipIndicator: ModelEntity
    private let emergencyBrakeIndicator: ModelEntity
    private let frontHeadlamps: [Entity]
    private let frontMarkerLamps: [Entity]
    private let rearTailLamps: [Entity]

    init(specification: VehicleSpecification = .fictionalPrototype) {
        let builtVehicle = RailwayVehicleModelBuilder.build(specification)
        vehicle = builtVehicle

        let cabCamera = PerspectiveCamera()
        cabCamera.name = "VehicleCabCamera"
        cabCamera.camera.fieldOfViewInDegrees = 70
        cabCamera.position = SIMD3<Float>(0, 1.67, -7.20)
        cabCamera.look(
            at: SIMD3<Float>(0, 1.88, -10.0),
            from: cabCamera.position,
            relativeTo: builtVehicle.root
        )
        builtVehicle.root.addChild(cabCamera)
        camera = cabCamera

        let cabDisplay = builtVehicle.groups[.cabInterior] ?? builtVehicle.root
        speedDigits = Self.makeSpeedDigits(in: cabDisplay)
        speedLimitBar = Self.makeBar(
            name: "CabSpeedLimitBar",
            center: SIMD3<Float>(-0.66, 2.055, -8.325),
            width: 0.48,
            in: cabDisplay
        )
        brakePipeBar = Self.makeBar(
            name: "CabBrakePipePressureBar",
            center: SIMD3<Float>(-0.66, 2.025, -8.325),
            width: 0.48,
            in: cabDisplay
        )
        wheelSlipIndicator = Self.makeIndicator(
            name: "CabWheelSlipIndicator",
            center: SIMD3<Float>(-0.37, 2.18, -8.325),
            color: UIColor(red: 1.0, green: 0.57, blue: 0.08, alpha: 1),
            in: cabDisplay
        )
        emergencyBrakeIndicator = Self.makeIndicator(
            name: "CabEmergencyBrakeIndicator",
            center: SIMD3<Float>(-0.37, 2.10, -8.325),
            color: UIColor(red: 0.96, green: 0.12, blue: 0.08, alpha: 1),
            in: cabDisplay
        )
        wheelSlipIndicator.isEnabled = false
        emergencyBrakeIndicator.isEnabled = false

        let lighting = builtVehicle.groups[.lighting] ?? builtVehicle.root
        frontHeadlamps = Self.findEntities(namedPrefix: "FrontHeadlampLens_", under: lighting)
        frontMarkerLamps = Self.findEntities(namedPrefix: "FrontMarkerLamp_", under: lighting)
        rearTailLamps = Self.findEntities(namedPrefix: "RearTailLamp_", under: lighting)
    }

    /// Updates controls and the cab display without replacing any RealityKit entities.
    /// TrainControls has no reverser, horn, wiper, or headlight fields, so those optional
    /// values are supplied separately and default to neutral / headlights on.
    func update(
        telemetry: TrainTelemetry,
        controls: TrainControls,
        auxiliary: AuxiliaryControls = .neutral
    ) {
        vehicle.cabControls.setValue(Float(controls.throttleNotch), for: .masterController)
        let brakeFraction = controls.emergencyBrake ? 1 : Float(controls.brakeNotch) / 7
        vehicle.cabControls.setValue(brakeFraction, for: .brakeLever)
        vehicle.cabControls.setValue(auxiliary.reverser, for: .reverser)
        vehicle.cabControls.setValue(auxiliary.horn, for: .hornButton)
        vehicle.cabControls.setValue(auxiliary.wiperMode, for: .wiperSwitch)
        vehicle.cabControls.setValue(auxiliary.headlightsOn ? 1 : 0, for: .headlightSwitch)

        let speedKmh = max(0, telemetry.speedMps * 3.6)
        Self.updateDigits(speedDigits, value: Int(speedKmh.rounded()))
        speedLimitBar.setFraction(speedKmh / max(telemetry.currentSpeedLimitKmh, 1))
        brakePipeBar.setFraction(telemetry.brakePipePressureKPa / 780)
        wheelSlipIndicator.isEnabled = telemetry.isWheelSlipActive || telemetry.isBrakeSlipActive
        emergencyBrakeIndicator.isEnabled = controls.emergencyBrake

        for lamp in frontHeadlamps { lamp.isEnabled = auxiliary.headlightsOn }
        for lamp in frontMarkerLamps { lamp.isEnabled = auxiliary.headlightsOn }
        let braking = controls.emergencyBrake || controls.brakeNotch > 0
        for lamp in rearTailLamps { lamp.isEnabled = braking }
    }

    private static func makeSpeedDigits(in parent: Entity) -> [SevenSegmentDigit] {
        let centers: [Float] = [-0.735, -0.66, -0.585]
        return centers.map { SevenSegmentDigit(center: SIMD3<Float>($0, 2.19, -8.325), in: parent) }
    }

    private static func makeBar(name: String, center: SIMD3<Float>, width: Float, in parent: Entity) -> ReadoutBar {
        let entity = ModelEntity(
            mesh: .generateBox(size: SIMD3<Float>(width, 0.012, 0.012)),
            materials: [SimpleMaterial(color: UIColor(red: 0.17, green: 0.88, blue: 0.63, alpha: 1), roughness: 0.3)]
        )
        entity.name = name
        entity.position = center
        entity.isEnabled = true
        parent.addChild(entity)
        return ReadoutBar(entity: entity, center: center, maximumWidth: width)
    }

    private static func makeIndicator(name: String, center: SIMD3<Float>, color: UIColor, in parent: Entity) -> ModelEntity {
        let entity = ModelEntity(
            mesh: .generateBox(size: SIMD3<Float>(0.035, 0.035, 0.012)),
            materials: [SimpleMaterial(color: color, roughness: 0.25)]
        )
        entity.name = name
        entity.position = center
        parent.addChild(entity)
        return entity
    }

    private static func findEntities(namedPrefix prefix: String, under root: Entity) -> [Entity] {
        var matches: [Entity] = []
        if root.name.hasPrefix(prefix) { matches.append(root) }
        for child in root.children {
            matches.append(contentsOf: findEntities(namedPrefix: prefix, under: child))
        }
        return matches
    }

    private static func updateDigits(_ digits: [SevenSegmentDigit], value: Int) {
        let bounded = min(max(value, 0), 999)
        let hundreds = bounded / 100
        let tens = (bounded / 10) % 10
        let ones = bounded % 10
        for (digit, value) in zip(digits, [hundreds, tens, ones]) {
            digit.show(value)
        }
    }
}

private struct ReadoutBar {
    let entity: ModelEntity
    let center: SIMD3<Float>
    let maximumWidth: Float

    func setFraction(_ rawValue: Double) {
        let fraction = Float(min(max(rawValue.isFinite ? rawValue : 0, 0), 1))
        entity.scale = SIMD3<Float>(max(fraction, 0.001), 1, 1)
        entity.position = SIMD3<Float>(
            center.x - maximumWidth * 0.5 + maximumWidth * fraction * 0.5,
            center.y,
            center.z
        )
    }
}

private struct SevenSegmentDigit {
    private enum Segment: Int, CaseIterable {
        case top, upperLeft, upperRight, middle, lowerLeft, lowerRight, bottom
    }

    private static let activeSegments: [Int: Set<Segment>] = [
        0: [.top, .upperLeft, .upperRight, .lowerLeft, .lowerRight, .bottom],
        1: [.upperRight, .lowerRight],
        2: [.top, .upperRight, .middle, .lowerLeft, .bottom],
        3: [.top, .upperRight, .middle, .lowerRight, .bottom],
        4: [.upperLeft, .upperRight, .middle, .lowerRight],
        5: [.top, .upperLeft, .middle, .lowerRight, .bottom],
        6: [.top, .upperLeft, .middle, .lowerLeft, .lowerRight, .bottom],
        7: [.top, .upperRight, .lowerRight],
        8: Set(Segment.allCases),
        9: [.top, .upperLeft, .upperRight, .middle, .lowerRight, .bottom]
    ]

    private let entities: [Segment: ModelEntity]

    init(center: SIMD3<Float>, in parent: Entity) {
        let width: Float = 0.058
        let height: Float = 0.105
        let thickness: Float = 0.008
        let half = height * 0.5
        let verticalLength = half - thickness * 0.75
        let positions: [Segment: (SIMD3<Float>, SIMD3<Float>)] = [
            .top: (SIMD3(0, half, 0), SIMD3(width, thickness, 0.012)),
            .upperLeft: (SIMD3(-width * 0.5 + thickness * 0.5, verticalLength * 0.5 + thickness * 0.15, 0), SIMD3(thickness, verticalLength, 0.012)),
            .upperRight: (SIMD3(width * 0.5 - thickness * 0.5, verticalLength * 0.5 + thickness * 0.15, 0), SIMD3(thickness, verticalLength, 0.012)),
            .middle: (SIMD3(0, 0, 0), SIMD3(width, thickness, 0.012)),
            .lowerLeft: (SIMD3(-width * 0.5 + thickness * 0.5, -verticalLength * 0.5 - thickness * 0.15, 0), SIMD3(thickness, verticalLength, 0.012)),
            .lowerRight: (SIMD3(width * 0.5 - thickness * 0.5, -verticalLength * 0.5 - thickness * 0.15, 0), SIMD3(thickness, verticalLength, 0.012)),
            .bottom: (SIMD3(0, -half, 0), SIMD3(width, thickness, 0.012))
        ]
        let material = SimpleMaterial(color: UIColor(red: 1.0, green: 0.73, blue: 0.24, alpha: 1), roughness: 0.25)
        var created: [Segment: ModelEntity] = [:]
        for segment in Segment.allCases {
            guard let (offset, size) = positions[segment] else { continue }
            let entity = ModelEntity(mesh: .generateBox(size: size), materials: [material])
            entity.name = "CabSpeedDigitSegment_\(segment.rawValue)_\(Int(center.x * 1000))"
            entity.position = center + offset
            entity.isEnabled = false
            parent.addChild(entity)
            created[segment] = entity
        }
        entities = created
    }

    func show(_ digit: Int) {
        let active = Self.activeSegments[min(max(digit, 0), 9)] ?? []
        for segment in Segment.allCases {
            entities[segment]?.isEnabled = active.contains(segment)
        }
    }
}
