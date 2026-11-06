# Vehicle / cab specification gap register

## Included in this isolated prototype

| Requirement | Prototype coverage | Limit |
|---|---|---|
| Exterior assembly detail | Split body belts/panels; front pillars and fascia; destination panel; coupler/gangway; windows and doors; side trim and lamps | Simple primitive volumes, no sculpted continuous shell or real model fidelity |
| Roof / underfloor | Three HVAC assemblies with grilles; pantograph geometry; named inverter, converter, compressor, resistor, battery casings, cooling slats and two pipes | Component placement and dimensions are invented for a fictional car |
| Running gear | Two bogie groups with side frames, beams, axles, wheels, hubs, brake discs/calipers, springs, dampers and frame fasteners; integrated high-quality host steers each bogie toward its sampled route tangent | Simplified geometry and visual yaw only; no suspension or wheel-rail contact simulation; not iPhone-verified |
| Cab | Dashboard, console, seat, grab rails, speed/pressure dial bezels and tick marks, needles, display cluster and named indicator lenses | Generic invented layout; not a model of a real operating cab; display labels are visual geometry and not tied to real systems |
| Moving controls | 15 named/clamped visual control nodes, door leaf translation, time-driven wiper sweep modes, collector extension, wheel rotation, bogie yaw, two gauge needles and headlights | No tap hit-testing/accessibility, state machine, save integration, physical linkage or actual operation mapping |
| Materials | Original color/roughness/metalness PBR parameter palette, tinted transparent glazing and selected emissive lenses | App model still has solid colors only: no texture maps/UVs/normal maps, wear layers, authored environment/reflection maps, refraction, rain drops, or calibrated lighting; separate texture experiment is not integrated |
| Rights | New procedural geometry only; fictional prototype; no BVE or third-party model data | No authentic vehicle numbering/decals/livery; any future real vehicle study requires documented reference rights and a distinct legal review |

## Still open against the supplied master directive

- **PART 4 — Cab operations and indications:** controls are visual handles only. All controls still need host hit testing and meaningful input behavior; force/coast/brakes, reverser, horn, wipers, lights, pantograph, main circuit, doors, PA, ATS acknowledgement and display modes must be mapped to app state. `setCabIndicatorState(_:)` now exposes seven explicit visual-only lamp states (ATSP, ATC, EB, door, power, regen, fault), but the host must supply them. Gauge telemetry remains limited to speed and brake-pipe pressure; current/voltage, notch and richer displays are still not wired.
- **3D goals in the supplied directives:** tinted glazing is transparent, but no rain on glass, authored reflection/refraction, tunnel brightness transitions, track/catenary/switches/platforms/passengers/ads/world scenery, rain/snow/smoke particles, sound propagation or wind force is implemented here.
- **Vehicle line-up and reference fidelity:** only one fictional single-car visual prototype. No accurate model-specific dimensions, internal arrangement, multi-car consist, accessible design references, measured/photogrammetry surfaces, vehicle number, or authentic livery.
- **Animation:** visual hooks cover wheel rotation, door leaves, time-driven wipers, pantograph, two gauge needles, front lamps and seven manually supplied indicator-lamp states. The high-quality app host now supplies route-tangent differences for bounded bogie yaw. No track-constrained wheel contact, bogie suspension, car-body roll/pitch, tail-light or cabin-light state, nor direct 3D cab-control hit-testing is implemented.
- **Rendering production work:** no sculpted curved nose/roof, production topology, custom UVs, texture baking, high/medium/low LOD, occlusion/instancing strategy, visual benchmark or scene-level lighting tune. Current `.balanced` reduces repeated slats/fasteners but is not a measured device-quality preset.
- **Runtime:** package was not built, tests were not executed, and no iPhone/Simulator view or performance readings exist in this environment. Host source changes are integrated, but they are not compiled or verified as running in the app.
- **Safety and data quality:** no real railway operating procedure or safety function is implemented here. All values and geometry are fictional and must not be presented as vehicle engineering data or training equipment.

## Minimum acceptance run on Mac/Xcode and target iPhone

1. Resolve package, clean-build app/package, run XCTest, record toolchain and device.
2. Capture exterior front/side/roof/undercarriage and seated driver-view screenshots at default and `.balanced`; inspect scale, occlusion, z-fighting, clipping and material response.
3. Exercise all 15 controls through host UI and assert the corresponding app/game state updates; independently update all cab indications from telemetry and assert no stale/conflicting lamps.
4. Check door movement, wiper sweep, wheel rotation, pantograph extension, and lamps at their min/max values and after save/load.
5. Profile object/mesh/material counts, GPU/CPU frame-time, memory, heat and battery on the oldest supported device; tune or add true LOD/mesh sharing before release.
6. Compare against lawfully usable references and get art/rights review. Only after this can visual quality or real-vehicle similarity be judged; passing source checks alone is not evidence of photorealism.
