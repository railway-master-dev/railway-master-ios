import Foundation

private struct TrainRuntime {
    let plan: AITrainPlan
    var positionM: Double
    var speedMps: Double = 0
    var phase: AITrainPhase = .scheduled
    var nextStopIndex = 0
    var dwellRemainingSeconds = 0.0
    var isHeldForSeparation = false
    var actualDepartureTimeSeconds: Double? = nil
}

private struct RoadVehicleRuntime {
    let plan: RoadVehiclePlan
    var positionM: Double
    var speedMps: Double = 0
    var phase: RoadVehiclePhase = .scheduled
    var isHeldForSeparation = false
}

private struct PassengerRuntime {
    let trip: PlatformPassengerTrip
    var alongPlatformM: Double
    var phase: PlatformPassengerPhase = .scheduled
}

private struct Occupant {
    let id: String
    let lengthM: Double
    let aiIndex: Int?
    let isPlayer: Bool
    var positionM: Double
}

/// Deterministic traffic-only simulation. It is a visual/gameplay subsystem, not
/// operational railway control, signalling, dispatch, or safety software.
public struct TrafficSimulationEngine: Sendable {
    public let scenario: TrafficScenario
    public private(set) var simulationTimeSeconds: Double = 0
    public private(set) var fixedTick: UInt64 = 0

    private var accumulatorSeconds = 0.0
    private var trains: [TrainRuntime]
    private var roadVehicles: [RoadVehicleRuntime]
    private var passengers: [PassengerRuntime]

    /// Rejects malformed scenario input so invalid settings are not silently repaired.
    public init(scenario: TrafficScenario) throws {
        let issues = scenario.validate()
        guard issues.isEmpty else { throw TrafficSimulationError.invalidScenario(issues) }
        self.scenario = scenario
        self.trains = scenario.trains.map { TrainRuntime(plan: $0, positionM: $0.startPositionM) }
        self.roadVehicles = scenario.roadVehicles.map { RoadVehicleRuntime(plan: $0, positionM: $0.startPositionM) }
        self.passengers = scenario.passengerTrips.map { PassengerRuntime(trip: $0, alongPlatformM: $0.startOffsetM) }
    }

    /// Standalone fixed-step driver. Different render-frame cadences produce the
    /// same simulation ticks when they supply the same total elapsed time.
    @discardableResult
    public mutating func advance(realDeltaSeconds: Double, playerTrain: SharedTrainState? = nil) throws -> TrafficSnapshot {
        guard realDeltaSeconds.isFinite, realDeltaSeconds >= 0 else { throw TrafficSimulationError.invalidDelta }
        try validate(playerTrain: playerTrain)
        let step = scenario.fixedTimeStepSeconds
        let candidateAccumulator = accumulatorSeconds + realDeltaSeconds
        guard candidateAccumulator.isFinite,
              candidateAccumulator / step <= 36_000 + 1e-8 else { throw TrafficSimulationError.invalidDelta }
        let stepCount = Int((candidateAccumulator + step * 1e-10) / step)
        if stepCount > 0 {
            for _ in 0..<stepCount {
                simulationTimeSeconds += step
                fixedTick &+= 1
                advanceOneTick(at: simulationTimeSeconds, playerTrain: playerTrain)
            }
        }
        accumulatorSeconds = candidateAccumulator - Double(stepCount) * step
        if accumulatorSeconds < 0 && accumulatorSeconds > -step * 1e-8 { accumulatorSeconds = 0 }
        return makeSnapshot(playerTrain: playerTrain)
    }

