#!/usr/bin/env python3
"""Add platform furniture and corridor details to the procedural GLBs.

The six target GLBs (five station archetypes plus the suburban corridor
module) are rebuilt in the exact format they already use:

- one mesh per part, one triangle primitive per mesh;
- every *new* part is a box: 8 vertices in binary-counting corner order
  (x = bit 4, y = bit 2, z = bit 1) with the shared 36-index uint32
  pattern used by the existing box meshes;
- COLOR_0 is a single uniform color per mesh, stored as normalized
  ubyte VEC4 (the encoding the runtime loader supports);
- nodes are a `world` node whose children are one node per mesh;
- meshes keep `extras` with shape/extents for boxes.

Existing meshes are preserved verbatim: name, extras, positions, indices
and color are read from the source GLB and written back unchanged (some
existing parts such as canopy lights and tree trunks are not boxes; their
geometry is copied, not approximated). Only new meshes are appended.
Re-running the script first drops previously added enhancement meshes,
so it is idempotent.

All added objects are original, fictional PLACEHOLDER game furniture.
No third-party mesh, texture, logo, or image is used.
"""
from __future__ import annotations

import json
import struct
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
ASSET_ROOT = ROOT / "Packages/RailwaySceneFidelity/Sources/RailwaySceneFidelity/Resources/Generated3D"

STATION_FILES = [
    "station_side_platform.glb",
    "station_island_platform.glb",
    "station_3track_passing.glb",
    "station_4track_major.glb",
    "station_terminal.glb",
]
CORRIDOR_FILE = "suburban_corridor_modules.glb"

BOX_INDICES = (
    1, 3, 0, 4, 1, 0, 0, 3, 2, 2, 4, 0,
    1, 7, 3, 5, 1, 4, 5, 7, 1, 3, 7, 2,
    6, 4, 2, 2, 7, 6, 6, 5, 4, 7, 5, 6,
)

ENHANCEMENT_PREFIXES = (
    "bench_", "platform_sign_", "canopy_fixture_", "vending_", "bin_",
    "white_line_", "end_fence_", "road_marking_", "street_light_",
    "utility_pole_", "hedge_", "extra_tree_",
)

# Fictional furniture palette (RGBA bytes).
WOOD = (150, 110, 70, 255)
DARK_STEEL = (60, 56, 50, 255)
SIGN_BLUE = (20, 82, 117, 255)
WHITE = (240, 240, 235, 255)
FIXTURE_WHITE = (245, 245, 238, 255)
VENDING_RED = (168, 44, 52, 255)
VENDING_GLASS = (30, 34, 40, 255)
BIN_GREEN = (52, 74, 58, 255)
LINE_WHITE = (235, 235, 228, 255)
FENCE_GRAY = (200, 200, 195, 255)
POLE_STEEL = (80, 84, 88, 255)
LAMP_WARM = (250, 240, 200, 255)
POLE_WOOD = (105, 80, 55, 255)


# --- GLB reading ------------------------------------------------------------

def parse_glb(data: bytes) -> tuple[dict, bytes]:
    magic, version, _declared = struct.unpack_from("<4sII", data, 0)
    if magic != b"glTF" or version != 2:
        raise ValueError("not a GLB 2.0 file")
    cursor = 12
    document = None
    binary = None
    while cursor < len(data):
        length, chunk_type = struct.unpack_from("<I4s", data, cursor)
        cursor += 8
        chunk = data[cursor:cursor + length]
        cursor += length
        if chunk_type == b"JSON":
            document = json.loads(chunk.rstrip(b" \t\r\n\x00"))
        elif chunk_type == b"BIN\x00":
            binary = chunk
    if document is None or binary is None:
        raise ValueError("missing GLB chunks")
    return document, binary


def _accessor_raw(document: dict, binary: bytes, accessor_index: int) -> tuple[dict, bytes]:
    accessor = document["accessors"][accessor_index]
    view = document["bufferViews"][accessor["bufferView"]]
    component_size = {5120: 1, 5121: 1, 5122: 2, 5123: 2, 5125: 4, 5126: 4}[accessor["componentType"]]
    components = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4}[accessor["type"]]
    count = accessor["count"]
    stride = view.get("byteStride", component_size * components)
    start = view.get("byteOffset", 0) + accessor.get("byteOffset", 0)
    raw = bytearray()
    for i in range(count):
        s = start + i * stride
        raw.extend(binary[s:s + component_size * components])
    return accessor, bytes(raw)


