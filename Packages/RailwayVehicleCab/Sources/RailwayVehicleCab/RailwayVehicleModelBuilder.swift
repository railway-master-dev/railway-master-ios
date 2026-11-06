import RailwayAudioEnhancements
import RealityKit

public struct RailwayVehicleModel {
    public let root: Entity
    public let groups: [VehiclePartGroup: Entity]
    public let cabControls: VehicleCabControlRig
    public let specification: VehicleSpecification
}

public enum RailwayVehicleModelBuilder {
    /// 1両分の低〜中ポリゴン架空車両を生成する。呼出元のRealityKitシーンへ `root` を追加する。
    public static func build(
        _ specification: VehicleSpecification = .fictionalPrototype,
        desk: FictionalCabDesk = FictionalCabAndSoundCatalog.fieldChopper
    ) -> RailwayVehicleModel {
        let root = Entity()
        root.name = specification.identifier
        root.scale = specification.modelScale

        let body = VehicleGeometryFactory.group("VehicleBodyGroup", kind: .carBody)
        let doors = VehicleGeometryFactory.group("VehicleDoorsGroup", kind: .doors)
        let glazing = VehicleGeometryFactory.group("VehicleGlazingGroup", kind: .glazing)
        let cab = VehicleGeometryFactory.group("CabInteriorGroup", kind: .cabInterior)
        let cabControls = VehicleGeometryFactory.group("CabControlsGroup", kind: .cabControls)
        let runningGear = VehicleGeometryFactory.group("RunningGearGroup", kind: .runningGear)
        let underfloor = VehicleGeometryFactory.group("UnderfloorEquipmentGroup", kind: .underfloorEquipment)
        let roof = VehicleGeometryFactory.group("RoofEquipmentGroup", kind: .roofEquipment)
        let pantograph = VehicleGeometryFactory.group("PantographGroup", kind: .pantograph)
        let lighting = VehicleGeometryFactory.group("LightingGroup", kind: .lighting)

        VehicleBodyBuilder.build(in: body)
        VehicleDoorsAndGlazingBuilder.buildDoors(in: doors)
        VehicleDoorsAndGlazingBuilder.buildGlazing(in: glazing)
        let controls = VehicleCabInteriorBuilder.build(interior: cab, controls: cabControls, desk: desk)
        VehicleRunningGearBuilder.build(in: runningGear)
        VehicleUnderfloorEquipmentBuilder.build(in: underfloor)
        VehicleRoofEquipmentBuilder.buildRoof(in: roof)
        VehicleRoofEquipmentBuilder.buildPantograph(in: pantograph)
        VehicleLightingBuilder.build(in: lighting)

        let orderedGroups: [(VehiclePartGroup, Entity)] = [
            (.carBody, body), (.doors, doors), (.glazing, glazing),
            (.cabInterior, cab), (.cabControls, cabControls), (.runningGear, runningGear),
            (.underfloorEquipment, underfloor), (.roofEquipment, roof),
            (.pantograph, pantograph), (.lighting, lighting)
        ]
        for (_, entity) in orderedGroups { root.addChild(entity) }
        return RailwayVehicleModel(
            root: root,
            groups: Dictionary(uniqueKeysWithValues: orderedGroups),
            cabControls: controls,
            specification: specification
        )
    }
}
