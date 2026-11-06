import Foundation

/// Small platform-neutral vector used at the boundary between simulation data and a scene adapter.
public struct RenderVector3: Sendable, Equatable {
    public var x: Double
    public var y: Double
    public var z: Double

    public init(x: Double, y: Double, z: Double) {
        self.x = x
        self.y = y
        self.z = z
    }
}

/// Local train-frame view presets. The adapter is responsible for transforming this pose into world space.
public enum CameraViewMode: String, CaseIterable, Sendable {
    case cab
    case forward
    case chase
}

public struct CameraPose: Sendable, Equatable {
    public var position: RenderVector3
    public var target: RenderVector3
    public var fieldOfViewDegrees: Double
    public var rollRadians: Double

    public init(position: RenderVector3, target: RenderVector3, fieldOfViewDegrees: Double, rollRadians: Double = 0) {
        self.position = position
        self.target = target
        self.fieldOfViewDegrees = fieldOfViewDegrees
        self.rollRadians = rollRadians
    }
}

public enum CurveDirection: Sendable, Equatable {
    case left
    case right
}

/// Motion values are copied from the simulation; radius is nil when the route is straight or unknown.
public struct TrainMotionSample: Sendable, Equatable {
    public var simulationTimeSeconds: Double
    public var speedMetersPerSecond: Double
    public var longitudinalAccelerationMetersPerSecondSquared: Double
    public var curveRadiusMeters: Double?
    public var curveDirection: CurveDirection?

    public init(
        simulationTimeSeconds: Double,
        speedMetersPerSecond: Double,
        longitudinalAccelerationMetersPerSecondSquared: Double,
        curveRadiusMeters: Double? = nil,
        curveDirection: CurveDirection? = nil
    ) {
        self.simulationTimeSeconds = simulationTimeSeconds
        self.speedMetersPerSecond = speedMetersPerSecond
        self.longitudinalAccelerationMetersPerSecondSquared = longitudinalAccelerationMetersPerSecondSquared
        self.curveRadiusMeters = curveRadiusMeters
        self.curveDirection = curveDirection
    }
}

public enum RenderingWeather: String, CaseIterable, Sendable {
    case dry
    case rain
    case snow
    case fog
}

/// Renderer-oriented environment input, deliberately separate from the train-physics weather model.
public struct EnvironmentInput: Sendable, Equatable {
    /// Local cycle hour in [0, 24); invalid values are normalized by the resolver.
    public var timeOfDayHours: Double
    public var weather: RenderingWeather
    /// 0...1, where 1 is the strongest visual precipitation.
    public var precipitationIntensity: Double
    /// Visibility in meters; nil lets the resolver use its weather default.
    public var visibilityMeters: Double?

    public init(timeOfDayHours: Double, weather: RenderingWeather, precipitationIntensity: Double = 0, visibilityMeters: Double? = nil) {
        self.timeOfDayHours = timeOfDayHours
        self.weather = weather
        self.precipitationIntensity = precipitationIntensity
        self.visibilityMeters = visibilityMeters
    }
}

public enum DeviceThermalCondition: Int, CaseIterable, Sendable {
    case nominal
    case fair
    case serious
    case critical
}