def extract_meshes(document: dict, binary: bytes) -> list[dict]:
    """Return [{name, extras, positions, indices, color}] for every mesh."""
    meshes = []
    for mesh in document["meshes"]:
        primitive = mesh["primitives"][0]
        attributes = primitive["attributes"]
        pos_accessor, pos_raw = _accessor_raw(document, binary, attributes["POSITION"])
        positions = [struct.unpack_from("<3f", pos_raw, i * 12) for i in range(pos_accessor["count"])]
        idx_accessor, idx_raw = _accessor_raw(document, binary, primitive["indices"])
        index_format = {5125: "I", 5123: "H", 5121: "B"}[idx_accessor["componentType"]]
        indices = list(struct.unpack_from("<" + index_format * idx_accessor["count"], idx_raw))
        color_accessor, color_raw = _accessor_raw(document, binary, attributes["COLOR_0"])
        if color_accessor["componentType"] == 5121:
            color = tuple(color_raw[0:4])
        else:  # float colors -> bytes
            floats = struct.unpack_from("<4f", color_raw, 0)
            color = tuple(int(round(c * 255)) for c in floats)
        meshes.append({
            "name": mesh["name"],
            "extras": mesh.get("extras"),
            "positions": [tuple(p) for p in positions],
            "indices": indices,
            "color": color,
        })
    return meshes


def box_mesh(name: str, center: tuple[float, float, float], size: tuple[float, float, float], color) -> dict:
    cx, cy, cz = center
    sx, sy, sz = size
    lo = (cx - sx / 2, cy - sy / 2, cz - sz / 2)
    hi = (cx + sx / 2, cy + sy / 2, cz + sz / 2)
    positions = []
    for i in range(8):  # binary-counting corner order: x=bit4, y=bit2, z=bit1
        positions.append((
            hi[0] if i & 4 else lo[0],
            hi[1] if i & 2 else lo[1],
            hi[2] if i & 1 else lo[2],
        ))
    return {
        "name": name,
        "extras": {"shape": "box", "extents": [sx, sy, sz]},
        "positions": positions,
        "indices": list(BOX_INDICES),
        "color": tuple(color),
    }


# --- GLB writing --------------------------------------------------------------

def build_glb(asset: dict, meshes: list[dict]) -> bytes:
    binary = bytearray()
    buffer_views = []
    accessors = []
    out_meshes = []

    def append_bytes(data: bytes) -> int:
        while len(binary) % 4:
            binary.append(0)
        offset = len(binary)
        binary.extend(data)
        buffer_views.append({"buffer": 0, "byteOffset": offset, "byteLength": len(data)})
        return len(buffer_views) - 1

    for mesh in meshes:
        positions = mesh["positions"]
        indices = mesh["indices"]
        color = mesh["color"]
        i_view = append_bytes(b"".join(struct.pack("<I", i) for i in indices))
        p_view = append_bytes(b"".join(struct.pack("<3f", *p) for p in positions))
        c_view = append_bytes(bytes(color) * len(positions))
        i_accessor = len(accessors)
        accessors.append({"componentType": 5125, "type": "SCALAR", "bufferView": i_view,
                          "count": len(indices), "max": [max(indices)], "min": [min(indices)]})
        by_axis = list(zip(*positions))
        p_accessor = len(accessors)
        accessors.append({"componentType": 5126, "type": "VEC3", "byteOffset": 0, "bufferView": p_view,
                          "count": len(positions),
                          "max": [max(a) for a in by_axis], "min": [min(a) for a in by_axis]})
        c_accessor = len(accessors)
        accessors.append({"componentType": 5121, "normalized": True, "type": "VEC4", "byteOffset": 0,
                          "bufferView": c_view, "count": len(positions),
                          "max": list(color), "min": list(color)})
        out_mesh = {"name": mesh["name"]}
        if mesh.get("extras") is not None:
            out_mesh["extras"] = mesh["extras"]
        out_mesh["primitives"] = [{"attributes": {"POSITION": p_accessor, "COLOR_0": c_accessor},
                                   "indices": i_accessor, "mode": 4}]
        out_meshes.append(out_mesh)

    nodes = [{"name": "world", "children": list(range(1, len(meshes) + 1))}]
    nodes.extend({"name": mesh["name"], "mesh": i} for i, mesh in enumerate(meshes))
    document = {
        "scene": 0,
        "scenes": [{"nodes": [0]}],
        "asset": asset,
        "accessors": accessors,
        "meshes": out_meshes,
        "nodes": nodes,
        "buffers": [{"byteLength": len(binary)}],
        "bufferViews": buffer_views,
    }
    json_chunk = json.dumps(document, separators=(",", ":")).encode("utf-8")
    json_chunk += b" " * ((-len(json_chunk)) % 4)
    binary_chunk = bytes(binary) + b"\x00" * ((-len(binary)) % 4)
    chunks = struct.pack("<I4s", len(json_chunk), b"JSON") + json_chunk
    chunks += struct.pack("<I4s", len(binary_chunk), b"BIN\x00") + binary_chunk
    return struct.pack("<4sII", b"glTF", 2, 12 + len(chunks)) + chunks


