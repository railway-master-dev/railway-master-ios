import Foundation

private let syntheticAssetLabel = "SYNTHETIC PLACEHOLDER — NOT MEASURED OR PHOTOGRAMMETRIC"

private struct AssemblyAccumulator {
    let id: String
    let role: SceneAssemblyRole
    let chainageM: Double
    let origin: SceneVector3
    let forward: SceneVector3
    let right: SceneVector3
    let up: SceneVector3
    let radius: Double
    let label: String?
    var pieces: [ScenePiece] = []

    init(id: String, role: SceneAssemblyRole, chainageM: Double, origin: SceneVector3,
         forward: SceneVector3, right: SceneVector3, up: SceneVector3,
         radius: Double, label: String? = nil) {
        self.id = id
        self.role = role
        self.chainageM = chainageM
        self.origin = origin
        self.forward = forward
        self.right = right
        self.up = up
        self.radius = radius
        self.label = label
    }

    mutating func addLocal(
        _ name: String,
        shape: ScenePieceShape = .box,
        position: SceneVector3,
        size: SceneVector3,
        rotation: SceneVector3 = .zero,
        material: SceneMaterialStyle,
        minimumLOD: SceneLODLevel = .far
    ) {
        guard size.x > 0, size.y > 0, size.z > 0,
              [position.x, position.y, position.z, size.x, size.y, size.z,
               rotation.x, rotation.y, rotation.z].allSatisfy(\.isFinite) else { return }
        pieces.append(ScenePiece(name: name, shape: shape, localPosition: position,
                                 dimensions: size, localRotationRadians: rotation,
                                 material: material, minimumLOD: minimumLOD))
    }

    mutating func addAt(
        _ name: String,
        routeFrame: SceneRouteFrame,
        lateralM: Double = 0,
        verticalM: Double = 0,
        size: SceneVector3,
        rotation: SceneVector3 = .zero,
        material: SceneMaterialStyle,
        minimumLOD: SceneLODLevel = .far
    ) {
        let worldPosition = routeFrame.position + routeFrame.right * lateralM + routeFrame.up * verticalM
        let delta = worldPosition - origin
        let localPosition = SceneVector3(delta.dot(right), delta.dot(up), delta.dot(forward))
        let localForwardX = routeFrame.forward.dot(right)
        let localForwardY = routeFrame.forward.dot(up)
        let localForwardZ = routeFrame.forward.dot(forward)
        let yaw = atan2(localForwardX, localForwardZ)
        let pitch = -atan2(localForwardY, max(1e-9, hypot(localForwardX, localForwardZ)))
        addLocal(name, position: localPosition, size: size,
                 rotation: SceneVector3(pitch + rotation.x, yaw + rotation.y, rotation.z),
                 material: material, minimumLOD: minimumLOD)
    }

    func finish() -> SceneAssembly {
        SceneAssembly(id: id, role: role, chainageM: chainageM, position: origin,
                      forward: forward, right: right, up: up, boundingRadiusM: radius,
                      pieces: pieces, syntheticPlaceholderLabel: label)
    }
}

private struct ScenePlanComposer {
    let route: SceneChainageRoute
    let corridor: SceneCorridorSpecification
    let camera: SceneCameraState
    let density: SceneDensityControls
    let buildStartM: Double
    let buildEndM: Double
    let landmarks: [SceneCorridorLandmark]
    var assemblies: [SceneAssembly] = []
    var warnings: [String] = []
    var sceneryCount = 0
    var generatedKeys = Set<String>()

    mutating func reserveScenery() -> Bool {
        guard sceneryCount < density.maxSceneryAssemblies else { return false }
        sceneryCount += 1
        return true
    }

    func localAccumulator(
        id: String,
        role: SceneAssemblyRole,
        chainage: Double,
        lateral: Double = 0,
        vertical: Double = 0,
        radius: Double,
        label: String? = syntheticAssetLabel
    ) -> AssemblyAccumulator? {
        guard let frame = route.frame(at: chainage) else { return nil }
        let origin = frame.position + frame.right * lateral + frame.up * vertical
        return AssemblyAccumulator(id: id, role: role, chainageM: chainage, origin: origin,
                                   forward: frame.forward, right: frame.right, up: frame.up,
                                   radius: radius, label: label)
    }

    mutating func append(_ accumulator: AssemblyAccumulator) {
        guard !accumulator.pieces.isEmpty, generatedKeys.insert(accumulator.id).inserted else { return }
        assemblies.append(accumulator.finish())
    }

    /// True when parallel streets, buildings, or trees should yield to a fictional landmark.
    func corridorReserved(at chainage: Double) -> Bool {
        landmarks.contains { landmark in
            landmark.contains(chainage, margin: SceneCorridorLandmarkSchedule.urbanClearanceM(for: landmark.kind))
        }
    }

    func chainages(step: Double) -> [Double] {
        guard step.isFinite, step > 0 else { return [] }
        var result: [Double] = []
        var value = floor(buildStartM / step) * step
        if value < route.startChainageM { value = route.startChainageM }
        while value <= buildEndM + 1e-7 {
            if value >= buildStartM - 1e-7 { result.append(value) }
            value += step
        }
        return result
    }

}

/// Deterministic, original procedural environment builder. All placements follow the route's chainage and local tangent.
public enum RailwaySceneFidelityBuilder {
    public static let syntheticPlaceholderLabel = syntheticAssetLabel

    public static func build(
        route: SceneChainageRoute,
        corridor: SceneCorridorSpecification = SceneCorridorSpecification(),
        camera: SceneCameraState,
        density: SceneDensityControls = .preset(.balanced)
    ) -> SceneBuildPlan {
        let lookAhead = density.visibleDistanceM
        let lookBehind = min(lookAhead * 0.18, 140)
        let rawStart = camera.towardIncreasingChainage ? camera.chainageM - lookBehind : camera.chainageM - lookAhead
        let rawEnd = camera.towardIncreasingChainage ? camera.chainageM + lookAhead : camera.chainageM + lookBehind
        let start = max(route.startChainageM, rawStart)
        let end = min(route.endChainageM, rawEnd)
        let landmarks = SceneCorridorLandmarkSchedule.landmarks(
            from: route.startChainageM,
            to: route.endChainageM,
            avoiding: corridor.platforms
        )
        var composer = ScenePlanComposer(route: route, corridor: corridor, camera: camera,
                                         density: density, buildStartM: start, buildEndM: end,
                                         landmarks: landmarks)
        guard start <= end else {
            return SceneBuildPlan(assemblies: [], cameraAtBuild: camera, density: density,
                                  diagnostics: SceneBuildDiagnostics(generatedAssemblyCount: 0,
                                      generatedPieceCount: 0, visibleAssemblyCountAtBuild: 0,
                                      countsByRole: [:], warnings: ["カメラのチェーン数が路線範囲外です。シーンは空です。\n"]))
        }

        appendTrack(to: &composer)
        appendCatenary(to: &composer)
        appendTracksideSigns(to: &composer)
        appendPlatforms(to: &composer)
        appendLandmarks(to: &composer)
        if corridor.generateUrbanScenery {
            appendRoadSurfaces(to: &composer)
            appendBuildings(to: &composer)
            if density.includeRoadVehicles { appendRoadVehicles(to: &composer) }
            if density.includePeople { appendPedestrians(to: &composer) }
            if density.includeVegetation { appendVegetation(to: &composer) }
        }

        let ordered = composer.assemblies.sorted {
            if $0.chainageM == $1.chainageM { return $0.id < $1.id }
            return $0.chainageM < $1.chainageM
        }
        let visibleCount = ordered.reduce(into: 0) { count, item in
            if SceneCullingPolicy.isVisible(item, camera: camera, maxDistanceM: density.visibleDistanceM) {
                count += 1
            }
        }
        var counts: [String: Int] = [:]
        for assembly in ordered { counts[assembly.role.rawValue, default: 0] += 1 }
        let pieceCount = ordered.reduce(0) { $0 + $1.pieces.count }
        return SceneBuildPlan(
            assemblies: ordered,
            cameraAtBuild: camera,
            density: density,
            diagnostics: SceneBuildDiagnostics(generatedAssemblyCount: ordered.count,
                generatedPieceCount: pieceCount, visibleAssemblyCountAtBuild: visibleCount,
                countsByRole: counts, warnings: composer.warnings)
        )
    }

