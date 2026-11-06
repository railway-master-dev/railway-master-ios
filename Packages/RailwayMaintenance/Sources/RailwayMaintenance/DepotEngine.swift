import Foundation

/// Fictional depot and vehicle state machine. It models game availability, not railway procedures.
public struct DepotOperationEngine: Sendable {
    public private(set) var state: DepotOperationState
    public let stoppedSpeedThresholdMps: Double
    public let accessToleranceM: Double

    public init(
        depots: [DepotDefinition],
        vehicles: [MaintenanceVehicleRecord],
        stoppedSpeedThresholdMps: Double = 0.1,
        accessToleranceM: Double = 5
    ) {
        self.state = DepotOperationState(depots: depots, vehicles: vehicles)
        self.stoppedSpeedThresholdMps = stoppedSpeedThresholdMps
        self.accessToleranceM = accessToleranceM
    }

    public init(
        restoring state: DepotOperationState,
        stoppedSpeedThresholdMps: Double = 0.1,
        accessToleranceM: Double = 5
    ) {
        self.state = state
        self.stoppedSpeedThresholdMps = stoppedSpeedThresholdMps
        self.accessToleranceM = accessToleranceM
    }

    /// Apply a player/dispatcher game action. Entry additionally requires the host's stopped train snapshot.
    @discardableResult
    public mutating func handle(
        _ command: DepotCommand,
        at time: Double,
        snapshot: MaintenanceSimulationSnapshot? = nil
    ) throws -> DepotOperationEvent {
        try validate(time: time)
        switch command {
        case .recordScenarioFault(let vehicleID, let eventInstanceID):
            return try recordScenarioFault(vehicleID: vehicleID, eventInstanceID: eventInstanceID, at: time)
        case .requestEntry(let vehicleID, let depotID, let depotTrackID):
            return try requestEntry(vehicleID: vehicleID, depotID: depotID, depotTrackID: depotTrackID, at: time, snapshot: snapshot)
        case .allocate(let vehicleID, let serviceID):
            return try allocate(vehicleID: vehicleID, serviceID: serviceID, at: time)
        case .releaseAllocation(let vehicleID):
            return try releaseAllocation(vehicleID: vehicleID, at: time)
        case .requestExit(let vehicleID, let serviceID):
            return try requestExit(vehicleID: vehicleID, serviceID: serviceID, at: time)
        case .beginInspection(let vehicleID, let kind, let durationSeconds):
            return try beginInspection(vehicleID: vehicleID, kind: kind, durationSeconds: durationSeconds, at: time)
        case .submitInspectionResult(let inspectionID, let result):
            return try submitInspectionResult(inspectionID: inspectionID, result: result, at: time)
        case .scheduleMaintenance(let vehicleID, let kind, let durationSeconds, let requiresReinspection):
            return try scheduleMaintenance(vehicleID: vehicleID, kind: kind, durationSeconds: durationSeconds, requiresReinspection: requiresReinspection, at: time)
        case .beginMaintenance(let taskID):
            return try beginMaintenance(taskID: taskID, at: time)
        case .cancelMaintenance(let taskID):
            return try cancelMaintenance(taskID: taskID, at: time)
        }
    }

