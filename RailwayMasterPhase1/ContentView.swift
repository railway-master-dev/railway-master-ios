import RailwayAudioEnhancements
import SwiftUI
import UIKit
import CrewWorkflow
import RailwayGameModes
import RailwayOperations
import RailwayVehicleHighFidelity
import RailwaySceneFidelity
import TrafficSimulation

private enum DrivingSheet: String, Identifiable {
    case routeSelection
    case servicePlan
    case liveTimetable
    case physicsDetails
    case trafficNetwork
    case regionalAudit
    case audioControls
    case vehicleProfiles
    case vehicleLibrary
    case environmentQuality
    case operationsGameplay
    case maintenanceGameplay
    case scenarioProgress
    case gameModes
    case doorProcedureScoring
    case saveManager
    case sessionResult
    case howToPlay
    case credits

    var id: String { rawValue }
}

struct ContentView: View {
    @StateObject private var model = SimulatorModel()
    /// batch66: build progress for the loading screen, fed by
    /// the scene world while its deferred build runs.
    @StateObject private var loadingProgress = LoadingProgress()
    @State private var activeSheet: DrivingSheet?
    @State private var selectedReferenceVehicleID = "jr-east-e233"
    @State private var titleDismissed = false
    /// batch71: true between a confirmed route selection and the
    /// deferred application of that selection (see
    /// startSelectedRoute). Guards against a double application
    /// while the loading screen is being raised.
    @State private var pendingRouteStart = false

    /// The demo-drive flag every CI screenshot-tour launch
    /// passes (the same flag SimulatorModel.demoDriveEnabled
    /// keys on).
    private var demoDriveEnabled: Bool {
        ProcessInfo.processInfo.arguments.contains("-RMDemoDrive")
    }

    /// The title screen gates a normal launch only. Every CI
    /// screenshot-tour launch passes -RMDemoDrive, so the tour
    /// path bypasses the title entirely and drives exactly as
    /// before.
    private var showsTitleScreen: Bool {
        !titleDismissed && !demoDriveEnabled
    }
    // batch51 (2026-11-14): the scene and the traffic sheet now
    // read the model's assembled scenario (model.trafficScenario)
    // directly. This view used to load the bundled placeholder
    // scenario (10 sample trains) and pass THAT to the scene,
    // while the engine simulated the assembled diagram scenario
    // (798 trains) — the scene's per-actor plan lookup therefore
    // failed for every real train and no AI train ever rendered,
    // in any photo, since the diagram was wired in.
    @AppStorage("railway.audio.enabled") private var audioEnabled = true
    @AppStorage("railway.audio.volume") private var audioVolume = 0.65
    private let frameTimer = Timer.publish(every: 1.0 / 60.0, on: .main, in: .common).autoconnect()

    private var speedKmh: Double { model.telemetry.speedMps * 3.6 }
    private var nextStop: RegionalRouteStop? {
        model.activeStops.indices.contains(model.nextStopIndex) ? model.activeStops[model.nextStopIndex] : nil
    }
    private var nextStopName: String { nextStop?.name ?? model.route.arrivalStation }
    private var distanceToNextStopM: Double {
        (nextStop?.positionM ?? model.route.stopMarkerM) - model.telemetry.positionM
    }

    private static let generatedStationLayoutsByID: [String: RailwayGeneratedStationLayout] = {
        guard let manifest = try? RailwayGeneratedAssetCatalog.stationLayoutManifest() else { return [:] }
        return Dictionary(manifest.stations.map { ($0.stationId, $0) }, uniquingKeysWith: { first, _ in first })
    }()

    private var generatedStationModelPlacements: [RailwayGeneratedStationPlacement] {
        model.activeStops.compactMap { stop in
            guard let layout = Self.generatedStationLayoutsByID[stop.stationID] else { return nil }
            return RailwayGeneratedStationPlacement(layout: layout, routeChainageM: stop.positionM)
        }
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // batch66 (方式A): while the title screen is up
                // the 3D view does not exist at all. It used to
                // be created behind the opaque title, where it
                // rendered invisibly and ran the deferred world
                // build for the DEFAULT profile (fieldChopper,
                // 6 cars) on the main actor — starving the
                // route-selection sheet — and because a route
                // selection always forces an 8-car formation,
                // the route signature then changed and the whole
                // world was built a second time. Now the view is
                // created only once the title is dismissed (a
                // confirmed selection, or a demo-drive launch,
                // which bypasses the title on the same
                // showsTitleScreen axis), so the world is built
                // exactly once, for the selected working.
                if !showsTitleScreen {
                RealityTrackView(
                    route: model.route,
                    positionM: model.telemetry.positionM,
                    speedKmh: speedKmh,
                    brakePipePressureKPa: model.telemetry.brakePipePressureKPa,
                    mainReservoirPressureKPa: model.trainPhysicsTelemetry.mainReservoirPressureKPa,
                    brakeCylinderPressureKPa: model.trainPhysicsTelemetry.brakeCylinderPressureKPa,
                    accelerationMps2: model.telemetry.accelerationMps2,
                    simulationTime: model.simulationTime,
                    weather: model.weather,
                    trafficScenario: model.trafficScenario,
                    trafficSnapshot: model.trafficSnapshot,
                    routeVariant: model.routeVariant,
                    travelDirection: model.travelDirection,
                    controls: model.appliedDrivingControls,
                    // ATSP/ATC lamps follow fictional live brake commands. Fault telemetry is still absent.
                    vehicleCabIndicatorState: VehicleCabIndicatorState(
                        atspActive: model.protectionActingSystems.contains("atsP"),
                        atcActive: model.protectionActingSystems.contains("atc"),
                        emergencyBrakeActive: model.appliedDrivingControls.emergencyBrake,
                        doorsOpen: model.gameModeDoorState.isOpen,
                        tractionPowerActive: model.controls.throttleNotch > 0,
                        regenerativeBrakingActive: model.telemetry.regenerativeBrakeForceN > 0,
                        faultActive: false
                    ),
                    vehicleMaximumSpeedKmh: model.train.maximumSpeedKmh,
                    environmentSelection: model.environmentSelection,
                    vehicleCarCount: model.selectedVehicleProfile.carCount,
                    // The player's cab is the E231 early analog desk
                    // (user decision 2026-11-08); vehicle physics and
                    // sound still follow the selected profile.
                    cabDesk: FictionalCabAndSoundCatalog.e231Early,
                    serviceCategory: model.serviceCategory,
                    stationModelPlacements: generatedStationModelPlacements,
                    nextStopName: nextStopName,
                    distanceToNextStopM: distanceToNextStopM,
                    signalPositionM: model.tracksideSignalReading?.blockStartM,
                    signalAspect: model.tracksideSignalReading?.aspect,
                    loadingProgress: loadingProgress
                )
                }
                // Full-bleed 3D: the cab interior in the scene is the desk;
                // no SwiftUI panel overlays the lower screen any more.
                VStack(spacing: 0) {
                    header
                        .frame(height: 38)
                        .padding(.horizontal, max(10, geometry.size.width * 0.018))
                        .padding(.top, 7)
                        .background(Color.black.opacity(0.30))

                    HStack(alignment: .top) {
                        operationsHUD
                        Spacer()
                        // Air / electric state as small text only, top-right.
                        VStack(alignment: .trailing, spacing: 1) {
                            // batch108: 時刻表示（現在時刻＋停車駅の
                            // 予定発／次駅の予定着）。ダイヤのない
                            // モードでは予定行は出ない。
                            Text(model.gameClockText)
                            if let scheduleLine = model.hudScheduleLine {
                                Text(scheduleLine)
                            }
                            Text("MR \(Int(model.telemetry.mainReservoirPressureKPa.rounded())) · BP \(Int(model.telemetry.brakePipePressureKPa.rounded())) · BC \(Int(model.telemetry.brakeCylinderPressureKPa.rounded())) kPa")
                            Text("引張 \(Int(model.telemetry.tractionForceN / 1_000)) kN · 制動 \(Int(model.telemetry.brakingForceN / 1_000)) kN")
                            if model.telemetry.isWheelSlipActive || model.telemetry.isBrakeSlipActive {
                                Text(model.telemetry.isWheelSlipActive && model.telemetry.isBrakeSlipActive ? "空転・滑走" : (model.telemetry.isWheelSlipActive ? "空転" : "滑走"))
                                    .foregroundStyle(.orange)
                            }
                            if let passingWaitMessage = model.passingWaitMessage {
                                Text(passingWaitMessage)
                                    .foregroundStyle(.yellow)
                            }
                        }
                        .font(.system(size: 9, weight: .semibold, design: .rounded).monospacedDigit())
                        .foregroundStyle(.white.opacity(0.85))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(.black.opacity(0.30), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                    .padding(.horizontal, 8)
                    .padding(.top, 6)

                    Spacer()

                    HStack(spacing: 7) {
                        Image(systemName: "viewfinder")
                        Text("\(model.route.lineName)")
                        Text("·")
                        Text(model.telemetry.currentGradientPermille == 0 ? "平坦" : String(format: "%+.0f‰", model.telemetry.currentGradientPermille))
                    }
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.86))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(.black.opacity(0.34), in: Capsule())
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 8)
                    .padding(.bottom, 6)

                    // No panel desk: the 3D cab interior is the desk.
                    Color.clear.frame(height: 52)
                }

