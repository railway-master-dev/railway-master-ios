import Foundation

private struct CarBrakeState: Sendable {
    var brakePipePressureKPa: Double
    var cylinderPressureKPa: Double
    var temperatureC: Double
}

public struct CarPhysicsTelemetry: Equatable, Sendable {
    public let identifier: String
    public let tareMassKg: Double
    public let loadedMassKg: Double
    public let brakePipePressureKPa: Double
    public let brakeCylinderPressureKPa: Double
    public let frictionBrakeForceN: Double
    public let brakeTemperatureC: Double
    public let brakeFadeFactor: Double
}

public struct TrainPhysicsTelemetry: Equatable, Sendable {
    public let simulationTimeSeconds: Double
    public let positionM: Double
    public let speedMps: Double
    public let speedKmh: Double
    public let accelerationMps2: Double
    public let physicalMassKg: Double
    public let effectiveMassKg: Double
    public let tractionForceN: Double
    public let totalBrakeForceN: Double
    public let regenerativeBrakeForceN: Double
    public let frictionBrakeForceN: Double
    public let rollingResistanceN: Double
    public let gradientForceN: Double
    public let curveResistanceN: Double
    public let brakePipePressureKPa: Double
    public let brakeCylinderPressureKPa: Double
    public let mainReservoirPressureKPa: Double
    public let lineVoltageV: Double
    /// Positive means traction draw; negative means regenerative return. Fictional meter estimate only.
    public let lineCurrentA: Double
    /// Positive means draw; negative means returned energy, computed as V × A.
    public let electricalPowerW: Double
    public let wheelSlipActive: Bool
    public let brakeSlipActive: Bool
    public let tractionAdhesionScale: Double
    public let brakeAdhesionScale: Double
    public let cars: [CarPhysicsTelemetry]
    public let controlIndicators: FictionalControlIndicators
}

public struct StoppingDistanceEstimate: Equatable, Sendable {
    public let distanceM: Double
    public let durationSeconds: Double
    public let reachedRest: Bool
}

/// Deterministic, longitudinal gameplay model. It never accepts a variable physics timestep.
public struct TrainPhysicsEngine: Sendable {
    public let profile: TrainsetProfile
    public private(set) var positionM: Double = 0
    public private(set) var speedMps: Double = 0
    public private(set) var accelerationMps2: Double = 0
    public private(set) var simulationTimeSeconds: Double = 0
    public private(set) var passengerLoadFactor: Double

    private var accumulatorSeconds = 0.0
    private var carBrakeStates: [CarBrakeState]
    private var mainReservoirPressureKPa: Double
    private var tractionAdhesionScale = 1.0
    private var commandedTractionForceN = 0.0
    private var brakeAdhesionScale = 1.0
    private var wheelSlipActive = false
    private var brakeSlipActive = false
    private var lastTrack = TrackCondition.level
    private var lastSurface = RailSurface.dry
    private var lastModifiers = PhysicsModifiers()
    private var lastTractionForceN = 0.0
    private var lastTotalBrakeForceN = 0.0
    private var lastRegenerativeBrakeForceN = 0.0
    private var lastFrictionBrakeForceN = 0.0
    private var lastRollingResistanceN = 0.0
    private var lastGradientForceN = 0.0
    private var lastCurveResistanceN = 0.0
    private var lastLineCurrentA = 0.0
    private var lastLineVoltageV: Double
    private var lastCarFrictionForcesN: [Double]
    /// Page-described handle law for the six formation profiles. Older JSON profiles stay `.none`.
    private var controlKind: FictionalPageDescribedControl
    private var notch1HoldSeconds = 0.0
    private var previousThrottleNotch = 0
    private var cruiseTargetKmh: Double?
    private var camProgress = 0.0
    private var parallelFinalReached = false

    /// The page says “数秒”. Two seconds is a PLACEHOLDER duration, not a copied timer.
    private static let vvvfNotch1HoldSeconds = 2.0
    /// PLACEHOLDER cam time. The public pages do not publish a step duration.
    private static let chopperCamSeconds = 5.0
    private static let resistanceCamSeconds = 4.0
    /// PLACEHOLDER for “速度が落ちすぎ”. The pages do not give this cutoff.
    private static let chopperRegenFloorKmh = 30.0
    /// PLACEHOLDER mid/high band where 0A re-acceleration is quicker.
    private static let chopperReaccelKmh = 40.0
    private static let chopperReaccelJerkScale = 3.0

