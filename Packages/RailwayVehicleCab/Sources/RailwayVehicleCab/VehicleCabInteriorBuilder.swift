import RailwayAudioEnhancements
import RealityKit
import UIKit

/// 運転台の内装。傾斜した計器盤に実物の文字盤テクスチャを持つ
/// アナログ計器（速度・MR/BP圧力・BC圧力、針は呼出側が毎フレーム
/// 駆動する）、ノッチ板、表示灯、ワンハンドル／個別レバー、
/// 運転室シェル（側壁・天井・後部隔壁・ワイパー）を組み立てる。
/// 机の色と計器・モニタ構成は架空デスク定義（FictionalCabDesk）に従う。
enum VehicleCabInteriorBuilder {
    static func build(
        interior: Entity,
        controls: Entity,
        desk: FictionalCabDesk = FictionalCabAndSoundCatalog.fieldChopper
    ) -> VehicleCabControlRig {
        if desk.fictionalCarNumber == "E231" {
            return buildE231(interior: interior, controls: controls, desk: desk)
        }
        buildDeskAndPanel(desk, in: interior)
        buildCabShell(in: interior)
        buildSeat(in: interior)
        return buildControls(desk, interior: interior, controls: controls)
    }

    // MARK: - E231 early analog layout

    /// Player cab modelled on the E231 early analog cab: driver sits
    /// left, one-handle master controller at the far left, white-face
    /// speedometer and dual-needle MR/BC pressure gauge in front of
    /// the driver, TIMS monitor at the panel centre, lamp panel to
    /// its right. Needle pivots keep the shared names so the scene
    /// can drive them (GaugeNeedle_speed / _mr / _bc).
    private static func buildE231(interior: Entity, controls: Entity, desk: FictionalCabDesk) -> VehicleCabControlRig {
        let dark = deskPaint(desk)
        VehicleGeometryFactory.box("CabDeskBody", size: SIMD3(2.30, 1.02, 0.50), at: SIMD3(0, 1.26, -8.50), material: dark, in: interior)
        VehicleGeometryFactory.box("CabDeskTop", size: SIMD3(2.34, 0.05, 0.78), at: SIMD3(0, 1.80, -8.42), material: texturedMaterial(named: "cab_desk_grain_light.png"), in: interior)
        // batch32 (2026-11-14, user verdict on the first cab
        // photo: the desk reads as one flat dark slab). Give
        // the desk a face: a lighter inset fascia panel with
        // seam strips on the front, a dark kick plate at foot
        // level, and a raised lip along the back of the desk
        // top so the top surface has an edge to catch light.
        let fascia = VehicleMaterialPalette.paint(UIColor(red: 0.30, green: 0.32, blue: 0.33, alpha: 1), roughness: 0.62)
        VehicleGeometryFactory.box("CabDeskFascia", size: SIMD3(1.90, 0.62, 0.02), at: SIMD3(0, 1.34, -8.245), material: fascia, in: interior)
        VehicleGeometryFactory.box("CabDeskFasciaSeamL", size: SIMD3(0.015, 0.62, 0.024), at: SIMD3(-0.62, 1.34, -8.245), material: VehicleMaterialPalette.rubber, in: interior)
        VehicleGeometryFactory.box("CabDeskFasciaSeamR", size: SIMD3(0.015, 0.62, 0.024), at: SIMD3(0.62, 1.34, -8.245), material: VehicleMaterialPalette.rubber, in: interior)
        VehicleGeometryFactory.box("CabDeskKickPlate", size: SIMD3(2.30, 0.20, 0.02), at: SIMD3(0, 0.84, -8.245), material: VehicleMaterialPalette.rubber, in: interior)
        VehicleGeometryFactory.box("CabDeskTopLip", size: SIMD3(2.34, 0.05, 0.04), at: SIMD3(0, 1.845, -8.79), material: dark, in: interior)
        // Timetable stand on the desk top, right of the
        // driver: a dark board, a paper card and a clip —
        // the small dressing every real cab carries.
        let stand = Entity()
        stand.name = "TimetableStand"
        stand.position = SIMD3(0.55, 1.83, -8.33)
        stand.orientation = simd_quatf(angle: -0.28, axis: SIMD3(1, 0, 0))
        interior.addChild(stand)
        VehicleGeometryFactory.box("TimetableBoard", size: SIMD3(0.24, 0.33, 0.012), at: SIMD3(0, 0.165, 0), material: VehicleMaterialPalette.darkMetal, in: stand)
        VehicleGeometryFactory.box("TimetablePaper", size: SIMD3(0.21, 0.30, 0.004), at: SIMD3(0, 0.16, 0.009), material: VehicleMaterialPalette.paint(UIColor(red: 0.93, green: 0.94, blue: 0.92, alpha: 1), roughness: 0.9), in: stand)
        VehicleGeometryFactory.box("TimetableClip", size: SIMD3(0.10, 0.025, 0.006), at: SIMD3(0, 0.315, 0.011), material: VehicleMaterialPalette.trim, in: stand)
        let binnacle = Entity()
        binnacle.name = "CabBinnacle"
        binnacle.position = SIMD3(0, 2.06, -8.55)
        binnacle.orientation = simd_quatf(angle: -0.32, axis: SIMD3(1, 0, 0))
        interior.addChild(binnacle)
        VehicleGeometryFactory.box("CabPanelFace", size: SIMD3(2.30, 0.56, 0.06), at: SIMD3(0, 0, 0), material: dark, in: binnacle)

        addRoundGauge(name: "speed", texture: "cab_gauge_speed_e231.png", x: -0.55, y: 0.18, radius: 0.095, in: binnacle)
        addRoundGauge(name: "pressure", texture: "cab_gauge_pressure_e231.png", x: -0.20, y: 0.18, radius: 0.095, in: binnacle)
        let inkBlack = UIColor(red: 0.08, green: 0.08, blue: 0.09, alpha: 1)
        addNeedle(name: "GaugeNeedle_speed", x: -0.55, y: 0.18, color: inkBlack, in: binnacle)
        addNeedle(name: "GaugeNeedle_mr", x: -0.20, y: 0.18, color: UIColor(red: 0.85, green: 0.16, blue: 0.10, alpha: 1), in: binnacle)
        addNeedle(name: "GaugeNeedle_bc", x: -0.20, y: 0.18, color: inkBlack, in: binnacle)
        addLamp(name: "door", x: -0.68, y: -0.20, litColor: UIColor(red: 0.55, green: 0.95, blue: 0.62, alpha: 1), litByDefault: true, in: binnacle)
        addLamp(name: "ats", x: -0.56, y: -0.20, litColor: UIColor(red: 0.98, green: 0.30, blue: 0.12, alpha: 1), litByDefault: false, in: binnacle)
        addLamp(name: "slip", x: -0.44, y: -0.20, litColor: UIColor(red: 1.0, green: 0.62, blue: 0.10, alpha: 1), litByDefault: false, in: binnacle)
        addLamp(name: "emergency", x: -0.32, y: -0.20, litColor: UIColor(red: 0.98, green: 0.16, blue: 0.10, alpha: 1), litByDefault: false, in: binnacle)

        // TIMS monitor at the panel centre. batch32: a deeper
        // frame with the screen set into it, and the screen is
        // unlit so it reads as a powered LCD instead of a
        // printed card.
        VehicleGeometryFactory.box("TIMSMonitorFrame", size: SIMD3(0.58, 0.42, 0.06), at: SIMD3(0.30, 0.0, 0.030), material: VehicleMaterialPalette.darkMetal, in: binnacle)
        VehicleGeometryFactory.box("TIMSMonitorBezel", size: SIMD3(0.52, 0.36, 0.02), at: SIMD3(0.30, 0.0, 0.058), material: VehicleMaterialPalette.rubber, in: binnacle)
        VehicleGeometryFactory.boxUnlit("TIMSMonitorScreen", size: SIMD3(0.50, 0.34, 0.012), at: SIMD3(0.30, 0.0, 0.066), material: unlitTexturedMaterial(named: "cab_tims_screen.png"), in: binnacle)
        // Lamp cluster panel right of the monitor.
        VehicleGeometryFactory.box("CabLampPanel", size: SIMD3(0.36, 0.30, 0.015), at: SIMD3(0.80, 0.03, 0.036), material: texturedMaterial(named: "cab_lamp_panel.png"), in: binnacle)
        VehicleGeometryFactory.box("RightKeypad", size: SIMD3(0.20, 0.10, 0.03), at: SIMD3(0.80, -0.20, 0.036), material: VehicleMaterialPalette.darkMetal, in: binnacle)
        VehicleGeometryFactory.box("FictionalCarNumberPlate_\(desk.fictionalCarNumber)", size: SIMD3(0.16, 0.055, 0.014), at: SIMD3(0.02, 0.245, 0.032), material: VehicleMaterialPalette.trim, in: binnacle)

        buildCabShell(in: interior, wideBlinds: true)
        buildSeat(in: interior, seatX: -0.35)

        var nodes: [VehicleCabControlKind: ModelEntity] = [:]
        let grip = gripPaint(desk.masterGrip)
        // One-handle master controller at the far left: a single lever
        // whose rig value spans -7 (full brake) .. +5 (full power).
        VehicleGeometryFactory.box("MasterQuadrantBase", size: SIMD3(0.20, 0.12, 0.36), at: SIMD3(-0.92, 1.89, -8.10), material: VehicleMaterialPalette.darkMetal, in: interior)
        let master = makeControl(kind: .masterController, name: "MasterControllerHandle", size: SIMD3(0.06, 0.34, 0.06), at: SIMD3(-0.92, 2.06, -8.10), minimum: -7, maximum: 5, neutral: 0, axis: SIMD3(-1, 0, 0), scale: 0.035, in: controls, tint: grip)
        VehicleGeometryFactory.cylinder("MasterGripBar", radius: 0.027, length: 0.23, at: SIMD3(0, 0.19, 0), axis: SIMD3(1, 0, 0), material: grip, in: master)
        nodes[.masterController] = master
        // The one handle IS the brake control on this desk; the rig
        // still needs a brakeLever node (control-count contract), so
        // it is built but hidden.
        let hiddenBrake = makeControl(kind: .brakeLever, name: "CombinedBrakeNode", size: SIMD3(0.10, 0.10, 0.10), at: SIMD3(-0.92, 1.90, -8.10), minimum: 0, maximum: 1, neutral: 0, axis: SIMD3(1, 0, 0), scale: 0.3, in: controls, tint: grip)
        hiddenBrake.isEnabled = false
        nodes[.brakeLever] = hiddenBrake
        // Notch plate standing beside the handle slot.
        let plate = VehicleGeometryFactory.box("CabNotchPlate", size: SIMD3(0.15, 0.46, 0.015), at: SIMD3(-1.09, 2.02, -8.10), material: texturedMaterial(named: "cab_notch_plate_e231.png"), in: interior)
        plate.orientation = simd_quatf(angle: -0.12, axis: SIMD3(1, 0, 0))
        // Train-radio handset on the right desk top.
        VehicleGeometryFactory.box("HandsetCradle", size: SIMD3(0.26, 0.05, 0.11), at: SIMD3(0.95, 1.855, -8.28), material: VehicleMaterialPalette.darkMetal, in: interior)
        VehicleGeometryFactory.box("RightHandset", size: SIMD3(0.22, 0.05, 0.08), at: SIMD3(0.95, 1.905, -8.28), material: VehicleMaterialPalette.darkMetal, in: interior)

        nodes[.reverser] = makeControl(kind: .reverser, name: "ReverserKey", size: SIMD3(0.10, 0.17, 0.10), at: SIMD3(0.48, 1.99, -8.12), minimum: -1, maximum: 1, neutral: 0, axis: SIMD3(0, 1, 0), scale: 0.55, in: controls)
        nodes[.hornButton] = makeControl(kind: .hornButton, name: "HornButton", size: SIMD3(0.12, 0.09, 0.12), at: SIMD3(0.66, 1.97, -8.12), minimum: 0, maximum: 1, neutral: 0, axis: SIMD3(0, -1, 0), scale: 0.045, in: controls, motion: .translation)
        nodes[.wiperSwitch] = makeControl(kind: .wiperSwitch, name: "WiperSwitch", size: SIMD3(0.085, 0.15, 0.085), at: SIMD3(0.84, 1.99, -8.12), minimum: 0, maximum: 3, neutral: 0, axis: SIMD3(0, 1, 0), scale: 0.20, in: controls)
        nodes[.headlightSwitch] = makeControl(kind: .headlightSwitch, name: "HeadlightSwitch", size: SIMD3(0.085, 0.15, 0.085), at: SIMD3(1.00, 1.99, -8.12), minimum: 0, maximum: 1, neutral: 0, axis: SIMD3(0, 1, 0), scale: 0.32, in: controls)
        return VehicleCabControlRig(nodes: nodes)
    }