                // Driving levers docked at the left edge (the driver's
                // side), slim enough not to cover the view.
                VStack {
                    Spacer()
                    HStack {
                        VStack {
                            CombinedNotchLever(
                                value: model.controls.emergencyBrake ? 8 : (model.controls.brakeNotch > 0 ? model.controls.brakeNotch : -model.controls.throttleNotch),
                                brakeMaximum: 7,
                                powerMaximum: max(model.train.tractionNotchFractions.count - 1, 1)
                            ) { combined in
                                // The detent past B7 is EB (user
                                // decision 2026-11-12): it latches the
                                // driver's emergency brake at full
                                // service brake, and moving the handle
                                // to any other detent releases it.
                                // ATS-commanded emergency braking is
                                // applied downstream in the model and
                                // is not affected by this.
                                if combined > 7 {
                                    model.setBrake(7)
                                    model.setEmergencyBrake(true)
                                } else {
                                    if model.controls.emergencyBrake {
                                        model.setEmergencyBrake(false)
                                    }
                                    if combined > 0 {
                                        model.setBrake(combined)
                                    } else if combined < 0 {
                                        model.setThrottle(-combined)
                                    } else {
                                        model.setThrottle(0)
                                        model.setBrake(0)
                                    }
                                }
                            }
                            .frame(height: geometry.size.height * 0.5)
                        }
                        .frame(width: 92)
                        .padding(8)
                        .background(Color.black.opacity(0.38), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .padding(.leading, 8)

                        Spacer()
                    }
                    .padding(.bottom, 64)
                }

                // Bottom row: speed readout on the left of the auxiliary
                // buttons; horn / ATS acknowledge are buttons at the
                // bottom-right edge. Emergency brake is not a button:
                // it is the mascon handle's deepest detent (past B7).
                VStack {
                    Spacer()
                    HStack(alignment: .bottom, spacing: 8) {
                        Text("\(Int(speedKmh.rounded())) km/h")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.9))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(.black.opacity(0.34), in: Capsule())
                        // batch67: 現在の制限速度。表示専用の再計算は
                        // せず、保護が実際に照査している値そのもの
                        // （simulationTick が permittedSpeed として
                        // operationsSnapshot に毎tick書く値）を出す。
                        // 信号現示の上限（減速75/注意55/警戒25/停止0）と
                        // 区間制限・駅停車パターンの合成結果。
                        if let limitKmh = model.operationsSnapshot?.permittedSpeedKmh {
                            Text("制限 \(Int(limitKmh.rounded())) km/h")
                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                                .foregroundStyle(.white.opacity(0.9))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(.black.opacity(0.34), in: Capsule())
                        }
                        Spacer()
                        cabAuxButton(symbol: "speaker.wave.3.fill", label: "警笛") { model.playHorn() }
                        cabAuxButton(symbol: "checkmark.shield.fill", label: "ATS確認") { _ = model.acknowledgeATS() }
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 10)
                }
            }
        }
        .background(Color(red: 0.025, green: 0.045, blue: 0.067).ignoresSafeArea())
        .preferredColorScheme(.dark)
        .statusBarHidden(true)
        .onReceive(frameTimer) { date in
            // The simulation holds while the title screen is up;
            // pressing start is what sets the railway in motion.
            // batch70: it also holds while the world is loading —
            // the train must not drive off during the loading
            // screen, and the main thread belongs to the build
            // task until the world lands (the tick, the snapshot
            // publishing and the body re-evaluations were all
            // competing with organizeWorldChunks, which stretched
            // the 99% tail of the load on device).
            guard !showsTitleScreen, !loadingProgress.isLoading else { return }
            model.advance(at: date.timeIntervalSinceReferenceDate)
        }
        .overlay {
            // batch71: the loading branch is tested BEFORE the
            // title branch. A confirmed route selection raises the
            // loading state first and applies the route one runloop
            // turn later (see startSelectedRoute), and during that
            // window the title is still up — the loading screen
            // must cover it, or the player stares at the frozen
            // title/sheet until the synchronous route application
            // and scene rebuild finally let a frame through.
            if loadingProgress.isLoading && !demoDriveEnabled {
                LoadingScreenView(progress: loadingProgress)
                    .transition(.opacity)
            } else if showsTitleScreen {
                // batch60: "運転をはじめる" no longer drops the
                // player straight into the default working. It
                // opens the route selection sheet first (the same
                // sheet the driving menu uses); the title only
                // dismisses when a selection is confirmed, which
                // is where selectRoute runs — see the sheet's
                // onStart below. Cancelling the sheet leaves the
                // title up, and the simulation stays held because
                // showsTitleScreen is still true.
                TitleScreenView(onStart: { activeSheet = .routeSelection }, onHelp: { activeSheet = .howToPlay })
                    .transition(.opacity)
            }
        }
        .onAppear {
            model.setAudioEnabled(audioEnabled)
            model.setAudioVolume(Float(audioVolume))
            // batch71: staged progress from inside selectRoute
            // (route applied, then scenario reset), reported into
            // the same loading flow the scene build feeds. The
            // isLoading guard keeps stray reports from a
            // non-loading caller from touching the bar.
            model.routeApplyProgressHandler = { [loadingProgress] percent, status in
                guard loadingProgress.isLoading else { return }
                loadingProgress.report(rawPercent: percent, floor: percent, status: status)
            }
        }
        .onChange(of: audioEnabled) { _, enabled in
            model.setAudioEnabled(enabled)
        }
        .onChange(of: audioVolume) { _, volume in
            model.setAudioVolume(Float(volume))
        }
        .onChange(of: model.audioEnabled) { _, enabled in
            audioEnabled = enabled
        }
        .onChange(of: model.audioVolume) { _, volume in
            audioVolume = volume
        }
        .onChange(of: model.completedSummary) { _, summary in
            if summary != nil {
                activeSheet = .sessionResult
            }
        }
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .routeSelection:
                RegionalRouteSelectionSheet(
                    initialVariant: model.routeVariant,
                    initialCategory: model.serviceCategory,
                    initialDirection: model.travelDirection,
                    onStart: { variant, category, direction in
                        // batch71: the application of the
                        // selection is deferred one runloop turn
                        // so the loading screen draws first — see
                        // startSelectedRoute below. (batch60: a
                        // confirmed selection from the title is
                        // also what dismisses the title and starts
                        // the run; from the driving menu the title
                        // is already dismissed. On failure the
                        // title stays up so the player can retry.)
                        startSelectedRoute(variant: variant, category: category, direction: direction)
                    }
                )
            case .servicePlan:
                ServicePlanSheet()
            case .liveTimetable:
                TimetableControlSheet(model: model)
            case .physicsDetails:
                TrainPhysicsDetailsSheet(model: model)
            case .trafficNetwork:
                TrafficNetworkSheet(
                    scenario: model.trafficScenario,
                    activeSegmentName: model.route.lineName,
                    activeSegmentDistanceM: model.route.distanceM
                )
            case .regionalAudit:
                RegionalNetworkAuditSheet()
            case .howToPlay:
                HowToPlaySheet()
            case .credits:
                CreditsSheet()
            case .audioControls:
                SoundControlSheet(
                    isEnabled: Binding(
                        get: { model.audioEnabled },
                        set: { model.setAudioEnabled($0) }
                    ),
                    volume: Binding(
                        get: { model.audioVolume },
                        set: { model.setAudioVolume(Float($0)) }
                    ),
                    selectedProfile: Binding(
                        get: { model.selectedSoundProfile },
                        set: { model.setTractionSoundProfile($0) }
                    ),
                    announcementLocale: Binding(
                        get: { model.announcementLocale },
                        set: { model.setAnnouncementLocale($0) }
                    ),
                    playShortHorn: { model.playHorn() },
                    playLongHorn: { model.playHorn(long: true) },
                    playBrakeAir: { model.playBrakeAir() },
                    playDepartureChime: { model.playDepartureChime() },
                    playDoorChime: { model.playDoorChime() },
                    announceNextStation: { model.announceNextStation() },
                    announceStop: { model.announceStop() }
                )
            case .vehicleProfiles:
                VehicleProfileSheet(selected: model.selectedVehicleProfile) { profile in
                    model.selectVehicleProfile(profile)
                }
            case .vehicleLibrary:
                VehicleLibrarySheet(selectedVehicleID: $selectedReferenceVehicleID)
            case .environmentQuality:
                EnvironmentQualitySheet(initialSelection: model.environmentSelection) { selection in
                    model.setEnvironmentSelection(selection)
                }
            case .operationsGameplay:
                if let coordinator = model.operationsGameplayCoordinator {
                    NavigationStack { OperationsGameplaySheet(coordinator: coordinator) }
                } else {
                    ContentUnavailableView("運転ゲームを準備できません", systemImage: "exclamationmark.triangle", description: Text("架空時刻表データの読み込みを確認してください。"))
                }
            case .maintenanceGameplay:
                if let coordinator = model.maintenanceGameplayCoordinator {
                    MaintenanceGameplaySheet(coordinator: coordinator)
                } else {
                    ContentUnavailableView("保守ゲームを準備できません", systemImage: "wrench", description: Text("架空路線データの読み込みを確認してください。"))
                }
            case .scenarioProgress:
                ScenarioProgressSheet(model: model)
            case .gameModes:
                if let snapshot = model.gameModeSnapshot {
                    GameModeSessionSheet(
                        session: Binding(
                            get: { model.gameModeSession },
                            set: { model.setGameModeSession($0) }
                        ),
                        context: model.gameModeContext,
                        snapshot: snapshot,
                        hostNotice: model.gameModeHostNotice,
                        onHostEffects: { _, effects in model.handleGameModeHostEffects(effects) },
                        onAcceptedAction: { model.recordDoorProcedureGameModeAction($0) }
                    )
                } else {
                    ContentUnavailableView("ゲームモードを準備できません", systemImage: "gamecontroller", description: Text("架空の運転路線・駅データを確認してください。"))
                }
            case .doorProcedureScoring:
                DoorProcedureScoringSheet(
                    evaluation: model.doorProcedureEvaluation,
                    errorMessage: model.doorProcedureScoringError
                )
            case .saveManager:
                SessionSaveSheet(model: model)
            case .sessionResult:
                if let summary = model.completedSummary {
                    SessionResultSheet(
                        summary: summary,
                        review: model.completedReview,
                        savedURL: model.latestSessionURL,
                        stopEvaluation: model.stopScoringEvaluation,
                        doorProcedureEvaluation: model.doorProcedureEvaluation,
                        onRestart: { model.reset() }
                    )
                } else {
                    EmptyView()
                }
            }
        }
    }

    /// Small auxiliary cab button used at the bottom-right edge
    /// (horn, ATS acknowledge).
    /// batch71: apply a confirmed route selection WITHOUT
    /// freezing the UI on the tap. Previously the sheet's onStart
    /// ran model.selectRoute synchronously inside the tap
    /// handler — RegionalRouteFactory.make, the formation
    /// profile, the block system and the whole reset() (scoring
    /// sessions, protection session, schedule engine, the
    /// 798-train traffic engine and its first snapshot) all
    /// blocked the main thread in the same runloop turn, and the
    /// body re-evaluation that followed created the scene view
    /// and ran the rebuild's synchronous head (route sampling,
    /// island/viaduct pre-passes, texture loads) before any
    /// frame could be presented. The loading state only began
    /// inside that rebuild, so the loading screen could not
    /// appear until every one of those stages had already run:
    /// the player saw the sheet/title sit frozen for the whole
    /// interval. Now the loading state is raised FIRST, the
    /// application is deferred to a fresh main-actor task that
    /// yields once — the runloop gets a turn to dismiss the
    /// sheet and present the loading screen — and only then does
    /// selectRoute run (reporting its own stages through
    /// routeApplyProgressHandler). titleDismissed flips last,
    /// after selectRoute, so the scene view is still created
    /// exactly once with the final route parameters (the batch66
    /// no-double-build property is preserved).
    private func startSelectedRoute(variant: RegionalRouteVariant, category: ServiceCategory, direction: RegionalTravelDirection) {
        guard !pendingRouteStart else { return }
        pendingRouteStart = true
        if !demoDriveEnabled {
            loadingProgress.begin(status: "運行データを準備しています")
        }
        Task { @MainActor in
            await Task.yield()
            if model.selectRoute(variant: variant, category: category, direction: direction) {
                titleDismissed = true
            } else if !demoDriveEnabled {
                // Selection failed (the factory is total, so this
                // is defensive): drop the loading state again so
                // the player is not left on a dead loading screen.
                // From the title the title branch covers the
                // overlay anyway; mid-drive this clears the bar.
                loadingProgress.finish()
            }
            pendingRouteStart = false
        }
    }

    private func cabAuxButton(symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Image(systemName: symbol).font(.system(size: 17, weight: .semibold))
                Text(label).font(.system(size: 8, weight: .bold, design: .rounded))
            }
            .foregroundStyle(.white)
            .frame(width: 54, height: 46)
            .background(Color.black.opacity(0.45), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            HStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8).fill(Color.cyan.opacity(0.16))
                    Image(systemName: "tram.fill").font(.system(size: 15, weight: .bold)).foregroundStyle(.cyan)
                }
                .frame(width: 31, height: 31)
                VStack(alignment: .leading, spacing: 1) {
                    // batch18: the title used to truncate to
                    // "RAILWAY M…" in the tour photos — 12 pt
                    // black with 1.15 tracking is wider than the
                    // old 148 pt minimum frame. The block now
                    // reserves its real width and never shrinks;
                    // the route summary beside it absorbs the
                    // squeeze instead.
                    Text("RAILWAY MASTER")
                        .font(.system(size: 12, weight: .black, design: .rounded))
                        .tracking(1.15)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                    Text("運転・運行管理")
                        .font(.system(size: 9, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.48))
                }
            }
            .frame(minWidth: 176, alignment: .leading)

            Rectangle().fill(Color.white.opacity(0.12)).frame(width: 1, height: 23)

            VStack(alignment: .leading, spacing: 1) {
                Text("\(model.route.departureStation)  →  \(model.route.arrivalStation)")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .lineLimit(1)
                Text("区間 \(Int(model.route.distanceM)) m  ·  次停車 \(nextStopName)  ·  \(Int(distanceToNextStopM.rounded())) m")
                    .font(.system(size: 9, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.5))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Menu {
                Button {
                    activeSheet = .howToPlay
                } label: {
                    Label("遊び方", systemImage: "questionmark.circle")
                }
                Button {
                    activeSheet = .saveManager
                } label: {
                    Label("セーブ / 再開", systemImage: "externaldrive.fill")
                }
                Button {
                    activeSheet = .routeSelection
                } label: {
                    Label("運転ルート・種別・方向", systemImage: "point.3.connected.trianglepath.dotted")
                }
                Button {
                    activeSheet = .operationsGameplay
                } label: {
                    Label("運転ゲーム・業務フロー・採点", systemImage: "checklist")
                }
                Button {
                    activeSheet = .maintenanceGameplay
                } label: {
                    Label("保守・故障・架空基地", systemImage: "wrench.and.screwdriver.fill")
                }
                Button {
                    activeSheet = .scenarioProgress
                } label: {
                    Label("乗務・故障の架空ゲーム進行", systemImage: "list.number")
                }
                Button {
                    activeSheet = .vehicleProfiles
                } label: {
                    Label("車両プロファイル", systemImage: "tram.fill")
                }
                Button {
                    activeSheet = .vehicleLibrary
                } label: {
                    Label("参考車両ライブラリ", systemImage: "books.vertical")
                }
                Button {
                    activeSheet = .environmentQuality
                } label: {
                    Label("環境・カメラ・描画品質", systemImage: "cloud.sun.fill")
                }
                Button {
                    activeSheet = .gameModes
                } label: {
                    Label(
                        model.gameModeSession?.status.isTerminal == false ? "9モードのセッションを開く" : "9つのゲームモード",
                        systemImage: "gamecontroller.fill"
                    )
                }
                Button {
                    activeSheet = .doorProcedureScoring
                } label: {
                    Label("駅別ドア・手順イベント評価", systemImage: "door.left.hand.open")
                }
                Menu("補助レベル・訓練負荷") {
                    ForEach(TrainingMode.allCases, id: \.self) { mode in
                        Button {
                            model.selectTrainingMode(mode)
                        } label: {
                            if model.trainingMode == mode {
                                Label(trainingModeTitle(mode), systemImage: "checkmark")
                            } else {
                                Text(trainingModeTitle(mode))
                            }
                        }
                    }
                }
                Divider()
                Button {
                    activeSheet = .liveTimetable
                } label: {
                    Label("曜日・時間帯・遅延ダイヤ", systemImage: "calendar.badge.clock")
                }
                Button {
                    activeSheet = .servicePlan
                } label: {
                    Label("運行計画・停車種別", systemImage: "list.bullet.rectangle")
                }
                Button {
                    activeSheet = .physicsDetails
                } label: {
                    Label("編成別物理・制動・温度", systemImage: "gauge.with.dots.needle.67percent")
                }
                Button {
                    activeSheet = .trafficNetwork
                } label: {
                    Label("交通ネットワーク", systemImage: "car.2.fill")
                }
                Button {
                    activeSheet = .regionalAudit
                } label: {
                    Label("地域ネットワーク統合監査", systemImage: "point.3.connected.trianglepath.dotted")
                }
                Button {
                    activeSheet = .audioControls
                } label: {
                    Label("サウンド試聴・音量", systemImage: "speaker.wave.2.fill")
                }
                Button {
                    activeSheet = .credits
                } label: {
                    Label("クレジット", systemImage: "doc.text")
                }
            } label: {
                Image(systemName: "calendar.badge.clock")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.cyan)
                    .frame(width: 31, height: 30)
                    .background(Color.white.opacity(0.075), in: Capsule())
            }
            .accessibilityLabel("運転、車両、9つのゲームモード、環境、運行計画の各画面を開く")

            Button {
                model.cycleWeather()
            } label: {
                Label(model.weather.rawValue, systemImage: model.weather.symbolName)
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 9)
                    .frame(height: 30)
                    .background(Color.white.opacity(0.075), in: Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("天候を変更。現在 \(model.weather.rawValue)")

            Menu {
                ForEach([0.0, 0.5, 1.0, 2.0], id: \.self) { load in
                    Button("乗車率 \(Int(load * 100))%") {
                        model.setPassengerLoadFactor(load)
                    }
                }
            } label: {
                Label("\(Int(model.telemetry.passengerLoadFactor * 100))%", systemImage: "person.2.fill")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 9)
                    .frame(height: 30)
                    .background(Color.white.opacity(0.075), in: Capsule())
            }
            .accessibilityLabel("乗車率を選択")

            Button {
                model.togglePause()
            } label: {
                Image(systemName: model.isPaused ? "play.fill" : "pause.fill")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(model.isPaused ? .green : .white)
                    .frame(width: 31, height: 30)
                    .background(Color.white.opacity(0.075), in: Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(model.isPaused ? "運転再開" : "一時停止")

            Button {
                model.reset()
            } label: {
                Image(systemName: "arrow.counterclockwise")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white.opacity(0.8))
                    .frame(width: 31, height: 30)
                    .background(Color.white.opacity(0.075), in: Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("運転をリセット")
        }
        .padding(.horizontal, 3)
    }

    private var operationsHUD: some View {
        VStack(alignment: .leading, spacing: 4) {
            if model.timetableDepartureRemainingSeconds > 0 {
                Label("架空ダイヤ出発待ち · \(Int(model.timetableDepartureRemainingSeconds.rounded(.up)))秒", systemImage: "clock.fill")
                    .font(.system(size: 9, weight: .black, design: .rounded).monospacedDigit())
                    .foregroundStyle(.orange)
            }
            if let reading = model.operationsSnapshot?.signalReading {
                HStack(spacing: 6) {
                    Image(systemName: "trafficlight.fill")
                        .foregroundStyle(signalTint(reading.aspect))
                    Text("信号 \(signalName(reading.aspect))")
                        .foregroundStyle(.white)
                }
                .font(.system(size: 10, weight: .bold, design: .rounded).monospacedDigit())
            } else {
                Label("信号状態 未取得", systemImage: "trafficlight")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.7))
            }

            if model.protectionNeedsAcknowledgement {
                HStack(spacing: 6) {
                    Text("架空ATS-S 確認待ち")
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .foregroundStyle(.orange)
                    Button("確認") { _ = model.acknowledgeATS() }
                        .font(.system(size: 9, weight: .black, design: .rounded))
                        .buttonStyle(.borderedProminent)
                        .tint(.orange)
                }
            }
            if let reason = model.operationsSnapshot?.automaticBrakeReason, model.operationsSnapshot?.automaticBrakeActive == true {
                Text(reason)
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .foregroundStyle(.red)
                    .lineLimit(2)
            }
            if let snapshot = model.operationsSnapshot, let ats = snapshot.atsStatus {
                HStack(spacing: 6) {
                    Text("ATS · \(atsName(ats.state))")
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .foregroundStyle(ats.state == .automaticBrakeApplied ? .red : .orange)
                    if ats.state == .awaitingAcknowledgement, let remaining = ats.remainingSeconds {
                        Text("\(Int(remaining.rounded(.up)))秒")
                            .font(.system(size: 9, weight: .black, design: .rounded).monospacedDigit())
                        Button("確認") { _ = model.acknowledgeATS() }
                            .font(.system(size: 9, weight: .black, design: .rounded))
                            .buttonStyle(.borderedProminent)
                            .tint(.orange)
                    }
                    if snapshot.automaticBrakeActive {
                        Image(systemName: "exclamationmark.octagon.fill")
                            .foregroundStyle(.red)
                    }
                }
            }
            if let warning = model.maintenanceWarning {
                Label(warning, systemImage: "wrench.and.screwdriver.fill")
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .foregroundStyle(.orange)
                    .lineLimit(2)
            }
            Label("乗務ゲーム \(model.crewWorkflow.events.count)/20 · \(model.crewWorkflow.currentPhase?.displayName ?? "完了")", systemImage: "list.number")
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .foregroundStyle(.cyan)
                .lineLimit(1)
            if !model.activeIncidentEvents.isEmpty {
                Label("架空イベント \(model.activeIncidentEvents.count)件 · ゲーム効果適用中", systemImage: "bolt.trianglebadge.exclamationmark.fill")
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .foregroundStyle(.orange)
                    .lineLimit(1)
            }
            if let notice = model.storageNotice {
                Label(notice, systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .foregroundStyle(.orange)
                    .lineLimit(2)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(.black.opacity(0.65), in: RoundedRectangle(cornerRadius: 9))
        .overlay(RoundedRectangle(cornerRadius: 9).stroke(Color.white.opacity(0.13), lineWidth: 1))
        .accessibilityElement(children: .contain)
    }

    private func signalName(_ aspect: ThreeAspectSignal) -> String {
        switch aspect {
        case .red: "停止"
        case .doubleYellow: "警戒"
        case .yellow: "注意"
        case .yellowGreen: "減速"
        case .green: "進行"
        }
    }

    private func signalTint(_ aspect: ThreeAspectSignal) -> Color {
        switch aspect {
        case .red: .red
        case .doubleYellow: .orange
        case .yellow: .yellow
        case .yellowGreen: Color(red: 0.62, green: 0.78, blue: 0.25)
        case .green: .green
        }
    }

    private func atsName(_ state: EducationalATSState) -> String {
        switch state {
        case .idle: "待機"
        case .awaitingAcknowledgement: "確認待ち"
        case .acknowledged: "確認済み"
        case .automaticBrakeApplied: "自動制動"
        }
    }

    private func trainingModeTitle(_ mode: TrainingMode) -> String {
        switch mode {
        case .practice: "練習（ヒントあり）"
        case .standard: "標準"
        case .disruptionTraining: "架空イベント"
        }
    }

    private var instrumentPanel: some View {
        VStack(spacing: 5) {
            HStack {
                Text("速度計")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                Spacer()
                Circle().fill(speedKmh > model.telemetry.currentSpeedLimitKmh ? .red : .green)
                    .frame(width: 6, height: 6)
                Text(speedKmh > model.telemetry.currentSpeedLimitKmh ? "速度超過" : "正常")
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .foregroundStyle(speedKmh > model.telemetry.currentSpeedLimitKmh ? .red : .green)
            }

            SpeedometerView(speedKmh: speedKmh, maximumKmh: model.train.maximumSpeedKmh)
                .frame(maxWidth: .infinity)
                .frame(height: 122)

            HStack(spacing: 5) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("制限").foregroundStyle(.white.opacity(0.48))
                    Text("\(Int(model.telemetry.currentSpeedLimitKmh)) km/h")
                        .foregroundStyle(.white)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Rectangle().fill(Color.white.opacity(0.12)).frame(width: 1, height: 24)
                VStack(alignment: .leading, spacing: 2) {
                    Text("次停車まで").foregroundStyle(.white.opacity(0.48))
                    Text(String(format: "%+.0f m", distanceToNextStopM))
                        .foregroundStyle(distanceToNextStopM < 0 ? .orange : .white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .font(.system(size: 9, weight: .bold, design: .rounded).monospacedDigit())

            HStack(spacing: 5) {
                Image(systemName: "arrow.up.right")
                    .foregroundStyle(.cyan)
                Text(String(format: "加速度 %+.2f m/s²", model.telemetry.accelerationMps2))
                    .foregroundStyle(.white.opacity(0.78))
                Spacer(minLength: 0)
                Text("\(model.train.carCount)両")
                    .foregroundStyle(.white.opacity(0.5))
            }
            .font(.system(size: 9, weight: .semibold, design: .rounded).monospacedDigit())
        }
        .padding(9)
        .background(CabPanel())
    }

    private var controllerPanel: some View {
        VStack(spacing: 6) {
            HStack {
                Text("主幹制御器 / ブレーキ弁")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                Spacer()
                Text("ドラッグでノッチ操作")
                    .font(.system(size: 8, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.42))
            }

            HStack(spacing: 9) {
                NotchLever(
                    title: "力行",
                    valueLabel: model.controls.throttleNotch == 0 ? "切" : "P\(model.controls.throttleNotch)",
                    value: model.controls.throttleNotch,
                    maximum: max(model.train.tractionNotchFractions.count - 1, 1),
                    tint: Color.cyan
                ) { model.setThrottle($0) }

                NotchLever(
                    title: "常用ブレーキ",
                    valueLabel: model.controls.brakeNotch == 0 ? "緩め" : "B\(model.controls.brakeNotch)",
                    value: model.controls.brakeNotch,
                    maximum: 7,
                    tint: Color.orange
                ) { model.setBrake($0) }
            }
            .frame(maxHeight: .infinity)

            if model.selectedVehicleProfile == .resistanceFormation8 || model.selectedVehicleProfile == .resistanceFormation10 {
                Button {
                    model.setMasterReversed(!model.controls.masterReversed)
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.uturn.backward")
                        Text(model.controls.masterReversed ? "抑速（マスコン逆回し）ON" : "抑速（マスコン逆回し）")
                        Spacer(minLength: 0)
                    }
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(model.controls.masterReversed ? .black : .white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(model.controls.masterReversed ? Color.orange : Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)
                Text("1ノッチで進段を止める。10両はページに無い追加PLACEHOLDER。")
                    .font(.system(size: 8, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.45))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if model.selectedVehicleProfile == .fieldChopperFormation8 || model.selectedVehicleProfile == .fieldChopperFormation10 {
                let lamps = model.trainPhysicsTelemetry.controlIndicators
                let names = [
                    lamps.seriesLamp ? "直列" : nil,
                    lamps.parallelLamp ? "並列" : nil,
                    lamps.finalStageLamp ? "最終" : nil,
                    lamps.fieldWeakeningLamp ? "界磁弱メ" : nil,
                    lamps.regenerativeLamp ? "回生制動" : nil
                ].compactMap { $0 }
                Text(names.isEmpty ? "界磁チョッパ灯: 消灯" : "界磁チョッパ灯: " + names.joined(separator: " "))
                    .font(.system(size: 9, weight: .semibold, design: .rounded))
                    .foregroundStyle(.orange.opacity(0.9))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if let cruise = model.trainPhysicsTelemetry.controlIndicators.cruiseTargetKmh,
               model.selectedVehicleProfile == .vvvfFormation8 || model.selectedVehicleProfile == .vvvfFormation10 {
                Text(String(format: "定速 %.0f km/h（ページの記述・PLACEHOLDER制御）", cruise))
                    .font(.system(size: 9, weight: .semibold, design: .rounded))
                    .foregroundStyle(.cyan.opacity(0.9))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack(spacing: 7) {
                Button {
                    model.setEmergencyBrake(!model.controls.emergencyBrake)
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.octagon.fill")
                        Text(model.controls.emergencyBrake ? "非常制動 ON" : "非常ブレーキ")
                        Spacer(minLength: 0)
                        Text(model.controls.emergencyBrake ? "解除" : "EB")
                            .font(.system(size: 9, weight: .black, design: .rounded))
                    }
                    .font(.system(size: 10, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .frame(height: 31)
                    .background(model.controls.emergencyBrake ? Color.red : Color.red.opacity(0.58), in: RoundedRectangle(cornerRadius: 9))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(model.controls.emergencyBrake ? "非常ブレーキ作動中。タップで解除" : "非常ブレーキを作動")

                Text(model.isPaused ? "PAUSE" : "RUN")
                    .font(.system(size: 8, weight: .black, design: .rounded))
                    .tracking(0.8)
                    .foregroundStyle(model.isPaused ? .orange : .green)
                    .frame(width: 49, height: 31)
                    .background(Color.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 9))
            }
        }
        .padding(9)
        .background(CabPanel())
    }

    private var pneumaticPanel: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text("空気・電気系")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                Spacer(minLength: 3)
                if model.telemetry.isWheelSlipActive || model.telemetry.isBrakeSlipActive {
                    Label(model.telemetry.isWheelSlipActive && model.telemetry.isBrakeSlipActive ? "空転・滑走" : (model.telemetry.isWheelSlipActive ? "空転" : "滑走"), systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 8, weight: .black, design: .rounded))
                        .foregroundStyle(.orange)
                } else {
                    Text("SYSTEM OK")
                        .font(.system(size: 8, weight: .black, design: .rounded))
                        .tracking(0.6)
                        .foregroundStyle(.green)
                }
            }

            PressureBar(label: "MR · 元空気ダメ", value: model.telemetry.mainReservoirPressureKPa, maximum: 800, tint: .cyan)
            PressureBar(label: "BP · ブレーキ管", value: model.telemetry.brakePipePressureKPa, maximum: 500, tint: .teal)
            PressureBar(label: "BC · 制動筒", value: model.telemetry.brakeCylinderPressureKPa, maximum: 400, tint: .orange)

            Rectangle().fill(Color.white.opacity(0.1)).frame(height: 1)

            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("引張力").foregroundStyle(.white.opacity(0.48))
                    Text(String(format: "%.0f kN", model.telemetry.tractionForceN / 1_000))
                        .foregroundStyle(.cyan)
                }
                Spacer(minLength: 4)
                VStack(alignment: .leading, spacing: 2) {
                    Text("制動力").foregroundStyle(.white.opacity(0.48))
                    Text(String(format: "%.0f kN", model.telemetry.brakingForceN / 1_000))
                        .foregroundStyle(.orange)
                }
                Spacer(minLength: 4)
                VStack(alignment: .leading, spacing: 2) {
                    Text("回生 / 空気").foregroundStyle(.white.opacity(0.48))
                    Text("\(Int(model.telemetry.regenerativeBrakeForceN / 1_000)) / \(Int(model.telemetry.airBrakeForceN / 1_000))")
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
            .font(.system(size: 9, weight: .bold, design: .rounded).monospacedDigit())

            Rectangle().fill(Color.white.opacity(0.1)).frame(height: 1)

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("編成質量 · 慣性換算込み")
                        .font(.system(size: 8, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.45))
                    Text(String(format: "%.0f t", model.telemetry.effectiveMassKg / 1_000))
                        .font(.system(size: 13, weight: .black, design: .rounded).monospacedDigit())
                }
                Spacer(minLength: 4)
                VStack(alignment: .trailing, spacing: 2) {
                    Text("推定制動距離")
                        .font(.system(size: 8, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.45))
                    Text(String(format: "%.0f m", model.telemetry.predictedStoppingDistanceM))
                        .font(.system(size: 13, weight: .black, design: .rounded).monospacedDigit())
                        .foregroundStyle(.white)
                }
            }

            Spacer(minLength: 0)
            Text("架空車両・物理モデル検証用。実車諸元・運転保安装置ではありません。")
                .font(.system(size: 7, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.38))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(9)
        .background(CabPanel())
    }
}

private struct CabPanel: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 13, style: .continuous)
            .fill(LinearGradient(
                colors: [Color(red: 0.085, green: 0.125, blue: 0.16), Color(red: 0.045, green: 0.073, blue: 0.103)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ))
            .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous).stroke(Color.white.opacity(0.09), lineWidth: 1))
            .shadow(color: .black.opacity(0.2), radius: 8, y: 3)
    }
}

