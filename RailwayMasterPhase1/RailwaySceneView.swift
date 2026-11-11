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
        // quality41: the scene's own top-trailing "next stop"
        // capsule is gone — the header already shows the next
        // stop, and the capsule landed on top of the header's
        // weather / load / pause controls in every screenshot.
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
        RailwaySceneWorld.texturedPBR(.white, roughness: 0.92, textureName: "scenery_apartment_facade_3", normalName: "normal_apartment_facade"),
        RailwaySceneWorld.texturedPBR(.white, roughness: 0.92, textureName: "scenery_apartment_facade_4", normalName: "normal_apartment_facade"),
        RailwaySceneWorld.texturedPBR(.white, roughness: 0.8, textureName: "scenery_office_facade"),
        RailwaySceneWorld.texturedPBR(.white, roughness: 0.95, textureName: "scenery_danchi_facade"),
        RailwaySceneWorld.texturedPBR(UIColor(red: 0.94, green: 0.90, blue: 0.84, alpha: 1), roughness: 0.9, textureName: "scenery_house_facade"),
        // quality32: tint variants of the same facades. Adjacent
        // towers used to cycle only three textures at one tone, so
        // the same building visibly repeated down the street;
        // per-tone variation breaks the repetition without new
        // assets.
        RailwaySceneWorld.texturedPBR(UIColor(red: 0.80, green: 0.79, blue: 0.77, alpha: 1), roughness: 0.68, textureName: "scenery_office_facade", normalName: "normal_office_facade"),
        RailwaySceneWorld.texturedPBR(UIColor(red: 0.84, green: 0.80, blue: 0.74, alpha: 1), roughness: 0.94, textureName: "scenery_apartment_facade", normalName: "normal_apartment_facade"),
        RailwaySceneWorld.texturedPBR(UIColor(red: 0.78, green: 0.83, blue: 0.90, alpha: 1), metallic: 0.06, roughness: 0.58, textureName: "scenery_glass_facade", normalName: "normal_glass_facade"),
        RailwaySceneWorld.texturedPBR(UIColor(red: 0.86, green: 0.84, blue: 0.80, alpha: 1), roughness: 0.9, textureName: "scenery_brick_warm"),
        // quality41 final (photoreal pass): weathered skins in the
        // shared pool so a share of towers and blocks line-wide
        // carry streaks and grime instead of the clean CG look.
        RailwaySceneWorld.texturedPBR(.white, roughness: 0.7, textureName: "scenery_office_facade_grimed", normalName: "normal_office_facade"),
        RailwaySceneWorld.texturedPBR(.white, roughness: 0.95, textureName: "scenery_apartment_facade_grimed", normalName: "normal_apartment_facade"),
        RailwaySceneWorld.texturedPBR(.white, roughness: 0.95, textureName: "scenery_danchi_facade_grimed")
    ]
    private let foliageMaterials = [
        RailwaySceneWorld.texturedPBR(UIColor(red: 0.75, green: 0.90, blue: 0.75, alpha: 1), roughness: 0.98, textureName: "scenery_foliage"),
        RailwaySceneWorld.texturedPBR(UIColor(red: 0.90, green: 1.0, blue: 0.85, alpha: 1), roughness: 0.98, textureName: "scenery_foliage"),
        RailwaySceneWorld.texturedPBR(UIColor(red: 0.80, green: 0.95, blue: 0.88, alpha: 1), roughness: 0.98, textureName: "scenery_foliage")
    ]
    /// Full-facade photo texture for suburban houses (windows and door are
    /// painted in, so those houses skip the separate window/door boxes).
    private let houseFacadeMaterial = RailwaySceneWorld.texturedPBR(.white, roughness: 0.92, textureName: "scenery_house_facade")
    /// quality40: two more house facades, flattened from the
    /// user's own reference renders of a modern house (wood over
    /// concrete side; lattice-door entrance front).
    private let houseFacadeMaterial2 = RailwaySceneWorld.texturedPBR(.white, roughness: 0.92, textureName: "scenery_house_facade_2")
    private let houseFacadeMaterial3 = RailwaySceneWorld.texturedPBR(.white, roughness: 0.92, textureName: "scenery_house_facade_3")
    /// quality40: station-front cafe facade, flattened from the
    /// user's reference render (the sign reads カフェ・木漏れ日).
    private let cafeFacadeMaterial = RailwaySceneWorld.texturedPBR(.white, roughness: 0.9, textureName: "scenery_cafe_facade")
    /// quality41: Ema-generated photoreal facades (straight-on
    /// photographic elevations made in-house, so the paid release
    /// stays license-clean): a modern house, a traditional wooden
    /// house, and a small station-front shop.
    private let houseFacadeMaterial4 = RailwaySceneWorld.texturedPBR(.white, roughness: 0.92, textureName: "scenery_house_facade_4")
    private let houseFacadeMaterial5 = RailwaySceneWorld.texturedPBR(.white, roughness: 0.92, textureName: "scenery_house_facade_5")
    private let shopFacadeMaterial = RailwaySceneWorld.texturedPBR(.white, roughness: 0.9, textureName: "scenery_shop_facade")
    /// quality41: photoreal storefronts for the procedural
    /// convenience store and supermarket (generated elevations:
    /// glass front with the interior showing, stripe band, blank
    /// signboards — no real brands, safe for the paid release).
    private let konbiniFacadeMaterial = RailwaySceneWorld.texturedPBR(.white, roughness: 0.85, textureName: "scenery_konbini_facade")
    private let supermarketFacadeMaterial = RailwaySceneWorld.texturedPBR(.white, roughness: 0.85, textureName: "scenery_supermarket_facade")
    /// quality41 final: public buildings — school and hospital
    /// facades (generated elevations, license-clean like the rest).
    private let schoolFacadeMaterial = RailwaySceneWorld.texturedPBR(.white, roughness: 0.9, textureName: "scenery_school_facade")
    private let hospitalFacadeMaterial = RailwaySceneWorld.texturedPBR(.white, roughness: 0.85, textureName: "scenery_hospital_facade")
    /// quality41 final (photoreal pass): weathered variants of the
    /// main facades — rain streaks, a dark splash zone at the base,
    /// mottling and a slight desaturation, derived in-house from
    /// the clean facades. The user's core complaint was that every
    /// surface reads too clean and CG-like; these join the shared
    /// pools, so the weathering applies along the whole line, not
    /// just in the showcase section.
    private let houseFacadeMaterialGrimed = RailwaySceneWorld.texturedPBR(.white, roughness: 0.95, textureName: "scenery_house_facade_grimed")
    /// quality41 (mega-batch): more Ema-generated elevations —
    /// two apartment variants, a danchi slab, an office curtain
    /// wall, and a drink vending machine front.
    private let photoApartmentMaterial = RailwaySceneWorld.texturedPBR(.white, roughness: 0.92, textureName: "scenery_apartment_facade_3")
    private let photoApartmentMaterial2 = RailwaySceneWorld.texturedPBR(.white, roughness: 0.92, textureName: "scenery_apartment_facade_4")
    private let danchiFacadeMaterial = RailwaySceneWorld.texturedPBR(.white, roughness: 0.95, textureName: "scenery_danchi_facade")
    private let officePhotoFacadeMaterial = RailwaySceneWorld.texturedPBR(.white, roughness: 0.8, textureName: "scenery_office_facade")
    private let vendingFacadeMaterial = RailwaySceneWorld.texturedPBR(.white, roughness: 0.55, textureName: "scenery_vending_facade")
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
    // quality41 expansion: articulated zoo animals on the zoo line.
    // Each rig is a small hierarchy of part entities (body, head,
    // legs, tail) posed every frame by a per-animal behaviour state
    // machine in updateZooAnimals.
    private struct ZooAnimalRig {
        var root: Entity
        var body: Entity
        var headPivot: Entity
        var neckPivot: Entity?
        var trunkPivots: [Entity]
        var legs: [Entity]
        var tailPivot: Entity
        var species: Int // 0 lion, 1 tiger, 2 giraffe, 3 elephant, 4 zebra, 5 penguin
        var routeDistanceM: Double
        var paddockCenter: SIMD3<Float>
        var axisX: SIMD3<Float>
        var axisZ: SIMD3<Float>
        var heading: Float
        var state: Int = 0 // 0 idle, 1 graze, 2 walk, 3 rest
        var stateUntil: Double = 0
        var walkTarget: SIMD3<Float>
        var phase: Float = 0
        var rngState: UInt64
        var bodyStandY: Float
        var bodyRestY: Float
        var grazeAmount: Float = 0
        var restAmount: Float = 0
    }
    private var zooAnimalRigs: [ZooAnimalRig] = []
    private var zooLastAnimTime: Double = 0
    // quality41 final: people. Static/animated figures placed by the
    // world builders (platforms, crossings, zoo and park), separate
    // from the traffic simulation's platform passengers, whose crude
    // two-box dummy is upgraded to the same figure builder below.
    private struct PersonRig {
        var root: Entity
        var legL: Entity
        var legR: Entity
        var armL: Entity
        var armR: Entity
        var mode: Int // 0 stand, 1 walk
        var routeDistanceM: Double
        var home: SIMD3<Float>
        var walkAxis: SIMD3<Float>
        var range: Float
        var offset: Float = 0
        var dirSign: Float = 1
        var speed: Float
        var phase: Float
        var armBaseR: Float = 0
    }
    private var personRigs: [PersonRig] = []
    private var peopleLastTime: Double = 0
    private var pantographSpark: ModelEntity?
    private var platformPeopleLegs: [String: (Entity, Entity)] = [:]
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
        platformPeopleLegs.removeAll()
        personRigs.removeAll()
        zooAnimalRigs.removeAll()
        pantographSpark = nil
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
            buildCableTrough(route: route, travelDirection: travelDirection)
            buildCatenary(route: route, routeVariant: routeVariant, travelDirection: travelDirection, showcaseSection: travelDirection == .up && (routeVariant == .mainline || routeVariant == .throughBranch))
            if routeVariant != .zooLine && routeVariant != .parkLine {
                buildSuburb(route: route, routeVariant: routeVariant, travelDirection: travelDirection)
                buildPublicBuildings(route: route, routeVariant: routeVariant)
                buildRuralDressing(route: route, routeVariant: routeVariant, travelDirection: travelDirection)
                buildTreeLinesAndHills(route: route, routeVariant: routeVariant, travelDirection: travelDirection)
                buildStationCharacter(route: route, routeVariant: routeVariant, travelDirection: travelDirection)
                buildSpeedSigns(route: route, routeVariant: routeVariant, travelDirection: travelDirection)
                buildSignCatalog(route: route, routeVariant: routeVariant, travelDirection: travelDirection)
            }
            buildUtilityPoles(route: route, routeVariant: routeVariant, travelDirection: travelDirection)
            if routeVariant != .zooLine && routeVariant != .parkLine {
                buildRoadTraffic(route: route, scenario: trafficScenario, routeVariant: routeVariant, travelDirection: travelDirection)
                buildFictionalCorridorLandmarks(route: route, quality: quality)
            }
            buildDepotYard(travelDirection: travelDirection)
            buildZooAndPark(routeVariant: routeVariant, travelDirection: travelDirection)
            buildZooLineWorld(routeVariant: routeVariant, travelDirection: travelDirection)
            buildParkLineWorld(routeVariant: routeVariant, travelDirection: travelDirection)
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
        buildTouristTerminus(route: route, routeVariant: routeVariant, travelDirection: travelDirection)
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
        if routeVariant == .zooLine {
            updateZooAnimals(trainPositionM: positionM, time: simulationTime)
        }
        updatePeople(trainPositionM: positionM, time: simulationTime)
        updatePantographSpark(speedKmh: speedKmh, time: simulationTime, inTunnel: route.condition(at: positionM).tunnelResistanceMultiplier > 1.01)
        updateGeneratedStationModel(positionM: positionM)
        let centerSample = sample(at: positionM)
        // Passing wait (2026-11-11): when the traffic snapshot
        // reports the player on a siding track, the consist and
        // the camera follow the fan profile out to the loop line
        // (9.64 m) and back — each car by its own chainage, the
        // way a real train threads the crossover.
        let playerOnSiding = trafficSnapshot?.playerTrain?.trackID.hasSuffix("-siding") ?? false
        func playerTrackLateral(at chainage: Double) -> Float {
            let base: Float = travelDirection == .up ? -2.1 : 2.1
            guard playerOnSiding else { return base }
            let side: Float = base < 0 ? -1 : 1
            for spec in throatFanSpecs() where abs(chainage - spec.center) <= spec.half + 340 {
                if chainage < spec.center - spec.half {
                    return side * throatFanLateral(u: (chainage - (spec.center - spec.half - 340)) / 340, tag: "in")
                }
                if chainage > spec.center + spec.half {
                    return side * throatFanLateral(u: (chainage - (spec.center + spec.half)) / 340, tag: "out")
                }
                return side * Float(9.64)
            }
            return base
        }
        let playerLateral: Float = playerTrackLateral(at: positionM)
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
            let trackSide: Float = playerTrackLateral(at: chainage)
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
            let trackSide: Float = playerTrackLateral(at: carChainage)
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
        guard routeVariant == .mainline || routeVariant == .throughBranch || routeVariant == .zooLine || routeVariant == .parkLine else { return }
        let headMaterial = Self.pbr(UIColor(red: 0.05, green: 0.05, blue: 0.06, alpha: 1), metallic: 0.3, roughness: 0.6)
        let plateMaterial = Self.pbr(.white, roughness: 0.6)
        // quality41: beige relay/equipment boxes cluster beside
        // real signals (survey cat05: 2-5 cabinets in the 3.5-4.5 m
        // band); until now the signals stood alone in empty grass.
        let relayMaterial = Self.pbr(UIColor(red: 0.76, green: 0.72, blue: 0.62, alpha: 1), metallic: 0.05, roughness: 0.8)
        var targets: [Double] = stride(from: 0.0, to: (routeVariant == .zooLine || routeVariant == .parkLine) ? route.distanceM : 60_000.0, by: 1_500.0).map { $0 }
        // quality41 final: signal roles — the 1,500 m grid signals
        // are block signals （閉そく）, the station-approach signals
        // are home signals （場内）, and every station also gets a
        // departure signal （出発） just past its far end; until now
        // stations had no departure signals at all. The role of each
        // built signal is kept in its entity name.
        var approachPoints: [Double] = []
        var departurePoints: [Double] = []
        for placement in stationModelPlacements {
            let center = chainageFromCenter(distanceM: placement.chainageM, route: route, travelDirection: travelDirection)
            guard center > 600, center < 59_400 else { continue }
            let approach = center + (travelDirection == .up ? -400 : 400)
            targets.append(approach)
            approachPoints.append(approach)
            let departure = center + (travelDirection == .up ? 170 : -170)
            if departure > 600, departure < 59_400 {
                targets.append(departure)
                departurePoints.append(departure)
            }
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
        if routeVariant != .zooLine && routeVariant != .parkLine {
            dedupedTargets = dedupedTargets.map { target in
                for span in fanSpansCenter where target > span.start && target < span.end {
                    return target - span.start < span.end - target ? span.start - 12 : span.end + 12
                }
                return target
            }
        }
        for target in dedupedTargets {
            var best: RouteSample?
            var bestDelta = Double.greatestFiniteMagnitude
            for sample in samples where routeVariant == .zooLine || routeVariant == .parkLine || isMainlineSection(distanceM: sample.distanceM, routeVariant: routeVariant, travelDirection: travelDirection) {
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
            // quality41: the post now stands at the unified spec's
            // 1,900 mm from its track's centre (2.1 + 1.9 = 4.0);
            // on a viaduct the deck edge gives the 2,000 mm
            // variant (4.08), as before.
            let lateral = sideSign * (lift >= 2 ? Float(4.08) : Float(4.0))
            let base = routeOffsetPoint(sample, lateral: lateral)
            let footY = base.y - (lift >= 2 ? Float(0.49) : Float(0.10))
            let postTop = base.y + 5.62
            let forward = SIMD3<Float>(sin(sample.heading), 0, -cos(sample.heading))
            let signalRole = approachPoints.contains(where: { abs($0 - target) < 60 }) ? "home" : (departurePoints.contains(where: { abs($0 - target) < 60 }) ? "departure" : "block")
            addBox(parent: world, name: "signal-\(signalRole)-\(Int(target))", size: SIMD3<Float>(0.16, postTop - footY, 0.16),
                   position: SIMD3<Float>(base.x, (footY + postTop) / 2, base.z), material: poleMaterial, orientation: yaw)
            // quality41: the head is now the TOO RAILWAY standard
            // 4-aspect A unit at catalogue size (maker data in
            // cat13: housing W580 x D169 mm, H 1,240 mm for four
            // aspects, phi150 lenses at 300 mm pitch, lowest lens
            // at least 4,200 mm above the rail head). Lamp order
            // top to bottom is yellow, red, yellow, green; the
            // aspects are proceed (G), caution (single Y), warning
            // (double Y) and stop (R). The model still supplies
            // three aspects, so the warning pair lights only when
            // the model grows it — the hardware is ready.
            addBox(parent: world, name: "signal-backboard-\(Int(target))", size: SIMD3<Float>(0.74, 1.42, 0.04),
                   position: SIMD3<Float>(base.x + forward.x * 0.10, base.y + 4.9, base.z + forward.z * 0.10), material: headMaterial, orientation: yaw)
            addBox(parent: world, name: "signal-head-\(Int(target))", size: SIMD3<Float>(0.58, 1.24, 0.17),
                   position: SIMD3<Float>(base.x, base.y + 4.9, base.z), material: headMaterial, orientation: yaw)
            addBox(parent: world, name: "signal-ladder-\(Int(target))", size: SIMD3<Float>(0.3, postTop - footY - 0.4, 0.04),
                   position: SIMD3<Float>(base.x + forward.x * 0.15, (footY + postTop) / 2, base.z + forward.z * 0.15), material: headMaterial, orientation: yaw)
            // Inspection platform 0.7 m below the lowest lens.
            addBox(parent: world, name: "signal-platform-\(Int(target))", size: SIMD3<Float>(0.72, 0.05, 0.55),
                   position: SIMD3<Float>(base.x + forward.x * 0.18, base.y + 3.75, base.z + forward.z * 0.18), material: headMaterial, orientation: yaw)
            addBox(parent: world, name: "signal-plate-\(Int(target))", size: SIMD3<Float>(0.22, 0.3, 0.02),
                   position: SIMD3<Float>(base.x - forward.x * 0.1, base.y + 2.55, base.z - forward.z * 0.1), material: plateMaterial, orientation: yaw)
            // Lamps sit on the face turned toward the approaching
            // train (opposite the direction of travel).
            let lampX = base.x - forward.x * 0.13
            let lampZ = base.z - forward.z * 0.13
            var lamps: [ModelEntity] = []
            for lampY in [5.35, 5.05, 4.75, 4.45] {
                addBox(parent: world, name: "signal-hood-\(Int(target))-\(lampY)", size: SIMD3<Float>(0.21, 0.05, 0.24),
                       position: SIMD3<Float>(lampX, base.y + Float(lampY) + 0.11, lampZ), material: headMaterial, orientation: yaw)
                let lamp = ModelEntity(mesh: MeshResource.generateSphere(radius: 0.075),
                                       materials: [signalDarkLampMaterial])
                lamp.scale = SIMD3<Float>(1, 1, 0.45)
                lamp.position = SIMD3<Float>(lampX, base.y + Float(lampY), lampZ)
                lamp.orientation = yaw
                world.addChild(lamp)
                lamps.append(lamp)
            }
            signalLampHeads[sample.distanceM] = lamps
            applyAspect(lamps, aspect: .green)
            // Relay cabinets behind the post, a little further out.
            let relayCount = 2 + Int(abs(target)) % 3
            for relayIndex in 0..<relayCount {
                let relayLateral = lateral + sideSign * 0.85
                let relayBase = routeOffsetPoint(sample, lateral: relayLateral)
                let back = Float(relayIndex) * 1.05 + 0.6
                let rx = relayBase.x - forward.x * back
                let rz = relayBase.z - forward.z * back
                addBox(parent: world, name: "signal-relay-\(Int(target))-\(relayIndex)", size: SIMD3<Float>(0.42, 1.15, 0.85),
                       position: SIMD3<Float>(rx, footY + 0.575, rz), material: relayMaterial, orientation: yaw)
            }
            // quality41: the TO-ATS-P transponder coils between
            // the rails of the served track, at the spec mounting
            // (track centre, top 70 mm below the rail head): two
            // dark slabs 25 m and 5 m in rear of the signal.
            let coilMaterial = Self.pbr(UIColor(red: 0.16, green: 0.16, blue: 0.17, alpha: 1), roughness: 0.8)
            for back in [25.0, 5.0] {
                let coilSample = self.sample(at: max(target - back, 0))
                let coilPoint = routeOffsetPoint(coilSample, lateral: sideSign * 2.1)
                let coilYaw = simd_quatf(angle: -coilSample.heading, axis: SIMD3<Float>(0, 1, 0))
                addBox(parent: world, name: "ats-coil-\(Int(target))-\(Int(back))", size: SIMD3<Float>(0.5, 0.07, 0.34),
                       position: SIMD3<Float>(coilPoint.x, coilPoint.y + 0.20, coilPoint.z), material: coilMaterial, orientation: coilYaw)
            }
        }
    }

    /// quality41: the lineside furniture ChatGPT's review and
    /// the photoreal research both rank first: a continuous cable
    /// trough along the cess and kilometre posts. The trough runs
    /// at route lateral -3.35 (the up side), stepping over every
    /// 8.5 m sample; it breaks at stations, fans, crossings and
    /// the tunnel, the way the real trough route diverts around
    /// them. Kilometre posts stand on the opposite side every
    /// 500 m.
    private func buildCableTrough(route: RailwayRouteProfile, travelDirection: RegionalTravelDirection) {
        var troughBatch = MeshBatchBuilder()
        var postBatch = MeshBatchBuilder()
        let troughMaterial = Self.pbr(UIColor(red: 0.62, green: 0.61, blue: 0.57, alpha: 1), roughness: 0.95)
        let postMaterial = Self.pbr(UIColor(red: 0.88, green: 0.88, blue: 0.85, alpha: 1), roughness: 0.8)
        guard let first = samples.first, let last = samples.last else { return }
        var d = first.distanceM
        while d <= last.distanceM {
            let s = sample(at: d)
            let centerChainage = chainageFromCenter(distanceM: d, route: route, travelDirection: travelDirection)
            let blocked = inStationZone(d, extraMargin: 6) || nearThroatFan(d) || nearCrossing(d, margin: 14)
                || (centerChainage > 41_400 && centerChainage < 44_400)
            if !blocked {
                let lift = s.elevationM - groundLevelM(at: s)
                let footY = s.elevationM - (lift >= 2 ? Float(0.45) : Float(0.52))
                let p = routeOffsetPoint(s, lateral: -3.35)
                troughBatch.addBox(center: SIMD3<Float>(p.x, footY + 0.13, p.z), size: SIMD3<Float>(0.5, 0.26, 8.7), yaw: -s.heading)
            }
            d += 8.5
        }
        var postD = (first.distanceM / 500).rounded(.down) * 500 + 500
        while postD < last.distanceM {
            if !inStationZone(postD, extraMargin: 6) {
                let s = sample(at: postD)
                let p = routeOffsetPoint(s, lateral: 3.35)
                let lift = s.elevationM - groundLevelM(at: s)
                let footY = s.elevationM - (lift >= 2 ? Float(0.49) : Float(0.55))
                postBatch.addBox(center: SIMD3<Float>(p.x, footY + 0.42, p.z), size: SIMD3<Float>(0.13, 0.85, 0.13), yaw: -s.heading)
                postBatch.addBox(center: SIMD3<Float>(p.x, footY + 0.80, p.z), size: SIMD3<Float>(0.30, 0.22, 0.04), yaw: -s.heading)
            }
            postD += 500
        }
        if let mesh = troughBatch.build(name: "cable-trough", material: troughMaterial) { world.addChild(mesh) }
        if let mesh = postBatch.build(name: "kilometre-posts", material: postMaterial) { world.addChild(mesh) }
    }

    /// quality41: the TOO RAILWAY depot yard beside the main
    /// line at 27,580-27,820 (inland side): inspection shed with
    /// three tall doors (the middle one open onto a lit
    /// interior), two yard tracks with buffer stops, an office,
    /// stored materials, yard lights and a chain-link perimeter.
    /// ChatGPT's depot review ranked exactly these: shed doors,
    /// yard tracks, clutter along the work paths, fence, lights.
    private func buildDepotYard(travelDirection: RegionalTravelDirection) {
        guard let first = samples.first, let last = samples.last, first.distanceM <= 27_560, last.distanceM >= 27_840 else { return }
        let sideSign: Float = -seaSideSign(travelDirection: travelDirection)
        func pt(_ d: Double, _ lateral: Float) -> SIMD3<Float> { self.groundOffsetPoint(self.sample(at: d), lateral: lateral) }
        func yawAt(_ d: Double) -> simd_quatf { simd_quatf(angle: -self.sample(at: d).heading, axis: SIMD3<Float>(0, 1, 0)) }
        let shedMaterial = Self.pbr(UIColor(red: 0.76, green: 0.77, blue: 0.76, alpha: 1), metallic: 0.18, roughness: 0.62)
        let doorMaterial = Self.pbr(UIColor(red: 0.23, green: 0.25, blue: 0.27, alpha: 1), metallic: 0.4, roughness: 0.55)
        let litMaterial = Self.pbr(UIColor(red: 0.98, green: 0.84, blue: 0.55, alpha: 1), roughness: 1)
        let bedMaterial = Self.texturedPBR(.white, roughness: 1, textureName: "scenery_trackbed", normalName: "normal_trackbed")
        let railMaterial = Self.pbr(UIColor(red: 0.52, green: 0.57, blue: 0.60, alpha: 1), metallic: 0.85, roughness: 0.36)
        var fenceMaterial = Self.texturedPBR(.white, metallic: 0.55, roughness: 0.45, textureName: "scenery_fence_chainlink")
        fenceMaterial.blending = .transparent(opacity: .init(floatLiteral: 1))
        fenceMaterial.faceCulling = .none
        // Ground pad.
        var padD = 27_580.0
        while padD <= 27_820 {
            let p = pt(padD, sideSign * 29)
            _ = addBox(parent: world, name: "depot-pad-\(Int(padD))", size: SIMD3<Float>(34, 0.1, 17.6), position: SIMD3<Float>(p.x, p.y + 0.05, p.z), material: roadMaterial, orientation: yawAt(padD))
            padD += 17
        }
        // Inspection shed and its doors.
        let shed = pt(27_700, sideSign * 34)
        let shedYaw = yawAt(27_700)
        _ = addBox(parent: world, name: "depot-shed", size: SIMD3<Float>(21, 9, 66), position: SIMD3<Float>(shed.x, shed.y + 4.5, shed.z), material: shedMaterial, orientation: shedYaw)
        _ = addBox(parent: world, name: "depot-shed-roof", size: SIMD3<Float>(22, 0.35, 67), position: SIMD3<Float>(shed.x, shed.y + 9.15, shed.z), material: roofMaterials[1], orientation: shedYaw)
        _ = addBox(parent: world, name: "depot-shed-clerestory", size: SIMD3<Float>(21.15, 1.1, 58), position: SIMD3<Float>(shed.x, shed.y + 7.5, shed.z), material: glassMaterial, orientation: shedYaw)
        for doorIndex in 0..<3 {
            let doorD = 27_700 + Double(doorIndex - 1) * 21
            let doorP = pt(doorD, sideSign * 23.35)
            if doorIndex == 1 {
                _ = addBox(parent: world, name: "depot-door-open", size: SIMD3<Float>(0.3, 5.8, 5.0), position: SIMD3<Float>(doorP.x, shed.y + 2.9, doorP.z), material: litMaterial, orientation: yawAt(doorD))
            } else {
                _ = addBox(parent: world, name: "depot-door-\(doorIndex)", size: SIMD3<Float>(0.22, 5.6, 4.8), position: SIMD3<Float>(doorP.x, shed.y + 2.8, doorP.z), material: doorMaterial, orientation: yawAt(doorD))
            }
        }
        // Two yard tracks with buffer stops.
        for trackLateral in [sideSign * 19.5, sideSign * 24.5] {
            var td = 27_605.0
            while td <= 27_795 {
                let bp = pt(td, trackLateral)
                _ = addBox(parent: world, name: "depot-bed-\(Int(trackLateral))-\(Int(td))", size: SIMD3<Float>(4.6, 0.16, 17.4), position: SIMD3<Float>(bp.x, bp.y + 0.10, bp.z), material: bedMaterial, orientation: yawAt(td))
                for railOff in [Float(-0.72), Float(0.72)] {
                    let rp = pt(td, trackLateral + railOff)
                    _ = addBox(parent: world, name: "depot-rail-\(Int(trackLateral))-\(Int(td))-\(railOff)", size: SIMD3<Float>(0.09, 0.13, 17.4), position: SIMD3<Float>(rp.x, rp.y + 0.245, rp.z), material: railMaterial, orientation: yawAt(td))
                }
                td += 17
            }
            let bufP = pt(27_800, trackLateral)
            _ = addBox(parent: world, name: "depot-buffer-\(Int(trackLateral))", size: SIMD3<Float>(2.2, 0.4, 0.3), position: SIMD3<Float>(bufP.x, bufP.y + 0.85, bufP.z), material: poleMaterial, orientation: yawAt(27_800))
        }
        // Office, clutter, lights, fence.
        let office = pt(27_635, sideSign * 43)
        _ = addBox(parent: world, name: "depot-office", size: SIMD3<Float>(13, 7, 11), position: SIMD3<Float>(office.x, office.y + 3.5, office.z), material: officePhotoFacadeMaterial, orientation: yawAt(27_635))
        _ = addBox(parent: world, name: "depot-office-roof", size: SIMD3<Float>(13.5, 0.3, 11.5), position: SIMD3<Float>(office.x, office.y + 7.15, office.z), material: roofMaterials[0], orientation: yawAt(27_635))
        let stackP = pt(27_660, sideSign * 26.5)
        for railLevel in 0..<3 {
            _ = addBox(parent: world, name: "depot-railstack-\(railLevel)", size: SIMD3<Float>(0.16, 0.16, 12), position: SIMD3<Float>(stackP.x, stackP.y + 0.25 + Float(railLevel) * 0.17, stackP.z), material: railMaterial, orientation: yawAt(27_660))
        }
        let drumP = pt(27_748, sideSign * 26)
        _ = addBox(parent: world, name: "depot-drum-a", size: SIMD3<Float>(1.3, 1.3, 1.3), position: SIMD3<Float>(drumP.x, drumP.y + 0.65, drumP.z), material: roofMaterials[1], orientation: yawAt(27_748))
        let drum2P = pt(27_751.5, sideSign * 26)
        _ = addBox(parent: world, name: "depot-drum-b", size: SIMD3<Float>(1.3, 1.3, 1.3), position: SIMD3<Float>(drum2P.x, drum2P.y + 0.65, drum2P.z), material: doorMaterial, orientation: yawAt(27_748))
        let cartP = pt(27_720, sideSign * 27.5)
        _ = addBox(parent: world, name: "depot-cart", size: SIMD3<Float>(1.8, 0.85, 3.1), position: SIMD3<Float>(cartP.x, cartP.y + 0.62, cartP.z), material: doorMaterial, orientation: yawAt(27_720))
        for lightD in [27_630.0, 27_710.0, 27_790.0] {
            let lp = pt(lightD, sideSign * 15.5)
            _ = addBox(parent: world, name: "depot-light-\(Int(lightD))", size: SIMD3<Float>(0.13, 6.8, 0.13), position: SIMD3<Float>(lp.x, lp.y + 3.4, lp.z), material: poleMaterial)
            _ = addBox(parent: world, name: "depot-light-head-\(Int(lightD))", size: SIMD3<Float>(0.95, 0.14, 0.32), position: SIMD3<Float>(lp.x, lp.y + 6.85, lp.z), material: litMaterial, orientation: yawAt(lightD))
        }
        var fenceD = 27_578.0
        while fenceD <= 27_822 {
            let fp = pt(fenceD, sideSign * 12.6)
            _ = addBox(parent: world, name: "depot-fence-\(Int(fenceD))", size: SIMD3<Float>(0.05, 1.9, 17.2), position: SIMD3<Float>(fp.x, fp.y + 0.95, fp.z), material: fenceMaterial, orientation: yawAt(fenceD))
            fenceD += 17
        }
    }

    /// quality41: one scenic branch line laid over the main
    /// line's samples, leaving the running track like a turnout
    /// (offset grows with a smoothstep) and then running
    /// parallel at `reachM`. Formation, trackbed, rails and an
    /// end buffer follow the divergence builder's recipe.
    /// Returns the branch's profile stations for theme scenery.
    private func buildScenicBranch(name: String, junctionM: Double, side: Float, lengthM: Double, reachM: Double, easeM: Double) -> [ProfileStation] {
        func offsetAt(_ t: Double) -> Float {
            let u = min(max(t / easeM, 0), 1)
            let s = u * u * (3 - 2 * u)
            return 2.1 + Float(reachM) * Float(s)
        }
        var stations: [ProfileStation] = []
        var t = 0.0
        while t <= lengthM {
            stations.append(profileStation(at: junctionM + t, trackLateral: side * offsetAt(t)))
            t += 8.5
        }
        let formationMaterial = Self.pbr(UIColor(red: 0.24, green: 0.28, blue: 0.24, alpha: 1), roughness: 1)
        let bedMaterial = Self.texturedPBR(.white, roughness: 1, textureName: "scenery_trackbed", normalName: "normal_trackbed")
        let railSteel = Self.pbr(UIColor(red: 0.52, green: 0.57, blue: 0.60, alpha: 1), metallic: 0.85, roughness: 0.36)
        let runningBand = Self.pbr(UIColor(red: 0.78, green: 0.82, blue: 0.85, alpha: 1), metallic: 0.95, roughness: 0.12)
        let railProfile: [(x: Float, y: Float)] = [
            (-0.075, 0.145), (0.075, 0.145), (0.075, 0.175), (0.018, 0.185),
            (0.018, 0.255), (0.037, 0.265), (0.037, 0.305), (-0.037, 0.305),
            (-0.037, 0.265), (-0.018, 0.255), (-0.018, 0.185), (-0.075, 0.175)
        ]
        let bandProfile: [(x: Float, y: Float)] = [(-0.026, 0.3065), (0.026, 0.3065)]
        if let formation = profileStripEntity(name: "\(name)-formation", stations: stations, profile: [(-6.5, -0.06), (6.5, -0.06)], closed: false, material: formationMaterial) { world.addChild(formation) }
        // Embankment skirts so the branch never floats where the
        // main line climbs: two grass slopes from the shoulders
        // down 2.4 m.
        let skirtMaterial = Self.texturedPBR(.white, roughness: 1, textureName: "scenery_grass")
        if let skirtL = profileStripEntity(name: "\(name)-skirt-l", stations: stations, profile: [(-6.5, -2.4), (-2.3, 0.10)], closed: false, material: skirtMaterial) { world.addChild(skirtL) }
        if let skirtR = profileStripEntity(name: "\(name)-skirt-r", stations: stations, profile: [(2.3, 0.10), (6.5, -2.4)], closed: false, material: skirtMaterial) { world.addChild(skirtR) }
        if let bed = profileStripEntity(name: "\(name)-trackbed", stations: stations, profile: [(-2.3, 0.185), (2.3, 0.185)], closed: false, material: bedMaterial) { world.addChild(bed) }
        for railSide: Float in [-0.72, 0.72] {
            let profile = railProfile.map { (x: $0.x + railSide, y: $0.y) }
            if let rail = profileStripEntity(name: "\(name)-rail-\(railSide)", stations: stations, profile: profile, closed: false, material: railSteel) { world.addChild(rail) }
            let band = bandProfile.map { (x: $0.x + railSide, y: $0.y) }
            if let bandEntity = profileStripEntity(name: "\(name)-band-\(railSide)", stations: stations, profile: band, closed: false, material: runningBand) { world.addChild(bandEntity) }
        }
        if let lastStation = stations.last {
            let tangent = -simd_cross(lastStation.xAxis, lastStation.yAxis)
            var bufferBatch = MeshBatchBuilder()
            for postU: Float in [-0.85, 0.85] {
                bufferBatch.addBoxAxes(center: lastStation.center + postU * lastStation.xAxis + 0.55 * lastStation.yAxis,
                                       size: SIMD3<Float>(0.28, 1.1, 0.28), ax: lastStation.xAxis, ay: lastStation.yAxis, az: tangent)
            }
            bufferBatch.addBoxAxes(center: lastStation.center + lastStation.yAxis,
                                   size: SIMD3<Float>(2.4, 0.42, 0.3), ax: lastStation.xAxis, ay: lastStation.yAxis, az: tangent)
            if let buffers = bufferBatch.build(name: "\(name)-buffer", material: poleMaterial) { world.addChild(buffers) }
        }
        return stations
    }

    /// Rural dressing (night pass P1, 2026-11-11): the stretches
    /// between stations used to be bare ground with the odd house.
    /// Real rural private-railway scenery is a patchwork — paddy
    /// and crop fields right up to the fence line, plastic
    /// greenhouses, farmhouses with sheds, hedgerows along the
    /// field edges. Sites are seeded every ~210 m wherever the
    /// urban band is 0, away from stations and off the beach.
    private func buildRuralDressing(route: RailwayRouteProfile, routeVariant: RegionalRouteVariant, travelDirection: RegionalTravelDirection) {
        guard routeVariant == .mainline || routeVariant == .throughBranch else { return }
        let fieldMats = [
            Self.pbr(UIColor(red: 0.36, green: 0.52, blue: 0.30, alpha: 1), roughness: 1.0),   // paddy green
            Self.pbr(UIColor(red: 0.46, green: 0.60, blue: 0.28, alpha: 1), roughness: 1.0),   // young crop
            Self.pbr(UIColor(red: 0.42, green: 0.33, blue: 0.24, alpha: 1), roughness: 1.0),   // bare soil
            Self.pbr(UIColor(red: 0.72, green: 0.62, blue: 0.35, alpha: 1), roughness: 1.0),   // wheat / dry field
            Self.pbr(UIColor(red: 0.55, green: 0.65, blue: 0.60, alpha: 1), roughness: 0.3),   // flooded paddy sheen
        ]
        let hedgeMat = foliageMaterials[0]
        let greenhouseMat = Self.pbr(UIColor(red: 0.88, green: 0.92, blue: 0.90, alpha: 1), metallic: 0.05, roughness: 0.35)
        var siteIndex = 0
        var d = 900.0
        while d < route.distanceM - 900 {
            let hash = stableIndex("rural-\(siteIndex)", count: 1_000)
            defer { siteIndex += 1 }
            let step = 195 + Double(hash % 90)
            if urbanBand(distanceM: d, route: route, routeVariant: routeVariant, travelDirection: travelDirection) == 0,
               !stationModelPlacements.contains(where: { abs($0.chainageM - d) < 430 }),
               !isCoastal(distanceM: d, route: route, routeVariant: routeVariant, travelDirection: travelDirection) {
                let s = sample(at: d)
                let groundY = groundLevelM(at: s)
                let yaw = simd_quatf(angle: -s.heading, axis: SIMD3<Float>(0, 1, 0))
                for side: Float in [-1, 1] {
                    if (hash + (side > 0 ? 0 : 377)) % 5 == 4 { continue }  // some sides stay open
                    let baseLat = side * (24 + Float((hash / 3) % 14))
                    // Field patchwork: 2-3 quads stepping outward.
                    let quads = 2 + (hash / 7) % 2
                    for q in 0..<quads {
                        let lat = baseLat + side * Float(q) * 27
                        let p = groundOffsetPoint(sample(at: d + Double(q) * 14 - 7), lateral: lat)
                        _ = addBox(parent: world, name: "rural-field-\(siteIndex)-\(Int(side))-\(q)",
                                   size: SIMD3<Float>(25, 0.07, 58 + Float((hash / (q + 2)) % 26)),
                                   position: SIMD3<Float>(p.x, groundY + 0.035, p.z),
                                   material: fieldMats[(hash / (q + 1)) % fieldMats.count], orientation: yaw)
                    }
                    // Hedgerow along the field's track-side edge.
                    let hp = groundOffsetPoint(s, lateral: side * 12.6)
                    _ = addBox(parent: world, name: "rural-hedge-\(siteIndex)-\(Int(side))",
                               size: SIMD3<Float>(1.15, 0.95, 74),
                               position: SIMD3<Float>(hp.x, groundY + 0.48, hp.z),
                               material: hedgeMat, orientation: yaw)
                    // Greenhouse on some sites.
                    if hash % 4 == 1 {
                        let gp2 = groundOffsetPoint(sample(at: d + 22), lateral: baseLat + side * 6)
                        _ = addBox(parent: world, name: "rural-greenhouse-\(siteIndex)-\(Int(side))",
                                   size: SIMD3<Float>(9, 2.9, 17),
                                   position: SIMD3<Float>(gp2.x, groundY + 1.45, gp2.z),
                                   material: greenhouseMat, orientation: yaw)
                    }
                    // Farmhouse + shed on some sites.
                    if hash % 5 == 2 {
                        addBackRowHouse(at: d - 18, side: side, seed: 40_000 + siteIndex * 2 + (side > 0 ? 1 : 0))
                        let sp = groundOffsetPoint(sample(at: d + 4), lateral: side * 33)
                        _ = addBox(parent: world, name: "rural-shed-\(siteIndex)-\(Int(side))",
                                   size: SIMD3<Float>(4.6, 2.6, 6.4),
                                   position: SIMD3<Float>(sp.x, groundY + 1.3, sp.z),
                                   material: roofMaterials[abs(hash) % roofMaterials.count], orientation: yaw)
                    }
                }
            }
            d += step
        }
    }

    /// Tree lines and distant hills (night passes P2/P3,
    /// 2026-11-11). The suburb builder's tree layers ride on its
    /// house loop, so stretches that loop skips (and the far end of
    /// the line, where its foliage budget runs dry) used to end up
    /// bare. This pass is keyed to chainage instead: seeded tree
    /// rows and clumps every ~90 m in the non-urban bands, on its
    /// own modest budget, plus half-buried ellipsoid hill mounds
    /// 150-260 m out in the rural and coastal windows so the middle
    /// distance has a silhouette between the fields and the 680 m
    /// backdrop walls.
    private func buildTreeLinesAndHills(route: RailwayRouteProfile, routeVariant: RegionalRouteVariant, travelDirection: RegionalTravelDirection) {
        guard routeVariant == .mainline || routeVariant == .throughBranch else { return }
        let hillMats = [foliageMaterials[1], foliageMaterials[2]]
        var planted = 0
        var siteIndex = 0
        var d = 500.0
        while d < route.distanceM - 500 {
            let hash = stableIndex("treeline-\(siteIndex)", count: 1_000)
            siteIndex += 1
            let step = 85 + Double(hash % 50)
            defer { d += step }
            if urbanBand(distanceM: d, route: route, routeVariant: routeVariant, travelDirection: travelDirection) != 0 { continue }
            if stationModelPlacements.contains(where: { abs($0.chainageM - d) < 300 }) { continue }
            let coastal = isCoastal(distanceM: d, route: route, routeVariant: routeVariant, travelDirection: travelDirection)
            for side: Float in [-1, 1] {
                if coastal && side == seaSideSign(travelDirection: travelDirection) { continue }
                if (hash + (side > 0 ? 0 : 311)) % 4 == 3 { continue }
                // Tree row / clump in the 13-30 m band.
                if planted < 760 {
                    let trees = 1 + (hash / 5) % 3
                    for t in 0..<trees where planted < 760 {
                        let ts = sample(at: d + Double(t) * 6.5 + Double((hash / (t + 3)) % 5))
                        let tp = groundOffsetPoint(ts, lateral: side * (14 + Float((hash / (t + 2)) % 15)))
                        addTree(parent: world, name: "treeline-\(siteIndex)-\(Int(side))-\(t)", x: tp.x, z: tp.z,
                                height: 3.2 + Float((hash / (t + 1)) % 9) * 0.45,
                                material: foliageMaterials[(siteIndex + t) % foliageMaterials.count], groundY: tp.y)
                        planted += 1
                    }
                }
                // Distant hill mound on some sites.
                if (hash + (side > 0 ? 0 : 517)) % 9 == 4 {
                    let hs = sample(at: d + 30)
                    let hp = groundOffsetPoint(hs, lateral: side * (165 + Float(hash % 80)))
                    let hill = ModelEntity(mesh: MeshResource.generateSphere(radius: 1), materials: [hillMats[siteIndex % hillMats.count]])
                    hill.name = "distant-hill-\(siteIndex)-\(Int(side))"
                    hill.scale = SIMD3<Float>(55 + Float(hash % 40), 6.5 + Float((hash / 7) % 4), 24 + Float((hash / 3) % 12))
                    hill.position = SIMD3<Float>(hp.x, hp.y - 1.5, hp.z)
                    hill.orientation = simd_quatf(angle: -hs.heading, axis: SIMD3<Float>(0, 1, 0))
                    world.addChild(hill)
                }
            }
        }
    }

    /// Station character (night pass P7, 2026-11-11): the layout
    /// data gives every station an environment style, but the
    /// world never dressed for it — a "river" station looked like
    /// any other. Thirteen stations now get their setting: rivers
    /// run behind the river stations, hillside stations sit
    /// against a retaining wall with wooded slope above, and the
    /// industrial stations gain warehouses, a tank and containers.
    /// Keyed by station ID, so it is the same place in both
    /// directions and on the through run.
    private func buildStationCharacter(route: RailwayRouteProfile, routeVariant: RegionalRouteVariant, travelDirection: RegionalTravelDirection) {
        guard routeVariant == .mainline || routeVariant == .throughBranch else { return }
        let styles: [String: String] = [
            "S03": "hillside", "S05": "hillside", "S14": "hillside", "S19": "hillside", "S21": "hillside",
            "S09": "river", "S11": "river", "S12": "river", "B03": "river", "B04": "river",
            "S23": "industrial", "S26": "industrial", "B01": "industrial",
        ]
        let waterMat = Self.pbr(UIColor(red: 0.32, green: 0.50, blue: 0.55, alpha: 1), metallic: 0.15, roughness: 0.18)
        let bankMat = RailwaySceneWorld.texturedPBR(.white, roughness: 1, textureName: "scenery_grass")
        let tankMat = Self.pbr(UIColor(red: 0.85, green: 0.86, blue: 0.84, alpha: 1), metallic: 0.35, roughness: 0.45)
        for (index, placement) in stationModelPlacements.enumerated() {
            guard let style = styles[placement.stationId] else { continue }
            var side: Float = index % 2 == 0 ? 1 : -1
            if isCoastal(distanceM: placement.chainageM, route: route, routeVariant: routeVariant, travelDirection: travelDirection) {
                side = -seaSideSign(travelDirection: travelDirection)
            }
            let c = placement.chainageM
            let mid = sample(at: c)
            let yaw = simd_quatf(angle: -mid.heading, axis: SIMD3<Float>(0, 1, 0))
            let gy = groundLevelM(at: mid)
            func pt(_ along: Double, _ lat: Float) -> SIMD3<Float> { groundOffsetPoint(sample(at: c + along), lateral: lat) }
            switch style {
            case "river":
                let w = pt(0, side * 42)
                _ = addBox(parent: world, name: "station-river-\(placement.stationId)", size: SIMD3<Float>(13, 0.06, 150), position: SIMD3<Float>(w.x, gy + 0.04, w.z), material: waterMat, orientation: yaw)
                for bankSide: Float in [-1, 1] {
                    let b = pt(0, side * 42 + bankSide * 8.2)
                    _ = addBox(parent: world, name: "station-riverbank-\(placement.stationId)-\(Int(bankSide))", size: SIMD3<Float>(3.2, 0.09, 150), position: SIMD3<Float>(b.x, gy + 0.05, b.z), material: bankMat, orientation: yaw)
                }
                for t in 0..<3 {
                    let tp = pt(Double(t - 1) * 44, side * 33)
                    addTree(parent: world, name: "station-rivertree-\(placement.stationId)-\(t)", x: tp.x, z: tp.z, height: 5.2 + Float(t) * 0.7, material: foliageMaterials[(index + t) % foliageMaterials.count], groundY: tp.y)
                }
            case "hillside":
                let w = pt(0, side * 21)
                _ = addBox(parent: world, name: "station-retaining-\(placement.stationId)", size: SIMD3<Float>(1.2, 2.4, 130), position: SIMD3<Float>(w.x, gy + 1.2, w.z), material: concreteMaterial, orientation: yaw)
                for h in 0..<3 {
                    let hp = pt(Double(h - 1) * 46, side * (31 + Float(h % 2) * 6))
                    let hill = ModelEntity(mesh: MeshResource.generateSphere(radius: 1), materials: [foliageMaterials[(index + h) % foliageMaterials.count]])
                    hill.name = "station-hill-\(placement.stationId)-\(h)"
                    hill.scale = SIMD3<Float>(30, 5.5 + Float(h) * 0.8, 17)
                    hill.position = SIMD3<Float>(hp.x, hp.y - 1.2, hp.z)
                    hill.orientation = yaw
                    world.addChild(hill)
                }
                for t in 0..<4 {
                    let tp = pt(Double(t) * 30 - 45, side * (26 + Float((index + t) % 3) * 3))
                    addTree(parent: world, name: "station-hilltree-\(placement.stationId)-\(t)", x: tp.x, z: tp.z, height: 4.6 + Float((index + t) % 5) * 0.5, material: foliageMaterials[(index + t) % foliageMaterials.count], groundY: tp.y)
                }
            default: // industrial
                let w1 = pt(-16, side * 33)
                _ = addBox(parent: world, name: "station-warehouse-a-\(placement.stationId)", size: SIMD3<Float>(13, 7.5, 20), position: SIMD3<Float>(w1.x, gy + 3.75, w1.z), material: officeMaterials[(index * 3 + 1) % officeMaterials.count], orientation: yaw)
                let w2 = pt(20, side * 38)
                _ = addBox(parent: world, name: "station-warehouse-b-\(placement.stationId)", size: SIMD3<Float>(10, 6, 14), position: SIMD3<Float>(w2.x, gy + 3, w2.z), material: officeMaterials[(index * 5 + 2) % officeMaterials.count], orientation: yaw)
                let tk = pt(6, side * 47)
                let tank = ModelEntity(mesh: FallbackCylinderMesh.make(height: 5.5, radius: 2.3), materials: [tankMat])
                tank.name = "station-tank-\(placement.stationId)"
                tank.position = SIMD3<Float>(tk.x, gy + 2.75, tk.z)
                world.addChild(tank)
                for k in 0..<2 {
                    let cp = pt(-2 + Double(k) * 8, side * 26)
                    _ = addBox(parent: world, name: "station-container-\(placement.stationId)-\(k)", size: SIMD3<Float>(2.4, 2.6, 6.1), position: SIMD3<Float>(cp.x, gy + 1.3, cp.z), material: commercialAccent(seed: index * 7 + k), orientation: yaw)
                }
            }
        }
    }

    /// Speed restriction signs (2026-11-11, user check): the zoo
    /// line had its 30 km/h signs, but the main line's restrictions
    /// existed only in the ATS and the HUD — nothing stood beside
    /// the track. Signs are now derived from the playable route's
    /// own section limits: where the limit drops and stays down
    /// (or drops by 20+ at once), a board shows the new limit
    /// rounded down to a multiple of five; where a signed
    /// restriction ends, a release board follows. They stand on
    /// the left of the running track, facing the approaching
    /// train, clear of the station spans.
    private func buildSpeedSigns(route: RailwayRouteProfile, routeVariant: RegionalRouteVariant, travelDirection: RegionalTravelDirection) {
        guard routeVariant == .mainline || routeVariant == .throughBranch || routeVariant == .branchShuttle else { return }
        let sections = route.sections
        guard sections.count > 2 else { return }
        let postMat = Self.pbr(UIColor(red: 0.55, green: 0.56, blue: 0.58, alpha: 1), metallic: 0.5, roughness: 0.5)
        var materials: [Int: PhysicallyBasedMaterial] = [:]
        func signMaterial(_ value: Int) -> PhysicallyBasedMaterial {
            if let cached = materials[value] { return cached }
            var m = Self.texturedPBR(.white, roughness: 0.55, textureName: value == 0 ? "scenery_speed_release" : "scenery_speed_\(value)")
            m.faceCulling = .none
            materials[value] = m
            return m
        }
        let lateral: Float = travelDirection == .up ? -4.0 : 4.0
        func placeSign(value: Int, at d: Double) {
            if stationModelPlacements.contains(where: { abs($0.chainageM - d) < 150 }) { return }
            let base = groundOffsetPoint(sample(at: d), lateral: lateral)
            let yaw = simd_quatf(angle: -sample(at: d).heading, axis: SIMD3<Float>(0, 1, 0))
            _ = addBox(parent: world, name: "speedsign-pole-\(value)-\(Int(d))", size: SIMD3<Float>(0.09, 2.4, 0.09), position: SIMD3<Float>(base.x, base.y + 1.2, base.z), material: postMat, orientation: yaw)
            let board = addBox(parent: world, name: "speedsign-\(value)-\(Int(d))", size: SIMD3<Float>(0.85, 0.85, 0.04), position: SIMD3<Float>(base.x, base.y + 2.15, base.z), material: signMaterial(value), orientation: yaw)
            board.orientation = board.orientation * simd_quatf(angle: Float.pi, axis: SIMD3<Float>(0, 1, 0))
        }
        var activeValue: Int? = nil
        for i in 1..<sections.count {
            let prev = sections[i - 1].speedLimitKmh
            let cur = sections[i].speedLimitKmh
            let next: Double? = i + 1 < sections.count ? sections[i + 1].speedLimitKmh : nil
            if cur < prev - 0.5 {
                let persists = next == nil || next! <= cur + 0.5 || prev - cur >= 20
                if persists {
                    let value = max(40, min(110, Int(cur / 5) * 5))
                    if activeValue == nil || value < activeValue! {
                        placeSign(value: value, at: sections[i].startM - 2)
                        activeValue = value
                    }
                }
            } else if cur > prev + 0.5, activeValue != nil {
                let persists = next == nil || next! >= cur - 0.5
                if persists {
                    placeSign(value: 0, at: sections[i].startM - 2)
                    activeValue = nil
                }
            }
        }
    }

    /// Sign catalog (2026-11-11, user request: every sign on the
    /// isok.jp railway-system catalog page). Part 1 — lineside:
    /// gradient posts at sustained gradient changes, curve posts
    /// and transition markers from the route's own curve data,
    /// hectometre posts （距離標・丙号）, land boundary posts
    /// （用地界標）, lineside telephones （連絡用屋外子）, catenary
    /// auto-tension weight stacks （自動張力調整装置）, train
    /// approach lamps at crossings （列車接近知らせ灯）, wind
    /// regulation boards on the coastal windows （風・始端/終端標）
    /// and catenary end boards （架線終端標識）. Part 2 — stations
    /// and signals: see buildSignCatalogStations.
    private func buildSignCatalog(route: RailwayRouteProfile, routeVariant: RegionalRouteVariant, travelDirection: RegionalTravelDirection) {
        guard routeVariant == .mainline || routeVariant == .throughBranch || routeVariant == .branchShuttle else { return }
        let up = travelDirection == .up
        let signLat: Float = up ? -4.0 : 4.0
        let postMat = Self.pbr(UIColor(red: 0.55, green: 0.56, blue: 0.58, alpha: 1), metallic: 0.5, roughness: 0.5)
        var matCache: [String: PhysicallyBasedMaterial] = [:]
        func mat(_ texture: String) -> PhysicallyBasedMaterial {
            if let cached = matCache[texture] { return cached }
            var m = Self.texturedPBR(.white, roughness: 0.55, textureName: texture)
            m.faceCulling = .none
            matCache[texture] = m
            return m
        }
        func postBoard(_ d: Double, _ lat: Float, _ texture: String, w: Float = 0.85, h: Float = 0.85, top: Float = 2.15, tag: String) {
            let base = groundOffsetPoint(sample(at: d), lateral: lat)
            let yaw = simd_quatf(angle: -sample(at: d).heading, axis: SIMD3<Float>(0, 1, 0))
            _ = addBox(parent: world, name: "signpost-\(tag)", size: SIMD3<Float>(0.09, top, 0.09), position: SIMD3<Float>(base.x, base.y + top / 2, base.z), material: postMat, orientation: yaw)
            let b = addBox(parent: world, name: "sign-\(tag)", size: SIMD3<Float>(w, h, 0.04), position: SIMD3<Float>(base.x, base.y + top - h / 2 + 0.08, base.z), material: mat(texture), orientation: yaw)
            b.orientation = b.orientation * simd_quatf(angle: Float.pi, axis: SIMD3<Float>(0, 1, 0))
        }
        func nearStation(_ d: Double, _ margin: Double = 150) -> Bool {
            stationModelPlacements.contains(where: { abs($0.chainageM - d) < margin })
        }

        // -- Gradient posts: at sustained changes of 3‰ or more.
        let gradientSet = [0, 5, 10, 15, 20, 25, 30, 35]
        let sections = route.sections
        for i in 1..<sections.count {
            let prev = sections[i - 1].gradientPermille
            let cur = sections[i].gradientPermille
            if abs(cur - prev) >= 3 {
                let persists = i + 1 >= sections.count || abs(sections[i + 1].gradientPermille - cur) < 3
                if persists && !nearStation(sections[i].startM) {
                    let v = Int(abs(cur).rounded())
                    let shown = gradientSet.min(by: { abs($0 - v) < abs($1 - v) }) ?? 0
                    postBoard(sections[i].startM - 2, signLat, "scenery_sign_gradient_\(shown)", tag: "gradient-\(Int(sections[i].startM))")
                }
            }
        }

        // -- Curve posts （曲線標） and transition markers （逓減標）.
        var seenCurves = Set<Int>()
        for section in sections {
            guard let transition = section.curveTransition, let radius = section.curveRadiusM else { continue }
            let key = Int(transition.startM / 10)
            if seenCurves.contains(key) { continue }
            seenCurves.insert(key)
            let rSet = [300, 400, 500, 600, 800, 1000, 1200, 1600, 2000]
            let shownR = rSet.min(by: { abs($0 - Int(radius)) < abs($1 - Int(radius)) }) ?? 800
            if !nearStation(transition.startM) {
                postBoard(transition.startM - 2, signLat, "scenery_sign_curve_\(shownR)", tag: "curve-\(key)")
                postBoard(transition.endM + 2, signLat, "scenery_sign_curve_\(shownR)", tag: "curve-end-\(key)")
                postBoard(transition.startM - 2, -signLat, "scenery_sign_transition", w: 0.5, h: 0.5, top: 1.5, tag: "transition-\(key)")
            }
        }

        // -- Hectometre posts, boundary posts, telephones (batched).
        var postBatch = MeshBatchBuilder()
        let phoneMat = Self.pbr(UIColor(red: 0.42, green: 0.44, blue: 0.46, alpha: 1), metallic: 0.3, roughness: 0.6)
        var d = 100.0
        while d < route.distanceM - 60 {
            let s = sample(at: d)
            if Int(d) % 1000 != 0 {
                let p = groundOffsetPoint(s, lateral: -signLat * 1.1)
                postBatch.addBox(center: SIMD3<Float>(p.x, p.y + 0.27, p.z), size: SIMD3<Float>(0.12, 0.55, 0.12), yaw: -s.heading)
            }
            if Int(d) % 200 == 0 {
                let side: Float = (Int(d / 200) % 2 == 0) ? -1 : 1
                let p = groundOffsetPoint(s, lateral: side * 12.0)
                postBatch.addBox(center: SIMD3<Float>(p.x, p.y + 0.35, p.z), size: SIMD3<Float>(0.15, 0.7, 0.15), yaw: -s.heading)
            }
            d += 100
        }
        if let mesh = postBatch.build(name: "sign-hectometre-posts", material: concreteMaterial) { world.addChild(mesh) }
        var phoneD = 1_000.0
        while phoneD < route.distanceM - 100 {
            if !nearStation(phoneD, 220) {
                let base = groundOffsetPoint(sample(at: phoneD), lateral: signLat * 1.2)
                let yaw = simd_quatf(angle: -sample(at: phoneD).heading, axis: SIMD3<Float>(0, 1, 0))
                _ = addBox(parent: world, name: "sign-phone-post-\(Int(phoneD))", size: SIMD3<Float>(0.08, 1.5, 0.08), position: SIMD3<Float>(base.x, base.y + 0.75, base.z), material: postMat, orientation: yaw)
                _ = addBox(parent: world, name: "sign-phone-\(Int(phoneD))", size: SIMD3<Float>(0.42, 0.62, 0.24), position: SIMD3<Float>(base.x, base.y + 1.55, base.z), material: phoneMat, orientation: yaw)
            }
            phoneD += 2_000
        }

        // -- Catenary auto-tension weight stacks every ~1,500 m.
        var tensionD = 750.0
        while tensionD < route.distanceM - 100 {
            if !nearStation(tensionD, 200) {
                let base = groundOffsetPoint(sample(at: tensionD), lateral: signLat * 1.45)
                let yaw = simd_quatf(angle: -sample(at: tensionD).heading, axis: SIMD3<Float>(0, 1, 0))
                for k in 0..<3 {
                    _ = addBox(parent: world, name: "sign-tension-\(Int(tensionD))-\(k)", size: SIMD3<Float>(0.55, 0.32, 0.55), position: SIMD3<Float>(base.x, base.y + 0.35 + Float(k) * 0.34, base.z), material: concreteMaterial, orientation: yaw)
                }
                let pulley = ModelEntity(mesh: FallbackCylinderMesh.make(height: 0.1, radius: 0.3), materials: [postMat])
                pulley.name = "sign-tension-pulley-\(Int(tensionD))"
                pulley.position = SIMD3<Float>(base.x, base.y + 1.65, base.z)
                pulley.orientation = yaw * simd_quatf(angle: Float.pi / 2, axis: SIMD3<Float>(0, 0, 1))
                world.addChild(pulley)
            }
            tensionD += 1_500
        }

        // -- Train approach lamps before crossings.
        var lampMat = Self.pbr(UIColor(red: 0.98, green: 0.72, blue: 0.25, alpha: 1), roughness: 0.35)
        lampMat.emissiveColor = .init(color: UIColor(red: 0.98, green: 0.72, blue: 0.25, alpha: 1))
        lampMat.emissiveIntensity = 2.0
        var redLampMat = Self.pbr(UIColor(red: 0.92, green: 0.15, blue: 0.12, alpha: 1), roughness: 0.35)
        redLampMat.emissiveColor = .init(color: UIColor(red: 0.92, green: 0.15, blue: 0.12, alpha: 1))
        redLampMat.emissiveIntensity = 2.0
        var whiteLampMat = Self.pbr(UIColor(red: 0.95, green: 0.96, blue: 0.98, alpha: 1), roughness: 0.35)
        whiteLampMat.emissiveColor = .init(color: UIColor(red: 0.95, green: 0.96, blue: 0.98, alpha: 1))
        whiteLampMat.emissiveIntensity = 1.8
        let sensorMat = Self.pbr(UIColor(red: 0.08, green: 0.08, blue: 0.09, alpha: 1), metallic: 0.3, roughness: 0.55)
        for crossing in crossingCenters {
            let d2 = crossing - 130
            if d2 < 60 { continue }
            let base = groundOffsetPoint(sample(at: d2), lateral: signLat * 1.7)
            let yaw = simd_quatf(angle: -sample(at: d2).heading, axis: SIMD3<Float>(0, 1, 0))
            _ = addBox(parent: world, name: "sign-approachlamp-post-\(Int(crossing))", size: SIMD3<Float>(0.08, 2.3, 0.08), position: SIMD3<Float>(base.x, base.y + 1.15, base.z), material: postMat, orientation: yaw)
            _ = addBox(parent: world, name: "sign-approachlamp-\(Int(crossing))", size: SIMD3<Float>(0.2, 0.2, 0.2), position: SIMD3<Float>(base.x, base.y + 2.35, base.z), material: lampMat, orientation: yaw)
            // 2026-11-11 addendum (user chose the 5 visible items
            // from the catalog re-check): special signal flasher
            // （特殊信号発光機） before the crossing, crossing
            // indicator lamp （踏切表示灯） past it, obstruction
            // alarm board （踏切支障報知装置） at the roadside and
            // obstacle detector posts （踏切障害物検知装置） at the
            // four corners.
            let flashD = crossing - 20
            let flashBase = groundOffsetPoint(sample(at: flashD), lateral: signLat * 1.15)
            let flashYaw = simd_quatf(angle: -sample(at: flashD).heading, axis: SIMD3<Float>(0, 1, 0))
            _ = addBox(parent: world, name: "sign-flasher-post-\(Int(crossing))", size: SIMD3<Float>(0.09, 2.6, 0.09), position: SIMD3<Float>(flashBase.x, flashBase.y + 1.3, flashBase.z), material: postMat, orientation: flashYaw)
            _ = addBox(parent: world, name: "sign-flasher-head-\(Int(crossing))", size: SIMD3<Float>(0.32, 0.55, 0.22), position: SIMD3<Float>(flashBase.x, flashBase.y + 2.75, flashBase.z), material: sensorMat, orientation: flashYaw)
            let flashLamp = ModelEntity(mesh: MeshResource.generateSphere(radius: 0.09), materials: [redLampMat])
            flashLamp.name = "sign-flasher-lamp-\(Int(crossing))"
            let flashFront = groundOffsetPoint(sample(at: flashD - 0.18), lateral: signLat * 1.15)
            flashLamp.position = SIMD3<Float>(flashFront.x, flashBase.y + 2.85, flashFront.z)
            world.addChild(flashLamp)
            let lampD = crossing + 4
            let lampBase = groundOffsetPoint(sample(at: lampD), lateral: -signLat * 1.15)
            let lampYaw = simd_quatf(angle: -sample(at: lampD).heading, axis: SIMD3<Float>(0, 1, 0))
            _ = addBox(parent: world, name: "sign-crosslamp-post-\(Int(crossing))", size: SIMD3<Float>(0.08, 2.4, 0.08), position: SIMD3<Float>(lampBase.x, lampBase.y + 1.2, lampBase.z), material: postMat, orientation: lampYaw)
            _ = addBox(parent: world, name: "sign-crosslamp-head-\(Int(crossing))", size: SIMD3<Float>(0.22, 0.3, 0.18), position: SIMD3<Float>(lampBase.x, lampBase.y + 2.5, lampBase.z), material: sensorMat, orientation: lampYaw)
            let crossLamp = ModelEntity(mesh: MeshResource.generateSphere(radius: 0.07), materials: [whiteLampMat])
            crossLamp.name = "sign-crosslamp-\(Int(crossing))"
            let lampFront = groundOffsetPoint(sample(at: lampD + 0.16), lateral: -signLat * 1.15)
            crossLamp.position = SIMD3<Float>(lampFront.x, lampBase.y + 2.5, lampFront.z)
            world.addChild(crossLamp)
            postBoard(crossing + 7, -signLat * 2.6, "scenery_sign_crossing_alarm", w: 0.62, h: 0.75, top: 1.75, tag: "crossalarm-\(Int(crossing))")
            for cornerD in [crossing - 5, crossing + 5] {
                for cornerLat in [Float(-3.4), Float(3.4)] {
                    let cb = groundOffsetPoint(sample(at: cornerD), lateral: cornerLat)
                    let cyaw = simd_quatf(angle: -sample(at: cornerD).heading, axis: SIMD3<Float>(0, 1, 0))
                    _ = addBox(parent: world, name: "sign-detector-\(Int(cornerD))-\(Int(cornerLat))", size: SIMD3<Float>(0.12, 0.95, 0.12), position: SIMD3<Float>(cb.x, cb.y + 0.47, cb.z), material: postMat, orientation: cyaw)
                    _ = addBox(parent: world, name: "sign-detector-head-\(Int(cornerD))-\(Int(cornerLat))", size: SIMD3<Float>(0.18, 0.25, 0.18), position: SIMD3<Float>(cb.x, cb.y + 1.05, cb.z), material: sensorMat, orientation: cyaw)
                }
            }
        }

        // -- Wind regulation boards on the coastal windows.
        if routeVariant == .mainline || routeVariant == .throughBranch {
            func travelD(_ c: Double) -> Double { up ? c : route.distanceM - c }
            for window in [(38_500.0, 40_500.0), (43_600.0, 48_600.0), (53_000.0, 59_900.0)] {
                let entry = min(travelD(window.0), travelD(window.1))
                let exit = max(travelD(window.0), travelD(window.1))
                postBoard(entry - 5, signLat, "scenery_sign_wind", tag: "wind-start-\(Int(window.0))")
                postBoard(exit + 5, signLat, "scenery_sign_wind", tag: "wind-end-\(Int(window.0))")
            }
            // Catenary end boards near both line ends.
            postBoard(150, signLat, "scenery_sign_catenary_end", top: 3.1, tag: "catenary-end-a")
            postBoard(route.distanceM - 150, signLat, "scenery_sign_catenary_end", top: 3.1, tag: "catenary-end-b")
        }

        buildSignCatalogStations(route: route, routeVariant: routeVariant, travelDirection: travelDirection)
    }

    /// Sign catalog part 2 — stations and signals: station limit
    /// boards （停車場標） at both ends of every station area,
    /// approach boards （停車場接近標）, brake boards （ブレーキ標）
    /// where the approach descends, train stop markers
    /// （列車停止目標） for 4/6/8/10-car trains on every platform,
    /// "long" boards at the wide stations, fouling-point markers
    /// （車両接触限界標識） at the throats, departure reaction
    /// boards （出発反応標識） at the departure signals, repeater
    /// signals （中継信号機） before blind home signals, distant
    /// signals （遠方信号機） on the fast approaches, route
    /// indicators （進路表示機） at the junctions, shunting signals
    /// （入換信号機） at the depot and junction throats, and the
    /// depot boards （無閉塞禁止・車両停止標識・移動禁止）.
    private func buildSignCatalogStations(route: RailwayRouteProfile, routeVariant: RegionalRouteVariant, travelDirection: RegionalTravelDirection) {
        let up = travelDirection == .up
        let signLat: Float = up ? -4.0 : 4.0
        let signalLat: Float = up ? -3.7 : 3.7
        let postMat = Self.pbr(UIColor(red: 0.55, green: 0.56, blue: 0.58, alpha: 1), metallic: 0.5, roughness: 0.5)
        let headMat = Self.pbr(UIColor(red: 0.05, green: 0.05, blue: 0.06, alpha: 1), metallic: 0.3, roughness: 0.6)
        var matCache: [String: PhysicallyBasedMaterial] = [:]
        func mat(_ texture: String) -> PhysicallyBasedMaterial {
            if let cached = matCache[texture] { return cached }
            var m = Self.texturedPBR(.white, roughness: 0.55, textureName: texture)
            m.faceCulling = .none
            matCache[texture] = m
            return m
        }
        func litMat(_ color: UIColor) -> PhysicallyBasedMaterial {
            var m = Self.pbr(color, roughness: 0.35)
            m.emissiveColor = .init(color: color)
            m.emissiveIntensity = 2.0
            return m
        }
        let whiteLamp = litMat(UIColor(red: 0.95, green: 0.96, blue: 0.98, alpha: 1))
        let redLamp = litMat(UIColor(red: 0.92, green: 0.15, blue: 0.12, alpha: 1))
        let greenLamp = litMat(UIColor(red: 0.25, green: 0.85, blue: 0.35, alpha: 1))
        let yellowLamp = litMat(UIColor(red: 0.98, green: 0.78, blue: 0.2, alpha: 1))
        func postBoard(_ d: Double, _ lat: Float, _ texture: String, w: Float = 0.85, h: Float = 0.85, top: Float = 2.15, tag: String) {
            let base = groundOffsetPoint(sample(at: d), lateral: lat)
            let yaw = simd_quatf(angle: -sample(at: d).heading, axis: SIMD3<Float>(0, 1, 0))
            _ = addBox(parent: world, name: "signpost-\(tag)", size: SIMD3<Float>(0.09, top, 0.09), position: SIMD3<Float>(base.x, base.y + top / 2, base.z), material: postMat, orientation: yaw)
            let b = addBox(parent: world, name: "sign-\(tag)", size: SIMD3<Float>(w, h, 0.04), position: SIMD3<Float>(base.x, base.y + top - h / 2 + 0.08, base.z), material: mat(texture), orientation: yaw)
            b.orientation = b.orientation * simd_quatf(angle: Float.pi, axis: SIMD3<Float>(0, 1, 0))
        }
        func staticHead(_ d: Double, _ lat: Float, lamps: [PhysicallyBasedMaterial], tag: String) {
            let base = groundOffsetPoint(sample(at: d), lateral: lat)
            let yaw = simd_quatf(angle: -sample(at: d).heading, axis: SIMD3<Float>(0, 1, 0))
            _ = addBox(parent: world, name: "signpost-\(tag)", size: SIMD3<Float>(0.11, 3.6, 0.11), position: SIMD3<Float>(base.x, base.y + 1.8, base.z), material: postMat, orientation: yaw)
            _ = addBox(parent: world, name: "signalhead-\(tag)", size: SIMD3<Float>(0.34, 0.34 + Float(lamps.count) * 0.3, 0.2), position: SIMD3<Float>(base.x, base.y + 3.6 + Float(lamps.count) * 0.15, base.z), material: headMat, orientation: yaw)
            for (i, lamp) in lamps.enumerated() {
                let lampEntity = ModelEntity(mesh: MeshResource.generateSphere(radius: 0.075), materials: [lamp])
                lampEntity.name = "signallamp-\(tag)-\(i)"
                let back = groundOffsetPoint(sample(at: d - 0.16), lateral: lat)
                lampEntity.position = SIMD3<Float>(back.x, base.y + 3.6 + Float(lamps.count - i) * 0.3 - 0.02, back.z)
                world.addChild(lampEntity)
            }
        }

        // -- Station boards from the placements (travel frame).
        for placement in stationModelPlacements {
            let c = placement.chainageM
            let half = platformLengthM(stationId: placement.stationId, archetype: placement.archetype) / 2
            postBoard(c - 430, signLat, "scenery_sign_station_limit", tag: "stationlimit-a-\(placement.stationId)")
            postBoard(c + 430, signLat, "scenery_sign_station_limit", tag: "stationlimit-b-\(placement.stationId)")
            postBoard(c - half - 350, signLat, "scenery_sign_station_approach", tag: "stationapproach-\(placement.stationId)")
            // Brake board where the approach descends at 8‰ or more.
            var gSum = 0.0
            var gLen = 0.0
            for s in route.sections {
                let a = max(s.startM, c - 1_500)
                let b = min(s.endM, c - 300)
                if b > a { gSum += s.gradientPermille * (b - a); gLen += (b - a) }
            }
            if gLen > 0 && gSum / gLen <= -8 {
                postBoard(c - half - 550, signLat, "scenery_sign_brake", tag: "brake-\(placement.stationId)")
            }
        }

        // -- Stop markers and long boards on the platforms.
        let topFull: Float = 0.3065 + 1.10
        var markerBatches: [Int: MeshBatchBuilder] = [:]
        var longBatch = MeshBatchBuilder()
        var standBatch = MeshBatchBuilder()
        var seenMarkers = Set<String>()
        for placement in stationModelPlacements {
            let length = platformLengthM(stationId: placement.stationId, archetype: placement.archetype)
            let wide = placement.archetype.contains("terminal") || placement.archetype.contains("major") || placement.archetype == "junction_3platform"
            let midSample = sample(at: placement.chainageM)
            let isMainlineSection = travelDirection == .up ? midSample.distanceM < 60_000 : midSample.distanceM >= 8_000
            let hasPassingTrack = routeVariant == .mainline || (routeVariant == .throughBranch && isMainlineSection)
            let trackLaterals: [Float] = hasPassingTrack ? [-2.1, 2.1] : [travelDirection == .up ? -2.1 : 2.1]
            for trackLateral in trackLaterals {
                let sides: [Float] = hasPassingTrack ? [trackLateral < 0 ? -1.0 : 1.0] : [-1.0, 1.0]
                for sideSign in sides {
                    for cars in [4, 6, 8, 10] {
                        for dirSign in [-1.0, 1.0] {
                            let cm = placement.chainageM + dirSign * (Double(cars) * 10 + 1)
                            let key = "\(Int(cm))-\(Int(trackLateral * 10))-\(Int(sideSign))-\(cars)-\(Int(dirSign))"
                            if seenMarkers.contains(key) { continue }
                            seenMarkers.insert(key)
                            let frame = profileStation(at: cm, trackLateral: trackLateral)
                            let axisZ = simd_cross(frame.xAxis, frame.yAxis)
                            let flip = dirSign > 0
                            let ax = flip ? frame.xAxis * -1 : frame.xAxis
                            let az = flip ? axisZ * -1 : axisZ
                            let center = frame.center + frame.xAxis * (sideSign * 1.85) + frame.yAxis * (topFull + 0.62)
                            if markerBatches[cars] == nil { markerBatches[cars] = MeshBatchBuilder() }
                            markerBatches[cars]!.addBoxAxes(center: center, size: SIMD3<Float>(0.55, 0.55, 0.04), ax: ax, ay: frame.yAxis, az: az)
                            standBatch.addBoxAxes(center: frame.center + frame.xAxis * (sideSign * 1.85) + frame.yAxis * (topFull + 0.28), size: SIMD3<Float>(0.06, 0.56, 0.06), ax: frame.xAxis, ay: frame.yAxis, az: axisZ)
                        }
                    }
                    if wide {
                        let cm = placement.chainageM - length / 2 + 10
                        let frame = profileStation(at: cm, trackLateral: trackLateral)
                        let axisZ = simd_cross(frame.xAxis, frame.yAxis)
                        longBatch.addBoxAxes(center: frame.center + frame.xAxis * (sideSign * 1.85) + frame.yAxis * (topFull + 0.85), size: SIMD3<Float>(0.95, 0.6, 0.04), ax: frame.xAxis, ay: frame.yAxis, az: axisZ)
                    }
                    // Fouling-point markers at both throats.
                    if hasPassingTrack {
                        for endSign in [-1.0, 1.0] {
                            let fm = placement.chainageM + endSign * (length / 2 + 28)
                            let fp = groundOffsetPoint(sample(at: fm), lateral: 0)
                            _ = addBox(parent: world, name: "sign-fouling-\(placement.stationId)-\(Int(endSign))", size: SIMD3<Float>(0.14, 0.85, 0.14), position: SIMD3<Float>(fp.x, fp.y + 0.42, fp.z), material: mat("scenery_sign_stop_train"), orientation: simd_quatf(angle: -sample(at: fm).heading, axis: SIMD3<Float>(0, 1, 0)))
                        }
                    }
                }
            }
        }
        for (cars, batch) in markerBatches {
            if let mesh = batch.build(name: "sign-stopmarkers-\(cars)", material: mat("scenery_sign_stopmark_\(cars)")) { world.addChild(mesh) }
        }
        if let mesh = longBatch.build(name: "sign-long-boards", material: mat("scenery_sign_long")) { world.addChild(mesh) }
        if let mesh = standBatch.build(name: "sign-stopmarker-stands", material: postMat) { world.addChild(mesh) }

        // -- Signal extras from the centre-frame signal geometry.
        if routeVariant == .mainline || routeVariant == .throughBranch || routeVariant == .branchShuttle {
            let totalCentre: Double = routeVariant == .throughBranch ? 68_000 : (routeVariant == .branchShuttle ? 8_000 : 60_000)
            func travelD(_ c: Double) -> Double { up ? c : route.distanceM - c }
            for placement in stationModelPlacements {
                let centre = chainageFromCenter(distanceM: placement.chainageM, route: route, travelDirection: travelDirection)
                guard centre > 300, centre < totalCentre - 300 else { continue }
                let approachC = centre + (up ? -400 : 400)
                let departureC = centre + (up ? 170 : -170)
                if departureC > 60, departureC < totalCentre - 60 {
                    postBoard(travelD(departureC), signalLat, "scenery_sign_departure_reaction", w: 0.5, h: 0.5, top: 1.7, tag: "depreact-\(placement.stationId)")
                }
                let approachTravel = travelD(approachC)
                // Repeater before a home signal on a blind curve.
                let probe = route.sections.first(where: { approachTravel - 250 >= $0.startM && approachTravel - 250 < $0.endM })
                if let radius = probe?.curveRadiusM, radius < 900 {
                    staticHead(approachTravel - 450, signalLat, lamps: [whiteLamp, whiteLamp], tag: "repeater-\(placement.stationId)")
                }
                // Distant signal on a fast approach.
                if let limit = probe?.speedLimitKmh, limit >= 95 {
                    staticHead(approachTravel - 950, signalLat, lamps: [yellowLamp, greenLamp], tag: "distant-\(placement.stationId)")
                }
                // Route indicator at the junctions.
                if placement.archetype.contains("junction") || placement.stationId == "S24" || placement.stationId == "S26" || placement.stationId == "S12" {
                    postBoard(approachTravel - 5, signalLat, "scenery_sign_route", w: 0.8, h: 0.8, top: 4.6, tag: "route-\(placement.stationId)")
                    // Route advance indicator （進路予告機）: the same
                    // diagram repeated about 480 m earlier.
                    postBoard(approachTravel - 480, signalLat, "scenery_sign_route", w: 0.8, h: 0.8, top: 4.2, tag: "routeadvance-\(placement.stationId)")
                }
            }
            // Shunting signals at the junction throats.
            for junctionId in ["S24", "S26"] {
                if let placement = stationModelPlacements.first(where: { $0.stationId == junctionId }) {
                    let base = groundOffsetPoint(sample(at: placement.chainageM - 320), lateral: signLat)
                    let yaw = simd_quatf(angle: -sample(at: placement.chainageM - 320).heading, axis: SIMD3<Float>(0, 1, 0))
                    _ = addBox(parent: world, name: "sign-shunt-\(junctionId)", size: SIMD3<Float>(0.3, 0.55, 0.24), position: SIMD3<Float>(base.x, base.y + 0.85, base.z), material: headMat, orientation: yaw)
                    let lampEntity = ModelEntity(mesh: MeshResource.generateSphere(radius: 0.06), materials: [redLamp])
                    lampEntity.name = "sign-shunt-lamp-\(junctionId)"
                    let back = groundOffsetPoint(sample(at: placement.chainageM - 320 - 0.15), lateral: signLat)
                    lampEntity.position = SIMD3<Float>(back.x, base.y + 0.98, back.z)
                    world.addChild(lampEntity)
                }
            }
        }

        // -- Depot boards (main line only).
        if routeVariant == .mainline || routeVariant == .throughBranch {
            func travelD(_ c: Double) -> Double { up ? c : route.distanceM - c }
            let yardSide: Float = up ? 6.5 : -6.5
            postBoard(travelD(27_545), yardSide, "scenery_sign_noblock", w: 1.7, h: 0.95, top: 2.0, tag: "depot-noblock")
            postBoard(travelD(27_660), yardSide * 1.3, "scenery_sign_stop_vehicle", w: 0.7, h: 0.7, top: 1.6, tag: "depot-stop-a")
            postBoard(travelD(27_750), yardSide * 1.3, "scenery_sign_stop_vehicle", w: 0.7, h: 0.7, top: 1.6, tag: "depot-stop-b")
            postBoard(travelD(27_700), yardSide, "scenery_sign_nomove", w: 0.85, h: 0.55, top: 1.5, tag: "depot-nomove")
            postBoard(travelD(27_790), yardSide * 1.3, "scenery_sign_stop_train", w: 0.7, h: 0.7, top: 1.6, tag: "depot-stoptrain")
            // Shunting signal at the depot throat.
            let base = groundOffsetPoint(sample(at: travelD(27_545)), lateral: signLat)
            let yaw = simd_quatf(angle: -sample(at: travelD(27_545)).heading, axis: SIMD3<Float>(0, 1, 0))
            _ = addBox(parent: world, name: "sign-shunt-depot", size: SIMD3<Float>(0.3, 0.55, 0.24), position: SIMD3<Float>(base.x, base.y + 0.85, base.z), material: headMat, orientation: yaw)
            let lampEntity = ModelEntity(mesh: MeshResource.generateSphere(radius: 0.06), materials: [redLamp])
            lampEntity.name = "sign-shunt-lamp-depot"
            lampEntity.position = SIMD3<Float>(base.x, base.y + 0.98, base.z)
            world.addChild(lampEntity)
        }
    }

    /// Tourist terminus (quality41 final, user request): the
    /// down-side terminus 鴨河 is a full tourist destination in the
    /// Hakone / Atami / Kamakura mould, and the approach builds up
    /// gradually — banner poles from 大野， pensions around 御浜，
    /// hotels from 館川 to 千蔵， then the terminus itself: a
    /// timber-and-white gateway station house with a clock tower,
    /// a plaza with a rotary and tour buses, a souvenir-shop row,
    /// ryokan blocks, a foot bath, and a lighthouse on the sea-side
    /// promenade. Zones are keyed to centre-frame chainages so the
    /// town is the same physical place in both directions.
    private func buildTouristTerminus(route: RailwayRouteProfile, routeVariant: RegionalRouteVariant, travelDirection: RegionalTravelDirection) {
        guard routeVariant == .mainline || routeVariant == .throughBranch else { return }
        let seaSide = seaSideSign(travelDirection: travelDirection)
        let land = -seaSide
        func travelD(_ c: Double) -> Double { travelDirection == .up ? c : route.distanceM - c }
        func gp(_ c: Double, _ lat: Float) -> SIMD3<Float> { groundOffsetPoint(sample(at: travelD(c)), lateral: lat) }
        func yaw(_ c: Double) -> simd_quatf { simd_quatf(angle: -sample(at: travelD(c)).heading, axis: SIMD3<Float>(0, 1, 0)) }
        func gy(_ c: Double) -> Float { groundLevelM(at: travelD(c)) }
        let whiteMat = Self.pbr(UIColor(red: 0.93, green: 0.92, blue: 0.90, alpha: 1), roughness: 0.85)
        let timberMat = RailwaySceneWorld.texturedPBR(UIColor(red: 0.72, green: 0.58, blue: 0.44, alpha: 1), roughness: 0.9, textureName: "scenery_timber")
        let roofMat = Self.pbr(UIColor(red: 0.16, green: 0.17, blue: 0.20, alpha: 1), metallic: 0.15, roughness: 0.65)
        let flagMats = [
            Self.pbr(UIColor(red: 0.80, green: 0.22, blue: 0.18, alpha: 1), roughness: 0.85),
            Self.pbr(UIColor(red: 0.10, green: 0.45, blue: 0.55, alpha: 1), roughness: 0.85),
            Self.pbr(UIColor(red: 0.90, green: 0.55, blue: 0.15, alpha: 1), roughness: 0.85),
            Self.pbr(UIColor(red: 0.95, green: 0.94, blue: 0.90, alpha: 1), roughness: 0.85),
        ]

        // -- Gradual build-up: nobori banner poles from 大野 on.
        var bannerIndex = 0
        var bc = 51_000.0
        while bc <= 59_850 {
            let p = gp(bc, land * 9.5)
            let y = gy(bc)
            _ = addBox(parent: world, name: "tourist-banner-pole-\(bannerIndex)", size: SIMD3<Float>(0.07, 4.6, 0.07), position: SIMD3<Float>(p.x, y + 2.3, p.z), material: roofMat, orientation: yaw(bc))
            _ = addBox(parent: world, name: "tourist-banner-\(bannerIndex)", size: SIMD3<Float>(0.05, 3.1, 0.58), position: SIMD3<Float>(p.x, y + 2.85, p.z), material: flagMats[bannerIndex % flagMats.count], orientation: yaw(bc))
            bannerIndex += 1
            bc += bc > 57_000 ? 420 : 700
        }

        // -- Pensions around 御浜 (zone B).
        for (i, c) in [53_300.0, 53_950.0, 54_600.0].enumerated() {
            let p = gp(c, land * 26)
            let y = gy(c)
            _ = addBox(parent: world, name: "tourist-pension-\(i)", size: SIMD3<Float>(9, 6.5, 10), position: SIMD3<Float>(p.x, y + 3.25, p.z), material: i % 2 == 0 ? houseFacadeMaterial5 : houseFacadeMaterial4, orientation: yaw(c))
            let sp = gp(c, land * 20.8)
            _ = addBox(parent: world, name: "tourist-pension-sign-\(i)", size: SIMD3<Float>(0.25, 1.0, 4.6), position: SIMD3<Float>(sp.x, y + 7.0, sp.z), material: whiteMat, orientation: yaw(c))
        }

        // -- Hotels from 館川 to 千蔵 (zone C) + souvenir shops
        // approaching 千蔵.
        for (i, c) in [55_500.0, 56_300.0, 57_000.0].enumerated() {
            let p = gp(c, land * 31)
            let y = gy(c)
            _ = addBox(parent: world, name: "tourist-hotel-\(i)", size: SIMD3<Float>(13, 16, 17), position: SIMD3<Float>(p.x, y + 8, p.z), material: officeMaterials[(i * 5 + 3) % officeMaterials.count], orientation: yaw(c))
            let sp = gp(c, land * 23.8)
            _ = addBox(parent: world, name: "tourist-hotel-sign-\(i)", size: SIMD3<Float>(0.3, 1.3, 6.5), position: SIMD3<Float>(sp.x, y + 17.2, sp.z), material: whiteMat, orientation: yaw(c))
            let cp = gp(c, land * 23.2)
            _ = addBox(parent: world, name: "tourist-hotel-canopy-\(i)", size: SIMD3<Float>(3.4, 0.22, 7), position: SIMD3<Float>(cp.x, y + 3.2, cp.z), material: roofMat, orientation: yaw(c))
        }
        for (i, c) in [57_250.0, 57_420.0].enumerated() {
            // Lateral 17.5 (was 15): 千蔵 became a passing-loop
            // station in diagram v4, and the loop deck edge runs
            // to 12.5 — the shops keep a clear margin from it.
            let p = gp(c, land * 17.5)
            let y = gy(c)
            _ = addBox(parent: world, name: "tourist-shop-chikura-\(i)", size: SIMD3<Float>(6, 4.4, 7.5), position: SIMD3<Float>(p.x, y + 2.2, p.z), material: shopFacadeMaterial, orientation: yaw(c))
        }

        // -- The terminus itself (zone D, 鴨河 60,000).
        let tc = 59_955.0
        // Plaza + rotary on the land side.
        let plaza = gp(tc, land * 21)
        let plazaY = gy(tc)
        _ = addBox(parent: world, name: "tourist-plaza", size: SIMD3<Float>(26, 0.07, 64), position: SIMD3<Float>(plaza.x, plazaY + 0.035, plaza.z), material: concreteMaterial, orientation: yaw(tc))
        let rotary = gp(59_905, land * 21)
        let rotaryDisc = ModelEntity(mesh: FallbackCylinderMesh.make(height: 0.09, radius: 10.5), materials: [roadMaterial])
        rotaryDisc.name = "tourist-rotary"
        rotaryDisc.position = SIMD3<Float>(rotary.x, plazaY + 0.045, rotary.z)
        world.addChild(rotaryDisc)
        // Gateway station house: timber-framed white hall, tiled
        // roof, clock tower.
        let hall = gp(tc, land * 15.5)
        _ = addBox(parent: world, name: "tourist-station-hall", size: SIMD3<Float>(10.5, 7.6, 21), position: SIMD3<Float>(hall.x, plazaY + 3.8, hall.z), material: whiteMat, orientation: yaw(tc))
        for beamZ: Float in [-9.5, -4.75, 0, 4.75, 9.5] {
            let bp = gp(tc + Double(beamZ), land * 10.1)
            _ = addBox(parent: world, name: "tourist-station-beam", size: SIMD3<Float>(0.35, 7.6, 0.35), position: SIMD3<Float>(bp.x, plazaY + 3.8, bp.z), material: timberMat, orientation: yaw(tc))
        }
        let roofP = gp(tc, land * 15.5)
        _ = addBox(parent: world, name: "tourist-station-roof", size: SIMD3<Float>(12.5, 0.4, 23), position: SIMD3<Float>(roofP.x, plazaY + 7.85, roofP.z), material: roofMat, orientation: yaw(tc))
        let towerP = gp(tc, land * 15.5)
        _ = addBox(parent: world, name: "tourist-clock-tower", size: SIMD3<Float>(2.4, 4.6, 2.4), position: SIMD3<Float>(towerP.x, plazaY + 10.2, towerP.z), material: timberMat, orientation: yaw(tc))
        let clockFace = gp(tc, land * 13.9)
        let clock = ModelEntity(mesh: FallbackCylinderMesh.make(height: 0.12, radius: 0.85), materials: [whiteMat])
        clock.name = "tourist-clock"
        clock.position = SIMD3<Float>(clockFace.x, plazaY + 11.0, clockFace.z)
        clock.orientation = yaw(tc) * simd_quatf(angle: Float.pi / 2, axis: SIMD3<Float>(0, 0, 1))
        world.addChild(clock)
        let signP = gp(tc, land * 10.0)
        _ = addBox(parent: world, name: "tourist-station-sign", size: SIMD3<Float>(0.25, 1.15, 8.0), position: SIMD3<Float>(signP.x, plazaY + 6.6, signP.z), material: whiteMat, orientation: yaw(tc))
        let logoP = gp(tc, land * 9.8)
        let logo = ModelEntity(mesh: FallbackCylinderMesh.make(height: 0.14, radius: 0.42), materials: [flagMats[0]])
        logo.name = "tourist-station-logo"
        logo.position = SIMD3<Float>(logoP.x, plazaY + 6.6, logoP.z)
        logo.orientation = yaw(tc) * simd_quatf(angle: Float.pi / 2, axis: SIMD3<Float>(0, 0, 1))
        world.addChild(logo)
        // Souvenir-shop row along the plaza.
        for i in 0..<4 {
            let c = 59_862.0 + Double(i) * 17
            let p = gp(c, land * 30)
            let y = gy(c)
            _ = addBox(parent: world, name: "tourist-shop-\(i)", size: SIMD3<Float>(6.5, 4.6, 8), position: SIMD3<Float>(p.x, y + 2.3, p.z), material: i % 2 == 0 ? shopFacadeMaterial : cafeFacadeMaterial, orientation: yaw(c))
            let sp = gp(c, land * 26.5)
            _ = addBox(parent: world, name: "tourist-shop-awning-\(i)", size: SIMD3<Float>(2.6, 0.15, 7.6), position: SIMD3<Float>(sp.x, y + 3.4, sp.z), material: flagMats[(i + 1) % flagMats.count], orientation: yaw(c))
        }
        // Ryokan blocks behind the shops, with timber balconies.
        for (i, c) in [59_880.0, 59_960.0].enumerated() {
            let p = gp(c, land * 44)
            let y = gy(c)
            _ = addBox(parent: world, name: "tourist-ryokan-\(i)", size: SIMD3<Float>(14, 12.5, 18), position: SIMD3<Float>(p.x, y + 6.25, p.z), material: officeMaterials[(i * 7 + 8) % officeMaterials.count], orientation: yaw(c))
            for floor in 0..<3 {
                let bp = gp(c, land * 36.6)
                _ = addBox(parent: world, name: "tourist-ryokan-balcony-\(i)-\(floor)", size: SIMD3<Float>(0.9, 0.18, 17), position: SIMD3<Float>(bp.x, y + 3.4 + Float(floor) * 3.6, bp.z), material: timberMat, orientation: yaw(c))
            }
        }
        // Foot bath at the plaza corner.
        let bath = gp(59_870, land * 13)
        _ = addBox(parent: world, name: "tourist-footbath", size: SIMD3<Float>(2.4, 0.55, 3.6), position: SIMD3<Float>(bath.x, plazaY + 0.28, bath.z), material: concreteMaterial, orientation: yaw(59_870))
        _ = addBox(parent: world, name: "tourist-footbath-water", size: SIMD3<Float>(1.9, 0.06, 3.1), position: SIMD3<Float>(bath.x, plazaY + 0.56, bath.z), material: Self.pbr(UIColor(red: 0.45, green: 0.68, blue: 0.78, alpha: 1), metallic: 0.1, roughness: 0.15), orientation: yaw(59_870))
        // Tour buses at the rotary.
        for (i, c) in [59_885.0, 59_928.0].enumerated() {
            let p = gp(c, land * 17.5)
            let busMat = Self.pbr(i == 0 ? UIColor(red: 0.88, green: 0.90, blue: 0.92, alpha: 1) : UIColor(red: 0.15, green: 0.50, blue: 0.55, alpha: 1), metallic: 0.2, roughness: 0.4)
            _ = addBox(parent: world, name: "tourist-bus-\(i)", size: SIMD3<Float>(2.5, 2.5, 10.6), position: SIMD3<Float>(p.x, plazaY + 1.55, p.z), material: busMat, orientation: yaw(c))
            _ = addBox(parent: world, name: "tourist-bus-glass-\(i)", size: SIMD3<Float>(2.54, 0.85, 9.6), position: SIMD3<Float>(p.x, plazaY + 2.15, p.z), material: glassMaterial, orientation: yaw(c))
            _ = addBox(parent: world, name: "tourist-bus-skirt-\(i)", size: SIMD3<Float>(2.54, 0.5, 10.2), position: SIMD3<Float>(p.x, plazaY + 0.42, p.z), material: roofMat, orientation: yaw(c))
        }
        // Sea-side promenade + lighthouse.
        let deck = gp(59_820, seaSide * 17)
        let deckY = gy(59_820)
        _ = addBox(parent: world, name: "tourist-promenade", size: SIMD3<Float>(9, 0.09, 130), position: SIMD3<Float>(deck.x, deckY + 0.045, deck.z), material: timberMat, orientation: yaw(59_820))
        let lightP = gp(59_760, seaSide * 24)
        let lighthouse = ModelEntity(mesh: FallbackCylinderMesh.make(height: 9.5, radius: 1.35), materials: [whiteMat])
        lighthouse.name = "tourist-lighthouse"
        lighthouse.position = SIMD3<Float>(lightP.x, deckY + 4.75, lightP.z)
        world.addChild(lighthouse)
        let lightRoom = ModelEntity(mesh: FallbackCylinderMesh.make(height: 1.5, radius: 0.95), materials: [glassMaterial])
        lightRoom.name = "tourist-lighthouse-lamp"
        lightRoom.position = SIMD3<Float>(lightP.x, deckY + 10.2, lightP.z)
        world.addChild(lightRoom)
        _ = addBox(parent: world, name: "tourist-lighthouse-band", size: SIMD3<Float>(2.78, 1.1, 2.78), position: SIMD3<Float>(lightP.x, deckY + 6.4, lightP.z), material: flagMats[0], orientation: yaw(59_760))
        // Tourists strolling the plaza and the promenade.
        for v in 0..<5 {
            let c = 59_880.0 + Double(v) * 26
            let home = gp(c, land * (19 + Float(v % 3) * 2.2))
            let s = sample(at: travelD(c))
            let axis = SIMD3<Float>(sin(s.heading), 0, -cos(s.heading))
            addPerson(position: home, yaw: atan2(axis.x, -axis.z), role: 3, mode: 1, routeDistanceM: travelD(c), walkAxis: axis, range: 13, seedKey: "tourist-plaza-\(v)")
        }
        for v in 0..<2 {
            let home = gp(59_800 + Double(v) * 60, seaSide * 17)
            let s = sample(at: travelD(59_800 + Double(v) * 60))
            let axis = SIMD3<Float>(sin(s.heading), 0, -cos(s.heading))
            addPerson(position: home, yaw: atan2(axis.x, -axis.z), role: 3, mode: 1, routeDistanceM: travelD(59_800 + Double(v) * 60), walkAxis: axis, range: 16, seedKey: "tourist-deck-\(v)")
        }
    }

    /// Schools and hospitals (quality41 final): the public
    /// buildings the gap analyses kept flagging as missing. Schools
    /// sit in the suburbs with a sandy yard and a gymnasium block;
    /// hospitals stand taller with a red-cross sign board proud of
    /// the track-side face and an entrance canopy.
    private func buildPublicBuildings(route: RailwayRouteProfile, routeVariant: RegionalRouteVariant) {
        guard routeVariant == .mainline || routeVariant == .throughBranch else { return }
        let schoolSites: [(Double, Float)] = [(7_400, 1), (16_200, -1), (33_800, 1), (47_300, -1), (63_500, 1)]
        let hospitalSites: [(Double, Float)] = [(11_300, -1), (25_600, 1), (42_900, -1)]
        func yawAt(_ d: Double) -> simd_quatf { simd_quatf(angle: -sample(at: d).heading, axis: SIMD3<Float>(0, 1, 0)) }
        let gymMaterial = Self.pbr(UIColor(red: 0.78, green: 0.76, blue: 0.72, alpha: 1), roughness: 0.9)
        let sandMaterial = Self.pbr(UIColor(red: 0.80, green: 0.72, blue: 0.55, alpha: 1), roughness: 1.0)
        for (d, side) in schoolSites where d < route.distanceM - 300 {
            let gy = groundLevelM(at: d)
            let yaw = yawAt(d)
            for half in [-1, 1] {
                let p = groundOffsetPoint(sample(at: d + Double(half) * 6.7), lateral: side * 27)
                _ = addBox(parent: world, name: "school-a-\(Int(d))", size: SIMD3<Float>(13, 9, 12.6), position: SIMD3<Float>(p.x, gy + 4.5, p.z), material: schoolFacadeMaterial, orientation: yaw)
            }
            let yard = groundOffsetPoint(sample(at: d), lateral: side * 47)
            _ = addBox(parent: world, name: "school-b-\(Int(d))", size: SIMD3<Float>(19, 0.08, 26), position: SIMD3<Float>(yard.x, gy + 0.04, yard.z), material: sandMaterial, orientation: yaw)
            let gym = groundOffsetPoint(sample(at: d + 19), lateral: side * 28)
            _ = addBox(parent: world, name: "school-yard-\(Int(d))", size: SIMD3<Float>(11, 7.5, 16), position: SIMD3<Float>(gym.x, gy + 3.75, gym.z), material: gymMaterial, orientation: yaw)
        }
        for (d, side) in hospitalSites where d < route.distanceM - 300 {
            let gy = groundLevelM(at: d)
            let yaw = yawAt(d)
            let p = groundOffsetPoint(sample(at: d), lateral: side * 30)
            _ = addBox(parent: world, name: "school-gym-\(Int(d))", size: SIMD3<Float>(15, 25, 19), position: SIMD3<Float>(p.x, gy + 12.5, p.z), material: hospitalFacadeMaterial, orientation: yaw)
            let signP = groundOffsetPoint(sample(at: d), lateral: side * 22.2)
            _ = addBox(parent: world, name: "hospital-main-\(Int(d))", size: SIMD3<Float>(0.3, 3.2, 3.2), position: SIMD3<Float>(signP.x, gy + 21.5, signP.z), material: Self.pbr(.white, roughness: 0.6), orientation: yaw)
            let crossMat = Self.pbr(UIColor(red: 0.81, green: 0.15, blue: 0.13, alpha: 1), roughness: 0.6)
            _ = addBox(parent: world, name: "hospital-sign-\(Int(d))", size: SIMD3<Float>(0.34, 1.9, 0.55), position: SIMD3<Float>(signP.x, gy + 21.5, signP.z), material: crossMat, orientation: yaw)
            _ = addBox(parent: world, name: "hospital-cross-v-\(Int(d))", size: SIMD3<Float>(0.34, 0.55, 1.9), position: SIMD3<Float>(signP.x, gy + 21.5, signP.z), material: crossMat, orientation: yaw)
            let canopy = groundOffsetPoint(sample(at: d), lateral: side * 21.5)
            _ = addBox(parent: world, name: "hospital-cross-h-\(Int(d))", size: SIMD3<Float>(3.2, 0.22, 8.5), position: SIMD3<Float>(canopy.x, gy + 3.1, canopy.z), material: Self.pbr(UIColor(red: 0.69, green: 0.71, blue: 0.73, alpha: 1), metallic: 0.3, roughness: 0.5), orientation: yaw)
        }
    }

    /// quality41: the two future branch lines from the user's
    /// 2026-11-10 concept, built as scenic lines in this batch
    /// (drivable route data is the follow-on step): the zoo
    /// line leaves at 50,150 for a hillside zoo with fenced
    /// paddocks and photographic animals, and the theme park
    /// line leaves at 55,500 for a park with a ferris wheel, a
    /// roller coaster and fairy-tale buildings.
    private func buildZooAndPark(routeVariant: RegionalRouteVariant, travelDirection: RegionalTravelDirection) {
        guard routeVariant == .mainline || routeVariant == .throughBranch else { return }
        guard let first = samples.first, let last = samples.last, first.distanceM <= 50_150, last.distanceM >= 57_200 else { return }
        let sideSign: Float = -seaSideSign(travelDirection: travelDirection)
        func cutout(_ texture: String) -> PhysicallyBasedMaterial {
            var m = Self.texturedPBR(.white, roughness: 0.9, textureName: texture)
            m.blending = .transparent(opacity: .init(floatLiteral: 1))
            m.faceCulling = .none
            return m
        }
        var chainlink = Self.texturedPBR(.white, metallic: 0.55, roughness: 0.45, textureName: "scenery_fence_chainlink")
        chainlink.blending = .transparent(opacity: .init(floatLiteral: 1))
        chainlink.faceCulling = .none
        let grassPad = Self.pbr(UIColor(red: 0.36, green: 0.48, blue: 0.27, alpha: 1), roughness: 1)

        // ---- The zoo line ----
        let zooJunction = 50_150.0
        let zooStations = buildScenicBranch(name: "zooline", junctionM: zooJunction, side: sideSign, lengthM: 2_300, reachM: 46, easeM: 550)
        func zooOffset(_ t: Double) -> Float {
            let u = min(max(t / 550, 0), 1)
            return 2.1 + 46 * Float(u * u * (3 - 2 * u))
        }
        // Zoo station platform at t = 1,150.
        let zooStationIndex = Int(1_150 / 8.5)
        var zooPlatformBatch = MeshBatchBuilder()
        for k in (zooStationIndex - 4)..<(zooStationIndex + 4) where zooStations.indices.contains(k) {
            let st = zooStations[k]
            zooPlatformBatch.addBoxAxes(center: st.center + st.xAxis * (sideSign * 3.4) + st.yAxis * 0.5,
                                        size: SIMD3<Float>(2.8, 1.0, 8.6), ax: st.xAxis, ay: st.yAxis, az: -simd_cross(st.xAxis, st.yAxis))
        }
        if let platform = zooPlatformBatch.build(name: "zoo-platform", material: concreteMaterial) { world.addChild(platform) }
        let zooHouse = groundOffsetPoint(self.sample(at: zooJunction + 1_150), lateral: sideSign * (zooOffset(1_150) + 10))
        _ = addBox(parent: world, name: "zoo-station-house", size: SIMD3<Float>(9, 5.5, 13), position: SIMD3<Float>(zooHouse.x, zooHouse.y + 2.75, zooHouse.z), material: houseFacadeMaterial5, orientation: simd_quatf(angle: -self.sample(at: zooJunction + 1_150).heading, axis: SIMD3<Float>(0, 1, 0)))
        // Paddocks with animals.
        let animalMaterials: [String: PhysicallyBasedMaterial] = [
            "elephant": cutout("scenery_zoo_elephant"),
            "giraffe": cutout("scenery_zoo_giraffe"),
            "zebra": cutout("scenery_zoo_zebra"),
            "lion": cutout("scenery_zoo_lion"),
        ]
        let animalSizes: [String: Float] = ["elephant": 4.65, "giraffe": 5.3, "zebra": 2.16, "lion": 1.60]
        let paddocks: [(t: Double, species: [String])] = [
            (620, ["elephant", "zebra"]), (1_020, ["giraffe", "zebra"]),
            (1_420, ["lion", "elephant"]), (1_820, ["giraffe", "lion"]),
        ]
        for (paddockIndex, paddock) in paddocks.enumerated() {
            let centerD = zooJunction + paddock.t
            let centerLat = sideSign * (zooOffset(paddock.t) + 30)
            let centerSample = self.sample(at: centerD)
            let groundY = groundLevelM(at: centerSample)
            let yaw = simd_quatf(angle: -centerSample.heading, axis: SIMD3<Float>(0, 1, 0))
            let c = groundOffsetPoint(centerSample, lateral: centerLat)
            _ = addBox(parent: world, name: "zoo-pad-\(paddockIndex)", size: SIMD3<Float>(40, 0.1, 32), position: SIMD3<Float>(c.x, groundY + 0.05, c.z), material: grassPad, orientation: yaw)
            for fenceSide in [-1.0, 1.0] {
                let fp = groundOffsetPoint(centerSample, lateral: centerLat + sideSign * Float(fenceSide) * 20)
                _ = addBox(parent: world, name: "zoo-fence-along-\(paddockIndex)-\(Int(fenceSide))", size: SIMD3<Float>(0.06, 2.2, 32), position: SIMD3<Float>(fp.x, groundY + 1.1, fp.z), material: chainlink, orientation: yaw)
                let cp = groundOffsetPoint(self.sample(at: centerD + fenceSide * 16), lateral: centerLat)
                _ = addBox(parent: world, name: "zoo-fence-cross-\(paddockIndex)-\(Int(fenceSide))", size: SIMD3<Float>(40, 2.2, 0.06), position: SIMD3<Float>(cp.x, groundY + 1.1, cp.z), material: chainlink, orientation: yaw)
            }
            for (animalIndex, species) in paddock.species.enumerated() {
                guard let material = animalMaterials[species], let size = animalSizes[species] else { continue }
                let aSample = self.sample(at: centerD + Double(animalIndex * 7 - 4))
                let aPoint = groundOffsetPoint(aSample, lateral: centerLat + sideSign * Float(animalIndex * 6 - 3))
                for cross in 0..<2 {
                    let board = ModelEntity(mesh: MeshResource.generatePlane(width: size, depth: size), materials: [material])
                    let yawQ = simd_quatf(angle: -aSample.heading + Float(cross) * Float.pi / 2 + Float(paddockIndex) * 0.35, axis: SIMD3<Float>(0, 1, 0))
                    let q = yawQ * simd_quatf(angle: -Float.pi / 2, axis: SIMD3<Float>(1, 0, 0))
                    board.orientation = q
                    board.position = SIMD3<Float>(aPoint.x, groundY + size / 2 - 0.04, aPoint.z)
                    board.name = "zoo-animal-\(species)-\(paddockIndex)-\(animalIndex)-\(cross)"
                    world.addChild(board)
                }
            }
            addTree(parent: world, name: "zoo-tree-\(paddockIndex)", x: c.x + 9, z: c.z - 7, height: 6.5, material: foliageMaterials[paddockIndex % foliageMaterials.count], groundY: groundY)
        }

        // ---- The theme park line ----
        let parkJunction = 55_500.0
        let parkStations = buildScenicBranch(name: "parkline", junctionM: parkJunction, side: sideSign, lengthM: 1_700, reachM: 105, easeM: 900)
        func parkOffset(_ t: Double) -> Float {
            let u = min(max(t / 900, 0), 1)
            return 2.1 + 105 * Float(u * u * (3 - 2 * u))
        }
        let parkStationIndex = Int(780 / 8.5)
        var parkPlatformBatch = MeshBatchBuilder()
        for k in (parkStationIndex - 4)..<(parkStationIndex + 4) where parkStations.indices.contains(k) {
            let st = parkStations[k]
            parkPlatformBatch.addBoxAxes(center: st.center + st.xAxis * (sideSign * 3.4) + st.yAxis * 0.5,
                                         size: SIMD3<Float>(2.8, 1.0, 8.6), ax: st.xAxis, ay: st.yAxis, az: -simd_cross(st.xAxis, st.yAxis))
        }
        if let platform = parkPlatformBatch.build(name: "park-platform", material: concreteMaterial) { world.addChild(platform) }
        // Park ground, wheel and coaster share one frame.
        let parkD = parkJunction + 1_150
        let parkLat = sideSign * (parkOffset(1_150) + 80)
        let parkSample = self.sample(at: parkD)
        let parkGroundY = groundLevelM(at: parkSample)
        let parkFrame = profileStation(at: parkD, trackLateral: parkLat)
        let parkCenter = SIMD3<Float>(parkFrame.center.x, parkGroundY, parkFrame.center.z)
        let xAxis = parkFrame.xAxis
        let tangent = -simd_cross(parkFrame.xAxis, parkFrame.yAxis)
        let parkYaw = simd_quatf(angle: -parkSample.heading, axis: SIMD3<Float>(0, 1, 0))
        _ = addBox(parent: world, name: "park-plaza", size: SIMD3<Float>(130, 0.09, 100), position: SIMD3<Float>(parkCenter.x, parkGroundY + 0.045, parkCenter.z), material: concreteMaterial, orientation: parkYaw)
        let pastels: [UIColor] = [
            UIColor(red: 0.96, green: 0.78, blue: 0.83, alpha: 1),
            UIColor(red: 0.98, green: 0.93, blue: 0.80, alpha: 1),
            UIColor(red: 0.78, green: 0.90, blue: 0.82, alpha: 1),
            UIColor(red: 0.82, green: 0.84, blue: 0.96, alpha: 1),
        ]
        // Ferris wheel: rim segments, spokes, legs, gondolas.
        let wheelCenter = parkCenter + tangent * 18 + SIMD3<Float>(0, 30, 0)
        let wheelMaterial = Self.pbr(UIColor(red: 0.94, green: 0.95, blue: 0.96, alpha: 1), metallic: 0.4, roughness: 0.4)
        var spokeBatch = MeshBatchBuilder()
        for spoke in 0..<8 {
            let a = Float(spoke) * Float.pi / 4
            let rimPoint = wheelCenter + (xAxis * cos(a) + SIMD3<Float>(0, 1, 0) * sin(a)) * 28
            spokeBatch.addSegment(from: wheelCenter, to: rimPoint, thickness: 0.16)
        }
        for legSide in [-1.0, 1.0] {
            let foot = parkCenter + tangent * 18 + xAxis * Float(legSide * 11)
            spokeBatch.addSegment(from: wheelCenter, to: SIMD3<Float>(foot.x, parkGroundY, foot.z), thickness: 0.55)
        }
        if let spokes = spokeBatch.build(name: "park-wheel-spokes", material: poleMaterial) { world.addChild(spokes) }
        var rimBatch = MeshBatchBuilder()
        for segment in 0..<28 {
            let a = Float(segment) / 28 * Float.pi * 2
            let radial = xAxis * cos(a) + SIMD3<Float>(0, 1, 0) * sin(a)
            let tang = -xAxis * sin(a) + SIMD3<Float>(0, 1, 0) * cos(a)
            rimBatch.addBoxAxes(center: wheelCenter + radial * 28, size: SIMD3<Float>(0.4, 6.35, 0.5), ax: radial, ay: tang, az: tangent)
        }
        if let rim = rimBatch.build(name: "park-wheel-rim", material: wheelMaterial) { world.addChild(rim) }
        for gondola in 0..<12 {
            let a = Float(gondola) / 12 * Float.pi * 2
            let radial = xAxis * cos(a) + SIMD3<Float>(0, 1, 0) * sin(a)
            let gp = wheelCenter + radial * 28
            _ = addBox(parent: world, name: "park-gondola-\(gondola)", size: SIMD3<Float>(1.7, 1.8, 1.7),
                       position: SIMD3<Float>(gp.x, gp.y - 1.8, gp.z), material: Self.pbr(pastels[gondola % pastels.count], roughness: 0.5), orientation: parkYaw)
        }
        _ = addBox(parent: world, name: "park-wheel-hub", size: SIMD3<Float>(1.4, 1.4, 2.4), position: wheelCenter, material: wheelMaterial, orientation: parkYaw)
        // Roller coaster: a closed ellipse with two hills.
        let coasterOrigin = parkCenter - tangent * 34 - xAxis * (sideSign * 6)
        var coasterStations: [ProfileStation] = []
        var coasterPoints: [SIMD3<Float>] = []
        let coasterN = 40
        for i in 0...coasterN {
            let theta = Double(i) / Double(coasterN) * Double.pi * 2
            let along = Float(cos(theta)) * 56
            let lat = Float(sin(theta)) * 34
            let hill = 7 + 15 * Float(pow(max(sin(theta + 0.6), 0), 1.4)) + 5 * Float(max(sin(2 * theta), 0))
            coasterPoints.append(coasterOrigin + tangent * along + xAxis * lat + SIMD3<Float>(0, hill, 0))
        }
        for i in 0...coasterN {
            let prev = coasterPoints[(i + coasterN - 1) % coasterN]
            let next = coasterPoints[(i + 1) % coasterN]
            let tan = simd_normalize(next - prev)
            var xA = simd_cross(SIMD3<Float>(0, 1, 0), tan)
            xA = simd_length(xA) > 0.001 ? simd_normalize(xA) : xAxis
            let yA = simd_normalize(simd_cross(xA, tan))
            coasterStations.append(ProfileStation(center: coasterPoints[i], xAxis: xA, yAxis: yA, distanceM: Double(i)))
        }
        let coasterMaterial = Self.pbr(UIColor(red: 0.30, green: 0.48, blue: 0.78, alpha: 1), metallic: 0.5, roughness: 0.45)
        if let track = profileStripEntity(name: "park-coaster-track", stations: Array(coasterStations.dropLast()), profile: [(-0.8, 0), (0.8, 0)], closed: true, material: coasterMaterial) { world.addChild(track) }
        for i in stride(from: 0, to: coasterN, by: 3) {
            let p = coasterPoints[i]
            let h = p.y - parkGroundY
            _ = addBox(parent: world, name: "park-coaster-support-\(i)", size: SIMD3<Float>(0.55, h, 0.55), position: SIMD3<Float>(p.x, parkGroundY + h / 2, p.z), material: concreteMaterial)
        }
        // Fairy-tale buildings and the castle.
        let fairySpots: [(along: Float, lat: Float, w: Float, h: Float, d: Float)] = [
            (-38, -30, 10, 7, 9), (34, -34, 11, 8, 9), (44, 22, 9, 6.5, 8),
        ]
        for (fairyIndex, spot) in fairySpots.enumerated() {
            let base = parkCenter + tangent * spot.along + xAxis * spot.lat
            let material = Self.pbr(pastels[fairyIndex % pastels.count], roughness: 0.8)
            _ = addBox(parent: world, name: "park-fairy-\(fairyIndex)", size: SIMD3<Float>(spot.w, spot.h, spot.d), position: SIMD3<Float>(base.x, parkGroundY + spot.h / 2, base.z), material: material, orientation: parkYaw)
            let roof = addBox(parent: world, name: "park-fairy-roof-\(fairyIndex)", size: SIMD3<Float>(spot.w * 0.78, spot.w * 0.78, spot.d + 0.4), position: SIMD3<Float>(base.x, parkGroundY + spot.h + spot.w * 0.24, base.z), material: Self.pbr(pastels[(fairyIndex + 1) % pastels.count], roughness: 0.7), orientation: parkYaw)
            roof.orientation = roof.orientation * simd_quatf(angle: Float.pi / 4, axis: SIMD3<Float>(0, 0, 1))
        }
        let castleBase = parkCenter + tangent * -6 + xAxis * (sideSign * 40)
        _ = addBox(parent: world, name: "park-castle", size: SIMD3<Float>(11, 19, 11), position: SIMD3<Float>(castleBase.x, parkGroundY + 9.5, castleBase.z), material: Self.pbr(pastels[1], roughness: 0.8), orientation: parkYaw)
        for turret in 0..<4 {
            let tx = (turret % 2 == 0 ? -5.5 : 5.5) as Float
            let tz = (turret < 2 ? -5.5 : 5.5) as Float
            let tp = castleBase + xAxis * tx + tangent * tz
            _ = addBox(parent: world, name: "park-castle-turret-\(turret)", size: SIMD3<Float>(2.4, 24, 2.4), position: SIMD3<Float>(tp.x, parkGroundY + 12, tp.z), material: Self.pbr(pastels[0], roughness: 0.8), orientation: parkYaw)
        }
        let castleRoof = addBox(parent: world, name: "park-castle-roof", size: SIMD3<Float>(8.6, 8.6, 11.4), position: SIMD3<Float>(castleBase.x, parkGroundY + 19 + 2.1, castleBase.z), material: Self.pbr(pastels[3], roughness: 0.7), orientation: parkYaw)
        castleRoof.orientation = castleRoof.orientation * simd_quatf(angle: Float.pi / 4, axis: SIMD3<Float>(0, 0, 1))
    }

    // MARK: - Zoo line (quality41 expansion)

    private func zooPart(_ mesh: MeshResource, _ material: PhysicallyBasedMaterial, _ position: SIMD3<Float>, name: String) -> Entity {
        let entity = ModelEntity(mesh: mesh, materials: [material])
        entity.name = name
        entity.position = position
        return entity
    }

    /// Builds one articulated animal under a fresh root entity. The
    /// caller positions the root inside its paddock and fills the
    /// rig's route/paddock fields. Local frame: forward is -Z, the
    /// ground is y = 0. Animals are part-built volumes (body, head,
    /// neck, legs, tail, trunk), never flat boards.
    private func makeZooAnimal(species: Int, mane: Bool) -> ZooAnimalRig {
        let root = Entity()
        root.name = "zoo-animal-\(species)"
        var legs: [Entity] = []
        var trunk: [Entity] = []
        var neckPivot: Entity? = nil
        let body: Entity
        let headPivot: Entity
        let tailPivot: Entity
        let standY: Float
        let restY: Float

        if species == 5 {
            // Penguin: a single rounded body with belly, beak and
            // flippers; it waddles instead of swinging legs.
            let black = Self.pbr(UIColor(red: 0.10, green: 0.10, blue: 0.12, alpha: 1), roughness: 0.9)
            let white = Self.pbr(UIColor(red: 0.93, green: 0.93, blue: 0.90, alpha: 1), roughness: 0.9)
            let orange = Self.pbr(UIColor(red: 0.90, green: 0.55, blue: 0.15, alpha: 1), roughness: 0.8)
            body = zooPart(MeshResource.generateSphere(radius: 1), black, SIMD3<Float>(0, 0.40, 0), name: "penguin-body")
            body.scale = SIMD3<Float>(0.30, 0.40, 0.27)
            root.addChild(body)
            let belly = zooPart(MeshResource.generateSphere(radius: 1), white, SIMD3<Float>(0, 0.36, -0.155), name: "penguin-belly")
            belly.scale = SIMD3<Float>(0.20, 0.29, 0.10)
            root.addChild(belly)
            let headBall = zooPart(MeshResource.generateSphere(radius: 0.155), black, SIMD3<Float>(0, 0.70, -0.02), name: "penguin-head")
            root.addChild(headBall)
            headPivot = Entity()
            headPivot.position = SIMD3<Float>(0, 0.70, -0.02)
            let beak = zooPart(MeshResource.generateBox(size: SIMD3<Float>(0.05, 0.03, 0.11), cornerRadius: 0.01), orange, SIMD3<Float>(0, -0.02, -0.17), name: "penguin-beak")
            headPivot.addChild(beak)
            root.addChild(headPivot)
            for side: Float in [-1.0, 1.0] {
                let flipper = zooPart(MeshResource.generateBox(size: SIMD3<Float>(0.05, 0.34, 0.15), cornerRadius: 0.02), black, SIMD3<Float>(side * 0.30, 0.42, 0.01), name: "penguin-flipper")
                flipper.orientation = simd_quatf(angle: side * -0.28, axis: SIMD3<Float>(0, 0, 1))
                root.addChild(flipper)
                let foot = zooPart(MeshResource.generateBox(size: SIMD3<Float>(0.09, 0.03, 0.15), cornerRadius: 0.01), orange, SIMD3<Float>(side * 0.09, 0.02, -0.05), name: "penguin-foot")
                root.addChild(foot)
            }
            tailPivot = Entity()
            root.addChild(tailPivot)
            standY = 0
            restY = 0
            return ZooAnimalRig(root: root, body: body, headPivot: headPivot, neckPivot: nil, trunkPivots: [],
                                legs: [], tailPivot: tailPivot, species: species, routeDistanceM: 0,
                                paddockCenter: .zero, axisX: SIMD3<Float>(1, 0, 0), axisZ: SIMD3<Float>(0, 0, 1),
                                heading: 0, walkTarget: .zero, rngState: 0x9E37_79B9, bodyStandY: standY, bodyRestY: restY)
        }

        // Quadruped dimensions per species (metres, from real animals).
        let legLen: Float, legR: Float, bodySize: SIMD3<Float>, headLen: Float
        let coat: PhysicallyBasedMaterial
        switch species {
        case 0: // lion
            legLen = 0.62; legR = 0.055; bodySize = SIMD3<Float>(0.55, 0.60, 1.70); headLen = 0.42
            coat = Self.pbr(UIColor(red: 0.78, green: 0.62, blue: 0.40, alpha: 1), roughness: 0.95)
        case 1: // tiger
            legLen = 0.60; legR = 0.055; bodySize = SIMD3<Float>(0.52, 0.58, 1.65); headLen = 0.40
            coat = Self.texturedPBR(.white, roughness: 0.95, textureName: "scenery_zoo_coat_tiger")
        case 2: // giraffe
            legLen = 1.72; legR = 0.06; bodySize = SIMD3<Float>(0.60, 0.72, 1.85); headLen = 0.52
            coat = Self.texturedPBR(.white, roughness: 0.95, textureName: "scenery_zoo_coat_giraffe")
        case 3: // elephant
            legLen = 1.22; legR = 0.15; bodySize = SIMD3<Float>(1.55, 1.65, 2.90); headLen = 0.70
            coat = Self.texturedPBR(.white, roughness: 0.95, textureName: "scenery_zoo_coat_giraffe")
        default: // zebra
            legLen = 0.80; legR = 0.045; bodySize = SIMD3<Float>(0.50, 0.58, 1.75); headLen = 0.48
            coat = Self.texturedPBR(.white, roughness: 0.95, textureName: "scenery_zoo_coat_zebra")
        }
        let bodyY = legLen + bodySize.y / 2
        if species == 3 {
            // Elephant body is an ellipsoid, not a box.
            body = zooPart(MeshResource.generateSphere(radius: 1), Self.pbr(UIColor(red: 0.52, green: 0.50, blue: 0.48, alpha: 1), roughness: 0.95), SIMD3<Float>(0, bodyY, 0), name: "elephant-body")
            body.scale = SIMD3<Float>(bodySize.x / 2, bodySize.y / 2, bodySize.z / 2)
        } else {
            body = zooPart(MeshResource.generateBox(size: bodySize, cornerRadius: min(bodySize.x, bodySize.y) * 0.32), coat, SIMD3<Float>(0, bodyY, 0), name: "animal-body")
        }
        root.addChild(body)
        standY = bodyY
        restY = legLen * 0.35 + bodySize.y / 2

        // Legs on hip pivots so they can swing and fold.
        for corner in 0..<4 {
            let sx: Float = corner % 2 == 0 ? -1 : 1
            let sz: Float = corner < 2 ? -1 : 1
            let hip = Entity()
            hip.name = "leg-\(corner)"
            hip.position = SIMD3<Float>(sx * (bodySize.x / 2 - 0.07), legLen, sz * (bodySize.z / 2 - 0.30))
            let legMesh = zooPart(FallbackCylinderMesh.make(height: legLen, radius: legR), species == 3 ? Self.pbr(UIColor(red: 0.52, green: 0.50, blue: 0.48, alpha: 1), roughness: 0.95) : coat, SIMD3<Float>(0, -legLen / 2 + 0.02, 0), name: "leg-mesh")
            hip.addChild(legMesh)
            root.addChild(hip)
            legs.append(hip)
        }

        // Neck and head.
        let headMat = species == 3 ? Self.pbr(UIColor(red: 0.52, green: 0.50, blue: 0.48, alpha: 1), roughness: 0.95) : coat
        if species == 2 {
            let neck = Entity()
            neck.name = "giraffe-neck"
            neck.position = SIMD3<Float>(0, bodyY + 0.24, -bodySize.z / 2 + 0.10)
            neck.orientation = simd_quatf(angle: 0.42, axis: SIMD3<Float>(1, 0, 0))
            let neckMesh = zooPart(FallbackCylinderMesh.make(height: 1.5, radius: 0.115), coat, SIMD3<Float>(0, 0.72, -0.16), name: "giraffe-neck-mesh")
            neck.addChild(neckMesh)
            root.addChild(neck)
            neckPivot = neck
            headPivot = Entity()
            headPivot.position = SIMD3<Float>(0, 1.44, -0.34)
            let headMesh = zooPart(MeshResource.generateBox(size: SIMD3<Float>(0.20, 0.26, headLen), cornerRadius: 0.07), coat, SIMD3<Float>(0, 0.04, -headLen / 2), name: "giraffe-head")
            headPivot.addChild(headMesh)
            for side: Float in [-1.0, 1.0] {
                let horn = zooPart(FallbackCylinderMesh.make(height: 0.16, radius: 0.025), headMat, SIMD3<Float>(side * 0.06, 0.22, -0.10), name: "giraffe-ossicone")
                headPivot.addChild(horn)
            }
            neck.addChild(headPivot)
        } else if species == 3 {
            headPivot = Entity()
            headPivot.position = SIMD3<Float>(0, bodyY + 0.22, -bodySize.z / 2 + 0.05)
            let headMesh = zooPart(MeshResource.generateSphere(radius: 0.60), headMat, SIMD3<Float>(0, 0, -0.30), name: "elephant-head")
            headPivot.addChild(headMesh)
            for side: Float in [-1.0, 1.0] {
                let ear = zooPart(MeshResource.generateSphere(radius: 1), headMat, SIMD3<Float>(side * 0.55, 0.08, -0.12), name: "elephant-ear")
                ear.scale = SIMD3<Float>(0.10, 0.58, 0.48)
                headPivot.addChild(ear)
                let tusk = zooPart(FallbackCylinderMesh.make(height: 0.42, radius: 0.028), Self.pbr(.white, roughness: 0.5), SIMD3<Float>(side * 0.20, -0.42, -0.62), name: "elephant-tusk")
                tusk.orientation = simd_quatf(angle: 0.5, axis: SIMD3<Float>(1, 0, 0))
                headPivot.addChild(tusk)
            }
            // Trunk: three chained segments hanging from the head.
            var parent = headPivot
            var radius: Float = 0.105
            for segment in 0..<3 {
                let pivot = Entity()
                pivot.name = "trunk-\(segment)"
                pivot.position = segment == 0 ? SIMD3<Float>(0, -0.28, -0.78) : SIMD3<Float>(0, -0.52, -0.03)
                let mesh = zooPart(FallbackCylinderMesh.make(height: 0.55, radius: radius), headMat, SIMD3<Float>(0, -0.26, 0), name: "trunk-mesh")
                pivot.addChild(mesh)
                parent.addChild(pivot)
                trunk.append(pivot)
                parent = pivot
                radius -= 0.018
            }
            root.addChild(headPivot)
        } else {
            headPivot = Entity()
            headPivot.position = SIMD3<Float>(0, bodyY + bodySize.y / 2 - 0.10, -bodySize.z / 2 - 0.02)
            let headMesh = zooPart(MeshResource.generateBox(size: SIMD3<Float>(headLen * 0.52, headLen * 0.58, headLen), cornerRadius: headLen * 0.16), headMat, SIMD3<Float>(0, 0.02, -headLen / 2), name: "animal-head")
            headPivot.addChild(headMesh)
            if species == 0 && mane {
                let maneMesh = zooPart(MeshResource.generateSphere(radius: 0.30), Self.pbr(UIColor(red: 0.45, green: 0.32, blue: 0.18, alpha: 1), roughness: 1), SIMD3<Float>(0, 0.05, -0.10), name: "lion-mane")
                headPivot.addChild(maneMesh)
            }
            for side: Float in [-1.0, 1.0] {
                let ear = zooPart(MeshResource.generateBox(size: SIMD3<Float>(0.09, 0.11, 0.03), cornerRadius: 0.01), headMat, SIMD3<Float>(side * headLen * 0.20, headLen * 0.30, -0.06), name: "animal-ear")
                headPivot.addChild(ear)
            }
            if species == 4 {
                let maneStrip = zooPart(MeshResource.generateBox(size: SIMD3<Float>(0.05, 0.30, 0.95), cornerRadius: 0.01), Self.pbr(UIColor(red: 0.12, green: 0.11, blue: 0.11, alpha: 1), roughness: 1), SIMD3<Float>(0, legLen + bodySize.y + 0.06, -bodySize.z / 2 + 0.42), name: "zebra-mane")
                maneStrip.orientation = simd_quatf(angle: 0.35, axis: SIMD3<Float>(1, 0, 0))
                root.addChild(maneStrip)
            }
            root.addChild(headPivot)
        }

        // Tail on a pivot at the rear top of the body.
        tailPivot = Entity()
        tailPivot.position = SIMD3<Float>(0, bodyY + bodySize.y / 2 - 0.10, bodySize.z / 2 - 0.02)
        tailPivot.orientation = simd_quatf(angle: 0.30, axis: SIMD3<Float>(1, 0, 0))
        let tailLen: Float = species == 3 ? 1.0 : 0.78
        let tailMesh = zooPart(FallbackCylinderMesh.make(height: tailLen, radius: species == 3 ? 0.035 : 0.028), headMat, SIMD3<Float>(0, -tailLen / 2, 0), name: "animal-tail")
        tailPivot.addChild(tailMesh)
        if species == 0 {
            let tuft = zooPart(MeshResource.generateSphere(radius: 0.07), Self.pbr(UIColor(red: 0.30, green: 0.22, blue: 0.12, alpha: 1), roughness: 1), SIMD3<Float>(0, -tailLen, 0), name: "lion-tuft")
            tailPivot.addChild(tuft)
        }
        root.addChild(tailPivot)

        return ZooAnimalRig(root: root, body: body, headPivot: headPivot, neckPivot: neckPivot, trunkPivots: trunk,
                            legs: legs, tailPivot: tailPivot, species: species, routeDistanceM: 0,
                            paddockCenter: .zero, axisX: SIMD3<Float>(1, 0, 0), axisZ: SIMD3<Float>(0, 0, 1),
                            heading: 0, walkTarget: .zero, rngState: 0x9E37_79B9, bodyStandY: standY, bodyRestY: restY)
    }

    /// One volumetric enclosure: ground pad, chain-link cage (tall
    /// with a top rail for the big cats), visitor safety fence,
    /// rocks, a pond and shelter where the species wants them, an
    /// explanation panel facing the track, and the animals
    /// themselves, registered for animation.
    private func buildZooPaddock(centerM: Double, sideSign: Float, species: Int, count: Int, hasCage: Bool, travelDirection: RegionalTravelDirection) {
        let mid = sample(at: centerM)
        let yaw = simd_quatf(angle: -mid.heading, axis: SIMD3<Float>(0, 1, 0))
        func gp(_ d: Double, _ lateral: Float) -> SIMD3<Float> { groundOffsetPoint(sample(at: d), lateral: lateral) }
        let sandMat = Self.pbr(UIColor(red: 0.76, green: 0.68, blue: 0.52, alpha: 1), roughness: 1)
        let savannaMat = Self.pbr(UIColor(red: 0.60, green: 0.57, blue: 0.36, alpha: 1), roughness: 1)
        let gravelMat = Self.pbr(UIColor(red: 0.78, green: 0.78, blue: 0.76, alpha: 1), roughness: 1)
        let padMat = species == 5 ? gravelMat : (species == 0 || species == 1 ? sandMat : savannaMat)
        var padD = centerM - 21
        while padD <= centerM + 21 {
            let p = gp(padD, sideSign * 26)
            _ = addBox(parent: world, name: "zoo-pad-\(Int(centerM))-\(Int(padD))", size: SIMD3<Float>(31, 0.09, 15.4), position: SIMD3<Float>(p.x, p.y + 0.02, p.z), material: padMat, orientation: yaw)
            padD += 15
        }
        // Chain-link fences: track side, far side and both ends.
        var fenceMat = Self.texturedPBR(.white, metallic: 0.55, roughness: 0.45, textureName: "scenery_fence_chainlink")
        fenceMat.blending = .transparent(opacity: .init(floatLiteral: 1))
        fenceMat.faceCulling = .none
        let postMat = Self.pbr(UIColor(red: 0.35, green: 0.36, blue: 0.37, alpha: 1), metallic: 0.6, roughness: 0.5)
        let fenceH: Float = hasCage ? 3.0 : 1.7
        func fenceRun(from: Double, to: Double, lateral: Float) {
            var d = from
            while d < to {
                let seg = min(7.0, to - d)
                let p = gp(d + seg / 2, lateral)
                _ = addBox(parent: world, name: "zoo-fence-\(Int(centerM))", size: SIMD3<Float>(0.03, fenceH, Float(seg) + 0.05), position: SIMD3<Float>(p.x, p.y + fenceH / 2, p.z), material: fenceMat, orientation: yaw)
                let post = gp(d, lateral)
                _ = addBox(parent: world, name: "zoo-fence-post-\(Int(centerM))", size: SIMD3<Float>(0.09, fenceH + 0.1, 0.09), position: SIMD3<Float>(post.x, post.y + fenceH / 2, post.z), material: postMat, orientation: yaw)
                d += seg
            }
        }
        fenceRun(from: centerM - 21, to: centerM + 21, lateral: sideSign * 11)
        fenceRun(from: centerM - 21, to: centerM + 21, lateral: sideSign * 41)
        for endSign: Float in [-1.0, 1.0] {
            let endD = centerM + Double(endSign) * 21
            var lat = 11.0 as Double
            while lat < 41 {
                let seg = min(7.5, 41 - lat)
                let p = gp(endD, sideSign * Float(lat + seg / 2))
                _ = addBox(parent: world, name: "zoo-fence-end-\(Int(centerM))", size: SIMD3<Float>(Float(seg) + 0.05, fenceH, 0.03), position: SIMD3<Float>(p.x, p.y + fenceH / 2, p.z), material: fenceMat, orientation: yaw)
                lat += seg
            }
        }
        if hasCage {
            let top = gp(centerM, sideSign * 11)
            _ = addBox(parent: world, name: "zoo-cage-toprail-\(Int(centerM))", size: SIMD3<Float>(0.07, 0.07, 42.5), position: SIMD3<Float>(top.x, top.y + fenceH + 0.03, top.z), material: postMat, orientation: yaw)
        }
        // Visitor safety fence between the track and the enclosure.
        var postD = centerM - 21
        while postD <= centerM + 21 {
            let p = gp(postD, sideSign * 8.2)
            _ = addBox(parent: world, name: "zoo-guard-post-\(Int(centerM))", size: SIMD3<Float>(0.07, 1.1, 0.07), position: SIMD3<Float>(p.x, p.y + 0.55, p.z), material: postMat, orientation: yaw)
            postD += 3.5
        }
        for railY: Float in [0.62, 1.04] {
            let p = gp(centerM, sideSign * 8.2)
            _ = addBox(parent: world, name: "zoo-guard-rail-\(Int(centerM))", size: SIMD3<Float>(0.05, 0.05, 42.5), position: SIMD3<Float>(p.x, p.y + railY, p.z), material: postMat, orientation: yaw)
        }
        // Rocks, pond, shelter, feeder, tree.
        let rockMat = Self.pbr(UIColor(red: 0.55, green: 0.54, blue: 0.52, alpha: 1), roughness: 0.95)
        for rock in 0..<4 {
            let along = Double(stableIndex("zoorock-\(Int(centerM))-\(rock)", count: 25)) - 12
            let lat = 15 + Float(stableIndex("zoorocklat-\(Int(centerM))-\(rock)", count: 22))
            let p = gp(centerM + along, sideSign * lat)
            let r = 0.5 + Float(stableIndex("zoorockr-\(Int(centerM))-\(rock)", count: 10)) * 0.09
            let rockEntity = zooPart(MeshResource.generateSphere(radius: r), rockMat, SIMD3<Float>(p.x, p.y + r * 0.35, p.z), name: "zoo-rock")
            rockEntity.scale = SIMD3<Float>(1.25, 0.72, 1)
            world.addChild(rockEntity)
        }
        if species == 5 || species == 3 || species == 2 {
            let p = gp(centerM - 8, sideSign * 33)
            let pond = zooPart(FallbackCylinderMesh.make(height: 0.07, radius: species == 5 ? 3.4 : 2.7), Self.pbr(UIColor(red: 0.25, green: 0.45, blue: 0.62, alpha: 1), metallic: 0.1, roughness: 0.18), SIMD3<Float>(p.x, p.y + 0.06, p.z), name: "zoo-pond")
            world.addChild(pond)
        }
        let hut = gp(centerM + 13, sideSign * 36)
        _ = addBox(parent: world, name: "zoo-shelter-\(Int(centerM))", size: SIMD3<Float>(3.2, 2.3, 2.6), position: SIMD3<Float>(hut.x, hut.y + 1.15, hut.z), material: Self.pbr(UIColor(red: 0.45, green: 0.35, blue: 0.24, alpha: 1), roughness: 0.9), orientation: yaw)
        _ = addBox(parent: world, name: "zoo-shelter-roof-\(Int(centerM))", size: SIMD3<Float>(3.7, 0.12, 3.1), position: SIMD3<Float>(hut.x, hut.y + 2.42, hut.z), material: Self.pbr(UIColor(red: 0.30, green: 0.28, blue: 0.27, alpha: 1), roughness: 0.8), orientation: yaw)
        let feed = gp(centerM + 6, sideSign * 18)
        _ = addBox(parent: world, name: "zoo-feeder-\(Int(centerM))", size: SIMD3<Float>(1.4, 0.5, 0.6), position: SIMD3<Float>(feed.x, feed.y + 0.25, feed.z), material: postMat, orientation: yaw)
        _ = addBox(parent: world, name: "zoo-hay-\(Int(centerM))", size: SIMD3<Float>(1.2, 0.3, 0.45), position: SIMD3<Float>(feed.x, feed.y + 0.62, feed.z), material: Self.pbr(UIColor(red: 0.82, green: 0.72, blue: 0.38, alpha: 1), roughness: 1), orientation: yaw)
        buildZooTree(at: gp(centerM - 14, sideSign * 30), seed: Int(centerM))
        // Explanation panel facing the track.
        let panel = gp(centerM, sideSign * 9.4)
        _ = addBox(parent: world, name: "zoo-panel-\(Int(centerM))", size: SIMD3<Float>(1.3, 0.85, 0.05), position: SIMD3<Float>(panel.x, panel.y + 1.05, panel.z), material: Self.pbr(UIColor(red: 0.94, green: 0.93, blue: 0.88, alpha: 1), roughness: 0.6), orientation: yaw)
        _ = addBox(parent: world, name: "zoo-panel-stripe-\(Int(centerM))", size: SIMD3<Float>(1.3, 0.22, 0.055), position: SIMD3<Float>(panel.x, panel.y + 1.36, panel.z), material: Self.pbr(UIColor(red: 0.85, green: 0.45, blue: 0.15, alpha: 1), roughness: 0.6), orientation: yaw)
        // Visitors watching from behind the far fence (people).
        for v in 0..<2 {
            let vp = gp(centerM - 6 + Double(v) * 13, sideSign * 44.5)
            let axis = SIMD3<Float>(sin(mid.heading), 0, -cos(mid.heading))
            if v == 0 {
                let face = SIMD3<Float>(cos(mid.heading), 0, sin(mid.heading)) * -sideSign
                addPerson(position: vp, yaw: atan2(face.x, -face.z), role: 3, mode: 0, routeDistanceM: centerM, walkAxis: axis, range: 0, seedKey: "zoovis-\(Int(centerM))-0")
            } else {
                addPerson(position: vp, yaw: atan2(axis.x, -axis.z), role: 3, mode: 1, routeDistanceM: centerM, walkAxis: axis, range: 7, seedKey: "zoovis-\(Int(centerM))-1")
            }
        }
        // Animals.
        let spots: [(along: Double, lat: Float)] = [(-9, 20), (6, 29), (-2, 24), (11, 33)]
        let axisX = SIMD3<Float>(cos(mid.heading), 0, sin(mid.heading))
        let axisZ = SIMD3<Float>(sin(mid.heading), 0, -cos(mid.heading))
        for index in 0..<count {
            let spot = spots[index % spots.count]
            var rig = makeZooAnimal(species: species, mane: index == 0)
            let p = gp(centerM + spot.along, sideSign * spot.lat)
            rig.root.position = SIMD3<Float>(p.x, p.y + 0.07, p.z)
            rig.heading = Float(stableIndex("zoohead-\(Int(centerM))-\(index)", count: 628)) / 100 - 3.14
            rig.root.orientation = simd_quatf(angle: -rig.heading, axis: SIMD3<Float>(0, 1, 0))
            rig.routeDistanceM = centerM + spot.along
            rig.paddockCenter = SIMD3<Float>(p.x, p.y + 0.07, p.z)
            rig.axisX = axisX
            rig.axisZ = axisZ
            rig.walkTarget = rig.root.position
            rig.rngState = UInt64(0x2545 + Int(centerM) * 131 + index * 17_171)
            world.addChild(rig.root)
            zooAnimalRigs.append(rig)
        }
    }

    private func buildZooTree(at point: SIMD3<Float>, seed: Int) {
        let trunkMat = Self.pbr(UIColor(red: 0.36, green: 0.28, blue: 0.20, alpha: 1), roughness: 1)
        let leafMat = Self.pbr(UIColor(red: 0.22, green: 0.38, blue: 0.20, alpha: 1), roughness: 1)
        let trunkH: Float = 2.0 + Float(abs(seed) % 7) * 0.12
        let trunk = zooPart(FallbackCylinderMesh.make(height: trunkH, radius: 0.13), trunkMat, SIMD3<Float>(point.x, point.y + trunkH / 2, point.z), name: "zoo-tree-trunk")
        world.addChild(trunk)
        let canopyR: Float = 1.5 + Float(abs(seed) % 5) * 0.18
        let canopy = zooPart(MeshResource.generateSphere(radius: canopyR), leafMat, SIMD3<Float>(point.x, point.y + trunkH + canopyR * 0.55, point.z), name: "zoo-tree-canopy")
        canopy.scale = SIMD3<Float>(1, 0.82, 1)
        world.addChild(canopy)
        let canopy2 = zooPart(MeshResource.generateSphere(radius: canopyR * 0.66), leafMat, SIMD3<Float>(point.x + 0.8, point.y + trunkH + canopyR * 0.95, point.z + 0.4), name: "zoo-tree-canopy2")
        world.addChild(canopy2)
    }

    /// The zoo line's own world: entrance, speed-limit signs, 25 m
    /// joint plates (the line is standard-length jointed rail end to
    /// end), six enclosures with living animals, and the 動物園
    /// terminal. Built only for the .zooLine variant; the mainline
    /// world keeps its scenic zoo strip from buildZooAndPark.
    private func buildZooLineWorld(routeVariant: RegionalRouteVariant, travelDirection: RegionalTravelDirection) {
        guard routeVariant == .zooLine else { return }
        zooAnimalRigs = []
        zooLastAnimTime = 0
        let up = travelDirection == .up
        let sideSign: Float = up ? -1 : 1
        let trackLat: Float = up ? -2.1 : 2.1
        func gp(_ d: Double, _ lateral: Float) -> SIMD3<Float> { groundOffsetPoint(sample(at: d), lateral: lateral) }
        func yawAt(_ d: Double) -> simd_quatf { simd_quatf(angle: -sample(at: d).heading, axis: SIMD3<Float>(0, 1, 0)) }
        let postMat = Self.pbr(UIColor(red: 0.35, green: 0.36, blue: 0.37, alpha: 1), metallic: 0.6, roughness: 0.5)

        // Entrance zone: gate over the visitor path, info board,
        // ticket booth, parking with cars on the far side.
        let gateA = gp(210, sideSign * 10.5)
        let gateB = gp(210, sideSign * 17.5)
        for gatePost in [gateA, gateB] {
            _ = addBox(parent: world, name: "zoo-gate-post", size: SIMD3<Float>(0.45, 4.0, 0.45), position: SIMD3<Float>(gatePost.x, gatePost.y + 2.0, gatePost.z), material: Self.pbr(UIColor(red: 0.55, green: 0.42, blue: 0.30, alpha: 1), roughness: 0.85), orientation: yawAt(210))
        }
        let gateMid = gp(210, sideSign * 14)
        _ = addBox(parent: world, name: "zoo-gate-beam", size: SIMD3<Float>(7.6, 0.5, 0.4), position: SIMD3<Float>(gateMid.x, gateMid.y + 3.85, gateMid.z), material: Self.pbr(UIColor(red: 0.55, green: 0.42, blue: 0.30, alpha: 1), roughness: 0.85), orientation: yawAt(210))
        _ = addBox(parent: world, name: "zoo-gate-sign", size: SIMD3<Float>(3.4, 0.95, 0.1), position: SIMD3<Float>(gateMid.x, gateMid.y + 3.0, gateMid.z), material: Self.pbr(UIColor(red: 0.96, green: 0.94, blue: 0.88, alpha: 1), roughness: 0.6), orientation: yawAt(210))
        let booth = gp(300, sideSign * 13)
        _ = addBox(parent: world, name: "zoo-booth", size: SIMD3<Float>(2.4, 2.6, 2.2), position: SIMD3<Float>(booth.x, booth.y + 1.3, booth.z), material: Self.pbr(UIColor(red: 0.88, green: 0.84, blue: 0.76, alpha: 1), roughness: 0.8), orientation: yawAt(300))
        _ = addBox(parent: world, name: "zoo-booth-roof", size: SIMD3<Float>(2.8, 0.14, 2.6), position: SIMD3<Float>(booth.x, booth.y + 2.7, booth.z), material: Self.pbr(UIColor(red: 0.40, green: 0.36, blue: 0.32, alpha: 1), roughness: 0.8), orientation: yawAt(300))
        var parkD = 205.0
        while parkD <= 320 {
            let p = gp(parkD, -sideSign * 15)
            _ = addBox(parent: world, name: "zoo-parking", size: SIMD3<Float>(17, 0.07, 15.4), position: SIMD3<Float>(p.x, p.y + 0.02, p.z), material: Self.pbr(UIColor(red: 0.32, green: 0.32, blue: 0.34, alpha: 1), roughness: 0.95), orientation: yawAt(parkD))
            parkD += 15
        }
        for car in 0..<3 {
            let p = gp(225 + Double(car) * 38, -sideSign * 13.5)
            addParkedCar(name: "zoo-car-\(car)", center: p, groundY: p.y + 0.06, yaw: -sample(at: 225 + Double(car) * 38).heading + Float.pi / 2, seed: car * 3 + 1)
        }
        // Park trees scattered along both sides, clear of the
        // paddock band and the station.
        var treeD = 90.0
        while treeD < 2_280 {
            for side: Float in [-1.0, 1.0] {
                let inPaddockBand = side == sideSign && treeD > 500 && treeD < 1_960
                let jitter = Float(stableIndex("zootree-\(Int(treeD))-\(side > 0 ? 1 : 0)", count: 12))
                if !inPaddockBand && stableIndex("zootreeok-\(Int(treeD))-\(side > 0 ? 1 : 0)", count: 4) != 0 {
                    buildZooTree(at: gp(treeD, side * (16 + jitter)), seed: Int(treeD) + (side > 0 ? 7 : 0))
                }
            }
            treeD += 55
        }

        // Speed-limit signs at the enclosure zone boundaries
        // (30 km/h from 450 m, released at 1,900 m).
        for (signD, texture) in [(450.0, "scenery_speed_30"), (1_900.0, "scenery_speed_end")] {
            let base = gp(signD, up ? -4.0 : 4.0)
            _ = addBox(parent: world, name: "zoo-speed-pole-\(Int(signD))", size: SIMD3<Float>(0.09, 2.4, 0.09), position: SIMD3<Float>(base.x, base.y + 1.2, base.z), material: postMat, orientation: yawAt(signD))
            var signMat = Self.texturedPBR(.white, roughness: 0.55, textureName: texture)
            signMat.faceCulling = .none
            let board = addBox(parent: world, name: "zoo-speed-sign-\(Int(signD))", size: SIMD3<Float>(0.85, 0.85, 0.04), position: SIMD3<Float>(base.x, base.y + 2.15, base.z), material: signMat, orientation: yawAt(signD))
            board.orientation = board.orientation * simd_quatf(angle: Float.pi, axis: SIMD3<Float>(0, 1, 0))
        }

        // Fishplates at every 25 m joint on both rails of the
        // running track (standard-length rail, user spec).
        var plateBatch = MeshBatchBuilder()
        let steelMat = Self.pbr(UIColor(red: 0.30, green: 0.31, blue: 0.33, alpha: 1), metallic: 0.7, roughness: 0.5)
        var jointD = 12.5
        while jointD < 2_500 {
            let s = sample(at: jointD)
            for railSide: Float in [-0.72, 0.72] {
                let outer: Float = railSide < 0 ? -0.095 : 0.095
                let p = routeOffsetPoint(s, lateral: trackLat + railSide + outer)
                plateBatch.addBox(center: SIMD3<Float>(p.x, p.y + 0.17, p.z), size: SIMD3<Float>(0.035, 0.13, 0.46), yaw: -s.heading)
            }
            jointD += 25
        }
        if let plates = plateBatch.build(name: "zoo-fishplates", material: steelMat) {
            world.addChild(plates)
        }

        // The six enclosures along the 30 km/h stretch.
        buildZooPaddock(centerM: 560, sideSign: sideSign, species: 5, count: 4, hasCage: false, travelDirection: travelDirection)
        buildZooPaddock(centerM: 770, sideSign: sideSign, species: 4, count: 3, hasCage: false, travelDirection: travelDirection)
        buildZooPaddock(centerM: 990, sideSign: sideSign, species: 0, count: 2, hasCage: true, travelDirection: travelDirection)
        buildZooPaddock(centerM: 1_230, sideSign: sideSign, species: 2, count: 2, hasCage: false, travelDirection: travelDirection)
        buildZooPaddock(centerM: 1_490, sideSign: sideSign, species: 1, count: 2, hasCage: true, travelDirection: travelDirection)
        buildZooPaddock(centerM: 1_710, sideSign: sideSign, species: 3, count: 2, hasCage: false, travelDirection: travelDirection)

        // 動物園 terminal: platform, furniture, station house,
        // departure board and a buffer stop past the end.
        let whiteLine = Self.pbr(UIColor(red: 0.92, green: 0.92, blue: 0.90, alpha: 1), roughness: 0.85)
        buildOneStationPlatform(name: "platform-ZOO", start: 2_290, end: 2_500, trackLateral: trackLat, sideSign: sideSign, width: 5.0, whiteLineMaterial: whiteLine)
        buildStationFurniture(name: "furniture-ZOO", centerChainage: 2_420, start: 2_290, end: 2_500, trackLateral: trackLat, sideSign: sideSign)
        let house = gp(2_440, sideSign * 13.5)
        _ = addBox(parent: world, name: "zoo-station-house", size: SIMD3<Float>(13, 4.2, 6.5), position: SIMD3<Float>(house.x, house.y + 2.1, house.z), material: Self.texturedPBR(.white, roughness: 0.85, textureName: "scenery_house_facade_5"), orientation: yawAt(2_440))
        _ = addBox(parent: world, name: "zoo-station-roof", size: SIMD3<Float>(13.8, 0.35, 7.3), position: SIMD3<Float>(house.x, house.y + 4.4, house.z), material: Self.pbr(UIColor(red: 0.38, green: 0.34, blue: 0.30, alpha: 1), roughness: 0.8), orientation: yawAt(2_440))
        let boardBase = gp(2_430, sideSign * 5.6)
        _ = addBox(parent: world, name: "zoo-departure-pole", size: SIMD3<Float>(0.09, 2.6, 0.09), position: SIMD3<Float>(boardBase.x, boardBase.y + 1.3, boardBase.z), material: postMat, orientation: yawAt(2_430))
        _ = addBox(parent: world, name: "zoo-departure-board", size: SIMD3<Float>(1.7, 0.55, 0.07), position: SIMD3<Float>(boardBase.x, boardBase.y + 2.45, boardBase.z), material: Self.pbr(UIColor(red: 0.08, green: 0.08, blue: 0.10, alpha: 1), roughness: 0.4), orientation: yawAt(2_430))
        _ = addBox(parent: world, name: "zoo-departure-band", size: SIMD3<Float>(1.55, 0.30, 0.075), position: SIMD3<Float>(boardBase.x, boardBase.y + 2.45, boardBase.z), material: Self.pbr(UIColor(red: 0.95, green: 0.90, blue: 0.70, alpha: 1), roughness: 0.35), orientation: yawAt(2_430))
        // People: entrance-path walkers and passengers (plus one
        // staff member) on the terminal platform.
        for w in 0..<2 {
            let s0 = sample(at: 240 + Double(w) * 90)
            let home = gp(240 + Double(w) * 90, sideSign * 14)
            let axis = SIMD3<Float>(sin(s0.heading), 0, -cos(s0.heading))
            addPerson(position: home, yaw: atan2(axis.x, -axis.z), role: 3, mode: 1, routeDistanceM: 240 + Double(w) * 90, walkAxis: axis, range: 42, seedKey: "zooentrance-\(w)")
        }
        let topVZ: Float = 0.3065 + 1.10
        for p in 0..<3 {
            let c = 2_400 + Double(p) * 22
            let station = profileStation(at: c, trackLateral: trackLat)
            let pos = station.center + station.xAxis * (sideSign * 2.6) + station.yAxis * topVZ
            let h = sample(at: c).heading
            let face = SIMD3<Float>(cos(h), 0, sin(h)) * -sideSign
            addPerson(position: pos, yaw: atan2(face.x, -face.z), role: p == 1 ? 1 : 0, mode: 0, routeDistanceM: c, walkAxis: SIMD3<Float>(1, 0, 0), range: 0, seedKey: "zoostation-\(p)")
        }
        // Buffer stop on a short stub past the terminal.
        let endSample = sample(at: 2_500)
        let endPoint = routeOffsetPoint(endSample, lateral: trackLat)
        let forward = SIMD3<Float>(sin(endSample.heading), 0, -cos(endSample.heading))
        let bufferPos = SIMD3<Float>(endPoint.x, endPoint.y, endPoint.z) + forward * 9
        _ = addBox(parent: world, name: "zoo-buffer-beam", size: SIMD3<Float>(1.9, 0.35, 0.3), position: SIMD3<Float>(bufferPos.x, bufferPos.y + 0.75, bufferPos.z), material: postMat, orientation: yawAt(2_500))
        for legSide: Float in [-0.7, 0.7] {
            let legPoint = routeOffsetPoint(endSample, lateral: trackLat + legSide)
            let lp = SIMD3<Float>(legPoint.x, legPoint.y, legPoint.z) + forward * 9
            _ = addBox(parent: world, name: "zoo-buffer-leg", size: SIMD3<Float>(0.22, 0.95, 0.22), position: SIMD3<Float>(lp.x, lp.y + 0.45, lp.z), material: postMat, orientation: yawAt(2_500))
        }
    }

    /// Per-frame animal behaviour: individual timers pick idle /
    /// graze / walk / rest; walking swings the legs and steers the
    /// body, grazing lowers the head (or the giraffe's neck), rest
    /// folds the legs and lowers the body, and every animal turns
    /// its head toward the train when it passes within 130 m.
    /// Animals beyond 430 m of the train are not posed (load gate).
    private func updateZooAnimals(trainPositionM: Double, time: Double) {
        guard !zooAnimalRigs.isEmpty else { return }
        let dt = min(max(time - zooLastAnimTime, 0.001), 0.1)
        zooLastAnimTime = time
        for index in zooAnimalRigs.indices {
            var rig = zooAnimalRigs[index]
            if abs(trainPositionM - rig.routeDistanceM) > 430 && rig.state != 2 {
                zooAnimalRigs[index] = rig
                continue
            }
            func nextUnit() -> Double {
                rig.rngState = rig.rngState &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
                return Double((rig.rngState >> 33) % 1_000) / 1_000
            }
            if time >= rig.stateUntil {
                let roll = nextUnit()
                if rig.species == 5 {
                    rig.state = roll < 0.45 ? 0 : 2
                    rig.stateUntil = time + 5 + nextUnit() * 6
                } else if roll < 0.30 {
                    rig.state = 0; rig.stateUntil = time + 4 + nextUnit() * 5
                } else if roll < 0.58 {
                    rig.state = 1; rig.stateUntil = time + 6 + nextUnit() * 6
                } else if roll < 0.85 {
                    rig.state = 2; rig.stateUntil = time + 26
                    let along = (nextUnit() - 0.5) * 30
                    let lat = (nextUnit() - 0.5) * 20
                    rig.walkTarget = rig.paddockCenter + rig.axisZ * Float(along) + rig.axisX * Float(lat)
                    rig.walkTarget.y = rig.root.position.y
                } else {
                    rig.state = 3; rig.stateUntil = time + 8 + nextUnit() * 8
                }
            }
            let trainNear = abs(trainPositionM - rig.routeDistanceM) < 130
            let grazeTarget: Float = (rig.state == 1 && !trainNear) ? 1 : 0
            rig.grazeAmount += (grazeTarget - rig.grazeAmount) * Float(min(1, dt * 2.5))
            let restTarget: Float = rig.state == 3 ? 1 : 0
            rig.restAmount += (restTarget - rig.restAmount) * Float(min(1, dt * 2.0))

            // Legs: swing while walking, fold while resting.
            let walkSpeed: Float = rig.species == 3 ? 0.55 : (rig.species == 2 ? 0.85 : (rig.species == 5 ? 0.22 : 0.7))
            if rig.state == 2 {
                let toTarget = rig.walkTarget - rig.root.position
                let dist = simd_length(SIMD2<Float>(toTarget.x, toTarget.z))
                if dist < 0.4 {
                    rig.state = 0
                    rig.stateUntil = time + 3 + nextUnit() * 4
                } else {
                    let desired = atan2(toTarget.x, -toTarget.z)
                    var delta = desired - rig.heading
                    while delta > Float.pi { delta -= 2 * Float.pi }
                    while delta < -Float.pi { delta += 2 * Float.pi }
                    rig.heading += delta * Float(min(1, dt * 2.2))
                    rig.root.orientation = simd_quatf(angle: -rig.heading, axis: SIMD3<Float>(0, 1, 0))
                    let step = min(Float(dist), walkSpeed * Float(dt))
                    rig.root.position += SIMD3<Float>(sin(rig.heading), 0, -cos(rig.heading)) * step
                    rig.routeDistanceM += Double(step) * (abs(delta) < 1.2 ? 1 : 0.3)
                    rig.phase += Float(dt) * (rig.species == 5 ? 9 : 5.2) * walkSpeed
                }
            }
            for (legIndex, leg) in rig.legs.enumerated() {
                let diagonal: Float = (legIndex == 0 || legIndex == 3) ? 0 : Float.pi
                let swing: Float = rig.state == 2 ? sin(rig.phase + diagonal) * 0.42 : 0
                let fold: Float = (legIndex < 2 ? -1.25 : 1.25) * rig.restAmount
                leg.orientation = simd_quatf(angle: swing + fold, axis: SIMD3<Float>(1, 0, 0))
            }
            // Body height: stand, or lowered onto folded legs at rest.
            if rig.species != 5 {
                rig.body.position.y = rig.bodyStandY + (rig.bodyRestY - rig.bodyStandY) * rig.restAmount + (rig.state == 2 ? abs(sin(rig.phase)) * 0.03 : 0)
            } else if rig.state == 2 {
                rig.body.orientation = simd_quatf(angle: sin(rig.phase) * 0.07, axis: SIMD3<Float>(0, 0, 1))
            }
            // Head: graze pitch, plus a look toward the train.
            var headYaw: Float = 0
            if trainNear {
                // The track lies toward -axisX * sideSign from the
                // paddock; approximate the look with a fixed yaw
                // toward the track side relative to the body.
                headYaw = -0.65
            }
            rig.headPivot.orientation = simd_quatf(angle: -0.78 * rig.grazeAmount, axis: SIMD3<Float>(1, 0, 0)) * simd_quatf(angle: headYaw * (1 - rig.grazeAmount), axis: SIMD3<Float>(0, 1, 0))
            if let neck = rig.neckPivot {
                neck.orientation = simd_quatf(angle: 0.42 - 0.95 * rig.grazeAmount, axis: SIMD3<Float>(1, 0, 0))
            }
            // Tail sway and trunk sway keep idle animals alive.
            rig.tailPivot.orientation = simd_quatf(angle: 0.30, axis: SIMD3<Float>(1, 0, 0)) * simd_quatf(angle: sin(Float(time) * 1.4 + Float(index) * 1.7) * 0.28, axis: SIMD3<Float>(0, 1, 0))
            for (seg, pivot) in rig.trunkPivots.enumerated() {
                pivot.orientation = simd_quatf(angle: sin(Float(time) * 0.8 + Float(seg) * 0.7 + Float(index)) * 0.10, axis: SIMD3<Float>(1, 0, 0))
            }
            zooAnimalRigs[index] = rig
        }
    }

    /// The theme park line's own world: entrance plaza, the park
    /// grounds beside the line (ferris wheel, roller coaster,
    /// fairy-tale buildings and castle on a plaza pad), fishplates
    /// every 25 m (standard-length jointed rail, like the zoo
    /// line), and the テーマパーク terminal.
    private func buildParkLineWorld(routeVariant: RegionalRouteVariant, travelDirection: RegionalTravelDirection) {
        guard routeVariant == .parkLine else { return }
        let up = travelDirection == .up
        let sideSign: Float = up ? -1 : 1
        let trackLat: Float = up ? -2.1 : 2.1
        func gp(_ d: Double, _ lateral: Float) -> SIMD3<Float> { groundOffsetPoint(sample(at: d), lateral: lateral) }
        func yawAt(_ d: Double) -> simd_quatf { simd_quatf(angle: -sample(at: d).heading, axis: SIMD3<Float>(0, 1, 0)) }
        let postMat = Self.pbr(UIColor(red: 0.35, green: 0.36, blue: 0.37, alpha: 1), metallic: 0.6, roughness: 0.5)
        let pastels: [UIColor] = [
            UIColor(red: 0.96, green: 0.80, blue: 0.85, alpha: 1),
            UIColor(red: 0.80, green: 0.88, blue: 0.96, alpha: 1),
            UIColor(red: 0.98, green: 0.92, blue: 0.72, alpha: 1),
            UIColor(red: 0.84, green: 0.94, blue: 0.82, alpha: 1),
        ]

        // Entrance plaza and parking near the origin.
        var plazaD = 120.0
        while plazaD <= 300 {
            let p = gp(plazaD, sideSign * 16)
            _ = addBox(parent: world, name: "park-entrance", size: SIMD3<Float>(20, 0.07, 15.4), position: SIMD3<Float>(p.x, p.y + 0.02, p.z), material: Self.pbr(UIColor(red: 0.85, green: 0.78, blue: 0.70, alpha: 1), roughness: 0.95), orientation: yawAt(plazaD))
            plazaD += 15
        }
        for car in 0..<2 {
            let p = gp(160 + Double(car) * 60, -sideSign * 13.5)
            addParkedCar(name: "park-car-\(car)", center: p, groundY: p.y + 0.06, yaw: -sample(at: 160 + Double(car) * 60).heading + Float.pi / 2, seed: car * 2 + 2)
        }
        // Park trees along both sides.
        var treeD = 80.0
        while treeD < 1_750 {
            for side: Float in [-1.0, 1.0] {
                if stableIndex("parktreeok-\(Int(treeD))-\(side > 0 ? 1 : 0)", count: 4) != 0 {
                    buildZooTree(at: gp(treeD, side * (15 + Float(stableIndex("parktree-\(Int(treeD))-\(side > 0 ? 1 : 0)", count: 12)))), seed: Int(treeD) + (side > 0 ? 3 : 0))
                }
            }
            treeD += 60
        }

        // Fishplates at every 25 m joint (standard-length rail).
        var plateBatch = MeshBatchBuilder()
        let steelMat = Self.pbr(UIColor(red: 0.30, green: 0.31, blue: 0.33, alpha: 1), metallic: 0.7, roughness: 0.5)
        var jointD = 12.5
        while jointD < 2_000 {
            let s = sample(at: jointD)
            for railSide: Float in [-0.72, 0.72] {
                let outer: Float = railSide < 0 ? -0.095 : 0.095
                let p = routeOffsetPoint(s, lateral: trackLat + railSide + outer)
                plateBatch.addBox(center: SIMD3<Float>(p.x, p.y + 0.17, p.z), size: SIMD3<Float>(0.035, 0.13, 0.46), yaw: -s.heading)
            }
            jointD += 25
        }
        if let plates = plateBatch.build(name: "park-fishplates", material: steelMat) {
            world.addChild(plates)
        }

        // Park grounds: plaza pad under the attractions.
        let parkStation = profileStation(at: 1_280, trackLateral: 0)
        let xAxis = parkStation.xAxis
        let tangent = -simd_cross(xAxis, parkStation.yAxis)
        let parkGround = gp(1_280, sideSign * 115)
        let parkGroundY = parkGround.y
        let parkCenter = SIMD3<Float>(parkGround.x, parkGroundY, parkGround.z)
        var padD = 950.0
        while padD <= 1_620 {
            let p = gp(padD, sideSign * 115)
            _ = addBox(parent: world, name: "park-plaza", size: SIMD3<Float>(150, 0.09, 16.6), position: SIMD3<Float>(p.x, p.y + 0.02, p.z), material: Self.pbr(UIColor(red: 0.82, green: 0.76, blue: 0.68, alpha: 1), roughness: 0.95), orientation: yawAt(padD))
            padD += 16
        }
        let parkYaw = yawAt(1_280)

        // Ferris wheel (diameter 56 m) facing the line.
        let wheelBase = parkCenter - xAxis * (sideSign * 37)
        let wheelCenter = SIMD3<Float>(wheelBase.x, parkGroundY + 30, wheelBase.z)
        let wheelMat = Self.pbr(UIColor(red: 0.92, green: 0.93, blue: 0.94, alpha: 1), metallic: 0.4, roughness: 0.4)
        var wheelBatch = MeshBatchBuilder()
        let rimSegments = 28
        for i in 0..<rimSegments {
            let a0 = Float(i) / Float(rimSegments) * Float.pi * 2
            let a1 = Float(i + 1) / Float(rimSegments) * Float.pi * 2
            let p0 = wheelCenter + (xAxis * cos(a0) + SIMD3<Float>(0, 1, 0) * sin(a0)) * 28
            let p1 = wheelCenter + (xAxis * cos(a1) + SIMD3<Float>(0, 1, 0) * sin(a1)) * 28
            wheelBatch.addSegment(from: p0, to: p1, thickness: 0.35)
            if i % 7 == 0 {
                wheelBatch.addSegment(from: wheelCenter, to: p0, thickness: 0.22)
            }
        }
        for legSign: Float in [-1, 1] {
            let foot = wheelBase + tangent * (legSign * 9)
            wheelBatch.addSegment(from: wheelCenter, to: SIMD3<Float>(foot.x, parkGroundY, foot.z), thickness: 0.5)
        }
        if let wheel = wheelBatch.build(name: "park-wheel", material: wheelMat) {
            world.addChild(wheel)
        }
        _ = addBox(parent: world, name: "park-wheel-hub", size: SIMD3<Float>(1.4, 1.4, 2.4), position: wheelCenter, material: wheelMat, orientation: parkYaw)
        for gondola in 0..<12 {
            let a = Float(gondola) / 12 * Float.pi * 2
            let gpnt = wheelCenter + (xAxis * cos(a) + SIMD3<Float>(0, 1, 0) * sin(a)) * 28
            _ = addBox(parent: world, name: "park-gondola-\(gondola)", size: SIMD3<Float>(1.7, 1.8, 1.7), position: SIMD3<Float>(gpnt.x, gpnt.y - 1.8, gpnt.z), material: Self.pbr(pastels[gondola % pastels.count], roughness: 0.5), orientation: parkYaw)
        }

        // Roller coaster: closed ellipse with two hills.
        let coasterOrigin = parkCenter + xAxis * (sideSign * 35) - tangent * 10
        var coasterStations: [ProfileStation] = []
        var coasterPoints: [SIMD3<Float>] = []
        let coasterN = 40
        for i in 0...coasterN {
            let theta = Double(i) / Double(coasterN) * Double.pi * 2
            let along = Float(cos(theta)) * 56
            let lat = Float(sin(theta)) * 34
            let hill = 7 + 15 * Float(pow(max(sin(theta + 0.6), 0), 1.4)) + 5 * Float(max(sin(2 * theta), 0))
            coasterPoints.append(coasterOrigin + tangent * along + xAxis * lat + SIMD3<Float>(0, hill, 0))
        }
        for i in 0...coasterN {
            let prev = coasterPoints[(i + coasterN - 1) % coasterN]
            let next = coasterPoints[(i + 1) % coasterN]
            let tan = simd_normalize(next - prev)
            var xA = simd_cross(SIMD3<Float>(0, 1, 0), tan)
            xA = simd_length(xA) > 0.001 ? simd_normalize(xA) : xAxis
            let yA = simd_normalize(simd_cross(xA, tan))
            coasterStations.append(ProfileStation(center: coasterPoints[i], xAxis: xA, yAxis: yA, distanceM: Double(i)))
        }
        let coasterMat = Self.pbr(UIColor(red: 0.85, green: 0.45, blue: 0.30, alpha: 1), metallic: 0.5, roughness: 0.45)
        if let track = profileStripEntity(name: "parkline-coaster-track", stations: Array(coasterStations.dropLast()), profile: [(-0.8, 0), (0.8, 0)], closed: true, material: coasterMat) { world.addChild(track) }
        for i in stride(from: 0, to: coasterN, by: 3) {
            let p = coasterPoints[i]
            let h = p.y - parkGroundY
            _ = addBox(parent: world, name: "parkline-coaster-support-\(i)", size: SIMD3<Float>(0.55, h, 0.55), position: SIMD3<Float>(p.x, parkGroundY + h / 2, p.z), material: Self.pbr(UIColor(red: 0.80, green: 0.80, blue: 0.78, alpha: 1), roughness: 0.8))
        }

        // Fairy-tale buildings and the castle.
        let fairySpots: [(along: Float, lat: Float, w: Float, h: Float, d: Float)] = [
            (-38, -30, 10, 7, 9), (34, -34, 11, 8, 9), (44, 22, 9, 6.5, 8),
        ]
        for (fairyIndex, spot) in fairySpots.enumerated() {
            let base = parkCenter + tangent * spot.along + xAxis * spot.lat
            _ = addBox(parent: world, name: "parkline-fairy-\(fairyIndex)", size: SIMD3<Float>(spot.w, spot.h, spot.d), position: SIMD3<Float>(base.x, parkGroundY + spot.h / 2, base.z), material: Self.pbr(pastels[fairyIndex % pastels.count], roughness: 0.8), orientation: parkYaw)
            let roof = addBox(parent: world, name: "parkline-fairy-roof-\(fairyIndex)", size: SIMD3<Float>(spot.w * 0.78, spot.w * 0.78, spot.d + 0.4), position: SIMD3<Float>(base.x, parkGroundY + spot.h + spot.w * 0.24, base.z), material: Self.pbr(pastels[(fairyIndex + 1) % pastels.count], roughness: 0.7), orientation: parkYaw)
            roof.orientation = roof.orientation * simd_quatf(angle: Float.pi / 4, axis: SIMD3<Float>(0, 0, 1))
        }
        let castleBase = parkCenter + tangent * -6 + xAxis * (sideSign * 40)
        _ = addBox(parent: world, name: "parkline-castle", size: SIMD3<Float>(11, 19, 11), position: SIMD3<Float>(castleBase.x, parkGroundY + 9.5, castleBase.z), material: Self.pbr(pastels[1], roughness: 0.8), orientation: parkYaw)
        for turret in 0..<4 {
            let tx = (turret % 2 == 0 ? -5.5 : 5.5) as Float
            let tz = (turret < 2 ? -5.5 : 5.5) as Float
            let tp = castleBase + xAxis * tx + tangent * tz
            _ = addBox(parent: world, name: "parkline-castle-turret-\(turret)", size: SIMD3<Float>(2.4, 24, 2.4), position: SIMD3<Float>(tp.x, parkGroundY + 12, tp.z), material: Self.pbr(pastels[0], roughness: 0.8), orientation: parkYaw)
        }
        let castleRoof = addBox(parent: world, name: "parkline-castle-roof", size: SIMD3<Float>(8.6, 8.6, 11.4), position: SIMD3<Float>(castleBase.x, parkGroundY + 19 + 2.1, castleBase.z), material: Self.pbr(pastels[3], roughness: 0.7), orientation: parkYaw)
        castleRoof.orientation = castleRoof.orientation * simd_quatf(angle: Float.pi / 4, axis: SIMD3<Float>(0, 0, 1))

        // Visitors strolling the plaza (people).
        for v in 0..<5 {
            let along = Float(stableIndex("parkvis-\(v)", count: 60)) - 30
            let lat = Float(stableIndex("parkvislat-\(v)", count: 50)) - 25
            let home = parkCenter + tangent * along + xAxis * lat
            let axis = v % 2 == 0 ? tangent : xAxis
            addPerson(position: SIMD3<Float>(home.x, parkGroundY, home.z), yaw: atan2(axis.x, -axis.z), role: 3, mode: 1, routeDistanceM: 1_280, walkAxis: axis, range: 11, seedKey: "parkvis-\(v)")
        }

        // テーマパーク terminal: platform, furniture, pastel
        // station house and a buffer stop past the end.
        let whiteLine = Self.pbr(UIColor(red: 0.92, green: 0.92, blue: 0.90, alpha: 1), roughness: 0.85)
        buildOneStationPlatform(name: "platform-PARK", start: 1_790, end: 2_000, trackLateral: trackLat, sideSign: sideSign, width: 5.0, whiteLineMaterial: whiteLine)
        buildStationFurniture(name: "furniture-PARK", centerChainage: 1_920, start: 1_790, end: 2_000, trackLateral: trackLat, sideSign: sideSign)
        let topVP: Float = 0.3065 + 1.10
        for p in 0..<3 {
            let c = 1_900 + Double(p) * 22
            let station = profileStation(at: c, trackLateral: trackLat)
            let pos = station.center + station.xAxis * (sideSign * 2.6) + station.yAxis * topVP
            let h = sample(at: c).heading
            let face = SIMD3<Float>(cos(h), 0, sin(h)) * -sideSign
            addPerson(position: pos, yaw: atan2(face.x, -face.z), role: p == 1 ? 1 : 3, mode: 0, routeDistanceM: c, walkAxis: SIMD3<Float>(1, 0, 0), range: 0, seedKey: "parkstation-\(p)")
        }
        let house = gp(1_940, sideSign * 13.5)
        _ = addBox(parent: world, name: "park-station-house", size: SIMD3<Float>(12, 4.6, 6.5), position: SIMD3<Float>(house.x, house.y + 2.3, house.z), material: Self.pbr(pastels[0], roughness: 0.85), orientation: yawAt(1_940))
        let houseRoof = addBox(parent: world, name: "park-station-roof", size: SIMD3<Float>(9.4, 9.4, 7.3), position: SIMD3<Float>(house.x, house.y + 4.6 + 2.2, house.z), material: Self.pbr(pastels[2], roughness: 0.7), orientation: yawAt(1_940))
        houseRoof.orientation = houseRoof.orientation * simd_quatf(angle: Float.pi / 4, axis: SIMD3<Float>(0, 0, 1))
        let endSample = sample(at: 2_000)
        let endPoint = routeOffsetPoint(endSample, lateral: trackLat)
        let forward = SIMD3<Float>(sin(endSample.heading), 0, -cos(endSample.heading))
        let bufferPos = SIMD3<Float>(endPoint.x, endPoint.y, endPoint.z) + forward * 9
        _ = addBox(parent: world, name: "park-buffer-beam", size: SIMD3<Float>(1.9, 0.35, 0.3), position: SIMD3<Float>(bufferPos.x, bufferPos.y + 0.75, bufferPos.z), material: postMat, orientation: yawAt(2_000))
        for legSide: Float in [-0.7, 0.7] {
            let legPoint = routeOffsetPoint(endSample, lateral: trackLat + legSide)
            let lp = SIMD3<Float>(legPoint.x, legPoint.y, legPoint.z) + forward * 9
            _ = addBox(parent: world, name: "park-buffer-leg", size: SIMD3<Float>(0.22, 0.95, 0.22), position: SIMD3<Float>(lp.x, lp.y + 0.45, lp.z), material: postMat, orientation: yawAt(2_000))
        }
    }

    // MARK: - People (quality41 final)

    /// One articulated human figure (legs, torso, arms, head, hair)
    /// at real proportions. role: 0 passenger, 1 station staff
    /// (uniform + cap + red armband), 2 child, 3 visitor.
    private func makePersonFigure(role: Int, seedKey: String) -> (root: Entity, legL: Entity, legR: Entity, armL: Entity, armR: Entity) {
        let hash = stableIndex(seedKey, count: 1_000)
        let s: Float = role == 2 ? 0.68 : (0.94 + Float(hash % 11) * 0.012)
        let jackets: [UIColor] = [
            UIColor(red: 0.20, green: 0.32, blue: 0.52, alpha: 1),
            UIColor(red: 0.55, green: 0.28, blue: 0.24, alpha: 1),
            UIColor(red: 0.30, green: 0.44, blue: 0.32, alpha: 1),
            UIColor(red: 0.45, green: 0.46, blue: 0.48, alpha: 1),
            UIColor(red: 0.72, green: 0.66, blue: 0.55, alpha: 1),
            UIColor(red: 0.16, green: 0.16, blue: 0.18, alpha: 1),
            UIColor(red: 0.55, green: 0.68, blue: 0.78, alpha: 1),
            UIColor(red: 0.78, green: 0.55, blue: 0.62, alpha: 1),
        ]
        let trousersPalette: [UIColor] = [
            UIColor(red: 0.16, green: 0.19, blue: 0.27, alpha: 1),
            UIColor(red: 0.32, green: 0.32, blue: 0.34, alpha: 1),
            UIColor(red: 0.36, green: 0.28, blue: 0.20, alpha: 1),
            UIColor(red: 0.10, green: 0.10, blue: 0.12, alpha: 1),
        ]
        let skins: [UIColor] = [
            UIColor(red: 0.87, green: 0.66, blue: 0.52, alpha: 1),
            UIColor(red: 0.76, green: 0.55, blue: 0.42, alpha: 1),
            UIColor(red: 0.62, green: 0.44, blue: 0.33, alpha: 1),
        ]
        let hairs: [UIColor] = [
            UIColor(red: 0.08, green: 0.07, blue: 0.07, alpha: 1),
            UIColor(red: 0.25, green: 0.16, blue: 0.10, alpha: 1),
            UIColor(red: 0.55, green: 0.55, blue: 0.55, alpha: 1),
        ]
        let jacketMat = Self.pbr(role == 1 ? UIColor(red: 0.13, green: 0.20, blue: 0.38, alpha: 1) : jackets[hash % jackets.count], roughness: 0.92)
        let trousersMat = Self.pbr(role == 1 ? UIColor(red: 0.10, green: 0.14, blue: 0.26, alpha: 1) : trousersPalette[hash / 7 % trousersPalette.count], roughness: 0.92)
        let skinMat = Self.pbr(skins[hash / 13 % skins.count], roughness: 0.75)
        let hairMat = Self.pbr(hairs[hash / 17 % hairs.count], roughness: 0.95)

        let legLen: Float = 0.84 * s
        let torsoH: Float = 0.60 * s
        let armLen: Float = 0.60 * s
        let root = Entity()
        root.name = "person-\(role)"
        var legs: [Entity] = []
        for side: Float in [-1, 1] {
            let hip = Entity()
            hip.position = SIMD3<Float>(side * 0.105 * s, legLen, 0)
            let mesh = zooPart(MeshResource.generateBox(size: SIMD3<Float>(0.145 * s, legLen, 0.175 * s), cornerRadius: 0.03 * s), trousersMat, SIMD3<Float>(0, -legLen / 2 + 0.01, 0), name: "person-leg")
            hip.addChild(mesh)
            root.addChild(hip)
            legs.append(hip)
        }
        let torso = zooPart(MeshResource.generateBox(size: SIMD3<Float>(0.41 * s, torsoH, 0.24 * s), cornerRadius: 0.05 * s), jacketMat, SIMD3<Float>(0, legLen + torsoH / 2 - 0.03 * s, 0), name: "person-torso")
        root.addChild(torso)
        var arms: [Entity] = []
        for side: Float in [-1, 1] {
            let shoulder = Entity()
            shoulder.position = SIMD3<Float>(side * 0.255 * s, legLen + torsoH - 0.09 * s, 0)
            let mesh = zooPart(MeshResource.generateBox(size: SIMD3<Float>(0.095 * s, armLen, 0.11 * s), cornerRadius: 0.03 * s), jacketMat, SIMD3<Float>(0, -armLen / 2, 0), name: "person-arm")
            shoulder.addChild(mesh)
            root.addChild(shoulder)
            arms.append(shoulder)
        }
        let head = zooPart(MeshResource.generateSphere(radius: 0.115 * s), skinMat, SIMD3<Float>(0, legLen + torsoH + 0.075 * s, 0), name: "person-head")
        root.addChild(head)
        if role == 1 {
            let cap = zooPart(FallbackCylinderMesh.make(height: 0.05 * s, radius: 0.128 * s), Self.pbr(UIColor(red: 0.13, green: 0.20, blue: 0.38, alpha: 1), roughness: 0.8), SIMD3<Float>(0, legLen + torsoH + 0.165 * s, 0), name: "staff-cap")
            root.addChild(cap)
            let band = zooPart(FallbackCylinderMesh.make(height: 0.028 * s, radius: 0.130 * s), Self.pbr(.white, roughness: 0.8), SIMD3<Float>(0, legLen + torsoH + 0.132 * s, 0), name: "staff-cap-band")
            root.addChild(band)
            let armband = zooPart(MeshResource.generateBox(size: SIMD3<Float>(0.115 * s, 0.07 * s, 0.13 * s), cornerRadius: 0.01), Self.pbr(UIColor(red: 0.80, green: 0.16, blue: 0.14, alpha: 1), roughness: 0.8), SIMD3<Float>(0, -0.20 * s, 0), name: "staff-armband")
            arms[0].addChild(armband)
        } else {
            let hair = zooPart(MeshResource.generateSphere(radius: 0.120 * s), hairMat, SIMD3<Float>(0, legLen + torsoH + 0.103 * s, 0.010 * s), name: "person-hair")
            hair.scale = SIMD3<Float>(1, 0.78, 1)
            root.addChild(hair)
        }
        if hash % 4 == 1 && role != 1 {
            let bag = zooPart(MeshResource.generateBox(size: SIMD3<Float>(0.13 * s, 0.34 * s, 0.30 * s), cornerRadius: 0.02), Self.pbr(UIColor(red: 0.30, green: 0.22, blue: 0.16, alpha: 1), roughness: 0.85), SIMD3<Float>(0.31 * s, legLen + 0.16 * s, 0.02), name: "person-bag")
            root.addChild(bag)
        }
        return (root, legs[0], legs[1], arms[0], arms[1])
    }

    private func addPerson(position: SIMD3<Float>, yaw: Float, role: Int, mode: Int, routeDistanceM: Double, walkAxis: SIMD3<Float>, range: Float, seedKey: String) {
        let figure = makePersonFigure(role: role, seedKey: seedKey)
        figure.root.position = position
        figure.root.orientation = simd_quatf(angle: -yaw, axis: SIMD3<Float>(0, 1, 0))
        var rig = PersonRig(root: figure.root, legL: figure.legL, legR: figure.legR, armL: figure.armL, armR: figure.armR,
                            mode: mode, routeDistanceM: routeDistanceM, home: position, walkAxis: walkAxis, range: range,
                            speed: 0.45 + Float(stableIndex(seedKey + "spd", count: 40)) * 0.01,
                            phase: Float(stableIndex(seedKey + "ph", count: 628)) / 100)
        if mode == 0 && stableIndex(seedKey + "phone", count: 5) == 2 && role != 1 {
            rig.armBaseR = -0.95
            rig.armR.orientation = simd_quatf(angle: -0.95, axis: SIMD3<Float>(1, 0, 0))
        }
        world.addChild(figure.root)
        personRigs.append(rig)
    }

    /// Waiting and walking figures for one platform side: a mix of
    /// standers facing the track and walkers pacing the platform,
    /// plus one uniformed staff member at the larger stations.
    private func addPlatformPeople(stationID: String, archetype: String, start: Double, end: Double, trackLateral: Float, sideSign: Float) {
        let topV: Float = 0.3065 + 1.10
        let major = archetype.contains("terminal") || archetype.contains("major") || archetype.contains("junction")
        let count = major ? 9 : (archetype.contains("branch") ? 3 : 5)
        let span = end - start
        guard span > 34 else { return }
        for i in 0..<count {
            let key = "people-\(stationID)-\(Int(trackLateral * 10))-\(Int(sideSign))-\(i)"
            let frac = 0.08 + Double(stableIndex(key, count: 84)) / 100
            let c = start + span * frac
            let station = profileStation(at: c, trackLateral: trackLateral)
            let isStaff = major && i == 0
            let u = sideSign * (isStaff ? 2.25 : 2.35 + Float(stableIndex(key + "u", count: 13)) * 0.12)
            let pos = station.center + station.xAxis * u + station.yAxis * topV
            let h = sample(at: c).heading
            let xAxis = SIMD3<Float>(cos(h), 0, sin(h))
            let faceTrack = -xAxis * sideSign
            let faceYaw = atan2(faceTrack.x, -faceTrack.z)
            let walker = !isStaff && stableIndex(key + "walk", count: 3) == 0
            if walker {
                let tangent = -simd_cross(station.xAxis, station.yAxis)
                let axis = simd_normalize(SIMD3<Float>(tangent.x, 0, tangent.z))
                addPerson(position: pos, yaw: atan2(axis.x, -axis.z), role: stableIndex(key + "role", count: 7) == 0 ? 2 : 0,
                          mode: 1, routeDistanceM: c, walkAxis: axis, range: Float(min(16, span / 2 - 14)), seedKey: key)
            } else {
                addPerson(position: pos, yaw: faceYaw, role: isStaff ? 1 : (stableIndex(key + "role", count: 7) == 0 ? 2 : 0),
                          mode: 0, routeDistanceM: c, walkAxis: xAxis, range: 0, seedKey: key)
            }
        }
    }

    /// Per-frame people animation: walkers pace their platform or
    /// path with swinging legs and arms, standers sway almost
    /// imperceptibly, and everyone beyond 320 m of the train rests.
    private func updatePeople(trainPositionM: Double, time: Double) {
        guard !personRigs.isEmpty else { return }
        let dt = min(max(time - peopleLastTime, 0.001), 0.1)
        peopleLastTime = time
        for index in personRigs.indices {
            var rig = personRigs[index]
            if abs(trainPositionM - rig.routeDistanceM) > 320 {
                continue
            }
            if rig.mode == 1 {
                rig.offset += rig.dirSign * rig.speed * Float(dt)
                if rig.offset > rig.range { rig.offset = rig.range; rig.dirSign = -1 }
                if rig.offset < -rig.range { rig.offset = -rig.range; rig.dirSign = 1 }
                rig.phase += Float(dt) * 6.2 * rig.speed
                rig.root.position = rig.home + rig.walkAxis * rig.offset
                let dir = rig.walkAxis * rig.dirSign
                rig.root.orientation = simd_quatf(angle: -atan2(dir.x, -dir.z), axis: SIMD3<Float>(0, 1, 0))
                let swing = sin(rig.phase) * 0.48
                rig.legL.orientation = simd_quatf(angle: swing, axis: SIMD3<Float>(1, 0, 0))
                rig.legR.orientation = simd_quatf(angle: -swing, axis: SIMD3<Float>(1, 0, 0))
                rig.armL.orientation = simd_quatf(angle: -swing * 0.55, axis: SIMD3<Float>(1, 0, 0))
                rig.armR.orientation = simd_quatf(angle: swing * 0.55 + rig.armBaseR, axis: SIMD3<Float>(1, 0, 0))
            } else {
                let sway = sin(Float(time) * 0.85 + rig.phase) * 0.045
                rig.armL.orientation = simd_quatf(angle: sway, axis: SIMD3<Float>(1, 0, 0))
                rig.armR.orientation = simd_quatf(angle: -sway + rig.armBaseR, axis: SIMD3<Float>(1, 0, 0))
            }
            personRigs[index] = rig
        }
    }

    /// Pantograph arc flashes (quality41 final): brief blue-white
    /// bursts at the second car's pantograph — likelier in tunnels
    /// and at speed. Cosmetic only; the flash pattern is a fast
    /// time hash so bursts look random without any state machine.
    private func updatePantographSpark(speedKmh: Double, time: Double, inTunnel: Bool) {
        guard speedKmh > 35, vehicleModels.count > 0 else {
            pantographSpark?.isEnabled = false
            return
        }
        let spark: ModelEntity
        if let existing = pantographSpark {
            spark = existing
        } else {
            var material = PhysicallyBasedMaterial()
            material.baseColor = .init(tint: UIColor(red: 0.75, green: 0.85, blue: 1.0, alpha: 1))
            material.emissiveColor = .init(color: UIColor(red: 0.65, green: 0.78, blue: 1.0, alpha: 1))
            material.emissiveIntensity = 6
            let made = ModelEntity(mesh: MeshResource.generateSphere(radius: 0.15), materials: [material])
            made.name = "pantograph-spark"
            world.addChild(made)
            pantographSpark = made
            spark = made
        }
        let quanta = Int(time * 24)
        let hash = stableIndex("spark-\(quanta)", count: 100)
        let threshold = inTunnel ? 15 : 4
        spark.isEnabled = hash < threshold
        if spark.isEnabled {
            let car = vehicleModels[min(1, vehicleModels.count - 1)]
            spark.position = car.root.position + SIMD3<Float>(0, 4.0, 0)
            let pulse = 0.8 + Float(hash % 7) * 0.22
            spark.scale = SIMD3<Float>(pulse, pulse * 0.7, pulse)
        }
    }

    private func applyAspect(_ lamps: [ModelEntity], aspect: ThreeAspectSignal) {
        guard lamps.count == 4 else { return }
        // The 4-aspect A head's lamp order is yellow, red,
        // yellow, green (top to bottom). Aspects: 進行 = green,
        // 減速 = lower yellow + green (YG), 注意 = top yellow,
        // 警戒 = both yellows (YY), 停止 = red.
        lamps[0].model?.materials = [aspect == .yellow || aspect == .doubleYellow ? signalYellowMaterial : signalDarkLampMaterial]
        lamps[1].model?.materials = [aspect == .red ? signalRedMaterial : signalDarkLampMaterial]
        lamps[2].model?.materials = [aspect == .doubleYellow || aspect == .yellowGreen ? signalYellowMaterial : signalDarkLampMaterial]
        lamps[3].model?.materials = [aspect == .green || aspect == .yellowGreen ? signalGreenMaterial : signalDarkLampMaterial]
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
                // quality41: the portal used to stand on flat
                // ground like a black box (photo rounds). Give it
                // a vegetated hillside: two side mounds flanking
                // the bore and a top mound above the lintel, so
                // the portal reads as cut into a hill. The bore
                // (|lateral| < 5.6, below +7.5) stays clear.
                let hillMaterial = Self.texturedPBR(.white, roughness: 1.0, textureName: "scenery_mountain_forest")
                for side in [-1.0, 1.0] {
                    let moundLateral = Float(side) * 13.5
                    let mx = portalSample.x + moundLateral * cos(portalSample.heading)
                    let mz = portalSample.z + moundLateral * sin(portalSample.heading)
                    addBox(parent: world, name: "tunnel-hill-side-\(Int(boundary))-\(Int(side))",
                           size: SIMD3<Float>(15, 9.5, 17), position: SIMD3<Float>(mx, portalSample.elevationM + 3.2, mz),
                           material: hillMaterial, orientation: yaw)
                }
                addBox(parent: world, name: "tunnel-hill-top-\(Int(boundary))",
                       size: SIMD3<Float>(26, 6.5, 17), position: SIMD3<Float>(portalSample.x, portalSample.elevationM + 10.6, portalSample.z),
                       material: hillMaterial, orientation: yaw)
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
        // quality41: the photoreal survey (cat01) found real
        // private-railway downtowns are mid-rise dominant — 4-9
        // floors with tall buildings only as occasional spikes
        // near stations — where the old distribution made nearly
        // every tower 10-15 floors. Base heights are now 12-26 m
        // downtown / 11-21 m in band 1, with a rarer, taller spike.
        var height: Float = band == 2
            ? 12 + Float((seed * 29) % 100) / 100 * 14
            : 11 + Float((seed * 29) % 100) / 100 * 10
        if band == 2 {
            let c = chainageFromCenter(distanceM: distance, route: route, travelDirection: travelDirection)
            height *= Float(1.05 - (c / 4_200) * 0.45)
            height = max(11, height)
            if seed % 6 == 0 {
                height *= 1.9
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
        guard buildingClearOfPlatforms(chainage: distance, halfLength: Double(width) / 2, lateral: lateral, halfDepth: depth / 2),
              buildingClearOfFans(chainage: distance, halfLength: Double(width) / 2, lateral: lateral, halfDepth: depth / 2) else { return }
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
        // quality41: outdoor AC units on most roofs — the small
        // clutter ChatGPT's review and the survey both name as
        // what separates a lived-in roof from a card edge.
        if seed % 3 != 0 {
            let acMaterial = Self.pbr(UIColor(red: 0.80, green: 0.81, blue: 0.80, alpha: 1), metallic: 0.3, roughness: 0.6)
            for acIndex in 0..<(1 + abs(seed) % 2) {
                let acOffsetX = Float((seed + acIndex * 3) % 5 - 2) * width * 0.14
                let acOffsetZ = Float((seed + acIndex * 7) % 5 - 2) * depth * 0.13
                let ac = addBox(parent: world, name: "office-roofac-\(seed)-\(acIndex)",
                                size: SIMD3<Float>(1.15, 0.68, 1.15),
                                position: SIMD3<Float>(x + acOffsetX, groundY + height + 0.64, z + acOffsetZ),
                                material: acMaterial)
                ac.orientation = orientation
            }
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

    /// Accent stripe/sign material for the roadside commercial
    /// buildings: konbini orange, green or blue by seed.
    private func commercialAccent(seed: Int) -> PhysicallyBasedMaterial {
        let palette = [
            UIColor(red: 0.95, green: 0.45, blue: 0.1, alpha: 1),
            UIColor(red: 0.1, green: 0.55, blue: 0.3, alpha: 1),
            UIColor(red: 0.1, green: 0.35, blue: 0.8, alpha: 1),
        ]
        return Self.pbr(palette[abs(seed) % palette.count], roughness: 0.5)
    }

    /// quality40: a convenience store on a suburban plot — parking
    /// lot with stall stripes on the track side, then the store:
    /// concrete body, full-width glass storefront with a warm glow
    /// band, the coloured stripe under the roof, and a tall sign
    /// pole at the lot corner. Real konbini proportions (about
    /// 16 m frontage, 3.9 m eaves, sign pole about 6 m).
    /// quality41: a parked car at real Japanese dimensions —
    /// kei, compact and minivan shapes in the proportions
    /// ChatGPT's review suggested (kei and compact dominant).
    /// Four boxes: body, glass cabin, and one dark box per axle
    /// that reads as wheels and shadow gap from the train.
    private func addParkedCar(name: String, center: SIMD3<Float>, groundY: Float, yaw: Float, seed: Int) {
        let orientation = simd_quatf(angle: yaw, axis: SIMD3<Float>(0, 1, 0))
        let kind = abs(seed) % 5
        let length: Float = kind < 2 ? 3.4 : (kind == 3 ? 4.75 : 4.05)
        let width: Float = kind < 2 ? 1.48 : (kind == 3 ? 1.80 : 1.70)
        let bodyH: Float = kind < 2 ? 0.62 : 0.58
        let cabinH: Float = kind == 3 ? 0.66 : (kind < 2 ? 0.60 : 0.50)
        let cabinLen: Float = kind == 3 ? 2.9 : 1.95
        let palette: [(Float, Float, Float)] = [
            (0.92, 0.92, 0.90), (0.72, 0.74, 0.76), (0.10, 0.10, 0.11),
            (0.45, 0.58, 0.72), (0.60, 0.17, 0.15), (0.78, 0.72, 0.60),
        ]
        let c = palette[abs(seed * 3 + 1) % palette.count]
        let bodyMaterial = Self.pbr(UIColor(red: CGFloat(c.0), green: CGFloat(c.1), blue: CGFloat(c.2), alpha: 1), metallic: 0.35, roughness: 0.42)
        let wheelMaterial = Self.pbr(UIColor(red: 0.05, green: 0.05, blue: 0.06, alpha: 1), roughness: 0.9)
        _ = addBox(parent: world, name: "\(name)-body", size: SIMD3<Float>(width, bodyH, length), position: SIMD3<Float>(center.x, groundY + 0.32 + bodyH / 2, center.z), material: bodyMaterial, orientation: orientation)
        _ = addBox(parent: world, name: "\(name)-cabin", size: SIMD3<Float>(width - 0.18, cabinH, cabinLen), position: SIMD3<Float>(center.x, groundY + 0.32 + bodyH + cabinH / 2, center.z), material: glassMaterial, orientation: orientation)
        for axle in [-1.0, 1.0] {
            let a = Float(axle) * (length / 2 - 0.72)
            let wx = center.x + a * sin(yaw)
            let wz = center.z + a * cos(yaw)
            _ = addBox(parent: world, name: "\(name)-axle-\(Int(axle))", size: SIMD3<Float>(width - 0.25, 0.52, 0.30), position: SIMD3<Float>(wx, groundY + 0.27, wz), material: wheelMaterial, orientation: orientation)
        }
    }

    private func buildConvenienceStore(at distance: Double, sample: RouteSample, sign: Float, groundY: Float, seed: Int) {
        let orientation = simd_quatf(angle: -sample.heading, axis: SIMD3<Float>(0, 1, 0))
        // quality41: the sign pole matches the facade's orange.
        let accent = commercialAccent(seed: 0)

        let pad = groundOffsetPoint(sample, lateral: sign * 9.7)
        _ = addBox(parent: world, name: "konbini-pad-\(seed)", size: SIMD3<Float>(7, 0.07, 13), position: SIMD3<Float>(pad.x, groundY + 0.035, pad.z), material: roadMaterial, orientation: orientation)
        for stripe in 0..<4 {
            let sp = groundOffsetPoint(self.sample(at: distance + Double(stripe) * 2.6 - 3.9), lateral: sign * 7.6)
            _ = addBox(parent: world, name: "konbini-stripe-\(seed)-\(stripe)", size: SIMD3<Float>(2.4, 0.015, 0.14), position: SIMD3<Float>(sp.x, groundY + 0.075, sp.z), material: roofMaterials[2], orientation: orientation)
        }
        // quality41: the body wears the photoreal facade (glass
        // front, interior, stripe and sign are in the texture);
        // the separate glass/glow/band boxes are gone.
        let body = groundOffsetPoint(sample, lateral: sign * 17.7)
        _ = addBox(parent: world, name: "konbini-body-\(seed)", size: SIMD3<Float>(9, 3.9, 13.5), position: SIMD3<Float>(body.x, groundY + 1.95, body.z), material: konbiniFacadeMaterial, orientation: orientation)
        _ = addBox(parent: world, name: "konbini-roof-\(seed)", size: SIMD3<Float>(9.7, 0.22, 14.2), position: SIMD3<Float>(body.x, groundY + 4.0, body.z), material: roofMaterials[0], orientation: orientation)
        let pole = groundOffsetPoint(self.sample(at: distance + 6.5), lateral: sign * 7.3)
        _ = addBox(parent: world, name: "konbini-pole-\(seed)", size: SIMD3<Float>(0.14, 6.2, 0.14), position: SIMD3<Float>(pole.x, groundY + 3.1, pole.z), material: poleMaterial)
        _ = addBox(parent: world, name: "konbini-sign-\(seed)", size: SIMD3<Float>(0.3, 1.15, 1.15), position: SIMD3<Float>(pole.x, groundY + 5.5, pole.z), material: accent, orientation: orientation)
        let signFace = groundOffsetPoint(self.sample(at: distance + 6.5), lateral: sign * 7.08)
        _ = addBox(parent: world, name: "konbini-signface-\(seed)", size: SIMD3<Float>(0.08, 0.9, 0.9), position: SIMD3<Float>(signFace.x, groundY + 5.5, signFace.z), material: roofMaterials[2], orientation: orientation)
        // quality41: parked cars on most stalls, nose-in.
        for stall in 0..<4 where (seed + stall) % 3 != 0 {
            let cp = groundOffsetPoint(self.sample(at: distance + Double(stall) * 2.6 - 3.9), lateral: sign * 7.6)
            addParkedCar(name: "konbini-car-\(seed)-\(stall)", center: cp, groundY: groundY + 0.07, yaw: -sample.heading + Float.pi / 2, seed: seed * 7 + stall)
        }
    }

    /// quality40: a supermarket — a much bigger flat box (about
    /// 34 m frontage, 7 m high) with an accent band under the roof,
    /// a glass entrance, rooftop plant boxes, a wide striped lot
    /// and a tall pole sign.
    private func buildSupermarket(at distance: Double, sample: RouteSample, sign: Float, groundY: Float, seed: Int) {
        let orientation = simd_quatf(angle: -sample.heading, axis: SIMD3<Float>(0, 1, 0))
        // quality41: the sign pole matches the facade's blue.
        let accent = commercialAccent(seed: 2)

        let pad = groundOffsetPoint(sample, lateral: sign * 9.8)
        _ = addBox(parent: world, name: "super-pad-\(seed)", size: SIMD3<Float>(7.2, 0.07, 28), position: SIMD3<Float>(pad.x, groundY + 0.035, pad.z), material: roadMaterial, orientation: orientation)
        for stripe in 0..<6 {
            let sp = groundOffsetPoint(self.sample(at: distance + Double(stripe) * 4 - 10), lateral: sign * 7.6)
            _ = addBox(parent: world, name: "super-stripe-\(seed)-\(stripe)", size: SIMD3<Float>(2.4, 0.015, 0.14), position: SIMD3<Float>(sp.x, groundY + 0.075, sp.z), material: roofMaterials[2], orientation: orientation)
        }
        // quality41: photoreal facade on the body; the separate
        // accent band and entrance glass boxes are gone.
        let body = groundOffsetPoint(sample, lateral: sign * 21)
        _ = addBox(parent: world, name: "super-body-\(seed)", size: SIMD3<Float>(16, 7, 27), position: SIMD3<Float>(body.x, groundY + 3.5, body.z), material: supermarketFacadeMaterial, orientation: orientation)
        _ = addBox(parent: world, name: "super-roof-\(seed)", size: SIMD3<Float>(16.7, 0.3, 27.7), position: SIMD3<Float>(body.x, groundY + 7.15, body.z), material: roofMaterials[1], orientation: orientation)
        for plant in 0..<2 {
            let pp = groundOffsetPoint(self.sample(at: distance + (plant == 0 ? -8.0 : 8.0)), lateral: sign * (plant == 0 ? 19 : 23))
            _ = addBox(parent: world, name: "super-plant-\(seed)-\(plant)", size: SIMD3<Float>(4.5, 1.3, 3.2), position: SIMD3<Float>(pp.x, groundY + 7.9, pp.z), material: concreteMaterial, orientation: orientation)
        }
        let pole = groundOffsetPoint(self.sample(at: distance + 13), lateral: sign * 7.4)
        _ = addBox(parent: world, name: "super-pole-\(seed)", size: SIMD3<Float>(0.18, 9.5, 0.18), position: SIMD3<Float>(pole.x, groundY + 4.75, pole.z), material: poleMaterial)
        _ = addBox(parent: world, name: "super-sign-\(seed)", size: SIMD3<Float>(0.35, 1.9, 2.4), position: SIMD3<Float>(pole.x, groundY + 8.4, pole.z), material: accent, orientation: orientation)
        let signFace = groundOffsetPoint(self.sample(at: distance + 13), lateral: sign * 7.12)
        _ = addBox(parent: world, name: "super-signface-\(seed)", size: SIMD3<Float>(0.08, 1.5, 2.0), position: SIMD3<Float>(signFace.x, groundY + 8.4, signFace.z), material: roofMaterials[2], orientation: orientation)
        // quality41: parked cars across the wider lot.
        for stall in 0..<6 where (seed + stall) % 2 == 0 {
            let cp = groundOffsetPoint(self.sample(at: distance + Double(stall) * 4 - 10), lateral: sign * 7.6)
            addParkedCar(name: "super-car-\(seed)-\(stall)", center: cp, groundY: groundY + 0.07, yaw: -sample.heading + Float.pi / 2, seed: seed * 11 + stall * 3)
        }
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
        var commercialSites: [(chainage: Double, side: Float)] = []
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
            if !buildingClearOfPlatforms(chainage: distance, halfLength: Double(width) / 2, lateral: lateral, halfDepth: depth / 2)
                || !buildingClearOfFans(chainage: distance, halfLength: Double(width) / 2, lateral: lateral, halfDepth: depth / 2) {
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
            // quality41: the TOO RAILWAY depot yard (27,580-27,820)
            // keeps its inland side clear of houses and shops.
            if sign == -seaSideSign(travelDirection: travelDirection), distance > 27_540, distance < 27_860 {
                index += 1
                distance += buildingStep
                continue
            }
            let nearestStation = stationModelPlacements.map { abs($0.chainageM - distance) }.min() ?? .infinity
            // quality40: roadside commercial plots near stations —
            // a convenience store (glass front, stripe band, sign
            // pole, parking) or, rarer, a supermarket (big box,
            // roof band, tall sign, wide lot). They replace house
            // plots and keep 150 m from each other per side.
            let commercialNear = commercialSites.contains { $0.side == sign && abs($0.chainage - distance) < 150 }
            if nearestStation <= 380, !commercialNear, index % 17 == 5 {
                commercialSites.append((chainage: distance, side: sign))
                buildConvenienceStore(at: distance, sample: sample, sign: sign, groundY: groundY, seed: index)
                index += 1
                distance += buildingStep
                continue
            }
            if nearestStation <= 600, !commercialNear, index % 41 == 20 {
                commercialSites.append((chainage: distance, side: sign))
                buildSupermarket(at: distance, sample: sample, sign: sign, groundY: groundY, seed: index)
                index += 1
                distance += buildingStep
                continue
            }
            if nearestStation <= 260, !shed, index % 3 == 0 {
                // Station-front apartment slab instead of a house:
                // flat-roofed, facade-textured, 3-5 floors.
                // quality41: the slabs wear the photoreal apartment
                // elevations; every third is a wide danchi slab
                // with open corridors.
                let aptMaterials = [photoApartmentMaterial, photoApartmentMaterial2, danchiFacadeMaterial]
                let aptKind = (index / 3) % 3
                let aptHeight: Float = aptKind == 2 ? 12.5 : 9.5 + Float(index % 4) * 2.6
                let aptWidth: Float = aptKind == 2 ? 17.5 : 11.5
                let apt = addBox(parent: world, name: "station-apartment-\(index)", size: SIMD3<Float>(aptWidth, aptHeight, 7.6), position: SIMD3<Float>(x, groundY + aptHeight / 2, z), material: aptMaterials[aptKind])
                apt.orientation = simd_quatf(angle: -sample.heading, axis: SIMD3<Float>(0, 1, 0))
                _ = addBox(parent: world, name: "station-apartment-roof-\(index)", size: SIMD3<Float>(aptWidth + 0.4, 0.3, 8.0), position: SIMD3<Float>(x, groundY + aptHeight + 0.15, z), material: roofMaterials[index % roofMaterials.count], orientation: simd_quatf(angle: -sample.heading, axis: SIMD3<Float>(0, 1, 0)))
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
                    // quality41: the monthly car park holds cars.
                    for carSlot in 0..<3 where (index + carSlot) % 2 == 0 {
                        let carPoint = groundOffsetPoint(self.sample(at: distance + Double(carSlot - 1) * 3.4), lateral: offset + sign * 1.2)
                        addParkedCar(name: "lowuse-car-\(index)-\(carSlot)", center: carPoint, groundY: groundY + 0.07, yaw: -sample.heading + Float.pi / 2, seed: index * 5 + carSlot)
                    }
                }
                index += 1
                distance += buildingStep
                continue
            }
            // Every third house wears the full photo facade; its windows
            // and door are painted in, so the separate boxes are skipped.
            let useFacadeTexture = !shed && index % 3 == 2
            let facadeVariants = [houseFacadeMaterial, houseFacadeMaterial2, houseFacadeMaterial3, houseFacadeMaterial4, houseFacadeMaterial5, houseFacadeMaterialGrimed]
            let bodyMaterial = useFacadeTexture ? facadeVariants[(index / 3) % facadeVariants.count] : sceneryMaterials[index % sceneryMaterials.count]
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

            // quality41: the foreground of a Japanese house plot
            // is a block wall or a hedge, not the house itself
            // (photoreal survey cat01). Two of three plots get one,
            // just in front of the house face.
            if !shed, index % 3 != 2 {
                let frontPoint = groundOffsetPoint(sample, lateral: offset - sign * (width / 2 + 0.75))
                if index % 3 == 0 {
                    _ = addBox(parent: world, name: "plot-wall-\(index)", size: SIMD3<Float>(0.18, 1.25, depth * 0.92), position: SIMD3<Float>(frontPoint.x, groundY + 0.62, frontPoint.z), material: concreteMaterial, orientation: simd_quatf(angle: -sample.heading, axis: SIMD3<Float>(0, 1, 0)))
                } else {
                    _ = addBox(parent: world, name: "plot-hedge-\(index)", size: SIMD3<Float>(0.55, 0.85, depth * 0.85), position: SIMD3<Float>(frontPoint.x, groundY + 0.42, frontPoint.z), material: foliageMaterials[index % foliageMaterials.count], orientation: simd_quatf(angle: -sample.heading, axis: SIMD3<Float>(0, 1, 0)))
                }
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
    // route. Crossings now sit wherever the line is at grade or
    // on a low embankment: terrain within 1.6 m of rail level
    // sustained over +/-30 m (the road slopes down the shoulder),
    // clear of station zones, throat fans, the tunnel
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
                if liftHere < 1.6, liftA < 2.0, liftB < 2.0,
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
        // The device log capture is capped, so the crossing list
        // also goes to a small file the CI script collects; that is
        // how the photo tour spots get aimed at real crossings.
        if let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            let text = crossingCenters.map { String(Int($0)) }.joined(separator: ",")
            try? text.write(to: documents.appendingPathComponent("rm-crossings.txt"), atomically: true, encoding: .utf8)
        }
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

        // Road across the apron in three pieces per side, so low
        // embankments (up to about 1.6 m) work too: a centre piece
        // at rail datum, a sloped piece down the shoulder, and an
        // outer piece at field level. On truly flat ground all
        // three are coplanar and the joints vanish.
        let lift = s.elevationM - groundLevelM(at: center)
        var roadBatch = MeshBatchBuilder()
        roadBatch.addBoxAxes(center: pt(0, -0.005, 0), size: SIMD3<Float>(26, 0.07, 5.6), ax: ax, ay: ay, az: az)
        let run: Float = 18
        let drop = max(lift - 0.02, 0)
        let slopePhi = atan2(drop, run)
        let slopeLen = (run * run + drop * drop).squareRoot()
        for sideSign: Float in [-1, 1] {
            let slopeAx = ax * cos(slopePhi) - ay * (sideSign * sin(slopePhi))
            let slopeAy = ax * (sideSign * sin(slopePhi)) + ay * cos(slopePhi)
            roadBatch.addBoxAxes(center: pt(sideSign * 17, -lift / 2 - 0.125, 0), size: SIMD3<Float>(slopeLen + 1.5, 0.3, 5.6), ax: slopeAx, ay: slopeAy, az: az)
            roadBatch.addBoxAxes(center: pt(sideSign * 50.25, -lift + 0.015, 0), size: SIMD3<Float>(49.5, 0.07, 5.6), ax: ax, ay: ay, az: az)
        }
        if let road = roadBatch.build(name: "crossing-road-\(index)", material: roadMaterial) { world.addChild(road) }
        // Waiting pedestrians at every third crossing, standing at
        // the road edge facing the track (quality41 final: people).
        if index % 3 == 0 {
            for sideSign: Float in [-1, 1] {
                let stand = groundOffsetPoint(sample(at: center + 3.6), lateral: sideSign * 5.4)
                let face = -ax * sideSign
                addPerson(position: stand, yaw: atan2(face.x, -face.z), role: sideSign < 0 ? 0 : 2, mode: 0,
                          routeDistanceM: center, walkAxis: ax, range: 0, seedKey: "crossing-\(index)-\(Int(sideSign))")
            }
        }
        // Deck panels flush with the rail head over the tracks, and
        // two terrace steps each side so the road climbs from apron
        // level to deck level.
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
            whiteBatch.addBoxAxes(center: pt(latSign * 9.75, 0.042, 0), size: SIMD3<Float>(6.5, 0.015, 0.14), ax: ax, ay: ay, az: az)
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
        for side: Float in [-1.0, 1.0] {
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
        for side: Float in [-1.0, 1.0] {
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
                for side: Float in [-1.0, 1.0] {
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
        for side: Float in [-1.0, 1.0] {
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
            if let legs = platformPeopleLegs[actor.id] {
                if actor.phase == .walking {
                    let swing: Float = sin(Float(currentSimulationTime) * 7 + Float(stableIndex(actor.id, count: 628)) / 100) * 0.45
                    legs.0.orientation = simd_quatf(angle: swing, axis: SIMD3<Float>(1, 0, 0))
                    legs.1.orientation = simd_quatf(angle: -swing, axis: SIMD3<Float>(1, 0, 0))
                } else {
                    legs.0.orientation = simd_quatf(angle: 0, axis: SIMD3<Float>(1, 0, 0))
                    legs.1.orientation = simd_quatf(angle: 0, axis: SIMD3<Float>(1, 0, 0))
                }
            }
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
        case .zooLine:
            return nil // No AI traffic paths exist on the zoo shuttle.
        case .parkLine:
            return nil // Nor on the theme park shuttle.
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
        // quality41 final: the traffic passengers use the same
        // articulated figure as the placed people (the old two-box
        // dummy with a concrete head is gone). Legs are registered
        // so updateTrafficActors can swing them while walking.
        let figure = makePersonFigure(role: stableIndex(id + "role", count: 9) == 0 ? 2 : 0, seedKey: id)
        platformPeopleLegs[id] = (figure.legL, figure.legR)
        return figure.root
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

    /// quality40: the throat fans widen the formation to a 17 m
    /// deck, but building placement only ever cleared the normal
    /// track width — at Touou-Chihara a tower face landed inside
    /// the fan deck and the siding ran into the building (user
    /// report on the quality38 photos). Inside a fan span a
    /// building's face must stay 11 m or more from the centre.
    private func buildingClearOfFans(chainage: Double, halfLength: Double, lateral: Float, halfDepth: Float) -> Bool {
        if abs(lateral) - halfDepth >= 11 { return true }
        for span in throatFanSpans() {
            if chainage + halfLength > span.start - 10 && chainage - halfLength < span.end + 10 { return false }
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
                    addPlatformPeople(stationID: placement.stationId, archetype: placement.archetype, start: start, end: end, trackLateral: trackLateral, sideSign: sideSign)
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
        // Departure board (quality41 final): a pole-mounted board
        // near the platform centre — dark panel with two lit rows,
        // read from the platform. The zoo and park terminals carry
        // their own boards, so they are skipped here.
        if !name.contains("ZOO") && !name.contains("PARK") {
            let boardChainage = centerChainage - 6
            if boardChainage >= start + 9 {
                let q = orientation(at: boardChainage)
                let poleMaterial = Self.pbr(UIColor(red: 0.25, green: 0.26, blue: 0.28, alpha: 1), metallic: 0.5, roughness: 0.5)
                _ = addBox(parent: world, name: "\(name)-departure-pole", size: SIMD3<Float>(0.09, 2.5, 0.09),
                           position: topPoint(at: boardChainage, u: sideSign * 5.5, v: topV + 1.25),
                           material: poleMaterial, orientation: q)
                _ = addBox(parent: world, name: "\(name)-departure-board", size: SIMD3<Float>(0.08, 0.62, 1.9),
                           position: topPoint(at: boardChainage, u: sideSign * 5.5, v: topV + 2.62),
                           material: Self.pbr(UIColor(red: 0.07, green: 0.07, blue: 0.09, alpha: 1), roughness: 0.4), orientation: q)
                let bandMaterial = Self.pbr(UIColor(red: 0.96, green: 0.89, blue: 0.62, alpha: 1), roughness: 0.35)
                for bandV: Float in [2.74, 2.50] {
                    _ = addBox(parent: world, name: "\(name)-departure-band", size: SIMD3<Float>(0.02, 0.15, 1.7),
                               position: topPoint(at: boardChainage, u: sideSign * 5.5 - sideSign * 0.05, v: topV + bandV),
                               material: bandMaterial, orientation: q)
                }
            }
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
        var cafeBatch = MeshBatchBuilder()
        var shopBatch = MeshBatchBuilder()
        var shrubBlobs: [(center: SIMD3<Float>, radii: SIMD3<Float>)] = []
        let topFull: Float = 0.3065 + 1.10
        // Stations with a loop line (passing waits): their
        // forecourt band is a running track, so furniture that
        // used to stand there has to move (2026-11-11 quality
        // pass for the added passing stations).
        let loopCenters = Set(throatFanSpecs().map { $0.center })

        for (stationIndex, placement) in stationModelPlacements.enumerated() {
            let length = platformLengthM(stationId: placement.stationId, archetype: placement.archetype)
            let start = placement.chainageM - length / 2
            let end = placement.chainageM + length / 2
            let wide = placement.archetype.contains("terminal") || placement.archetype.contains("major") || placement.archetype == "junction_3platform"
            let width: Float = wide ? 6.0 : 4.5
            let isLoopStation = loopCenters.contains(placement.chainageM)
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

                    // -- Ticket gates (quality41 final) at the wide
                    // stations: a row of three gate units under a
                    // canopy on the forecourt walk, in the centre gap
                    // the platform-back fence leaves for the station
                    // core. Flap panels, a coloured top lamp per unit.
                    if wide {
                        let gateFrame = profileStation(at: placement.chainageM, trackLateral: trackLateral)
                        let gateAxisZ = simd_cross(gateFrame.xAxis, gateFrame.yAxis)
                        let gateBasis = simd_quatf(simd_float3x3(gateFrame.xAxis, gateFrame.yAxis, gateAxisZ))
                        let gateCenter = gateFrame.center + gateFrame.xAxis * (sideSign * (backU + (isLoopStation ? 5.6 : 1.25))) + gateFrame.yAxis * 0.03
                        let gateBodyMat = Self.pbr(UIColor(red: 0.62, green: 0.64, blue: 0.66, alpha: 1), metallic: 0.45, roughness: 0.4)
                        let gateFlapMat = Self.pbr(UIColor(red: 0.85, green: 0.55, blue: 0.20, alpha: 1), roughness: 0.5)
                        for gateIndex in -1...1 {
                            let unitCenter = gateCenter + gateAxisZ * (Float(gateIndex) * 1.10)
                            _ = addBox(parent: world, name: "gates-\(placement.stationId)-\(gateIndex)", size: SIMD3<Float>(1.7, 0.95, 0.72),
                                       position: unitCenter + gateFrame.yAxis * 0.475, material: gateBodyMat, orientation: gateBasis)
                            _ = addBox(parent: world, name: "gates-flap-\(placement.stationId)-\(gateIndex)", size: SIMD3<Float>(0.55, 0.62, 0.05),
                                       position: unitCenter + gateFrame.yAxis * 0.55 - gateFrame.xAxis * (sideSign * 0.2), material: gateFlapMat, orientation: gateBasis)
                            _ = addBox(parent: world, name: "gates-lamp-\(placement.stationId)-\(gateIndex)", size: SIMD3<Float>(0.34, 0.06, 0.20),
                                       position: unitCenter + gateFrame.yAxis * 0.99, material: Self.pbr(gateIndex == 0 ? UIColor(red: 0.85, green: 0.20, blue: 0.16, alpha: 1) : UIColor(red: 0.25, green: 0.75, blue: 0.35, alpha: 1), roughness: 0.35), orientation: gateBasis)
                        }
                        _ = addBox(parent: world, name: "gates-canopy-\(placement.stationId)", size: SIMD3<Float>(3.4, 0.12, 4.1),
                                   position: gateCenter + gateFrame.yAxis * 2.62, material: Self.pbr(UIColor(red: 0.30, green: 0.31, blue: 0.33, alpha: 1), metallic: 0.4, roughness: 0.5), orientation: gateBasis)
                        for postOffset: Float in [-1.8, 1.8] {
                            _ = addBox(parent: world, name: "gates-post-\(placement.stationId)", size: SIMD3<Float>(0.09, 2.6, 0.09),
                                       position: gateCenter + gateAxisZ * postOffset + gateFrame.yAxis * 1.3, material: gateBodyMat, orientation: gateBasis)
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
                        var bHeight: Float = 9 + Float((seed * 29) % 70) / 10
                        let bLateral = backLateral + sideSign * (12.5 + bDepth / 2)
                        let bx = bSample.x + bLateral * cos(bSample.heading)
                        let bz = bSample.z + bLateral * sin(bSample.heading)
                        let baseY = bSample.elevationM - 0.06
                        // quality40: every fifth frontage slot is
                        // the station cafe (user reference): two
                        // storeys, and no podium band — the band
                        // would swallow its entrance.
                        let isCafe = abs(seed) % 5 == 2
                        if isCafe { bHeight = 7 }
                        // quality41: the neighbouring slot is a
                        // small shop with the Ema-generated facade.
                        let isShop = abs(seed) % 5 == 3
                        if isShop { bHeight = 7.5 }
                        if isCafe {
                            cafeBatch.addBox(center: SIMD3<Float>(bx, baseY + bHeight / 2, bz), size: SIMD3<Float>(bDepth, bHeight, bWidth), yaw: -bSample.heading)
                        } else if isShop {
                            shopBatch.addBox(center: SIMD3<Float>(bx, baseY + bHeight / 2, bz), size: SIMD3<Float>(bDepth, bHeight, bWidth), yaw: -bSample.heading)
                        } else {
                            bodyBatches[abs(seed) % bodyBatches.count].addBox(center: SIMD3<Float>(bx, baseY + bHeight / 2, bz), size: SIMD3<Float>(bDepth, bHeight, bWidth), yaw: -bSample.heading)
                            baseBatch.addBox(center: SIMD3<Float>(bx, baseY + 1.0, bz), size: SIMD3<Float>(bDepth + 0.15, 2.0, bWidth + 0.15), yaw: -bSample.heading)
                        }
                        roofBatch.addBox(center: SIMD3<Float>(bx, baseY + bHeight + 0.12, bz), size: SIMD3<Float>(bDepth + 0.4, 0.24, bWidth + 0.4), yaw: -bSample.heading)
                    }

                    // quality41: a drink vending machine at the
                    // walkway's edge on the end opposite the
                    // Vending machine by the station front. At
                    // the loop stations the forecourt band is the
                    // loop line itself, so the machine stands on
                    // the platform back instead (2026-11-11).
                    if isLoopStation {
                        let vFrame = profileStation(at: placement.chainageM - length * 0.32, trackLateral: trackLateral)
                        let vAxisZ = simd_cross(vFrame.xAxis, vFrame.yAxis)
                        let vBasis = simd_quatf(simd_float3x3(vFrame.xAxis, vFrame.yAxis, vAxisZ))
                        let vPos = vFrame.center + vFrame.xAxis * (sideSign * (backU - 0.75)) + vFrame.yAxis * (topFull + 0.925)
                        _ = addBox(parent: world, name: "station-vending-\(stationIndex)-\(Int(trackLateral))-\(Int(sideSign))", size: SIMD3<Float>(0.65, 1.85, 1.1), position: vPos, material: vendingFacadeMaterial, orientation: vBasis)
                    } else {
                        let vSample = sample(at: placement.chainageM - length * 0.32)
                        let vLateral = backLateral + sideSign * 2.2
                        let vx = vSample.x + vLateral * cos(vSample.heading)
                        let vz = vSample.z + vLateral * sin(vSample.heading)
                        _ = addBox(parent: world, name: "station-vending-\(stationIndex)-\(Int(trackLateral))-\(Int(sideSign))", size: SIMD3<Float>(0.65, 1.85, 1.1), position: SIMD3<Float>(vx, vSample.elevationM + 0.90, vz), material: vendingFacadeMaterial, orientation: simd_quatf(angle: -vSample.heading, axis: SIMD3<Float>(0, 1, 0)))
                    }
                    // Pedestrian crossing over the loop line on
                    // the station walkway (loop stations): a low
                    // slab between the rails, top below rail head.
                    if isLoopStation {
                        let cFrame = profileStation(at: placement.chainageM, trackLateral: trackLateral)
                        let cAxisZ = simd_cross(cFrame.xAxis, cFrame.yAxis)
                        let cBasis = simd_quatf(simd_float3x3(cFrame.xAxis, cFrame.yAxis, cAxisZ))
                        let cPos = cFrame.center + cFrame.xAxis * (sideSign * 7.54) + cFrame.yAxis * 0.24
                        _ = addBox(parent: world, name: "station-loop-crossing-\(stationIndex)-\(Int(sideSign))", size: SIMD3<Float>(5.4, 0.05, 2.4), position: cPos, material: concreteMaterial, orientation: cBasis)
                    }

                    // -- Night pass P4 (2026-11-11): small life at
                    // the local stations. A car park past the
                    // platform end beside the front road, a bus
                    // stop on the road's outer edge, and a guardrail
                    // run along that edge for the platform span.
                    if !wide {
                        let parkSample = sample(at: end + 26)
                        let parkLateral = backLateral + sideSign * 8
                        let px = parkSample.x + parkLateral * cos(parkSample.heading)
                        let pz = parkSample.z + parkLateral * sin(parkSample.heading)
                        let parkYaw = simd_quatf(angle: -parkSample.heading, axis: SIMD3<Float>(0, 1, 0))
                        _ = addBox(parent: world, name: "station-carpark-\(stationIndex)-\(Int(sideSign))", size: SIMD3<Float>(13, 0.06, 26), position: SIMD3<Float>(px, parkSample.elevationM + 0.03, pz), material: roadMaterial, orientation: parkYaw)
                        for carI in 0..<4 {
                            let carSample = sample(at: end + 19 + Double(carI % 2) * 13)
                            let carLateral = backLateral + sideSign * (5.6 + Float(carI / 2) * 5.2)
                            let cx = carSample.x + carLateral * cos(carSample.heading)
                            let cz = carSample.z + carLateral * sin(carSample.heading)
                            addParkedCar(name: "station-car-\(stationIndex)-\(Int(sideSign))-\(carI)", center: SIMD3<Float>(cx, parkSample.elevationM + 0.06, cz), groundY: parkSample.elevationM + 0.06, yaw: -carSample.heading + Float.pi / 2, seed: stationIndex * 13 + carI * 3 + (sideSign > 0 ? 1 : 0))
                        }
                    }
                    let busSample = sample(at: placement.chainageM + length * 0.18)
                    let busLateral = backLateral + sideSign * 11.7
                    let busX = busSample.x + busLateral * cos(busSample.heading)
                    let busZ = busSample.z + busLateral * sin(busSample.heading)
                    let busYaw = simd_quatf(angle: -busSample.heading, axis: SIMD3<Float>(0, 1, 0))
                    let busPole = ModelEntity(mesh: FallbackCylinderMesh.make(height: 2.6, radius: 0.035), materials: [poleMaterial])
                    busPole.name = "station-busstop-pole-\(stationIndex)-\(Int(sideSign))"
                    busPole.position = SIMD3<Float>(busX, busSample.elevationM + 1.3, busZ)
                    world.addChild(busPole)
                    _ = addBox(parent: world, name: "station-busstop-sign-\(stationIndex)-\(Int(sideSign))", size: SIMD3<Float>(0.06, 0.72, 0.55), position: SIMD3<Float>(busX, busSample.elevationM + 2.25, busZ), material: concreteMaterial, orientation: busYaw)
                    _ = addBox(parent: world, name: "station-busstop-bench-\(stationIndex)-\(Int(sideSign))", size: SIMD3<Float>(0.45, 0.09, 1.8), position: SIMD3<Float>(busX, busSample.elevationM + 0.46, busZ), material: roofMaterials[1], orientation: busYaw)
                    var railPrevTop: SIMD3<Float>? = nil
                    var railPrevMid: SIMD3<Float>? = nil
                    var railD = start
                    while railD <= end {
                        let railFrame = profileStation(at: railD, trackLateral: trackLateral)
                        let railAxisZ = simd_cross(railFrame.xAxis, railFrame.yAxis)
                        let railBase = railFrame.center + railFrame.xAxis * (sideSign * (backU + 11.4)) + railFrame.yAxis * 0.3065
                        let railTop = railBase + railFrame.yAxis * 0.68
                        fenceBatch.addBoxAxes(center: railBase + railFrame.yAxis * 0.34, size: SIMD3<Float>(0.09, 0.68, 0.09), ax: railFrame.xAxis, ay: railFrame.yAxis, az: railAxisZ)
                        if let prevTop = railPrevTop, let prevMid = railPrevMid {
                            fenceBatch.addSegment(from: prevTop, to: railTop, thickness: 0.06)
                            fenceBatch.addSegment(from: prevMid, to: railBase + railFrame.yAxis * 0.38, thickness: 0.05)
                        }
                        railPrevTop = railTop
                        railPrevMid = railBase + railFrame.yAxis * 0.38
                        railD += 8.5
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
        if let mesh = cafeBatch.build(name: "station-front-cafes", material: cafeFacadeMaterial) { world.addChild(mesh) }
        if let mesh = shopBatch.build(name: "station-front-shops", material: shopFacadeMaterial) { world.addChild(mesh) }
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
                // quality41: the river is rebuilt as a river. The
                // water is one band flowing UNDER the bridge across
                // the line (it used to be a strip running along the
                // track at rail level), the deck gains two plate
                // girders, and real piers carry it down to the
                // water. Where the line runs at grade the channel
                // is faked with grass banks wedged under the deck
                // edges, the same trick as the cutting banks below.
                let samples = landmarkSampleChainages(landmark, limit: sampleLimit)
                let midChainage = (landmark.startChainageM + landmark.endChainageM) / 2
                let midSample = sample(at: midChainage)
                let midCenter = routeOffsetPoint(midSample, lateral: 0)
                let midYaw = simd_quatf(angle: -midSample.heading, axis: SIMD3<Float>(0, 1, 0))
                let groundY = groundLevelM(at: midSample)
                let lift = midSample.elevationM - groundY
                let waterY = lift >= 1.2 ? groundY + 0.15 : midCenter.y - 1.5
                addSurfaceBox(parent: world, name: "\(landmark.id)-river", size: SIMD3<Float>(300, 0.24, Float(min(landmark.lengthM * 0.72, 26))),
                              position: SIMD3<Float>(midCenter.x, waterY, midCenter.z), color: water, roughness: 0.12, orientation: midYaw)
                for shoreSide in [-1.0, 1.0] {
                    let shore = routeOffsetPoint(midSample, lateral: 0)
                    let shoreZ = Float(landmark.lengthM * 0.36 + 2.2) * Float(shoreSide)
                    let shoreCenter = SIMD3<Float>(shore.x + shoreZ * sin(midSample.heading), waterY + 0.10, shore.z - shoreZ * cos(midSample.heading))
                    addSurfaceBox(parent: world, name: "\(landmark.id)-shore-\(Int(shoreSide))", size: SIMD3<Float>(300, 0.18, 4.4),
                                  position: shoreCenter, color: UIColor(red: 0.45, green: 0.42, blue: 0.34, alpha: 1), roughness: 1, orientation: midYaw)
                }
                if lift < 1.2 {
                    for bankSide in [-1.0, 1.0] {
                        let bankD = bankSide > 0 ? landmark.endChainageM - 4 : landmark.startChainageM + 4
                        let bankSample = sample(at: bankD)
                        let bankYaw = simd_quatf(angle: -bankSample.heading, axis: SIMD3<Float>(0, 1, 0))
                        let pitch = simd_quatf(angle: Float(bankSide) * 0.22, axis: SIMD3<Float>(1, 0, 0))
                        let bankCenter = routeOffsetPoint(bankSample, lateral: 0)
                        addSurfaceBox(parent: world, name: "\(landmark.id)-bank-\(Int(bankSide))", size: SIMD3<Float>(34, 0.4, 11),
                                      position: SIMD3<Float>(bankCenter.x, bankCenter.y - 1.35, bankCenter.z),
                                      color: grass, roughness: 0.95, orientation: bankYaw * pitch)
                    }
                }
                let girderMaterial = Self.pbr(UIColor(red: 0.30, green: 0.33, blue: 0.36, alpha: 1), metallic: 0.55, roughness: 0.55)
                for (index, chainage) in samples.enumerated() {
                    let sample = sample(at: chainage)
                    let yaw = simd_quatf(angle: -sample.heading, axis: SIMD3<Float>(0, 1, 0))
                    let length = Float(landmark.lengthM / Double(samples.count))
                    let center = routeOffsetPoint(sample, lateral: 0)
                    addSurfaceBox(parent: world, name: "\(landmark.id)-deck-\(index)", size: SIMD3<Float>(8.4, 0.16, length),
                                  position: SIMD3<Float>(center.x, center.y - 0.08, center.z), color: UIColor(red: 0.46, green: 0.48, blue: 0.47, alpha: 1),
                                  roughness: 0.84, orientation: yaw)
                    for side in [-1.0, 1.0] {
                        let edge = routeOffsetPoint(sample, lateral: Float(side) * 4.55)
                        addSurfaceBox(parent: world, name: "\(landmark.id)-parapet-\(index)-\(Int(side))",
                                      size: SIMD3<Float>(0.28, 1.2, length),
                                      position: SIMD3<Float>(edge.x, edge.y + 0.7, edge.z), color: UIColor(red: 0.52, green: 0.54, blue: 0.52, alpha: 1),
                                      roughness: 0.8, orientation: yaw)
                        let girder = routeOffsetPoint(sample, lateral: Float(side) * 2.7)
                        addBox(parent: world, name: "\(landmark.id)-girder-\(index)-\(Int(side))", size: SIMD3<Float>(0.45, 1.05, length),
                               position: SIMD3<Float>(girder.x, center.y - 0.72, girder.z), material: girderMaterial, orientation: yaw)
                    }
                    if index % 2 == 0 {
                        let pierTop = center.y - 0.35
                        let pierH = max(pierTop - (waterY - 0.4), 0.8)
                        addBox(parent: world, name: "\(landmark.id)-pier-\(index)", size: SIMD3<Float>(7.4, pierH, 1.5),
                               position: SIMD3<Float>(center.x, pierTop - pierH / 2, center.z), material: concreteMaterial, orientation: yaw)
                    }
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
        // The loop line is drawn at the multi-track archetypes
        // plus the stations PassingWaitPlanner names for the
        // full diagram build (2026-11-11): the diagram v4 set of
        // 15 passing stations (7 original + 荻沼・小原・
        // ひばりヶ岡・東村川・津田池・三街道・波花・千蔵)
        // carry the same fan + through-loop treatment even
        // though their cores are ordinary two-platform layouts.
        // Every scenery guard keys off this list (fences,
        // walkway slabs, pole/building/tree clearances), so a
        // station added here inherits the whole treatment.
        let extraLoopStations: Set<String> = ["S03", "S04", "S06", "S07", "S09", "S11", "S14", "S15", "S19", "S23", "S24", "S27"]
        var specs: [(center: Double, half: Double)] = []
        for placement in stationModelPlacements {
            if placement.archetype == "major_5track_4platform" || placement.archetype == "passing_3track_2platform" || extraLoopStations.contains(placement.stationId) {
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

    /// Siding lateral across its 340 m fan span. Since the
    /// passing-wait work (2026-11-11) the loop line runs THROUGH
    /// the station at 9.64 m — outside the platform, whose outer
    /// face (platform band ends at 8.12 m) serves the siding with
    /// the standard 1.52 m clearance. The "in" fan diverges over
    /// its first 240 m and then holds; the "out" fan holds and
    /// converges over its last 300 m; between the fans the
    /// through segment (buildThroatFans) stays at 9.64 m.
    private func throatFanLateral(u: Double, tag: String) -> Float {
        func smooth(_ x: Double) -> Double {
            let t = min(max(x, 0), 1)
            return t * t * (3 - 2 * t)
        }
        let shift: Double
        if tag == "in" {
            shift = smooth(u / (240.0 / 340.0))
        } else {
            shift = 1 - smooth((u - 40.0 / 340.0) / (300.0 / 340.0))
        }
        return Float(2.1 + 7.54 * shift)
    }

    private func buildThroatFans(routeVariant: RegionalRouteVariant) {
        guard routeVariant == .mainline || routeVariant == .throughBranch else { return }
        guard let firstSample = samples.first, let lastSample = samples.last, firstSample.distanceM < lastSample.distanceM else { return }
        let railSteel = Self.pbr(UIColor(red: 0.52, green: 0.57, blue: 0.60, alpha: 1), metallic: 0.85, roughness: 0.36)
        let runningBand = Self.pbr(UIColor(red: 0.78, green: 0.82, blue: 0.85, alpha: 1), metallic: 0.95, roughness: 0.12)
        let shoulderMaterial = Self.texturedPBR(.white, roughness: 1, textureName: "scenery_ballast", normalName: "normal_ballast")
        let trackbedMaterial = Self.texturedPBR(.white, roughness: 0.95, textureName: "scenery_trackbed", normalName: "normal_trackbed")
        let deckMaterial = Self.pbr(UIColor(red: 0.46, green: 0.48, blue: 0.47, alpha: 1), roughness: 0.84)
        let fenceMat = Self.pbr(UIColor(red: 0.55, green: 0.57, blue: 0.58, alpha: 1), metallic: 0.6, roughness: 0.45)
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
                if let deck = ribbonEntity(name: "fan-deck-\(Int(spec.center))-\(span.tag)", width: 25, y: -0.495, tileLength: 12, offsets: zeroOffsets, material: deckMaterial, range: range) {
                    world.addChild(deck)
                }
                for side: Float in [-1.0, 1.0] {
                    let sideTag = side > 0 ? "r" : "l"
                    let offsets = samples.map { sample -> Float in
                        let u = (min(max(sample.distanceM, span.start), span.end) - span.start) / 340
                        return side * throatFanLateral(u: u, tag: span.tag)
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
                        stations.append(profileStation(at: d, trackLateral: side * throatFanLateral(u: (d - span.start) / 340, tag: span.tag)))
                        d += 8.5
                    }
                    stations.append(profileStation(at: span.end, trackLateral: side * throatFanLateral(u: 1, tag: span.tag)))
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
            // Passing-wait addendum (2026-11-11): the loop line
            // continues through the station at 9.64 m, outside the
            // platform — the track the waiting train stands on.
            for side: Float in [-1.0, 1.0] {
                let sideTag = side > 0 ? "r" : "l"
                let midStart = spec.center - spec.half
                let midEnd = spec.center + spec.half
                if let lo = samples.firstIndex(where: { $0.distanceM >= midStart - 8.5 }),
                   let hi = samples.lastIndex(where: { $0.distanceM <= midEnd + 8.5 }), lo < hi {
                    let range = lo..<(hi + 1)
                    if let deck = ribbonEntity(name: "fan-mid-deck-\(Int(spec.center))-\(sideTag)", width: 25, y: -0.495, tileLength: 12, offsets: zeroOffsets, material: deckMaterial, range: range) {
                        world.addChild(deck)
                    }
                    let midOffsets = samples.map { _ in side * Float(9.64) }
                    if let bed = ribbonEntity(name: "fan-mid-trackbed-\(Int(spec.center))-\(sideTag)", width: 4.6, y: 0.185, tileLength: 5, offsets: midOffsets, material: trackbedMaterial, range: range) {
                        world.addChild(bed)
                    }
                }
                var stations: [ProfileStation] = []
                var d = midStart
                while d < midEnd {
                    stations.append(profileStation(at: d, trackLateral: side * Float(9.64)))
                    d += 8.5
                }
                stations.append(profileStation(at: midEnd, trackLateral: side * Float(9.64)))
                let prefix = "fan-mid-\(Int(spec.center))-\(sideTag)"
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
                // Fence along the loop's outer edge through the
                // station (2026-11-11 quality pass), with gaps at
                // the walkway crossing and the bicycle shelter.
                var fenceBatch = MeshBatchBuilder()
                var fd = midStart
                while fd < midEnd {
                    let segMid = (fd + min(fd + 8.5, midEnd)) / 2
                    let atWalkway = abs(segMid - spec.center) < 2.2
                    let atShelter = abs(segMid - (spec.center + spec.half * 2 * 0.32)) < 4.8
                    if !atWalkway && !atShelter {
                        let f0 = profileStation(at: fd, trackLateral: side * Float(12.3))
                        let f1 = profileStation(at: min(fd + 8.5, midEnd), trackLateral: side * Float(12.3))
                        let fAxisZ = simd_cross(f0.xAxis, f0.yAxis)
                        let mid = (f0.center + f1.center) / 2
                        for railY: Float in [0.55, 0.95] {
                            fenceBatch.addBoxAxes(center: mid + f0.yAxis * railY, size: SIMD3<Float>(0.05, 0.07, 8.6), ax: f0.xAxis, ay: f0.yAxis, az: fAxisZ)
                        }
                        fenceBatch.addBoxAxes(center: f0.center + f0.yAxis * 0.55, size: SIMD3<Float>(0.09, 1.1, 0.09), ax: f0.xAxis, ay: f0.yAxis, az: fAxisZ)
                    }
                    fd += 8.5
                }
                if let fence = fenceBatch.build(name: "fan-mid-fence-\(Int(spec.center))-\(sideTag)", material: fenceMat) {
                    world.addChild(fence)
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
                // quality41: poles stood inside station zones at
                // platform edges (quality35 photo round); the
                // station area is served by the station's own
                // lighting, so poles skip it.
                if !onSeaSide && !corridorReserved(at: d, landmarks: landmarks) && !inStationZone(d, extraMargin: 10) && !nearThroatFan(d) && !(d > 27_540 && d < 27_860) {
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