    /// Host-integration entry point. The host supplies the same route identity,
    /// simulation time, and fixed-tick concepts used by its shared train snapshot.
    /// If ticks were skipped between calls, the engine deterministically catches up
    /// using the latest sampled player-train state for those ticks.
    @discardableResult
    public mutating func advance(
        to clock: SharedSimulationClock,
        route: SharedRouteReference,
        playerTrain: SharedTrainState? = nil
    ) throws -> TrafficSnapshot {
        guard route.routeID == scenario.routeID,
              route.lengthM.isFinite,
              abs(route.lengthM - scenario.routeLengthM) <= 0.001 else {
            throw TrafficSimulationError.invalidSharedRoute
        }
        let fixedStepTolerance = scenario.fixedTimeStepSeconds.ulp * 4
        guard clock.simulationTimeSeconds.isFinite,
              clock.simulationTimeSeconds >= 0,
              clock.fixedTimeStepSeconds.isFinite,
              abs(clock.fixedTimeStepSeconds - scenario.fixedTimeStepSeconds) <= fixedStepTolerance else {
            throw TrafficSimulationError.invalidSharedClock
        }
        guard clock.fixedTick >= fixedTick,
              clock.simulationTimeSeconds + 1e-9 >= simulationTimeSeconds else {
            throw TrafficSimulationError.clockMovedBackward
        }
        let tickDelta = clock.fixedTick - fixedTick
        guard tickDelta <= 36_000 else { throw TrafficSimulationError.invalidSharedClock }
        let tickTime = Double(clock.fixedTick) * scenario.fixedTimeStepSeconds
        let timeMagnitude = max(abs(clock.simulationTimeSeconds), abs(tickTime))
        let accumulatedRoundoff = (timeMagnitude.ulp + scenario.fixedTimeStepSeconds.ulp) * Double(clock.fixedTick)
        let floatingTolerance = max(1e-15, max(timeMagnitude.ulp * 4, accumulatedRoundoff * 2))
        let timeTolerance = min(scenario.fixedTimeStepSeconds * 1e-4, floatingTolerance)
        guard abs(clock.simulationTimeSeconds - tickTime) <= timeTolerance,
              tickDelta > 0 || abs(clock.simulationTimeSeconds - simulationTimeSeconds) <= timeTolerance else {
            throw TrafficSimulationError.invalidSharedClock
        }
        try validate(playerTrain: playerTrain)

        if tickDelta > 0 {
            for offset in 1...tickDelta {
                let tickNumber = clock.fixedTick - (tickDelta - offset)
                let tickTimeAtStep = Double(tickNumber) * scenario.fixedTimeStepSeconds
                simulationTimeSeconds = tickTimeAtStep
                fixedTick = tickNumber
                advanceOneTick(at: tickTimeAtStep, playerTrain: playerTrain)
            }
        }
        simulationTimeSeconds = clock.simulationTimeSeconds
        accumulatorSeconds = 0
        return makeSnapshot(playerTrain: playerTrain)
    }

    public func snapshot(playerTrain: SharedTrainState? = nil) -> TrafficSnapshot {
        makeSnapshot(playerTrain: playerTrain)
    }

    public func stateSnapshot() -> TrafficSimulationStateSnapshot {
        TrafficSimulationStateSnapshot(
            revision: TrafficSimulationStateSnapshot.currentRevision,
            scenarioID: scenario.scenarioID,
            routeID: scenario.routeID,
            simulationTimeSeconds: simulationTimeSeconds,
            fixedTick: fixedTick,
            accumulatorSeconds: accumulatorSeconds,
            trains: trains.map {
                TrafficTrainRuntimeSnapshot(id: $0.plan.id, positionM: $0.positionM, speedMps: $0.speedMps,
                                            phase: $0.phase, nextStopIndex: $0.nextStopIndex,
                                            dwellRemainingSeconds: $0.dwellRemainingSeconds,
                                            isHeldForSeparation: $0.isHeldForSeparation,
                                            actualDepartureTimeSeconds: $0.actualDepartureTimeSeconds)
            },
            roadVehicles: roadVehicles.map {
                TrafficRoadVehicleRuntimeSnapshot(id: $0.plan.id, positionM: $0.positionM,
                                                  speedMps: $0.speedMps, phase: $0.phase,
                                                  isHeldForSeparation: $0.isHeldForSeparation)
            },
            passengers: passengers.map {
                TrafficPassengerRuntimeSnapshot(id: $0.trip.id, alongPlatformM: $0.alongPlatformM, phase: $0.phase)
            }
        )
    }

