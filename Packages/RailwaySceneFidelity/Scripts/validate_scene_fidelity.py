#!/usr/bin/env python3
"""Static contract checks for RailwaySceneFidelity when Swift/Xcode is unavailable."""
from __future__ import annotations

from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[1]
REQUIRED = [
    ROOT / "Package.swift",
    ROOT / "README.md",
    ROOT / "INTEGRATION.md",
    ROOT / "IMPLEMENTATION_NOTES.md",
    ROOT / "Sources/RailwaySceneFidelity/Geometry.swift",
    ROOT / "Sources/RailwaySceneFidelity/SceneTypes.swift",
    ROOT / "Sources/RailwaySceneFidelity/ScenePlanBuilder.swift",
    ROOT / "Sources/RailwaySceneFidelity/RealityKitSceneAdapter.swift",
    ROOT / "Sources/RailwaySceneFidelity/GeneratedRailwayAssetCatalog.swift",
    ROOT / "Sources/RailwaySceneFidelity/GeneratedRailwayAssetLoader.swift",
    ROOT / "Sources/RailwaySceneFidelity/Resources/Generated3D/asset_manifest.json",
    ROOT / "Sources/RailwaySceneFidelity/Resources/Generated3D/station_layouts_32.json",
    ROOT / "Tests/RailwaySceneFidelityTests/RailwaySceneFidelityTests.swift",
    ROOT / "Tests/RailwaySceneFidelityTests/GeneratedRailwayAssetCatalogTests.swift",
]

errors: list[str] = []
for file in REQUIRED:
    if not file.is_file() or file.stat().st_size == 0:
        errors.append(f"missing or empty required file: {file.relative_to(ROOT)}")

