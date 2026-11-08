import RealityKit
import UIKit
import simd
import RailwayAudioEnhancements
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

    private let speedNeedle: Entity?
    private let mainReservoirNeedle: Entity?
    private let brakePipeNeedle: Entity?
    private let brakeCylinderNeedle: Entity?
    private let slipLamp: Entity?
    private let emergencyLamp: Entity?
    private let frontHeadlamps: [Entity]
    private let frontMarkerLamps: [Entity]
    private let rearTailLamps: [Entity]

    init(specification: VehicleSpecification = .fictionalPrototype) {
        // Matches the scene: the player's cab is the E231 early
        // analog desk (one-handle, white-face gauges).
        let builtVehicle = RailwayVehicleModelBuilder.build(specification, desk: FictionalCabAndSoundCatalog.e231Early)
        vehicle = builtVehicle

        let cabCamera = PerspectiveCamera()
        cabCamera.name = "VehicleCabCamera"
        cabCamera.camera.fieldOfViewInDegrees = 70
        cabCamera.position = SIMD3<Float>(-0.35, 1.67, -7.20)
        cabCamera.look(
            at: SIMD3<Float>(-0.35, 1.88, -10.0),
            from: cabCamera.position,
            relativeTo: builtVehicle.root
        )
        builtVehicle.root.addChild(cabCamera)
        camera = cabCamera

        // Analog cab instruments: the builder creates the gauge faces
        // and needle pivots; this adapter drives the needles from live
        // telemetry every frame. Gauges a desk variant lacks simply
        // stay unwired.
        let cabDisplay = builtVehicle.groups[.cabInterior] ?? builtVehicle.root
        speedNeedle = Self.findEntity(named: "GaugeNeedle_speed", under: cabDisplay)
        mainReservoirNeedle = Self.findEntity(named: "GaugeNeedle_mr", under: cabDisplay)
        brakePipeNeedle = Self.findEntity(named: "GaugeNeedle_bp", under: cabDisplay)
        brakeCylinderNeedle = Self.findEntity(named: "GaugeNeedle_bc", under: cabDisplay)
        slipLamp = Self.findEntity(named: "CabLampLit_slip", under: cabDisplay)
        emergencyLamp = Self.findEntity(named: "CabLampLit_emergency", under: cabDisplay)
        slipLamp?.isEnabled = false
        emergencyLamp?.isEnabled = false

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
        // One-handle desk: the master value spans -7 (full brake)
        // through neutral to +5 (full power).
        let combined: Float
        if controls.emergencyBrake {
            combined = -7
        } else if controls.throttleNotch > 0 {
            combined = Float(controls.throttleNotch)
        } else {
            combined = -Float(controls.brakeNotch)
        }
        vehicle.cabControls.setValue(combined, for: .masterController)
        let brakeFraction = controls.emergencyBrake ? 1 : Float(controls.brakeNotch) / 7
        vehicle.cabControls.setValue(brakeFraction, for: .brakeLever)
        vehicle.cabControls.setValue(auxiliary.reverser, for: .reverser)
        vehicle.cabControls.setValue(auxiliary.horn, for: .hornButton)
        vehicle.cabControls.setValue(auxiliary.wiperMode, for: .wiperSwitch)
        vehicle.cabControls.setValue(auxiliary.headlightsOn ? 1 : 0, for: .headlightSwitch)

        let speedKmh = max(0, telemetry.speedMps * 3.6)
        Self.setNeedle(speedNeedle, fraction: speedKmh / 120)
        Self.setNeedle(mainReservoirNeedle, fraction: telemetry.mainReservoirPressureKPa / 1000)
        Self.setNeedle(brakePipeNeedle, fraction: telemetry.brakePipePressureKPa / 1000)
        // The E231 dual pressure gauge reads BC on the shared
        // 0-1000 kPa scale.
        Self.setNeedle(brakeCylinderNeedle, fraction: telemetry.brakeCylinderPressureKPa / 1000)
        slipLamp?.isEnabled = telemetry.isWheelSlipActive || telemetry.isBrakeSlipActive
        emergencyLamp?.isEnabled = controls.emergencyBrake

        for lamp in frontHeadlamps { lamp.isEnabled = auxiliary.headlightsOn }
        for lamp in frontMarkerLamps { lamp.isEnabled = auxiliary.headlightsOn }
        let braking = controls.emergencyBrake || controls.brakeNotch > 0
        for lamp in rearTailLamps { lamp.isEnabled = braking }
    }

    /// Gauge faces are drawn with zero at 225 degrees sweeping 270
    /// degrees clockwise to full scale (see Scripts/generate_cab_textures.py).
    /// The needle geometry points straight up at rest, so the pivot
    /// rotation about the panel normal is (270 * fraction - 135) degrees.
    private static func setNeedle(_ pivot: Entity?, fraction rawFraction: Double) {
        guard let pivot else { return }
        let fraction = Float(min(max(rawFraction.isFinite ? rawFraction : 0, 0), 1))
        let degrees = 270 * fraction - 135
        pivot.orientation = simd_quatf(angle: degrees * .pi / 180, axis: SIMD3<Float>(0, 0, 1))
    }

    private static func findEntity(named name: String, under root: Entity) -> Entity? {
        if root.name == name { return root }
        for child in root.children {
            if let match = findEntity(named: name, under: child) { return match }
        }
        return nil
    }

    private static func findEntities(namedPrefix prefix: String, under root: Entity) -> [Entity] {
        var matches: [Entity] = []
        if root.name.hasPrefix(prefix) { matches.append(root) }
        for child in root.children {
            matches.append(contentsOf: findEntities(namedPrefix: prefix, under: child))
        }
        return matches
    }
}