    private static func appendTrack(to composer: inout ScenePlanComposer) {
        let route = composer.route
        let corridor = composer.corridor
        let controls = composer.density
        let chunkLength = max(9, controls.railChunkLengthM * 4)
        let lowerChunk = floor(composer.buildStartM / chunkLength) * chunkLength
        var chunkStart = max(route.startChainageM, lowerChunk)
        while chunkStart <= composer.buildEndM + 1e-7 {
            let segmentStart = max(chunkStart, composer.buildStartM)
            let chunkEnd = min(route.endChainageM, min(composer.buildEndM, chunkStart + chunkLength))
            guard segmentStart < chunkEnd else { chunkStart += chunkLength; continue }
            let center = (segmentStart + chunkEnd) * 0.5
            guard let centerFrame = route.frame(at: center) else { chunkStart += chunkLength; continue }
            let groupID = Int((chunkStart / chunkLength).rounded())

            if var ballast = composer.localAccumulator(id: "trackbed-\(groupID)", role: .trackBed,
                chainage: center, radius: chunkLength * 0.72) {
                let ballastStride = min(6.0, chunkLength)
                var s = segmentStart
                var n = 0
                while s < chunkEnd - 1e-6 {
                    let length = min(ballastStride + 0.04, chunkEnd - s + 0.04)
                    if let frame = route.frame(at: min(chunkEnd, s + length * 0.5)) {
                        ballast.addAt("ballast-crib-\(n)", routeFrame: frame,
                            lateralM: 0, verticalM: -0.245,
                            size: SceneVector3(4.55, 0.34, length),
                            material: .ballast)
                        ballast.addAt("subgrade-\(n)", routeFrame: frame,
                            lateralM: 0, verticalM: -0.43,
                            size: SceneVector3(5.2, 0.16, length), material: .subBallast)
                    }
                    s += ballastStride
                    n += 1
                }
                composer.append(ballast)
            }

            if var rails = composer.localAccumulator(id: "rails-\(groupID)", role: .rail,
                chainage: center, radius: chunkLength * 0.72) {
                var s = segmentStart
                var n = 0
                while s < chunkEnd - 1e-6 {
                    let length = min(controls.railChunkLengthM + 0.025, chunkEnd - s + 0.025)
                    let midpoint = min(chunkEnd, s + length * 0.5)
                    if let frame = route.frame(at: midpoint) {
                        for (side, sign) in [(-1, -1.0), (1, 1.0)] {
                            rails.addAt("running-rail-\(n)-\(side)", routeFrame: frame,
                                lateralM: sign * corridor.trackGaugeM * 0.5, verticalM: 0.085,
                                size: SceneVector3(0.074, 0.17, length),
                                material: .polishedRailSteel)
                            rails.addAt("rail-foot-\(n)-\(side)", routeFrame: frame,
                                lateralM: sign * corridor.trackGaugeM * 0.5, verticalM: 0.008,
                                size: SceneVector3(0.18, 0.028, length), material: .darkSteel,
                                minimumLOD: .medium)
                        }
                    }
                    s += controls.railChunkLengthM
                    n += 1
                }
                composer.append(rails)
            }

            if var sleepers = composer.localAccumulator(id: "sleepers-\(groupID)",
                role: .sleeper, chainage: center, radius: chunkLength * 0.72) {
                let sleeperSpacing = corridor.sleeperSpacingM
                var n = Int(ceil(segmentStart / sleeperSpacing - 1e-9))
                while Double(n) * sleeperSpacing < chunkEnd - 1e-7 {
                    let sleeperChainage = Double(n) * sleeperSpacing
                    if let frame = route.frame(at: sleeperChainage) {
                        let wood = n.isMultiple(of: 9)
                        sleepers.addAt("sleeper-\(n)", routeFrame: frame, verticalM: -0.118,
                            size: SceneVector3(2.62, 0.236, 0.255),
                            material: wood ? .wood : .concrete)
                    }
                    n += 1
                }
                composer.append(sleepers)
            }
            if controls.detailLevel >= 1,
               var fasteners = composer.localAccumulator(id: "fasteners-\(groupID)",
                    role: .trackFastener, chainage: center, radius: chunkLength * 0.72) {
                let sleeperSpacing = corridor.sleeperSpacingM
                var n = Int(ceil(segmentStart / sleeperSpacing - 1e-9))
                while Double(n) * sleeperSpacing < chunkEnd - 1e-7 {
                    let sleeperChainage = Double(n) * sleeperSpacing
                    if let frame = route.frame(at: sleeperChainage) {
                        for sign in [-1.0, 1.0] {
                            let x = sign * corridor.trackGaugeM * 0.5
                            fasteners.addAt("baseplate-\(n)-\(Int(sign))", routeFrame: frame,
                                lateralM: x, verticalM: 0.014,
                                size: SceneVector3(0.225, 0.026, 0.245), material: .darkSteel,
                                minimumLOD: .medium)
                            if controls.detailLevel >= 2 {
                                for outside in [-1.0, 1.0] {
                                    fasteners.addAt("rail-clip-\(n)-\(Int(sign))-\(Int(outside))",
                                        routeFrame: frame, lateralM: x + outside * 0.091, verticalM: 0.043,
                                        size: SceneVector3(0.035, 0.048, 0.13),
                                        rotation: SceneVector3(0, 0, outside * 0.12),
                                        material: .galvanizedSteel, minimumLOD: .high)
                                }
                            }
                        }
                    }
                    n += 1
                }
                composer.append(fasteners)
            }
            chunkStart += chunkLength
            _ = centerFrame
        }
    }

