#!/usr/bin/env python3
"""Static checks for the iOS source package. This does not replace an Xcode build."""
from __future__ import annotations

import csv
import json
import re
import subprocess
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def fail(message: str) -> None:
    print(f"FAIL: {message}", file=sys.stderr)
    raise SystemExit(1)


def require(condition: bool, message: str) -> None:
    if not condition:
        fail(message)


try:
    from pbxproj import XcodeProject
    from tree_sitter import Language, Parser
    import tree_sitter_swift
except ImportError as exc:
    fail(
        "Missing optional static-check dependencies. Install them with: "
        "python3 -m pip install -r Scripts/requirements.txt "
        f"({exc})"
    )

# Parse every Swift file, including the local Swift packages and tests. Use a
# fresh parser per file to avoid native parser state accumulating on large trees.
swift_language = Language(tree_sitter_swift.language())
generated_dirs = {".build", "DerivedData", "xcuserdata", ".git", "__pycache__"}
swift_files = sorted(
    path for path in ROOT.rglob("*.swift")
    if not any(part in generated_dirs for part in path.relative_to(ROOT).parts)
)
require(bool(swift_files), "No Swift source files were found")
syntax_errors: list[str] = []
for source in swift_files:
    data = source.read_bytes()
    tree = Parser(swift_language).parse(data)
    if tree.root_node.has_error:
        pending = [tree.root_node]
        while pending:
            node = pending.pop()
            if node.is_error or node.is_missing:
                point = node.start_point
                syntax_errors.append(f"{source.relative_to(ROOT)}:{point.row + 1}:{point.column + 1}: {node.type}")
            pending.extend(node.children)
require(not syntax_errors, "Swift grammar errors:\n" + "\n".join(syntax_errors[:40]))

# Parse the Xcode project with an OpenStep plist parser, then check local references.
project_path = ROOT / "RailwayMasterPhase1.xcodeproj" / "project.pbxproj"
project = XcodeProject.load(str(project_path))
require(project is not None, "project.pbxproj could not be parsed")
raw_project = project_path.read_text(encoding="utf-8")
object_ids = re.findall(r"^\s*([A-F0-9]{24})\s*/\*.*?\*/\s*=", raw_project, re.M)
require(len(object_ids) == len(set(object_ids)), "Duplicate Xcode project object IDs found")
reference_ids = re.findall(
    r"\b(?:fileRef|productRef|package|target|targetProxy|buildConfigurationList|productReference)\s*=\s*([A-F0-9]{24})",
    raw_project,
)
missing_ids = sorted(set(reference_ids) - set(object_ids))
require(not missing_ids, f"Dangling Xcode project references: {missing_ids}")

target_names = {target.get("name", "") for target in project.objects.get_targets()}
require({"RailwayMasterPhase1", "RailwayMasterPhase1Tests"}.issubset(target_names), "Expected app and XCTest targets are missing")
for target in project.objects.get_targets():
    if target.get("name", "") == "RailwayMasterPhase1":
        require(len(target.get("packageProductDependencies", [])) == 20, "Expected twenty local package products on the full app target")
    elif target.get("name", "") == "RailwayMasterPhase1Tests":
        require(len(target.get("packageProductDependencies", [])) == 13, "Expected thirteen local package products on the XCTest target")

for name in [
    "SessionResultSheet.swift",
    "RegionalNetworkIntegration.swift",
    "RailwayAudioEngine.swift",
    "RegionalIntegrationTests.swift",
    "ScenarioProgressSheet.swift",
    "PackageIntegrationTests.swift",
]:
    require(name in raw_project, f"Xcode project does not reference {name}")
for directory in [ROOT / "RailwayMasterPhase1", ROOT / "RailwayMasterPhase1Tests"]:
    for source in directory.glob("*.swift"):
        require(source.name in raw_project, f"Xcode project does not reference {source.relative_to(ROOT)}")
for source in (ROOT / "RailwayMasterPhase1").glob("*.swift"):
    require(f"{source.name} in Sources" in raw_project, f"App source is not in the Sources build phase: {source.name}")
for resource in (ROOT / "RailwayMasterPhase1" / "Resources").glob("*.json"):
    require(resource.name in raw_project, f"Xcode project does not reference {resource.relative_to(ROOT)}")
for package_name in [
    "RailwayRouteData", "RailwaySignalling", "TrafficSimulation",
    "EnvironmentConditions", "RailwayMaintenance", "RailwayOperations",
    "RailwayRendering", "RailwayVehicleCab", "StopScoring", "RailwayTimetable",
    "TrainPhysics", "RailwayGameModes",
    "RailwaySessionPersistence", "DoorProcedureScoring",
    "RailwayAudioEnhancements", "CrewWorkflow", "IncidentMaintenance",
    "RailwaySceneFidelity", "RailwayVehicleHighFidelity", "ProtectionSystems",
]:
    package_dir = ROOT / "Packages" / package_name
    require((package_dir / "Package.swift").is_file(), f"Missing local Swift Package {package_name}")
    require(f"relativePath = Packages/{package_name};" in raw_project, f"Xcode package path is missing for {package_name}")

