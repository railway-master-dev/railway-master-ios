import XCTest
@testable import RailwaySceneFidelity

final class GeneratedRailwayAssetCatalogTests: XCTestCase {
    func testAssetManifestMatchesCatalogWithoutDuplicateResourceEntries() throws {
        let manifestURL = try XCTUnwrap(RailwayGeneratedAssetCatalog.manifestURL)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: manifestURL)) as? [String: Any])
        let models = try XCTUnwrap(object["models"] as? [[String: Any]])
        let files = try models.map { try XCTUnwrap($0["file"] as? String) }
        var expected = Set<String>()
        for asset in RailwayGenerated3DAsset.allCases {
            let subdirectory = asset == .commuterCarDetailed || asset == .driverCabInteriorDetailed
                ? "HighFidelityAssets/" : ""
            expected.insert("\(subdirectory)\(asset.rawValue).glb")
        }
        XCTAssertEqual(files.count, Set(files).count)
        XCTAssertEqual(Set(files), expected)
    }

    func testSelectedDetailedVehicleAssetsAreBundledOnceInTheirAxisDocumentedSubfolder() throws {
        let selected: [RailwayGenerated3DAsset] = [.commuterCarDetailed, .driverCabInteriorDetailed]
        XCTAssertEqual(Set(RailwayGenerated3DAsset.allCases.map(\.rawValue)).count, RailwayGenerated3DAsset.allCases.count)
        for asset in selected {
            let url = try XCTUnwrap(RailwayGeneratedAssetCatalog.sourceModelURL(for: asset))
            XCTAssertEqual(url.deletingLastPathComponent().lastPathComponent, "HighFidelityAssets")
            let files = try FileManager.default.contentsOfDirectory(
                at: url.deletingLastPathComponent(), includingPropertiesForKeys: nil
            )
            XCTAssertEqual(files.filter { $0.lastPathComponent == "\(asset.rawValue).glb" }.count, 1)
        }
    }

    func testBundledGLBModelsHaveEmbeddedGeometryAndNoExternalURIs() throws {
        for asset in RailwayGenerated3DAsset.allCases {
            let url = try XCTUnwrap(RailwayGeneratedAssetCatalog.sourceModelURL(for: asset))
            let inspection = try GeneratedGLBContainerInspector.inspect(fileAt: url)
            XCTAssertEqual(inspection.version, 2, "Unexpected GLB version for \(asset.rawValue)")
            XCTAssertGreaterThan(inspection.meshCount, 0, "No mesh in \(asset.rawValue)")
            XCTAssertGreaterThan(inspection.nodeCount, 0, "No node in \(asset.rawValue)")
            XCTAssertGreaterThan(inspection.primitiveCount, 0, "No triangles in \(asset.rawValue)")
            XCTAssertGreaterThan(inspection.embeddedBufferByteCount, 0, "No embedded geometry in \(asset.rawValue)")
            XCTAssertEqual(inspection.externalResourceURICount, 0, "External material or texture URI in \(asset.rawValue)")
        }
    }

    func testTypedStationLayoutsCoverDistinctPlatformAndTrackTopologies() throws {
        let manifest = try RailwayGeneratedAssetCatalog.stationLayoutManifest()
        XCTAssertEqual(manifest.stationCount, 32)
        XCTAssertEqual(manifest.stations.count, 32)
        XCTAssertEqual(Set(manifest.stations.map(\.stationId)).count, 32)
        XCTAssertTrue(manifest.stations.allSatisfy { $0.trackCount >= 2 && $0.platformCount >= 1 })
        XCTAssertTrue(manifest.stations.contains { $0.archetype == "island_platform" && $0.modelAsset == .stationIslandPlatform })
        XCTAssertTrue(manifest.stations.contains { $0.trackCount == 4 && $0.platformCount >= 3 && $0.modelAsset == .station4TrackMajor })
        XCTAssertTrue(manifest.stations.contains { $0.trackCount == 5 && $0.platformCount == 4 && $0.modelAsset == .station5Track4Platform })
        XCTAssertTrue(manifest.stations.contains { $0.modelAsset == .stationTerminal })
        XCTAssertTrue(manifest.stations.contains { $0.stationId == "B04" && $0.trackCount == 4 && $0.modelAsset == .stationTerminal })
        XCTAssertGreaterThan(Set(manifest.stations.map(\.modelAsset)).count, 3)
    }

    func testAllSourceModelsAreBundled() {
        for asset in RailwayGenerated3DAsset.allCases {
            XCTAssertNotNil(RailwayGeneratedAssetCatalog.sourceModelURL(for: asset), "Missing bundled model: \(asset.rawValue)")
        }
    }

    func testStationLayoutManifestContains32UniqueStations() throws {
        let data = try RailwayGeneratedAssetCatalog.stationLayoutsData()
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(object["stationCount"] as? Int, 32)
        let stations = try XCTUnwrap(object["stations"] as? [[String: Any]])
        XCTAssertEqual(stations.count, 32)
        let ids = stations.compactMap { $0["stationId"] as? String }
        XCTAssertEqual(Set(ids).count, 32)
        XCTAssertEqual(stations.filter { ($0["lineId"] as? String) == "MAIN" }.count, 28)
        XCTAssertEqual(stations.filter { ($0["lineId"] as? String) == "BRANCH" }.count, 4)
    }
}
