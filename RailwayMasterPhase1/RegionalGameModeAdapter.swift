import Foundation
import RailwayGameModes
import RailwayTimetable

/// A host train value before it is projected into a PLACEHOLDER game-only identifier.
struct RegionalGameModeTrainState: Sendable {
    let id: String
    let routeID: String
    let trackID: String
    let positionM: Double
    let speedMps: Double
}

/// Actual timetable event times relative to the selected trip's simulated route-origin departure.
struct RegionalGameModeTimetableEvent: Sendable {
    let arrivalSeconds: Double
    let departureSeconds: Double?
}

/// Immutable host inputs needed to build game-only scenarios. IDs in this type remain native;
/// the adapter prefixes every scenario-only identifier before passing it to RailwayGameModes.
struct RegionalGameModeContext {
    let routeID: String
    let route: RailwayRouteProfile
    let stops: [RegionalRouteStop]
    /// The selected route variant, when the host knows it. Used
    /// only for validity rules whose expectation differs by
    /// variant (the depot yard zone in validOrderedStops).
    let variant: RegionalRouteVariant?
    /// batch74 follow-up: the prepared front stop target at the
    /// run origin (StopScoringRouteAdapter's originTargetM). The
    /// origin stop plan carries this position so the game layer
    /// works entirely in the physics route frame: the snapshot
    /// position is the raw leading-end chainage, every stop plan
    /// is a front stop target, and the full-line origin check
    /// anchors on this value instead of ~0.
    let originTargetM: Double
    let timetableByStationID: [String: RegionalGameModeTimetableEvent]
    let trains: [RegionalGameModeTrainState]
    let availableTrainingPromptIDs: Set<String>

    init(
        routeID: String,
        route: RailwayRouteProfile,
        stops: [RegionalRouteStop],
        variant: RegionalRouteVariant? = nil,
        originTargetM: Double = 0,
        timetableByStationID: [String: RegionalGameModeTimetableEvent] = [:],
        trains: [RegionalGameModeTrainState] = [],
        availableTrainingPromptIDs: Set<String> = []
    ) {
        self.routeID = routeID
        self.route = route
        self.stops = stops
        self.variant = variant
        self.originTargetM = originTargetM
        self.timetableByStationID = timetableByStationID
        self.trains = trains
        self.availableTrainingPromptIDs = availableTrainingPromptIDs
    }

    /// Converts the selected canonical timetable to elapsed seconds from its actual simulated origin.
    /// Missing or pass-through native events are deliberately omitted, not synthesized.
    static func timetableEvents(
        from selection: RegionalTimetableSelection?,
        activeStops: [RegionalRouteStop]
    ) -> [String: RegionalGameModeTimetableEvent] {
        guard let selection,
              let origin = selection.simulatedTrip.stationEvents.first(where: {
                  $0.stationID == selection.routeOriginStationID
              }) else { return [:] }
        var result: [String: RegionalGameModeTimetableEvent] = [:]
        for stop in activeStops where stop.stationID != selection.routeOriginStationID {
            guard let event = selection.simulatedTrip.stationEvents.first(where: {
                $0.stationID == stop.stationID && $0.kind == .stop
            }) else { continue }
            let arrival = Double(event.arrivalSeconds - origin.departureSeconds)
            let departure = Double(event.departureSeconds - origin.departureSeconds)
            guard arrival >= 0, departure >= arrival else { continue }
            result[stop.stationID] = RegionalGameModeTimetableEvent(
                arrivalSeconds: arrival,
                departureSeconds: departure
            )
        }
        return result
    }
}

struct RegionalGameModeScenarioBuildResult {
    let scenario: GameModeScenario?
    let blockingReason: GameModeBlockingReason?
    let blockingMessages: [String]

    var isPlayable: Bool { scenario != nil && blockingMessages.isEmpty && blockingReason == nil }
}

enum RegionalGameModeAdapter {
    private static let announcementID = "PLACEHOLDER-cabin-announcement-arrival"
    private static let signalPromptID = "PLACEHOLDER-training-signal-display"
    private static let protectionPromptID = "PLACEHOLDER-training-protection-display"

    static func gameStationID(for nativeStationID: String, in stops: [RegionalRouteStop]) -> String? {
        guard let index = stops.firstIndex(where: { $0.stationID == nativeStationID }) else { return nil }
        return "PLACEHOLDER-stop-\(String(format: "%03d", index + 1))-\(nativeStationID)"
    }

