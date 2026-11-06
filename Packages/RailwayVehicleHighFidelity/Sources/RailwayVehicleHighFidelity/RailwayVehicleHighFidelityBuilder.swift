import RailwayAudioEnhancements
import RealityKit
import UIKit
import simd

public struct RailwayVehicleHighFidelityModel {
    public let root: Entity
    public let parts: [HighFidelityVehiclePart: Entity]
    public let controls: VehicleCabControlRig
    public let animatedParts: VehicleAnimatedParts
    public let specification: RailwayVehicleHighFidelitySpecification
}

public enum RailwayVehicleHighFidelityBuilder {
    /// Original, fictional, dimension-scaled commuter-car geometry. Attach `root` under a scene anchor.
    public static func build(
        _ specification: RailwayVehicleHighFidelitySpecification = .fictionalPrototype,
        desk: FictionalCabDesk = FictionalCabAndSoundCatalog.fieldChopper
    ) -> RailwayVehicleHighFidelityModel {
        let root = Entity()
        root.name = specification.identifier
        root.scale = specification.modelScale

        var parts: [HighFidelityVehiclePart: Entity] = [:]
        for part in HighFidelityVehiclePart.allCases {
            let entity = Entity()
            entity.name = "VehiclePart_\(part.rawValue)"
            root.addChild(entity)
            parts[part] = entity
        }
        guard let body = parts[.body], let glazing = parts[.glazing], let doors = parts[.doors],
              let bogies = parts[.bogies], let underfloor = parts[.underfloorEquipment],
              let roof = parts[.roofEquipment], let pantographPart = parts[.pantograph],
              let lighting = parts[.lighting], let cab = parts[.cabStructure],
              let instruments = parts[.cabInstruments], let controlPanel = parts[.cabControls],
              let wipers = parts[.windshieldWipers] else {
            preconditionFailure("High-fidelity vehicle group construction failed")
        }

        VehicleExteriorBuilder.buildBody(in: body)
        VehicleExteriorBuilder.buildGlazing(in: glazing)
        let doorHandles = VehicleExteriorBuilder.buildDoors(in: doors)
        let bogieHandles = VehicleExteriorBuilder.buildBogie(in: bogies, detail: specification.detailLevel)
        VehicleExteriorBuilder.buildUnderfloor(in: underfloor, detail: specification.detailLevel)
        VehicleExteriorBuilder.buildRoof(in: roof, detail: specification.detailLevel)
        let pantograph = VehicleExteriorBuilder.buildPantograph(in: pantographPart)
        VehicleExteriorBuilder.buildLighting(in: lighting)
        let wiperHandles = VehicleExteriorBuilder.buildWipers(in: wipers)
        let gaugeNeedles = VehicleCabBuilder.buildCab(in: cab, instruments: instruments, desk: desk)
        let controls = VehicleCabBuilder.buildControls(in: controlPanel, desk: desk)
        let animatedParts = VehicleAnimatedParts(
            doorLeaves: doorHandles,
            wheels: bogieHandles.wheels,
            bogies: bogieHandles.bogies,
            wipers: wiperHandles,
            pantograph: pantograph.movingAssembly,
            pantographBaseY: pantograph.baseY,
            gaugeNeedles: gaugeNeedles,
            lighting: lighting,
            instrumentCluster: instruments
        )
        return RailwayVehicleHighFidelityModel(root: root, parts: parts, controls: controls, animatedParts: animatedParts, specification: specification)
    }
}

public final class VehicleCabControlRig {
    public let nodes: [CabControlKind: ModelEntity]
    private let ranges: [CabControlKind: CabControlRange]
    private var values: [CabControlKind: Float]

    init(nodes: [CabControlKind: ModelEntity], ranges: [CabControlKind: CabControlRange]) {
        self.nodes = nodes
        self.ranges = ranges
        self.values = Dictionary(uniqueKeysWithValues: ranges.map { ($0.key, $0.value.neutral) })
    }

