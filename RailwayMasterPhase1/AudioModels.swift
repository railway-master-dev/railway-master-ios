import Foundation

/// 3D位置。座標系はシミュレーターと統一し、単位はメートル。
public struct AudioVector3: Codable, Hashable, Sendable {
    public var x: Float
    public var y: Float
    public var z: Float

    public init(x: Float = 0, y: Float = 0, z: Float = 0) {
        self.x = x
        self.y = y
        self.z = z
    }

    public func distance(to other: AudioVector3) -> Float {
        let dx = x - other.x
        let dy = y - other.y
        let dz = z - other.z
        return (dx * dx + dy * dy + dz * dz).squareRoot()
    }
}

public enum RailwayWeather: String, Codable, Sendable, Equatable {
    case clear, rain, heavyRain, snow, wind
}

/// オーディオ更新に必要な共通シミュレーション状態。
/// `simulationTime` と `trackDistanceMeters` は巻き戻しを含むシミュレーション時刻・距離。
public struct RailwaySimulationSnapshot: Codable, Sendable {
    public var simulationTime: TimeInterval
    public var speedMetersPerSecond: Float
    public var accelerationMetersPerSecondSquared: Float
    public var motorRPM: Float
    public var tractionLoad: Float
    public var powerNotch: Int
    public var fieldWeakeningRatio: Float
    public var brakeCommand: Float
    public var regenerativeBrakeRatio: Float
    public var trackDistanceMeters: Double
    public var curveRadiusMeters: Float?
    public var isInTunnel: Bool
    public var isOnBridge: Bool
    public var isOnPoints: Bool
    public var doorsOpen: Bool
    public var weather: RailwayWeather
    public var windMetersPerSecond: Float
    public var trainPosition: AudioVector3
    public var listenerPosition: AudioVector3

    public init(
        simulationTime: TimeInterval = 0,
        speedMetersPerSecond: Float = 0,
        accelerationMetersPerSecondSquared: Float = 0,
        motorRPM: Float = 0,
        tractionLoad: Float = 0,
        powerNotch: Int = 0,
        fieldWeakeningRatio: Float = 0,
        brakeCommand: Float = 0,
        regenerativeBrakeRatio: Float = 0,
        trackDistanceMeters: Double = 0,
        curveRadiusMeters: Float? = nil,
        isInTunnel: Bool = false,
        isOnBridge: Bool = false,
        isOnPoints: Bool = false,
        doorsOpen: Bool = false,
        weather: RailwayWeather = .clear,
        windMetersPerSecond: Float = 0,
        trainPosition: AudioVector3 = .init(),
        listenerPosition: AudioVector3 = .init()
    ) {
        self.simulationTime = simulationTime
        self.speedMetersPerSecond = speedMetersPerSecond
        self.accelerationMetersPerSecondSquared = accelerationMetersPerSecondSquared
        self.motorRPM = motorRPM
        self.tractionLoad = tractionLoad
        self.powerNotch = powerNotch
        self.fieldWeakeningRatio = fieldWeakeningRatio
        self.brakeCommand = brakeCommand
        self.regenerativeBrakeRatio = regenerativeBrakeRatio
        self.trackDistanceMeters = trackDistanceMeters
        self.curveRadiusMeters = curveRadiusMeters
        self.isInTunnel = isInTunnel
        self.isOnBridge = isOnBridge
        self.isOnPoints = isOnPoints
        self.doorsOpen = doorsOpen
        self.weather = weather
        self.windMetersPerSecond = windMetersPerSecond
        self.trainPosition = trainPosition
        self.listenerPosition = listenerPosition
    }
}

public enum RailwayAudioProfile: String, CaseIterable, Codable, Sendable, Equatable {
    case realistic
    case quiet
    case night
    case accessibility
}

