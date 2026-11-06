import Foundation

public struct DepartureMelodyKey: Codable, Hashable, Sendable {
    public var stationID: String
    public var directionID: String
    public var platformID: String

    public init(stationID: String, directionID: String, platformID: String) {
        self.stationID = stationID
        self.directionID = directionID
        self.platformID = platformID
    }
}

public struct DepartureMelodyNote: Codable, Sendable {
    public var offset: TimeInterval
    public var frequencyHz: Float
    public var duration: TimeInterval
    public var intensity: Float

    public init(offset: TimeInterval, frequencyHz: Float, duration: TimeInterval = 0.28, intensity: Float = 0.55) {
        self.offset = max(0, offset.isFinite ? offset : 0)
        self.frequencyHz = min(4_000, max(100, frequencyHz.isFinite ? frequencyHz : 440))
        self.duration = max(0.08, duration.isFinite ? min(5, duration) : 0.28)
        self.intensity = min(1, max(0, intensity.isFinite ? intensity : 0.55))
    }
}

public struct DepartureMelodyDefinition: Codable, Sendable {
    public var notes: [DepartureMelodyNote]
    public init(notes: [DepartureMelodyNote]) { self.notes = notes }
}

/// 駅・方向・番線をキーにした出発チャイム設定。
/// 未登録キーはオリジナルの五音音階フレーズを決定的に生成します。既存曲や実在メロディは収録しません。
public final class DepartureMelodyCatalog {
    private var definitions: [DepartureMelodyKey: DepartureMelodyDefinition] = [:]

    public init() {}

    public func register(_ definition: DepartureMelodyDefinition, for key: DepartureMelodyKey) {
        definitions[key] = definition
    }

    public func definition(for key: DepartureMelodyKey) -> DepartureMelodyDefinition {
        if let authored = definitions[key], !authored.notes.isEmpty { return authored }
        let seed = stableHash("\(key.stationID)|\(key.directionID)|\(key.platformID)")
        let scale: [Float] = [587.33, 659.25, 739.99, 880.00, 987.77, 1_174.66]
        let count = 3 + Int(seed % 3)
        var state = seed
        var notes: [DepartureMelodyNote] = []
        var offset: TimeInterval = 0
        var previous = Int((seed >> 8) % UInt64(scale.count))
        for index in 0..<count {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            let step = Int((state >> 32) % 3) + 1
            let direction = (state & 1) == 0 ? 1 : -1
            previous = min(scale.count - 1, max(0, previous + direction * step))
            let frequency = scale[previous] * ((index == count - 1 && (seed & 2) != 0) ? 2.0 : 1.0)
            notes.append(.init(offset: offset, frequencyHz: frequency, duration: 0.22 + Double(index % 2) * 0.035, intensity: 0.46))
            offset += 0.18
        }
        return DepartureMelodyDefinition(notes: notes)
    }

    public func events(for key: DepartureMelodyKey, startingAt time: TimeInterval, position: AudioVector3? = nil) -> [RailwayAudioEvent] {
        definition(for: key).notes.enumerated().map { index, note in
            RailwayAudioEvent(
                id: "departure-\(stableHash(key.stationID + key.directionID + key.platformID))-\(Int(time * 1_000))-\(index)",
                kind: .departureMelodyNote,
                scheduledTime: time + note.offset,
                duration: note.duration,
                intensity: note.intensity,
                frequencyHz: note.frequencyHz,
                priority: 4,
                position: position
            )
        }
    }

    private func stableHash(_ text: String) -> UInt64 {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in text.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 1_099_511_628_211
        }
        return hash
    }
}