    public func value(for kind: CabControlKind) -> Float { values[kind] ?? 0 }

    @discardableResult
    public func setValue(_ rawValue: Float, for kind: CabControlKind) -> Float {
        guard let range = ranges[kind], let entity = nodes[kind] else { return 0 }
        let safe = rawValue.isFinite ? rawValue : range.neutral
        let value = min(max(safe, range.minimum), range.maximum)
        values[kind] = value
        let denominator = max(range.maximum - range.minimum, 0.0001)
        let normalized = (value - range.minimum) / denominator
        let neutralNormalized = (range.neutral - range.minimum) / denominator
        let travel = (normalized - neutralNormalized) * range.maximumTravelRadians
        if range.rotates {
            entity.orientation = simd_quatf(angle: travel, axis: SIMD3<Float>(0, 0, 1))
        } else {
            entity.position.y = entity.components[VehicleControlHomeComponent.self]?.homeY ?? entity.position.y
            entity.position.y -= travel * 0.018
        }
        return value
    }
}

public struct VehicleControlHomeComponent: Component {
    public var homeY: Float
    public init(homeY: Float) { self.homeY = homeY }
}

public final class VehicleAnimatedParts {
    private let doorLeaves: [DoorLeafHandle]
    private let wheels: [WheelHandle]
    private let bogies: [BogieHandle]
    private let wipers: [WiperHandle]
    private let pantograph: Entity
    private let pantographBaseY: Float
    private let gaugeNeedles: [String: Entity]
    private let lamps: [Entity]
    private let indicatorLenses: [String: Entity]
    private var wheelTravelDistance: Float = 0

    init(doorLeaves: [DoorLeafHandle], wheels: [WheelHandle], bogies: [BogieHandle], wipers: [WiperHandle], pantograph: Entity, pantographBaseY: Float, gaugeNeedles: [String: Entity], lighting: Entity, instrumentCluster: Entity) {
        self.doorLeaves = doorLeaves
        self.wheels = wheels
        self.bogies = bogies
        self.wipers = wipers
        self.pantograph = pantograph
        self.pantographBaseY = pantographBaseY
        self.gaugeNeedles = gaugeNeedles
        self.lamps = Self.find(namedPrefix: "FrontHeadlamp_", under: lighting) + Self.find(namedPrefix: "FrontMarkerLamp_", under: lighting)
        let indicatorNames = ["ATSP", "ATC", "EB", "DOOR", "POWER", "REGEN", "FAULT"]
        self.indicatorLenses = Dictionary(uniqueKeysWithValues: indicatorNames.compactMap { name in
            Self.find(namedPrefix: "IndicatorLens_\(name)", under: instrumentCluster).first.map { (name, $0) }
        })
        self.indicatorLenses.values.forEach { $0.isEnabled = false }
    }

    /// Door fraction 0 is closed, 1 is fully open; this is a visual animation hook only.
    public func setDoorOpenFraction(_ rawFraction: Float) {
        let fraction = Self.unit(rawFraction)
        for leaf in doorLeaves {
            leaf.entity.position.z = leaf.closedZ + leaf.direction * 0.38 * fraction
        }
    }

    /// Rotates both wipers across their visible screen; use a bounded angle in radians.
    public func setWiperSweep(_ radians: Float) {
        let angle = min(max(radians.isFinite ? radians : 0, -0.8), 0.8)
        for handle in wipers {
            handle.pivot.orientation = simd_quatf(angle: angle * handle.side, axis: SIMD3<Float>(0, 0, 1))
        }
    }

