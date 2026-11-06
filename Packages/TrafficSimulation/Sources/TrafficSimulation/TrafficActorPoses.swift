import Foundation

/// Portable actor categories for a renderer. IDs are namespaced by scenario and remain stable across restore/replay.
public enum TrafficActorKind: String, Codable, CaseIterable, Equatable, Sendable {
    case train
    case roadVehicle
    case platformPassenger
}

/// Discrete simulation state at the sampled instant; renderers should not advance this state themselves.
public enum TrafficActorMotionPhase: String, Codable, CaseIterable, Equatable, Sendable {
    case scheduled
    case running
    case dwelling
    case moving
    case walking
    case waiting
    case completed
}

/// Route-relative pose and deterministic cosmetic animation channels for one simulated actor.
/// Position is chainage along the route path; no SceneKit, RealityKit, or UIKit types leak into this core.
public struct TrafficActorPose: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let sourceID: String
    public let kind: TrafficActorKind
    public let routePathID: String
    public let positionM: Double
    public let lateralOffsetM: Double
    public let headingRadians: Double
    public let speedMps: Double
    public let lengthM: Double
    public let phase: TrafficActorMotionPhase
    public let isVisible: Bool
    /// Absolute-distance-derived wheel rotation. It is reproducible after pause, restore, and replay.
    public let wheelRotationRadians: Double
    /// Stable per-person offset plus walked distance; only animate limbs while `phase == .walking`.
    public let walkCycleRadians: Double
}

/// A render-time view of all scenario actors, derived exclusively from simulation snapshots.
public struct TrafficActorPoseFrame: Codable, Equatable, Sendable {
    public let scenarioID: String
    public let routeID: String
    public let simulationTimeSeconds: Double
    public let fixedTick: UInt64
    public let poses: [TrafficActorPose]
}

public enum TrafficActorPoseSamplingError: Error, Equatable, Sendable {
    case invalidSnapshot
    case mismatchedSnapshots
    case invalidSampleTime
}

/// Samples/interpolates actor poses without advancing simulation state. Use the same simulation clock
/// as `TrafficSimulationEngine`; interpolation only smooths between its deterministic 120 Hz ticks.
public enum TrafficActorPoseSampler {
    private static let twoPi = 2 * Double.pi

    public static func sample(
        scenario: TrafficScenario,
        snapshot: TrafficSnapshot
    ) throws -> TrafficActorPoseFrame {
        try sample(scenario: scenario, previous: nil, current: snapshot,
                   simulationTimeSeconds: snapshot.simulationTimeSeconds)
    }

