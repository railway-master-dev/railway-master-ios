import XCTest
@testable import VehicleGeometryUV

final class VehicleMeshDataTests: XCTestCase {
    func testRoundedLoftCreatesValidMeshWithLongitudinalAndPerimeterUVs() throws {
        let mesh = try XCTUnwrap(VehicleMeshData.roundedLoft(sections: [
            VehicleLoftSection(z: -1, centerX: 0, centerY: 1, width: 2, height: 1, radius: 0.2),
            VehicleLoftSection(z: 1, centerX: 0.1, centerY: 1, width: 2.2, height: 1.1, radius: 0.22)
        ]))

        XCTAssertTrue(mesh.isValid)
        XCTAssertTrue(mesh.supportsNormalMapping)
        XCTAssertEqual(mesh.positions.count, 68)
        XCTAssertEqual(mesh.indices.count, 192)
        XCTAssertEqual(mesh.textureCoordinates[0].x, 0, accuracy: 0.0001)
        XCTAssertEqual(mesh.textureCoordinates[16].x, 0, accuracy: 0.0001)
        XCTAssertEqual(mesh.textureCoordinates[16].y, 1, accuracy: 0.0001)
        XCTAssertEqual(mesh.textureCoordinates[17].x, 1, accuracy: 0.0001)
        XCTAssertEqual(mesh.normals[50].z, -1, accuracy: 0.0001)
        XCTAssertEqual(mesh.normals[67].z, 1, accuracy: 0.0001)
        assertOrthonormalFrames(mesh)
    }

    func testRoundedLoftSortsSectionsByLongitudinalPosition() throws {
        let mesh = try XCTUnwrap(VehicleMeshData.roundedLoft(sections: [
            VehicleLoftSection(z: 2, centerX: 0, centerY: 0, width: 1, height: 1, radius: 0.1),
            VehicleLoftSection(z: -2, centerX: 0, centerY: 0, width: 1, height: 1, radius: 0.1)
        ]))
        XCTAssertEqual(mesh.positions[0].z, -2, accuracy: 0.0001)
        XCTAssertEqual(mesh.positions[17].z, 2, accuracy: 0.0001)
        XCTAssertTrue(mesh.isValid)
        XCTAssertTrue(mesh.supportsNormalMapping)
    }

    func testRoofCrownHasUpwardNormalsAndUnitUVRange() throws {
        let mesh = try XCTUnwrap(VehicleMeshData.roofCrown(length: 10, width: 2.8, centerY: 3.4, rise: 0.2, zStart: -5, widthSegments: 8, lengthSegments: 6))
        XCTAssertTrue(mesh.isValid)
        XCTAssertTrue(mesh.supportsNormalMapping)
        XCTAssertEqual(mesh.positions.count, 63)
        XCTAssertEqual(mesh.indices.count, 8 * 6 * 6)
        XCTAssertTrue(mesh.normals.allSatisfy { $0.y > 0.90 })
        XCTAssertEqual(mesh.textureCoordinates.first?.x, 0)
        XCTAssertEqual(mesh.textureCoordinates.first?.y, 0)
        XCTAssertEqual(mesh.textureCoordinates.last?.x, 1)
        XCTAssertEqual(mesh.textureCoordinates.last?.y, 1)
        assertOrthonormalFrames(mesh)
    }

    func testQuadWindingControlsNormalDirectionAndUVsStayNormalized() throws {
        let corners = [
            SIMD3<Float>(-1, -1, 0), SIMD3<Float>(1, -1, 0),
            SIMD3<Float>(1, 1, 0), SIMD3<Float>(-1, 1, 0)
        ]
        let front = try XCTUnwrap(VehicleMeshData.quad(corners: corners))
        let reverse = try XCTUnwrap(VehicleMeshData.quad(corners: corners, reverseWinding: true))
        XCTAssertTrue(front.isValid)
        XCTAssertTrue(reverse.isValid)
        XCTAssertTrue(front.supportsNormalMapping)
        XCTAssertTrue(reverse.supportsNormalMapping)
        XCTAssertEqual(front.normals[0].z, 1, accuracy: 0.0001)
        XCTAssertEqual(reverse.normals[0].z, -1, accuracy: 0.0001)
        XCTAssertEqual(front.textureCoordinates.min(by: { $0.x < $1.x })?.x, 0)
        XCTAssertEqual(front.textureCoordinates.max(by: { $0.x < $1.x })?.x, 1)
        assertOrthonormalFrames(front)
        assertOrthonormalFrames(reverse)
    }

