#!/usr/bin/env python3
"""Generate an original low-poly 5-track / 4-platform fictional station GLB.

No third-party mesh, texture, logo, or image is used. Coordinates are metres,
Y-up, with station longitudinal axis +X. Uses only the Python standard library.
"""
from __future__ import annotations

import argparse
import json
import math
import struct
from collections import defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DEFAULT_OUT = ROOT / "Packages/RailwaySceneFidelity/Sources/RailwaySceneFidelity/Resources/Generated3D/station_5track_4platform.glb"

# Colors are deliberately fictional and are embedded as per-vertex RGBA values.
COLORS = {
    "gravel": (0.34, 0.35, 0.34, 1.0),
    "rail": (0.60, 0.65, 0.67, 1.0),
    "sleeper": (0.30, 0.24, 0.18, 1.0),
    "concrete": (0.58, 0.61, 0.60, 1.0),
    "tactile": (0.91, 0.72, 0.18, 1.0),
    "canopy": (0.21, 0.31, 0.36, 1.0),
    "roof": (0.24, 0.34, 0.40, 1.0),
    "building": (0.74, 0.70, 0.61, 1.0),
    "glass": (0.30, 0.59, 0.69, 0.82),
    "sign": (0.15, 0.35, 0.42, 1.0),
    "white": (0.88, 0.88, 0.82, 1.0),
    # 2026-11-07 scenery/station quality additions (fictional furniture).
    "vending": (0.66, 0.17, 0.20, 1.0),
    "vendinglass": (0.12, 0.13, 0.16, 1.0),
    "bin": (0.20, 0.29, 0.23, 1.0),
}