private struct SpeedometerView: View {
    let speedKmh: Double
    let maximumKmh: Double

    var body: some View {
        GeometryReader { geometry in
            let side = min(geometry.size.width, geometry.size.height)
            let value = min(max(speedKmh, 0), 120)
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.075), lineWidth: 9)
                    .padding(7)
                Circle()
                    .trim(from: 0, to: 0.75 * min(value / 120, 1))
                    .stroke(LinearGradient(colors: [.cyan, .teal], startPoint: .leading, endPoint: .trailing), style: StrokeStyle(lineWidth: 9, lineCap: .round))
                    .rotationEffect(.degrees(135))
                    .padding(7)

                Canvas { context, size in
                    // Xcode 15.2: bare cos/sin are ambiguous here — on arm64
                    // CGFloat == Double, so Darwin's cos(Double) and
                    // CoreGraphics' cos(CGFloat) collide. Qualify with
                    // Darwin (Xcode 16 dropped the duplicate overloads).
                    let center = CGPoint(x: size.width / 2, y: size.height / 2)
                    let radius = min(size.width, size.height) * 0.43
                    for tick in 0...12 {
                        let fraction = Double(tick) / 12
                        let angle = (-135 + fraction * 270) * .pi / 180
                        let outer = CGPoint(x: center.x + Darwin.cos(angle) * radius, y: center.y + Darwin.sin(angle) * radius)
                        let innerRadius = radius - (tick.isMultiple(of: 2) ? 10 : 5)
                        let inner = CGPoint(x: center.x + Darwin.cos(angle) * innerRadius, y: center.y + Darwin.sin(angle) * innerRadius)
                        var path = Path()
                        path.move(to: inner)
                        path.addLine(to: outer)
                        context.stroke(path, with: .color(.white.opacity(tick.isMultiple(of: 2) ? 0.62 : 0.28)), lineWidth: tick.isMultiple(of: 2) ? 1.5 : 1)
                    }

                    let needleAngle = (-135 + min(max(speedKmh / 120, 0), 1) * 270) * .pi / 180
                    var needle = Path()
                    needle.move(to: center)
                    needle.addLine(to: CGPoint(x: center.x + Darwin.cos(needleAngle) * radius * 0.72, y: center.y + Darwin.sin(needleAngle) * radius * 0.72))
                    context.stroke(needle, with: .color(.cyan), style: StrokeStyle(lineWidth: 2.4, lineCap: .round))
                    let hub = CGRect(x: center.x - 3.5, y: center.y - 3.5, width: 7, height: 7)
                    context.fill(Path(ellipseIn: hub), with: .color(.white))
                }