    /// Makes a read-only mode snapshot from one coherent host physics sample. Doors, station events,
    /// visible landmarks, and prompts are explicit host inputs; unknown values remain unknown/nil.
    static func makeSimulationSnapshot(
        context: RegionalGameModeContext,
        telemetry: TrainTelemetry,
        simulationTimeSeconds: Double,
        fixedTick: UInt64,
        speedLimitKmh: Double,
        doors: GameModeDoorState,
        nativeStationID: String? = nil,
        stationEvent: GameModeStationEvent? = nil,
        visibleLandmarkID: String? = nil,
        trainingPromptID: String? = nil,
        vehicleID: String? = nil,
        weather: WeatherCondition? = nil,
        timeOfDayID: String? = nil,
        seasonID: String? = nil,
        trains: [RegionalGameModeTrainState]? = nil
    ) throws -> GameModeSimulationSnapshot {
        let hostTrains = trains ?? context.trains
        let mappedStationID = nativeStationID.flatMap { gameStationID(for: $0, in: context.stops) }
        let gameTrains = makeTrainSnapshots(routeID: context.routeID, trains: hostTrains)
        let gameWeatherID: String? = weather.map { "PLACEHOLDER-weather-\($0 == .dry ? "dry" : ($0 == .rain ? "rain" : "snow"))" }
        let gameVehicleID = vehicleID.map { "PLACEHOLDER-vehicle-\($0)" }
        let gameTimeID = timeOfDayID.map { "PLACEHOLDER-time-\($0)" }
        let gameSeasonID = seasonID.map { "PLACEHOLDER-season-\($0)" }
        return try GameModeSimulationSnapshot(
            simulationTimeSeconds: simulationTimeSeconds,
            fixedTick: fixedTick,
            routeID: context.routeID,
            routeLengthM: context.route.distanceM,
            positionM: telemetry.positionM,
            speedMps: telemetry.speedMps,
            accelerationMps2: telemetry.accelerationMps2,
            speedLimitKmh: speedLimitKmh,
            atStationID: mappedStationID,
            stationEvent: stationEvent,
            doors: doors,
            visibleLandmarkID: visibleLandmarkID,
            vehicleID: gameVehicleID,
            weatherID: gameWeatherID,
            timeOfDayID: gameTimeID,
            seasonID: gameSeasonID,
            passengerLoadFactor: telemetry.passengerLoadFactor,
            trainingPromptID: trainingPromptID,
            trains: gameTrains
        )
    }

    /// A convenience for hosts whose authoritative clock advances by the package's fixed 120 Hz step.
    static func fixedTick(for simulationTimeSeconds: Double) -> UInt64 {
        guard simulationTimeSeconds.isFinite, simulationTimeSeconds > 0 else { return 0 }
        return UInt64((simulationTimeSeconds * 120).rounded())
    }

