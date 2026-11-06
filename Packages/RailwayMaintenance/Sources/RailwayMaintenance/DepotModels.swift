import Foundation

public struct DepotTrackDefinition: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let capacity: Int
    /// Empty means any fictional vehicle profile is accepted.
    public let allowedVehicleProfileIDs: [String]

    public init(id: String, capacity: Int, allowedVehicleProfileIDs: [String] = []) {
        self.id = id
        self.capacity = capacity
        self.allowedVehicleProfileIDs = allowedVehicleProfileIDs
    }
}

/// Fictional game depot data. Access locations and transfer times are authored scenario values.
public struct DepotDefinition: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let routeID: String
    public let accessTrackID: String
    public let accessChainageM: Double
    public let entryTransferDurationSeconds: Double
    public let exitTransferDurationSeconds: Double
    public let tracks: [DepotTrackDefinition]

    public init(
        id: String,
        routeID: String,
        accessTrackID: String,
        accessChainageM: Double,
        entryTransferDurationSeconds: Double = 20,
        exitTransferDurationSeconds: Double = 20,
        tracks: [DepotTrackDefinition]
    ) {
        self.id = id
        self.routeID = routeID
        self.accessTrackID = accessTrackID
        self.accessChainageM = accessChainageM
        self.entryTransferDurationSeconds = entryTransferDurationSeconds
        self.exitTransferDurationSeconds = exitTransferDurationSeconds
        self.tracks = tracks
    }

    public func track(id trackID: String) -> DepotTrackDefinition? {
        tracks.first { $0.id == trackID }
    }
}

public enum DepotVehicleLocation: Codable, Equatable, Sendable {
    case onRoute(trackID: String, chainageM: Double)
    case inDepot(depotID: String, trackID: String)
    case inTransit(movementID: String)
}

public enum VehicleOperationalState: String, Codable, CaseIterable, Sendable {
    case inService
    case transitToDepot
    case inspectionDue
    case inDepot
    case inspectionInProgress
    case inspectionAwaitingReview
    case repairHold
    case outOfService
    case ready
    case allocated
    case maintenanceInProgress
    case transitToService
}

public enum InspectionClearance: String, Codable, CaseIterable, Sendable {
    case notInspected
    case cleared
    case repairRequired
    case reinspectionRequired
    case heldOutOfService
}

public struct MaintenanceVehicleRecord: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let profileID: String
    public let lengthM: Double
    public var location: DepotVehicleLocation
    public var operationalState: VehicleOperationalState
    public var inspectionClearance: InspectionClearance
    public var assignedServiceID: String?
    public var lastInspectionAtSeconds: Double?
    public var activeScenarioFaultEventIDs: [String]

    public init(
        id: String,
        profileID: String,
        lengthM: Double,
        location: DepotVehicleLocation,
        operationalState: VehicleOperationalState = .inService,
        inspectionClearance: InspectionClearance = .notInspected,
        assignedServiceID: String? = nil,
        lastInspectionAtSeconds: Double? = nil,
        activeScenarioFaultEventIDs: [String] = []
    ) {
        self.id = id
        self.profileID = profileID
        self.lengthM = lengthM
        self.location = location
        self.operationalState = operationalState
        self.inspectionClearance = inspectionClearance
        self.assignedServiceID = assignedServiceID
        self.lastInspectionAtSeconds = lastInspectionAtSeconds
        self.activeScenarioFaultEventIDs = activeScenarioFaultEventIDs
    }
}

public enum DepotMovementKind: String, Codable, Sendable {
    case entry
    case exit
}

public enum DepotMovementStatus: String, Codable, Sendable {
    case inProgress
    case completed
    case cancelled
}

public struct DepotMovement: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let kind: DepotMovementKind
    public let vehicleID: String
    public let depotID: String
    public let depotTrackID: String
    public let serviceID: String?
    public let startedAtSeconds: Double
    public let completesAtSeconds: Double
    public var status: DepotMovementStatus
    public var completedAtSeconds: Double?

    public init(
        id: String,
        kind: DepotMovementKind,
        vehicleID: String,
        depotID: String,
        depotTrackID: String,
        serviceID: String?,
        startedAtSeconds: Double,
        completesAtSeconds: Double,
        status: DepotMovementStatus = .inProgress,
        completedAtSeconds: Double? = nil
    ) {
        self.id = id
        self.kind = kind
        self.vehicleID = vehicleID
        self.depotID = depotID
        self.depotTrackID = depotTrackID
        self.serviceID = serviceID
        self.startedAtSeconds = startedAtSeconds
        self.completesAtSeconds = completesAtSeconds
        self.status = status
        self.completedAtSeconds = completedAtSeconds
    }
}

public enum InspectionKind: String, Codable, CaseIterable, Sendable {
    case preServiceGameCheck
    case postServiceGameCheck
    case scheduledGameCheck
    case faultFollowUpScenario
}

public enum InspectionRecordStatus: String, Codable, CaseIterable, Sendable {
    case inProgress
    case awaitingResult
    case passed
    case repairRequired
    case heldOutOfService
}

public enum InspectionFindingCategory: String, Codable, CaseIterable, Sendable {
    case cosmeticScenarioNote
    case minorGameplayFault
    case majorGameplayFault
}

/// Descriptions are player-facing scenario notes, not real inspection findings or instructions.
public struct InspectionFinding: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let category: InspectionFindingCategory
    public let scenarioNote: String

    public init(id: String, category: InspectionFindingCategory, scenarioNote: String) {
        self.id = id
        self.category = category
        self.scenarioNote = scenarioNote
    }
}