# --- enhancement placement ----------------------------------------------------

def bounds(mesh: dict) -> tuple[tuple[float, float, float], tuple[float, float, float]]:
    by_axis = list(zip(*mesh["positions"]))
    return tuple(min(a) for a in by_axis), tuple(max(a) for a in by_axis)


def fmt_x(x: float) -> str:
    return str(int(x)) if float(x).is_integer() else str(x)


def station_additions(meshes: list[dict]) -> list[dict]:
    by_name = {m["name"]: m for m in meshes}
    platforms = []
    for name, mesh in by_name.items():
        if name.startswith("platform_") and name.split("_", 1)[1].isdigit():
            lo, hi = bounds(mesh)
            platforms.append({"index": name.split("_", 1)[1], "lo": lo, "hi": hi,
                              "center_z": (lo[2] + hi[2]) / 2, "width": hi[2] - lo[2]})
    tactiles = []
    for name, mesh in by_name.items():
        if name.startswith("tactile_strip_"):
            lo, hi = bounds(mesh)
            tactiles.append({"lo": lo, "hi": hi, "center_z": (lo[2] + hi[2]) / 2})

    additions: list[dict] = []
    top = 0.22  # platform slab top in every archetype module
    for platform in platforms:
        p = platform["index"]
        zc = platform["center_z"]
        # Track side = direction of the nearest tactile strip of this platform.
        own_tactiles = [t for t in tactiles if platform["lo"][2] - 0.6 <= t["center_z"] <= platform["hi"][2] + 0.6]
        if own_tactiles:
            nearest = min(own_tactiles, key=lambda t: abs(t["center_z"] - zc))
            track_dir = 1.0 if nearest["center_z"] >= zc else -1.0
        else:
            track_dir = 1.0

        # Benches between the canopy columns (columns sit at x=-16,-8,0,8,16).
        for x in (-12, -4, 4, 12):
            xs = fmt_x(x)
            additions.append(box_mesh(f"bench_{p}_{xs}_seat", (x, top + 0.49, zc), (1.8, 0.08, 0.45), WOOD))
            additions.append(box_mesh(f"bench_{p}_{xs}_back", (x, top + 0.78, zc - track_dir * 0.19), (1.8, 0.5, 0.06), WOOD))
            additions.append(box_mesh(f"bench_{p}_{xs}_leg_l", (x - 0.7, top + 0.225, zc), (0.08, 0.45, 0.4), DARK_STEEL))
            additions.append(box_mesh(f"bench_{p}_{xs}_leg_r", (x + 0.7, top + 0.225, zc), (0.08, 0.45, 0.4), DARK_STEEL))
        # Hanging station sign boards under the canopy roof (roof underside y=3.16).
        for x in (-6, 6):
            xs = fmt_x(x)
            additions.append(box_mesh(f"platform_sign_{p}_{xs}_board", (x, 2.65, zc), (2.2, 0.6, 0.08), SIGN_BLUE))
            additions.append(box_mesh(f"platform_sign_{p}_{xs}_band", (x, 2.65, zc), (2.2, 0.2, 0.1), WHITE))
            additions.append(box_mesh(f"platform_sign_{p}_{xs}_hanger_l", (x - 0.8, 3.055, zc), (0.05, 0.21, 0.05), DARK_STEEL))
            additions.append(box_mesh(f"platform_sign_{p}_{xs}_hanger_r", (x + 0.8, 3.055, zc), (0.05, 0.21, 0.05), DARK_STEEL))
        # Elongated canopy light fixtures (existing 0.16 cubes stay as-is).
        for x in (-10, -5, 0, 5, 10):
            additions.append(box_mesh(f"canopy_fixture_{p}_{fmt_x(x)}", (x, 3.08, zc), (1.6, 0.12, 0.24), FIXTURE_WHITE))
        # Vending machine near the platform end, slightly behind centre.
        if platform["width"] >= 5:
            vz = zc + 1.0
            glass_z = vz - 0.34
        else:
            vz = zc
            glass_z = vz + track_dir * 0.34
        additions.append(box_mesh(f"vending_{p}_body", (17.5, top + 0.95, vz), (1.0, 1.9, 0.7), VENDING_RED))
        additions.append(box_mesh(f"vending_{p}_glass", (17.5, top + 1.13, glass_z), (0.8, 1.1, 0.04), VENDING_GLASS))
        # Trash bin near the x=-16 column, offset from the centre line.
        additions.append(box_mesh(f"bin_{p}", (-17.5, top + 0.3, zc + 0.6), (0.45, 0.6, 0.45), BIN_GREEN))
        # End fences across the platform width at both ends.
        for label, x in (("neg", -20.8), ("pos", 20.8)):
            additions.append(box_mesh(f"end_fence_{p}_{label}_post_a", (x, top + 0.425, platform["lo"][2] + 0.3), (0.06, 0.85, 0.06), FENCE_GRAY))
            additions.append(box_mesh(f"end_fence_{p}_{label}_post_b", (x, top + 0.425, platform["hi"][2] - 0.3), (0.06, 0.85, 0.06), FENCE_GRAY))
            additions.append(box_mesh(f"end_fence_{p}_{label}_rail_top", (x, top + 0.82, zc), (0.05, 0.06, platform["width"] - 0.6), FENCE_GRAY))
            additions.append(box_mesh(f"end_fence_{p}_{label}_rail_mid", (x, top + 0.43, zc), (0.04, 0.05, platform["width"] - 0.6), FENCE_GRAY))

    # White safety lines: 0.55 m inward (toward the platform centre) from
    # each tactile strip, derived per strip so island/side edges both work.
    for i, tactile in enumerate(tactiles):
        owner = min(platforms, key=lambda pl: 0 if pl["lo"][2] - 0.6 <= tactile["center_z"] <= pl["hi"][2] + 0.6 else 1e9)
        inward = 1.0 if owner["center_z"] >= tactile["center_z"] else -1.0
        line_z = tactile["center_z"] + inward * 0.55
        additions.append(box_mesh(f"white_line_{owner['index']}_{i}", (0, 0.2375, line_z), (42, 0.015, 0.12), LINE_WHITE))
    return additions


