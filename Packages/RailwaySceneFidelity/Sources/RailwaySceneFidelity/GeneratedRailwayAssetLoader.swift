import Foundation

public struct GeneratedGLBInspection: Equatable, Sendable {
    public let version: Int
    public let meshCount: Int
    public let nodeCount: Int
    public let accessorCount: Int
    public let primitiveCount: Int
    public let materialCount: Int
    public let externalResourceURICount: Int
    public let embeddedBufferByteCount: Int
}

public enum GeneratedGLBFormatError: Error, Equatable, LocalizedError {
    case truncatedHeader
    case invalidMagic
    case unsupportedVersion(Int)
    case invalidDeclaredLength
    case truncatedChunk
    case missingJSONChunk
    case malformedJSON
    case missingEmbeddedBuffer
    case invalidReference(String)
    case unsupportedGeometry(String)

    public var errorDescription: String? {
        switch self {
        case .truncatedHeader: return "GLB header is truncated."
        case .invalidMagic: return "File is not a binary glTF (GLB) asset."
        case .unsupportedVersion(let version): return "Unsupported GLB version \(version)."
        case .invalidDeclaredLength: return "GLB declared length does not match the file."
        case .truncatedChunk: return "A GLB chunk exceeds the file boundary."
        case .missingJSONChunk: return "GLB JSON chunk is missing."
        case .malformedJSON: return "GLB JSON chunk is malformed."
        case .missingEmbeddedBuffer: return "GLB has no usable embedded binary buffer."
        case .invalidReference(let detail): return "GLB contains an invalid reference: \(detail)."
        case .unsupportedGeometry(let detail): return "GLB geometry is outside the supported subset: \(detail)."
        }
    }
}

/// Structural inspection for the self-contained GLB 2.0 source assets bundled with this package.
public enum GeneratedGLBContainerInspector {
    public static func inspect(fileAt url: URL) throws -> GeneratedGLBInspection {
        try inspect(data: Data(contentsOf: url))
    }

    public static func inspect(data: Data) throws -> GeneratedGLBInspection {
        let document = try ParsedGeneratedGLB(data: data)
        let json = document.json
        let meshes = json["meshes"] as? [[String: Any]] ?? []
        let nodes = json["nodes"] as? [[String: Any]] ?? []
        let accessors = json["accessors"] as? [[String: Any]] ?? []
        let materials = json["materials"] as? [[String: Any]] ?? []
        let primitiveCount = meshes.reduce(0) { $0 + (($1["primitives"] as? [Any])?.count ?? 0) }
        try document.validateReferences()
        let externalURIcount = document.externalURIcount
        return GeneratedGLBInspection(
            version: document.version,
            meshCount: meshes.count,
            nodeCount: nodes.count,
            accessorCount: accessors.count,
            primitiveCount: primitiveCount,
            materialCount: materials.count,
            externalResourceURICount: externalURIcount,
            embeddedBufferByteCount: document.binary.count
        )
    }
}

private struct ParsedGeneratedGLB {
    let version: Int
    let json: [String: Any]
    let binary: Data

