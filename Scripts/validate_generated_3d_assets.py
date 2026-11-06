#!/usr/bin/env python3
"""Validate bundled procedural GLBs and station layouts without Apple frameworks."""
from __future__ import annotations

import hashlib
import json
import struct
import sys
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[1]
ASSET_ROOT = ROOT / "Packages/RailwaySceneFidelity/Sources/RailwaySceneFidelity/Resources/Generated3D"


def fail(message: str) -> None:
    print(f"FAIL: {message}", file=sys.stderr)
    raise SystemExit(1)


def require(ok: bool, message: str) -> None:
    if not ok:
        fail(message)


def glb_document(path: Path) -> tuple[dict[str, Any], bytes]:
    data = path.read_bytes()
    require(len(data) >= 20, f"truncated GLB header: {path}")
    magic, version, declared = struct.unpack_from("<4sII", data, 0)
    require(magic == b"glTF" and version == 2, f"not GLB 2.0: {path}")
    require(declared == len(data), f"declared GLB length mismatch: {path}")
    cursor = 12
    document = None
    binary = None
    while cursor < len(data):
        require(cursor + 8 <= len(data), f"truncated GLB chunk header: {path}")
        length, chunk_type = struct.unpack_from("<I4s", data, cursor)
        cursor += 8
        require(cursor + length <= len(data), f"chunk exceeds GLB boundary: {path}")
        chunk = data[cursor:cursor + length]
        cursor += length
        if chunk_type == b"JSON":
            document = json.loads(chunk.rstrip(b" \t\r\n\x00"))
        elif chunk_type == b"BIN\x00":
            binary = chunk
    require(isinstance(document, dict), f"missing GLB JSON: {path}")
    require(isinstance(binary, bytes), f"missing embedded GLB binary: {path}")
    require(document.get("asset", {}).get("version") == "2.0", f"unsupported glTF asset version: {path}")
    buffers = document.get("buffers", [])
    require(len(buffers) == 1 and "uri" not in buffers[0], f"expected one embedded buffer: {path}")
    require(0 <= buffers[0].get("byteLength", -1) <= len(binary), f"invalid embedded buffer length: {path}")
    return document, binary


def external_uris(value: Any) -> int:
    if isinstance(value, dict):
        return sum((1 if k == "uri" and isinstance(v, str) and not v.startswith("data:") else 0) + external_uris(v)
                   for k, v in value.items())
    if isinstance(value, list):
        return sum(external_uris(v) for v in value)
    return 0


def accessor_values(document: dict[str, Any], binary: bytes, accessor_index: int, type_name: str) -> tuple[int, int, bool, list[tuple[Any, ...]]]:
    accessors = document.get("accessors", [])
    views = document.get("bufferViews", [])
    require(0 <= accessor_index < len(accessors), "accessor index out of range")
    accessor = accessors[accessor_index]
    require(accessor.get("type") == type_name, f"expected {type_name} accessor")
    component = accessor.get("componentType")
    count = accessor.get("count")
    view_index = accessor.get("bufferView")
    require(isinstance(count, int) and count > 0, "invalid accessor count")
    require(isinstance(view_index, int) and 0 <= view_index < len(views), "invalid accessor bufferView")
    view = views[view_index]
    offset = view.get("byteOffset", 0) + accessor.get("byteOffset", 0)
    normalized = accessor.get("normalized", False)
    components = 4 if type_name == "VEC4" else 3
    size = 4 if component == 5126 else 1 if component == 5121 else 2 if component == 5123 else 0
    require(size > 0, f"unsupported accessor component type {component}")
    stride = view.get("byteStride", components * size)
    require(stride >= components * size, "accessor stride too short")
    values = []
    for i in range(count):
        start = offset + i * stride
        require(start >= 0 and start + components * size <= len(binary), "accessor exceeds embedded buffer")
        if component == 5126:
            values.append(struct.unpack_from("<" + "f" * components, binary, start))
        elif component == 5121:
            raw = struct.unpack_from("<" + "B" * components, binary, start)
            values.append(tuple(v / 255.0 for v in raw) if normalized else raw)
        elif component == 5123:
            raw = struct.unpack_from("<" + "H" * components, binary, start)
            values.append(tuple(v / 65535.0 for v in raw) if normalized else raw)
    return component, count, bool(normalized), values


