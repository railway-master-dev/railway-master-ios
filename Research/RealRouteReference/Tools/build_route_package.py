#!/usr/bin/env python3
"""Build the Kyoto–Toji route-reference package from the pinned MLIT N02-25 archive.

Only the selected railway-section line and two station line features are emitted.
The source archive is CC BY 4.0. This script preserves source coordinates and
vertex order except for reversing the railway-section line to define the local
Kyoto -> Toji chainage direction. No curve, grade, cant, speed, platform, signal,
or physical-track values are inferred.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import math
import urllib.request
import zipfile
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[1]
DATA_DIR = ROOT / "Data"
DOWNLOAD_URL = "https://nlftp.mlit.go.jp/ksj/gml/data/N02/N02-25/N02-25_GML.zip"
SOURCE_PAGE = "https://nlftp.mlit.go.jp/ksj/gml/datalist/KsjTmplt-N02-2025.html"
LICENSE_URL = "https://creativecommons.org/licenses/by/4.0/"
EXPECTED_SHA256 = "aaf76af133b2e771e538fabc4646d2e443dc1d5a67b221382a28d744e706cc9f"
SOURCE_ID = "mlit_n02_2025"
ROUTE_ID = "kintetsu_kyoto_line_kyoto_toji"
TRACK_ID = "kintetsu_kyoto_toji_reference_geometry"

# Official N02-25 route-link feature is ordered Toji -> Kyoto. These exact
# endpoints also touch the corresponding station-line features.
EXPECTED_ROUTE_FROM = [135.75260, 34.98029]  # Toji-side route-link endpoint
EXPECTED_ROUTE_TO = [135.75684, 34.98459]    # Kyoto-side route-link endpoint


def read_json_member(zf: zipfile.ZipFile, path: str) -> dict[str, Any]:
    return json.loads(zf.read(path).decode("utf-8"))


def vincenty_grs80_m(a: list[float], b: list[float]) -> float:
    """Inverse geodesic on GRS80, using source order [longitude, latitude]."""
    lon1, lat1 = map(math.radians, a)
    lon2, lat2 = map(math.radians, b)
    semi_major = 6_378_137.0
    flattening = 1.0 / 298.257222101
    semi_minor = (1.0 - flattening) * semi_major
    reduced1 = math.atan((1.0 - flattening) * math.tan(lat1))
    reduced2 = math.atan((1.0 - flattening) * math.tan(lat2))
    sin_u1, cos_u1 = math.sin(reduced1), math.cos(reduced1)
    sin_u2, cos_u2 = math.sin(reduced2), math.cos(reduced2)
    longitude_diff = lon2 - lon1
    lam = longitude_diff

    for _ in range(200):
        sin_lam, cos_lam = math.sin(lam), math.cos(lam)
        sin_sigma = math.sqrt(
            (cos_u2 * sin_lam) ** 2
            + (cos_u1 * sin_u2 - sin_u1 * cos_u2 * cos_lam) ** 2
        )
        if sin_sigma == 0:
            return 0.0
        cos_sigma = sin_u1 * sin_u2 + cos_u1 * cos_u2 * cos_lam
        sigma = math.atan2(sin_sigma, cos_sigma)
        sin_alpha = cos_u1 * cos_u2 * sin_lam / sin_sigma
        cos_sq_alpha = 1.0 - sin_alpha * sin_alpha
        cos2_sigma_m = 0.0 if cos_sq_alpha < 1e-15 else cos_sigma - 2.0 * sin_u1 * sin_u2 / cos_sq_alpha
        c = flattening / 16.0 * cos_sq_alpha * (4.0 + flattening * (4.0 - 3.0 * cos_sq_alpha))
        next_lam = longitude_diff + (1.0 - c) * flattening * sin_alpha * (
            sigma + c * sin_sigma * (
                cos2_sigma_m + c * cos_sigma * (-1.0 + 2.0 * cos2_sigma_m**2)
            )
        )
        if abs(next_lam - lam) < 1e-12:
            lam = next_lam
            break
        lam = next_lam
    else:
        raise ValueError("GRS80 inverse geodesic did not converge")

    u_sq = cos_sq_alpha * (semi_major**2 - semi_minor**2) / (semi_minor**2)
    aa = 1.0 + u_sq / 16384.0 * (4096.0 + u_sq * (-768.0 + u_sq * (320.0 - 175.0 * u_sq)))
    bb = u_sq / 1024.0 * (256.0 + u_sq * (-128.0 + u_sq * (74.0 - 47.0 * u_sq)))
    delta_sigma = bb * sin_sigma * (
        cos2_sigma_m + bb / 4.0 * (
            cos_sigma * (-1.0 + 2.0 * cos2_sigma_m**2)
            - bb / 6.0 * cos2_sigma_m * (-3.0 + 4.0 * sin_sigma**2)
            * (-3.0 + 4.0 * cos2_sigma_m**2)
        )
    )
    return semi_minor * aa * (sigma - delta_sigma)


def evidence(value: Any, status: str, note: str, *, source_ids: list[str] | None = None,
             confidence: str = "UNRATED", uncertainty: float | None = None) -> dict[str, Any]:
    return {
        "value": value,
        "status": status,
        "sourceIDs": source_ids or [],
        "uncertainty": uncertainty,
        "confidence": confidence,
        "note": note,
    }


def unknown(note: str) -> dict[str, Any]:
    return evidence(None, "UNKNOWN", note)


def load_archive(path: Path | None) -> tuple[bytes, str]:
    if path:
        blob = path.read_bytes()
    else:
        request = urllib.request.Request(
            DOWNLOAD_URL,
            headers={"User-Agent": "CueRailwayRouteDataBuilder/1.0 (public open-data research)"},
        )
        with urllib.request.urlopen(request, timeout=120) as response:
            blob = response.read()
    digest = hashlib.sha256(blob).hexdigest()
    if digest != EXPECTED_SHA256:
        raise ValueError(
            f"N02-25 archive hash mismatch: expected {EXPECTED_SHA256}, got {digest}. "
            "Inspect source version before rebuilding; do not silently replace the pinned data."
        )
    return blob, digest


def unique_feature(features: list[dict[str, Any]], predicate, label: str) -> dict[str, Any]:
    matches = [feature for feature in features if predicate(feature)]
    if len(matches) != 1:
        raise ValueError(f"Expected exactly one {label} feature; found {len(matches)}")
    return matches[0]


def build(archive_path: Path | None, retrieved_at: str) -> tuple[dict[str, Any], dict[str, Any], dict[str, Any]]:
    blob, archive_sha256 = load_archive(archive_path)
    with zipfile.ZipFile(__import__("io").BytesIO(blob)) as zf:
        route_fc = read_json_member(zf, "N02-25_GML/UTF-8/N02-25_RailroadSection.geojson")
        station_fc = read_json_member(zf, "N02-25_GML/UTF-8/N02-25_Station.geojson")

    def is_kintetsu_kyoto_line(feature: dict[str, Any]) -> bool:
        p = feature.get("properties", {})
        coords = feature.get("geometry", {}).get("coordinates", [])
        return (p.get("N02_003") == "京都線" and p.get("N02_004") == "近畿日本鉄道"
                and feature.get("geometry", {}).get("type") == "LineString"
                and len(coords) == 16 and coords[0] == EXPECTED_ROUTE_FROM
                and coords[-1] == EXPECTED_ROUTE_TO)

    route_feature = unique_feature(route_fc["features"], is_kintetsu_kyoto_line, "Kintetsu Kyoto Line route")
    source_coords = route_feature["geometry"]["coordinates"]
    if source_coords[0] != EXPECTED_ROUTE_FROM or source_coords[-1] != EXPECTED_ROUTE_TO:
        raise ValueError(f"Pinned N02-25 route endpoints changed: {source_coords[0]} -> {source_coords[-1]}")
    kyoto = unique_feature(
        station_fc["features"],
        lambda f: f.get("properties", {}).get("N02_004") == "近畿日本鉄道"
        and f.get("properties", {}).get("N02_003") == "京都線"
        and f.get("properties", {}).get("N02_005") == "京都",
        "Kintetsu Kyoto station",
    )
    toji = unique_feature(
        station_fc["features"],
        lambda f: f.get("properties", {}).get("N02_004") == "近畿日本鉄道"
        and f.get("properties", {}).get("N02_003") == "京都線"
        and f.get("properties", {}).get("N02_005") == "東寺",
        "Toji station",
    )
    kyoto_coords = kyoto["geometry"]["coordinates"]
    toji_coords = toji["geometry"]["coordinates"]
    if kyoto_coords[0] != EXPECTED_ROUTE_TO or toji_coords[-1] != EXPECTED_ROUTE_FROM:
        raise ValueError("The route-link endpoints no longer match the station-line boundaries")

    # Reverse only the route line vertex order to define Kyoto -> Toji chainage.
    coords = list(reversed(source_coords))
    cumulative = [0.0]
    for first, second in zip(coords, coords[1:]):
        cumulative.append(cumulative[-1] + vincenty_grs80_m(first, second))
    route_length_m = round(cumulative[-1], 1)

    coordinate_note = (
        "Coordinate is the published N02-25 route-line vertex in JGD2011/(B,L); "
        "this is a national-scale line-level route representation, not an individually "
        "surveyed physical track centerline. The source metadata gives 1:25,000 equivalent "
        "scale but no metre-valued absolute-position error bound."
    )
    chainage_note = (
        "Local chainage is calculated by cumulative GRS80 inverse geodesic between the published "
        "N02-25 route-line vertices and rounded to 0.1 m. Status ESTIMATED reflects that the "
        "input is generalized route geometry, not a surveyed physical track or operator chainage; "
        "physical position error is not quantified by the source."
    )
    geometry_samples = []
    for chainage, point in zip(cumulative, coords):
        lon, lat = point
        geometry_samples.append({
            "chainageM": evidence(round(chainage, 1), "ESTIMATED", chainage_note,
                                  source_ids=[SOURCE_ID], confidence="LOW"),
            "coordinate": evidence(
                {"latitudeDeg": lat, "longitudeDeg": lon, "elevationM": None},
                "VERIFIED", coordinate_note,
                source_ids=[SOURCE_ID], confidence="LOW",
            ),
        })

    route_props = route_feature["properties"]
    kyoto_props = kyoto["properties"]
    toji_props = toji["properties"]
    source_metadata = {
        "sourceID": SOURCE_ID,
        "title": "国土数値情報（鉄道データ）2025年度版 N02-25",
        "publisher": "国土交通省",
        "url": DOWNLOAD_URL,
        "accessedAt": retrieved_at,
        "publishedAt": "2026-03-06",
        "license": "Creative Commons Attribution 4.0 International (CC BY 4.0); https://creativecommons.org/licenses/by/4.0/",
        "attribution": (
            "Source: MLIT National Land Numerical Information (Railway) N02-25, "
            "2025 dataset, https://nlftp.mlit.go.jp/ksj/gml/datalist/KsjTmplt-N02-2025.html, "
            "retrieved " + retrieved_at + ". Extracted Kyoto–Toji route-link and station-line features; "
            "route geometry vertex order reversed and local cumulative chainage calculated by Cue."
        ),
        "usageNotes": (
            "Credit the Ministry of Land, Infrastructure, Transport and Tourism and the dataset page; "
            "state that the route/station subset was extracted and the route order/chainage processed. "
            "Do not imply that MLIT certifies this derivative simulator geometry."
        ),
        "reliabilityNotes": (
            "The dataset contains line geometry for railway routes and stations. Metadata equivalent scale: 1:25,000; "
            "coordinate QA compares values with the referenced source and reports 0% mismatch, not a metre-level "
            "absolute survey error. It does not describe individual tracks, curve radius, cant, gradient, speed limits, "
            "signals, blocks, platform dimensions, or stop markers. N02-25 metadata dateStamp is 2026-03-06; "
            "the dataset reference date is 2025-12-31."
        ),
    }

    track_segment = {
        "segmentID": "kintetsu_kyoto_toji_reference_segment_001",
        "startChainageM": evidence(0.0, "ESTIMATED", "Start of the extracted route-link geometry at the Kyoto-side station-line boundary.", source_ids=[SOURCE_ID], confidence="LOW"),
        "endChainageM": evidence(route_length_m, "ESTIMATED", "End of the extracted route-link geometry at the Toji-side station-line boundary.", source_ids=[SOURCE_ID], confidence="LOW"),
        "alignment": unknown("N02 provides a route line, not a surveyed tangent/circular/transition-curve classification."),
        "curveRadiusM": unknown("No curve radius is supplied by the source. Do not infer it from this generalized line geometry."),
        "transitionLengthM": unknown("No transition-curve length is supplied by the source."),
        "cantMM": unknown("Cant is not supplied by the source."),
        "cantTransitionLengthM": unknown("Cant run-off length is not supplied by the source."),
        "gradientPermille": unknown("Rail elevation profile and gradient are not supplied by the source."),
        "speedLimitKmh": unknown("Authorized speed limits and restriction extents are not supplied by the source."),
        "trackStructure": unknown("Ballast/slab/other track structure is not supplied by the source."),
        "railProfile": unknown("Rail section/profile is not supplied by the source."),
        "sleeperType": unknown("Sleeper type is not supplied by the source."),
        "longWeldedRail": unknown("Long-welded-rail status is not supplied by the source."),
        "notes": (
            "Compatibility container only: the N02 feature represents railway route geometry, not an individual "
            "track segment. Not safe as-is for rail rendering or physics."
        ),
    }

    def station_record(feature: dict[str, Any], station_name: str, station_code: str, boundary_chainage: float) -> dict[str, Any]:
        p = feature["properties"]
        return {
            "stationID": f"kintetsu_{station_code.lower()}",
            "name": evidence(station_name, "VERIFIED", "Station name and operator are recorded in the MLIT N02-25 Station feature.", source_ids=[SOURCE_ID], confidence="HIGH"),
            "chainageM": unknown("Station-center chainage is not supplied; see org.cue.railway.segmentBoundaryChainageM for the route-link boundary only."),
            "stopPositionChainageM": unknown("Train stop marker/position is not supplied."),
            "location": unknown("The source station feature is a LineString, not a station-centre point; preserve its exact line in route_geometry.geojson instead of inventing a centroid."),
            "trackIDs": [TRACK_ID],
            "platforms": [],
            "trackLayoutNotes": unknown("The N02 station line does not establish platform count, track layout, platform dimensions, or equipment."),
        }

    route_package = {
        "schemaVersion": "1.0.0",
        "packageID": "kintetsu-kyoto-toji-real-route-reference-v1",
        "sources": [source_metadata],
        "route": {
            "routeID": ROUTE_ID,
            "name": evidence("近鉄京都線 京都—東寺", "VERIFIED", "N02-25 route feature identifies route name 京都線 and operator 近畿日本鉄道; the two selected station features are 京都 and 東寺.", source_ids=[SOURCE_ID], confidence="HIGH"),
            "datasetKind": "REAL_WORLD",
            "description": (
                "One station-to-station route-link geometry segment extracted from MLIT N02-25. "
                "This is a route-reference line, not a physical track-level or operations-complete simulator route."
            ),
            "totalLengthM": evidence(route_length_m, "ESTIMATED", chainage_note, source_ids=[SOURCE_ID], confidence="LOW"),
            "mainTrackID": TRACK_ID,
            "networkLengthM": unknown("An N02 route-link line is not an inventory of individual tracks; physical network length is not established."),
            "officialCommercialDistanceM": unknown("Not included in this CC BY route-data payload; fare distance is a separate operator measure and is documented separately in QUALITY_REPORT.md."),
            "timezone": "Asia/Tokyo",
            "tracks": [{
                "trackID": TRACK_ID,
                "name": unknown("Compatibility container for the N02 route-link geometry; no individual physical track identity is established."),
                "direction": unknown("Operational up/down direction and individual track direction are not established. Package chainage orientation is documented separately as Kyoto to Toji."),
                "gaugeMM": unknown("Track gauge is not asserted by the selected N02 route-link feature."),
                "centerSpacingMM": unknown("Track count and track-center spacing are not asserted by N02 route geometry."),
                "geometry": geometry_samples,
                "segments": [track_segment],
                "blockCoverageRequired": False,
            }],
            "stations": [
                station_record(kyoto, "京都", kyoto_props["N02_005c"], 0.0),
                station_record(toji, "東寺", toji_props["N02_005c"], route_length_m),
            ],
            "speedRestrictions": [],
            "signals": [],
            "blocks": [],
            "switches": [],
            "interlockings": [],
            "structures": [],
            "levelCrossings": [],
            "landmarks": [],
            "servicePatterns": [],
            "operatingProfiles": [],
            "depots": [],
            "timetables": [],
            "scenarios": [],
            "validationPolicy": {
                "requireFullSpeedCoverage": False,
                "maxGeometryGapM": 250.0,
                "maxCoordinateJumpM": 250.0,
                "maxHeadingChangeDegrees": 135.0,
                "minimumThroughRunTimeSeconds": 3600.0,
                "maximumLocalRunTimeSeconds": 9000.0,
            },
            "extensions": {
                "org.cue.railway.referenceGeometry": {
                    "representation": "N02 railway route-link line; not a surveyed individual track centerline",
                    "coordinateReferenceSystem": "JGD2011 / (B,L), source geometry is longitude-latitude pairs; no datum transformation performed",
                    "packageChainageOrientation": "KYOTO_TO_TOJI",
                    "chainageMethod": "Cumulative inverse geodesic on GRS80; output rounded to 0.1 m",
                    "routeSectionSourceProperties": route_props,
                    "stationSourceProperties": {
                        "kyoto": kyoto_props,
                        "toji": toji_props,
                    },
                    "sourceReferenceDate": "2025-12-31",
                    "sourceArchiveSHA256": archive_sha256,
                },
                "org.cue.railway.segmentBoundaryChainageM": {
                    "kyoto": {"value": 0.0, "status": "ESTIMATED", "note": "N02 railway-section line begins at the Kyoto-station-line endpoint; this is not the train stopping position or station center."},
                    "toji": {"value": route_length_m, "status": "ESTIMATED", "note": "N02 railway-section line ends at the Toji-station-line endpoint; this is not the train stopping position or station center."},
                },
                "org.cue.railway.dataCompleteness": {
                    "individualTrackIdentity": "UNKNOWN",
                    "trackCountAndSpacing": "UNKNOWN",
                    "gauge": "UNKNOWN",
                    "curveRadiusAndTransition": "UNKNOWN",
                    "cant": "UNKNOWN",
                    "gradientAndRailElevation": "UNKNOWN",
                    "speedLimits": "UNKNOWN_NOT_ASSERTED_EMPTY_ARRAY",
                    "signalsAndAspects": "UNKNOWN_NOT_ASSERTED_EMPTY_ARRAY",
                    "blocksAndATS": "UNKNOWN_NOT_ASSERTED_EMPTY_ARRAY",
                    "platformsAndStopMarkers": "UNKNOWN_NOT_ASSERTED_EMPTY_ARRAY",
                    "switchesAndInterlocking": "UNKNOWN_NOT_ASSERTED_EMPTY_ARRAY",
                    "crossingsAndStructures": "UNKNOWN_NOT_ASSERTED_EMPTY_ARRAY",
                    "timetableAndScenario": "UNKNOWN_NOT_ASSERTED_EMPTY_ARRAY",
                    "safeForPhysicsOrSignalling": False,
                },
            },
        },
    }

    features = [
        {
            "type": "Feature",
            "id": "N02-25-kintetsu-kyoto-toji-route-link",
            "properties": {
                "featureRole": "ROUTE_REFERENCE_LINE_NOT_PHYSICAL_TRACK_CENTERLINE",
                "sourceDataset": "N02-25_RailroadSection",
                "sourceProperties": route_props,
                "packageChainageOrientation": "KYOTO_TO_TOJI",
                "sourceVertexOrder": "TOJI_TO_KYOTO",
                "routeVertexOrderReversed": True,
                "startChainageM": 0.0,
                "endChainageM": route_length_m,
                "distanceMethod": "GRS80 inverse geodesic over source vertices; rounded to 0.1 m",
                "coordinateReferenceSystem": "JGD2011 / (B,L); GeoJSON array order [longitude, latitude]; no datum transformation",
                "source": SOURCE_ID,
                "license": "CC BY 4.0",
            },
            "geometry": {"type": "LineString", "coordinates": coords},
        },
    ]
    for feature, label, code in ((kyoto, "京都", kyoto_props["N02_005c"]), (toji, "東寺", toji_props["N02_005c"])):
        features.append({
            "type": "Feature",
            "id": f"N02-25-kintetsu-station-{code}",
            "properties": {
                "featureRole": "SOURCE_STATION_LINE_NOT_POINT_OR_PLATFORM_SURVEY",
                "sourceDataset": "N02-25_Station",
                "sourceProperties": feature["properties"],
                "stationName": label,
                "coordinateReferenceSystem": "JGD2011 / (B,L); GeoJSON array order [longitude, latitude]; no datum transformation",
                "source": SOURCE_ID,
                "license": "CC BY 4.0",
            },
            "geometry": feature["geometry"],
        })
    geojson = {
        "type": "FeatureCollection",
        "name": "kintetsu_kyoto_toji_reference_geometry",
        "metadata": {
            "sourceDataset": "MLIT National Land Numerical Information N02-25",
            "sourceURL": SOURCE_PAGE,
            "sourceArchiveURL": DOWNLOAD_URL,
            "sourceArchiveSHA256": archive_sha256,
            "retrievedAt": retrieved_at,
            "license": "CC BY 4.0",
            "licenseURL": LICENSE_URL,
            "coordinateReferenceSystem": "JGD2011 / (B,L); coordinates stored in GeoJSON [longitude, latitude] order without a datum transformation",
            "disclaimer": "The railway section is a national-scale route line, not an individual track centerline or survey of rail geometry.",
        },
        "features": features,
    }
    manifest = {
        "dataset": {
            "name": "国土数値情報（鉄道データ）2025年度版 N02-25",
            "publisher": "国土交通省",
            "pageURL": SOURCE_PAGE,
            "downloadURL": DOWNLOAD_URL,
            "retrievedAt": retrieved_at,
            "dataReferenceDate": "2025-12-31",
            "metadataDateStamp": "2026-03-06",
            "license": "CC BY 4.0",
            "licenseURL": LICENSE_URL,
            "archiveSHA256": archive_sha256,
            "coordinateReferenceSystem": "JGD2011 / (B,L)",
            "metadataEquivalentScale": "1:25,000",
        },
        "extraction": {
            "routeFeatureProperties": route_props,
            "stationFeatures": {"kyoto": kyoto_props, "toji": toji_props},
            "routeVertexCount": len(coords),
            "routeLengthM": route_length_m,
            "routeLengthStatus": "ESTIMATED",
            "routeLengthMethod": "Cumulative inverse geodesic on GRS80 between published source vertices; route order reversed to Kyoto -> Toji; rounded to 0.1 m",
            "positionErrorMetres": None,
            "positionErrorNote": "No metre-valued absolute positioning error bound was found in N02-25 metadata; the 0% coordinate QA refers to matching the referenced source, not ground-truth track survey accuracy.",
        },
    }
    return route_package, geojson, manifest


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source-zip", type=Path, help="Use a local N02-25_GML.zip instead of downloading it")
    parser.add_argument("--retrieved-at", default=datetime.now(timezone.utc).date().isoformat(), help="ISO date to record for source retrieval")
    args = parser.parse_args()
    route_package, geojson, manifest = build(args.source_zip, args.retrieved_at)
    DATA_DIR.mkdir(parents=True, exist_ok=True)
    for filename, payload in (
        ("route-package.json", route_package),
        ("route_geometry.geojson", geojson),
        ("source_manifest.json", manifest),
    ):
        (DATA_DIR / filename).write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        print(f"wrote {DATA_DIR / filename}")
    print(f"route length: {route_package['route']['totalLengthM']['value']:.1f} m; vertices: {len(route_package['route']['tracks'][0]['geometry'])}")
    print(f"source archive sha256: {manifest['dataset']['archiveSHA256']}")


if __name__ == "__main__":
    main()
