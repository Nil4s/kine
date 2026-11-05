# Engineering challenges: the feedback every lane must write, and the gaps found so far

Nick (11-04): every building challenge ends with feedback, and the feedback rates its engineering level. Most challenges are engineering-level in complexity and detail. Their point is to push Kine (and the agents) to the limit and find out what is lacking.

## 1. The required feedback doc (`docs/CHxx_FEEDBACK.md`)

Every challenge lane writes these sections. A lane is not done without them.

1. **Result:** the bar table (ok / fail, every planted control), the key numbers against the cited real object, and the last commit.
2. **Engineering level reached:** a grade on the scale in section 2, per discipline the challenge touches (mechanical, structural, electrical, fluids, thermal, ...). Give the evidence for the grade and what the next level would need. Be honest: a model with assumed dimensions is not L4 just because its maths is right.
3. **What Kine lacked:** one row per gap, each with:
   - the thing the lane needed
   - what exists in Kine today (file / command), or "nothing"
   - the workaround the lane used (e.g. "wrote 200 lines of GDScript", "scripted KCad booleans")
   - the cost of that workaround (lines, hours, or "could not do it")
   - a proposed feature in one sentence

   Search the code before claiming a gap. A tool that exists but the lane did not find is a DISCOVERABILITY gap, which is also a gap: say so.
4. **What looks wrong:** after LOOKING at the contact sheet, the section and the video frames.
5. **What was changed after seeing results:** every amended bar and why (git has the diff).

The lead copies section 3's rows into the ledger below, one line each, so gaps from many challenges can be counted and ranked.

## 2. Engineering level scale

| level | name | what it means here |
|---|---|---|
| L1 | sketch | looks right; proportions by eye; no numbers checked |
| L2 | maker | real dimensions from a cited object; it fits together; simple checks (reach, counts) |
| L3 | student engineer | first-principles calculations, each checked by hand arithmetic or a closed form; cited material and catalogue values; planted controls; assumptions flagged |
| L4 | professional design check | the governing code or standard applied (ISO 286, IRC, AISC, IEC, ASME ...); tolerances and stack-ups; load cases and combinations; numerical analysis cross-checked against a closed form; drawings someone could build from |
| L5 | licensed / regulatory | what a stamped design or a safety case needs: full code compliance, independent verification, real site data, QA. Out of reach for an app challenge; name what would be needed |

## 3. Challenges graded so far

| challenge | level reached | why not higher |
|---|---|---|
| CH13 single-cylinder engine | mechanical L3-L4 (ISO 286 fits and stack-up are L4; the dimensions are assumed, not from a drawing) | L4 needs the real C50 drawings, crank balance, bearing life and an FEA of the rod |
| CH14 syringe hydraulic arm | mechanical/fluids L3 | prices and several material values are ASSUMED; no prototype measurement; compliance is a lumped model |
| CH1e fasteners on the house | structural L4 for connections (IRC schedule, Simpson values, R403.1.6) | L5 needs local code (Brazil NBR 7190) and an engineer's review |
| CH1f soil + masonry/LSF house (Mato Grosso) | structural dynamics L3, geotechnical L2-L3, masonry/LSF L2-L3 | El Centro stand-in, not an NBR spectrum; no load combinations; walls as lines; no soil report |
| SRETOPO stroke retopology | geometry processing L3 | open-edge regions are skipped, not filled; no comparison against a reference retopo tool on the same strokes |
| CH5c wet street at night (PARKED) | rendering/optics L2-L3 | wet roughness, wetness and bump height unsourced; the glint streak needs a direction-aware roughness filter |
| CH15 nuclear plant (Angra 2 class PWR) | thermal-fluids, electrical, containment, decay heat L3; mechanical and civil/layout L2 | 8 of 12 footprints and all heights assumed; no transient analysis; block-level equipment |
| CH8b liquids (PARKED, 28/5) | fluids/CFD L3 | blocked-cell walls, no air phase; the Martin and Moyce front leads by 24 pct |
| CH6b bowline on a simulated rope (PARKED, 11/16) | rope/contact mechanics L3, knot topology L2-L3, hand manipulation L1-L2 | no knot forms: the hand cannot pass from behind to in front of the standing part without crossing rope; the code check is view-dependent |
| CH7b parkour run (PARKED, 21/1) | landings and flight L3, joint limits and timing L2 | no whole-body COM, contact impulses or conserved spin in flight; the course was changed to fit gravity |

## 4. Gap ledger (one row per gap; newest last)

