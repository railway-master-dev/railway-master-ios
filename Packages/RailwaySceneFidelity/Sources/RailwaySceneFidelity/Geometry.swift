import Foundation

/// Metre-based right-handed coordinates: X is lateral/right, Y is up, Z is forward.
public struct SceneVector3: Codable, Hashable, Sendable {
    public var x: Double
    public var y: Double
    public var z: Double

    public init(_ x: Double, _ y: Double, _ z: Double) {
        self.x = x
        self.y = y
        self.z = z
    }

    public static let zero = SceneVector3(0, 0, 0)
    public static let up = SceneVector3(0, 1, 0)
    public static let forward = SceneVector3(0, 0, 1)

    public var lengthSquared: Double { x * x + y * y + z * z }
    public var length: Double { sqrt(lengthSquared) }

    public func normalized(or fallback: SceneVector3 = .forward) -> SceneVector3 {
        let magnitude = length
        guard magnitude.isFinite, magnitude > 1e-9 else { return fallback }
        return self / magnitude
    }

    public func dot(_ other: SceneVector3) -> Double {
        x * other.x + y * other.y + z * other.z
    }

    public func cross(_ other: SceneVector3) -> SceneVector3 {
        SceneVector3(y * other.z - z * other.y,
                     z * other.x - x * other.z,
                     x * other.y - y * other.x)
    }

    public static func + (lhs: Self, rhs: Self) -> Self {
        Self(lhs.x + rhs.x, lhs.y + rhs.y, lhs.z + rhs.z)
    }

    public static func - (lhs: Self, rhs: Self) -> Self {
        Self(lhs.x - rhs.x, lhs.y - rhs.y, lhs.z - rhs.z)
    }

    public static prefix func - (value: Self) -> Self {
        Self(-value.x, -value.y, -value.z)
    }

    public static func * (lhs: Self, rhs: Double) -> Self {
        Self(lhs.x * rhs, lhs.y * rhs, lhs.z * rhs)
    }

    public static func * (lhs: Double, rhs: Self) -> Self { rhs * lhs }

    public static func / (lhs: Self, rhs: Double) -> Self {
        guard rhs.isFinite, abs(rhs) > 1e-12 else { return .zero }
        return Self(lhs.x / rhs, lhs.y / rhs, lhs.z / rhs)
    }
}

public struct SceneRouteControlPoint: Codable, Hashable, Sendable {
    public let chainageM: Double
    public let position: SceneVector3
    /// Optional d(position)/d(chainage), in metres per metre. If omitted, a centred secant is used.
    public let tangentPerMeter: SceneVector3?
    /// Local track roll in radians, interpolated between control points.
    public let bankRadians: Double

    public init(
        chainageM: Double,
        position: SceneVector3,
        tangentPerMeter: SceneVector3? = nil,
        bankRadians: Double = 0
    ) {
        self.chainageM = chainageM
        self.position = position
        self.tangentPerMeter = tangentPerMeter
        self.bankRadians = bankRadians
    }
}

public struct SceneRouteFrame: Codable, Hashable, Sendable {
    public let chainageM: Double
    public let position: SceneVector3
    public let forward: SceneVector3
    public let right: SceneVector3
    public let up: SceneVector3
    public let bankRadians: Double
}

public enum SceneRouteGeometryError: Error, Equatable, Sendable {
    case tooFewControlPoints
    case nonFiniteControlPoint(index: Int)
    case chainageNotStrictlyIncreasing(index: Int)
    case degenerateSegment(index: Int)
    case invalidBank(index: Int)
}

/// A cubic-Hermite railway centreline parameterised by route chainage, not repeated world-space planes.
public struct SceneChainageRoute: Sendable {
    public let controlPoints: [SceneRouteControlPoint]
    private let slopes: [SceneVector3]

    public var startChainageM: Double { controlPoints[0].chainageM }
    public var endChainageM: Double { controlPoints[controlPoints.count - 1].chainageM }
    public var lengthM: Double { endChainageM - startChainageM }

