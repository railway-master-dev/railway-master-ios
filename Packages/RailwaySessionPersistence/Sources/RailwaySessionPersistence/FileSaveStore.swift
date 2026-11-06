import Foundation

public struct SaveSlotSummary: Equatable, Sendable, Identifiable {
    public let id: String
    public let saveName: String
    public let savedAt: Date
    public let routeID: String
    public let vehicleProfileID: String
    public let simulationTimeSeconds: Double

    public init(id: String, saveName: String, savedAt: Date, routeID: String, vehicleProfileID: String, simulationTimeSeconds: Double) {
        self.id = id
        self.saveName = saveName
        self.savedAt = savedAt
        self.routeID = routeID
        self.vehicleProfileID = vehicleProfileID
        self.simulationTimeSeconds = simulationTimeSeconds
    }
}

public enum FileSaveStoreError: Error, Equatable, Sendable, CustomStringConvertible {
    case invalidSlotID
    case slotNotFound
    case unreadableDirectory

    public var description: String {
        switch self {
        case .invalidSlotID: return "Slot IDs may contain only ASCII letters, digits, hyphens, and underscores (1–64 characters)."
        case .slotNotFound: return "Save slot was not found."
        case .unreadableDirectory: return "The save directory could not be read."
        }
    }
}

/// Foundation-only JSON store. Writes use a same-directory atomic replacement, and slot IDs
/// are constrained before becoming filenames. Exported JSON can be transferred to another device.
public final class FileSaveStore: @unchecked Sendable {
    public let directoryURL: URL
    private let fileManager: FileManager
    private let lock = NSLock()

    public init(directoryURL: URL, fileManager: FileManager = .default) throws {
        self.directoryURL = directoryURL.standardizedFileURL
        self.fileManager = fileManager
        try fileManager.createDirectory(at: self.directoryURL, withIntermediateDirectories: true)
    }

    @discardableResult
    public func save(_ state: SimulationSaveState, toSlot slotID: String, savedAt: Date = Date()) throws -> URL {
        try withLock {
            let url = try fileURL(for: slotID)
            let data = try SessionSaveCodec.encode(state, savedAt: savedAt)
            try data.write(to: url, options: .atomic)
            return url
        }
    }

    public func load(slot slotID: String) throws -> DecodedSimulationSave {
        try withLock {
            let url = try fileURL(for: slotID)
            guard fileManager.fileExists(atPath: url.path) else { throw FileSaveStoreError.slotNotFound }
            let attributes = try fileManager.attributesOfItem(atPath: url.path)
            if let size = attributes[.size] as? NSNumber, size.intValue > SessionSaveCodec.maximumEncodedBytes {
                throw SessionSaveCodecError.dataTooLarge
            }
            return try SessionSaveCodec.decode(Data(contentsOf: url))
        }
    }

    /// Returns valid slots newest-first. Corrupt/unsupported files are omitted and remain untouched.
    public func listSlots() throws -> [SaveSlotSummary] {
        try withLock {
            let urls: [URL]
            do {
                urls = try fileManager.contentsOfDirectory(
                    at: directoryURL,
                    includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
                    options: [.skipsHiddenFiles]
                )
            } catch { throw FileSaveStoreError.unreadableDirectory }

            return urls.compactMap { url in
                guard url.pathExtension == "json", let slotID = url.deletingPathExtension().lastPathComponent.nilIfEmpty else { return nil }
                guard (try? validateSlotID(slotID)) != nil,
                      let data = try? Data(contentsOf: url),
                      let decoded = try? SessionSaveCodec.decode(data) else { return nil }
                return SaveSlotSummary(
                    id: slotID,
                    saveName: decoded.state.saveName,
                    savedAt: decoded.savedAt,
                    routeID: decoded.state.route.routeID,
                    vehicleProfileID: decoded.state.vehicle.profileID,
                    simulationTimeSeconds: decoded.state.simulation.simulationTimeSeconds
                )
            }.sorted { $0.savedAt > $1.savedAt }
        }
    }

    /// Validates before export so callers never transfer a corrupt or unsupported file silently.
    public func exportData(fromSlot slotID: String) throws -> Data {
        try withLock {
            let url = try fileURL(for: slotID)
            guard fileManager.fileExists(atPath: url.path) else { throw FileSaveStoreError.slotNotFound }
            let data = try Data(contentsOf: url)
            _ = try SessionSaveCodec.decode(data)
            return data
        }
    }

    /// Imports portable JSON into a caller-selected slot, validating it before the atomic write.
    /// Existing content in the selected slot is replaced only after the imported data is valid.
    @discardableResult
    public func importData(_ data: Data, toSlot slotID: String) throws -> DecodedSimulationSave {
        try withLock {
            let decoded = try SessionSaveCodec.decode(data)
            let url = try fileURL(for: slotID)
            let canonicalData = try SessionSaveCodec.encode(decoded.state, savedAt: decoded.savedAt)
            try canonicalData.write(to: url, options: .atomic)
            return decoded
        }
    }

    public func delete(slot slotID: String) throws {
        try withLock {
            let url = try fileURL(for: slotID)
            guard fileManager.fileExists(atPath: url.path) else { throw FileSaveStoreError.slotNotFound }
            try fileManager.removeItem(at: url)
        }
    }

    private func fileURL(for slotID: String) throws -> URL {
        try validateSlotID(slotID)
        return directoryURL.appendingPathComponent(slotID, isDirectory: false).appendingPathExtension("json")
    }

    private func validateSlotID(_ slotID: String) throws {
        let bytes = Array(slotID.utf8)
        guard !bytes.isEmpty, bytes.count <= 64,
              bytes.allSatisfy({
                  (65...90).contains($0) || (97...122).contains($0) || (48...57).contains($0) || $0 == 45 || $0 == 95
              }) else { throw FileSaveStoreError.invalidSlotID }
    }

    private func withLock<T>(_ operation: () throws -> T) rethrows -> T {
        lock.lock()
        defer { lock.unlock() }
        return try operation()
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