                VStack(spacing: 0) {
                    Spacer(minLength: side * 0.27)
                    Text("\(Int(speedKmh.rounded()))")
                        .font(.system(size: min(side * 0.245, 33), weight: .black, design: .rounded).monospacedDigit())
                        .contentTransition(.numericText())
                    Text("km/h")
                        .font(.system(size: 8, weight: .bold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.5))
                    Spacer(minLength: 0)
                }
            }
            .frame(width: side, height: side)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("速度 \(Int(speedKmh.rounded())) キロメートル毎時")
    }
}

private struct NotchLever: View {
    let title: String
    let valueLabel: String
    let value: Int
    let maximum: Int
    let tint: Color
    let onChange: (Int) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.72))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Spacer(minLength: 2)
                Text(valueLabel)
                    .font(.system(size: 12, weight: .black, design: .rounded).monospacedDigit())
                    .foregroundStyle(tint)
            }

            GeometryReader { geometry in
                let height = max(geometry.size.height, 60)
                let travel = max(height - 16, 1)
                ZStack(alignment: .topLeading) {
                    Capsule()
                        .fill(Color.black.opacity(0.55))
                        .overlay(Capsule().stroke(Color.white.opacity(0.11), lineWidth: 1))
                        .frame(width: 13, height: travel)
                        .position(x: 20, y: height / 2)

                    ForEach(0...maximum, id: \.self) { notch in
                        let y = 8 + travel - CGFloat(notch) / CGFloat(maximum) * travel
                        HStack(spacing: 4) {
                            Circle()
                                .fill(notch == value ? tint : Color.white.opacity(0.30))
                                .frame(width: notch == value ? 5 : 3, height: notch == value ? 5 : 3)
                            Text(notch == 0 ? (title == "力行" ? "切" : "緩め") : "\(title == "力行" ? "P" : "B")\(notch)")
                                .font(.system(size: 8, weight: notch == value ? .black : .medium, design: .rounded).monospacedDigit())
                                .foregroundStyle(notch == value ? .white : .white.opacity(0.43))
                        }
                        .position(x: 59, y: y)
                        .contentShape(Rectangle())
                        .onTapGesture { select(notch) }
                    }

                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(LinearGradient(colors: [tint, tint.opacity(0.68)], startPoint: .top, endPoint: .bottom))
                        .overlay(RoundedRectangle(cornerRadius: 5).stroke(.white.opacity(0.6), lineWidth: 0.7))
                        .frame(width: 25, height: 12)
                        .shadow(color: tint.opacity(0.38), radius: 5)
                        .position(x: 20, y: 8 + travel - CGFloat(value) / CGFloat(maximum) * travel)
                        .allowsHitTesting(false)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0).onChanged { gesture in
                    let fraction = min(max(1 - (gesture.location.y - 8) / travel, 0), 1)
                    select(Int((fraction * CGFloat(maximum)).rounded()))
                })
            }
            .accessibilityElement()
            .accessibilityLabel(title)
            .accessibilityValue(valueLabel)
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: select(min(value + 1, maximum))
                case .decrement: select(max(value - 1, 0))
                @unknown default: break
                }
            }
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 5)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.opacity(0.17), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
    }

    private func select(_ proposedValue: Int) {
        let next = min(max(proposedValue, 0), maximum)
        guard next != value else { return }
        UISelectionFeedbackGenerator().selectionChanged()
        onChange(next)
    }
}

