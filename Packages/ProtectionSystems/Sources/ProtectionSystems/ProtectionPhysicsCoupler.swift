import Foundation

/// Driver notches before a fictional protection device intervenes.
/// Notch numbers are game controls, not a real brake-handle specification.
public struct FictionalDriverControls: Equatable, Sendable {
    public var throttleNotch: Int
    public var brakeNotch: Int
    public var emergencyBrake: Bool

    public init(throttleNotch: Int, brakeNotch: Int, emergencyBrake: Bool) {
        self.throttleNotch = throttleNotch
        self.brakeNotch = brakeNotch
        self.emergencyBrake = emergencyBrake
    }
}

public enum FictionalProtectionIntervention: String, Codable, Equatable, Sendable {
    case none
    /// Traction cut and full service-brake notch. PLACEHOLDER, not a service-brake curve.
    case serviceBrakeCutTraction
    /// Traction cut and emergency-brake request. PLACEHOLDER, not an EB valve specification.
    case emergencyBrakeCutTraction
}

/// Physics-facing command. The host applies this on its fixed timestep.
/// ATO traction is intentionally ignored: this coupler only tightens braking.
public struct FictionalProtectionPhysicsCommand: Equatable, Sendable {
    public let intervention: FictionalProtectionIntervention
    /// System ids that commanded a brake, sorted. Empty when `intervention` is `none`.
    public let actingSystems: [String]
    public let throttleNotch: Int
    public let brakeNotch: Int
    public let emergencyBrake: Bool
    public let dataStatus: String

    public init(intervention: FictionalProtectionIntervention, actingSystems: [String], throttleNotch: Int, brakeNotch: Int, emergencyBrake: Bool) {
        self.intervention = intervention
        self.actingSystems = actingSystems
        self.throttleNotch = throttleNotch
        self.brakeNotch = brakeNotch
        self.emergencyBrake = emergencyBrake
        self.dataStatus = "PLACEHOLDER"
    }
}

public enum FictionalProtectionPhysicsCoupler {
    /// Acknowledgement-timer and vigilance latches use the emergency request.
    public static let emergencySystemIDs: Set<String> = ["atsS", "eb", "deadman"]
    /// Speed-supervision latches use the service-brake notch and cut traction.
    public static let serviceSystemIDs: Set<String> = ["atsP", "atsPs", "atc", "ato"]

    /// Returns controls that are at least as restrictive as the driver request.
    /// Unknown system ids are ignored. ATO traction demand is not applied.
    public static func apply(
        driver: FictionalDriverControls,
        states: [SystemProtectionState],
        trainID: String,
        maximumServiceBrakeNotch: Int = 7,
        maximumThrottleNotch: Int = 5
    ) -> FictionalProtectionPhysicsCommand {
        let throttleLimit = max(0, maximumThrottleNotch)
        let brakeLimit = max(0, maximumServiceBrakeNotch)
        let driverThrottle = clamp(driver.throttleNotch, upper: throttleLimit)
        let driverBrake = clamp(driver.brakeNotch, upper: brakeLimit)
        let relevant = states.filter { $0.trainID == trainID && $0.brakeCommanded }
        let emergency = relevant.map(\.system).filter(emergencySystemIDs.contains).sorted()
        let service = relevant.map(\.system).filter(serviceSystemIDs.contains).sorted()

        if !emergency.isEmpty {
            return FictionalProtectionPhysicsCommand(
                intervention: .emergencyBrakeCutTraction,
                actingSystems: Array(Set(emergency + service)).sorted(),
                throttleNotch: 0,
                brakeNotch: brakeLimit,
                emergencyBrake: true
            )
        }
        if !service.isEmpty {
            return FictionalProtectionPhysicsCommand(
                intervention: .serviceBrakeCutTraction,
                actingSystems: service,
                throttleNotch: 0,
                brakeNotch: max(driverBrake, brakeLimit),
                emergencyBrake: driver.emergencyBrake
            )
        }
        return FictionalProtectionPhysicsCommand(
            intervention: .none,
            actingSystems: [],
            throttleNotch: driverThrottle,
            brakeNotch: driverBrake,
            emergencyBrake: driver.emergencyBrake
        )
    }

    private static func clamp(_ value: Int, upper: Int) -> Int {
        min(max(value, 0), upper)
    }
}

/// Single-track PLACEHOLDER equipment laid along a driving route.
/// Positions are a repeating game pattern, not surveyed beacon locations.
public enum FictionalLiveProtectionLayout {
    public static let trackID = "fictional-player-route"
    public static let blockLengthM = 1_000.0
    public static let patternLengthM = 4_000.0

    public static func network(routeLengthM: Double) throws -> RailwayNetwork {
        guard routeLengthM.isFinite, routeLengthM >= 100 else {
            throw ProtectionPackageError.invalidValue("fictional protection route length")
        }
        let blocks = try blocksCovering(lengthM: routeLengthM)
        let track = try RailwayTrack(id: trackID, lengthM: routeLengthM, blocks: blocks)
        return try RailwayNetwork(id: "fictional-live-protection", tracks: [track], equipment: try equipment(lengthM: routeLengthM))
    }

    static func blocksCovering(lengthM: Double) throws -> [BlockSection] {
        var blocks: [BlockSection] = []
        var cursor = 0.0
        var index = 0
        while cursor < lengthM - 0.001 {
            var end = min(lengthM, cursor + blockLengthM)
            if lengthM - end < 50 { end = lengthM }
            blocks.append(try BlockSection(id: "fictional-block-\(index)", trackID: trackID, startM: cursor, endM: end))
            cursor = end
            index += 1
        }
        return blocks
    }

