import Foundation

public enum DisruptionKind: String, Codable, CaseIterable, Sendable {
    case simulatedDoorDelay
    case temporaryGameSpeedCap
    case gameSignalHold
    case simulatedEquipmentPrompt
}

public enum DisruptionGameChoice: String, Codable, CaseIterable, Sendable {
    case acknowledgeGamePrompt
    case requestGameHint
    case holdGameSession
    case resumeAfterPromptClears
}

/// A scripted, fictional game event. The expected choice is not an operating instruction.
public struct DisruptionEventDefinition: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let kind: DisruptionKind
    public let triggerTimeSeconds: Double
    public let availableChoices: [DisruptionGameChoice]
    public let expectedGameChoice: DisruptionGameChoice
    public let description: String

    public var contentLabel: OperationsContentLabel { .gameOnlyNotSafetyTraining }

    public init(id: String, kind: DisruptionKind, triggerTimeSeconds: Double, availableChoices: [DisruptionGameChoice], expectedGameChoice: DisruptionGameChoice, description: String) throws {
        guard !id.isEmpty, triggerTimeSeconds.isFinite, triggerTimeSeconds >= 0,
              !availableChoices.isEmpty, Set(availableChoices).count == availableChoices.count,
              availableChoices.contains(expectedGameChoice), !description.isEmpty else {
            throw OperationsError.invalidValue("disruption event definition")
        }
        self.id = id
        self.kind = kind
        self.triggerTimeSeconds = triggerTimeSeconds
        self.availableChoices = availableChoices
        self.expectedGameChoice = expectedGameChoice
        self.description = description
    }
}

public enum DisruptionEventStatus: String, Codable, Sendable {
    case scheduled
    case active
    case resolved
}

public struct DisruptionTrainingRecord: Codable, Equatable, Sendable, Identifiable {
    public let id: Int
    public let eventID: String
    public let kind: DisruptionKind
    public let selectedChoice: DisruptionGameChoice
    public let matchedGameChoice: Bool
    public let simulationTimeSeconds: Double
    public let label: OperationsContentLabel
}

/// Event queue for the disruption-training game mode. It does not provide real incident response training.
public struct DisruptionTrainingSession: Codable, Equatable, Sendable {
    public let mode: TrainingMode
    public let definitions: [DisruptionEventDefinition]
    public private(set) var statusByEventID: [String: DisruptionEventStatus]
    public private(set) var records: [DisruptionTrainingRecord]

    public init(mode: TrainingMode, definitions: [DisruptionEventDefinition]) throws {
        guard mode == .disruptionTraining || definitions.isEmpty else {
            throw OperationsError.invalidValue("disruption events are only enabled in disruption-training mode")
        }
        guard Set(definitions.map(\.id)).count == definitions.count else {
            throw OperationsError.duplicateIdentifier("disruption event id")
        }
        self.mode = mode
        self.definitions = definitions
        self.statusByEventID = Dictionary(uniqueKeysWithValues: definitions.map { ($0.id, .scheduled) })
        self.records = []
    }

    public var contentLabel: OperationsContentLabel { .gameOnlyNotSafetyTraining }
    public var activeEventIDs: [String] { definitions.filter { statusByEventID[$0.id] == .active }.map(\.id) }

    @discardableResult
    public mutating func activateDueEvents(at simulationTimeSeconds: Double) throws -> [DisruptionEventDefinition] {
        guard simulationTimeSeconds.isFinite, simulationTimeSeconds >= 0 else {
            throw OperationsError.invalidValue("disruption time")
        }
        let due = definitions.filter { $0.triggerTimeSeconds <= simulationTimeSeconds && statusByEventID[$0.id] == .scheduled }
        for event in due { statusByEventID[event.id] = .active }
        return due
    }

    @discardableResult
    public mutating func respond(eventID: String, choice: DisruptionGameChoice, at simulationTimeSeconds: Double) throws -> DisruptionTrainingRecord {
        guard simulationTimeSeconds.isFinite, simulationTimeSeconds >= 0 else {
            throw OperationsError.invalidValue("disruption response time")
        }
        guard let definition = definitions.first(where: { $0.id == eventID }) else {
            throw OperationsError.unknownIdentifier(eventID)
        }
        guard statusByEventID[eventID] == .active else { throw OperationsError.eventNotActive(eventID) }
        guard definition.availableChoices.contains(choice) else {
            throw OperationsError.invalidValue("choice is not available for this fictional event")
        }
        statusByEventID[eventID] = .resolved
        let record = DisruptionTrainingRecord(
            id: records.count,
            eventID: eventID,
            kind: definition.kind,
            selectedChoice: choice,
            matchedGameChoice: choice == definition.expectedGameChoice,
            simulationTimeSeconds: simulationTimeSeconds,
            label: .gameOnlyNotSafetyTraining
        )
        records.append(record)
        return record
    }
}
