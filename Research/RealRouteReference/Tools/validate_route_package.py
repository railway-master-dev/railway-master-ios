#!/usr/bin/env python3
"""Validate the extracted route package using only Python's standard library."""
from __future__ import annotations

import json
import math
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "Tools"))
from build_route_package import vincenty_grs80_m  # noqa: E402

PACKAGE = json.loads((ROOT / "Data/route-package.json").read_text(encoding="utf-8"))
GEOJSON = json.loads((ROOT / "Data/route_geometry.geojson").read_text(encoding="utf-8"))
MANIFEST = json.loads((ROOT / "Data/source_manifest.json").read_text(encoding="utf-8"))


def require(condition: bool, message: str) -> None:
    if not condition:
        raise AssertionError(message)


def check() -> dict[str, float | int | str]:
    route = PACKAGE["route"]
    track = route["tracks"][0]
    samples = track["geometry"]
    route_feature = GEOJSON["features"][0]
    coords = route_feature["geometry"]["coordinates"]
    stations = {feature["properties"]["stationName"]: feature for feature in GEOJSON["features"][1:]}
    source_ids = {source["sourceID"] for source in PACKAGE["sources"]}

    require(PACKAGE["schemaVersion"] == "1.0.0", "Unexpected schema version")
    require(route["datasetKind"] == "REAL_WORLD", "Route must be labeled real-world")
    require(len(PACKAGE["sources"]) == 1 and "mlit_n02_2025" in source_ids, "Expected one pinned MLIT source")
    source = PACKAGE["sources"][0]
    require(source["license"].find("CC BY 4.0") >= 0, "Source license must be explicit")
    require(source["url"].startswith("https://"), "Source URL must be absolute")
    require(MANIFEST["dataset"]["archiveSHA256"] == route["extensions"]["org.cue.railway.referenceGeometry"]["sourceArchiveSHA256"], "Archive hash mismatch")
    require(MANIFEST["dataset"]["license"] == "CC BY 4.0", "Manifest license mismatch")

    require(len(samples) == 16 and len(coords) == 16, "Expected the pinned 16-vertex route feature")
    require(len(stations) == 2 and set(stations) == {"京都", "東寺"}, "Expected exactly Kyoto and Toji station-line features")
    require(route_feature["properties"]["featureRole"] == "ROUTE_REFERENCE_LINE_NOT_PHYSICAL_TRACK_CENTERLINE", "Route geometry role is unclear")
    require(route_feature["properties"]["packageChainageOrientation"] == "KYOTO_TO_TOJI", "Unexpected package direction")
    require(route_feature["properties"]["routeVertexOrderReversed"] is True, "Source vertex-order processing must be disclosed")

    # Route endpoints must join the exact source station-line endpoints.
    require(coords[0] == stations["京都"]["geometry"]["coordinates"][0], "Kyoto route boundary does not meet its source station line")
    require(coords[-1] == stations["東寺"]["geometry"]["coordinates"][-1], "Toji route boundary does not meet its source station line")
    require(coords[0] == [135.75684, 34.98459] and coords[-1] == [135.7526, 34.98029], "Pinned endpoints changed")

    chainages = [sample["chainageM"]["value"] for sample in samples]
    require(chainages[0] == 0.0, "First chainage must be zero")
    require(all(a < b for a, b in zip(chainages, chainages[1:])), "Chainage must increase strictly")
    require(all(sample["chainageM"]["status"] == "ESTIMATED" for sample in samples), "Computed route-line chainage must not be labeled as a physical measurement")
    require(all(sample["coordinate"]["status"] == "VERIFIED" for sample in samples), "Source coordinate provenance missing")
    require(all(set(sample["coordinate"]["sourceIDs"]).issubset(source_ids) for sample in samples), "Coordinate has unknown source ID")

    leg_lengths = [vincenty_grs80_m(a, b) for a, b in zip(coords, coords[1:])]
    computed_length = sum(leg_lengths)
    rounded_length = round(computed_length, 1)
    declared_length = route["totalLengthM"]["value"]
    require(rounded_length == declared_length == chainages[-1], "Declared route length does not match source geometry")
    require(route["totalLengthM"]["status"] == "ESTIMATED" and route["totalLengthM"]["confidence"] == "LOW", "Route-line length provenance/confidence is not conservative")
    require(max(leg_lengths) < route["validationPolicy"]["maxGeometryGapM"], "Geometry gap exceeds validation threshold")

    unknown_fields = [
        track["gaugeMM"], track["centerSpacingMM"], track["direction"],
        track["segments"][0]["alignment"], track["segments"][0]["curveRadiusM"],
        track["segments"][0]["transitionLengthM"], track["segments"][0]["cantMM"],
        track["segments"][0]["cantTransitionLengthM"], track["segments"][0]["gradientPermille"],
        track["segments"][0]["speedLimitKmh"], track["segments"][0]["trackStructure"],
        track["segments"][0]["railProfile"], track["segments"][0]["sleeperType"],
        track["segments"][0]["longWeldedRail"],
    ]
    require(all(item["status"] == "UNKNOWN" and item["value"] is None for item in unknown_fields), "A simulator-critical unknown was silently populated")
    require(route["officialCommercialDistanceM"]["status"] == "UNKNOWN" and route["officialCommercialDistanceM"]["value"] is None, "Commercial distance must not be conflated with route geometry")
    require(not route["speedRestrictions"] and not route["signals"] and not route["blocks"], "No sourced speed/signal/block records are expected")
    completeness = route["extensions"]["org.cue.railway.dataCompleteness"]
    require(completeness["safeForPhysicsOrSignalling"] is False, "The package must not claim operational readiness")
    require(completeness["speedLimits"] == "UNKNOWN_NOT_ASSERTED_EMPTY_ARRAY", "Empty speed list must not mean no restrictions")
    require(all(station["chainageM"]["status"] == "UNKNOWN" for station in route["stations"]), "Station center chainage must remain unknown")
    require(all(station["stopPositionChainageM"]["status"] == "UNKNOWN" for station in route["stations"]), "Stop position must remain unknown")
    require(all(not station["platforms"] for station in route["stations"]), "No platform records are expected")

    return {
        "routeID": route["routeID"],
        "routeVertices": len(coords),
        "stationFeatures": len(stations),
        "computedLengthM": rounded_length,
        "maximumVertexGapM": round(max(leg_lengths), 3),
        "minimumVertexGapM": round(min(leg_lengths), 3),
        "sourceArchiveSHA256": MANIFEST["dataset"]["archiveSHA256"],
        "physicsOrSignallingReady": "NO",
    }


if __name__ == "__main__":
    try:
        print(json.dumps(check(), ensure_ascii=False, indent=2))
    except Exception as exc:
        print(f"FAIL: {exc}", file=sys.stderr)
        raise
