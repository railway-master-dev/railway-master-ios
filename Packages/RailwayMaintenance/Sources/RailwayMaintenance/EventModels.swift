import Foundation

/// Three broad presentation groups are retained for simple UI filters.
/// Simulation logic uses the more precise `MaintenanceEventDomain` and `MaintenanceEventKind`.
public enum MaintenanceEventFamily: String, Codable, CaseIterable, Hashable, Sendable {
    case abnormal
    case incident
    case disaster
}

/// Specific simulation area; this is deliberately more detailed than the three UI families.
public enum MaintenanceEventDomain: String, Codable, CaseIterable, Hashable, Sendable {
    case rollingStock
    case passengerAndOnboard
    case trackInfrastructure
    case levelCrossing
    case signalling
    case tractionPower
    case weather
    case naturalHazard
    case trafficOperations
    case stationSystems
}

public enum MaintenanceEventKind: String, Codable, CaseIterable, Hashable, Sendable {
    case vehicleTractionFault
    case vehicleBrakeFault
    case vehicleDoorFault
    case stationPlatformSystemFault
    case passengerMedicalIncident
    case onboardDisruption
    case levelCrossingObstruction
    case trackObstruction
    case signalFailure
    case tractionPowerInterruption
    case precedingTrainDelay
    case heavyRainScenario
    case strongWindScenario
    case heavySnowScenario
    case earthquakeScenario
    case lightningScenario

    public var family: MaintenanceEventFamily {
        switch self {
        case .vehicleTractionFault, .vehicleBrakeFault, .vehicleDoorFault,
             .stationPlatformSystemFault, .signalFailure, .tractionPowerInterruption, .precedingTrainDelay,
             .trackObstruction:
            return .abnormal
        case .passengerMedicalIncident, .onboardDisruption, .levelCrossingObstruction:
            return .incident
        case .heavyRainScenario, .strongWindScenario, .heavySnowScenario,
             .earthquakeScenario, .lightningScenario:
            return .disaster
        }
    }

    public var domain: MaintenanceEventDomain {
        switch self {
        case .vehicleTractionFault, .vehicleBrakeFault, .vehicleDoorFault:
            return .rollingStock
        case .stationPlatformSystemFault:
            return .stationSystems
        case .passengerMedicalIncident, .onboardDisruption:
            return .passengerAndOnboard
        case .levelCrossingObstruction:
            return .levelCrossing
        case .trackObstruction:
            return .trackInfrastructure
        case .signalFailure:
            return .signalling
        case .tractionPowerInterruption:
            return .tractionPower
        case .precedingTrainDelay:
            return .trafficOperations
        case .heavyRainScenario, .strongWindScenario, .heavySnowScenario:
            return .weather
        case .earthquakeScenario, .lightningScenario:
            return .naturalHazard
        }
    }
}

/// Chainage coordinates are fictional game-space metres, never a real-world instruction.
public enum MaintenanceEventScope: Codable, Equatable, Sendable {
    case train(trainID: String)
    case station(stationID: String)
    case track(trackID: String, startChainageM: Double, endChainageM: Double)
    case crossing(crossingID: String, trackID: String, chainageM: Double)
    case route(routeID: String)
    case network
}

public enum MaintenanceTriggerCondition: Codable, Equatable, Sendable {
    case always
    case atLeastOneTrainMoving
    case atLeastOneTrainStoppedAtStation
    case crossingAvailable
    case windAtLeast(Double)
    case rainAtLeast(Double)
    case snowCoverAtLeast(Double)
    case visibilityBelow(Double)
    case earthquakeIntensityAtLeast(Double)
    case scenarioFlagPresent(String)
}

public enum MaintenanceScopeSelector: Codable, Equatable, Sendable {
    case movingTrain
    case stoppedTrainAtStation
    case nearestCrossingAhead
    case trackAhead(distanceM: Double)
    case route
    case network
    case stationWithStoppedTrain
}

public struct MaintenanceDurationRange: Codable, Equatable, Sendable {
    public let minimumSeconds: Double
    public let maximumSeconds: Double

    public init(minimumSeconds: Double, maximumSeconds: Double) {
        self.minimumSeconds = minimumSeconds
        self.maximumSeconds = maximumSeconds
    }

