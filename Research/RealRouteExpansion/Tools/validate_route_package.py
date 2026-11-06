#!/usr/bin/env python3
"""Validate the isolated N02-25 route-reference package."""
from __future__ import annotations

import json
import math
import sys
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "Tools"))
from build_route_package import EXPECTED_SHA256, SOURCE_ID, grs80_inverse_m  # noqa: E402

DATA = ROOT / "Data"
PACKAGE = json.loads((DATA / "route-package.json").read_text(encoding="utf-8"))
GEOMETRY = json.loads((DATA / "route_geometry.geojson").read_text(encoding="utf-8"))
SEGMENTS = json.loads((DATA / "route_segments.geojson").read_text(encoding="utf-8"))
MANIFEST = json.loads((DATA / "source_manifest.json").read_text(encoding="utf-8"))


def require(condition: bool, message: str) -> None:
    if not condition:
        raise AssertionError(message)


def point_key(coord: list[float]) -> tuple[float, float]:
    return (round(float(coord[0]), 7), round(float(coord[1]), 7))


def validate() -> dict[str, Any]:
    route = PACKAGE["route"]
    require(PACKAGE["schemaVersion"] == "1.0.0", "Unexpected package schema")
    require(PACKAGE["datasetKind"] == "REAL_WORLD_REFERENCE_ONLY", "Package must remain reference-only")
    require(PACKAGE["notForDrivingPhysicsOrSignalling"] is True, "Safety/integration guard is missing")
    require(PACKAGE["sources"][0]["sourceID"] == SOURCE_ID, "Source ID mismatch")
    require(PACKAGE["sources"][0]["sourceArchiveSHA256"] == EXPECTED_SHA256, "Pinned archive hash mismatch")
    require(MANIFEST["dataset"]["sourceArchiveSHA256"] == EXPECTED_SHA256, "Manifest archive hash mismatch")
    require(MANIFEST["dataset"]["coordinateReferenceSystem"] == "JGD2011 / (B, L)", "CRS mismatch")
    require(MANIFEST["dataset"]["geoJSONCoordinateOrder"] == "[longitude, latitude]", "Coordinate order mismatch")
    require(MANIFEST["dataset"]["coordinateTransformation"].startswith("None"), "Unexpected coordinate transformation")
    require("CC BY 4.0" in MANIFEST["dataset"]["license"], "License not recorded")
    require(MANIFEST["dataset"]["retrievedAt"] == PACKAGE["sources"][0]["retrievedAt"], "Retrieval date mismatch")
    provenance = PACKAGE["fieldProvenance"]
    required_provenance = {
        "packageLocalIdentifier", "routeNameOperatorAndClass", "stationNamesAndDatasetCodes",
        "extractedFeatureAndVertexCounts", "sourceRecordIndices",
        "routeCoordinates", "stationLineGeometry", "segmentOrientationAndContinuity",
        "localVertexChainageAndReferenceLength", "stationOrderReferenceMeasure",
        "operationalAndTrackEngineeringFields",
    }
    require(set(provenance) == required_provenance, "Field provenance coverage is incomplete")
    allowed_statuses = {"VERIFIED", "MEASURED", "ESTIMATED", "PLACEHOLDER", "UNKNOWN"}
    allowed_confidence = {"HIGH", "MEDIUM", "LOW", "UNRATED"}
    for name, item in provenance.items():
        require(item["status"] in allowed_statuses, f"Invalid provenance status for {name}")
        require(item["confidence"] in allowed_confidence, f"Invalid confidence for {name}")
        require(isinstance(item.get("note"), str) and item["note"], f"Provenance note missing for {name}")
    require(provenance["operationalAndTrackEngineeringFields"]["status"] == "UNKNOWN", "Operational provenance must be UNKNOWN")
    require(provenance["localVertexChainageAndReferenceLength"]["status"] == "ESTIMATED", "Derived route measures must be ESTIMATED")

    features = GEOMETRY["features"]
    route_features = [f for f in features if f["properties"].get("featureRole") == "CONTINUOUS_ROUTE_REFERENCE_LINE_NOT_PHYSICAL_TRACK_CENTERLINE"]
    station_features = [f for f in features if f["properties"].get("featureRole") == "SOURCE_STATION_LINE_NOT_CENTER_POINT_OR_PLATFORM"]
    require(len(route_features) == 1, "Expected exactly one continuous route reference line")
    route_feature = route_features[0]
    route_coords = route_feature["geometry"]["coordinates"]
    route_props = route_feature["properties"]
    measures = route_props["vertexChainageM"]
    require(len(route_coords) == len(measures), "Each route vertex must have a local measure")
    require(route_props["vertexChainageStatus"] == "ESTIMATED", "Vertex chainage must be marked estimated")
    require(route_props["physicalTrackCenterline"] == "UNKNOWN", "Physical track centerline must remain unknown")
    require(route_props["chainageUnit"] == "m", "Route measures must declare metres")
    require(len(route_coords) == route["routeVertexCount"], "Vertex count mismatch")
    require(len(station_features) == route["stationCount"] == 26, "Expected 26 source station lines")
    require(len(SEGMENTS["features"]) == route["sourceRouteFeatureCount"] == 52, "Expected 52 source route segments")

    def check_coords(coords: list[list[float]], context: str) -> None:
        require(len(coords) >= 2, f"Too few coordinates in {context}")
        for coord in coords:
            require(len(coord) >= 2, f"Malformed coordinate in {context}")
            lon, lat = float(coord[0]), float(coord[1])
            require(math.isfinite(lon) and math.isfinite(lat), f"Non-finite coordinate in {context}")
            require(-180 <= lon <= 180 and -90 <= lat <= 90, f"Invalid coordinate range in {context}: {coord}")
        require(all(point_key(a) != point_key(b) for a, b in zip(coords, coords[1:])), f"Adjacent duplicate coordinate in {context}")

    check_coords(route_coords, "continuous route")
    require(len({point_key(c) for c in route_coords}) == len(route_coords), "Unexpected duplicate route coordinate")
    require(measures[0] == 0.0, "Route measure must start at zero")
    require(all(a < b for a, b in zip(measures, measures[1:])), "Route measures must strictly increase")
    recomputed = [0.0]
    gaps = []
    for a, b in zip(route_coords, route_coords[1:]):
        gap = grs80_inverse_m(a, b)
        require(gap > 0, "Zero-length route edge")
        gaps.append(gap)
        recomputed.append(recomputed[-1] + gap)
    require(abs(recomputed[-1] - measures[-1]) <= 0.005, "Final vertex chainage does not match GRS80 recomputation")
    require(abs(route["routeReferenceLineLengthM"]["value"] - measures[-1]) <= 0.005, "Route length does not match final measure")
    require(route["routeReferenceLineLengthM"]["status"] == "ESTIMATED", "Route length status must remain estimated")
    require(len(route_coords) >= 400 and measures[-1] > 10_000, "Corridor is not materially longer than the short reference")

    segment_features = SEGMENTS["features"]
    require([f["properties"]["routeOrder"] for f in segment_features] == list(range(1, len(segment_features) + 1)), "Segment order must be contiguous")
    reconstructed: list[list[float]] = []
    indices = []
    for feature in segment_features:
        props = feature["properties"]
        coords = feature["geometry"]["coordinates"]
        check_coords(coords, feature["id"])
        require(props["sourceID"] == SOURCE_ID, "Segment source ID missing")
        require(isinstance(props.get("sourceRecordIndex"), int), "Segment source record index missing")
        require(props["featureRole"] == "ROUTE_REFERENCE_LINE_SEGMENT_NOT_PHYSICAL_TRACK_CENTERLINE", "Segment role is misleading")
        indices.append(props["sourceRecordIndex"])
        if reconstructed:
            require(point_key(reconstructed[-1]) == point_key(coords[0]), "Discontinuous route segment endpoints")
            reconstructed.extend(coords[1:])
        else:
            reconstructed.extend(coords)
    require(len(indices) == len(set(indices)), "Duplicate source route record index")
    require(indices == MANIFEST["extraction"]["routeSourceRecordIndices"], "Segment source indices differ from manifest")
    require(len(reconstructed) == len(route_coords), "Reconstructed route vertex count differs")
    require(all(point_key(a) == point_key(b) for a, b in zip(reconstructed, route_coords)), "Segments do not reconstruct the published route line")

    stations = route["stations"]
    require(len(stations) == len(station_features), "Package station count mismatch")
    station_features_by_id = {f["id"]: f for f in station_features}
    station_names = []
    station_source_indices = []
    station_measures = []
    for index, station in enumerate(stations, start=1):
        require(station["routeOrder"] == index, "Station route order is not contiguous")
        require(station["name"]["status"] == "VERIFIED" and station["name"]["sourceIDs"] == [SOURCE_ID], "Station name provenance missing")
        require(station["stationCode"]["status"] == "VERIFIED", "Station-code provenance missing")
        measure = station["routeOrderReferencePositionM"]
        require(measure["status"] == "ESTIMATED" and measure["sourceIDs"] == [SOURCE_ID], "Station ordering measure must be sourced and estimated")
        require("not a station-center" in measure["note"], "Station measure must not be represented as a station center")
        station_names.append(station["name"]["value"])
        station_measures.append(measure["value"])
        sid = station["sourceGeometry"]["featureID"]
        require(sid in station_features_by_id, "Source station geometry feature missing")
        feature = station_features_by_id[sid]
        props = feature["properties"]
        coords = feature["geometry"]["coordinates"]
        check_coords(coords, sid)
        require(props["routeOrder"] == index, "Station GeoJSON route order mismatch")
        require(props["stationName"] == station["name"]["value"], "Station name differs from source geometry")
        require(isinstance(props.get("sourceRecordIndex"), int), "Station source record index missing")
        station_source_indices.append(props["sourceRecordIndex"])
        for coord in coords:
            nearest = min(grs80_inverse_m(coord, route_coord) for route_coord in route_coords)
            require(nearest <= 0.01, f"Station vertex does not meet route reference line: {sid} ({nearest} m)")
    require(len(set(station_names)) == len(station_names), "Station names are not unique in this corridor")
    require(all(a < b for a, b in zip(station_measures, station_measures[1:])), "Station route ordering is not strictly increasing")
    require(station_names[0] == "京都" and station_names[-1] == "大和西大寺", "Wrong corridor end stations")
    require(station_source_indices == MANIFEST["extraction"]["stationSourceRecordIndicesInRouteOrder"], "Station source indices differ from manifest")

    operational = route["operationalData"]
    for key, value in operational.items():
        require(value["status"] == "UNKNOWN" and value["value"] is None and value["sourceIDs"] == [], f"Operational field should remain UNKNOWN: {key}")
    require(set(PACKAGE["unknownFields"]) == set(operational), "Unknown-field index differs from operational field records")
    require(route["officialRailwayChainageM"]["status"] == "UNKNOWN", "Official chainage must remain unknown")
    require(route["physicalTrackLengthM"]["status"] == "UNKNOWN", "Physical track length must remain unknown")

    report = {
        "status": "PASS",
        "routeID": route["routeID"],
        "routeFeatureCount": len(segment_features),
        "stationCount": len(stations),
        "vertexCount": len(route_coords),
        "routeReferenceLineLengthM": round(measures[-1], 3),
        "maxConsecutiveVertexGapM": round(max(gaps), 3),
        "minConsecutiveVertexGapM": round(min(gaps), 3),
        "duplicateOrInvalidRouteCoordinates": 0,
        "stationVertexRouteMatchMaxM": max(
            min(grs80_inverse_m(coord, route_coord) for route_coord in route_coords)
            for feature in station_features for coord in feature["geometry"]["coordinates"]
        ),
        "stationOrder": station_names,
        "unknownOperationalFields": sorted(operational),
        "checks": [
            "source hash, license, retrieval date, CRS, coordinate order, and no datum transformation",
            "route segment continuity and source-record provenance",
            "station ordering, geometry matching, and source-record provenance",
            "units and GRS80 local chainage recomputation",
            "invalid, non-finite, duplicate coordinates and zero-length edges",
            "critical operational fields remain UNKNOWN",
        ],
    }
    return report


if __name__ == "__main__":
    print(json.dumps(validate(), ensure_ascii=False, indent=2))
