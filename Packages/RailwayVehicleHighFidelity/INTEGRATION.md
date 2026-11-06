# Integration contract

This package is included at `Packages/RailwayVehicleHighFidelity/` and linked from the app and XCTest targets. The integrated high-quality scene uses its procedural model for the lead car; lower qualities and the rest of the consist retain the existing vehicle generator.

## Add to the iOS host

1. Add this directory to Xcode as a local Swift Package and link the `RailwayVehicleHighFidelity` product to the iOS app target.
2. Import `RailwayVehicleHighFidelity` in the app's RealityKit adapter.
3. Build once on the main actor/app scene setup path: `let model = RailwayVehicleHighFidelityBuilder.build(specification)` and attach `model.root` to the host's existing vehicle anchor.
4. Keep the `RailwayVehicleHighFidelityModel` reference alive. Use its `parts` map for visibility and tuning; do not rebuild the model each frame.
5. The integrated host maps speed/pipe pressure, brake/door/throttle/regen state, wipers, headlights, wheel travel, and bounded bogie yaw derived from route-tangent samples. Wiper sweeps are driven by the fictional simulation clock; bogie yaw is a visual tangent-following approximation, not wheel/rail dynamics. Only existing fictional simulator signals are presented: ATSP, ATC, and fault lamps remain off because the host has no corresponding live state. These methods only animate view entities; the host remains authoritative for simulation, input state, safety logic, doors, and audio.
6. The app builds the high-fidelity model only for the lead car in high quality; the remaining consist uses the existing generator. Confirm framing, dimensions, clipping, and frame time on a supported iPhone before treating it as a player-facing visual upgrade.
7. Add UI hit testing / accessibility labels separately. This package exposes handles but does not implement gestures, touch picking, camera switching, or operable SwiftUI controls.

## Stable API

- Build: `RailwayVehicleHighFidelityBuilder.build(_:) -> RailwayVehicleHighFidelityModel`
- Scene root: `model.root`
- Named independent groups: `model.parts[HighFidelityVehiclePart]`
- Control handles and clamped values: `model.controls.nodes`, `setValue(_:for:)`, `value(for:)`
- Visual dynamic state: `model.animatedParts`
- Time-driven visual wipers: `setWiperState(_:simulationTimeSeconds:)`
- Bounded visual bogie yaw: `setBogieYaw(frontRadians:rearRadians:)`
- Seven host-supplied cab annunciators: `setCabIndicatorState(_:)` with `VehicleCabIndicatorState`
- Specification: fictional identifier/name, configurable length/width/height, `.balanced` or `.high` geometry detail
- Axes: X=width, Y=up, Z=length, cab front at -Z; metres

## Release gate

The source-only checks are not acceptance. On supported Xcode/iPhone versions: resolve the local package; clean build; run package XCTest; render exterior and driver-view closeups; verify windows do not occlude dashboard and controls; check curve transitions, wiper modes, every control-to-game-state link, and save/restore behavior in the host; measure object count, GPU/CPU frame time, memory, heat, and battery; review low/balanced quality on the oldest supported iPhone; obtain legal review of any real-world reference or third-party asset before adoption.