# Every SwiftPM local dependency path shipped in this tree must resolve inside the package root.
for package_manifest in ROOT.rglob("Package.swift"):
    manifest_text = package_manifest.read_text(encoding="utf-8")
    for dependency_path in re.findall(r"\.package\s*\(\s*path:\s*\"([^\"]+)\"", manifest_text):
        resolved_dependency = (package_manifest.parent / dependency_path).resolve()
        try:
            resolved_dependency.relative_to(ROOT.resolve())
        except ValueError:
            fail(f"SwiftPM local dependency escapes the distributed project: {package_manifest.relative_to(ROOT)} -> {dependency_path}")
        require(resolved_dependency.is_dir(), f"SwiftPM local dependency path is missing: {package_manifest.relative_to(ROOT)} -> {dependency_path}")
candidate_root = ROOT / "Prototypes" / "VehicleUVModelCandidate"
candidate_geometry = candidate_root / "GeometryUV"
for candidate_file in [
    candidate_geometry / "Package.swift",
    candidate_geometry / "Sources" / "VehicleGeometryUV" / "VehicleMeshData.swift",
    candidate_geometry / "Tests" / "VehicleGeometryUVTests" / "VehicleMeshDataTests.swift",
    candidate_root / "VehicleComponentModel.swift",
    candidate_root / "VehicleAuthoredMesh.swift",
    candidate_root / "VehicleComponentModelTests.swift",
]:
    require(candidate_file.is_file(), f"HF-01 candidate package source/test is missing: {candidate_file.relative_to(ROOT)}")
candidate_readme = (candidate_root / "README.md").read_text(encoding="utf-8")
candidate_status = (candidate_root / "INTEGRATION_STATUS.md").read_text(encoding="utf-8")
vehicle_package_manifest = (ROOT / "Packages" / "RailwayVehicleHighFidelity" / "Package.swift").read_text(encoding="utf-8")
require("../../Prototypes/VehicleUVModelCandidate/GeometryUV" in candidate_readme, "HF-01 dependency example must use the in-tree GeometryUV package")
documented_geometry_path = (ROOT / "Packages" / "RailwayVehicleHighFidelity" / "../../Prototypes/VehicleUVModelCandidate/GeometryUV").resolve()
require(documented_geometry_path == candidate_geometry.resolve() and documented_geometry_path.is_dir(), "HF-01 documented local dependency path must resolve inside the distributed project")
external_workstream_marker = "railway-" + "workstreams"
require(external_workstream_marker not in candidate_readme.lower() and external_workstream_marker not in candidate_status.lower(), "HF-01 docs must not point to an external workstream path")
require("配布ZIP外の作業領域を参照しません" in candidate_status, "HF-01 package must document its self-contained GeometryUV dependency")
require("VehicleGeometryUV" not in vehicle_package_manifest, "HF-01 must remain a separate, non-integrated vehicle prototype")

# Confirm the latest package APIs are connected to their host inputs. These are source checks, not type-checks.
scene_types = (ROOT / "Packages/RailwaySceneFidelity/Sources/RailwaySceneFidelity/SceneTypes.swift").read_text(encoding="utf-8")
scene_adapter = (ROOT / "Packages/RailwaySceneFidelity/Sources/RailwaySceneFidelity/RealityKitSceneAdapter.swift").read_text(encoding="utf-8")
scene_tests = (ROOT / "Packages/RailwaySceneFidelity/Tests/RailwaySceneFidelityTests/RailwaySceneFidelityTests.swift").read_text(encoding="utf-8")
vehicle_tests = (ROOT / "Packages/RailwayVehicleHighFidelity/Tests/RailwayVehicleHighFidelityTests/VehicleHighFidelityTests.swift").read_text(encoding="utf-8")
scene_host = (ROOT / "RailwayMasterPhase1/RailwaySceneView.swift").read_text(encoding="utf-8")
content_host = (ROOT / "RailwayMasterPhase1/ContentView.swift").read_text(encoding="utf-8")
require("public struct SceneSurfaceWeather" in scene_types, "SceneSurfaceWeather API is missing")
require("public func updateSurfaceWeather(_ weather: SceneSurfaceWeather)" in scene_adapter, "In-place weather material API is missing")
require("delta >= 0.05" in scene_adapter and "component.materials = [material]" in scene_adapter, "Weather material updates must be bounded and applied")
require("sceneFidelityAdapter.updateSurfaceWeather(SceneSurfaceWeather(" in scene_host, "Host environment blends are not connected to SceneFidelity weather")
require("surfaceWeather: sceneFidelityAdapter.surfaceWeather" in scene_host, "Streamed SceneFidelity builds must retain current weather")
require("func testSurfaceWeatherNormalizesInputsAndHandlesNonFiniteValues()" in scene_tests, "SceneSurfaceWeather range test is missing")
require("func testCabIndicatorStateControlsAllFictionalAnnunciatorLenses()" in vehicle_tests, "Vehicle indicator display test is missing")
require("model.animatedParts.setCabIndicatorState(vehicleCabIndicatorState)" in scene_host, "Vehicle cab indicator state is not applied by the host scene")
require("TrafficActorPoseSampler.sample(" in scene_host, "Host scene does not sample/interpolate traffic actor poses")
require("SceneTrafficActorProjector.project(" in scene_host, "Host scene does not project traffic actor poses onto its route")
require("trafficActorAdapter.update(poses: scenePoses)" in scene_host, "Snapshot-driven traffic poses are not sent to the RealityKit adapter")
require((ROOT / "Packages/TrafficSimulation/Tests/TrafficSimulationTests/TrafficActorPoseSamplerTests.swift").is_file(), "Traffic pose sampler tests are missing")
require((ROOT / "Packages/RailwaySceneFidelity/Tests/RailwaySceneFidelityTests/SceneTrafficActorTests.swift").is_file(), "Scene traffic actor projection tests are missing")
for indicator_input in [
    "emergencyBrakeActive: model.appliedDrivingControls.emergencyBrake",
    "doorsOpen: model.gameModeDoorState.isOpen",
    "tractionPowerActive: model.controls.throttleNotch > 0",
    "regenerativeBrakingActive: model.telemetry.regenerativeBrakeForceN > 0",
    "atspActive: model.protectionActingSystems.contains(\"atsP\")",
    "atcActive: model.protectionActingSystems.contains(\"atc\")",
    "faultActive: false",
]:
    require(indicator_input in content_host, f"Vehicle indicator mapping/disclaimer missing: {indicator_input}")