    init(data: Data) throws {
        guard data.count >= 12 else { throw GeneratedGLBFormatError.truncatedHeader }
        guard Self.u32(data, at: 0) == 0x46546C67 else { throw GeneratedGLBFormatError.invalidMagic }
        let fileVersion = Int(Self.u32(data, at: 4))
        guard fileVersion == 2 else { throw GeneratedGLBFormatError.unsupportedVersion(fileVersion) }
        guard Int(Self.u32(data, at: 8)) == data.count else { throw GeneratedGLBFormatError.invalidDeclaredLength }

        var cursor = 12
        var parsedJSON: [String: Any]?
        var parsedBinary: Data?
        while cursor < data.count {
            guard cursor + 8 <= data.count else { throw GeneratedGLBFormatError.truncatedChunk }
            let chunkLength = Int(Self.u32(data, at: cursor))
            let chunkType = Self.u32(data, at: cursor + 4)
            cursor += 8
            guard chunkLength >= 0, cursor + chunkLength <= data.count else {
                throw GeneratedGLBFormatError.truncatedChunk
            }
            let chunk = data.subdata(in: cursor..<(cursor + chunkLength))
            cursor += chunkLength
            if chunkType == 0x4E4F534A {
                var jsonBytes = [UInt8](chunk)
                while let last = jsonBytes.last, last == 0 || last == 0x20 || last == 0x09 || last == 0x0A || last == 0x0D {
                    jsonBytes.removeLast()
                }
                guard let value = try? JSONSerialization.jsonObject(with: Data(jsonBytes)),
                      let object = value as? [String: Any] else {
                    throw GeneratedGLBFormatError.malformedJSON
                }
                parsedJSON = object
            } else if chunkType == 0x004E4942 {
                parsedBinary = chunk
            }
        }
        guard let parsedJSON else { throw GeneratedGLBFormatError.missingJSONChunk }
        guard let asset = parsedJSON["asset"] as? [String: Any], asset["version"] as? String == "2.0" else {
            throw GeneratedGLBFormatError.unsupportedGeometry("glTF asset.version is not 2.0")
        }
        guard let parsedBinary else { throw GeneratedGLBFormatError.missingEmbeddedBuffer }
        self.version = fileVersion
        self.json = parsedJSON
        self.binary = parsedBinary
        try validateEmbeddedBuffer()
    }

    var externalURIcount: Int {
        func count(_ value: Any) -> Int {
            if let dictionary = value as? [String: Any] {
                return dictionary.reduce(0) { result, entry in
                    let uriCount: Int
                    if entry.key == "uri", let uri = entry.value as? String, !uri.hasPrefix("data:") {
                        uriCount = 1
                    } else {
                        uriCount = 0
                    }
                    return result + uriCount + count(entry.value)
                }
            }
            if let array = value as? [Any] { return array.reduce(0) { $0 + count($1) } }
            return 0
        }
        return count(json)
    }

    func validateReferences() throws {
        let accessors = json["accessors"] as? [[String: Any]] ?? []
        let views = json["bufferViews"] as? [[String: Any]] ?? []
        let meshes = json["meshes"] as? [[String: Any]] ?? []
        let nodes = json["nodes"] as? [[String: Any]] ?? []
        let scenes = json["scenes"] as? [[String: Any]] ?? []
        for (index, accessor) in accessors.enumerated() {
            if accessor["sparse"] != nil {
                throw GeneratedGLBFormatError.unsupportedGeometry("sparse accessor \(index)")
            }
            guard let viewIndex = accessor["bufferView"] as? Int,
                  views.indices.contains(viewIndex) else {
                throw GeneratedGLBFormatError.invalidReference("accessor \(index) bufferView")
            }
        }
        for (meshIndex, mesh) in meshes.enumerated() {
            for primitive in mesh["primitives"] as? [[String: Any]] ?? [] {
                guard let attributes = primitive["attributes"] as? [String: Int],
                      let positionAccessor = attributes["POSITION"], accessors.indices.contains(positionAccessor) else {
                    throw GeneratedGLBFormatError.invalidReference("mesh \(meshIndex) POSITION")
                }
                for accessorIndex in attributes.values where !accessors.indices.contains(accessorIndex) {
                    throw GeneratedGLBFormatError.invalidReference("mesh \(meshIndex) attribute")
                }
                if let index = primitive["indices"] as? Int, !accessors.indices.contains(index) {
                    throw GeneratedGLBFormatError.invalidReference("mesh \(meshIndex) indices")
                }
            }
        }
        for (nodeIndex, node) in nodes.enumerated() {
            if let meshIndex = node["mesh"] as? Int, !meshes.indices.contains(meshIndex) {
                throw GeneratedGLBFormatError.invalidReference("node \(nodeIndex) mesh")
            }
            for child in node["children"] as? [Int] ?? [] where !nodes.indices.contains(child) {
                throw GeneratedGLBFormatError.invalidReference("node \(nodeIndex) child")
            }
        }
        for scene in scenes {
            for nodeIndex in scene["nodes"] as? [Int] ?? [] where !nodes.indices.contains(nodeIndex) {
                throw GeneratedGLBFormatError.invalidReference("scene node")
            }
        }
    }

