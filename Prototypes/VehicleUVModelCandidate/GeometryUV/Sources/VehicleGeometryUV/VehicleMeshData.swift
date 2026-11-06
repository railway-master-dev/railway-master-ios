import Foundation

public struct VehicleLoftSection: Sendable {
    public let z: Float
    public let centerX: Float
    public let centerY: Float
    public let width: Float
    public let height: Float
    public let radius: Float

    public init(z: Float, centerX: Float, centerY: Float, width: Float, height: Float, radius: Float) {
        self.z = z
        self.centerX = centerX
        self.centerY = centerY
        self.width = width
        self.height = height
        self.radius = radius
    }
}

public struct VehicleMeshData: Sendable {
    public let positions: [SIMD3<Float>]
    public let normals: [SIMD3<Float>]
    public let textureCoordinates: [SIMD2<Float>]
    public let tangents: [SIMD3<Float>]
    public let bitangents: [SIMD3<Float>]
    public let indices: [UInt32]
    /// False when any triangle cannot derive a trustworthy tangent basis from its UVs.
    public let supportsNormalMapping: Bool

    public var hasFiniteAttributes: Bool {
        positions.allSatisfy { Self.isFinite($0) }
            && normals.allSatisfy { Self.isFinite($0) }
            && textureCoordinates.allSatisfy { $0.x.isFinite && $0.y.isFinite }
            && tangents.allSatisfy { Self.isFinite($0) }
            && bitangents.allSatisfy { Self.isFinite($0) }
    }

    public var hasUnitNormals: Bool {
        normals.allSatisfy { abs(Self.length($0) - 1) < 0.002 }
    }

    public var hasOrthonormalTangentFrames: Bool {
        guard normals.count == positions.count,
              tangents.count == positions.count,
              bitangents.count == positions.count else { return false }
        return normals.indices.allSatisfy { index in
            let normal = normals[index]
            let tangent = tangents[index]
            let bitangent = bitangents[index]
            return abs(Self.length(tangent) - 1) < 0.002
                && abs(Self.length(bitangent) - 1) < 0.002
                && abs(Self.dot(normal, tangent)) < 0.002
                && abs(Self.dot(normal, bitangent)) < 0.002
                && abs(Self.dot(tangent, bitangent)) < 0.002
        }
    }

    public var hasNormalizedUVs: Bool {
        textureCoordinates.allSatisfy { $0.x >= -0.0001 && $0.x <= 1.0001 && $0.y >= -0.0001 && $0.y <= 1.0001 }
    }

    public var hasValidTriangleIndices: Bool {
        !indices.isEmpty && indices.count.isMultiple(of: 3) && indices.allSatisfy { Int($0) < positions.count }
    }

    public var isValid: Bool {
        positions.count >= 3
            && normals.count == positions.count
            && textureCoordinates.count == positions.count
            && hasFiniteAttributes
            && hasUnitNormals
            && hasOrthonormalTangentFrames
            && hasNormalizedUVs
            && hasValidTriangleIndices
    }

    /// Generates a mesh from triangle indices and UVs. Degenerate UV/geometry triangles get
    /// deterministic fallback frames, but disable normal-map support for the mesh.
    public static func fromTriangles(
        positions: [SIMD3<Float>],
        textureCoordinates: [SIMD2<Float>],
        indices: [UInt32]
    ) -> VehicleMeshData? {
        guard positions.count >= 3,
              textureCoordinates.count == positions.count,
              positions.allSatisfy({ isFinite($0) }),
              textureCoordinates.allSatisfy({ $0.x.isFinite && $0.y.isFinite }),
              indices.count >= 3,
              indices.count.isMultiple(of: 3),
              indices.allSatisfy({ Int($0) < positions.count }) else { return nil }
        return finish(positions: positions, textureCoordinates: textureCoordinates, indices: indices)
    }