if not errors:
    package = (ROOT / "Package.swift").read_text(encoding="utf-8")
    geometry = (ROOT / "Sources/RailwaySceneFidelity/Geometry.swift").read_text(encoding="utf-8")
    types = (ROOT / "Sources/RailwaySceneFidelity/SceneTypes.swift").read_text(encoding="utf-8")
    builder = (ROOT / "Sources/RailwaySceneFidelity/ScenePlanBuilder.swift").read_text(encoding="utf-8")
    adapter = (ROOT / "Sources/RailwaySceneFidelity/RealityKitSceneAdapter.swift").read_text(encoding="utf-8")
    tests = "\n".join(
        path.read_text(encoding="utf-8") for path in sorted((ROOT / "Tests").rglob("*.swift"))
    )

    if ".package(url:" in package or "dependencies: [\n        .package" in package:
        errors.append("Package.swift unexpectedly adds an external package dependency")
    if 'platforms: [.iOS(.v17)]' not in package:
        errors.append("iOS 17 deployment platform declaration missing")
    if 'resources: [.process("Resources")]' not in package:
        errors.append("procedural GLB and station resources are not copied into the SwiftPM bundle")
    if "cubic-Hermite" not in geometry or "SceneRouteFrame" not in geometry or "tangentPerMeter" not in geometry:
        errors.append("chainage curve interpolation/tangent frame contract missing")
    for required in [".trackBed", ".rail", ".sleeper", ".trackFastener", ".catenarySupport", ".overheadWire",
                     ".platform", ".stationFurniture", ".building", ".roadSurface", ".roadVehicle", ".pedestrian", ".vegetation",
                     ".bridgeStructure", ".cuttingWall", ".embankment", ".levelCrossing", "NOT INTERLOCKED"]:
        if required not in builder:
            errors.append(f"scene builder feature missing: {required}")
    if "SYNTHETIC PLACEHOLDER" not in builder or "NOT MEASURED OR PHOTOGRAMMETRIC" not in builder:
        errors.append("synthetic geometry provenance label missing")
    if "SceneCullingPolicy.isVisible" not in types or "levelOfDetail" not in types or "pendingLODAssemblyIDs" not in adapter:
        errors.append("camera culling / LOD refresh contract missing")
    if "#if canImport(RealityKit) && canImport(UIKit)" not in adapter:
        errors.append("RealityKit adapter is not isolated behind platform availability")
    if "MeshDescriptor" not in adapter or "SceneMeshAccumulator" not in adapter:
        errors.append("per-material mesh batching path missing")
    if "SceneDensityPreset" not in types or "maxSceneryAssemblies" not in types or "detailLevel" not in types:
        errors.append("density presets and explicit scenery budget missing")
    if "SceneSurfaceWeather" not in types or "surfaceWeather: SceneSurfaceWeather = .dry" not in adapter:
        errors.append("optional wetness/snow material response API missing")
    if "sleeperSpacingM" not in builder or "trackSleeperSpacingM" in builder:
        errors.append("physical sleeper spacing is not sourced from the corridor specification")
    if "catenarySpacingM" not in builder or "density.catenarySpacingM" in builder:
        errors.append("physical catenary spacing is not sourced from corridor specification")
    for case in re.findall(r"^\s*case\s+(\w+)\s*$", re.search(r"public enum SceneMaterialStyle.*?\n}", types, re.S).group(0), re.M):
        if f"case .{case}:" not in adapter:
            errors.append(f"RealityKit material palette does not cover SceneMaterialStyle.{case}")
    for name in ["testHermiteRouteUsesChainageAndCurveTangents", "testBuilderCreatesDetailedTrackWiresAndSyntheticPlaceholderTags",
                 "testDensityChangesDetailBudgetWithoutChangingPhysicalSleeperCadence", "testCullingUsesViewFrustumAndDistanceAndLodBands",
                 "testSceneryCapDoesNotRemoveEssentialTrack", "testSurfaceWeatherNormalizesInputsAndHandlesNonFiniteValues",
                 "testLandmarkScheduleIsDeterministicAndSkipsPlatforms",
                 "testBuilderPlacesFictionalCorridorLandmarksAndClearsUrbanFabric",
                 "testLandmarkGeometrySurvivesZeroSceneryBudget",
                 "testLandmarkIdentityIsStableAcrossCameraWindows"]:
        if name not in tests:
            errors.append(f"unit test missing: {name}")

    source_root = ROOT / "Sources"
    for path in source_root.rglob("*.swift"):
        guard_depth = 0
        for line in path.read_text(encoding="utf-8").splitlines():
            stripped = line.strip()
            if stripped.startswith("#if canImport(RealityKit)"):
                guard_depth += 1
            elif stripped.startswith("#endif") and guard_depth > 0:
                guard_depth -= 1
            elif stripped == "import RealityKit" and guard_depth == 0:
                errors.append(f"RealityKit dependency leaked into portable core: {path.relative_to(ROOT)}")

    parser_status = "Tree-sitter Swift parser unavailable; syntax parse skipped"
    try:
        from tree_sitter import Language, Parser
        import tree_sitter_swift
        parser = Parser(Language(tree_sitter_swift.language()))
        syntax_files = list((ROOT / "Sources").rglob("*.swift")) + list((ROOT / "Tests").rglob("*.swift"))
        for path in syntax_files:
            data = path.read_bytes()
            tree = parser.parse(data)
            stack = [tree.root_node]
            while stack:
                node = stack.pop()
                if node.type == "ERROR" or node.is_missing:
                    excerpt = data[node.start_byte:min(node.end_byte, node.start_byte + 120)].decode("utf-8", errors="replace")
                    errors.append(f"Swift syntax parse issue in {path.relative_to(ROOT)} at {node.start_point}: {excerpt!r}")
                stack.extend(node.children)
        parser_status = f"Tree-sitter parsed {len(syntax_files)} Swift files"
    except ImportError:
        pass

    forbidden = [path for path in ROOT.rglob("*") if path.is_file()
                 and path.suffix.lower() in {".obj", ".fbx", ".blend", ".dae", ".gltf", ".glb", ".usdz", ".png", ".jpg", ".jpeg", ".tif", ".tiff"}]
    allowed_binary_assets: set[Path] = set()
    asset_root = ROOT / "Sources/RailwaySceneFidelity/Resources/Generated3D"
    manifest_path = asset_root / "asset_manifest.json"
    try:
        manifest = __import__("json").loads(manifest_path.read_text(encoding="utf-8"))
        allowed_binary_assets.update(asset_root / record["file"] for record in manifest.get("models", []))
    except Exception as exc:
        errors.append(f"generated 3D asset manifest is missing or invalid: {exc}")
    surface_license = ROOT / "Sources/RailwaySceneFidelity/Resources/ORIGINAL_SURFACE_LICENSE.md"
    if surface_license.is_file():
        allowed_binary_assets.update((ROOT / "Sources/RailwaySceneFidelity/Resources").glob("*.png"))
    unexpected = [path for path in forbidden if path not in allowed_binary_assets]
    missing = [path for path in allowed_binary_assets if not path.is_file()]
    if unexpected:
        errors.append("unlisted or unsupported bundled binary assets: " + ", ".join(str(p.relative_to(ROOT)) for p in unexpected))
    if missing:
        errors.append("manifest-listed generated model is missing: " + ", ".join(str(p.relative_to(ROOT)) for p in missing))

if errors:
    print("SCENE_FIDELITY_STATIC_VALIDATION: FAIL")
    for error in errors:
        print(f"- {error}")
    sys.exit(1)

swift_files = list((ROOT / "Sources").rglob("*.swift")) + list((ROOT / "Tests").rglob("*.swift"))
print("SCENE_FIDELITY_STATIC_VALIDATION: PASS")
print(f"Required files: {len(REQUIRED)}; Swift source/test files: {len(swift_files)}")
print(parser_status)
print("Checks: package isolation, chainage curve API, track/catenary/platform/scenery coverage, placeholder labels, density and physical spacing separation, RealityKit batching/culling/LOD, material coverage, test inventory, only manifest-listed generated GLBs and licensed procedural PNGs.")
print("This static check is not Swift type-checking, XCTest, Xcode/iOS SDK validation, or an iPhone performance measurement.")