    public init(profile: TrainsetProfile, passengerLoadFactor: Double = 0.7) throws {
        let issues = profile.validationIssues()
        guard issues.isEmpty else { throw TrainPhysicsError.invalidProfile(issues) }
        self.profile = profile
        self.passengerLoadFactor = passengerLoadFactor.isFinite ? min(max(passengerLoadFactor, 0), 2) : 0
        self.carBrakeStates = profile.cars.map { _ in
            CarBrakeState(
                brakePipePressureKPa: profile.brakeSystem.chargePressureKPa,
                cylinderPressureKPa: 0,
                temperatureC: profile.brakeSystem.ambientTemperatureC
            )
        }
        self.mainReservoirPressureKPa = profile.brakeSystem.maximumReservoirPressureKPa
        self.lastLineVoltageV = profile.traction.nominalLineVoltageV
        self.lastCarFrictionForcesN = Array(repeating: 0, count: profile.cars.count)
        self.controlKind = FictionalPageDescribedControl.kind(forProfileIdentifier: profile.identifier)
    }

    public static let fixedTimeStepSeconds = PhysicsConstants.fixedTimeStepSeconds

    public mutating func setPassengerLoadFactor(_ value: Double) {
        guard value.isFinite else { return }
        passengerLoadFactor = min(max(value, 0), 2)
    }

    public mutating func reset() {
        positionM = 0
        speedMps = 0
        accelerationMps2 = 0
        simulationTimeSeconds = 0
        accumulatorSeconds = 0
        carBrakeStates = profile.cars.map { _ in
            CarBrakeState(brakePipePressureKPa: profile.brakeSystem.chargePressureKPa,
                          cylinderPressureKPa: 0,
                          temperatureC: profile.brakeSystem.ambientTemperatureC)
        }
        mainReservoirPressureKPa = profile.brakeSystem.maximumReservoirPressureKPa
        tractionAdhesionScale = 1
        commandedTractionForceN = 0
        brakeAdhesionScale = 1
        wheelSlipActive = false
        brakeSlipActive = false
        lastTrack = .level
        lastSurface = .dry
        lastModifiers = PhysicsModifiers()
        lastTractionForceN = 0
        lastTotalBrakeForceN = 0
        lastRegenerativeBrakeForceN = 0
        lastFrictionBrakeForceN = 0
        lastRollingResistanceN = 0
        lastGradientForceN = 0
        lastCurveResistanceN = 0
        lastLineCurrentA = 0
        lastLineVoltageV = profile.traction.nominalLineVoltageV
        lastCarFrictionForcesN = Array(repeating: 0, count: profile.cars.count)
        clearPageDescribedMemory()
    }

    /// Exports all engine-owned mutable state required for deterministic continuation.
    public func stateSnapshot() -> TrainPhysicsEngineStateSnapshot {
        TrainPhysicsEngineStateSnapshot(
            profileID: profile.identifier,
            modelVersion: TrainPhysicsEngineStateSnapshot.currentModelVersion,
            positionM: positionM,
            speedMps: speedMps,
            accelerationMps2: accelerationMps2,
            simulationTimeSeconds: simulationTimeSeconds,
            passengerLoadFactor: passengerLoadFactor,
            accumulatorSeconds: accumulatorSeconds,
            carBrakes: zip(profile.cars, carBrakeStates).map { pair in
                let (car, state) = pair
                return TrainPhysicsCarBrakeSnapshot(
                    carID: car.identifier,
                    brakePipePressureKPa: state.brakePipePressureKPa,
                    cylinderPressureKPa: state.cylinderPressureKPa,
                    temperatureC: state.temperatureC
                )
            },
            mainReservoirPressureKPa: mainReservoirPressureKPa,
            tractionAdhesionScale: tractionAdhesionScale,
            commandedTractionForceN: commandedTractionForceN,
            brakeAdhesionScale: brakeAdhesionScale,
            wheelSlipActive: wheelSlipActive,
            brakeSlipActive: brakeSlipActive,
            lastTrack: TrainPhysicsTrackSnapshot(lastTrack),
            lastSurface: lastSurface,
            lastModifiers: TrainPhysicsModifiersSnapshot(lastModifiers),
            lastTractionForceN: lastTractionForceN,
            lastTotalBrakeForceN: lastTotalBrakeForceN,
            lastRegenerativeBrakeForceN: lastRegenerativeBrakeForceN,
            lastFrictionBrakeForceN: lastFrictionBrakeForceN,
            lastRollingResistanceN: lastRollingResistanceN,
            lastGradientForceN: lastGradientForceN,
            lastCurveResistanceN: lastCurveResistanceN,
            lastLineCurrentA: lastLineCurrentA,
            lastLineVoltageV: lastLineVoltageV,
            lastCarFrictionForcesN: lastCarFrictionForcesN
        )
    }