    /// Builds rounded-rectangle cross-sections along the car length, including separately UV-mapped end caps.
    /// Side U follows longitudinal Z and V follows each ring's perimeter; cap UVs map across the end face.
    public static func roundedLoft(sections: [VehicleLoftSection], pointsPerCorner: Int = 4) -> VehicleMeshData? {
        guard sections.count >= 2, pointsPerCorner >= 2,
              sections.allSatisfy({ $0.z.isFinite && $0.centerX.isFinite && $0.centerY.isFinite && $0.width.isFinite && $0.height.isFinite && $0.radius.isFinite && $0.width > 0 && $0.height > 0 }) else {
            return nil
        }
        let ordered = sections.sorted { $0.z < $1.z }
        for index in 1..<ordered.count where ordered[index].z - ordered[index - 1].z <= 0.0001 { return nil }

        let ringSize = pointsPerCorner * 4
        let sideRingSize = ringSize + 1 // duplicate seam vertex so V=0 and V=1 do not interpolate across the wrap
        let minZ = ordered[0].z
        let maxZ = ordered[ordered.count - 1].z
        let zSpan = max(maxZ - minZ, 0.001)
        var positions: [SIMD3<Float>] = []
        var uvs: [SIMD2<Float>] = []
        var rings: [[SIMD3<Float>]] = []
        positions.reserveCapacity(ordered.count * sideRingSize + ringSize * 2 + 2)
        uvs.reserveCapacity(positions.capacity)
        rings.reserveCapacity(ordered.count)

        for section in ordered {
            let halfWidth = max(section.width * 0.5, 0.001)
            let halfHeight = max(section.height * 0.5, 0.001)
            let radius = min(max(section.radius, 0.001), min(halfWidth, halfHeight) * 0.95)
            let right = section.centerX + halfWidth - radius
            let left = section.centerX - halfWidth + radius
            let top = section.centerY + halfHeight - radius
            let bottom = section.centerY - halfHeight + radius
            let corners: [(Float, Float, Float)] = [
                (right, bottom, -Float.pi * 0.5),
                (right, top, 0),
                (left, top, Float.pi * 0.5),
                (left, bottom, Float.pi)
            ]
            var ring: [SIMD3<Float>] = []
            for (cx, cy, startAngle) in corners {
                for step in 0..<pointsPerCorner {
                    let angle = startAngle + Float(step) * (Float.pi * 0.5 / Float(pointsPerCorner))
                    ring.append(SIMD3<Float>(cx + cos(angle) * radius, cy + sin(angle) * radius, section.z))
                }
            }
            let edgeLengths = ring.indices.map { index in length(ring[(index + 1) % ring.count] - ring[index]) }
            let perimeter = max(edgeLengths.reduce(0, +), 0.001)
            var cumulative = [Float](repeating: 0, count: ringSize + 1)
            for index in 0..<ringSize { cumulative[index + 1] = cumulative[index] + edgeLengths[index] }
            for index in 0...ringSize {
                positions.append(ring[index % ringSize])
                let v = index == ringSize ? 1 : cumulative[index] / perimeter
                uvs.append(SIMD2<Float>((section.z - minZ) / zSpan, v))
            }
            rings.append(ring)
        }

        var indices: [UInt32] = []
        for ring in 0..<(ordered.count - 1) {
            let first = ring * sideRingSize
            let second = (ring + 1) * sideRingSize
            for point in 0..<ringSize {
                let a = UInt32(first + point)
                let b = UInt32(first + point + 1)
                let c = UInt32(second + point + 1)
                let d = UInt32(second + point)
                indices.append(contentsOf: [a, b, c, a, c, d])
            }
        }

        func appendCap(_ ring: [SIMD3<Float>], center: SIMD3<Float>, front: Bool) {
            let minX = ring.map(\.x).min() ?? center.x
            let maxX = ring.map(\.x).max() ?? center.x
            let minY = ring.map(\.y).min() ?? center.y
            let maxY = ring.map(\.y).max() ?? center.y
            let spanX = max(maxX - minX, 0.001)
            let spanY = max(maxY - minY, 0.001)
            let capStart = positions.count
            for point in ring {
                positions.append(point)
                uvs.append(SIMD2<Float>((point.x - minX) / spanX, (point.y - minY) / spanY))
            }
            let centerIndex = UInt32(positions.count)
            positions.append(center)
            uvs.append(SIMD2<Float>((center.x - minX) / spanX, (center.y - minY) / spanY))
            for point in 0..<ringSize {
                let next = (point + 1) % ringSize
                if front {
                    indices.append(contentsOf: [centerIndex, UInt32(capStart + next), UInt32(capStart + point)])
                } else {
                    indices.append(contentsOf: [centerIndex, UInt32(capStart + point), UInt32(capStart + next)])
                }
            }
        }

        let firstSection = ordered[0]
        appendCap(rings[0], center: SIMD3<Float>(firstSection.centerX, firstSection.centerY, firstSection.z), front: true)
        let lastSection = ordered[ordered.count - 1]
        appendCap(rings[rings.count - 1], center: SIMD3<Float>(lastSection.centerX, lastSection.centerY, lastSection.z), front: false)
        return fromTriangles(positions: positions, textureCoordinates: uvs, indices: indices)
    }