    func makeFloat3Accessor(_ accessorIndex: Int) throws -> [SIMD3<Float>] {
        let accessor = try accessor(at: accessorIndex)
        guard accessor["type"] as? String == "VEC3",
              (accessor["componentType"] as? Int) == 5126,
              let count = accessor["count"] as? Int,
              let viewIndex = accessor["bufferView"] as? Int else {
            throw GeneratedGLBFormatError.unsupportedGeometry("POSITION must be float VEC3")
        }
        let view = try bufferView(at: viewIndex)
        let offset = (view["byteOffset"] as? Int ?? 0) + (accessor["byteOffset"] as? Int ?? 0)
        let stride = view["byteStride"] as? Int ?? 12
        guard count >= 0, stride >= 12, offset >= 0, offset + max(count - 1, 0) * stride + (count > 0 ? 12 : 0) <= binary.count else {
            throw GeneratedGLBFormatError.invalidReference("POSITION accessor range")
        }
        return try (0..<count).map { index in
            let start = offset + index * stride
            return SIMD3(Self.float32(binary, at: start), Self.float32(binary, at: start + 4), Self.float32(binary, at: start + 8))
        }
    }

    func makeIndexAccessor(_ accessorIndex: Int?, vertexCount: Int) throws -> [UInt32] {
        guard let accessorIndex else { return (0..<vertexCount).map(UInt32.init) }
        let accessor = try accessor(at: accessorIndex)
        guard accessor["type"] as? String == "SCALAR",
              let componentType = accessor["componentType"] as? Int,
              let count = accessor["count"] as? Int,
              let viewIndex = accessor["bufferView"] as? Int,
              [5121, 5123, 5125].contains(componentType) else {
            throw GeneratedGLBFormatError.unsupportedGeometry("indices must be unsigned scalar values")
        }
        let componentSize = componentType == 5121 ? 1 : (componentType == 5123 ? 2 : 4)
        let view = try bufferView(at: viewIndex)
        let offset = (view["byteOffset"] as? Int ?? 0) + (accessor["byteOffset"] as? Int ?? 0)
        let stride = view["byteStride"] as? Int ?? componentSize
        guard count >= 0, stride >= componentSize, offset >= 0,
              offset + max(count - 1, 0) * stride + (count > 0 ? componentSize : 0) <= binary.count else {
            throw GeneratedGLBFormatError.invalidReference("index accessor range")
        }
        let values = (0..<count).map { index -> UInt32 in
            let start = offset + index * stride
            switch componentType {
            case 5121: return UInt32(binary[start])
            case 5123: return UInt32(Self.u16(binary, at: start))
            default: return Self.u32(binary, at: start)
            }
        }
        guard values.allSatisfy({ $0 < UInt32(vertexCount) }) else {
            throw GeneratedGLBFormatError.invalidReference("index exceeds vertex count")
        }
        return values
    }

