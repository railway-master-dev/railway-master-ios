#!/usr/bin/env python3
"""Build the final BVE metadata inventory and count summary from reviewed CSV only."""
from __future__ import annotations

import csv
import json
from collections import Counter, defaultdict
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[3]
BVE = ROOT / "Research" / "BVE"
ADDITIONAL = BVE / "additional"
SOURCE_CSV = ADDITIONAL / "inventory_updated.csv"
FINAL_CSV = BVE / "inventory_final.csv"
FINAL_JSON = BVE / "inventory_final.json"
SUMMARY_JSON = BVE / "summary_final.json"

JSON_FIELDS = {
    "license_or_reuse_terms",
    "route_definition_files",
    "helper_table_files",
    "inspected_files",
    "features",
}
INT_FIELDS = {"archive_bytes", "file_count", "uncompressed_bytes"}


def parse_cell(key: str, raw: str) -> Any:
    if key in INT_FIELDS:
        return int(raw) if raw else 0
    if key in JSON_FIELDS:
        return json.loads(raw) if raw else ([] if key.endswith("_files") else {})
    return raw


def summarize_category(category: str, records: list[dict[str, Any]]) -> dict[str, Any]:
    result: dict[str, Any] = {
        "package_count": len(records),
        "unique_archive_sha256_count": len({r["sha256"].strip().lower() for r in records}),
        "file_count_total": sum(int(r.get("file_count", 0)) for r in records),
        "uncompressed_bytes_total": sum(int(r.get("uncompressed_bytes", 0)) for r in records),
        "archive_formats": dict(sorted(Counter(r["archive_format"] for r in records).items())),
        "records_with_rights_scope_notes": sum(
            bool(r.get("license_or_reuse_terms") or r.get("commercial_app_suitability") or
                 r.get("commercial_app_rights_note") or r.get("third_party_rights_note"))
            for r in records
        ),
    }
    if category == "route":
        result["route_definition_file_paths_recorded"] = sum(
            len(r.get("route_definition_files", [])) for r in records
        )
        command_totals: Counter[str] = Counter()
        packages_with_command: Counter[str] = Counter()
        for record in records:
            counts = (record.get("features") or {}).get("feature_command_counts", {})
            for name, value in counts.items():
                count = int(value or 0)
                command_totals[name] += count
                if count > 0:
                    packages_with_command[name] += 1
        result["feature_command_occurrence_totals_not_normalized"] = dict(sorted(command_totals.items()))
        result["packages_with_text_command_hits"] = dict(sorted(packages_with_command.items()))
        result["packages_with_station_related_files"] = sum(
            int((r.get("features") or {}).get("station_related_file_count", 0) or 0) > 0
            for r in records
        )
    else:
        result["packages_with_sound_config"] = sum(
            int((r.get("features") or {}).get("sound_config_count", 0) or 0) > 0
            for r in records
        )
        sections: set[str] = set()
        for record in records:
            sections.update((record.get("features") or {}).get("sound_sections", {}).keys())
        result["sound_event_sections_present"] = sorted(sections)
    return result


def main() -> None:
    with SOURCE_CSV.open("r", encoding="utf-8-sig", newline="") as stream:
        reader = csv.DictReader(stream)
        rows = [{key: parse_cell(key, value or "") for key, value in row.items()} for row in reader]
    if not rows:
        raise SystemExit("FAIL: inventory CSV is empty")
    FINAL_CSV.write_bytes(SOURCE_CSV.read_bytes())

    categories = {name: [r for r in rows if r.get("category") == name] for name in ("route", "vehicle")}
    expected_counts = {"route": 69, "vehicle": 68}
    for name, expected in expected_counts.items():
        if len(categories[name]) != expected:
            raise SystemExit(f"FAIL: expected {expected} {name} records, found {len(categories[name])}")
        hashes = [r["sha256"].strip().lower() for r in categories[name]]
        if len(hashes) != len(set(hashes)):
            raise SystemExit(f"FAIL: duplicate archive SHA-256 within {name} category")

    by_hash: dict[str, list[dict[str, Any]]] = defaultdict(list)
    for row in rows:
        by_hash[row["sha256"].strip().lower()].append(row)
    shared_pairs = []
    for archive_hash, grouped in sorted(by_hash.items()):
        route_records = [r for r in grouped if r["category"] == "route"]
        vehicle_records = [r for r in grouped if r["category"] == "vehicle"]
        if len(route_records) > 1 or len(vehicle_records) > 1:
            raise SystemExit("FAIL: category-internal archive SHA-256 duplicate")
        if route_records and vehicle_records:
            shared_pairs.append({
                "sha256": archive_hash,
                "route_package": route_records[0]["package"],
                "vehicle_package": vehicle_records[0]["package"],
            })

    FINAL_JSON.write_text(json.dumps(rows, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    summary = {
        "summary": {name: summarize_category(name, records) for name, records in categories.items()},
        "no_network_access": False,
        "inventory_state": "FINAL_FORMAL_METADATA_SNAPSHOT_2026-11-06",
        "category_internal_sha256_deduplication": "No duplicate archive SHA-256 values within either category.",
        "unique_archive_counts_across_categories": {
            "route": len(categories["route"]),
            "vehicle": len(categories["vehicle"]),
            "shared_hashes_across_categories": len(shared_pairs),
            "global_unique_archive_sha256_count": len(by_hash),
            "shared_pairs": shared_pairs,
        },
        "requested_target": {"route": 100, "vehicle": 100, "route_shortfall": 31, "vehicle_shortfall": 32},
        "final_counts_are_archive_sha256_deduplicated": True,
        "rights_summary_note": "Rights are retained per inventory record; permission scope may cover only specific text/config components, while third-party assets may have separate terms. Do not infer app inclusion permission from a license label.",
        "baseline_excluded_after_offline_review": 12,
        "historical_recovered_from_old_false_ai_filter": 10,
        "additional_research": {
            "baseline_counts_before_latest_round": {"route": 63, "vehicle": 58},
            "latest_additions": {"route": 6, "vehicle": 10, "category_records": 16, "unique_archives": 13},
            "final_counts": {"route": 69, "vehicle": 68},
            "new_static_text_configuration_files_inspected": 541,
            "latest_addition_records_with_noncommercial_terms_or_license": 8,
            "sgtrains_candidates_excluded_http_403": 3,
            "osaka_tanimachi_excluded_bve_only_restriction": 1,
            "original_download_archives_included_in_project": False,
            "raw_config_text_saved": False,
            "audio_image_texture_model_or_executable_payloads_opened_or_copied": False,
            "application_reuse_permission_inferred": False,
            "earlier_audio_sample_review_audit_caveat": "A separate earlier audio sample review had its own procedural deviations; this metadata update does not resolve or certify that separate review. No audio was read or played in the latest static text inspection.",
        },
        "app_inclusion_status": "No BVE packages, assets, executable data, audio, images, textures, or models are included in the iOS app; bundled BVE materials are metadata and research documentation only.",
    }
    SUMMARY_JSON.write_text(json.dumps(summary, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(
        f"Wrote final BVE metadata: route={len(categories['route'])}, vehicle={len(categories['vehicle'])}, "
        f"shared hashes={len(shared_pairs)}, global unique archives={len(by_hash)}; "
        "no same-category SHA-256 duplicates"
    )


if __name__ == "__main__":
    main()
