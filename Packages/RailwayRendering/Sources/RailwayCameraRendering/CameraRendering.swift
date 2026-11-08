import Foundation
import RailwayRenderingCore

/// Conservative tuning values for camera mode transitions and motion response.
public struct CameraMotionSettings: Sendable, Equatable {
    /// Time for a view-mode change to reach its destination, in seconds.
    public var transitionDurationSeconds: Double
    /// Maximum acceleration-driven fore/aft camera offset, in meters.
    public var maximumAccelerationOffsetMeters: Double
    /// Maximum acceleration-driven vertical offset, in meters.
    public var maximumAccelerationVerticalOffsetMeters: Double
    /// Maximum curve-driven sideways offset, in meters.
    public var maximumCurveOffsetMeters: Double
    /// Maximum curve-induced camera roll, in radians.
    public var maximumCurveRollRadians: Double
    /// Maximum amplitude of deterministic camera vibration, in meters.
    public var shakeAmplitudeMeters: Double
    /// Frequency of the deterministic vibration, in hertz.
    public var shakeFrequencyHz: Double

    public init(
        transitionDurationSeconds: Double = 0.65,
        maximumAccelerationOffsetMeters: Double = 0.08,
        maximumAccelerationVerticalOffsetMeters: Double = 0.025,
        maximumCurveOffsetMeters: Double = 0.045,
        maximumCurveRollRadians: Double = 0.025,
        shakeAmplitudeMeters: Double = 0.006,
        shakeFrequencyHz: Double = 7.0
    ) {
        self.transitionDurationSeconds = transitionDurationSeconds
        self.maximumAccelerationOffsetMeters = maximumAccelerationOffsetMeters
        self.maximumAccelerationVerticalOffsetMeters = maximumAccelerationVerticalOffsetMeters
        self.maximumCurveOffsetMeters = maximumCurveOffsetMeters
        self.maximumCurveRollRadians = maximumCurveRollRadians
        self.shakeAmplitudeMeters = shakeAmplitudeMeters
        self.shakeFrequencyHz = shakeFrequencyHz
    }
}

/// Produces a smoothed camera pose in the train's local frame (+Z is forward).
public final class CameraController {
    /// The requested view preset. Changing it begins a smooth transition.
    public var viewMode: CameraViewMode {
        didSet {
            if viewMode != oldValue { beginTransition() }
        }
    }

    /// Configurable transition and restrained motion-effect settings.
    public var settings: CameraMotionSettings

    private var motion = TrainMotionSample(
        simulationTimeSeconds: 0,
        speedMetersPerSecond: 0,
        longitudinalAccelerationMetersPerSecondSquared: 0
    )
    private var fallbackTimeSeconds = 0.0
    private var currentBasePose: CameraPose
    private var transitionStartPose: CameraPose
    private var transitionTargetPose: CameraPose
    private var transitionElapsedSeconds = 0.0

    /// Creates a controller, initially positioned at the chosen preset.
    public init(viewMode: CameraViewMode = .cab, settings: CameraMotionSettings = CameraMotionSettings()) {
        self.viewMode = viewMode
        self.settings = settings
        let initialPose = Self.preset(for: viewMode)
        self.currentBasePose = initialPose
        self.transitionStartPose = initialPose
        self.transitionTargetPose = initialPose
    }

    /// Replaces the latest train-motion input; invalid values are made safe on update.
    public func setMotion(_ sample: TrainMotionSample) {
        motion = sample
    }

    /// Updates the camera from the latest motion sample and returns its local-frame pose.
    public func update(deltaTime: Double) -> CameraPose {
        let dt = Self.clamp(deltaTime, to: 0...1, fallback: 0)
        fallbackTimeSeconds += dt
        if !fallbackTimeSeconds.isFinite { fallbackTimeSeconds = 0 }

        advanceTransition(by: dt)
        let safeSpeed = Self.clamp(motion.speedMetersPerSecond, to: 0...100, fallback: 0)
        let safeAcceleration = Self.clamp(motion.longitudinalAccelerationMetersPerSecondSquared, to: -8...8, fallback: 0)
        let time = motion.simulationTimeSeconds.isFinite ? motion.simulationTimeSeconds : fallbackTimeSeconds

        var pose = currentBasePose
        let accelerationRatio = safeAcceleration / 8
        let foreAft = -accelerationRatio * Self.setting(settings.maximumAccelerationOffsetMeters, maximum: 0.25, fallback: 0.08)
        let vertical = abs(accelerationRatio) * Self.setting(settings.maximumAccelerationVerticalOffsetMeters, maximum: 0.1, fallback: 0.025)
        let curve = curveResponse(speed: safeSpeed)

        let frequency = Self.setting(settings.shakeFrequencyHz, maximum: 20, fallback: 7)
        let shake = Self.setting(settings.shakeAmplitudeMeters, maximum: 0.03, fallback: 0.006)
        let phaseTime = time.truncatingRemainder(dividingBy: 100_000)
        let phase = phaseTime * (2 * Double.pi * frequency)
        let shakeX = shake * 0.55 * sin(phase)
        let shakeY = shake * 0.35 * sin(phase * 1.37 + 0.7)
        let shakeZ = shake * 0.25 * sin(phase * 0.73 + 1.9)

        let offset = RenderVector3(
            x: curve.lateralOffset + shakeX,
            y: vertical + shakeY,
            z: foreAft + shakeZ
        )
        pose.position = Self.add(pose.position, offset)
        pose.target = Self.add(pose.target, offset)
        pose.rollRadians += curve.roll
        return Self.sanitized(pose)
    }