/// One-handle master controller: EB at the very top (one detent
/// past full service brake), then the brake steps, N in the
/// middle, power notches at the bottom. `value` is >0 for a brake
/// step, `brakeMaximum + 1` for EB, 0 for N, and <0 for a power
/// notch (absolute value = notch).
private struct CombinedNotchLever: View {
    let value: Int
    let brakeMaximum: Int
    let powerMaximum: Int
    let onChange: (Int) -> Void

    private var emergencyValue: Int { brakeMaximum + 1 }
    private var span: Int { brakeMaximum + 1 + powerMaximum }
    private var currentLabel: String {
        if value >= emergencyValue { return "EB" }
        if value > 0 { return "B\(value)" }
        if value < 0 { return "P\(-value)" }
        return "N"
    }
    private var currentTint: Color {
        if value >= emergencyValue { return .red }
        if value > 0 { return .orange }
        if value < 0 { return .cyan }
        return .white
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline) {
                Text("マスコン")
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.72))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Spacer(minLength: 2)
                Text(currentLabel)
                    .font(.system(size: 13, weight: .black, design: .rounded).monospacedDigit())
                    .foregroundStyle(currentTint)
            }

            GeometryReader { geometry in
                let height = max(geometry.size.height, 60)
                let travel = max(height - 16, 1)
                ZStack(alignment: .topLeading) {
                    Capsule()
                        .fill(Color.black.opacity(0.55))
                        .overlay(Capsule().stroke(Color.white.opacity(0.11), lineWidth: 1))
                        .frame(width: 13, height: travel)
                        .position(x: 20, y: height / 2)

                    ForEach(0...span, id: \.self) { index in
                        let combined = emergencyValue - index
                        let y = 8 + travel - CGFloat(combined + powerMaximum) / CGFloat(span) * travel
                        HStack(spacing: 4) {
                            Circle()
                                .fill(combined == value ? currentTint : Color.white.opacity(0.30))
                                .frame(width: combined == value ? 5 : 3, height: combined == value ? 5 : 3)
                            Text(combined >= emergencyValue ? "EB" : combined > 0 ? "B\(combined)" : combined < 0 ? "P\(-combined)" : "N")
                                .font(.system(size: 8, weight: combined == value ? .black : .medium, design: .rounded).monospacedDigit())
                                .foregroundStyle(combined == value ? .white : .white.opacity(0.43))
                        }
                        .position(x: 59, y: y)
                        .contentShape(Rectangle())
                        .onTapGesture { select(combined) }
                    }

                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(LinearGradient(colors: [currentTint, currentTint.opacity(0.68)], startPoint: .top, endPoint: .bottom))
                        .overlay(RoundedRectangle(cornerRadius: 5).stroke(.white.opacity(0.6), lineWidth: 0.7))
                        .frame(width: 25, height: 12)
                        .shadow(color: currentTint.opacity(0.38), radius: 5)
                        .position(x: 20, y: 8 + travel - CGFloat(value + powerMaximum) / CGFloat(span) * travel)
                        .allowsHitTesting(false)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0).onChanged { gesture in
                    let fraction = min(max(1 - (gesture.location.y - 8) / travel, 0), 1)
                    select(Int((fraction * CGFloat(span)).rounded()) - powerMaximum)
                })
            }
            .accessibilityElement()
            .accessibilityLabel("マスコン")
            .accessibilityValue(currentLabel)
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: select(min(value + 1, emergencyValue))
                case .decrement: select(max(value - 1, -powerMaximum))
                @unknown default: break
                }
            }
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 5)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.opacity(0.17), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
    }

    private func select(_ proposedValue: Int) {
        let next = min(max(proposedValue, -powerMaximum), emergencyValue)
        guard next != value else { return }
        if next == emergencyValue {
            NotchHaptic.emergencyBrake(engaged: true)
        } else if value == emergencyValue {
            NotchHaptic.emergencyBrake(engaged: false)
        } else {
            NotchHaptic.notchChanged(to: next, brakeMaximum: brakeMaximum)
        }
        onChange(next)
    }
}

