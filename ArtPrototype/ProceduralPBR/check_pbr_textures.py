#!/usr/bin/env python3
"""Check expected map files, dimensions, channels, alpha, and wrap seams."""
from __future__ import annotations

import argparse
from pathlib import Path

import numpy as np
from PIL import Image

SIZE = 512
MATERIALS = (
    "pearl_painted_metal", "teal_painted_band", "dark_steel", "smoked_glass",
)
MAPS = {"albedo": "RGB", "roughness": "L", "normal": "RGB"}


def seam_report(array: np.ndarray) -> tuple[float, float, float, float]:
    """Return seam/interior mean and 99th-percentile absolute pixel deltas."""
    data = array.astype(np.int16)
    wrap_x = np.abs(data[:, 0, ...] - data[:, -1, ...]).astype(np.float32).ravel()
    wrap_y = np.abs(data[0, :, ...] - data[-1, :, ...]).astype(np.float32).ravel()
    inner_x = np.abs(data[:, 1:, ...] - data[:, :-1, ...]).astype(np.float32).ravel()
    inner_y = np.abs(data[1:, :, ...] - data[:-1, :, ...]).astype(np.float32).ravel()
    seam = np.concatenate((wrap_x, wrap_y))
    interior = np.concatenate((inner_x, inner_y))
    return (float(seam.mean()), float(np.percentile(seam, 99)),
            float(interior.mean()), float(np.percentile(interior, 99)))


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input", type=Path, default=Path(__file__).resolve().parent,
                        help="directory containing the generated maps")
    args = parser.parse_args()
    errors = []
    count = 0
    for material in MATERIALS:
        for map_name, expected_mode in MAPS.items():
            path = args.input / f"{material}_{map_name}.png"
            if not path.is_file():
                errors.append(f"MISSING {path.name}")
                continue
            try:
                with Image.open(path) as image:
                    image.load()
                    if image.size != (SIZE, SIZE):
                        errors.append(f"SIZE {path.name}: {image.size}, expected {(SIZE, SIZE)}")
                    if image.mode != expected_mode:
                        errors.append(f"MODE {path.name}: {image.mode}, expected {expected_mode}")
                    if "A" in image.getbands() or "transparency" in image.info:
                        errors.append(f"ALPHA {path.name}: unexpected transparency/alpha")
                    if image.size == (SIZE, SIZE) and image.mode == expected_mode:
                        values = np.asarray(image)
                        seam_mean, seam_p99, inside_mean, inside_p99 = seam_report(values)
                        # Seam steps should be comparable to ordinary adjacent-pixel
                        # steps. Limits allow quantization while catching hard borders.
                        if seam_mean > inside_mean * 1.8 + 1.5 or seam_p99 > inside_p99 * 2.0 + 3.0:
                            errors.append(
                                f"SEAM {path.name}: mean {seam_mean:.2f}/{inside_mean:.2f}, "
                                f"p99 {seam_p99:.2f}/{inside_p99:.2f} (wrap/interior)"
                            )
                        count += 1
            except Exception as exc:
                errors.append(f"READ {path.name}: {exc}")
    if errors:
        print("FAIL")
        for error in errors:
            print(f"- {error}")
        return 1
    print(f"PASS: {count} PNG maps; {SIZE}x{SIZE}; RGB/L/RGB; opaque; wrap seam deltas within limits.")
    print("Seam criterion: compare opposite-edge pixel deltas with ordinary neighboring-pixel deltas;")
    print("mean <= 1.8x interior mean + 1.5 and p99 <= 2.0x interior p99 + 3 (8-bit levels).")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
