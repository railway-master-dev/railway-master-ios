import Foundation
import TrainPhysics

/// Maps the app's route and controls into the single authoritative fictional physics package.
enum TrainPhysicsProfileAdapter {
    static func makeEngine(
        for vehicle: FictionalVehicleProfile,
        passengerLoadFactor: Double
    ) -> TrainPhysics.TrainPhysicsEngine {
        // The bundled catalog is validated by the package and the project validator; a missing
        // or invalid resource is a packaging defect, not a reason to silently use legacy physics.
        let profile = try! TrainPhysics.FictionalProfileCatalog.profile(identifier: vehicle.physicsProfileIdentifier)
        return try! TrainPhysics.TrainPhysicsEngine(profile: profile, passengerLoadFactor: passengerLoadFactor)
    }

    static func trackCondition(
        route: RailwayRouteProfile,
        positionM: Double,
        profile: TrainPhysics.TrainsetProfile
    ) -> TrainPhysics.TrackCondition {
        let section = route.condition(at: positionM)
        return TrainPhysics.TrackCondition(
            gradientPermille: section.gradientPermille,
            curveRadiusM: section.curveRadiusM,
            speedLimitKmh: min(section.speedLimitKmh, profile.traction.maximumSpeedKmh),
            tunnelResistanceMultiplier: section.tunnelResistanceMultiplier,
            supplyVoltageV: profile.traction.nominalLineVoltageV
        )
    }

    static func railSurface(for weather: WeatherCondition) -> TrainPhysics.RailSurface {
        switch weather {
        case .dry, .fog: .dry
        case .rain, .heavyRain: .wet
        case .snow: .snow
        }
    }

    static func projectTelemetry(
        _ source: TrainPhysics.TrainPhysicsTelemetry,
        engine: TrainPhysics.TrainPhysicsEngine,
        route: RailwayRouteProfile,
        stoppingDistance: TrainPhysics.StoppingDistanceEstimate?
    ) -> TrainTelemetry {
        let condition = route.condition(at: source.positionM)
        let distanceToMarker = route.stopMarkerM - source.positionM
        let curveAcceleration: Double
        if let radius = condition.curveRadiusM, radius > 0 {
            let cantAcceleration = 9.80665 * (condition.cantMm ?? 0) / route.trackGaugeMm
            curveAcceleration = Double(condition.curveDirection ?? 1) * (source.speedMps * source.speedMps / radius - cantAcceleration)
        } else {
            curveAcceleration = 0
        }
        let maximumCylinder = max(engine.profile.brakeSystem.maximumCylinderPressureKPa, 1)
        let appliedBrake = min(max(source.brakeCylinderPressureKPa / maximumCylinder, 0), 1)
        return TrainTelemetry(
            positionM: source.positionM,
            speedMps: source.speedMps,
            accelerationMps2: source.accelerationMps2,
            tractionForceN: source.tractionForceN,
            brakingForceN: source.totalBrakeForceN,
            regenerativeBrakeForceN: source.regenerativeBrakeForceN,
            airBrakeForceN: source.frictionBrakeForceN,
            rollingResistanceN: source.rollingResistanceN,
            gradientForceN: source.gradientForceN,
            curveResistanceN: source.curveResistanceN,
            appliedBrakeFraction: appliedBrake,
            brakePipePressureKPa: source.brakePipePressureKPa,
            brakeCylinderPressureKPa: source.brakeCylinderPressureKPa,
            mainReservoirPressureKPa: source.mainReservoirPressureKPa,
            effectiveMassKg: source.effectiveMassKg,
            passengerLoadFactor: engine.passengerLoadFactor,
            currentGradientPermille: condition.gradientPermille,
            currentCantMm: condition.cantMm ?? 0,
            lateralAccelerationMps2: curveAcceleration,
            currentSpeedLimitKmh: condition.speedLimitKmh,
            distanceToStopMarkerM: distanceToMarker,
            predictedStoppingDistanceM: stoppingDistance?.distanceM ?? 0,
            isStoppedAtMarker: abs(distanceToMarker) <= 0.5 && source.speedMps <= 0.2,
            isWheelSlipActive: source.wheelSlipActive,
            isBrakeSlipActive: source.brakeSlipActive
        )
    }
}