    static func build(
        mode: GameModeID,
        playStyle: GameModePlayStyle,
        context: RegionalGameModeContext,
        snapshot: GameModeSimulationSnapshot
    ) -> RegionalGameModeScenarioBuildResult {
        var blockers: [String] = []
        var packageBlock: GameModeBlockingReason?

        guard !context.routeID.isEmpty, context.route.distanceM.isFinite, context.route.distanceM > 0,
              snapshot.routeID == context.routeID,
              abs(snapshot.routeLengthM - context.route.distanceM) <= 0.1 else {
            return RegionalGameModeScenarioBuildResult(
                scenario: nil, blockingReason: nil,
                blockingMessages: ["現在の架空ホスト路線ID/路線長とスナップショットが一致しません。"]
            )
        }
        guard playStyle != .freeRun || mode == .free,
              playStyle != .disruptionTraining || mode == .disruption else {
            return RegionalGameModeScenarioBuildResult(
                scenario: nil, blockingReason: nil,
                blockingMessages: ["このプレイスタイルは対応するフリー/異常対応モードでのみ使えます。"]
            )
        }
        guard validOrderedStops(context.stops, routeLengthM: context.route.distanceM, variant: context.variant, originTargetM: context.originTargetM) else {
            return RegionalGameModeScenarioBuildResult(
                scenario: nil, blockingReason: .missingStops,
                blockingMessages: ["現在の路線に有効な始発・順序付き停車駅データがありません。"]
            )
        }
        // batch103: the depot transfer's yard is a single zone.
        // StopScoringRouteAdapter bounds every depot stop by the
        // whole 2 km spur and centres both the origin placement
        // target and the final stop's target on that one zone, so
        // the origin stop plan and the final stop plan sit at
        // exactly the position the consist is placed at on reset
        // (originTargetM == the final stop's adjusted position).
        // The driver and full-line modes judge a run purely by
        // stop visits and the service-end position, so on this
        // variant both would certify a run that never moved: the
        // only required stop is recorded as visited from the
        // start position and every finish gate is already met.
        // Intermediate targets cannot fix this from the adapter:
        // the host reports station IDs only for activeStops
        // entries (SimulatorModel's target-stop tracking and
        // landmark visibility both key off that list), so a plan
        // invented here could never be visited and would make
        // the session unfinishable; and the depot route data
        // itself has no intermediate stops or yard-feature
        // chainages to project (the plan carries only the depot
        // station and the 2 km spur length). The scored-run
        // modes are therefore honestly unavailable on this
        // variant instead of presenting one co-located target
        // as a scored run. The guard keys on the co-location
        // itself, so it lifts on its own if a future depot
        // layout ever gives the origin a distinct target.
        // Conductor mode stays available: its scored content is
        // the door procedure performed at the yard target, not
        // travel between targets.
        // batch116: StopScoringRouteAdapter now splits the
        // depot zones (origin [0, 200], terminal [1,800,
        // 2,000]), so the prepared origin target and the final
        // stop's target no longer coincide and this guard no
        // longer fires for the standard depot layout — driver
        // and full-line runs on the spur are scored like any
        // other two-target route. The guard stays as a safety
        // net: it keys purely on co-location, so any future
        // layout that collapses the two targets again is
        // refused here instead of certifying a run that never
        // moved.
        if context.variant == .depotTransfer,
           let finalStop = context.stops.last,
           abs(context.originTargetM - finalStop.positionM) <= 0.1,
           mode == .driver || mode == .fullLine {
            return RegionalGameModeScenarioBuildResult(
                scenario: nil, blockingReason: nil,
                blockingMessages: ["車庫入出庫はヤード全体が単一ゾーンで、始発目標と終着目標が同じ地点に重なるため、停車位置で判定する運転士・全線モードでは走行を判定できません。"]
            )
        }

        let nativeStops = context.stops
        let requiredNativeStops = nativeStops.filter { $0.positionM > 0.1 }
        let hasTimetable = !requiredNativeStops.isEmpty && requiredNativeStops.allSatisfy { stop in
            guard let event = context.timetableByStationID[stop.stationID] else { return false }
            return event.arrivalSeconds.isFinite && event.arrivalSeconds >= 0 &&
                (event.departureSeconds.map { $0.isFinite && $0 >= event.arrivalSeconds } ?? true)
        }

        switch mode {
        case .driver:
            if requiredNativeStops.isEmpty {
                blockers.append("運転士モードには始発以外の実停車駅が必要です。")
                packageBlock = .missingStops
            }
        case .timetable:
            if !hasTimetable {
                blockers.append("ダイヤモードは選択中の架空正本ダイヤに全停車駅の実イベント時刻が必要です。")
                packageBlock = .missingStops
            }
        case .free:
            break
        case .conductor:
            if requiredNativeStops.isEmpty {
                blockers.append("車掌モードには始発以外の実停車駅が必要です。")
                packageBlock = .missingStops
            }
            if snapshot.doors == .unknown {
                blockers.append("ホストから明示的な初期ドア状態が供給されていません。")
                packageBlock = .unknownInitialDoorState
            }
        case .disruption:
            break
        case .training:
            let needed: Set<String> = [signalPromptID, protectionPromptID]
            guard needed.isSubset(of: context.availableTrainingPromptIDs) else {
                return RegionalGameModeScenarioBuildResult(
                    scenario: nil, blockingReason: .missingTrainingSteps,
                    blockingMessages: ["教習は架空の信号/保護表示プロンプトをホストが実際に供給できる場合のみ開始できます。"]
                )
            }
        case .fullLine:
            if requiredNativeStops.isEmpty {
                blockers.append("全線モードには始発以外の実停車駅が必要です。")
                packageBlock = .missingStops
            } else if snapshot.positionM > context.originTargetM + 0.1 {
                blockers.append("全線モードは現在の路線始発の停車位置からのみ開始できます。")
                packageBlock = .mustStartAtRouteOrigin
            }
        case .tourism:
            if nativeStops.dropFirst().dropLast().count < 2 {
                blockers.append("観光モードには路線内の異なる2つ以上の中間停車地点が必要です。")
                packageBlock = .missingLandmarks
            }
        case .companyOperations:
            let presentTrains = makeTrainSnapshots(routeID: context.routeID, trains: context.trains)
                .filter { $0.routeID == context.routeID }
            if presentTrains.count < 2 {
                blockers.append("会社運行にはホストから同一路線上の2編成以上のライブ状態が必要です。")
                packageBlock = .missingTrainSnapshots
            }
            if !hasTimetable {
                blockers.append("会社運行の期限枠には選択中の架空正本ダイヤが必要です。")
                packageBlock = .missingDispatchPlan
            }
        }

        guard mode == .free || mode == .disruption || !requiredNativeStops.isEmpty else {
            return RegionalGameModeScenarioBuildResult(scenario: nil, blockingReason: packageBlock, blockingMessages: blockers)
        }
        if mode == .timetable && !hasTimetable {
            return RegionalGameModeScenarioBuildResult(scenario: nil, blockingReason: packageBlock, blockingMessages: blockers)
        }
        if mode == .companyOperations && (context.trains.filter { $0.routeID == context.routeID }.count < 2 || !hasTimetable) {
            return RegionalGameModeScenarioBuildResult(scenario: nil, blockingReason: packageBlock, blockingMessages: blockers)
        }
        if mode == .tourism && nativeStops.dropFirst().dropLast().count < 2 {
            return RegionalGameModeScenarioBuildResult(scenario: nil, blockingReason: .missingLandmarks, blockingMessages: blockers)
        }

        do {
            let plans = try makeStopPlans(context: context, useActualTimetable: mode == .timetable || mode == .companyOperations)
            let landmarks: [GameModeLandmarkPlan] = mode == .tourism
                ? nativeStops.dropFirst().dropLast().prefix(2).enumerated().map { index, stop in
                    GameModeLandmarkPlan(
                        id: "PLACEHOLDER-landmark-\(String(format: "%02d", index + 1))",
                        displayName: "PLACEHOLDER・架空景観ポイント \(index + 1)",
                        positionM: stop.positionM,
                        observationRadiusM: 120,
                        maximumObservationSpeedMps: 12
                    )
                } : []
            let trainingSteps = mode == .training ? [
                GameModeTrainingStep(id: "PLACEHOLDER-training-stop-check", title: "PLACEHOLDER・停止状態の教材表示を確認", requirement: .stopped),
                GameModeTrainingStep(id: "PLACEHOLDER-training-signal-check", title: "PLACEHOLDER・架空信号表示プロンプトを確認", requirement: .promptVisible, requiredPromptID: signalPromptID),
                GameModeTrainingStep(id: "PLACEHOLDER-training-speed-check", title: "PLACEHOLDER・ゲーム内速度表示を確認", requirement: .withinCurrentSpeedLimit),
                GameModeTrainingStep(id: "PLACEHOLDER-training-station-check", title: "PLACEHOLDER・架空駅の停止表示を確認", requirement: .atStation),
                GameModeTrainingStep(id: "PLACEHOLDER-training-protection-check", title: "PLACEHOLDER・架空保護表示プロンプトを確認", requirement: .promptVisible, requiredPromptID: protectionPromptID)
            ] : []
            let incident = GameModeIncidentPlan(
                id: "PLACEHOLDER-incident-game-update",
                kind: .signalDisplayAnomaly,
                displayText: "PLACEHOLDER・架空ゲーム表示イベント。実在設備・実運転の状況を示しません。",
                triggerAfterSeconds: 30,
                responseDeadlineSeconds: 60,
                expectedChoice: .requestGameHint
            )
            let dispatch: (tasks: [GameModeDispatchTask], slots: [GameModeDispatchSlot]) = mode == .companyOperations
                ? makeDispatchPlan(context: context, routeDurationSeconds: max(1, plans.last?.scheduledArrivalSeconds ?? 1))
                : ([], [])
            let scenario = try GameModeScenario(
                routeID: context.routeID,
                routeLengthM: context.route.distanceM,
                stops: plans,
                driverDutyStepIDs: GameModeScenario.defaultDriverDutyStepIDs,
                driverDepartureCheckStepID: "PLACEHOLDER-departure-check",
                playStyle: playStyle,
                landmarks: landmarks,
                trainingSteps: trainingSteps,
                incident: incident,
                requiredAnnouncementIDs: [announcementID],
                dispatchTasks: dispatch.tasks,
                dispatchSlots: dispatch.slots,
                minimumTrainSeparationM: 300
            )
            return RegionalGameModeScenarioBuildResult(
                scenario: scenario,
                blockingReason: packageBlock,
                blockingMessages: blockers
            )
        } catch {
            return RegionalGameModeScenarioBuildResult(
                scenario: nil,
                blockingReason: nil,
                blockingMessages: ["架空ゲームシナリオを検証できませんでした: \(error.localizedDescription)"]
            )
        }
    }