    private static func appendCatenary(to composer: inout ScenePlanComposer) {
        let route = composer.route
        let controls = composer.density
        let gauge = composer.corridor.trackGaugeM
        let contactHeight = composer.corridor.overheadContactWireHeightM
        let supportStep = composer.corridor.catenarySpacingM

        for chainage in composer.chainages(step: supportStep) {
            guard let frame = route.frame(at: chainage) else { continue }
            let supportIndex = Int((chainage / supportStep).rounded())
            for side in [supportIndex.isMultiple(of: 2) ? -1.0 : 1.0] {
                let offset = side * 3.65
                guard var support = composer.localAccumulator(
                    id: "catenary-\(Int((chainage / supportStep).rounded()))-\(Int(side))",
                    role: .catenarySupport, chainage: chainage, lateral: offset,
                    radius: 7.0, label: syntheticAssetLabel) else { continue }
                support.addLocal("mast-footing", position: SceneVector3(0, -0.10, 0),
                    size: SceneVector3(0.55, 0.20, 0.55), material: .concrete)
                support.addLocal("steel-mast", shape: .cylinder, position: SceneVector3(0, 3.15, 0),
                    size: SceneVector3(0.19, 6.30, 0.19), material: .galvanizedSteel)
                support.addLocal("mast-collar-lower", position: SceneVector3(0, 1.05, 0),
                    size: SceneVector3(0.30, 0.10, 0.30), material: .darkSteel, minimumLOD: .medium)
                support.addLocal("mast-collar-upper", position: SceneVector3(0, 4.15, 0),
                    size: SceneVector3(0.28, 0.09, 0.28), material: .darkSteel, minimumLOD: .medium)
                let armDirection = -side
                support.addLocal("cantilever-arm", position: SceneVector3(armDirection * 1.65, contactHeight - 0.15, 0),
                    size: SceneVector3(3.65, 0.12, 0.12), material: .galvanizedSteel)
                support.addLocal("support-brace", position: SceneVector3(armDirection * 0.95, 4.62, 0),
                    size: SceneVector3(0.10, 1.05, 0.10),
                    rotation: SceneVector3(0, 0, -armDirection * 0.55), material: .darkSteel,
                    minimumLOD: .medium)
                let wireX = armDirection * (3.65 - gauge * 0.5)
                for (index, y) in [(0, contactHeight - 0.10), (1, contactHeight + 0.83)] {
                    support.addLocal("ceramic-insulator-\(index)", shape: .cylinder,
                        position: SceneVector3(wireX, y, 0), size: SceneVector3(0.12, 0.27, 0.12),
                        material: .ceramicInsulator, minimumLOD: .medium)
                }
                support.addLocal("dropper-bracket", position: SceneVector3(wireX, contactHeight + 0.38, 0),
                    size: SceneVector3(0.16, 0.045, 0.06), material: .darkSteel,
                    minimumLOD: .medium)
                _ = frame
                composer.append(support)
            }
        }

        // Contact and messenger wires are broken into short tangent-following spans with explicit catenary sag.
        let wireChunk = max(12, min(24, controls.railChunkLengthM * 8))
        let lower = floor(composer.buildStartM / wireChunk) * wireChunk
        var chunkStart = max(route.startChainageM, lower)
        while chunkStart < composer.buildEndM - 1e-7 {
            let chunkEnd = min(composer.buildEndM, chunkStart + wireChunk)
            let center = (chunkStart + chunkEnd) * 0.5
            guard let frame = route.frame(at: center),
                  var wires = composer.localAccumulator(id: "overhead-wires-\(Int((chunkStart / wireChunk).rounded()))",
                    role: .overheadWire, chainage: center, radius: wireChunk * 0.8) else {
                chunkStart += wireChunk
                continue
            }
            let segmentStep = min(3.0, max(1.0, controls.railChunkLengthM))
            var s = chunkStart
            var index = 0
            while s < chunkEnd - 1e-7 {
                let e = min(chunkEnd, s + segmentStep)
                let middle = (s + e) * 0.5
                if let middleFrame = route.frame(at: middle) {
                    let t = (middle - chunkStart) / max(1e-6, chunkEnd - chunkStart)
                    let sag = 0.045 * 4 * t * (1 - t)
                    for (wireIndex, height, lateral, gaugeSize, material) in [
                        (0, contactHeight, 0.0, 0.018, SceneMaterialStyle.polishedRailSteel),
                        (1, contactHeight + 0.82, 0.0, 0.014, SceneMaterialStyle.galvanizedSteel)
                    ] {
                        let baseY = height - (wireIndex == 0 ? sag : sag * 0.55)
                        let halfLength = (e - s) * 0.5
                        wires.addAt("wire-\(wireIndex)-\(index)", routeFrame: middleFrame,
                            lateralM: lateral, verticalM: baseY,
                            size: SceneVector3(gaugeSize, gaugeSize, max(0.25, e - s + 0.04)),
                            material: material, minimumLOD: .medium)
                        if wireIndex == 0, controls.detailLevel >= 2,
                           index % max(1, Int(6 / segmentStep)) == 0 {
                            wires.addAt("wire-dropper-\(index)", routeFrame: middleFrame,
                                lateralM: 0, verticalM: contactHeight + 0.41,
                                size: SceneVector3(0.018, 0.82, 0.018), material: .darkSteel,
                                minimumLOD: .high)
                        }
                        _ = halfLength
                        _ = gaugeSize
                    }
                }
                s = e
                index += 1
            }
            composer.append(wires)
            _ = frame
            chunkStart += wireChunk
        }
    }

    /// Lineside kilometre posts (every 1 km) and marker boards (every
    /// 250 m, alternating sides): the small track furniture BVE routes
    /// repeat along the whole line, so no stretch reads as empty.
    /// Track furniture like the catenary masts, not urban scenery.
    private static func appendTracksideSigns(to composer: inout ScenePlanComposer) {
        var km = Int((composer.buildStartM / 1000).rounded(.down))
        var kmChainage = Double(km) * 1000
        while kmChainage <= composer.buildEndM {
            if kmChainage >= composer.buildStartM,
               var post = composer.localAccumulator(
                id: "trackside-kmpost-\(km)", role: .tracksideSign,
                chainage: kmChainage, lateral: 3.2, radius: 1.5,
                label: syntheticAssetLabel) {
                post.addLocal("km-post", position: SceneVector3(0, 0.85, 0),
                    size: SceneVector3(0.12, 1.7, 0.12), material: .darkSteel)
                post.addLocal("km-plate", position: SceneVector3(0, 1.55, 0),
                    size: SceneVector3(0.42, 0.30, 0.06), material: .buildingCool,
                    minimumLOD: .medium)
                post.addLocal("km-plate-band", position: SceneVector3(0, 1.55, 0.035),
                    size: SceneVector3(0.30, 0.06, 0.012), material: .tactileAmber,
                    minimumLOD: .medium)
                composer.append(post)
            }
            km += 1
            kmChainage = Double(km) * 1000
        }
        var marker = Int((composer.buildStartM / 250).rounded(.down))
        var markerChainage = Double(marker) * 250
        while markerChainage <= composer.buildEndM {
            if markerChainage >= composer.buildStartM {
                let side: Double = marker.isMultiple(of: 2) ? -1 : 1
                if var board = composer.localAccumulator(
                    id: "trackside-marker-\(marker)", role: .tracksideSign,
                    chainage: markerChainage, lateral: side * 3.1, radius: 1.5,
                    label: syntheticAssetLabel) {
                    board.addLocal("marker-post", position: SceneVector3(0, 0.75, 0),
                        size: SceneVector3(0.10, 1.5, 0.10), material: .galvanizedSteel)
                    board.addLocal("marker-board", position: SceneVector3(0, 1.35, 0),
                        size: SceneVector3(0.55, 0.42, 0.05), material: .buildingCool,
                        minimumLOD: .medium)
                    board.addLocal("marker-stripe", position: SceneVector3(0, 1.35, 0.03),
                        size: SceneVector3(0.55, 0.09, 0.012), material: .tactileAmber,
                        minimumLOD: .medium)
                    composer.append(board)
                }
            }
            marker += 1
            markerChainage = Double(marker) * 250
        }
    }