    // MARK: - Desk and instrument panel

    private static func buildDeskAndPanel(_ desk: FictionalCabDesk, in interior: Entity) {
        let dark = deskPaint(desk)
        // Desk body (knee panel) and top slab with a grain texture.
        VehicleGeometryFactory.box("CabDeskBody", size: SIMD3(2.30, 1.02, 0.50), at: SIMD3(0, 1.26, -8.50), material: dark, in: interior)
        VehicleGeometryFactory.box("CabDeskTop", size: SIMD3(2.34, 0.05, 0.78), at: SIMD3(0, 1.80, -8.42), material: texturedMaterial(named: "cab_desk_grain.png"), in: interior)
        // Sloped instrument binnacle, tilted so the panel faces the
        // driver's eyes. Gauges and lamps are its children and inherit
        // the tilt; needle pivots rotate about the panel normal (+Z).
        let binnacle = Entity()
        binnacle.name = "CabBinnacle"
        binnacle.position = SIMD3(0, 2.06, -8.55)
        binnacle.orientation = simd_quatf(angle: -0.32, axis: SIMD3(1, 0, 0))
        interior.addChild(binnacle)
        VehicleGeometryFactory.box("CabPanelFace", size: SIMD3(2.30, 0.56, 0.06), at: SIMD3(0, 0, 0), material: dark, in: binnacle)

        if desk.analogGaugeCount >= 2 {
            addGauge(name: "speed", texture: "cab_gauge_speed.png", x: -0.80, in: binnacle)
            addGauge(name: "pressure", texture: "cab_gauge_pressure_mr.png", x: -0.475, in: binnacle)
            addNeedle(name: "GaugeNeedle_speed", x: -0.80, color: UIColor(red: 1.0, green: 0.45, blue: 0.10, alpha: 1), in: binnacle)
            addNeedle(name: "GaugeNeedle_mr", x: -0.475, color: UIColor(red: 0.95, green: 0.28, blue: 0.16, alpha: 1), in: binnacle)
            addNeedle(name: "GaugeNeedle_bp", x: -0.475, color: UIColor(white: 0.95, alpha: 1), in: binnacle)
        }
        if desk.analogGaugeCount >= 3 {
            addGauge(name: "bc", texture: "cab_gauge_pressure_bc.png", x: -0.15, in: binnacle)
            addNeedle(name: "GaugeNeedle_bc", x: -0.15, color: UIColor(white: 0.95, alpha: 1), in: binnacle)
        }
        appendPanelFurniture(desk, in: binnacle)
        // Notch quadrant plate lying on the desk top by the master handle.
        VehicleGeometryFactory.box("CabNotchPlate", size: SIMD3(0.52, 0.012, 0.26), at: SIMD3(-0.55, 1.835, -8.16), material: texturedMaterial(named: "cab_notch_plate.png"), in: interior)
    }