    func colorAccessor(_ accessorIndex: Int?) throws -> SIMD4<Float> {
        guard let accessorIndex else { return SIMD4(0.68, 0.72, 0.75, 1) }
        let accessor = try self.accessor(at: accessorIndex)
        guard accessor["type"] as? String == "VEC4",
              let componentType = accessor["componentType"] as? Int,
              let viewIndex = accessor["bufferView"] as? Int,
              let count = accessor["count"] as? Int, count > 0 else {
            throw GeneratedGLBFormatError.unsupportedGeometry("COLOR_0 must be a non-empty VEC4")
        }
        let normalized = accessor["normalized"] as? Bool ?? false
        let view = try bufferView(at: viewIndex)
        let componentSize = componentType == 5126 ? 4 : 1
        let offset = (view["byteOffset"] as? Int ?? 0) + (accessor["byteOffset"] as? Int ?? 0)
        let stride = view["byteStride"] as? Int ?? 4 * componentSize
        guard [5121, 5126].contains(componentType), stride >= 4 * componentSize,
              offset >= 0, offset + 4 * componentSize <= binary.count else {
            throw GeneratedGLBFormatError.unsupportedGeometry("COLOR_0 component encoding")
        }
        var values = (0..<4).map { component -> Float in
            let start = offset + component * componentSize
            if componentType == 5126 { return Self.float32(binary, at: start) }
            let byte = Float(binary[start])
            return normalized ? byte / 255 : byte
        }
        values = values.map { min(max($0, 0), 1) }
        return SIMD4(values[0], values[1], values[2], values[3])
    }

    func node(at index: Int) throws -> [String: Any] {
        let nodes = json["nodes"] as? [[String: Any]] ?? []
        guard nodes.indices.contains(index) else { throw GeneratedGLBFormatError.invalidReference("node index") }
        return nodes[index]
    }

    func mesh(at index: Int) throws -> [String: Any] {
        let meshes = json["meshes"] as? [[String: Any]] ?? []
        guard meshes.indices.contains(index) else { throw GeneratedGLBFormatError.invalidReference("mesh index") }
        return meshes[index]
    }

    func accessor(at index: Int) throws -> [String: Any] {
        let accessors = json["accessors"] as? [[String: Any]] ?? []
        guard accessors.indices.contains(index) else { throw GeneratedGLBFormatError.invalidReference("accessor index") }
        return accessors[index]
    }

    private func bufferView(at index: Int) throws -> [String: Any] {
        let views = json["bufferViews"] as? [[String: Any]] ?? []
        guard views.indices.contains(index) else { throw GeneratedGLBFormatError.invalidReference("bufferView index") }
        let view = views[index]
        let start = view["byteOffset"] as? Int ?? 0
        let length = view["byteLength"] as? Int ?? -1
        guard start >= 0, length >= 0, start + length <= binary.count else {
            throw GeneratedGLBFormatError.invalidReference("bufferView bounds")
        }
        return view
    }

    private func validateEmbeddedBuffer() throws {
        guard let buffers = json["buffers"] as? [[String: Any]], let first = buffers.first,
              buffers.count == 1, first["uri"] == nil,
              let byteLength = first["byteLength"] as? Int,
              byteLength >= 0, byteLength <= binary.count else {
            throw GeneratedGLBFormatError.missingEmbeddedBuffer
        }
        let declaredVersion = (json["asset"] as? [String: Any])?["version"] as? String
        guard declaredVersion == "2.0" else { throw GeneratedGLBFormatError.unsupportedGeometry("unsupported glTF asset version") }
    }

    private static func u16(_ data: Data, at offset: Int) -> UInt16 {
        UInt16(data[offset]) | (UInt16(data[offset + 1]) << 8)
    }

    private static func u32(_ data: Data, at offset: Int) -> UInt32 {
        UInt32(data[offset]) | (UInt32(data[offset + 1]) << 8) | (UInt32(data[offset + 2]) << 16) | (UInt32(data[offset + 3]) << 24)
    }

    private static func float32(_ data: Data, at offset: Int) -> Float {
        Float(bitPattern: u32(data, at: offset))
    }
}

#if canImport(RealityKit) && canImport(UIKit)
import RealityKit
import UIKit
import simd

public enum RailwayGeneratedAssetLoaderError: Error, LocalizedError {
    case sourceAssetMissing(RailwayGenerated3DAsset)
    case unsupportedNodeMatrix(String)
    case unsupportedPrimitiveMode(String)