    private static func appendPlatforms(to composer: inout ScenePlanComposer) {
        let route = composer.route
        let controls = composer.density
        for platform in composer.corridor.platforms {
            let clippedStart = max(platform.startChainageM, composer.buildStartM)
            let clippedEnd = min(platform.endChainageM, composer.buildEndM)
            guard platform.startChainageM.isFinite, platform.endChainageM.isFinite,
                  platform.endChainageM > platform.startChainageM,
                  clippedStart < clippedEnd else { continue }
            let moduleLength = 12.0
            var start = floor(clippedStart / moduleLength) * moduleLength
            while start < clippedEnd - 1e-7 {
                let end = min(clippedEnd, start + moduleLength)
                let center = (start + end) * 0.5
                guard let centerFrame = route.frame(at: center),
                      var platformBody = composer.localAccumulator(
                        id: "platform-\(platform.id)-\(Int(start.rounded()))", role: .platform,
                        chainage: center, lateral: Double(platform.side) * platform.offsetFromTrackCenterM,
                        vertical: 0.48, radius: moduleLength * 0.7,
                        label: "SYNTHETIC STATION PLACEHOLDER — VERIFY PLATFORM LOCATION") else {
                    start += moduleLength
                    continue
                }
                let length = end - start + 0.04
                platformBody.addAt("platform-slab", routeFrame: centerFrame,
                    lateralM: Double(platform.side) * platform.offsetFromTrackCenterM, verticalM: 0.27,
                    size: SceneVector3(platform.widthM, 0.42, length), material: .platformConcrete)
                platformBody.addAt("platform-edge-band", routeFrame: centerFrame,
                    lateralM: Double(platform.side) * (platform.offsetFromTrackCenterM - platform.widthM * 0.5 + 0.08), verticalM: 0.50,
                    size: SceneVector3(0.12, 0.045, length), material: .tactileAmber,
                    minimumLOD: .medium)
                if controls.detailLevel >= 1 {
                    let tileStep = 0.50
                    var tileS = start
                    var tile = 0
                    while tileS < end {
                        if let tileFrame = route.frame(at: tileS) {
                            platformBody.addAt("tactile-warning-tile-\(tile)", routeFrame: tileFrame,
                                lateralM: Double(platform.side) * (platform.offsetFromTrackCenterM - platform.widthM * 0.5 + 0.27),
                                verticalM: 0.49, size: SceneVector3(0.28, 0.012, 0.33),
                                material: .tactileAmber, minimumLOD: .high)
                        }
                        tileS += tileStep
                        tile += 1
                    }
                }
                composer.append(platformBody)
                start += moduleLength
            }

            // Posts, canopy beams, benches, lights and blank synthetic wayfinding panels are separate serviceable nodes.
            for chainage in composer.chainages(step: 5.0) {
                guard chainage >= clippedStart, chainage <= clippedEnd,
                      let frame = route.frame(at: chainage) else { continue }
                if platform.hasCanopy, var canopy = composer.localAccumulator(
                    id: "canopy-\(platform.id)-\(Int(chainage.rounded()))", role: .stationFurniture,
                    chainage: chainage, lateral: Double(platform.side) * platform.offsetFromTrackCenterM,
                    vertical: 0.48, radius: 4.5,
                    label: "SYNTHETIC STATION FURNITURE — NO REAL OPERATOR MARKS") {
                    let outer = -Double(platform.side) * (platform.widthM * 0.5 - 0.16)
                    for (index, lateral) in [outer, Double(platform.side) * (platform.widthM * 0.5 - 0.22)].enumerated() {
                        canopy.addLocal("canopy-column-\(index)", position: SceneVector3(lateral, 1.75, 0),
                            size: SceneVector3(0.13, 3.5, 0.13), material: .canopyMetal)
                        canopy.addLocal("column-foot-\(index)", position: SceneVector3(lateral, 0.18, 0),
                            size: SceneVector3(0.30, 0.18, 0.30), material: .darkSteel,
                            minimumLOD: .medium)
                    }
                    canopy.addLocal("canopy-roof", position: SceneVector3(0, 3.53, 0),
                        size: SceneVector3(platform.widthM, 0.15, 5.2), material: .canopyMetal)
                    canopy.addLocal("canopy-gutter", position: SceneVector3(-Double(platform.side) * platform.widthM * 0.5, 3.40, 0),
                        size: SceneVector3(0.12, 0.12, 5.1), material: .darkSteel,
                        minimumLOD: .medium)
                    composer.append(canopy)
                }
                if Int(chainage.rounded()) % 20 < 5,
                   var furnishing = composer.localAccumulator(
                    id: "platform-light-\(platform.id)-\(Int(chainage.rounded()))", role: .stationFurniture,
                    chainage: chainage, lateral: Double(platform.side) * (platform.offsetFromTrackCenterM + platform.widthM * 0.35),
                    vertical: 0.48, radius: 4.0,
                    label: "SYNTHETIC PLATFORM LIGHT — LIGHTING NOT PHOTOMETRIC") {
                    furnishing.addLocal("light-pole", shape: .cylinder, position: SceneVector3(0, 2.0, 0),
                        size: SceneVector3(0.10, 4.0, 0.10), material: .darkSteel)
                    furnishing.addLocal("light-head", position: SceneVector3(0, 4.03, 0),
                        size: SceneVector3(0.42, 0.13, 0.32), material: .tactileAmber)
                    composer.append(furnishing)
                }
                if Int(chainage.rounded()) % 25 < 5,
                   var bench = composer.localAccumulator(
                    id: "platform-bench-\(platform.id)-\(Int(chainage.rounded()))", role: .stationFurniture,
                    chainage: chainage, lateral: Double(platform.side) * (platform.offsetFromTrackCenterM + platform.widthM * 0.12),
                    vertical: 0.0, radius: 2.5,
                    label: "SYNTHETIC PLATFORM FURNITURE") {
                    bench.addLocal("bench-seat", position: SceneVector3(0, 0.52, 0),
                        size: SceneVector3(1.65, 0.10, 0.42), material: .wood)
                    bench.addLocal("bench-back", position: SceneVector3(0, 0.93, 0.18),
                        size: SceneVector3(1.65, 0.55, 0.10), material: .wood)
                    for x in [-0.58, 0.58] {
                        bench.addLocal("bench-leg-\(x)", position: SceneVector3(x, 0.24, 0),
                            size: SceneVector3(0.09, 0.48, 0.32), material: .darkSteel)
                    }
                    composer.append(bench)
                }
                if Int(chainage.rounded()) % 40 < 5,
                   var bin = composer.localAccumulator(
                    id: "platform-bin-\(platform.id)-\(Int(chainage.rounded()))", role: .stationFurniture,
                    chainage: chainage, lateral: Double(platform.side) * (platform.offsetFromTrackCenterM + platform.widthM * 0.28),
                    vertical: 0.48, radius: 1.2,
                    label: "SYNTHETIC PLATFORM BIN — BLANK, NO OPERATOR MARK") {
                    bin.addLocal("platform-bin", position: SceneVector3(0, 0.55, 0),
                        size: SceneVector3(0.48, 0.85, 0.38), material: .darkSteel)
                    composer.append(bin)
                }
                _ = frame
            }
            let signChainage = platform.startChainageM
                + min(15, (platform.endChainageM - platform.startChainageM) * 0.5)
            if signChainage >= composer.buildStartM, signChainage <= composer.buildEndM,
               var sign = composer.localAccumulator(
                id: "synthetic-platform-sign-\(platform.id)", role: .stationFurniture,
                chainage: signChainage, lateral: Double(platform.side) * platform.offsetFromTrackCenterM,
                vertical: 0.48, radius: 3.0,
                label: "SYNTHETIC WAYFINDING PANEL — NO REAL STATION NAME OR OPERATOR") {
                sign.addLocal("sign-post", shape: .cylinder, position: SceneVector3(0, 1.1, 0),
                    size: SceneVector3(0.11, 2.2, 0.11), material: .darkSteel)
                sign.addLocal("blank-sign-face", position: SceneVector3(0, 2.18, 0),
                    size: SceneVector3(1.55, 0.72, 0.10), material: .buildingCool)
                sign.addLocal("placeholder-color-band", position: SceneVector3(0, 2.22, 0.058),
                    size: SceneVector3(1.10, 0.10, 0.018), material: .tactileAmber,
                    minimumLOD: .medium)
                composer.append(sign)
            }
        }
    }