| # | from | needed | exists today | workaround | proposed feature |
|---|---|---|---|---|---|
| G1 | CH13 | clash detection while a mechanism MOVES (parts passing through each other over a cycle) | Part.HIT_VOL checks bodies inside one part; KCad.overlap_volume (C70) is a kernel call only | bar j scripted 390 KCad booleans over 36 crank angles; it found 4 real clashes | Assembly "Check motion": sweep the joint parameter, list clashing pairs and angles, colour them red on the timeline |
| G2 | CH13 | kinematic joints in an Assembly (slider-crank: revolute + prismatic, closed loop) | Assembly parts have a pose (pos/rot) only | pose_of() computed every part's pose in GDScript | Assembly joints (revolute, slider, gear, rack) with a loop solver and a drive parameter |
| G3 | CH13 | tolerances and fits on a Part (ISO 286 class on a hole/shaft, stack-up chains) | nothing in Part; the lane wrote ch13_engine.gd (IT tables, deviations) | 362 lines of GDScript | fit classes as Part dimension attributes, with a stack-up panel (worst case + RSS) |
| G4 | CH13, CH14 | double precision in poses | Transform3D and Vector2 are float32: about 1e-4 mm at 100 mm | bars amended to 1e-4 mm | keep CAD poses in doubles (Dictionary floats / PackedFloat64Array) and convert only for display |
| G5 | CH14 | hydraulic and fluid circuit elements (syringe pair, hose compliance, air) | nothing | ch14_arm.gd closed forms | a "circuit" layer: hydraulic and pneumatic actuators with line compliance, joined to Assembly joints |
| G6 | CH14 | flexible hoses and cables routed between parts | nothing (cloth and rope exist for animation, not for CAD routing) | hoses not drawn | a hose/cable route tool: spline through clips, length readout, bend radius check |
| G7 | CH14 | linkage animation driven from the Assembly timeline | Assembly view poses parts; no driven timeline | ch14_scene.gd (240 lines) built a custom node hierarchy | Assembly animation: keyframe the drive parameters and record the build sequence |
| G8 | CH14 | BOM with prices and a cost optimiser | no BOM in Assembly; CH4 cut list for wood only | ch14_bom.gd | Assembly BOM (part, material, qty, mass from CAD, price table) with export |
| G9 | CH14 | gears with involute teeth | an involute generator exists (clock_ch2, gear tool C-items) | the lane drew box teeth: a DISCOVERABILITY gap | Part step "gear" listed in the step menu and the agent brief |
| G10 | CH14 | STL of a Part in Z-up mm from a script | print_check / slicer_send export from the UI | the test converted the mesh by hand | one scripted call: Part.export_stl(rec, path) |
| G11 | CH13, CH14 | contact sheet and video of an assembly | each lane writes its own scene and grab loop | about 100 lines per lane | a shared "render sequence" helper: assembly + timeline -> frames, sheet, mp4 |
| G12 | CH1f | soil under a structure (springs and dashpots per soil class) | nothing | ch1f_soil.gd (Gazetas closed forms) | a Foundation property on a building: soil class -> springs, used by the CH10 solver |
| G13 | CH1f | wall systems as switchable materials on one plan | wood framing only | ch1f_systems.gd built each system by hand | a wall-system picker that regenerates members, mass and stiffness |
| G14 | CH1f | Brazilian code loads (NBR 6123 wind, NBR 15421 seismic) | nothing | constants from memory | code load generators per region, with the source printed |
| G15 | CH1f | masonry and shear walls as panels in the frame solver | beam elements only | walls drawn as lines | a shell or equivalent-strut wall element |
| G16 | SRETOPO | retopo across a mesh's open edges (neck, face holes) | regions with a boundary edge are skipped; the UI says only "3 regions skipped" | none | name the skipped regions and offer to close the hole or use the boundary as a side |
| G17 | CH5c | match a camera to a photo (lens, height, horizon) | nothing | camera solved by hand from EXIF and brick courses | a photo-match camera tool: pick lines -> focal, height, tilt |
| G18 | CH5c | a direction-aware roughness filter so tiny shiny normals don't sparkle at a distance | nothing (Toksvig was tried: grey wash) | could not do it | anisotropic normal-map roughness filtering (LEAN/vMF style) in the PBR material |
| G19 | CH5c | a wet material state (darkened albedo, low roughness, puddles) | nothing | hand-set roughness per material | a wetness slider on materials, plus puddle decals |
| G20 | CH5c | soft shadows from a sized lamp 20 m away | the engine's shadow blur has a floor (both control and real at 2.8-3.1 px) | could not do it | PCSS with a light-size parameter that resolves at distance |
| G21 | CH5c, CH13, CH14 | render-vs-photo and render-sequence comparison | each lane writes its own side-by-side and grab loop | about 100 lines per lane | one shared compare/render helper (see G11) |
| G22 | CH7b | a contact-schedule solver: pin limbs to surfaces, solve the pelvis ballistically between contacts | nothing | about 520 lines of lane code | contact-first motion planning in the move tools |
| G23 | CH7b | a hand that conforms flat to a surface | the hand is one capsule | 13-54 mm palm penetrations | a palm/fingers collision shape that can lie flat |
| G24 | CH7b | keep free limbs out of obstacles while animating | nothing | a custom avoidance pass | obstacle avoidance for non-contact limbs in IK |
| G25 | CH7b | pinned body-surface contacts (shoulder, back, hip) for a roll | foot/hand contacts only | the roll became a tight ball | body-surface contact targets |
| G26 | CH7b | whole-body centre of mass and jump arcs off obstacles | Balance.com and floor-only jump arcs exist: a DISCOVERABILITY gap | used the pelvis as the COM | list Balance.com in the agent brief; jump arcs from any surface |
| G27 | CH15 | Part meshing at building scale | **FIXED #195**: Part.fine_defl scales the deflection with body size (28 m shell 144 s -> 8.9 s) | 1 cm self-meshing in the lane | done |
| G28 | CH15 | Split of a body bigger than 20 m | **FIXED #195**: the half-space is sized from the bodies | a 2 km cut box | done |
| G29 | CH15 | a refused boolean cut was silent | **FIXED #195**: it is the step's error naming the body (the concentric-sphere repro itself did not reproduce) | revolved profiles | done |
| G30 | CH15 | blueprints of anything but Building records (site plan, section of a Part assembly) | blueprint.gd draws Building records only | site plan and section drawn by hand: they can drift from the model | Blueprint from an Assembly: plan and section views with dimensions |
| G31 | CH15 | electrical one-line / schematic diagrams | nothing | SVG drawn by the lane's code | a schematic editor with IEC symbols and ratings on the parts |
| G32 | CH15 | water/steam properties (IAPWS-IF97) and thermodynamic cycles | nothing | GDScript IF97 written in the lane (30 check values to 2.8e-9) | promote ch15's IF97 to a shared module with a cycle calculator |
| G33 | CH15 | construction staging (build order, support check, sequence video) | nothing | ch15 build sequence and support check | Assembly stages: each stage adds parts, with a support check and a staged video |
| G34 | CH8b | sub-cell fluid walls (a mug holds its real volume) | the grid blocks any cell a wall touches (caps the mug at 86-89 pct) | could not do it | cut-cell or variational walls (Batty 2007) in the fluid solver |
| G35 | CH8b | an air phase and a better free-surface boundary | water only | none (the dam front leads the paper by 24 pct) | a two-phase option or ghost-fluid free surface |
| G36 | CH8b | fluids in the app UI | the solver exists only in tests and tools | none | a Fluid emitter / container in the scene with a water material |
| G37 | CH8b | testing native code without Godot | nothing checked in | Godot runs only | a small C++ test harness for native/ |

