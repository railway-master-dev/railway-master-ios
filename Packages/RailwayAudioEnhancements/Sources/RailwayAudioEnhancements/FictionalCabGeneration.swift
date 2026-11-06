import Foundation

/// Procedural cab parts the RealityKit builders should emit.
/// Layout and color only. Not a traced photo, panel image, or commercial-game copy.
public struct FictionalCabGenerationPlan: Equatable, Sendable {
    public var family: FictionalControlFamily
    public var dataStatus: String
    public var deskColorName: String
    public var combinedMasterBrake: Bool
    public var separateBrakeSphere: Bool
    public var woodMasterGrip: Bool
    public var gaugeCount: Int
    public var monitorNames: [String]
    public var lampNames: [String]
    public var captionPanels: [String]
    public var masterMarkings: [String]
    public var fictionalCarNumber: String
    public var includesSeriesParallelFinalLamps: Bool

    public var partNames: [String] {
        var names = ["DeskHousing", fictionalCarNumber]
        if combinedMasterBrake { names.append("CombinedMaster") } else { names.append("SeparateMaster") }
        if separateBrakeSphere { names.append("BrakeSphere") }
        names.append(contentsOf: (0..<gaugeCount).map { "Gauge\($0)" })
        names.append(contentsOf: monitorNames)
        names.append(contentsOf: lampNames)
        names.append(contentsOf: captionPanels)
        names.append(contentsOf: masterMarkings)
        return names
    }
}

public extension FictionalCabAndSoundCatalog {
    static func generationPlan(for family: FictionalControlFamily) -> FictionalCabGenerationPlan {
        let desk = desk(for: family)
        let monitors: [String]
        switch family {
        case .vvvf:
            monitors = ["CenterMonitor", "RightStatusScreen", "Handset"]
        case .fieldChopper:
            monitors = ["RightKeypad"]
        case .resistance:
            monitors = []
        }
        var captions: [String] = []
        if let dashboard = desk.dashboardCaption { captions.append(dashboard) }
        if let door = desk.doorLampCaption { captions.append(door) }
        return FictionalCabGenerationPlan(
            family: family,
            dataStatus: "PLACEHOLDER",
            deskColorName: family == .vvvf ? "grey" : "mint",
            combinedMasterBrake: desk.oneHandleMasterBrake,
            separateBrakeSphere: desk.brakeGrip == .sphere,
            woodMasterGrip: desk.masterGrip == .woodBrown,
            gaugeCount: desk.analogGaugeCount,
            monitorNames: monitors,
            lampNames: desk.indicatorCaptions,
            captionPanels: captions,
            masterMarkings: desk.masterMarkings,
            fictionalCarNumber: desk.fictionalCarNumber,
            includesSeriesParallelFinalLamps: desk.indicatorCaptions.contains("直列")
        )
    }
}