    public init(controlPoints: [SceneRouteControlPoint]) throws {
        guard controlPoints.count >= 2 else { throw SceneRouteGeometryError.tooFewControlPoints }
        for index in controlPoints.indices {
            let point = controlPoints[index]
            let values = [point.chainageM, point.position.x, point.position.y, point.position.z, point.bankRadians]
            guard values.allSatisfy(\.isFinite),
                  point.tangentPerMeter.map({ $0.x.isFinite && $0.y.isFinite && $0.z.isFinite }) ?? true else {
                throw SceneRouteGeometryError.nonFiniteControlPoint(index: index)
            }
            if abs(point.bankRadians) > .pi {
                throw SceneRouteGeometryError.invalidBank(index: index)
            }
            if index > 0 {
                let previous = controlPoints[index - 1]
                guard point.chainageM > previous.chainageM else {
                    throw SceneRouteGeometryError.chainageNotStrictlyIncreasing(index: index)
                }
                guard (point.position - previous.position).length > 1e-6 else {
                    throw SceneRouteGeometryError.degenerateSegment(index: index - 1)
                }
            }
            if let tangent = point.tangentPerMeter, tangent.length <= 1e-9 {
                throw SceneRouteGeometryError.degenerateSegment(index: index)
            }
        }
        self.controlPoints = controlPoints
        self.slopes = controlPoints.indices.map { index in
            if let explicit = controlPoints[index].tangentPerMeter { return explicit }
            if index == 0 {
                let a = controlPoints[0], b = controlPoints[1]
                return (b.position - a.position) / (b.chainageM - a.chainageM)
            }
            if index == controlPoints.count - 1 {
                let a = controlPoints[index - 1], b = controlPoints[index]
                return (b.position - a.position) / (b.chainageM - a.chainageM)
            }
            let a = controlPoints[index - 1], b = controlPoints[index + 1]
            return (b.position - a.position) / (b.chainageM - a.chainageM)
        }
    }

    /// Returns a smooth position, tangent and banked local frame for any in-range chainage.
    public func frame(at chainageM: Double) -> SceneRouteFrame? {
        guard chainageM.isFinite,
              chainageM >= startChainageM - 1e-8,
              chainageM <= endChainageM + 1e-8 else { return nil }
        let s = min(endChainageM, max(startChainageM, chainageM))
        let index = segmentIndex(containing: s)
        let a = controlPoints[index]
        let b = controlPoints[index + 1]
        let span = b.chainageM - a.chainageM
        let t = min(1, max(0, (s - a.chainageM) / span))
        let t2 = t * t
        let t3 = t2 * t
        let h00 = 2 * t3 - 3 * t2 + 1
        let h10 = t3 - 2 * t2 + t
        let h01 = -2 * t3 + 3 * t2
        let h11 = t3 - t2
        let position = a.position * h00 + slopes[index] * (span * h10)
            + b.position * h01 + slopes[index + 1] * (span * h11)

        let dh00 = 6 * t2 - 6 * t
        let dh10 = 3 * t2 - 4 * t + 1
        let dh01 = -6 * t2 + 6 * t
        let dh11 = 3 * t2 - 2 * t
        let derivative = (a.position * dh00 + slopes[index] * (span * dh10)
            + b.position * dh01 + slopes[index + 1] * (span * dh11)) / span
        let forward = derivative.normalized(or: (b.position - a.position).normalized())
        var right = SceneVector3.up.cross(forward).normalized(or: SceneVector3(1, 0, 0))
        var up = forward.cross(right).normalized(or: .up)
        let bank = a.bankRadians + (b.bankRadians - a.bankRadians) * t
        if abs(bank) > 1e-9 {
            let c = cos(bank), s = sin(bank)
            let bankedRight = right * c + up * s
            let bankedUp = up * c - right * s
            right = bankedRight.normalized(or: right)
            up = bankedUp.normalized(or: up)
        }
        return SceneRouteFrame(
            chainageM: s,
            position: position,
            forward: forward,
            right: right,
            up: up,
            bankRadians: bank
        )
    }

    private func segmentIndex(containing chainage: Double) -> Int {
        var lower = 0
        var upper = controlPoints.count - 1
        while lower + 1 < upper {
            let middle = (lower + upper) / 2
            if chainage < controlPoints[middle].chainageM { upper = middle }
            else { lower = middle }
        }
        return min(controlPoints.count - 2, lower)
    }
}

public struct SceneCameraState: Codable, Hashable, Sendable {
    public var position: SceneVector3
    public var forward: SceneVector3
    public var chainageM: Double
    public var verticalFieldOfViewRadians: Double
    public var aspectRatio: Double
    public var nearDistanceM: Double
    public var farDistanceM: Double
    public var towardIncreasingChainage: Bool

    public init(
        position: SceneVector3,
        forward: SceneVector3,
        chainageM: Double,
        verticalFieldOfViewRadians: Double = 66 * .pi / 180,
        aspectRatio: Double = 1.8,
        nearDistanceM: Double = 0.25,
        farDistanceM: Double = 1_400,
        towardIncreasingChainage: Bool = true
    ) {
        self.position = position
        self.forward = forward.normalized()
        self.chainageM = chainageM
        self.verticalFieldOfViewRadians = min(.pi - 0.01, max(0.01, verticalFieldOfViewRadians))
        self.aspectRatio = max(0.1, aspectRatio)
        self.nearDistanceM = max(0, nearDistanceM)
        self.farDistanceM = max(self.nearDistanceM, farDistanceM)
        self.towardIncreasingChainage = towardIncreasingChainage
    }

    public var right: SceneVector3 {
        SceneVector3.up.cross(forward).normalized(or: SceneVector3(1, 0, 0))
    }

    public var up: SceneVector3 {
        forward.cross(right).normalized(or: .up)
    }
}