def corridor_additions(meshes: list[dict]) -> list[dict]:
    by_name = {m["name"]: m for m in meshes}
    canopy_color = next(m["color"] for n, m in by_name.items() if n.startswith("tree_canopy"))
    trunk_color = next(m["color"] for n, m in by_name.items() if n.startswith("tree_trunk"))
    road_lo, road_hi = bounds(by_name["road_surface"])
    road_top = road_hi[1]

    additions: list[dict] = []
    # Dashed centre line on the road (road spans z=-12..-4, centre z=-8).
    for x in range(-20, 21, 4):
        additions.append(box_mesh(f"road_marking_{fmt_x(x)}", (x, road_top + 0.0125, -8), (2, 0.025, 0.18), LINE_WHITE))
    # Street lights on the sidewalk (sidewalk spans z=-4..-2, top y=0.13).
    for x in (-15, -5, 5, 15):
        xs = fmt_x(x)
        additions.append(box_mesh(f"street_light_{xs}_pole", (x, 0.13 + 2.2, -2.5), (0.09, 4.4, 0.09), POLE_STEEL))
        additions.append(box_mesh(f"street_light_{xs}_arm", (x, 4.45, -3.1), (0.07, 0.07, 1.3), POLE_STEEL))
        additions.append(box_mesh(f"street_light_{xs}_lamp", (x, 4.38, -3.7), (0.5, 0.08, 0.24), LAMP_WARM))
    # Utility poles on the far strip between road edge (z=-12) and fence (z=-12.94).
    for x in (-16, -5.5, 5, 15.5):
        xs = fmt_x(x)
        additions.append(box_mesh(f"utility_pole_{xs}_pole", (x, 3.25, -12.6), (0.14, 6.5, 0.14), POLE_WOOD))
        additions.append(box_mesh(f"utility_pole_{xs}_arm_top", (x, 5.9, -12.6), (1.8, 0.1, 0.1), POLE_WOOD))
        additions.append(box_mesh(f"utility_pole_{xs}_arm_low", (x, 5.4, -12.6), (1.4, 0.1, 0.1), POLE_WOOD))
    # Low hedges in front of the buildings (buildings end at z<=5.03; hedge at z=5.5).
    for i, (x0, x1) in enumerate(((-12.5, -5.5), (-4.5, 4.5), (7, 13))):
        additions.append(box_mesh(f"hedge_{i}", ((x0 + x1) / 2, 0.35, 5.5), (x1 - x0, 0.7, 0.5), canopy_color))
    # Extra trees in the gaps of the existing tree row (same layered style:
    # trunk plus three canopy cubes copied from the existing proportions).
    for x in (-9, 0, 10):
        xs = fmt_x(x)
        zc = 10.5
        additions.append(box_mesh(f"extra_tree_trunk_{xs}", (x, 1.1, zc), (0.35, 2.2, 0.35), trunk_color))
        additions.append(box_mesh(f"extra_tree_canopy_{xs}_3.3", (x, 3.3, zc), (2.7, 2.7, 1.24), canopy_color))
        additions.append(box_mesh(f"extra_tree_canopy_{xs}_4.2", (x, 4.2, zc), (2.0, 2.0, 1.24), canopy_color))
        additions.append(box_mesh(f"extra_tree_canopy_{xs}_4.9", (x, 4.9, zc), (1.24, 1.24, 1.24), canopy_color))
    return additions


