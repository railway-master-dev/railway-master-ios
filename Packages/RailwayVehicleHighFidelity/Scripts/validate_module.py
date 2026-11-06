#!/usr/bin/env python3
"""Source-contract checks only; this does not parse Swift or replace Xcode build/tests."""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "Sources/RailwayVehicleHighFidelity"
EXPECTED = [
    ROOT / "Package.swift",
    SOURCE / "VehicleSpecification.swift",
    SOURCE / "VehicleGeometry.swift",
    SOURCE / "VehicleExteriorBuilder.swift",
    SOURCE / "VehicleCabBuilder.swift",
    SOURCE / "RailwayVehicleHighFidelityBuilder.swift",
    ROOT / "Tests/RailwayVehicleHighFidelityTests/VehicleHighFidelityTests.swift",
]
REQUIRED = {
    "VehicleSpecification.swift": ["VehicleDetailLevel", "HighFidelityVehiclePart", "CabControlKind", "VehicleCabIndicatorState", "validationIssues"],
    "VehicleGeometry.swift": ["PhysicallyBasedMaterial", "roughness", "metallic", "transparent(opacity", "SharedPrimitiveMeshes"],
    "VehicleExteriorBuilder.swift": ["buildBody", "buildGlazing", "buildDoors", "buildBogie", "buildUnderfloor", "buildRoof", "buildPantograph", "buildWipers"],
    "VehicleCabBuilder.swift": ["buildCab", "buildControls", "Speedometer", "BrakePipeGauge", "CabControlComponent"],
    "RailwayVehicleHighFidelityBuilder.swift": ["RailwayVehicleHighFidelityBuilder", "VehicleCabControlRig", "VehicleAnimatedParts", "setTelemetry", "setCabIndicatorState", "setDoorOpenFraction", "setWiperSweep", "setPantographExtension", "advanceWheels"],
}


def fail(message: str) -> None:
    print(f"FAIL: {message}")
    raise SystemExit(1)


def balanced_delimiters(source: str) -> bool:
    """Check braces/brackets/parens outside comments and quoted strings; not a Swift parser."""
    stack: list[str] = []
    pairs = {")": "(", "]": "[", "}": "{"}
    i = 0
    state = "code"
    block_depth = 0
    while i < len(source):
        char = source[i]
        nxt = source[i + 1] if i + 1 < len(source) else ""
        if state == "line_comment":
            if char == "\n":
                state = "code"
        elif state == "block_comment":
            if char == "/" and nxt == "*":
                block_depth += 1
                i += 1
            elif char == "*" and nxt == "/":
                block_depth -= 1
                i += 1
                if block_depth == 0:
                    state = "code"
        elif state == "string":
            if char == "\\":
                i += 1
            elif char == '"':
                state = "code"
        else:
            if char == "/" and nxt == "/":
                state = "line_comment"
                i += 1
            elif char == "/" and nxt == "*":
                state = "block_comment"
                block_depth = 1
                i += 1
            elif char == '"':
                state = "string"
            elif char in "([{":
                stack.append(char)
            elif char in ")]}":
                if not stack or stack.pop() != pairs[char]:
                    return False
        i += 1
    return not stack and state in {"code", "line_comment"}


for path in EXPECTED:
    if not path.is_file() or path.stat().st_size == 0:
        fail(f"missing/empty: {path.relative_to(ROOT)}")

for path in sorted(ROOT.rglob("*.swift")):
    text = path.read_text(encoding="utf-8")
    if not balanced_delimiters(text):
        fail(f"unbalanced delimiters (lexical check only): {path.name}")

for filename, symbols in REQUIRED.items():
    path = SOURCE / filename
    text = path.read_text(encoding="utf-8")
    for symbol in symbols:
        if symbol not in text:
            fail(f"{filename} missing contract token: {symbol}")

manifest = (ROOT / "Package.swift").read_text(encoding="utf-8")
if 'platforms: [.iOS(.v17)]' not in manifest or 'name: "RailwayVehicleHighFidelity"' not in manifest:
    fail("package manifest does not declare the expected iOS library")
tests = (ROOT / "Tests/RailwayVehicleHighFidelityTests/VehicleHighFidelityTests.swift").read_text(encoding="utf-8")
if "testCabIndicatorStateControlsAllFictionalAnnunciatorLenses" not in tests:
    fail("vehicle tests missing cab-indicator-state coverage")

source_text = "\n".join(path.read_text(encoding="utf-8") for path in ROOT.rglob("*.swift"))
for forbidden in ("bve://", "sketchfab.com", "turbosquid.com"):
    if forbidden.lower() in source_text.lower():
        fail(f"unexpected third-party asset reference in source: {forbidden}")

print(f"PASS: {len(EXPECTED)} package/test files, lexical delimiter balance, manifest, and source/API contracts")
print("LIMIT: lexical balance is not Swift syntax checking; no Swift compiler, XCTest, RealityKit render, or device validation was run")