    /// Restores runtime phases only into an engine built from the same trusted scenario definition.
    public mutating func restoreState(from saved: TrafficSimulationStateSnapshot) throws {
        let step = scenario.fixedTimeStepSeconds
        let tickTime = Double(saved.fixedTick) * step
        guard saved.revision == TrafficSimulationStateSnapshot.currentRevision,
              saved.scenarioID == scenario.scenarioID, saved.routeID == scenario.routeID,
              saved.simulationTimeSeconds.isFinite, saved.simulationTimeSeconds >= 0,
              saved.fixedTick <= 120_000_000_000,
              abs(saved.simulationTimeSeconds - tickTime) <= max(1e-9, tickTime.ulp * 8),
              saved.accumulatorSeconds.isFinite, saved.accumulatorSeconds >= 0, saved.accumulatorSeconds < step,
              saved.trains.count == trains.count, saved.roadVehicles.count == roadVehicles.count,
              saved.passengers.count == passengers.count,
              zip(saved.trains, trains).allSatisfy({ pair in pair.0.id == pair.1.plan.id }),
              zip(saved.roadVehicles, roadVehicles).allSatisfy({ pair in pair.0.id == pair.1.plan.id }),
              zip(saved.passengers, passengers).allSatisfy({ pair in pair.0.id == pair.1.trip.id }) else {
            throw TrafficSimulationError.invalidRuntimeState
        }

        let pathLengthByID = Dictionary(uniqueKeysWithValues: scenario.routePaths.map { ($0.id, $0.lengthM) })
        let roadByID = Dictionary(uniqueKeysWithValues: scenario.roads.map { ($0.id, $0) })
        for (state, runtime) in zip(saved.trains, trains) {
            let track = scenario.tracks.first(where: { $0.id == runtime.plan.trackID })
            let pathLength = track.flatMap { pathLengthByID[$0.routePathID] } ?? scenario.routeLengthM
            guard state.positionM.isFinite, (0...pathLength).contains(state.positionM),
                  state.speedMps.isFinite, (0...runtime.plan.maximumSpeedMps).contains(state.speedMps),
                  (0...runtime.plan.stops.count).contains(state.nextStopIndex),
                  state.dwellRemainingSeconds.isFinite, (0...86_400).contains(state.dwellRemainingSeconds),
                  state.actualDepartureTimeSeconds.map({ $0.isFinite && (0...saved.simulationTimeSeconds).contains($0) }) ?? true,
                  state.phase != .dwelling || state.dwellRemainingSeconds > 0 else {
                throw TrafficSimulationError.invalidRuntimeState
            }
        }
        for (state, runtime) in zip(saved.roadVehicles, roadVehicles) {
            let pathLength = roadByID[runtime.plan.roadID].flatMap { pathLengthByID[$0.routePathID] } ?? scenario.routeLengthM
            guard state.positionM.isFinite, (0...pathLength).contains(state.positionM),
                  state.speedMps.isFinite, (0...runtime.plan.targetSpeedMps).contains(state.speedMps) else {
                throw TrafficSimulationError.invalidRuntimeState
            }
        }
        let platformLengthByID = Dictionary(uniqueKeysWithValues: scenario.platforms.map { ($0.id, $0.lengthM) })
        for (state, runtime) in zip(saved.passengers, passengers) {
            guard let length = platformLengthByID[runtime.trip.platformID],
                  state.alongPlatformM.isFinite, (0...length).contains(state.alongPlatformM) else {
                throw TrafficSimulationError.invalidRuntimeState
            }
        }

        for index in trains.indices {
            trains[index].positionM = saved.trains[index].positionM
            trains[index].speedMps = saved.trains[index].speedMps
            trains[index].phase = saved.trains[index].phase
            trains[index].nextStopIndex = saved.trains[index].nextStopIndex
            trains[index].dwellRemainingSeconds = saved.trains[index].dwellRemainingSeconds
            trains[index].isHeldForSeparation = saved.trains[index].isHeldForSeparation
            trains[index].actualDepartureTimeSeconds = saved.trains[index].actualDepartureTimeSeconds
        }
        for index in roadVehicles.indices {
            roadVehicles[index].positionM = saved.roadVehicles[index].positionM
            roadVehicles[index].speedMps = saved.roadVehicles[index].speedMps
            roadVehicles[index].phase = saved.roadVehicles[index].phase
            roadVehicles[index].isHeldForSeparation = saved.roadVehicles[index].isHeldForSeparation
        }
        for index in passengers.indices {
            passengers[index].alongPlatformM = saved.passengers[index].alongPlatformM
            passengers[index].phase = saved.passengers[index].phase
        }
        simulationTimeSeconds = saved.simulationTimeSeconds
        fixedTick = saved.fixedTick
        accumulatorSeconds = saved.accumulatorSeconds
    }