/// Launch title screen (user decision 2026-11-12): a slow
/// crossfading slideshow of five CC0 E231 photographs from
/// Wikimedia Commons (Resources/title_e231.jpg and
/// title_e231_2.jpg ... title_e231_5.jpg; authors and titles
/// are listed in the in-app credits) full bleed under a dark
/// scrim, the game title, and one start button. Tapping
/// anywhere also starts. ContentView only shows this on a
/// normal launch; demo-drive launches bypass it, and the
/// simulation stays parked behind it until start. The photos
/// are decoded once when the view is created, and the slide
/// timer is a Timer publisher whose connection ends with the
/// view, so nothing keeps running after the title goes away.
/// batch66: full-screen loading view shown while the scene
/// world builds — from a confirmed route selection to the
/// first drivable frame, and during a mid-drive route
/// re-selection. Same visual family as the title screen
/// (title photo under a dark gradient), with the build's
/// progress as a large percent figure over a Too Railway
/// teal bar and a one-line status naming the current build
/// phase. The percent is monotonic and reaches 100 only
/// when the build has fully landed (see LoadingProgress).
private struct LoadingScreenView: View {
    @ObservedObject var progress: LoadingProgress

    private let backgroundImage: UIImage?

    init(progress: LoadingProgress) {
        self._progress = ObservedObject(wrappedValue: progress)
        // Reuse the title photographs as the backdrop; the
        // first one that loads wins, the dark base colour is
        // the fallback when none do.
        var loaded: UIImage?
        for name in ["title_e231", "title_e231_2", "title_e231_3", "title_e231_4", "title_e231_5"] {
            if let url = Bundle.main.url(forResource: name, withExtension: "jpg"),
               let image = UIImage(contentsOfFile: url.path) {
                loaded = image
                break
            }
        }
        backgroundImage = loaded
    }

