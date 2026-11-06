#!/usr/bin/env python3
"""Build deterministic, seamless 512x512 procedural PBR material maps.

Only NumPy and Pillow are required. Every stochastic field uses a fixed,
material-specific seed and periodic (wrap-around) filtering.
"""
from __future__ import annotations

import argparse
from pathlib import Path

import numpy as np
from PIL import Image

SIZE = 512
MATERIALS = {
    "pearl_painted_metal": {
        "base": (194, 205, 210), "roughness": 84, "height": 1.6,
        "grain": 3.3, "direction": "vertical", "seed": 1101,
    },
    "teal_painted_band": {
        "base": (18, 112, 119), "roughness": 96, "height": 2.2,
        "grain": 3.0, "direction": "horizontal", "seed": 2202,
    },
    "dark_steel": {
        "base": (43, 51, 56), "roughness": 142, "height": 3.4,
        "grain": 4.2, "direction": "vertical", "seed": 3303,
    },
    "smoked_glass": {
        "base": (31, 49, 57), "roughness": 38, "height": 0.65,
        "grain": 1.6, "direction": "horizontal", "seed": 4404,
    },
}


def periodic_blur(array: np.ndarray, sigma: float, axis: int) -> np.ndarray:
    """Gaussian-like 1D blur on a periodic domain (edges wrap, never pad)."""
    if sigma <= 0:
        return array.astype(np.float32, copy=True)
    radius = max(1, int(np.ceil(3.0 * sigma)))
    offsets = np.arange(-radius, radius + 1, dtype=np.float32)
    weights = np.exp(-0.5 * (offsets / sigma) ** 2)
    weights /= weights.sum()
    result = np.zeros_like(array, dtype=np.float32)
    for offset, weight in zip(range(-radius, radius + 1), weights):
        result += np.roll(array, shift=offset, axis=axis) * weight
    return result


def periodic_noise(rng: np.random.Generator, size: int, direction: str | None = None) -> np.ndarray:
    """A multi-scale, zero-mean field on a torus; no nonperiodic borders."""
    fields = []
    for sigma in (19.0, 5.5, 1.25):
        raw = rng.standard_normal((size, size), dtype=np.float32)
        if direction == "vertical":
            # Blurring along rows preserves fine vertical streaks.
            field = periodic_blur(raw, sigma, axis=1)
            field = periodic_blur(field, sigma * 0.22, axis=0)
        elif direction == "horizontal":
            field = periodic_blur(raw, sigma, axis=0)
            field = periodic_blur(field, sigma * 0.22, axis=1)
        else:
            field = periodic_blur(periodic_blur(raw, sigma, axis=0), sigma, axis=1)
        std = float(field.std())
        fields.append(field / max(std, 1e-6))
    result = 0.52 * fields[0] + 0.31 * fields[1] + 0.17 * fields[2]
    result -= result.mean()
    result /= max(float(result.std()), 1e-6)
    return result


def periodic_pattern(size: int, rng: np.random.Generator, axis: str) -> np.ndarray:
    """Very low-contrast integer-frequency variation, exactly periodic."""
    coords = np.arange(size, dtype=np.float32) * (2.0 * np.pi / size)
    cycles = int(rng.integers(2, 6))
    phase = float(rng.uniform(0.0, 2.0 * np.pi))
    wave = np.sin(coords * cycles + phase)
    return np.broadcast_to(wave[None, :], (size, size)).copy() if axis == "vertical" else np.broadcast_to(wave[:, None], (size, size)).copy()


def save_material(name: str, spec: dict, out_dir: Path) -> None:
    rng = np.random.default_rng(spec["seed"])
    detail = periodic_noise(rng, SIZE, spec["direction"])
    broad = periodic_noise(rng, SIZE)
    micro = rng.standard_normal((SIZE, SIZE), dtype=np.float32)
    wave = periodic_pattern(SIZE, rng, spec["direction"])

    # Height is deliberately low amplitude: it represents subtle original
    # painted/metal/glass surface variation, not a measured real-world material.
    height = (0.62 * broad + 0.25 * detail + 0.09 * micro + 0.12 * wave) * spec["height"]
    height -= height.mean()
    dy = (np.roll(height, -1, axis=0) - np.roll(height, 1, axis=0)) * 0.5
    dx = (np.roll(height, -1, axis=1) - np.roll(height, 1, axis=1)) * 0.5
    nx = -dx * 95.0
    ny = -dy * 95.0
    nz = np.full_like(nx, 127.0)
    length = np.sqrt(nx * nx + ny * ny + nz * nz)
    normal = np.stack((nx / length, ny / length, nz / length), axis=-1)
    normal_rgb = np.clip(np.rint(normal * 127.5 + 127.5), 0, 255).astype(np.uint8)

    base = np.asarray(spec["base"], dtype=np.float32)
    # Tiny correlated mottling plus sparse-scale grain; RGB remains opaque.
    color_field = 2.6 * broad + spec["grain"] * detail + 0.55 * micro + 0.7 * wave
    albedo = np.clip(np.rint(base[None, None, :] + color_field[..., None]), 0, 255).astype(np.uint8)
    rough_field = periodic_noise(rng, SIZE) * (5.0 if name == "smoked_glass" else 7.0) + detail * 2.0
    roughness = np.clip(np.rint(spec["roughness"] + rough_field), 0, 255).astype(np.uint8)

    Image.fromarray(albedo, mode="RGB").save(out_dir / f"{name}_albedo.png", optimize=True)
    Image.fromarray(roughness, mode="L").save(out_dir / f"{name}_roughness.png", optimize=True)
    Image.fromarray(normal_rgb, mode="RGB").save(out_dir / f"{name}_normal.png", optimize=True)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, default=Path(__file__).resolve().parent,
                        help="directory for PNG maps (default: this script's directory)")
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    for material, spec in MATERIALS.items():
        save_material(material, spec, args.output)
    print(f"Generated {len(MATERIALS) * 3} maps ({SIZE}x{SIZE}) in {args.output}")


if __name__ == "__main__":
    main()
