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
    /// batch64: the frame's poses indexed by sourceID, built by
    /// the sampler alongside `poses` so renderers no longer pay
    /// a second dictionary pass over the frame on every update.
    /// Deliberately not part of the coded form: decoding a frame
    /// rebuilds the index from `poses`.
    public let posesBySourceID: [String: TrafficActorPose]

    public init(scenarioID: String, routeID: String, simulationTimeSeconds: Double, fixedTick: UInt64, poses: [TrafficActorPose]) {
        self.scenarioID = scenarioID
        self.routeID = routeID
        self.simulationTimeSeconds = simulationTimeSeconds
        self.fixedTick = fixedTick
        self.poses = poses
        self.posesBySourceID = Dictionary(poses.map { ($0.sourceID, $0) }, uniquingKeysWith: { first, _ in first })
    }

    init(scenarioID: String, routeID: String, simulationTimeSeconds: Double, fixedTick: UInt64, poses: [TrafficActorPose], posesBySourceID: [String: TrafficActorPose]) {
        self.scenarioID = scenarioID
        self.routeID = routeID
        self.simulationTimeSeconds = simulationTimeSeconds
        self.fixedTick = fixedTick
        self.poses = poses
        self.posesBySourceID = posesBySourceID
    }

    private enum CodingKeys: String, CodingKey {
        case scenarioID
        case routeID
        case simulationTimeSeconds
        case fixedTick
        case poses
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            scenarioID: try container.decode(String.self, forKey: .scenarioID),
            routeID: try container.decode(String.self, forKey: .routeID),
            simulationTimeSeconds: try container.decode(Double.self, forKey: .simulationTimeSeconds),
            fixedTick: try container.decode(UInt64.self, forKey: .fixedTick),
            poses: try container.decode([TrafficActorPose].self, forKey: .poses)
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(scenarioID, forKey: .scenarioID)
        try container.encode(routeID, forKey: .routeID)
        try container.encode(simulationTimeSeconds, forKey: .simulationTimeSeconds)
        try container.encode(fixedTick, forKey: .fixedTick)
        try container.encode(poses, forKey: .poses)
    }
}

public enum TrafficActorPoseSamplingError: Error, Equatable, Sendable {
    case invalidSnapshot
    case mismatchedSnapshots
    case invalidSampleTime
}

/// batch64: monotonic revision of the scenario installed in
/// the running process. The pose caches (TrafficPoseStaticDataCache
/// below, and the renderer's per-scenario lookup tables) used
/// to validate themselves with a full `Equatable` comparison
/// of the whole scenario — ~800 plans deep — on every frame.
/// They now key on the scenario's identity fields, its table
/// counts, and this generation. The generation advances
/// wherever a scenario is installed: `TrafficSimulationEngine`'s
/// initializer advances it (every scenario the host runs is
/// installed by building an engine from it), and the host's
/// own scenario assignment points advance it explicitly. A
/// rebuilt scenario can therefore never be served stale
/// tables, even one that reuses a scenarioID.
public enum TrafficScenarioGeneration {
    private static let lock = NSLock()
    private static var storage: UInt64 = 0

    public static var current: UInt64 {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    public static func advance() {
        lock.lock()
        storage &+= 1
        lock.unlock()
    }
}

/// batch64: a sampling focus for the renderer. A focused
/// sample poses only the actors that are active at the sample
/// instant (trains running or dwelling, road vehicles moving,
/// passengers walking or waiting) AND lie within `radiusM` of
/// the focus position. Distance is network distance along the
/// scenario's route paths, measured through junctions, so an
/// actor on a connecting branch or depot spur is judged by
/// its true distance from the focus rather than by raw path
/// coordinates. Actors outside the focus are not posed at
/// all: no pose construction, no state dictionaries and no
/// sorting are spent on them. Inclusion is a pure function of
/// the current snapshot, so an actor appears in the frame
/// exactly while it is active and in range and drops out the
/// moment either stops holding — nothing can linger.
public struct TrafficActorPoseFocus: Equatable, Sendable {
    public let routePathID: String
    public let positionM: Double
    public let radiusM: Double