    /// Completes elapsed depot transfers, inspections and maintenance tasks at the simulation time.
    public mutating func advance(to time: Double) -> [DepotOperationEvent] {
        guard time.isFinite, time >= 0, validTuning else { return [] }
        var events: [DepotOperationEvent] = []

        for index in state.movements.indices where state.movements[index].status == .inProgress {
            guard time >= state.movements[index].completesAtSeconds else { continue }
            let movement = state.movements[index]
            state.movements[index].status = .completed
            state.movements[index].completedAtSeconds = time
            guard let vehicleIndex = state.vehicles.firstIndex(where: { $0.id == movement.vehicleID }) else { continue }
            switch movement.kind {
            case .entry:
                state.vehicles[vehicleIndex].location = .inDepot(depotID: movement.depotID, trackID: movement.depotTrackID)
                state.vehicles[vehicleIndex].assignedServiceID = nil
                if !state.vehicles[vehicleIndex].activeScenarioFaultEventIDs.isEmpty {
                    state.vehicles[vehicleIndex].inspectionClearance = .repairRequired
                }
                recomputeVehicleState(at: vehicleIndex)
            case .exit:
                guard let depot = state.depots.first(where: { $0.id == movement.depotID }) else { continue }
                state.vehicles[vehicleIndex].location = .onRoute(trackID: depot.accessTrackID, chainageM: depot.accessChainageM)
                state.vehicles[vehicleIndex].operationalState = .inService
                state.vehicles[vehicleIndex].assignedServiceID = movement.serviceID
            }
            events.append(makeEvent(
                kind: .movementCompleted,
                vehicleID: movement.vehicleID,
                referenceID: movement.id,
                at: time
            ))
        }

        for index in state.inspections.indices where state.inspections[index].status == .inProgress {
            guard time >= state.inspections[index].reviewReadyAtSeconds else { continue }
            let inspection = state.inspections[index]
            state.inspections[index].status = .awaitingResult
            if let vehicleIndex = state.vehicles.firstIndex(where: { $0.id == inspection.vehicleID }) {
                state.vehicles[vehicleIndex].operationalState = .inspectionAwaitingReview
            }
            events.append(makeEvent(
                kind: .inspectionReadyForReview,
                vehicleID: inspection.vehicleID,
                referenceID: inspection.id,
                at: time
            ))
        }

        for index in state.maintenanceTasks.indices where state.maintenanceTasks[index].status == .inProgress {
            guard let due = state.maintenanceTasks[index].completesAtSeconds, time >= due else { continue }
            state.maintenanceTasks[index].status = .completed
            state.maintenanceTasks[index].completedAtSeconds = time
            let task = state.maintenanceTasks[index]
            if let vehicleIndex = state.vehicles.firstIndex(where: { $0.id == task.vehicleID }) {
                if task.kind == .correctiveScenarioRepair {
                    state.vehicles[vehicleIndex].activeScenarioFaultEventIDs.removeAll()
                }
                if task.requiresReinspection || task.kind == .correctiveScenarioRepair {
                    state.vehicles[vehicleIndex].inspectionClearance = .reinspectionRequired
                }
                recomputeVehicleState(at: vehicleIndex)
            }
            events.append(makeEvent(
                kind: .maintenanceCompleted,
                vehicleID: task.vehicleID,
                referenceID: task.id,
                at: time
            ))
        }
        return events
    }

    public func configurationIssues() -> [String] {
        var issues: [String] = []
        if !stoppedSpeedThresholdMps.isFinite || stoppedSpeedThresholdMps < 0 {
            issues.append("停止判定速度のゲーム設定が不正です。")
        }
        if !accessToleranceM.isFinite || accessToleranceM < 0 {
            issues.append("車庫アクセス許容距離のゲーム設定が不正です。")
        }
        let depotIDs = state.depots.map(\.id)
        if depotIDs.contains(where: \.isEmpty) || Set(depotIDs).count != depotIDs.count {
            issues.append("車庫IDが空または重複しています。")
        }
        let vehicleIDs = state.vehicles.map(\.id)
        if vehicleIDs.contains(where: \.isEmpty) || Set(vehicleIDs).count != vehicleIDs.count {
            issues.append("車両IDが空または重複しています。")
        }
        for depot in state.depots {
            if depot.routeID.isEmpty || depot.accessTrackID.isEmpty || !depot.accessChainageM.isFinite || depot.accessChainageM < 0 ||
                !depot.entryTransferDurationSeconds.isFinite || depot.entryTransferDurationSeconds < 0 ||
                !depot.exitTransferDurationSeconds.isFinite || depot.exitTransferDurationSeconds < 0 {
                issues.append("車庫 \(depot.id) の位置または移動時間設定が不正です。")
            }
            let trackIDs = depot.tracks.map(\.id)
            if trackIDs.isEmpty || trackIDs.contains(where: \.isEmpty) || Set(trackIDs).count != trackIDs.count ||
                depot.tracks.contains(where: { $0.capacity <= 0 }) {
                issues.append("車庫 \(depot.id) の留置線ID・収容数が不正です。")
            }
        }
        for vehicle in state.vehicles where vehicle.id.isEmpty || vehicle.profileID.isEmpty || !vehicle.lengthM.isFinite || vehicle.lengthM <= 0 {
            issues.append("車両レコードのID、仮想形式ID、編成長が不正です。")
        }
        return issues
    }

    private var validTuning: Bool {
        stoppedSpeedThresholdMps.isFinite && stoppedSpeedThresholdMps >= 0 && accessToleranceM.isFinite && accessToleranceM >= 0
    }

