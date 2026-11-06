import Foundation

/// Deterministic event engine. Call once per host fixed simulation tick, not once per render frame.
public struct MaintenanceEventEngine: Sendable {
    public private(set) var state: MaintenanceEventEngineState
    public let definitions: [MaintenanceEventDefinition]
    public let maximumConcurrentEvents: Int

    public init(
        seed: UInt64,
        definitions: [MaintenanceEventDefinition] = MaintenanceEventCatalog.defaultDefinitions,
        maximumConcurrentEvents: Int = 4
    ) {
        self.state = MaintenanceEventEngineState(randomState: seed)
        self.definitions = definitions.filter(\.isValid)
        self.maximumConcurrentEvents = max(0, maximumConcurrentEvents)
    }

    public init(
        restoring state: MaintenanceEventEngineState,
        definitions: [MaintenanceEventDefinition] = MaintenanceEventCatalog.defaultDefinitions,
        maximumConcurrentEvents: Int = 4
    ) {
        self.state = state
        self.definitions = definitions.filter(\.isValid)
        self.maximumConcurrentEvents = max(0, maximumConcurrentEvents)
    }

    /// Advances event recovery and probabilistic scheduling using one immutable host snapshot.
    /// Per-tick probability is derived from a rate/hour, so changing render FPS does not change it.
    public mutating func advance(
        snapshot: MaintenanceSimulationSnapshot,
        actions: [MaintenanceEventAction] = []
    ) -> MaintenanceTickResult {
        guard isUsable(snapshot) else {
            return makeResult(snapshot: snapshot, started: [], recovered: [])
        }

        let now = snapshot.simulationTimeSeconds
        let actionMap = Dictionary(grouping: actions, by: \.eventInstanceID)
            .mapValues { Set($0.map(\.actionID)) }
        var recovered: [MaintenanceEventInstance] = []
        for index in state.events.indices where state.events[index].status == .active {
            let eventID = state.events[index].id
            state.events[index].recordedRecoveryActionIDs.formUnion(actionMap[eventID] ?? [])
            let event = state.events[index]
            if recoverySatisfied(
                event.recoveryRule,
                event: event,
                now: now,
                weather: snapshot.weather,
                actions: event.recordedRecoveryActionIDs
            ) {
                state.events[index].status = .recovered
                state.events[index].recoveredAtSeconds = now
                recovered.append(state.events[index])
            }
        }

        var started: [MaintenanceEventInstance] = []
        let activeKinds = Set(state.events.filter { $0.status == .active }.map(\.kind))
        let activeCount = state.events.reduce(into: 0) { count, event in
            if event.status == .active { count += 1 }
        }
        var remainingSlots = max(0, maximumConcurrentEvents - activeCount)
        guard remainingSlots > 0 else {
            trimHistoryIfNeeded()
            return makeResult(snapshot: snapshot, started: started, recovered: recovered)
        }

        let timestep = snapshot.fixedTimeStepSeconds
        for definition in definitions.sorted(by: { $0.kind.rawValue < $1.kind.rawValue }) {
            guard remainingSlots > 0,
                  !activeKinds.contains(definition.kind),
                  triggerMatches(definition.trigger, snapshot: snapshot),
                  let scope = selectScope(definition.scopeSelector, snapshot: snapshot) else {
                continue
            }
            let lastTime = state.lastTriggeredAtByKind[definition.kind.rawValue]
            if let lastTime, now - lastTime < definition.cooldownSeconds { continue }

            let rate = definition.occurrenceRatePerHour
            let probability = rate == 0 ? 0 : 1 - exp(-rate * timestep / 3_600)
            guard nextUnitIntervalValue() < min(1, max(0, probability)) else { continue }
            let event = makeEvent(
                definition: definition,
                scope: scope,
                now: now,
                fixedScenario: false
            )
            state.events.append(event)
            state.lastTriggeredAtByKind[definition.kind.rawValue] = now
            started.append(event)
            remainingSlots -= 1
        }
        trimHistoryIfNeeded()
        return makeResult(snapshot: snapshot, started: started, recovered: recovered)
    }