    func testTangentFramesAreFiniteUnitAndOrthogonalOnQuadLoftAndRoof() throws {
        let quad = try XCTUnwrap(VehicleMeshData.quad(corners: [
            SIMD3<Float>(-1, -1, 0), SIMD3<Float>(1, -1, 0),
            SIMD3<Float>(1, 1, 0), SIMD3<Float>(-1, 1, 0)
        ]))
        let loft = try XCTUnwrap(VehicleMeshData.roundedLoft(sections: [
            VehicleLoftSection(z: -2, centerX: 0, centerY: 0, width: 2, height: 1, radius: 0.2),
            VehicleLoftSection(z: 2, centerX: 0, centerY: 0, width: 2, height: 1, radius: 0.2)
        ]))
        let roof = try XCTUnwrap(VehicleMeshData.roofCrown(length: 8, width: 2.8, centerY: 3, rise: 0.2, zStart: -4, widthSegments: 10, lengthSegments: 8))
        for mesh in [quad, loft, roof] {
            XCTAssertTrue(mesh.supportsNormalMapping)
            assertOrthonormalFrames(mesh)
        }
    }

    func testDegenerateUVsUseDeterministicFallbackAndDisableNormalMapping() throws {
        let positions = [SIMD3<Float>(0, 0, 0), SIMD3<Float>(1, 0, 0), SIMD3<Float>(0, 1, 0)]
        let degenerateUVs = [SIMD2<Float>(0, 0), SIMD2<Float>(0, 0), SIMD2<Float>(0, 0)]
        let first = try XCTUnwrap(VehicleMeshData.fromTriangles(positions: positions, textureCoordinates: degenerateUVs, indices: [0, 1, 2]))
        let repeated = try XCTUnwrap(VehicleMeshData.fromTriangles(positions: positions, textureCoordinates: degenerateUVs, indices: [0, 1, 2]))

        XCTAssertTrue(first.isValid)
        XCTAssertFalse(first.supportsNormalMapping)
        XCTAssertEqual(first.tangents, repeated.tangents)
        XCTAssertEqual(first.bitangents, repeated.bitangents)
        assertOrthonormalFrames(first)
    }

    func testInvalidGeometryInputsAreRejected() {
        XCTAssertNil(VehicleMeshData.roundedLoft(sections: []))
        XCTAssertNil(VehicleMeshData.roundedLoft(sections: [
            VehicleLoftSection(z: 0, centerX: 0, centerY: 0, width: -1, height: 1, radius: 0.1),
            VehicleLoftSection(z: 1, centerX: 0, centerY: 0, width: 1, height: 1, radius: 0.1)
        ]))
        XCTAssertNil(VehicleMeshData.roofCrown(length: 1, width: 1, centerY: 0, rise: 0.1, zStart: 0, widthSegments: 1, lengthSegments: 2))
        XCTAssertNil(VehicleMeshData.quad(corners: [SIMD3<Float>(0, 0, 0)]))
        XCTAssertNil(VehicleMeshData.fromTriangles(positions: [SIMD3<Float>(0, 0, 0)], textureCoordinates: [], indices: [0, 0, 0]))
        XCTAssertNil(VehicleMeshData.fromTriangles(positions: [SIMD3<Float>(0, 0, 0), SIMD3<Float>(1, 0, 0), SIMD3<Float>(0, 1, 0)], textureCoordinates: [SIMD2<Float>(0, 0), SIMD2<Float>(1, 0), SIMD2<Float>(0, 1)], indices: [0, 1, 3]))
    }

    private func assertOrthonormalFrames(
        _ mesh: VehicleMeshData,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertTrue(mesh.isValid, file: file, line: line)
        XCTAssertTrue(mesh.hasOrthonormalTangentFrames, file: file, line: line)
        XCTAssertEqual(mesh.tangents.count, mesh.positions.count, file: file, line: line)
        XCTAssertEqual(mesh.bitangents.count, mesh.positions.count, file: file, line: line)
        for index in mesh.positions.indices {
            let normal = mesh.normals[index]
            let tangent = mesh.tangents[index]
            let bitangent = mesh.bitangents[index]
            XCTAssertEqual(length(tangent), 1, accuracy: 0.002, file: file, line: line)
            XCTAssertEqual(length(bitangent), 1, accuracy: 0.002, file: file, line: line)
            XCTAssertEqual(dot(normal, tangent), 0, accuracy: 0.002, file: file, line: line)
            XCTAssertEqual(dot(normal, bitangent), 0, accuracy: 0.002, file: file, line: line)
            XCTAssertEqual(dot(tangent, bitangent), 0, accuracy: 0.002, file: file, line: line)
        }
    }

    private func dot(_ a: SIMD3<Float>, _ b: SIMD3<Float>) -> Float {
        a.x * b.x + a.y * b.y + a.z * b.z
    }

    private func length(_ vector: SIMD3<Float>) -> Float {
        sqrt(dot(vector, vector))
    }
}