    /// Restores only a snapshot validated against this engine's exact profile and state version.
    public mutating func restoreState(from saved: TrainPhysicsEngineStateSnapshot) throws {
        guard saved.profileID == profile.identifier else { throw TrainPhysicsStateRestoreError.profileMismatch }
        guard saved.modelVersion == TrainPhysicsEngineStateSnapshot.currentModelVersion else {
            throw TrainPhysicsStateRestoreError.unsupportedVersion(saved.modelVersion)
        }
        guard saved.carBrakes.count == profile.cars.count,
              saved.lastCarFrictionForcesN.count == profile.cars.count,
              zip(saved.carBrakes, profile.cars).allSatisfy({ pair in pair.0.carID == pair.1.identifier }) else {
            throw TrainPhysicsStateRestoreError.invalidState("per-car state does not match the ordered profile cars")
        }
        let scalars = [saved.positionM, saved.speedMps, saved.accelerationMps2, saved.simulationTimeSeconds,
                       saved.passengerLoadFactor, saved.accumulatorSeconds, saved.mainReservoirPressureKPa,
                       saved.tractionAdhesionScale, saved.commandedTractionForceN, saved.brakeAdhesionScale,
                       saved.lastTractionForceN, saved.lastTotalBrakeForceN, saved.lastRegenerativeBrakeForceN,
                       saved.lastFrictionBrakeForceN, saved.lastRollingResistanceN, saved.lastGradientForceN,
                       saved.lastCurveResistanceN, saved.lastLineCurrentA, saved.lastLineVoltageV]
            + saved.lastCarFrictionForcesN
            + saved.carBrakes.flatMap { [$0.brakePipePressureKPa, $0.cylinderPressureKPa, $0.temperatureC] }
        guard scalars.allSatisfy(\.isFinite), saved.positionM >= 0, saved.positionM <= 1_000_000,
              saved.speedMps >= 0, saved.speedMps <= 500 / 3.6, abs(saved.accelerationMps2) <= 100,
              saved.simulationTimeSeconds >= 0, saved.simulationTimeSeconds <= 1_000_000_000,
              (0...2).contains(saved.passengerLoadFactor),
              (0...Self.fixedTimeStepSeconds).contains(saved.accumulatorSeconds),
              (profile.brakeSystem.minimumReservoirPressureKPa...profile.brakeSystem.maximumReservoirPressureKPa).contains(saved.mainReservoirPressureKPa),
              (0.35...1).contains(saved.tractionAdhesionScale), (0.35...1).contains(saved.brakeAdhesionScale),
              saved.commandedTractionForceN >= 0, saved.commandedTractionForceN <= 10_000_000,
              saved.lastTractionForceN >= 0, saved.lastTotalBrakeForceN >= 0,
              saved.lastRegenerativeBrakeForceN >= 0, saved.lastFrictionBrakeForceN >= 0,
              saved.lastRollingResistanceN >= 0, saved.lastCurveResistanceN >= 0,
              saved.lastCarFrictionForcesN.allSatisfy({ $0 >= 0 && $0 <= 10_000_000 }),
              abs(saved.lastLineCurrentA) <= profile.traction.currentLimitA,
              saved.lastLineVoltageV > 0, saved.lastLineVoltageV <= 100_000,
              saved.lastTrack.trackCondition().isValid,
              (0...2).contains(saved.lastModifiers.tractionMultiplier),
              (0...2).contains(saved.lastModifiers.brakingMultiplier),
              saved.lastModifiers.speedCapKmh.map({ (0.0...500.0).contains($0) }) ?? true,
              saved.lastModifiers.adhesionCoefficientOverride.map({ (0.01...1).contains($0) }) ?? true,
              (0...40_000).contains(saved.lastModifiers.extraResistanceN) else {
            throw TrainPhysicsStateRestoreError.invalidState("one or more values are outside validated engine bounds")
        }
        for (index, brake) in saved.carBrakes.enumerated() {
            guard (0...profile.brakeSystem.chargePressureKPa).contains(brake.brakePipePressureKPa),
                  (0...profile.brakeSystem.maximumCylinderPressureKPa).contains(brake.cylinderPressureKPa),
                  brake.temperatureC >= profile.brakeSystem.ambientTemperatureC,
                  brake.temperatureC <= 2_000 else {
                throw TrainPhysicsStateRestoreError.invalidState("invalid brake state for car \(profile.cars[index].identifier)")
            }
        }

        positionM = saved.positionM
        speedMps = saved.speedMps
        accelerationMps2 = saved.accelerationMps2
        simulationTimeSeconds = saved.simulationTimeSeconds
        passengerLoadFactor = saved.passengerLoadFactor
        accumulatorSeconds = saved.accumulatorSeconds
        carBrakeStates = saved.carBrakes.map {
            CarBrakeState(brakePipePressureKPa: $0.brakePipePressureKPa,
                          cylinderPressureKPa: $0.cylinderPressureKPa,
                          temperatureC: $0.temperatureC)
        }
        mainReservoirPressureKPa = saved.mainReservoirPressureKPa
        tractionAdhesionScale = saved.tractionAdhesionScale
        commandedTractionForceN = saved.commandedTractionForceN
        brakeAdhesionScale = saved.brakeAdhesionScale
        wheelSlipActive = saved.wheelSlipActive
        brakeSlipActive = saved.brakeSlipActive
        lastTrack = saved.lastTrack.trackCondition()
        lastSurface = saved.lastSurface
        lastModifiers = saved.lastModifiers.modifiers()
        lastTractionForceN = saved.lastTractionForceN
        lastTotalBrakeForceN = saved.lastTotalBrakeForceN
        lastRegenerativeBrakeForceN = saved.lastRegenerativeBrakeForceN
        lastFrictionBrakeForceN = saved.lastFrictionBrakeForceN
        lastRollingResistanceN = saved.lastRollingResistanceN
        lastGradientForceN = saved.lastGradientForceN
        lastCurveResistanceN = saved.lastCurveResistanceN
        lastLineCurrentA = saved.lastLineCurrentA
        lastLineVoltageV = saved.lastLineVoltageV
        lastCarFrictionForcesN = saved.lastCarFrictionForcesN
        // v1 snapshots do not store cam or cruise memory, so a restored run starts that memory at rest.
        clearPageDescribedMemory()
    }

