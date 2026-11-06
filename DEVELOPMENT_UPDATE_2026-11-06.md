# Railway Master — route and 3D asset update

Date: 2026-11-06

This note reflects the current working tree. Earlier drafts that said GLBs were not wired into the renderer or station layouts were not active have been superseded.

## Current implementation

`RegionalRouteFactory.swift` generates a seeded, non-periodic alignment for the 60 km mainline, 8 km branch and 2 km depot spur. The app’s fixed default seed is reproducible; callers may supply another seed. Mainline curves use radii 900–1,850 m, 55–105 mm cant and 300–500 m entry/exit transitions. Branch curves use 450–900 m radius, 45–90 mm cant and 130–260 m transitions. Depot curves use 450–650 m radius, 35–70 mm cant and 90–150 m transitions. All are fictional game placeholders, not survey or engineering data.

The 32 station records (28 mainline, 4 branch) each specify track/platform topology and a model archetype. Layouts cover side and island platforms, passing/major stations, terminal layouts and a five-track/four-platform hub. These are shared topology-specific models, not 32 unique station-building facades.

The live RealityKit scene has a native GLB resource catalog/loader. It places vehicle/cab, track, equipment, station and corridor assets; it selects the nearby station model from the active route. The detailed add-on car and cab are preferred in the high-fidelity lead vehicle, with procedural/generic fallbacks. The selected add-on assets use Z-up coordinates and per-primitive uniform `COLOR_0`; the scene applies an explicit coordinate transform.

The package contains 13 unique embedded GLB 2.0 files, 935 colored triangle primitives and zero external resource URIs. From the supplied add-on pack (27 GLBs and 21 PNGs), only two detailed models were copied. The remaining 15 distinct detailed GLBs, 10 duplicate base GLBs and all PNGs were omitted. The supplied README says 14 detailed models, while its folder contains 17. The owner described the models as ChatGPT-generated; this is not independent proof of authorship, commercial terms or exclusivity.

## Current static verification

- `Scripts/validate_project.py`: PASS — 203 Swift files grammar-parsed, 218 Xcode project object IDs, 45 app sources linked, 20 app and 13 test package products, 26 JSON files, 48 route combinations and 42 app-host XCTest methods counted.
- `Scripts/validate_generated_3d_assets.py`: PASS — GLB structure/colors, no external URIs, 32 station layouts and five-track/four-platform hub.
- `Packages/RailwaySceneFidelity/Scripts/validate_scene_fidelity.py`: PASS — 15 Swift source/test files and static integration rules.
- `PACKAGE_INVENTORY.md --check`: PASS — 356 manifested files match sizes and SHA-256 values.

These are source/static checks only. The 42 app-host XCTest methods, iOS type-check/build, Simulator/device rendering, performance and visual scale have not been run in this environment because Swift/Xcode is unavailable. See `UPDATE_LEDGER.md`, `ACCEPTANCE_CHECKLIST.md` and `TEST_CHECKLIST.md` for the detailed handoff.
