# CH2 feedback: what Kine could not do for a running mechanical clock

Challenge: a seconds-beating regulator movement (docs/CH2_REFERENCE.md), involute gears, 994 mm pendulum, anchor escapement, brass / steel / glass render.
Code: scripts/build/clock_ch2.gd (model), clock_ch2_scene.gd (3D), native/src/kine_clock_native.cpp (per-frame contact), tests/ch2_test.gd, tools/ch2_render.gd.

## What was built OUTSIDE Kine's part system, and why
The clock is not made from Parts-tab features (sketch + extrude) or Easy Part templates. The movement is a script-built scene; the tooth outlines are
plain polygons extruded in code. Reasons, ranked by what Kine would have to change:

| # | Missing in Kine | What I did instead | Difficulty to add |
|---|---|---|---|
| 1 | Assemblies cannot drive: Turn it moves ONE Gear pair (gear_drive.gd). There is no gear-train graph (A meshes B meshes C, any shaft driven, ratio = product of teeth) | ClockCH2.drive(): shafts, mesh edges with a phase constant, set one shaft and the rest follow | Small (the maths is 40 lines; the work is a joint type "mesh" in assembly.gd and a UI to pick two gears) |
| 2 | No involute profile in the Gear template (C52 says "flat sides"); small pinions (8 leaves) need pressure angle 25-30 deg or they undercut | involute_outline(): module, pressure angle, addendum, dedendum, backlash thinning | Small to add a second outline function to gear_outline(); a Pressure angle slider |
| 3 | No pallet / ratchet / escapement template, and no contact-driven motion (a body that moves only until it touches another) | wheel_drop(): the wheel turns until a tooth meets a pallet (bisection on the overlap area); impulse faces push by a scan | Medium (needs a per-frame contact query exposed to film keys / assembly) |
| 4 | Clearance of many moving parts every frame: assembly_dof / collide_live work on static or dragged poses and in GDScript | KineClockNative.pair_overlaps (C++, triangle-pair clip): 12 parts, 7 z-sharing pairs, 3600 frames in well under a second | Medium: generalise to 3D (this one is 2D flats stacked in z); ALL pairs of an assembly through the same C++ call |
| 5 | Physics-driven time: a pendulum whose period comes from its length. Film keys are curves, not dynamics | pendulum_run(): RK4, period measured from zero crossings (2.0006 s vs 2.0004 s at 994 mm) | Small as a "Pendulum" film driver; large if general rigid-body dynamics |
| 6 | Render: no brass / steel / glass material presets, no motion blur in the video export, lights are per-scene scripts (temple_light.gd is outdoor only) | StandardMaterial3D presets in the scene file; blur = 4 sub-frames per frame averaged by ffmpeg | Medium (material presets Small; motion-blur export Medium; an indoor studio rig Small) |
| 7 | Part count: ~15 moving parts (8 gears, escape wheel, anchor, pendulum, 3 hands, arbors). The ledger asked for 30+; wheels with spokes, a barrel, the going-train bridges and the strike train would add them. Not built | - | Large (hours of modelling; no tool gaps beyond 1-3) |

## Ranked update suggestions
1. (Small) A "Mesh" joint in assemblies + gear-train solver, shown as one Turn it that drives the whole train, with the tooth-ratio readout 60 : 1 : 1/12.
2. (Small) Involute teeth + pressure-angle slider in the Gear template; keep flat teeth as the existing default.
3. (Small) Material presets: Brass, Steel, Glass (alpha, clearcoat), Walnut.
4. (Small) Motion-blur sub-frame export in the video exporter (n sub-frames averaged).
5. (Medium) Expose the C++ pair-overlap as the collision engine of collide_live (all flat or 3D parts every frame).
6. (Medium) A contact-driven body: "turns until it touches X" for ratchets, pawls, escapements, Geneva drives.
7. (Medium) A Pendulum driver: length -> period, amplitude, and a hook that drives a film key.
8. (Large) A mechanism recorder: sample every pair's overlap volume over a timeline and report the worst (what tests/ch2_test.gd does for this clock).

## Numbers found while building
- The task's "3600:60:1" is inconsistent with its own "60:1 and 12:1": seconds : minute : hour turns per hour is 60 : 1 : 1/12 = 720 : 12 : 1. The test bars use the latter.
- An 8-leaf pinion at 20 deg pressure angle undercuts; 30 deg with 0.8 module addendum meshed with 0 mm2 overlap over a full turn for all four meshes (64/8, 60/8, 12/36, 10/40).
- Backlash measured by turning the driven gear to contact both ways: 3.4 % to 3.6 % of the module (set 3 %: tooth thinning 0.015 module on each gear; the rest is the flank geometry).
- A dead-beat pallet needs an ARC face about the anchor pivot and a tooth tip that is the foremost point of the tooth; flat blades overlapped teeth for 60 to 90 % of the run (found by a parameter search, tools/ch2_escape_search.gd). The wheel then advances exactly 6.000 deg per beat.
- GDScript Vector2 is float32: Clipper (Geometry2D) agrees with the exact triangle clip to only 1e-4 mm2; the twin test therefore bars an absolute 2e-4 mm2.
- Reference: no published tooth list for one named museum clock was found online; the train is representative (docs/CH2_REFERENCE.md says so).