    private func validate(playerTrain: SharedTrainState?) throws {
        guard let playerTrain else { return }
        guard let track = scenario.tracks.first(where: { $0.id == playerTrain.trackID }) else {
            throw TrafficSimulationError.invalidPlayerTrain
        }
        let pathLength = scenario.routePaths.first(where: { $0.id == track.routePathID })?.lengthM ?? scenario.routeLengthM
        guard !playerTrain.trainID.isEmpty,
              playerTrain.positionM.isFinite,
              playerTrain.positionM >= 0,
              playerTrain.positionM <= pathLength,
              playerTrain.speedMps.isFinite,
              playerTrain.speedMps >= 0,
              playerTrain.lengthM.isFinite,
              playerTrain.lengthM > 0,
              playerTrain.direction == track.direction else {
            throw TrafficSimulationError.invalidPlayerTrain
        }
    }

    private mutating func advanceOneTick(at time: Double, playerTrain: SharedTrainState?) {
        let dt = scenario.fixedTimeStepSeconds
        for index in trains.indices {
            trains[index].isHeldForSeparation = false
            if trains[index].phase == .scheduled && trains[index].plan.departureTimeSeconds <= time + 1e-10 {
                if canDepartTrain(index, playerTrain: playerTrain) {
                    trains[index].phase = .running
                    trains[index].actualDepartureTimeSeconds = time
                } else {
                    trains[index].isHeldForSeparation = true
                }
            }
            switch trains[index].phase {
            case .running:
                advanceTrain(index, dt: dt, time: time)
            case .dwelling:
                trains[index].dwellRemainingSeconds = max(0, trains[index].dwellRemainingSeconds - dt)
                if trains[index].dwellRemainingSeconds <= 1e-10 {
                    trains[index].dwellRemainingSeconds = 0
                    trains[index].phase = .running
                }
            case .scheduled, .completed:
                break
            }
        }

        for index in roadVehicles.indices {
            roadVehicles[index].isHeldForSeparation = false
            if roadVehicles[index].phase == .scheduled && roadVehicles[index].plan.departureTimeSeconds <= time + 1e-10 {
                if canDepartRoadVehicle(index) {
                    roadVehicles[index].phase = .moving
                } else {
                    roadVehicles[index].isHeldForSeparation = true
                }
            }
            if roadVehicles[index].phase == .moving {
                advanceRoadVehicle(index, dt: dt)
            }
        }

        for index in passengers.indices {
            let trip = passengers[index].trip
            if passengers[index].phase == .scheduled && trip.startTimeSeconds <= time + 1e-10 {
                passengers[index].phase = .walking
            }
            guard passengers[index].phase == .walking else { continue }
            let delta = trip.destinationOffsetM - passengers[index].alongPlatformM
            let movement = trip.walkingSpeedMps * dt
            if abs(delta) <= movement + 1e-10 {
                passengers[index].alongPlatformM = trip.destinationOffsetM
                passengers[index].phase = .waiting
            } else {
                passengers[index].alongPlatformM += (delta > 0 ? 1 : -1) * movement
            }
        }

        enforceTrainSeparation(playerTrain: playerTrain)
        enforceRoadVehicleSeparation()
    }

    private func canDepartTrain(_ index: Int, playerTrain: SharedTrainState?) -> Bool {
        let plan = trains[index].plan
        let requiredGap = scenario.minimumTrainGapM
        for other in trains where other.plan.id != plan.id && other.plan.trackID == plan.trackID && other.phase != .scheduled {
            let requiredCenterSpacing = requiredGap + (plan.lengthM + other.plan.lengthM) * 0.5
            if abs(plan.startPositionM - other.positionM) < requiredCenterSpacing - 1e-8 { return false }
        }
        if let playerTrain, playerTrain.trackID == plan.trackID {
            let requiredCenterSpacing = requiredGap + (plan.lengthM + playerTrain.lengthM) * 0.5
            if abs(plan.startPositionM - playerTrain.positionM) < requiredCenterSpacing - 1e-8 { return false }
        }
        return true
    }

