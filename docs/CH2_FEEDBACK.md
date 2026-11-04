# CH2 feedback: what Kine could not do for a running mechanical clock

Challenge: a seconds-beating regulator movement (docs/CH2_REFERENCE.md), involute gears, 994 mm pendulum, anchor escapement, brass / steel / glass render.
Code: scripts/build/clock_ch2.gd (model), clock_ch2_scene.gd (3D), native/src/kine_clock_native.cpp (per-frame contact), tests/ch2_test.gd, tools/ch2_render.gd.

## What went through the Part API, and what did not (second pass)
Built as Part records (scripts/build/clock_ch2_parts.gd; Part.make + sketch / extrude / pattern / combine / move; replayed by Part.body_faces; the scene draws that
mesh): 8 gears + barrel gear + its pinion (spokes cut as an annulus window, one bar patterned, joined), the 30-tooth escape wheel, the anchor (hub, two arms,
two pallets, combined), anchor arbor, crutch (stem moved by a Move step, two pins and a cross bar combined), arbors C T E M, the spring arbor, hour pipe, going
barrel (drum with floor, cavity cut) and lid, three hands, three collets, back and front plates (arbor holes cut), four pillars, barrel bridge, escapement cock,
dial (windows cut), 120 dial ticks (one sketch), 12 numerals (Kine's PartText font outlines in one sketch). That is 28 moving + 11 structural = 39 Part-built bodies;
each scene node carries meta part_features (its feature kinds) and bar 8 checks it. Script-made: the pendulum rod and bob (kept as primitives because the unedited
bar 2 measures the bob as a CylinderMesh), eight screw heads, the walnut case, glass, floor and wall.

Gaps found (script path kept for these pieces only):
| # | Missing feature | Where it bit | Difficulty |
|---|---|---|---|
| 1 | No involute curve entity or gear macro in the sketch: the tooth flank is 8 sampled points per side, entered as lines | every gear: the OUTLINE points come from ClockCH2.involute_outline, everything after is Part | Small (an involute sketch entity or a Gear template with pressure angle) |
| 2 | Circular pattern of a tooth is slow: it fuses copies one by one, super-linear in the count. 30 teeth 5.6 s, 64 teeth 18-30 s, 56 teeth 18 s; the whole clock replays in ~100 s | triangles are cached in assets/ch2_parts/ under the feature-list hash (2.1 MB); without the cache the test takes 2 extra minutes | Medium (pattern as ONE boolean of all copies, or a "pattern into a sketch" step that repeats a loop) |
| 3 | A pattern only copies a body, not a sketch loop or a cut: every spoke wheel needs "cut ring, add one bar, pattern the bar, combine" instead of "cut one window, pattern the cut" (the FRULER row of cuts exists for linear rows only) | spokes | Small (circular _cut_row) |
| 4 | The sketch plane cannot be placed along z by a number; I used a Move step per body (crutch stem) and put each part's z in the scene node | plate, dial, hands, crutch | Small (a plane at offset in the Sketch UI exists; the feature list needs it from a number) |
| 5 | No text on a sketch plane outside Easy Part: I called PartText directly (works headless) | dial numerals | Small to expose as a Sketch tool |
| 6 | Part has no assembly state: every body is its own record, the clock is 39 records plus a script that places them. Kine's assembly needs a "mesh" joint and a record per part | all | Large (see 1 below) |
| 7 | No contact-driven motion, no mesh joint (Turn it drives ONE gear pair) | train driver is ClockCH2.drive() | Small (the maths is 40 lines) |
| 8 | Clearance of many moving parts every frame is GDScript in assembly_dof / collide_live; C++ pair_overlaps (2D flats stacked in z) did it | 68 z-sharing pairs, 3600 frames | Medium |
| 9 | Physics-driven time (pendulum period from length) is not a film key | pendulum_run RK4 | Small as a driver |
| 10 | Materials: no brass / steel / enamel presets, no motion-blur video export, no indoor light rig | scene materials, 4 sub-frames per frame averaged by ffmpeg | Small to Medium |

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