    private mutating func validate(time: Double) throws {
        guard time.isFinite && time >= 0 else { throw DepotOperationError.invalidTime }
        if let issue = configurationIssues().first { throw DepotOperationError.invalidConfiguration(issue) }
    }

    private mutating func requestEntry(
        vehicleID: String,
        depotID: String,
        depotTrackID: String,
        at time: Double,
        snapshot: MaintenanceSimulationSnapshot?
    ) throws -> DepotOperationEvent {
        guard let vehicleIndex = state.vehicles.firstIndex(where: { $0.id == vehicleID }) else {
            throw DepotOperationError.unknownVehicle(vehicleID)
        }
        guard let depotIndex = state.depots.firstIndex(where: { $0.id == depotID }) else {
            throw DepotOperationError.unknownDepot(depotID)
        }
        let depot = state.depots[depotIndex]
        guard let yardTrack = depot.track(id: depotTrackID) else {
            throw DepotOperationError.unknownDepotTrack(depotTrackID)
        }
        let vehicle = state.vehicles[vehicleIndex]
        guard case .onRoute = vehicle.location, vehicle.operationalState == .inService else {
            throw DepotOperationError.invalidTransition("車庫への入場を開始できる車両状態ではありません。")
        }
        guard let snapshot else { throw DepotOperationError.hostTrainStateRequired }
        guard snapshot.routeID == depot.routeID,
              let train = snapshot.train(id: vehicleID),
              train.isInService,
              train.trackID == depot.accessTrackID,
              train.speedMps <= stoppedSpeedThresholdMps,
              abs(train.positionM - depot.accessChainageM) <= accessToleranceM else {
            throw DepotOperationError.vehicleNotAtDepotAccess
        }
        if !yardTrack.allowedVehicleProfileIDs.isEmpty && !yardTrack.allowedVehicleProfileIDs.contains(vehicle.profileID) {
            throw DepotOperationError.incompatibleVehicleProfile
        }
        let occupied = occupiedCount(depotID: depotID, depotTrackID: depotTrackID)
        guard occupied < yardTrack.capacity else { throw DepotOperationError.depotTrackFull(depotTrackID) }

        let movementID = nextID(prefix: "depot-move")
        state.movements.append(DepotMovement(
            id: movementID,
            kind: .entry,
            vehicleID: vehicleID,
            depotID: depotID,
            depotTrackID: depotTrackID,
            serviceID: nil,
            startedAtSeconds: time,
            completesAtSeconds: time + depot.entryTransferDurationSeconds
        ))
        state.vehicles[vehicleIndex].location = .inTransit(movementID: movementID)
        state.vehicles[vehicleIndex].operationalState = .transitToDepot
        return makeEvent(kind: .movementStarted, vehicleID: vehicleID, referenceID: movementID, at: time)
    }

    private mutating func recordScenarioFault(
        vehicleID: String,
        eventInstanceID: String,
        at time: Double
    ) throws -> DepotOperationEvent {
        guard !eventInstanceID.isEmpty else {
            throw DepotOperationError.invalidTransition("ゲーム内故障イベントIDが必要です。")
        }
        guard let index = state.vehicles.firstIndex(where: { $0.id == vehicleID }) else {
            throw DepotOperationError.unknownVehicle(vehicleID)
        }
        if !state.vehicles[index].activeScenarioFaultEventIDs.contains(eventInstanceID) {
            state.vehicles[index].activeScenarioFaultEventIDs.append(eventInstanceID)
        }
        if case .inDepot = state.vehicles[index].location {
            state.vehicles[index].assignedServiceID = nil
            state.vehicles[index].inspectionClearance = .repairRequired
            state.vehicles[index].operationalState = .repairHold
        }
        return makeEvent(kind: .scenarioFaultRecorded, vehicleID: vehicleID, referenceID: eventInstanceID, at: time)
    }

    private mutating func allocate(vehicleID: String, serviceID: String, at time: Double) throws -> DepotOperationEvent {
        guard let index = state.vehicles.firstIndex(where: { $0.id == vehicleID }) else {
            throw DepotOperationError.unknownVehicle(vehicleID)
        }
        guard case .inDepot = state.vehicles[index].location,
              state.vehicles[index].operationalState == .ready,
              state.vehicles[index].inspectionClearance == .cleared,
              state.vehicles[index].activeScenarioFaultEventIDs.isEmpty,
              !hasOpenMaintenance(vehicleID: vehicleID),
              !serviceID.isEmpty else {
            throw DepotOperationError.inspectionRequired
        }
        state.vehicles[index].assignedServiceID = serviceID
        state.vehicles[index].operationalState = .allocated
        return makeEvent(kind: .vehicleAllocated, vehicleID: vehicleID, referenceID: serviceID, at: time)
    }

