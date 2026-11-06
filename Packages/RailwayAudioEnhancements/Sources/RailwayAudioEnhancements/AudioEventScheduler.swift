import Foundation

/// 音声イベントが再生される先。実際のAVAudioEngineノードへの接続はホストが行います。
public enum AudioBus: String, CaseIterable, Codable, Hashable, Sendable {
    case cabInterior
    case exterior
    case stationPublicAddress
    case onboardAnnouncement
    case tunnelReflection
    case effects
}

public enum AnnouncementChannel: String, Codable, Hashable, Sendable {
    case stationPublicAddress
    case onboardAutomated
    case conductor

    public var audioBus: AudioBus {
        switch self {
        case .stationPublicAddress: return .stationPublicAddress
        case .onboardAutomated, .conductor: return .onboardAnnouncement
        }
    }
}

public enum SpeakerTone: String, Codable, Hashable, Sendable {
    case attentionChime
    case doorWarning
    case stationBell
    /// Short ATS acknowledge tone. Not the station chime.
    case atsConfirm
}

/// 放送の文章と対象チャンネル。時刻はAudioScheduledEvent側に一元化します。
public struct AnnouncementRequest: Codable, Hashable, Sendable {
    public var template: AnnouncementTemplate
    public var locale: AnnouncementLocale
    public var context: AnnouncementContext
    public var channel: AnnouncementChannel

    public init(
        template: AnnouncementTemplate,
        locale: AnnouncementLocale,
        context: AnnouncementContext = .init(),
        channel: AnnouncementChannel = .onboardAutomated
    ) {
        self.template = template
        self.locale = locale
        self.context = context
        self.channel = channel
    }
}

/// 車両シミュレーターから受け取る駆動状態。単位はm/s、m/s²、rpmです。
public struct ControlSignalRequest: Codable, Hashable, Sendable {
    public var mode: TractionControlMode
    public var state: ControlSignalState
    public var durationSeconds: Double

    public init(mode: TractionControlMode, state: ControlSignalState, durationSeconds: Double = 0.25) {
        self.mode = mode
        self.state = state
        self.durationSeconds = durationSeconds.isFinite ? min(10, max(0, durationSeconds)) : 0
    }
}

public enum AudioCuePayload: Codable, Hashable, Sendable {
    case announcement(AnnouncementRequest)
    case speakerTone(SpeakerTone)
    case controlModeSignature(ControlSignalRequest)
}

/// 予約された通知・話者音・合成制御シグネチャ。
public struct AudioScheduledEvent: Codable, Hashable, Sendable {
    public var id: String
    public var scheduledTime: TimeInterval
    public var priority: Int
    public var deduplicationKey: String?
    public var bus: AudioBus
    public var payload: AudioCuePayload

    public init(
        id: String,
        scheduledTime: TimeInterval,
        priority: Int = 0,
        deduplicationKey: String? = nil,
        bus: AudioBus,
        payload: AudioCuePayload
    ) {
        self.id = id
        self.scheduledTime = scheduledTime
        self.priority = priority
        self.deduplicationKey = deduplicationKey
        self.bus = bus
        self.payload = payload
    }
}

public enum AudioScheduleOutcome: Equatable, Sendable {
    case scheduled
    case duplicateEventID
    case duplicateKey(String)
    case eventInPast
    case invalidTime
}

public enum AudioEventSchedulerError: Error, Equatable {
    case invalidClock
    case clockMovedBackwards(current: TimeInterval, requested: TimeInterval)
}

/// 実時間タイマーを使わず、ホストから渡されるシミュレーション秒だけでキューを進めます。
/// 同時刻は「優先度の降順、IDの辞書順」で排出し、投入順に依存しない結果にします。
public final class AudioEventScheduler {
    public private(set) var currentTime: TimeInterval
    public private(set) var pendingCount: Int = 0

    private var pending: [AudioScheduledEvent] = []
    private var seenEventIDs: Set<String> = []
    private var seenDeduplicationKeys: Set<String> = []

    public init(startTime: TimeInterval = 0) {
        currentTime = startTime.isFinite ? startTime : 0
    }

    @discardableResult
    public func schedule(_ event: AudioScheduledEvent) -> AudioScheduleOutcome {
        guard event.scheduledTime.isFinite else { return .invalidTime }
        guard event.scheduledTime >= currentTime else { return .eventInPast }
        guard !event.id.isEmpty, !seenEventIDs.contains(event.id) else { return .duplicateEventID }
        if let key = event.deduplicationKey, !key.isEmpty, seenDeduplicationKeys.contains(key) {
            return .duplicateKey(key)
        }

        seenEventIDs.insert(event.id)
        if let key = event.deduplicationKey, !key.isEmpty {
            seenDeduplicationKeys.insert(key)
        }
        pending.append(event)
        pending.sort(by: Self.order)
        pendingCount = pending.count
        return .scheduled
    }

    /// 指定時刻までのイベントを一度だけ返します。同じ時刻での再呼び出しは空配列です。
    public func advance(to simulationTime: TimeInterval) throws -> [AudioScheduledEvent] {
        guard simulationTime.isFinite else { throw AudioEventSchedulerError.invalidClock }
        guard simulationTime >= currentTime else {
            throw AudioEventSchedulerError.clockMovedBackwards(current: currentTime, requested: simulationTime)
        }
        currentTime = simulationTime
        let due = pending.filter { $0.scheduledTime <= simulationTime }
        pending.removeAll { $0.scheduledTime <= simulationTime }
        pendingCount = pending.count
        return due
    }

    /// 未実行イベントの取り消し。取り消したイベントのIDと重複キーは再利用できます。
    @discardableResult
    public func cancel(eventID: String) -> Bool {
        guard let index = pending.firstIndex(where: { $0.id == eventID }) else { return false }
        let removed = pending.remove(at: index)
        seenEventIDs.remove(removed.id)
        if let key = removed.deduplicationKey, !key.isEmpty {
            seenDeduplicationKeys.remove(key)
        }
        pendingCount = pending.count
        return true
    }

    /// シーク／リプレイ開始時に呼び、旧キューと重複履歴を破棄します。
    /// 再現性のため、ホストは復元したシミュレーション状態からイベントを再投入してください。
    public func reset(to simulationTime: TimeInterval = 0) {
        currentTime = simulationTime.isFinite ? simulationTime : 0
        pending.removeAll(keepingCapacity: true)
        seenEventIDs.removeAll(keepingCapacity: true)
        seenDeduplicationKeys.removeAll(keepingCapacity: true)
        pendingCount = 0
    }

    private static func order(_ lhs: AudioScheduledEvent, _ rhs: AudioScheduledEvent) -> Bool {
        if lhs.scheduledTime != rhs.scheduledTime { return lhs.scheduledTime < rhs.scheduledTime }
        if lhs.priority != rhs.priority { return lhs.priority > rhs.priority }
        return lhs.id < rhs.id
    }
}