    /// batch50: a real round instrument for the E231 desk —
    /// a proud bezel ring, a black recess and the dial texture
    /// on a UV-mapped disc set back inside it, replacing the
    /// flat square plate that read as a sprite in the first
    /// cab photo. The needle pivot stays at z 0.048 (addNeedle),
    /// ahead of the disc face at 0.041.
    /// batch50 (2026-11-14, cab gauges half-cut in batch46):
    /// the 0.28 m dials sat at binnacle y 0 (world 2.07), 36 deg
    /// below the cab eye, so only their tops cleared the
    /// frame's bottom edge (fy 0.95, centres fy 1.05). The
    /// dials shrink to 0.19 m and move to y +0.18 (world 2.24,
    /// bezel top just under the panel top at 2.34): the centre
    /// is then ~21 deg below the eye and the whole dial spans
    /// fy ~0.70-0.96 at the unchanged FOV 61, so the outside
    /// view ratio (~0.55) is untouched. The lamps move to
    /// y -0.20 to clear the raised dials.
    private static func addRoundGauge(name: String, texture: String, x: Float, y: Float = 0, radius: Float = 0.140, in binnacle: Entity) {
        VehicleGeometryFactory.cylinder("GaugeBezel_\(name)", radius: radius, length: 0.036, at: SIMD3(x, y, 0.020), axis: SIMD3(0, 0, 1), material: VehicleMaterialPalette.darkMetal, in: binnacle)
        let recess = VehicleMaterialPalette.paint(UIColor(red: 0.05, green: 0.05, blue: 0.055, alpha: 1), roughness: 0.6)
        VehicleGeometryFactory.cylinder("GaugeRecess_\(name)", radius: radius * 0.907, length: 0.032, at: SIMD3(x, y, 0.024), axis: SIMD3(0, 0, 1), material: recess, in: binnacle)
        VehicleGeometryFactory.disc("GaugeFace_\(name)", radius: radius * 0.857, at: SIMD3(x, y, 0.041), material: texturedMaterial(named: texture), in: binnacle)
    }