    /// Injects a scripted event for authored scenarios. It bypasses random trigger gates,
    /// but validates identifiers and route-space bounds before creating the same event state.
    @discardableResult
    public mutating func startScenario(
        kind: MaintenanceEventKind,
        scope: MaintenanceEventScope,
        snapshot: MaintenanceSimulationSnapshot
    ) throws -> MaintenanceEventInstance {
        guard isUsable(snapshot) else { throw MaintenanceEventEngineError.invalidSnapshot }
        guard let definition = definitions.first(where: { $0.kind == kind }) else {
            throw MaintenanceEventEngineError.unknownEventKind(kind)
        }
        guard !state.events.contains(where: { $0.kind == kind && $0.status == .active }) else {
            throw MaintenanceEventEngineError.duplicateActiveEvent(kind)
        }
        guard state.events.filter({ $0.status == .active }).count < maximumConcurrentEvents else {
            throw MaintenanceEventEngineError.maximumConcurrentEventsReached
        }
        guard scopeIsValid(scope, snapshot: snapshot) else {
            throw MaintenanceEventEngineError.invalidScope
        }
        let event = makeEvent(definition: definition, scope: scope, now: snapshot.simulationTimeSeconds, fixedScenario: true)
        state.events.append(event)
        state.lastTriggeredAtByKind[kind.rawValue] = snapshot.simulationTimeSeconds
        trimHistoryIfNeeded()
        return event
    }

    private func isUsable(_ snapshot: MaintenanceSimulationSnapshot) -> Bool {
        snapshot.routeID.isEmpty == false && snapshot.routeLengthM.isFinite && snapshot.routeLengthM > 0 &&
        snapshot.simulationTimeSeconds.isFinite && snapshot.fixedTimeStepSeconds.isFinite &&
        snapshot.fixedTimeStepSeconds > 0 &&
        snapshot.trackIDs.allSatisfy { !$0.isEmpty } && Set(snapshot.trackIDs).count == snapshot.trackIDs.count &&
        snapshot.stationIDs.allSatisfy { !$0.isEmpty } && Set(snapshot.stationIDs).count == snapshot.stationIDs.count &&
        snapshot.trains.allSatisfy {
            !$0.trainID.isEmpty && !$0.trackID.isEmpty && snapshot.trackIDs.contains($0.trackID) && $0.positionM.isFinite &&
            $0.positionM >= 0 && $0.positionM <= snapshot.routeLengthM &&
            $0.speedMps.isFinite && $0.speedMps >= 0 && $0.lengthM.isFinite && $0.lengthM > 0
        } && Set(snapshot.trains.map(\.trainID)).count == snapshot.trains.count &&
        snapshot.crossings.allSatisfy {
            !$0.crossingID.isEmpty && !$0.trackID.isEmpty && snapshot.trackIDs.contains($0.trackID) &&
            $0.chainageM.isFinite && $0.chainageM >= 0 && $0.chainageM <= snapshot.routeLengthM
        } && Set(snapshot.crossings.map(\.crossingID)).count == snapshot.crossings.count &&
        snapshot.weather.windSpeedMps.isFinite && snapshot.weather.windSpeedMps >= 0 &&
        snapshot.weather.rainRateMmPerHour.isFinite && snapshot.weather.rainRateMmPerHour >= 0 &&
        snapshot.weather.snowCoverM.isFinite && snapshot.weather.snowCoverM >= 0 &&
        snapshot.weather.visibilityM.isFinite && snapshot.weather.visibilityM >= 0 &&
        snapshot.weather.earthquakeIntensity.isFinite && snapshot.weather.earthquakeIntensity >= 0 &&
        snapshot.weather.earthquakeIntensity <= 1
    }

