#!/usr/bin/env python3
"""Verify ZIP CRC, exact member paths, sizes, and SHA-256 against this project tree."""
from __future__ import annotations

import argparse
import hashlib
import sys
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
EXCLUDED_DIRS = {".git", ".build", "DerivedData", "__pycache__", "xcuserdata"}
EXCLUDED_NAMES = {".DS_Store"}
ARCHIVE_ROOT = ROOT.name


def project_files() -> dict[str, Path]:
    result: dict[str, Path] = {}
    for path in ROOT.rglob("*"):
        if not path.is_file():
            continue
        relative = path.relative_to(ROOT)
        if any(part in EXCLUDED_DIRS for part in relative.parts):
            continue
        if path.name in EXCLUDED_NAMES or path.suffix == ".zip":
            continue
        result[relative.as_posix()] = path
    return result


def digest(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("zip_path", type=Path, help="archive to verify")
    args = parser.parse_args()
    archive = args.zip_path.expanduser().resolve()
    if not archive.is_file():
        print(f"FAIL: ZIP not found: {archive}", file=sys.stderr)
        return 1

    expected = project_files()
    expected_members = {f"{ARCHIVE_ROOT}/{relative}" for relative in expected}
    try:
        with zipfile.ZipFile(archive) as zipped:
            infos = [info for info in zipped.infolist() if not info.is_dir()]
            names = [info.filename for info in infos]
            if len(names) != len(set(names)):
                print("FAIL: ZIP contains duplicate member paths", file=sys.stderr)
                return 1
            actual_members = set(names)
            missing = sorted(expected_members - actual_members)
            extra = sorted(actual_members - expected_members)
            if missing or extra:
                if missing:
                    print("Missing ZIP members:", *missing, sep="\n  ", file=sys.stderr)
                if extra:
                    print("Unexpected ZIP members:", *extra, sep="\n  ", file=sys.stderr)
                return 1
            corrupt = zipped.testzip()
            if corrupt is not None:
                print(f"FAIL: ZIP CRC failed for {corrupt}", file=sys.stderr)
                return 1
            for info in infos:
                relative = info.filename[len(ARCHIVE_ROOT) + 1:]
                source = expected[relative]
                data = zipped.read(info)
                if len(data) != source.stat().st_size:
                    print(f"FAIL: size mismatch for {relative}", file=sys.stderr)
                    return 1
                if digest(data) != digest(source.read_bytes()):
                    print(f"FAIL: SHA-256 mismatch for {relative}", file=sys.stderr)
                    return 1
    except (OSError, zipfile.BadZipFile, KeyError) as exc:
        print(f"FAIL: cannot verify ZIP: {exc}", file=sys.stderr)
        return 1

    print(f"PASS: {archive.name}: {len(expected_members)} exact members; CRC, sizes, and SHA-256 match the project tree")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