    private static func appendRoadSurfaces(to composer: inout ScenePlanComposer) {
        let route = composer.route
        let chunkLength = 18.0
        var start = max(route.startChainageM, floor(composer.buildStartM / chunkLength) * chunkLength)
        while start < composer.buildEndM - 1e-7 {
            let end = min(composer.buildEndM, start + chunkLength)
            let center = (start + end) * 0.5
            if composer.corridorReserved(at: center) { start += chunkLength; continue }
            guard let frame = route.frame(at: center) else { start += chunkLength; continue }
            let group = Int((start / chunkLength).rounded())
            for side in [-1.0, 1.0] {
                guard var road = composer.localAccumulator(
                    id: "synthetic-road-surface-\(group)-\(Int(side))", role: .roadSurface,
                    chainage: center, lateral: side * 11.0, vertical: -0.10,
                    radius: chunkLength * 0.8,
                    label: "SYNTHETIC STREET PLACEHOLDER — ALIGNMENT AND MARKINGS ARE FICTIONAL") else { continue }
                let length = end - start + 0.08
                road.addLocal("asphalt-carriageway", position: SceneVector3(0, 0, 0),
                    size: SceneVector3(6.4, 0.20, length), material: .roadAsphalt)
                road.addLocal("inner-curb", position: SceneVector3(-side * 3.22, 0.05, 0),
                    size: SceneVector3(0.22, 0.30, length), material: .concrete)
                road.addLocal("outer-curb", position: SceneVector3(side * 3.22, 0.05, 0),
                    size: SceneVector3(0.22, 0.30, length), material: .concrete)
                road.addLocal("sidewalk", position: SceneVector3(side * 4.15, 0.085, 0),
                    size: SceneVector3(1.65, 0.17, length), material: .platformConcrete)
                var dashChainage = start
                var dashIndex = 0
                while dashChainage < end {
                    if let dashFrame = route.frame(at: dashChainage) {
                        road.addAt("lane-dash-\(dashIndex)", routeFrame: dashFrame,
                            lateralM: side * 11.0, verticalM: 0.011,
                            size: SceneVector3(0.12, 0.012, 2.2), material: .roadPaint,
                            minimumLOD: .medium)
                    }
                    dashChainage += 8.0
                    dashIndex += 1
                }
                composer.append(road)
            }
            start += chunkLength
            _ = frame
        }
    }

    /// Buildings line both sides of the track at every step, with a
    /// second row behind the first every third step: the BVE benchmark
    /// routes never leave one side empty, and a single alternating line
    /// reads as a fence rather than a settled area.
    private static func appendBuildings(to composer: inout ScenePlanComposer) {
        let route = composer.route
        var index = Int((composer.buildStartM / composer.density.scenerySpacingM).rounded(.down))
        var chainage = Double(index) * composer.density.scenerySpacingM
        while chainage <= composer.buildEndM {
            guard let frame = route.frame(at: chainage) else { chainage += composer.density.scenerySpacingM; index += 1; continue }
            if composer.corridorReserved(at: chainage) {
                chainage += composer.density.scenerySpacingM * (1.35 + randomUnit(seed: UInt64(index &* 2141 &+ 5)) * 0.75)
                index += 1
                continue
            }
            for sideIndex in 0..<2 {
                let side: Double = sideIndex == 0 ? -1 : 1
                appendOneBuilding(to: &composer, slot: index * 2 + sideIndex,
                                  chainage: chainage, side: side,
                                  lateralBase: 14, lateralSpread: 12,
                                  id: "synthetic-building-\(index * 2 + sideIndex)")
            }
            if index % 3 == 0 {
                for sideIndex in 0..<2 {
                    let side: Double = sideIndex == 0 ? -1 : 1
                    appendOneBuilding(to: &composer, slot: 100_000 + index * 2 + sideIndex,
                                      chainage: chainage, side: side,
                                      lateralBase: 30, lateralSpread: 6,
                                      id: "synthetic-building-back-\(index * 2 + sideIndex)")
                }
            }
            chainage += composer.density.scenerySpacingM * (1.35 + randomUnit(seed: UInt64(index &* 2141 &+ 5)) * 0.75)
            index += 1
            _ = frame
        }
    }

    private static func appendOneBuilding(
        to composer: inout ScenePlanComposer,
        slot: Int,
        chainage: Double,
        side: Double,
        lateralBase: Double,
        lateralSpread: Double,
        id: String
    ) {
        let jitter = randomUnit(seed: UInt64(slot &* 7919 &+ 23))
        let offset = side * (lateralBase + jitter * lateralSpread)
        let width = 7.5 + randomUnit(seed: UInt64(slot &* 3571 &+ 109)) * 8.0
        let height = 7.5 + randomUnit(seed: UInt64(slot &* 1237 &+ 31)) * 12.5
        let depth = 7 + randomUnit(seed: UInt64(slot &* 1879 &+ 17)) * 8
        guard composer.reserveScenery(), var building = composer.localAccumulator(
            id: id, role: .building,
            chainage: chainage, lateral: offset, radius: sqrt(width * width + depth * depth + height * height) * 0.52,
            label: "SYNTHETIC BUILDING — FICTIONAL FACADE, SCALE AND USE") else { return }
        appendBuildingPieces(to: &building, slot: slot, width: width, height: height, depth: depth,
                             detailLevel: composer.density.detailLevel)
        composer.append(building)
    }

    private static func appendBuildingPieces(
        to building: inout AssemblyAccumulator,
        slot: Int,
        width: Double,
        height: Double,
        depth: Double,
        detailLevel: Int
    ) {
        let kind = slot % 4
        var bodyWidth = width
        var bodyHeight = height
        var bodyDepth = depth
        var bodyName = "facade-volume"
        var bodyMaterial: SceneMaterialStyle = slot.isMultiple(of: 3) ? .buildingCool : .buildingWarm
        var roofMaterial: SceneMaterialStyle = .darkSteel
        var roofThickness = 0.24
        switch kind {
        case 1:
            bodyHeight = min(height, 6.4)
            bodyName = "house-body"
            roofThickness = 0.85
            roofMaterial = .buildingWarm
        case 2:
            bodyWidth = width * 1.35
            bodyHeight = min(5.4, height * 0.42)
            bodyDepth = depth * 1.15
            bodyName = "warehouse-volume"
            bodyMaterial = .buildingCool
            roofMaterial = .galvanizedSteel
        case 3:
            bodyHeight = min(7.5, height * 0.55)
            bodyName = "shop-volume"
            bodyMaterial = .buildingWarm
        default:
            break
        }
        building.addLocal(bodyName, position: SceneVector3(0, bodyHeight * 0.5, 0),
            size: SceneVector3(bodyWidth, bodyHeight, bodyDepth), material: bodyMaterial)
        building.addLocal(kind == 1 ? "house-roof" : "roof-cap", position: SceneVector3(0, bodyHeight + roofThickness * 0.45, 0),
            size: SceneVector3(bodyWidth + 0.4, roofThickness, bodyDepth + 0.4), material: roofMaterial)
        if kind == 3 {
            building.addLocal("shop-awning", position: SceneVector3(0, 2.4, bodyDepth * 0.5 + 0.45),
                size: SceneVector3(bodyWidth * 0.92, 0.08, 1.1), material: .canopyMetal)
        }
        building.addLocal("ground-floor-plinth", position: SceneVector3(0, 0.35, 0),
            size: SceneVector3(bodyWidth + 0.12, 0.70, bodyDepth + 0.12), material: .concrete)
        let height = bodyHeight
        let width = bodyWidth
        let depth = bodyDepth
        let floors = max(kind == 2 ? 1 : 2, Int(height / 3.0))
        for floor in 0..<floors {
            let y = 1.45 + Double(floor) * 2.55
            for bay in 0..<max(2, Int(width / 2.2)) {
                let x = -width * 0.5 + 1.1 + Double(bay) * 2.2
                if detailLevel >= 1 {
                    for sideFace in [-1.0, 1.0] {
                        building.addLocal("window-side-\(floor)-\(bay)-\(Int(sideFace))",
                            position: SceneVector3(sideFace * (width * 0.5 + 0.014), y, x * 0.12),
                            size: SceneVector3(0.035, 1.18, 1.10), material: .windowGlass,
                            minimumLOD: .medium)
                    }
                    building.addLocal("front-window-\(floor)-\(bay)",
                        position: SceneVector3(x, y, depth * 0.5 + 0.015),
                        size: SceneVector3(1.15, 1.16, 0.035), material: .windowGlass,
                        minimumLOD: .medium)
                    building.addLocal("rear-window-\(floor)-\(bay)",
                        position: SceneVector3(x, y, -depth * 0.5 - 0.015),
                        size: SceneVector3(1.15, 1.16, 0.035), material: .windowGlass,
                        minimumLOD: .medium)
                }
            }
            if detailLevel >= 2, floor.isMultiple(of: 2) {
                for balcony in 0..<max(1, Int(width / 5.0)) {
                    let x = -width * 0.35 + Double(balcony) * 4.8
                    building.addLocal("balcony-slab-\(floor)-\(balcony)",
                        position: SceneVector3(x, y - 0.66, depth * 0.5 + 0.28),
                        size: SceneVector3(2.6, 0.10, 0.72), material: .concrete,
                        minimumLOD: .high)
                    building.addLocal("balcony-rail-\(floor)-\(balcony)",
                        position: SceneVector3(x, y - 0.30, depth * 0.5 + 0.55),
                        size: SceneVector3(2.55, 0.08, 0.07), material: .darkSteel,
                        minimumLOD: .high)
                }
            }
        }
        for sideFace in [-1.0, 1.0] {
            building.addLocal("rainwater-pipe-\(Int(sideFace))", shape: .cylinder,
                position: SceneVector3(sideFace * (width * 0.5 - 0.18), height * 0.5, -depth * 0.5 + 0.20),
                size: SceneVector3(0.09, height, 0.09), material: .darkSteel,
                minimumLOD: .medium)
        }
    }