    /// Interpolates between two snapshots at a simulation-time instant. Times outside the interval
    /// clamp to the nearest snapshot (no extrapolation); `previous` may be nil for an initial frame.
    public static func sample(
        scenario: TrafficScenario,
        previous: TrafficSnapshot?,
        current: TrafficSnapshot,
        simulationTimeSeconds: Double
    ) throws -> TrafficActorPoseFrame {
        guard simulationTimeSeconds.isFinite, simulationTimeSeconds >= 0 else {
            throw TrafficActorPoseSamplingError.invalidSampleTime
        }
        try validate(scenario: scenario, snapshot: current)
        if let previous {
            try validate(scenario: scenario, snapshot: previous)
            guard previous.fixedTick <= current.fixedTick,
                  previous.simulationTimeSeconds <= current.simulationTimeSeconds + 1e-9,
                  previous.fixedTimeStepSeconds == current.fixedTimeStepSeconds else {
                throw TrafficActorPoseSamplingError.mismatchedSnapshots
            }
        }

        let alpha: Double
        if let previous, current.simulationTimeSeconds > previous.simulationTimeSeconds + 1e-12 {
            alpha = min(1, max(0, (simulationTimeSeconds - previous.simulationTimeSeconds)
                / (current.simulationTimeSeconds - previous.simulationTimeSeconds)))
        } else {
            alpha = 1
        }
        let previousTrains = Dictionary(previous?.trains.map { ($0.id, $0) } ?? [], uniquingKeysWith: { first, _ in first })
        let previousRoadVehicles = Dictionary(previous?.roadVehicles.map { ($0.id, $0) } ?? [], uniquingKeysWith: { first, _ in first })
        let previousPassengers = Dictionary(previous?.passengers.map { ($0.id, $0) } ?? [], uniquingKeysWith: { first, _ in first })
        let currentTrains = Dictionary(current.trains.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let currentRoadVehicles = Dictionary(current.roadVehicles.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let currentPassengers = Dictionary(current.passengers.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let tracks = Dictionary(scenario.tracks.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let roads = Dictionary(scenario.roads.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let platforms = Dictionary(scenario.platforms.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

        var poses: [TrafficActorPose] = []
        poses.reserveCapacity(scenario.trains.count + scenario.roadVehicles.count + scenario.passengerTrips.count)

        for plan in scenario.trains {
            guard let track = tracks[plan.trackID], let state = currentTrains[plan.id] else { continue }
            let old = previousTrains[plan.id]
            let position = interpolate(old?.positionM, state.positionM, alpha)
            let speed = interpolate(old?.speedMps, state.speedMps, alpha)
            let phase = sampledPhase(old.map { $0.phase.actorMotionPhase }, state.phase.actorMotionPhase, alpha)
            let actorID = "\(scenario.scenarioID)/train/\(plan.id)"
            poses.append(TrafficActorPose(
                id: actorID, sourceID: plan.id, kind: .train, routePathID: track.routePathID,
                positionM: position, lateralOffsetM: track.lateralOffsetM,
                headingRadians: track.direction == .increasing ? 0 : Double.pi,
                speedMps: speed, lengthM: plan.lengthM, phase: phase,
                isVisible: phase != .scheduled,
                wheelRotationRadians: wrapped((position - plan.startPositionM) / 0.46),
                walkCycleRadians: stablePhase(for: actorID)
            ))
        }

        for plan in scenario.roadVehicles {
            guard let road = roads[plan.roadID], let state = currentRoadVehicles[plan.id] else { continue }
            let old = previousRoadVehicles[plan.id]
            let position = interpolate(old?.positionM, state.positionM, alpha)
            let speed = interpolate(old?.speedMps, state.speedMps, alpha)
            let phase = sampledPhase(old.map { $0.phase.actorMotionPhase }, state.phase.actorMotionPhase, alpha)
            let actorID = "\(scenario.scenarioID)/road/\(plan.id)"
            poses.append(TrafficActorPose(
                id: actorID, sourceID: plan.id, kind: .roadVehicle, routePathID: road.routePathID,
                positionM: position, lateralOffsetM: road.lateralOffsetM,
                headingRadians: road.direction == .increasing ? 0 : Double.pi,
                speedMps: speed, lengthM: plan.lengthM, phase: phase,
                isVisible: phase != .scheduled,
                wheelRotationRadians: wrapped((position - plan.startPositionM) / 0.33),
                walkCycleRadians: stablePhase(for: actorID)
            ))
        }

        for trip in scenario.passengerTrips {
            guard let platform = platforms[trip.platformID],
                  let track = tracks[platform.trackID],
                  let state = currentPassengers[trip.id] else { continue }
            let old = previousPassengers[trip.id]
            let along = interpolate(old?.alongPlatformM, state.alongPlatformM, alpha)
            let phase = sampledPhase(old.map { $0.phase.actorMotionPhase }, state.phase.actorMotionPhase, alpha)
            let actorID = "\(scenario.scenarioID)/platform/\(trip.id)"
            let walkedDistance = along - trip.startOffsetM
            poses.append(TrafficActorPose(
                id: actorID, sourceID: trip.id, kind: .platformPassenger,
                routePathID: track.routePathID,
                // Platform chainage is its center; passenger offsets are measured from its near end.
                positionM: platform.chainageM - platform.lengthM * 0.5 + along,
                lateralOffsetM: platform.lateralOffsetM,
                headingRadians: trip.destinationOffsetM < trip.startOffsetM ? Double.pi : 0,
                speedMps: phase == .walking ? trip.walkingSpeedMps : 0,
                lengthM: 0.5, phase: phase, isVisible: phase != .scheduled,
                wheelRotationRadians: 0,
                walkCycleRadians: wrapped(stablePhase(for: actorID) + walkedDistance / 0.72 * twoPi)
            ))
        }

        return TrafficActorPoseFrame(
            scenarioID: scenario.scenarioID, routeID: scenario.routeID,
            simulationTimeSeconds: simulationTimeSeconds,
            fixedTick: current.fixedTick, poses: poses.sorted { $0.id < $1.id }
        )
    }

    private static func validate(scenario: TrafficScenario, snapshot: TrafficSnapshot) throws {
        guard snapshot.scenarioID == scenario.scenarioID,
              snapshot.routeID == scenario.routeID,
              abs(snapshot.routeLengthM - scenario.routeLengthM) <= 0.001,
              abs(snapshot.fixedTimeStepSeconds - scenario.fixedTimeStepSeconds) <= scenario.fixedTimeStepSeconds.ulp * 4,
              snapshot.simulationTimeSeconds.isFinite, snapshot.simulationTimeSeconds >= 0 else {
            throw TrafficActorPoseSamplingError.invalidSnapshot
        }
    }

    private static func interpolate(_ old: Double?, _ current: Double, _ alpha: Double) -> Double {
        guard let old else { return current }
        return old + (current - old) * alpha
    }

    private static func sampledPhase(
        _ old: TrafficActorMotionPhase?,
        _ current: TrafficActorMotionPhase,
        _ alpha: Double
    ) -> TrafficActorMotionPhase {
        guard let old else { return current }
        return alpha >= 1 ? current : old
    }

    private static func wrapped(_ radians: Double) -> Double {
        let value = radians.truncatingRemainder(dividingBy: twoPi)
        return value < 0 ? value + twoPi : value
    }

    /// FNV-1a keeps small per-actor animation offsets identical across processes and replay sessions.
    private static func stablePhase(for id: String) -> Double {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in id.utf8 {
            hash = (hash ^ UInt64(byte)) &* 1_099_511_628_211
        }
        let unit = Double(hash % 1_000_003) / 1_000_003
        return unit * twoPi
    }
}

private extension AITrainPhase {
    var actorMotionPhase: TrafficActorMotionPhase {
        switch self {
        case .scheduled: .scheduled
        case .running: .running
        case .dwelling: .dwelling
        case .completed: .completed
        }
    }
}

private extension RoadVehiclePhase {
    var actorMotionPhase: TrafficActorMotionPhase {
        switch self {
        case .scheduled: .scheduled
        case .moving: .moving
        case .completed: .completed
        }
    }
}

private extension PlatformPassengerPhase {
    var actorMotionPhase: TrafficActorMotionPhase {
        switch self {
        case .scheduled: .scheduled
        case .walking: .walking
        case .waiting: .waiting
        }
    }
}