simulator_model = (ROOT / "RailwayMasterPhase1/SimulatorModel.swift").read_text(encoding="utf-8")
require("FictionalLiveProtectionSession" in simulator_model, "Live protection session is not stepped by the host")
require("protectionAdjustedControls" in simulator_model, "Protection brake command is not applied to the fixed physics tick")

# Check all distributable JSON metadata, excluding local build/cache artifacts.
json_files = sorted(
    path for path in ROOT.rglob("*.json")
    if not any(part in generated_dirs for part in path.relative_to(ROOT).parts)
)
require(bool(json_files), "No JSON files were found")
json_values: dict[Path, object] = {}
for path in json_files:
    try:
        json_values[path] = json.loads(path.read_text(encoding="utf-8"))
    except Exception as exc:
        fail(f"Invalid JSON in {path.relative_to(ROOT)}: {exc}")

bve_summary = json_values.get(ROOT / "Research" / "BVE" / "summary_final.json")
bve_inventory = json_values.get(ROOT / "Research" / "BVE" / "inventory_final.json")
bve_restricted = json_values.get(ROOT / "Research" / "BVE" / "restricted_sources.json")
bve_csv_path = ROOT / "Research" / "BVE" / "inventory_final.csv"
try:
    with bve_csv_path.open("r", encoding="utf-8-sig", newline="") as stream:
        bve_csv_inventory = list(csv.DictReader(stream))
except Exception as exc:
    fail(f"Unable to read final BVE CSV inventory: {exc}")
require(isinstance(bve_summary, dict), "Bundled BVE summary_final.json is missing")
require(isinstance(bve_inventory, list) and len(bve_inventory) == 137, "Bundled BVE inventory must contain 69 route and 68 vehicle records")
require(len(bve_csv_inventory) == 137, "Bundled BVE CSV inventory must contain 137 category records")
require(isinstance(bve_restricted, list) and len(bve_restricted) == 17, "Bundled BVE restricted-source register must contain 17 records")
require(bve_summary.get("no_network_access") is False, "BVE combined inventory must disclose the network-based additional research")
require(bve_summary.get("final_counts_are_archive_sha256_deduplicated") is True, "BVE counts must retain archive SHA-256 deduplication disclosure")
for category, expected in (("route", 69), ("vehicle", 68)):
    json_rows = [record for record in bve_inventory if record.get("category") == category]
    csv_rows = [record for record in bve_csv_inventory if record.get("category") == category]
    require(len(json_rows) == expected and len(csv_rows) == expected, f"BVE {category} inventory count must be {expected}")
    json_hashes = [str(record.get("sha256", "")).lower() for record in json_rows]
    csv_hashes = [str(record.get("sha256", "")).lower() for record in csv_rows]
    require(len(json_hashes) == len(set(json_hashes)), f"BVE {category} JSON inventory has duplicate archive SHA-256")
    require(len(csv_hashes) == len(set(csv_hashes)), f"BVE {category} CSV inventory has duplicate archive SHA-256")
    require(set(json_hashes) == set(csv_hashes), f"BVE {category} CSV and JSON archive hashes differ")