    /// Builds an upward-facing crowned roof surface with explicit cross-car/longitudinal UVs.
    public static func roofCrown(
        length: Float,
        width: Float,
        centerY: Float,
        rise: Float,
        zStart: Float,
        widthSegments: Int = 20,
        lengthSegments: Int = 12
    ) -> VehicleMeshData? {
        guard length.isFinite, width.isFinite, centerY.isFinite, rise.isFinite, zStart.isFinite,
              length > 0, width > 0, widthSegments >= 2, lengthSegments >= 2 else { return nil }
        var positions: [SIMD3<Float>] = []
        var uvs: [SIMD2<Float>] = []
        positions.reserveCapacity((widthSegments + 1) * (lengthSegments + 1))
        uvs.reserveCapacity((widthSegments + 1) * (lengthSegments + 1))
        for iz in 0...lengthSegments {
            let v = Float(iz) / Float(lengthSegments)
            let z = zStart + length * v
            for ix in 0...widthSegments {
                let u = Float(ix) / Float(widthSegments)
                let x = -width * 0.5 + width * u
                let ratio = min(max(x / max(width * 0.5, 0.001), -1), 1)
                let y = centerY + rise * sqrt(max(0, 1 - ratio * ratio))
                positions.append(SIMD3<Float>(x, y, z))
                uvs.append(SIMD2<Float>(u, v))
            }
        }
        var indices: [UInt32] = []
        for iz in 0..<lengthSegments {
            for ix in 0..<widthSegments {
                let a = UInt32(iz * (widthSegments + 1) + ix)
                let b = a + 1
                let d = UInt32((iz + 1) * (widthSegments + 1) + ix)
                let c = d + 1
                indices.append(contentsOf: [a, c, b, a, d, c])
            }
        }
        return fromTriangles(positions: positions, textureCoordinates: uvs, indices: indices)
    }

    /// Builds a single planar quad; UVs span its two largest dimensions.
    public static func quad(corners: [SIMD3<Float>], reverseWinding: Bool = false) -> VehicleMeshData? {
        guard corners.count == 4, corners.allSatisfy({ isFinite($0) }) else { return nil }
        let indices: [UInt32] = reverseWinding ? [0, 2, 1, 0, 3, 2] : [0, 1, 2, 0, 2, 3]
        return fromTriangles(positions: corners, textureCoordinates: projectedUVs(corners), indices: indices)
    }

    private static func finish(positions: [SIMD3<Float>], textureCoordinates: [SIMD2<Float>], indices: [UInt32]) -> VehicleMeshData? {
        guard positions.count == textureCoordinates.count,
              indices.count >= 3,
              indices.count.isMultiple(of: 3),
              indices.allSatisfy({ Int($0) < positions.count }) else { return nil }
        var normals = [SIMD3<Float>](repeating: .zero, count: positions.count)
        var hasSafeNormalGeometry = true
        for offset in stride(from: 0, to: indices.count, by: 3) {
            let ia = Int(indices[offset])
            let ib = Int(indices[offset + 1])
            let ic = Int(indices[offset + 2])
            let faceNormal = cross(positions[ib] - positions[ia], positions[ic] - positions[ia])
            if length(faceNormal) <= 0.000001 {
                hasSafeNormalGeometry = false
                continue
            }
            normals[ia] += faceNormal
            normals[ib] += faceNormal
            normals[ic] += faceNormal
        }
        normals = normals.map { normal in
            let magnitude = length(normal)
            return magnitude > 0.000001 ? normal / magnitude : SIMD3<Float>(0, 1, 0)
        }
        let frame = calculateTangentFrames(positions: positions, normals: normals, textureCoordinates: textureCoordinates, indices: indices)
        return VehicleMeshData(
            positions: positions,
            normals: normals,
            textureCoordinates: textureCoordinates,
            tangents: frame.tangents,
            bitangents: frame.bitangents,
            indices: indices,
            supportsNormalMapping: hasSafeNormalGeometry && frame.supportsNormalMapping
        )
    }