    private mutating func releaseAllocation(vehicleID: String, at time: Double) throws -> DepotOperationEvent {
        guard let index = state.vehicles.firstIndex(where: { $0.id == vehicleID }) else {
            throw DepotOperationError.unknownVehicle(vehicleID)
        }
        guard case .inDepot = state.vehicles[index].location,
              state.vehicles[index].operationalState == .allocated else {
            throw DepotOperationError.invalidTransition("割当解除は車庫内の割当済み車両に限られます。")
        }
        let serviceID = state.vehicles[index].assignedServiceID
        state.vehicles[index].assignedServiceID = nil
        state.vehicles[index].operationalState = .ready
        return makeEvent(kind: .allocationReleased, vehicleID: vehicleID, referenceID: serviceID, at: time)
    }

    private mutating func requestExit(vehicleID: String, serviceID: String, at time: Double) throws -> DepotOperationEvent {
        guard let vehicleIndex = state.vehicles.firstIndex(where: { $0.id == vehicleID }) else {
            throw DepotOperationError.unknownVehicle(vehicleID)
        }
        let vehicle = state.vehicles[vehicleIndex]
        guard case .inDepot(let depotID, let depotTrackID) = vehicle.location,
              vehicle.operationalState == .allocated,
              vehicle.assignedServiceID == serviceID,
              vehicle.inspectionClearance == .cleared,
              vehicle.activeScenarioFaultEventIDs.isEmpty,
              !hasOpenMaintenance(vehicleID: vehicleID) else {
            throw DepotOperationError.invalidTransition("出庫には、点検クリア済みで対象運用へ割当済みの車両が必要です。")
        }
        guard let depot = state.depots.first(where: { $0.id == depotID }), depot.track(id: depotTrackID) != nil else {
            throw DepotOperationError.unknownDepot(depotID)
        }
        let movementID = nextID(prefix: "depot-move")
        state.movements.append(DepotMovement(
            id: movementID,
            kind: .exit,
            vehicleID: vehicleID,
            depotID: depotID,
            depotTrackID: depotTrackID,
            serviceID: serviceID,
            startedAtSeconds: time,
            completesAtSeconds: time + depot.exitTransferDurationSeconds
        ))
        state.vehicles[vehicleIndex].location = .inTransit(movementID: movementID)
        state.vehicles[vehicleIndex].operationalState = .transitToService
        return makeEvent(kind: .movementStarted, vehicleID: vehicleID, referenceID: movementID, at: time)
    }

    private mutating func beginInspection(
        vehicleID: String,
        kind: InspectionKind,
        durationSeconds: Double,
        at time: Double
    ) throws -> DepotOperationEvent {
        guard durationSeconds.isFinite && durationSeconds >= 0 else { throw DepotOperationError.invalidTime }
        guard let vehicleIndex = state.vehicles.firstIndex(where: { $0.id == vehicleID }) else {
            throw DepotOperationError.unknownVehicle(vehicleID)
        }
        guard case .inDepot = state.vehicles[vehicleIndex].location,
              state.vehicles[vehicleIndex].assignedServiceID == nil,
              !state.inspections.contains(where: {
                  $0.vehicleID == vehicleID && ($0.status == .inProgress || $0.status == .awaitingResult)
              }),
              !state.maintenanceTasks.contains(where: { $0.vehicleID == vehicleID && $0.status == .inProgress }) else {
            throw DepotOperationError.invalidTransition("点検シナリオを開始できない車両状態です。")
        }
        let inspectionID = nextID(prefix: "inspection")
        state.inspections.append(VehicleInspectionRecord(
            id: inspectionID,
            vehicleID: vehicleID,
            kind: kind,
            startedAtSeconds: time,
            reviewReadyAtSeconds: time + durationSeconds
        ))
        state.vehicles[vehicleIndex].operationalState = .inspectionInProgress
        return makeEvent(kind: .inspectionStarted, vehicleID: vehicleID, referenceID: inspectionID, at: time)
    }