    static func makeSession(
        mode: GameModeID,
        playStyle: GameModePlayStyle,
        context: RegionalGameModeContext,
        snapshot: GameModeSimulationSnapshot
    ) throws -> GameModeSession {
        let result = build(mode: mode, playStyle: playStyle, context: context, snapshot: snapshot)
        guard let scenario = result.scenario else {
            throw GameModeError.actionUnavailable(result.blockingMessages.joined(separator: " "))
        }
        // The package applies its authoritative blocked status (including unknown door state and
        // non-origin full-line starts); the UI must not convert that state into ready/playable.
        return try GameModeSession(mode: mode, snapshot: snapshot, scenario: scenario)
    }

    static func makeTrainSnapshots(
        routeID: String,
        trains: [RegionalGameModeTrainState]
    ) -> [GameModeTrainSnapshot] {
        let valid = trains.filter {
            !$0.id.isEmpty && !$0.routeID.isEmpty && !$0.trackID.isEmpty &&
            $0.positionM.isFinite && $0.positionM >= 0 && $0.speedMps.isFinite && $0.speedMps >= 0
        }.sorted { $0.id < $1.id }
        let trackIDs = Array(Set(valid.map(\.trackID))).sorted()
        let gameTrackID = Dictionary(uniqueKeysWithValues: trackIDs.enumerated().map {
            ($0.element, "PLACEHOLDER-track-\(String(format: "%02d", $0.offset + 1))")
        })
        return valid.enumerated().compactMap { index, train in
            guard let gameTrack = gameTrackID[train.trackID] else { return nil }
            return try? GameModeTrainSnapshot(
                id: "PLACEHOLDER-train-\(String(format: "%02d", index + 1))",
                routeID: train.routeID == routeID ? routeID : "PLACEHOLDER-other-route-\(train.routeID)",
                trackID: gameTrack,
                positionM: train.positionM,
                speedMps: train.speedMps
            )
        }
    }