    private static func addGauge(name: String, texture: String, x: Float, in binnacle: Entity) {
        VehicleGeometryFactory.cylinder("GaugeBezel_\(name)", radius: 0.128, length: 0.030, at: SIMD3(x, 0, 0.018), axis: SIMD3(0, 0, 1), material: VehicleMaterialPalette.darkMetal, in: binnacle)
        VehicleGeometryFactory.box("GaugeFace_\(name)", size: SIMD3(0.235, 0.235, 0.012), at: SIMD3(x, 0, 0.036), material: texturedMaterial(named: texture), in: binnacle)
    }

    private static func addNeedle(name: String, x: Float, y: Float = 0, color: UIColor, in binnacle: Entity) {
        let pivot = Entity()
        pivot.name = name
        pivot.position = SIMD3(x, y, 0.048)
        binnacle.addChild(pivot)
        let needleMaterial = VehicleMaterialPalette.paint(color, roughness: 0.4)
        VehicleGeometryFactory.box("\(name)_Arm", size: SIMD3(0.013, 0.088, 0.004), at: SIMD3(0, 0.026, 0), material: needleMaterial, in: pivot)
        VehicleGeometryFactory.box("\(name)_Tail", size: SIMD3(0.017, 0.030, 0.004), at: SIMD3(0, -0.020, 0), material: needleMaterial, in: pivot)
        VehicleGeometryFactory.cylinder("\(name)_Hub", radius: 0.015, length: 0.010, at: SIMD3(0, 0, 0.002), axis: SIMD3(0, 0, 1), material: VehicleMaterialPalette.darkMetal, in: pivot)
    }

