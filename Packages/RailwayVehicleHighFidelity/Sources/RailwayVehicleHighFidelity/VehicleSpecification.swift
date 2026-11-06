import Foundation
import RealityKit

/// 架空の都市通勤車両。実車諸元・特定事業者の外観を表すものではありません。
public struct RailwayVehicleHighFidelitySpecification: Codable, Sendable {
    public var identifier: String
    public var displayName: String
    public var carLengthMeters: Float
    public var carWidthMeters: Float
    public var carHeightMeters: Float
    public var detailLevel: VehicleDetailLevel

    public init(
        identifier: String = "fictional-commuter-hf-01",
        displayName: String = "架空通勤車両 HF-01",
        carLengthMeters: Float = 19.5,
        carWidthMeters: Float = 2.8,
        carHeightMeters: Float = 3.65,
        detailLevel: VehicleDetailLevel = .high
    ) {
        self.identifier = identifier
        self.displayName = displayName
        self.carLengthMeters = carLengthMeters
        self.carWidthMeters = carWidthMeters
        self.carHeightMeters = carHeightMeters
        self.detailLevel = detailLevel
    }

    public static let fictionalPrototype = RailwayVehicleHighFidelitySpecification()

    public func validationIssues() -> [String] {
        var issues: [String] = []
        if identifier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            issues.append("identifier must not be empty")
        }
        if !carLengthMeters.isFinite || !(15...25).contains(carLengthMeters) {
            issues.append("carLengthMeters must be finite and within 15...25")
        }
        if !carWidthMeters.isFinite || !(2.4...3.4).contains(carWidthMeters) {
            issues.append("carWidthMeters must be finite and within 2.4...3.4")
        }
        if !carHeightMeters.isFinite || !(3...4.5).contains(carHeightMeters) {
            issues.append("carHeightMeters must be finite and within 3...4.5")
        }
        return issues
    }

    var modelScale: SIMD3<Float> {
        SIMD3(carWidthMeters / 2.8, carHeightMeters / 3.65, carLengthMeters / 19.5)
    }
}

public enum VehicleDetailLevel: String, Codable, Sendable {
    case balanced
    case high

    var grilleSlats: Int { self == .high ? 9 : 5 }
    var fastenerRows: Int { self == .high ? 4 : 2 }
}

/// 各機能を個別に差し替え・表示調整できる車両サブアセンブリ。
public enum HighFidelityVehiclePart: String, CaseIterable, Codable, Hashable, Sendable {
    case body
    case glazing
    case doors
    case bogies
    case underfloorEquipment
    case roofEquipment
    case pantograph
    case lighting
    case cabStructure
    case cabInstruments
    case cabControls
    case windshieldWipers
}

public enum CabControlKind: String, CaseIterable, Codable, Hashable, Sendable {
    case masterController
    case brakeLever
    case reverser
    case hornButton
    case wiperSwitch
    case headlightSwitch
    case interiorLightSwitch
    case pantographSwitch
    case mainCircuitBreaker
    case doorCloseButton
    case publicAddressSwitch
    case atsAcknowledgement
    case instrumentSelector
    case displaySelector
    case emergencyBrake
}

/// Host-selected visual wiper mode. Motion is time-driven and is not linked to real weather sensing.
public enum VehicleWiperMode: String, CaseIterable, Codable, Sendable {
    case off
    case intermittent
    case low
    case high
}

/// 操作器の動作値。これは視覚モデルであり、運転物理・安全装置の実装ではありません。
public struct CabControlRange: Sendable {
    public let minimum: Float
    public let maximum: Float
    public let neutral: Float
    public let maximumTravelRadians: Float
    public let rotates: Bool

    public init(minimum: Float, maximum: Float, neutral: Float, maximumTravelRadians: Float, rotates: Bool = true) {
        self.minimum = minimum
        self.maximum = maximum
        self.neutral = neutral
        self.maximumTravelRadians = maximumTravelRadians
        self.rotates = rotates
    }
}

/// Presentation-only cab lamp states supplied by the host simulator; these are not safety or signaling functions.
public struct VehicleCabIndicatorState: Equatable, Sendable {
    public var atspActive: Bool
    public var atcActive: Bool
    public var emergencyBrakeActive: Bool
    public var doorsOpen: Bool
    public var tractionPowerActive: Bool
    public var regenerativeBrakingActive: Bool
    public var faultActive: Bool

    public init(
        atspActive: Bool = false,
        atcActive: Bool = false,
        emergencyBrakeActive: Bool = false,
        doorsOpen: Bool = false,
        tractionPowerActive: Bool = false,
        regenerativeBrakingActive: Bool = false,
        faultActive: Bool = false
    ) {
        self.atspActive = atspActive
        self.atcActive = atcActive
        self.emergencyBrakeActive = emergencyBrakeActive
        self.doorsOpen = doorsOpen
        self.tractionPowerActive = tractionPowerActive
        self.regenerativeBrakingActive = regenerativeBrakingActive
        self.faultActive = faultActive
    }
}
