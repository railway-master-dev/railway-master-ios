import Foundation

private struct FictionalProfileDocument: Decodable {
    let profiles: [TrainsetProfile]
}

public enum FictionalProfileCatalog {
    /// Loads and validates all profiles shipped as this package's JSON resource.
    public static func loadBundled() throws -> [TrainsetProfile] {
        guard let url = Bundle.module.url(forResource: "fictional_vehicle_profiles", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let document = try? JSONDecoder().decode(FictionalProfileDocument.self, from: data),
              !document.profiles.isEmpty else {
            throw TrainPhysicsError.bundledProfilesUnavailable
        }
        let profiles = document.profiles + FictionalFormationCatalog.all
        for profile in profiles {
            let issues = profile.validationIssues()
            guard issues.isEmpty else { throw TrainPhysicsError.invalidProfile(issues) }
        }
        guard Set(profiles.map(\.identifier)).count == profiles.count else {
            throw TrainPhysicsError.invalidProfile(["profile identifiers must be unique"])
        }
        return profiles
    }

    public static func profile(identifier: String) throws -> TrainsetProfile {
        guard let match = try loadBundled().first(where: { $0.identifier == identifier }) else {
            throw TrainPhysicsError.invalidProfile(["unknown profile identifier: \(identifier)"])
        }
        return match
    }
}