    private func beginTransition() {
        transitionStartPose = currentBasePose
        transitionTargetPose = Self.preset(for: viewMode)
        transitionElapsedSeconds = 0
        let duration = Self.setting(settings.transitionDurationSeconds, maximum: 10, fallback: 0.65)
        if duration <= 0 { currentBasePose = transitionTargetPose }
    }

    private func advanceTransition(by deltaTime: Double) {
        let duration = Self.setting(settings.transitionDurationSeconds, maximum: 10, fallback: 0.65)
        guard duration > 0 else {
            currentBasePose = transitionTargetPose
            return
        }
        transitionElapsedSeconds = min(duration, transitionElapsedSeconds + deltaTime)
        let linear = transitionElapsedSeconds / duration
        let eased = linear * linear * (3 - 2 * linear)
        currentBasePose = Self.interpolate(transitionStartPose, transitionTargetPose, amount: eased)
    }

    private func curveResponse(speed: Double) -> (lateralOffset: Double, roll: Double) {
        guard let direction = motion.curveDirection,
              let rawRadius = motion.curveRadiusMeters,
              rawRadius.isFinite, rawRadius > 0 else { return (0, 0) }
        let radius = max(5, min(rawRadius, 100_000))
        let centripetal = min(speed * speed / radius, 8)
        let strength = centripetal / 8
        let side: Double = direction == .left ? 1 : -1
        let offsetLimit = Self.setting(settings.maximumCurveOffsetMeters, maximum: 0.15, fallback: 0.045)
        let rollLimit = Self.setting(settings.maximumCurveRollRadians, maximum: 0.08, fallback: 0.025)
        return (side * strength * offsetLimit, -side * strength * rollLimit)
    }

    private static func preset(for mode: CameraViewMode) -> CameraPose {
        switch mode {
        case .cab:
            // The eye sits ~2.45 m behind the train's front face, at the
            // driver seat (seat cushion top is 1.55 m above rail; a seated
            // driver's eyes are ~0.77 m above the cushion). Pose y is
            // height above rail, matching the cab geometry: dashboard top
            // ~1.86 m, console/instruments ~1.92-2.17 m, windscreen
            // 2.62-3.34 m. The previous y of 1.55 put the eye at cushion
            // height, staring into the dashboard and the front bulkhead.
            // The E231 cab seats the driver left of centre, so the eye
            // shifts to x -0.35 (user decision 2026-11-08).
            return CameraPose(position: RenderVector3(x: -0.35, y: 2.32, z: -2.45), target: RenderVector3(x: -0.35, y: 2.30, z: 60), fieldOfViewDegrees: 66)
        case .forward:
            // Scenery-only front view (user decision 2026-11-08: the cab
            // interior is no longer shown). The eye floats just ahead of
            // the nose at driver eye height, so the frame is all track
            // and lineside, BVE front-view style.
            return CameraPose(position: RenderVector3(x: 0, y: 2.5, z: 1.6), target: RenderVector3(x: 0, y: 0.9, z: 100), fieldOfViewDegrees: 72)
        case .chase:
            return CameraPose(position: RenderVector3(x: 0, y: 4.0, z: -8.0), target: RenderVector3(x: 0, y: 1.4, z: 24), fieldOfViewDegrees: 68)
        }
    }

    private static func interpolate(_ from: CameraPose, _ to: CameraPose, amount: Double) -> CameraPose {
        func mix(_ a: Double, _ b: Double) -> Double { a + (b - a) * amount }
        return CameraPose(
            position: RenderVector3(x: mix(from.position.x, to.position.x), y: mix(from.position.y, to.position.y), z: mix(from.position.z, to.position.z)),
            target: RenderVector3(x: mix(from.target.x, to.target.x), y: mix(from.target.y, to.target.y), z: mix(from.target.z, to.target.z)),
            fieldOfViewDegrees: mix(from.fieldOfViewDegrees, to.fieldOfViewDegrees),
            rollRadians: mix(from.rollRadians, to.rollRadians)
        )
    }

    private static func add(_ lhs: RenderVector3, _ rhs: RenderVector3) -> RenderVector3 {
        RenderVector3(x: lhs.x + rhs.x, y: lhs.y + rhs.y, z: lhs.z + rhs.z)
    }

    private static func sanitized(_ pose: CameraPose) -> CameraPose {
        func finite(_ value: Double, fallback: Double) -> Double { value.isFinite ? value : fallback }
        return CameraPose(
            position: RenderVector3(x: finite(pose.position.x, fallback: 0), y: finite(pose.position.y, fallback: 0), z: finite(pose.position.z, fallback: 0)),
            target: RenderVector3(x: finite(pose.target.x, fallback: 0), y: finite(pose.target.y, fallback: 1), z: finite(pose.target.z, fallback: 1)),
            fieldOfViewDegrees: clamp(pose.fieldOfViewDegrees, to: 20...110, fallback: 66),
            rollRadians: clamp(pose.rollRadians, to: -0.1...0.1, fallback: 0)
        )
    }

    private static func setting(_ value: Double, maximum: Double, fallback: Double) -> Double {
        clamp(value, to: 0...maximum, fallback: fallback)
    }

    private static func clamp(_ value: Double, to range: ClosedRange<Double>, fallback: Double) -> Double {
        guard value.isFinite else { return fallback }
        return min(range.upperBound, max(range.lowerBound, value))
    }
}