require(bve_summary["summary"]["route"]["package_count"] == 69, "BVE route summary count must be 69")
require(bve_summary["summary"]["vehicle"]["package_count"] == 68, "BVE vehicle summary count must be 68")
require(bve_summary["requested_target"]["route_shortfall"] == 31 and bve_summary["requested_target"]["vehicle_shortfall"] == 32, "BVE inventory shortfalls must be 31/32")
require(bve_summary["unique_archive_counts_across_categories"]["shared_hashes_across_categories"] == 10, "BVE shared archive hash count must be 10")
require(bve_summary["unique_archive_counts_across_categories"]["global_unique_archive_sha256_count"] == 127, "BVE global archive hash count must be 127")
require(bve_summary["additional_research"]["new_static_text_configuration_files_inspected"] == 541, "BVE latest static text inspection count must remain 541")
require("separate earlier audio sample review" in bve_summary["additional_research"]["earlier_audio_sample_review_audit_caveat"], "BVE audio-review audit caveat must be retained")
for research_file in [
    "RESEARCH_PLATFORM_DISTRIBUTION.md",
    "ASSET_LICENSE_RESEARCH.md",
    "VEHICLE_DATA_AND_LICENSE_INVENTORY.md",
    "Research/BVE_RESEARCH_SUMMARY.md",
    "Research/BVE_RESEARCH_SOURCES_AND_LIMITATIONS.md",
    "Research/BVE/inventory_final.csv",
    "Research/BVE/additional/report.md",
    "Research/BVE/additional/source_screening_round3.md",
    "Research/BVE/additional/source_screening_round4.md",
    "Research/BVE/additional/text_config_inspection_round3.json",
    "Research/BVE/additional/build_inventory_summary.py",
    "Research/RealRouteReference/README.md",
    "Research/RealRouteReference/LICENSES.md",
    "Research/RealRouteReference/QUALITY_REPORT.md",
    "Research/RealRouteExpansion/README.md",
    "Research/RealRouteExpansion/LICENSES.md",
    "Research/RealRouteExpansion/QUALITY_REPORT.md",
    "Research/RealRouteExpansion/Tests/validation-report.json",
    "Prototypes/VehicleUVModelCandidate/INTEGRATION_STATUS.md",
    "Packages/RailwaySceneFidelity/Scripts/validate_scene_fidelity.py",
    "Scripts/generate_4platform_station_glb.py",
    "Scripts/validate_generated_3d_assets.py",
    "PACKAGE_INVENTORY.md",
    "Scripts/generate_package_inventory.py",
    "Scripts/verify_package_zip.py",
]:
    require((ROOT / research_file).is_file(), f"Missing bundled research artifact: {research_file}")
bve_summary_markdown = (ROOT / "Research" / "BVE_RESEARCH_SUMMARY.md").read_text(encoding="utf-8")
require("最終のメタデータ台帳は、路線69パッケージ、車両68パッケージ" in bve_summary_markdown, "BVE summary must identify the final 69/68 inventory")
require("履歴スナップショット](BVE/additional/inventory_baseline_63_58.csv)" in bve_summary_markdown, "BVE summary must preserve the earlier 63/58 baseline snapshot")
require("独立した手順逸脱" in bve_summary_markdown, "BVE summary must preserve the separate audio-review audit caveat")
bve_report = (ROOT / "Research" / "BVE" / "additional" / "report.md").read_text(encoding="utf-8")
require("独立した手順逸脱" in bve_report, "BVE final report must retain the separate audio-review audit caveat")

real_route_path = ROOT / "Research" / "RealRouteReference" / "Data" / "route-package.json"
real_route_package = json_values.get(real_route_path)
require(isinstance(real_route_package, dict), "Real-route reference package is missing")
real_route = real_route_package.get("route", {})
require(real_route.get("routeID") == "kintetsu_kyoto_line_kyoto_toji", "Unexpected real-route reference identity")
require(abs(real_route.get("totalLengthM", {}).get("value", 0) - 801.5) < 0.05, "Real-route reference estimate changed")
require(real_route.get("totalLengthM", {}).get("status") == "ESTIMATED", "Real-route distance must stay marked ESTIMATED")
require(real_route.get("networkLengthM", {}).get("status") == "UNKNOWN", "Real-route physical network length must remain UNKNOWN")
require(real_route.get("officialCommercialDistanceM", {}).get("status") == "UNKNOWN", "Real-route commercial distance must remain UNKNOWN")
require("CC BY 4.0" in real_route_package["sources"][0]["license"], "Real-route reference must retain its CC BY 4.0 attribution")
require(len(real_route["tracks"][0]["geometry"]) == 16 and len(real_route["stations"]) == 2, "Real-route reference geometry/station feature count changed")

expanded_route_validator = ROOT / "Research" / "RealRouteExpansion" / "Tools" / "validate_route_package.py"
expanded_route_check = subprocess.run(
    [sys.executable, str(expanded_route_validator)],
    cwd=expanded_route_validator.parent.parent,
    capture_output=True,
    text=True,
)
if expanded_route_check.returncode != 0:
    fail(expanded_route_check.stderr.strip() or expanded_route_check.stdout.strip() or "Expanded real-route reference validation failed")
