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
    var signalPositionM: Double? = nil
    var signalAspect: ThreeAspectSignal? = nil

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
                stationModelPlacements: stationModelPlacements,
                signalPositionM: signalPositionM,
                signalAspect: signalAspect
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
    var signalPositionM: Double? = nil
    var signalAspect: ThreeAspectSignal? = nil

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> ARView {
        let view = ARView(frame: .zero, cameraMode: .nonAR, automaticallyConfigureSession: false)
        // The renderer clears with environment.background, not with the
        // UIView's backgroundColor: setting only the latter left the
        // sky black in every running shot (CI #166) even though the
        // palette itself was correct.
        let skyColor = RailwaySkyPalette.color(for: environmentSelection)
        view.backgroundColor = skyColor
        view.environment.background = .color(skyColor)
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
            cabDesk: cabDesk, stationModelPlacements: stationModelPlacements,
            signalPositionM: signalPositionM, signalAspect: signalAspect
        )
        return view
    }

    func updateUIView(_ view: ARView, context: Context) {
        if context.coordinator.lastSkySelection != environmentSelection {
            let skyColor = RailwaySkyPalette.color(for: environmentSelection)
            view.backgroundColor = skyColor
            view.environment.background = .color(skyColor)
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
            cabDesk: cabDesk, stationModelPlacements: stationModelPlacements,
            signalPositionM: signalPositionM, signalAspect: signalAspect
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

    private let ballastMaterial = RailwaySceneWorld.texturedPBR(UIColor(red: 0.92, green: 0.92, blue: 0.92, alpha: 1), roughness: 0.96, textureName: "scenery_ballast", normalName: "normal_ballast")
    private let sleeperMaterial = RailwaySceneWorld.texturedPBR(UIColor(red: 0.72, green: 0.62, blue: 0.52, alpha: 1), roughness: 0.88, textureName: "scenery_timber")
    private let railMaterial = RailwaySceneWorld.pbr(UIColor(red: 0.48, green: 0.54, blue: 0.55, alpha: 1), metallic: 0.82, roughness: 0.27)
    private let concreteMaterial = RailwaySceneWorld.texturedPBR(.white, roughness: 0.87, textureName: "scenery_concrete", normalName: "normal_concrete")
    private let poleMaterial = RailwaySceneWorld.texturedPBR(UIColor(red: 0.55, green: 0.58, blue: 0.58, alpha: 1), metallic: 0.62, roughness: 0.42, textureName: "scenery_steel")
    private let wireMaterial = RailwaySceneWorld.pbr(UIColor(red: 0.68, green: 0.66, blue: 0.57, alpha: 1), metallic: 0.84, roughness: 0.24)
    private let roadMaterial = RailwaySceneWorld.texturedPBR(.white, roughness: 0.78, textureName: "scenery_asphalt", normalName: "normal_asphalt")
    private let glassMaterial = RailwaySceneWorld.pbr(UIColor(red: 0.12, green: 0.26, blue: 0.31, alpha: 1), metallic: 0.18, roughness: 0.20)
    private let roofMaterials = [
        RailwaySceneWorld.texturedPBR(UIColor(red: 0.45, green: 0.38, blue: 0.33, alpha: 1), roughness: 0.84, textureName: "scenery_steel"),
        RailwaySceneWorld.texturedPBR(UIColor(red: 0.55, green: 0.50, blue: 0.44, alpha: 1), roughness: 0.82, textureName: "scenery_steel"),
        RailwaySceneWorld.texturedPBR(UIColor(red: 0.40, green: 0.46, blue: 0.50, alpha: 1), metallic: 0.12, roughness: 0.71, textureName: "scenery_steel")
    ]
    private let buildingMaterials = [
        RailwaySceneWorld.texturedPBR(.white, roughness: 0.89, textureName: "scenery_brick_warm"),
        RailwaySceneWorld.texturedPBR(.white, roughness: 0.86, textureName: "scenery_brick_cool"),
        RailwaySceneWorld.texturedPBR(UIColor(red: 0.88, green: 0.82, blue: 0.76, alpha: 1), roughness: 0.91, textureName: "scenery_brick_warm"),
        RailwaySceneWorld.texturedPBR(UIColor(red: 0.95, green: 0.90, blue: 0.82, alpha: 1), roughness: 0.88, textureName: "scenery_concrete"),
        RailwaySceneWorld.texturedPBR(UIColor(red: 0.90, green: 0.95, blue: 1.0, alpha: 1), metallic: 0.06, roughness: 0.7, textureName: "scenery_brick_cool")
    ]
    private let officeMaterials = [
        RailwaySceneWorld.texturedPBR(.white, roughness: 0.62, textureName: "scenery_office_facade", normalName: "normal_office_facade"),
        RailwaySceneWorld.texturedPBR(UIColor(red: 0.90, green: 0.88, blue: 0.84, alpha: 1), roughness: 0.66, textureName: "scenery_office_facade", normalName: "normal_office_facade"),
        RailwaySceneWorld.texturedPBR(.white, metallic: 0.25, roughness: 0.34, textureName: "scenery_glass_facade", normalName: "normal_glass_facade"),
        RailwaySceneWorld.texturedPBR(UIColor(red: 0.88, green: 0.92, blue: 1.0, alpha: 1), metallic: 0.25, roughness: 0.38, textureName: "scenery_glass_facade", normalName: "normal_glass_facade"),
        RailwaySceneWorld.texturedPBR(.white, roughness: 0.92, textureName: "scenery_apartment_facade", normalName: "normal_apartment_facade"),
        RailwaySceneWorld.texturedPBR(UIColor(red: 0.94, green: 0.90, blue: 0.84, alpha: 1), roughness: 0.9, textureName: "scenery_house_facade")
    ]
    private let foliageMaterials = [
        RailwaySceneWorld.texturedPBR(UIColor(red: 0.75, green: 0.90, blue: 0.75, alpha: 1), roughness: 0.98, textureName: "scenery_foliage"),
        RailwaySceneWorld.texturedPBR(UIColor(red: 0.90, green: 1.0, blue: 0.85, alpha: 1), roughness: 0.98, textureName: "scenery_foliage"),
        RailwaySceneWorld.texturedPBR(UIColor(red: 0.80, green: 0.95, blue: 0.88, alpha: 1), roughness: 0.98, textureName: "scenery_foliage")
    ]
    /// Full-facade photo texture for suburban houses (windows and door are
    /// painted in, so those houses skip the separate window/door boxes).
    private let houseFacadeMaterial = RailwaySceneWorld.texturedPBR(.white, roughness: 0.92, textureName: "scenery_house_facade")
    /// Platform-edge tactile paving: the safety yellow band reads as
    /// tactile paving at platform distance even without modelled dots.
    private let tactileMaterial = RailwaySceneWorld.pbr(UIColor(red: 0.87, green: 0.66, blue: 0.10, alpha: 1), roughness: 0.9)
    /// Signal lamp materials: unlit, so a lit lamp reads at full
    /// brightness in daylight while a dark lens stays near-black.
    private let signalDarkLampMaterial = UnlitMaterial(color: UIColor(red: 0.07, green: 0.07, blue: 0.08, alpha: 1))
    private let signalRedMaterial = UnlitMaterial(color: UIColor(red: 1.0, green: 0.12, blue: 0.08, alpha: 1))
    private let signalYellowMaterial = UnlitMaterial(color: UIColor(red: 1.0, green: 0.75, blue: 0.10, alpha: 1))
    private let signalGreenMaterial = UnlitMaterial(color: UIColor(red: 0.15, green: 0.95, blue: 0.35, alpha: 1))
    /// Trackside signal lamp heads by travel-frame distance [m]:
    /// the three lamp entities in red / yellow / green order.
    private var signalLampHeads: [Double: [ModelEntity]] = [:]
    private var dynamicSignalDistance: Double?
    private var dynamicSignalAspect: ThreeAspectSignal?

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
        signalLampHeads.removeAll()
        dynamicSignalDistance = nil
        dynamicSignalAspect = nil
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
            buildTunnels(route: route)
            buildSignals(route: route, routeVariant: routeVariant, travelDirection: travelDirection)
            buildCatenary(route: route)
            buildSuburb(route: route, routeVariant: routeVariant, travelDirection: travelDirection)
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
        stationModelPlacements: [RailwayGeneratedStationPlacement],
        signalPositionM: Double? = nil,
        signalAspect: ThreeAspectSignal? = nil
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
        updateSignalAspect(positionM: signalPositionM, aspect: signalAspect)
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
            let chainage = positionM - 9.75 - Double(consistIndex) * 19.5
            let carSample = self.sample(at: chainage)
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
            let carChainage = positionM - 9.75
            let carSample = self.sample(at: carChainage)
            let frontBogieSample = self.sample(at: carChainage - 6.35)
            let rearBogieSample = self.sample(at: carChainage + 6.35)
            let carLateral = SIMD3<Float>(cos(carSample.heading), 0, sin(carSample.heading))
            let trackSide: Float = travelDirection == .up ? -2.1 : 2.1
            model.root.position = SIMD3<Float>(
                carSample.x + trackSide * carLateral.x, 0, carSample.z + trackSide * carLateral.z
            )
            model.root.orientation = simd_quatf(angle: -carSample.heading, axis: SIMD3<Float>(0, 1, 0)) *
                simd_quatf(angle: -carSample.bankRadians, axis: SIMD3<Float>(0, 0, 1))
            generatedLeadVehicleRoot?.position = model.root.position
            generatedLeadVehicleRoot?.orientation = model.root.orientation
            func relativeBogieYaw(_ heading: Float) -> Float {
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
        if renderingWeather == .dry || renderingWeather == .fog {
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

    /// Chainage measured from the central terminal (Kanun-Chuo),
    /// regardless of travel direction, so scenery zoning is
    /// direction-independent.
    private func chainageFromCenter(distanceM: Double, route: RailwayRouteProfile, travelDirection: RegionalTravelDirection) -> Double {
        travelDirection == .up ? distanceM : route.distanceM - distanceM
    }

    private func isMainlineSection(distanceM: Double, routeVariant: RegionalRouteVariant, travelDirection: RegionalTravelDirection) -> Bool {
        switch routeVariant {
        case .mainline: return true
        case .throughBranch: return travelDirection == .up ? distanceM < 60_000 : distanceM >= 8_000
        default: return false
        }
    }

    /// 2 = urban core around the central terminal, 1 = mid-rise band
    /// (secondary city node / core fringe), 0 = ordinary suburb/rural.
    private func urbanBand(distanceM: Double, route: RailwayRouteProfile, routeVariant: RegionalRouteVariant, travelDirection: RegionalTravelDirection) -> Int {
        guard isMainlineSection(distanceM: distanceM, routeVariant: routeVariant, travelDirection: travelDirection) else { return 0 }
        let c = chainageFromCenter(distanceM: distanceM, route: route, travelDirection: travelDirection)
        if c <= 4_200 { return 2 }
        if c <= 6_000 { return 1 }
        if c >= 22_600 && c <= 25_800 { return 1 }
        return 0
    }

    /// Coastal stretches with beach and open sea on one side, about
    /// 14 km in total across three windows. The middle window starts
    /// exactly at the 42.1-43.6 km tunnel's exit portal, so the train
    /// bursts out of the tunnel straight into the sea view.
    ///   38.5-40.5 km: a first taste of the sea around Kaigandori
    ///   43.6-48.6 km: the tunnel-exit reveal
    ///   53.0-60.0 km: Shirahama to the Higashihama terminus
    private func isCoastal(distanceM: Double, route: RailwayRouteProfile, routeVariant: RegionalRouteVariant, travelDirection: RegionalTravelDirection) -> Bool {
        guard isMainlineSection(distanceM: distanceM, routeVariant: routeVariant, travelDirection: travelDirection) else { return false }
        let c = chainageFromCenter(distanceM: distanceM, route: route, travelDirection: travelDirection)
        return (c >= 38_500 && c <= 40_500) || (c >= 43_600 && c <= 48_600) || c >= 53_000
    }

    /// Lateral sign of the sea in travel-frame coordinates. The single
    /// running track flips its offset by direction the same way, so the
    /// sea stays on the same geographic side in both directions.
    private func seaSideSign(travelDirection: RegionalTravelDirection) -> Float {
        travelDirection == .up ? 1 : -1
    }

    private func buildTrack(
        route: RailwayRouteProfile,
        routeVariant: RegionalRouteVariant,
        travelDirection: RegionalTravelDirection
    ) {
        let distance = Float(route.distanceM)
        addSurfaceBox(parent: world, name: "formation-ground", size: SIMD3<Float>(1_400, 0.38, distance + 100), position: SIMD3<Float>(0, -0.28, -distance / 2), color: UIColor(red: 0.24, green: 0.28, blue: 0.24, alpha: 1), roughness: 1)

        // Distant backdrop planes repeated along the line, so the horizon
        // is never empty (BVE-style background). City skyline inside the
        // urban bands, mountain ranges elsewhere — real BVE routes swap
        // backgrounds per section the same way.
        var backdropMaterial = Self.texturedPBR(.white, roughness: 1, textureName: "backdrop_mountains")
        backdropMaterial.faceCulling = .none
        var skylineMaterial = Self.texturedPBR(.white, roughness: 1, textureName: "backdrop_skyline")
        skylineMaterial.faceCulling = .none
        let backdropSegment: Float = 4_000
        let backdropCount = max(1, Int((distance / backdropSegment).rounded(.up)))
        for side in [-1, 1] {
            for i in 0..<backdropCount {
                let centerM = Double(backdropSegment) * (Double(i) + 0.5)
                let startM = Double(backdropSegment) * Double(i)
                let endM = Double(backdropSegment) * Double(i + 1)
                let isUrban = urbanBand(distanceM: centerM, route: route, routeVariant: routeVariant, travelDirection: travelDirection) > 0
                    || urbanBand(distanceM: startM, route: route, routeVariant: routeVariant, travelDirection: travelDirection) > 0
                    || urbanBand(distanceM: endM, route: route, routeVariant: routeVariant, travelDirection: travelDirection) > 0
                addBox(parent: world, name: "backdrop-\(isUrban ? "skyline" : "mountains")-\(side)-\(i)",
                       size: SIMD3<Float>(1, 110, backdropSegment),
                       position: SIMD3<Float>(Float(side) * 680, 40, -backdropSegment * (Float(i) + 0.5)),
                       material: isUrban ? skylineMaterial : backdropMaterial)
                // Mid-distance tree line (the forest texture that has
                // been bundled unused until now): a second, nearer
                // backdrop layer so the far view has depth instead of
                // one wall of mountains. Skipped in the city and on
                // the sea side of the coast, where it would stand in
                // the water.
                if !isUrban {
                    var forestMaterial = Self.texturedPBR(.white, roughness: 1, textureName: "scenery_mountain_forest")
                    forestMaterial.faceCulling = .none
                    let midSeaSign = seaSideSign(travelDirection: travelDirection)
                    if !(Float(side) == midSeaSign && isCoastal(distanceM: centerM, route: route, routeVariant: routeVariant, travelDirection: travelDirection)) {
                        addBox(parent: world, name: "forest-mid-\(side)-\(i)",
                               size: SIMD3<Float>(1, 24, backdropSegment),
                               position: SIMD3<Float>(Float(side) * 300, 9, -backdropSegment * (Float(i) + 0.5)),
                               material: forestMaterial)
                    }
                }
            }
        }

        // Photographic ground apron following the line over the flat far
        // slab: grass at real-world scale, asphalt inside the urban bands
        // so the towers stand on city ground.
        if samples.count > 1 {
            let apronOffsets = [Float](repeating: 0, count: samples.count)
            let grassApron = Self.texturedPBR(.white, roughness: 1, textureName: "scenery_grass")
            let cityApron = Self.texturedPBR(.white, roughness: 1, textureName: "scenery_asphalt", normalName: "normal_asphalt")
            var runStart = 0
            var runBand = urbanBand(distanceM: samples[0].distanceM, route: route, routeVariant: routeVariant, travelDirection: travelDirection)
            var runCoastal = isCoastal(distanceM: samples[0].distanceM, route: route, routeVariant: routeVariant, travelDirection: travelDirection)
            for i in 1...samples.count {
                let band = i < samples.count ? urbanBand(distanceM: samples[i].distanceM, route: route, routeVariant: routeVariant, travelDirection: travelDirection) : -1
                let coastal = i < samples.count ? isCoastal(distanceM: samples[i].distanceM, route: route, routeVariant: routeVariant, travelDirection: travelDirection) : false
                if band != runBand || (i < samples.count && coastal != runCoastal) {
                    let runEnd = min(i + 1, samples.count)
                    // Wide apron inland; on the coastal stretch keep the
                    // original width so the apron edge meets the beach
                    // instead of covering the sand and the near sea.
                    if let apron = ribbonEntity(name: "ground-apron-\(runStart)", width: runCoastal ? 46 : 150, y: -0.04, tileLength: 12,
                                                offsets: apronOffsets,
                                                material: runBand > 0 ? cityApron : grassApron,
                                                range: runStart..<runEnd, uTileLength: 12) {
                        world.addChild(apron)
                    }
                    runStart = i
                    runBand = band
                    runCoastal = coastal
                }
            }
        }

        // Far ground: textured fields out to the backdrop wall, in
        // ~3 km runs whose height steps gently (±1 m) so the land is
        // not one flat slab. The sea side of the coastal stretch is
        // skipped — that ground is beach and water.
        if samples.count > 1 {
            let farGrassMaterial = Self.texturedPBR(UIColor(red: 0.80, green: 0.84, blue: 0.76, alpha: 1), roughness: 1, textureName: "scenery_grass")
            let farCityMaterial = Self.texturedPBR(UIColor(red: 0.82, green: 0.82, blue: 0.84, alpha: 1), roughness: 1, textureName: "scenery_asphalt", normalName: "normal_asphalt")
            let farSeaSign = seaSideSign(travelDirection: travelDirection)
            for sideSign: Float in [-1, 1] {
                let farOffsets = samples.map { _ in sideSign * 375 }
                func farKey(_ i: Int) -> Int {
                    let band = urbanBand(distanceM: samples[i].distanceM, route: route, routeVariant: routeVariant, travelDirection: travelDirection) > 0 ? 1 : 0
                    let chunk = Int(samples[i].distanceM / 3_000)
                    let blocked = (sideSign == farSeaSign && isCoastal(distanceM: samples[i].distanceM, route: route, routeVariant: routeVariant, travelDirection: travelDirection)) ? 1 : 0
                    return band * 1_000_000 + chunk * 10 + blocked
                }
                var farRunStart = 0
                var farRunKey = farKey(0)
                for i in 1...samples.count {
                    let key = i < samples.count ? farKey(i) : -1
                    if key != farRunKey {
                        let farRunEnd = min(i + 1, samples.count)
                        let wasBlocked = farRunKey % 10 == 1
                        if !wasBlocked {
                            let chunk = (farRunKey / 10) % 100_000
                            let lift = Float(((chunk * 37 + (sideSign > 0 ? 11 : 5)) % 10)) / 10 * 0.95
                            if let far = ribbonEntity(name: "far-ground-\(sideSign > 0 ? "r" : "l")-\(farRunStart)", width: 600, y: 0.02 + lift, tileLength: 90,
                                                      offsets: farOffsets,
                                                      material: farRunKey >= 1_000_000 ? farCityMaterial : farGrassMaterial,
                                                      range: farRunStart..<farRunEnd, uTileLength: 90) {
                                world.addChild(far)
                            }
                        }
                        farRunStart = i
                        farRunKey = key
                    }
                }
            }
        }

        // Coastal stretch: a sand beach just outside the ground apron
        // and open sea beyond it, as ribbons over the coastal samples.
        // The far edge of the sea meets the backdrop wall, which then
        // reads as a distant shore across the water.
        if samples.count > 1 {
            let seaSign = seaSideSign(travelDirection: travelDirection)
            let beachOffsets = samples.map { _ in seaSign * 31 }
            let seaOffsets = samples.map { _ in seaSign * 369 }
            let beachMaterial = Self.pbr(UIColor(red: 0.76, green: 0.69, blue: 0.52, alpha: 1), roughness: 1)
            let seaMaterial = Self.texturedPBR(.white, roughness: 0.55, textureName: "scenery_sea")
            var runStart = 0
            var runCoastal = isCoastal(distanceM: samples[0].distanceM, route: route, routeVariant: routeVariant, travelDirection: travelDirection)
            for i in 1...samples.count {
                let coastal = i < samples.count ? isCoastal(distanceM: samples[i].distanceM, route: route, routeVariant: routeVariant, travelDirection: travelDirection) : false
                if coastal != runCoastal {
                    if runCoastal {
                        let runEnd = min(i + 1, samples.count)
                        if let beach = ribbonEntity(name: "beach-\(runStart)", width: 16, y: -0.03, tileLength: 12,
                                                    offsets: beachOffsets, material: beachMaterial, range: runStart..<runEnd) {
                            world.addChild(beach)
                        }
                        if let sea = ribbonEntity(name: "sea-\(runStart)", width: 660, y: -0.06, tileLength: 30,
                                                  offsets: seaOffsets, material: seaMaterial, range: runStart..<runEnd, uTileLength: 30) {
                            world.addChild(sea)
                        }
                    }
                    runStart = i
                    runCoastal = coastal
                }
            }
        }

        // One-piece trackbed ribbons (rails + sleepers + ballast in a
        // single texture whose rails sit at the exact gauge) per track.
        func offsetsFor(sample: RouteSample) -> [Float] {
            let isMainlineSection = travelDirection == .up ? sample.distanceM < 60_000 : sample.distanceM >= 8_000
            let hasPassingTrack = routeVariant == .mainline || (routeVariant == .throughBranch && isMainlineSection)
            return hasPassingTrack ? [-2.1, 2.1] : [travelDirection == .up ? -2.1 : 2.1]
        }
        var trackOffsetsSeen: [Float] = []
        for sample in samples {
            for o in offsetsFor(sample: sample) where !trackOffsetsSeen.contains(o) {
                trackOffsetsSeen.append(o)
            }
        }
        let trackbedMaterial = Self.texturedPBR(.white, roughness: 0.95, textureName: "scenery_trackbed", normalName: "normal_trackbed")
        for offset in trackOffsetsSeen {
            let offsets = samples.map { sample -> Float in
                let available = offsetsFor(sample: sample)
                return available.contains(offset) ? offset : available[0]
            }
            if let ribbon = ribbonEntity(name: "trackbed-\(offset)", width: 4.6, y: 0.18, tileLength: 5, offsets: offsets, material: trackbedMaterial) {
                world.addChild(ribbon)
            }
        }

        buildRailsAndShoulders(trackOffsetsSeen: trackOffsetsSeen, availableOffsets: offsetsFor)
        buildTracksideMarkers(route: route, routeVariant: routeVariant, travelDirection: travelDirection)

        let wallLandmarks = fictionalCorridorLandmarks(for: route)
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
                    // Rails are no longer boxes: buildRailsAndShoulders
                    // extrudes a true head/web/base profile along the
                    // line (see below).
                }
            }
            for (trackIndex, lateral) in trackOffsets.enumerated() {
                let x = sample.x + lateral * cos(sample.heading)
                let z = sample.z - lateral * sin(sample.heading)
                // Per-sleeper shade variation: real sleepers weather
                // unevenly, and a perfectly uniform row reads fake.
                let sleeperShade = 0.82 + Float((index * 37 + trackIndex * 11) % 5) * 0.09
                addSurfaceBox(parent: world, name: "sleeper-\(index)-\(trackIndex)", size: SIMD3<Float>(2.55, 0.13, 0.26), position: SIMD3<Float>(x, 0.105, z), color: UIColor(red: 0.34 * CGFloat(sleeperShade), green: 0.27 * CGFloat(sleeperShade), blue: 0.19 * CGFloat(sleeperShade), alpha: 1), roughness: 0.88, orientation: trackOrientation)
            }

            // Continuous lineside walls (noise barriers), laid as
            // per-segment slabs the way BVE routes repeat WallL/WallR:
            // they enclose the corridor and separate it from the parallel
            // roads and houses. Mainline sections only, kept clear of
            // stations and crossings.
            if index.isMultiple(of: 3), hasPassingTrack, !corridorReserved(at: sample.distanceM, landmarks: wallLandmarks) {
                let band = urbanBand(distanceM: sample.distanceM, route: route, routeVariant: routeVariant, travelDirection: travelDirection)
                let wallHeight: Float = band == 2 ? 2.6 : band == 1 ? 2.2 : 1.8
                let wallMaterial = (index / 3).isMultiple(of: 2) ? concreteMaterial : poleMaterial
                for side in [-1.0, 1.0] {
                    let wallLateral = Float(side) * 5.6
                    let wallX = sample.x + wallLateral * cos(sample.heading)
                    let wallZ = sample.z - wallLateral * sin(sample.heading)
                    let wall = addBox(parent: world, name: "lineside-wall-\(index)-\(Int(side))",
                                      size: SIMD3<Float>(0.18, wallHeight, segmentLength + 0.3),
                                      position: SIMD3<Float>(wallX, wallHeight / 2, wallZ),
                                      material: wallMaterial)
                    wall.orientation = trackOrientation
                }
            }
        }
    }

    /// Trackside colour-light signals at the canonical 3 km spacing on
    /// the main line (the route data carries its signals every 3 km,
    /// sighted on the left of the running track). Each head defaults to
    /// green; the signal protecting the block ahead is re-lit from the
    /// model's actual reading in updateSignalAspect.
    private func buildSignals(route: RailwayRouteProfile, routeVariant: RegionalRouteVariant, travelDirection: RegionalTravelDirection) {
        guard routeVariant == .mainline || routeVariant == .throughBranch else { return }
        let lateral: Float = travelDirection == .up ? -3.7 : 3.7
        let headMaterial = Self.pbr(UIColor(red: 0.05, green: 0.05, blue: 0.06, alpha: 1), metallic: 0.3, roughness: 0.6)
        for target in stride(from: 0.0, to: 60_000.0, by: 3_000.0) {
            var best: RouteSample?
            var bestDelta = Double.greatestFiniteMagnitude
            for sample in samples where isMainlineSection(distanceM: sample.distanceM, routeVariant: routeVariant, travelDirection: travelDirection) {
                let delta = abs(chainageFromCenter(distanceM: sample.distanceM, route: route, travelDirection: travelDirection) - target)
                if delta < bestDelta {
                    bestDelta = delta
                    best = sample
                }
            }
            guard let sample = best else { continue }
            let yaw = simd_quatf(angle: sample.heading, axis: SIMD3<Float>(0, 1, 0))
            let base = routeOffsetPoint(sample, lateral: lateral)
            addBox(parent: world, name: "signal-post-\(Int(target))", size: SIMD3<Float>(0.14, 3.6, 0.14),
                   position: SIMD3<Float>(base.x, 1.8, base.z), material: poleMaterial, orientation: yaw)
            addBox(parent: world, name: "signal-head-\(Int(target))", size: SIMD3<Float>(0.36, 1.1, 0.24),
                   position: SIMD3<Float>(base.x, 3.9, base.z), material: headMaterial, orientation: yaw)
            // Lamps sit on the face turned toward the approaching train
            // (opposite the direction of travel), red over yellow over
            // green.
            let forward = SIMD3<Float>(sin(sample.heading), 0, -cos(sample.heading))
            let lampX = base.x - forward.x * 0.16
            let lampZ = base.z - forward.z * 0.16
            var lamps: [ModelEntity] = []
            for lampY in [4.25, 3.9, 3.55] {
                let lamp = ModelEntity(mesh: MeshResource.generateBox(size: SIMD3<Float>(0.17, 0.17, 0.05)),
                                       materials: [signalDarkLampMaterial])
                lamp.position = SIMD3<Float>(lampX, Float(lampY), lampZ)
                lamp.orientation = yaw
                world.addChild(lamp)
                lamps.append(lamp)
            }
            signalLampHeads[sample.distanceM] = lamps
            applyAspect(lamps, aspect: .green)
        }
    }

    private func applyAspect(_ lamps: [ModelEntity], aspect: ThreeAspectSignal) {
        guard lamps.count == 3 else { return }
        lamps[0].model?.materials = [aspect == .red ? signalRedMaterial : signalDarkLampMaterial]
        lamps[1].model?.materials = [aspect == .yellow ? signalYellowMaterial : signalDarkLampMaterial]
        lamps[2].model?.materials = [aspect == .green ? signalGreenMaterial : signalDarkLampMaterial]
    }

    /// Lights the placed signal nearest the model's current reading
    /// with that reading's aspect; the previously lit signal returns to
    /// the default green.
    private func updateSignalAspect(positionM: Double?, aspect: ThreeAspectSignal?) {
        var matched: Double?
        if let positionM {
            matched = signalLampHeads.keys.min { abs($0 - positionM) < abs($1 - positionM) }
            if let candidate = matched, abs(candidate - positionM) > 250 {
                matched = nil
            }
        }
        if matched == dynamicSignalDistance && aspect == dynamicSignalAspect { return }
        if let previous = dynamicSignalDistance, let lamps = signalLampHeads[previous] {
            applyAspect(lamps, aspect: .green)
        }
        dynamicSignalDistance = matched
        dynamicSignalAspect = aspect
        if let matched, let lamps = signalLampHeads[matched], let aspect {
            applyAspect(lamps, aspect: aspect)
        }
    }

    /// Visual tunnel shells over the sections the physics profile marks
    /// as tunnels (tunnelResistanceMultiplier > 1): side walls and a roof
    /// slab in dark concrete, with a three-piece portal frame at each
    /// end. Built with addBox (not surface boxes) so the weather pass
    /// never repaints them. The 42.1-43.6 km tunnel's exit portal is
    /// where the coastal reveal window begins.
    private func buildTunnels(route: RailwayRouteProfile) {
        var ranges: [(start: Double, end: Double)] = []
        for section in route.sections where section.tunnelResistanceMultiplier > 1 {
            if let last = ranges.last, section.startM <= last.end + 0.5 {
                ranges[ranges.count - 1].end = section.endM
            } else {
                ranges.append((section.startM, section.endM))
            }
        }
        guard !ranges.isEmpty else { return }
        let tunnelMaterial = Self.texturedPBR(UIColor(red: 0.32, green: 0.33, blue: 0.34, alpha: 1), roughness: 0.95, textureName: "scenery_concrete", normalName: "normal_concrete")
        for range in ranges {
            let inside = samples.indices.filter { samples[$0].distanceM >= range.start && samples[$0].distanceM <= range.end }
            guard inside.count > 1 else { continue }
            for (offsetIndex, index) in inside.enumerated() where offsetIndex.isMultiple(of: 2) {
                let sample = samples[index]
                let yaw = simd_quatf(angle: sample.heading, axis: SIMD3<Float>(0, 1, 0))
                let nextIndex = inside[min(offsetIndex + 2, inside.count - 1)]
                let length = max(Float(samples[nextIndex].distanceM - sample.distanceM), 8)
                for side in [-1.0, 1.0] {
                    let lateral = Float(side) * 5.6
                    let x = sample.x + lateral * cos(sample.heading)
                    let z = sample.z - lateral * sin(sample.heading)
                    addBox(parent: world, name: "tunnel-wall-\(Int(range.start))-\(index)-\(Int(side))",
                           size: SIMD3<Float>(0.5, 6.2, length), position: SIMD3<Float>(x, 3.1, z),
                           material: tunnelMaterial, orientation: yaw)
                }
                addBox(parent: world, name: "tunnel-roof-\(Int(range.start))-\(index)",
                       size: SIMD3<Float>(11.7, 0.5, length), position: SIMD3<Float>(sample.x, 6.45, sample.z),
                       material: tunnelMaterial, orientation: yaw)
            }
            // Portal frames at both ends: two pillars and a lintel,
            // leaving the bore opening clear.
            for boundary in [range.start, range.end] {
                let portalSample = sample(at: boundary)
                let yaw = simd_quatf(angle: portalSample.heading, axis: SIMD3<Float>(0, 1, 0))
                for side in [-1.0, 1.0] {
                    let lateral = Float(side) * 7.9
                    let x = portalSample.x + lateral * cos(portalSample.heading)
                    let z = portalSample.z - lateral * sin(portalSample.heading)
                    addBox(parent: world, name: "tunnel-portal-\(Int(boundary))-\(Int(side))",
                           size: SIMD3<Float>(4.6, 9.2, 0.9), position: SIMD3<Float>(x, 4.6, z),
                           material: concreteMaterial, orientation: yaw)
                }
                addBox(parent: world, name: "tunnel-portal-lintel-\(Int(boundary))",
                       size: SIMD3<Float>(20.4, 3.0, 0.9), position: SIMD3<Float>(portalSample.x, 7.7, portalSample.z),
                       material: concreteMaterial, orientation: yaw)
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

    /// One city tower built from stacked facade segments (each segment
    /// shows the office-facade texture once, so windows keep a realistic
    /// ~3 m floor height instead of stretching over the whole tower).
    private func addTower(at distance: Double, side: Float, seed: Int, band: Int, route: RailwayRouteProfile, routeVariant: RegionalRouteVariant, travelDirection: RegionalTravelDirection, lateralOverride: Float? = nil, heightScale: Float = 1) {
        let sample = sample(at: distance)
        let lateral: Float = lateralOverride ?? ((band == 2 ? 12.5 : 13.5) + Float(seed % 3) * 1.4)
        let width: Float = 11 + Float((seed / 3) % 4) * 1.4
        let depth: Float = 10 + Float((seed / 7) % 3) * 1.6
        var height: Float = 15 + Float((seed * 29) % 100) / 100 * (band == 2 ? 30 : 15)
        if band == 2 {
            let c = chainageFromCenter(distanceM: distance, route: route, travelDirection: travelDirection)
            height *= Float(1.05 - (c / 4_200) * 0.45)
            height = max(15, height)
        }
        height *= heightScale
        let segments = max(1, Int((height / 15).rounded()))
        let segmentHeight = height / Float(segments)
        let offset = side * lateral
        let x = sample.x + offset * cos(sample.heading)
        let z = sample.z - offset * sin(sample.heading)
        let orientation = simd_quatf(angle: sample.heading, axis: SIMD3<Float>(0, 1, 0))
        // Apartment facades only on mid-rise towers; tall ones are
        // office or glass.
        let materialPool = height > 30 ? Array(officeMaterials.prefix(4)) : officeMaterials
        let material = materialPool[abs(seed) % materialPool.count]
        for segment in 0..<segments {
            let box = addBox(parent: world, name: "office-tower-\(seed)-\(segment)",
                             size: SIMD3<Float>(width, segmentHeight, depth),
                             position: SIMD3<Float>(x, segmentHeight * (Float(segment) + 0.5), z),
                             material: material)
            box.orientation = orientation
        }
        let roof = addBox(parent: world, name: "office-roof-\(seed)",
                          size: SIMD3<Float>(width + 0.4, 0.3, depth + 0.4),
                          position: SIMD3<Float>(x, height + 0.15, z),
                          material: roofMaterials[abs(seed) % roofMaterials.count])
        roof.orientation = orientation
        // Rooftop block (stair tower / tank) on some towers so the
        // silhouette is not a plain card edge.
        if seed % 2 == 0 {
            let block = addBox(parent: world, name: "office-rooftop-\(seed)",
                               size: SIMD3<Float>(width * 0.34, 2.3, depth * 0.4),
                               position: SIMD3<Float>(x, height + 1.15, z),
                               material: concreteMaterial)
            block.orientation = orientation
        }
        // Slightly proud ground-floor band: hides the wall/ground seam
        // and reads as a storefront/podium base.
        let baseBand = addBox(parent: world, name: "office-base-\(seed)",
                              size: SIMD3<Float>(width + 0.18, 3.1, depth + 0.18),
                              position: SIMD3<Float>(x, 1.55, z),
                              material: band == 2 ? glassMaterial : concreteMaterial)
        baseBand.orientation = orientation
    }

    private func buildSuburb(route: RailwayRouteProfile, routeVariant: RegionalRouteVariant, travelDirection: RegionalTravelDirection) {
        let sceneryMaterials = buildingMaterials
        let landmarks = fictionalCorridorLandmarks(for: route)
        var index = 0
        var urbanIndex = 0
        var foliageCount = 0
        let buildingLimit = max(1, renderQualitySettings.sceneryInstanceLimit * 3 / 4)
        let buildingStep = max(45, (route.distanceM - 114) / Double(buildingLimit))
        var distance = 34.0
        while distance < route.distanceM - 80 {
            let band = urbanBand(distanceM: distance, route: route, routeVariant: routeVariant, travelDirection: travelDirection)
            if band > 0 {
                if urbanIndex < 720 && !corridorReserved(at: distance, landmarks: landmarks) {
                    addTower(at: distance, side: 1, seed: urbanIndex * 2, band: band, route: route, routeVariant: routeVariant, travelDirection: travelDirection)
                    addTower(at: distance + 9, side: -1, seed: urbanIndex * 2 + 1, band: band, route: route, routeVariant: routeVariant, travelDirection: travelDirection)
                    // Second row of towers behind the first, so the
                    // skyline has depth instead of a single line of
                    // facades with gaps of empty sky between them.
                    if urbanIndex.isMultiple(of: 2) {
                        addTower(at: distance + 4.5, side: urbanIndex % 4 == 0 ? 1 : -1, seed: urbanIndex * 7 + 3, band: band, route: route, routeVariant: routeVariant, travelDirection: travelDirection, lateralOverride: 30 + Float(urbanIndex % 3) * 2.5, heightScale: 1.2)
                    }
                }
                urbanIndex += 1
                distance += band == 2 ? 27 : 36
                continue
            }
            if corridorReserved(at: distance, landmarks: landmarks) {
                distance += buildingStep
                continue
            }
            if index >= buildingLimit {
                distance += buildingStep
                continue
            }
            let sample = sample(at: distance)
            let side = index.isMultiple(of: 2) ? 1.0 : -1.0
            let sign = Float(side)
            // No houses on the sea side of the coastal stretch: that
            // ground is beach and water.
            if isCoastal(distanceM: distance, route: route, routeVariant: routeVariant, travelDirection: travelDirection),
               sign == seaSideSign(travelDirection: travelDirection) {
                index += 1
                distance += buildingStep
                continue
            }
            let lateral = 9.0 + Float((index * 13) % 4) * 1.7
            let shed = index.isMultiple(of: 4)
            let width = (shed ? 7.2 : 4.6) + Float((index * 7) % 4) * 0.75
            let depth = (shed ? 4.2 : 5.4) + Float((index * 5) % 4) * 0.8
            let height = (shed ? 2.6 : 3.6) + Float((index * 11) % 6) * 0.65
            let offset = sign * lateral
            let x = sample.x + offset * cos(sample.heading)
            let z = sample.z - offset * sin(sample.heading)
            // Every third house wears the full photo facade; its windows
            // and door are painted in, so the separate boxes are skipped.
            let useFacadeTexture = !shed && index % 3 == 2
            let bodyMaterial = useFacadeTexture ? houseFacadeMaterial : sceneryMaterials[index % sceneryMaterials.count]
            let building = addBox(parent: world, name: shed ? "fictional-shed-\(index)" : "fictional-home-\(index)", size: SIMD3<Float>(width, height, depth), position: SIMD3<Float>(x, height / 2, z), material: bodyMaterial)
            building.orientation = simd_quatf(angle: sample.heading, axis: SIMD3<Float>(0, 1, 0))

            if !index.isMultiple(of: 3) {
                let roof = addBox(parent: world, name: "roof-\(index)", size: SIMD3<Float>(width + 0.45, 0.24, depth + 0.35), position: SIMD3<Float>(x, height + 0.14, z), material: roofMaterials[index % roofMaterials.count], orientation: simd_quatf(angle: sample.heading, axis: SIMD3<Float>(0, 1, 0)))
                roof.orientation = roof.orientation * simd_quatf(angle: Float(index.isMultiple(of: 2) ? 0.04 : -0.04), axis: SIMD3<Float>(0, 0, 1))
            } else {
                let balconySample = self.sample(at: distance - Double(depth * 0.52))
                let balconyPoint = routeOffsetPoint(balconySample, lateral: offset)
                let balcony = addBox(parent: world, name: "balcony-\(index)", size: SIMD3<Float>(width + 0.35, 0.12, 0.35), position: SIMD3<Float>(balconyPoint.x, height * 0.56, balconyPoint.z), material: concreteMaterial)
                balcony.orientation = simd_quatf(angle: sample.heading, axis: SIMD3<Float>(0, 1, 0))
            }

            if !useFacadeTexture {
                let facadeLateral = offset - sign * (width / 2 + 0.035)
                for window in 0..<2 {
                    let windowSample = self.sample(at: distance + Double((Float(window) - 0.5) * depth * 0.42))
                    let windowPoint = routeOffsetPoint(windowSample, lateral: facadeLateral)
                    let pane = addBox(parent: world, name: "window-\(index)-\(window)", size: SIMD3<Float>(0.07, 0.72, 0.78), position: SIMD3<Float>(windowPoint.x, min(height * 0.72, 2.45), windowPoint.z), material: glassMaterial)
                    pane.orientation = simd_quatf(angle: sample.heading, axis: SIMD3<Float>(0, 1, 0))
                }
                let doorPoint = routeOffsetPoint(sample, lateral: facadeLateral)
                let door = addBox(parent: world, name: "door-\(index)", size: SIMD3<Float>(0.07, 1.8, 0.78), position: SIMD3<Float>(doorPoint.x, 0.95, doorPoint.z), material: roofMaterials[(index + 1) % roofMaterials.count])
                door.orientation = simd_quatf(angle: sample.heading, axis: SIMD3<Float>(0, 1, 0))
            }

            if index.isMultiple(of: 2), foliageCount < renderQualitySettings.foliageInstanceLimit {
                let treeSample = self.sample(at: distance + 5)
                let treePoint = routeOffsetPoint(treeSample, lateral: offset + sign * width * 0.65)
                addTree(parent: world, name: "tree-\(index)", x: treePoint.x, z: treePoint.z, height: 3.1 + Float(index % 4) * 0.35, material: foliageMaterials[index % foliageMaterials.count])
                foliageCount += 1
            }
            if index.isMultiple(of: 5) {
                let poleSample = self.sample(at: distance + 7)
                let polePoint = routeOffsetPoint(poleSample, lateral: offset + sign * 4.2)
                addBox(parent: world, name: "utility-pole-\(index)", size: SIMD3<Float>(0.13, 5.2, 0.13), position: SIMD3<Float>(polePoint.x, 2.55, polePoint.z), material: poleMaterial)
            }
            // A second, simpler house row further back on the opposite
            // side, so the suburb reads as a settled area with depth
            // rather than a single line of houses along the fence.
            if index.isMultiple(of: 2) {
                let farDistance = distance + 22
                let farSign = -sign
                let farOnSeaSide = isCoastal(distanceM: farDistance, route: route, routeVariant: routeVariant, travelDirection: travelDirection)
                    && farSign == seaSideSign(travelDirection: travelDirection)
                if !farOnSeaSide && !corridorReserved(at: farDistance, landmarks: landmarks) {
                    let farSample = self.sample(at: farDistance)
                    let farLateral = farSign * (23 + Float((index * 7) % 6))
                    let fx = farSample.x + farLateral * cos(farSample.heading)
                    let fz = farSample.z - farLateral * sin(farSample.heading)
                    let fw = 5.2 + Float((index * 5) % 4) * 0.8
                    let fh = 3.4 + Float((index * 11) % 5) * 0.6
                    let fd = 5.6 + Float((index * 3) % 4) * 0.7
                    let farOrientation = simd_quatf(angle: farSample.heading, axis: SIMD3<Float>(0, 1, 0))
                    let farHouse = addBox(parent: world, name: "fictional-home-far-\(index)", size: SIMD3<Float>(fw, fh, fd), position: SIMD3<Float>(fx, fh / 2, fz), material: sceneryMaterials[(index + 2) % sceneryMaterials.count])
                    farHouse.orientation = farOrientation
                    let farRoof = addBox(parent: world, name: "roof-far-\(index)", size: SIMD3<Float>(fw + 0.45, 0.24, fd + 0.35), position: SIMD3<Float>(fx, fh + 0.14, fz), material: roofMaterials[(index + 1) % roofMaterials.count])
                    farRoof.orientation = farOrientation
                }
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
            addBox(parent: world, name: "tactile-strip-\(Int(side))", size: SIMD3<Float>(0.3, 0.035, 115), position: SIMD3<Float>(x - Float(side) * 0.8 * cos(sample.heading), 0.50, z + Float(side) * 0.8 * sin(sample.heading)), material: tactileMaterial, orientation: yaw)
        }
        let signSample = self.sample(at: max(route.stopMarkerM - 42, 0))
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
            // Bogies: without them the cars float above the rails.
            for bogie in [-1.0, 1.0] {
                addBox(parent: train, name: "bogie-\(carIndex)-\(Int(bogie))", size: SIMD3<Float>(2.0, 0.55, 2.6), position: SIMD3<Float>(0, 0.48, centerZ + Float(bogie) * 6.4), material: poleMaterial)
            }
        }
        // Pantograph on the second car: base, crossed arms, contact strip.
        let pantographZ: Float = 27.5
        addBox(parent: train, name: "pantograph-base", size: SIMD3<Float>(1.6, 0.08, 1.2), position: SIMD3<Float>(0, 3.60, pantographZ), material: poleMaterial)
        for armSide in [-1.0, 1.0] {
            let arm = addBox(parent: train, name: "pantograph-arm-\(Int(armSide))", size: SIMD3<Float>(0.06, 1.15, 0.06), position: SIMD3<Float>(0, 4.05, pantographZ + Float(armSide) * 0.35), material: poleMaterial)
            arm.orientation = simd_quatf(angle: -Float(armSide) * 0.62, axis: SIMD3<Float>(1, 0, 0))
        }
        addBox(parent: train, name: "pantograph-strip", size: SIMD3<Float>(1.8, 0.05, 0.32), position: SIMD3<Float>(0, 4.52, pantographZ), material: poleMaterial)
        // Cab ends: window band, destination display, headlights.
        let displayMaterial = Self.pbr(UIColor(red: 0.65, green: 0.85, blue: 0.90, alpha: 1), metallic: 0.1, roughness: 0.4)
        for endZ: Float in [-0.54, 74.54] {
            addBox(parent: train, name: "cab-window-\(Int(endZ))", size: SIMD3<Float>(2.4, 0.85, 0.07), position: SIMD3<Float>(0, 2.62, endZ), material: glassMaterial)
            addBox(parent: train, name: "destination-\(Int(endZ))", size: SIMD3<Float>(0.95, 0.3, 0.06), position: SIMD3<Float>(0, 3.28, endZ), material: displayMaterial)
            for lightSide in [-1.0, 1.0] {
                addBox(parent: train, name: "headlight-\(Int(endZ))-\(Int(lightSide))", size: SIMD3<Float>(0.28, 0.22, 0.06), position: SIMD3<Float>(Float(lightSide) * 0.95, 1.15, endZ), material: displayMaterial)
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
        // Outside the sampled range, extrapolate along the end sample's
        // heading instead of clamping: at the route origin the lead car
        // legitimately extends behind chainage 0, and clamping would
        // stack the whole consist onto the first sample.
        if let first = samples.first, distanceM < first.distanceM {
            let delta = Float(distanceM - first.distanceM)
            return RouteSample(
                distanceM: distanceM,
                x: first.x + sin(first.heading) * delta,
                z: first.z - cos(first.heading) * delta,
                heading: first.heading,
                bankRadians: first.bankRadians
            )
        }
        guard let upperIndex = samples.firstIndex(where: { $0.distanceM >= distanceM }) else {
            if let last = samples.last {
                let delta = Float(distanceM - last.distanceM)
                return RouteSample(
                    distanceM: distanceM,
                    x: last.x + sin(last.heading) * delta,
                    z: last.z - cos(last.heading) * delta,
                    heading: last.heading,
                    bankRadians: last.bankRadians
                )
            }
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

    /// Photographic-texture material: the bundled scenery texture carries
    /// the surface detail and the color acts as a multiply tint. Falls back
    /// to the flat color when the texture cannot be loaded.
    static func texturedPBR(_ color: UIColor, metallic: Float = 0.0, roughness: Float, textureName: String, normalName: String? = nil) -> PhysicallyBasedMaterial {
        var material = PhysicallyBasedMaterial()
        if let texture = SceneTextureProvider.texture(named: textureName) {
            material.baseColor = .init(tint: color, texture: .init(texture))
        } else {
            material.baseColor = .init(tint: color, texture: nil)
        }
        // A normal map gives flat texture walls real relief (window
        // frames, balcony rails) under the scene lighting, which is what
        // keeps them from reading as printed paper.
        if let normalName, let normal = SceneTextureProvider.texture(named: normalName) {
            material.normal = .init(texture: .init(normal))
        }
        material.metallic = .init(floatLiteral: metallic)
        material.roughness = .init(floatLiteral: roughness)
        return material
    }

    /// A textured strip that follows the route samples. The V coordinate
    /// runs along the line in tileLength-metre repeats, so the texture
    /// keeps its real-world scale over any distance (BVE-style trackbed
    /// and ground aprons without UV stretching).
    /// One station of a profile extrusion: the track centre at ground
    /// level plus the bank-rotated local axes (x = lateral, y = up).
    private struct ProfileStation {
        var center: SIMD3<Float>
        var xAxis: SIMD3<Float>
        var yAxis: SIMD3<Float>
        var distanceM: Double
    }

    private func profileStation(at distanceM: Double, trackLateral: Float) -> ProfileStation {
        let s = sample(at: distanceM)
        let h = s.heading
        let bank = s.bankRadians
        let center = SIMD3<Float>(s.x + trackLateral * cos(h), 0, s.z - trackLateral * sin(h))
        let xAxis = SIMD3<Float>(cos(bank) * cos(h), -sin(bank), -cos(bank) * sin(h))
        let yAxis = SIMD3<Float>(sin(bank) * cos(h), cos(bank), -sin(bank) * sin(h))
        return ProfileStation(center: center, xAxis: xAxis, yAxis: yAxis, distanceM: distanceM)
    }

    /// Extrudes a 2D profile (lateral, height) along profile stations
    /// into one mesh. Used for the rail cross-section (closed) and the
    /// ballast shoulders (open, textured).
    private func profileStripEntity(name: String, stations: [ProfileStation], profile: [(x: Float, y: Float)], closed: Bool, material: PhysicallyBasedMaterial, uvVTileLength: Float? = nil) -> ModelEntity? {
        guard stations.count > 1, profile.count > 1 else { return nil }
        let cols = profile.count
        var positions: [SIMD3<Float>] = []
        var normals: [SIMD3<Float>] = []
        var uvs: [SIMD2<Float>] = []
        var indices: [UInt32] = []
        positions.reserveCapacity(stations.count * cols)
        // Cumulative profile length, for texture u along the profile.
        var profileU: [Float] = [0]
        for j in 1..<cols {
            let dx = profile[j].x - profile[j - 1].x
            let dy = profile[j].y - profile[j - 1].y
            profileU.append(profileU[j - 1] + sqrt(dx * dx + dy * dy))
        }
        for station in stations {
            let tangent = -simd_cross(station.xAxis, station.yAxis)
            for j in 0..<cols {
                let p = profile[j]
                positions.append(station.center + p.x * station.xAxis + p.y * station.yAxis)
                let next = profile[closed ? (j + 1) % cols : min(j + 1, cols - 1)]
                let edge = (next.x - p.x) * station.xAxis + (next.y - p.y) * station.yAxis
                var normal = simd_cross(tangent, edge)
                if simd_length(normal) < 1e-6 { normal = SIMD3<Float>(0, 1, 0) }
                normals.append(simd_normalize(normal))
                if let uvVTileLength {
                    uvs.append(SIMD2<Float>(profileU[j], Float(station.distanceM) / uvVTileLength))
                }
            }
        }
        let edgeCount = closed ? cols : cols - 1
        for i in 0..<(stations.count - 1) {
            for j in 0..<edgeCount {
                let jNext = (j + 1) % cols
                let a = UInt32(i * cols + j)
                let b = UInt32(i * cols + jNext)
                let c = UInt32((i + 1) * cols + j)
                let d = UInt32((i + 1) * cols + jNext)
                indices.append(contentsOf: [a, c, b, b, c, d])
            }
        }
        var descriptor = MeshDescriptor(name: name)
        descriptor.positions = MeshBuffers.Positions(positions)
        descriptor.normals = MeshBuffers.Normals(normals)
        if uvVTileLength != nil {
            descriptor.textureCoordinates = MeshBuffers.TextureCoordinates(uvs)
        }
        descriptor.primitives = .triangles(indices)
        guard let mesh = try? MeshResource.generate(from: [descriptor]) else { return nil }
        var material = material
        material.faceCulling = .none
        return ModelEntity(mesh: mesh, materials: [material])
    }

    /// Rails with a real cross-section (base, web, head) plus a
    /// polished running band on the head, and sloped ballast shoulders
    /// either side of the flat trackbed ribbon. Built in ~600 m runs
    /// per rail, following heading and cant from the route samples —
    /// the same frames the train itself rides on.
    private func buildRailsAndShoulders(trackOffsetsSeen: [Float], availableOffsets: (RouteSample) -> [Float]) {
        guard let first = samples.first, let last = samples.last else { return }
        let railSteel = Self.pbr(UIColor(red: 0.52, green: 0.57, blue: 0.60, alpha: 1), metallic: 0.85, roughness: 0.36)
        let runningBand = Self.pbr(UIColor(red: 0.78, green: 0.82, blue: 0.85, alpha: 1), metallic: 0.95, roughness: 0.12)
        let shoulderMaterial = Self.texturedPBR(.white, roughness: 1, textureName: "scenery_ballast", normalName: "normal_ballast")
        // 60 kg/m rail outline, base at sleeper-top height. Heights
        // are absolute (profile y), widths relative to the rail centre.
        let railProfile: [(x: Float, y: Float)] = [
            (-0.075, 0.145), (0.075, 0.145), (0.075, 0.175), (0.018, 0.185),
            (0.018, 0.255), (0.037, 0.265), (0.037, 0.305), (-0.037, 0.305),
            (-0.037, 0.265), (-0.018, 0.255), (-0.018, 0.185), (-0.075, 0.175)
        ]
        let bandProfile: [(x: Float, y: Float)] = [(-0.026, 0.3065), (0.026, 0.3065)]
        let shoulderLeft: [(x: Float, y: Float)] = [(-2.65, 0.03), (-1.72, 0.165)]
        let shoulderRight: [(x: Float, y: Float)] = [(1.72, 0.165), (2.65, 0.03)]
        let step = 10.5
        for trackOffset in trackOffsetsSeen {
            var run: [ProfileStation] = []
            var runIndex = 0
            func flushRun() {
                guard run.count > 1 else { run = []; return }
                for side: Float in [-0.72, 0.72] {
                    let profile = railProfile.map { (x: $0.x + side, y: $0.y) }
                    if let rail = profileStripEntity(name: "rail-profile-\(trackOffset)-\(side)-\(runIndex)", stations: run, profile: profile, closed: true, material: railSteel) {
                        world.addChild(rail)
                    }
                    let band = bandProfile.map { (x: $0.x + side, y: $0.y) }
                    if let bandEntity = profileStripEntity(name: "rail-band-\(trackOffset)-\(side)-\(runIndex)", stations: run, profile: band, closed: false, material: runningBand) {
                        world.addChild(bandEntity)
                    }
                }
                if let left = profileStripEntity(name: "ballast-shoulder-l-\(trackOffset)-\(runIndex)", stations: run, profile: shoulderLeft, closed: false, material: shoulderMaterial, uvVTileLength: 6) {
                    world.addChild(left)
                }
                if let right = profileStripEntity(name: "ballast-shoulder-r-\(trackOffset)-\(runIndex)", stations: run, profile: shoulderRight, closed: false, material: shoulderMaterial, uvVTileLength: 6) {
                    world.addChild(right)
                }
                runIndex += 1
                run = []
            }
            var d = first.distanceM
            while d <= last.distanceM {
                let available = availableOffsets(sample(at: d))
                if available.contains(trackOffset) {
                    let station = profileStation(at: d, trackLateral: trackOffset)
                    if let previous = run.last, station.distanceM - previous.distanceM > 600 {
                        let bridge = previous
                        flushRun()
                        run = [bridge]
                    }
                    run.append(station)
                } else {
                    flushRun()
                }
                d += step
            }
            flushRun()
        }
    }

    /// Trackside furniture that sells the railway at a glance:
    /// kilometre posts every 1,000 m and ATS balises (ground coils)
    /// between the running rails just before each signal.
    private func buildTracksideMarkers(route: RailwayRouteProfile, routeVariant: RegionalRouteVariant, travelDirection: RegionalTravelDirection) {
        let isMainlineKind = routeVariant == .mainline || routeVariant == .throughBranch
        func matchValue(_ sample: RouteSample) -> Double {
            if isMainlineKind {
                return chainageFromCenter(distanceM: sample.distanceM, route: route, travelDirection: travelDirection)
            }
            return sample.distanceM
        }
        func bestSample(for target: Double, mainlineOnly: Bool) -> RouteSample? {
            var best: RouteSample?
            var bestDelta = Double.greatestFiniteMagnitude
            for sample in samples {
                if mainlineOnly && !isMainlineSection(distanceM: sample.distanceM, routeVariant: routeVariant, travelDirection: travelDirection) { continue }
                let delta = abs(matchValue(sample) - target)
                if delta < bestDelta {
                    bestDelta = delta
                    best = sample
                }
            }
            return best
        }
        // Kilometre posts on the left of the running direction.
        let postLateral: Float = travelDirection == .up ? -4.6 : 4.6
        let limit = isMainlineKind ? 60_000.0 : route.distanceM
        let markerLandmarks = fictionalCorridorLandmarks(for: route)
        var km = 1_000.0
        while km < limit {
            if let sample = bestSample(for: km, mainlineOnly: false), !corridorReserved(at: sample.distanceM, landmarks: markerLandmarks) {
                let yaw = simd_quatf(angle: sample.heading, axis: SIMD3<Float>(0, 1, 0))
                let base = routeOffsetPoint(sample, lateral: postLateral)
                addBox(parent: world, name: "km-post-\(Int(km))", size: SIMD3<Float>(0.12, 0.95, 0.12),
                       position: SIMD3<Float>(base.x, 0.48, base.z), material: concreteMaterial, orientation: yaw)
                addBox(parent: world, name: "km-post-cap-\(Int(km))", size: SIMD3<Float>(0.15, 0.2, 0.15),
                       position: SIMD3<Float>(base.x, 0.98, base.z), material: poleMaterial, orientation: yaw)
            }
            km += 1_000
        }
        // ATS balises on the running track before each signal.
        guard isMainlineKind else { return }
        let baliseMaterial = Self.pbr(UIColor(red: 0.80, green: 0.66, blue: 0.20, alpha: 1), metallic: 0.05, roughness: 0.7)
        let runningTrack: Float = travelDirection == .up ? -2.1 : 2.1
        for target in stride(from: 0.0, to: 60_000.0, by: 3_000.0) {
            for approach in [target - 30, target] {
                guard let sample = bestSample(for: approach, mainlineOnly: true) else { continue }
                let orientation = simd_quatf(angle: sample.heading, axis: SIMD3<Float>(0, 1, 0)) * simd_quatf(angle: -sample.bankRadians, axis: SIMD3<Float>(0, 0, 1))
                let center = routeOffsetPoint(sample, lateral: runningTrack)
                addBox(parent: world, name: "ats-balise-\(Int(approach))", size: SIMD3<Float>(0.34, 0.07, 0.55),
                       position: SIMD3<Float>(center.x, 0.22, center.z), material: baliseMaterial, orientation: orientation)
            }
        }
    }

    private func ribbonEntity(name: String, width: Float, y: Float, tileLength: Float, offsets: [Float], material: PhysicallyBasedMaterial, range: Range<Int>? = nil, uTileLength: Float? = nil) -> ModelEntity? {
        guard offsets.count == samples.count, samples.count > 1 else { return nil }
        let sampleRange = range ?? samples.indices
        guard sampleRange.count > 1 else { return nil }
        var positions: [SIMD3<Float>] = []
        var normals: [SIMD3<Float>] = []
        var uvs: [SIMD2<Float>] = []
        var indices: [UInt32] = []
        positions.reserveCapacity(sampleRange.count * 2)
        var vertexIndex = 0
        for i in sampleRange {
            let sample = samples[i]
            let lateral = offsets[i]
            let cx = sample.x + lateral * cos(sample.heading)
            let cz = sample.z - lateral * sin(sample.heading)
            let rx = cos(sample.heading)
            let rz = -sin(sample.heading)
            let half = width / 2
            positions.append(SIMD3<Float>(cx - rx * half, y, cz - rz * half))
            positions.append(SIMD3<Float>(cx + rx * half, y, cz + rz * half))
            normals.append(SIMD3<Float>(0, 1, 0))
            normals.append(SIMD3<Float>(0, 1, 0))
            let v = Float(sample.distanceM) / tileLength
            // Wide ribbons (the sea) tile across their width too, so the
            // texture keeps its scale in both directions instead of
            // stretching into streaks.
            let u0: Float
            let u1: Float
            if let uTileLength {
                let center = lateral / uTileLength
                u0 = center - half / uTileLength
                u1 = center + half / uTileLength
            } else {
                u0 = 0
                u1 = 1
            }
            uvs.append(SIMD2<Float>(u0, v))
            uvs.append(SIMD2<Float>(u1, v))
            if vertexIndex > 0 {
                let base = UInt32((vertexIndex - 1) * 2)
                indices.append(contentsOf: [base, base + 1, base + 2, base + 1, base + 3, base + 2])
            }
            vertexIndex += 1
        }
        var descriptor = MeshDescriptor(name: name)
        descriptor.positions = MeshBuffers.Positions(positions)
        descriptor.normals = MeshBuffers.Normals(normals)
        descriptor.textureCoordinates = MeshBuffers.TextureCoordinates(uvs)
        descriptor.primitives = .triangles(indices)
        guard let mesh = try? MeshResource.generate(from: [descriptor]) else { return nil }
        var material = material
        material.faceCulling = .none
        return ModelEntity(mesh: mesh, materials: [material])
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
