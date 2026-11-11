import Foundation

/// Renderer-facing categories. The simulation package can be bridged into these values without a package cycle.
public enum SceneTrafficActorKind: String, Codable, CaseIterable, Hashable, Sendable {
    case train
    case roadVehicle
    case platformPassenger
}

/// Minimal route-relative input copied from the platform-neutral traffic pose core.
public struct SceneTrafficActorInput: Codable, Hashable, Sendable, Identifiable {
    public let id: String
    public let kind: SceneTrafficActorKind
    public let routePathID: String
    public let chainageM: Double
    public let lateralOffsetM: Double
    /// Relative to increasing route chainage: 0 faces forward; π faces backward.
    public let headingRadians: Double
    public let speedMps: Double
    public let lengthM: Double
    public let isVisible: Bool
    public let isWalking: Bool
    public let wheelRotationRadians: Double
    public let walkCycleRadians: Double
    public let verticalOffsetM: Double
    /// Raw service-type value for train actors (e.g. "limitedExpress"),
    /// bridged as a plain string so this package stays decoupled from
    /// the traffic simulation package. Renderers use it to pick a
    /// vehicle model; nil for non-train actors.
    public let trainServiceRawValue: String?

    public init(
        id: String,
        kind: SceneTrafficActorKind,
        routePathID: String,
        chainageM: Double,
        lateralOffsetM: Double,
        headingRadians: Double,
        speedMps: Double,
        lengthM: Double,
        isVisible: Bool,
        isWalking: Bool = false,
        wheelRotationRadians: Double = 0,
        walkCycleRadians: Double = 0,
        verticalOffsetM: Double = 0,
        trainServiceRawValue: String? = nil
    ) {
        self.id = id
        self.kind = kind
        self.routePathID = routePathID
        self.chainageM = chainageM
        self.lateralOffsetM = lateralOffsetM
        self.headingRadians = headingRadians
        self.speedMps = speedMps
        self.lengthM = lengthM
        self.isVisible = isVisible
        self.isWalking = isWalking
        self.wheelRotationRadians = wheelRotationRadians
        self.walkCycleRadians = walkCycleRadians
        self.verticalOffsetM = verticalOffsetM
        self.trainServiceRawValue = trainServiceRawValue
    }
}

/// World-space actor pose projected onto the same curved/banked chainage route as the scene.
public struct SceneTrafficActorPose: Codable, Hashable, Sendable, Identifiable {
    public let id: String
    public let kind: SceneTrafficActorKind
    public let routePathID: String
    public let position: SceneVector3
    public let forward: SceneVector3
    public let right: SceneVector3
    public let up: SceneVector3
    public let speedMps: Double
    public let lengthM: Double
    public let isVisible: Bool
    public let isWalking: Bool
    public let wheelRotationRadians: Double
    public let walkCycleRadians: Double
    /// Raw service-type value for train actors; see SceneTrafficActorInput.
    public let trainServiceRawValue: String?
}

/// Projects route-relative actor poses using the exact frame used by the track and platform meshes.
public enum SceneTrafficActorProjector {
    public static func project(
        _ actors: [SceneTrafficActorInput],
        on route: SceneChainageRoute,
        supportedRoutePathIDs: Set<String>? = nil
    ) -> [SceneTrafficActorPose] {
        actors.sorted { $0.id < $1.id }.compactMap { actor in
            guard !actor.id.isEmpty,
                  actor.chainageM.isFinite, actor.lateralOffsetM.isFinite,
                  actor.headingRadians.isFinite, actor.speedMps.isFinite,
                  actor.lengthM.isFinite, actor.lengthM >= 0,
                  actor.verticalOffsetM.isFinite,
                  actor.wheelRotationRadians.isFinite, actor.walkCycleRadians.isFinite,
                  supportedRoutePathIDs?.contains(actor.routePathID) ?? true,
                  let frame = route.frame(at: actor.chainageM) else { return nil }

            let cosine = cos(actor.headingRadians)
            let sine = sin(actor.headingRadians)
            let forward = (frame.forward * cosine + frame.right * sine).normalized(or: frame.forward)
            let right = (frame.right * cosine - frame.forward * sine).normalized(or: frame.right)
            let position = frame.position + frame.right * actor.lateralOffsetM
                + frame.up * actor.verticalOffsetM
            return SceneTrafficActorPose(
                id: actor.id, kind: actor.kind, routePathID: actor.routePathID,
                position: position, forward: forward, right: right, up: frame.up,
                speedMps: actor.speedMps, lengthM: actor.lengthM,
                isVisible: actor.isVisible, isWalking: actor.isWalking,
                wheelRotationRadians: actor.wheelRotationRadians,
                walkCycleRadians: actor.walkCycleRadians,
                trainServiceRawValue: actor.trainServiceRawValue
            )
        }
    }
}