expanded_route_report = json.loads(expanded_route_check.stdout)
require(expanded_route_report.get("status") == "PASS", "Expanded real-route reference did not report PASS")
require(expanded_route_report.get("routeFeatureCount") == 52 and expanded_route_report.get("stationCount") == 26 and expanded_route_report.get("vertexCount") == 466, "Expanded route feature counts changed")
require(abs(expanded_route_report.get("routeReferenceLineLengthM", 0) - 35_140.556) < 0.005, "Expanded route reference length changed")
print("PASS: expanded real-route reference: 52 segments / 26 stations / 466 vertices; 35,140.556 m ESTIMATED; operational fields UNKNOWN")

route_path = ROOT / "RailwayMasterPhase1" / "Resources" / "FictionalRegionalMainline.json"
route = json_values.get(route_path)
require(isinstance(route, dict), "FictionalRegionalMainline.json is missing")
route_info = route["route"]
segments = route["segments"]
require(route_info["dataStatus"] == "PLACEHOLDER", "Playable route must remain explicitly PLACEHOLDER")
require(abs(route_info["routeLengthM"] - 60_000) < 0.01, "Full mainline fallback must remain 60 km")
require(segments and abs(segments[0]["distanceM"] - 60_000) < 0.01, "Fallback segment must cover the complete 60 km mainline")
require(len(route["stations"]) == 28, "Full mainline fallback must include all 28 mainline stations")
require(abs(sum(segment["distanceM"] for segment in segments) - route_info["routeLengthM"]) < 0.01, "Full route segment lengths do not sum to the package length")
for previous, current in zip(segments, segments[1:]):
    require(abs(previous["endChainageM"] - current["startChainageM"]) < 0.01, "Route segment chainage is discontinuous")
for station in route["stations"]:
    for platform in station["platforms"]:
        require(
            abs(platform["lengthM"] - (platform["endChainageM"] - platform["startChainageM"])) < 0.01,
            f"Platform length disagrees with its chainage range: {platform['platformId']}",
        )

plan_path = ROOT / "RailwayMasterPhase1" / "Resources" / "FictionalOperationsPlan.json"
plan = json_values.get(plan_path)
require(isinstance(plan, dict), "FictionalOperationsPlan.json is missing")
network = plan["network"]
require(
    abs(network["mainlineLengthKm"] - 60) < 0.001
    and abs(network["branchLengthKm"] - 8) < 0.001
    and abs(network["depotSpurLengthKm"] - 2) < 0.001,
    "Canonical regional network must remain 60+8+2 km",
)
require(len(plan["stations"]) == 32, "Canonical regional network station count changed unexpectedly")
require(len(plan["services"]) == 6, "Canonical regional service-category count changed unexpectedly")
require(len(plan["timetablePatterns"]) == 48, "Expected 6 categories × 2 directions × 4 dayparts")
require(all(station["dataStatus"] == "PLACEHOLDER" for station in plan["stations"]), "Every canonical station must remain marked PLACEHOLDER")
require("架空" in plan["disclaimer"] and "PLACEHOLDER" in plan["disclaimer"], "Station names and operating data must remain explicitly fictional PLACEHOLDER data")
services_by_category = {service["category"]: service for service in plan["services"]}
rapid_stops = services_by_category["rapid"]["stopStationIDs"]
express_stops = services_by_category["express"]["stopStationIDs"]
require(rapid_stops != express_stops, "Rapid and express must have distinct stop patterns")
require(express_stops[0] == rapid_stops[0] == network["mainlineTermini"][0], "Rapid/express must share the passenger route origin")
require(express_stops[-1] == rapid_stops[-1] == network["branchTerminalStationID"], "Rapid/express must share the branch passenger-route terminus")
require(set(express_stops).issubset(set(rapid_stops)), "Express stops should be a strict subset of rapid stops")
require(express_stops != rapid_stops and len(express_stops) < len(rapid_stops), "Express should be faster-stopping than rapid")
require([station_id for station_id in express_stops if station_id in {"S28", "B02", "B04"}] == ["S28", "B02", "B04"], "Express must retain the branch junction, branch stop, and branch terminus")
require(all(station_id in {station["stationId"] for station in plan["stations"]} for station_id in rapid_stops + express_stops), "Service stop IDs must reference canonical stations")

# Service hierarchy (2026-11-07 fix): rank order is
# limitedExpress > rapidExpress > express > rapid > semiExpress > local.
# Stop counts and planned durations must both strictly increase in that
# order, every service must run the same through passenger route
# (origin = mainline terminus, terminus = branch terminal), and every
# stop list must follow the canonical through-route station order
# (the local service's stop list).
hierarchy_order = ["limitedExpress", "rapidExpress", "express", "rapid", "semiExpress", "local"]
require(set(hierarchy_order) == set(services_by_category), "Service hierarchy must cover exactly the six canonical categories")
hierarchy_services = [services_by_category[category] for category in hierarchy_order]
through_route_order = services_by_category["local"]["stopStationIDs"]
through_route_index = {station_id: index for index, station_id in enumerate(through_route_order)}
for service in hierarchy_services:
    stops = service["stopStationIDs"]
    require(stops[0] == network["mainlineTermini"][0], f"{service['category']} must start at the passenger route origin")
    require(stops[-1] == network["branchTerminalStationID"], f"{service['category']} must end at the branch terminal")
    require(all(station_id in through_route_index for station_id in stops), f"{service['category']} stops must reference canonical stations")
    require([through_route_index[station_id] for station_id in stops] == sorted(through_route_index[station_id] for station_id in stops), f"{service['category']} stops must follow the through-route order")
    require(len(set(stops)) == len(stops), f"{service['category']} stops must not contain duplicates")