    public var errorDescription: String? {
        switch self {
        case .sourceAssetMissing(let asset): return "Bundled GLB source asset \(asset.rawValue) is missing."
        case .unsupportedNodeMatrix(let node): return "GLB node matrix is not supported by this source-asset loader: \(node)."
        case .unsupportedPrimitiveMode(let mesh): return "GLB primitive mode is not triangles: \(mesh)."
        }
    }
}

/// Main-thread RealityKit importer for the self-contained, static GLB subset used by the bundled original-procedural models.
/// It converts per-mesh GLB vertex colors to SimpleMaterial colors and caches decoded meshes across scene rebuilds.
@MainActor
public enum RailwayGeneratedAssetLoader {
    private static var documents: [String: ParsedGeneratedGLB] = [:]
    private static var meshes: [String: MeshResource] = [:]

    public static func loadModel(for asset: RailwayGenerated3DAsset) throws -> Entity {
        let document = try parsedDocument(for: asset)
        let result = Entity()
        result.name = "Generated3D_\(asset.rawValue)"
        let sceneIndex = document.json["scene"] as? Int ?? 0
        let scenes = document.json["scenes"] as? [[String: Any]] ?? []
        let roots: [Int]
        if scenes.indices.contains(sceneIndex), let sceneRoots = scenes[sceneIndex]["nodes"] as? [Int] {
            roots = sceneRoots
        } else {
            roots = Self.rootNodeIndices(in: document)
        }
        var activePath = Set<Int>()
        for nodeIndex in roots {
            result.addChild(try makeNode(nodeIndex, asset: asset, document: document, activePath: &activePath))
        }
        return result
    }

    private static func parsedDocument(for asset: RailwayGenerated3DAsset) throws -> ParsedGeneratedGLB {
        if let cached = documents[asset.rawValue] { return cached }
        guard let url = RailwayGeneratedAssetCatalog.sourceModelURL(for: asset) else {
            throw RailwayGeneratedAssetLoaderError.sourceAssetMissing(asset)
        }
        let document = try ParsedGeneratedGLB(data: Data(contentsOf: url))
        try document.validateReferences()
        documents[asset.rawValue] = document
        return document
    }

    private static func rootNodeIndices(in document: ParsedGeneratedGLB) -> [Int] {
        let nodes = document.json["nodes"] as? [[String: Any]] ?? []
        let children = Set(nodes.flatMap { $0["children"] as? [Int] ?? [] })
        return nodes.indices.filter { !children.contains($0) }
    }