    /// Accumulates render-clock time, caps one call at 0.5 s, and simulates whole 1/120 s ticks only.
    /// Returns the number of fixed ticks executed. Invalid/non-positive deltas are ignored.
    @discardableResult
    public mutating func advance(
        realDeltaSeconds: Double,
        controls: SimulationControls,
        track: TrackCondition = .level,
        surface: RailSurface = .dry,
        modifiers: PhysicsModifiers = PhysicsModifiers()
    ) -> Int {
        guard realDeltaSeconds.isFinite, realDeltaSeconds > 0 else { return 0 }
        accumulatorSeconds += min(realDeltaSeconds, PhysicsConstants.maximumFrameDeltaSeconds)
        var ticks = 0
        while accumulatorSeconds + 1e-12 >= Self.fixedTimeStepSeconds {
            simulateFixedTick(controls: controls, track: track, surface: surface, modifiers: modifiers)
            accumulatorSeconds -= Self.fixedTimeStepSeconds
            if accumulatorSeconds < 0, accumulatorSeconds > -1e-10 { accumulatorSeconds = 0 }
            ticks += 1
        }
        return ticks
    }

    /// Current state and per-car instrument readings, all in SI units unless field names say otherwise.
    public var telemetry: TrainPhysicsTelemetry {
        let masses = loadedCarMassesKg
        let cars = profile.cars.indices.map { index in
            let car = profile.cars[index]
            let state = carBrakeStates[index]
            return CarPhysicsTelemetry(
                identifier: car.identifier,
                tareMassKg: car.tareMassKg,
                loadedMassKg: masses[index],
                brakePipePressureKPa: state.brakePipePressureKPa,
                brakeCylinderPressureKPa: state.cylinderPressureKPa,
                frictionBrakeForceN: lastCarFrictionForcesN[index],
                brakeTemperatureC: state.temperatureC,
                brakeFadeFactor: car.fadeFactor(at: state.temperatureC)
            )
        }
        let averagePipe = carBrakeStates.isEmpty ? 0 : carBrakeStates.map(\.brakePipePressureKPa).reduce(0, +) / Double(carBrakeStates.count)
        let averageCylinder = carBrakeStates.isEmpty ? 0 : carBrakeStates.map(\.cylinderPressureKPa).reduce(0, +) / Double(carBrakeStates.count)
        let power = lastLineVoltageV * lastLineCurrentA
        return TrainPhysicsTelemetry(
            simulationTimeSeconds: simulationTimeSeconds,
            positionM: positionM,
            speedMps: speedMps,
            speedKmh: speedMps * 3.6,
            accelerationMps2: accelerationMps2,
            physicalMassKg: profile.totalMassKg(passengerLoadFactor: passengerLoadFactor),
            effectiveMassKg: profile.effectiveMassKg(passengerLoadFactor: passengerLoadFactor),
            tractionForceN: lastTractionForceN,
            totalBrakeForceN: lastTotalBrakeForceN,
            regenerativeBrakeForceN: lastRegenerativeBrakeForceN,
            frictionBrakeForceN: lastFrictionBrakeForceN,
            rollingResistanceN: lastRollingResistanceN,
            gradientForceN: lastGradientForceN,
            curveResistanceN: lastCurveResistanceN,
            brakePipePressureKPa: averagePipe,
            brakeCylinderPressureKPa: averageCylinder,
            mainReservoirPressureKPa: mainReservoirPressureKPa,
            lineVoltageV: lastLineVoltageV,
            lineCurrentA: lastLineCurrentA,
            electricalPowerW: power.isFinite ? power : 0,
            wheelSlipActive: wheelSlipActive,
            brakeSlipActive: brakeSlipActive,
            tractionAdhesionScale: tractionAdhesionScale,
            brakeAdhesionScale: brakeAdhesionScale,
            cars: cars,
            controlIndicators: currentControlIndicators(speedKmh: speedMps * 3.6, regenerativeForceN: lastRegenerativeBrakeForceN, tractionForceN: lastTractionForceN)
        )
    }