def validate_glb(path: Path) -> tuple[int, int, str]:
    document, binary = glb_document(path)
    require(external_uris(document) == 0, f"external resource URI in {path.relative_to(ASSET_ROOT)}")
    require(not document.get("skins") and not document.get("animations"), f"unexpected rig/animation in {path.relative_to(ASSET_ROOT)}")
    for node in document.get("nodes", []):
        require("matrix" not in node, f"unsupported node matrix in {path.relative_to(ASSET_ROOT)}")

    primitive_count = 0
    colored_count = 0
    for mesh in document.get("meshes", []):
        for primitive in mesh.get("primitives", []):
            primitive_count += 1
            require(primitive.get("mode", 4) == 4, f"non-triangle primitive in {path.relative_to(ASSET_ROOT)}")
            attributes = primitive.get("attributes", {})
            position_index = attributes.get("POSITION")
            require(isinstance(position_index, int), f"missing POSITION in {path.relative_to(ASSET_ROOT)}")
            _, position_count, _, _ = accessor_values(document, binary, position_index, "VEC3")
            color_index = attributes.get("COLOR_0")
            require(isinstance(color_index, int), f"missing COLOR_0 in {path.relative_to(ASSET_ROOT)}")
            component, color_count, normalized, colors = accessor_values(document, binary, color_index, "VEC4")
            require(color_count == position_count, f"COLOR_0 vertex count mismatch in {path.relative_to(ASSET_ROOT)}")
            require(component == 5126 or (component == 5121 and normalized),
                    f"COLOR_0 encoding unsupported by runtime loader in {path.relative_to(ASSET_ROOT)}")
            require(all(color == colors[0] for color in colors[1:]),
                    f"nonuniform per-vertex color would be flattened by runtime loader: {path.relative_to(ASSET_ROOT)}")
            colored_count += 1
    require(primitive_count > 0 and colored_count == primitive_count, f"missing mesh/color data in {path.relative_to(ASSET_ROOT)}")
    digest = hashlib.sha256(path.read_bytes()).hexdigest()
    return primitive_count, colored_count, digest


