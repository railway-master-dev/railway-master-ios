import RealityKit
import VehicleGeometryUV

/// Converts platform-neutral, tested mesh data into RealityKit ModelEntity instances.
/// Normal maps remain unbound; meshes without a safe UV-derived basis omit tangent buffers.
enum VehicleAuthoredMesh {
    @discardableResult
    static func quad(
        _ name: String,
        corners: [SIMD3<Float>],
        material: any Material,
        reverseWinding: Bool = false,
        in parent: Entity
    ) -> ModelEntity {
        guard let data = VehicleMeshData.quad(corners: corners, reverseWinding: reverseWinding) else {
            return VehicleGeometry.box(name, size: SIMD3<Float>(0.01, 0.01, 0.01), at: .zero, material: material, in: parent)
        }
        return makeEntity(name, data: data, material: material, fallbackSize: SIMD3<Float>(0.1, 0.1, 0.01), in: parent)
    }

    @discardableResult
    static func roundedLoft(
        _ name: String,
        sections: [VehicleLoftSection],
        material: any Material,
        in parent: Entity
    ) -> ModelEntity {
        guard let data = VehicleMeshData.roundedLoft(sections: sections) else {
            return VehicleGeometry.box(name, size: SIMD3<Float>(0.05, 0.05, 0.05), at: .zero, material: material, in: parent)
        }
        return makeEntity(name, data: data, material: material, fallbackSize: SIMD3<Float>(0.1, 0.1, 0.1), in: parent)
    }

    @discardableResult
    static func roofCrown(
        _ name: String,
        length: Float,
        width: Float,
        centerY: Float,
        rise: Float,
        zStart: Float,
        widthSegments: Int = 20,
        lengthSegments: Int = 12,
        material: any Material,
        in parent: Entity
    ) -> ModelEntity {
        guard let data = VehicleMeshData.roofCrown(
            length: length,
            width: width,
            centerY: centerY,
            rise: rise,
            zStart: zStart,
            widthSegments: widthSegments,
            lengthSegments: lengthSegments
        ) else {
            return VehicleGeometry.box(name, size: SIMD3<Float>(width, 0.04, length), at: SIMD3<Float>(0, centerY, zStart + length * 0.5), material: material, in: parent)
        }
        return makeEntity(name, data: data, material: material, fallbackSize: SIMD3<Float>(width, 0.04, length), in: parent)
    }

    private static func makeEntity(
        _ name: String,
        data: VehicleMeshData,
        material: any Material,
        fallbackSize: SIMD3<Float>,
        in parent: Entity
    ) -> ModelEntity {
        var descriptor = MeshDescriptor(name: name)
        descriptor.positions = MeshBuffers.Positions(data.positions)
        descriptor.normals = MeshBuffers.Normals(data.normals)
        descriptor.textureCoordinates = MeshBuffers.TextureCoordinates(data.textureCoordinates)
        if data.supportsNormalMapping {
            descriptor.tangents = MeshBuffers.Tangents(data.tangents)
            descriptor.bitangents = MeshBuffers.Tangents(data.bitangents)
        }
        descriptor.primitives = .triangles(data.indices)
        let mesh = (try? MeshResource.generate(from: [descriptor])) ?? MeshResource.generateBox(size: fallbackSize)
        let entity = ModelEntity(mesh: mesh, materials: [material])
        entity.name = name
        parent.addChild(entity)
        return entity
    }
}