class StationMesh:
    def __init__(self) -> None:
        self.groups = defaultdict(lambda: {"positions": [], "normals": [], "indices": []})
        self.box_count = 0

    def box(self, material: str, center: tuple[float, float, float], size: tuple[float, float, float]) -> None:
        cx, cy, cz = center
        sx, sy, sz = (v / 2 for v in size)
        faces = [
            ((1, 0, 0), ((sx, -sy, -sz), (sx, sy, -sz), (sx, sy, sz), (sx, -sy, sz))),
            ((-1, 0, 0), ((-sx, -sy, sz), (-sx, sy, sz), (-sx, sy, -sz), (-sx, -sy, -sz))),
            ((0, 1, 0), ((-sx, sy, -sz), (-sx, sy, sz), (sx, sy, sz), (sx, sy, -sz))),
            ((0, -1, 0), ((-sx, -sy, sz), (-sx, -sy, -sz), (sx, -sy, -sz), (sx, -sy, sz))),
            ((0, 0, 1), ((-sx, -sy, sz), (sx, -sy, sz), (sx, sy, sz), (-sx, sy, sz))),
            ((0, 0, -1), ((sx, -sy, -sz), (-sx, -sy, -sz), (-sx, sy, -sz), (sx, sy, -sz))),
        ]
        group = self.groups[material]
        for normal, corners in faces:
            base = len(group["positions"])
            group["positions"].extend((cx + x, cy + y, cz + z) for x, y, z in corners)
            group["normals"].extend([normal] * 4)
            group["indices"].extend((base, base + 1, base + 2, base, base + 2, base + 3))
        self.box_count += 1

    def build(self) -> None:
        # Five parallel tracks, with four usable platform faces: two outer side
        # platforms and two islands. This is a game layout, not an engineering plan.
        track_z = (-8.4, -4.2, 0.0, 4.2, 8.4)
        for track_index, z in enumerate(track_z):
            self.box("gravel", (0, -0.32, z), (42, 0.24, 3.0))
            for sleeper_x in range(-20, 21, 2):
                self.box("sleeper", (sleeper_x, -0.16, z), (0.28, 0.16, 2.55))
            for rail_z in (z - 0.72, z + 0.72):
                self.box("rail", (0, 0.04, rail_z), (42, 0.16, 0.12))

        platforms = [
            ("side", -10.65, 5.2),
            ("island", -6.3, 7.2),
            ("island", 2.1, 7.2),
            ("side", 10.65, 5.2),
        ]
        platform_edges = [(-8.9, -4.0), (-0.1, 4.1), (8.9,)]
        for platform_index, (kind, z, width) in enumerate(platforms):
            self.box("concrete", (0, 0.43, z), (42, 0.66, width))
            edge_offsets = {
                0: (z + width / 2 - 0.34,),
                1: (z - width / 2 + 0.32, z + width / 2 - 0.32),
                2: (z - width / 2 + 0.32, z + width / 2 - 0.32),
                3: (z - width / 2 + 0.34,),
            }[platform_index]
            for edge_z in edge_offsets:
                self.box("tactile", (0, 0.78, edge_z), (41.4, 0.06, 0.34))
            # Canopy, supports, benches and platform signs make the four faces
            # visibly distinct instead of reading as a single slab.
            self.box("roof", (0, 5.15, z), (34, 0.30, width + 0.7))
            for column_x in (-15, -8, 0, 8, 15):
                for column_z in (z - width * 0.40, z + width * 0.40):
                    self.box("canopy", (column_x, 2.85, column_z), (0.28, 4.5, 0.28))
            for bench_x in (-11, 11):
                self.box("building", (bench_x, 1.12, z), (2.3, 0.16, 0.65))
            self.box("sign", (0, 2.35, z), (1.8, 0.85, 0.12))

            # 2026-11-07 quality additions, mirroring the other station
            # archetypes. Platform top is y=0.76 (concrete centre 0.43 +
            # 0.66/2), tactile top is 0.81, canopy roof centre is y=5.15.
            # White safety lines 0.55 m inward from each tactile edge.
            for edge_z in edge_offsets:
                inward = 1.0 if z >= edge_z else -1.0
                self.box("white", (0, 0.775, edge_z + inward * 0.55), (41.4, 0.03, 0.12))
            # Hanging sign boards under the canopy roof with white band
            # and two hanger rods (roof underside is y=5.0).
            for sign_x in (-6, 6):
                self.box("sign", (sign_x, 3.9, z), (2.2, 0.6, 0.08))
                self.box("white", (sign_x, 3.9, z), (2.2, 0.2, 0.1))
                for hanger_x in (sign_x - 0.8, sign_x + 0.8):
                    self.box("canopy", (hanger_x, 4.6, z), (0.05, 0.8, 0.05))
            # Elongated light fixtures under the roof.
            for fixture_x in (-10, -5, 0, 5, 10):
                self.box("white", (fixture_x, 4.92, z), (1.6, 0.12, 0.24))
            # Vending machine and trash bin on each platform.
            self.box("vending", (17.5, 0.76 + 0.95, z + 1.0), (1.0, 1.9, 0.7))
            self.box("vendinglass", (17.5, 0.76 + 1.13, z + 1.0 - 0.34), (0.8, 1.1, 0.04))
            self.box("bin", (-17.5, 0.76 + 0.3, z + 0.6), (0.45, 0.6, 0.45))

        # Compact concourse, station hall, overhead footbridge and stair flights.
        self.box("building", (-2.0, 2.15, 15.2), (15, 4.2, 6.0))
        self.box("roof", (-2.0, 4.38, 15.2), (15.8, 0.32, 6.7))
        for window_x in (-7.0, -3.5, 0.0, 3.5):
            self.box("glass", (window_x, 2.4, 12.12), (1.8, 1.7, 0.08))
        self.box("concrete", (0, 7.15, 0), (5.0, 0.38, 29.0))
        self.box("roof", (0, 8.45, 0), (4.2, 0.24, 27.0))
        for z in (-12, -6, 0, 6, 12):
            self.box("canopy", (0, 7.8, z), (0.24, 1.4, 0.24))
        for sign in (-1, 1):
            for step in range(7):
                self.box("concrete", (-10 + step * 0.42, 0.62 + step * 0.25, sign * 13.5), (0.65, 0.14, 2.4))
        # Buffer-free through tracks, turnout indication and switch cabinets.
        for cabinet_z in (-13.8, 13.8):
            self.box("building", (16.0, 0.7, cabinet_z), (1.2, 1.4, 0.9))
            self.box("sign", (18.2, 2.2, cabinet_z), (0.18, 3.2, 0.18))
            self.box("white", (18.2, 3.45, cabinet_z), (0.62, 0.42, 0.2))