    public init(routePathID: String, positionM: Double, radiusM: Double) {
        self.routePathID = routePathID
        self.positionM = positionM
        self.radiusM = radiusM
    }
}

/// Samples/interpolates actor poses without advancing simulation state. Use the same simulation clock
/// as `TrafficSimulationEngine`; interpolation only smooths between its deterministic 120 Hz ticks.
public enum TrafficActorPoseSampler {
    private static let twoPi = 2 * Double.pi

    public static func sample(
        scenario: TrafficScenario,
        snapshot: TrafficSnapshot
    ) throws -> TrafficActorPoseFrame {
        try sampleCore(scenario: scenario, previous: nil, current: snapshot,
                       simulationTimeSeconds: snapshot.simulationTimeSeconds, focus: nil)
    }

    /// Interpolates between two snapshots at a simulation-time instant. Times outside the interval
    /// clamp to the nearest snapshot (no extrapolation); `previous` may be nil for an initial frame.
    public static func sample(
        scenario: TrafficScenario,
        previous: TrafficSnapshot?,
        current: TrafficSnapshot,
        simulationTimeSeconds: Double
    ) throws -> TrafficActorPoseFrame {
        try sampleCore(scenario: scenario, previous: previous, current: current,
                       simulationTimeSeconds: simulationTimeSeconds, focus: nil)
    }

    /// Focused variant of `sample(scenario:snapshot:)`; see
    /// `TrafficActorPoseFocus`. Poses for the actors it does
    /// include are computed exactly as the unfocused sample
    /// computes them.
    public static func sample(
        scenario: TrafficScenario,
        snapshot: TrafficSnapshot,
        focus: TrafficActorPoseFocus
    ) throws -> TrafficActorPoseFrame {
        try sampleCore(scenario: scenario, previous: nil, current: snapshot,
                       simulationTimeSeconds: snapshot.simulationTimeSeconds, focus: focus)
    }

    /// Focused variant of the interpolating sample; see
    /// `TrafficActorPoseFocus`.
    public static func sample(
        scenario: TrafficScenario,
        previous: TrafficSnapshot?,
        current: TrafficSnapshot,
        simulationTimeSeconds: Double,
        focus: TrafficActorPoseFocus
    ) throws -> TrafficActorPoseFrame {
        try sampleCore(scenario: scenario, previous: previous, current: current,
                       simulationTimeSeconds: simulationTimeSeconds, focus: focus)
    }

    private static func sampleCore(
        scenario: TrafficScenario,
        previous: TrafficSnapshot?,
        current: TrafficSnapshot,
        simulationTimeSeconds: Double,
        focus: TrafficActorPoseFocus?
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
        // The scenario's static lookup tables come from a
        // per-scenario cache: rebuilding them on every sample
        // cost the renderer several dictionary constructions
        // (and ~800 string hashes each) per frame for data
        // that only changes when the scenario itself does.
        let staticData = TrafficPoseStaticDataCache.shared.data(for: scenario)
        if let focus {
            return sampleFocused(
                scenario: scenario, previous: previous, current: current,
                simulationTimeSeconds: simulationTimeSeconds, alpha: alpha,
                staticData: staticData, focus: focus
            )
        }
        return sampleAll(
            scenario: scenario, previous: previous, current: current,
            simulationTimeSeconds: simulationTimeSeconds, alpha: alpha,
            staticData: staticData
        )
    }