    private static func appendPanelFurniture(_ desk: FictionalCabDesk, in binnacle: Entity) {
        let bezel = VehicleMaterialPalette.darkMetal
        let glass = VehicleMaterialPalette.glass
        var screenX: Float = 0.22
        if desk.hasCenterMonitor {
            VehicleGeometryFactory.box("CenterMonitorFrame", size: SIMD3(0.46, 0.34, 0.04), at: SIMD3(screenX, 0.01, 0.030), material: bezel, in: binnacle)
            VehicleGeometryFactory.box("CenterMonitorScreen", size: SIMD3(0.40, 0.28, 0.012), at: SIMD3(screenX, 0.01, 0.052), material: glass, in: binnacle)
            screenX += 0.52
        }
        if desk.hasRightStatusScreen {
            VehicleGeometryFactory.box("RightStatusFrame", size: SIMD3(0.32, 0.24, 0.04), at: SIMD3(screenX, 0.02, 0.030), material: bezel, in: binnacle)
            VehicleGeometryFactory.box("RightStatusScreen", size: SIMD3(0.27, 0.19, 0.012), at: SIMD3(screenX, 0.02, 0.052), material: glass, in: binnacle)
        }
        // Lamp cluster: the door-closed lamp is lit by default (the
        // running state); slip and emergency overlays are toggled by
        // the adapter from live telemetry and controls.
        addLamp(name: "door", x: 0.68, litColor: UIColor(red: 0.55, green: 0.95, blue: 0.62, alpha: 1), litByDefault: true, in: binnacle)
        addLamp(name: "ats", x: 0.80, litColor: UIColor(red: 0.98, green: 0.30, blue: 0.12, alpha: 1), litByDefault: false, in: binnacle)
        addLamp(name: "slip", x: 0.92, litColor: UIColor(red: 1.0, green: 0.62, blue: 0.10, alpha: 1), litByDefault: false, in: binnacle)
        addLamp(name: "emergency", x: 1.04, litColor: UIColor(red: 0.98, green: 0.16, blue: 0.10, alpha: 1), litByDefault: false, in: binnacle)

        let plan = FictionalCabAndSoundCatalog.generationPlan(for: desk.family)
        if plan.includesSeriesParallelFinalLamps {
            for (index, name) in plan.lampNames.enumerated() {
                VehicleGeometryFactory.box("ChopperLamp_\(name)", size: SIMD3(0.035, 0.05, 0.018), at: SIMD3(0.60, 0.16 - Float(index) * 0.058, 0.036), material: VehicleMaterialPalette.warning, in: binnacle)
            }
        }
        if desk.hasRightKeypad {
            VehicleGeometryFactory.box("RightKeypad", size: SIMD3(0.20, 0.15, 0.03), at: SIMD3(0.95, -0.16, 0.036), material: bezel, in: binnacle)
        }
        if let caption = desk.dashboardCaption {
            VehicleGeometryFactory.box("DashboardCaption_\(caption)", size: SIMD3(0.14, 0.045, 0.014), at: SIMD3(0.42, 0.245, 0.032), material: glass, in: binnacle)
        }
        VehicleGeometryFactory.box("FictionalCarNumberPlate_\(desk.fictionalCarNumber)", size: SIMD3(0.16, 0.055, 0.014), at: SIMD3(0.10, 0.245, 0.032), material: VehicleMaterialPalette.trim, in: binnacle)
    }