    public var isValid: Bool {
        minimumSeconds.isFinite && maximumSeconds.isFinite && minimumSeconds >= 0 && maximumSeconds >= minimumSeconds
    }
}

public indirect enum MaintenanceRecoveryRule: Codable, Equatable, Sendable {
    case eventDurationElapsed
    case elapsedAtLeast(Double)
    case actionRequired(String)
    case weatherMetricAtMost(MaintenanceWeatherMetric, Double)
    case all([MaintenanceRecoveryRule])
    case any([MaintenanceRecoveryRule])
}

public struct MaintenanceEventImpact: Codable, Equatable, Sendable {
    /// 1 is no change. Multipliers are fictional gameplay values, not measured vehicle performance.
    public let tractionMultiplier: Double
    public let brakingMultiplier: Double
    public let maximumSpeedMultiplier: Double
    public let speedCapKmh: Double?
    public let additionalDwellSeconds: Double
    public let holdsDeparture: Bool
    /// A crossing event may affect approaching trains within this radius; nil means exact scope only.
    public let influenceRadiusM: Double?

    public init(
        tractionMultiplier: Double = 1,
        brakingMultiplier: Double = 1,
        maximumSpeedMultiplier: Double = 1,
        speedCapKmh: Double? = nil,
        additionalDwellSeconds: Double = 0,
        holdsDeparture: Bool = false,
        influenceRadiusM: Double? = nil
    ) {
        self.tractionMultiplier = tractionMultiplier
        self.brakingMultiplier = brakingMultiplier
        self.maximumSpeedMultiplier = maximumSpeedMultiplier
        self.speedCapKmh = speedCapKmh
        self.additionalDwellSeconds = additionalDwellSeconds
        self.holdsDeparture = holdsDeparture
        self.influenceRadiusM = influenceRadiusM
    }
}

public struct MaintenanceEventDefinition: Codable, Equatable, Sendable {
    public let kind: MaintenanceEventKind
    public let trigger: MaintenanceTriggerCondition
    public let scopeSelector: MaintenanceScopeSelector
    /// Poisson occurrence rate per simulation hour, only while `trigger` is true.
    public let occurrenceRatePerHour: Double
    public let cooldownSeconds: Double
    public let duration: MaintenanceDurationRange
    public let recoveryRule: MaintenanceRecoveryRule
    public let impact: MaintenanceEventImpact

    public init(
        kind: MaintenanceEventKind,
        trigger: MaintenanceTriggerCondition,
        scopeSelector: MaintenanceScopeSelector,
        occurrenceRatePerHour: Double,
        cooldownSeconds: Double,
        duration: MaintenanceDurationRange,
        recoveryRule: MaintenanceRecoveryRule,
        impact: MaintenanceEventImpact
    ) {
        self.kind = kind
        self.trigger = trigger
        self.scopeSelector = scopeSelector
        self.occurrenceRatePerHour = occurrenceRatePerHour
        self.cooldownSeconds = cooldownSeconds
        self.duration = duration
        self.recoveryRule = recoveryRule
        self.impact = impact
    }

    public var isValid: Bool {
        occurrenceRatePerHour.isFinite && occurrenceRatePerHour >= 0 &&
        cooldownSeconds.isFinite && cooldownSeconds >= 0 && duration.isValid &&
        impact.tractionMultiplier.isFinite && impact.tractionMultiplier >= 0 &&
        impact.brakingMultiplier.isFinite && impact.brakingMultiplier >= 0 &&
        impact.maximumSpeedMultiplier.isFinite && impact.maximumSpeedMultiplier >= 0 &&
        (impact.speedCapKmh == nil || (impact.speedCapKmh!.isFinite && impact.speedCapKmh! >= 0)) &&
        impact.additionalDwellSeconds.isFinite && impact.additionalDwellSeconds >= 0 &&
        (impact.influenceRadiusM == nil || (impact.influenceRadiusM!.isFinite && impact.influenceRadiusM! >= 0))
    }
}

public enum MaintenanceEventStatus: String, Codable, CaseIterable, Sendable {
    case active
    case recovered
}

