import Foundation

public enum AnnouncementLocale: String, Codable, Hashable, Sendable {
    case japanese
    case english

    public var speechLanguageTag: String {
        switch self {
        case .japanese: return "ja-JP"
        case .english: return "en-GB"
        }
    }
}

public enum AnnouncementTemplate: String, CaseIterable, Codable, Hashable, Sendable {
    case approachingStation
    case nextStation
    case doorsClosing
    case platformSafety
    case serviceDelay
    case transfer
}

/// テンプレートで任意に参照する、架空路線にも実路線にも使える表示名。
public struct AnnouncementContext: Codable, Hashable, Sendable {
    public var stationName: String?
    public var destination: String?

    public init(stationName: String? = nil, destination: String? = nil) {
        self.stationName = stationName
        self.destination = destination
    }
}

/// AVSpeechSynthesizerなど、ホスト側TTSへ渡す文章。音声ファイルは生成・同梱しません。
public struct SpeechInstruction: Equatable, Sendable {
    public var text: String
    public var languageTag: String
    public var channel: AnnouncementChannel
    public var audioBus: AudioBus

    public init(text: String, languageTag: String, channel: AnnouncementChannel) {
        self.text = text
        self.languageTag = languageTag
        self.channel = channel
        self.audioBus = channel.audioBus
    }
}

public enum AnnouncementRenderer {
    /// 必須差し込み値が欠けている場合はnilを返し、未完成の文を放送しません。
    public static func render(_ request: AnnouncementRequest) -> SpeechInstruction? {
        let text: String
        switch (request.template, request.locale) {
        case (.approachingStation, .japanese):
            guard let station = nonEmpty(request.context.stationName) else { return nil }
            text = "まもなく、\(station)、\(station)です。"
        case (.approachingStation, .english):
            guard let station = nonEmpty(request.context.stationName) else { return nil }
            text = "We will soon arrive at \(station)."
        case (.nextStation, .japanese):
            guard let station = nonEmpty(request.context.stationName) else { return nil }
            text = "次は、\(station)です。"
        case (.nextStation, .english):
            guard let station = nonEmpty(request.context.stationName) else { return nil }
            text = "The next station is \(station)."
        case (.doorsClosing, .japanese):
            text = "ドアが閉まります。ご注意ください。"
        case (.doorsClosing, .english):
            text = "The doors are closing. Please stand clear."
        case (.platformSafety, .japanese):
            text = "黄色い線までお下がりください。"
        case (.platformSafety, .english):
            text = "Please stand behind the yellow line."
        case (.serviceDelay, .japanese):
            text = "ただいま、列車に遅れが発生しております。ご迷惑をおかけして申し訳ございません。"
        case (.serviceDelay, .english):
            text = "This train is delayed. We apologise for the inconvenience."
        case (.transfer, .japanese):
            guard let destination = nonEmpty(request.context.destination) else { return nil }
            text = "\(destination)方面へお越しのお客様は、お乗り換えください。"
        case (.transfer, .english):
            guard let destination = nonEmpty(request.context.destination) else { return nil }
            text = "Please change here for services towards \(destination)."
        }
        return SpeechInstruction(
            text: text,
            languageTag: request.locale.speechLanguageTag,
            channel: request.channel
        )
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