    /// Numerically integrates the present state on a copy using the requested full-service or emergency brake.
    /// This is a gameplay estimate, not a safety envelope. It returns reachedRest=false at the duration cap.
    public func estimateStoppingDistance(brake: BrakeDemand = .service(notch: 7), maximumDurationSeconds: Double = 180) -> StoppingDistanceEstimate {
        let safeDuration = maximumDurationSeconds.isFinite ? min(max(maximumDurationSeconds, 0), 600) : 0
        if speedMps <= PhysicsConstants.stopSpeedThresholdMps {
            return StoppingDistanceEstimate(distanceM: 0, durationSeconds: 0, reachedRest: true)
        }
        var probe = self
        let startPosition = positionM
        let maximumTicks = Int(safeDuration / Self.fixedTimeStepSeconds)
        let controls: SimulationControls
        switch brake {
        case .service(let notch):
            controls = SimulationControls(throttleNotch: 0, brakeNotch: notch)
        case .emergency:
            controls = SimulationControls(throttleNotch: 0, brakeNotch: 0, emergencyBrake: true)
        }
        for tick in 0..<maximumTicks {
            probe.simulateFixedTick(controls: controls, track: lastTrack, surface: lastSurface, modifiers: lastModifiers)
            if probe.speedMps <= PhysicsConstants.stopSpeedThresholdMps {
                return StoppingDistanceEstimate(
                    distanceM: max(probe.positionM - startPosition, 0),
                    durationSeconds: Double(tick + 1) * Self.fixedTimeStepSeconds,
                    reachedRest: true
                )
            }
        }
        return StoppingDistanceEstimate(
            distanceM: max(probe.positionM - startPosition, 0),
            durationSeconds: Double(maximumTicks) * Self.fixedTimeStepSeconds,
            reachedRest: false
        )
    }

    private var loadedCarMassesKg: [Double] {
        let load = min(max(passengerLoadFactor, 0), 2)
        return profile.cars.map { $0.tareMassKg + Double($0.passengerCapacity) * load * PhysicsConstants.passengerMassKg }
    }

