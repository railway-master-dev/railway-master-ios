import Foundation

public extension TrafficScenarioLibrary {
    /// Loads a fully fictional, PLACEHOLDER regional traffic example. Its topology
    /// is illustrative only and is not an authoritative route or timetable source.
    static func loadBundledRegionalNetwork() throws -> TrafficScenario {
        guard let url = Bundle.module.url(forResource: "FictionalRegionalNetwork", withExtension: "json") else {
            throw CocoaError(.fileNoSuchFile)
        }
        return try JSONDecoder().decode(TrafficScenario.self, from: Data(contentsOf: url))
    }
}