    private static func appendRoadVehicles(to composer: inout ScenePlanComposer) {
        let step = max(16, composer.density.scenerySpacingM * 1.3)
        for chainage in composer.chainages(step: step) {
            let slot = Int((chainage / step).rounded())
            guard let frame = composer.route.frame(at: chainage) else { continue }
            if composer.corridorReserved(at: chainage) { continue }
            guard composer.reserveScenery() else { continue }
            let side: Double = slot.isMultiple(of: 2) ? -1 : 1
            let laneOffset = side * (9.0 + randomUnit(seed: UInt64(slot &* 449 &+ 71)) * 2.2)
            let length = 4.25 + randomUnit(seed: UInt64(slot &* 271 &+ 7)) * 0.65
            let width = 1.76 + randomUnit(seed: UInt64(slot &* 953 &+ 11)) * 0.22
            let paint: SceneMaterialStyle = slot % 3 == 0 ? .vehicleBlue : (slot % 3 == 1 ? .vehicleRed : .vehicleSilver)
            guard var car = composer.localAccumulator(id: "synthetic-road-vehicle-\(slot)", role: .roadVehicle,
                chainage: chainage, lateral: laneOffset, vertical: 0.0,
                radius: 3.4, label: "SYNTHETIC TRAFFIC — NOT A REAL MAKE OR LICENSE PLATE") else { continue }
            car.addLocal("monocoque-body", position: SceneVector3(0, 0.48, 0),
                size: SceneVector3(width, 0.82, length), material: paint)
            car.addLocal("roof", position: SceneVector3(0, 1.03, -0.12),
                size: SceneVector3(width * 0.78, 0.47, length * 0.50), material: paint)
            car.addLocal("front-windscreen", position: SceneVector3(0, 1.02, length * 0.28),
                size: SceneVector3(width * 0.69, 0.34, 0.035), material: .windowGlass)
            car.addLocal("rear-glass", position: SceneVector3(0, 1.02, -length * 0.28),
                size: SceneVector3(width * 0.67, 0.31, 0.035), material: .windowGlass)
            for side in [-1.0, 1.0] {
                for axle in [-1.0, 1.0] {
                    car.addLocal("wheel-\(Int(side))-\(Int(axle))", shape: .cylinder,
                        position: SceneVector3(side * width * 0.49, 0.31, axle * length * 0.31),
                        size: SceneVector3(0.25, 0.61, 0.61),
                        rotation: SceneVector3(0, 0, .pi / 2), material: .tireRubber)
                    car.addLocal("side-glass-\(Int(side))-\(Int(axle))",
                        position: SceneVector3(side * (width * 0.5 + 0.015), 0.99, axle * 0.52),
                        size: SceneVector3(0.035, 0.30, 0.72), material: .windowGlass,
                        minimumLOD: .medium)
                }
                car.addLocal("headlamp-\(Int(side))", position: SceneVector3(side * 0.57, 0.55, length * 0.5 + 0.02),
                    size: SceneVector3(0.18, 0.12, 0.035), material: .tactileAmber,
                    minimumLOD: .medium)
            }
            car.addLocal("front-grille", position: SceneVector3(0, 0.49, length * 0.5 + 0.02),
                size: SceneVector3(0.62, 0.20, 0.035), material: .darkSteel,
                minimumLOD: .medium)
            composer.append(car)
            _ = frame
        }
    }

    private static func appendPedestrians(to composer: inout ScenePlanComposer) {
        for platform in composer.corridor.platforms {
            let start = max(platform.startChainageM, composer.buildStartM)
            let end = min(platform.endChainageM, composer.buildEndM)
            guard start < end else { continue }
            let step = max(7.5, composer.density.scenerySpacingM * 0.9)
            for chainage in composer.chainages(step: step) {
                guard chainage >= start, chainage <= end else { continue }
                let slot = Int((chainage / step).rounded())
                guard composer.reserveScenery() else { continue }
                let lateral = Double(platform.side) * (platform.offsetFromTrackCenterM - platform.widthM * 0.5 + 0.6
                    + randomUnit(seed: UInt64(slot &* 191 &+ 3)) * max(0.1, platform.widthM - 1.2))
                let turn = randomUnit(seed: UInt64(slot &* 577 &+ 19))
                guard var person = composer.localAccumulator(
                    id: "synthetic-person-\(platform.id)-\(slot)", role: .pedestrian,
                    chainage: chainage, lateral: lateral, vertical: 0.23,
                    radius: 1.25,
                    label: "SYNTHETIC HUMAN PLACEHOLDER — NO IDENTITY OR BEHAVIOUR CLAIM") else { continue }
                let jacket: SceneMaterialStyle = turn < 0.5 ? .personJacket : .vehicleBlue
                let trousers: SceneMaterialStyle = turn < 0.5 ? .personTrousers : .darkSteel
                person.addLocal("torso", position: SceneVector3(0, 1.15, 0),
                    size: SceneVector3(0.43, 0.67, 0.25), material: jacket)
                person.addLocal("head", shape: .sphere, position: SceneVector3(0, 1.69, 0),
                    size: SceneVector3(0.22, 0.25, 0.22), material: .skinTone)
                for side in [-1.0, 1.0] {
                    person.addLocal("leg-\(Int(side))", position: SceneVector3(side * 0.12, 0.60, 0),
                        size: SceneVector3(0.16, 0.52, 0.19), material: trousers)
                    person.addLocal("arm-\(Int(side))", shape: .cylinder,
                        position: SceneVector3(side * 0.28, 1.16, 0.015),
                        size: SceneVector3(0.105, 0.58, 0.105),
                        rotation: SceneVector3(0, 0, -side * 0.12), material: jacket)
                    person.addLocal("shoe-\(Int(side))", position: SceneVector3(side * 0.12, 0.30, 0.07),
                        size: SceneVector3(0.17, 0.10, 0.29), material: .darkSteel)
                }
                if composer.density.detailLevel >= 2 {
                    person.addLocal("shoulder-bag", position: SceneVector3(-0.23, 0.99, 0.13),
                        size: SceneVector3(0.19, 0.26, 0.12), material: .vehicleRed,
                        minimumLOD: .high)
                }
                composer.append(person)
            }
        }
    }