    /// The original full sample: every actor in the scenario
    /// is posed. Kept for callers that need the whole frame
    /// (and for the package's own tests); the renderer uses
    /// the focused path below.
    private static func sampleAll(
        scenario: TrafficScenario,
        previous: TrafficSnapshot?,
        current: TrafficSnapshot,
        simulationTimeSeconds: Double,
        alpha: Double,
        staticData: TrafficPoseStaticDataCache.StaticData
    ) -> TrafficActorPoseFrame {
        let previousTrains = Dictionary(previous?.trains.map { ($0.id, $0) } ?? [], uniquingKeysWith: { first, _ in first })
        let previousRoadVehicles = Dictionary(previous?.roadVehicles.map { ($0.id, $0) } ?? [], uniquingKeysWith: { first, _ in first })
        let previousPassengers = Dictionary(previous?.passengers.map { ($0.id, $0) } ?? [], uniquingKeysWith: { first, _ in first })
        let currentTrains = Dictionary(current.trains.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let currentRoadVehicles = Dictionary(current.roadVehicles.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let currentPassengers = Dictionary(current.passengers.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let tracks = staticData.tracks
        let roads = staticData.roads
        let platforms = staticData.platforms

        var poses: [TrafficActorPose] = []
        poses.reserveCapacity(scenario.trains.count + scenario.roadVehicles.count + scenario.passengerTrips.count)
        var posesBySourceID: [String: TrafficActorPose] = [:]
        posesBySourceID.reserveCapacity(poses.capacity)

        for plan in scenario.trains {
            guard let track = tracks[plan.trackID], let state = currentTrains[plan.id] else { continue }
            let old = previousTrains[plan.id]
            let position = interpolate(old?.positionM, state.positionM, alpha)
            let speed = interpolate(old?.speedMps, state.speedMps, alpha)
            let phase = sampledPhase(old.map { $0.phase.actorMotionPhase }, state.phase.actorMotionPhase, alpha)
            // batch64: actor IDs and stable phases are
            // precomputed in the static cache (identical
            // strings, identical FNV values) instead of being
            // re-interpolated and re-hashed on every frame.
            let actorID = staticData.trainActorIDs[plan.id] ?? "\(scenario.scenarioID)/train/\(plan.id)"
            let pose = TrafficActorPose(
                id: actorID, sourceID: plan.id, kind: .train, routePathID: track.routePathID,
                positionM: position, lateralOffsetM: track.lateralOffsetM,
                headingRadians: track.direction == .increasing ? 0 : Double.pi,
                speedMps: speed, lengthM: plan.lengthM, phase: phase,
                isVisible: phase != TrafficActorMotionPhase.scheduled,
                wheelRotationRadians: wrapped((position - plan.startPositionM) / 0.46),
                walkCycleRadians: staticData.trainStablePhases[plan.id] ?? stablePhase(for: actorID)
            )
            poses.append(pose)
            posesBySourceID[pose.sourceID] = pose
        }

        for plan in scenario.roadVehicles {
            guard let road = roads[plan.roadID], let state = currentRoadVehicles[plan.id] else { continue }
            let old = previousRoadVehicles[plan.id]
            let position = interpolate(old?.positionM, state.positionM, alpha)
            let speed = interpolate(old?.speedMps, state.speedMps, alpha)
            let phase = sampledPhase(old.map { $0.phase.actorMotionPhase }, state.phase.actorMotionPhase, alpha)
            let actorID = staticData.roadActorIDs[plan.id] ?? "\(scenario.scenarioID)/road/\(plan.id)"
            let pose = TrafficActorPose(
                id: actorID, sourceID: plan.id, kind: .roadVehicle, routePathID: road.routePathID,
                positionM: position, lateralOffsetM: road.lateralOffsetM,
                headingRadians: road.direction == .increasing ? 0 : Double.pi,
                speedMps: speed, lengthM: plan.lengthM, phase: phase,
                isVisible: phase != TrafficActorMotionPhase.scheduled,
                wheelRotationRadians: wrapped((position - plan.startPositionM) / 0.33),
                walkCycleRadians: staticData.roadStablePhases[plan.id] ?? stablePhase(for: actorID)
            )
            poses.append(pose)
            posesBySourceID[pose.sourceID] = pose
        }

        for trip in scenario.passengerTrips {
            guard let platform = platforms[trip.platformID],
                  let track = tracks[platform.trackID],
                  let state = currentPassengers[trip.id] else { continue }
            let old = previousPassengers[trip.id]
            let along = interpolate(old?.alongPlatformM, state.alongPlatformM, alpha)
            let phase = sampledPhase(old.map { $0.phase.actorMotionPhase }, state.phase.actorMotionPhase, alpha)
            let actorID = staticData.passengerActorIDs[trip.id] ?? "\(scenario.scenarioID)/platform/\(trip.id)"
            let walkedDistance = along - trip.startOffsetM
            let pose = TrafficActorPose(
                id: actorID, sourceID: trip.id, kind: .platformPassenger,
                routePathID: track.routePathID,
                // Platform chainage is its center; passenger offsets are measured from its near end.
                positionM: platform.chainageM - platform.lengthM * 0.5 + along,
                lateralOffsetM: platform.lateralOffsetM,
                headingRadians: trip.destinationOffsetM < trip.startOffsetM ? Double.pi : 0,
                speedMps: phase == TrafficActorMotionPhase.walking ? trip.walkingSpeedMps : 0,
                lengthM: 0.5, phase: phase, isVisible: phase != TrafficActorMotionPhase.scheduled,
                wheelRotationRadians: 0,
                walkCycleRadians: wrapped((staticData.passengerStablePhases[trip.id] ?? stablePhase(for: actorID)) + walkedDistance / 0.72 * twoPi)
            )
            poses.append(pose)
            posesBySourceID[pose.sourceID] = pose
        }

        return TrafficActorPoseFrame(
            scenarioID: scenario.scenarioID, routeID: scenario.routeID,
            simulationTimeSeconds: simulationTimeSeconds,
            fixedTick: current.fixedTick, poses: poses.sorted { $0.id < $1.id },
            posesBySourceID: posesBySourceID
        )
    }

    /// batch64: the renderer's focused sample. Only actors
    /// that are active in the CURRENT snapshot and within the
    /// focus radius are posed; everyone else costs one phase
    /// comparison against the snapshot arrays and nothing
    /// more. Inclusion is decided from the current snapshot
    /// alone (the same phases the renderer itself filters
    /// on), and previous-snapshot states for interpolation
    /// are resolved only for the included actors.
    private static func sampleFocused(
        scenario: TrafficScenario,
        previous: TrafficSnapshot?,
        current: TrafficSnapshot,
        simulationTimeSeconds: Double,
        alpha: Double,
        staticData: TrafficPoseStaticDataCache.StaticData,
        focus: TrafficActorPoseFocus
    ) -> TrafficActorPoseFrame {
        var poses: [TrafficActorPose] = []
        var posesBySourceID: [String: TrafficActorPose] = [:]
        let previousTrains = PreviousStateResolver(states: previous?.trains) { $0.id }
        let previousRoadVehicles = PreviousStateResolver(states: previous?.roadVehicles) { $0.id }
        let previousPassengers = PreviousStateResolver(states: previous?.passengers) { $0.id }

        for (index, state) in current.trains.enumerated() where state.phase == .running || state.phase == .dwelling {
            guard let plan = staticData.trainPlansByID[state.id],
                  let track = staticData.tracks[plan.trackID] else { continue }
            // The consist extends up to its full length behind
            // the sampled position, so the radius grows by the
            // length: an actor whose body overlaps the focus
            // window is always included.
            guard networkDistanceM(staticData: staticData, actorPathID: track.routePathID, actorPositionM: state.positionM, focus: focus) <= focus.radiusM + plan.lengthM else { continue }
            let old = previousTrains.state(atIndex: index, matching: state.id)
            let position = interpolate(old?.positionM, state.positionM, alpha)
            let speed = interpolate(old?.speedMps, state.speedMps, alpha)
            let phase = sampledPhase(old.map { $0.phase.actorMotionPhase }, state.phase.actorMotionPhase, alpha)
            let actorID = staticData.trainActorIDs[plan.id] ?? "\(scenario.scenarioID)/train/\(plan.id)"
            let pose = TrafficActorPose(
                id: actorID, sourceID: plan.id, kind: .train, routePathID: track.routePathID,
                positionM: position, lateralOffsetM: track.lateralOffsetM,
                headingRadians: track.direction == .increasing ? 0 : Double.pi,
                speedMps: speed, lengthM: plan.lengthM, phase: phase,
                isVisible: phase != TrafficActorMotionPhase.scheduled,
                wheelRotationRadians: wrapped((position - plan.startPositionM) / 0.46),
                walkCycleRadians: staticData.trainStablePhases[plan.id] ?? stablePhase(for: actorID)
            )
            poses.append(pose)
            posesBySourceID[pose.sourceID] = pose
        }

        for (index, state) in current.roadVehicles.enumerated() where state.phase == .moving {
            guard let plan = staticData.roadPlansByID[state.id],
                  let road = staticData.roads[plan.roadID] else { continue }
            guard networkDistanceM(staticData: staticData, actorPathID: road.routePathID, actorPositionM: state.positionM, focus: focus) <= focus.radiusM + plan.lengthM else { continue }
            let old = previousRoadVehicles.state(atIndex: index, matching: state.id)
            let position = interpolate(old?.positionM, state.positionM, alpha)
            let speed = interpolate(old?.speedMps, state.speedMps, alpha)
            let phase = sampledPhase(old.map { $0.phase.actorMotionPhase }, state.phase.actorMotionPhase, alpha)
            let actorID = staticData.roadActorIDs[plan.id] ?? "\(scenario.scenarioID)/road/\(plan.id)"
            let pose = TrafficActorPose(
                id: actorID, sourceID: plan.id, kind: .roadVehicle, routePathID: road.routePathID,
                positionM: position, lateralOffsetM: road.lateralOffsetM,
                headingRadians: road.direction == .increasing ? 0 : Double.pi,
                speedMps: speed, lengthM: plan.lengthM, phase: phase,
                isVisible: phase != TrafficActorMotionPhase.scheduled,
                wheelRotationRadians: wrapped((position - plan.startPositionM) / 0.33),
                walkCycleRadians: staticData.roadStablePhases[plan.id] ?? stablePhase(for: actorID)
            )
            poses.append(pose)
            posesBySourceID[pose.sourceID] = pose
        }

        for (index, state) in current.passengers.enumerated() where state.phase == .walking || state.phase == .waiting {
            guard let trip = staticData.passengerTripsByID[state.id],
                  let platform = staticData.platforms[trip.platformID],
                  let track = staticData.tracks[platform.trackID] else { continue }
            let currentPositionM = platform.chainageM - platform.lengthM * 0.5 + state.alongPlatformM
            guard networkDistanceM(staticData: staticData, actorPathID: track.routePathID, actorPositionM: currentPositionM, focus: focus) <= focus.radiusM else { continue }
            let old = previousPassengers.state(atIndex: index, matching: state.id)
            let along = interpolate(old?.alongPlatformM, state.alongPlatformM, alpha)
            let phase = sampledPhase(old.map { $0.phase.actorMotionPhase }, state.phase.actorMotionPhase, alpha)
            let actorID = staticData.passengerActorIDs[trip.id] ?? "\(scenario.scenarioID)/platform/\(trip.id)"
            let walkedDistance = along - trip.startOffsetM
            let pose = TrafficActorPose(
                id: actorID, sourceID: trip.id, kind: .platformPassenger,
                routePathID: track.routePathID,
                // Platform chainage is its center; passenger offsets are measured from its near end.
                positionM: platform.chainageM - platform.lengthM * 0.5 + along,
                lateralOffsetM: platform.lateralOffsetM,
                headingRadians: trip.destinationOffsetM < trip.startOffsetM ? Double.pi : 0,
                speedMps: phase == TrafficActorMotionPhase.walking ? trip.walkingSpeedMps : 0,
                lengthM: 0.5, phase: phase, isVisible: phase != TrafficActorMotionPhase.scheduled,
                wheelRotationRadians: 0,
                walkCycleRadians: wrapped((staticData.passengerStablePhases[trip.id] ?? stablePhase(for: actorID)) + walkedDistance / 0.72 * twoPi)
            )
            poses.append(pose)
            posesBySourceID[pose.sourceID] = pose
        }

        return TrafficActorPoseFrame(
            scenarioID: scenario.scenarioID, routeID: scenario.routeID,
            simulationTimeSeconds: simulationTimeSeconds,
            fixedTick: current.fixedTick, poses: poses.sorted { $0.id < $1.id },
            posesBySourceID: posesBySourceID
        )
    }

    /// Network distance between an actor position and the
    /// focus, through route-path junctions (see
    /// `TrafficActorPoseFocus`). Positions on the same path
    /// compare directly; positions on different paths are
    /// routed through the hub path both paths connect to
    /// (a child path's position is measured from its junction,
    /// so the leg along the child is the position itself).
    /// Paths that share no hub are infinitely far apart.
    private static func networkDistanceM(
        staticData: TrafficPoseStaticDataCache.StaticData,
        actorPathID: String,
        actorPositionM: Double,
        focus: TrafficActorPoseFocus
    ) -> Double {
        if actorPathID == focus.routePathID {
            return abs(actorPositionM - focus.positionM)
        }
        guard let actorHub = staticData.pathHubs[actorPathID],
              let focusHub = staticData.pathHubs[focus.routePathID],
              actorHub.hubPathID == focusHub.hubPathID else { return .infinity }
        let actorLeg = actorHub.junctionPositionM == nil ? 0 : actorPositionM
        let actorHubPosition = actorHub.junctionPositionM ?? actorPositionM
        let focusLeg = focusHub.junctionPositionM == nil ? 0 : focus.positionM
        let focusHubPosition = focusHub.junctionPositionM ?? focus.positionM
        return actorLeg + abs(actorHubPosition - focusHubPosition) + focusLeg
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
        trafficStablePhase(for: id)
    }
}

/// FNV-1a stable phase for an actor ID, shared by the sampler
/// and the static-data cache (which precomputes it per actor).
private func trafficStablePhase(for id: String) -> Double {
    var hash: UInt64 = 14_695_981_039_346_656_037
    for byte in id.utf8 {
        hash = (hash ^ UInt64(byte)) &* 1_099_511_628_211
    }
    let unit = Double(hash % 1_000_003) / 1_000_003
    return unit * 2 * Double.pi
}

/// batch64: resolves a previous-snapshot state for one
/// focused actor without building a dictionary over the
/// whole snapshot. Snapshots produced by one engine list
/// their actors in scenario order, so the previous state of
/// the actor at a given current index normally sits at the
/// same index; the ID is verified before the entry is used.
/// If verification ever fails (the arrays are not aligned),
/// a per-kind dictionary is built once, lazily, and used
/// from then on — the result is identical either way, the
/// aligned path is simply the fast one.
private final class PreviousStateResolver<State> {
    private let states: [State]
    private let idOf: (State) -> String
    private var fallback: [String: State]?

    init(states: [State]?, idOf: @escaping (State) -> String) {
        self.states = states ?? []
        self.idOf = idOf
    }

    func state(atIndex index: Int, matching targetID: String) -> State? {
        if states.indices.contains(index), idOf(states[index]) == targetID {
            return states[index]
        }
        if fallback == nil {
            fallback = Dictionary(states.map { (idOf($0), $0) }, uniquingKeysWith: { first, _ in first })
        }
        return fallback?[targetID]
    }
}

/// Per-scenario cache of the sampler's static lookup tables
/// (tracks / roads / platforms by id, plans by id, precomputed
/// actor IDs and stable phases, route-path junction data).
/// The cache holds exactly one scenario — the one most
/// recently sampled. batch64: it validates the cached tables
/// against a lightweight key (scenario identity fields, table
/// counts, and `TrafficScenarioGeneration.current`) instead
/// of a full `Equatable` comparison of the whole scenario,
/// which cost a deep ~800-plan comparison on every frame.
/// The generation advances wherever a scenario is installed
/// (see `TrafficScenarioGeneration`), so a different scenario
/// that happens to reuse a scenarioID can never be served
/// stale tables. The lock keeps the cache safe for callers
/// on any thread; the key check and the (rare) rebuild both
/// run under it.
private final class TrafficPoseStaticDataCache: @unchecked Sendable {
    static let shared = TrafficPoseStaticDataCache()

    /// How a route path reaches the network's hub path: the
    /// hub's id, and the position on the hub where this path
    /// joins it (nil when this path IS a hub — a path with no
    /// connection of its own).
    struct PathHub {
        let hubPathID: String
        let junctionPositionM: Double?
    }

    struct StaticData {
        let tracks: [String: TrafficTrackDefinition]
        let roads: [String: ParallelRoadDefinition]
        let platforms: [String: TrafficPlatformDefinition]
        let trainPlansByID: [String: AITrainPlan]
        let roadPlansByID: [String: RoadVehiclePlan]
        let passengerTripsByID: [String: PlatformPassengerTrip]
        let trainActorIDs: [String: String]
        let roadActorIDs: [String: String]
        let passengerActorIDs: [String: String]
        let trainStablePhases: [String: Double]
        let roadStablePhases: [String: Double]
        let passengerStablePhases: [String: Double]
        let pathHubs: [String: PathHub]
    }

    private struct CacheKey: Equatable {
        let scenarioID: String
        let routeID: String
        let routeLengthM: Double
        let fixedTimeStepSeconds: Double
        let generation: UInt64
        let trackCount: Int
        let roadCount: Int
        let platformCount: Int
        let trainCount: Int
        let roadVehicleCount: Int
        let passengerTripCount: Int
        let routePathCount: Int

        init(scenario: TrafficScenario) {
            scenarioID = scenario.scenarioID
            routeID = scenario.routeID
            routeLengthM = scenario.routeLengthM
            fixedTimeStepSeconds = scenario.fixedTimeStepSeconds
            generation = TrafficScenarioGeneration.current
            trackCount = scenario.tracks.count
            roadCount = scenario.roads.count
            platformCount = scenario.platforms.count
            trainCount = scenario.trains.count
            roadVehicleCount = scenario.roadVehicles.count
            passengerTripCount = scenario.passengerTrips.count
            routePathCount = scenario.routePaths.count
        }
    }

    private let lock = NSLock()
    private var cachedKey: CacheKey?
    private var cachedData: StaticData?

    func data(for scenario: TrafficScenario) -> StaticData {
        lock.lock()
        defer { lock.unlock() }
        let key = CacheKey(scenario: scenario)
        if let cachedKey, let cachedData, cachedKey == key {
            return cachedData
        }
        var trainActorIDs: [String: String] = [:]
        var trainStablePhases: [String: Double] = [:]
        for plan in scenario.trains {
            let actorID = "\(scenario.scenarioID)/train/\(plan.id)"
            trainActorIDs[plan.id] = actorID
            trainStablePhases[plan.id] = trafficStablePhase(for: actorID)
        }
        var roadActorIDs: [String: String] = [:]
        var roadStablePhases: [String: Double] = [:]
        for plan in scenario.roadVehicles {
            let actorID = "\(scenario.scenarioID)/road/\(plan.id)"
            roadActorIDs[plan.id] = actorID
            roadStablePhases[plan.id] = trafficStablePhase(for: actorID)
        }
        var passengerActorIDs: [String: String] = [:]
        var passengerStablePhases: [String: Double] = [:]
        for trip in scenario.passengerTrips {
            let actorID = "\(scenario.scenarioID)/platform/\(trip.id)"
            passengerActorIDs[trip.id] = actorID
            passengerStablePhases[trip.id] = trafficStablePhase(for: actorID)
        }
        var pathHubs: [String: PathHub] = [:]
        for path in scenario.routePaths {
            if let connected = path.connectsToPathID, let junction = path.junctionPositionM {
                pathHubs[path.id] = PathHub(hubPathID: connected, junctionPositionM: junction)
            } else {
                pathHubs[path.id] = PathHub(hubPathID: path.id, junctionPositionM: nil)
            }
        }
        let data = StaticData(
            tracks: Dictionary(scenario.tracks.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first }),
            roads: Dictionary(scenario.roads.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first }),
            platforms: Dictionary(scenario.platforms.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first }),
            trainPlansByID: Dictionary(scenario.trains.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first }),
            roadPlansByID: Dictionary(scenario.roadVehicles.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first }),
            passengerTripsByID: Dictionary(scenario.passengerTrips.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first }),
            trainActorIDs: trainActorIDs,
            roadActorIDs: roadActorIDs,
            passengerActorIDs: passengerActorIDs,
            trainStablePhases: trainStablePhases,
            roadStablePhases: roadStablePhases,
            passengerStablePhases: passengerStablePhases,
            pathHubs: pathHubs
        )
        cachedKey = key
        cachedData = data
        return data
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