    private func canDepartRoadVehicle(_ index: Int) -> Bool {
        let plan = roadVehicles[index].plan
        for other in roadVehicles where other.plan.id != plan.id && other.plan.roadID == plan.roadID && other.phase != .scheduled {
            let requiredCenterSpacing = scenario.minimumRoadVehicleGapM + (plan.lengthM + other.plan.lengthM) * 0.5
            if abs(plan.startPositionM - other.positionM) < requiredCenterSpacing - 1e-8 { return false }
        }
        return true
    }

    private mutating func advanceTrain(_ index: Int, dt: Double, time: Double) {
        let plan = trains[index].plan
        guard let track = scenario.tracks.first(where: { $0.id == plan.trackID }) else { return }
        let direction = track.direction
        let hasStop = trains[index].nextStopIndex < plan.stops.count
        let targetM = hasStop ? plan.stops[trains[index].nextStopIndex].positionM : plan.destinationPositionM
        let distanceM = max(0, (targetM - trains[index].positionM) * direction.sign)

        if distanceM <= 0.35 && trains[index].speedMps <= max(plan.brakingDecelerationMps2 * dt, 0.25) {
            arriveTrain(at: targetM, hasStop: hasStop, index: index)
            return
        }

        let brakingSpeed = sqrt(max(0, 2 * plan.brakingDecelerationMps2 * distanceM))
        var desiredSpeed = min(plan.maximumSpeedMps, brakingSpeed)
        if plan.operationKind == .passengerService, let plannedDuration = plan.scheduledTripDurationSeconds {
            let departure = trains[index].actualDepartureTimeSeconds ?? plan.departureTimeSeconds
            let elapsed = max(0, time - departure)
            let futureDwell = plan.stops.dropFirst(trains[index].nextStopIndex).reduce(0.0) { $0 + $1.dwellSeconds }
            let remainingMovingSeconds = max(dt, plannedDuration - elapsed - futureDwell)
            let remainingRouteM = abs(plan.destinationPositionM - trains[index].positionM)
            desiredSpeed = min(desiredSpeed, remainingRouteM / remainingMovingSeconds)
        }
        if trains[index].speedMps < desiredSpeed {
            trains[index].speedMps = min(desiredSpeed, trains[index].speedMps + plan.accelerationMps2 * dt)
        } else {
            trains[index].speedMps = max(desiredSpeed, trains[index].speedMps - plan.brakingDecelerationMps2 * dt)
        }
        let movementM = trains[index].speedMps * dt
        if movementM + 1e-10 >= distanceM {
            arriveTrain(at: targetM, hasStop: hasStop, index: index)
        } else {
            trains[index].positionM += direction.sign * movementM
        }
    }

    private mutating func arriveTrain(at targetM: Double, hasStop: Bool, index: Int) {
        trains[index].positionM = targetM
        trains[index].speedMps = 0
        if hasStop {
            let stop = trains[index].plan.stops[trains[index].nextStopIndex]
            trains[index].nextStopIndex += 1
            trains[index].dwellRemainingSeconds = stop.dwellSeconds
            if stop.dwellSeconds > 0 {
                trains[index].phase = .dwelling
            }
        } else {
            trains[index].phase = .completed
        }
    }

    private mutating func advanceRoadVehicle(_ index: Int, dt: Double) {
        let plan = roadVehicles[index].plan
        guard let road = scenario.roads.first(where: { $0.id == plan.roadID }) else { return }
        let distanceM = max(0, (plan.destinationPositionM - roadVehicles[index].positionM) * road.direction.sign)
        if distanceM <= 0.25 {
            roadVehicles[index].positionM = plan.destinationPositionM
            roadVehicles[index].speedMps = 0
            roadVehicles[index].phase = .completed
            return
        }
        roadVehicles[index].speedMps = min(plan.targetSpeedMps, roadVehicles[index].speedMps + plan.accelerationMps2 * dt)
        let movementM = roadVehicles[index].speedMps * dt
        if movementM + 1e-10 >= distanceM {
            roadVehicles[index].positionM = plan.destinationPositionM
            roadVehicles[index].speedMps = 0
            roadVehicles[index].phase = .completed
        } else {
            roadVehicles[index].positionM += road.direction.sign * movementM
        }
    }