    private mutating func simulateFixedTick(
        controls: SimulationControls,
        track: TrackCondition,
        surface: RailSurface,
        modifiers: PhysicsModifiers
    ) {
        let dt = Self.fixedTimeStepSeconds
        let condition = track.isValid ? track : .level
        let effects = modifiers.sanitized()
        lastTrack = condition
        lastSurface = surface
        lastModifiers = effects
        let notch = max(controls.throttleNotch, 0)
        updatePageDescribedControl(
            notch: notch,
            braking: controls.emergencyBrake || controls.brakeNotch > 0,
            masterReversed: controls.masterReversed,
            dt: dt,
            speedKmh: max(speedMps, 0) * 3.6
        )

        let oldStates = carBrakeStates
        let brakeFraction = controls.emergencyBrake ? 1 : min(max(Double(controls.brakeNotch), 0), 7) / 7
        let pipeTarget = controls.emergencyBrake
            ? 0
            : profile.brakeSystem.chargePressureKPa - profile.brakeSystem.maximumServicePipeReductionKPa * brakeFraction

        var updatedStates = oldStates
        for index in profile.cars.indices {
            let upstreamPressure = index == 0 ? pipeTarget : oldStates[index - 1].brakePipePressureKPa
            let pipeTau = max(profile.brakeSystem.propagationSecondsPerCar, dt)
            let pipeAlpha = 1 - exp(-dt / pipeTau)
            let newPipe = clamp(oldStates[index].brakePipePressureKPa + (upstreamPressure - oldStates[index].brakePipePressureKPa) * pipeAlpha,
                                0, profile.brakeSystem.chargePressureKPa)
            let pressureDrop = max(profile.brakeSystem.chargePressureKPa - newPipe, 0)
            let cylinderTarget = profile.brakeSystem.maximumCylinderPressureKPa *
                min(max(pressureDrop / profile.brakeSystem.maximumServicePipeReductionKPa, 0), 1)
            let carProfile = profile.cars[index]
            let applying = cylinderTarget > oldStates[index].cylinderPressureKPa
            let responseSeconds = applying ? carProfile.brakeApplySeconds : carProfile.brakeReleaseSeconds
            let cylinderAlpha = 1 - exp(-dt / max(responseSeconds, dt))
            let newCylinder = clamp(oldStates[index].cylinderPressureKPa
                + (cylinderTarget - oldStates[index].cylinderPressureKPa) * cylinderAlpha,
                0, profile.brakeSystem.maximumCylinderPressureKPa)
            updatedStates[index].brakePipePressureKPa = newPipe
            updatedStates[index].cylinderPressureKPa = newCylinder
        }

        let masses = loadedCarMassesKg
        let physicalMass = masses.reduce(0, +)
        let effectiveMass = max(physicalMass * profile.rotationalInertiaFactor, 1)
        let gradientAngle = atan(condition.gradientPermille / 1_000)
        let speed = max(speedMps.isFinite ? speedMps : 0, 0)
        let speedKmh = speed * 3.6
        let speedAdhesionFactor = 1 / (1 + speedKmh / 2_000)
        let baseAdhesionCoefficient = effects.adhesionCoefficientOverride ?? surface.fictionalAdhesionCoefficient
        let adhesionCoefficient = baseAdhesionCoefficient * speedAdhesionFactor
        let drivenMass = zip(masses, profile.cars).reduce(0) { $0 + $1.0 * $1.1.drivenMassFraction }
        let brakedMass = zip(masses, profile.cars).reduce(0) { $0 + $1.0 * $1.1.brakedMassFraction }
        let gradeNormalMass = max(cos(gradientAngle), 0)
        let tractionAdhesionLimit = adhesionCoefficient * PhysicsConstants.gravityMps2 * drivenMass * gradeNormalMass

        let powerCut = controls.emergencyBrake || controls.brakeNotch > 0 || (controlKind == .resistanceCam && controls.masterReversed)
        var requestedTraction = powerCut
            ? 0
            : profile.traction.availableTractionForceN(speedKmh: speedKmh, notch: controls.throttleNotch) * effects.tractionMultiplier
        if controlKind == .resistanceCam && !powerCut && controls.throttleNotch >= 1 {
            let full = profile.traction.availableTractionForceN(speedKmh: speedKmh, notch: profile.maximumTractionNotch) * effects.tractionMultiplier
            requestedTraction = full * camProgress
        }
        var tractionJerk = profile.traction.tractionJerkMps3
        if controlKind == .fieldChopperCam && parallelFinalReached && speedKmh >= Self.chopperReaccelKmh {
            tractionJerk *= Self.chopperReaccelJerkScale
        }
        wheelSlipActive = requestedTraction > tractionAdhesionLimit + 1
        if wheelSlipActive {
            tractionAdhesionScale = max(0.35, tractionAdhesionScale - 3.0 * dt)
        } else {
            tractionAdhesionScale = min(1, tractionAdhesionScale + 0.8 * dt)
        }
        let tractionTarget = requestedTraction * tractionAdhesionScale
        if controls.emergencyBrake || controls.brakeNotch > 0 {
            commandedTractionForceN = 0
        } else {
            let maximumForceChange = effectiveMass * tractionJerk * dt
            commandedTractionForceN = moveTowards(commandedTractionForceN, tractionTarget, maximumForceChange)
        }
        let traction = min(max(commandedTractionForceN, 0), tractionAdhesionLimit)

        var requestedPerCar: [Double] = []
        for index in profile.cars.indices {
            let car = profile.cars[index]
            let state = updatedStates[index]
            let cylinderFraction = state.cylinderPressureKPa / max(profile.brakeSystem.maximumCylinderPressureKPa, 1)
            let nominalForce = controls.emergencyBrake ? car.maximumEmergencyBrakeForceN : car.maximumServiceBrakeForceN
            requestedPerCar.append(nominalForce * cylinderFraction * car.fadeFactor(at: state.temperatureC) * effects.brakingMultiplier)
        }
        let requestedBrake = requestedPerCar.reduce(0, +)
        let brakeAdhesionLimit = adhesionCoefficient * PhysicsConstants.gravityMps2 * brakedMass * gradeNormalMass
        brakeSlipActive = requestedBrake > brakeAdhesionLimit + 1
        if brakeSlipActive {
            brakeAdhesionScale = max(0.35, brakeAdhesionScale - 3.5 * dt)
        } else {
            brakeAdhesionScale = min(1, brakeAdhesionScale + 0.8 * dt)
        }
        let totalBrakeAllowed = min(requestedBrake * brakeAdhesionScale, brakeAdhesionLimit)
        let regenerativeAllowed = controlKind != .fieldChopperCam || (parallelFinalReached && speedKmh >= Self.chopperRegenFloorKmh)
        let regenerativeRequest = regenerativeAllowed
            ? profile.traction.regenerativeForceRequestN(brakeDemandN: requestedBrake, speedKmh: speedKmh)
            : 0
        let drivenAdhesionLimit = adhesionCoefficient * PhysicsConstants.gravityMps2 * drivenMass * gradeNormalMass
        let regenerative = min(min(regenerativeRequest, totalBrakeAllowed), drivenAdhesionLimit * brakeAdhesionScale)
        let frictionDemand = max(totalBrakeAllowed - regenerative, 0)
        let requestedSum = max(requestedPerCar.reduce(0, +), 1)
        var frictionPerCar = Array(repeating: 0.0, count: profile.cars.count)
        for index in profile.cars.indices {
            let car = profile.cars[index]
            let carAdhesionLimit = adhesionCoefficient * PhysicsConstants.gravityMps2 * masses[index] *
                car.brakedMassFraction * gradeNormalMass * brakeAdhesionScale
            let allocated = frictionDemand * requestedPerCar[index] / requestedSum
            frictionPerCar[index] = min(allocated, carAdhesionLimit)
        }
        let friction = frictionPerCar.reduce(0, +)
        let totalBrake = regenerative + friction

        let lineVoltage = condition.supplyVoltageV ?? profile.traction.nominalLineVoltageV
        let davis = profile.davisResistance.resistanceN(massKg: physicalMass, speedMps: speed)
        let rolling = davis * condition.tunnelResistanceMultiplier + effects.extraResistanceN
        let gradientForce = physicalMass * PhysicsConstants.gravityMps2 * sin(gradientAngle)
        let curveResistance: Double
        if let radius = condition.curveRadiusM {
            curveResistance = physicalMass * PhysicsConstants.gravityMps2 / 1_000 *
                profile.curveResistanceNPerKNAtOnePerM / max(radius, 1)
        } else {
            curveResistance = 0
        }
        var tractionForce = traction
        var brakeForce = totalBrake
        if controlKind == .vvvfCruise,
           let target = cruiseTargetKmh,
           controls.throttleNotch == 2,
           controls.brakeNotch == 0,
           !controls.emergencyBrake {
            let errorMps = target / 3.6 - speed
            let desiredAccel = clamp(errorMps / 0.45, -0.7, 0.55)
            let needed = desiredAccel * effectiveMass + rolling + gradientForce + curveResistance
            if needed >= 0 {
                let cap = profile.traction.availableTractionForceN(speedKmh: speedKmh, notch: 2) * effects.tractionMultiplier
                let targetForce = min(min(needed, cap), tractionAdhesionLimit)
                let maximumForceChange = effectiveMass * profile.traction.tractionJerkMps3 * dt
                commandedTractionForceN = moveTowards(commandedTractionForceN, targetForce, maximumForceChange)
                tractionForce = min(max(commandedTractionForceN, 0), tractionAdhesionLimit)
            } else {
                commandedTractionForceN = 0
                tractionForce = 0
                brakeForce += min(-needed, effectiveMass * 0.8)
            }
        }
        if controlKind == .resistanceCam && controls.masterReversed && !controls.emergencyBrake {
            commandedTractionForceN = 0
            tractionForce = 0
            let service = profile.cars.map(\.maximumServiceBrakeForceN).reduce(0, +)
            let fade = clamp((speedKmh - 8) / 12, 0, 1)
            brakeForce += service * 0.45 * fade
        }
        let tractionCurrent = profile.traction.lineCurrentA(forceN: tractionForce, speedMps: speed, lineVoltageV: lineVoltage)
        let regenCurrent = regenerative > 0
            ? profile.traction.lineCurrentA(forceN: regenerative, speedMps: speed, lineVoltageV: lineVoltage, regenerative: true)
            : 0
        lastLineVoltageV = lineVoltage
        lastLineCurrentA = tractionCurrent + regenCurrent
        let netForce = tractionForce - brakeForce - rolling - gradientForce - curveResistance
        let rawAcceleration = netForce / effectiveMass
        let newSpeed = max(speed + rawAcceleration * dt, 0)
        let requestedSpeedLimitKmh = min(min(profile.traction.maximumSpeedKmh, condition.speedLimitKmh), effects.speedCapKmh ?? .infinity)
        let speedLimitMps = max(requestedSpeedLimitKmh, 0) / 3.6
        let finiteNewSpeed = newSpeed.isFinite ? min(newSpeed, speedLimitMps) : 0
        accelerationMps2 = (finiteNewSpeed - speed) / dt
        speedMps = finiteNewSpeed
        positionM += finiteNewSpeed * dt
        simulationTimeSeconds += dt

        for index in profile.cars.indices {
            let car = profile.cars[index]
            let oldTemperature = oldStates[index].temperatureC
            let heatJ = frictionPerCar[index] * speed * dt
            let coolingJ = car.brakeCoolingWPerC * max(oldTemperature - profile.brakeSystem.ambientTemperatureC, 0) * dt
            let newTemperature = max(profile.brakeSystem.ambientTemperatureC,
                                     oldTemperature + (heatJ - coolingJ) / car.brakeThermalCapacityJPerC)
            updatedStates[index].temperatureC = newTemperature.isFinite ? newTemperature : profile.brakeSystem.ambientTemperatureC
        }
        carBrakeStates = updatedStates

        let averageCylinderRise = updatedStates.indices.map {
            max(updatedStates[$0].cylinderPressureKPa - oldStates[$0].cylinderPressureKPa, 0)
        }.reduce(0, +) / Double(max(updatedStates.count, 1))
        let reservoirDrop = averageCylinderRise * 0.12
        let reservoirRecovery = (brakeFraction == 0 ? profile.brakeSystem.reservoirRecoveryKPaPerSecond * dt : 0)
        mainReservoirPressureKPa = clamp(mainReservoirPressureKPa - reservoirDrop + reservoirRecovery,
                                         profile.brakeSystem.minimumReservoirPressureKPa,
                                         profile.brakeSystem.maximumReservoirPressureKPa)

        lastTractionForceN = finiteOrZero(tractionForce)
        lastTotalBrakeForceN = finiteOrZero(brakeForce)
        lastRegenerativeBrakeForceN = finiteOrZero(regenerative)
        lastFrictionBrakeForceN = finiteOrZero(friction)
        lastRollingResistanceN = finiteOrZero(rolling)
        lastGradientForceN = finiteOrZero(gradientForce)
        lastCurveResistanceN = finiteOrZero(curveResistance)
        lastCarFrictionForcesN = frictionPerCar.map(finiteOrZero)

    }