for faster, slower in zip(hierarchy_services, hierarchy_services[1:]):
    require(len(faster["stopStationIDs"]) < len(slower["stopStationIDs"]), f"Stop counts must strictly increase down the hierarchy: {faster['category']} < {slower['category']}")
    require(faster["plannedDurationMinutes"] < slower["plannedDurationMinutes"], f"Planned durations must strictly increase down the hierarchy: {faster['category']} < {slower['category']}")
require(services_by_category["rapidExpress"]["stopStationIDs"] == ["S01", "S11", "S16", "S21", "S26", "S28", "B04"], "Rapid express stop pattern changed unexpectedly")
require(express_stops == ["S01", "S07", "S12", "S16", "S20", "S24", "S28", "B02", "B04"], "Express stop pattern changed unexpectedly")
print("PASS: service hierarchy stop counts and durations strictly increase: limitedExpress 5/60, rapidExpress 7/80, express 9/100, rapid 11/125, semiExpress 17/140, local 32/150")

route_data_path = ROOT / "Packages" / "RailwayRouteData" / "Data" / "fictional_70km_network.json"
route_package = json_values.get(route_data_path)
require(isinstance(route_package, dict), "Canonical RouteData package is missing")
route_data = route_package["route"]
require(abs(route_data["totalLengthM"]["value"] - 60_000) < 0.01, "RouteData mainline must match 60 km")
require(abs(route_data["networkLengthM"]["value"] - 70_000) < 0.01, "RouteData physical network must match 70 km")
track_extents = {}
for track in route_data["tracks"]:
    segments_for_track = track["segments"]
    track_extents[track["trackID"]] = max(item["endChainageM"]["value"] for item in segments_for_track) - min(item["startChainageM"]["value"] for item in segments_for_track)
require({key: round(value, 2) for key, value in track_extents.items()} == {"main_line": 60_000, "branch_line": 8_000, "depot_spur": 2_000}, "RouteData track extents must be 60+8+2 km")
require(abs(sum(track_extents.values()) - route_data["networkLengthM"]["value"]) < 0.01, "RouteData track extents do not sum to the network length")
require(len(route_data["stations"]) == len(plan["stations"]) == 32, "RouteData and operations plan must both contain 32 stations")
plan_stations = {station["stationId"]: station for station in plan["stations"]}
route_stations = {station["stationID"]: station for station in route_data["stations"]}
require(set(plan_stations) == set(route_stations), "RouteData station IDs differ from the operations plan")
for station_id, station in plan_stations.items():
    route_station = route_stations[station_id]
    require(route_station["name"]["value"] == station["name"], f"Station name mismatch for {station_id}")
    require(abs(route_station["chainageM"]["value"] - station["chainageKm"] * 1_000) < 0.01, f"Station chainage mismatch for {station_id}")
    expected_track = "main_line" if station["lineId"] == "MAIN" else "branch_line"
    require(route_station["trackIDs"] == [expected_track], f"Station track mismatch for {station_id}")
    for platform in route_station["platforms"]:
        require(abs(platform["lengthM"]["value"] - (platform["endChainageM"]["value"] - platform["startChainageM"]["value"])) < 0.01, f"Platform chainage mismatch for {station_id}")

fallback_stations = {station["stationId"]: station for station in route["stations"]}
mainline_stations = {station_id: station for station_id, station in plan_stations.items() if station["lineId"] == network["mainlineID"]}
require(set(fallback_stations) == set(mainline_stations), "Mainline fallback station IDs differ from the canonical plan")
for station_id, station in mainline_stations.items():
    require(fallback_stations[station_id]["name"] == station["name"], f"Fallback route station name mismatch for {station_id}")
    require(abs(fallback_stations[station_id]["chainageM"] - station["chainageKm"] * 1_000) < 0.01, f"Fallback route chainage mismatch for {station_id}")

layout_path = ROOT / "Packages" / "RailwaySceneFidelity" / "Sources" / "RailwaySceneFidelity" / "Resources" / "Generated3D" / "station_layouts_32.json"
station_layouts = json_values.get(layout_path)
require(isinstance(station_layouts, dict) and len(station_layouts.get("stations", [])) == 32, "Generated station layout manifest must include all 32 stations")
layout_by_id = {station["stationId"]: station for station in station_layouts["stations"]}
require(set(layout_by_id) == set(plan_stations), "Generated station layout IDs differ from the canonical plan")
for station_id, station in plan_stations.items():
    layout_station = layout_by_id[station_id]
    require(layout_station["name"] == station["name"], f"Generated station layout name mismatch for {station_id}")
    require(abs(layout_station["chainageM"] - station["chainageKm"] * 1_000) < 0.01, f"Generated station layout chainage mismatch for {station_id}")

