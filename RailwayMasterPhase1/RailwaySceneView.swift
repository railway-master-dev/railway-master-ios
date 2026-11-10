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
    var mainReservoirPressureKPa: Double = 690
    var brakeCylinderPressureKPa: Double = 0
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
                mainReservoirPressureKPa: mainReservoirPressureKPa,
                brakeCylinderPressureKPa: brakeCylinderPressureKPa,
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
    var mainReservoirPressureKPa: Double = 690
    var brakeCylinderPressureKPa: Double = 0
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
            mainReservoirPressureKPa: mainReservoirPressureKPa,
            brakeCylinderPressureKPa: brakeCylinderPressureKPa,
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
            mainReservoirPressureKPa: mainReservoirPressureKPa,
            brakeCylinderPressureKPa: brakeCylinderPressureKPa,
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
            (8, SIMD3(0.56, 0.66, 0.77)),
            (12, SIMD3(0.68, 0.76, 0.83)),
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
    private var skyDome: ModelEntity?
    private lazy var renderingCoordinator = RailwayRenderingCoordinator(applier: self)
    private var didBuild = false
    private var routeSignature = ""
    private var samples: [RouteSample] = []
    /// Ground level under the track, per sample (see
    /// `computeViaductGround`). In a viaduct zone it is the
    /// valley-floor datum (rolling minimum of the elevation); under
    /// stations and outside zones it is the track elevation; 300 m
    /// smooth tapers join the two, so the ground never steps. Ground
    /// -level scenery stands on this; track furniture stays on
    /// `elevationM`.
    private var viaductGround: [Float] = []
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
    private var cabNeedlePivots: [String: Entity] = [:]
    private var cabLampOverlays: [String: Entity] = [:]
    private var renderQualitySettings = RenderQualityResolver.resolve(profile: .balanced, thermalCondition: .nominal)
    private var precipitationEntities: [ModelEntity] = []
    private var precipitationKind: RenderingWeather?
    private var currentSample = RouteSample(distanceM: 0, x: 0, z: 0, heading: 0, bankRadians: 0, elevationM: 0)
    private var currentSimulationTime = 0.0
    private var previousRenderTime: Double?
    private var cameraWorldPosition = SIMD3<Float>(0, 0, 0)
    private var windVelocity = SIMD3<Float>(0, 0, 0)
    private var surfaceMaterialTargets: [SurfaceMaterialTarget] = []
    private var lastSurfaceMaterialKey: String?
    /// Shared mesh caches (quality26). Every addBox and every tree
    /// used to generate a unique MeshResource, and RealityKit
    /// streams meshes in per area as the camera moves, so unique
    /// meshes meant constant AssetLoad churn (the CI #238 device
    /// log was full of "Blocking engine queue waiting for
    /// AssetLoadRequest … PrimitiveBox …") and steady memory
    /// growth until the tour wedged after spot 8. Sizes are
    /// quantized before keying, so the whole line shares a bounded
    /// set of box, trunk and crown meshes.
    private var sharedBoxMeshes: [String: MeshResource] = [:]
    private var sharedTrunkMeshes: [String: MeshResource] = [:]
    private var sharedCrownMeshes: [String: MeshResource] = [:]
    private var sceneFidelityRoute: SceneChainageRoute?
    private var sceneFidelityAdapter = RailwayRealityKitSceneAdapter()
    private var sceneFidelityDensity = SceneDensityControls.preset(.balanced)
    private var currentCabDesk = FictionalCabAndSoundCatalog.fieldChopper
    private var lastSceneFidelityBuildChainage = Double.nan

    private let ballastMaterial = RailwaySceneWorld.texturedPBR(UIColor(red: 0.74, green: 0.68, blue: 0.62, alpha: 1), roughness: 0.96, textureName: "scenery_ballast", normalName: "normal_ballast")
    private let sleeperMaterial = RailwaySceneWorld.texturedPBR(UIColor(red: 0.72, green: 0.62, blue: 0.52, alpha: 1), roughness: 0.88, textureName: "scenery_timber")
    private let railMaterial = RailwaySceneWorld.pbr(UIColor(red: 0.48, green: 0.54, blue: 0.55, alpha: 1), metallic: 0.82, roughness: 0.27)
    private let concreteMaterial = RailwaySceneWorld.texturedPBR(.white, roughness: 0.87, textureName: "scenery_concrete", normalName: "normal_concrete")
    private let poleMaterial = RailwaySceneWorld.texturedPBR(UIColor(red: 0.55, green: 0.58, blue: 0.58, alpha: 1), metallic: 0.30, roughness: 0.55, textureName: "scenery_steel")
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
        RailwaySceneWorld.texturedPBR(UIColor(red: 0.90, green: 0.95, blue: 1.0, alpha: 1), metallic: 0.06, roughness: 0.7, textureName: "scenery_brick_cool"),
        // quality32: two more tones so neighbouring houses differ.
        RailwaySceneWorld.texturedPBR(UIColor(red: 0.82, green: 0.78, blue: 0.72, alpha: 1), roughness: 0.9, textureName: "scenery_brick_warm"),
        RailwaySceneWorld.texturedPBR(UIColor(red: 0.84, green: 0.86, blue: 0.88, alpha: 1), roughness: 0.88, textureName: "scenery_concrete")
    ]
    private let officeMaterials = [
        RailwaySceneWorld.texturedPBR(.white, roughness: 0.62, textureName: "scenery_office_facade", normalName: "normal_office_facade"),
        // quality33: derived facade variants (different window
        // pitch/proportions, tints, lit windows, weathering
        // streaks) so neighbouring towers no longer share one
        // identical skin. The first four entries are the tall
        // towers' pool, so they lead the list.
        RailwaySceneWorld.texturedPBR(.white, roughness: 0.64, textureName: "scenery_office_facade_2", normalName: "normal_office_facade"),
        RailwaySceneWorld.texturedPBR(.white, metallic: 0.06, roughness: 0.52, textureName: "scenery_glass_facade", normalName: "normal_glass_facade"),
        RailwaySceneWorld.texturedPBR(.white, metallic: 0.06, roughness: 0.54, textureName: "scenery_glass_facade_2", normalName: "normal_glass_facade"),
        RailwaySceneWorld.texturedPBR(UIColor(red: 0.90, green: 0.88, blue: 0.84, alpha: 1), roughness: 0.66, textureName: "scenery_office_facade", normalName: "normal_office_facade"),
        RailwaySceneWorld.texturedPBR(UIColor(red: 0.88, green: 0.92, blue: 1.0, alpha: 1), metallic: 0.06, roughness: 0.56, textureName: "scenery_glass_facade", normalName: "normal_glass_facade"),
        RailwaySceneWorld.texturedPBR(.white, roughness: 0.6, textureName: "scenery_office_facade_3", normalName: "normal_office_facade"),
        RailwaySceneWorld.texturedPBR(.white, metallic: 0.06, roughness: 0.55, textureName: "scenery_glass_facade_3", normalName: "normal_glass_facade"),
        RailwaySceneWorld.texturedPBR(.white, roughness: 0.92, textureName: "scenery_apartment_facade", normalName: "normal_apartment_facade"),
        RailwaySceneWorld.texturedPBR(.white, roughness: 0.92, textureName: "scenery_apartment_facade_2", normalName: "normal_apartment_facade"),
        RailwaySceneWorld.texturedPBR(UIColor(red: 0.94, green: 0.90, blue: 0.84, alpha: 1), roughness: 0.9, textureName: "scenery_house_facade"),
        // quality32: tint variants of the same facades. Adjacent
        // towers used to cycle only three textures at one tone, so
        // the same building visibly repeated down the street;
        // per-tone variation breaks the repetition without new
        // assets.
        RailwaySceneWorld.texturedPBR(UIColor(red: 0.80, green: 0.79, blue: 0.77, alpha: 1), roughness: 0.68, textureName: "scenery_office_facade", normalName: "normal_office_facade"),
        RailwaySceneWorld.texturedPBR(UIColor(red: 0.84, green: 0.80, blue: 0.74, alpha: 1), roughness: 0.94, textureName: "scenery_apartment_facade", normalName: "normal_apartment_facade"),
        RailwaySceneWorld.texturedPBR(UIColor(red: 0.78, green: 0.83, blue: 0.90, alpha: 1), metallic: 0.06, roughness: 0.58, textureName: "scenery_glass_facade", normalName: "normal_glass_facade"),
        RailwaySceneWorld.texturedPBR(UIColor(red: 0.86, green: 0.84, blue: 0.80, alpha: 1), roughness: 0.9, textureName: "scenery_brick_warm")
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
        skyDome = nil
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
        cabNeedlePivots = [:]
        cabLampOverlays = [:]
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
        var sampleInterval = max(profileInterval, route.distanceM / Double(sampleBudget))
        // quality24 (C3): the scenery budget used to double as the
        // alignment sampling density, which left the integrated
        // polyline at ~42.5 m chords on the balanced preset. Every
        // builder follows that one polyline (trackbed ribbons, rails
        // via sample(at:), walls, the camera itself), so on the
        // sharpest curve (R324) each chord sagged 0.68 m inside the
        // true arc and headings stepped ~7.5 degrees at a time: the
        // "kakkukaku" polygonal curves in the CI photos, even though
        // the alignment model itself has proper transition curves.
        // Decouple the two budgets: sample the alignment at 8.5 m
        // (sagitta 2.8 cm at R324, 2.0 cm at the showcase R450),
        // whatever the scenery instance budget says. The .low preset
        // keeps its coarse sampling for weak devices. Per-sample
        // entity placements in buildTrack are gated by chainage, so
        // the finer polyline does not multiply entity counts.
        if quality != .low {
            sampleInterval = min(sampleInterval, 8.5)
        }
        samples = makeSamples(route: route, interval: sampleInterval)
        viaductGround = computeViaductGround(route: route, routeVariant: routeVariant, travelDirection: travelDirection)
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
        // quality26: base intensity cut 18,000 → 10,000 — with the
        // sun direction fixed in quality25 the old value blew sunlit
        // ground and white surfaces out to white (CI #238); the
        // balance had been tuned when the sun pointed up and only
        // fill + environment lit the scene. apply() scales this per
        // environment; the fill base rises 1,200 → 1,800 to compensate.
        sunlight.light.intensity = 6_600
        sunlight.light.color = UIColor(red: 1.0, green: 0.91, blue: 0.77, alpha: 1)
        // Cast shadows: without a shadow configuration RealityKit
        // renders no shadows at all, which left every building, pole
        // and train floating on flat-lit ground (the single biggest
        // "not real" cue in the CI #213 tour photos). The range is
        // capped at ~250 m so the shadow map stays detailed around
        // the line instead of covering the whole visible distance.
        if #available(iOS 26.0, *) {
            var sunlightShadow = DirectionalLightComponent.Shadow()
            sunlightShadow.shadowProjection = .automatic(maximumDistance: 250)
            sunlight.components.set(sunlightShadow)
        }
        // quality25 (D): the orientation this replaces —
        // simd_quatf(angle: -.pi/3.6, axis: (-0.6, 0.8, -0.3)) —
        // rotates the light's forward vector [0, 0, -1] to
        // (0.53, +0.52, -0.67) under the standard right-hand rule:
        // the light shone UPWARD, its sun 31 degrees BELOW the
        // horizon. An upward sun can cast no shadow on the ground
        // and lights no upward face, which is why no CI photo ever
        // showed a shadow (the scene was lit by the fill light and
        // the environment alone) — the Shadow component itself was
        // set correctly all along. Build the orientation from an
        // explicit travel direction instead: the basis below maps
        // local -Z onto sunTravelDirection by construction.
        // Sun elevation: asin(0.62 / |v|) ≈ 38 degrees.
        let sunDir = simd_normalize(Self.sunTravelDirection)
        let sunZ = -sunDir
        let sunX = simd_normalize(simd_cross(SIMD3<Float>(0, 1, 0), sunZ))
        let sunY = simd_cross(sunZ, sunX)
        sunlight.orientation = simd_quatf(simd_float3x3(sunX, sunY, sunZ))
        root.addChild(sunlight)

        fillLight = PointLight()
        fillLight.light.intensity = 3_100
        fillLight.light.attenuationRadius = 500
        fillLight.light.color = UIColor(red: 0.70, green: 0.79, blue: 0.88, alpha: 1)
        fillLight.position = SIMD3<Float>(0, 16, -30)
        root.addChild(fillLight)

        // quality37: photographic sky dome (photo from BEIZ images,
        // whose terms allow commercial use in apps without credit),
        // replacing the flat colour sky — the single biggest
        // "game look" surface in the frame. The dome follows the
        // camera in update(), so the horizon stays at eye level
        // anywhere on the line; if the texture is missing the flat
        // palette colour remains as the fallback.
        if let skyTexture = SceneTextureProvider.texture(named: "scenery_sky") {
            var skyMaterial = UnlitMaterial()
            skyMaterial.color = .init(tint: .white, texture: .init(skyTexture))
            skyDome = ModelEntity(mesh: MeshResource.generateSphere(radius: 1_800), materials: [skyMaterial])
            // The dome is viewed from inside, but UnlitMaterial's
            // faceCulling needs iOS 18 (the project targets 17) and
            // emissiveColor takes no texture in this SDK. Mirroring
            // the sphere on X flips its winding instead, so the
            // inside faces render on any iOS version; a mirrored
            // sky is indistinguishable from the original.
            skyDome?.scale = SIMD3<Float>(-1, 1, 1)
            if let skyDome {
                root.addChild(skyDome)
            }
        }

        if quality == .high, sceneFidelityRoute != nil {
            buildSceneFidelityRegion(route: route, chainageM: 0, useLiveCamera: false)
        } else {
            sceneFidelityRoute = nil
            computeCrossingCenters(route: route, routeVariant: routeVariant, travelDirection: travelDirection)
            buildTrack(route: route, routeVariant: routeVariant, travelDirection: travelDirection)
            buildTunnels(route: route)
            buildSignals(route: route, routeVariant: routeVariant, travelDirection: travelDirection)
            buildCatenary(route: route, routeVariant: routeVariant, travelDirection: travelDirection, showcaseSection: travelDirection == .up && (routeVariant == .mainline || routeVariant == .throughBranch))
            buildSuburb(route: route, routeVariant: routeVariant, travelDirection: travelDirection)
            buildUtilityPoles(route: route, routeVariant: routeVariant, travelDirection: travelDirection)
            buildRoadTraffic(route: route, scenario: trafficScenario, routeVariant: routeVariant, travelDirection: travelDirection)
            buildFictionalCorridorLandmarks(route: route, quality: quality)
            buildShowcaseSection(route: route, routeVariant: routeVariant, travelDirection: travelDirection)
            // quality29: buildDestinationPlatform is gone. It was a
            // pre-quality25 leftover that laid two rigid 115 m
            // concrete boxes centred ON the tracks at the demo's
            // destination (lateral +/-1.9 m, top above rail head),
            // pitched level while the track climbs ~20 per mille —
            // at Matsubaracho the boxes sliced through both tracks
            // diagonally for the whole platform length, which is
            // the "broken track" in the Codemagic photos. The
            // curve-following platforms from buildStationPlatforms
            // below serve every station, the destination included.
        }
        buildLevelCrossings(route: route)
        buildConsist(carCount: safeCarCount, useHighFidelityLead: quality == .high)
        // quality25 (A): curve-following platforms at the corrected
        // lengths; the station GLBs keep only their cores (see
        // stripGeneratedPlatformParts).
        buildStationPlatforms(routeVariant: routeVariant, travelDirection: travelDirection)
        buildStationSurroundings(routeVariant: routeVariant, travelDirection: travelDirection)
        buildGenerated3DAssets(route: route)
    }

    func update(
        route: RailwayRouteProfile,
        positionM: Double,
        speedKmh: Double,
        brakePipePressureKPa: Double,
        mainReservoirPressureKPa: Double = 690,
        brakeCylinderPressureKPa: Double = 0,
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
            z: centerSample.z + playerLateral * sin(centerSample.heading),
            heading: centerSample.heading,
            bankRadians: centerSample.bankRadians,
            elevationM: centerSample.elevationM
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
                carSample.x + trackSide * carLateral.x, carSample.elevationM, carSample.z + trackSide * carLateral.z
            )
            // Pitch the body about its lateral axis from the two bogie
            // heights, so the car follows the grade instead of staying
            // level while the rail climbs or falls under it.
            let carPitch = RegionalRouteGeometrySampler.carBodyPitchRadians(
                frontBogieElevationM: self.sample(at: chainage + 6.35).elevationM,
                rearBogieElevationM: self.sample(at: chainage - 6.35).elevationM
            )
            // Vehicle meshes face local -Z; negative route yaw aligns that end with route-forward.
            model.root.orientation = simd_quatf(angle: -carSample.heading, axis: SIMD3<Float>(0, 1, 0)) *
                simd_quatf(angle: carPitch, axis: SIMD3<Float>(1, 0, 0)) *
                simd_quatf(angle: -carSample.bankRadians, axis: SIMD3<Float>(0, 0, 1))
        }
        if let model = highFidelityLeadVehicle {
            let carChainage = positionM - 9.75
            let carSample = self.sample(at: carChainage)
            // Bogies sit ±6.35 m from the car centre; the front bogie is
            // toward increasing chainage (the mesh front, local -Z,
            // faces route-forward). These were previously swapped, so
            // each bogie yawed as if it stood at the other end.
            let frontBogieSample = self.sample(at: carChainage + 6.35)
            let rearBogieSample = self.sample(at: carChainage - 6.35)
            let carLateral = SIMD3<Float>(cos(carSample.heading), 0, sin(carSample.heading))
            let trackSide: Float = travelDirection == .up ? -2.1 : 2.1
            model.root.position = SIMD3<Float>(
                carSample.x + trackSide * carLateral.x, carSample.elevationM, carSample.z + trackSide * carLateral.z
            )
            let leadPitch = RegionalRouteGeometrySampler.carBodyPitchRadians(
                frontBogieElevationM: frontBogieSample.elevationM,
                rearBogieElevationM: rearBogieSample.elevationM
            )
            model.root.orientation = simd_quatf(angle: -carSample.heading, axis: SIMD3<Float>(0, 1, 0)) *
                simd_quatf(angle: leadPitch, axis: SIMD3<Float>(1, 0, 0)) *
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
            if currentCabDesk.fictionalCarNumber == "E231" {
                // One-handle desk: a single lever value spans brake
                // (-7) through neutral to power (+5).
                let combined: Float
                if controls.emergencyBrake {
                    combined = -7
                } else if controls.throttleNotch > 0 {
                    combined = Float(controls.throttleNotch)
                } else {
                    combined = -Float(controls.brakeNotch)
                }
                cabModel.cabControls.setValue(combined, for: .masterController)
            } else {
                cabModel.cabControls.setValue(Float(controls.throttleNotch), for: .masterController)
            }
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
        updateCabGauges(speedKmh: speedKmh, brakePipePressureKPa: brakePipePressureKPa, mainReservoirPressureKPa: mainReservoirPressureKPa, brakeCylinderPressureKPa: brakeCylinderPressureKPa, indicator: vehicleCabIndicatorState, controls: controls)
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
            // The eye rides on the rail elevation at its own chainage.
            // The camera preset's heights are above the rail head.
            let pointElevationM = sample(at: currentSample.distanceM + point.z).elevationM
            return SIMD3<Float>(
                currentSample.x + right.x * Float(point.x) + forward.x * Float(point.z),
                Float(point.y) + pointElevationM,
                currentSample.z + right.z * Float(point.x) + forward.z * Float(point.z)
            )
        }
        let position = worldPoint(pose.position)
        // Aim along the local tangent at the eye instead of at a far
        // point on the route: on a curve the +100 m point lies on the
        // chord, so looking at it swung the vanishing point off the
        // rails the train is actually running on (CI #213 tour photos:
        // the track left the centre of the frame on every curve). The
        // pitch follows the gradient under the eye, sampled over a
        // short +/-12 m base so it matches the track the camera is
        // standing on rather than the average grade 100 m ahead, and
        // the preset's eye-to-target height difference is kept as a
        // fixed look-down offset. The lateral position is untouched:
        // currentSample already carries the running line's offset.
        let eyeChainage = currentSample.distanceM + pose.position.z
        let gradientRise = sample(at: eyeChainage + 12).elevationM - sample(at: eyeChainage - 12).elevationM
        let gradient = gradientRise / 24
        let lookDistance = max(Float(pose.target.z - pose.position.z), 10)
        let lookDrop = Float(pose.target.y - pose.position.y)
        let target = SIMD3<Float>(
            position.x + forward.x * lookDistance,
            position.y + lookDrop + gradient * lookDistance,
            position.z + forward.z * lookDistance
        )
        camera.position = position
        camera.camera.fieldOfViewInDegrees = Float(min(max(pose.fieldOfViewDegrees, 20), 110))
        camera.look(at: target, from: position, relativeTo: nil)
        if abs(pose.rollRadians) > 0.0001 {
            camera.orientation = simd_mul(camera.orientation, simd_quatf(angle: Float(pose.rollRadians), axis: SIMD3<Float>(0, 0, 1)))
        }
        cameraWorldPosition = position

        // The sunlight follows the camera (a habit kept from
        // quality24; Apple's docs say a directional light's
        // position does not affect its illumination, and the
        // automatic shadow projection is described as
        // camera-relative — but IF the projection anchors at the
        // light, riding 120 m sunward of the camera with a 250 m
        // range still covers the ground around the train, so the
        // follow is correct under both readings). The actual
        // shadow defect was the light's DIRECTION — see rebuild().
        // The fill light follows at cab height (150 m radius).
        sunlight.position = position - simd_normalize(Self.sunTravelDirection) * 120
        fillLight.position = position + SIMD3<Float>(0, 16, 0)
        skyDome?.position = position

        let tint = environment.warmCoolTint
        sunlight.light.intensity = 6_600 * Float(environment.sunLightScale)
        sunlight.light.color = UIColor(
            red: CGFloat(min(max(tint.x, 0), 1.2)), green: CGFloat(min(max(tint.y, 0), 1.2)),
            blue: CGFloat(min(max(tint.z, 0), 1.2)), alpha: 1
        )
        fillLight.light.intensity = 3_100 * Float(environment.ambientLightScale * (1 - environment.fogStrength * 0.35))
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

    /// Mainline station chainages (m from Kanun-Chuo), from
    /// `Packages/RailwayRouteData/Data/fictional_70km_network.json`.
    /// Stations sit on filled ground, never on piers: the viaduct
    /// ground rises to track level under each station (see
    /// `computeViaductGround`).
    private static let mainlineStationChainagesM: [Double] = [
        0, 1_839, 3_871, 6_000, 8_226, 10_355, 12_387, 14_613,
        16_935, 19_161, 21_290, 24_194, 26_323, 28_452, 30_677,
        32_903, 35_129, 37_355, 39_581, 41_806, 44_032, 46_258,
        48_484, 50_710, 52_935, 55_161, 57_387, 60_000
    ]

    /// Chainages of the physical tunnels, where the ground must stay
    /// at track level (the tunnel bore carries the line, not piers).
    private func isTunnelChainage(_ chainageM: Double) -> Bool {
        (chainageM >= 17_800 && chainageM <= 19_300)
            || (chainageM >= 24_000 && chainageM <= 25_846)
            || (chainageM >= 42_100 && chainageM <= 43_600)
    }

    /// Ground level under the track, one value per sample. A viaduct
    /// is where the line rides high above its valley floor: the datum
    /// is the lowest track elevation within +/-1.5 km, and a zone
    /// opens where the track sits >= 10 m above it (measured: three
    /// zones, about 10.5 km of the 60 km mainline, tallest pier
    /// about 33 m in the downtown climb). Short runs are dropped and
    /// gaps under 300 m are merged, tunnels and the coast are
    /// excluded, and stations get filled ground with 300 m tapers so
    /// no station, house, tower or pole ever floats. The tapers are
    /// smoothstep blends centred on each zone edge, so the ground is
    /// a continuous ramp (an embankment approach) rather than a step.
    private func computeViaductGround(route: RailwayRouteProfile, routeVariant: RegionalRouteVariant, travelDirection: RegionalTravelDirection) -> [Float] {
        guard samples.count > 1 else { return samples.map(\.elevationM) }
        let datumWindowM = 1_500.0
        let zoneThresholdM: Float = 10
        let minRunM = 300.0
        let mergeGapM = 300.0
        let taperM = 300.0
        let stationHalfWidthM = 250.0
        // 1. Valley-floor datum: rolling minimum of the elevation.
        var datum = [Float](repeating: 0, count: samples.count)
        for i in samples.indices {
            var low = samples[i].elevationM
            var j = i
            while j > 0, samples[i].distanceM - samples[j - 1].distanceM <= datumWindowM {
                j -= 1
                low = min(low, samples[j].elevationM)
            }
            j = i
            while j + 1 < samples.count, samples[j + 1].distanceM - samples[i].distanceM <= datumWindowM {
                j += 1
                low = min(low, samples[j].elevationM)
            }
            datum[i] = low
        }
        // 2. Raw zones, excluding tunnels and the coast.
        var inZone = [Bool](repeating: false, count: samples.count)
        for i in samples.indices {
            guard isMainlineSection(distanceM: samples[i].distanceM, routeVariant: routeVariant, travelDirection: travelDirection) else { continue }
            let chainage = chainageFromCenter(distanceM: samples[i].distanceM, route: route, travelDirection: travelDirection)
            if isTunnelChainage(chainage) { continue }
            if isCoastal(distanceM: samples[i].distanceM, route: route, routeVariant: routeVariant, travelDirection: travelDirection) { continue }
            inZone[i] = samples[i].elevationM - datum[i] >= zoneThresholdM
        }
        // 3. Merge gaps under 300 m, drop runs under 300 m.
        var runs: [(Int, Int)] = []
        var runStart: Int? = nil
        for i in samples.indices {
            if inZone[i], runStart == nil { runStart = i }
            if !inZone[i], let start = runStart {
                runs.append((start, i - 1))
                runStart = nil
            }
        }
        if let start = runStart { runs.append((start, samples.count - 1)) }
        var mergedRuns: [(Int, Int)] = []
        for run in runs {
            if let last = mergedRuns.last,
               samples[run.0].distanceM - samples[last.1].distanceM < mergeGapM {
                mergedRuns[mergedRuns.count - 1] = (last.0, run.1)
            } else {
                mergedRuns.append(run)
            }
        }
        var zone = [Bool](repeating: false, count: samples.count)
        for run in mergedRuns where samples[run.1].distanceM - samples[run.0].distanceM >= minRunM {
            for i in run.0...run.1 { zone[i] = true }
        }
        // 4. Zone edges (chainage positions where the zone flag flips),
        // tagged entry (ground falls away) vs exit (ground returns).
        var edges: [(Double, Bool)] = []
        for i in 1..<samples.count where zone[i] != zone[i - 1] {
            edges.append(((samples[i].distanceM + samples[i - 1].distanceM) / 2, zone[i]))
        }
        func smoothstep(_ x: Float) -> Float {
            let clamped = min(max(x, 0), 1)
            return clamped * clamped * (3 - 2 * clamped)
        }
        // 5. Ground level: blend from elevation (outside) to datum
        // (inside) across a 300 m taper centred on each edge, and
        // force filled ground under stations with the same taper.
        var ground = [Float](repeating: 0, count: samples.count)
        for i in samples.indices {
            let sample = samples[i]
            var blend: Float = zone[i] ? 1 : 0
            if let nearestEdge = edges.min(by: { abs($0.0 - sample.distanceM) < abs($1.0 - sample.distanceM) }) {
                // Distance from the edge into the zone: positive
                // inside, negative outside, whichever side the edge is.
                let intoZone = nearestEdge.1 ? (sample.distanceM - nearestEdge.0) : (nearestEdge.0 - sample.distanceM)
                blend = smoothstep(Float((intoZone + taperM / 2) / taperM))
            }
            if isMainlineSection(distanceM: sample.distanceM, routeVariant: routeVariant, travelDirection: travelDirection) {
                let chainage = chainageFromCenter(distanceM: sample.distanceM, route: route, travelDirection: travelDirection)
                if let nearestStation = Self.mainlineStationChainagesM.min(by: { abs($0 - chainage) < abs($1 - chainage) }) {
                    let stationBlend = smoothstep(Float((abs(chainage - nearestStation) - stationHalfWidthM) / taperM))
                    blend = min(blend, stationBlend)
                }
            }
            ground[i] = sample.elevationM - blend * (sample.elevationM - datum[i])
        }
        return ground
    }

    /// Ground height at an arbitrary chainage, interpolating the
    /// per-sample viaduct ground the way `sample(at:)` interpolates
    /// elevation. Falls back to the track elevation if the ground
    /// has not been computed yet.
    private func groundLevelM(at distanceM: Double) -> Float {
        guard viaductGround.count == samples.count, samples.count > 1 else {
            return sample(at: distanceM).elevationM
        }
        if distanceM <= samples[0].distanceM { return viaductGround[0] }
        // First sample at or past the target chainage. The samples
        // are sorted by construction (the sampler walks the chainage
        // upward); a binary search keeps this lookup O(log n) now
        // that the alignment is sampled at 8.5 m (~8,000 samples)
        // and this runs for every ground query.
        var searchLow = 0
        var searchHigh = samples.count
        while searchLow < searchHigh {
            let mid = (searchLow + searchHigh) / 2
            if samples[mid].distanceM >= distanceM {
                searchHigh = mid
            } else {
                searchLow = mid + 1
            }
        }
        let upperIndex: Int? = searchLow < samples.count ? searchLow : nil
        guard let upperIndex else {
            return viaductGround[viaductGround.count - 1]
        }
        guard upperIndex > 0 else { return viaductGround[upperIndex] }
        let lower = samples[upperIndex - 1]
        let upper = samples[upperIndex]
        let span = max(upper.distanceM - lower.distanceM, 0.001)
        let fraction = Float(min(max((distanceM - lower.distanceM) / span, 0), 1))
        return viaductGround[upperIndex - 1] + (viaductGround[upperIndex] - viaductGround[upperIndex - 1]) * fraction
    }

    private func groundLevelM(at sample: RouteSample) -> Float {
        groundLevelM(at: sample.distanceM)
    }

    /// `routeOffsetPoint` for ground-level scenery: same plan
    /// position, but standing on the viaduct ground instead of the
    /// track elevation.
    private func groundOffsetPoint(_ sample: RouteSample, lateral: Float) -> SIMD3<Float> {
        SIMD3<Float>(
            sample.x + lateral * cos(sample.heading),
            groundLevelM(at: sample),
            sample.z + lateral * sin(sample.heading)
        )
    }

    private func buildTrack(
        route: RailwayRouteProfile,
        routeVariant: RegionalRouteVariant,
        travelDirection: RegionalTravelDirection
    ) {
        // Formation ground: the base fill under everything. It used
        // to be one straight 1,400 m box on the global -z axis, but
        // the route wanders up to 31 km off that axis (plan view), so
        // beyond the first kilometres the train ran over void. Two
        // route-following ribbons now carry it along the line at
        // rail-head minus 9 cm. On the sea side of the coast the
        // ribbons stop: the beach and the sea cover that ground, and
        // a ribbon following the rising track would poke through the
        // flat water. Where the line is on a viaduct the ribbons
        // drop to the valley floor instead (see `viaductGround`):
        // the deck and piers below carry the track there.
        let groundOffsets = samples.map { groundLevelM(at: $0) - $0.elevationM }
        let slabMaterial = Self.pbr(UIColor(red: 0.24, green: 0.28, blue: 0.24, alpha: 1), roughness: 1)
        let slabSeaSign = seaSideSign(travelDirection: travelDirection)
        for sideSign: Float in [-1, 1] {
            let slabSpan = clampedRibbonSpan(route: route, centerOffset: sideSign * 350, width: 700)
            var runStart = 0
            var runSeaCoastal = sideSign == slabSeaSign && isCoastal(distanceM: samples[0].distanceM, route: route, routeVariant: routeVariant, travelDirection: travelDirection)
            for i in 1...samples.count {
                let coastal = i < samples.count ? (sideSign == slabSeaSign && isCoastal(distanceM: samples[i].distanceM, route: route, routeVariant: routeVariant, travelDirection: travelDirection)) : false
                if coastal != runSeaCoastal {
                    let runEnd = min(i + 1, samples.count)
                    if !runSeaCoastal {
                        if let slab = ribbonEntity(name: "formation-ground-\(sideSign > 0 ? "r" : "l")-\(runStart)", width: 700, y: -0.09, tileLength: 12,
                                                   offsets: slabSpan.centers, material: slabMaterial, range: runStart..<runEnd, yOffsets: groundOffsets, widths: slabSpan.widths) {
                            world.addChild(slab)
                        }
                    }
                    runStart = i
                    runSeaCoastal = coastal
                }
            }
        }

        // Distant backdrops that follow the route (BVE-style
        // background): city skyline inside the urban bands, mountain
        // ranges elsewhere — real BVE routes swap backgrounds per
        // section the same way. The old version was a straight 4 km
        // box on the global -z axis; the route leaves that axis
        // within kilometres, so the horizon was empty past the
        // suburbs and the straight walls sliced through the line
        // wherever the route crossed x = +/-680 m. A 4 km straight
        // wall fitted to the local chord still drifts up to 1,134 m
        // off the track (measured), so the wall is a vertical strip
        // following the samples instead, pulled in inside tight
        // curves so it can never fold through the track.
        // quality38 (photoreal batch 3): aerial perspective baked
        // into the backdrop textures. The 680 m wall now uses
        // variants mixed 40-45 % toward the horizon colour so the
        // silhouettes soften and the wall's top edge stops fighting
        // the photo sky dome; the 300 m city layer gets a lighter
        // 18 % mix of the same skyline (citylineMaterial below).
        var backdropMaterial = Self.texturedPBR(.white, roughness: 1, textureName: "backdrop_mountains_haze")
        backdropMaterial.faceCulling = .none
        var skylineMaterial = Self.texturedPBR(.white, roughness: 1, textureName: "backdrop_skyline_haze")
        skylineMaterial.faceCulling = .none
        var citylineMaterial = Self.texturedPBR(.white, roughness: 1, textureName: "backdrop_skyline_haze300")
        citylineMaterial.faceCulling = .none
        let backdropLaterals: [Float] = samples.map { clampedWallLateral(side: 1, standoff: 680, route: route, sample: $0) }
        let backdropBottoms: [Float] = samples.map { groundLevelM(at: $0) - 15 }
        // Top at +45 m, not +95 m: with the old height the upper,
        // near-white part of the panorama filled the horizon and read
        // as a hard white band across every outdoor photo (CI #213).
        // The replacement panoramas carry their scenery in the lower
        // 60 %, so a 60 m wall shows mountains/buildings, not blank sky.
        let backdropTops: [Float] = samples.map { $0.elevationM + 45 }
        for sideSign: Float in [-1, 1] {
            let laterals = backdropLaterals.map { $0 * sideSign }
            var runStart = 0
            var runUrban = urbanBand(distanceM: samples[0].distanceM, route: route, routeVariant: routeVariant, travelDirection: travelDirection) > 0
            for i in 1...samples.count {
                let urban = i < samples.count ? urbanBand(distanceM: samples[i].distanceM, route: route, routeVariant: routeVariant, travelDirection: travelDirection) > 0 : !runUrban
                if urban != runUrban {
                    let runEnd = min(i + 1, samples.count)
                    if let wall = verticalRibbonEntity(name: "backdrop-\(runUrban ? "skyline" : "mountains")-\(sideSign > 0 ? "r" : "l")-\(runStart)",
                                                       lateralOffsets: laterals, bottomYs: backdropBottoms, topYs: backdropTops,
                                                       tileLength: 2_000, material: runUrban ? skylineMaterial : backdropMaterial,
                                                       range: runStart..<runEnd) {
                        world.addChild(wall)
                    }
                    runStart = i
                    runUrban = urban
                }
            }
        }
        // Mid-distance tree line: a second, nearer backdrop layer so
        // the far view has depth instead of one wall of mountains.
        // Skipped in the city and on the sea side of the coast,
        // where it would stand in the water.
        var forestMaterial = Self.texturedPBR(.white, roughness: 1, textureName: "scenery_mountain_forest")
        forestMaterial.faceCulling = .none
        let forestLaterals: [Float] = samples.map { clampedWallLateral(side: 1, standoff: 300, route: route, sample: $0) }
        let forestBottoms: [Float] = samples.map { groundLevelM(at: $0) - 3 }
        let forestTops: [Float] = samples.map { groundLevelM(at: $0) + 21 }
        // quality34: inside the urban bands the same 300 m layer
        // carries the skyline panorama instead of trees, taller, so
        // the city has a mid-distance mass of buildings behind the
        // real tower rows instead of flat apron running straight
        // out to the 680 m backdrop.
        let cityTops: [Float] = samples.map { groundLevelM(at: $0) + 52 }
        let forestSeaSign = seaSideSign(travelDirection: travelDirection)
        for sideSign: Float in [-1, 1] {
            let laterals = forestLaterals.map { $0 * sideSign }
            func forestKey(_ i: Int) -> Int {
                let urban = urbanBand(distanceM: samples[i].distanceM, route: route, routeVariant: routeVariant, travelDirection: travelDirection) > 0 ? 1 : 0
                let sea = (sideSign == forestSeaSign && isCoastal(distanceM: samples[i].distanceM, route: route, routeVariant: routeVariant, travelDirection: travelDirection)) ? 1 : 0
                return urban * 10 + sea
            }
            var runStart = 0
            var runKey = forestKey(0)
            for i in 1...samples.count {
                let key = i < samples.count ? forestKey(i) : -1
                if key != runKey {
                    let runEnd = min(i + 1, samples.count)
                    if runKey == 0 {
                        // 600 m repeats, not 4 km: at 4 km the painted
                        // trees smeared into the horizontal green streaks
                        // that crossed the CI #213 photos at the horizon.
                        if let forest = verticalRibbonEntity(name: "forest-mid-\(sideSign > 0 ? "r" : "l")-\(runStart)",
                                                             lateralOffsets: laterals, bottomYs: forestBottoms, topYs: forestTops,
                                                             tileLength: 600, material: forestMaterial,
                                                             range: runStart..<runEnd) {
                            world.addChild(forest)
                        }
                    } else if runKey >= 10 {
                        // quality34: urban run of the mid layer —
                        // skyline panorama at 300 m (see cityTops).
                        if let city = verticalRibbonEntity(name: "cityline-mid-\(sideSign > 0 ? "r" : "l")-\(runStart)",
                                                           lateralOffsets: laterals, bottomYs: forestBottoms, topYs: cityTops,
                                                           tileLength: 900, material: citylineMaterial,
                                                           range: runStart..<runEnd) {
                            world.addChild(city)
                        }
                    }
                    runStart = i
                    runKey = key
                }
            }
        }

        // Photographic ground apron following the line over the flat far
        // slab: grass at real-world scale, asphalt inside the urban bands
        // so the towers stand on city ground.
        if samples.count > 1 {
            let apronOffsets = [Float](repeating: 0, count: samples.count)
            // quality26: both apron tints were .white (1, 1, 1), so
            // the grass / asphalt photo textures took the full force
            // of the corrected sun and blew out (CI #238). A 0.74
            // neutral tint multiplies them down to a sunlit-but-not-
            // clipped range. The far-ground materials below already
            // sit at 0.80–0.84 tints and are left as they are.
            let apronTint = UIColor(red: 0.68, green: 0.68, blue: 0.68, alpha: 1)
            let grassApron = Self.texturedPBR(apronTint, roughness: 1, textureName: "scenery_grass")
            let cityApron = Self.texturedPBR(apronTint, roughness: 1, textureName: "scenery_asphalt", normalName: "normal_asphalt")
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
                                                range: runStart..<runEnd, uTileLength: 12, yOffsets: groundOffsets) {
                        world.addChild(apron)
                    }
                    runStart = i
                    runBand = band
                    runCoastal = coastal
                }
            }
        }

        // Far ground: textured fields out to the backdrop wall. The
        // height used to step by up to ~1 m at every 3 km chunk
        // boundary, which read from the train as hard rectangular
        // patches and a black band at the horizon. The lift is now
        // one smooth function of chainage, so adjacent runs share
        // the same height at their boundary and the land rolls
        // gently instead of stepping. The sea side of the coastal
        // stretch is skipped — that ground is beach and water.
        if samples.count > 1 {
            let farGrassMaterial = Self.texturedPBR(UIColor(red: 0.80, green: 0.84, blue: 0.76, alpha: 1), roughness: 1, textureName: "scenery_grass")
            // Patchwork fields: the same grass texture under a deeper
            // green tint, alternated in ~3 km chunks, so the far ground
            // reads as separate fields instead of one endless sheet.
            let farFieldMaterial = Self.texturedPBR(UIColor(red: 0.52, green: 0.63, blue: 0.44, alpha: 1), roughness: 1, textureName: "scenery_grass")
            let farCityMaterial = Self.texturedPBR(UIColor(red: 0.82, green: 0.82, blue: 0.84, alpha: 1), roughness: 1, textureName: "scenery_asphalt", normalName: "normal_asphalt")
            let farSeaSign = seaSideSign(travelDirection: travelDirection)
            // Gentle undulation: +/-0.45 m over ~10.9 km, continuous
            // everywhere (no steps at run boundaries).
            let farLifts: [Float] = samples.map { sample in
                0.5 + 0.45 * Float(sin(sample.distanceM / 1_730 + 0.8))
            }
            // Far fields ride the viaduct ground too: under a viaduct
            // they lie on the valley floor, not at rail level.
            let farGroundOffsets = samples.indices.map { farLifts[$0] + groundOffsets[$0] }
            for sideSign: Float in [-1, 1] {
                let farSpan = clampedRibbonSpan(route: route, centerOffset: sideSign * 375, width: 600)
                func farKey(_ i: Int) -> Int {
                    let band = urbanBand(distanceM: samples[i].distanceM, route: route, routeVariant: routeVariant, travelDirection: travelDirection) > 0 ? 1 : 0
                    let blocked = (sideSign == farSeaSign && isCoastal(distanceM: samples[i].distanceM, route: route, routeVariant: routeVariant, travelDirection: travelDirection)) ? 1 : 0
                    let chunk = Int(samples[i].distanceM / 3_000) % 2
                    return band * 100 + chunk * 10 + blocked
                }
                var farRunStart = 0
                var farRunKey = farKey(0)
                for i in 1...samples.count {
                    let key = i < samples.count ? farKey(i) : -1
                    if key != farRunKey {
                        let farRunEnd = min(i + 1, samples.count)
                        let wasBlocked = farRunKey % 10 == 1
                        if !wasBlocked {
                            // 30 m texture tiles in both directions, not
                            // 90 m: the 90 m features smeared into bands
                            // at grazing angles (CI #213 photos).
                            if let far = ribbonEntity(name: "far-ground-\(sideSign > 0 ? "r" : "l")-\(farRunStart)", width: 600, y: 0.02, tileLength: 30,
                                                      offsets: farSpan.centers,
                                                      material: farRunKey >= 100 ? farCityMaterial : ((farRunKey / 10) % 2 == 0 ? farGrassMaterial : farFieldMaterial),
                                                      range: farRunStart..<farRunEnd, uTileLength: 30, yOffsets: farGroundOffsets, widths: farSpan.widths) {
                                world.addChild(far)
                            }
                        }
                        farRunStart = i
                        farRunKey = key
                    }
                }
            }
        }

        // Viaduct: where the ground falls 2 m or more below the
        // track, the formation is a concrete girder deck on piers
        // instead of fill. Deck: 8.4 m wide slab, 0.8 m thick, top
        // at rail-head minus 9 cm so the ballast sits on it exactly
        // as it sits on the formation slab elsewhere. Piers: one
        // every 30 m (real PC-girder span), a 3.0 x 2.2 m concrete
        // column from the valley floor to the deck soffit with an
        // 8.6 m crossbeam cap, batched into one mesh. The deck and
        // the piers both end where the tapered ground has risen to
        // within 2 m of the track, so they die into the embankment
        // approach instead of stopping on a cliff edge.
        if samples.count > 1 {
            let deckOffsets = [Float](repeating: 0, count: samples.count)
            let deckMaterial = Self.pbr(UIColor(red: 0.46, green: 0.48, blue: 0.47, alpha: 1), roughness: 0.84)
            func deckLift(_ i: Int) -> Float { samples[i].elevationM - groundLevelM(at: samples[i]) }
            var deckRunStart = 0
            var deckRunOn = deckLift(0) >= 2
            for i in 1...samples.count {
                let onDeck = i < samples.count ? deckLift(i) >= 2 : !deckRunOn
                if onDeck != deckRunOn {
                    let runEnd = min(i + 1, samples.count)
                    if deckRunOn {
                        if let deck = ribbonEntity(name: "viaduct-deck-\(deckRunStart)", width: 8.4, y: -0.49, tileLength: 12,
                                                   offsets: deckOffsets, material: deckMaterial, range: deckRunStart..<runEnd) {
                            world.addChild(deck)
                        }
                    }
                    deckRunStart = i
                    deckRunOn = onDeck
                }
            }
            var pierBatch = MeshBatchBuilder()
            var pierCount = 0
            var pierDistance = 15.0
            while pierDistance < route.distanceM {
                let pierSample = sample(at: pierDistance)
                let pierGround = groundLevelM(at: pierSample)
                let lift = pierSample.elevationM - pierGround
                if lift >= 2 {
                    let deckBottom = pierSample.elevationM - 0.89
                    let columnHeight = deckBottom - (pierGround - 0.1)
                    let centerX = pierSample.x
                    let centerZ = pierSample.z
                    // quality25: batch yaw follows the entity
                    // convention (see MeshBatchBuilder.addBox), so
                    // the across-track axis takes -heading.
                    pierBatch.addBox(center: SIMD3<Float>(centerX, pierGround - 0.1 + columnHeight / 2, centerZ),
                                     size: SIMD3<Float>(3.0, columnHeight, 2.2), yaw: -pierSample.heading)
                    pierBatch.addBox(center: SIMD3<Float>(centerX, deckBottom - 0.6, centerZ),
                                     size: SIMD3<Float>(8.6, 1.2, 1.6), yaw: -pierSample.heading)
                    pierCount += 1
                }
                pierDistance += 30
            }
            if pierCount > 0, let piers = pierBatch.build(name: "viaduct-piers", material: concreteMaterial) {
                world.addChild(piers)
            }
        }

        // Coastal stretch: a sand beach just outside the ground apron
        // and open sea beyond it, as ribbons over the coastal samples.
        // The far edge of the sea meets the backdrop wall, which then
        // reads as a distant shore across the water.
        // The sea is flat: it sits at the lowest track elevation of
        // its run (the datum), it must not climb with the track the
        // way the ground ribbons do. The track climbs up to ~11 m
        // above the datum inside a coastal window, so a bluff strip
        // closes the gap between the apron edge and the beach —
        // otherwise a slit of void would show along the shoreline.
        if samples.count > 1 {
            let seaSign = seaSideSign(travelDirection: travelDirection)
            let beachOffsets = samples.map { _ in seaSign * 31 }
            let seaSpan = clampedRibbonSpan(route: route, centerOffset: seaSign * 369, width: 660)
            let beachMaterial = Self.pbr(UIColor(red: 0.76, green: 0.69, blue: 0.52, alpha: 1), roughness: 1)
            let seaMaterial = Self.texturedPBR(.white, roughness: 0.55, textureName: "scenery_sea")
            let bluffMaterial = Self.pbr(UIColor(red: 0.52, green: 0.48, blue: 0.40, alpha: 1), roughness: 1)
            let bluffLaterals = samples.map { _ in seaSign * 23.5 }
            var runStart = 0
            var runCoastal = isCoastal(distanceM: samples[0].distanceM, route: route, routeVariant: routeVariant, travelDirection: travelDirection)
            for i in 1...samples.count {
                let coastal = i < samples.count ? isCoastal(distanceM: samples[i].distanceM, route: route, routeVariant: routeVariant, travelDirection: travelDirection) : false
                if coastal != runCoastal {
                    if runCoastal {
                        let runEnd = min(i + 1, samples.count)
                        let datum = samples[runStart..<runEnd].map(\.elevationM).min() ?? 0
                        if let beach = ribbonEntity(name: "beach-\(runStart)", width: 16, y: -0.03, tileLength: 12,
                                                    offsets: beachOffsets, material: beachMaterial, range: runStart..<runEnd,
                                                    absoluteY: datum - 0.03) {
                            world.addChild(beach)
                        }
                        if let sea = ribbonEntity(name: "sea-\(runStart)", width: 660, y: -0.06, tileLength: 30,
                                                  offsets: seaSpan.centers, material: seaMaterial, range: runStart..<runEnd, uTileLength: 30,
                                                  absoluteY: datum - 0.06, widths: seaSpan.widths) {
                            world.addChild(sea)
                        }
                        let bluffBottoms = samples.map { _ in datum - 0.03 }
                        let bluffTops = samples.map { $0.elevationM - 0.04 }
                        if let bluff = verticalRibbonEntity(name: "bluff-\(runStart)",
                                                            lateralOffsets: bluffLaterals, bottomYs: bluffBottoms, topYs: bluffTops,
                                                            tileLength: 30, material: bluffMaterial,
                                                            range: runStart..<runEnd) {
                            world.addChild(bluff)
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
        buildThroatFans(routeVariant: routeVariant)
        buildTerminusDivergence(route: route, routeVariant: routeVariant, travelDirection: travelDirection)
        buildTracksideMarkers(route: route, routeVariant: routeVariant, travelDirection: travelDirection)
        // Utility poles are built from prepare() after buildSuburb,
        // so urban poles can avoid the tower footprints.

        let wallLandmarks = fictionalCorridorLandmarks(for: route)
        // quality24 (C3): placements in this loop are gated by
        // CHAINAGE, not by sample index. The alignment polyline is
        // now sampled at 8.5 m, but sleepers keep their ~42.5 m
        // cadence and sit under the trackbed ribbon, so their chord
        // error is invisible and their entity counts must not grow.
        // (The ~127.5 m ballast slabs that shared this gating were
        // removed in quality36 — see the note at the sleeper gate.)
        // The lineside walls below are the exception: they drop to
        // a 12.75 m pitch and merge into batched meshes.
        var nextSleeperChainage = samples.first?.distanceM ?? 0
        var nextWallChainage = samples.first?.distanceM ?? 0
        var wallBatch = MeshBatchBuilder()
        // quality25 (G): showcase-section wall dressing (coping and
        // posts) rides in its own batch, flushed with the walls.
        var showcaseWallBatch = MeshBatchBuilder()
        var wallBatchIndex = 0
        var wallBatchStartChainage = samples.first?.distanceM ?? 0
        func flushWallBatch() {
            if let mesh = wallBatch.build(name: "lineside-wall-batch-\(wallBatchIndex)", material: concreteMaterial) {
                world.addChild(mesh)
                wallBatchIndex += 1
            }
            if let trim = showcaseWallBatch.build(name: "showcase-walltrim-\(wallBatchIndex)", material: poleMaterial) {
                world.addChild(trim)
            }
            wallBatch = MeshBatchBuilder()
            showcaseWallBatch = MeshBatchBuilder()
            wallBatchStartChainage = nextWallChainage
        }
        for index in samples.indices {
            let sample = samples[index]
            let yaw = simd_quatf(angle: -sample.heading, axis: SIMD3<Float>(0, 1, 0))
            let trackOrientation = yaw * simd_quatf(angle: -sample.bankRadians, axis: SIMD3<Float>(0, 0, 1))
            let isMainlineSection = travelDirection == .up ? sample.distanceM < 60_000 : sample.distanceM >= 8_000
            let hasPassingTrack = routeVariant == .mainline || (routeVariant == .throughBranch && isMainlineSection)
            let trackOffsets: [Float] = hasPassingTrack ? [-2.1, 2.1] : [travelDirection == .up ? -2.1 : 2.1]
            // quality36: the dark ballast slab boxes that used to be
            // placed here (3.2 m wide, ~127.5 m long, flat grey) are
            // REMOVED. They were pitched as rigid chords while the
            // trackbed ribbon follows the grade sample by sample, so
            // on every grade and curve they sliced up through the
            // ribbon and read in tour photos as unexplained black
            // bands lying on the track (isolated by the diag6
            // red-slab build, 2026-11-10). The ribbon and the
            // fidelity trackbed below it carry the formation now.
            if sample.distanceM >= nextSleeperChainage {
                nextSleeperChainage = sample.distanceM + 42.5
                for (trackIndex, lateral) in trackOffsets.enumerated() {
                    let x = sample.x + lateral * cos(sample.heading)
                    let z = sample.z + lateral * sin(sample.heading)
                    // Per-sleeper shade variation: real sleepers weather
                    // unevenly, and a perfectly uniform row reads fake.
                    let sleeperShade = 0.82 + Float((index * 37 + trackIndex * 11) % 5) * 0.09
                    addSurfaceBox(parent: world, name: "sleeper-\(index)-\(trackIndex)", size: SIMD3<Float>(2.55, 0.13, 0.26), position: SIMD3<Float>(x, sample.elevationM + 0.105, z), color: UIColor(red: 0.34 * CGFloat(sleeperShade), green: 0.27 * CGFloat(sleeperShade), blue: 0.19 * CGFloat(sleeperShade), alpha: 1), roughness: 0.88, orientation: trackOrientation)
                }
            }

            // Continuous lineside walls (noise barriers), laid as
            // per-segment slabs the way BVE routes repeat WallL/WallR:
            // they enclose the corridor and separate it from the parallel
            // roads and houses. Mainline sections only, kept clear of
            // stations and crossings.
            // The walls used to alternate concrete and steel segment by
            // segment; the metallic blue-grey steel halves read from
            // the train as water running along both sides of the track
            // (the "both sides water" in the sea screenshots, taken
            // nowhere near the coast). All segments are concrete now,
            // and the wall steps down outside the city so the rural
            // view opens up instead of running inside a channel.
            // quality25 (B): station zones are excluded too — the
            // wall at ±5.6 m used to run straight through the
            // platform slabs of every station on the line.
            if sample.distanceM >= nextWallChainage, hasPassingTrack, !corridorReserved(at: sample.distanceM, landmarks: wallLandmarks), !inStationZone(sample.distanceM), !nearThroatFan(sample.distanceM), !nearCrossing(sample.distanceM, margin: 10) {
                var spanEnd = index
                while spanEnd + 1 < samples.count, samples[spanEnd].distanceM - sample.distanceM < 12.75 {
                    spanEnd += 1
                }
                nextWallChainage = sample.distanceM + 12.75
                let band = urbanBand(distanceM: sample.distanceM, route: route, routeVariant: routeVariant, travelDirection: travelDirection)
                let wallHeight: Float = band == 2 ? 2.6 : band == 1 ? 2.2 : 1.4
                // quality37: the slab used to be one level chord per
                // span, framed on the span-start sample alone — on a
                // grade the next span started a full step higher
                // (the sawtooth beside the track in the photos), and
                // at ±5.6 m on a viaduct it hung in the air beside
                // the 8.4 m deck. Each span now runs from its start
                // point to its end point, so neighbours share an
                // edge and follow the grade; on structures (lift
                // >= 2 m) the wall stands on the deck edge
                // (±4.08 m) with its foot at deck level.
                let endSample = samples[spanEnd]
                let elevated = sample.elevationM - groundLevelM(at: sample) >= 2
                let wallLateral: Float = elevated ? 4.08 : 5.6
                let footDrop: Float = elevated ? 0.49 : 0
                func wallPoint(_ s: RouteSample, side: Double) -> SIMD3<Float> {
                    let bc = cos(s.bankRadians)
                    let bs = sin(s.bankRadians)
                    let ax = SIMD3<Float>(bc * cos(s.heading), -bs, bc * sin(s.heading))
                    return SIMD3<Float>(s.x, s.elevationM - footDrop, s.z) + ax * (Float(side) * wallLateral)
                }
                for side in [-1.0, 1.0] {
                    let p0 = wallPoint(sample, side: side)
                    let p1 = wallPoint(endSample, side: side)
                    var axisZ = p1 - p0
                    let spanLength = max(simd_length(axisZ), 1)
                    axisZ = axisZ / spanLength
                    let bc = cos(sample.bankRadians)
                    let bs = sin(sample.bankRadians)
                    let rawX = SIMD3<Float>(bc * cos(sample.heading), -bs, bc * sin(sample.heading))
                    var axisY = simd_cross(rawX, axisZ)
                    axisY = axisY / max(simd_length(axisY), 0.000001)
                    let axisX = simd_cross(axisY, axisZ)
                    let center = (p0 + p1) / 2 + axisY * (wallHeight / 2)
                    wallBatch.addBoxAxes(center: center,
                                         size: SIMD3<Float>(0.18, wallHeight, spanLength + 0.3),
                                         ax: axisX, ay: axisY, az: axisZ)
                    // quality25 (G): in the showcase section the
                    // bare slab gets its real component structure —
                    // a coping cap along the top edge and a post at
                    // each panel joint, standing proud of the slab
                    // the way precast noise-barrier panels bolt to
                    // their H-posts.
                    if sample.distanceM <= 1_856 {
                        let capCenter = center + axisY * (wallHeight / 2 + 0.05)
                        showcaseWallBatch.addBoxAxes(center: capCenter,
                                                     size: SIMD3<Float>(0.34, 0.10, spanLength + 0.3),
                                                     ax: axisX, ay: axisY, az: axisZ)
                        let postCenter = center - axisZ * (spanLength / 2)
                        showcaseWallBatch.addBoxAxes(center: postCenter,
                                                     size: SIMD3<Float>(0.30, wallHeight, 0.16),
                                                     ax: axisX, ay: axisY, az: axisZ)
                    }
                }
                if sample.distanceM - wallBatchStartChainage >= 1_200 {
                    flushWallBatch()
                }
            }
        }
        flushWallBatch()
    }

    /// Trackside colour-light signals on the main line, sighted on
    /// the left of the running track. Each head defaults to green;
    /// the signal protecting the block ahead is re-lit from the
    /// model's actual reading in updateSignalAspect.
    /// quality36: the placement grid densified from the route data's
    /// 3 km block spacing — at 3 km the tour photos never contained
    /// a signal at all (every spot sat just past one). Signals now
    /// stand every 1.5 km, plus a home signal 400 m before every
    /// mainline station, the way real lines mix automatic block
    /// signals with station entry signals.
    private func buildSignals(route: RailwayRouteProfile, routeVariant: RegionalRouteVariant, travelDirection: RegionalTravelDirection) {
        guard routeVariant == .mainline || routeVariant == .throughBranch else { return }
        let headMaterial = Self.pbr(UIColor(red: 0.05, green: 0.05, blue: 0.06, alpha: 1), metallic: 0.3, roughness: 0.6)
        let plateMaterial = Self.pbr(.white, roughness: 0.6)
        var targets: [Double] = stride(from: 0.0, to: 60_000.0, by: 1_500.0).map { $0 }
        for placement in stationModelPlacements {
            let center = chainageFromCenter(distanceM: placement.chainageM, route: route, travelDirection: travelDirection)
            guard center > 600, center < 59_400 else { continue }
            targets.append(center + (travelDirection == .up ? -400 : 400))
        }
        targets.sort()
        var dedupedTargets: [Double] = []
        for target in targets where dedupedTargets.last.map({ target - $0 >= 250 }) ?? true {
            dedupedTargets.append(target)
        }
        // quality37: a signal post at ±3.7 m would stand on a throat
        // fan siding (the siding sweeps from 2.1 m out to 6.3 m), so
        // targets inside a fan span move just outside it. The fan
        // spans are kept in the placements' frame; convert to the
        // centre frame these targets use.
        let fanSpansCenter: [(start: Double, end: Double)] = throatFanSpans().map { span in
            let a = chainageFromCenter(distanceM: span.start, route: route, travelDirection: travelDirection)
            let b = chainageFromCenter(distanceM: span.end, route: route, travelDirection: travelDirection)
            return (start: min(a, b), end: max(a, b))
        }
        dedupedTargets = dedupedTargets.map { target in
            for span in fanSpansCenter where target > span.start && target < span.end {
                return target - span.start < span.end - target ? span.start - 12 : span.end + 12
            }
            return target
        }
        for target in dedupedTargets {
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
            let yaw = simd_quatf(angle: -sample.heading, axis: SIMD3<Float>(0, 1, 0))
            // quality37: the post used to stand 1.6 m from the
            // running track's centre — inside the structure gauge
            // (about 1.9 m), as the user spotted. It now stands
            // 2.25 m out at ground level; on a viaduct it steps in
            // to the deck edge and its foot drops to the deck,
            // like the noise walls. The head is a real three-lamp
            // unit: backboard, hooded round lenses in the real
            // order (yellow over red over green), ladder, plate.
            let lift = sample.elevationM - groundLevelM(at: sample)
            let sideSign: Float = travelDirection == .up ? -1 : 1
            let lateral = sideSign * (lift >= 2 ? Float(4.08) : Float(4.35))
            let base = routeOffsetPoint(sample, lateral: lateral)
            let footY = base.y - (lift >= 2 ? Float(0.49) : Float(0.10))
            let postTop = base.y + 4.62
            let forward = SIMD3<Float>(sin(sample.heading), 0, -cos(sample.heading))
            addBox(parent: world, name: "signal-post-\(Int(target))", size: SIMD3<Float>(0.16, postTop - footY, 0.16),
                   position: SIMD3<Float>(base.x, (footY + postTop) / 2, base.z), material: poleMaterial, orientation: yaw)
            addBox(parent: world, name: "signal-backboard-\(Int(target))", size: SIMD3<Float>(0.62, 1.34, 0.04),
                   position: SIMD3<Float>(base.x + forward.x * 0.09, base.y + 3.9, base.z + forward.z * 0.09), material: headMaterial, orientation: yaw)
            addBox(parent: world, name: "signal-head-\(Int(target))", size: SIMD3<Float>(0.36, 1.16, 0.24),
                   position: SIMD3<Float>(base.x, base.y + 3.9, base.z), material: headMaterial, orientation: yaw)
            addBox(parent: world, name: "signal-ladder-\(Int(target))", size: SIMD3<Float>(0.3, postTop - footY - 0.4, 0.04),
                   position: SIMD3<Float>(base.x + forward.x * 0.15, (footY + postTop) / 2, base.z + forward.z * 0.15), material: headMaterial, orientation: yaw)
            addBox(parent: world, name: "signal-plate-\(Int(target))", size: SIMD3<Float>(0.22, 0.3, 0.02),
                   position: SIMD3<Float>(base.x - forward.x * 0.1, base.y + 2.55, base.z - forward.z * 0.1), material: plateMaterial, orientation: yaw)
            // Lamps sit on the face turned toward the approaching
            // train (opposite the direction of travel).
            let lampX = base.x - forward.x * 0.17
            let lampZ = base.z - forward.z * 0.17
            var lamps: [ModelEntity] = []
            for lampY in [4.25, 3.9, 3.55] {
                addBox(parent: world, name: "signal-hood-\(Int(target))-\(lampY)", size: SIMD3<Float>(0.27, 0.06, 0.3),
                       position: SIMD3<Float>(lampX, base.y + Float(lampY) + 0.14, lampZ), material: headMaterial, orientation: yaw)
                let lamp = ModelEntity(mesh: MeshResource.generateSphere(radius: 0.105),
                                       materials: [signalDarkLampMaterial])
                lamp.scale = SIMD3<Float>(1, 1, 0.45)
                lamp.position = SIMD3<Float>(lampX, base.y + Float(lampY), lampZ)
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
        // The head's lamp order is the real three-lamp order:
        // yellow over red over green.
        lamps[0].model?.materials = [aspect == .yellow ? signalYellowMaterial : signalDarkLampMaterial]
        lamps[1].model?.materials = [aspect == .red ? signalRedMaterial : signalDarkLampMaterial]
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
                let yaw = simd_quatf(angle: -sample.heading, axis: SIMD3<Float>(0, 1, 0))
                let nextIndex = inside[min(offsetIndex + 2, inside.count - 1)]
                let length = max(Float(samples[nextIndex].distanceM - sample.distanceM), 8)
                for side in [-1.0, 1.0] {
                    let lateral = Float(side) * 5.6
                    let x = sample.x + lateral * cos(sample.heading)
                    let z = sample.z + lateral * sin(sample.heading)
                    addBox(parent: world, name: "tunnel-wall-\(Int(range.start))-\(index)-\(Int(side))",
                           size: SIMD3<Float>(0.5, 6.2, length), position: SIMD3<Float>(x, sample.elevationM + 3.1, z),
                           material: tunnelMaterial, orientation: yaw)
                }
                addBox(parent: world, name: "tunnel-roof-\(Int(range.start))-\(index)",
                       size: SIMD3<Float>(11.7, 0.5, length), position: SIMD3<Float>(sample.x, sample.elevationM + 6.45, sample.z),
                       material: tunnelMaterial, orientation: yaw)
            }
            // Portal frames at both ends: two pillars and a lintel,
            // leaving the bore opening clear.
            for boundary in [range.start, range.end] {
                let portalSample = sample(at: boundary)
                let yaw = simd_quatf(angle: -portalSample.heading, axis: SIMD3<Float>(0, 1, 0))
                for side in [-1.0, 1.0] {
                    let lateral = Float(side) * 7.9
                    let x = portalSample.x + lateral * cos(portalSample.heading)
                    let z = portalSample.z + lateral * sin(portalSample.heading)
                    addBox(parent: world, name: "tunnel-portal-\(Int(boundary))-\(Int(side))",
                           size: SIMD3<Float>(4.6, 9.2, 0.9), position: SIMD3<Float>(x, portalSample.elevationM + 4.6, z),
                           material: concreteMaterial, orientation: yaw)
                }
                addBox(parent: world, name: "tunnel-portal-lintel-\(Int(boundary))",
                       size: SIMD3<Float>(20.4, 3.0, 0.9), position: SIMD3<Float>(portalSample.x, portalSample.elevationM + 7.7, portalSample.z),
                       material: concreteMaterial, orientation: yaw)
            }
        }
    }

    /// Overhead contact system in the real three-element form
    /// (quality24, C2, from the user's reference diagram): a
    /// messenger wire (ちょう架線) carried on portal masts, hangers
    /// (ハンガー) dropping from it, and the contact wire
    /// (トロリー線) at exactly 5.0 m above the rail head, zig-zagging
    /// ±0.25 m about each track centre (stagger, so the pantograph
    /// carbon strip wears evenly instead of grooving).
    ///
    /// What was wrong before, in numbers: the whole system was
    /// built in a frame shifted +2.1 m to one side — masts at
    /// laterals −3.2/+7.4, the crossbeam centred at +2.1, and the
    /// two wire runs at offsets 0.0 and +4.2 — so the wires hung
    /// over the centreline and 2.1 m OUTSIDE the far track rather
    /// than over the running rails at −2.1/+2.1. The wire boxes
    /// sat at elevation +4.95, only 4.64 m above the rail head
    /// (rail head top = elevation +0.3065); there was no messenger
    /// wire and no hangers at all; and the crossbeam at +5.15 was
    /// BELOW the contact wire's proper height, so it would have
    /// blocked the wire outright.
    ///
    /// Wire points are computed in the same banked frame as the
    /// rail profile (profileStation): heights run along the canted
    /// up axis from the rail head, stagger along the canted
    /// lateral axis. A purely horizontal offset would drift up to
    /// ~0.22 m sideways at 5 m height on the line's maximum cant,
    /// which alone would eat the ±0.25 m stagger tolerance.
    private func buildCatenary(route: RailwayRouteProfile, routeVariant: RegionalRouteVariant, travelDirection: RegionalTravelDirection, showcaseSection: Bool = false) {
        // quality35: line-wide support pitch of about 50 m
        // (46-54 m, varying deterministically). The 2026-11-10
        // front-view reference study measured real railways at
        // 40-55 m in every scene type, while the old budget-derived
        // pitch was 340 m outside the showcase section — the single
        // largest measured gap to reality. The masts and beams are
        // batched below (not individual entities), which is what
        // makes ~1,360 supports affordable; the showcase section's
        // separate 45 m insertion is no longer needed.
        _ = showcaseSection
        var chainages: [Double] = []
        var cursor = 12.0
        var stepIndex = 0
        while cursor < route.distanceM {
            chainages.append(cursor)
            cursor += 50 + Double((stepIndex * 37) % 9) - 4
            stepIndex += 1
        }
        // quality25 (B): no support inside a station zone — the
        // portal masts at ±4.0 m would stand on the new platforms
        // (which reach 3.6–8.1 m from the route centre) and the
        // crossbeam would cut across the station core. The wires
        // simply span the station, as they span any longer gap.
        // quality37: also clear of the throat fan sidings — a mast
        // at ±4.0 m would stand on a siding that sweeps out to
        // 6.3 m. The wires span the throat, as they span stations.
        chainages = chainages.filter { !inStationZone($0) && !nearThroatFan($0) }
        // Track laterals at a chainage, the same rule as the
        // trackbed (buildTrack): both tracks where a passing track
        // exists, otherwise only the running track — wires are
        // strung over tracks that exist, nowhere else.
        func trackLaterals(at distance: Double) -> [Float] {
            let isMainlineSection = travelDirection == .up ? distance < 60_000 : distance >= 8_000
            let hasPassingTrack = routeVariant == .mainline || (routeVariant == .throughBranch && isMainlineSection)
            if hasPassingTrack { return [-2.1, 2.1] }
            return [travelDirection == .up ? -2.1 : 2.1]
        }
        // One point of one track's wire system, in the banked frame:
        // `heightAboveRail` runs from the rail head (profile
        // y = 0.3065) along the canted up axis, `stagger` from the
        // track centre along the canted lateral axis.
        func wirePoint(at distance: Double, trackLateral: Float, stagger: Float, heightAboveRail: Float) -> SIMD3<Float> {
            let s = sample(at: distance)
            let bankCos = cos(s.bankRadians)
            let bankSin = sin(s.bankRadians)
            let headCos = cos(s.heading)
            let headSin = sin(s.heading)
            let center = SIMD3<Float>(s.x + trackLateral * headCos, s.elevationM, s.z + trackLateral * headSin)
            let axisX = SIMD3<Float>(bankCos * headCos, -bankSin, bankCos * headSin)
            let axisY = SIMD3<Float>(bankSin * headCos, bankCos, bankSin * headSin)
            return center + axisX * stagger + axisY * (0.3065 + heightAboveRail)
        }
        var wireBatch = MeshBatchBuilder()
        var wireBatchIndex = 0
        var wireBatchStartChainage = chainages.first ?? 0
        func flushWireBatch() {
            if let mesh = wireBatch.build(name: "catenary-wires-\(wireBatchIndex)", material: wireMaterial) {
                world.addChild(mesh)
                wireBatchIndex += 1
            }
            wireBatch = MeshBatchBuilder()
        }
        // quality35: supports are batched on the same 2,400 m
        // cadence as the wires (see buildCatenary's pitch note).
        var supportBatch = MeshBatchBuilder()
        var supportBatchIndex = 0
        func flushSupportBatch() {
            if let mesh = supportBatch.build(name: "catenary-supports-\(supportBatchIndex)", material: poleMaterial) {
                world.addChild(mesh)
                supportBatchIndex += 1
            }
            supportBatch = MeshBatchBuilder()
        }
        var previousChainage: Double? = nil
        for (index, distance) in chainages.enumerated() {
            let sample = sample(at: distance)
            let heading = sample.heading
            // Portal masts at ±4.0 m: clear of the trackbed (2.3 m)
            // and the deck cable trough (3.85 m), and just inside
            // the deck edge (4.2 m) where the line is on viaduct;
            // at ground level they stand inside the ±4.9 m trough.
            let lift = sample.elevationM - groundLevelM(at: sample)
            let mastBase = lift >= 2 ? sample.elevationM - 0.49 : sample.elevationM - 0.10
            // Crossbeam at rail head +6.45 m; the messenger rides at
            // contact +1.30 = rail head +6.30 at the supports, so
            // the wires hang just under the beam.
            let beamY = sample.elevationM + 0.3065 + 6.45
            let mastHeight = beamY + 0.1 - mastBase
            for lateral in [Float(-4), Float(4)] {
                let x = sample.x + lateral * cos(heading)
                let z = sample.z + lateral * sin(heading)
                supportBatch.addBox(center: SIMD3<Float>(x, mastBase + mastHeight / 2, z), size: SIMD3<Float>(0.18, mastHeight, 0.2), yaw: -heading)
            }
            supportBatch.addBox(center: SIMD3<Float>(sample.x, beamY, sample.z), size: SIMD3<Float>(8.6, 0.12, 0.16), yaw: -heading)
            // Wires reach back to the previous support. Stagger
            // alternates ±0.25 m support by support, interpolated
            // linearly between them — the classic zig-zag.
            if let previous = previousChainage {
                if previous - wireBatchStartChainage >= 2_400 {
                    flushWireBatch()
                    flushSupportBatch()
                    wireBatchStartChainage = previous
                }
                let staggerHere: Float = index.isMultiple(of: 2) ? 0.25 : -0.25
                let staggerPrev: Float = (index - 1).isMultiple(of: 2) ? 0.25 : -0.25
                let spanLength = distance - previous
                let subdivisions = max(1, Int((spanLength / 8.5).rounded()))
                let hangerEvery = max(1, subdivisions / 4)
                for trackLateral in trackLaterals(at: (previous + distance) / 2) {
                    var contactPrev: SIMD3<Float>? = nil
                    var messengerPrev: SIMD3<Float>? = nil
                    for stepIndex in 0...subdivisions {
                        let u = Double(stepIndex) / Double(subdivisions)
                        let d = previous + spanLength * u
                        let stagger = staggerPrev + (staggerHere - staggerPrev) * Float(u)
                        // System height (messenger above contact):
                        // 1.30 m at the supports, sagging to 0.60 m
                        // at mid-span.
                        let du = 2 * u - 1
                        let systemHeight = Float(0.6 + 0.7 * du * du)
                        let contact = wirePoint(at: d, trackLateral: trackLateral, stagger: stagger, heightAboveRail: 5)
                        let messenger = wirePoint(at: d, trackLateral: trackLateral, stagger: stagger, heightAboveRail: 5 + systemHeight)
                        if let cp = contactPrev, let mp = messengerPrev {
                            wireBatch.addSegment(from: cp, to: contact, thickness: 0.03)
                            wireBatch.addSegment(from: mp, to: messenger, thickness: 0.03)
                        }
                        if stepIndex > 0, stepIndex < subdivisions, stepIndex.isMultiple(of: hangerEvery) {
                            wireBatch.addSegment(from: contact, to: messenger, thickness: 0.015)
                        }
                        contactPrev = contact
                        messengerPrev = messenger
                    }
                }
            }
            previousChainage = distance
        }
        flushWireBatch()
        flushSupportBatch()
    }

    /// One city tower built from stacked facade segments (each segment
    /// shows the office-facade texture once, so windows keep a realistic
    /// ~3 m floor height instead of stretching over the whole tower).
    private func addTower(at distance: Double, side: Float, seed: Int, band: Int, route: RailwayRouteProfile, routeVariant: RegionalRouteVariant, travelDirection: RegionalTravelDirection, lateralOverride: Float? = nil, heightScale: Float = 1) {
        let sample = sample(at: distance)
        // Towers stand on the ground, not on the track: under a
        // viaduct they rise from the valley floor.
        let groundY = groundLevelM(at: sample)
        let lateral: Float = lateralOverride ?? ((band == 2 ? 12.5 : 13.5) + Float(seed % 3) * 1.4)
        let width: Float = 11 + Float((seed / 3) % 4) * 1.4
        // quality32: depth is the along-track extent of the box, so
        // a longer depth closes the gaps in the downtown frontage
        // (was 10-13.2 m of facade per 27 m step).
        let depth: Float = 12 + Float((seed / 7) % 4) * 1.8
        var height: Float = 15 + Float((seed * 29) % 100) / 100 * (band == 2 ? 30 : 15)
        if band == 2 {
            let c = chainageFromCenter(distanceM: distance, route: route, travelDirection: travelDirection)
            height *= Float(1.05 - (c / 4_200) * 0.45)
            height = max(15, height)
            // quality35: every sixth downtown tower is a tall one
            // (about 1.5x), so the front row has the 2-4x height
            // jumps between neighbours that real front views show
            // (reference study, 2026-11-10).
            if seed % 6 == 0 {
                height *= 1.5
            }
        }
        height *= heightScale
        // quality32: beside an elevated section the towers rise
        // from the valley floor far below the rails, so at their
        // old heights most of them never reached the driver's eye
        // and the downtown climb read as nearly building-free.
        // Full-height towers beside a structure now rise well
        // above rail level, the way real buildings flank an urban
        // elevated line; low podium blocks (heightScale < 0.9)
        // keep their street-level height.
        if heightScale >= 0.9 {
            let structureHeight = sample.elevationM - groundY
            if structureHeight > 3 {
                let aboveRail: Float = band == 2
                    ? 14 + Float((seed * 37) % 12)
                    : 10 + Float((seed * 37) % 8)
                height = max(height, Float(structureHeight) + aboveRail)
            }
        }
        // quality29: no station check used to exist here, so a
        // tower face could land inside a station platform (the
        // Matsubaracho apartment sliced by the platform back).
        guard buildingClearOfPlatforms(chainage: distance, halfLength: Double(width) / 2, lateral: lateral, halfDepth: depth / 2) else { return }
        let segments = max(1, Int((height / 15).rounded()))
        let segmentHeight = height / Float(segments)
        let offset = side * lateral
        let x = sample.x + offset * cos(sample.heading)
        let z = sample.z + offset * sin(sample.heading)
        let orientation = simd_quatf(angle: -sample.heading, axis: SIMD3<Float>(0, 1, 0))
        // Apartment facades only on mid-rise towers; tall ones are
        // office or glass.
        let materialPool = height > 30 ? Array(officeMaterials.prefix(4)) : officeMaterials
        let material = materialPool[abs(seed) % materialPool.count]
        for segment in 0..<segments {
            let box = addBox(parent: world, name: "office-tower-\(seed)-\(segment)",
                             size: SIMD3<Float>(width, segmentHeight, depth),
                             position: SIMD3<Float>(x, groundY + segmentHeight * (Float(segment) + 0.5), z),
                             material: material)
            box.orientation = orientation
        }
        let roof = addBox(parent: world, name: "office-roof-\(seed)",
                          size: SIMD3<Float>(width + 0.4, 0.3, depth + 0.4),
                          position: SIMD3<Float>(x, groundY + height + 0.15, z),
                          material: roofMaterials[abs(seed) % roofMaterials.count])
        roof.orientation = orientation
        // Rooftop block (stair tower / tank) on some towers so the
        // silhouette is not a plain card edge.
        if seed % 2 == 0 {
            let block = addBox(parent: world, name: "office-rooftop-\(seed)",
                               size: SIMD3<Float>(width * 0.34, 2.3, depth * 0.4),
                               position: SIMD3<Float>(x, groundY + height + 1.15, z),
                               material: concreteMaterial)
            block.orientation = orientation
        }
        // Slightly proud ground-floor band: hides the wall/ground seam
        // and reads as a storefront/podium base.
        let baseBand = addBox(parent: world, name: "office-base-\(seed)",
                              size: SIMD3<Float>(width + 0.18, 3.1, depth + 0.18),
                              position: SIMD3<Float>(x, groundY + 1.55, z),
                              material: band == 2 ? glassMaterial : concreteMaterial)
        baseBand.orientation = orientation
    }

    /// quality34: one-box towers for the deep urban rows (roughly
    /// 60 m and 110 m out). At that distance the segmented facade,
    /// roof block and base band of addTower are invisible, so a
    /// single box with a facade texture carries the mass; the rows
    /// give the city depth behind the detailed front rows, which
    /// used to stand alone against flat empty apron.
    private func addDistantTower(at distance: Double, side: Float, seed: Int, lateral: Float, band: Int, heightOverride: Float? = nil) {
        let sample = sample(at: distance)
        let groundY = groundLevelM(at: sample)
        let width: Float = 17 + Float((seed / 3) % 4) * 2.2
        let depth: Float = 15 + Float((seed / 7) % 4) * 2.4
        var height: Float = band == 2 ? 26 + Float((seed * 31) % 30) : 19 + Float((seed * 31) % 20)
        // quality35: the deep rows carry the city's real height
        // range — about one in five is a high-rise of 60-120 m and
        // a few are landmarks above that (heightOverride). Until
        // now nothing in the scene exceeded 56 m, while the
        // reference study found 150 m-class towers in ordinary
        // downtown front views.
        if seed % 5 == 0 {
            height *= 2.2
        } else if seed % 5 == 1 {
            height *= 1.5
        }
        if let heightOverride = heightOverride {
            height = max(height, heightOverride)
        }
        // Beside an elevated section the deep rows also rise from
        // the valley floor; keep their tops above rail level so
        // they register over the nearer rows' bases.
        let structureHeight = sample.elevationM - groundY
        if structureHeight > 3 {
            height = max(height, structureHeight + 9 + Float((seed * 13) % 13))
        }
        let offset = side * lateral
        let x = sample.x + offset * cos(sample.heading)
        let z = sample.z + offset * sin(sample.heading)
        let material = officeMaterials[abs(seed) % officeMaterials.count]
        let orientation = simd_quatf(angle: -sample.heading, axis: SIMD3<Float>(0, 1, 0))
        // Stacked in up-to-30 m segments so the facade texture
        // repeats instead of stretching over the full height.
        let segments = max(1, Int((height / 30).rounded()))
        let segmentHeight = height / Float(segments)
        for segment in 0..<segments {
            let body = addBox(parent: world, name: "distant-tower-\(seed)-\(segment)",
                              size: SIMD3<Float>(width, segmentHeight, depth),
                              position: SIMD3<Float>(x, groundY + segmentHeight * (Float(segment) + 0.5), z),
                              material: material)
            body.orientation = orientation
        }
    }

    /// quality34: a plain second-row house for the suburbs, about
    /// 25 m out, so the housing does not stop at one trackside row.
    private func addBackRowHouse(at distance: Double, side: Float, seed: Int) {
        let sample = sample(at: distance)
        let groundY = groundLevelM(at: sample)
        let lateral: Float = 24 + Float(seed % 3) * 2.2
        let width: Float = 5.4 + Float((seed / 3) % 3) * 0.9
        let depth: Float = 5.8 + Float((seed / 5) % 3) * 0.8
        let height: Float = 3.8 + Float((seed / 7) % 4) * 0.6
        guard buildingClearOfPlatforms(chainage: distance, halfLength: Double(width) / 2, lateral: lateral, halfDepth: depth / 2) else { return }
        let offset = side * lateral
        let x = sample.x + offset * cos(sample.heading)
        let z = sample.z + offset * sin(sample.heading)
        let orientation = simd_quatf(angle: -sample.heading, axis: SIMD3<Float>(0, 1, 0))
        let body = addBox(parent: world, name: "back-row-home-\(seed)",
                          size: SIMD3<Float>(width, height, depth),
                          position: SIMD3<Float>(x, groundY + height / 2, z),
                          material: seed % 3 == 2 ? houseFacadeMaterial : buildingMaterials[abs(seed) % buildingMaterials.count])
        body.orientation = orientation
        let roof = addBox(parent: world, name: "back-row-roof-\(seed)",
                          size: SIMD3<Float>(width + 0.45, 0.24, depth + 0.35),
                          position: SIMD3<Float>(x, groundY + height + 0.14, z),
                          material: roofMaterials[abs(seed) % roofMaterials.count])
        roof.orientation = orientation
    }

    private func buildSuburb(route: RailwayRouteProfile, routeVariant: RegionalRouteVariant, travelDirection: RegionalTravelDirection) {
        let sceneryMaterials = buildingMaterials
        let landmarks = fictionalCorridorLandmarks(for: route)
        var index = 0
        var urbanIndex = 0
        var foliageCount = 0
        var lastWoodlandBlock = -1
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
                    // quality32: every step now (was every other), so
                    // the second row reads as a continuous skyline.
                    addTower(at: distance + 4.5, side: urbanIndex % 4 == 0 ? 1 : -1, seed: urbanIndex * 7 + 3, band: band, route: route, routeVariant: routeVariant, travelDirection: travelDirection, lateralOverride: 30 + Float(urbanIndex % 3) * 2.5, heightScale: 1.2)
                    // quality32: a low commercial podium on one side
                    // of each downtown step closes the street wall at
                    // eye level between the towers.
                    if band == 2 {
                        addTower(at: distance + 13, side: urbanIndex.isMultiple(of: 2) ? 1 : -1, seed: urbanIndex * 11 + 5, band: band, route: route, routeVariant: routeVariant, travelDirection: travelDirection, lateralOverride: 11.8, heightScale: 0.34)
                    }
                    // quality34: deep rows of plain towers behind
                    // the detailed frontage (about 60 m and 110 m
                    // out), so the buildings have depth instead of
                    // ending at the trackside row.
                    if urbanIndex.isMultiple(of: 2) {
                        addDistantTower(at: distance + 7, side: 1, seed: urbanIndex * 13 + 7, lateral: 58 + Float((urbanIndex / 2) % 3) * 6, band: band)
                        addDistantTower(at: distance + 16, side: -1, seed: urbanIndex * 13 + 8, lateral: 64 + Float((urbanIndex / 2) % 3) * 6, band: band)
                    }
                    if urbanIndex.isMultiple(of: 3) {
                        addDistantTower(at: distance + 3, side: -1, seed: urbanIndex * 19 + 11, lateral: 102 + Float((urbanIndex / 3) % 3) * 10, band: band)
                        addDistantTower(at: distance + 19, side: 1, seed: urbanIndex * 19 + 12, lateral: 112 + Float((urbanIndex / 3) % 3) * 10, band: band)
                    }
                    // quality35: a downtown landmark tower every
                    // eighth step (about every 175 m), 105-135 m at
                    // roughly 120 m out, alternating sides.
                    if band == 2, urbanIndex % 8 == 4 {
                        addDistantTower(at: distance + 10, side: urbanIndex % 16 == 4 ? 1 : -1, seed: urbanIndex * 23 + 15, lateral: 118 + Float((urbanIndex / 8) % 3) * 9, band: band, heightOverride: 105 + Float((urbanIndex * 7) % 30))
                    }
                }
                urbanIndex += 1
                // quality32: tighter downtown frontage (was 27/36 m
                // steps with 11-15 m towers, about half the frontage
                // left as empty gaps).
                distance += band == 2 ? 22 : 30
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
            // Houses stand on the ground: under a viaduct they sit
            // on the valley floor with the piers, not at rail level.
            let groundY = groundLevelM(at: sample)
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
            // quality29: houses keep clear of station platforms too
            // (a house face could reach 5.1 m from the centre, well
            // inside the 8.12 m platform back).
            if !buildingClearOfPlatforms(chainage: distance, halfLength: Double(width) / 2, lateral: lateral, halfDepth: depth / 2) {
                index += 1
                distance += buildingStep
                continue
            }
            let offset = sign * lateral
            let x = sample.x + offset * cos(sample.heading)
            let z = sample.z + offset * sin(sample.heading)
            // quality38 (photoreal batch 2): break the metronome.
            // Houses keep off the new level-crossing roads, and the
            // suburban density follows the surveyed waveform: a peak
            // near stations, thinning between them where low-use
            // land (monthly parking, vacant lots) takes whole plots.
            if nearCrossing(distance, margin: 9) {
                index += 1
                distance += buildingStep
                continue
            }
            let nearestStation = stationModelPlacements.map { abs($0.chainageM - distance) }.min() ?? .infinity
            if nearestStation <= 260, !shed, index % 3 == 0 {
                // Station-front apartment slab instead of a house:
                // flat-roofed, facade-textured, 3-5 floors.
                let aptHeight = 9.5 + Float(index % 4) * 2.6
                let apt = addBox(parent: world, name: "station-apartment-\(index)", size: SIMD3<Float>(11.5, aptHeight, 7.6), position: SIMD3<Float>(x, groundY + aptHeight / 2, z), material: officeMaterials[index % officeMaterials.count])
                apt.orientation = simd_quatf(angle: -sample.heading, axis: SIMD3<Float>(0, 1, 0))
                _ = addBox(parent: world, name: "station-apartment-roof-\(index)", size: SIMD3<Float>(11.9, 0.3, 8.0), position: SIMD3<Float>(x, groundY + aptHeight + 0.15, z), material: roofMaterials[index % roofMaterials.count], orientation: simd_quatf(angle: -sample.heading, axis: SIMD3<Float>(0, 1, 0)))
                index += 1
                distance += buildingStep
                continue
            }
            if nearestStation > 700, !shed, index % 10 == 3 || index % 10 == 7 {
                // Low-use plot: asphalt pad, and a signpost on the
                // parking variant. No house, no roof, no windows.
                _ = addBox(parent: world, name: "lowuse-lot-\(index)", size: SIMD3<Float>(width + 3.4, 0.07, depth + 3.2), position: SIMD3<Float>(x, groundY + 0.035, z), material: roadMaterial, orientation: simd_quatf(angle: -sample.heading, axis: SIMD3<Float>(0, 1, 0)))
                if index % 10 == 3 {
                    let postPoint = groundOffsetPoint(sample, lateral: offset - sign * (width / 2))
                    _ = addBox(parent: world, name: "lowuse-sign-\(index)", size: SIMD3<Float>(0.09, 1.7, 0.09), position: SIMD3<Float>(postPoint.x, postPoint.y + 0.85, postPoint.z), material: poleMaterial)
                    _ = addBox(parent: world, name: "lowuse-board-\(index)", size: SIMD3<Float>(0.06, 0.5, 0.9), position: SIMD3<Float>(postPoint.x, postPoint.y + 1.55, postPoint.z), material: roofMaterials[2], orientation: simd_quatf(angle: -sample.heading, axis: SIMD3<Float>(0, 1, 0)))
                }
                index += 1
                distance += buildingStep
                continue
            }
            // Every third house wears the full photo facade; its windows
            // and door are painted in, so the separate boxes are skipped.
            let useFacadeTexture = !shed && index % 3 == 2
            let bodyMaterial = useFacadeTexture ? houseFacadeMaterial : sceneryMaterials[index % sceneryMaterials.count]
            let building = addBox(parent: world, name: shed ? "fictional-shed-\(index)" : "fictional-home-\(index)", size: SIMD3<Float>(width, height, depth), position: SIMD3<Float>(x, groundY + height / 2, z), material: bodyMaterial)
            building.orientation = simd_quatf(angle: -sample.heading, axis: SIMD3<Float>(0, 1, 0))

            if !index.isMultiple(of: 3) {
                let roof = addBox(parent: world, name: "roof-\(index)", size: SIMD3<Float>(width + 0.45, 0.24, depth + 0.35), position: SIMD3<Float>(x, groundY + height + 0.14, z), material: roofMaterials[index % roofMaterials.count], orientation: simd_quatf(angle: -sample.heading, axis: SIMD3<Float>(0, 1, 0)))
                roof.orientation = roof.orientation * simd_quatf(angle: Float(index.isMultiple(of: 2) ? 0.04 : -0.04), axis: SIMD3<Float>(0, 0, 1))
            } else {
                let balconySample = self.sample(at: distance - Double(depth * 0.52))
                let balconyPoint = groundOffsetPoint(balconySample, lateral: offset)
                let balcony = addBox(parent: world, name: "balcony-\(index)", size: SIMD3<Float>(width + 0.35, 0.12, 0.35), position: SIMD3<Float>(balconyPoint.x, balconyPoint.y + height * 0.56, balconyPoint.z), material: concreteMaterial)
                balcony.orientation = simd_quatf(angle: -sample.heading, axis: SIMD3<Float>(0, 1, 0))
            }

            if !useFacadeTexture {
                let facadeLateral = offset - sign * (width / 2 + 0.035)
                for window in 0..<2 {
                    let windowSample = self.sample(at: distance + Double((Float(window) - 0.5) * depth * 0.42))
                    let windowPoint = groundOffsetPoint(windowSample, lateral: facadeLateral)
                    let pane = addBox(parent: world, name: "window-\(index)-\(window)", size: SIMD3<Float>(0.07, 0.72, 0.78), position: SIMD3<Float>(windowPoint.x, windowPoint.y + min(height * 0.72, 2.45), windowPoint.z), material: glassMaterial)
                    pane.orientation = simd_quatf(angle: -sample.heading, axis: SIMD3<Float>(0, 1, 0))
                }
                let doorPoint = groundOffsetPoint(sample, lateral: facadeLateral)
                let door = addBox(parent: world, name: "door-\(index)", size: SIMD3<Float>(0.07, 1.8, 0.78), position: SIMD3<Float>(doorPoint.x, doorPoint.y + 0.95, doorPoint.z), material: roofMaterials[(index + 1) % roofMaterials.count])
                door.orientation = simd_quatf(angle: -sample.heading, axis: SIMD3<Float>(0, 1, 0))
            }

            // quality34: a second row of houses deeper in the
            // suburb (about 25 m out) every fourth house, never on
            // the sea side of the coastal stretch.
            if index % 4 == 2,
               !(isCoastal(distanceM: distance, route: route, routeVariant: routeVariant, travelDirection: travelDirection)
                 && sign == seaSideSign(travelDirection: travelDirection)) {
                addBackRowHouse(at: distance + 6, side: sign, seed: index * 3 + 1)
            }

            if index.isMultiple(of: 2), foliageCount < renderQualitySettings.foliageInstanceLimit {
                let treeSample = self.sample(at: distance + 5)
                let treePoint = groundOffsetPoint(treeSample, lateral: offset + sign * width * 0.65)
                addTree(parent: world, name: "tree-\(index)", x: treePoint.x, z: treePoint.z, height: 2.9 + Float((index * 7) % 9) * 0.45, material: foliageMaterials[index % foliageMaterials.count], groundY: treePoint.y)
                foliageCount += 1
            }
            // Lineside planting, BVE-style: on the measured Tobu Tojo
            // route trees are the lead actor of the suburban scenery
            // (~1,000 placements in 32 km), standing in near-continuous
            // rows and clumps in the 8-25 m band, not as isolated
            // specimens. Three deterministic layers approximate that
            // here, all inside the foliage instance budget: a row on
            // the side opposite the houses, small groves of close-
            // spaced trees, and a denser woodland belt every few
            // hundred metres. Placement is a pure function of the
            // house index / chainage, so every build is identical.
            if index.isMultiple(of: 2), (index * 7) % 10 < 7, foliageCount < renderQualitySettings.foliageInstanceLimit {
                let rowDistance = distance + 8
                let rowSign = -sign
                let rowOnSeaSide = isCoastal(distanceM: rowDistance, route: route, routeVariant: routeVariant, travelDirection: travelDirection)
                    && rowSign == seaSideSign(travelDirection: travelDirection)
                if !rowOnSeaSide, !corridorReserved(at: rowDistance, landmarks: landmarks) {
                    let rowSample = self.sample(at: rowDistance)
                    let rowPoint = groundOffsetPoint(rowSample, lateral: rowSign * (18 + Float((index * 5) % 6)))
                    addTree(parent: world, name: "rowtree-\(index)", x: rowPoint.x, z: rowPoint.z, height: 3.4 + Float((index * 11) % 8) * 0.5, material: foliageMaterials[(index + 1) % foliageMaterials.count], groundY: rowPoint.y)
                    foliageCount += 1
                }
            }
            if index.isMultiple(of: 2) {
                for cluster in 0..<2 where foliageCount < renderQualitySettings.foliageInstanceLimit {
                    let groveIndex = index * 2 + cluster
                    if groveIndex % 3 == 0 { continue }
                    let groveDistance = distance + 13 + Double(cluster * 19) + Double(groveIndex % 5)
                    if groveDistance >= route.distanceM - 60 || corridorReserved(at: groveDistance, landmarks: landmarks) { continue }
                    let groveSign: Float = groveIndex % 2 == 0 ? sign : -sign
                    if isCoastal(distanceM: groveDistance, route: route, routeVariant: routeVariant, travelDirection: travelDirection),
                       groveSign == seaSideSign(travelDirection: travelDirection) { continue }
                    let groveSample = self.sample(at: groveDistance)
                    let groveLateral = groveSign * (15 + Float((groveIndex * 11) % 16))
                    let grovePoint = groundOffsetPoint(groveSample, lateral: groveLateral)
                    // A clump, not a point: two crowns a few metres apart.
                    addTree(parent: world, name: "grove-\(groveIndex)", x: grovePoint.x, z: grovePoint.z, height: 3.0 + Float((groveIndex * 7) % 10) * 0.42, material: foliageMaterials[groveIndex % foliageMaterials.count], groundY: grovePoint.y)
                    foliageCount += 1
                    if foliageCount < renderQualitySettings.foliageInstanceLimit {
                        let clumpSample = self.sample(at: groveDistance + 4)
                        let clumpPoint = groundOffsetPoint(clumpSample, lateral: groveLateral + groveSign * 2.5)
                        addTree(parent: world, name: "grove-\(groveIndex)-b", x: clumpPoint.x, z: clumpPoint.z, height: 2.6 + Float((groveIndex * 5) % 8) * 0.4, material: foliageMaterials[(groveIndex + 1) % foliageMaterials.count], groundY: clumpPoint.y)
                        foliageCount += 1
                    }
                }
                // Woodland belt: taller trees ~60 m long, alternating
                // sides on a ~750 m grid (skipping every third block).
                let block = Int(distance / 750)
                if block != lastWoodlandBlock, block % 3 != 2 {
                    lastWoodlandBlock = block
                    let beltSign: Float = block % 2 == 0 ? 1 : -1
                    let beltOnSeaSide = isCoastal(distanceM: distance, route: route, routeVariant: routeVariant, travelDirection: travelDirection)
                        && beltSign == seaSideSign(travelDirection: travelDirection)
                    if !beltOnSeaSide {
                        for k in 0..<7 where foliageCount < renderQualitySettings.foliageInstanceLimit {
                            let beltDistance = distance + Double(k * 8) + Double((k * 37 + block * 13) % 5)
                            if beltDistance >= route.distanceM - 60 || corridorReserved(at: beltDistance, landmarks: landmarks) { continue }
                            let beltSample = self.sample(at: beltDistance)
                            let beltPoint = groundOffsetPoint(beltSample, lateral: beltSign * (19 + Float((k * 3 + block) % 8)))
                            addTree(parent: world, name: "belt-\(block)-\(k)", x: beltPoint.x, z: beltPoint.z, height: 4.2 + Float((k * 7 + block) % 9) * 0.45, material: foliageMaterials[(k + block) % foliageMaterials.count], groundY: beltPoint.y)
                            foliageCount += 1
                        }
                    }
                }
            }
            // (Utility poles used to be a single thin box here every
            // fifth house. They are now a full distribution-pole
            // system — see buildUtilityPoles.)
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
                    let fz = farSample.z + farLateral * sin(farSample.heading)
                    let fw = 5.2 + Float((index * 5) % 4) * 0.8
                    let fh = 3.4 + Float((index * 11) % 5) * 0.6
                    let fd = 5.6 + Float((index * 3) % 4) * 0.7
                    let farOrientation = simd_quatf(angle: -farSample.heading, axis: SIMD3<Float>(0, 1, 0))
                    let farGroundY = groundLevelM(at: farSample)
                    let farHouse = addBox(parent: world, name: "fictional-home-far-\(index)", size: SIMD3<Float>(fw, fh, fd), position: SIMD3<Float>(fx, farGroundY + fh / 2, fz), material: sceneryMaterials[(index + 2) % sceneryMaterials.count])
                    farHouse.orientation = farOrientation
                    let farRoof = addBox(parent: world, name: "roof-far-\(index)", size: SIMD3<Float>(fw + 0.45, 0.24, fd + 0.35), position: SIMD3<Float>(fx, farGroundY + fh + 0.14, fz), material: roofMaterials[(index + 1) % roofMaterials.count])
                    farRoof.orientation = farOrientation
                }
            }
            index += 1
            distance += buildingStep
        }
    }

    // quality38: level crossings rebuilt to the surveyed spec
    // (cat07). The old version was two token crossings (a road slab,
    // a 1.4 m post and a floating bar each) at 31 %/69 % of the
    // route. Crossings now sit wherever the line is genuinely at
    // grade: terrain within 1 m of rail level sustained over
    // +/-30 m, clear of station zones, throat fans, the tunnel
    // stretch and the coastal sea sections, spaced roughly
    // 600-1,400 m apart with a seeded jitter so the rhythm is not
    // metronomic. Each crossing is the full roadside set: a road
    // strip across the apron, stepped ramps up to deck panels laid
    // flush with the rail head, stop lines, four warning-pole units
    // (pole, crossbuck, twin red lamps with backboard, direction
    // indicator, speaker, name plate, emergency button box), two
    // barrier machines with striped arms lowered across the road,
    // and short fences tying the corners back into the lineside.
    private var crossingCenters: [Double] = []

    private func computeCrossingCenters(route: RailwayRouteProfile, routeVariant: RegionalRouteVariant, travelDirection: RegionalTravelDirection) {
        var centers: [Double] = []
        var cursor = 2_400.0
        while cursor < route.distanceM - 1_200 {
            let jitter = Double(stableIndex("crossing-\(Int(cursor))", count: 5)) * 55.0
            var probe = cursor + jitter
            var placed: Double? = nil
            while probe < cursor + jitter + 520 {
                let liftHere = sample(at: probe).elevationM - groundLevelM(at: probe)
                let liftA = sample(at: probe - 30).elevationM - groundLevelM(at: probe - 30)
                let liftB = sample(at: probe + 30).elevationM - groundLevelM(at: probe + 30)
                if liftHere < 1.0, liftA < 1.3, liftB < 1.3,
                   !inStationZone(probe, extraMargin: 45), !nearThroatFan(probe),
                   !(probe > 41_500 && probe < 44_300),
                   !isCoastal(distanceM: probe, route: route, routeVariant: routeVariant, travelDirection: travelDirection) {
                    placed = probe
                    break
                }
                probe += 25
            }
            if let found = placed {
                centers.append(found)
                cursor = found + 600
            } else {
                cursor += 850
            }
        }
        crossingCenters = centers
    }

    private func nearCrossing(_ chainage: Double, margin: Double) -> Bool {
        for center in crossingCenters where abs(chainage - center) < margin {
            return true
        }
        return false
    }

    private func buildLevelCrossings(route: RailwayRouteProfile) {
        guard !crossingCenters.isEmpty else { return }
        print("RM crossings at: \(crossingCenters.map { Int($0) })")
        for (index, center) in crossingCenters.enumerated() {
            buildOneCrossing(index: index, center: center)
        }
    }

    private func buildOneCrossing(index: Int, center: Double) {
        let s = sample(at: center)
        let heading = s.heading
        let ax = SIMD3<Float>(cos(heading), 0, sin(heading))
        let ay = SIMD3<Float>(0, 1, 0)
        let az = SIMD3<Float>(-sin(heading), 0, cos(heading))
        let origin = SIMD3<Float>(s.x, s.elevationM, s.z)
        func pt(_ lat: Float, _ up: Float, _ along: Float) -> SIMD3<Float> {
            origin + ax * lat + ay * up + az * along
        }
        let roadYaw = simd_quatf(angle: -heading, axis: SIMD3<Float>(0, 1, 0))

        // Road strip across the whole apron, deck panels flush with
        // the rail head over the tracks, and two terrace steps each
        // side so the road climbs from apron level to deck level.
        addBox(parent: world, name: "crossing-road-\(index)", size: SIMD3<Float>(150, 0.07, 5.6), position: pt(0, -0.005, 0), material: roadMaterial, orientation: roadYaw)
        addBox(parent: world, name: "crossing-deck-\(index)", size: SIMD3<Float>(10.4, 0.1, 5.6), position: pt(0, 0.237, 0), material: roadMaterial, orientation: roadYaw)
        for sideSign: Float in [-1, 1] {
            addBox(parent: world, name: "crossing-ramp1-\(index)-\(Int(sideSign))", size: SIMD3<Float>(3.2, 0.09, 5.6), position: pt(sideSign * 6.8, 0.145, 0), material: roadMaterial, orientation: roadYaw)
            addBox(parent: world, name: "crossing-ramp2-\(index)-\(Int(sideSign))", size: SIMD3<Float>(3.2, 0.09, 5.6), position: pt(sideSign * 10.0, 0.055, 0), material: roadMaterial, orientation: roadYaw)
        }

        var darkBatch = MeshBatchBuilder()
        var yellowBatch = MeshBatchBuilder()
        var whiteBatch = MeshBatchBuilder()
        var redBatch = MeshBatchBuilder()

        // Stop lines 1.8 m before the outer rail on every approach
        // half, plus short centre dashes leading into the crossing.
        for latSign: Float in [-1, 1] {
            for alongSign: Float in [-1, 1] {
                whiteBatch.addBoxAxes(center: pt(latSign * 4.83, 0.045, alongSign * 1.4), size: SIMD3<Float>(0.35, 0.02, 2.7), ax: ax, ay: ay, az: az)
            }
            whiteBatch.addBoxAxes(center: pt(latSign * 13.5, 0.042, 0), size: SIMD3<Float>(13, 0.015, 0.14), ax: ax, ay: ay, az: az)
        }

        let bladeCos = Float(cos(0.73))
        let bladeSin = Float(sin(0.73))
        for latSign: Float in [-1, 1] {
            for alongSign: Float in [-1, 1] {
                let poleLat = latSign * 4.35
                let poleAlong = alongSign * 3.55
                // Warning pole unit (spec: 3.6 m pole at the road
                // corners, about 4 m from the track centre).
                darkBatch.addBoxAxes(center: pt(poleLat, 1.8, poleAlong), size: SIMD3<Float>(0.16, 3.6, 0.16), ax: ax, ay: ay, az: az)
                darkBatch.addBoxAxes(center: pt(poleLat, 3.48, poleAlong), size: SIMD3<Float>(0.3, 0.16, 0.3), ax: ax, ay: ay, az: az)
                // Crossbuck: two blades crossed at about 42 degrees,
                // facing the road traffic.
                for flip: Float in [1, -1] {
                    let bladeUp = ay * bladeCos + az * (bladeSin * flip)
                    let bladeAlong = ay * (-bladeSin * flip) + az * bladeCos
                    yellowBatch.addBoxAxes(center: pt(poleLat + latSign * 0.06, 3.02, poleAlong), size: SIMD3<Float>(0.04, 1.25, 0.24), ax: ax, ay: bladeUp, az: bladeAlong)
                }
                // Twin red warning lamps in a housing with a back
                // disc, and the direction indicator beside them.
                darkBatch.addBoxAxes(center: pt(poleLat + latSign * 0.1, 2.32, poleAlong), size: SIMD3<Float>(0.18, 0.66, 0.36), ax: ax, ay: ay, az: az)
                darkBatch.addBoxAxes(center: pt(poleLat - latSign * 0.02, 2.32, poleAlong), size: SIMD3<Float>(0.03, 0.42, 0.42), ax: ax, ay: ay, az: az)
                for lampDy: Float in [0.16, -0.16] {
                    redBatch.addBoxAxes(center: pt(poleLat + latSign * 0.21, 2.32 + lampDy, poleAlong), size: SIMD3<Float>(0.06, 0.19, 0.19), ax: ax, ay: ay, az: az)
                }
                darkBatch.addBoxAxes(center: pt(poleLat + latSign * 0.08, 2.32, poleAlong + alongSign * 0.34), size: SIMD3<Float>(0.1, 0.55, 0.2), ax: ax, ay: ay, az: az)
                whiteBatch.addBoxAxes(center: pt(poleLat + latSign * 0.14, 2.32, poleAlong + alongSign * 0.34), size: SIMD3<Float>(0.03, 0.3, 0.1), ax: ax, ay: ay, az: az)
                // Name plate and emergency button box on the pole's
                // road face at eye height.
                whiteBatch.addBoxAxes(center: pt(poleLat + latSign * 0.1, 1.72, poleAlong), size: SIMD3<Float>(0.03, 0.48, 0.68), ax: ax, ay: ay, az: az)
                whiteBatch.addBoxAxes(center: pt(poleLat + latSign * 0.13, 1.22, poleAlong), size: SIMD3<Float>(0.15, 0.4, 0.3), ax: ax, ay: ay, az: az)
                redBatch.addBoxAxes(center: pt(poleLat + latSign * 0.22, 1.3, poleAlong), size: SIMD3<Float>(0.04, 0.1, 0.1), ax: ax, ay: ay, az: az)
                // Corner fence running back along the line.
                darkBatch.addBoxAxes(center: pt(latSign * 4.8, 0.55, poleAlong + alongSign * 8.6), size: SIMD3<Float>(0.05, 1.1, 10), ax: ax, ay: ay, az: az)

                // Barrier machines on the two diagonal corners;
                // the arm lies across the road at 1 m, striped.
                if latSign == alongSign {
                    darkBatch.addBoxAxes(center: pt(poleLat, 0.11, poleAlong), size: SIMD3<Float>(0.5, 0.22, 0.56), ax: ax, ay: ay, az: az)
                    yellowBatch.addBoxAxes(center: pt(poleLat, 0.72, poleAlong), size: SIMD3<Float>(0.42, 1.0, 0.48), ax: ax, ay: ay, az: az)
                    darkBatch.addBoxAxes(center: pt(poleLat, 1.26, poleAlong), size: SIMD3<Float>(0.46, 0.08, 0.52), ax: ax, ay: ay, az: az)
                    let armCenter = poleAlong - alongSign * 2.3
                    yellowBatch.addBoxAxes(center: pt(poleLat, 1.0, armCenter), size: SIMD3<Float>(0.09, 0.2, 5.2), ax: ax, ay: ay, az: az)
                    for bandIndex in 0..<4 {
                        let bandAlong = poleAlong - alongSign * (0.9 + Float(bandIndex) * 1.15)
                        darkBatch.addBoxAxes(center: pt(poleLat, 1.0, bandAlong), size: SIMD3<Float>(0.11, 0.22, 0.5), ax: ax, ay: ay, az: az)
                    }
                }
            }
        }

        if let dark = darkBatch.build(name: "crossing-dark-\(index)", material: poleMaterial) { world.addChild(dark) }
        if let yellow = yellowBatch.build(name: "crossing-yellow-\(index)", material: Self.pbr(UIColor(red: 0.93, green: 0.72, blue: 0.1, alpha: 1), roughness: 0.55)) { world.addChild(yellow) }
        if let white = whiteBatch.build(name: "crossing-white-\(index)", material: roofMaterials[2]) { world.addChild(white) }
        var lensMaterial = PhysicallyBasedMaterial()
        lensMaterial.baseColor = .init(tint: UIColor(red: 0.4, green: 0.04, blue: 0.04, alpha: 1))
        lensMaterial.emissiveColor = .init(color: UIColor(red: 1, green: 0.12, blue: 0.08, alpha: 1))
        lensMaterial.emissiveIntensity = 1.6
        if let red = redBatch.build(name: "crossing-red-\(index)", material: lensMaterial) { world.addChild(red) }
    }

    /// quality24 phase 1 — the showcase section, Kankumo-Chuo (0 m)
    /// to Matsubaracho (1,856 m), built to the density the BVE
    /// survey measured instead of the line-wide procedural fill:
    /// continuous lineside elements (fence, cable trough, equipment
    /// boxes), street trees and a shrub row along the roads, and a
    /// low-rise front band in the 6-12 m strip the towers leave
    /// empty. Catenary at a 45 m pitch inside the section is added
    /// by buildCatenary. Station plaza and under-viaduct dressing
    /// are phase 2 and deliberately not here. Nothing outside
    /// 0...1,856 m changes.
    private func buildShowcaseSection(route: RailwayRouteProfile, routeVariant: RegionalRouteVariant, travelDirection: RegionalTravelDirection) {
        guard travelDirection == .up, routeVariant == .mainline || routeVariant == .throughBranch else { return }
        let sectionEnd = 1_856.0
        let landmarks = fictionalCorridorLandmarks(for: route)

        // Tower footprints (placed by buildSuburb) so nothing in
        // this layer grows inside a tower.
        var towerBases: [(x: Float, z: Float)] = []
        for child in world.children where child.name.hasPrefix("office-base-") {
            towerBases.append((x: child.position.x, z: child.position.z))
        }
        func clearOfTowers(_ x: Float, _ z: Float, _ radius: Float) -> Bool {
            for base in towerBases {
                let dx = x - base.x
                let dz = z - base.z
                if dx * dx + dz * dz < radius * radius { return false }
            }
            return true
        }
        // Urban utility poles stand at lateral +/-11.0 m on a 45 m
        // pitch (from 60 m on the left, 82.5 m on the right); a
        // front building centred within 5.5 m of one would swallow it.
        func poleNear(_ d: Double, side: Float) -> Bool {
            var p = side < 0 ? 60.0 : 82.5
            while p < d + 6 {
                if abs(p - d) < 5.5 { return true }
                p += 45
            }
            return false
        }

        // -- A6: low-rise front band in the 6-12 m strip. Placed
        // first; trees and shrubs keep out of its footprint. Centres
        // sit in the gaps of the 27 m tower rhythm (tower chainages
        // 34 + 27k, this band at 50.5 + 27k), clear of the poles.
        var placedFronts: [(chainage: Double, side: Float)] = []
        func frontNear(_ d: Double, side: Float, within: Double) -> Bool {
            placedFronts.contains { $0.side == side && abs($0.chainage - d) < within }
        }
        var frontSerial = 0
        // quality25 (G): the fronts used to be a textured box, a
        // roof slab and ONE dark glass slit — the "windows are
        // black holes" of the CI #232 photos. They now get their
        // component structure in batches: a plinth and parapet cap
        // and an entrance canopy (concrete batch), a window band
        // per floor in dark glass or lit warm glass (about one
        // floor in three lit), mullions breaking each band into
        // window units, and a rooftop tank on every third roof.
        var frontTrimBatch = MeshBatchBuilder()
        var frontGlassBatch = MeshBatchBuilder()
        var frontLitBatch = MeshBatchBuilder()
        var frontMullionBatch = MeshBatchBuilder()
        let litWindowMaterial = Self.pbr(UIColor(red: 0.98, green: 0.93, blue: 0.76, alpha: 1), metallic: 0.05, roughness: 0.35)
        let frontRanges: [(from: Double, to: Double, rightOnly: Bool)] = [(60, 490, false), (1_595, 1_745, true)]
        for range in frontRanges {
            let sides: [Float] = range.rightOnly ? [1] : [-1, 1]
            var d = 50.5
            while d < range.to {
                // quality25 (B): the second range used to end at
                // 1,745 m — inside Matsubaracho's station zone.
                if d >= range.from, !corridorReserved(at: d, landmarks: landmarks), !inStationZone(d) {
                    for side in sides where !poleNear(d, side: side) {
                        let s = sample(at: d)
                        let ground = groundOffsetPoint(s, lateral: side * 10.7)
                        if clearOfTowers(ground.x, ground.z, 9.5) {
                            let height = 4.5 + Float((frontSerial * 53) % 45) * 0.1
                            let yaw = simd_quatf(angle: -s.heading, axis: SIMD3<Float>(0, 1, 0))
                            let bodyMaterial: PhysicallyBasedMaterial
                            switch frontSerial % 4 {
                            case 0:
                                bodyMaterial = buildingMaterials[frontSerial % buildingMaterials.count]
                            case 1:
                                bodyMaterial = officeMaterials[frontSerial % officeMaterials.count]
                            case 2:
                                bodyMaterial = houseFacadeMaterial
                            default:
                                bodyMaterial = buildingMaterials[(frontSerial + 2) % buildingMaterials.count]
                            }
                            _ = addBox(parent: world, name: "showcase-front-\(frontSerial)", size: SIMD3<Float>(5.5, height, 7.0), position: SIMD3<Float>(ground.x, ground.y + height / 2, ground.z), material: bodyMaterial, orientation: yaw)
                            _ = addBox(parent: world, name: "showcase-front-roof-\(frontSerial)", size: SIMD3<Float>(5.9, 0.22, 7.4), position: SIMD3<Float>(ground.x, ground.y + height + 0.11, ground.z), material: roofMaterials[frontSerial % roofMaterials.count], orientation: yaw)
                            // Batched dressing. The track-facing
                            // side is -side along the lateral axis
                            // (cos h, sin h); the along-track axis
                            // is (sin h, -cos h).
                            let lateralVec = SIMD3<Float>(cos(s.heading), 0, sin(s.heading))
                            let tangentVec = SIMD3<Float>(sin(s.heading), 0, -cos(s.heading))
                            let center = SIMD3<Float>(ground.x, ground.y, ground.z)
                            frontTrimBatch.addBox(center: center + SIMD3<Float>(0, 0.5, 0), size: SIMD3<Float>(6.0, 1.0, 7.5), yaw: -s.heading)
                            frontTrimBatch.addBox(center: center + SIMD3<Float>(0, height + 0.10, 0), size: SIMD3<Float>(6.1, 0.42, 7.6), yaw: -s.heading)
                            let canopyCenter = center - lateralVec * (side * 3.30) + SIMD3<Float>(0, 2.55, 0)
                            frontTrimBatch.addBox(center: canopyCenter, size: SIMD3<Float>(1.2, 0.10, 3.2), yaw: -s.heading)
                            if frontSerial % 3 == 0 {
                                let tankBase = center + tangentVec * 1.5 + SIMD3<Float>(0, height + 0.22, 0)
                                frontTrimBatch.addPrism(baseCenter: tankBase, radius: 0.55, height: 1.1, yaw: 0)
                            }
                            let floors = max(1, Int((height - 1.2) / 2.9))
                            for floor in 1...floors {
                                let bandY = ground.y + 3.05 + Float(floor - 1) * 2.9
                                guard bandY < ground.y + height - 0.7 else { break }
                                let bandCenter = center - lateralVec * (side * 2.80) + SIMD3<Float>(0, bandY - ground.y, 0)
                                if (frontSerial + floor) % 3 == 0 {
                                    frontLitBatch.addBox(center: bandCenter, size: SIMD3<Float>(0.10, 1.15, 5.8), yaw: -s.heading)
                                } else {
                                    frontGlassBatch.addBox(center: bandCenter, size: SIMD3<Float>(0.10, 1.15, 5.8), yaw: -s.heading)
                                }
                                for mullionOffset: Float in [-1.95, 0, 1.95] {
                                    frontMullionBatch.addBox(center: bandCenter + tangentVec * mullionOffset, size: SIMD3<Float>(0.06, 1.15, 0.10), yaw: -s.heading)
                                }
                            }
                            placedFronts.append((chainage: d, side: side))
                            frontSerial += 1
                        }
                    }
                }
                d += 27
            }
        }
        if let trim = frontTrimBatch.build(name: "showcase-front-trim", material: concreteMaterial) { world.addChild(trim) }
        if let glass = frontGlassBatch.build(name: "showcase-front-glass", material: glassMaterial) { world.addChild(glass) }
        if let lit = frontLitBatch.build(name: "showcase-front-lit", material: litWindowMaterial) { world.addChild(lit) }
        if let mullions = frontMullionBatch.build(name: "showcase-front-mullions", material: poleMaterial) { world.addChild(mullions) }

        // -- A5: street trees along the outer road edge (+/-10.5 m).
        // On the elevated part they stand on the valley floor beside
        // the road below the viaduct, which is where the road is.
        // Phases are offset per side so crowns never meet a utility
        // pole (poles every 45 m; trees every 22.5 m land at least
        // 11.25 m away in chainage).
        var treeSerial = 0
        for side: Float in [-1, 1] {
            var d = side < 0 ? 26.25 : 48.75
            while d < 1_845 {
                // quality25 (B): street trees stop at the station
                // zone too (they used to grow beside the platform).
                if !frontNear(d, side: side, within: 5.5), !inStationZone(d) {
                    let s = sample(at: d)
                    let point = groundOffsetPoint(s, lateral: side * 10.5)
                    if clearOfTowers(point.x, point.z, 8) {
                        let height = 5 + Float((treeSerial * 29) % 31) * 0.1
                        addTree(parent: world, name: "showcase-tree-\(treeSerial)", x: point.x, z: point.z, height: height, material: foliageMaterials[treeSerial % foliageMaterials.count], groundY: point.y)
                    }
                }
                treeSerial += 1
                d += 22.5
            }
        }

        // -- Spec 8.1 shrub row. The literal 6.5-9 m band is the
        // parallel road itself (road boxes span 3.4-10.6 m), so the
        // hedge runs along the road's outer edge at +/-11.4 m: the
        // first band outside the wall/fence corridor that is not
        // carriageway. quality25 (C): the hedge used to be a row of
        // flat 5.4 m boxes; it is now three overlapping squashed
        // leaf blobs per spot, merged into one foliage mesh — a
        // lumpy hedge line instead of a green plank. Station zones
        // are skipped (quality25, B).
        var shrubBlobs: [(center: SIMD3<Float>, radii: SIMD3<Float>)] = []
        var shrubSerial = 0
        for side: Float in [-1, 1] {
            var d = 6.0
            while d < 1_852 {
                if !frontNear(d, side: side, within: 6.5), !inStationZone(d) {
                    let s = sample(at: d)
                    let lateral = side * (11.4 + Float(shrubSerial % 3) * 0.3)
                    let point = groundOffsetPoint(s, lateral: lateral)
                    if clearOfTowers(point.x, point.z, 7.5) {
                        let tangent = SIMD3<Float>(sin(s.heading), 0, -cos(s.heading))
                        for k in -1...1 {
                            let j1 = foliageJitter(seed: Float(d), salt: Float(shrubSerial * 3 + k + 2))
                            let j2 = foliageJitter(seed: Float(d), salt: Float(shrubSerial * 5 + k + 7))
                            let center = SIMD3<Float>(point.x, point.y + 0.28 + j1 * 0.10, point.z) + tangent * (Float(k) * 1.8)
                            let radii = SIMD3<Float>(0.62 * (0.85 + 0.3 * j2), 0.34 * (0.85 + 0.3 * j1), 0.58 * (0.85 + 0.3 * j2))
                            shrubBlobs.append((center: center, radii: radii))
                        }
                    }
                }
                shrubSerial += 1
                d += d < 140 ? 6 : 8
            }
        }
        if let hedges = foliageBlobEntity(name: "showcase-hedges", blobs: shrubBlobs, material: foliageMaterials[0], longitudes: 6, latitudes: 5) {
            world.addChild(hedges)
        }

        // -- A3: cable trough both sides, following the fine 10.5 m
        // stations like the rails do. On the deck (lift >= 2 m) the
        // trough moves inboard to +/-3.85 m: the deck is only 8.4 m
        // wide, so the ground-level offset would float in the air.
        var troughBatch = MeshBatchBuilder()
        var spanStart = 0.0
        while spanStart < sectionEnd {
            let mid = spanStart + 5.25
            let s = sample(at: mid)
            let elevated = s.elevationM - groundLevelM(at: mid) >= 2
            // quality25 (B): the trough dives out of the station
            // zone — at ±4.9 m (ground) / ±3.85 m (deck) it would
            // run straight through the new platform bodies, whose
            // footprint reaches 3.6–8.1 m from the route centre.
            if !inStationZone(mid) {
                for side: Float in [-1, 1] {
                    let lateral: Float = side * Float(elevated ? 3.85 : 4.9)
                    troughBatch.addBox(center: SIMD3<Float>(s.x + lateral * cos(s.heading), s.elevationM + 0.01, s.z + lateral * sin(s.heading)), size: SIMD3<Float>(0.55, 0.22, 11.0), yaw: -s.heading)
                }
            }
            spanStart += 10.5
        }
        if let trough = troughBatch.build(name: "showcase-cable-trough", material: concreteMaterial) {
            world.addChild(trough)
        }

        // -- A3: lineside equipment boxes (relay / power) every
        // ~75 m, alternating sides, inboard on the deck.
        // quality25 (B): boxes are skipped inside the station zone
        // — the 1,780 m and 1,855 m boxes used to stand inside
        // Matsubaracho's platforms (the red-brown boxes in the CI
        // #232 station photo are this power batch). quality25 (G):
        // each box also gets a plinth, a cap, a door panel on its
        // track-facing side and two vent slits, in trim batches.
        var relayBatch = MeshBatchBuilder()
        var powerBatch = MeshBatchBuilder()
        var boxTrimBatch = MeshBatchBuilder()
        var boxVentBatch = MeshBatchBuilder()
        var boxChainage = 55.0
        var boxSerial = 0
        while boxChainage < sectionEnd {
            let s = sample(at: boxChainage)
            let elevated = s.elevationM - groundLevelM(at: boxChainage) >= 2
            let side: Float = boxSerial % 2 == 0 ? -1 : 1
            let lateral: Float = side * Float(elevated ? 4.0 : 5.15)
            let baseY = elevated ? s.elevationM - 0.10 : s.elevationM - 0.06
            let center = SIMD3<Float>(s.x + lateral * cos(s.heading), baseY + 0.52, s.z + lateral * sin(s.heading))
            if !inStationZone(boxChainage) {
                if boxSerial % 4 < 2 {
                    relayBatch.addBox(center: center, size: SIMD3<Float>(0.45, 1.05, 0.7), yaw: -s.heading)
                } else {
                    powerBatch.addBox(center: center, size: SIMD3<Float>(0.45, 1.05, 0.7), yaw: -s.heading)
                }
                let lateralVec = SIMD3<Float>(cos(s.heading), 0, sin(s.heading))
                let doorCenter = center - lateralVec * (side * 0.237)
                boxTrimBatch.addBox(center: doorCenter + SIMD3<Float>(0, -0.04, 0), size: SIMD3<Float>(0.03, 0.78, 0.46), yaw: -s.heading)
                boxTrimBatch.addBox(center: SIMD3<Float>(center.x, baseY + 0.07, center.z), size: SIMD3<Float>(0.62, 0.14, 0.86), yaw: -s.heading)
                boxTrimBatch.addBox(center: SIMD3<Float>(center.x, baseY + 1.08, center.z), size: SIMD3<Float>(0.56, 0.06, 0.80), yaw: -s.heading)
                for ventIndex in 0..<2 {
                    let ventCenter = center - lateralVec * (side * 0.24) + SIMD3<Float>(0, 0.30 - Float(ventIndex) * 0.11, 0)
                    boxVentBatch.addBox(center: ventCenter, size: SIMD3<Float>(0.02, 0.05, 0.38), yaw: -s.heading)
                }
            }
            boxSerial += 1
            boxChainage += 75
        }
        if let boxes = relayBatch.build(name: "showcase-relay-boxes", material: poleMaterial) {
            world.addChild(boxes)
        }
        if let boxes = powerBatch.build(name: "showcase-power-boxes", material: roofMaterials[1]) {
            world.addChild(boxes)
        }
        if let trim = boxTrimBatch.build(name: "showcase-box-trim", material: poleMaterial) {
            world.addChild(trim)
        }
        if let vents = boxVentBatch.build(name: "showcase-box-vents", material: glassMaterial) {
            world.addChild(vents)
        }

        // -- A2: continuous chain-link fence both sides, 1.5 m high,
        // on fine 10.5 m stations so it hugs the curve (a 60 m
        // coarse ribbon would cut inside the wall). One UV strip
        // per side; the diamond mesh is an alpha-cutout texture.
        // At ground level the fence runs at +/-6.2 m, just outside
        // the sound walls at +/-5.6 m; on the viaduct it steps
        // inboard to +/-4.05 m and stands on the deck (top at rail
        // elevation -0.49 m, the deck ribbon's height): the deck is
        // only 8.4 m wide, so a fence left at 6.2 m would hang in
        // the air beside it for the whole elevated kilometre.
        var fenceMaterial = Self.texturedPBR(.white, metallic: 0.55, roughness: 0.45, textureName: "scenery_fence_chainlink")
        fenceMaterial.blending = .transparent(opacity: .init(floatLiteral: 1))
        // The texture's alpha is binary (wire or hole), so plain
        // transparent blending already renders the cutout; no
        // alpha-test threshold is set — the plausible-looking
        // property for it could not be verified against the SDK
        // from here, and an unverified property name is exactly
        // what failed CI #196.
        fenceMaterial.faceCulling = .none
        // quality25 (B/G): the fence now breaks at the station zone
        // (at ±4.05 m on the deck it used to cross the platform
        // area) and gets its component structure — a post at every
        // station point and a top rail along each run, batched.
        var fencePostBatch = MeshBatchBuilder()
        struct FencePoint {
            var bottom: SIMD3<Float>
            var top: SIMD3<Float>
            var chainage: Double
            var heading: Float
        }
        for side: Float in [-1, 1] {
            var points: [FencePoint] = []
            var d = 0.0
            while d <= sectionEnd {
                let s = sample(at: d)
                let elevated = s.elevationM - groundLevelM(at: d) >= 2
                let baseY = elevated ? s.elevationM - 0.48 : s.elevationM - 0.06
                let lateral: Float = side * (elevated ? 4.05 : 6.2)
                let px = s.x + lateral * cos(s.heading)
                let pz = s.z + lateral * sin(s.heading)
                points.append(FencePoint(
                    bottom: SIMD3<Float>(px, baseY, pz),
                    top: SIMD3<Float>(px, baseY + 1.5, pz),
                    chainage: d,
                    heading: s.heading
                ))
                d += 10.5
            }
            var runStart: Int? = nil
            var runIndex = 0
            func emitRun(_ runEnd: Int) {
                guard let start = runStart, runEnd - start > 1 else { return }
                var positions: [SIMD3<Float>] = []
                var normals: [SIMD3<Float>] = []
                var uvs: [SIMD2<Float>] = []
                var indices: [UInt32] = []
                for (offset, index) in (start..<runEnd).enumerated() {
                    let point = points[index]
                    positions.append(point.bottom)
                    positions.append(point.top)
                    let nx = -side * cos(point.heading)
                    let nz = -side * sin(point.heading)
                    normals.append(SIMD3<Float>(nx, 0, nz))
                    normals.append(SIMD3<Float>(nx, 0, nz))
                    let u = Float(point.chainage / 0.9)
                    uvs.append(SIMD2<Float>(u, 0))
                    uvs.append(SIMD2<Float>(u, 1))
                    if offset > 0 {
                        let a = UInt32((offset - 1) * 2)
                        indices.append(contentsOf: [a, a + 1, a + 2, a + 1, a + 3, a + 2])
                    }
                    // Top rail to the previous point of the run.
                    if offset > 0 {
                        fencePostBatch.addSegment(from: points[index - 1].top, to: point.top, thickness: 0.045)
                    }
                }
                let fenceName = (side < 0 ? "showcase-fence-l" : "showcase-fence-r") + "-\(runIndex)"
                runIndex += 1
                var descriptor = MeshDescriptor(name: fenceName)
                descriptor.positions = MeshBuffers.Positions(positions)
                descriptor.normals = MeshBuffers.Normals(normals)
                descriptor.textureCoordinates = MeshBuffers.TextureCoordinates(uvs)
                descriptor.primitives = .triangles(indices)
                if let mesh = try? MeshResource.generate(from: [descriptor]) {
                    let fence = ModelEntity(mesh: mesh, materials: [fenceMaterial])
                    fence.name = fenceName
                    world.addChild(fence)
                }
            }
            for index in points.indices {
                let point = points[index]
                if inStationZone(point.chainage) {
                    if runStart != nil {
                        emitRun(index)
                        runStart = nil
                    }
                } else {
                    if runStart == nil { runStart = index }
                    let ax = SIMD3<Float>(cos(point.heading), 0, sin(point.heading))
                    let az = SIMD3<Float>(-sin(point.heading), 0, cos(point.heading))
                    fencePostBatch.addBoxAxes(center: (point.bottom + point.top) / 2,
                                              size: SIMD3<Float>(0.09, 1.5, 0.09),
                                              ax: ax, ay: SIMD3<Float>(0, 1, 0), az: az)
                }
            }
            if runStart != nil {
                emitRun(points.count)
                runStart = nil
            }
        }
        if let posts = fencePostBatch.build(name: "showcase-fence-posts", material: poleMaterial) {
            world.addChild(posts)
        }
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
        for road in scenario.roads {
            guard let path = paths[road.routePathID] else { continue }
            // quality25 (B): the road used to be a row of rigid
            // 120 m boxes, each posed at ONE sample's yaw and at the
            // ground height of its centre only. On the R450 curve
            // above Matsubaracho a 120 m chord sags 4.0 m inside the
            // arc (L^2/8R), so the slab's inner edge swung across
            // the running line, and where the hillside falls away
            // the flat slab floated — the "big plate" hanging over
            // the right-hand track in the CI #232 photos. The road
            // is now a sample-following ribbon at ground level, the
            // same construction as the trackbed and the ground
            // apron, so it bends with the curve and sits on the
            // ground at every sample. It also stops at station
            // zones, where it used to run along the platform edge.
            //
            // Coverage first: which route chainages this road's
            // path projects onto (its lateral offset is constant).
            var coveredMin = Double.greatestFiniteMagnitude
            var coveredMax = -Double.greatestFiniteMagnitude
            var probe = 0.0
            while probe <= path.lengthM {
                if let chainage = projectedChainage(road.routePathID, positionM: probe, routeVariant: routeVariant, direction: travelDirection),
                   chainage >= 0, chainage <= route.distanceM {
                    coveredMin = min(coveredMin, chainage)
                    coveredMax = max(coveredMax, chainage)
                }
                probe += 50
            }
            guard coveredMax > coveredMin else { continue }
            let lateral = Float(road.lateralOffsetM)
            let offsets = [Float](repeating: lateral, count: samples.count)
            let yOffsets = samples.map { groundLevelM(at: $0) - $0.elevationM + 0.04 }
            var markBatch = MeshBatchBuilder()
            var runStart: Int? = nil
            var runIndex = 0
            var lastMarkChainage = -1_000.0
            func flushRun(endIndex: Int) {
                guard let start = runStart else { return }
                if endIndex - start > 1,
                   let ribbon = ribbonEntity(name: "parallel-road-\(road.id)-\(runIndex)", width: 7.2, y: 0, tileLength: 30, offsets: offsets, material: roadMaterial, range: start..<endIndex, yOffsets: yOffsets) {
                    world.addChild(ribbon)
                    runIndex += 1
                }
                runStart = nil
            }
            for index in samples.indices {
                let sample = samples[index]
                let chainage = sample.distanceM
                let active = chainage >= coveredMin && chainage <= coveredMax
                    && !inStationZone(chainage)
                    && !nearThroatFan(chainage)
                    && !corridorReserved(at: chainage, landmarks: landmarks)
                if active {
                    if runStart == nil { runStart = index }
                    // Dashed centre line, following the ground the
                    // way the ribbon does.
                    if chainage - lastMarkChainage >= 15 {
                        lastMarkChainage = chainage
                        let center = routeOffsetPoint(sample, lateral: lateral)
                        markBatch.addBox(center: SIMD3<Float>(center.x, groundLevelM(at: sample) + 0.10, center.z),
                                         size: SIMD3<Float>(0.14, 0.02, 5.0), yaw: -sample.heading)
                    }
                } else {
                    flushRun(endIndex: index)
                }
            }
            flushRun(endIndex: samples.count)
            if let marks = markBatch.build(name: "road-lane-marks-\(road.id)", material: roofMaterials[2]) {
                world.addChild(marks)
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
        // The cab builder places real gauge needles and lamp overlays
        // inside the interior group; collect them so the per-frame
        // update can drive them from live physics and indicators.
        guard let model = cabModel, let interior = model.groups[.cabInterior] else { return }
        cabNeedlePivots = [:]
        cabLampOverlays = [:]
        collectCabInstruments(in: interior)
    }

    private func collectCabInstruments(in entity: Entity) {
        if entity.name.hasPrefix("GaugeNeedle_") {
            cabNeedlePivots[entity.name] = entity
        } else if entity.name.hasPrefix("CabLampLit_") {
            cabLampOverlays[entity.name] = entity
        }
        for child in entity.children {
            collectCabInstruments(in: child)
        }
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
                // quality25 (A): the GLB's own platform slabs,
                // tactile strips, white lines, platform-end fences
                // and its straight 42 m track parts are removed —
                // the app builds curve-following platforms at the
                // corrected length and the app track already runs
                // through the station. Building, canopy, footbridge
                // and signs stay. quality29: benches, vending
                // machines and bins are removed too — as part of the
                // rigid 42 m GLB they cannot follow the platform's
                // grade (on Matsubaracho's 20 per mille they ended
                // up sunk into the new platform away from the
                // anchor point), so buildStationFurniture now
                // places them procedurally along the platform.
                // quality31: the station_ group (building, glazing,
                // sign) is removed too — bisection photo runs
                // (diag3/4/5) proved that group renders as a rusty
                // corrugated wall intruding behind the down
                // platform at Matsubaracho; buildStationSurroundings
                // now provides the station-front buildings instead.
                stripGeneratedPlatformParts(entity)
                adjustGeneratedStationHeights(entity)
                entity.name = "generated-station-\(placement.stationId)-\(placement.trackCount)track-\(placement.platformCount)platform"
                world.addChild(entity)
                importedStationEntity = entity
            }
        }
        if let entity = importedStationEntity {
            setGeneratedAssetPose(entity, chainageM: placement.chainageM)
        }
    }

    /// Removes the generated station model's own platform and track
    /// parts (quality25, A); see the call site. The 5-track major
    /// station GLB is a single merged node named "station", so
    /// nothing matches there and Kankumo-shi keeps its modelled
    /// platforms — a known limitation, recorded in the revision
    /// report. Platform SIGNS are kept: they hang over the platform
    /// and belong to the core furniture.
    private func stripGeneratedPlatformParts(_ entity: Entity) {
        for child in Array(entity.children) {
            let name = child.name
            let isPlatformSlab = (name.hasPrefix("platform_") || name == "platform") && !name.hasPrefix("platform_sign")
            if isPlatformSlab
                || name.hasPrefix("tactile_strip_")
                || name.hasPrefix("white_line_")
                || name.hasPrefix("end_fence_")
                || name.hasPrefix("trackbed_")
                || name.hasPrefix("rail_")
                || name.hasPrefix("sleeper_")
                || name.hasPrefix("station_")
                || name.hasPrefix("bench_")
                || name.hasPrefix("vending_")
                || name.hasPrefix("bin_") {
                child.removeFromParent()
            } else {
                stripGeneratedPlatformParts(child)
            }
        }
    }

    /// Raises the generated station model's canopy and platform
    /// furniture to the quality25 platform height (quality26).
    /// Measured from the station GLBs (station-local metres; the
    /// geometry is baked into the vertices and node translations
    /// are zero): rail head = local Y +0.315, the GLB's own
    /// platform top was +0.225, and the procedural platform top
    /// built since quality25 is rail head + 1.10 = local 1.415.
    /// The canopy roof slab spans Y 3.16–3.34 — an underside only
    /// 2.85 m above the rail head — so the forward camera eye at
    /// rail + 3.6 m sat inside the roof (CI #238 photos P5–P7
    /// showed the roof interior). Platform signs hang from that
    /// roof (hanger tops exactly 3.16), so they rise with it;
    /// canopy columns span Y 0.20–3.20 and are stretched so their
    /// tops meet the raised underside (3.16 + 1.85 = 5.01 =
    /// 3.20 × 1.566) while their bases stay buried below the new
    /// platform top. (Benches, vending machines and bins used to be
    /// raised here too; since quality29 they are stripped from the
    /// GLB and placed procedurally — see buildStationFurniture.)
    /// The footbridge deck (Y 5.84–6.16) and the station building
    /// are already correct and untouched. The 5-track major station
    /// GLB is a single merged node named "station", so nothing
    /// matches there — the same known limitation as
    /// stripGeneratedPlatformParts.
    private func adjustGeneratedStationHeights(_ entity: Entity) {
        for child in Array(entity.children) {
            let name = child.name
            if name.hasPrefix("canopy_roof_")
                || name.hasPrefix("canopy_light_")
                || name.hasPrefix("canopy_fixture_")
                || name.hasPrefix("platform_sign_") {
                child.position.y += 1.85
            } else if name.hasPrefix("canopy_column_") {
                child.scale.y *= 1.566
            }
            adjustGeneratedStationHeights(child)
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
            sample.elevationM + verticalOffsetM,
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

    /// Drives the cab builder's gauge needles and lamp overlays.
    /// Gauge faces sweep 270 degrees: zero at 225 degrees (lower
    /// left), full scale at -45 degrees. The E231 dual pressure
    /// gauge reads BC on the shared 0-1000 kPa scale; the fictional
    /// desks use a separate 0-600 kPa BC gauge.
    private func updateCabGauges(speedKmh: Double, brakePipePressureKPa: Double, mainReservoirPressureKPa: Double, brakeCylinderPressureKPa: Double, indicator: VehicleCabIndicatorState, controls: TrainControls) {
        func setNeedle(_ name: String, fraction: Double) {
            guard let pivot = cabNeedlePivots[name] else { return }
            let clamped = min(max(fraction, 0), 1)
            let degrees = Float(270 * clamped - 135)
            pivot.orientation = simd_quatf(angle: degrees * .pi / 180, axis: SIMD3<Float>(0, 0, 1))
        }
        setNeedle("GaugeNeedle_speed", fraction: speedKmh / 120)
        setNeedle("GaugeNeedle_mr", fraction: mainReservoirPressureKPa / 1000)
        setNeedle("GaugeNeedle_bp", fraction: brakePipePressureKPa / 1000)
        let bcScale = currentCabDesk.fictionalCarNumber == "E231" ? 1000.0 : 600.0
        setNeedle("GaugeNeedle_bc", fraction: brakeCylinderPressureKPa / bcScale)
        cabLampOverlays["CabLampLit_door"]?.isEnabled = !indicator.doorsOpen
        cabLampOverlays["CabLampLit_ats"]?.isEnabled = indicator.atspActive || indicator.atcActive
        cabLampOverlays["CabLampLit_emergency"]?.isEnabled = indicator.emergencyBrakeActive || controls.emergencyBrake
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
                sample.x + lateral * cos(sample.heading), sample.elevationM,
                sample.z + lateral * sin(sample.heading)
            )
            let directionOffset: Float = (actor.serviceDirection == (travelDirection == .up ? .up : .down)) ? 0 : .pi
            entity.orientation = simd_quatf(angle: -sample.heading + directionOffset, axis: SIMD3<Float>(0, 1, 0))
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
            entity.position = SIMD3<Float>(sample.x + lateral * cos(sample.heading), groundLevelM(at: sample), sample.z + lateral * sin(sample.heading))
            let directionOffset: Float = road.direction.serviceDirection == (travelDirection == .up ? .up : .down) ? 0 : .pi
            entity.orientation = simd_quatf(angle: -sample.heading + directionOffset, axis: SIMD3<Float>(0, 1, 0))
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
            entity.position = SIMD3<Float>(sample.x + lateral * cos(sample.heading), sample.elevationM + 0.48, sample.z + lateral * sin(sample.heading))
            entity.orientation = simd_quatf(angle: -(sample.heading + Float(actor.headingRadians)), axis: SIMD3<Float>(0, 1, 0))
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

    /// Deterministic 0..<1 jitter from a seed (the same tree must
    /// get the same crown on every rebuild, so no Hasher / random).
    private func foliageJitter(seed: Float, salt: Float) -> Float {
        let value = sin(seed * 127.1 + salt * 311.7) * 43_758.5453
        return value - floor(value)
    }

    /// One merged mesh of ellipsoid leaf blobs (quality25, C). The
    /// old crown was a single sphere with the leaf texture, which
    /// read in the CI photos as a giant green ball floating beside
    /// the track. A crown here is four overlapping ellipsoids of
    /// different sizes and offsets (see addTree), and a hedge is a
    /// row of squashed blobs — no single sphere anywhere. Normals
    /// use the ellipsoid gradient; UVs are spherical so the leaf
    /// texture wraps each blob.
    private func foliageBlobEntity(name: String, blobs: [(center: SIMD3<Float>, radii: SIMD3<Float>)], material: PhysicallyBasedMaterial, longitudes: Int = 8, latitudes: Int = 6) -> ModelEntity? {
        guard let mesh = foliageBlobMesh(name: name, blobs: blobs, longitudes: longitudes, latitudes: latitudes) else { return nil }
        var material = material
        material.faceCulling = .none
        return ModelEntity(mesh: mesh, materials: [material])
    }

    /// The merged ellipsoid-blob geometry behind foliageBlobEntity,
    /// split out in quality26 so addTree's cached crowns share the
    /// exact same construction instead of duplicating it.
    private func foliageBlobMesh(name: String, blobs: [(center: SIMD3<Float>, radii: SIMD3<Float>)], longitudes: Int = 8, latitudes: Int = 6) -> MeshResource? {
        guard !blobs.isEmpty else { return nil }
        var positions: [SIMD3<Float>] = []
        var normals: [SIMD3<Float>] = []
        var uvs: [SIMD2<Float>] = []
        var indices: [UInt32] = []
        for blob in blobs {
            let base = UInt32(positions.count)
            for latIndex in 0...latitudes {
                let v = Float(latIndex) / Float(latitudes)
                let phi = v * Float.pi
                let sinPhi = sin(phi)
                let cosPhi = cos(phi)
                for lonIndex in 0...longitudes {
                    let u = Float(lonIndex) / Float(longitudes)
                    let theta = u * 2 * Float.pi
                    let dir = SIMD3<Float>(sinPhi * cos(theta), cosPhi, sinPhi * sin(theta))
                    positions.append(blob.center + dir * blob.radii)
                    var normal = SIMD3<Float>(dir.x / blob.radii.x, dir.y / blob.radii.y, dir.z / blob.radii.z)
                    if simd_length(normal) < 1e-6 { normal = SIMD3<Float>(0, 1, 0) }
                    normals.append(simd_normalize(normal))
                    uvs.append(SIMD2<Float>(u, v))
                }
            }
            let ring = longitudes + 1
            for latIndex in 0..<latitudes {
                for lonIndex in 0..<longitudes {
                    let a = base + UInt32(latIndex * ring + lonIndex)
                    let b = a + 1
                    let c = a + UInt32(ring)
                    let dd = c + 1
                    indices.append(contentsOf: [a, c, b, b, c, dd])
                }
            }
        }
        var descriptor = MeshDescriptor(name: name)
        descriptor.positions = MeshBuffers.Positions(positions)
        descriptor.normals = MeshBuffers.Normals(normals)
        descriptor.textureCoordinates = MeshBuffers.TextureCoordinates(uvs)
        descriptor.primitives = .triangles(indices)
        return try? MeshResource.generate(from: [descriptor])
    }

    private func addTree(parent: Entity, name: String, x: Float, z: Float, height: Float, material: PhysicallyBasedMaterial, groundY: Float = 0) {
        // quality25 (C): real street-tree proportions — a trunk of
        // believable girth (Ø ≈ 0.09 × height + 0.08 m, capped) up
        // to about half the height, then a crown of four jittered
        // ellipsoids instead of one perfect sphere.
        // quality26: the requested height is quantized to a 1.5 m
        // class (world height = classHeight, at most 0.75 m from
        // the request) so the trunk and crown meshes come from the
        // shared caches instead of one generated mesh per tree.
        // Four crown variants per class — built in local space from
        // a fixed per-variant seed — plus a per-tree yaw keep the
        // line from looking stamped out.
        let classIndex = min(max(Int((height / 1.5).rounded()), 1), 8)
        let h = Float(classIndex) * 1.5
        let trunkHeight = h * 0.52
        let trunkRadius = min(0.20, 0.045 * h + 0.04)
        let trunkKey = "\(Int((trunkHeight / 0.01).rounded()))/\(Int((trunkRadius / 0.01).rounded()))"
        let trunkMesh: MeshResource
        if let cached = sharedTrunkMeshes[trunkKey] {
            trunkMesh = cached
        } else {
            // Generate at the key's quantized dimensions so the
            // cached mesh is exactly what its key promises.
            let meshHeight = (trunkHeight / 0.01).rounded() * 0.01
            let meshRadius = (trunkRadius / 0.01).rounded() * 0.01
            if #available(iOS 18.0, *) {
                trunkMesh = .generateCylinder(height: meshHeight, radius: meshRadius)
            } else {
                trunkMesh = FallbackCylinderMesh.make(height: meshHeight, radius: meshRadius)
            }
            sharedTrunkMeshes[trunkKey] = trunkMesh
        }
        let trunk = ModelEntity(mesh: trunkMesh, materials: [sleeperMaterial])
        trunk.name = "\(name)-trunk"
        trunk.position = SIMD3<Float>(x, groundY + trunkHeight / 2, z)
        parent.addChild(trunk)

        let seed = x * 0.37 + z * 0.91
        let variant = Int(abs(seed)) % 4
        let crownKey = "\(classIndex)-\(variant)"
        let crownMesh: MeshResource?
        if let cached = sharedCrownMeshes[crownKey] {
            crownMesh = cached
        } else {
            let crownSeed = Float(classIndex * 16 + variant)
            func j(_ salt: Float) -> Float { foliageJitter(seed: crownSeed, salt: salt) }
            let blobs: [(center: SIMD3<Float>, radii: SIMD3<Float>)] = [
                (center: SIMD3<Float>((j(1) - 0.5) * 0.10 * h, 0.74 * h, (j(2) - 0.5) * 0.10 * h),
                 radii: SIMD3<Float>(0.36 * h * (0.85 + 0.3 * j(3)), 0.30 * h * (0.85 + 0.3 * j(4)), 0.36 * h * (0.85 + 0.3 * j(5)))),
                (center: SIMD3<Float>(-0.16 * h, 0.60 * h, (j(6) - 0.5) * 0.14 * h),
                 radii: SIMD3<Float>(0.24 * h * (0.85 + 0.3 * j(7)), 0.20 * h, 0.24 * h * (0.85 + 0.3 * j(8)))),
                (center: SIMD3<Float>(0.15 * h, 0.64 * h, -(j(9) - 0.5) * 0.14 * h),
                 radii: SIMD3<Float>(0.22 * h * (0.85 + 0.3 * j(10)), 0.19 * h, 0.23 * h * (0.85 + 0.3 * j(11)))),
                (center: SIMD3<Float>((j(12) - 0.5) * 0.08 * h, 0.90 * h, 0),
                 radii: SIMD3<Float>(0.19 * h, 0.16 * h * (0.85 + 0.3 * j(13)), 0.19 * h))
            ]
            crownMesh = foliageBlobMesh(name: "crown-\(crownKey)", blobs: blobs)
            if let crownMesh { sharedCrownMeshes[crownKey] = crownMesh }
        }
        if let crownMesh {
            var crownMaterial = material
            crownMaterial.faceCulling = .none
            let crown = ModelEntity(mesh: crownMesh, materials: [crownMaterial])
            crown.name = "\(name)-crown"
            crown.position = SIMD3<Float>(x, groundY, z)
            crown.orientation = simd_quatf(angle: foliageJitter(seed: seed, salt: 21) * 2 * .pi, axis: SIMD3<Float>(0, 1, 0))
            parent.addChild(crown)
        }
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
        // quality26: one shared MeshResource per size quantized to
        // a 0.02 m grid (at most 1 cm of size error, and at least
        // one grid step per axis so no axis collapses to zero)
        // instead of a unique generated box per call — see the
        // sharedBoxMeshes declaration for why.
        let steps = SIMD3<Int>(
            max(1, Int((size.x / 0.02).rounded())),
            max(1, Int((size.y / 0.02).rounded())),
            max(1, Int((size.z / 0.02).rounded()))
        )
        let boxKey = "\(steps.x)/\(steps.y)/\(steps.z)"
        let boxMesh: MeshResource
        if let cached = sharedBoxMeshes[boxKey] {
            boxMesh = cached
        } else {
            boxMesh = .generateBox(size: SIMD3<Float>(Float(steps.x) * 0.02, Float(steps.y) * 0.02, Float(steps.z) * 0.02))
            sharedBoxMeshes[boxKey] = boxMesh
        }
        let entity = ModelEntity(mesh: boxMesh, materials: [material])
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
                bankRadians: sample.bankRadians,
                elevationM: sample.elevationM
            )
        }
    }

    private func makeSceneFidelityRoute() -> SceneChainageRoute? {
        let controlPoints = samples.map { routeSample in
            let heading = Double(routeSample.heading)
            return SceneRouteControlPoint(
                chainageM: routeSample.distanceM,
                position: SceneVector3(Double(routeSample.x), Double(routeSample.elevationM), Double(routeSample.z)),
                tangentPerMeter: SceneVector3(sin(heading), 0, -cos(heading)),
                bankRadians: Double(routeSample.bankRadians)
            )
        }
        guard controlPoints.count >= 2 else { return nil }
        return try? SceneChainageRoute(controlPoints: controlPoints)
    }

    private func fictionalTerminalPlatforms(for route: RailwayRouteProfile) -> [ScenePlatformSpecification] {
        let end = min(max(route.stopMarkerM, 0), route.distanceM)
        // quality25 (A): aligned with the corrected platform-length
        // standard below (mainline 210 m); this spec was 180 m.
        let start = max(0, end - 210)
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

    /// Corrected platform-length standard (quality25, A). The layout
    /// manifest (station_layouts_32.json) now carries the same
    /// values; the scene derives lengths from the rule because the
    /// placement type does not carry the manifest's platforms array.
    /// Mainline: 210 m — the longest stopping formation is 10 cars
    /// (10 × 19.5 m = 195 m) plus 15 m of margin. Branch: 170 m —
    /// 8 cars (156 m) plus margin; the branch is a local shuttle
    /// whose standard formations are 4/6/8 cars (the 10-car profiles
    /// are catalogue extras), and the branch terminal keeps 180 m.
    /// Before this fix every platform on the line was 100–180 m, so
    /// even an 8-car train overhung most stations.
    private func platformLengthM(stationId: String, archetype: String) -> Double {
        if stationId.hasPrefix("B") {
            if archetype == "branch_terminal" { return 180 }
            return 170
        }
        return 210
    }

    /// Station zones (quality25, B): no lineside furniture, wall,
    /// fence, road or catenary support may be placed within a
    /// station's platform span plus 20 m at each end. Before this
    /// existed, the showcase layer put equipment boxes and fence
    /// lines straight through Matsubaracho's platforms, and the
    /// lineside noise walls ran through every station on the line.
    /// True when a building footprint stays clear of every station
    /// platform (quality29). Towers and houses used to be placed
    /// with no station check at all: a mid-rise tower's face could
    /// land inside the platform box (Matsubaracho, Codemagic
    /// photos: the apartment wall flush with the platform back,
    /// its ground floor sliced by the platform). The widest
    /// platform back reaches 2.1 + 1.52 + 6.0 = 9.62 m from the
    /// route centre, so a face at 10 m or beyond is always clear;
    /// inside that, the footprint must not overlap the platform's
    /// chainage range either.
    private func buildingClearOfPlatforms(chainage: Double, halfLength: Double, lateral: Float, halfDepth: Float) -> Bool {
        if abs(lateral) - halfDepth >= 10 { return true }
        for placement in stationModelPlacements {
            let platformHalf = platformLengthM(stationId: placement.stationId, archetype: placement.archetype) / 2 + 10
            if abs(chainage - placement.chainageM) < platformHalf + halfLength { return false }
        }
        return true
    }

    private func inStationZone(_ chainage: Double, extraMargin: Double = 0) -> Bool {
        for placement in stationModelPlacements {
            let half = platformLengthM(stationId: placement.stationId, archetype: placement.archetype) / 2 + 20 + extraMargin
            if abs(chainage - placement.chainageM) <= half { return true }
        }
        return false
    }

    /// App-side station platforms (quality25, A). The generated
    /// station GLBs are 42 m cores posed rigidly at the station
    /// centre; on a curve the platform ends drifted metres away
    /// from the track (Matsubaracho: ~5.8 m at the end of its
    /// 140 m platform on the R450 curve), so the track visibly
    /// pierced the platform. These platforms are built the way the
    /// trackbed is: as strips through the route's own profile
    /// stations, so they follow heading and cant exactly, at the
    /// corrected lengths, with the platform edge 1.52 m from the
    /// centre of the track they serve, the top 1.10 m above the
    /// rail head (layout heightAboveRailM), a tactile band and a
    /// white safety line on top, and a 6 m end slope at each end.
    /// The GLB keeps the station building, canopy, footbridge and
    /// furniture of the core (its own platform/track parts are
    /// stripped at load — see stripGeneratedPlatformParts).
    private func buildStationPlatforms(routeVariant: RegionalRouteVariant, travelDirection: RegionalTravelDirection) {
        guard !stationModelPlacements.isEmpty else { return }
        let whiteLineMaterial = Self.pbr(UIColor(red: 0.92, green: 0.92, blue: 0.90, alpha: 1), roughness: 0.85)
        for placement in stationModelPlacements {
            let length = platformLengthM(stationId: placement.stationId, archetype: placement.archetype)
            let start = placement.chainageM - length / 2
            let end = placement.chainageM + length / 2
            let wide = placement.archetype.contains("terminal") || placement.archetype.contains("major") || placement.archetype == "junction_3platform"
            let width: Float = wide ? 6.0 : 4.5
            // Track laterals at the station, the same rule the
            // trackbed uses: both tracks on double-track sections,
            // the single running track elsewhere.
            let midSample = sample(at: placement.chainageM)
            let isMainlineSection = travelDirection == .up ? midSample.distanceM < 60_000 : midSample.distanceM >= 8_000
            let hasPassingTrack = routeVariant == .mainline || (routeVariant == .throughBranch && isMainlineSection)
            let trackLaterals: [Float] = hasPassingTrack ? [-2.1, 2.1] : [travelDirection == .up ? -2.1 : 2.1]
            for trackLateral in trackLaterals {
                // Double track: a platform outside each track.
                // Single track: platforms on both sides (the branch
                // layouts list two side platforms per station).
                let sides: [Float] = hasPassingTrack ? [trackLateral < 0 ? -1.0 : 1.0] : [-1.0, 1.0]
                for sideSign in sides {
                    buildOneStationPlatform(
                        name: "platform-\(placement.stationId)-\(trackLateral)-\(sideSign)",
                        start: start, end: end,
                        trackLateral: trackLateral, sideSign: sideSign, width: width,
                        whiteLineMaterial: whiteLineMaterial
                    )
                    buildStationFurniture(
                        name: "furniture-\(placement.stationId)-\(trackLateral)-\(sideSign)",
                        centerChainage: placement.chainageM,
                        start: start, end: end,
                        trackLateral: trackLateral, sideSign: sideSign
                    )
                }
            }
        }
    }

    private func buildOneStationPlatform(name: String, start: Double, end: Double, trackLateral: Float, sideSign: Float, width: Float, whiteLineMaterial: PhysicallyBasedMaterial) {
        let edgeOffset: Float = 1.52
        let topFull: Float = 0.3065 + 1.10
        let rampLength = 6.0
        let step = 4.25
        var chainages: [Double] = []
        var d = start
        while d < end {
            chainages.append(d)
            d += step
        }
        chainages.append(end)
        guard chainages.count > 1 else { return }
        // Cross-section corners per station point, in the served
        // track's canted profile frame (u = lateral from the track
        // centre, v = height above the track-centre datum):
        // 0 = edge top, 1 = outer top, 2 = outer base, 3 = edge base.
        var corners: [[SIMD3<Float>]] = []
        var tops: [Float] = []
        for chainage in chainages {
            let station = profileStation(at: chainage, trackLateral: trackLateral)
            let ramp = Float(min(min(chainage - start, end - chainage) / rampLength, 1))
            let top = 0.30 + (topFull - 0.30) * max(ramp, 0)
            tops.append(top)
            let baseV = groundLevelM(at: chainage) - 0.4 - sample(at: chainage).elevationM
            let us: [Float] = [sideSign * edgeOffset, sideSign * (edgeOffset + width), sideSign * (edgeOffset + width), sideSign * edgeOffset]
            let vs: [Float] = [top, top, baseV, baseV]
            var row: [SIMD3<Float>] = []
            for i in 0..<4 {
                row.append(station.center + station.xAxis * us[i] + station.yAxis * vs[i])
            }
            corners.append(row)
        }
        var positions: [SIMD3<Float>] = []
        var normals: [SIMD3<Float>] = []
        var indices: [UInt32] = []
        func quad(_ a: SIMD3<Float>, _ b: SIMD3<Float>, _ c: SIMD3<Float>, _ dd: SIMD3<Float>) {
            let base = UInt32(positions.count)
            var normal = simd_cross(b - a, dd - a)
            if simd_length(normal) < 1e-6 { normal = SIMD3<Float>(0, 1, 0) }
            normal = simd_normalize(normal)
            positions.append(contentsOf: [a, b, c, dd])
            for _ in 0..<4 { normals.append(normal) }
            indices.append(contentsOf: [base, base + 1, base + 2, base, base + 2, base + 3])
        }
        // Faces: top (0-1), outer side (1-2), edge face (3-0).
        let facePairs = [(0, 1), (1, 2), (3, 0)]
        for i in 0..<(corners.count - 1) {
            for (p, q) in facePairs {
                quad(corners[i][p], corners[i][q], corners[i + 1][q], corners[i + 1][p])
            }
        }
        // End caps.
        if let first = corners.first {
            quad(first[0], first[3], first[2], first[1])
        }
        if let last = corners.last {
            quad(last[0], last[1], last[2], last[3])
        }
        var descriptor = MeshDescriptor(name: name)
        descriptor.positions = MeshBuffers.Positions(positions)
        descriptor.normals = MeshBuffers.Normals(normals)
        descriptor.primitives = .triangles(indices)
        if let mesh = try? MeshResource.generate(from: [descriptor]) {
            var material = concreteMaterial
            material.faceCulling = .none
            let entity = ModelEntity(mesh: mesh, materials: [material])
            entity.name = name
            world.addChild(entity)
        }
        // Tactile band and white safety line on the full-height
        // part of the platform top.
        let tactileInner = edgeOffset + 0.30
        func topStrip(name: String, innerU: Float, outerU: Float, lift: Float, material: PhysicallyBasedMaterial) {
            var stripPositions: [SIMD3<Float>] = []
            var stripNormals: [SIMD3<Float>] = []
            var stripIndices: [UInt32] = []
            var vertexCount = 0
            var previousInStrip = false
            for (index, chainage) in chainages.enumerated() {
                let ramp = min(min(chainage - start, end - chainage) / rampLength, 1)
                guard ramp >= 0.99 else { previousInStrip = false; continue }
                let station = profileStation(at: chainage, trackLateral: trackLateral)
                let v = tops[index] + lift
                let a = station.center + station.xAxis * (sideSign * innerU) + station.yAxis * v
                let b = station.center + station.xAxis * (sideSign * outerU) + station.yAxis * v
                stripPositions.append(contentsOf: [a, b])
                stripNormals.append(contentsOf: [station.yAxis, station.yAxis])
                if previousInStrip {
                    let base = UInt32((vertexCount - 1) * 2)
                    stripIndices.append(contentsOf: [base, base + 1, base + 2, base + 1, base + 3, base + 2])
                }
                vertexCount += 1
                previousInStrip = true
            }
            guard stripIndices.count > 0 else { return }
            var stripDescriptor = MeshDescriptor(name: name)
            stripDescriptor.positions = MeshBuffers.Positions(stripPositions)
            stripDescriptor.normals = MeshBuffers.Normals(stripNormals)
            stripDescriptor.primitives = .triangles(stripIndices)
            guard let mesh = try? MeshResource.generate(from: [stripDescriptor]) else { return }
            var material = material
            material.faceCulling = .none
            let entity = ModelEntity(mesh: mesh, materials: [material])
            entity.name = name
            world.addChild(entity)
        }
        topStrip(name: "\(name)-tactile", innerU: tactileInner, outerU: tactileInner + 0.30, lift: 0.012, material: tactileMaterial)
        topStrip(name: "\(name)-whiteline", innerU: edgeOffset + 0.08, outerU: edgeOffset + 0.18, lift: 0.006, material: whiteLineMaterial)
    }

    // MARK: quality29 procedural station furniture

    private var stationBenchWoodMesh: MeshResource?
    private var stationBenchFrameMesh: MeshResource?

    /// Appends an axis-aligned box to mesh buffers, in the furniture
    /// local frame: X = lateral (a bench's front faces -X), Y = up
    /// from the platform top, Z = along the track. 24 vertices with
    /// per-face normals and 0..1 UVs so textured materials work.
    private func appendFurnitureBox(
        positions: inout [SIMD3<Float>], normals: inout [SIMD3<Float>],
        uvs: inout [SIMD2<Float>], indices: inout [UInt32],
        center: SIMD3<Float>, size: SIMD3<Float>
    ) {
        let hx = size.x / 2
        let hy = size.y / 2
        let hz = size.z / 2
        let faces: [(SIMD3<Float>, [SIMD3<Float>])] = [
            (SIMD3<Float>(0, 0, 1), [SIMD3<Float>(-hx, -hy, hz), SIMD3<Float>(hx, -hy, hz), SIMD3<Float>(hx, hy, hz), SIMD3<Float>(-hx, hy, hz)]),
            (SIMD3<Float>(0, 0, -1), [SIMD3<Float>(hx, -hy, -hz), SIMD3<Float>(-hx, -hy, -hz), SIMD3<Float>(-hx, hy, -hz), SIMD3<Float>(hx, hy, -hz)]),
            (SIMD3<Float>(1, 0, 0), [SIMD3<Float>(hx, -hy, hz), SIMD3<Float>(hx, -hy, -hz), SIMD3<Float>(hx, hy, -hz), SIMD3<Float>(hx, hy, hz)]),
            (SIMD3<Float>(-1, 0, 0), [SIMD3<Float>(-hx, -hy, -hz), SIMD3<Float>(-hx, -hy, hz), SIMD3<Float>(-hx, hy, hz), SIMD3<Float>(-hx, hy, -hz)]),
            (SIMD3<Float>(0, 1, 0), [SIMD3<Float>(-hx, hy, hz), SIMD3<Float>(hx, hy, hz), SIMD3<Float>(hx, hy, -hz), SIMD3<Float>(-hx, hy, -hz)]),
            (SIMD3<Float>(0, -1, 0), [SIMD3<Float>(-hx, -hy, -hz), SIMD3<Float>(hx, -hy, -hz), SIMD3<Float>(hx, -hy, hz), SIMD3<Float>(-hx, -hy, hz)]),
        ]
        let faceUV: [SIMD2<Float>] = [SIMD2<Float>(0, 0), SIMD2<Float>(1, 0), SIMD2<Float>(1, 1), SIMD2<Float>(0, 1)]
        for (normal, corners) in faces {
            let base = UInt32(positions.count)
            for (cornerIndex, corner) in corners.enumerated() {
                positions.append(center + corner)
                normals.append(normal)
                uvs.append(faceUV[cornerIndex])
            }
            indices.append(contentsOf: [base, base + 1, base + 2, base, base + 2, base + 3])
        }
    }

    /// The shared bench meshes: timber seat/back slats (wood) and
    /// the steel frame (panel legs + back posts). Real dimensions:
    /// 1.8 m long, seat top 0.45 m, back top 0.97 m. The GLB bench
    /// this replaces had the same nominal size but read as a solid
    /// timber wall in photos because its back was one slab wearing
    /// a stretched plank texture; slats with gaps fix that.
    private func makeStationBenchMeshes() -> (wood: MeshResource, frame: MeshResource)? {
        if let wood = stationBenchWoodMesh, let frame = stationBenchFrameMesh {
            return (wood, frame)
        }
        var wp: [SIMD3<Float>] = []
        var wn: [SIMD3<Float>] = []
        var wuv: [SIMD2<Float>] = []
        var wi: [UInt32] = []
        for sx: Float in [-0.17, 0, 0.17] {
            appendFurnitureBox(positions: &wp, normals: &wn, uvs: &wuv, indices: &wi,
                               center: SIMD3<Float>(sx, 0.4275, 0), size: SIMD3<Float>(0.13, 0.045, 1.8))
        }
        for sy: Float in [0.72, 0.90] {
            appendFurnitureBox(positions: &wp, normals: &wn, uvs: &wuv, indices: &wi,
                               center: SIMD3<Float>(0.26, sy, 0), size: SIMD3<Float>(0.04, 0.13, 1.8))
        }
        var woodDescriptor = MeshDescriptor(name: "station-bench-wood")
        woodDescriptor.positions = MeshBuffers.Positions(wp)
        woodDescriptor.normals = MeshBuffers.Normals(wn)
        woodDescriptor.textureCoordinates = MeshBuffers.TextureCoordinates(wuv)
        woodDescriptor.primitives = .triangles(wi)
        var fp: [SIMD3<Float>] = []
        var fn: [SIMD3<Float>] = []
        var fuv: [SIMD2<Float>] = []
        var fi: [UInt32] = []
        for sz: Float in [-0.72, 0.72] {
            appendFurnitureBox(positions: &fp, normals: &fn, uvs: &fuv, indices: &fi,
                               center: SIMD3<Float>(0, 0.225, sz), size: SIMD3<Float>(0.5, 0.45, 0.06))
            appendFurnitureBox(positions: &fp, normals: &fn, uvs: &fuv, indices: &fi,
                               center: SIMD3<Float>(0.26, 0.66, sz), size: SIMD3<Float>(0.04, 0.48, 0.05))
        }
        var frameDescriptor = MeshDescriptor(name: "station-bench-frame")
        frameDescriptor.positions = MeshBuffers.Positions(fp)
        frameDescriptor.normals = MeshBuffers.Normals(fn)
        frameDescriptor.textureCoordinates = MeshBuffers.TextureCoordinates(fuv)
        frameDescriptor.primitives = .triangles(fi)
        guard let wood = try? MeshResource.generate(from: [woodDescriptor]),
              let frame = try? MeshResource.generate(from: [frameDescriptor]) else { return nil }
        stationBenchWoodMesh = wood
        stationBenchFrameMesh = frame
        return (wood, frame)
    }

    /// Benches, a vending machine and a bin for one platform,
    /// placed in the same canted profile frame the platform itself
    /// is built in, so every item sits exactly on the platform top
    /// and follows its curve and grade (quality29; the rigid GLB
    /// items they replace sank into the platform on grades). The
    /// station core stays clear: footbridge stairs land within
    /// +/-2.5 m of the centre and the GLB station building spans
    /// local X -19...-9 on one side, so no bench goes at -17 m.
    private func buildStationFurniture(name: String, centerChainage: Double, start: Double, end: Double, trackLateral: Float, sideSign: Float) {
        let topV: Float = 0.3065 + 1.10
        func topPoint(at chainage: Double, u: Float, v: Float) -> SIMD3<Float> {
            let station = profileStation(at: chainage, trackLateral: trackLateral)
            return station.center + station.xAxis * u + station.yAxis * v
        }
        func orientation(at chainage: Double) -> simd_quatf {
            let s = sample(at: chainage)
            var q = simd_quatf(angle: -s.heading, axis: SIMD3<Float>(0, 1, 0)) * simd_quatf(angle: -s.bankRadians, axis: SIMD3<Float>(0, 0, 1))
            if sideSign < 0 {
                q = q * simd_quatf(angle: Float.pi, axis: SIMD3<Float>(0, 1, 0))
            }
            return q
        }
        if let meshes = makeStationBenchMeshes() {
            var woodMaterial = sleeperMaterial
            woodMaterial.faceCulling = .none
            var frameMaterial = Self.pbr(UIColor(red: 0.16, green: 0.17, blue: 0.18, alpha: 1), metallic: 0.55, roughness: 0.5)
            frameMaterial.faceCulling = .none
            for offset: Double in [-51, -34, 17, 34, 51] {
                let chainage = centerChainage + offset
                guard chainage >= start + 9, chainage <= end - 9 else { continue }
                let q = orientation(at: chainage)
                let position = topPoint(at: chainage, u: sideSign * 5.35, v: topV)
                let wood = ModelEntity(mesh: meshes.wood, materials: [woodMaterial])
                wood.name = "\(name)-bench-wood-\(Int(offset))"
                wood.position = position
                wood.orientation = q
                world.addChild(wood)
                let frame = ModelEntity(mesh: meshes.frame, materials: [frameMaterial])
                frame.name = "\(name)-bench-frame-\(Int(offset))"
                frame.position = position
                frame.orientation = q
                world.addChild(frame)
            }
        }
        let vendingBodyMaterial = Self.pbr(UIColor(red: 0.84, green: 0.85, blue: 0.86, alpha: 1), metallic: 0.15, roughness: 0.45)
        let binMaterial = Self.pbr(UIColor(red: 0.20, green: 0.28, blue: 0.22, alpha: 1), roughness: 0.8)
        let vendingChainage = centerChainage + 12.5
        if vendingChainage <= end - 9 {
            let q = orientation(at: vendingChainage)
            _ = addBox(parent: world, name: "\(name)-vending", size: SIMD3<Float>(0.62, 1.9, 1.05),
                       position: topPoint(at: vendingChainage, u: sideSign * 5.45, v: topV + 0.95),
                       material: vendingBodyMaterial, orientation: q)
            _ = addBox(parent: world, name: "\(name)-vending-front", size: SIMD3<Float>(0.04, 1.35, 0.88),
                       position: topPoint(at: vendingChainage, u: sideSign * 5.45 - sideSign * 0.32, v: topV + 1.02),
                       material: glassMaterial, orientation: q)
        }
        let binChainage = centerChainage + 14.3
        if binChainage <= end - 9 {
            _ = addBox(parent: world, name: "\(name)-bin", size: SIMD3<Float>(0.45, 0.6, 0.45),
                       position: topPoint(at: binChainage, u: sideSign * 5.45, v: topV + 0.3),
                       material: binMaterial, orientation: orientation(at: binChainage))
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

    /// Station surroundings (quality31). quality29's platform
    /// clearance pushed every building back from the platforms, and
    /// the stations were left standing on a bare flat apron: nothing
    /// behind the platform, no forecourt, no frontage. This pass
    /// dresses every station the platform builder serves, in the
    /// same placement order: a paved forecourt (concrete walk plus
    /// an asphalt band) stepped along the banked frame, a post-and-
    /// rail fence along the platform's back edge on the outer
    /// thirds (the GLB core around the centre carries the footbridge
    /// stairs and signs), a bicycle shelter with racks near the
    /// +end, a shrub line along the forecourt's outer edge, and two
    /// mid-rise frontage buildings per side standing on the apron
    /// with their faces about 12.5 m behind the platform back —
    /// clear of the platforms by construction, so the quality29
    /// clearance stays intact. Everything stands on the apron datum
    /// (sample elevation), which is the visible ground plane beside
    /// the line at both grade and elevated stations.
    private func buildStationSurroundings(routeVariant: RegionalRouteVariant, travelDirection: RegionalTravelDirection) {
        guard !stationModelPlacements.isEmpty else { return }
        var walkBatch = MeshBatchBuilder()
        var roadBatch = MeshBatchBuilder()
        var fenceBatch = MeshBatchBuilder()
        var shelterBatch = MeshBatchBuilder()
        var roofBatch = MeshBatchBuilder()
        var baseBatch = MeshBatchBuilder()
        var bodyBatches = officeMaterials.map { _ in MeshBatchBuilder() }
        var shrubBlobs: [(center: SIMD3<Float>, radii: SIMD3<Float>)] = []
        let topFull: Float = 0.3065 + 1.10

        for (stationIndex, placement) in stationModelPlacements.enumerated() {
            let length = platformLengthM(stationId: placement.stationId, archetype: placement.archetype)
            let start = placement.chainageM - length / 2
            let end = placement.chainageM + length / 2
            let wide = placement.archetype.contains("terminal") || placement.archetype.contains("major") || placement.archetype == "junction_3platform"
            let width: Float = wide ? 6.0 : 4.5
            let midSample = sample(at: placement.chainageM)
            let isMainlineSection = travelDirection == .up ? midSample.distanceM < 60_000 : midSample.distanceM >= 8_000
            let hasPassingTrack = routeVariant == .mainline || (routeVariant == .throughBranch && isMainlineSection)
            let trackLaterals: [Float] = hasPassingTrack ? [-2.1, 2.1] : [travelDirection == .up ? -2.1 : 2.1]
            for trackLateral in trackLaterals {
                let sides: [Float] = hasPassingTrack ? [trackLateral < 0 ? -1.0 : 1.0] : [-1.0, 1.0]
                for sideSign in sides {
                    let backU: Float = 1.52 + width
                    let backLateral = trackLateral + sideSign * backU

                    // -- Forecourt paving, stepped every 8.5 m in
                    // the banked frame like the lineside walls.
                    var pavingD = start - 6
                    while pavingD < end + 6 {
                        let mid = min(pavingD + 4.25, end + 6)
                        let frame = profileStation(at: mid, trackLateral: 0)
                        let axisZ = simd_cross(frame.xAxis, frame.yAxis)
                        let span = Float(min(8.5, end + 6 - pavingD)) + 0.4
                        let walkCenter = frame.center + frame.xAxis * (backLateral + sideSign * 1.25) + frame.yAxis * (-0.005)
                        walkBatch.addBoxAxes(center: walkCenter, size: SIMD3<Float>(2.5, 0.07, span), ax: frame.xAxis, ay: frame.yAxis, az: axisZ)
                        let roadCenter = frame.center + frame.xAxis * (backLateral + sideSign * 6.9) + frame.yAxis * (-0.012)
                        roadBatch.addBoxAxes(center: roadCenter, size: SIMD3<Float>(8.8, 0.06, span), ax: frame.xAxis, ay: frame.yAxis, az: axisZ)
                        pavingD += 8.5
                    }

                    // -- Platform-back fence on the outer thirds:
                    // posts every 4.25 m with a top and mid rail,
                    // standing on the platform's back edge (the
                    // benches at u = 5.35 sit just in front of it).
                    let fenceU = sideSign * (backU - 0.15)
                    let fenceRuns: [(Double, Double)] = [(start, placement.chainageM - 22), (placement.chainageM + 22, end)]
                    for run in fenceRuns {
                        var previousTop: SIMD3<Float>? = nil
                        var previousMid: SIMD3<Float>? = nil
                        var fd = run.0
                        while fd <= run.1 {
                            let station = profileStation(at: fd, trackLateral: trackLateral)
                            let axisZ = simd_cross(station.xAxis, station.yAxis)
                            let ramp = Float(min(min(fd - start, end - fd) / 6.0, 1))
                            let top = 0.30 + (topFull - 0.30) * max(ramp, 0)
                            let base = station.center + station.xAxis * fenceU + station.yAxis * top
                            let postTop = base + station.yAxis * 0.95
                            fenceBatch.addBoxAxes(center: base + station.yAxis * 0.475, size: SIMD3<Float>(0.07, 0.95, 0.07), ax: station.xAxis, ay: station.yAxis, az: axisZ)
                            if let prevTop = previousTop, let prevMid = previousMid {
                                fenceBatch.addSegment(from: prevTop, to: postTop, thickness: 0.05)
                                fenceBatch.addSegment(from: prevMid, to: base + station.yAxis * 0.55, thickness: 0.04)
                            }
                            previousTop = postTop
                            previousMid = base + station.yAxis * 0.55
                            fd += 4.25
                        }
                    }

                    // -- Bicycle shelter near the +end of the
                    // forecourt: a steel canopy on four posts over
                    // two rows of rack bars. The GLB station
                    // building spans centre -19...-9 on one side,
                    // so the +end stays clear on both sides.
                    let shelterFrame = profileStation(at: placement.chainageM + length * 0.32, trackLateral: 0)
                    let shelterAxisZ = simd_cross(shelterFrame.xAxis, shelterFrame.yAxis)
                    let shelterCenter = shelterFrame.center + shelterFrame.xAxis * (backLateral + sideSign * 4.7)
                    shelterBatch.addBoxAxes(center: shelterCenter + shelterFrame.yAxis * 2.25, size: SIMD3<Float>(3.4, 0.09, 6.4), ax: shelterFrame.xAxis, ay: shelterFrame.yAxis, az: shelterAxisZ)
                    for postU: Float in [-1.5, 1.5] {
                        for postV: Float in [-3.0, 3.0] {
                            let postCenter = shelterCenter + shelterFrame.xAxis * postU + shelterAxisZ * postV + shelterFrame.yAxis * 1.1
                            shelterBatch.addBoxAxes(center: postCenter, size: SIMD3<Float>(0.08, 2.2, 0.08), ax: shelterFrame.xAxis, ay: shelterFrame.yAxis, az: shelterAxisZ)
                        }
                    }
                    for rackRow: Float in [-0.8, 0.8] {
                        var rackV: Float = -2.4
                        while rackV <= 2.4 {
                            let rackCenter = shelterCenter + shelterFrame.xAxis * rackRow + shelterAxisZ * rackV + shelterFrame.yAxis * 0.3
                            shelterBatch.addBoxAxes(center: rackCenter, size: SIMD3<Float>(0.9, 0.55, 0.05), ax: shelterFrame.xAxis, ay: shelterFrame.yAxis, az: shelterAxisZ)
                            rackV += 1.2
                        }
                    }

                    // -- Station-front buildings: two per side on
                    // the apron, faces about 12.5 m behind the
                    // platform back, clear of the platform span's
                    // lateral band by construction.
                    for (buildingIndex, fraction) in [(-0.58), (0.58)].enumerated() {
                        let seed = stationIndex * 7 + buildingIndex * 3 + (sideSign > 0 ? 1 : 0) + (trackLateral > 0 ? 2 : 0)
                        let bSample = sample(at: placement.chainageM + length * fraction)
                        let bWidth: Float = 11 + Float(seed % 3) * 1.6
                        let bDepth: Float = 7.5 + Float((seed / 3) % 2) * 1.5
                        let bHeight: Float = 9 + Float((seed * 29) % 70) / 10
                        let bLateral = backLateral + sideSign * (12.5 + bDepth / 2)
                        let bx = bSample.x + bLateral * cos(bSample.heading)
                        let bz = bSample.z + bLateral * sin(bSample.heading)
                        let baseY = bSample.elevationM - 0.06
                        bodyBatches[abs(seed) % bodyBatches.count].addBox(center: SIMD3<Float>(bx, baseY + bHeight / 2, bz), size: SIMD3<Float>(bDepth, bHeight, bWidth), yaw: -bSample.heading)
                        roofBatch.addBox(center: SIMD3<Float>(bx, baseY + bHeight + 0.12, bz), size: SIMD3<Float>(bDepth + 0.4, 0.24, bWidth + 0.4), yaw: -bSample.heading)
                        baseBatch.addBox(center: SIMD3<Float>(bx, baseY + 1.0, bz), size: SIMD3<Float>(bDepth + 0.15, 2.0, bWidth + 0.15), yaw: -bSample.heading)
                    }

                    // -- Trees between the forecourt and the
                    // frontage buildings.
                    for treeIndex in 0..<3 {
                        let tSample = sample(at: placement.chainageM + length * (Double(treeIndex) - 1) * 0.30)
                        let tLateral = backLateral + sideSign * 12.3
                        let tx = tSample.x + tLateral * cos(tSample.heading)
                        let tz = tSample.z + tLateral * sin(tSample.heading)
                        addTree(parent: world, name: "station-tree-\(stationIndex)-\(Int(trackLateral))-\(Int(sideSign))-\(treeIndex)", x: tx, z: tz, height: 5 + Float((stationIndex + treeIndex) % 4) * 0.8, material: foliageMaterials[(stationIndex + treeIndex) % foliageMaterials.count], groundY: tSample.elevationM - 0.02)
                    }

                    // -- Shrub line along the forecourt's outer
                    // edge.
                    var shrubD = start + 3
                    while shrubD < end - 2 {
                        let sSample = sample(at: shrubD)
                        let sLateral = backLateral + sideSign * 11.9
                        let cx = sSample.x + sLateral * cos(sSample.heading)
                        let cz = sSample.z + sLateral * sin(sSample.heading)
                        let jitter = foliageJitter(seed: Float(shrubD), salt: Float(stationIndex * 3 + 1))
                        shrubBlobs.append((center: SIMD3<Float>(cx, sSample.elevationM + 0.30 + jitter * 0.08, cz), radii: SIMD3<Float>(0.85, 0.42, 0.7)))
                        shrubD += 7
                    }
                }
            }
        }

        if let mesh = walkBatch.build(name: "station-forecourt-walk", material: concreteMaterial) { world.addChild(mesh) }
        if let mesh = roadBatch.build(name: "station-forecourt-road", material: roadMaterial) { world.addChild(mesh) }
        if let mesh = fenceBatch.build(name: "station-back-fence", material: poleMaterial) { world.addChild(mesh) }
        if let mesh = shelterBatch.build(name: "station-bike-shelter", material: poleMaterial) { world.addChild(mesh) }
        if let mesh = roofBatch.build(name: "station-front-roofs", material: roofMaterials[2]) { world.addChild(mesh) }
        if let mesh = baseBatch.build(name: "station-front-bases", material: concreteMaterial) { world.addChild(mesh) }
        for (materialIndex, batch) in bodyBatches.enumerated() {
            if let mesh = batch.build(name: "station-front-body-\(materialIndex)", material: officeMaterials[materialIndex]) { world.addChild(mesh) }
        }
        if let shrubs = foliageBlobEntity(name: "station-shrubs", blobs: shrubBlobs, material: foliageMaterials[0], longitudes: 6, latitudes: 5) { world.addChild(shrubs) }
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
                    let yaw = simd_quatf(angle: -sample.heading, axis: SIMD3<Float>(0, 1, 0))
                    let length = Float(landmark.lengthM / Double(samples.count))
                    let center = routeOffsetPoint(sample, lateral: 0)
                    addSurfaceBox(parent: world, name: "\(landmark.id)-water-\(index)", size: SIMD3<Float>(18, 0.28, length),
                                  position: SIMD3<Float>(center.x, center.y - 0.62, center.z), color: water, roughness: 0.18, orientation: yaw)
                    addSurfaceBox(parent: world, name: "\(landmark.id)-deck-\(index)", size: SIMD3<Float>(8.4, 0.16, length),
                                  position: SIMD3<Float>(center.x, center.y - 0.08, center.z), color: UIColor(red: 0.46, green: 0.48, blue: 0.47, alpha: 1),
                                  roughness: 0.84, orientation: yaw)
                    for side in [-1.0, 1.0] {
                        let edge = routeOffsetPoint(sample, lateral: Float(side) * 4.55)
                        addSurfaceBox(parent: world, name: "\(landmark.id)-parapet-\(index)-\(Int(side))",
                                      size: SIMD3<Float>(0.28, 1.2, length),
                                      position: SIMD3<Float>(edge.x, edge.y + 0.7, edge.z), color: UIColor(red: 0.52, green: 0.54, blue: 0.52, alpha: 1),
                                      roughness: 0.8, orientation: yaw)
                    }
                    addBox(parent: world, name: "\(landmark.id)-pier-\(index)", size: SIMD3<Float>(0.7, 1.05, 0.7),
                           position: SIMD3<Float>(center.x, center.y - 0.85, center.z), material: concreteMaterial, orientation: yaw)
                }
            case .cutting:
                // quality24: this scene has no raised terrain beside
                // the line (the ground model is at or below rail
                // level everywhere), so the old sheer concrete walls
                // stood on flat ground with nothing behind them and
                // read as two giant blank boards filling the frame
                // (CI #221 photo 11, 45,310 m). A cutting the terrain
                // cannot back is drawn as a grass bank instead: a
                // slope rising away from the line, the mirror of the
                // embankment case below, which is consistent with
                // flat surrounding ground.
                let samples = landmarkSampleChainages(landmark, limit: sampleLimit)
                for (index, chainage) in samples.enumerated() {
                    let sample = sample(at: chainage)
                    let yaw = simd_quatf(angle: -sample.heading, axis: SIMD3<Float>(0, 1, 0))
                    let length = Float(landmark.lengthM / Double(samples.count))
                    for side in [-1.0, 1.0] {
                        let edge = routeOffsetPoint(sample, lateral: Float(side) * 6.8)
                        let roll = simd_quatf(angle: Float(side) * 0.48, axis: SIMD3<Float>(0, 0, 1))
                        addSurfaceBox(parent: world, name: "\(landmark.id)-bank-\(index)-\(Int(side))",
                                      size: SIMD3<Float>(6.5, 0.42, length),
                                      position: SIMD3<Float>(edge.x, edge.y + 0.35, edge.z),
                                      color: grass, roughness: 0.95, orientation: yaw * roll)
                    }
                }
            case .embankment:
                let samples = landmarkSampleChainages(landmark, limit: sampleLimit)
                for (index, chainage) in samples.enumerated() {
                    let sample = sample(at: chainage)
                    let yaw = simd_quatf(angle: -sample.heading, axis: SIMD3<Float>(0, 1, 0))
                    let length = Float(landmark.lengthM / Double(samples.count))
                    for side in [-1.0, 1.0] {
                        let edge = routeOffsetPoint(sample, lateral: Float(side) * 6.8)
                        let roll = simd_quatf(angle: Float(side) * -0.48, axis: SIMD3<Float>(0, 0, 1))
                        addSurfaceBox(parent: world, name: "\(landmark.id)-slope-\(index)-\(Int(side))",
                                      size: SIMD3<Float>(6.5, 0.42, length),
                                      position: SIMD3<Float>(edge.x, edge.y - 0.35, edge.z),
                                      color: grass, roughness: 0.95, orientation: yaw * roll)
                    }
                }
            case .levelCrossing:
                let sample = sample(at: (landmark.startChainageM + landmark.endChainageM) * 0.5)
                let yaw = simd_quatf(angle: -sample.heading, axis: SIMD3<Float>(0, 1, 0))
                for side in [-1.0, 1.0] {
                    let approach = routeOffsetPoint(sample, lateral: Float(side) * 8.0)
                    addSurfaceBox(parent: world, name: "\(landmark.id)-approach-\(Int(side))",
                                  size: SIMD3<Float>(11, 0.12, 6.4),
                                  position: SIMD3<Float>(approach.x, approach.y + 0.06, approach.z),
                                  color: UIColor(red: 0.17, green: 0.18, blue: 0.18, alpha: 1),
                                  roughness: 0.78, orientation: yaw)
                    let post = routeOffsetPoint(sample, lateral: Float(side) * 4.3)
                    addBox(parent: world, name: "\(landmark.id)-post-\(Int(side))", size: SIMD3<Float>(0.16, 2.3, 0.16),
                           position: SIMD3<Float>(post.x, post.y + 1.15, post.z), material: poleMaterial)
                    addBox(parent: world, name: "\(landmark.id)-raised-arm-\(Int(side))", size: SIMD3<Float>(0.12, 2.15, 0.1),
                           position: SIMD3<Float>(post.x, post.y + 2.35, post.z), material: roofMaterials[0])
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
            : SIMD3<Float>(routeSample.x, routeSample.elevationM + 2.7, routeSample.z)
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
                bankRadians: first.bankRadians,
                // Extrapolation holds the end elevation: the lead car
                // extends only a few metres past the sampled range.
                elevationM: first.elevationM
            )
        }
        // First sample at or past the target chainage, by binary
        // search (the samples are sorted by construction; this runs
        // every frame and the alignment is now sampled at 8.5 m).
        var searchLow = 0
        var searchHigh = samples.count
        while searchLow < searchHigh {
            let mid = (searchLow + searchHigh) / 2
            if samples[mid].distanceM >= distanceM {
                searchHigh = mid
            } else {
                searchLow = mid + 1
            }
        }
        let upperIndex: Int? = searchLow < samples.count ? searchLow : nil
        guard let upperIndex else {
            if let last = samples.last {
                let delta = Float(distanceM - last.distanceM)
                return RouteSample(
                    distanceM: distanceM,
                    x: last.x + sin(last.heading) * delta,
                    z: last.z - cos(last.heading) * delta,
                    heading: last.heading,
                    bankRadians: last.bankRadians,
                    elevationM: last.elevationM
                )
            }
            return RouteSample(distanceM: distanceM, x: 0, z: Float(-distanceM), heading: 0, bankRadians: 0, elevationM: 0)
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
            bankRadians: lower.bankRadians + (upper.bankRadians - lower.bankRadians) * fraction,
            elevationM: lower.elevationM + (upper.elevationM - lower.elevationM) * fraction
        )
    }

    private func routeOffsetPoint(_ sample: RouteSample, lateral: Float) -> SIMD3<Float> {
        SIMD3<Float>(
            sample.x + lateral * cos(sample.heading),
            sample.elevationM,
            sample.z + lateral * sin(sample.heading)
        )
    }

    private func stableIndex(_ value: String, count: Int) -> Int {
        guard count > 0 else { return 0 }
        let checksum = value.utf8.reduce(UInt64(2_166_136_261)) { ($0 ^ UInt64($1)) &* 16_777_619 }
        return Int(checksum % UInt64(count))
    }

    /// Direction the sunlight travels (unit-ized at the use sites):
    /// downward at ≈38° elevation, from ahead-right of the route's
    /// initial heading, so shadows fall beside the objects that cast
    /// them in the forward view instead of hiding behind them.
    static let sunTravelDirection = SIMD3<Float>(-0.55, -0.62, -0.56)

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
        // quality24: the lateral convention here must match the one
        // every other builder uses (routeOffsetPoint, ribbonEntity,
        // the vehicle placement in update): lateral offset =
        // (cos h, +sin h) in (x, z), and the banked axes are the
        // vehicle's own frame (yaw -h, then roll -bank about the
        // local z). This function used to mirror the z terms
        // (- sin h), which put the rails in a reflected frame: the
        // rail pair drifted off the sleepers by -2L sin^2(h) laterally
        // and L sin(2h) longitudinally (L = track offset), i.e. ~0.4 m
        // sideways at h = 0.3 rad and over 1 m at h = 0.55 rad, worst
        // exactly on the curved sections the tour photographs.
        let center = SIMD3<Float>(s.x + trackLateral * cos(h), s.elevationM, s.z + trackLateral * sin(h))
        let xAxis = SIMD3<Float>(cos(bank) * cos(h), -sin(bank), cos(bank) * sin(h))
        let yAxis = SIMD3<Float>(sin(bank) * cos(h), cos(bank), sin(bank) * sin(h))
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
        // Station spacing for the extruded strips: it also sets how
        // finely curves are faceted (quality24, C3). 8.5 m matches
        // the alignment sampling, so stations sit exactly on the
        // polyline vertices; the chord deviation at R324 is ~2.8 cm.
        let step = 8.5
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

    /// quality37: the multi-track stations (the 5-track major
    /// station and the two 3-track passing stations) get fan
    /// sidings on both throats: a track that leaves the running
    /// line, runs parallel outside it and merges back before the
    /// platform starts — the visible branching the plain two-track
    /// world never had. The specs come from the station placements,
    /// in the same chainage frame the placement loop uses.
    private func throatFanSpecs() -> [(center: Double, half: Double)] {
        var specs: [(center: Double, half: Double)] = []
        for placement in stationModelPlacements {
            if placement.archetype == "major_5track_4platform" || placement.archetype == "passing_3track_2platform" {
                specs.append((center: placement.chainageM, half: platformLengthM(stationId: placement.stationId, archetype: placement.archetype) / 2))
            }
        }
        return specs
    }

    private func throatFanSpans() -> [(start: Double, end: Double)] {
        var spans: [(start: Double, end: Double)] = []
        for spec in throatFanSpecs() {
            spans.append((start: spec.center - spec.half - 340, end: spec.center - spec.half))
            spans.append((start: spec.center + spec.half, end: spec.center + spec.half + 340))
        }
        return spans
    }

    /// Walls, roads, catenary masts and signal posts all keep out
    /// of the fan spans: the siding sweeps through their laterals.
    private func nearThroatFan(_ chainage: Double) -> Bool {
        for span in throatFanSpans() where chainage >= span.start - 15 && chainage <= span.end + 15 {
            return true
        }
        return false
    }

    /// Siding lateral across its 340 m span: diverge over the
    /// first 200 m, hold at 6.3 m, converge over the last 80 m.
    private func throatFanLateral(u: Double) -> Float {
        func smooth(_ x: Double) -> Double {
            let t = min(max(x, 0), 1)
            return t * t * (3 - 2 * t)
        }
        let diverge = smooth(u / (200.0 / 340.0))
        let converge = smooth((u - 260.0 / 340.0) / (80.0 / 340.0))
        return Float(2.1 + 4.2 * diverge * (1 - converge))
    }

    private func buildThroatFans(routeVariant: RegionalRouteVariant) {
        guard routeVariant == .mainline || routeVariant == .throughBranch else { return }
        guard let firstSample = samples.first, let lastSample = samples.last, firstSample.distanceM < lastSample.distanceM else { return }
        let railSteel = Self.pbr(UIColor(red: 0.52, green: 0.57, blue: 0.60, alpha: 1), metallic: 0.85, roughness: 0.36)
        let runningBand = Self.pbr(UIColor(red: 0.78, green: 0.82, blue: 0.85, alpha: 1), metallic: 0.95, roughness: 0.12)
        let shoulderMaterial = Self.texturedPBR(.white, roughness: 1, textureName: "scenery_ballast", normalName: "normal_ballast")
        let trackbedMaterial = Self.texturedPBR(.white, roughness: 0.95, textureName: "scenery_trackbed", normalName: "normal_trackbed")
        let deckMaterial = Self.pbr(UIColor(red: 0.46, green: 0.48, blue: 0.47, alpha: 1), roughness: 0.84)
        let railProfile: [(x: Float, y: Float)] = [
            (-0.075, 0.145), (0.075, 0.145), (0.075, 0.175), (0.018, 0.185),
            (0.018, 0.255), (0.037, 0.265), (0.037, 0.305), (-0.037, 0.305),
            (-0.037, 0.265), (-0.018, 0.255), (-0.018, 0.185), (-0.075, 0.175)
        ]
        let bandProfile: [(x: Float, y: Float)] = [(-0.026, 0.3065), (0.026, 0.3065)]
        let shoulderLeft: [(x: Float, y: Float)] = [(-2.65, 0.03), (-1.72, 0.165)]
        let shoulderRight: [(x: Float, y: Float)] = [(1.72, 0.165), (2.65, 0.03)]
        let zeroOffsets = [Float](repeating: 0, count: samples.count)
        for spec in throatFanSpecs() {
            let spans: [(start: Double, end: Double, tag: String)] = [
                (start: spec.center - spec.half - 340, end: spec.center - spec.half, tag: "in"),
                (start: spec.center + spec.half, end: spec.center + spec.half + 340, tag: "out")
            ]
            for span in spans {
                guard let lo = samples.firstIndex(where: { $0.distanceM >= span.start - 8.5 }),
                      let hi = samples.lastIndex(where: { $0.distanceM <= span.end + 8.5 }), lo < hi else { continue }
                let range = lo..<(hi + 1)
                // Widened deck under the fan: on the elevated
                // Kankumoshi throat the siding would otherwise hang
                // off the 8.4 m deck edge. At ground level the slab
                // lies below the formation and stays invisible.
                if let deck = ribbonEntity(name: "fan-deck-\(Int(spec.center))-\(span.tag)", width: 17, y: -0.495, tileLength: 12, offsets: zeroOffsets, material: deckMaterial, range: range) {
                    world.addChild(deck)
                }
                for side: Float in [-1, 1] {
                    let sideTag = side > 0 ? "r" : "l"
                    let offsets = samples.map { sample -> Float in
                        let u = (min(max(sample.distanceM, span.start), span.end) - span.start) / 340
                        return side * throatFanLateral(u: u)
                    }
                    // 5 mm above the running trackbed so the two
                    // ribbons never z-fight where the siding lies
                    // on top of the running line at the pinch ends.
                    if let bed = ribbonEntity(name: "fan-trackbed-\(Int(spec.center))-\(span.tag)-\(sideTag)", width: 4.6, y: 0.185, tileLength: 5, offsets: offsets, material: trackbedMaterial, range: range) {
                        world.addChild(bed)
                    }
                    var stations: [ProfileStation] = []
                    var d = span.start
                    while d < span.end {
                        stations.append(profileStation(at: d, trackLateral: side * throatFanLateral(u: (d - span.start) / 340)))
                        d += 8.5
                    }
                    stations.append(profileStation(at: span.end, trackLateral: side * throatFanLateral(u: 1)))
                    let prefix = "fan-\(Int(spec.center))-\(span.tag)-\(sideTag)"
                    for railSide: Float in [-0.72, 0.72] {
                        let profile = railProfile.map { (x: $0.x + railSide, y: $0.y) }
                        if let rail = profileStripEntity(name: "\(prefix)-rail-\(railSide)", stations: stations, profile: profile, closed: true, material: railSteel) {
                            world.addChild(rail)
                        }
                        let band = bandProfile.map { (x: $0.x + railSide, y: $0.y) }
                        if let bandEntity = profileStripEntity(name: "\(prefix)-band-\(railSide)", stations: stations, profile: band, closed: false, material: runningBand) {
                            world.addChild(bandEntity)
                        }
                    }
                    if let left = profileStripEntity(name: "\(prefix)-shoulder-l", stations: stations, profile: shoulderLeft, closed: false, material: shoulderMaterial, uvVTileLength: 6) {
                        world.addChild(left)
                    }
                    if let right = profileStripEntity(name: "\(prefix)-shoulder-r", stations: stations, profile: shoulderRight, closed: false, material: shoulderMaterial, uvVTileLength: 6) {
                        world.addChild(right)
                    }
                }
            }
        }
    }

    /// quality37: at Touhama the branch visibly leaves the
    /// terminus. A track peels away from the inland running track
    /// past the end of the line on fabricated profile stations,
    /// and buffer stops close both running tracks — the end of
    /// the main line and the start of the branch finally read as
    /// a junction instead of the two tracks simply stopping.
    private func buildTerminusDivergence(route: RailwayRouteProfile, routeVariant: RegionalRouteVariant, travelDirection: RegionalTravelDirection) {
        guard routeVariant == .mainline || routeVariant == .throughBranch else { return }
        guard let firstSample = samples.first, let lastSample = samples.last, firstSample.distanceM < lastSample.distanceM else { return }
        guard let terminus = stationModelPlacements.first(where: { $0.archetype == "junction_3platform" }) else { return }
        let center = terminus.chainageM
        let inlandSign = -seaSideSign(travelDirection: travelDirection)
        // Buffer stops on both running tracks, 10 m before the end.
        var bufferBatch = MeshBatchBuilder()
        for lateral: Float in [-2.1, 2.1] {
            let st = profileStation(at: center - 10, trackLateral: lateral)
            let tangent = -simd_cross(st.xAxis, st.yAxis)
            for postU: Float in [-0.85, 0.85] {
                bufferBatch.addBoxAxes(center: st.center + postU * st.xAxis + 0.55 * st.yAxis,
                                       size: SIMD3<Float>(0.28, 1.1, 0.28), ax: st.xAxis, ay: st.yAxis, az: tangent)
            }
            bufferBatch.addBoxAxes(center: st.center + st.yAxis,
                                   size: SIMD3<Float>(2.4, 0.42, 0.3), ax: st.xAxis, ay: st.yAxis, az: tangent)
            bufferBatch.addBoxAxes(center: st.center + 0.15 * st.yAxis,
                                   size: SIMD3<Float>(2.4, 0.3, 0.8), ax: st.xAxis, ay: st.yAxis, az: tangent)
        }
        if let buffers = bufferBatch.build(name: "terminus-buffers", material: poleMaterial) {
            world.addChild(buffers)
        }
        // The diverging track: lateral grows with the square of
        // the distance past its root, the way a turnout curve
        // leaves the straight — slow enough at the root to clear
        // the platform face (3.62 m) until the line has ended.
        let railSteel = Self.pbr(UIColor(red: 0.52, green: 0.57, blue: 0.60, alpha: 1), metallic: 0.85, roughness: 0.36)
        let runningBand = Self.pbr(UIColor(red: 0.78, green: 0.82, blue: 0.85, alpha: 1), metallic: 0.95, roughness: 0.12)
        let shoulderMaterial = Self.texturedPBR(.white, roughness: 1, textureName: "scenery_ballast", normalName: "normal_ballast")
        let formationMaterial = Self.pbr(UIColor(red: 0.24, green: 0.28, blue: 0.24, alpha: 1), roughness: 1)
        let branchBedMaterial = Self.pbr(UIColor(red: 0.37, green: 0.36, blue: 0.34, alpha: 1), roughness: 1)
        let railProfile: [(x: Float, y: Float)] = [
            (-0.075, 0.145), (0.075, 0.145), (0.075, 0.175), (0.018, 0.185),
            (0.018, 0.255), (0.037, 0.265), (0.037, 0.305), (-0.037, 0.305),
            (-0.037, 0.265), (-0.018, 0.255), (-0.018, 0.185), (-0.075, 0.175)
        ]
        let bandProfile: [(x: Float, y: Float)] = [(-0.026, 0.3065), (0.026, 0.3065)]
        let shoulderLeft: [(x: Float, y: Float)] = [(-2.65, 0.03), (-1.72, 0.165)]
        let shoulderRight: [(x: Float, y: Float)] = [(1.72, 0.165), (2.65, 0.03)]
        let base = profileStation(at: center - 30, trackLateral: inlandSign * 2.1)
        let tangent = -simd_cross(base.xAxis, base.yAxis)
        var stations: [ProfileStation] = []
        var t = 0.0
        while t <= 330 {
            let lateral = inlandSign * Float(2.1 + (t * t) / 2400.0)
            let c = base.center + Float(t) * tangent + (lateral - inlandSign * 2.1) * base.xAxis
            stations.append(ProfileStation(center: c, xAxis: base.xAxis, yAxis: base.yAxis, distanceM: center - 30 + t))
            t += 8.5
        }
        let formationProfile: [(x: Float, y: Float)] = [(-6.5, -0.06), (6.5, -0.06)]
        if let formation = profileStripEntity(name: "branch-formation", stations: stations, profile: formationProfile, closed: false, material: formationMaterial) {
            world.addChild(formation)
        }
        let bedProfile: [(x: Float, y: Float)] = [(-2.3, 0.185), (2.3, 0.185)]
        if let bed = profileStripEntity(name: "branch-trackbed", stations: stations, profile: bedProfile, closed: false, material: branchBedMaterial) {
            world.addChild(bed)
        }
        for railSide: Float in [-0.72, 0.72] {
            let profile = railProfile.map { (x: $0.x + railSide, y: $0.y) }
            if let rail = profileStripEntity(name: "branch-rail-\(railSide)", stations: stations, profile: profile, closed: true, material: railSteel) {
                world.addChild(rail)
            }
            let band = bandProfile.map { (x: $0.x + railSide, y: $0.y) }
            if let bandEntity = profileStripEntity(name: "branch-band-\(railSide)", stations: stations, profile: band, closed: false, material: runningBand) {
                world.addChild(bandEntity)
            }
        }
        if let left = profileStripEntity(name: "branch-shoulder-l", stations: stations, profile: shoulderLeft, closed: false, material: shoulderMaterial, uvVTileLength: 6) {
            world.addChild(left)
        }
        if let right = profileStripEntity(name: "branch-shoulder-r", stations: stations, profile: shoulderRight, closed: false, material: shoulderMaterial, uvVTileLength: 6) {
            world.addChild(right)
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
                let yaw = simd_quatf(angle: -sample.heading, axis: SIMD3<Float>(0, 1, 0))
                let base = routeOffsetPoint(sample, lateral: postLateral)
                addBox(parent: world, name: "km-post-\(Int(km))", size: SIMD3<Float>(0.12, 0.95, 0.12),
                       position: SIMD3<Float>(base.x, base.y + 0.48, base.z), material: concreteMaterial, orientation: yaw)
                addBox(parent: world, name: "km-post-cap-\(Int(km))", size: SIMD3<Float>(0.15, 0.2, 0.15),
                       position: SIMD3<Float>(base.x, base.y + 0.98, base.z), material: poleMaterial, orientation: yaw)
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
                let orientation = simd_quatf(angle: -sample.heading, axis: SIMD3<Float>(0, 1, 0)) * simd_quatf(angle: -sample.bankRadians, axis: SIMD3<Float>(0, 0, 1))
                let center = routeOffsetPoint(sample, lateral: runningTrack)
                addBox(parent: world, name: "ats-balise-\(Int(approach))", size: SIMD3<Float>(0.34, 0.07, 0.55),
                       position: SIMD3<Float>(center.x, center.y + 0.22, center.z), material: baliseMaterial, orientation: orientation)
            }
        }
    }

    /// Accumulates boxes and prisms into one mesh, so a whole street
    /// of detailed small parts costs a handful of entities instead of
    /// thousands. Faces carry flat normals; materials come from the
    /// caller, one batch per material family.
    private struct MeshBatchBuilder {
        var positions: [SIMD3<Float>] = []
        var normals: [SIMD3<Float>] = []
        var indices: [UInt32] = []

        mutating func addBoxAxes(center: SIMD3<Float>, size: SIMD3<Float>, ax: SIMD3<Float>, ay: SIMD3<Float>, az: SIMD3<Float>) {
            let hx = size.x / 2, hy = size.y / 2, hz = size.z / 2
            func corner(_ sx: Float, _ sy: Float, _ sz: Float) -> SIMD3<Float> {
                center + ax * (sx * hx) + ay * (sy * hy) + az * (sz * hz)
            }
            // Six faces as (normal, four corners CCW from outside).
            let faces: [(SIMD3<Float>, [SIMD3<Float>])] = [
                (ax, [corner(1, -1, -1), corner(1, -1, 1), corner(1, 1, 1), corner(1, 1, -1)]),
                (-ax, [corner(-1, -1, 1), corner(-1, -1, -1), corner(-1, 1, -1), corner(-1, 1, 1)]),
                (ay, [corner(-1, 1, -1), corner(1, 1, -1), corner(1, 1, 1), corner(-1, 1, 1)]),
                (-ay, [corner(-1, -1, 1), corner(1, -1, 1), corner(1, -1, -1), corner(-1, -1, -1)]),
                (az, [corner(-1, -1, 1), corner(1, -1, 1), corner(1, 1, 1), corner(-1, 1, 1)]),
                (-az, [corner(1, -1, -1), corner(-1, -1, -1), corner(-1, 1, -1), corner(1, 1, -1)])
            ]
            for (normal, corners) in faces {
                let base = UInt32(positions.count)
                for c in corners {
                    positions.append(c)
                    normals.append(normal)
                }
                indices.append(contentsOf: [base, base + 1, base + 2, base, base + 2, base + 3])
            }
        }

        mutating func addBox(center: SIMD3<Float>, size: SIMD3<Float>, yaw: Float) {
            // quality25: this used to build az as (-sin, 0, cos)
            // while ax implied the opposite rotation — a mirrored
            // frame, not a Y rotation at all. On a curve a long box
            // (the 11 m cable trough, the 5.4 m hedge segments) sat
            // skewed by up to twice the heading angle, swinging its
            // ends metres sideways — at the Matsubaracho curve the
            // trough ends reached across the running line. The
            // frame is now the same pure Y rotation the entity
            // builders use (orientation angle = yaw): local X maps
            // to (cos, 0, -sin), local Z to (sin, 0, cos), so with
            // yaw = -heading local X is the route lateral and local
            // Z runs along the track.
            let c = cos(yaw), s = sin(yaw)
            addBoxAxes(center: center, size: size,
                       ax: SIMD3<Float>(c, 0, -s), ay: SIMD3<Float>(0, 1, 0), az: SIMD3<Float>(s, 0, c))
        }

        /// Vertical hexagonal prism (pole, transformer can, insulator).
        mutating func addPrism(baseCenter: SIMD3<Float>, radius: Float, height: Float, yaw: Float) {
            let sides = 6
            var ringBottom: [SIMD3<Float>] = []
            var ringTop: [SIMD3<Float>] = []
            for i in 0..<sides {
                let a = yaw + Float(i) * (Float.pi / 3)
                let dir = SIMD3<Float>(cos(a), 0, -sin(a))
                ringBottom.append(baseCenter + dir * radius)
                ringTop.append(baseCenter + dir * radius + SIMD3<Float>(0, height, 0))
            }
            for i in 0..<sides {
                let j = (i + 1) % sides
                let mid = (ringBottom[i] + ringBottom[j]) / 2 - baseCenter
                var normal = SIMD3<Float>(mid.x, 0, mid.z)
                normal = simd_normalize(normal)
                let base = UInt32(positions.count)
                positions.append(contentsOf: [ringBottom[i], ringBottom[j], ringTop[j], ringTop[i]])
                for _ in 0..<4 { normals.append(normal) }
                indices.append(contentsOf: [base, base + 1, base + 2, base, base + 2, base + 3])
            }
            // Top cap as a fan.
            let capCenter = baseCenter + SIMD3<Float>(0, height, 0)
            for i in 0..<sides {
                let j = (i + 1) % sides
                let base = UInt32(positions.count)
                positions.append(contentsOf: [capCenter, ringTop[j], ringTop[i]])
                for _ in 0..<3 { normals.append(SIMD3<Float>(0, 1, 0)) }
                indices.append(contentsOf: [base, base + 1, base + 2])
            }
        }

        /// A straight wire segment between two points, as a thin box.
        mutating func addSegment(from: SIMD3<Float>, to: SIMD3<Float>, thickness: Float) {
            let dir = to - from
            let length = simd_length(dir)
            guard length > 0.01 else { return }
            let az = dir / length
            var ax = simd_cross(SIMD3<Float>(0, 1, 0), az)
            if simd_length(ax) < 0.01 { ax = SIMD3<Float>(1, 0, 0) }
            ax = simd_normalize(ax)
            let ay = simd_cross(az, ax)
            addBoxAxes(center: (from + to) / 2, size: SIMD3<Float>(thickness, thickness, length), ax: ax, ay: ay, az: az)
        }

        func build(name: String, material: PhysicallyBasedMaterial) -> ModelEntity? {
            guard !positions.isEmpty else { return nil }
            var descriptor = MeshDescriptor(name: name)
            descriptor.positions = MeshBuffers.Positions(positions)
            descriptor.normals = MeshBuffers.Normals(normals)
            descriptor.primitives = .triangles(indices)
            guard let mesh = try? MeshResource.generate(from: [descriptor]) else { return nil }
            var material = material
            material.faceCulling = .none
            return ModelEntity(mesh: mesh, materials: [material])
        }
    }

    /// Full distribution-pole system for the suburban sections:
    /// tapered concrete poles with two steel crossarms, porcelain
    /// insulators, a transformer can on every sixth pole, and wires
    /// that actually sag between poles. Replaces the old single-stick
    /// poles. Geometry is batched per ~1.2 km chunk into three meshes
    /// (concrete / steel / porcelain) to keep the entity count low.
    private func buildUtilityPoles(route: RailwayRouteProfile, routeVariant: RegionalRouteVariant, travelDirection: RegionalTravelDirection) {
        let concrete = Self.pbr(UIColor(red: 0.62, green: 0.62, blue: 0.60, alpha: 1), metallic: 0.02, roughness: 0.9)
        let steel = Self.pbr(UIColor(red: 0.23, green: 0.25, blue: 0.26, alpha: 1), metallic: 0.55, roughness: 0.55)
        let porcelain = Self.pbr(UIColor(red: 0.88, green: 0.87, blue: 0.84, alpha: 1), metallic: 0.05, roughness: 0.35)
        let landmarks = fictionalCorridorLandmarks(for: route)
        let seaSign = seaSideSign(travelDirection: travelDirection)
        // Urban towers already stand in the world (buildSuburb ran
        // first). City poles run along the street edge and must not
        // intersect a tower footprint, so collect tower positions
        // and skip any pole that would land inside one.
        let towerPositions: [SIMD3<Float>] = world.children.compactMap { child in
            child.name.hasPrefix("office-base-") ? child.position : nil
        }
        struct PoleSpot { var chainage: Double; var sample: RouteSample; var lateral: Float }
        for sideSign: Float in [-1, 1] {
            // Collect this side's pole spots first so wires can be
            // strung between consecutive poles.
            var spots: [PoleSpot] = []
            var d = 60.0 + (sideSign > 0 ? 22.5 : 0.0)
            while d < route.distanceM - 60 {
                let band = urbanBand(distanceM: d, route: route, routeVariant: routeVariant, travelDirection: travelDirection)
                let onSeaSide = isCoastal(distanceM: d, route: route, routeVariant: routeVariant, travelDirection: travelDirection) && sideSign == seaSign
                if !onSeaSide && !corridorReserved(at: d, landmarks: landmarks) {
                    if band == 0 {
                        spots.append(PoleSpot(chainage: d, sample: sample(at: d), lateral: sideSign * 18.6))
                    } else {
                        let s = sample(at: d)
                        let p = routeOffsetPoint(s, lateral: sideSign * 11.0)
                        var blocked = false
                        for tower in towerPositions {
                            let dx = tower.x - p.x
                            let dz = tower.z - p.z
                            if dx * dx + dz * dz < 90.25 { blocked = true; break }
                        }
                        if !blocked {
                            spots.append(PoleSpot(chainage: d, sample: s, lateral: sideSign * 11.0))
                        }
                    }
                }
                d += 45
            }
            var concreteBatch = MeshBatchBuilder()
            var steelBatch = MeshBatchBuilder()
            var porcelainBatch = MeshBatchBuilder()
            var chunkIndex = 0
            var chunkStart = spots.first?.chainage ?? 0
            func flush() {
                let tag = "\(sideSign > 0 ? "r" : "l")-\(chunkIndex)"
                if let e = concreteBatch.build(name: "utility-concrete-\(tag)", material: concrete) { world.addChild(e) }
                if let e = steelBatch.build(name: "utility-steel-\(tag)", material: steel) { world.addChild(e) }
                if let e = porcelainBatch.build(name: "utility-porcelain-\(tag)", material: porcelain) { world.addChild(e) }
                concreteBatch = MeshBatchBuilder()
                steelBatch = MeshBatchBuilder()
                porcelainBatch = MeshBatchBuilder()
                chunkIndex += 1
            }
            // Wire runs: attach offsets (lateral from pole centre,
            // height) for the two crossarms.
            let wireRuns: [(offset: Float, height: Float)] = [(-0.8, 8.44), (0.8, 8.44), (-0.65, 7.64), (0.65, 7.64)]
            for (index, spot) in spots.enumerated() {
                if spot.chainage - chunkStart > 1_200 {
                    flush()
                    chunkStart = spot.chainage
                }
                let s = spot.sample
                // Poles stand on the ground: under a viaduct the whole
                // pole, crossarms, insulators and wires drop to the
                // valley floor with it (the wire sag interpolates
                // between the two pole bases, so it follows the
                // ground too).
                let base = groundOffsetPoint(s, lateral: spot.lateral)
                let bc = SIMD3<Float>(base.x, base.y, base.z)
                // Tapered pole: two stacked prisms.
                concreteBatch.addPrism(baseCenter: bc, radius: 0.17, height: 5.0, yaw: s.heading)
                concreteBatch.addPrism(baseCenter: bc + SIMD3<Float>(0, 5.0, 0), radius: 0.125, height: 4.0, yaw: s.heading)
                // Crossarms across the line of the street.
                // (quality25: batch yaw convention — see
                // MeshBatchBuilder.addBox — takes -heading for the
                // across-track axis.)
                for (armHeight, armWidth) in [(Float(8.3), Float(1.9)), (Float(7.5), Float(1.6))] {
                    steelBatch.addBox(center: bc + SIMD3<Float>(0, armHeight, 0),
                                      size: SIMD3<Float>(armWidth, 0.1, 0.09), yaw: -s.heading)
                }
                // Insulators on the arm ends.
                for run in wireRuns {
                    let p = groundOffsetPoint(s, lateral: spot.lateral + run.offset)
                    porcelainBatch.addPrism(baseCenter: SIMD3<Float>(p.x, p.y + run.height - 0.14, p.z), radius: 0.045, height: 0.14, yaw: s.heading)
                }
                // Transformer can on every sixth pole, track side.
                if index % 6 == 3 {
                    let t = groundOffsetPoint(s, lateral: spot.lateral - sideSign * 0.52)
                    steelBatch.addPrism(baseCenter: SIMD3<Float>(t.x, t.y + 5.6, t.z), radius: 0.34, height: 0.95, yaw: s.heading)
                }
                // Sagging wires to the previous pole on this side.
                // The wire sags between the two pole heights and
                // follows the ground elevation between the poles.
                if index > 0 {
                    let prev = spots[index - 1]
                    let span = spot.chainage - prev.chainage
                    if span <= 60 {
                        for run in wireRuns {
                            let a = groundOffsetPoint(prev.sample, lateral: prev.lateral + run.offset)
                            let b = groundOffsetPoint(s, lateral: spot.lateral + run.offset)
                            var lastPoint = SIMD3<Float>(a.x, a.y + run.height, a.z)
                            let steps = 7
                            for k in 1...steps {
                                let t = Float(k) / Float(steps)
                                let sag = 0.85 * 4 * t * (1 - t)
                                let point = SIMD3<Float>(
                                    a.x + (b.x - a.x) * t,
                                    a.y + (b.y - a.y) * t + run.height - sag,
                                    a.z + (b.z - a.z) * t)
                                steelBatch.addSegment(from: lastPoint, to: point, thickness: 0.035)
                                lastPoint = point
                            }
                        }
                    }
                }
            }
            flush()
        }
    }

    /// A horizontal strip that follows the route samples. `y` is the
    /// height above the rail head at each sample: the strip rides on
    /// the track elevation, so ground, ballast and apron follow the
    /// gradients instead of lying on one flat plane. `yOffsets`
    /// adds a per-sample extra height (used for the far ground's
    /// gentle undulation); `absoluteY` pins the whole strip to one
    /// level instead — the sea and beach are flat water and sand,
    /// they must not climb with the track. `widths` overrides the
    /// uniform `width` per sample (see `clampedRibbonSpan`): wide
    /// ground ribbons narrow on the inner side of tight curves so
    /// they never fold through the track.
    private func ribbonEntity(name: String, width: Float, y: Float, tileLength: Float, offsets: [Float], material: PhysicallyBasedMaterial, range: Range<Int>? = nil, uTileLength: Float? = nil, yOffsets: [Float]? = nil, absoluteY: Float? = nil, widths: [Float]? = nil) -> ModelEntity? {
        guard offsets.count == samples.count, samples.count > 1, widths == nil || widths?.count == samples.count else { return nil }
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
            let cz = sample.z + lateral * sin(sample.heading)
            let rx = cos(sample.heading)
            let rz = sin(sample.heading)
            let half = (widths?[i] ?? width) / 2
            let vertexY = absoluteY ?? (y + sample.elevationM + (yOffsets?[i] ?? 0))
            positions.append(SIMD3<Float>(cx - rx * half, vertexY, cz - rz * half))
            positions.append(SIMD3<Float>(cx + rx * half, vertexY, cz + rz * half))
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

    /// A vertical strip that follows the route samples: backdrops,
    /// forest lines and the coastal bluff. The old backdrop was a
    /// straight 4 km box on the global -z axis, but the route wanders
    /// up to 31 km off that axis (plan view), so beyond the first
    /// kilometres the horizon was empty and the straight walls sliced
    /// through the line wherever the route crossed x = +/-680 m.
    /// A curve-following strip stays beside the track everywhere.
    /// `lateralOffsets`, `bottomYs` and `topYs` are per-sample
    /// absolute values; the UV runs along the chainage (one texture
    /// repeat per `tileLength` metres) and once over the height.
    /// The caller clamps the lateral offset inside tight curves
    /// (see `backdropLateral`), because a strip offset further than
    /// the curve radius would fold back through the track.
    private func verticalRibbonEntity(name: String, lateralOffsets: [Float], bottomYs: [Float], topYs: [Float], tileLength: Float, material: PhysicallyBasedMaterial, range: Range<Int>? = nil) -> ModelEntity? {
        guard lateralOffsets.count == samples.count, bottomYs.count == samples.count, topYs.count == samples.count, samples.count > 1 else { return nil }
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
            let lateral = lateralOffsets[i]
            let cx = sample.x + lateral * cos(sample.heading)
            let cz = sample.z + lateral * sin(sample.heading)
            // Face the track: the normal points from the wall back
            // toward the centreline. Face culling is off, so the far
            // side still renders; the normal only sets the lighting.
            let sideSign: Float = lateral < 0 ? -1 : 1
            let inward = SIMD3<Float>(-sideSign * cos(sample.heading), 0, -sideSign * sin(sample.heading))
            positions.append(SIMD3<Float>(cx, bottomYs[i], cz))
            positions.append(SIMD3<Float>(cx, topYs[i], cz))
            normals.append(inward)
            normals.append(inward)
            let u = Float(sample.distanceM) / tileLength
            uvs.append(SIMD2<Float>(u, 0))
            uvs.append(SIMD2<Float>(u, 1))
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

    /// Lateral offset of a route-following wall at one sample: the
    /// requested standoff, pulled in where the curve is tighter than
    /// the standoff so the wall never folds through the track.
    /// `route.condition(at:)` returns the effective radius with the
    /// transition fraction already applied, so this is continuous
    /// through the transitions.
    private func clampedWallLateral(side: Float, standoff: Float, route: RailwayRouteProfile, sample: RouteSample) -> Float {
        guard let radius = route.condition(at: sample.distanceM).curveRadiusM, radius.isFinite, radius > 0 else { return side * standoff }
        return side * min(standoff, Float(radius) * 0.9)
    }

    /// Per-sample (centre, width) for a wide horizontal ribbon, so
    /// the strip never folds through the track on a tight curve.
    /// The ribbon nominally spans [centre-half, centre+half]
    /// laterally, with + on the vehicle's right (the true
    /// perpendicular, see `ribbonEntity`). On the inner side of a
    /// curve the far edge is pulled in to 0.9R while the near edge
    /// stays put, so the strip still meets the apron and the track
    /// instead of leaving a gap. On the outer side, and on
    /// tangents, the nominal span is kept. A ribbon whose centre is
    /// already past 0.9R (far ground at R300: centre 375 m) is
    /// re-centred rather than just narrowed, so it still covers
    /// the ground out to the backdrop wall. The effective radius
    /// already carries the transition fraction (see
    /// `RailwayRouteProfile.condition(at:)`), so the clamp eases
    /// in and out continuously through the transitions.
    private func clampedRibbonSpan(route: RailwayRouteProfile, centerOffset: Float, width: Float) -> (centers: [Float], widths: [Float]) {
        let half = width / 2
        var centers: [Float] = []
        var widths: [Float] = []
        centers.reserveCapacity(samples.count)
        widths.reserveCapacity(samples.count)
        for sample in samples {
            var center = centerOffset
            var halfWidth = half
            let condition = route.condition(at: sample.distanceM)
            if let radius = condition.curveRadiusM, radius.isFinite, radius > 0,
               let direction = condition.curveDirection {
                let s = Float(direction)
                let limit = Float(radius) * 0.9
                let lo = center - halfWidth
                let hi = center + halfWidth
                if s > 0 && hi > limit {
                    if limit <= lo {
                        center = lo + 0.5
                        halfWidth = 0.5
                    } else {
                        center = (lo + limit) / 2
                        halfWidth = (limit - lo) / 2
                    }
                } else if s < 0 && lo < -limit {
                    if -limit >= hi {
                        center = hi - 0.5
                        halfWidth = 0.5
                    } else {
                        center = (-limit + hi) / 2
                        halfWidth = (hi + limit) / 2
                    }
                }
            }
            centers.append(center)
            widths.append(halfWidth * 2)
        }
        return (centers, widths)
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
    /// Track height above the route origin datum (see
    /// RegionalRouteGeometrySampler). Every route-following surface
    /// and object adds this to its base height; the sea is the one
    /// exception and stays flat at a per-run datum instead.
    let elevationM: Float
}
    private var currentSample = RouteSample(distanceM: 0, x: 0, z: 0, heading: 0, bankRadians: 0, elevationM: 0)
    private var generatedLeadVehicleRoot: Entity?