    private static func appendVegetation(to composer: inout ScenePlanComposer) {
        let spacing = max(composer.density.scenerySpacingM * 1.0, 12)
        for chainage in composer.chainages(step: spacing) {
            let index = Int((chainage / spacing).rounded())
            guard let frame = composer.route.frame(at: chainage) else { continue }
            if composer.corridorReserved(at: chainage) { continue }
            guard composer.reserveScenery() else { continue }
            let side: Double = index.isMultiple(of: 2) ? -1 : 1
            let lateral = side * (7.2 + randomUnit(seed: UInt64(index &* 397 &+ 29)) * 8.0)
            if index.isMultiple(of: 3) {
                guard var hedge = composer.localAccumulator(id: "synthetic-hedge-\(index)", role: .vegetation,
                    chainage: chainage, lateral: lateral, vertical: 0, radius: 6,
                    label: "SYNTHETIC HEDGE — ORIGINAL SHRUB MASS, NOT A SURVEYED PLANTING") else { continue }
                for clump in 0..<4 {
                    let z = -3.2 + Double(clump) * 2.1
                    hedge.addLocal("hedge-mass-\(clump)", position: SceneVector3(0, 0.7, z),
                        size: SceneVector3(1.15, 1.35, 1.8), material: clump.isMultiple(of: 2) ? .foliageDeep : .foliageLight)
                }
                composer.append(hedge)
                continue
            }
            let height = 4.5 + randomUnit(seed: UInt64(index &* 811 &+ 13)) * 5.4
            let canopyWidth = 2.5 + randomUnit(seed: UInt64(index &* 683 &+ 37)) * 2.8
            guard var tree = composer.localAccumulator(id: "synthetic-tree-\(index)", role: .vegetation,
                chainage: chainage, lateral: lateral, vertical: 0,
                radius: height * 0.85 + canopyWidth,
                label: "SYNTHETIC VEGETATION — PROCEDURAL SHAPE, NOT A BOTANICAL SPECIMEN") else { continue }
            tree.addLocal("trunk", shape: .cylinder, position: SceneVector3(0, height * 0.33, 0),
                size: SceneVector3(0.32, height * 0.68, 0.32), material: .bark)
            if index.isMultiple(of: 4) {
                for clump in [(-1.4, 0.8), (1.2, -0.6)] {
                    tree.addLocal("cluster-trunk-\(clump.0)", shape: .cylinder,
                        position: SceneVector3(clump.0, height * 0.22, clump.1),
                        size: SceneVector3(0.22, height * 0.46, 0.22), material: .bark)
                    tree.addLocal("cluster-canopy-\(clump.0)", shape: .sphere,
                        position: SceneVector3(clump.0, height * 0.62, clump.1),
                        size: SceneVector3(canopyWidth * 0.55, height * 0.28, canopyWidth * 0.55),
                        material: .foliageLight, minimumLOD: .medium)
                }
            }
            tree.addLocal("low-branch", position: SceneVector3(0.26, height * 0.46, 0),
                size: SceneVector3(0.12, 0.11, height * 0.28),
                rotation: SceneVector3(0, 0, -0.42), material: .bark, minimumLOD: .medium)
            let tiers = composer.density.detailLevel >= 2 ? 4 : 2
            for tier in 0..<tiers {
                let t = Double(tier) / Double(max(1, tiers - 1))
                let y = height * (0.55 + t * 0.38)
                let radius = canopyWidth * (1 - t * 0.45)
                tree.addLocal("canopy-mass-\(tier)", shape: .sphere,
                    position: SceneVector3((tier.isMultiple(of: 2) ? -0.18 : 0.18), y, 0),
                    size: SceneVector3(radius, max(1.35, height * 0.36), radius),
                    material: tier.isMultiple(of: 2) ? .foliageDeep : .foliageLight,
                    minimumLOD: tier == 0 ? .far : .medium)
            }
            composer.append(tree)
            _ = frame
        }
    }

    /// Curve-following PLACEHOLDER spans. Chunks use an absolute chainage grid so a
    /// streaming camera window rebuilds the same assembly IDs as a wider build.
    private static func appendLandmarks(to composer: inout ScenePlanComposer) {
        for landmark in composer.landmarks {
            let route = composer.route
            let detailLevel = composer.density.detailLevel
            switch landmark.kind {
            case .riverBridge:
                appendChunkedLandmark(landmark, to: &composer, role: .bridgeStructure, radius: 18,
                    label: "SYNTHETIC RIVER BRIDGE — FICTIONAL SPAN AND WATER, NOT A SURVEYED STRUCTURE"
                ) { assembly, chunk in
                    appendBridgePieces(to: &assembly, route: route, detailLevel: detailLevel,
                                       landmark: landmark, frame: chunk.frame, cursor: chunk.cursor, length: chunk.length)
                }
            case .cutting:
                appendChunkedLandmark(landmark, to: &composer, role: .cuttingWall, radius: 12,
                    label: "SYNTHETIC CUTTING — FICTIONAL RETAINING WALLS, NOT A MEASURED EARTHWORK"
                ) { assembly, chunk in
                    appendCuttingPieces(to: &assembly, detailLevel: detailLevel, frame: chunk.frame, length: chunk.length)
                }
            case .embankment:
                appendChunkedLandmark(landmark, to: &composer, role: .embankment, radius: 14,
                    label: "SYNTHETIC EMBANKMENT — FICTIONAL SLOPE, NOT A MEASURED EARTHWORK"
                ) { assembly, chunk in
                    appendEmbankmentPieces(to: &assembly, detailLevel: detailLevel, frame: chunk.frame, length: chunk.length)
                }
            case .levelCrossing:
                appendLevelCrossing(landmark, to: &composer)
            }
        }
    }

    private struct LandmarkChunk {
        let cursor: Double
        let length: Double
        let frame: SceneRouteFrame
        let index: Int
    }

    private static func landmarkChunks(
        _ landmark: SceneCorridorLandmark,
        route: SceneChainageRoute,
        buildStartM: Double,
        buildEndM: Double,
        step: Double
    ) -> [LandmarkChunk] {
        let routeEnd = route.endChainageM
        var cursor = landmark.startChainageM
        var chunks: [LandmarkChunk] = []
        while cursor < min(landmark.endChainageM, routeEnd) - 0.4 {
            let next = min(landmark.endChainageM, cursor + step)
            let chunkEnd = min(next, routeEnd)
            let length = chunkEnd - cursor
            let overlaps = chunkEnd > buildStartM + 1e-6 && cursor < buildEndM - 1e-6
            if overlaps, length > 0.4, let frame = route.frame(at: cursor + length * 0.5) {
                chunks.append(LandmarkChunk(
                    cursor: cursor,
                    length: length,
                    frame: frame,
                    index: Int((cursor / step).rounded())
                ))
            }
            cursor = next
        }
        return chunks
    }

    private static func appendChunkedLandmark(
        _ landmark: SceneCorridorLandmark,
        to composer: inout ScenePlanComposer,
        role: SceneAssemblyRole,
        radius: Double,
        label: String,
        fill: (inout AssemblyAccumulator, LandmarkChunk) -> Void
    ) {
        let chunks = landmarkChunks(landmark, route: composer.route, buildStartM: composer.buildStartM,
                                    buildEndM: composer.buildEndM, step: 16)
        for chunk in chunks {
            guard var assembly = composer.localAccumulator(
                id: "\(landmark.id)-c\(chunk.index)",
                role: role,
                chainage: chunk.cursor + chunk.length * 0.5,
                radius: radius,
                label: label
            ) else { continue }
            fill(&assembly, chunk)
            composer.append(assembly)
        }
    }