| G38 | CH6b | a hand that can grasp and pass rope (slim palm, fingers, wrist orientation) | the rig's palm is one 9 cm capsule (see G23) | replaced by 4 slim capsules | an articulated hand collision model and a grasp pose solver |
| G39 | CH6b | a clearance-aware transit planner for a hand among rope and body | nothing | waypoints by hand; the hand dragged the rope | hand path planning that avoids rope and body (sampling or optimisation) |
| G40 | CH6b | a real off hand that holds rope (not frozen particles) | frozen rope particles only | hand-through-held-rope never measured | two-hand rope holding with contact, both hands simulated |
| G41 | CH6b | a topological knot invariant (not a view-dependent crossing code) | Gauss code from one view | false P2 fail in pass 1 | a knot-type check (e.g. Dowker-Thistlethwaite reduction or Alexander polynomial) |

## 5. Tools that already exist (search before writing your own)
Several lanes rebuilt tools Kine already had (gaps G9, G26, and the CH1f cutaway). Before writing a helper, check this list and grep:
- **Involute gears:** scripts/build/part_gear.gd (+ part_gear_ui.gd), clock_ch2.gd involute_outline(), scripts/gear_drive.gd.
- **Overlap of posed parts:** KCad.overlap_volume (scripts/kcad.gd). Pose exact solids with ch13_parts.gd solid() / place().
- **Section or cutaway render:** scripts/build/section_look.gd (SectionLook; ch13_scene.gd set_cut shows the use).
- **Whole-body centre of mass:** Balance.com(body) (scripts/balance.gd).
- **STL export:** scripts/build/mesh_export.gd write_stl. Print checks: print_check.gd, slicer_send.gd.
- **Blueprints and SVG with a title block:** scripts/build/blueprint.gd, blueprint_view.gd, ch15_draw.gd (site plan, section, one-line).
- **Water/steam properties (IAPWS-IF97):** scripts/build/ch15_if97.gd.
- **BOM with prices and a cheapest-design search:** ch14_bom.gd.
- **Contact sheets and frame grabs:** grab() in tests/ch13_test.gd and ch14_test.gd, plus ch14_scene.gd.
- **Big parts:** Part.fine_defl() scales the meshing with size, and Split works at any size (#195).

The lane brief (kine_workers/q4/_sonnet_brief.txt) carries the same list.