    private func triggerMatches(_ trigger: MaintenanceTriggerCondition, snapshot: MaintenanceSimulationSnapshot) -> Bool {
        switch trigger {
        case .always:
            return true
        case .atLeastOneTrainMoving:
            return snapshot.trains.contains { $0.isInService && $0.isMoving }
        case .atLeastOneTrainStoppedAtStation:
            return snapshot.trains.contains { $0.isInService && $0.isStopped && $0.stationID != nil }
        case .crossingAvailable:
            return !snapshot.crossings.isEmpty
        case .windAtLeast(let value):
            return snapshot.weather.windSpeedMps >= value
        case .rainAtLeast(let value):
            return snapshot.weather.rainRateMmPerHour >= value
        case .snowCoverAtLeast(let value):
            return snapshot.weather.snowCoverM >= value
        case .visibilityBelow(let value):
            return snapshot.weather.visibilityM < value
        case .earthquakeIntensityAtLeast(let value):
            return snapshot.weather.earthquakeIntensity >= value
        case .scenarioFlagPresent(let flag):
            return snapshot.scenarioFlags.contains(flag)
        }
    }

    private func selectScope(
        _ selector: MaintenanceScopeSelector,
        snapshot: MaintenanceSimulationSnapshot
    ) -> MaintenanceEventScope? {
        let moving = snapshot.trains
            .filter { $0.isInService && $0.isMoving }
            .sorted { $0.trainID < $1.trainID }
            .first
        let stopped = snapshot.trains
            .filter { $0.isInService && $0.isStopped && $0.stationID != nil }
            .sorted { $0.trainID < $1.trainID }
            .first

        switch selector {
        case .movingTrain:
            return moving.map { .train(trainID: $0.trainID) }
        case .stoppedTrainAtStation:
            return stopped.map { .train(trainID: $0.trainID) }
        case .nearestCrossingAhead:
            guard let train = moving else { return nil }
            let ahead = snapshot.crossings
                .filter { crossing in
                    crossing.trackID == train.trackID &&
                    (crossing.chainageM - train.positionM) * train.direction.sign >= 0
                }
                .sorted { lhs, rhs in
                    abs(lhs.chainageM - train.positionM) < abs(rhs.chainageM - train.positionM)
                }
                .first
            guard let crossing = ahead else { return nil }
            return .crossing(crossingID: crossing.crossingID, trackID: crossing.trackID, chainageM: crossing.chainageM)
        case .trackAhead(let distance):
            guard let train = moving, distance.isFinite, distance > 0 else { return nil }
            let end = min(snapshot.routeLengthM, max(0, train.positionM + train.direction.sign * distance))
            return .track(
                trackID: train.trackID,
                startChainageM: min(train.positionM, end),
                endChainageM: max(train.positionM, end)
            )
        case .route:
            return .route(routeID: snapshot.routeID)
        case .network:
            return .network
        case .stationWithStoppedTrain:
            guard let train = stopped, let stationID = train.stationID,
                  snapshot.stationIDs.contains(stationID) else { return nil }
            return .station(stationID: stationID)
        }
    }

    private func scopeIsValid(_ scope: MaintenanceEventScope, snapshot: MaintenanceSimulationSnapshot) -> Bool {
        switch scope {
        case .train(let trainID):
            return snapshot.trains.contains { $0.trainID == trainID }
        case .station(let stationID):
            return snapshot.stationIDs.contains(stationID)
        case .track(let trackID, let start, let end):
            return !trackID.isEmpty && snapshot.trackIDs.contains(trackID) && start.isFinite && end.isFinite &&
                start >= 0 && end >= start && end <= snapshot.routeLengthM
        case .crossing(let crossingID, let trackID, let chainage):
            return snapshot.crossings.contains {
                $0.crossingID == crossingID && $0.trackID == trackID && $0.chainageM == chainage
            }
        case .route(let routeID):
            return routeID == snapshot.routeID
        case .network:
            return true
        }
    }

    private mutating func makeEvent(
        definition: MaintenanceEventDefinition,
        scope: MaintenanceEventScope,
        now: Double,
        fixedScenario: Bool
    ) -> MaintenanceEventInstance {
        let range = definition.duration
        let sampledDuration = range.minimumSeconds + nextUnitIntervalValue() * (range.maximumSeconds - range.minimumSeconds)
        let sequence = state.nextEventSequence
        state.nextEventSequence &+= 1
        let identifier = String(format: "%@-%06llu", definition.kind.rawValue, sequence)
        return MaintenanceEventInstance(
            id: identifier,
            kind: definition.kind,
            scope: scope,
            startedAtSeconds: now,
            durationSeconds: sampledDuration,
            recoveryRule: definition.recoveryRule,
            impact: definition.impact,
            isFixedScenario: fixedScenario
        )
    }