    private mutating func enforceTrainSeparation(playerTrain: SharedTrainState?) {
        for track in scenario.tracks {
            let pathLength = scenario.routePaths.first(where: { $0.id == track.routePathID })!.lengthM
            var occupants: [Occupant] = trains.indices.compactMap { index in
                guard trains[index].plan.trackID == track.id, trains[index].phase != .scheduled else { return nil }
                return Occupant(id: trains[index].plan.id, lengthM: trains[index].plan.lengthM, aiIndex: index, isPlayer: false, positionM: trains[index].positionM)
            }
            if let playerTrain, playerTrain.trackID == track.id {
                occupants.append(Occupant(id: playerTrain.trainID, lengthM: playerTrain.lengthM, aiIndex: nil, isPlayer: true, positionM: playerTrain.positionM))
            }
            occupants.sort {
                if $0.positionM == $1.positionM { return $0.id < $1.id }
                return track.direction == .increasing ? $0.positionM > $1.positionM : $0.positionM < $1.positionM
            }
            guard occupants.count > 1 else { continue }

            for index in 1..<occupants.count {
                let leader = occupants[index - 1]
                let follower = occupants[index]
                let leaderPosition = leader.aiIndex.map { trains[$0].positionM } ?? leader.positionM
                let followerPosition = follower.aiIndex.map { trains[$0].positionM } ?? follower.positionM
                let requiredCenterSpacing = scenario.minimumTrainGapM + (leader.lengthM + follower.lengthM) * 0.5
                let permittedFollowerPosition = leaderPosition - track.direction.sign * requiredCenterSpacing
                let violation = track.direction == .increasing
                    ? followerPosition > permittedFollowerPosition
                    : followerPosition < permittedFollowerPosition
                guard violation, let followerAIIndex = follower.aiIndex else { continue }

                let boundedPosition = min(max(permittedFollowerPosition, 0), pathLength)
                trains[followerAIIndex].positionM = boundedPosition
                trains[followerAIIndex].speedMps = 0
                trains[followerAIIndex].isHeldForSeparation = true
            }
        }
    }

    private mutating func enforceRoadVehicleSeparation() {
        for road in scenario.roads {
            let pathLength = scenario.routePaths.first(where: { $0.id == road.routePathID })!.lengthM
            var indices = roadVehicles.indices.filter {
                roadVehicles[$0].plan.roadID == road.id && roadVehicles[$0].phase != .scheduled
            }
            indices.sort {
                let left = roadVehicles[$0]
                let right = roadVehicles[$1]
                if left.positionM == right.positionM { return left.plan.id < right.plan.id }
                return road.direction == .increasing ? left.positionM > right.positionM : left.positionM < right.positionM
            }
            guard indices.count > 1 else { continue }
            for offset in 1..<indices.count {
                let leaderIndex = indices[offset - 1]
                let followerIndex = indices[offset]
                let leader = roadVehicles[leaderIndex]
                let follower = roadVehicles[followerIndex]
                let requiredCenterSpacing = scenario.minimumRoadVehicleGapM + (leader.plan.lengthM + follower.plan.lengthM) * 0.5
                let permittedFollowerPosition = leader.positionM - road.direction.sign * requiredCenterSpacing
                let violation = road.direction == .increasing
                    ? follower.positionM > permittedFollowerPosition
                    : follower.positionM < permittedFollowerPosition
                guard violation else { continue }
                roadVehicles[followerIndex].positionM = min(max(permittedFollowerPosition, 0), pathLength)
                roadVehicles[followerIndex].speedMps = 0
                roadVehicles[followerIndex].isHeldForSeparation = true
            }
        }
    }