    private mutating func clearPageDescribedMemory() {
        notch1HoldSeconds = 0
        previousThrottleNotch = 0
        cruiseTargetKmh = nil
        camProgress = 0
        parallelFinalReached = false
    }

    private mutating func updatePageDescribedControl(notch: Int, braking: Bool, masterReversed: Bool, dt: Double, speedKmh: Double) {
        switch controlKind {
        case .vvvfCruise:
            if braking || masterReversed {
                cruiseTargetKmh = nil
                if notch != 1 { notch1HoldSeconds = 0 }
            } else if notch == 2 && previousThrottleNotch != 2 {
                if speedKmh >= 20 {
                    cruiseTargetKmh = speedKmh
                } else if previousThrottleNotch == 1 && notch1HoldSeconds >= Self.vvvfNotch1HoldSeconds {
                    cruiseTargetKmh = 20
                } else {
                    cruiseTargetKmh = nil
                }
                notch1HoldSeconds = 0
            } else if notch == 1 {
                notch1HoldSeconds += dt
                cruiseTargetKmh = nil
            } else if notch != 2 {
                notch1HoldSeconds = 0
                cruiseTargetKmh = nil
            }
        case .fieldChopperCam:
            if !braking && notch >= 1 && !masterReversed {
                camProgress = min(1, camProgress + dt / Self.chopperCamSeconds)
                if camProgress >= 1 { parallelFinalReached = true }
            }
        case .resistanceCam:
            if !braking && notch >= 2 && !masterReversed {
                camProgress = min(1, camProgress + dt / Self.resistanceCamSeconds)
            }
        case .none:
            break
        }
        previousThrottleNotch = notch
    }