    private static func validOrderedStops(_ stops: [RegionalRouteStop], routeLengthM: Double, variant: RegionalRouteVariant?, originTargetM: Double) -> Bool {
        // The first stop in a prepared list is the origin stop
        // TARGET, not the raw station position: batch112 made
        // StopScoringRouteAdapter mirror originTargetM into
        // index 0 (makeStopPlans below has always substituted
        // it for the origin plan on the same reasoning), so the
        // validity anchor for the first stop is the prepared
        // origin target itself. (Before batch116 this clause
        // demanded ~0, which no prepared list satisfied any
        // more; the depot's split zones give it a 178 m origin
        // target, so the depot needs the anchored form too.)
        guard stops.count >= 2,
              abs(stops[0].positionM - originTargetM) <= 0.1 else { return false }
        // Follow-up to batch71: the final stop in the prepared
        // stop list is the terminal stop TARGET, not the route
        // end itself. StopScoringRouteAdapter places the front
        // at platformEnd − platformEndMarginM at the terminal
        // like every other stop (batch43's restoration of the
        // terminal position to exactly routeLengthM was
        // superseded, and GameModeSession.finish now gates on
        // the final stop's position via serviceEndPositionM).
        // The terminal platform end coincides with the route
        // end on every passenger variant, so the legitimate
        // shortfall is exactly that margin; a larger shortfall
        // means the stop list does not reach the terminal.
        // The depot transfer's terminal target is centred in
        // its own 200 m end zone (batch116; it used to be
        // centred in the whole 2 km spur, ~900 m short, and
        // the shortfall test was skipped there entirely
        // because it carried no signal). A centred target's
        // shortfall is half the zone minus half the consist,
        // bounded by half the zone length, so the depot gets
        // that bound instead of the passenger margin: the
        // test carries a validity signal again — a collapsed
        // or misplaced depot target fails here — while the
        // ordering and range checks below apply as before.
        let terminalShortfallM = routeLengthM - stops[stops.count - 1].positionM
        let maximumShortfallM = variant == .depotTransfer
            ? StopScoringRouteAdapter.depotZoneLengthM / 2 + 0.1
            : StopScoringRouteAdapter.platformEndMarginM + 0.1
        guard terminalShortfallM >= -0.1,
              terminalShortfallM <= maximumShortfallM else { return false }
        for index in stops.indices {
            let stop = stops[index]
            guard !stop.stationID.isEmpty, stop.positionM.isFinite,
                  stop.positionM >= 0, stop.positionM <= routeLengthM,
                  index == 0 || stop.positionM > stops[index - 1].positionM else { return false }
        }
        return true
    }