    private static func makeNode(
        _ index: Int,
        asset: RailwayGenerated3DAsset,
        document: ParsedGeneratedGLB,
        activePath: inout Set<Int>
    ) throws -> Entity {
        guard !activePath.contains(index) else { throw GeneratedGLBFormatError.invalidReference("cyclic node hierarchy") }
        let source = try document.node(at: index)
        let name = source["name"] as? String ?? "node_\(index)"
        if source["matrix"] != nil { throw RailwayGeneratedAssetLoaderError.unsupportedNodeMatrix(name) }
        var entity = Entity()
        entity.name = name
        let translation = Self.vector3(source["translation"], fallback: SIMD3<Float>(repeating: 0))
        let scale = Self.vector3(source["scale"], fallback: SIMD3<Float>(repeating: 1))
        let rotationValues = source["rotation"] as? [NSNumber] ?? []
        let rotation = rotationValues.count == 4
            ? simd_quatf(ix: rotationValues[0].floatValue, iy: rotationValues[1].floatValue,
                         iz: rotationValues[2].floatValue, r: rotationValues[3].floatValue)
            : simd_quatf(angle: 0, axis: SIMD3<Float>(0, 1, 0))
        entity.transform = Transform(scale: scale, rotation: rotation, translation: translation)

        if let meshIndex = source["mesh"] as? Int {
            let mesh = try document.mesh(at: meshIndex)
            let primitives = mesh["primitives"] as? [[String: Any]] ?? []
            for (primitiveIndex, primitive) in primitives.enumerated() {
                let mode = primitive["mode"] as? Int ?? 4
                guard mode == 4 else { throw RailwayGeneratedAssetLoaderError.unsupportedPrimitiveMode(name) }
                guard let attributes = primitive["attributes"] as? [String: Int],
                      let positionAccessor = attributes["POSITION"] else {
                    throw GeneratedGLBFormatError.invalidReference("mesh POSITION")
                }
                let positions = try document.makeFloat3Accessor(positionAccessor)
                let indices = try document.makeIndexAccessor(primitive["indices"] as? Int, vertexCount: positions.count)
                guard !positions.isEmpty, indices.count >= 3, indices.count.isMultiple(of: 3) else {
                    throw GeneratedGLBFormatError.unsupportedGeometry("triangle index count")
                }
                let meshCacheKey = "\(asset.rawValue):\(meshIndex):\(primitiveIndex)"
                let meshResource: MeshResource
                if let cached = meshes[meshCacheKey] {
                    meshResource = cached
                } else {
                    var descriptor = MeshDescriptor(name: meshCacheKey)
                    descriptor.positions = MeshBuffers.Positions(positions)
                    descriptor.normals = MeshBuffers.Normals(Self.vertexNormals(positions: positions, indices: indices))
                    descriptor.primitives = .triangles(indices)
                    meshResource = try MeshResource.generate(from: [descriptor])
                    meshes[meshCacheKey] = meshResource
                }
                let color = try document.colorAccessor(attributes["COLOR_0"])
                let material = SimpleMaterial(
                    color: UIColor(red: CGFloat(color.x), green: CGFloat(color.y), blue: CGFloat(color.z), alpha: CGFloat(color.w)),
                    roughness: Self.roughness(for: name),
                    isMetallic: Self.isMetallic(name)
                )
                let model = ModelEntity(mesh: meshResource, materials: [material])
                model.name = "\(name)_primitive_\(primitiveIndex)"
                entity.addChild(model)
            }
        }

        activePath.insert(index)
        defer { activePath.remove(index) }
        for childIndex in source["children"] as? [Int] ?? [] {
            entity.addChild(try makeNode(childIndex, asset: asset, document: document, activePath: &activePath))
        }
        return entity
    }

    private static func vector3(_ value: Any?, fallback: SIMD3<Float>) -> SIMD3<Float> {
        guard let numbers = value as? [NSNumber], numbers.count == 3 else { return fallback }
        return SIMD3(numbers[0].floatValue, numbers[1].floatValue, numbers[2].floatValue)
    }

    private static func vertexNormals(positions: [SIMD3<Float>], indices: [UInt32]) -> [SIMD3<Float>] {
        var normals = Array(repeating: SIMD3<Float>.zero, count: positions.count)
        for start in stride(from: 0, to: indices.count - 2, by: 3) {
            let a = Int(indices[start]), b = Int(indices[start + 1]), c = Int(indices[start + 2])
            let face = simd_cross(positions[b] - positions[a], positions[c] - positions[a])
            normals[a] += face
            normals[b] += face
            normals[c] += face
        }
        return normals.map { simd_length_squared($0) > 1e-10 ? simd_normalize($0) : SIMD3<Float>(0, 1, 0) }
    }

    private static func roughness(for name: String) -> Float {
        let lower = name.lowercased()
        if lower.contains("glass") || lower.contains("window") { return 0.24 }
        if lower.contains("rail") || lower.contains("metal") || lower.contains("steel") { return 0.32 }
        return 0.76
    }

    private static func isMetallic(_ name: String) -> Bool {
        let lower = name.lowercased()
        return lower.contains("rail") || lower.contains("metal") || lower.contains("steel") || lower.contains("bogie")
    }
}
#endif
