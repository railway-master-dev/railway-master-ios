import Foundation

public enum GameCheckpointTrigger: String, Codable, CaseIterable, Sendable {
    case beforeDuty
    case cabSetup
    case depotExit
    case beforeDeparture
    case signalEncounter
    case speedRestrictionEncounter
    case stationApproach
    case stopMarker
    case doorsClosed
    case endOfRun
    case disruptionPrompt
}

public struct PointingCallingDefinition: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let trigger: GameCheckpointTrigger
    public let contextID: String?
    public let targetLabel: String
    public let acceptedCallouts: [String]

    public var contentLabel: OperationsContentLabel { .fictionalGameRules }

    public init(id: String, trigger: GameCheckpointTrigger, contextID: String? = nil, targetLabel: String, acceptedCallouts: [String]) throws {
        guard !id.isEmpty, !targetLabel.isEmpty,
              !acceptedCallouts.isEmpty,
              acceptedCallouts.allSatisfy({ !Self.normalize($0).isEmpty }) else {
            throw OperationsError.invalidValue("pointing/calling definition")
        }
        self.id = id
        self.trigger = trigger
        self.contextID = contextID
        self.targetLabel = targetLabel
        self.acceptedCallouts = acceptedCallouts
    }

    fileprivate static func normalize(_ text: String) -> String {
        String(text.lowercased().filter { character in
            !character.isWhitespace && !"、。，,.!?！？”’\"'".contains(character)
        })
    }
}

public enum PointingCallingResultKind: String, Codable, CaseIterable, Sendable {
    case correct
    case incorrect
    case missed
}

public enum PointingCallingStatus: String, Codable, Sendable {
    case notDue
    case due
    case resolved
}

public struct PointingCallingRecord: Codable, Equatable, Sendable, Identifiable {
    public let id: Int
    public let checkpointID: String
    public let trigger: GameCheckpointTrigger
    public let targetLabel: String
    public let result: PointingCallingResultKind
    public let callout: String?
    public let simulationTimeSeconds: Double
    public let positionM: Double?
    public let label: OperationsContentLabel
}

/// The tracker records game prompts and player callouts; it does not model an operator's real procedure.
public struct PointingCallingTracker: Codable, Equatable, Sendable {
    public let definitions: [PointingCallingDefinition]
    public private(set) var statusByCheckpointID: [String: PointingCallingStatus]
    public private(set) var records: [PointingCallingRecord]

    public init(definitions: [PointingCallingDefinition]) throws {
        guard Set(definitions.map(\.id)).count == definitions.count else {
            throw OperationsError.duplicateIdentifier("pointing/calling checkpoint id")
        }
        self.definitions = definitions
        self.statusByCheckpointID = Dictionary(uniqueKeysWithValues: definitions.map { ($0.id, .notDue) })
        self.records = []
    }

    public var contentLabel: OperationsContentLabel { .fictionalGameRules }

    @discardableResult
    public mutating func activate(trigger: GameCheckpointTrigger, contextID: String? = nil, at simulationTimeSeconds: Double, positionM: Double? = nil) throws -> [String] {
        try validateMoment(simulationTimeSeconds: simulationTimeSeconds, positionM: positionM)
        let matching = definitions.filter {
            $0.trigger == trigger && ($0.contextID == nil || $0.contextID == contextID) && statusByCheckpointID[$0.id] == .notDue
        }
        for definition in matching { statusByCheckpointID[definition.id] = .due }
        return matching.map(\.id)
    }

    @discardableResult
    public mutating func perform(checkpointID: String, callout: String, at simulationTimeSeconds: Double, positionM: Double? = nil) throws -> PointingCallingRecord {
        try validateMoment(simulationTimeSeconds: simulationTimeSeconds, positionM: positionM)
        guard let definition = definitions.first(where: { $0.id == checkpointID }) else {
            throw OperationsError.unknownIdentifier(checkpointID)
        }
        guard statusByCheckpointID[checkpointID] == .due else {
            if statusByCheckpointID[checkpointID] == .resolved { throw OperationsError.checkpointAlreadyResolved(checkpointID) }
            throw OperationsError.checkpointNotDue(checkpointID)
        }
        let normalizedCallout = PointingCallingDefinition.normalize(callout)
        let isCorrect = definition.acceptedCallouts.contains { PointingCallingDefinition.normalize($0) == normalizedCallout }
        statusByCheckpointID[checkpointID] = .resolved
        let record = PointingCallingRecord(
            id: records.count,
            checkpointID: checkpointID,
            trigger: definition.trigger,
            targetLabel: definition.targetLabel,
            result: isCorrect ? .correct : .incorrect,
            callout: callout,
            simulationTimeSeconds: simulationTimeSeconds,
            positionM: positionM,
            label: .fictionalGameRules
        )
        records.append(record)
        return record
    }

    @discardableResult
    public mutating func markMissed(checkpointID: String, at simulationTimeSeconds: Double, positionM: Double? = nil) throws -> PointingCallingRecord {
        try validateMoment(simulationTimeSeconds: simulationTimeSeconds, positionM: positionM)
        guard let definition = definitions.first(where: { $0.id == checkpointID }) else {
            throw OperationsError.unknownIdentifier(checkpointID)
        }
        guard statusByCheckpointID[checkpointID] == .due else {
            if statusByCheckpointID[checkpointID] == .resolved { throw OperationsError.checkpointAlreadyResolved(checkpointID) }
            throw OperationsError.checkpointNotDue(checkpointID)
        }
        statusByCheckpointID[checkpointID] = .resolved
        let record = PointingCallingRecord(
            id: records.count,
            checkpointID: checkpointID,
            trigger: definition.trigger,
            targetLabel: definition.targetLabel,
            result: .missed,
            callout: nil,
            simulationTimeSeconds: simulationTimeSeconds,
            positionM: positionM,
            label: .fictionalGameRules
        )
        records.append(record)
        return record
    }

    public var dueCheckpointIDs: [String] {
        definitions.filter { statusByCheckpointID[$0.id] == .due }.map(\.id)
    }

    public var resolvedCount: Int { records.count }
    public var correctCount: Int { records.filter { $0.result == .correct }.count }
    public var coverageRate: Double? {
        let dueCount = statusByCheckpointID.values.filter { $0 != .notDue }.count
        guard dueCount > 0 else { return nil }
        return Double(correctCount) / Double(dueCount)
    }

    private func validateMoment(simulationTimeSeconds: Double, positionM: Double?) throws {
        guard simulationTimeSeconds.isFinite, simulationTimeSeconds >= 0,
              positionM.map({ $0.isFinite && $0 >= 0 }) ?? true else {
            throw OperationsError.invalidValue("checkpoint time/position")
        }
    }
}