def main() -> None:
    glbs = sorted(ASSET_ROOT.rglob("*.glb"))
    require(bool(glbs), "no GLB resources found")
    relative_paths = [path.relative_to(ASSET_ROOT).as_posix() for path in glbs]
    require(len(relative_paths) == len(set(relative_paths)), "duplicate GLB resource path")
    hashes: dict[str, str] = {}
    total_primitives = 0
    for path, relative in zip(glbs, relative_paths):
        primitives, colors, digest = validate_glb(path)
        require(digest not in hashes, f"duplicate GLB content: {relative} duplicates {hashes.get(digest)}")
        hashes[digest] = relative
        total_primitives += primitives

    manifest = json.loads((ASSET_ROOT / "asset_manifest.json").read_text(encoding="utf-8"))
    declared = [model.get("file") for model in manifest.get("models", [])]
    require(len(declared) == len(set(declared)), "duplicate asset_manifest model entry")
    require(set(declared) == set(relative_paths), "asset_manifest file list differs from bundled GLBs")
    require(manifest.get("provenance", {}).get("externalResourceURICount") == 0, "manifest does not record zero external URIs")

    station_doc = json.loads((ASSET_ROOT / "station_layouts_32.json").read_text(encoding="utf-8"))
    stations = station_doc.get("stations", [])
    require(station_doc.get("stationCount") == 32 and len(stations) == 32, "station layout count is not 32")
    ids = [station.get("stationId") for station in stations]
    require(len(ids) == len(set(ids)), "duplicate station IDs")
    require(sum(station.get("lineId") == "MAIN" for station in stations) == 28, "expected 28 mainline stations")
    require(sum(station.get("lineId") == "BRANCH" for station in stations) == 4, "expected 4 branch stations")
    for station in stations:
        require(station.get("platformCount") == len(station.get("platforms", [])),
                f"platform count mismatch for {station.get('stationId')}")
    hub = next((station for station in stations if station.get("stationId") == "S12"), None)
    require(hub is not None and hub.get("trackCount") == 5 and hub.get("platformCount") == 4,
            "five-track/four-platform hub topology missing")

    selected = [path for path in glbs if path.parent.name == "HighFidelityAssets"]
    require({path.name for path in selected} == {"commuter_train_car_detailed.glb", "driver_cab_interior_detailed.glb"},
            "unexpected add-on high-fidelity resource set; only two selected models are intended")
    print(f"PASS: {len(glbs)} unique embedded GLB 2.0 files, {total_primitives} colored triangle primitives, zero external URIs")
    print("PASS: every primitive has loader-compatible uniform COLOR_0; selected add-on car/cab resources appear once")
    print("PASS: 32 unique station layouts (28 mainline, 4 branch), platform counts match, S12 is 5-track/4-platform")

    # 2026-11-07 scenery/station quality revision checks.
    # (a) All nine original scenery textures must be 256x256 PNGs
    # (IHDR width/height are big-endian uint32 at bytes 16..24).
    texture_root = ROOT / "Packages/RailwaySceneFidelity/Sources/RailwaySceneFidelity/Resources"
    textures = sorted(texture_root.glob("scenery_*.png"))
    require(len(textures) == 9, f"expected 9 scenery textures, found {len(textures)}")
    for texture in textures:
        header = texture.read_bytes()[:24]
        require(header[:8] == b"\x89PNG\r\n\x1a\n", f"not a PNG: {texture.name}")
        width, height = struct.unpack(">II", header[16:24])
        require((width, height) == (256, 256), f"scenery texture is {width}x{height}, expected 256x256: {texture.name}")
    print("PASS: 9 original scenery textures are 256x256 PNGs")

    # (b) Enhancement meshes must exist in all six enhance-target GLBs.
    station_prefixes = ("bench_", "platform_sign_", "canopy_fixture_", "vending_", "bin_", "white_line_", "end_fence_")
    corridor_prefixes = ("road_marking_", "street_light_", "utility_pole_", "hedge_", "extra_tree_")
    enhancement_targets = {
        "station_side_platform.glb": station_prefixes,
        "station_island_platform.glb": station_prefixes,
        "station_3track_passing.glb": station_prefixes,
        "station_4track_major.glb": station_prefixes,
        "station_terminal.glb": station_prefixes,
        "suburban_corridor_modules.glb": corridor_prefixes,
    }
    enhancement_total = 0
    for filename, prefixes in enhancement_targets.items():
        document, _binary = glb_document(ASSET_ROOT / filename)
        names = [mesh.get("name", "") for mesh in document.get("meshes", [])]
        for prefix in prefixes:
            require(any(name.startswith(prefix) for name in names),
                    f"enhancement meshes missing ({prefix}*) in {filename}")
        enhancement_total += sum(1 for name in names if name.startswith(prefixes))
    print(f"PASS: enhancement meshes present in all 6 enhanced GLBs ({enhancement_total} added meshes)")

    # (c) The 5-track hub uses a different format (single mesh, float
    # colors, materials) and is enhanced through its generator instead:
    # confirm the added furniture material groups exist.
    hub_document, _hub_binary = glb_document(ASSET_ROOT / "station_5track_4platform.glb")
    hub_materials = {material.get("name") for material in hub_document.get("materials", [])}
    require({"fictional_vending", "fictional_vendinglass", "fictional_bin"} <= hub_materials,
            "5-track hub is missing the generator-added furniture material groups")
    print("PASS: 5-track/4-platform hub contains generator-added furniture (vending/bin material groups)")

if __name__ == "__main__":
    main()