    private func makeSnapshot(playerTrain: SharedTrainState?) -> TrafficSnapshot {
        // Performance (2026-11-12, CI #412): this used to rescan
        // every train for every train (nearestTrainClearance and
        // isPassing were O(n) per train), making snapshot
        // construction O(n^2). With the diagram's 798 trains and a
        // snapshot built on every 120 Hz physics tick, the host's
        // main thread saturated and simulation time dilated to a
        // small fraction of real time on loaded CI runners: the
        // screenshot tour's READY/ACK handshake desynchronised and
        // the demo drive could not even depart. Clearances and
        // passing flags are now derived from position-sorted
        // occupant lists in O(n log n). Each outward scan stops
        // only once every train further away is provably unable to
        // beat the best value found (position gaps grow
        // monotonically while the length term is bounded by the
        // longest train in the group), so the values produced are
        // identical to the full scan.
        let tracksByID = Dictionary(scenario.tracks.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

        struct SnapshotOccupant {
            let positionM: Double
            let lengthM: Double
            let trainIndex: Int?
        }
        // Active (non-scheduled) occupants per track, sorted by
        // position, with the player inserted on its own track.
        var occupantsByTrack: [String: [SnapshotOccupant]] = [:]
        for (index, runtime) in trains.enumerated() where runtime.phase != .scheduled {
            occupantsByTrack[runtime.plan.trackID, default: []].append(
                SnapshotOccupant(positionM: runtime.positionM, lengthM: runtime.plan.lengthM, trainIndex: index)
            )
        }
        if let playerTrain {
            occupantsByTrack[playerTrain.trackID, default: []].append(
                SnapshotOccupant(positionM: playerTrain.positionM, lengthM: playerTrain.lengthM, trainIndex: nil)
            )
        }
        for trackID in Array(occupantsByTrack.keys) {
            occupantsByTrack[trackID]?.sort { $0.positionM < $1.positionM }
        }
        let maxOccupantLengthByTrack: [String: Double] = occupantsByTrack.mapValues { occupants in
            occupants.map(\.lengthM).max() ?? 0
        }

        func nearestClearance(trackID: String, positionM: Double, lengthM: Double, selfIndex: Int) -> Double? {
            guard let occupants = occupantsByTrack[trackID], !occupants.isEmpty else { return nil }
            let maxLength = maxOccupantLengthByTrack[trackID] ?? 0
            var lo = 0
            var hi = occupants.count
            while lo < hi {
                let mid = (lo + hi) / 2
                if occupants[mid].positionM < positionM { lo = mid + 1 } else { hi = mid }
            }
            var best: Double? = nil
            var j = lo - 1
            while j >= 0 {
                let other = occupants[j]
                let gap = positionM - other.positionM
                if let best, gap - (lengthM + maxLength) * 0.5 >= best { break }
                if other.trainIndex != selfIndex {
                    let clearance = gap - (lengthM + other.lengthM) * 0.5
                    if best == nil || clearance < best! { best = clearance }
                }
                j -= 1
            }
            var k = lo
            while k < occupants.count {
                let other = occupants[k]
                let gap = other.positionM - positionM
                if let best, gap - (lengthM + maxLength) * 0.5 >= best { break }
                if other.trainIndex != selfIndex {
                    let clearance = gap - (lengthM + other.lengthM) * 0.5
                    if best == nil || clearance < best! { best = clearance }
                }
                k += 1
            }
            return best
        }

        // Passing flags: group the tracks by parallel group and
        // route path; inside a group, a train is passing when an
        // active train on an opposite-direction track is within
        // the visualisation distance (plus half of each length).
        var passingByTrainIndex: [Int: Bool] = [:]
        var tracksByGroup: [String: [TrafficTrackDefinition]] = [:]
        for track in scenario.tracks {
            tracksByGroup["\(track.parallelGroupID)|\(track.routePathID)", default: []].append(track)
        }
        struct GroupOccupant {
            let positionM: Double
            let lengthM: Double
            let trainIndex: Int
            let direction: TrafficDirection
        }
        for groupTracks in tracksByGroup.values {
            var groupOccupants: [GroupOccupant] = []
            for track in groupTracks {
                for occupant in occupantsByTrack[track.id] ?? [] {
                    if let trainIndex = occupant.trainIndex {
                        groupOccupants.append(GroupOccupant(positionM: occupant.positionM, lengthM: occupant.lengthM, trainIndex: trainIndex, direction: track.direction))
                    }
                }
            }
            guard groupOccupants.count > 1 else { continue }
            groupOccupants.sort { $0.positionM < $1.positionM }
            let maxGroupLength = groupOccupants.map(\.lengthM).max() ?? 0
            for (i, entry) in groupOccupants.enumerated() {
                if passingByTrainIndex[entry.trainIndex] == true { continue }
                var found = false
                var j = i - 1
                while j >= 0, !found {
                    let other = groupOccupants[j]
                    let gap = entry.positionM - other.positionM
                    if gap - (entry.lengthM + maxGroupLength) * 0.5 > scenario.passingVisualizationDistanceM { break }
                    if other.direction != entry.direction,
                       gap - (entry.lengthM + other.lengthM) * 0.5 <= scenario.passingVisualizationDistanceM {
                        found = true
                    }
                    j -= 1
                }
                var k = i + 1
                while k < groupOccupants.count, !found {
                    let other = groupOccupants[k]
                    let gap = other.positionM - entry.positionM
                    if gap - (entry.lengthM + maxGroupLength) * 0.5 > scenario.passingVisualizationDistanceM { break }
                    if other.direction != entry.direction,
                       gap - (entry.lengthM + other.lengthM) * 0.5 <= scenario.passingVisualizationDistanceM {
                        found = true
                    }
                    k += 1
                }
                passingByTrainIndex[entry.trainIndex] = found
            }
        }

        let trainSnapshots = trains.enumerated().map { (index, runtime) -> AITrainSnapshot in
            let track = tracksByID[runtime.plan.trackID]!
            let clearance = nearestClearance(trackID: runtime.plan.trackID, positionM: runtime.positionM, lengthM: runtime.plan.lengthM, selfIndex: index)
            return AITrainSnapshot(
                id: runtime.plan.id,
                trackID: runtime.plan.trackID,
                routePathID: track.routePathID,
                serviceType: runtime.plan.serviceType,
                servicePeriod: runtime.plan.servicePeriod,
                serviceDirection: track.direction.serviceDirection,
                operationKind: runtime.plan.operationKind,
                scheduledArrivalTimeSeconds: runtime.plan.scheduledTripDurationSeconds.map { runtime.plan.departureTimeSeconds + $0 },
                positionM: runtime.positionM,
                speedMps: runtime.speedMps,
                signedSpeedMps: runtime.speedMps * track.direction.sign,
                headingRadians: track.direction == .increasing ? 0 : Double.pi,
                phase: runtime.phase,
                isHeldForSeparation: runtime.isHeldForSeparation,
                nearestTrainClearanceM: clearance,
                isPassing: passingByTrainIndex[index] ?? false
            )
        }
        let roadSnapshots = roadVehicles.map { runtime -> RoadVehicleSnapshot in
            let road = scenario.roads.first { $0.id == runtime.plan.roadID }!
            let nearest = nearestRoadVehicleClearance(for: runtime)
            return RoadVehicleSnapshot(
                id: runtime.plan.id,
                roadID: runtime.plan.roadID,
                routePathID: road.routePathID,
                positionM: runtime.positionM,
                speedMps: runtime.speedMps,
                headingRadians: road.direction == .increasing ? 0 : Double.pi,
                phase: runtime.phase,
                isHeldForSeparation: runtime.isHeldForSeparation,
                nearestVehicleClearanceM: nearest
            )
        }
        let passengerSnapshots = passengers.map { runtime -> PlatformPassengerSnapshot in
            let platform = scenario.platforms.first { $0.id == runtime.trip.platformID }!
            let delta = runtime.trip.destinationOffsetM - runtime.trip.startOffsetM
            return PlatformPassengerSnapshot(
                id: runtime.trip.id,
                platformID: runtime.trip.platformID,
                alongPlatformM: runtime.alongPlatformM,
                lateralOffsetM: platform.lateralOffsetM,
                headingRadians: delta < 0 ? Double.pi : 0,
                phase: runtime.phase
            )
        }
        return TrafficSnapshot(
            scenarioID: scenario.scenarioID,
            routeID: scenario.routeID,
            routeLengthM: scenario.routeLengthM,
            totalNetworkLengthM: scenario.totalNetworkLengthM,
            routePaths: scenario.routePaths,
            dataStatus: scenario.dataStatus,
            simulationTimeSeconds: simulationTimeSeconds,
            fixedTick: fixedTick,
            fixedTimeStepSeconds: scenario.fixedTimeStepSeconds,
            playerTrain: playerTrain,
            trains: trainSnapshots,
            roadVehicles: roadSnapshots,
            passengers: passengerSnapshots
        )
    }

    private func nearestRoadVehicleClearance(for runtime: RoadVehicleRuntime) -> Double? {
        roadVehicles.compactMap { other in
            guard other.plan.id != runtime.plan.id,
                  other.plan.roadID == runtime.plan.roadID,
                  other.phase != .scheduled else { return nil }
            return abs(other.positionM - runtime.positionM) - (other.plan.lengthM + runtime.plan.lengthM) * 0.5
        }.min()
    }
}
