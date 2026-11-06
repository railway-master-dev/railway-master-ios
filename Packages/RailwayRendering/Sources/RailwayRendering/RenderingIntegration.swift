@_exported import RailwayCameraRendering
@_exported import RailwayEnvironmentRendering
@_exported import RailwayQualityRendering
@_exported import RailwayRenderingCore

/// App-owned bridge that applies abstract state to existing RealityKit entities.
/// Implementations should update existing entities rather than rebuilding the route scene each frame.
@MainActor
public protocol RenderingStateApplying: AnyObject {
    func apply(camera: CameraPose, environment: EnvironmentRenderState, quality: RenderQualitySettings)
}

/// Coordinates the three rendering domains once per rendered frame without owning scene geometry.
@MainActor
public final class RailwayRenderingCoordinator {
    public let cameraController: CameraController
    public var qualityController: RenderQualityController
    private weak var applier: (any RenderingStateApplying)?

    public init(
        cameraController: CameraController = CameraController(),
        qualityController: RenderQualityController = RenderQualityController(),
        applier: (any RenderingStateApplying)? = nil
    ) {
        self.cameraController = cameraController
        self.qualityController = qualityController
        self.applier = applier
    }

    /// Resolves camera, environment and quality state, then sends it to the app-owned scene adapter.
    public func update(motion: TrainMotionSample, environment: EnvironmentInput, deltaTime: Double) {
        cameraController.setMotion(motion)
        let cameraPose = cameraController.update(deltaTime: deltaTime)
        let environmentState = EnvironmentRenderResolver.resolve(environment)
        let quality = qualityController.settings
        applier?.apply(camera: cameraPose, environment: environmentState, quality: quality)
    }
}
