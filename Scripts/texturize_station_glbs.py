#!/usr/bin/env python3
"""Add box-projected TEXCOORD_0 UVs to the six station GLBs (quality5).

The bundled station GLBs ship POSITION + uniform COLOR_0 only. The runtime
loader (GeneratedRailwayAssetLoader) maps station surfaces to the package's
photo textures by mesh/material name, but it can only do so when the
primitive carries UVs. This script generates them offline:

- per-vertex normals are accumulated from face normals (the same scheme
  the runtime loader uses for shading),
- each vertex is projected along its dominant normal axis, and the two
  remaining position coordinates become UVs, divided by a per-role tile
  size in meters so the photo textures repeat at a physical scale.

Geometry, colors, indices, materials and node structure are preserved;
only attributes gain TEXCOORD_0 and the binary buffer grows by the UV
data. Idempotent: primitives that already have TEXCOORD_0 are skipped.

Role/tile table (mirrors the loader's texture-name table in
GeneratedRailwayAssetLoader.swift — keep the two in sync):
  sleeper 2.0 m, trackbed 4.0 m, platform 4.0 m, canopy 3.0 m,
  footbridge 3.0 m, bench seat/back 1.0 m, building 6.0 m, rail 2.0 m,
  hub materials: concrete 4.0, gravel 4.0, sleeper 2.0, building 6.0,
  canopy/roof/rail 3.0/3.0/2.0. Default 4.0 m.
"""
from __future__ import annotations

import json
import math
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
    "station_5track_4platform.glb",
]


def tile_for(mesh_name: str, material_name: str | None) -> float:
    if material_name:
        table = {
            "fictional_concrete": 4.0,
            "fictional_gravel": 4.0,
            "fictional_sleeper": 2.0,
            "fictional_building": 6.0,
            "fictional_canopy": 3.0,
            "fictional_roof": 3.0,
            "fictional_rail": 2.0,
        }
        return table.get(material_name, 4.0)
    name = mesh_name
    if name.startswith("sleeper"):
        return 2.0
    if name.startswith("trackbed"):
        return 4.0
    if name.startswith("platform"):
        return 4.0
    if name.startswith("canopy_"):
        return 3.0
    if name.startswith("footbridge_"):
        return 3.0
    if name.startswith("bench_"):
        return 1.0
    if name.startswith("station_main_building"):
        return 6.0
    if name.startswith("rail_"):
        return 2.0
    return 4.0


def parse_glb(data: bytes) -> tuple[dict, bytes]:
    magic, version, _length = struct.unpack("<4sII", data[:12])
    if magic != b"glTF" or version != 2:
        raise ValueError("not a GLB 2.0 file")
    json_length = struct.unpack("<I", data[12:16])[0]
    document = json.loads(data[20:20 + json_length])
    offset = 20 + json_length
    binary = b""
    if offset < len(data):
        bin_length = struct.unpack("<I", data[offset:offset + 4])[0]
        binary = data[offset + 8:offset + 8 + bin_length]
    return document, binary


def build_glb(document: dict, binary: bytes) -> bytes:
    json_bytes = json.dumps(document, separators=(",", ":"), ensure_ascii=False).encode("utf-8")
    json_bytes += b" " * ((4 - len(json_bytes) % 4) % 4)
    total = 12 + 8 + len(json_bytes) + 8 + len(binary)
    out = bytearray()
    out += struct.pack("<4sII", b"glTF", 2, total)
    out += struct.pack("<II", len(json_bytes), 0x4E4F534A)
    out += json_bytes
    out += struct.pack("<II", len(binary), 0x004E4942)
    out += binary
    return bytes(out)


def accessor_bytes(document: dict, binary: bytes, accessor_index: int) -> bytes:
    accessor = document["accessors"][accessor_index]
    view = document["bufferViews"][accessor["bufferView"]]
    start = view.get("byteOffset", 0) + accessor.get("byteOffset", 0)
    component_sizes = {5120: 1, 5121: 1, 5122: 2, 5123: 2, 5125: 4, 5126: 4}
    components = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4}[accessor["type"]]
    size = component_sizes[accessor["componentType"]] * components
    stride = view.get("byteStride", size)
    count = accessor["count"]
    if stride == size:
        return binary[start:start + size * count]
    out = bytearray()
    for i in range(count):
        out += binary[start + i * stride:start + i * stride + size]
    return bytes(out)