    private static func addLamp(name: String, x: Float, y: Float = 0.15, litColor: UIColor, litByDefault: Bool, in binnacle: Entity) {
        VehicleGeometryFactory.cylinder("CabLampBezel_\(name)", radius: 0.021, length: 0.014, at: SIMD3(x, y, 0.034), axis: SIMD3(0, 0, 1), material: VehicleMaterialPalette.darkMetal, in: binnacle)
        let dim = VehicleMaterialPalette.paint(UIColor(red: 0.16, green: 0.17, blue: 0.16, alpha: 1), roughness: 0.35)
        VehicleGeometryFactory.cylinder("CabLampLens_\(name)", radius: 0.016, length: 0.010, at: SIMD3(x, y, 0.040), axis: SIMD3(0, 0, 1), material: dim, in: binnacle)
        let lit = VehicleGeometryFactory.cylinder("CabLampLit_\(name)", radius: 0.016, length: 0.006, at: SIMD3(x, y, 0.047), axis: SIMD3(0, 0, 1), material: VehicleMaterialPalette.paint(litColor, roughness: 0.25), in: binnacle)
        lit.isEnabled = litByDefault
    }

    // MARK: - Cab shell and seat

    private static func buildCabShell(in interior: Entity, wideBlinds: Bool = false) {
        let wall = VehicleMaterialPalette.interior
        VehicleGeometryFactory.box("CabWallLeft", size: SIMD3(0.05, 2.50, 2.20), at: SIMD3(-1.13, 2.20, -8.55), material: wall, in: interior)
        VehicleGeometryFactory.box("CabWallRight", size: SIMD3(0.05, 2.50, 2.20), at: SIMD3(1.13, 2.20, -8.55), material: wall, in: interior)
        VehicleGeometryFactory.box("CabCeiling", size: SIMD3(2.30, 0.05, 2.30), at: SIMD3(0, 3.48, -8.55), material: wall, in: interior)
        VehicleGeometryFactory.box("CabRearBulkhead", size: SIMD3(2.30, 2.60, 0.05), at: SIMD3(0, 2.20, -7.42), material: wall, in: interior)
        VehicleGeometryFactory.box("CabRearDoor", size: SIMD3(0.70, 1.90, 0.03), at: SIMD3(0.45, 1.95, -7.44), material: VehicleMaterialPalette.darkMetal, in: interior)
        VehicleGeometryFactory.box("CabRearDoorWindow", size: SIMD3(0.30, 0.45, 0.02), at: SIMD3(0.45, 2.45, -7.46), material: VehicleMaterialPalette.glass, in: interior)
        // Sun visors above the windshield and parked wipers on it.
        for side: Float in [-1, 1] {
            let visorSize = wideBlinds ? SIMD3<Float>(1.06, 0.36, 0.02) : SIMD3<Float>(0.95, 0.28, 0.02)
            let visor = VehicleGeometryFactory.box("SunVisor_\(side)", size: visorSize, at: SIMD3(side * 0.58, wideBlinds ? 3.27 : 3.24, -9.52), material: VehicleMaterialPalette.rubber, in: interior)
            visor.orientation = simd_quatf(angle: 0.5, axis: SIMD3(1, 0, 0))
            // batch45 (2026-11-14, cab photo verdict): the
            // blades parked at y 2.655, which the photo showed
            // as a black bar crossing the window at mid height
            // because the old glass band floated high. With the
            // windshield lowered (band 2.30..3.30 in the glazing
            // builder) the blades now park at its bottom edge,
            // y 2.36, the real rest position.
            // batch46: the glass bottom drops to 2.05, so the
            // parked blades follow it down (blade 2.11, arm
            // 2.18 — the same +0.06 / +0.13 offsets from the
            // glass bottom as batch45 set).
            VehicleGeometryFactory.box("WiperBlade_\(side)", size: SIMD3(0.52, 0.030, 0.010), at: SIMD3(side * 0.60, 2.11, -9.685), material: VehicleMaterialPalette.rubber, in: interior)
            VehicleGeometryFactory.box("WiperArm_\(side)", size: SIMD3(0.020, 0.020, 0.010), at: SIMD3(side * 0.60, 2.18, -9.685), material: VehicleMaterialPalette.darkMetal, in: interior)
        }
    }

    private static func buildSeat(in interior: Entity, seatX: Float = 0) {
        let trim = VehicleMaterialPalette.darkMetal
        let seat = VehicleMaterialPalette.seat
        VehicleGeometryFactory.box("DriverSeatBase", size: SIMD3(0.48, 0.42, 0.48), at: SIMD3(seatX, 1.15, -7.45), material: trim, in: interior)
        VehicleGeometryFactory.box("DriverSeatCushion", size: SIMD3(0.62, 0.18, 0.58), at: SIMD3(seatX, 1.46, -7.45), material: seat, in: interior)
        VehicleGeometryFactory.box("DriverSeatBack", size: SIMD3(0.62, 0.78, 0.16), at: SIMD3(seatX, 1.88, -7.70), material: seat, in: interior)
        VehicleGeometryFactory.box("DriverSeatHeadrest", size: SIMD3(0.36, 0.24, 0.13), at: SIMD3(seatX, 2.42, -7.72), material: seat, in: interior)
    }