# Verify every route variant × service × direction can be represented as an
# ordered stop sequence by the same rules used by RegionalRouteFactory.
stations_by_id = {station["stationId"]: station for station in plan["stations"]}
mainline_id = network["mainlineID"]
branch_id = network["branchID"]
mainline_length_m = network["mainlineLengthKm"] * 1_000
branch_length_m = network["branchLengthKm"] * 1_000
depot_length_m = network["depotSpurLengthKm"] * 1_000
branch_stations = sorted(
    (station for station in plan["stations"] if station["lineId"] == branch_id),
    key=lambda station: station["chainageKm"],
)
route_combinations = 0
for service in plan["services"]:
    for variant in ("mainline", "throughBranch", "branchShuttle", "depotTransfer"):
        if variant == "mainline":
            ids = [station_id for station_id in service["stopStationIDs"] if stations_by_id[station_id]["lineId"] == mainline_id]
            route_length = mainline_length_m
        elif variant == "throughBranch":
            ids = list(service["stopStationIDs"])
            route_length = mainline_length_m + branch_length_m
        elif variant == "branchShuttle":
            ids = [network["branchJunctionStationID"]] + [
                station["stationId"] for station in branch_stations
                if station["stationId"] in service["stopStationIDs"]
            ]
            route_length = branch_length_m
        else:
            ids = [network["depotStationID"], "DEPOT_END"]
            route_length = depot_length_m
        for direction in ("up", "down"):
            ordered_ids = ids if direction == "up" else list(reversed(ids))
            positions = []
            for station_id in ordered_ids:
                if station_id == "DEPOT_END":
                    raw_position = depot_length_m
                else:
                    station = stations_by_id[station_id]
                    if variant == "throughBranch" and station["lineId"] == branch_id:
                        raw_position = mainline_length_m + station["chainageKm"] * 1_000
                    elif variant == "branchShuttle" and station["lineId"] == mainline_id:
                        raw_position = 0.0
                    else:
                        raw_position = station["chainageKm"] * 1_000
                positions.append(raw_position if direction == "up" else route_length - raw_position)
            require(len(positions) >= 2, f"Route has fewer than two stops: {variant}/{service['category']}/{direction}")
            require(abs(positions[0]) < 0.01 and abs(positions[-1] - route_length) < 0.01,
                    f"Route endpoints do not match its length: {variant}/{service['category']}/{direction}")
            require(all(left < right for left, right in zip(positions, positions[1:])),
                    f"Stop chainage is not strictly increasing: {variant}/{service['category']}/{direction}")
            route_combinations += 1
require(route_combinations == 48, f"Expected 48 playable route combinations, found {route_combinations}")

traffic_path = ROOT / "Packages" / "TrafficSimulation" / "Sources" / "TrafficSimulation" / "Resources" / "FictionalRegionalNetwork.json"
traffic = json_values.get(traffic_path)
require(isinstance(traffic, dict), "FictionalRegionalNetwork.json is missing")
traffic_paths = traffic["routePaths"]
require(abs(sum(item["lengthM"] for item in traffic_paths) - 70_000) < 0.01, "Regional traffic path lengths must sum to 70 km")
require(abs(traffic["routeLengthM"] - 60_000) < 0.01, "Traffic shared mainline length must remain 60 km")

scene_host_path = ROOT / "RailwayMasterPhase1" / "RailwaySceneView.swift"
scene_host_source = scene_host_path.read_text(encoding="utf-8")
require("import RailwaySceneFidelity" in scene_host_source, "The high-quality scene adapter is not imported by the app")
require("import RailwayVehicleHighFidelity" in scene_host_source, "The fictional vehicle module is not imported by the scene adapter")
require("RailwayVehicleHighFidelityBuilder.build" in scene_host_source, "The detailed fictional lead vehicle is not built by the scene adapter")
require("trackGaugeM: route.trackGaugeMm / 1_000" in scene_host_source, "High-quality scene gauge must follow the selected route profile")
require("commuterCarDetailed" in scene_host_source and "driverCabInteriorDetailed" in scene_host_source,
        "Selected detailed car/cab GLBs are not connected to the high-quality scene")
require("simd_quatf(angle: -Float.pi / 2" in scene_host_source,
        "Selected Z-up car/cab assets do not have an explicit conversion to the app's Y-up frame")
route_factory_source = (ROOT / "RailwayMasterPhase1" / "RegionalRouteFactory.swift").read_text(encoding="utf-8")
for route_marker in [
    "SplitMix64(seed: geometrySeed ^ region.seedSalt)",
    "curveTransition: run?.transition",
    "curveTransition: section.curveTransition?.reversed(over: lengthM)",
    "struct RegionalRouteGeometrySample",
    "static func makeSamples(route: RailwayRouteProfile, interval: Double)",
    "radiusRange: 900...1_850",
    "radiusRange: 450...900",
    "radiusRange: 450...650",
]:
    require(route_marker in route_factory_source, f"Seeded route geometry marker missing: {route_marker}")