public enum InspectionResult: Codable, Equatable, Sendable {
    case passed(findings: [InspectionFinding])
    case repairRequired(findings: [InspectionFinding])
    case heldOutOfService(findings: [InspectionFinding])
}

public struct VehicleInspectionRecord: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let vehicleID: String
    public let kind: InspectionKind
    public let startedAtSeconds: Double
    public let reviewReadyAtSeconds: Double
    public var status: InspectionRecordStatus
    public var findings: [InspectionFinding]
    public var completedAtSeconds: Double?

    public init(
        id: String,
        vehicleID: String,
        kind: InspectionKind,
        startedAtSeconds: Double,
        reviewReadyAtSeconds: Double,
        status: InspectionRecordStatus = .inProgress,
        findings: [InspectionFinding] = [],
        completedAtSeconds: Double? = nil
    ) {
        self.id = id
        self.vehicleID = vehicleID
        self.kind = kind
        self.startedAtSeconds = startedAtSeconds
        self.reviewReadyAtSeconds = reviewReadyAtSeconds
        self.status = status
        self.findings = findings
        self.completedAtSeconds = completedAtSeconds
    }
}

public enum GameplayMaintenanceTaskKind: String, Codable, CaseIterable, Sendable {
    case scheduledGameplayService
    case correctiveScenarioRepair
    case cleaningAndPresentation
    case scenarioRecovery
}

public enum MaintenanceTaskStatus: String, Codable, CaseIterable, Sendable {
    case planned
    case inProgress
    case completed
    case cancelled
}

public struct GameplayMaintenanceTask: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let vehicleID: String
    public let kind: GameplayMaintenanceTaskKind
    public let durationSeconds: Double
    public let requiresReinspection: Bool
    public var status: MaintenanceTaskStatus
    public var startedAtSeconds: Double?
    public var completesAtSeconds: Double?
    public var completedAtSeconds: Double?

    public init(
        id: String,
        vehicleID: String,
        kind: GameplayMaintenanceTaskKind,
        durationSeconds: Double,
        requiresReinspection: Bool,
        status: MaintenanceTaskStatus = .planned,
        startedAtSeconds: Double? = nil,
        completesAtSeconds: Double? = nil,
        completedAtSeconds: Double? = nil
    ) {
        self.id = id
        self.vehicleID = vehicleID
        self.kind = kind
        self.durationSeconds = durationSeconds
        self.requiresReinspection = requiresReinspection
        self.status = status
        self.startedAtSeconds = startedAtSeconds
        self.completesAtSeconds = completesAtSeconds
        self.completedAtSeconds = completedAtSeconds
    }
}

public struct DepotOperationState: Codable, Equatable, Sendable {
    public var depots: [DepotDefinition]
    public var vehicles: [MaintenanceVehicleRecord]
    public var movements: [DepotMovement]
    public var inspections: [VehicleInspectionRecord]
    public var maintenanceTasks: [GameplayMaintenanceTask]
    public var nextSequence: UInt64

    public init(
        depots: [DepotDefinition],
        vehicles: [MaintenanceVehicleRecord],
        movements: [DepotMovement] = [],
        inspections: [VehicleInspectionRecord] = [],
        maintenanceTasks: [GameplayMaintenanceTask] = [],
        nextSequence: UInt64 = 1
    ) {
        self.depots = depots
        self.vehicles = vehicles
        self.movements = movements
        self.inspections = inspections
        self.maintenanceTasks = maintenanceTasks
        self.nextSequence = nextSequence
    }
}

public enum DepotCommand: Sendable {
    case recordScenarioFault(vehicleID: String, eventInstanceID: String)
    case requestEntry(vehicleID: String, depotID: String, depotTrackID: String)
    case allocate(vehicleID: String, serviceID: String)
    case releaseAllocation(vehicleID: String)
    case requestExit(vehicleID: String, serviceID: String)
    case beginInspection(vehicleID: String, kind: InspectionKind, durationSeconds: Double)
    case submitInspectionResult(inspectionID: String, result: InspectionResult)
    case scheduleMaintenance(vehicleID: String, kind: GameplayMaintenanceTaskKind, durationSeconds: Double, requiresReinspection: Bool)
    case beginMaintenance(taskID: String)
    case cancelMaintenance(taskID: String)
}

public enum DepotOperationEventKind: String, Codable, Sendable {
    case scenarioFaultRecorded
    case movementStarted
    case movementCompleted
    case vehicleAllocated
    case allocationReleased
    case inspectionStarted
    case inspectionReadyForReview
    case inspectionCompleted
    case maintenanceScheduled
    case maintenanceStarted
    case maintenanceCompleted
    case maintenanceCancelled
}

public struct DepotOperationEvent: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let kind: DepotOperationEventKind
    public let vehicleID: String
    public let referenceID: String?
    public let simulationTimeSeconds: Double

    public init(id: String, kind: DepotOperationEventKind, vehicleID: String, referenceID: String?, simulationTimeSeconds: Double) {
        self.id = id
        self.kind = kind
        self.vehicleID = vehicleID
        self.referenceID = referenceID
        self.simulationTimeSeconds = simulationTimeSeconds
    }
}

public enum DepotOperationError: Error, Equatable, Sendable {
    case invalidTime
    case invalidConfiguration(String)
    case unknownDepot(String)
    case unknownVehicle(String)
    case unknownDepotTrack(String)
    case unknownMovement(String)
    case unknownInspection(String)
    case unknownMaintenanceTask(String)
    case invalidTransition(String)
    case hostTrainStateRequired
    case vehicleNotAtDepotAccess
    case depotTrackFull(String)
    case incompatibleVehicleProfile
    case inspectionNotReady
    case inspectionRequired
    case activeInspection
    case activeMaintenanceTask
}