def enhance(path: Path, is_corridor: bool) -> tuple[int, int]:
    document, binary = parse_glb(path.read_bytes())
    meshes = extract_meshes(document, binary)
    kept = [m for m in meshes if not m["name"].startswith(ENHANCEMENT_PREFIXES)]
    additions = corridor_additions(kept) if is_corridor else station_additions(kept)
    rebuilt = build_glb(document["asset"], kept + additions)
    # Self-check: existing meshes must survive the rebuild byte-identically
    # in name, positions, indices and color.
    check_doc, check_binary = parse_glb(rebuilt)
    check_meshes = extract_meshes(check_doc, check_binary)
    if len(check_meshes) != len(kept) + len(additions):
        raise ValueError(f"{path.name}: mesh count mismatch after rebuild")
    for original, restored in zip(kept, check_meshes):
        if (original["name"] != restored["name"] or original["indices"] != restored["indices"]
                or original["color"] != restored["color"]
                or any(abs(a - b) > 1e-6 for p, q in zip(original["positions"], restored["positions"]) for a, b in zip(p, q))):
            raise ValueError(f"{path.name}: existing mesh {original['name']} changed during rebuild")
    path.write_bytes(rebuilt)
    return len(kept), len(additions)


def main() -> None:
    total_added = 0
    for name in STATION_FILES:
        kept, added = enhance(ASSET_ROOT / name, is_corridor=False)
        total_added += added
        print(f"{name}: kept {kept} meshes, added {added} enhancement meshes")
    kept, added = enhance(ASSET_ROOT / CORRIDOR_FILE, is_corridor=True)
    total_added += added
    print(f"{CORRIDOR_FILE}: kept {kept} meshes, added {added} enhancement meshes")
    print(f"total enhancement meshes added: {total_added}")


if __name__ == "__main__":
    main()