require("RegionalRouteGeometrySampler.makeSamples(route: route, interval: interval)" in scene_host_source,
        "The host scene does not use the tested shared route sampler")
regional_tests_source = (ROOT / "RailwayMasterPhase1Tests" / "RegionalIntegrationTests.swift").read_text(encoding="utf-8")
require("testSeededPolylineSamplerProducesConnectedFinitePointsAndContinuousFrames" in regional_tests_source,
        "Route polyline connectivity test is missing")
protection_host_source = (ROOT / "RailwayMasterPhase1" / "RegionalNetworkIntegration.swift").read_text(encoding="utf-8")
require("import ProtectionSystems" in protection_host_source and "makeProtectionSystemsDemo" in protection_host_source,
        "The separate fictional ProtectionSystems demo is not connected to the regional audit adapter")

# Count XCTest methods without executing them; Xcode is required to run the tests.
test_files = list((ROOT / "RailwayMasterPhase1Tests").glob("*.swift"))
test_source = "\n".join(path.read_text(encoding="utf-8") for path in test_files)
test_count = len(re.findall(r"\bfunc\s+test[A-Za-z0-9_]*\s*\(", test_source))
require(test_count == 43, f"Expected 43 XCTest methods, found {test_count}")

scheme = ROOT / "RailwayMasterPhase1.xcodeproj" / "xcshareddata" / "xcschemes" / "RailwayMasterPhase1.xcscheme"
ET.parse(scheme)

print(f"PASS: Swift grammar: {len(swift_files)} files")
app_source_count = len(list((ROOT / "RailwayMasterPhase1").glob("*.swift")))
print(f"PASS: Xcode project parser: {len(object_ids)} unique objects; all {app_source_count} app sources linked; 20 app / 13 test package products")
print("PASS: SceneSurfaceWeather host/material connection and visual-only cab indicators with covered API tests")
print(f"PASS: JSON resources: {len(json_files)} files")
print("PASS: bundled BVE inventory metadata: 69 route / 68 vehicle; 10 cross-category shared hashes / 127 unique archive hashes; 541 latest-round static text configs; rights and separate audio-review audit caveat retained")
print("PASS: real-route reference: 16 vertices / 2 station lines; 801.5 m ESTIMATED; physical/commercial lengths UNKNOWN; CC BY 4.0 retained")
generated_assets_check = subprocess.run(
    [sys.executable, str(ROOT / "Scripts" / "validate_generated_3d_assets.py")],
    cwd=ROOT,
    capture_output=True,
    text=True,
)
if generated_assets_check.returncode != 0:
    fail(generated_assets_check.stderr.strip() or generated_assets_check.stdout.strip() or "Generated 3D asset validation failed")
print(generated_assets_check.stdout.strip())
scene_fidelity_check = subprocess.run(
    [sys.executable, str(ROOT / "Packages" / "RailwaySceneFidelity" / "Scripts" / "validate_scene_fidelity.py")],
    cwd=ROOT,
    capture_output=True,
    text=True,
)
if scene_fidelity_check.returncode != 0:
    fail(scene_fidelity_check.stderr.strip() or scene_fidelity_check.stdout.strip() or "SceneFidelity static validation failed")
print(scene_fidelity_check.stdout.strip())
inventory_check = subprocess.run(
    [sys.executable, str(ROOT / "Scripts" / "generate_package_inventory.py"), "--check"],
    cwd=ROOT,
    capture_output=True,
    text=True,
)
if inventory_check.returncode != 0:
    fail(inventory_check.stderr.strip() or inventory_check.stdout.strip() or "Package inventory is stale")
print(inventory_check.stdout.strip())
release_zip = ROOT.parent / f"{ROOT.name}.zip"
if release_zip.is_file():
    zip_check = subprocess.run(
        [sys.executable, str(ROOT / "Scripts" / "verify_package_zip.py"), str(release_zip)],
        cwd=ROOT,
        capture_output=True,
        text=True,
    )
    if zip_check.returncode != 0:
        fail(zip_check.stderr.strip() or zip_check.stdout.strip() or "Release ZIP is stale or invalid")
    print(zip_check.stdout.strip())
else:
    print("NOTE: adjacent release ZIP absent; run Scripts/verify_package_zip.py <archive> after packaging")
print("PASS: canonical operations + RouteData + signalling test + traffic network (60+8+2 km, 32 stations)")
print("PASS: fictional station names synchronized across operations, fallback, RouteData, and 3D layouts; rapid/express patterns distinct and nested")
print(f"PASS: all {route_combinations} route variant/service/direction combinations have ordered endpoints")
print(f"PASS: app-host XCTest source inventory: {test_count} methods (counted only; not executed by this static checker)")
print("NOTE: This static script does not type-check Swift, build the iOS app, or execute app-host XCTest. The previously recorded SwiftPM matrix predates the current station/service revision; XCTest source methods are counted only and are not run here. No Swift/Xcode or iOS host execution is available in this environment. This script also does not launch Simulator, sign, or test hardware.")
