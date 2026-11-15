import XCTest
@testable import RailwaySceneFidelity

final class SceneTrafficActorTests: XCTestCase {
    func testProjectorUsesCurvedRouteFrameAndPreservesStableActorIdentity() throws {
        let route = try SceneChainageRoute(controlPoints: [
            SceneRouteControlPoint(chainageM: 0, position: SceneVector3(0, 0, 0),
                                   tangentPerMeter: SceneVector3(0, 0, 1)),
            SceneRouteControlPoint(chainageM: 100, position: SceneVector3(12, 0, 98),
                                   tangentPerMeter: SceneVector3(0.2, 0, 0.98)),
            SceneRouteControlPoint(chainageM: 220, position: SceneVector3(54, 0, 210),
                                   tangentPerMeter: SceneVector3(0.45, 0, 0.89))
        ])
        let inputs = [
            SceneTrafficActorInput(id: "scenario/road/car-2", kind: .roadVehicle,
                routePathID: "mainline", chainageM: 80, lateralOffsetM: -7,
                headingRadians: 0, speedMps: 11, lengthM: 4.5, isVisible: true,
                wheelRotationRadians: 2.4),
            SceneTrafficActorInput(id: "scenario/train/west-1", kind: .train,
                routePathID: "mainline", chainageM: 120, lateralOffsetM: 2.1,
                headingRadians: .pi, speedMps: 15, lengthM: 110, isVisible: true),
            SceneTrafficActorInput(id: "scenario/platform/person-1", kind: .platformPassenger,
                routePathID: "mainline", chainageM: 150, lateralOffsetM: 4.4,
                headingRadians: 0, speedMps: 1.1, lengthM: 0.5, isVisible: true,
                isWalking: true, walkCycleRadians: 1.2),
            SceneTrafficActorInput(id: "scenario/branch/train-1", kind: .train,
                routePathID: "branch", chainageM: 120, lateralOffsetM: 0,
                headingRadians: 0, speedMps: 12, lengthM: 100, isVisible: true)
        ]

        let poses = SceneTrafficActorProjector.project(inputs, on: route, supportedRoutePathIDs: ["mainline"])
        XCTAssertEqual(poses.map(\.id), ["scenario/platform/person-1", "scenario/road/car-2", "scenario/train/west-1"])

        let reverseTrain = try XCTUnwrap(poses.first { $0.id == "scenario/train/west-1" })
        let routeFrame = try XCTUnwrap(route.frame(at: 120))
        // batch56: the projector places actors on the SCENE's
        // lateral axis, which is the negative of the route frame's
        // right vector (see SceneTrafficActorProjector) — a
        // positive lateral offset lands at position − right ×
        // offset. The old assertion mirrored the projector's own
        // formula and so could not catch the sign error against
        // the scene convention.
        XCTAssertEqual(reverseTrain.position.x,
                       routeFrame.position.x - routeFrame.right.x * 2.1, accuracy: 1e-8)
        XCTAssertEqual(reverseTrain.forward.dot(routeFrame.forward), -1, accuracy: 1e-7)
        XCTAssertEqual(reverseTrain.up.dot(routeFrame.up), 1, accuracy: 1e-7)
        // batch58: the POSE basis must stay right-handed in the
        // route frame even though the position offset uses the
        // scene lateral. For a π heading the pose right is the
        // negated frame right, and right × up must reproduce the
        // pose forward — batch56's scene-lateral basis was a
        // reflection (right × up = −forward), which the adapter
        // rendered as a world-axis-aligned consist lying across
        // the track.
        XCTAssertEqual(reverseTrain.right.dot(routeFrame.right), -1, accuracy: 1e-7)
        let handedness = reverseTrain.right.cross(reverseTrain.up)
        XCTAssertEqual(handedness.dot(reverseTrain.forward), 1, accuracy: 1e-7)

        let pedestrian = try XCTUnwrap(poses.first { $0.kind == .platformPassenger })
        XCTAssertTrue(pedestrian.isWalking)
        XCTAssertEqual(pedestrian.walkCycleRadians, 1.2)
        XCTAssertTrue(pedestrian.position.length.isFinite)
    }

    func testProjectorSkipsOutOfRangeOrNonFiniteActorWithoutChangingOtherIDs() throws {
        let route = try SceneChainageRoute(controlPoints: [
            SceneRouteControlPoint(chainageM: 0, position: .zero),
            SceneRouteControlPoint(chainageM: 100, position: SceneVector3(0, 0, 100))
        ])
        let poses = SceneTrafficActorProjector.project([
            SceneTrafficActorInput(id: "ok", kind: .roadVehicle, routePathID: "mainline",
                chainageM: 50, lateralOffsetM: 0, headingRadians: 0, speedMps: 4,
                lengthM: 4, isVisible: true),
            SceneTrafficActorInput(id: "outside", kind: .train, routePathID: "mainline",
                chainageM: 101, lateralOffsetM: 0, headingRadians: 0, speedMps: 1,
                lengthM: 20, isVisible: true),
            SceneTrafficActorInput(id: "nan", kind: .platformPassenger, routePathID: "mainline",
                chainageM: .nan, lateralOffsetM: 0, headingRadians: 0, speedMps: 1,
                lengthM: 0.5, isVisible: true)
        ], on: route)

        XCTAssertEqual(poses.map(\.id), ["ok"])
    }
}