    private mutating func nextUnitIntervalValue() -> Double {
        // SplitMix64: small, deterministic PRNG suitable for reproducible gameplay, not security.
        state.randomState &+= 0x9E3779B97F4A7C15
        var value = state.randomState
        value = (value ^ (value >> 30)) &* 0xBF58476D1CE4E5B9
        value = (value ^ (value >> 27)) &* 0x94D049BB133111EB
        value ^= value >> 31
        return Double(value >> 11) / 9_007_199_254_740_992
    }

    private func recoverySatisfied(
        _ rule: MaintenanceRecoveryRule,
        event: MaintenanceEventInstance,
        now: Double,
        weather: MaintenanceWeatherSnapshot,
        actions: Set<String>
    ) -> Bool {
        switch rule {
        case .eventDurationElapsed:
            return now - event.startedAtSeconds >= event.durationSeconds
        case .elapsedAtLeast(let seconds):
            return seconds.isFinite && now - event.startedAtSeconds >= max(0, seconds)
        case .actionRequired(let actionID):
            return actions.contains(actionID)
        case .weatherMetricAtMost(let metric, let threshold):
            return threshold.isFinite && weather.value(for: metric) <= threshold
        case .all(let rules):
            return rules.allSatisfy {
                recoverySatisfied($0, event: event, now: now, weather: weather, actions: actions)
            }
        case .any(let rules):
            return rules.contains {
                recoverySatisfied($0, event: event, now: now, weather: weather, actions: actions)
            }
        }
    }

    private func makeResult(
        snapshot: MaintenanceSimulationSnapshot,
        started: [MaintenanceEventInstance],
        recovered: [MaintenanceEventInstance]
    ) -> MaintenanceTickResult {
        var effects: [String: MaintenanceTrainEffects] = [:]
        let active = state.events.filter { $0.status == .active }.sorted { $0.id < $1.id }
        for train in snapshot.trains {
            var traction = 1.0
            var braking = 1.0
            var speedMultiplier = 1.0
            var speedCap: Double?
            var dwell = 0.0
            var held = false
            var ids: [String] = []
            var kinds: [MaintenanceEventKind] = []
            for event in active where affects(event.scope, train: train, routeID: snapshot.routeID, radius: event.impact.influenceRadiusM) {
                traction *= event.impact.tractionMultiplier
                braking *= event.impact.brakingMultiplier
                speedMultiplier *= event.impact.maximumSpeedMultiplier
                if let cap = event.impact.speedCapKmh {
                    speedCap = min(speedCap ?? cap, cap)
                }
                dwell += event.impact.additionalDwellSeconds
                held = held || event.impact.holdsDeparture
                ids.append(event.id)
                kinds.append(event.kind)
            }
            effects[train.trainID] = MaintenanceTrainEffects(
                trainID: train.trainID,
                tractionMultiplier: min(2, max(0, traction)),
                brakingMultiplier: min(2, max(0, braking)),
                maximumSpeedMultiplier: min(2, max(0, speedMultiplier)),
                speedCapKmh: speedCap,
                additionalDwellSeconds: dwell,
                departureHeld: held,
                activeEventIDs: ids,
                warningKinds: kinds
            )
        }
        return MaintenanceTickResult(
            fixedTick: snapshot.fixedTick,
            startedEvents: started,
            recoveredEvents: recovered,
            activeEvents: active,
            effectsByTrainID: effects
        )
    }

    private func affects(
        _ scope: MaintenanceEventScope,
        train: MaintenanceTrainSnapshot,
        routeID: String,
        radius: Double?
    ) -> Bool {
        switch scope {
        case .train(let trainID):
            return trainID == train.trainID
        case .station(let stationID):
            return train.stationID == stationID
        case .track(let trackID, let start, let end):
            return train.trackID == trackID && train.positionM >= start && train.positionM <= end
        case .crossing(_, let trackID, let chainage):
            let distance = abs(train.positionM - chainage)
            return train.trackID == trackID && distance <= (radius ?? 0)
        case .route(let scopeRouteID):
            return routeID == scopeRouteID
        case .network:
            return true
        }
    }