/// ユーザー設定およびプロファイル由来のミックス値。音量は0...1に制限されます。
public struct RailwayAudioSettings: Codable, Sendable {
    public var profile: RailwayAudioProfile
    public var tractionSoundProfile: RailwayTractionSoundProfile
    public var masterVolume: Float
    public var effectsVolume: Float
    public var ambienceVolume: Float
    public var announcementVolume: Float
    public var tunnelReverbMix: Float
    public var enableCabInteriorSounds: Bool
    public var enableExteriorSounds: Bool

    public init(
        profile: RailwayAudioProfile = .realistic,
        tractionSoundProfile: RailwayTractionSoundProfile = .vvvfIGBT,
        masterVolume: Float = 0.85,
        effectsVolume: Float = 0.8,
        ambienceVolume: Float = 0.55,
        announcementVolume: Float = 1,
        tunnelReverbMix: Float = 0.42,
        enableCabInteriorSounds: Bool = true,
        enableExteriorSounds: Bool = true
    ) {
        self.profile = profile
        self.tractionSoundProfile = tractionSoundProfile
        self.masterVolume = Self.clamp(masterVolume)
        self.effectsVolume = Self.clamp(effectsVolume)
        self.ambienceVolume = Self.clamp(ambienceVolume)
        self.announcementVolume = Self.clamp(announcementVolume)
        self.tunnelReverbMix = Self.clamp(tunnelReverbMix)
        self.enableCabInteriorSounds = enableCabInteriorSounds
        self.enableExteriorSounds = enableExteriorSounds
    }

    public static func defaults(for profile: RailwayAudioProfile) -> RailwayAudioSettings {
        switch profile {
        case .realistic:
            return .init(profile: profile)
        case .quiet:
            return .init(profile: profile, masterVolume: 0.58, effectsVolume: 0.55, ambienceVolume: 0.32)
        case .night:
            return .init(profile: profile, masterVolume: 0.62, effectsVolume: 0.58, ambienceVolume: 0.25, announcementVolume: 0.8)
        case .accessibility:
            return .init(profile: profile, masterVolume: 0.95, effectsVolume: 0.9, ambienceVolume: 0.38, announcementVolume: 1, tunnelReverbMix: 0.25)
        }
    }

    private static func clamp(_ value: Float) -> Float {
        min(1, max(0, value.isFinite ? value : 0))
    }
}

public enum RailwayAudioEventKind: String, Codable, CaseIterable, Sendable, Equatable {
    case departureMelodyNote
    case controllerStep
    case doorOpen, doorClose, doorWarning
    case whistle
    case atsAlert, atsConfirm, emergencyBrakeAlert, inductionTone
    case crossingBell
    case pneumaticBrakeRelease, brakeSqueal
    case pointClatter, railJoint, bridgeRumble
    case stationChime
}

/// ワンショット効果音の要求。出所に応じてpositionを指定すると距離減衰と左右定位が適用されます。
public struct RailwayAudioEvent: Codable, Sendable {
    public var id: String
    public var kind: RailwayAudioEventKind
    public var scheduledTime: TimeInterval
    public var duration: TimeInterval
    public var intensity: Float
    public var frequencyHz: Float?
    public var priority: Int
    public var position: AudioVector3?

    public init(
        id: String = UUID().uuidString,
        kind: RailwayAudioEventKind,
        scheduledTime: TimeInterval,
        duration: TimeInterval = 0.6,
        intensity: Float = 0.7,
        frequencyHz: Float? = nil,
        priority: Int = 3,
        position: AudioVector3? = nil
    ) {
        self.id = id
        self.kind = kind
        self.scheduledTime = scheduledTime.isFinite ? scheduledTime : 0
        self.duration = max(0.05, duration.isFinite ? min(30, duration) : 0.6)
        self.intensity = min(1, max(0, intensity.isFinite ? intensity : 0))
        if let frequencyHz, frequencyHz.isFinite {
            self.frequencyHz = min(12_000, max(20, frequencyHz))
        } else {
            self.frequencyHz = nil
        }
        self.priority = min(10, max(0, priority))
        self.position = position
    }
}