    private mutating func submitInspectionResult(
        inspectionID: String,
        result: InspectionResult,
        at time: Double
    ) throws -> DepotOperationEvent {
        guard let inspectionIndex = state.inspections.firstIndex(where: { $0.id == inspectionID }) else {
            throw DepotOperationError.unknownInspection(inspectionID)
        }
        guard state.inspections[inspectionIndex].status == .awaitingResult else {
            throw DepotOperationError.inspectionNotReady
        }
        let vehicleID = state.inspections[inspectionIndex].vehicleID
        guard let vehicleIndex = state.vehicles.firstIndex(where: { $0.id == vehicleID }) else {
            throw DepotOperationError.unknownVehicle(vehicleID)
        }
        switch result {
        case .passed(let findings):
            state.inspections[inspectionIndex].status = .passed
            state.vehicles[vehicleIndex].inspectionClearance = state.vehicles[vehicleIndex].activeScenarioFaultEventIDs.isEmpty ? .cleared : .repairRequired
            state.inspections[inspectionIndex].findings = findings
        case .repairRequired(let findings):
            state.inspections[inspectionIndex].status = .repairRequired
            state.vehicles[vehicleIndex].inspectionClearance = .repairRequired
            state.inspections[inspectionIndex].findings = findings
        case .heldOutOfService(let findings):
            state.inspections[inspectionIndex].status = .heldOutOfService
            state.vehicles[vehicleIndex].inspectionClearance = .heldOutOfService
            state.inspections[inspectionIndex].findings = findings
        }
        state.inspections[inspectionIndex].completedAtSeconds = time
        state.vehicles[vehicleIndex].lastInspectionAtSeconds = time
        recomputeVehicleState(at: vehicleIndex)
        return makeEvent(kind: .inspectionCompleted, vehicleID: vehicleID, referenceID: inspectionID, at: time)
    }

    private mutating func scheduleMaintenance(
        vehicleID: String,
        kind: GameplayMaintenanceTaskKind,
        durationSeconds: Double,
        requiresReinspection: Bool,
        at time: Double
    ) throws -> DepotOperationEvent {
        guard durationSeconds.isFinite && durationSeconds >= 0 else { throw DepotOperationError.invalidTime }
        guard let vehicleIndex = state.vehicles.firstIndex(where: { $0.id == vehicleID }) else {
            throw DepotOperationError.unknownVehicle(vehicleID)
        }
        guard case .inDepot = state.vehicles[vehicleIndex].location,
              state.vehicles[vehicleIndex].assignedServiceID == nil,
              state.vehicles[vehicleIndex].operationalState != .inspectionInProgress,
              state.vehicles[vehicleIndex].operationalState != .inspectionAwaitingReview else {
            throw DepotOperationError.invalidTransition("整備シナリオを登録できない車両状態です。")
        }
        let taskID = nextID(prefix: "maintenance")
        state.maintenanceTasks.append(GameplayMaintenanceTask(
            id: taskID,
            vehicleID: vehicleID,
            kind: kind,
            durationSeconds: durationSeconds,
            requiresReinspection: requiresReinspection
        ))
        recomputeVehicleState(at: vehicleIndex)
        return makeEvent(kind: .maintenanceScheduled, vehicleID: vehicleID, referenceID: taskID, at: time)
    }

    private mutating func beginMaintenance(taskID: String, at time: Double) throws -> DepotOperationEvent {
        guard let taskIndex = state.maintenanceTasks.firstIndex(where: { $0.id == taskID }) else {
            throw DepotOperationError.unknownMaintenanceTask(taskID)
        }
        guard state.maintenanceTasks[taskIndex].status == .planned else {
            throw DepotOperationError.invalidTransition("開始できる整備タスクではありません。")
        }
        let vehicleID = state.maintenanceTasks[taskIndex].vehicleID
        guard let vehicleIndex = state.vehicles.firstIndex(where: { $0.id == vehicleID }) else {
            throw DepotOperationError.unknownVehicle(vehicleID)
        }
        guard case .inDepot = state.vehicles[vehicleIndex].location,
              state.vehicles[vehicleIndex].assignedServiceID == nil else {
            throw DepotOperationError.invalidTransition("整備開始に適した車両状態ではありません。")
        }
        guard !state.inspections.contains(where: {
            $0.vehicleID == vehicleID && ($0.status == .inProgress || $0.status == .awaitingResult)
        }) else {
            throw DepotOperationError.activeInspection
        }
        guard !state.maintenanceTasks.contains(where: { $0.vehicleID == vehicleID && $0.status == .inProgress }) else {
            throw DepotOperationError.activeMaintenanceTask
        }
        state.maintenanceTasks[taskIndex].status = .inProgress
        state.maintenanceTasks[taskIndex].startedAtSeconds = time
        state.maintenanceTasks[taskIndex].completesAtSeconds = time + state.maintenanceTasks[taskIndex].durationSeconds
        state.vehicles[vehicleIndex].operationalState = .maintenanceInProgress
        return makeEvent(kind: .maintenanceStarted, vehicleID: vehicleID, referenceID: taskID, at: time)
    }