public struct MaintenanceEventInstance: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let kind: MaintenanceEventKind
    public let family: MaintenanceEventFamily
    public let domain: MaintenanceEventDomain
    public let scope: MaintenanceEventScope
    public let startedAtSeconds: Double
    public let durationSeconds: Double
    public let recoveryRule: MaintenanceRecoveryRule
    public let impact: MaintenanceEventImpact
    public var status: MaintenanceEventStatus
    public var recoveredAtSeconds: Double?
    public var recordedRecoveryActionIDs: Set<String>
    public let isFixedScenario: Bool

    public init(
        id: String,
        kind: MaintenanceEventKind,
        scope: MaintenanceEventScope,
        startedAtSeconds: Double,
        durationSeconds: Double,
        recoveryRule: MaintenanceRecoveryRule,
        impact: MaintenanceEventImpact,
        status: MaintenanceEventStatus = .active,
        recoveredAtSeconds: Double? = nil,
        recordedRecoveryActionIDs: Set<String> = [],
        isFixedScenario: Bool = false
    ) {
        self.id = id
        self.kind = kind
        self.family = kind.family
        self.domain = kind.domain
        self.scope = scope
        self.startedAtSeconds = startedAtSeconds
        self.durationSeconds = durationSeconds
        self.recoveryRule = recoveryRule
        self.impact = impact
        self.status = status
        self.recoveredAtSeconds = recoveredAtSeconds
        self.recordedRecoveryActionIDs = recordedRecoveryActionIDs
        self.isFixedScenario = isFixedScenario
    }

    public var plannedRecoveryTimeSeconds: Double { startedAtSeconds + durationSeconds }
}

public struct MaintenanceEventAction: Codable, Equatable, Sendable {
    public let eventInstanceID: String
    public let actionID: String

    public init(eventInstanceID: String, actionID: String) {
        self.eventInstanceID = eventInstanceID
        self.actionID = actionID
    }
}

public struct MaintenanceTrainEffects: Codable, Equatable, Sendable {
    public let trainID: String
    public let tractionMultiplier: Double
    public let brakingMultiplier: Double
    public let maximumSpeedMultiplier: Double
    public let speedCapKmh: Double?
    public let additionalDwellSeconds: Double
    public let departureHeld: Bool
    public let activeEventIDs: [String]
    public let warningKinds: [MaintenanceEventKind]

    public static func neutral(trainID: String) -> MaintenanceTrainEffects {
        MaintenanceTrainEffects(
            trainID: trainID,
            tractionMultiplier: 1,
            brakingMultiplier: 1,
            maximumSpeedMultiplier: 1,
            speedCapKmh: nil,
            additionalDwellSeconds: 0,
            departureHeld: false,
            activeEventIDs: [],
            warningKinds: []
        )
    }
}

public struct MaintenanceEventEngineState: Codable, Equatable, Sendable {
    public var randomState: UInt64
    public var nextEventSequence: UInt64
    public var lastTriggeredAtByKind: [String: Double]
    public var events: [MaintenanceEventInstance]

    public init(
        randomState: UInt64,
        nextEventSequence: UInt64 = 1,
        lastTriggeredAtByKind: [String: Double] = [:],
        events: [MaintenanceEventInstance] = []
    ) {
        self.randomState = randomState
        self.nextEventSequence = nextEventSequence
        self.lastTriggeredAtByKind = lastTriggeredAtByKind
        self.events = events
    }

    public var activeEvents: [MaintenanceEventInstance] {
        events.filter { $0.status == .active }
    }
}

public struct MaintenanceTickResult: Codable, Equatable, Sendable {
    public let fixedTick: UInt64
    public let startedEvents: [MaintenanceEventInstance]
    public let recoveredEvents: [MaintenanceEventInstance]
    public let activeEvents: [MaintenanceEventInstance]
    public let effectsByTrainID: [String: MaintenanceTrainEffects]

    public func effects(for trainID: String) -> MaintenanceTrainEffects {
        effectsByTrainID[trainID] ?? .neutral(trainID: trainID)
    }
}

public enum MaintenanceEventEngineError: Error, Equatable, Sendable {
    case invalidSnapshot
    case unknownEventKind(MaintenanceEventKind)
    case invalidScope
    case duplicateActiveEvent(MaintenanceEventKind)
    case maximumConcurrentEventsReached
}