    static func equipment(lengthM: Double) throws -> [RouteEquipment] {
        var devices: [RouteEquipment] = []
        var pattern = 0
        var origin = 0.0
        while origin < lengthM - 1 {
            func place(_ device: RouteEquipment) {
                if device.positionM <= lengthM { devices.append(device) }
            }
            let beacon = origin + 650
            if beacon < lengthM {
                place(try RouteEquipment(id: "fictional-ats-s-\(pattern)", trackID: trackID, kind: .atsSBeacon, positionM: beacon))
            }
            let profile = origin + 900
            let target = min(lengthM, profile + 500)
            if profile < target {
                place(try RouteEquipment(
                    id: "fictional-ats-p-\(pattern)", trackID: trackID, kind: .atsPProfileTarget,
                    positionM: profile, targetPositionM: target, targetSpeedKmh: 0
                ))
            }
            let point = origin + 1_600
            if point + 180 <= lengthM {
                place(try RouteEquipment(
                    id: "fictional-ats-ps-\(pattern)", trackID: trackID, kind: .atsPsSpeedBeacon,
                    positionM: point, targetSpeedKmh: 70, supervisionDistanceM: 180
                ))
            }
            let zoneStart = origin + 1_800
            let zoneEnd = origin + 1_950
            if zoneEnd <= lengthM {
                place(try RouteEquipment(
                    id: "fictional-atc-\(pattern)", trackID: trackID, kind: .atcCommandZone,
                    positionM: zoneStart + 20, targetSpeedKmh: 55, zoneStartM: zoneStart, zoneEndM: zoneEnd
                ))
            }
            origin += patternLengthM
            pattern += 1
            if pattern > 10_000 { break }
        }
        return devices
    }
}

public struct FictionalProtectionTickOutcome: Equatable, Sendable {
    public let command: FictionalProtectionPhysicsCommand
    public let states: [SystemProtectionState]
}

/// Steps the fictional protection engine once per host physics tick and returns the brake command.
/// Enabled devices are ATS-S, ATS-P, ATS-Ps, ATC, and EB. ATO traction and the deadman
/// release are not driven here: ATO traction stays unused, and deadman stays held.
public struct FictionalLiveProtectionSession {
    public static let playerTrainID = "PLAYER"
    public let routeLengthM: Double
    private var engine: ProtectionSystemEngine

    public init(routeLengthM: Double) throws {
        let network = try FictionalLiveProtectionLayout.network(routeLengthM: routeLengthM)
        let configuration = try ProtectionEngineConfiguration(
            atcSpeedCommandsByClearBlocks: [0: 0, 1: 45, 2: 75, 3: 120]
        )
        self.routeLengthM = routeLengthM
        self.engine = ProtectionSystemEngine(
            network: network,
            systemsByTrain: [Self.playerTrainID: [.atsS, .atsP, .atsPs, .atc, .eb]],
            configuration: configuration
        )
    }

    public struct Input: Equatable, Sendable {
        public var fixedTick: UInt64
        public var timeSeconds: Double
        public var frontPositionM: Double
        public var speedKmh: Double
        public var trainLengthM: Double
        public var acknowledgeATSS: Bool
        public var driverActivityPulse: Bool
        public var resetAfterStop: Bool
        public var driver: FictionalDriverControls

        public init(
            fixedTick: UInt64,
            timeSeconds: Double,
            frontPositionM: Double,
            speedKmh: Double,
            trainLengthM: Double,
            acknowledgeATSS: Bool = false,
            driverActivityPulse: Bool = false,
            resetAfterStop: Bool = false,
            driver: FictionalDriverControls
        ) {
            self.fixedTick = fixedTick
            self.timeSeconds = timeSeconds
            self.frontPositionM = frontPositionM
            self.speedKmh = speedKmh
            self.trainLengthM = trainLengthM
            self.acknowledgeATSS = acknowledgeATSS
            self.driverActivityPulse = driverActivityPulse
            self.resetAfterStop = resetAfterStop
            self.driver = driver
        }
    }

    public mutating func step(_ input: Input) throws -> FictionalProtectionTickOutcome {
        let position = min(max(input.frontPositionM, 0), routeLengthM)
        let train = try TrainState(
            id: Self.playerTrainID,
            trackID: FictionalLiveProtectionLayout.trackID,
            frontPositionM: position,
            speedKmh: max(0, input.speedKmh),
            lengthM: max(1, input.trainLengthM)
        )
        let frame = try SimulationFrame(
            fixedTick: input.fixedTick,
            timeSeconds: input.timeSeconds,
            trains: [train],
            operatorInputs: [
                Self.playerTrainID: OperatorInput(
                    acknowledgeATSS: input.acknowledgeATSS,
                    driverActivityPulse: input.driverActivityPulse,
                    deadmanHeld: true,
                    resetProtectionAtStop: input.resetAfterStop && input.speedKmh <= 0.1
                )
            ]
        )
        let result = try engine.step(frame)
        let command = FictionalProtectionPhysicsCoupler.apply(
            driver: input.driver,
            states: result.protectionStates,
            trainID: Self.playerTrainID
        )
        return FictionalProtectionTickOutcome(command: command, states: result.protectionStates)
    }
}