    private mutating func cancelMaintenance(taskID: String, at time: Double) throws -> DepotOperationEvent {
        guard let taskIndex = state.maintenanceTasks.firstIndex(where: { $0.id == taskID }) else {
            throw DepotOperationError.unknownMaintenanceTask(taskID)
        }
        guard state.maintenanceTasks[taskIndex].status == .planned else {
            throw DepotOperationError.invalidTransition("開始済みまたは完了済みの整備タスクは取り消せません。")
        }
        let vehicleID = state.maintenanceTasks[taskIndex].vehicleID
        state.maintenanceTasks[taskIndex].status = .cancelled
        if let vehicleIndex = state.vehicles.firstIndex(where: { $0.id == vehicleID }) {
            recomputeVehicleState(at: vehicleIndex)
        }
        return makeEvent(kind: .maintenanceCancelled, vehicleID: vehicleID, referenceID: taskID, at: time)
    }

    private func occupiedCount(depotID: String, depotTrackID: String) -> Int {
        let parked = state.vehicles.reduce(into: 0) { count, vehicle in
            if case .inDepot(let foundDepotID, let foundTrackID) = vehicle.location,
               foundDepotID == depotID && foundTrackID == depotTrackID {
                count += 1
            }
        }
        let inbound = state.movements.reduce(into: 0) { count, movement in
            if movement.kind == .entry && movement.status == .inProgress &&
                movement.depotID == depotID && movement.depotTrackID == depotTrackID {
                count += 1
            }
        }
        return parked + inbound
    }

    private func hasOpenMaintenance(vehicleID: String) -> Bool {
        state.maintenanceTasks.contains {
            $0.vehicleID == vehicleID && ($0.status == .planned || $0.status == .inProgress)
        }
    }

    private mutating func recomputeVehicleState(at index: Int) {
        guard index >= 0 && index < state.vehicles.count else { return }
        guard case .inDepot = state.vehicles[index].location else { return }
        let vehicleID = state.vehicles[index].id
        if state.inspections.contains(where: { $0.vehicleID == vehicleID && $0.status == .inProgress }) {
            state.vehicles[index].operationalState = .inspectionInProgress
            return
        }
        if state.inspections.contains(where: { $0.vehicleID == vehicleID && $0.status == .awaitingResult }) {
            state.vehicles[index].operationalState = .inspectionAwaitingReview
            return
        }
        if state.maintenanceTasks.contains(where: { $0.vehicleID == vehicleID && $0.status == .inProgress }) {
            state.vehicles[index].operationalState = .maintenanceInProgress
            return
        }
        if !state.vehicles[index].activeScenarioFaultEventIDs.isEmpty {
            state.vehicles[index].operationalState = .repairHold
            state.vehicles[index].inspectionClearance = .repairRequired
            return
        }
        switch state.vehicles[index].inspectionClearance {
        case .notInspected, .reinspectionRequired:
            state.vehicles[index].operationalState = .inspectionDue
        case .repairRequired:
            state.vehicles[index].operationalState = .repairHold
        case .heldOutOfService:
            state.vehicles[index].operationalState = .outOfService
        case .cleared:
            state.vehicles[index].operationalState = hasOpenMaintenance(vehicleID: vehicleID) ? .inDepot : .ready
        }
    }

    private mutating func nextID(prefix: String) -> String {
        let sequence = state.nextSequence
        state.nextSequence &+= 1
        return String(format: "%@-%06llu", prefix, sequence)
    }

    private mutating func makeEvent(
        kind: DepotOperationEventKind,
        vehicleID: String,
        referenceID: String?,
        at time: Double
    ) -> DepotOperationEvent {
        DepotOperationEvent(
            id: nextID(prefix: "depot-event"),
            kind: kind,
            vehicleID: vehicleID,
            referenceID: referenceID,
            simulationTimeSeconds: time
        )
    }
}