    // MARK: - Controls

    private static func buildControls(_ desk: FictionalCabDesk, interior: Entity, controls: Entity) -> VehicleCabControlRig {
        var nodes: [VehicleCabControlKind: ModelEntity] = [:]
        let grip = gripPaint(desk.masterGrip)
        let masterX: Float = desk.oneHandleMasterBrake ? -0.55 : -0.78
        let brakeX: Float = desk.oneHandleMasterBrake ? -0.55 : -0.28
        // Quadrant base the master lever pivots on.
        VehicleGeometryFactory.box("MasterQuadrantBase", size: SIMD3(0.17, 0.11, 0.32), at: SIMD3(masterX, 1.875, -8.05), material: VehicleMaterialPalette.darkMetal, in: interior)

        let master = makeControl(kind: .masterController, name: "MasterControllerHandle", size: SIMD3(0.055, 0.40, 0.055), at: SIMD3(masterX, 2.08, -8.05), minimum: 0, maximum: 5, neutral: 0, axis: SIMD3(-1, 0, 0), scale: 0.07, in: controls, tint: grip)
        VehicleGeometryFactory.cylinder("MasterGripBar", radius: 0.026, length: 0.21, at: SIMD3(0, 0.21, 0), axis: SIMD3(1, 0, 0), material: grip, in: master)
        nodes[.masterController] = master

        if desk.oneHandleMasterBrake {
            nodes[.brakeLever] = makeControl(kind: .brakeLever, name: "CombinedBrakeCollar", size: SIMD3(0.15, 0.055, 0.15), at: SIMD3(masterX, 1.99, -8.05), minimum: 0, maximum: 1, neutral: 0, axis: SIMD3(1, 0, 0), scale: 0.30, in: controls, tint: grip)
        } else if desk.brakeGrip == .sphere {
            nodes[.brakeLever] = makeSphereControl(kind: .brakeLever, name: "BrakeLeverHandle", at: SIMD3(brakeX, 2.02, -8.05), in: controls)
            VehicleGeometryFactory.box("BrakeQuadrantBase", size: SIMD3(0.15, 0.10, 0.26), at: SIMD3(brakeX, 1.87, -8.05), material: VehicleMaterialPalette.darkMetal, in: interior)
        } else {
            let brake = makeControl(kind: .brakeLever, name: "BrakeLeverHandle", size: SIMD3(0.05, 0.32, 0.05), at: SIMD3(brakeX, 2.02, -8.05), minimum: 0, maximum: 1, neutral: 0, axis: SIMD3(1, 0, 0), scale: 0.50, in: controls, tint: grip)
            VehicleGeometryFactory.sphere("BrakeGripKnob", radius: 0.045, at: SIMD3(0, 0.18, 0), material: grip, in: brake)
            VehicleGeometryFactory.box("BrakeQuadrantBase", size: SIMD3(0.15, 0.10, 0.26), at: SIMD3(brakeX, 1.87, -8.05), material: VehicleMaterialPalette.darkMetal, in: interior)
            nodes[.brakeLever] = brake
        }
        if desk.centerSwitchBank {
            VehicleGeometryFactory.box("CenterSwitchBank", size: SIMD3(0.55, 0.05, 0.16), at: SIMD3(0.15, 1.85, -8.15), material: deskPaint(desk), in: interior)
        }
        if desk.blueSwitchLabels {
            let blue = VehicleMaterialPalette.paint(UIColor(red: 0.20, green: 0.38, blue: 0.72, alpha: 1), roughness: 0.45)
            VehicleGeometryFactory.box("BlueLabelStrip", size: SIMD3(0.7, 0.02, 0.03), at: SIMD3(0.2, 1.885, -8.15), material: blue, in: interior)
        }
        if desk.hasRightHandset {
            VehicleGeometryFactory.box("RightHandset", size: SIMD3(0.08, 0.18, 0.05), at: SIMD3(1.05, 1.95, -8.10), material: VehicleMaterialPalette.darkMetal, in: interior)
        }
        nodes[.reverser] = makeControl(kind: .reverser, name: "ReverserKey", size: SIMD3(0.10, 0.17, 0.10), at: SIMD3(0.42, 1.99, -8.10), minimum: -1, maximum: 1, neutral: 0, axis: SIMD3(0, 1, 0), scale: 0.55, in: controls)
        nodes[.hornButton] = makeControl(kind: .hornButton, name: "HornButton", size: SIMD3(0.12, 0.09, 0.12), at: SIMD3(0.62, 1.97, -8.10), minimum: 0, maximum: 1, neutral: 0, axis: SIMD3(0, -1, 0), scale: 0.045, in: controls, motion: .translation)
        nodes[.wiperSwitch] = makeControl(kind: .wiperSwitch, name: "WiperSwitch", size: SIMD3(0.085, 0.15, 0.085), at: SIMD3(0.80, 1.99, -8.10), minimum: 0, maximum: 3, neutral: 0, axis: SIMD3(0, 1, 0), scale: 0.20, in: controls)
        nodes[.headlightSwitch] = makeControl(kind: .headlightSwitch, name: "HeadlightSwitch", size: SIMD3(0.085, 0.15, 0.085), at: SIMD3(0.96, 1.99, -8.10), minimum: 0, maximum: 1, neutral: 0, axis: SIMD3(0, 1, 0), scale: 0.32, in: controls)
        return VehicleCabControlRig(nodes: nodes)
    }