    var body: some View {
        ZStack {
            Color(red: 0.025, green: 0.045, blue: 0.067)
                .ignoresSafeArea()
            if let backgroundImage {
                Image(uiImage: backgroundImage)
                    .resizable()
                    .scaledToFill()
                    .ignoresSafeArea()
            }
            LinearGradient(
                colors: [Color.black.opacity(0.52), Color.black.opacity(0.30), Color.black.opacity(0.82)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()
                Text("RAILWAY MASTER")
                    .font(.system(size: 30, weight: .heavy, design: .rounded))
                    .tracking(3)
                    .foregroundStyle(.white)
                Text("東央電鉄")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.75))
                    .padding(.top, 6)
                Spacer()
                HStack(alignment: .lastTextBaseline, spacing: 2) {
                    Text("\(progress.percent)")
                        .font(.system(size: 68, weight: .bold, design: .rounded).monospacedDigit())
                        .foregroundStyle(.white)
                    Text("%")
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.85))
                }
                GeometryReader { barGeometry in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.white.opacity(0.18))
                        Capsule()
                            .fill(Color(red: 38.0 / 255.0, green: 140.0 / 255.0, blue: 161.0 / 255.0))
                            .frame(width: barGeometry.size.width * CGFloat(progress.percent) / 100)
                    }
                }
                .frame(height: 8)
                .padding(.top, 18)
                Text(progress.statusText)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.88))
                    .padding(.top, 14)
                Spacer()
                    .frame(height: 56)
            }
            .padding(.horizontal, 40)
        }
    }
}

private struct TitleScreenView: View {
    let onStart: () -> Void
    let onHelp: () -> Void

    /// batch93: the five title JPEGs (~3.5 MB on disk) were
    /// reloaded from the bundle on every TitleScreenView
    /// creation — and SwiftUI re-creates this view whenever
    /// ContentView's body re-evaluates, including the route
    /// selection sheet's presentation and dismissal, so the
    /// selection flow paid the file I/O again at exactly the
    /// presentation moment. Load once per process; the
    /// slideshow reads the same images in the same order.
    private static let cachedTitleImages: [UIImage] = loadTitleImages()

    private let titleImages: [UIImage]
    @State private var slideIndex = 0

    private let slideTimer = Timer.publish(every: 5, on: .main, in: .common).autoconnect()

    init(onStart: @escaping () -> Void, onHelp: @escaping () -> Void = {}) {
        self.onStart = onStart
        self.onHelp = onHelp
        self.titleImages = Self.cachedTitleImages
    }

    private static func loadTitleImages() -> [UIImage] {
        let names = ["title_e231", "title_e231_2", "title_e231_3", "title_e231_4", "title_e231_5"]
        var images: [UIImage] = []
        for name in names {
            guard let url = Bundle.main.url(forResource: name, withExtension: "jpg") else { continue }
            guard let image = UIImage(contentsOfFile: url.path) else { continue }
            images.append(image)
        }
        return images
    }

    var body: some View {
        ZStack {
            Color(red: 0.025, green: 0.045, blue: 0.067)
            if !titleImages.isEmpty {
                Image(uiImage: titleImages[slideIndex])
                    .resizable()
                    .scaledToFill()
                    .id(slideIndex)
                    .transition(.opacity)
            }
            LinearGradient(
                colors: [Color.black.opacity(0.52), Color.black.opacity(0.04), Color.black.opacity(0.80)],
                startPoint: .top,
                endPoint: .bottom
            )
            // batch18: tap-to-start lives on the background and
            // the title block only, so the buttons below (start
            // / how-to-play) never trigger it by accident.
            .onTapGesture { onStart() }
            VStack(spacing: 0) {
                Spacer()
                VStack(spacing: 10) {
                    Text("東央電鉄 TOO RAILWAY")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.92))
                        .tracking(2)
                    Text("RAILWAY MASTER")
                        .font(.system(size: 44, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .shadow(color: .black.opacity(0.6), radius: 8, y: 3)
                    Rectangle()
                        .fill(Color(red: 0.15, green: 0.55, blue: 0.63))
                        .frame(width: 120, height: 3)
                }
                .onTapGesture { onStart() }
                Spacer()
                Button(action: onStart) {
                    Text("運転をはじめる")
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 15)
                        .background(Color(red: 0.12, green: 0.23, blue: 0.43), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .padding(.horizontal, 40)
                Button(action: onHelp) {
                    Text("遊び方・信号の見方")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.92))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        .background(Color.white.opacity(0.14), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .padding(.horizontal, 40)
                .padding(.top, 10)
                Text("タップして開始")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.65))
                    .padding(.top, 10)
                Spacer()
                    .frame(height: 54)
            }
            .padding(.horizontal, 20)
        }
        .ignoresSafeArea()
        .contentShape(Rectangle())
        .onReceive(slideTimer) { _ in
            guard titleImages.count > 1 else { return }
            let nextIndex = (slideIndex + 1) % titleImages.count
            withAnimation(.easeInOut(duration: 1.0)) {
                slideIndex = nextIndex
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("RAILWAY MASTER タイトル画面")
    }
}

/// batch18: the how-to-play sheet — a ¥2,000-tier product
/// cannot drop a first-time buyer in front of a mascon, ATS
/// and five signal aspects with no explanation. Reachable
/// from the title screen (before the first departure) and
/// from the driving menu.
private struct HowToPlaySheet: View {
    @Environment(\.dismiss) private var dismiss

    private func section(_ title: String, _ lines: [String]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(Color(red: 0.45, green: 0.75, blue: 0.85))
            ForEach(lines, id: \.self) { line in
                Text(line)
                    .font(.system(size: 13.5, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.88))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func signalRow(_ color: Color, _ name: String, _ rule: String) -> some View {
        HStack(spacing: 10) {
            Circle().fill(color).frame(width: 13, height: 13)
            Text(name)
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .frame(width: 44, alignment: .leading)
            Text(rule)
                .font(.system(size: 13.5, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.85))
        }
    }

    var body: some View {
        ZStack {
            Color(red: 0.025, green: 0.045, blue: 0.067).ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    HStack {
                        Text("遊び方")
                            .font(.system(size: 22, weight: .black, design: .rounded))
                        Spacer()
                        Button("閉じる") { dismiss() }
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                    }
                    section("運転のしかた", [
                        "左端のハンドル（マスコン）を縦にドラッグしてノッチを選びます。上から EB（非常ブレーキ）・B7〜B1（ブレーキ）・N（中立）・P1〜P5（力行）です。",
                        "右下のボタンは「警笛」と「ATS確認」。ATSの警報が出たら、すぐに ATS確認 を押してください。",
                        "速度は左下に表示されます。信号の現示と区間の制限速度を守ってください。",
                    ])
                    VStack(alignment: .leading, spacing: 8) {
                        Text("信号の見方")
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                            .foregroundStyle(Color(red: 0.45, green: 0.75, blue: 0.85))
                        signalRow(.green, "進行", "制限なしで進めます")
                        signalRow(.yellow, "減速", "黄＋緑の2灯。75 km/hまで")
                        signalRow(.yellow, "注意", "黄1灯。55 km/hまで")
                        signalRow(.yellow, "警戒", "黄2灯。25 km/hまで")
                        signalRow(.red, "停止", "赤。信号の手前で停止")
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    section("停車と採点", [
                        "次の停車駅と残りの距離は、画面の上部に出ます。",
                        "ホームの停止目標に合わせて止めてください。停車位置・定時性・ドアの手順で採点されます。",
                        "停車中はドアが開閉します。ドアが閉まってから発車してください。",
                    ])
                    section("路線と列車", [
                        "東央本線 60 km・32駅のほか、支線・動物園線・テーマパーク線があります。",
                        "種別は各停・準急・快速・急行・快速急行・特急。メニューから路線・種別・上下方向を変更できます。",
                        "対向列車はダイヤどおりに運行しています。待避駅では追い越し・行き違いがあります。",
                        "視点（運転台／前方展望）と画質は、メニューの「環境・カメラ・描画品質」から変更できます。",
                    ])
                }
                .padding(20)
            }
        }
        .preferredColorScheme(.dark)
    }
}

/// Haptic feedback for the driving controls. Generators are kept alive so
/// `prepare()` actually warms the Taptic Engine between detents; a fresh
/// generator per tap drops or weakens most clicks on real hardware.
/// Ordinary notches get the light selection tick, the neutral detent a
/// firmer medium thunk, and full service brake / emergency a heavy one,
/// roughly matching the feel of a real master controller.
private enum NotchHaptic {
    static let selection = UISelectionFeedbackGenerator()
    static let medium = UIImpactFeedbackGenerator(style: .medium)
    static let heavy = UIImpactFeedbackGenerator(style: .heavy)

