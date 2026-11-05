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