    private func currentControlIndicators(speedKmh: Double, regenerativeForceN: Double, tractionForceN: Double) -> FictionalControlIndicators {
        guard controlKind != .none else { return .dark }
        let chopper = controlKind == .fieldChopperCam
        return FictionalControlIndicators(
            camProgress: camProgress,
            parallelFinalReached: parallelFinalReached,
            cruiseTargetKmh: cruiseTargetKmh,
            notchProgressHeld: controlKind == .resistanceCam && previousThrottleNotch == 1,
            seriesLamp: chopper && camProgress > 0.02 && camProgress < 0.45,
            parallelLamp: chopper && camProgress >= 0.45 && camProgress < 0.98,
            finalStageLamp: chopper && (parallelFinalReached || camProgress >= 0.98),
            fieldWeakeningLamp: chopper && parallelFinalReached && tractionForceN > 1 && speedKmh >= Self.chopperReaccelKmh,
            regenerativeLamp: chopper && regenerativeForceN > 1
        )
    }

    private func clamp(_ value: Double, _ lower: Double, _ upper: Double) -> Double {
        min(max(value, lower), upper)
    }

    private func moveTowards(_ value: Double, _ target: Double, _ maximumDelta: Double) -> Double {
        if value < target { return min(value + maximumDelta, target) }
        return max(value - maximumDelta, target)
    }

    private func finiteOrZero(_ value: Double) -> Double {
        value.isFinite ? value : 0
    }
}