    private static func makeStopPlans(
        context: RegionalGameModeContext,
        useActualTimetable: Bool
    ) throws -> [GameModeStopPlan] {
        let duration = max(120, context.route.distanceM / 15.0)
        return try context.stops.enumerated().map { index, stop in
            let schedule: RegionalGameModeTimetableEvent?
            if index == 0 {
                schedule = RegionalGameModeTimetableEvent(arrivalSeconds: 0, departureSeconds: 0)
            } else if useActualTimetable {
                schedule = context.timetableByStationID[stop.stationID]
            } else {
                let arrival = duration * stop.positionM / context.route.distanceM
                schedule = RegionalGameModeTimetableEvent(
                    arrivalSeconds: arrival,
                    departureSeconds: index == context.stops.count - 1 ? nil : arrival + 20
                )
            }
            guard let schedule,
                  schedule.arrivalSeconds.isFinite, schedule.arrivalSeconds >= 0,
                  schedule.departureSeconds.map({ $0.isFinite && $0 >= schedule.arrivalSeconds }) ?? true else {
                throw GameModeError.invalidValue("missing or invalid host timetable event at \(stop.stationID)")
            }
            let gameID = "PLACEHOLDER-stop-\(String(format: "%03d", index + 1))-\(stop.stationID)"
            return GameModeStopPlan(
                id: gameID,
                stationNameAnnouncementID: index == 0 ? nil : "PLACEHOLDER-station-announcement-\(String(format: "%03d", index + 1))",
                // Every stop plan position is the front stop
                // target in the physics route frame. The origin
                // stop's context position is the station's raw
                // route position (0), which is not where the
                // consist front stands; the origin plan carries
                // the prepared origin target instead, anchoring
                // GameModeSession's full-line origin check. The
                // origin is excluded from the required stops by
                // list position (first), not by being ~0.
                positionM: index == 0 ? context.originTargetM : stop.positionM,
                scheduledArrivalSeconds: schedule.arrivalSeconds,
                scheduledDepartureSeconds: schedule.departureSeconds,
                expectedPlatformSide: DoorProcedureScoringRouteAdapter.gameModePlatformSide(routeID: context.routeID, stationID: stop.stationID)
                    ?? (index.isMultiple(of: 2) ? .left : .right),
                arrivalToleranceSeconds: 30
            )
        }
    }

    private static func makeDispatchPlan(
        context: RegionalGameModeContext,
        routeDurationSeconds: Double
    ) -> (tasks: [GameModeDispatchTask], slots: [GameModeDispatchSlot]) {
        let slots = [
            GameModeDispatchSlot(id: "PLACEHOLDER-dispatch-slot-a", trackID: "PLACEHOLDER-dispatch-track-a", startTimeSeconds: 0, endTimeSeconds: routeDurationSeconds),
            GameModeDispatchSlot(id: "PLACEHOLDER-dispatch-slot-b", trackID: "PLACEHOLDER-dispatch-track-b", startTimeSeconds: 0, endTimeSeconds: routeDurationSeconds)
        ]
        let normalizedTrains = makeTrainSnapshots(routeID: context.routeID, trains: context.trains)
            .filter { $0.routeID == context.routeID }
        let tasks = normalizedTrains.enumerated().map { index, train in
            GameModeDispatchTask(
                id: "PLACEHOLDER-dispatch-task-\(String(format: "%02d", index + 1))",
                trainID: train.id,
                deadlineSeconds: routeDurationSeconds,
                allowedSlotIDs: slots.map(\.id)
            )
        }
        return (tasks, slots)
    }
}
