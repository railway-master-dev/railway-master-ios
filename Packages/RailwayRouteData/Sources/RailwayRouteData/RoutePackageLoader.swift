import Foundation

public enum RoutePackageLoadingError: Error, LocalizedError {
    case resourceNotFound(String)

    public var errorDescription: String? {
        switch self {
        case .resourceNotFound(let name):
            return "Route package resource '\(name)' was not found in the Data bundle directory."
        }
    }
}

/// Loads a route JSON bundled with this Swift package or supplied by an integrator.
public enum RoutePackageLoader {
    public static func loadResourceData(named name: String) throws -> Data {
        try loadResourceData(named: name, bundle: .module)
    }

    public static func loadResourceData(
        named name: String,
        bundle: Bundle
    ) throws -> Data {
        let requested = name as NSString
        let resourceName = requested.pathExtension.lowercased() == "json" ? requested.deletingPathExtension : name
        guard let url = bundle.url(forResource: resourceName, withExtension: "json", subdirectory: "Data") else {
            throw RoutePackageLoadingError.resourceNotFound(name)
        }
        return try Data(contentsOf: url)
    }

    public static func loadResource(named name: String) throws -> RoutePackage {
        try loadResource(named: name, bundle: .module)
    }

    public static func loadResource(named name: String, decoder: JSONDecoder) throws -> RoutePackage {
        try loadResource(named: name, bundle: .module, decoder: decoder)
    }

    public static func loadResource(
        named name: String,
        bundle: Bundle,
        decoder: JSONDecoder = JSONDecoder()
    ) throws -> RoutePackage {
        try decode(loadResourceData(named: name, bundle: bundle), decoder: decoder)
    }

    public static func load(from url: URL, decoder: JSONDecoder = JSONDecoder()) throws -> RoutePackage {
        let data = try Data(contentsOf: url)
        return try decode(data, decoder: decoder)
    }

    public static func decode(_ data: Data, decoder: JSONDecoder = JSONDecoder()) throws -> RoutePackage {
        try decoder.decode(RoutePackage.self, from: data)
    }
}