def read_positions(document: dict, binary: bytes, accessor_index: int) -> list[tuple[float, float, float]]:
    raw = accessor_bytes(document, binary, accessor_index)
    count = len(raw) // 12
    return [struct.unpack_from("<3f", raw, i * 12) for i in range(count)]


def read_indices(document: dict, binary: bytes, primitive: dict, vertex_count: int) -> list[int]:
    if "indices" not in primitive:
        return list(range(vertex_count))
    accessor = document["accessors"][primitive["indices"]]
    raw = accessor_bytes(document, binary, primitive["indices"])
    component = accessor["componentType"]
    if component == 5121:
        return list(raw[:accessor["count"]])
    if component == 5123:
        return list(struct.unpack(f"<{accessor['count']}H", raw))
    return list(struct.unpack(f"<{accessor['count']}I", raw))


def compute_uvs(positions: list[tuple[float, float, float]], indices: list[int], tile: float) -> list[tuple[float, float]]:
    normals = [[0.0, 0.0, 0.0] for _ in positions]
    for start in range(0, len(indices) - 2, 3):
        a, b, c = indices[start], indices[start + 1], indices[start + 2]
        pa, pb, pc = positions[a], positions[b], positions[c]
        ux, uy, uz = pb[0] - pa[0], pb[1] - pa[1], pb[2] - pa[2]
        vx, vy, vz = pc[0] - pa[0], pc[1] - pa[1], pc[2] - pa[2]
        fx, fy, fz = uy * vz - uz * vy, uz * vx - ux * vz, ux * vy - uy * vx
        for index in (a, b, c):
            normals[index][0] += fx
            normals[index][1] += fy
            normals[index][2] += fz
    uvs = []
    for (x, y, z), (nx, ny, nz) in zip(positions, normals):
        ax, ay, az = abs(nx), abs(ny), abs(nz)
        if ay >= ax and ay >= az:
            u, v = x, z          # ground / horizontal faces
        elif ax >= ay and ax >= az:
            u, v = z, y          # side faces (normal along X)
        else:
            u, v = x, y          # front / back faces (normal along Z)
        uvs.append((u / tile, v / tile))
    return uvs


def texturize(path: Path) -> int:
    document, binary = parse_glb(path.read_bytes())
    materials = document.get("materials", [])
    additions = bytearray()
    added = 0

    def append_uv_buffer(uvs: list[tuple[float, float]]) -> int:
        nonlocal additions
        while (len(binary) + len(additions)) % 4:
            additions += b"\x00"
        offset = len(binary) + len(additions)
        raw = b"".join(struct.pack("<2f", u, v) for u, v in uvs)
        document["bufferViews"].append({"buffer": 0, "byteOffset": offset, "byteLength": len(raw)})
        view_index = len(document["bufferViews"]) - 1
        us = [uv[0] for uv in uvs]
        vs = [uv[1] for uv in uvs]
        document["accessors"].append({
            "bufferView": view_index,
            "componentType": 5126,
            "count": len(uvs),
            "type": "VEC2",
            "min": [min(us), min(vs)],
            "max": [max(us), max(vs)],
        })
        additions += raw
        return len(document["accessors"]) - 1

    for mesh in document.get("meshes", []):
        mesh_name = mesh.get("name", "")
        for primitive in mesh.get("primitives", []):
            attributes = primitive.get("attributes", {})
            if "TEXCOORD_0" in attributes or "POSITION" not in attributes:
                continue
            material_name = None
            if "material" in primitive and materials:
                material_name = materials[primitive["material"]].get("name")
            positions = read_positions(document, binary, attributes["POSITION"])
            indices = read_indices(document, binary, primitive, len(positions))
            uvs = compute_uvs(positions, indices, tile_for(mesh_name, material_name))
            attributes["TEXCOORD_0"] = append_uv_buffer(uvs)
            added += 1
    if added:
        new_binary = binary + bytes(additions)
        document["buffers"][0]["byteLength"] = len(new_binary)
        path.write_bytes(build_glb(document, new_binary))
    return added


def main() -> None:
    total = 0
    for filename in STATION_FILES:
        count = texturize(ASSET_ROOT / filename)
        print(f"{filename}: {count} primitives gained TEXCOORD_0")
        total += count
    print(f"total: {total}")


if __name__ == "__main__":
    main()
