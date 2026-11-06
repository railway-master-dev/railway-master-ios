import Foundation
import RealityKit

/// 完全に架空の通勤車両を手続き生成するための寸法・表示設定。
/// 形状寸法の基準モデルは長さ19.5m、幅2.8m、高さ3.65m。
public struct VehicleSpecification: Codable, Sendable {
    public var identifier: String
    public var displayName: String
    public var carLengthMeters: Float
    public var carWidthMeters: Float
    public var carHeightMeters: Float
    public var passengerCapacity: Int
    public var designSpeedKmh: Int

    public init(
        identifier: String = "fictional-commuter-01",
        displayName: String = "架空通勤車両 01",
        carLengthMeters: Float = 19.5,
        carWidthMeters: Float = 2.8,
        carHeightMeters: Float = 3.65,
        passengerCapacity: Int = 110,
        designSpeedKmh: Int = 100
    ) {
        self.identifier = identifier
        self.displayName = displayName
        self.carLengthMeters = carLengthMeters
        self.carWidthMeters = carWidthMeters
        self.carHeightMeters = carHeightMeters
        self.passengerCapacity = passengerCapacity
        self.designSpeedKmh = designSpeedKmh
    }

    public static let fictionalPrototype = VehicleSpecification()

    /// 必須値と、基準メッシュを無理なくスケールできる寸法範囲を検査する。
    public func validationIssues() -> [String] {
        var issues: [String] = []
        if identifier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            issues.append("identifier must not be empty")
        }
        if !carLengthMeters.isFinite || carLengthMeters < 15 || carLengthMeters > 25 {
            issues.append("carLengthMeters must be finite and within 15...25")
        }
        if !carWidthMeters.isFinite || carWidthMeters < 2.4 || carWidthMeters > 3.4 {
            issues.append("carWidthMeters must be finite and within 2.4...3.4")
        }
        if !carHeightMeters.isFinite || carHeightMeters < 3 || carHeightMeters > 4.5 {
            issues.append("carHeightMeters must be finite and within 3...4.5")
        }
        if passengerCapacity <= 0 { issues.append("passengerCapacity must be positive") }
        if designSpeedKmh <= 0 { issues.append("designSpeedKmh must be positive") }
        return issues
    }

    var modelScale: SIMD3<Float> {
        SIMD3(carLengthMeters / 19.5, carWidthMeters / 2.8, carHeightMeters / 3.65)
    }
}

/// 車両ルート下に置く10個の独立した交換・調整単位。
public enum VehiclePartGroup: String, Codable, Hashable, Sendable {
    case carBody
    case doors
    case glazing
    case cabInterior
    case cabControls
    case runningGear
    case underfloorEquipment
    case roofEquipment
    case pantograph
    case lighting
}

public struct VehiclePartGroupComponent: Component {
    public var group: VehiclePartGroup
    public init(group: VehiclePartGroup) { self.group = group }
}