    static func notchChanged(to value: Int, brakeMaximum: Int) {
        if value == 0 {
            medium.impactOccurred()
            medium.prepare()
        } else if value == brakeMaximum {
            heavy.impactOccurred()
            heavy.prepare()
        } else {
            selection.selectionChanged()
            selection.prepare()
        }
    }

    static func emergencyBrake(engaged: Bool) {
        if engaged {
            heavy.impactOccurred()
        } else {
            medium.impactOccurred()
        }
        heavy.prepare()
        medium.prepare()
    }
}

private struct PressureBar: View {
    let label: String
    let value: Double
    let maximum: Double
    let tint: Color

    var body: some View {
        VStack(spacing: 3) {
            HStack {
                Text(label)
                    .font(.system(size: 8, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.63))
                Spacer(minLength: 2)
                Text(String(format: "%.0f kPa", value))
                    .font(.system(size: 9, weight: .black, design: .rounded).monospacedDigit())
                    .foregroundStyle(.white)
            }
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.08))
                    Capsule().fill(tint.gradient).frame(width: max(3, geometry.size.width * min(max(value / maximum, 0), 1)))
                }
            }
            .frame(height: 5)
        }
    }
}

private struct TrackPanorama: View {
    let route: RailwayRouteProfile
    let positionM: Double
    let speedKmh: Double
    let weather: WeatherCondition

    var body: some View {
        Canvas { context, size in
            let horizon = size.height * 0.43
            let centerX = size.width / 2
            let sky: [Color]
            switch weather {
            case .dry: sky = [Color(red: 0.15, green: 0.34, blue: 0.45), Color(red: 0.80, green: 0.61, blue: 0.39)]
            case .rain, .heavyRain: sky = [Color(red: 0.12, green: 0.23, blue: 0.31), Color(red: 0.39, green: 0.43, blue: 0.43)]
            case .snow: sky = [Color(red: 0.27, green: 0.39, blue: 0.48), Color(red: 0.65, green: 0.68, blue: 0.66)]
            case .fog: sky = [Color(red: 0.45, green: 0.50, blue: 0.52), Color(red: 0.62, green: 0.64, blue: 0.64)]
            }
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .linearGradient(Gradient(colors: sky), startPoint: .zero, endPoint: CGPoint(x: 0, y: horizon)))

            var distantHill = Path()
            distantHill.move(to: CGPoint(x: 0, y: horizon + 7))
            distantHill.addCurve(to: CGPoint(x: size.width * 0.53, y: horizon + 4), control1: CGPoint(x: size.width * 0.17, y: horizon - 15), control2: CGPoint(x: size.width * 0.36, y: horizon + 18))
            distantHill.addCurve(to: CGPoint(x: size.width, y: horizon + 11), control1: CGPoint(x: size.width * 0.75, y: horizon - 8), control2: CGPoint(x: size.width * 0.87, y: horizon + 18))
            distantHill.addLine(to: CGPoint(x: size.width, y: size.height))
            distantHill.addLine(to: CGPoint(x: 0, y: size.height))
            distantHill.closeSubpath()
            context.fill(distantHill, with: .color(Color(red: 0.10, green: 0.19, blue: 0.20).opacity(0.90)))

            // Fictional low-rise skyline provides a readable, original horizon without borrowed imagery.
            for building in 0..<18 {
                let x = CGFloat(building) * size.width / 17
                let width = size.width * (0.018 + CGFloat((building * 7) % 5) * 0.004)
                let height = size.height * (0.08 + CGFloat((building * 11) % 7) * 0.018)
                let rect = CGRect(x: x - width / 2, y: horizon - height * 0.58, width: width, height: height)
                context.fill(Path(roundedRect: rect, cornerRadius: 1), with: .color(Color(red: 0.12, green: 0.20, blue: 0.21).opacity(0.70)))
            }

            var ballast = Path()
            ballast.move(to: CGPoint(x: centerX - 3, y: horizon + 2))
            ballast.addLine(to: CGPoint(x: centerX + 3, y: horizon + 2))
            ballast.addLine(to: CGPoint(x: size.width * 0.82, y: size.height))
            ballast.addLine(to: CGPoint(x: size.width * 0.18, y: size.height))
            ballast.closeSubpath()
            context.fill(ballast, with: .color(Color(red: 0.18, green: 0.20, blue: 0.19)))

            let phase = (positionM / 25).truncatingRemainder(dividingBy: 1)
            for sleeper in 0..<22 {
                let t = (Double(sleeper) / 22 + phase).truncatingRemainder(dividingBy: 1)
                let depth = t * t
                let y = horizon + (size.height - horizon) * depth
                let half = 4 + (size.width * 0.31 - 4) * CGFloat(depth)
                var path = Path()
                path.move(to: CGPoint(x: centerX - half, y: y))
                path.addLine(to: CGPoint(x: centerX + half, y: y))
                context.stroke(path, with: .color(Color(red: 0.54, green: 0.48, blue: 0.36).opacity(0.65)), lineWidth: 1 + 4 * depth)
            }

            for side in [-1.0, 1.0] {
                var rail = Path()
                for point in 0...20 {
                    let t = Double(point) / 20
                    let x = centerX + CGFloat(side) * (3 + (size.width * 0.265 - 3) * CGFloat(t))
                    let y = horizon + (size.height - horizon) * t
                    if point == 0 { rail.move(to: CGPoint(x: x, y: y)) } else { rail.addLine(to: CGPoint(x: x, y: y)) }
                }
                context.stroke(rail, with: .color(Color(red: 0.75, green: 0.77, blue: 0.72)), lineWidth: 1.3)
            }

            // Simplified overhead wires and poles make the view read as a railway cab.
            for side in [-1.0, 1.0] {
                let x = centerX + side * size.width * 0.38
                var pole = Path()
                pole.move(to: CGPoint(x: x, y: horizon - 1))
                pole.addLine(to: CGPoint(x: x + side * 12, y: size.height * 0.91))
                context.stroke(pole, with: .color(Color.white.opacity(0.29)), lineWidth: 1.3)
                var wire = Path()
                wire.move(to: CGPoint(x: centerX - size.width * 0.42, y: horizon + 1))
                wire.addQuadCurve(to: CGPoint(x: centerX + size.width * 0.42, y: horizon + 1), control: CGPoint(x: centerX, y: horizon - 9))
                context.stroke(wire, with: .color(Color.white.opacity(0.28)), lineWidth: 0.8)
            }

            let inTunnel = route.condition(at: positionM).tunnelResistanceMultiplier > 1.2
            if inTunnel {
                var arch = Path()
                arch.addRoundedRect(in: CGRect(x: -size.width * 0.08, y: -size.height * 0.76, width: size.width * 1.16, height: size.height * 1.9), cornerSize: CGSize(width: size.width * 0.5, height: size.height * 0.5))
                context.stroke(arch, with: .color(Color.black.opacity(0.72)), lineWidth: max(18, size.width * 0.055))
                context.fill(Path(CGRect(origin: .zero, size: CGSize(width: size.width, height: 8))), with: .color(.black.opacity(0.25)))
            }

            let glow = CGRect(x: centerX - 2, y: horizon - 2, width: 4, height: 4)
            context.fill(Path(ellipseIn: glow), with: .color(Color.white.opacity(0.8)))
        }
        .overlay(alignment: .topTrailing) {
            HStack(spacing: 5) {
                Image(systemName: "location.fill")
                Text("\(max(0, Int(modelTargetDistance)) ) m")
            }
            .font(.system(size: 10, weight: .black, design: .rounded).monospacedDigit())
            .foregroundStyle(.white)
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(.black.opacity(0.38), in: Capsule())
            .padding(8)
        }
        .overlay(alignment: .bottomTrailing) {
            if speedKmh > 0.5 {
                HStack(spacing: 4) {
                    Image(systemName: "speedometer")
                    Text(String(format: "%.0f km/h", speedKmh))
                }
                .font(.system(size: 9, weight: .bold, design: .rounded).monospacedDigit())
                .foregroundStyle(.white.opacity(0.86))
                .padding(8)
            }
        }
    }

    private var modelTargetDistance: Double { route.stopMarkerM - positionM }
}