    private static func calculateTangentFrames(
        positions: [SIMD3<Float>],
        normals: [SIMD3<Float>],
        textureCoordinates: [SIMD2<Float>],
        indices: [UInt32]
    ) -> (tangents: [SIMD3<Float>], bitangents: [SIMD3<Float>], supportsNormalMapping: Bool) {
        var tangentSums = [SIMD3<Float>](repeating: .zero, count: positions.count)
        var bitangentSums = [SIMD3<Float>](repeating: .zero, count: positions.count)
        var hasContribution = [Bool](repeating: false, count: positions.count)
        var supportsNormalMapping = true

        for offset in stride(from: 0, to: indices.count, by: 3) {
            let ia = Int(indices[offset])
            let ib = Int(indices[offset + 1])
            let ic = Int(indices[offset + 2])
            let edge1 = positions[ib] - positions[ia]
            let edge2 = positions[ic] - positions[ia]
            let area = length(cross(edge1, edge2))
            let duv1 = textureCoordinates[ib] - textureCoordinates[ia]
            let duv2 = textureCoordinates[ic] - textureCoordinates[ia]
            let determinant = duv1.x * duv2.y - duv1.y * duv2.x
            guard area > 0.000001, determinant.isFinite, abs(determinant) > 0.000001 else {
                supportsNormalMapping = false
                continue
            }
            let inverse = 1 / determinant
            let tangent = (edge1 * duv2.y - edge2 * duv1.y) * inverse
            let bitangent = (edge2 * duv1.x - edge1 * duv2.x) * inverse
            guard isFinite(tangent), isFinite(bitangent) else {
                supportsNormalMapping = false
                continue
            }
            for index in [ia, ib, ic] {
                tangentSums[index] += tangent * area
                bitangentSums[index] += bitangent * area
                hasContribution[index] = true
            }
        }

        var tangents: [SIMD3<Float>] = []
        var bitangents: [SIMD3<Float>] = []
        tangents.reserveCapacity(positions.count)
        bitangents.reserveCapacity(positions.count)
        for index in positions.indices {
            let normal = normals[index]
            let projectedTangent = tangentSums[index] - normal * dot(normal, tangentSums[index])
            let tangentLength = length(projectedTangent)
            let tangent: SIMD3<Float>
            if hasContribution[index] && tangentLength > 0.000001 {
                tangent = projectedTangent / tangentLength
            } else {
                supportsNormalMapping = false
                tangent = fallbackTangent(for: normal)
            }

            let accumulatedBitangent = bitangentSums[index]
            let projectedBitangent = accumulatedBitangent
                - normal * dot(normal, accumulatedBitangent)
                - tangent * dot(tangent, accumulatedBitangent)
            let projectedBitangentLength = length(projectedBitangent)
            if !hasContribution[index] || projectedBitangentLength <= 0.000001 {
                supportsNormalMapping = false
            }
            let orientation = dot(cross(normal, tangent), projectedBitangent) < 0 ? -1 as Float : 1 as Float
            let bitangent = cross(normal, tangent) * orientation
            tangents.append(tangent)
            bitangents.append(bitangent)
        }
        return (tangents, bitangents, supportsNormalMapping)
    }

    private static func fallbackTangent(for normal: SIMD3<Float>) -> SIMD3<Float> {
        let absolute = SIMD3<Float>(abs(normal.x), abs(normal.y), abs(normal.z))
        let axis: SIMD3<Float>
        if absolute.x <= absolute.y && absolute.x <= absolute.z {
            axis = SIMD3<Float>(1, 0, 0)
        } else if absolute.y <= absolute.x && absolute.y <= absolute.z {
            axis = SIMD3<Float>(0, 1, 0)
        } else {
            axis = SIMD3<Float>(0, 0, 1)
        }
        let candidate = cross(axis, normal)
        let magnitude = length(candidate)
        return magnitude > 0.000001 ? candidate / magnitude : SIMD3<Float>(1, 0, 0)
    }

    private static func projectedUVs(_ positions: [SIMD3<Float>]) -> [SIMD2<Float>] {
        var minimum = SIMD3<Float>(repeating: Float.greatestFiniteMagnitude)
        var maximum = SIMD3<Float>(repeating: -Float.greatestFiniteMagnitude)
        for point in positions {
            minimum.x = min(minimum.x, point.x); minimum.y = min(minimum.y, point.y); minimum.z = min(minimum.z, point.z)
            maximum.x = max(maximum.x, point.x); maximum.y = max(maximum.y, point.y); maximum.z = max(maximum.z, point.z)
        }
        let spans = maximum - minimum
        let collapsedAxis = spans.x <= spans.y && spans.x <= spans.z ? 0 : (spans.y <= spans.x && spans.y <= spans.z ? 1 : 2)
        let axes = collapsedAxis == 0 ? (1, 2) : (0, collapsedAxis == 1 ? 2 : 1)
        let minA = component(minimum, axes.0)
        let minB = component(minimum, axes.1)
        let spanA = max(component(spans, axes.0), 0.001)
        let spanB = max(component(spans, axes.1), 0.001)
        return positions.map { point in
            SIMD2<Float>((component(point, axes.0) - minA) / spanA, (component(point, axes.1) - minB) / spanB)
        }
    }

    private static func component(_ point: SIMD3<Float>, _ axis: Int) -> Float {
        axis == 0 ? point.x : (axis == 1 ? point.y : point.z)
    }

    private static func cross(_ a: SIMD3<Float>, _ b: SIMD3<Float>) -> SIMD3<Float> {
        SIMD3<Float>(a.y * b.z - a.z * b.y, a.z * b.x - a.x * b.z, a.x * b.y - a.y * b.x)
    }

    private static func dot(_ a: SIMD3<Float>, _ b: SIMD3<Float>) -> Float {
        a.x * b.x + a.y * b.y + a.z * b.z
    }

    private static func length(_ vector: SIMD3<Float>) -> Float {
        sqrt(dot(vector, vector))
    }

    private static func isFinite(_ vector: SIMD3<Float>) -> Bool {
        vector.x.isFinite && vector.y.isFinite && vector.z.isFinite
    }
}