    private static func makeControl(
        kind: VehicleCabControlKind,
        name: String,
        size: SIMD3<Float>,
        at position: SIMD3<Float>,
        minimum: Float,
        maximum: Float,
        neutral: Float,
        axis: SIMD3<Float>,
        scale: Float,
        in parent: Entity,
        motion: VehicleCabControlMotion = .rotation,
        tint: SimpleMaterial? = nil
    ) -> ModelEntity {
        VehicleGeometryFactory.cylinder("\(name)_Pedestal", radius: 0.09, length: 0.07, at: SIMD3(position.x, position.y - size.y / 2 - 0.03, position.z), material: VehicleMaterialPalette.darkMetal, in: parent)
        let entity = VehicleGeometryFactory.box(name, size: size, at: position, material: tint ?? VehicleMaterialPalette.warning, in: parent)
        entity.components[VehicleCabControlComponent.self] = VehicleCabControlComponent(
            kind: kind, motion: motion, axis: axis,
            minimumValue: minimum, maximumValue: maximum, neutralValue: neutral,
            motionScale: scale, value: neutral
        )
        return entity
    }

    private static func makeSphereControl(kind: VehicleCabControlKind, name: String, at position: SIMD3<Float>, in parent: Entity) -> ModelEntity {
        VehicleGeometryFactory.cylinder("\(name)_Pedestal", radius: 0.10, length: 0.06, at: SIMD3(position.x, position.y - 0.10, position.z), material: VehicleMaterialPalette.darkMetal, in: parent)
        let entity = VehicleGeometryFactory.sphere(name, radius: 0.085, at: position, material: VehicleMaterialPalette.darkMetal, in: parent)
        entity.components[VehicleCabControlComponent.self] = VehicleCabControlComponent(
            kind: kind, motion: .rotation, axis: SIMD3(1, 0, 0),
            minimumValue: 0, maximumValue: 1, neutralValue: 0, motionScale: 0.5, value: 0
        )
        return entity
    }

    // MARK: - Materials

    /// Unlit variant for powered screens (TIMS): the texture
    /// shows at full brightness regardless of scene lighting.
    private static func unlitTexturedMaterial(named name: String) -> UnlitMaterial {
        if let texture = try? TextureResource.load(named: name, in: Bundle.module) {
            var material = UnlitMaterial()
            material.color = .init(tint: .white, texture: .init(texture))
            return material
        }
        return UnlitMaterial(color: UIColor(red: 0.10, green: 0.14, blue: 0.16, alpha: 1))
    }

    private static func texturedMaterial(named name: String, tint: UIColor = .white) -> SimpleMaterial {
        if let texture = try? TextureResource.load(named: name, in: Bundle.module) {
            var material = SimpleMaterial()
            material.color = .init(tint: tint, texture: .init(texture))
            material.roughness = .init(floatLiteral: 0.55)
            material.metallic = .init(floatLiteral: 0)
            return material
        }
        return VehicleMaterialPalette.interior
    }

    private static func deskPaint(_ desk: FictionalCabDesk) -> SimpleMaterial {
        VehicleMaterialPalette.paint(UIColor(red: desk.deskRed, green: desk.deskGreen, blue: desk.deskBlue, alpha: 1), roughness: 0.72)
    }

    private static func gripPaint(_ grip: FictionalMasterGrip) -> SimpleMaterial {
        switch grip {
        case .darkCombined:
            return VehicleMaterialPalette.darkMetal
        case .woodBrown:
            return VehicleMaterialPalette.paint(UIColor(red: 0.45, green: 0.24, blue: 0.12, alpha: 1), roughness: 0.62)
        case .markedReverseAndOff:
            return VehicleMaterialPalette.paint(UIColor(red: 0.62, green: 0.64, blue: 0.66, alpha: 1), roughness: 0.4, metallic: true)
        }
    }
}