    private static func appendBridgePieces(
        to assembly: inout AssemblyAccumulator,
        route: SceneChainageRoute,
        detailLevel: Int,
        landmark: SceneCorridorLandmark,
        frame: SceneRouteFrame,
        cursor: Double,
        length: Double
    ) {
        let span = max(length, 0.5)
        assembly.addAt("river-surface", routeFrame: frame, verticalM: -3.55,
                       size: SceneVector3(24, 0.36, span + 0.12), material: .riverWater)
        assembly.addAt("deck-slab", routeFrame: frame, verticalM: -0.62,
                       size: SceneVector3(5.5, 0.22, span + 0.04), material: .concrete)
        for side in [-1.0, 1.0] {
            assembly.addAt("main-girder-\(Int(side))", routeFrame: frame,
                           lateralM: side * 1.55, verticalM: -0.98,
                           size: SceneVector3(0.36, 0.58, span), material: .darkSteel)
            assembly.addAt("parapet-\(Int(side))", routeFrame: frame,
                           lateralM: side * 2.42, verticalM: 0.52,
                           size: SceneVector3(0.22, 1.02, span), material: .concrete)
            if detailLevel >= 1 {
                assembly.addAt("parapet-rail-\(Int(side))", routeFrame: frame,
                               lateralM: side * 2.42, verticalM: 1.08,
                               size: SceneVector3(0.08, 0.08, span), material: .galvanizedSteel,
                               minimumLOD: .medium)
            }
        }
        var pier = landmark.startChainageM
        while pier <= landmark.endChainageM + 1e-6 {
            if pier >= cursor - 1e-6, pier < cursor + length - 1e-4,
               let pierFrame = route.frame(at: pier) {
                assembly.addAt("pier-column-\(Int(pier.rounded()))", routeFrame: pierFrame,
                               verticalM: -2.15, size: SceneVector3(0.72, 2.85, 0.72), material: .concrete)
                assembly.addAt("pier-footing-\(Int(pier.rounded()))", routeFrame: pierFrame,
                               verticalM: -3.42, size: SceneVector3(1.7, 0.28, 1.45), material: .concrete)
                if detailLevel >= 2 {
                    assembly.addAt("pier-cap-\(Int(pier.rounded()))", routeFrame: pierFrame,
                                   verticalM: -0.78, size: SceneVector3(4.4, 0.18, 0.72),
                                   material: .darkSteel, minimumLOD: .high)
                }
            }
            pier += 32
        }
        for endChainage in [landmark.startChainageM, landmark.endChainageM] {
            guard endChainage >= cursor - 1e-6, endChainage <= cursor + length + 1e-6,
                  endChainage <= route.endChainageM,
                  let endFrame = route.frame(at: endChainage) else { continue }
            assembly.addAt("abutment-\(Int(endChainage.rounded()))", routeFrame: endFrame,
                           verticalM: -1.35, size: SceneVector3(6.2, 2.5, 1.05), material: .concrete)
        }
    }

    private static func appendCuttingPieces(
        to assembly: inout AssemblyAccumulator,
        detailLevel: Int,
        frame: SceneRouteFrame,
        length: Double
    ) {
        let span = max(length, 0.5)
        for side in [-1.0, 1.0] {
            assembly.addAt("retaining-wall-\(Int(side))", routeFrame: frame,
                           lateralM: side * 5.35, verticalM: 2.55,
                           size: SceneVector3(0.7, 5.7, span + 0.04), material: .concrete)
            assembly.addAt("wall-coping-\(Int(side))", routeFrame: frame,
                           lateralM: side * 5.35, verticalM: 5.48,
                           size: SceneVector3(0.95, 0.16, span), material: .grassSlope,
                           minimumLOD: .medium)
            if detailLevel >= 1 {
                assembly.addAt("drainage-\(Int(side))", routeFrame: frame,
                               lateralM: side * 3.15, verticalM: -0.36,
                               size: SceneVector3(0.42, 0.16, span), material: .concrete,
                               minimumLOD: .medium)
            }
        }
    }

    private static func appendEmbankmentPieces(
        to assembly: inout AssemblyAccumulator,
        detailLevel: Int,
        frame: SceneRouteFrame,
        length: Double
    ) {
        let span = max(length, 0.5)
        for side in [-1.0, 1.0] {
            assembly.addAt("grass-slope-\(Int(side))", routeFrame: frame,
                           lateralM: side * 6.4, verticalM: -1.85,
                           size: SceneVector3(7.4, 0.48, span + 0.04),
                           rotation: SceneVector3(0, 0, side > 0 ? -0.62 : 0.62),
                           material: .grassSlope)
            assembly.addAt("crest-shoulder-\(Int(side))", routeFrame: frame,
                           lateralM: side * 3.15, verticalM: -0.28,
                           size: SceneVector3(1.15, 0.18, span), material: .ballast,
                           minimumLOD: .medium)
            if detailLevel >= 1 {
                assembly.addAt("fence-post-\(Int(side))", routeFrame: frame,
                               lateralM: side * 2.85, verticalM: 0.55,
                               size: SceneVector3(0.08, 1.15, 0.08), material: .galvanizedSteel,
                               minimumLOD: .high)
            }
        }
    }

    private static func appendLevelCrossing(_ landmark: SceneCorridorLandmark, to composer: inout ScenePlanComposer) {
        let midpoint = (landmark.startChainageM + landmark.endChainageM) * 0.5
        guard landmark.overlaps(composer.buildStartM, composer.buildEndM),
              let frame = composer.route.frame(at: midpoint),
              var crossing = composer.localAccumulator(
                id: landmark.id,
                role: .levelCrossing,
                chainage: midpoint,
                radius: 14,
                label: "SYNTHETIC LEVEL CROSSING — STATIC PLACEHOLDER, NOT INTERLOCKED OR OPERATIONAL"
              ) else { return }
        // Approaches stop outside the rails. The center panel sits between them.
        // Barrier arms are raised: this drawing does not close a road or stop the train.
        for side in [-1.0, 1.0] {
            crossing.addAt("approach-road-\(Int(side))", routeFrame: frame,
                           lateralM: side * 8.2, verticalM: -0.16,
                           size: SceneVector3(10.4, 0.16, 7.2), material: .roadAsphalt)
            crossing.addAt("approach-verge-\(Int(side))", routeFrame: frame,
                           lateralM: side * 8.2, verticalM: -0.22,
                           size: SceneVector3(14.2, 0.08, 9.4), material: .grassSlope)
            crossing.addAt("outer-panel-\(Int(side))", routeFrame: frame,
                           lateralM: side * 1.55, verticalM: -0.05,
                           size: SceneVector3(1.15, 0.08, 6.4), material: .concrete)
            crossing.addAt("warning-post-\(Int(side))", routeFrame: frame,
                           lateralM: side * 3.35, verticalM: 1.15,
                           size: SceneVector3(0.16, 2.3, 0.16), material: .darkSteel)
            crossing.addAt("raised-barrier-arm-\(Int(side))", routeFrame: frame,
                           lateralM: side * 3.35, verticalM: 2.55,
                           size: SceneVector3(0.12, 2.4, 0.08), material: .vehicleRed)
            if composer.density.detailLevel >= 1 {
                crossing.addAt("barrier-stripe-\(Int(side))", routeFrame: frame,
                               lateralM: side * 3.35, verticalM: 3.15,
                               size: SceneVector3(0.13, 0.28, 0.09), material: .tactileAmber,
                               minimumLOD: .medium)
                crossing.addAt("crossbuck-\(Int(side))", routeFrame: frame,
                               lateralM: side * 3.55, verticalM: 2.05,
                               size: SceneVector3(0.08, 0.72, 0.72),
                               rotation: SceneVector3(0.6, 0, side * 0.5),
                               material: .buildingCool, minimumLOD: .medium)
            }
        }
        crossing.addAt("between-rail-panel", routeFrame: frame, verticalM: -0.04,
                       size: SceneVector3(0.9, 0.05, 6.2), material: .concrete)
        crossing.addAt("stop-line-left", routeFrame: frame, lateralM: -3.05, verticalM: -0.02,
                       size: SceneVector3(0.18, 0.02, 6.6), material: .roadPaint, minimumLOD: .medium)
        crossing.addAt("stop-line-right", routeFrame: frame, lateralM: 3.05, verticalM: -0.02,
                       size: SceneVector3(0.18, 0.02, 6.6), material: .roadPaint, minimumLOD: .medium)
        _ = frame
        composer.append(crossing)
    }

    private static func randomUnit(seed: UInt64) -> Double {
        var value = seed &+ 0x9E3779B97F4A7C15
        value = (value ^ (value >> 30)) &* 0xBF58476D1CE4E5B9
        value = (value ^ (value >> 27)) &* 0x94D049BB133111EB
        value ^= value >> 31
        return Double(value >> 11) / Double(1 << 53)
    }
}
