import RailwayAudioEnhancements
import RealityKit
import RailwayRendering
import RailwaySceneFidelity
import RailwayVehicleHighFidelity
import RailwayVehicleCab
import SwiftUI
import UIKit
import simd
import TrafficSimulation

/// Procedural game scene with fictional data; it is not a photoreal or real-railway simulation.
struct RealityTrackView: View {
    let route: RailwayRouteProfile
    let positionM: Double
    let speedKmh: Double
    let brakePipePressureKPa: Double
    let accelerationMps2: Double
    let simulationTime: Double
    let weather: WeatherCondition
    let trafficScenario: TrafficScenario?
    let trafficSnapshot: TrafficSnapshot?
    let routeVariant: RegionalRouteVariant
    let travelDirection: RegionalTravelDirection
    let controls: TrainControls
    let vehicleCabIndicatorState: VehicleCabIndicatorState
    let vehicleMaximumSpeedKmh: Double
    let environmentSelection: EnvironmentQualitySelection
    var vehicleCarCount: Int = 4
    var cabDesk: FictionalCabDesk = FictionalCabAndSoundCatalog.fieldChopper
    let stationModelPlacements: [RailwayGeneratedStationPlacement]
    let nextStopName: String
    let distanceToNextStopM: Double

    var body: some View {
        ZStack {
            LinearGradient(
                colors: weather == .dry
                    ? [Color(red: 0.14, green: 0.31, blue: 0.42), Color(red: 0.65, green: 0.56, blue: 0.43)]
                    : [Color(red: 0.12, green: 0.22, blue: 0.29), Color(red: 0.42, green: 0.46, blue: 0.46)],
                startPoint: .top,
                endPoint: .bottom
            )
            RailwayARViewRepresentable(
                route: route,
                positionM: positionM,
                speedKmh: speedKmh,
                brakePipePressureKPa: brakePipePressureKPa,
                accelerationMps2: accelerationMps2,
                simulationTime: simulationTime,
                trafficScenario: trafficScenario,
                trafficSnapshot: trafficSnapshot,
                routeVariant: routeVariant,
                travelDirection: travelDirection,
                controls: controls,
                vehicleCabIndicatorState: vehicleCabIndicatorState,
                vehicleMaximumSpeedKmh: vehicleMaximumSpeedKmh,
                environmentSelection: environmentSelection,
                vehicleCarCount: vehicleCarCount,
                cabDesk: cabDesk,
                stationModelPlacements: stationModelPlacements
            )
                .accessibilityHidden(true)
            let visibilityLoss = max(0, 1 - environmentSelection.environment.visibilityM / 20_000)
            let fogOpacity = min(0.34, max(0, environmentSelection.environment.fogDensity * 0.24 + visibilityLoss * 0.12))
            if fogOpacity > 0 {
                Color(red: 0.72, green: 0.77, blue: 0.78)
                    .opacity(fogOpacity)
                    .allowsHitTesting(false)
            }
            if weather == .rain || weather == .heavyRain {
                Color(red: 0.18, green: 0.29, blue: 0.38)
                    .opacity(weather == .heavyRain ? 0.22 : 0.12)
                    .blendMode(.multiply)
                    .allowsHitTesting(false)
            } else if weather == .snow {
                Color(red: 0.78, green: 0.82, blue: 0.84).opacity(0.08).blendMode(.screen).allowsHitTesting(false)
            } else if weather == .fog {
                Color(red: 0.70, green: 0.74, blue: 0.76).opacity(0.16).allowsHitTesting(false)
            }
            LinearGradient(colors: [.clear, .black.opacity(0.24)], startPoint: .center, endPoint: .bottom)
                .allowsHitTesting(false)
        }
        .overlay(alignment: .topTrailing) {
            HStack(spacing: 5) {
                Image(systemName: "location.fill")
                Text("次停車 \(nextStopName) · \(Int(distanceToNextStopM.rounded())) m")
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .font(.system(size: 10, weight: .black, design: .rounded).monospacedDigit())
            .foregroundStyle(.white)
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(.black.opacity(0.38), in: Capsule())
            .padding(8)
        }
        .overlay(alignment: .bottomTrailing) {
            if speedKmh > 0.5 {
                HStack(spacing: 4) {
                    Image(systemName: "speedometer")
                    Text(String(format: "%.0f km/h", speedKmh))
                }
                .font(.system(size: 9, weight: .bold, design: .rounded).monospacedDigit())
                .foregroundStyle(.white.opacity(0.86))
                .padding(8)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
    }
}

@MainActor
private struct RailwayARViewRepresentable: UIViewRepresentable {
    let route: RailwayRouteProfile
    let positionM: Double
    let speedKmh: Double
    let brakePipePressureKPa: Double
    let accelerationMps2: Double
    let simulationTime: Double
    let trafficScenario: TrafficScenario?
    let trafficSnapshot: TrafficSnapshot?
    let routeVariant: RegionalRouteVariant
    let travelDirection: RegionalTravelDirection
    let controls: TrainControls
    let vehicleCabIndicatorState: VehicleCabIndicatorState
    let vehicleMaximumSpeedKmh: Double
    let environmentSelection: EnvironmentQualitySelection
    let vehicleCarCount: Int
    let cabDesk: FictionalCabDesk
    let stationModelPlacements: [RailwayGeneratedStationPlacement]

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> ARView {
        let view = ARView(frame: .zero, cameraMode: .nonAR, automaticallyConfigureSession: false)
        view.backgroundColor = RailwaySkyPalette.color(for: environmentSelection)
        context.coordinator.lastSkySelection = environmentSelection
        context.coordinator.scene.prepare(
            route: route, quality: environmentSelection.renderQuality,
            trafficScenario: trafficScenario, routeVariant: routeVariant,
            travelDirection: travelDirection, vehicleCarCount: vehicleCarCount, cabDesk: cabDesk,
            stationModelPlacements: stationModelPlacements
        )
        view.scene.addAnchor(context.coordinator.scene.root)
        context.coordinator.scene.update(
            route: route, positionM: positionM, speedKmh: speedKmh,
            brakePipePressureKPa: brakePipePressureKPa,
            accelerationMps2: accelerationMps2, simulationTime: simulationTime,
            trafficScenario: trafficScenario, trafficSnapshot: trafficSnapshot,
            routeVariant: routeVariant, travelDirection: travelDirection,
            controls: controls, vehicleCabIndicatorState: vehicleCabIndicatorState,
            vehicleMaximumSpeedKmh: vehicleMaximumSpeedKmh,
            environmentSelection: environmentSelection, vehicleCarCount: vehicleCarCount,
            cabDesk: cabDesk, stationModelPlacements: stationModelPlacements
        )
        return view
    }

    func updateUIView(_ view: ARView, context: Context) {
        if context.coordinator.lastSkySelection != environmentSelection {
            view.backgroundColor = RailwaySkyPalette.color(for: environmentSelection)
            context.coordinator.lastSkySelection = environmentSelection
        }
        context.coordinator.scene.update(
            route: route, positionM: positionM, speedKmh: speedKmh,
            brakePipePressureKPa: brakePipePressureKPa,
            accelerationMps2: accelerationMps2, simulationTime: simulationTime,
            trafficScenario: trafficScenario, trafficSnapshot: trafficSnapshot,
            routeVariant: routeVariant, travelDirection: travelDirection,
            controls: controls, vehicleCabIndicatorState: vehicleCabIndicatorState,
            vehicleMaximumSpeedKmh: vehicleMaximumSpeedKmh,
            environmentSelection: environmentSelection, vehicleCarCount: vehicleCarCount,
            cabDesk: cabDesk, stationModelPlacements: stationModelPlacements
        )
    }

    @MainActor
    final class Coordinator {
        let scene = RailwaySceneWorld()
        var lastSkySelection: EnvironmentQualitySelection?
    }
}

@MainActor
private enum RailwaySkyPalette {
    static func color(for selection: EnvironmentQualitySelection) -> UIColor {
        let stops: [(hour: Double, color: SIMD3<Double>)] = [
            (0, SIMD3(0.025, 0.040, 0.085)),
            (5, SIMD3(0.075, 0.105, 0.190)),
            (6.5, SIMD3(0.43, 0.27, 0.32)),
            (8, SIMD3(0.34, 0.58, 0.76)),
            (12, SIMD3(0.47, 0.72, 0.87)),
            (17, SIMD3(0.86, 0.48, 0.31)),
            (19, SIMD3(0.34, 0.23, 0.37)),
            (21, SIMD3(0.035, 0.055, 0.115)),
            (24, SIMD3(0.025, 0.040, 0.085))
        ]
        func mix(_ start: SIMD3<Double>, _ end: SIMD3<Double>, _ amount: Double) -> SIMD3<Double> {
            SIMD3(
                start.x + (end.x - start.x) * amount,
                start.y + (end.y - start.y) * amount,
                start.z + (end.z - start.z) * amount
            )
        }

        let hour = selection.timeOfDayHours
        var lower = stops[0]
        var upper = stops[1]
        for index in 0..<(stops.count - 1) where hour >= stops[index].hour && hour <= stops[index + 1].hour {
            lower = stops[index]
            upper = stops[index + 1]
            break
        }
        let linear = min(max((hour - lower.hour) / (upper.hour - lower.hour), 0), 1)
        let eased = linear * linear * (3 - 2 * linear)
        var sky = mix(lower.color, upper.color, eased)

        let conditions = selection.environment
        let visibilityHaze = 1 - min(max(conditions.visibilityM / 20_000, 0), 1)
        let haze = min(max(conditions.fogDensity * 0.58 + visibilityHaze * 0.32, 0), 0.78)
        sky = mix(sky, SIMD3(0.56, 0.63, 0.68), haze)
        switch conditions.precipitation {
        case .none:
            break
        case .rain:
            sky = mix(sky, SIMD3(0.12, 0.18, 0.25), 0.16)
        case .snow:
            sky = mix(sky, SIMD3(0.72, 0.78, 0.84), 0.14)
        }

        return UIColor(
            red: CGFloat(min(max(sky.x, 0), 1)),
            green: CGFloat(min(max(sky.y, 0), 1)),
            blue: CGFloat(min(max(sky.z, 0), 1)),
            alpha: 1
        )
    }
}

/// Cylinder mesh built with a MeshDescriptor for iOS 17, where
/// `MeshResource.generateCylinder(height:radius:)` is unavailable.
/// Matches generateCylinder's placement: height along the Y axis, centered at the origin.
private enum FallbackCylinderMesh {
    static func make(height: Float, radius: Float, radialSegments: Int = 24) -> MeshResource {
        let halfHeight = height / 2
        var positions: [SIMD3<Float>] = []
        var normals: [SIMD3<Float>] = []
        var indices: [UInt32] = []

        // Side wall with smooth radial normals.
        for step in 0...radialSegments {
            let theta = Float(step) / Float(radialSegments) * 2 * .pi
            let direction = SIMD3<Float>(cos(theta), 0, sin(theta))
            positions.append(SIMD3<Float>(direction.x * radius, -halfHeight, direction.z * radius))
            normals.append(direction)
            positions.append(SIMD3<Float>(direction.x * radius, halfHeight, direction.z * radius))
            normals.append(direction)
        }
        for step in 0..<radialSegments {
            let bottom0 = UInt32(step * 2)
            let top0 = bottom0 + 1
            let bottom1 = bottom0 + 2
            let top1 = bottom0 + 3
            indices.append(contentsOf: [bottom0, top0, bottom1, top0, top1, bottom1])
        }

        // End caps with flat normals: one center vertex plus a dedicated ring each.
        for (sign, y) in [(Float(1), halfHeight), (Float(-1), -halfHeight)] {
            let centerIndex = UInt32(positions.count)
            positions.append(SIMD3<Float>(0, y, 0))
            normals.append(SIMD3<Float>(0, sign, 0))
            let ringStart = UInt32(positions.count)
            for step in 0...radialSegments {
                let theta = Float(step) / Float(radialSegments) * 2 * .pi
                positions.append(SIMD3<Float>(radius * cos(theta), y, radius * sin(theta)))
                normals.append(SIMD3<Float>(0, sign, 0))
            }
            for step in 0..<radialSegments {
                let a = ringStart + UInt32(step)
                let b = a + 1
                if sign > 0 {
                    indices.append(contentsOf: [centerIndex, b, a])
                } else {
                    indices.append(contentsOf: [centerIndex, a, b])
                }
            }
        }

        var descriptor = MeshDescriptor(name: "fallback-cylinder")
        descriptor.positions = MeshBuffers.Positions(positions)
        descriptor.normals = MeshBuffers.Normals(normals)
        descriptor.primitives = .triangles(indices)
        // The descriptor is built entirely from the values above, so generation cannot fail.
        return try! MeshResource.generate(from: [descriptor])
    }
}

@MainActor
private final class RailwaySceneWorld: RenderingStateApplying {
    private var stationModelPlacements: [RailwayGeneratedStationPlacement] = []
    private var importedStationEntity: Entity?
    private var importedStationKey: String?
    private var generatedStaticAssetRoots: [Entity] = []

    private struct SurfaceMaterialTarget {
        let entity: ModelEntity
        let baseColor: UIColor
        let metallic: Float
        let roughness: Float
    }

    let root = AnchorEntity(world: SIMD3<Float>(0, 0, 0))
    private var world = Entity()
    private var camera = PerspectiveCamera()
    private var sunlight = DirectionalLight()
    private var fillLight = PointLight()
    private lazy var renderingCoordinator = RailwayRenderingCoordinator(applier: self)
    private var didBuild = false
    private var routeSignature = ""
    private var samples: [RouteSample] = []
    private var trafficSceneRoute: SceneChainageRoute?
    private var trafficActorAdapter = RailwayTrafficActorRealityKitAdapter()
    private var previousTrafficSnapshot: TrafficSnapshot?
    private var roadCarEntities: [String: Entity] = [:]
    private var platformPeople: [String: Entity] = [:]
    private var aiTrainEntities: [String: Entity] = [:]
    private var vehicleModels: [RailwayVehicleModel] = []
    private var cabModel: RailwayVehicleModel?
    private var highFidelityLeadVehicle: RailwayVehicleHighFidelityModel?
    private var lastHighFidelityUpdateTime: Double?
    private var wheelBaseOrientations: [(entity: Entity, orientation: simd_quatf)] = []
    private var speedNeedle: ModelEntity?
    private var limitNeedle: ModelEntity?
    private var renderQualitySettings = RenderQualityResolver.resolve(profile: .balanced, thermalCondition: .nominal)
    private var precipitationEntities: [ModelEntity] = []
    private var precipitationKind: RenderingWeather?
    private var currentSample = RouteSample(distanceM: 0, x: 0, z: 0, heading: 0, bankRadians: 0)
    private var currentSimulationTime = 0.0
    private var previousRenderTime: Double?
    private var cameraWorldPosition = SIMD3<Float>(0, 0, 0)
    private var windVelocity = SIMD3<Float>(0, 0, 0)
    private var surfaceMaterialTargets: [SurfaceMaterialTarget] = []
    private var lastSurfaceMaterialKey: String?
    private var sceneFidelityRoute: SceneChainageRoute?
    private var sceneFidelityAdapter = RailwayRealityKitSceneAdapter()
    private var sceneFidelityDensity = SceneDensityControls.preset(.balanced)
    private var currentCabDesk = FictionalCabAndSoundCatalog.fieldChopper
    private var lastSceneFidelityBuildChainage = Double.nan

    private let ballastMaterial = RailwaySceneWorld.pbr(UIColor(red: 0.25, green: 0.26, blue: 0.25, alpha: 1), roughness: 0.96)
    private let sleeperMaterial = RailwaySceneWorld.pbr(UIColor(red: 0.34, green: 0.27, blue: 0.19, alpha: 1), roughness: 0.88)
    private let railMaterial = RailwaySceneWorld.pbr(UIColor(red: 0.48, green: 0.54, blue: 0.55, alpha: 1), metallic: 0.82, roughness: 0.27)
    private let concreteMaterial = RailwaySceneWorld.pbr(UIColor(red: 0.49, green: 0.51, blue: 0.50, alpha: 1), roughness: 0.87)
    private let poleMaterial = RailwaySceneWorld.pbr(UIColor(red: 0.34, green: 0.37, blue: 0.36, alpha: 1), metallic: 0.62, roughness: 0.42)
    private let wireMaterial = RailwaySceneWorld.pbr(UIColor(red: 0.68, green: 0.66, blue: 0.57, alpha: 1), metallic: 0.84, roughness: 0.24)
    private let roadMaterial = RailwaySceneWorld.pbr(UIColor(red: 0.17, green: 0.18, blue: 0.18, alpha: 1), roughness: 0.78)
    private let glassMaterial = RailwaySceneWorld.pbr(UIColor(red: 0.12, green: 0.26, blue: 0.31, alpha: 1), metallic: 0.18, roughness: 0.20)
    private let roofMaterials = [
        RailwaySceneWorld.pbr(UIColor(red: 0.28, green: 0.23, blue: 0.20, alpha: 1), roughness: 0.84),
        RailwaySceneWorld.pbr(UIColor(red: 0.34, green: 0.30, blue: 0.25, alpha: 1), roughness: 0.82),
        RailwaySceneWorld.pbr(UIColor(red: 0.22, green: 0.26, blue: 0.28, alpha: 1), metallic: 0.12, roughness: 0.71)
    ]
    private let buildingMaterials = [
        RailwaySceneWorld.pbr(UIColor(red: 0.68, green: 0.62, blue: 0.52, alpha: 1), roughness: 0.89),
        RailwaySceneWorld.pbr(UIColor(red: 0.54, green: 0.60, blue: 0.59, alpha: 1), roughness: 0.86),
        RailwaySceneWorld.pbr(UIColor(red: 0.67, green: 0.57, blue: 0.49, alpha: 1), roughness: 0.91),
        RailwaySceneWorld.pbr(UIColor(red: 0.58, green: 0.57, blue: 0.53, alpha: 1), roughness: 0.88),
        RailwaySceneWorld.pbr(UIColor(red: 0.57, green: 0.63, blue: 0.65, alpha: 1), metallic: 0.06, roughness: 0.7)
    ]
    private let foliageMaterials = [
        RailwaySceneWorld.pbr(UIColor(red: 0.18, green: 0.31, blue: 0.20, alpha: 1), roughness: 0.98),
        RailwaySceneWorld.pbr(UIColor(red: 0.28, green: 0.36, blue: 0.21, alpha: 1), roughness: 0.98),
        RailwaySceneWorld.pbr(UIColor(red: 0.22, green: 0.32, blue: 0.27, alpha: 1), roughness: 0.98)
    ]

    func prepare(
        route: RailwayRouteProfile,
        quality: EnvironmentRenderQuality,
        trafficScenario: TrafficScenario?,
        routeVariant: RegionalRouteVariant,
        travelDirection: RegionalTravelDirection,
        vehicleCarCount: Int,
        cabDesk: FictionalCabDesk,
        stationModelPlacements: [RailwayGeneratedStationPlacement]
    ) {
        rebuild(
            route: route, quality: quality, trafficScenario: trafficScenario,
            routeVariant: routeVariant, travelDirection: travelDirection, vehicleCarCount: vehicleCarCount,
            cabDesk: cabDesk, stationModelPlacements: stationModelPlacements
        )
    }

    private func rebuild(
        route: RailwayRouteProfile,
        quality: EnvironmentRenderQuality,
        trafficScenario: TrafficScenario?,
        routeVariant: RegionalRouteVariant = .throughBranch,
        travelDirection: RegionalTravelDirection = .up,
        vehicleCarCount: Int = 4,
        cabDesk: FictionalCabDesk = FictionalCabAndSoundCatalog.fieldChopper,
        stationModelPlacements: [RailwayGeneratedStationPlacement]
    ) {
        for child in Array(root.children) { child.removeFromParent() }
        surfaceMaterialTargets.removeAll(keepingCapacity: true)
        lastSurfaceMaterialKey = nil
        world = Entity()
        camera = PerspectiveCamera()
        trafficActorAdapter = RailwayTrafficActorRealityKitAdapter()
        previousTrafficSnapshot = nil
        roadCarEntities.removeAll()
        platformPeople.removeAll()
        aiTrainEntities.removeAll()
        vehicleModels.removeAll()
        highFidelityLeadVehicle = nil
        generatedLeadVehicleRoot = nil
        importedStationEntity = nil
        importedStationKey = nil
        generatedStaticAssetRoots.removeAll(keepingCapacity: true)
        self.stationModelPlacements = stationModelPlacements
        lastHighFidelityUpdateTime = nil
        wheelBaseOrientations.removeAll()
        cabModel = nil
        precipitationEntities.removeAll()
        precipitationKind = nil
        speedNeedle = nil
        limitNeedle = nil
        renderQualitySettings = RenderQualityResolver.resolve(profile: quality.profile, thermalCondition: .nominal)
        let safeCarCount = min(max(vehicleCarCount, 1), 12)
        currentCabDesk = cabDesk
        let stationSignature = stationModelPlacements.map { "\($0.stationId):\($0.chainageM):\($0.asset.rawValue)" }.joined(separator: ",")
        routeSignature = "\(route.lineName)|\(route.distanceM)|\(quality.rawValue)|\(routeVariant.rawValue)|\(travelDirection.rawValue)|cars:\(safeCarCount)|cab:\(cabDesk.family.rawValue)|stations:\(stationSignature)"
        didBuild = true
        let profileInterval: Double
        switch quality {
        case .low: profileInterval = 110
        case .medium: profileInterval = 60
        case .high: profileInterval = 30
        }
        let sampleBudget = max(300, min(1_600, renderQualitySettings.sceneryInstanceLimit))
        let sampleInterval = max(profileInterval, route.distanceM / Double(sampleBudget))
        samples = makeSamples(route: route, interval: sampleInterval)
        trafficSceneRoute = makeSceneFidelityRoute()
        sceneFidelityRoute = trafficSceneRoute
        sceneFidelityAdapter = RailwayRealityKitSceneAdapter()
        sceneFidelityDensity = quality == .high ? .preset(.highDetail) : .preset(.balanced)
        lastSceneFidelityBuildChainage = Double.nan

        root.addChild(world)
        world.addChild(trafficActorAdapter.root)
        root.addChild(camera)
        camera.camera.fieldOfViewInDegrees = 66

        sunlight = DirectionalLight()
        sunlight.light.intensity = 18_000
        sunlight.light.color = UIColor(red: 1.0, green: 0.91, blue: 0.77, alpha: 1)
        sunlight.orientation = simd_quatf(angle: -.pi / 3.6, axis: SIMD3<Float>(-0.6, 0.8, -0.3))
        root.addChild(sunlight)

        fillLight = PointLight()
        fillLight.light.intensity = 1_200
        fillLight.light.attenuationRadius = 150
        fillLight.light.color = UIColor(red: 0.70, green: 0.79, blue: 0.88, alpha: 1)
        fillLight.position = SIMD3<Float>(0, 16, -30)
        root.addChild(fillLight)

        if quality == .high, sceneFidelityRoute != nil {
            buildSceneFidelityRegion(route: route, chainageM: 0, useLiveCamera: false)
        } else {
            sceneFidelityRoute = nil
            buildTrack(route: route, routeVariant: routeVariant, travelDirection: travelDirection)
            buildCatenary(route: route)
            buildSuburb(route: route)
            buildRoadTraffic(route: route, scenario: trafficScenario, routeVariant: routeVariant, travelDirection: travelDirection)
            buildFictionalCorridorLandmarks(route: route, quality: quality)
            buildDestinationPlatform(route: route)
        }
        buildLevelCrossings(route: route)
        buildConsist(carCount: safeCarCount, useHighFidelityLead: quality == .high)
        buildGenerated3DAssets(route: route)
    }

    func update(
        route: RailwayRouteProfile,
        positionM: Double,
        speedKmh: Double,
        brakePipePressureKPa: Double,
        accelerationMps2: Double,
        simulationTime: Double,
        trafficScenario: TrafficScenario?,
        trafficSnapshot: TrafficSnapshot?,
        routeVariant: RegionalRouteVariant,
        travelDirection: RegionalTravelDirection,
        controls: TrainControls,
        vehicleCabIndicatorState: VehicleCabIndicatorState,
        vehicleMaximumSpeedKmh: Double,
        environmentSelection: EnvironmentQualitySelection,
        vehicleCarCount: Int,
        cabDesk: FictionalCabDesk,
        stationModelPlacements: [RailwayGeneratedStationPlacement]
    ) {
        let safeCarCount = min(max(vehicleCarCount, 1), 12)
        let stationSignature = stationModelPlacements.map { "\($0.stationId):\($0.chainageM):\($0.asset.rawValue)" }.joined(separator: ",")
        let signature = "\(route.lineName)|\(route.distanceM)|\(environmentSelection.renderQuality.rawValue)|\(routeVariant.rawValue)|\(travelDirection.rawValue)|cars:\(safeCarCount)|cab:\(cabDesk.family.rawValue)|stations:\(stationSignature)"
        if !didBuild || routeSignature != signature {
            rebuild(
                route: route, quality: environmentSelection.renderQuality,
                trafficScenario: trafficScenario, routeVariant: routeVariant,
                travelDirection: travelDirection, vehicleCarCount: safeCarCount,
                cabDesk: cabDesk, stationModelPlacements: stationModelPlacements
            )
        }
        guard !samples.isEmpty else { return }
        updateGeneratedStationModel(positionM: positionM)
        let centerSample = sample(at: positionM)
        let playerLateral: Float = travelDirection == .up ? -2.1 : 2.1
        let sample = RouteSample(
            distanceM: centerSample.distanceM,
            x: centerSample.x + playerLateral * cos(centerSample.heading),
            z: centerSample.z - playerLateral * sin(centerSample.heading),
            heading: centerSample.heading,
            bankRadians: centerSample.bankRadians
        )
        currentSample = sample
        currentSimulationTime = simulationTime
        for (index, model) in vehicleModels.enumerated() {
            let consistIndex = index + (highFidelityLeadVehicle == nil ? 0 : 1)
            let chainage = max(0, positionM - 9.75 - Double(consistIndex) * 19.5)
            let carSample = sample(at: chainage)
            let carLateral = SIMD3<Float>(cos(carSample.heading), 0, sin(carSample.heading))
            let trackSide: Float = travelDirection == .up ? -2.1 : 2.1
            model.root.position = SIMD3<Float>(
                carSample.x + trackSide * carLateral.x, 0, carSample.z + trackSide * carLateral.z
            )
            // Vehicle meshes face local -Z; negative route yaw aligns that end with route-forward.
            model.root.orientation = simd_quatf(angle: -carSample.heading, axis: SIMD3<Float>(0, 1, 0)) *
                simd_quatf(angle: -carSample.bankRadians, axis: SIMD3<Float>(0, 0, 1))
        }
        if let model = highFidelityLeadVehicle {
            let carChainage = max(0, positionM - 9.75)
            let carSample = sample(at: carChainage)
            let frontBogieSample = sample(at: max(0, carChainage - 6.35))
            let rearBogieSample = sample(at: carChainage + 6.35)
            let carLateral = SIMD3<Float>(cos(carSample.heading), 0, sin(carSample.heading))
            let trackSide: Float = travelDirection == .up ? -2.1 : 2.1
            model.root.position = SIMD3<Float>(
                carSample.x + trackSide * carLateral.x, 0, carSample.z + trackSide * carLateral.z
            )
            model.root.orientation = simd_quatf(angle: -carSample.heading, axis: SIMD3<Float>(0, 1, 0)) *
                simd_quatf(angle: -carSample.bankRadians, axis: SIMD3<Float>(0, 0, 1))
            generatedLeadVehicleRoot?.position = model.root.position
            generatedLeadVehicleRoot?.orientation = model.root.orientation
            func relativeBogieYaw(_ heading: Double) -> Float {
                let delta = atan2(sin(heading - carSample.heading), cos(heading - carSample.heading))
                return Float(-delta)
            }
            model.animatedParts.setBogieYaw(
                frontRadians: relativeBogieYaw(frontBogieSample.heading),
                rearRadians: relativeBogieYaw(rearBogieSample.heading)
            )
            model.controls.setValue(Float(controls.throttleNotch), for: .masterController)
            model.controls.setValue(controls.emergencyBrake ? 8 : Float(controls.brakeNotch), for: .brakeLever)
            model.controls.setValue(controls.emergencyBrake ? 1 : 0, for: .emergencyBrake)
            model.controls.setValue(Float(environmentSelection.environment.headlightIntensity), for: .headlightSwitch)
            model.controls.setValue(environmentSelection.environment.wiperState == .off ? 0 : 1, for: .wiperSwitch)
            model.animatedParts.setTelemetry(
                speedKmh: speedKmh, brakePipePressureKPa: brakePipePressureKPa
            )
            model.animatedParts.setCabIndicatorState(vehicleCabIndicatorState)
            model.animatedParts.setHeadlightsEnabled(environmentSelection.environment.headlightIntensity > 0)
            let wiperMode: VehicleWiperMode
            switch environmentSelection.environment.wiperState {
            case .off: wiperMode = .off
            case .intermittent: wiperMode = .intermittent
            case .low: wiperMode = .low
            case .high: wiperMode = .high
            }
            model.animatedParts.setWiperState(wiperMode, simulationTimeSeconds: simulationTime)
            if let lastHighFidelityUpdateTime, simulationTime > lastHighFidelityUpdateTime,
               simulationTime - lastHighFidelityUpdateTime <= 0.5 {
                let delta = simulationTime - lastHighFidelityUpdateTime
                model.animatedParts.advanceWheels(distanceMeters: Float(max(0, speedKmh) / 3.6 * delta))
            }
            lastHighFidelityUpdateTime = simulationTime.isFinite ? simulationTime : nil
        }
        if let cabModel {
            cabModel.cabControls.setValue(Float(controls.throttleNotch), for: .masterController)
            cabModel.cabControls.setValue(Float(controls.brakeNotch) / 7, for: .brakeLever)
            cabModel.cabControls.setValue(1, for: .reverser)
            cabModel.cabControls.setValue(Float(environmentSelection.environment.headlightIntensity), for: .headlightSwitch)
            let wiperValue: Float
            switch environmentSelection.environment.wiperState {
            case .off: wiperValue = 0
            case .intermittent: wiperValue = 1
            case .low: wiperValue = 2
            case .high: wiperValue = 3
            }
            cabModel.cabControls.setValue(wiperValue, for: .wiperSwitch)
        }
        updateCabGauges(speedKmh: speedKmh, maximumSpeedKmh: vehicleMaximumSpeedKmh)
        updateWheels(speedKmh: speedKmh, simulationTime: simulationTime)
        renderingCoordinator.cameraController.viewMode = environmentSelection.cameraViewMode
        renderingCoordinator.qualityController = RenderQualityController(
            selectedProfile: environmentSelection.renderQuality.profile, thermalCondition: .nominal
        )
        let conditions = environmentSelection.environment
        let renderingWeather: RenderingWeather
        switch conditions.precipitation {
        case .rain: renderingWeather = .rain
        case .snow: renderingWeather = .snow
        case .none: renderingWeather = conditions.fogDensity >= 0.25 ? .fog : .dry
        }
        let curve = route.condition(at: positionM)
        let curveDirection: CurveDirection? = curve.curveRadiusM != nil
            ? ((curve.curveDirection ?? 1) < 0 ? .left : .right) : nil
        let motion = TrainMotionSample(
            simulationTimeSeconds: simulationTime, speedMetersPerSecond: speedKmh / 3.6,
            longitudinalAccelerationMetersPerSecondSquared: accelerationMps2,
            curveRadiusMeters: curve.curveRadiusM, curveDirection: curveDirection
        )
        let precipitation: Double
        if weather == .heavyRain {
            precipitation = 1
        } else if renderingWeather == .dry || renderingWeather == .fog {
            precipitation = 0
        } else {
            precipitation = 0.65
        }
        let environment = EnvironmentInput(
            timeOfDayHours: environmentSelection.timeOfDayHours, weather: renderingWeather,
            precipitationIntensity: precipitation, visibilityMeters: conditions.visibilityM
        )
        let deltaTime: Double
        if let previousRenderTime, simulationTime.isFinite, simulationTime > previousRenderTime,
           simulationTime - previousRenderTime <= 1 {
            deltaTime = simulationTime - previousRenderTime
        } else {
            deltaTime = 1.0 / 60.0
        }
        previousRenderTime = simulationTime.isFinite ? simulationTime : nil
        let radians = conditions.windDirectionDegrees * .pi / 180
        windVelocity = SIMD3<Float>(
            Float(sin(radians) * conditions.windSpeedMps), 0, Float(-cos(radians) * conditions.windSpeedMps)
        )
        renderingCoordinator.update(motion: motion, environment: environment, deltaTime: deltaTime)
        updateTrafficActors(
            route: route,
            scenario: trafficScenario,
            snapshot: trafficSnapshot,
            routeVariant: routeVariant,
            travelDirection: travelDirection,
            simulationTime: simulationTime
        )
        updateSceneFidelity(route: route, positionM: positionM)
    }

    func apply(camera pose: CameraPose, environment: EnvironmentRenderState, quality: RenderQualitySettings) {
        renderQualitySettings = quality
        updateSurfaceMaterials(wetness: environment.surfaceWetnessBlend, snowCoverage: environment.snowSurfaceCoverageBlend)
        sceneFidelityAdapter.updateSurfaceWeather(SceneSurfaceWeather(
            wetness: environment.surfaceWetnessBlend,
            snowCoverage: environment.snowSurfaceCoverageBlend
        ))
        let heading = currentSample.heading
        let right = SIMD3<Float>(cos(heading), 0, sin(heading))
        let forward = SIMD3<Float>(sin(heading), 0, -cos(heading))
        func worldPoint(_ point: RenderVector3) -> SIMD3<Float> {
            SIMD3<Float>(
                currentSample.x + right.x * Float(point.x) + forward.x * Float(point.z),
                Float(point.y),
                currentSample.z + right.z * Float(point.x) + forward.z * Float(point.z)
            )
        }
        let position = worldPoint(pose.position)
        let target = worldPoint(pose.target)
        camera.position = position
        camera.camera.fieldOfViewInDegrees = Float(min(max(pose.fieldOfViewDegrees, 20), 110))
        camera.look(at: target, from: position, relativeTo: nil)
        if abs(pose.rollRadians) > 0.0001 {
            camera.orientation = simd_mul(camera.orientation, simd_quatf(angle: Float(pose.rollRadians), axis: SIMD3<Float>(0, 0, 1)))
        }
        cameraWorldPosition = position

        let tint = environment.warmCoolTint
        sunlight.light.intensity = 18_000 * Float(environment.sunLightScale)
        sunlight.light.color = UIColor(
            red: CGFloat(min(max(tint.x, 0), 1.2)), green: CGFloat(min(max(tint.y, 0), 1.2)),
            blue: CGFloat(min(max(tint.z, 0), 1.2)), alpha: 1
        )
        fillLight.light.intensity = 1_200 * Float(environment.ambientLightScale * (1 - environment.fogStrength * 0.35))
        fillLight.light.color = UIColor(
            red: CGFloat(min(max(tint.x * 0.70, 0), 1)), green: CGFloat(min(max(tint.y * 0.79, 0), 1)),
            blue: CGFloat(min(max(tint.z * 0.88, 0), 1)), alpha: 1
        )
        let sceneVisibility = min(quality.visibleDistanceMeters, environment.visibilityMeters)
        fillLight.light.attenuationRadius = Float(min(max(sceneVisibility, 40), 2_000))

        let kind: RenderingWeather? = environment.rainVisualIntensity > 0 ? .rain
            : (environment.snowVisualIntensity > 0 ? .snow : nil)
        let intensity = kind == .rain ? environment.rainVisualIntensity : environment.snowVisualIntensity
        ensurePrecipitation(kind: kind, budget: quality.precipitationParticleBudget)
        updatePrecipitation(intensity: intensity, simulationTime: currentSimulationTime)
    }

    private func ensurePrecipitation(kind: RenderingWeather?, budget: Int) {
        let count = min(max(budget, 0), 96)
        guard precipitationKind != kind || precipitationEntities.count != count else { return }
        for entity in precipitationEntities { entity.removeFromParent() }
        precipitationEntities.removeAll(keepingCapacity: true)
        precipitationKind = kind
        guard let kind, count > 0 else { return }
        let material = Self.pbr(
            kind == .rain ? UIColor(red: 0.70, green: 0.82, blue: 0.91, alpha: 0.58)
                          : UIColor(red: 0.94, green: 0.97, blue: 1.0, alpha: 0.86),
            roughness: 0.3
        )
        for index in 0..<count {
            let size: SIMD3<Float> = kind == .rain
                ? SIMD3<Float>(0.012, 0.23, 0.012) : SIMD3<Float>(0.055, 0.055, 0.055)
            let particle = ModelEntity(mesh: .generateBox(size: size), materials: [material])
            particle.name = "visual-precipitation-\(index)"
            precipitationEntities.append(particle)
            root.addChild(particle)
        }
    }

    private func updatePrecipitation(intensity: Double, simulationTime: Double) {
        let activeCount = Int((Double(precipitationEntities.count) * min(max(intensity, 0), 1)).rounded(.up))
        let windDrift = windVelocity * 0.35
        for (index, particle) in precipitationEntities.enumerated() {
            particle.isEnabled = index < activeCount
            let seed = Float(index)
            let phase = Float(simulationTime * (precipitationKind == .rain ? 13 : 2.2)) + seed * 1.71
            let x = sin(seed * 12.9898) * 10 + windDrift.x * Float(simulationTime.truncatingRemainder(dividingBy: 3))
            let z = -6 - abs(cos(seed * 7.123)) * 36 + windDrift.z * Float(simulationTime.truncatingRemainder(dividingBy: 3))
            let fall = Float((Double(phase).truncatingRemainder(dividingBy: 18) + 18).truncatingRemainder(dividingBy: 18))
            particle.position = cameraWorldPosition + SIMD3<Float>(x, 8 - fall * 0.8, z)
        }
    }

    private func buildTrack(
        route: RailwayRouteProfile,
        routeVariant: RegionalRouteVariant,
        travelDirection: RegionalTravelDirection
    ) {
        let distance = Float(route.distanceM)
        addSurfaceBox(parent: world, name: "formation-ground", size: SIMD3<Float>(1_400, 0.38, distance + 100), position: SIMD3<Float>(0, -0.28, -distance / 2), color: UIColor(red: 0.24, green: 0.28, blue: 0.24, alpha: 1), roughness: 1)

        for index in samples.indices {
            let sample = samples[index]
            let yaw = simd_quatf(angle: sample.heading, axis: SIMD3<Float>(0, 1, 0))
            let trackOrientation = yaw * simd_quatf(angle: -sample.bankRadians, axis: SIMD3<Float>(0, 0, 1))
            let isMainlineSection = travelDirection == .up ? sample.distanceM < 60_000 : sample.distanceM >= 8_000
            let hasPassingTrack = routeVariant == .mainline || (routeVariant == .throughBranch && isMainlineSection)
            let trackOffsets: [Float] = hasPassingTrack ? [-2.1, 2.1] : [travelDirection == .up ? -2.1 : 2.1]
            let segmentLength: Float
            if index + 3 < samples.count {
                segmentLength = max(Float(samples[index + 3].distanceM - sample.distanceM), 8)
            } else if index + 1 < samples.count {
                segmentLength = max(Float(samples[index + 1].distanceM - sample.distanceM), 8)
            } else {
                segmentLength = 8
            }
            if index.isMultiple(of: 3) {
                for (trackIndex, lateral) in trackOffsets.enumerated() {
                    let centerX = sample.x + lateral * cos(sample.heading)
                    let centerZ = sample.z - lateral * sin(sample.heading)
                    addSurfaceBox(parent: world, name: "ballast-\(index)-\(trackIndex)", size: SIMD3<Float>(3.2, 0.15, segmentLength), position: SIMD3<Float>(centerX, -0.01, centerZ), color: UIColor(red: 0.25, green: 0.26, blue: 0.25, alpha: 1), roughness: 0.96, orientation: trackOrientation)
                    for side in [-1.0, 1.0] {
                        let railLateral = lateral + Float(side) * 0.72
                        let railX = sample.x + railLateral * cos(sample.heading)
                        let railZ = sample.z - railLateral * sin(sample.heading)
                        let railY = 0.24 - Float(side) * 0.72 * sin(sample.bankRadians)
                        addSurfaceBox(parent: world, name: "rail-\(index)-\(trackIndex)-\(Int(side))", size: SIMD3<Float>(0.12, 0.15, segmentLength), position: SIMD3<Float>(railX, railY, railZ), color: UIColor(red: 0.48, green: 0.54, blue: 0.55, alpha: 1), metallic: 0.82, roughness: 0.27, orientation: trackOrientation)
                    }
                }
            }
            for (trackIndex, lateral) in trackOffsets.enumerated() {
                let x = sample.x + lateral * cos(sample.heading)
                let z = sample.z - lateral * sin(sample.heading)
                addSurfaceBox(parent: world, name: "sleeper-\(index)-\(trackIndex)", size: SIMD3<Float>(2.55, 0.13, 0.26), position: SIMD3<Float>(x, 0.105, z), color: UIColor(red: 0.34, green: 0.27, blue: 0.19, alpha: 1), roughness: 0.88, orientation: trackOrientation)
            }
        }
    }

    private func buildCatenary(route: RailwayRouteProfile) {
        let supportBudget = max(40, renderQualitySettings.sceneryInstanceLimit / 8)
        let interval = max(120.0, route.distanceM / Double(supportBudget))
        var distance = 12.0
        var index = 0
        while distance < route.distanceM {
            let sample = sample(at: distance)
            let heading = sample.heading
            let yaw = simd_quatf(angle: heading, axis: SIMD3<Float>(0, 1, 0))
            let poleOffsets: [Float] = [-3.2, 7.4]
            for (poleIndex, lateral) in poleOffsets.enumerated() {
                let x = sample.x + lateral * cos(heading)
                let z = sample.z - lateral * sin(heading)
                addBox(parent: world, name: "catenary-mast-\(index)-\(poleIndex)", size: SIMD3<Float>(0.16, 5.6, 0.18), position: SIMD3<Float>(x, 2.7, z), material: poleMaterial, orientation: yaw)
            }
            addBox(parent: world, name: "double-track-crossbeam-\(index)", size: SIMD3<Float>(10.6, 0.10, 0.14), position: SIMD3<Float>(sample.x + 2.1 * cos(heading), 5.15, sample.z - 2.1 * sin(heading)), material: poleMaterial, orientation: yaw)
            for (trackIndex, trackOffset) in [0.0, 4.2].enumerated() {
                let offset = Float(trackOffset)
                let wireX = sample.x + offset * cos(heading)
                let wireZ = sample.z - offset * sin(heading)
                addBox(parent: world, name: "contact-wire-\(index)-\(trackIndex)", size: SIMD3<Float>(0.035, 0.035, Float(interval)), position: SIMD3<Float>(wireX, 4.95, wireZ - Float(interval) / 2), material: wireMaterial, orientation: yaw)
            }
            distance += interval
            index += 1
        }
    }

    private func buildSuburb(route: RailwayRouteProfile) {
        let sceneryMaterials = buildingMaterials
        let landmarks = fictionalCorridorLandmarks(for: route)
        var index = 0
        var foliageCount = 0
        let buildingLimit = max(1, renderQualitySettings.sceneryInstanceLimit / 6)
        let buildingStep = max(105, (route.distanceM - 114) / Double(buildingLimit))
        var distance = 34.0
        while distance < route.distanceM - 80 && index < buildingLimit {
            if corridorReserved(at: distance, landmarks: landmarks) {
                distance += buildingStep
                continue
            }
            let sample = sample(at: distance)
            let side = index.isMultiple(of: 2) ? 1.0 : -1.0
            let sign = Float(side)
            let lateral = 9.0 + Float((index * 13) % 4) * 1.7
            let shed = index.isMultiple(of: 4)
            let width = (shed ? 7.2 : 4.6) + Float((index * 7) % 4) * 0.75
            let depth = (shed ? 4.2 : 5.4) + Float((index * 5) % 4) * 0.8
            let height = (shed ? 2.6 : 3.6) + Float((index * 11) % 6) * 0.65
            let offset = sign * lateral
            let x = sample.x + offset * cos(sample.heading)
            let z = sample.z - offset * sin(sample.heading)
            let bodyMaterial = sceneryMaterials[index % sceneryMaterials.count]
            let building = addBox(parent: world, name: shed ? "fictional-shed-\(index)" : "fictional-home-\(index)", size: SIMD3<Float>(width, height, depth), position: SIMD3<Float>(x, height / 2, z), material: bodyMaterial)
            building.orientation = simd_quatf(angle: sample.heading, axis: SIMD3<Float>(0, 1, 0))

            if !index.isMultiple(of: 3) {
                let roof = addBox(parent: world, name: "roof-\(index)", size: SIMD3<Float>(width + 0.45, 0.24, depth + 0.35), position: SIMD3<Float>(x, height + 0.14, z), material: roofMaterials[index % roofMaterials.count], orientation: simd_quatf(angle: sample.heading, axis: SIMD3<Float>(0, 1, 0)))
                roof.orientation = roof.orientation * simd_quatf(angle: Float(index.isMultiple(of: 2) ? 0.04 : -0.04), axis: SIMD3<Float>(0, 0, 1))
            } else {
                let balconySample = sample(at: distance - Double(depth * 0.52))
                let balconyPoint = routeOffsetPoint(balconySample, lateral: offset)
                let balcony = addBox(parent: world, name: "balcony-\(index)", size: SIMD3<Float>(width + 0.35, 0.12, 0.35), position: SIMD3<Float>(balconyPoint.x, height * 0.56, balconyPoint.z), material: concreteMaterial)
                balcony.orientation = simd_quatf(angle: sample.heading, axis: SIMD3<Float>(0, 1, 0))
            }

            let facadeLateral = offset - sign * (width / 2 + 0.035)
            for window in 0..<2 {
                let windowSample = sample(at: distance + Double((Float(window) - 0.5) * depth * 0.42))
                let windowPoint = routeOffsetPoint(windowSample, lateral: facadeLateral)
                let pane = addBox(parent: world, name: "window-\(index)-\(window)", size: SIMD3<Float>(0.07, 0.72, 0.78), position: SIMD3<Float>(windowPoint.x, min(height * 0.72, 2.45), windowPoint.z), material: glassMaterial)
                pane.orientation = simd_quatf(angle: sample.heading, axis: SIMD3<Float>(0, 1, 0))
            }
            let doorPoint = routeOffsetPoint(sample, lateral: facadeLateral)
            let door = addBox(parent: world, name: "door-\(index)", size: SIMD3<Float>(0.07, 1.8, 0.78), position: SIMD3<Float>(doorPoint.x, 0.95, doorPoint.z), material: roofMaterials[(index + 1) % roofMaterials.count])
            door.orientation = simd_quatf(angle: sample.heading, axis: SIMD3<Float>(0, 1, 0))

            if index.isMultiple(of: 2), foliageCount < renderQualitySettings.foliageInstanceLimit {
                let treeSample = sample(at: distance + 5)
                let treePoint = routeOffsetPoint(treeSample, lateral: offset + sign * width * 0.65)
                addTree(parent: world, name: "tree-\(index)", x: treePoint.x, z: treePoint.z, height: 3.1 + Float(index % 4) * 0.35, material: foliageMaterials[index % foliageMaterials.count])
                foliageCount += 1
            }
            if index.isMultiple(of: 5) {
                let poleSample = sample(at: distance + 7)
                let polePoint = routeOffsetPoint(poleSample, lateral: offset + sign * 4.2)
                addBox(parent: world, name: "utility-pole-\(index)", size: SIMD3<Float>(0.13, 5.2, 0.13), position: SIMD3<Float>(polePoint.x, 2.55, polePoint.z), material: poleMaterial)
            }
            index += 1
            distance += buildingStep
        }
    }

    private func buildLevelCrossings(route: RailwayRouteProfile) {
        for (index, distance) in [route.distanceM * 0.31, route.distanceM * 0.69].enumerated() {
            let sample = sample(at: distance)
            let roadYaw = simd_quatf(angle: sample.heading, axis: SIMD3<Float>(0, 1, 0))
            addBox(parent: world, name: "crossing-road-\(index)", size: SIMD3<Float>(18, 0.1, 5.5), position: SIMD3<Float>(sample.x, 0.19, sample.z), material: roadMaterial, orientation: roadYaw)
            for side in [-1.0, 1.0] {
                let lateral = Float(side) * 2.4
                let x = sample.x + lateral * cos(sample.heading)
                let z = sample.z - lateral * sin(sample.heading)
                addBox(parent: world, name: "crossing-warning-post-\(index)-\(Int(side))", size: SIMD3<Float>(0.14, 1.4, 0.14), position: SIMD3<Float>(x, 0.9, z), material: roofMaterials[0])
                let arm = addBox(parent: world, name: "crossing-arm-\(index)-\(Int(side))", size: SIMD3<Float>(0.12, 0.1, 3.0), position: SIMD3<Float>(x, 1.48, z), material: railMaterial)
                arm.orientation = simd_quatf(angle: sample.heading, axis: SIMD3<Float>(0, 1, 0))
            }
        }
    }

    private func buildDestinationPlatform(route: RailwayRouteProfile) {
        let sample = sample(at: route.stopMarkerM)
        for side in [-1.0, 1.0] {
            let lateral = Float(side) * 1.9
            let x = sample.x + lateral * cos(sample.heading)
            let z = sample.z - lateral * sin(sample.heading)
            let yaw = simd_quatf(angle: sample.heading, axis: SIMD3<Float>(0, 1, 0))
            addBox(parent: world, name: "arrival-platform-\(Int(side))", size: SIMD3<Float>(2.0, 0.48, 115), position: SIMD3<Float>(x, 0.24, z), material: concreteMaterial, orientation: yaw)
            addBox(parent: world, name: "tactile-strip-\(Int(side))", size: SIMD3<Float>(0.22, 0.035, 115), position: SIMD3<Float>(x - Float(side) * 0.83 * cos(sample.heading), 0.50, z + Float(side) * 0.83 * sin(sample.heading)), material: roofMaterials[0], orientation: yaw)
        }
        let signSample = sample(at: max(route.stopMarkerM - 42, 0))
        let signYaw = simd_quatf(angle: signSample.heading, axis: SIMD3<Float>(0, 1, 0))
        addBox(parent: world, name: "fictional-station-sign-post", size: SIMD3<Float>(0.12, 2.8, 0.12), position: SIMD3<Float>(signSample.x + 3.4, 1.4, signSample.z), material: poleMaterial)
        addBox(parent: world, name: "fictional-station-sign", size: SIMD3<Float>(2.4, 0.75, 0.14), position: SIMD3<Float>(signSample.x + 3.4, 2.6, signSample.z), material: glassMaterial, orientation: signYaw)
    }

    private func buildRoadTraffic(
        route: RailwayRouteProfile,
        scenario: TrafficScenario?,
        routeVariant: RegionalRouteVariant,
        travelDirection: RegionalTravelDirection
    ) {
        guard let scenario else { return }
        let landmarks = fictionalCorridorLandmarks(for: route)
        let paths = Dictionary(scenario.routePaths.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let roadSegmentBudget = max(30, renderQualitySettings.sceneryInstanceLimit / max(scenario.roads.count, 1))
        for road in scenario.roads {
            guard let path = paths[road.routePathID] else { continue }
            var pathPosition = 0.0
            let pathStep = max(110, path.lengthM / Double(roadSegmentBudget))
            var segment = 0
            while pathPosition < path.lengthM {
                if let chainage = projectedChainage(road.routePathID, positionM: pathPosition, routeVariant: routeVariant, direction: travelDirection),
                   chainage >= 0, chainage <= route.distanceM,
                   !corridorReserved(at: chainage, landmarks: landmarks) {
                    let sample = sample(at: chainage)
                    let lateral = Float(road.lateralOffsetM)
                    let x = sample.x + lateral * cos(sample.heading)
                    let z = sample.z - lateral * sin(sample.heading)
                    let yaw = simd_quatf(angle: sample.heading, axis: SIMD3<Float>(0, 1, 0))
                    addBox(parent: world, name: "parallel-road-\(road.id)-\(segment)", size: SIMD3<Float>(7.2, 0.12, 120), position: SIMD3<Float>(x, 0.02, z), material: roadMaterial, orientation: yaw)
                    if segment.isMultiple(of: 2) {
                        addBox(parent: world, name: "road-lane-mark-\(road.id)-\(segment)", size: SIMD3<Float>(0.12, 0.025, 5.2), position: SIMD3<Float>(x, 0.09, z), material: roofMaterials[2], orientation: yaw)
                    }
                }
                pathPosition += pathStep
                segment += 1
            }
        }
    }

    private func buildConsist(carCount: Int, useHighFidelityLead: Bool) {
        let count = min(max(carCount, 1), 12)
        if useHighFidelityLead {
            let model = RailwayVehicleHighFidelityBuilder.build(.fictionalPrototype, desk: currentCabDesk)
            highFidelityLeadVehicle = model
            let exterior: Entity?
            let exteriorUsesZUp: Bool
            if let detailed = try? RailwayGeneratedAssetLoader.loadModel(for: .commuterCarDetailed) {
                exterior = detailed
                exteriorUsesZUp = true
            } else {
                exterior = try? RailwayGeneratedAssetLoader.loadModel(for: .commuterCarGeneric)
                exteriorUsesZUp = false
            }
            if let exterior {
                let generatedLead = Entity()
                generatedLead.name = "generated-original-commuter-lead"
                exterior.name = "generated-original-commuter-exterior"
                if exteriorUsesZUp {
                    // Owner-provided GLB: local +X is longitudinal and +Z is up.
                    // The quarter-turn maps +Z-up to Y-up; yaw then maps +X-forward to route-forward.
                    exterior.position = SIMD3<Float>(0, 0.24, 0)
                    exterior.orientation = simd_quatf(angle: Float.pi / 2, axis: SIMD3<Float>(0, 1, 0)) *
                        simd_quatf(angle: -Float.pi / 2, axis: SIMD3<Float>(1, 0, 0))
                } else {
                    exterior.position = SIMD3<Float>(0, 0.9, 0)
                    exterior.scale = SIMD3<Float>(1, 0.7, 1)
                    exterior.orientation = simd_quatf(angle: Float.pi / 2, axis: SIMD3<Float>(0, 1, 0))
                }
                generatedLead.addChild(exterior)
                if let detailedCab = try? RailwayGeneratedAssetLoader.loadModel(for: .driverCabInteriorDetailed) {
                    detailedCab.name = "generated-original-driver-cab-detailed"
                    detailedCab.position = SIMD3<Float>(0, 0.24, -7.6)
                    detailedCab.orientation = simd_quatf(angle: Float.pi / 2, axis: SIMD3<Float>(0, 1, 0)) *
                        simd_quatf(angle: -Float.pi / 2, axis: SIMD3<Float>(1, 0, 0))
                    generatedLead.addChild(detailedCab)
                } else if let cab = try? RailwayGeneratedAssetLoader.loadModel(for: .driverCabInterior) {
                    cab.name = "generated-original-driver-cab"
                    cab.position = SIMD3<Float>(0, 0.9, -7.6)
                    cab.scale = SIMD3<Float>(repeating: 0.7)
                    cab.orientation = simd_quatf(angle: Float.pi / 2, axis: SIMD3<Float>(0, 1, 0))
                    generatedLead.addChild(cab)
                }
                generatedLeadVehicleRoot = generatedLead
                world.addChild(generatedLead)
            } else {
                world.addChild(model.root)
            }
        }
        let firstStandardCar = useHighFidelityLead ? 1 : 0
        for index in firstStandardCar..<count {
            var specification = VehicleSpecification.fictionalPrototype
            specification.identifier = "fictional-commuter-car-\(index + 1)"
            specification.displayName = "Fictional Prototype Car \(index + 1)"
            let model = RailwayVehicleModelBuilder.build(specification, desk: currentCabDesk)
            if index > firstStandardCar {
                model.groups[.cabInterior]?.isEnabled = false
                model.groups[.cabControls]?.isEnabled = false
            }
            world.addChild(model.root)
            vehicleModels.append(model)
            collectWheelEntities(in: model.root)
            if index == 0 && !useHighFidelityLead { cabModel = model }
        }
        guard let model = cabModel else { return }
        speedNeedle = addBox(
            parent: model.root, name: "live-speed-gauge-needle",
            size: SIMD3<Float>(0.035, 0.035, 0.25),
            position: SIMD3<Float>(-0.64, 1.98, -8.02),
            material: Self.pbr(UIColor(red: 0.16, green: 0.82, blue: 0.94, alpha: 1), metallic: 0.15, roughness: 0.34)
        )
        limitNeedle = addBox(
            parent: model.root, name: "live-speed-limit-gauge-needle",
            size: SIMD3<Float>(0.035, 0.035, 0.20),
            position: SIMD3<Float>(0.63, 1.98, -8.02),
            material: Self.pbr(UIColor(red: 0.97, green: 0.48, blue: 0.24, alpha: 1), roughness: 0.35)
        )
    }

    private func buildGenerated3DAssets(route: RailwayRouteProfile) {
        let length = max(route.distanceM, 1)
        addGeneratedStaticAsset(.trackPanel20m, name: "generated-track-panel", chainageM: min(200, length * 0.10), verticalOffsetM: 0.18)
        addGeneratedStaticAsset(.railwayEquipmentModule, name: "generated-railway-equipment", chainageM: min(470, length * 0.24))
        addGeneratedStaticAsset(.suburbanCorridorModules, name: "generated-suburban-corridor", chainageM: min(760, length * 0.38))
    }

    private func addGeneratedStaticAsset(
        _ asset: RailwayGenerated3DAsset,
        name: String,
        chainageM: Double,
        verticalOffsetM: Float = 0
    ) {
        guard let entity = try? RailwayGeneratedAssetLoader.loadModel(for: asset) else { return }
        entity.name = name
        setGeneratedAssetPose(entity, chainageM: chainageM, verticalOffsetM: verticalOffsetM)
        world.addChild(entity)
        generatedStaticAssetRoots.append(entity)
    }

    private func updateGeneratedStationModel(positionM: Double) {
        guard let placement = stationModelPlacements.min(by: {
            abs($0.chainageM - positionM) < abs($1.chainageM - positionM)
        }), abs(placement.chainageM - positionM) <= 350 else {
            importedStationEntity?.removeFromParent()
            importedStationEntity = nil
            importedStationKey = nil
            return
        }
        let key = "\(placement.stationId):\(placement.asset.rawValue)"
        if importedStationKey != key {
            importedStationEntity?.removeFromParent()
            importedStationEntity = nil
            importedStationKey = key
            if let entity = try? RailwayGeneratedAssetLoader.loadModel(for: placement.asset) {
                entity.name = "generated-station-\(placement.stationId)-\(placement.trackCount)track-\(placement.platformCount)platform"
                world.addChild(entity)
                importedStationEntity = entity
            }
        }
        if let entity = importedStationEntity {
            setGeneratedAssetPose(entity, chainageM: placement.chainageM)
        }
    }

    private func setGeneratedAssetPose(
        _ entity: Entity,
        chainageM: Double,
        lateralOffsetM: Float = 0,
        verticalOffsetM: Float = 0
    ) {
        let sample = sample(at: chainageM)
        entity.position = SIMD3<Float>(
            sample.x + lateralOffsetM * cos(sample.heading),
            verticalOffsetM,
            sample.z + lateralOffsetM * sin(sample.heading)
        )
        let alignment = simd_quatf(angle: Float.pi / 2 - sample.heading, axis: SIMD3<Float>(0, 1, 0))
        let cant = simd_quatf(angle: sample.bankRadians, axis: SIMD3<Float>(1, 0, 0))
        entity.orientation = alignment * cant
    }

    private func collectWheelEntities(in parent: Entity) {
        for child in parent.children {
            if child.name.hasPrefix("Wheel_"), let _ = child as? ModelEntity {
                wheelBaseOrientations.append((child, child.orientation))
            }
            collectWheelEntities(in: child)
        }
    }

    private func updateWheels(speedKmh: Double, simulationTime: Double) {
        let angularPosition = Float((speedKmh / 3.6) / 0.43 * simulationTime)
        let spin = simd_quatf(angle: angularPosition, axis: SIMD3<Float>(0, 1, 0))
        for wheel in wheelBaseOrientations {
            wheel.entity.orientation = simd_mul(wheel.orientation, spin)
        }
    }

    private func updateCabGauges(speedKmh: Double, maximumSpeedKmh: Double) {
        let speedFraction = min(max(speedKmh / max(maximumSpeedKmh, 1), 0), 1)
        speedNeedle?.orientation = simd_quatf(angle: Float(-1.25 + speedFraction * 2.5), axis: SIMD3<Float>(0, 1, 0))
        limitNeedle?.orientation = simd_quatf(angle: 0.72, axis: SIMD3<Float>(0, 1, 0))
    }

    private func updateTrafficActors(
        route: RailwayRouteProfile,
        scenario: TrafficScenario?,
        snapshot: TrafficSnapshot?,
        routeVariant: RegionalRouteVariant,
        travelDirection: RegionalTravelDirection,
        simulationTime: Double
    ) {
        guard let scenario, let snapshot, let trafficSceneRoute else {
            previousTrafficSnapshot = nil
            trafficActorAdapter.update(poses: [])
            return
        }
        let previous = previousTrafficSnapshot?.scenarioID == snapshot.scenarioID
            ? previousTrafficSnapshot
            : nil
        let frame = (try? TrafficActorPoseSampler.sample(
            scenario: scenario,
            previous: previous,
            current: snapshot,
            simulationTimeSeconds: simulationTime
        )) ?? (try? TrafficActorPoseSampler.sample(scenario: scenario, snapshot: snapshot))
        previousTrafficSnapshot = snapshot
        guard let frame else {
            trafficActorAdapter.update(poses: [])
            return
        }

        let posesBySourceID = Dictionary(frame.poses.map { ($0.sourceID, $0) }, uniquingKeysWith: { first, _ in first })
        let trainsByID = Dictionary(scenario.trains.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let tracksByID = Dictionary(scenario.tracks.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let roadsByID = Dictionary(scenario.roads.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let roadPlansByID = Dictionary(scenario.roadVehicles.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let platformsByID = Dictionary(scenario.platforms.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let tripsByID = Dictionary(scenario.passengerTrips.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let serviceDirection: RailwayServiceDirection = travelDirection == .up ? .up : .down
        var inputs: [SceneTrafficActorInput] = []
        inputs.reserveCapacity(frame.poses.count)

        for actor in snapshot.trains where actor.phase == .running || actor.phase == .dwelling {
            guard let pose = posesBySourceID[actor.id],
                  let plan = trainsByID[actor.id],
                  let track = tracksByID[actor.trackID],
                  let chainage = projectedChainage(actor.routePathID, positionM: pose.positionM, routeVariant: routeVariant, direction: travelDirection),
                  chainage >= 0, chainage <= route.distanceM else { continue }
            inputs.append(SceneTrafficActorInput(
                id: pose.id, kind: .train, routePathID: pose.routePathID,
                chainageM: chainage, lateralOffsetM: track.lateralOffsetM,
                headingRadians: actor.serviceDirection == serviceDirection ? 0 : .pi,
                speedMps: pose.speedMps, lengthM: plan.lengthM, isVisible: pose.isVisible,
                wheelRotationRadians: pose.wheelRotationRadians
            ))
        }

        for actor in snapshot.roadVehicles where actor.phase == .moving {
            guard let pose = posesBySourceID[actor.id],
                  let plan = roadPlansByID[actor.id],
                  let road = roadsByID[actor.roadID],
                  let chainage = projectedChainage(actor.routePathID, positionM: pose.positionM, routeVariant: routeVariant, direction: travelDirection),
                  chainage >= 0, chainage <= route.distanceM else { continue }
            inputs.append(SceneTrafficActorInput(
                id: pose.id, kind: .roadVehicle, routePathID: pose.routePathID,
                chainageM: chainage, lateralOffsetM: road.lateralOffsetM,
                headingRadians: road.direction.serviceDirection == serviceDirection ? 0 : .pi,
                speedMps: pose.speedMps, lengthM: plan.lengthM, isVisible: pose.isVisible,
                wheelRotationRadians: pose.wheelRotationRadians
            ))
        }

        for actor in snapshot.passengers where actor.phase == .walking || actor.phase == .waiting {
            guard let pose = posesBySourceID[actor.id],
                  let platform = platformsByID[actor.platformID],
                  let track = tracksByID[platform.trackID],
                  let chainage = projectedChainage(track.routePathID, positionM: pose.positionM, routeVariant: routeVariant, direction: travelDirection),
                  chainage >= 0, chainage <= route.distanceM,
                  tripsByID[actor.id] != nil else { continue }
            inputs.append(SceneTrafficActorInput(
                id: pose.id, kind: .platformPassenger, routePathID: pose.routePathID,
                chainageM: chainage, lateralOffsetM: platform.lateralOffsetM + actor.lateralOffsetM,
                headingRadians: actor.headingRadians, speedMps: pose.speedMps,
                lengthM: pose.lengthM, isVisible: pose.isVisible,
                isWalking: actor.phase == .walking, walkCycleRadians: pose.walkCycleRadians,
                verticalOffsetM: 0.48
            ))
        }

        let scenePoses = SceneTrafficActorProjector.project(
            inputs,
            on: trafficSceneRoute,
            supportedRoutePathIDs: Set(scenario.routePaths.map(\.id))
        )
        trafficActorAdapter.update(poses: scenePoses)
    }

    private func updateLegacyTrafficActors(
        route: RailwayRouteProfile,
        scenario: TrafficScenario?,
        snapshot: TrafficSnapshot?,
        routeVariant: RegionalRouteVariant,
        travelDirection: RegionalTravelDirection
    ) {
        guard let scenario, let snapshot else { return }
        let tracks = Dictionary(scenario.tracks.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let roads = Dictionary(scenario.roads.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let platforms = Dictionary(scenario.platforms.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

        let activeTrains = snapshot.trains.filter { $0.phase == .running || $0.phase == .dwelling }
        let activeTrainIDs = Set(activeTrains.map(\.id))
        let staleTrainIDs = aiTrainEntities.keys.filter { !activeTrainIDs.contains($0) }
        for id in staleTrainIDs {
            aiTrainEntities[id]?.removeFromParent()
            aiTrainEntities.removeValue(forKey: id)
        }
        for actor in activeTrains {
            guard let track = tracks[actor.trackID],
                  let chainage = projectedChainage(actor.routePathID, positionM: actor.positionM, routeVariant: routeVariant, direction: travelDirection),
                  chainage >= 0, chainage <= route.distanceM else { continue }
            let entity = aiTrainEntities[actor.id] ?? makeAITrain(id: actor.id, service: actor.serviceType)
            if aiTrainEntities[actor.id] == nil {
                aiTrainEntities[actor.id] = entity
                world.addChild(entity)
            }
            let sample = sample(at: chainage)
            let lateral = Float(track.lateralOffsetM)
            entity.position = SIMD3<Float>(
                sample.x + lateral * cos(sample.heading), 0,
                sample.z - lateral * sin(sample.heading)
            )
            let directionOffset: Float = (actor.serviceDirection == (travelDirection == .up ? .up : .down)) ? 0 : .pi
            entity.orientation = simd_quatf(angle: sample.heading + directionOffset, axis: SIMD3<Float>(0, 1, 0))
        }

        let activeRoadVehicles = snapshot.roadVehicles.filter { $0.phase == .moving }
        let activeRoadIDs = Set(activeRoadVehicles.map(\.id))
        let staleRoadIDs = roadCarEntities.keys.filter { !activeRoadIDs.contains($0) }
        for id in staleRoadIDs {
            roadCarEntities[id]?.removeFromParent()
            roadCarEntities.removeValue(forKey: id)
        }
        for actor in activeRoadVehicles {
            guard let road = roads[actor.roadID],
                  let chainage = projectedChainage(actor.routePathID, positionM: actor.positionM, routeVariant: routeVariant, direction: travelDirection),
                  chainage >= 0, chainage <= route.distanceM else { continue }
            let entity = roadCarEntities[actor.id] ?? makeRoadCar(id: actor.id)
            if roadCarEntities[actor.id] == nil {
                roadCarEntities[actor.id] = entity
                world.addChild(entity)
            }
            let sample = sample(at: chainage)
            let lateral = Float(road.lateralOffsetM)
            entity.position = SIMD3<Float>(sample.x + lateral * cos(sample.heading), 0, sample.z - lateral * sin(sample.heading))
            let directionOffset: Float = road.direction.serviceDirection == (travelDirection == .up ? .up : .down) ? 0 : .pi
            entity.orientation = simd_quatf(angle: sample.heading + directionOffset, axis: SIMD3<Float>(0, 1, 0))
        }

        let activePeople = snapshot.passengers.filter { $0.phase == .walking || $0.phase == .waiting }
        let activePersonIDs = Set(activePeople.map(\.id))
        let stalePersonIDs = platformPeople.keys.filter { !activePersonIDs.contains($0) }
        for id in stalePersonIDs {
            platformPeople[id]?.removeFromParent()
            platformPeople.removeValue(forKey: id)
        }
        for actor in activePeople {
            guard let platform = platforms[actor.platformID],
                  let track = tracks[platform.trackID],
                  let chainage = projectedChainage(
                    track.routePathID,
                    positionM: platform.chainageM + actor.alongPlatformM,
                    routeVariant: routeVariant,
                    direction: travelDirection
                  ), chainage >= 0, chainage <= route.distanceM else { continue }
            let entity = platformPeople[actor.id] ?? makePlatformPerson(id: actor.id)
            if platformPeople[actor.id] == nil {
                platformPeople[actor.id] = entity
                world.addChild(entity)
            }
            let sample = sample(at: chainage)
            let lateral = Float(platform.lateralOffsetM + actor.lateralOffsetM)
            entity.position = SIMD3<Float>(sample.x + lateral * cos(sample.heading), 0.48, sample.z - lateral * sin(sample.heading))
            entity.orientation = simd_quatf(angle: sample.heading + Float(actor.headingRadians), axis: SIMD3<Float>(0, 1, 0))
        }
    }

    private func projectedChainage(
        _ pathID: String,
        positionM: Double,
        routeVariant: RegionalRouteVariant,
        direction: RegionalTravelDirection
    ) -> Double? {
        let mainLength = 60_000.0
        let branchLength = 8_000.0
        switch routeVariant {
        case .mainline:
            guard pathID == "mainline" else { return nil }
            return direction == .up ? positionM : mainLength - positionM
        case .throughBranch:
            if direction == .up {
                if pathID == "mainline" { return positionM }
                if pathID == "branch" { return mainLength + positionM }
            } else {
                if pathID == "branch" { return branchLength - positionM }
                if pathID == "mainline" { return branchLength + mainLength - positionM }
            }
            return nil
        case .branchShuttle:
            guard pathID == "branch" else { return nil }
            return direction == .up ? positionM : branchLength - positionM
        case .depotTransfer:
            guard pathID == "depot-spur" else { return nil }
            return direction == .up ? positionM : 2_000 - positionM
        }
    }

    private func makeAITrain(id: String, service: TrainServiceType) -> Entity {
        let train = Entity()
        train.name = "traffic-ai-train-\(id)"
        let accentColors: [UIColor] = [
            UIColor(red: 0.15, green: 0.55, blue: 0.63, alpha: 1),
            UIColor(red: 0.78, green: 0.45, blue: 0.19, alpha: 1),
            UIColor(red: 0.39, green: 0.48, blue: 0.72, alpha: 1)
        ]
        let accent = Self.pbr(accentColors[stableIndex(service.rawValue, count: accentColors.count)], metallic: 0.08, roughness: 0.52)
        let body = Self.pbr(UIColor(red: 0.75, green: 0.79, blue: 0.77, alpha: 1), metallic: 0.12, roughness: 0.47)
        for carIndex in 0..<4 {
            let centerZ = Float(carIndex) * 19 + 8.5
            addBox(parent: train, name: "body-\(carIndex)", size: SIMD3<Float>(2.85, 3.25, 18), position: SIMD3<Float>(0, 1.80, centerZ), material: body)
            addBox(parent: train, name: "livery-\(carIndex)", size: SIMD3<Float>(2.88, 0.28, 18), position: SIMD3<Float>(0, 1.86, centerZ), material: accent)
            addBox(parent: train, name: "roof-\(carIndex)", size: SIMD3<Float>(2.52, 0.18, 17.3), position: SIMD3<Float>(0, 3.47, centerZ), material: sleeperMaterial)
            for side in [-1.0, 1.0] {
                for window in 0..<5 {
                    let z = centerZ + Float(window - 2) * 2.7
                    addBox(parent: train, name: "window-\(carIndex)-\(window)-\(Int(side))", size: SIMD3<Float>(0.035, 0.72, 1.65), position: SIMD3<Float>(Float(side) * 1.435, 2.55, z), material: glassMaterial)
                }
            }
        }
        return train
    }

    private func makeRoadCar(id: String) -> Entity {
        let car = Entity()
        car.name = "traffic-road-vehicle-\(id)"
        let palette = [
            Self.pbr(UIColor(red: 0.67, green: 0.31, blue: 0.25, alpha: 1), metallic: 0.08, roughness: 0.48),
            Self.pbr(UIColor(red: 0.25, green: 0.43, blue: 0.56, alpha: 1), metallic: 0.10, roughness: 0.48),
            Self.pbr(UIColor(red: 0.68, green: 0.64, blue: 0.49, alpha: 1), metallic: 0.05, roughness: 0.55)
        ]
        let paint = palette[stableIndex(id, count: palette.count)]
        addBox(parent: car, name: "car-body", size: SIMD3<Float>(1.75, 0.58, 3.8), position: SIMD3<Float>(0, 0.55, 0), material: paint)
        addBox(parent: car, name: "car-cabin", size: SIMD3<Float>(1.46, 0.52, 1.95), position: SIMD3<Float>(0, 1.04, 0.10), material: glassMaterial)
        for side in [-1.0, 1.0] {
            for end in [-1.0, 1.0] {
                let wheel = ModelEntity(mesh: .generateSphere(radius: 0.23), materials: [sleeperMaterial])
                wheel.position = SIMD3<Float>(Float(side) * 0.78, 0.24, Float(end) * 1.20)
                car.addChild(wheel)
            }
        }
        return car
    }

    private func makePlatformPerson(id: String) -> Entity {
        let person = Entity()
        person.name = "traffic-platform-passenger-\(id)"
        let clothes = [
            Self.pbr(UIColor(red: 0.24, green: 0.39, blue: 0.53, alpha: 1), roughness: 0.87),
            Self.pbr(UIColor(red: 0.53, green: 0.28, blue: 0.25, alpha: 1), roughness: 0.89),
            Self.pbr(UIColor(red: 0.31, green: 0.43, blue: 0.34, alpha: 1), roughness: 0.92)
        ]
        let shirt = ModelEntity(mesh: .generateBox(size: SIMD3<Float>(0.38, 0.72, 0.24)), materials: [clothes[stableIndex(id, count: clothes.count)]])
        shirt.position = SIMD3<Float>(0, 0.82, 0)
        person.addChild(shirt)
        let head = ModelEntity(mesh: .generateSphere(radius: 0.16), materials: [concreteMaterial])
        head.position = SIMD3<Float>(0, 1.30, 0)
        person.addChild(head)
        return person
    }

    /// Uses package-provided cosmetic blend hints to select procedural material variants.
    /// This is not accumulated water/snow or a physical surface simulation.
    private func updateSurfaceMaterials(wetness: Double, snowCoverage: Double) {
        let wet = min(max(wetness.isFinite ? wetness : 0, 0), 1)
        let snow = min(max(snowCoverage.isFinite ? snowCoverage : 0, 0), 1)
        let key = "\(Int((wet * 100).rounded()))-\(Int((snow * 100).rounded()))"
        guard key != lastSurfaceMaterialKey else { return }
        lastSurfaceMaterialKey = key
        for target in surfaceMaterialTargets {
            let damp = Self.mixColor(target.baseColor, UIColor(red: 0.48, green: 0.56, blue: 0.62, alpha: 1), amount: CGFloat(wet * 0.20))
            let finalColor = Self.mixColor(damp, UIColor(red: 0.88, green: 0.92, blue: 0.95, alpha: 1), amount: CGFloat(snow * 0.72))
            let wetRoughness = target.roughness * (1 - 0.55 * Float(wet))
            let finalRoughness = wetRoughness + (0.88 - wetRoughness) * Float(snow * 0.72)
            target.entity.model?.materials = [Self.pbr(finalColor, metallic: target.metallic, roughness: min(max(finalRoughness, 0.08), 1))]
        }
    }

    private static func mixColor(_ from: UIColor, _ to: UIColor, amount: CGFloat) -> UIColor {
        var fr: CGFloat = 0, fg: CGFloat = 0, fb: CGFloat = 0, fa: CGFloat = 1
        var tr: CGFloat = 0, tg: CGFloat = 0, tb: CGFloat = 0, ta: CGFloat = 1
        from.getRed(&fr, green: &fg, blue: &fb, alpha: &fa)
        to.getRed(&tr, green: &tg, blue: &tb, alpha: &ta)
        let t = min(max(amount, 0), 1)
        return UIColor(red: fr + (tr - fr) * t, green: fg + (tg - fg) * t, blue: fb + (tb - fb) * t, alpha: fa + (ta - fa) * t)
    }

    private func addSurfaceBox(
        parent: Entity, name: String, size: SIMD3<Float>, position: SIMD3<Float>,
        color: UIColor, metallic: Float = 0, roughness: Float, orientation: simd_quatf? = nil
    ) {
        let entity = addBox(parent: parent, name: name, size: size, position: position,
                            material: Self.pbr(color, metallic: metallic, roughness: roughness), orientation: orientation)
        surfaceMaterialTargets.append(SurfaceMaterialTarget(entity: entity, baseColor: color, metallic: metallic, roughness: roughness))
    }

    private func addTree(parent: Entity, name: String, x: Float, z: Float, height: Float, material: PhysicallyBasedMaterial) {
        let trunkMesh: MeshResource
        if #available(iOS 18.0, *) {
            trunkMesh = .generateCylinder(height: height * 0.55, radius: 0.10)
        } else {
            trunkMesh = FallbackCylinderMesh.make(height: height * 0.55, radius: 0.10)
        }
        let trunk = ModelEntity(mesh: trunkMesh, materials: [sleeperMaterial])
        trunk.name = "\(name)-trunk"
        trunk.position = SIMD3<Float>(x, height * 0.275, z)
        parent.addChild(trunk)

        let crown = ModelEntity(mesh: .generateSphere(radius: height * 0.32), materials: [material])
        crown.name = "\(name)-crown"
        crown.position = SIMD3<Float>(x, height * 0.70, z)
        crown.scale = SIMD3<Float>(1, 1.12, 0.92)
        parent.addChild(crown)
    }

    @discardableResult
    private func addBox(
        parent: Entity,
        name: String,
        size: SIMD3<Float>,
        position: SIMD3<Float>,
        material: PhysicallyBasedMaterial,
        orientation: simd_quatf? = nil
    ) -> ModelEntity {
        let entity = ModelEntity(mesh: .generateBox(size: size), materials: [material])
        entity.name = name
        entity.position = position
        if let orientation { entity.orientation = orientation }
        parent.addChild(entity)
        return entity
    }

    private func makeSamples(route: RailwayRouteProfile, interval: Double) -> [RouteSample] {
        RegionalRouteGeometrySampler.makeSamples(route: route, interval: interval).map { sample in
            RouteSample(
                distanceM: sample.distanceM,
                x: sample.x,
                z: sample.z,
                heading: sample.heading,
                bankRadians: sample.bankRadians
            )
        }
    }

    private func makeSceneFidelityRoute() -> SceneChainageRoute? {
        let controlPoints = samples.map { routeSample in
            let heading = Double(routeSample.heading)
            return SceneRouteControlPoint(
                chainageM: routeSample.distanceM,
                position: SceneVector3(Double(routeSample.x), 0, Double(routeSample.z)),
                tangentPerMeter: SceneVector3(sin(heading), 0, -cos(heading)),
                bankRadians: Double(routeSample.bankRadians)
            )
        }
        guard controlPoints.count >= 2 else { return nil }
        return try? SceneChainageRoute(controlPoints: controlPoints)
    }

    private func fictionalTerminalPlatforms(for route: RailwayRouteProfile) -> [ScenePlatformSpecification] {
        let end = min(max(route.stopMarkerM, 0), route.distanceM)
        let start = max(0, end - 180)
        guard end - start >= 30 else { return [] }
        return [ScenePlatformSpecification(
            id: "fictional-terminal-platform",
            startChainageM: start,
            endChainageM: end,
            side: 1,
            offsetFromTrackCenterM: 3.4,
            widthM: 3.6,
            hasCanopy: true
        )]
    }

    /// Same PLACEHOLDER chainage beats as the high-quality builder. Low/medium draws a coarse version.
    private func fictionalCorridorLandmarks(for route: RailwayRouteProfile) -> [SceneCorridorLandmark] {
        SceneCorridorLandmarkSchedule.landmarks(
            from: 0,
            to: max(route.distanceM, 0),
            avoiding: fictionalTerminalPlatforms(for: route)
        )
    }

    private func corridorReserved(at chainage: Double, landmarks: [SceneCorridorLandmark]) -> Bool {
        landmarks.contains { landmark in
            landmark.contains(chainage, margin: SceneCorridorLandmarkSchedule.urbanClearanceM(for: landmark.kind))
        }
    }

    private func sceneFidelityCorridor(for route: RailwayRouteProfile) -> SceneCorridorSpecification {
        let platforms = fictionalTerminalPlatforms(for: route)
        return SceneCorridorSpecification(
            trackGaugeM: route.trackGaugeMm / 1_000,
            sleeperSpacingM: 0.60,
            catenarySpacingM: 45,
            overheadContactWireHeightM: 5.2,
            platforms: platforms,
            generateUrbanScenery: true
        )
    }

    /// Coarse PLACEHOLDER bridges, cuttings, embankments, and static crossings for the low/medium scene.
    /// High quality uses the curve-following meshes from `RailwaySceneFidelity` instead.
    /// Barrier arms are drawn raised. These crossings do not interlock or affect physics.
    /// Rain and snow only recolor the surfaces; they do not add accumulation geometry.
    private func buildFictionalCorridorLandmarks(route: RailwayRouteProfile, quality: EnvironmentRenderQuality) {
        let sampleLimit = quality == .low ? 2 : 3
        let water = UIColor(red: 0.13, green: 0.30, blue: 0.38, alpha: 1)
        let grass = UIColor(red: 0.24, green: 0.40, blue: 0.20, alpha: 1)
        for landmark in fictionalCorridorLandmarks(for: route) {
            switch landmark.kind {
            case .riverBridge:
                let samples = landmarkSampleChainages(landmark, limit: sampleLimit)
                for (index, chainage) in samples.enumerated() {
                    let sample = sample(at: chainage)
                    let yaw = simd_quatf(angle: sample.heading, axis: SIMD3<Float>(0, 1, 0))
                    let length = Float(landmark.lengthM / Double(samples.count))
                    let center = routeOffsetPoint(sample, lateral: 0)
                    addSurfaceBox(parent: world, name: "\(landmark.id)-water-\(index)", size: SIMD3<Float>(18, 0.28, length),
                                  position: SIMD3<Float>(center.x, -0.62, center.z), color: water, roughness: 0.18, orientation: yaw)
                    addSurfaceBox(parent: world, name: "\(landmark.id)-deck-\(index)", size: SIMD3<Float>(8.4, 0.16, length),
                                  position: SIMD3<Float>(center.x, -0.08, center.z), color: UIColor(red: 0.46, green: 0.48, blue: 0.47, alpha: 1),
                                  roughness: 0.84, orientation: yaw)
                    for side in [-1.0, 1.0] {
                        let edge = routeOffsetPoint(sample, lateral: Float(side) * 4.55)
                        addSurfaceBox(parent: world, name: "\(landmark.id)-parapet-\(index)-\(Int(side))",
                                      size: SIMD3<Float>(0.28, 1.2, length),
                                      position: SIMD3<Float>(edge.x, 0.7, edge.z), color: UIColor(red: 0.52, green: 0.54, blue: 0.52, alpha: 1),
                                      roughness: 0.8, orientation: yaw)
                    }
                    addBox(parent: world, name: "\(landmark.id)-pier-\(index)", size: SIMD3<Float>(0.7, 1.05, 0.7),
                           position: SIMD3<Float>(center.x, -0.85, center.z), material: concreteMaterial, orientation: yaw)
                }
            case .cutting:
                let samples = landmarkSampleChainages(landmark, limit: sampleLimit)
                for (index, chainage) in samples.enumerated() {
                    let sample = sample(at: chainage)
                    let yaw = simd_quatf(angle: sample.heading, axis: SIMD3<Float>(0, 1, 0))
                    let length = Float(landmark.lengthM / Double(samples.count))
                    for side in [-1.0, 1.0] {
                        let edge = routeOffsetPoint(sample, lateral: Float(side) * 6.6)
                        addSurfaceBox(parent: world, name: "\(landmark.id)-wall-\(index)-\(Int(side))",
                                      size: SIMD3<Float>(0.7, 4.6, length),
                                      position: SIMD3<Float>(edge.x, 2.15, edge.z),
                                      color: UIColor(red: 0.45, green: 0.46, blue: 0.44, alpha: 1),
                                      roughness: 0.9, orientation: yaw)
                    }
                }
            case .embankment:
                let samples = landmarkSampleChainages(landmark, limit: sampleLimit)
                for (index, chainage) in samples.enumerated() {
                    let sample = sample(at: chainage)
                    let yaw = simd_quatf(angle: sample.heading, axis: SIMD3<Float>(0, 1, 0))
                    let length = Float(landmark.lengthM / Double(samples.count))
                    for side in [-1.0, 1.0] {
                        let edge = routeOffsetPoint(sample, lateral: Float(side) * 6.8)
                        let roll = simd_quatf(angle: Float(side) * -0.48, axis: SIMD3<Float>(0, 0, 1))
                        addSurfaceBox(parent: world, name: "\(landmark.id)-slope-\(index)-\(Int(side))",
                                      size: SIMD3<Float>(6.5, 0.42, length),
                                      position: SIMD3<Float>(edge.x, -0.35, edge.z),
                                      color: grass, roughness: 0.95, orientation: yaw * roll)
                    }
                }
            case .levelCrossing:
                let sample = sample(at: (landmark.startChainageM + landmark.endChainageM) * 0.5)
                let yaw = simd_quatf(angle: sample.heading, axis: SIMD3<Float>(0, 1, 0))
                for side in [-1.0, 1.0] {
                    let approach = routeOffsetPoint(sample, lateral: Float(side) * 8.0)
                    addSurfaceBox(parent: world, name: "\(landmark.id)-approach-\(Int(side))",
                                  size: SIMD3<Float>(11, 0.12, 6.4),
                                  position: SIMD3<Float>(approach.x, 0.06, approach.z),
                                  color: UIColor(red: 0.17, green: 0.18, blue: 0.18, alpha: 1),
                                  roughness: 0.78, orientation: yaw)
                    let post = routeOffsetPoint(sample, lateral: Float(side) * 4.3)
                    addBox(parent: world, name: "\(landmark.id)-post-\(Int(side))", size: SIMD3<Float>(0.16, 2.3, 0.16),
                           position: SIMD3<Float>(post.x, 1.15, post.z), material: poleMaterial)
                    addBox(parent: world, name: "\(landmark.id)-raised-arm-\(Int(side))", size: SIMD3<Float>(0.12, 2.15, 0.1),
                           position: SIMD3<Float>(post.x, 2.35, post.z), material: roofMaterials[0])
                }
            }
        }
    }

    private func landmarkSampleChainages(_ landmark: SceneCorridorLandmark, limit: Int) -> [Double] {
        let count = min(max(limit, 1), max(1, Int((landmark.lengthM / 36).rounded(.up))))
        let step = landmark.lengthM / Double(count)
        return (0..<count).map { landmark.startChainageM + (Double($0) + 0.5) * step }
    }

    private func sceneCameraState(at chainageM: Double, useLiveCamera: Bool) -> SceneCameraState {
        let safeChainage = min(max(chainageM, 0), sceneFidelityRoute?.endChainageM ?? chainageM)
        let routeSample = sample(at: safeChainage)
        let cameraPosition = useLiveCamera
            ? cameraWorldPosition
            : SIMD3<Float>(routeSample.x, 2.7, routeSample.z)
        let cameraForward = useLiveCamera
            ? simd_act(camera.orientation, SIMD3<Float>(0, 0, -1))
            : SIMD3<Float>(sin(routeSample.heading), 0, -cos(routeSample.heading))
        return SceneCameraState(
            position: SceneVector3(Double(cameraPosition.x), Double(cameraPosition.y), Double(cameraPosition.z)),
            forward: SceneVector3(Double(cameraForward.x), Double(cameraForward.y), Double(cameraForward.z)),
            chainageM: safeChainage,
            verticalFieldOfViewRadians: 66 * .pi / 180,
            aspectRatio: 1.8,
            farDistanceM: sceneFidelityDensity.visibleDistanceM,
            towardIncreasingChainage: true
        )
    }

    private func buildSceneFidelityRegion(
        route: RailwayRouteProfile,
        chainageM: Double,
        useLiveCamera: Bool
    ) {
        guard let sceneRoute = sceneFidelityRoute else { return }
        let cameraState = sceneCameraState(at: chainageM, useLiveCamera: useLiveCamera)
        let plan = RailwaySceneFidelityBuilder.build(
            route: sceneRoute,
            corridor: sceneFidelityCorridor(for: route),
            camera: cameraState,
            density: sceneFidelityDensity
        )
        sceneFidelityAdapter.build(plan: plan, camera: cameraState, surfaceWeather: sceneFidelityAdapter.surfaceWeather)
        if sceneFidelityAdapter.root.parent == nil {
            world.addChild(sceneFidelityAdapter.root)
        }
        lastSceneFidelityBuildChainage = cameraState.chainageM
    }

    private func updateSceneFidelity(route: RailwayRouteProfile, positionM: Double) {
        guard sceneFidelityRoute != nil, lastSceneFidelityBuildChainage.isFinite else { return }
        let cameraState = sceneCameraState(at: positionM, useLiveCamera: true)
        sceneFidelityAdapter.updateCamera(cameraState)
        if !sceneFidelityAdapter.pendingLODAssemblyIDs.isEmpty {
            sceneFidelityAdapter.rebuildLODAssemblies(
                sceneFidelityAdapter.pendingLODAssemblyIDs,
                camera: cameraState
            )
        }
        let streamThreshold = max(120, sceneFidelityDensity.visibleDistanceM * 0.35)
        if sceneFidelityAdapter.needsSceneRebuild ||
            abs(cameraState.chainageM - lastSceneFidelityBuildChainage) >= streamThreshold {
            buildSceneFidelityRegion(route: route, chainageM: positionM, useLiveCamera: true)
        }
    }

    private func sample(at distanceM: Double) -> RouteSample {
        guard let upperIndex = samples.firstIndex(where: { $0.distanceM >= distanceM }) else {
            if let last = samples.last { return last }
            return RouteSample(distanceM: distanceM, x: 0, z: Float(-distanceM), heading: 0, bankRadians: 0)
        }
        guard upperIndex > 0 else { return samples[upperIndex] }
        let lower = samples[upperIndex - 1]
        let upper = samples[upperIndex]
        let span = max(upper.distanceM - lower.distanceM, 0.001)
        let fraction = Float(min(max((distanceM - lower.distanceM) / span, 0), 1))
        return RouteSample(
            distanceM: distanceM,
            x: lower.x + (upper.x - lower.x) * fraction,
            z: lower.z + (upper.z - lower.z) * fraction,
            heading: lower.heading + (upper.heading - lower.heading) * fraction,
            bankRadians: lower.bankRadians + (upper.bankRadians - lower.bankRadians) * fraction
        )
    }

    private func routeOffsetPoint(_ sample: RouteSample, lateral: Float) -> SIMD3<Float> {
        SIMD3<Float>(
            sample.x + lateral * cos(sample.heading),
            0,
            sample.z - lateral * sin(sample.heading)
        )
    }

    private func stableIndex(_ value: String, count: Int) -> Int {
        guard count > 0 else { return 0 }
        let checksum = value.utf8.reduce(UInt64(2_166_136_261)) { ($0 ^ UInt64($1)) &* 16_777_619 }
        return Int(checksum % UInt64(count))
    }

    private static func pbr(_ color: UIColor, metallic: Float = 0.0, roughness: Float) -> PhysicallyBasedMaterial {
        var material = PhysicallyBasedMaterial()
        material.baseColor = .init(tint: color, texture: nil)
        material.metallic = .init(floatLiteral: metallic)
        material.roughness = .init(floatLiteral: roughness)
        return material
    }
}

@MainActor
private struct RoadCarActor {
    let entity: Entity
    let startM: Double
    let speedMps: Double
    let lane: Float
}

@MainActor
private struct PlatformPersonActor {
    let entity: Entity
    let chainageOffsetM: Double
    let phase: Double
    let side: Float
    let walking: Bool
}

private struct RouteSample {
    let distanceM: Double
    let x: Float
    let z: Float
    let heading: Float
    let bankRadians: Float
}
    private var currentSample = RouteSample(distanceM: 0, x: 0, z: 0, heading: 0, bankRadians: 0)
    private var generatedLeadVehicleRoot: Entity?
