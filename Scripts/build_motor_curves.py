#!/usr/bin/env python3
"""Build motor_curves.json from the BVE Workshop MotorNoise volume tables.

Offline step for the sampled traction sound (audio2 / quality6). Parses the
Bvets MotorNoise *volume* tables of the three downloaded sets and samples
them into per-family curves: for every 2 km/h step, the active samples and
their volumes under column-wise linear interpolation (the BVE rule).
Frequency tables are not used in v1; the samples play at their recorded
pitch and the crossfades carry the character.

Inputs (outside the repo, in the audio workspace):
  toq5000_motor_140401/motornoise/{powervol,brakevol}.csv  -> family "vvvf"
  tokyu8500h_motor_190602/Vol.csv (power+brake)            -> family "chopper"
  meitetsu5300_motor/Vol.csv (power+brake)                 -> family "resistance"

Output: RailwayMasterPhase1/Resources/motor_curves.json with entries
  { "family": {"power": [[speedKmh, [[sampleName, volume], ...]], ...],
               "brake": [...] } }
Only samples whose WAV exists in the app Resources (motor_<family>_<nn>
or the family's Run0) are emitted; volumes below 0.04 are dropped and at
most three samples are kept per step.
"""
from __future__ import annotations

import csv
import io
import json
import sys
from pathlib import Path

AUDIO_ROOT = Path.home() / "workspace" / "audio" / "bvews"
ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / "RailwayMasterPhase1" / "Resources" / "motor_curves.json"
RESOURCE_NAMES = {
    path.stem for path in (ROOT / "RailwayMasterPhase1" / "Resources").glob("motor_*.wav")
}

FAMILIES = {
    "vvvf": {
        "power": AUDIO_ROOT / "toq5000_motor_140401" / "motornoise" / "powervol.csv",
        "brake": AUDIO_ROOT / "toq5000_motor_140401" / "motornoise" / "brakevol.csv",
        "prefix": "motor_vvvf_",
        "run_name": None,  # Run0 column maps to run_ballast for this family
    },
    "chopper": {
        "power": AUDIO_ROOT / "tokyu8500h_motor_190602" / "Vol.csv",
        "brake": AUDIO_ROOT / "tokyu8500h_motor_190602" / "Vol.csv",
        "prefix": "motor_chopper_",
        "run_name": None,
    },
    "resistance": {
        "power": AUDIO_ROOT / "meitetsu5300_motor" / "Vol.csv",
        "brake": AUDIO_ROOT / "meitetsu5300_motor" / "Vol.csv",
        "prefix": "motor_res_",
        "run_name": None,
    },
}

MAX_SPEED = 120.0
STEP = 2.0


def parse_volume_table(path: Path) -> dict[str, list[tuple[float, float]]]:
    """Return {column label: [(speed, value), ...]} from a Bvets table."""
    text = path.read_text(encoding="utf-8", errors="replace")
    rows = list(csv.reader(io.StringIO(text)))
    header_index = None
    for i, row in enumerate(rows):
        if row and row[0].strip() == "#" and len(row) > 2 and row[1].strip() in ("0", ""):
            # The label row is the one whose second cell is the first index.
            if any(cell.strip().isdigit() for cell in row[1:]):
                header_index = i
                break
    if header_index is None:
        raise ValueError(f"no label row in {path}")
    labels = [cell.strip() for cell in rows[header_index][1:]]
    columns: dict[str, list[tuple[float, float]]] = {label: [] for label in labels if label}
    for row in rows[header_index + 1:]:
        if not row:
            continue
        try:
            speed = float(row[0])
        except (ValueError, TypeError):
            continue  # reference-pitch rows and comment rows start with '#'
        for label, cell in zip(labels, row[1:]):
            if not label:
                continue
            cell = cell.strip()
            if cell in ("", "*"):
                continue
            try:
                value = float(cell)
            except ValueError:
                continue
            columns[label].append((speed, value))
    for points in columns.values():
        points.sort()
    return columns


def interpolate(points: list[tuple[float, float]], speed: float) -> float:
    if not points:
        return 0.0
    if speed <= points[0][0]:
        return points[0][1] if points[0][0] <= 0.01 else 0.0
    if speed >= points[-1][0]:
        return points[-1][1]
    for (s0, v0), (s1, v1) in zip(points, points[1:]):
        if s0 <= speed <= s1:
            if s1 == s0:
                return v1
            return v0 + (v1 - v0) * (speed - s0) / (s1 - s0)
    return 0.0


def sample_name(family: dict, label: str) -> str | None:
    if label == "Run":
        return family["run_name"]
    if not label.isdigit():
        return None
    name = f"{family['prefix']}{int(label):02d}"
    return name if name in RESOURCE_NAMES else None


def build_curve(family: dict, table_path: Path) -> list:
    columns = parse_volume_table(table_path)
    named = {}
    for label, points in columns.items():
        name = sample_name(family, label)
        if name:
            named[name] = points
    curve = []
    speed = 0.0
    while speed <= MAX_SPEED + 0.01:
        active = []
        for name, points in named.items():
            volume = interpolate(points, speed)
            if volume >= 0.04:
                active.append([name, round(volume, 3)])
        active.sort(key=lambda item: -item[1])
        curve.append([speed, active[:3]])
        speed += STEP
    return curve


def main() -> None:
    result = {}
    for family_name, family in FAMILIES.items():
        result[family_name] = {
            "power": build_curve(family, family["power"]),
            "brake": build_curve(family, family["brake"]),
        }
        counts = {key: sum(1 for _s, a in result[family_name][key] if a) for key in ("power", "brake")}
        print(f"{family_name}: active steps power={counts['power']} brake={counts['brake']}")
    OUTPUT.write_text(json.dumps(result, separators=(",", ":")), encoding="utf-8")
    print(f"wrote {OUTPUT} ({OUTPUT.stat().st_size} bytes)")


if __name__ == "__main__":
    main()
