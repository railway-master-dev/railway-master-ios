#!/usr/bin/env python3
"""Build an isolated MLIT N02-25 route-reference package for Kintetsu Kyoto Line.

The extracted geometry is a generalized public route/station line dataset, not
surveyed physical track centerline or operational railway data.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import math
import statistics
import tempfile
import urllib.request
import zipfile
from datetime import date
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[1]
DATA_DIR = ROOT / "Data"
SOURCE_URL = "https://nlftp.mlit.go.jp/ksj/gml/data/N02/N02-25/N02-25_GML.zip"
SOURCE_PAGE = "https://nlftp.mlit.go.jp/ksj/gml/datalist/KsjTmplt-N02-2025.html"
LICENSE_URL = "https://creativecommons.org/licenses/by/4.0/"
TERMS_URL = "https://nlftp.mlit.go.jp/ksj/other/agreement_01.html"
PRODUCT_SPEC_URL = "https://nlftp.mlit.go.jp/ksj/gml/product_spec/KS-PS-N02-v3_1.pdf"
EXPECTED_SHA256 = "aaf76af133b2e771e538fabc4646d2e443dc1d5a67b221382a28d744e706cc9f"
ROUTE_OPERATOR = "近畿日本鉄道"
ROUTE_NAME = "京都線"
START_STATION = "京都"
END_STATION = "大和西大寺"
SOURCE_ID = "mlit_n02_2025"
ROUTE_ID = "kintetsu_kyoto_line_kyoto_yamato_saidaiji_reference"


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def download_source(path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    request = urllib.request.Request(SOURCE_URL, headers={"User-Agent": "Cue-RealRoutePrototype/1.0"})
    with urllib.request.urlopen(request, timeout=120) as response, path.open("wb") as output:
        while True:
            chunk = response.read(1024 * 1024)
            if not chunk:
                break
            output.write(chunk)


def grs80_inverse_m(a: list[float], b: list[float]) -> float:
    """Vincenty inverse distance on GRS80; input coordinates are [lon, lat]."""
    lon1, lat1 = map(math.radians, a[:2])
    lon2, lat2 = map(math.radians, b[:2])
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
            sigma + c * sin_sigma * (cos2_sigma_m + c * cos_sigma * (-1.0 + 2.0 * cos2_sigma_m**2))
        )
        if abs(next_lam - lam) < 1e-12:
            lam = next_lam
            break
        lam = next_lam
    else:
        raise ValueError("GRS80 inverse geodesic failed to converge")

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


def coord_key(coord: list[float]) -> tuple[float, float]:
    # N02 coordinates are recorded to more than seven decimal places where needed.
    return (round(float(coord[0]), 7), round(float(coord[1]), 7))


def read_json_member(archive: zipfile.ZipFile, member: str) -> dict[str, Any]:
    return json.loads(archive.read(member).decode("utf-8"))


def field(value: Any, status: str, source_ids: list[str], confidence: str, note: str) -> dict[str, Any]:
    return {
        "value": value,
        "status": status,
        "sourceIDs": source_ids,
        "confidence": confidence,
        "uncertainty": None,
        "note": note,
    }


def build(archive_path: Path, retrieved_at: str) -> dict[str, Any]:
    archive_hash = sha256(archive_path)
    if archive_hash != EXPECTED_SHA256:
        raise ValueError(f"N02-25 archive SHA-256 mismatch: {archive_hash}")

    with zipfile.ZipFile(archive_path) as archive:
        rail_data = read_json_member(archive, "N02-25_GML/UTF-8/N02-25_RailroadSection.geojson")
        station_data = read_json_member(archive, "N02-25_GML/UTF-8/N02-25_Station.geojson")

    route_edges: list[dict[str, Any]] = []
    for source_index, feature in enumerate(rail_data["features"]):
        props = feature.get("properties", {})
        if props.get("N02_004") == ROUTE_OPERATOR and props.get("N02_003") == ROUTE_NAME:
            coords = feature["geometry"]["coordinates"]
            if feature["geometry"].get("type") != "LineString" or len(coords) < 2:
                raise ValueError(f"Unsupported route geometry at source record {source_index}")
            route_edges.append({
                "sourceIndex": source_index,
                "sourceProperties": props,
                "sourceCoordinates": coords,
                "a": coord_key(coords[0]),
                "b": coord_key(coords[-1]),
            })

    station_rows: list[dict[str, Any]] = []
    for source_index, feature in enumerate(station_data["features"]):
        props = feature.get("properties", {})
        if props.get("N02_004") == ROUTE_OPERATOR and props.get("N02_003") == ROUTE_NAME:
            if feature["geometry"].get("type") != "LineString":
                raise ValueError(f"Unsupported station geometry at source record {source_index}")
            station_rows.append({
                "sourceIndex": source_index,
                "sourceProperties": props,
                "sourceCoordinates": feature["geometry"]["coordinates"],
            })

    if not route_edges or not station_rows:
        raise ValueError("No route or station features matched the configured corridor")

    adjacency: dict[tuple[float, float], list[int]] = {}
    for edge_index, edge in enumerate(route_edges):
        adjacency.setdefault(edge["a"], []).append(edge_index)
        adjacency.setdefault(edge["b"], []).append(edge_index)
    endpoints = [node for node, incident in adjacency.items() if len(incident) == 1]
    if len(endpoints) != 2 or any(len(incident) > 2 for incident in adjacency.values()):
        raise ValueError("Selected route features are not one unbranched open chain")

    station_by_name: dict[str, list[dict[str, Any]]] = {}
    for station in station_rows:
        station_by_name.setdefault(station["sourceProperties"]["N02_005"], []).append(station)
    if len(station_by_name.get(START_STATION, [])) != 1 or len(station_by_name.get(END_STATION, [])) != 1:
        raise ValueError("Start/end station names are not unique in the selected route")

    def endpoint_distance(node: tuple[float, float], station: dict[str, Any]) -> float:
        return min(grs80_inverse_m(list(node), coord) for coord in station["sourceCoordinates"])

    start_station = station_by_name[START_STATION][0]
    start_node = min(endpoints, key=lambda node: endpoint_distance(node, start_station))
    if endpoint_distance(start_node, start_station) > 0.01:
        raise ValueError("Route chain endpoint does not match the published start-station line")

    ordered_edges: list[dict[str, Any]] = []
    oriented_segments: list[dict[str, Any]] = []
    full_coords: list[list[float]] = []
    current_node = start_node
    used: set[int] = set()
    while True:
        choices = [idx for idx in adjacency[current_node] if idx not in used]
        if not choices:
            break
        edge_index = choices[0]
        used.add(edge_index)
        edge = route_edges[edge_index]
        reverse = edge["b"] == current_node
        coords = list(reversed(edge["sourceCoordinates"])) if reverse else list(edge["sourceCoordinates"])
        if coord_key(coords[0]) != current_node:
            raise ValueError("Route edge endpoint orientation is inconsistent")
        if full_coords and coord_key(full_coords[-1]) != coord_key(coords[0]):
            raise ValueError("Route segments are not coordinate-continuous")
        start_vertex_index = len(full_coords) - 1 if full_coords else 0
        if full_coords:
            full_coords.extend(coords[1:])
        else:
            full_coords.extend(coords)
        end_vertex_index = len(full_coords) - 1
        ordered_edges.append(edge)
        oriented_segments.append({
            "edge": edge,
            "coordinates": coords,
            "reversed": reverse,
            "startVertexIndex": start_vertex_index,
            "endVertexIndex": end_vertex_index,
        })
        current_node = edge["b"] if edge["a"] == current_node else edge["a"]

    if len(used) != len(route_edges) or current_node not in endpoints:
        raise ValueError("Route chain does not cover exactly the selected features")
    end_station = station_by_name[END_STATION][0]
    if endpoint_distance(current_node, end_station) > 0.01:
        raise ValueError("Route chain endpoint does not match the published end-station line")

    chainages = [0.0]
    for first, second in zip(full_coords, full_coords[1:]):
        chainages.append(chainages[-1] + grs80_inverse_m(first, second))
    total_length = chainages[-1]
    if total_length <= 10_000:
        raise ValueError("Selected corridor is not materially longer than the existing short reference")

    route_vertex_positions: dict[tuple[float, float], list[float]] = {}
    for coord, measure in zip(full_coords, chainages):
        route_vertex_positions.setdefault(coord_key(coord), []).append(measure)

    ordered_stations: list[dict[str, Any]] = []
    for station in station_rows:
        per_vertex_measures: list[float] = []
        nearest_distances: list[float] = []
        for coord in station["sourceCoordinates"]:
            candidates = sorted(
                (grs80_inverse_m(coord, route_coord), route_measure)
                for route_coord, route_measure in zip(full_coords, chainages)
            )
            nearest_distance = candidates[0][0]
            nearest_measures = [measure for distance, measure in candidates if abs(distance - nearest_distance) < 1e-5]
            per_vertex_measures.append(statistics.median(nearest_measures))
            nearest_distances.append(nearest_distance)
        if max(nearest_distances) > 0.01:
            raise ValueError(f"Station geometry does not match route vertices: {station['sourceProperties']['N02_005']}")
        station_measure = statistics.median(per_vertex_measures)
        ordered_stations.append({
            **station,
            "orderingMeasureM": station_measure,
            "measureRangeM": [min(per_vertex_measures), max(per_vertex_measures)],
            "maxVertexMatchDistanceM": max(nearest_distances),
        })
    ordered_stations.sort(key=lambda item: (item["orderingMeasureM"], item["sourceIndex"]))
    station_measures = [item["orderingMeasureM"] for item in ordered_stations]
    if any(a >= b for a, b in zip(station_measures, station_measures[1:])):
        raise ValueError("Station order measures are not strictly increasing")
    if ordered_stations[0]["sourceProperties"]["N02_005"] != START_STATION:
        raise ValueError("First ordered station is not the configured start station")
    if ordered_stations[-1]["sourceProperties"]["N02_005"] != END_STATION:
        raise ValueError("Last ordered station is not the configured end station")

    segment_features: list[dict[str, Any]] = []
    for order_index, segment in enumerate(oriented_segments, start=1):
        edge = segment["edge"]
        seg_start = chainages[segment["startVertexIndex"]]
        seg_end = chainages[segment["endVertexIndex"]]
        feature_id = f"N02-25-RS-record-{edge['sourceIndex']:05d}"
        segment_features.append({
            "type": "Feature",
            "id": feature_id,
            "properties": {
                "featureRole": "ROUTE_REFERENCE_LINE_SEGMENT_NOT_PHYSICAL_TRACK_CENTERLINE",
                "routeOrder": order_index,
                "sourceID": SOURCE_ID,
                "sourceDataset": "N02-25_RailroadSection",
                "sourceRecordIndex": edge["sourceIndex"],
                "sourceProperties": edge["sourceProperties"],
                "sourceVertexOrderReversed": segment["reversed"],
                "startChainageM": round(seg_start, 3),
                "endChainageM": round(seg_end, 3),
                "computedSegmentLengthM": round(seg_end - seg_start, 3),
                "measureStatus": "ESTIMATED",
                "sourceCoordinateStatus": "VERIFIED_SOURCE_VALUE",
                "positioningConfidence": "LOW",
                "license": "CC BY 4.0",
            },
            "geometry": {"type": "LineString", "coordinates": segment["coordinates"]},
        })

    geojson_features: list[dict[str, Any]] = [{
        "type": "Feature",
        "id": "kintetsu-kyoto-yamato-saidaiji-route-reference-line",
        "properties": {
            "featureRole": "CONTINUOUS_ROUTE_REFERENCE_LINE_NOT_PHYSICAL_TRACK_CENTERLINE",
            "routeID": ROUTE_ID,
            "routeOrderOrientation": "京都 → 大和西大寺",
            "sourceID": SOURCE_ID,
            "sourceDataset": "N02-25_RailroadSection",
            "sourceFeatureCount": len(ordered_edges),
            "vertexCount": len(full_coords),
            "chainageUnit": "m",
            "chainageMethod": "Cumulative GRS80 inverse-geodesic distance between published source vertices; 0.001 m stored, not official railway chainage",
            "vertexChainageM": [round(measure, 3) for measure in chainages],
            "vertexChainageStatus": "ESTIMATED",
            "vertexChainageSourceID": SOURCE_ID,
            "sourceCoordinateStatus": "VERIFIED_SOURCE_VALUE",
            "geometryStatus": "ESTIMATED_GENERALIZED_ROUTE_REFERENCE_LINE",
            "positioningConfidence": "LOW",
            "physicalTrackCenterline": "UNKNOWN",
            "license": "CC BY 4.0",
            "sourceURL": SOURCE_PAGE,
        },
        "geometry": {"type": "LineString", "coordinates": full_coords},
    }]

    package_stations: list[dict[str, Any]] = []
    for order_index, station in enumerate(ordered_stations, start=1):
        props = station["sourceProperties"]
        station_id = f"station-{props.get('N02_005c', station['sourceIndex']):s}"
        package_stations.append({
            "stationID": station_id,
            "routeOrder": order_index,
            "name": field(
                props["N02_005"], "VERIFIED", [SOURCE_ID], "HIGH",
                "Published N02-25 station-name attribute; this does not identify a particular platform, stop point, or station center.",
            ),
            "stationCode": field(
                props.get("N02_005c"), "VERIFIED", [SOURCE_ID], "HIGH",
                "Published N02-25 station code. It is a dataset key, not a railway operator station code.",
            ),
            "sourceGeometry": {
                "file": "route_geometry.geojson",
                "featureID": f"station-{props.get('N02_005c', station['sourceIndex'])}",
                "geometryRole": "SOURCE_STATION_LINE_NOT_CENTER_POINT_OR_PLATFORM",
                "status": "VERIFIED_SOURCE_VALUE",
            },
            "routeOrderReferencePositionM": field(
                round(station["orderingMeasureM"], 3), "ESTIMATED", [SOURCE_ID], "LOW",
                "Median of the nearest route-vertex chainages for the vertices of the published station LineString. It is an ordering aid only, not a station-center position, official chainage, or stop marker.",
            ),
            "stationLineRouteMeasureRangeM": {
                "value": [round(v, 3) for v in station["measureRangeM"]],
                "status": "ESTIMATED",
                "sourceIDs": [SOURCE_ID],
                "confidence": "LOW",
                "uncertainty": None,
                "note": "Range of route-reference measures nearest to the published station-line vertices; not platform endpoints or station limits.",
            },
            "sourceProperties": props,
        })
        geojson_features.append({
            "type": "Feature",
            "id": f"station-{props.get('N02_005c', station['sourceIndex'])}",
            "properties": {
                "featureRole": "SOURCE_STATION_LINE_NOT_CENTER_POINT_OR_PLATFORM",
                "routeOrder": order_index,
                "stationName": props["N02_005"],
                "stationCode": props.get("N02_005c"),
                "sourceID": SOURCE_ID,
                "sourceDataset": "N02-25_Station",
                "sourceRecordIndex": station["sourceIndex"],
                "sourceProperties": props,
                "routeOrderReferencePositionM": round(station["orderingMeasureM"], 3),
                "stationLineRouteMeasureRangeM": [round(v, 3) for v in station["measureRangeM"]],
                "maxVertexMatchDistanceM": round(station["maxVertexMatchDistanceM"], 6),
                "orderingMeasureStatus": "ESTIMATED_ORDERING_AID_ONLY",
                "license": "CC BY 4.0",
            },
            "geometry": {"type": "LineString", "coordinates": station["sourceCoordinates"]},
        })

    station_names = [s["sourceProperties"]["N02_005"] for s in ordered_stations]
    network_fields = [
        ("physicalTrackCenterline", "Physical individual track centerline is not supplied by N02 route reference geometry."),
        ("trackCountAndAlignment", "Number and alignment of individual running tracks are not established by this package."),
        ("trackGaugeMM", "Track gauge is not part of the selected N02 source attributes."),
        ("curveRadiusM", "Curve radii and transition curves are not supplied."),
        ("cantMM", "Cant and cant run-off are not supplied."),
        ("gradientPermille", "Longitudinal gradients and vertical curves are not supplied."),
        ("elevationM", "Rail elevation is not supplied by the selected source features."),
        ("speedRestrictions", "Route-, direction-, vehicle-, and time-specific speed restrictions are not supplied."),
        ("signalsAndBlocks", "Signals, interlocking, block boundaries, and aspects are not supplied."),
        ("protectionSystems", "ATS/ATC and wayside protection equipment are not supplied."),
        ("platformsAndStopPoints", "Platform geometry, platform lengths, and stopping points are not supplied; station lines are not platforms."),
        ("switchesAndYards", "Turnouts, crossovers, yards, and station track layout are not supplied."),
        ("bridgesTunnelsCrossings", "Structure identities and exact chainage are not supplied in the selected extraction."),
        ("timetable", "Timetables and operating plans are not supplied."),
    ]

    field_provenance = {
        "packageLocalIdentifier": {
            "sourceIDs": [], "status": "PLACEHOLDER", "confidence": "UNRATED",
            "note": "The packageID and routeID are local identifiers created for this separate research package; they are not MLIT or operator route identifiers.",
        },
        "routeNameOperatorAndClass": {
            "sourceIDs": [SOURCE_ID], "status": "VERIFIED", "confidence": "HIGH",
            "sourceFields": ["N02_001", "N02_003", "N02_004"],
            "note": "Values are copied from the selected N02-25 route feature attributes.",
        },
        "stationNamesAndDatasetCodes": {
            "sourceIDs": [SOURCE_ID], "status": "VERIFIED", "confidence": "HIGH",
            "sourceFields": ["N02_005", "N02_005c", "N02_005g"],
            "note": "Names and dataset codes are copied from N02-25 station feature attributes; codes are not operator station identifiers.",
        },
        "extractedFeatureAndVertexCounts": {
            "sourceIDs": [SOURCE_ID], "status": "VERIFIED", "confidence": "HIGH",
            "note": "Counts are exact counts of the route/station features and route vertices selected from the pinned source archive; they are not railway engineering measurements.",
        },
        "sourceRecordIndices": {
            "sourceIDs": [SOURCE_ID], "status": "VERIFIED", "confidence": "HIGH",
            "note": "Zero-based feature positions in the pinned N02-25 GeoJSON collections, retained for provenance and reproducibility.",
        },
        "routeCoordinates": {
            "sourceIDs": [SOURCE_ID], "status": "VERIFIED", "confidence": "LOW",
            "note": "Coordinates preserve N02-25 source vertices in JGD2011/(B,L); low confidence describes their use as physical track alignment because the source line is generalized and no ground-survey error bound is given.",
        },
        "stationLineGeometry": {
            "sourceIDs": [SOURCE_ID], "status": "VERIFIED", "confidence": "LOW",
            "note": "Original source station LineStrings are preserved; they are not station-center points, platform shapes, or stop markers.",
        },
        "segmentOrientationAndContinuity": {
            "sourceIDs": [SOURCE_ID], "status": "ESTIMATED", "confidence": "LOW",
            "note": "The source line segments are ordered/oriented using shared endpoints to make a Kyoto-to-Yamato-Saidaiji reference chain.",
        },
        "localVertexChainageAndReferenceLength": {
            "sourceIDs": [SOURCE_ID], "status": "ESTIMATED", "confidence": "LOW",
            "note": "Derived from GRS80 inverse-geodesic distances between published vertices; not official railway chainage or measured track length.",
        },
        "stationOrderReferenceMeasure": {
            "sourceIDs": [SOURCE_ID], "status": "ESTIMATED", "confidence": "LOW",
            "note": "Median nearest-route-vertex measure of the source station-line vertices; used only to order stations, not as station-center chainage.",
        },
        "operationalAndTrackEngineeringFields": {
            "sourceIDs": [], "status": "UNKNOWN", "confidence": "UNRATED",
            "note": "Physical track, operations, platforms, signals, restrictions, structures, and timetable values are absent from this extraction and must not be inferred.",
        },
    }

    source_metadata = {
        "sourceID": SOURCE_ID,
        "title": "国土数値情報（鉄道データ）2025年度版 N02-25",
        "publisher": "国土交通省",
        "sourcePageURL": SOURCE_PAGE,
        "downloadURL": SOURCE_URL,
        "productSpecificationURL": PRODUCT_SPEC_URL,
        "termsURL": TERMS_URL,
        "retrievedAt": retrieved_at,
        "dataReferenceDate": "2025-12-31",
        "metadataDateStamp": "2026-03-06",
        "license": "Creative Commons Attribution 4.0 International (CC BY 4.0); the MLIT page also states open data conditions for 2020 onward.",
        "licenseURL": LICENSE_URL,
        "sourceArchiveSHA256": archive_hash,
        "coordinateReferenceSystem": "JGD2011 / (B, L)",
        "geoJSONCoordinateOrder": "[longitude, latitude]",
        "coordinateTransformation": "None. Source JGD2011 geographic coordinates are preserved without datum or projection transformation.",
        "metadataEquivalentScale": "1:25,000",
        "sourceGeometryDescription": "Generalized route/station line features; not individual surveyed physical track centerlines.",
        "sourceCoordinateQualityNote": "MLIT product-page quality rate is a comparison against referenced source data and is not a stated ground-survey metre error bound.",
        "sourceFeatureNames": {
            "route": "N02-25_RailroadSection.geojson",
            "station": "N02-25_Station.geojson",
        },
    }
    route_note = "The route line is preserved from MLIT N02-25 and joined by exact shared endpoints. Only direction, local chainage, station ordering measures, and package IDs are derived. This is a generalized map-scale reference line; it is not a measured individual rail or a driving route."
    route_package = {
        "schemaVersion": "1.0.0",
        "packageID": "kintetsu-kyoto-yamato-saidaiji-real-route-expansion-v1",
        "datasetKind": "REAL_WORLD_REFERENCE_ONLY",
        "notForDrivingPhysicsOrSignalling": True,
        "sources": [source_metadata],
        "route": {
            "routeID": ROUTE_ID,
            "name": field("近鉄京都線 京都—大和西大寺", "VERIFIED", [SOURCE_ID], "HIGH", "Route name, operator, and selected station names are present in the N02-25 route/station records."),
            "operator": field(ROUTE_OPERATOR, "VERIFIED", [SOURCE_ID], "HIGH", "N02-25 route attribute N02_004."),
            "sourceRouteName": field(ROUTE_NAME, "VERIFIED", [SOURCE_ID], "HIGH", "N02-25 route attribute N02_003."),
            "railwayClass": field("12", "VERIFIED", [SOURCE_ID], "HIGH", "N02-25 railway-class attribute N02_001; code 12 is ordinary railway per the official code list."),
            "datasetKind": "REAL_WORLD_REFERENCE_ONLY",
            "description": route_note,
            "orientation": "京都 → 大和西大寺",
            "geometryFile": "route_geometry.geojson",
            "segmentsFile": "route_segments.geojson",
            "routeGeometryFeatureID": "kintetsu-kyoto-yamato-saidaiji-route-reference-line",
            "sourceRouteFeatureCount": len(ordered_edges),
            "routeVertexCount": len(full_coords),
            "routeReferenceLineLengthM": field(
                round(total_length, 3), "ESTIMATED", [SOURCE_ID], "LOW",
                "Cumulative GRS80 ellipsoidal inverse-geodesic distance between published route-line vertices, rounded to 0.001 m. This is not track survey length or operator mileage; absolute position/generalization error is not quantified.",
            ),
            "officialRailwayChainageM": field(None, "UNKNOWN", [], "UNRATED", "No official station chainage or operational kilometer-post data is included in the selected source."),
            "physicalTrackLengthM": field(None, "UNKNOWN", [], "UNRATED", "The generalized route reference line is not measured rail length."),
            "stationCount": len(package_stations),
            "stations": package_stations,
            "operationalData": {
                key: field(None, "UNKNOWN", [], "UNRATED", reason)
                for key, reason in network_fields
            },
            "provenanceNote": route_note,
        },
        "processing": {
            "routeSelection": f"Filtered N02-25_RailroadSection and N02-25_Station by operator={ROUTE_OPERATOR!r}, route={ROUTE_NAME!r}; traversed the resulting one-component, unbranched, open endpoint chain from the endpoint matching {START_STATION} to the endpoint matching {END_STATION}.",
            "routeOrientation": "Source route segments were reversed only when needed to form a continuous Kyoto-to-Yamato-Saidaiji chain; coordinates themselves were not transformed.",
            "chainageComputation": "GRS80 ellipsoid inverse-geodesic between each consecutive published source vertex. Unit: metre. Values are local route-reference measures, not official railway chainage.",
            "stationOrdering": "Stations sorted by the median of nearest route-vertex measures for each source station-line vertex. The derived measure is only an ordering aid; source station LineStrings are retained and not converted to center points or platforms.",
            "provenance": "Original N02 attributes and source record indices are included in each extracted feature. New IDs are package identifiers, not MLIT feature IDs.",
        },
        "unknownFields": [item[0] for item in network_fields],
        "fieldProvenance": field_provenance,
    }

    route_geometry = {
        "type": "FeatureCollection",
        "name": ROUTE_ID,
        "metadata": {
            "sourceID": SOURCE_ID,
            "sourceURL": SOURCE_PAGE,
            "sourceArchiveURL": SOURCE_URL,
            "sourceArchiveSHA256": archive_hash,
            "retrievedAt": retrieved_at,
            "license": "CC BY 4.0",
            "licenseURL": LICENSE_URL,
            "coordinateReferenceSystem": "JGD2011 / (B, L)",
            "coordinateOrder": "[longitude, latitude]",
            "coordinateTransformation": "None; source coordinates preserved.",
            "lineDisclaimer": "Generalized route reference line; not an individual physical track centerline or survey.",
            "chainageUnit": "m",
            "chainageMethod": "Cumulative GRS80 inverse-geodesic between published vertices; not official track chainage.",
        },
        "features": geojson_features,
    }
    route_segments = {
        "type": "FeatureCollection",
        "name": ROUTE_ID + "_segments",
        "metadata": {
            "sourceID": SOURCE_ID,
            "sourceURL": SOURCE_PAGE,
            "sourceArchiveSHA256": archive_hash,
            "retrievedAt": retrieved_at,
            "license": "CC BY 4.0",
            "coordinateReferenceSystem": "JGD2011 / (B, L)",
            "coordinateOrder": "[longitude, latitude]",
            "coordinateTransformation": "None; source coordinates preserved.",
            "orientation": "京都 → 大和西大寺; individual source LineString vertex order may be reversed to create endpoint continuity.",
        },
        "features": segment_features,
    }

    DATA_DIR.mkdir(parents=True, exist_ok=True)
    (DATA_DIR / "route-package.json").write_text(json.dumps(route_package, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    (DATA_DIR / "route_geometry.geojson").write_text(json.dumps(route_geometry, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    (DATA_DIR / "route_segments.geojson").write_text(json.dumps(route_segments, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

    source_manifest = {
        "dataset": source_metadata,
        "extraction": {
            "routeFilter": {"N02_004": ROUTE_OPERATOR, "N02_003": ROUTE_NAME},
            "routeFeatureCount": len(ordered_edges),
            "stationFeatureCount": len(ordered_stations),
            "routeSourceRecordIndices": [edge["sourceIndex"] for edge in ordered_edges],
            "stationSourceRecordIndicesInRouteOrder": [station["sourceIndex"] for station in ordered_stations],
            "routeVertexCount": len(full_coords),
            "routeReferenceLineLengthM": round(total_length, 3),
            "routeReferenceLineLengthStatus": "ESTIMATED",
            "coordinateTransformation": "None",
            "distanceAlgorithm": "Vincenty inverse geodesic on GRS80 (a=6378137.0 m, 1/f=298.257222101)",
            "distanceRounding": "0.001 m in output; extra decimals do not imply source positional accuracy",
            "stationOrderMeasureMethod": "Median nearest route-vertex measure for source station-line vertices; ordering aid only.",
            "statusCaution": "No metre-valued absolute position error bound is reported by this extraction; source-coordinate QA is not ground-truth track survey accuracy.",
        },
        "fieldProvenance": field_provenance,
        "attribution": f"出典：国土交通省「国土数値情報（鉄道データ）2025年度版 N02-25」({SOURCE_PAGE})（{retrieved_at}取得）。近鉄京都線・京都—大和西大寺の路線・駅線形を抽出し、線分順序を連結方向に整理、GRS80測地距離による局所参照chainageと駅順用測定値を付加して加工。CC BY 4.0。",
        "usageNotes": "Attribute MLIT and the dataset page, and state that this subset was extracted and processed. Do not imply MLIT authored, surveyed, or certified the derivative simulator geometry.",
    }
    (DATA_DIR / "source_manifest.json").write_text(json.dumps(source_manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    return {
        "routeFeatureCount": len(ordered_edges),
        "stationCount": len(ordered_stations),
        "vertexCount": len(full_coords),
        "lengthM": round(total_length, 3),
        "start": full_coords[0],
        "end": full_coords[-1],
    }


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--archive", type=Path, help="Use a local official N02-25_GML.zip; otherwise download to a temporary path.")
    parser.add_argument("--retrieved-at", default=date.today().isoformat(), help="Date the source archive was retrieved, YYYY-MM-DD.")
    args = parser.parse_args()
    if args.archive:
        result = build(args.archive, args.retrieved_at)
    else:
        with tempfile.TemporaryDirectory(prefix="n02-25-route-") as temp_dir:
            archive_path = Path(temp_dir) / "N02-25_GML.zip"
            download_source(archive_path)
            result = build(archive_path, args.retrieved_at)
    print(json.dumps(result, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