def make_glb(mesh: StationMesh) -> bytes:
    binary = bytearray()
    buffer_views = []
    accessors = []
    primitives = []
    materials = []

    def append_bytes(data: bytes, target: int | None = None) -> int:
        while len(binary) % 4:
            binary.append(0)
        offset = len(binary)
        binary.extend(data)
        view = {"buffer": 0, "byteOffset": offset, "byteLength": len(data)}
        if target is not None:
            view["target"] = target
        buffer_views.append(view)
        return len(buffer_views) - 1

    for material_index, (name, group) in enumerate(sorted(mesh.groups.items())):
        positions = group["positions"]
        normals = group["normals"]
        indices = group["indices"]
        if not positions or not indices:
            continue
        p_bytes = b"".join(struct.pack("<3f", *v) for v in positions)
        n_bytes = b"".join(struct.pack("<3f", *v) for v in normals)
        color = COLORS[name]
        c_bytes = b"".join(struct.pack("<4f", *color) for _ in positions)
        index_type = 5123 if len(positions) < 65_535 else 5125
        i_bytes = b"".join(struct.pack("<H" if index_type == 5123 else "<I", i) for i in indices)
        p_view = append_bytes(p_bytes, 34962)
        n_view = append_bytes(n_bytes, 34962)
        c_view = append_bytes(c_bytes, 34962)
        i_view = append_bytes(i_bytes, 34963)
        positions_by_axis = list(zip(*positions))
        p_accessor = len(accessors)
        accessors.append({"bufferView": p_view, "componentType": 5126, "count": len(positions), "type": "VEC3",
                          "min": [min(a) for a in positions_by_axis], "max": [max(a) for a in positions_by_axis]})
        n_accessor = len(accessors)
        accessors.append({"bufferView": n_view, "componentType": 5126, "count": len(normals), "type": "VEC3"})
        c_accessor = len(accessors)
        accessors.append({"bufferView": c_view, "componentType": 5126, "count": len(positions), "type": "VEC4"})
        i_accessor = len(accessors)
        accessors.append({"bufferView": i_view, "componentType": index_type, "count": len(indices), "type": "SCALAR",
                          "min": [min(indices)], "max": [max(indices)]})
        base_color = list(color)
        materials.append({"name": f"fictional_{name}", "pbrMetallicRoughness": {
            "baseColorFactor": base_color, "metallicFactor": 0.0, "roughnessFactor": 0.78
        }})
        primitives.append({"attributes": {"POSITION": p_accessor, "NORMAL": n_accessor, "COLOR_0": c_accessor},
                           "indices": i_accessor, "material": material_index, "mode": 4})

    document = {
        "asset": {"version": "2.0", "generator": "Railway Master original procedural station generator"},
        "scene": 0,
        "scenes": [{"name": "fictional_five_track_four_platform_station", "nodes": [0]}],
        "nodes": [{"name": "station_5track_4platform", "mesh": 0}],
        "meshes": [{"name": "station_5track_4platform", "primitives": primitives}],
        "materials": materials,
        "buffers": [{"byteLength": len(binary)}],
        "bufferViews": buffer_views,
        "accessors": accessors,
        "extras": {"status": "SYNTHETIC_PROCEDURAL_PLACEHOLDER", "units": "metres",
                   "coordinateSystem": "Y-up; longitudinal axis +X", "thirdPartyAssets": False,
                   "platformFaces": 4, "trackCount": 5}
    }
    json_chunk = json.dumps(document, separators=(",", ":"), ensure_ascii=False).encode("utf-8")
    json_chunk += b" " * ((-len(json_chunk)) % 4)
    binary_chunk = bytes(binary) + b"\x00" * ((-len(binary)) % 4)
    chunks = struct.pack("<I4s", len(json_chunk), b"JSON") + json_chunk
    chunks += struct.pack("<I4s", len(binary_chunk), b"BIN\x00") + binary_chunk
    total_length = 12 + len(chunks)
    return struct.pack("<4sII", b"glTF", 2, total_length) + chunks


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", type=Path, default=DEFAULT_OUT)
    args = parser.parse_args()
    mesh = StationMesh()
    mesh.build()
    data = make_glb(mesh)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_bytes(data)
    print(f"wrote {args.output} ({len(data)} bytes, {mesh.box_count} original box modules, {len(mesh.groups)} material batches)")

if __name__ == "__main__":
    main()