    /// Drives the visual wipers from simulation time; this is not a weather sensor or real wiper control.
    public func setWiperState(_ mode: VehicleWiperMode, simulationTimeSeconds: Double) {
        let time = simulationTimeSeconds.isFinite ? max(simulationTimeSeconds, 0) : 0
        let angle: Float
        switch mode {
        case .off:
            angle = 0
        case .intermittent:
            let phase = time.truncatingRemainder(dividingBy: 3.2)
            angle = phase < 0.55 ? Float(sin(.pi * phase / 0.55) * 0.68) : 0
        case .low:
            angle = Float(sin(time * 2 * .pi * 0.72) * 0.42)
        case .high:
            angle = Float(sin(time * 2 * .pi * 1.15) * 0.72)
        }
        setWiperSweep(angle)
    }

    /// Turns each bogie toward its local route tangent. Angles are presentation-only and bounded.
    public func setBogieYaw(frontRadians: Float, rearRadians: Float) {
        let angles = [frontRadians, rearRadians]
        for (bogie, rawAngle) in zip(bogies, angles) {
            let angle = min(max(rawAngle.isFinite ? rawAngle : 0, -0.35), 0.35)
            bogie.entity.orientation = simd_quatf(angle: angle, axis: SIMD3<Float>(0, 1, 0))
        }
    }

    /// Approximate collector extension for visual state feedback, not electrical simulation.
    public func setPantographExtension(_ rawFraction: Float) {
        let fraction = Self.unit(rawFraction)
        pantograph.position.y = pantographBaseY + 0.48 * fraction
        pantograph.scale = SIMD3<Float>(1, 0.20 + 0.80 * fraction, 1)
    }

    /// Applies accumulated distance to wheel rotation; distance is in metres.
    public func advanceWheels(distanceMeters: Float) {
        guard distanceMeters.isFinite else { return }
        wheelTravelDistance += distanceMeters
        for wheel in wheels {
            let angle = wheelTravelDistance / max(wheel.radius, 0.001)
            wheel.entity.orientation = simd_quatf(angle: angle, axis: SIMD3<Float>(1, 0, 0)) * wheel.baseOrientation
        }
    }

    /// Updates the two cab needles from simulation telemetry. Units are km/h and kPa.
    public func setTelemetry(speedKmh: Double, brakePipePressureKPa: Double) {
        if let speed = gaugeNeedles["speed"] {
            let ratio = Self.unit(Double(speedKmh.isFinite ? speedKmh : 0) / 160)
            speed.orientation = simd_quatf(angle: Float((-0.72 + ratio * 1.44) * .pi), axis: SIMD3<Float>(0, 0, 1))
        }
        if let pressure = gaugeNeedles["pressure"] {
            let ratio = Self.unit(Double(brakePipePressureKPa.isFinite ? brakePipePressureKPa : 0) / 800)
            pressure.orientation = simd_quatf(angle: Float((-0.72 + ratio * 1.44) * .pi), axis: SIMD3<Float>(0, 0, 1))
        }
    }

    public func setHeadlightsEnabled(_ enabled: Bool) {
        for lamp in lamps { lamp.isEnabled = enabled }
    }

    /// Updates visual-only annunciator lenses from host-owned fictional simulator state.
    public func setCabIndicatorState(_ state: VehicleCabIndicatorState) {
        let active: [String: Bool] = [
            "ATSP": state.atspActive,
            "ATC": state.atcActive,
            "EB": state.emergencyBrakeActive,
            "DOOR": state.doorsOpen,
            "POWER": state.tractionPowerActive,
            "REGEN": state.regenerativeBrakingActive,
            "FAULT": state.faultActive
        ]
        for (name, lens) in indicatorLenses {
            lens.isEnabled = active[name] ?? false
        }
    }

    private static func unit(_ value: Float) -> Float {
        value.isFinite ? min(max(value, 0), 1) : 0
    }

    private static func unit(_ value: Double) -> Double {
        value.isFinite ? min(max(value, 0), 1) : 0
    }

    private static func find(namedPrefix prefix: String, under root: Entity) -> [Entity] {
        var found: [Entity] = []
        if root.name.hasPrefix(prefix) { found.append(root) }
        for child in root.children { found.append(contentsOf: find(namedPrefix: prefix, under: child)) }
        return found
    }
}