    private mutating func trimHistoryIfNeeded() {
        let limit = 512
        guard state.events.count > limit else { return }
        let excess = state.events.count - limit
        let removable = state.events.indices.filter { state.events[$0].status == .recovered }
        let removeSet = Set(removable.prefix(excess))
        state.events = state.events.enumerated().compactMap { index, event in
            removeSet.contains(index) ? nil : event
        }
    }
}

public enum MaintenanceEventCatalog {
    public static let defaultDefinitions: [MaintenanceEventDefinition] = [
        .init(kind: .vehicleTractionFault, trigger: .atLeastOneTrainMoving, scopeSelector: .movingTrain,
              occurrenceRatePerHour: 0.025, cooldownSeconds: 1_800,
              duration: .init(minimumSeconds: 30, maximumSeconds: 150),
              recoveryRule: .all([.eventDurationElapsed, .actionRequired("gameplay_recovery")]),
              impact: .init(tractionMultiplier: 0.45, maximumSpeedMultiplier: 0.8)),
        .init(kind: .vehicleBrakeFault, trigger: .atLeastOneTrainMoving, scopeSelector: .movingTrain,
              occurrenceRatePerHour: 0.008, cooldownSeconds: 3_600,
              duration: .init(minimumSeconds: 45, maximumSeconds: 180),
              recoveryRule: .all([.eventDurationElapsed, .actionRequired("gameplay_recovery")]),
              impact: .init(brakingMultiplier: 0.55, maximumSpeedMultiplier: 0.75)),
        .init(kind: .vehicleDoorFault, trigger: .atLeastOneTrainStoppedAtStation, scopeSelector: .stoppedTrainAtStation,
              occurrenceRatePerHour: 0.012, cooldownSeconds: 2_400,
              duration: .init(minimumSeconds: 20, maximumSeconds: 100),
              recoveryRule: .all([.eventDurationElapsed, .actionRequired("gameplay_recovery")]),
              impact: .init(additionalDwellSeconds: 75, holdsDeparture: true)),
        .init(kind: .stationPlatformSystemFault, trigger: .atLeastOneTrainStoppedAtStation, scopeSelector: .stationWithStoppedTrain,
              occurrenceRatePerHour: 0.004, cooldownSeconds: 3_600,
              duration: .init(minimumSeconds: 30, maximumSeconds: 150),
              recoveryRule: .all([.eventDurationElapsed, .actionRequired("complete_scenario_recovery")]),
              impact: .init(additionalDwellSeconds: 60, holdsDeparture: true)),
        .init(kind: .passengerMedicalIncident, trigger: .atLeastOneTrainStoppedAtStation, scopeSelector: .stationWithStoppedTrain,
              occurrenceRatePerHour: 0.01, cooldownSeconds: 3_600,
              duration: .init(minimumSeconds: 60, maximumSeconds: 240),
              recoveryRule: .all([.eventDurationElapsed, .actionRequired("complete_incident_scenario")]),
              impact: .init(additionalDwellSeconds: 120, holdsDeparture: true)),
        .init(kind: .onboardDisruption, trigger: .atLeastOneTrainMoving, scopeSelector: .movingTrain,
              occurrenceRatePerHour: 0.012, cooldownSeconds: 2_400,
              duration: .init(minimumSeconds: 30, maximumSeconds: 150),
              recoveryRule: .all([.eventDurationElapsed, .actionRequired("complete_incident_scenario")]),
              impact: .init(additionalDwellSeconds: 45)),
        .init(kind: .levelCrossingObstruction, trigger: .crossingAvailable, scopeSelector: .nearestCrossingAhead,
              occurrenceRatePerHour: 0.006, cooldownSeconds: 3_600,
              duration: .init(minimumSeconds: 45, maximumSeconds: 210),
              recoveryRule: .all([.eventDurationElapsed, .actionRequired("clear_scenario_obstruction")]),
              impact: .init(speedCapKmh: 15, holdsDeparture: true, influenceRadiusM: 500)),
        .init(kind: .trackObstruction, trigger: .atLeastOneTrainMoving, scopeSelector: .trackAhead(distanceM: 500),
              occurrenceRatePerHour: 0.006, cooldownSeconds: 3_600,
              duration: .init(minimumSeconds: 30, maximumSeconds: 180),
              recoveryRule: .all([.eventDurationElapsed, .actionRequired("clear_scenario_obstruction")]),
              impact: .init(speedCapKmh: 20, holdsDeparture: true)),
        .init(kind: .signalFailure, trigger: .atLeastOneTrainMoving, scopeSelector: .trackAhead(distanceM: 350),
              occurrenceRatePerHour: 0.005, cooldownSeconds: 3_600,
              duration: .init(minimumSeconds: 30, maximumSeconds: 180),
              recoveryRule: .all([.eventDurationElapsed, .actionRequired("complete_scenario_recovery")]),
              impact: .init(speedCapKmh: 15)),
        .init(kind: .tractionPowerInterruption, trigger: .scenarioFlagPresent("maintenance.powerRisk"), scopeSelector: .route,
              occurrenceRatePerHour: 0.02, cooldownSeconds: 3_600,
              duration: .init(minimumSeconds: 30, maximumSeconds: 180),
              recoveryRule: .all([.eventDurationElapsed, .actionRequired("power_scenario_recovered")]),
              impact: .init(tractionMultiplier: 0, holdsDeparture: true)),
        .init(kind: .precedingTrainDelay, trigger: .atLeastOneTrainMoving, scopeSelector: .route,
              occurrenceRatePerHour: 0.015, cooldownSeconds: 1_800,
              duration: .init(minimumSeconds: 30, maximumSeconds: 180),
              recoveryRule: .eventDurationElapsed,
              impact: .init(additionalDwellSeconds: 25)),
        .init(kind: .heavyRainScenario, trigger: .rainAtLeast(40), scopeSelector: .route,
              occurrenceRatePerHour: 0.02, cooldownSeconds: 1_800,
              duration: .init(minimumSeconds: 60, maximumSeconds: 300),
              recoveryRule: .all([.eventDurationElapsed, .weatherMetricAtMost(.rainRateMmPerHour, 39.9)]),
              impact: .init(tractionMultiplier: 0.9, maximumSpeedMultiplier: 0.9)),
        .init(kind: .strongWindScenario, trigger: .windAtLeast(18), scopeSelector: .route,
              occurrenceRatePerHour: 0.015, cooldownSeconds: 1_800,
              duration: .init(minimumSeconds: 60, maximumSeconds: 300),
              recoveryRule: .all([.eventDurationElapsed, .weatherMetricAtMost(.windSpeedMps, 17.9)]),
              impact: .init(maximumSpeedMultiplier: 0.8, holdsDeparture: true)),
        .init(kind: .heavySnowScenario, trigger: .snowCoverAtLeast(0.03), scopeSelector: .route,
              occurrenceRatePerHour: 0.012, cooldownSeconds: 1_800,
              duration: .init(minimumSeconds: 60, maximumSeconds: 360),
              recoveryRule: .all([.eventDurationElapsed, .weatherMetricAtMost(.snowCoverM, 0.029)]),
              impact: .init(tractionMultiplier: 0.8, maximumSpeedMultiplier: 0.75)),
        .init(kind: .earthquakeScenario, trigger: .earthquakeIntensityAtLeast(0.35), scopeSelector: .route,
              occurrenceRatePerHour: 0.5, cooldownSeconds: 3_600,
              duration: .init(minimumSeconds: 60, maximumSeconds: 420),
              recoveryRule: .all([.eventDurationElapsed, .actionRequired("earthquake_scenario_cleared")]),
              impact: .init(speedCapKmh: 0, holdsDeparture: true)),
        .init(kind: .lightningScenario, trigger: .scenarioFlagPresent("maintenance.lightningRisk"), scopeSelector: .route,
              occurrenceRatePerHour: 0.03, cooldownSeconds: 1_800,
              duration: .init(minimumSeconds: 30, maximumSeconds: 180),
              recoveryRule: .all([.eventDurationElapsed, .actionRequired("lightning_scenario_cleared")]),
              impact: .init(maximumSpeedMultiplier: 0.8))
    ]
}
