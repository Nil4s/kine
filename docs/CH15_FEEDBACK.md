# CH15 feedback: an Angra 2 class PWR plant, its blueprints, its one-line and its construction section video

Lane w4-ch15. Brief: docs/CH15_BRIEF.md. Every number and its source: docs/CH15_REFERENCE.md. Test: tests/ch15_test.gd (registered as `ch15:w` in tools/run_all.sh).
Code: scripts/build/ch15_if97.gd (IAPWS-IF97 regions 1, 2, 4, GDScript), ch15_plant.gd (physics + one-line model), ch15_parts.gd (53 Part records),
ch15_site.gd (assembly, plant-scale meshing, layout and support checks), ch15_draw.gd (three Blueprint sheets), ch15_scene.gd (section video).

## 1. Result

`wtest.sh ch15 easypart peasy3 freestart`: ch15 ok 44 fail 0, easypart ok 73, peasy3 ok 23, freestart ok 14, no script errors.

| bar | result | planted control |
|---|---|---|
| 1 primary Q = m cp dT | ok: 18800 kg/s x 5.6982 kJ/kg K (IF97 R1, 308.6 C, 15.5 MPa) x 34.8 K = 3728.0 MWt, 1.14 pct under 3771 (the enthalpy route m dh gives 3766.5, 0.12 pct) | ok: one loop 932 MWt, 75 pct off |
| 2a IF97 | ok: 30 values of tables 5, 15, 35, 36, worst relative 2.8e-9 | (the tables are the control) |
| 2b Rankine | ok: ideal cycle 6.2959 MPa x 0.9975 to 6.622 kPa (37.97 C) = 36.69 pct, cited 35.80 (+0.89 points); Carnot 43.63 pct | ok: ideal-gas steam 186.9 pct, caught |
| 3 electrical | ok: S = 1350/0.9 = 1500 MVA, I = 34 641 A at 25 kV; MT 1560 >= 1500 and 1458; UAT 2 x 50 and SST 90 >= 82.35 MVA; (4-2) x 5.4 = 10.8 >= 9.2 MW | ok: three diesels 5.4 < 9.2 MW |
| 4 decay | ok: Way-Wigner 3.731 / 1.016 / 0.447 pct at 10 s / 1 h / 1 d; boil-off at 1 h 38.30 MW / 2649.8 kJ/kg = 14.45 kg/s <= 36 kg/s | ok: T_op = 0 gives 0, outside 0.5..2 pct |
| 5 sphere | ok: Angra 2 247.3 <= 289.7 MPa; Angra 3 cross-check 195.3 <= 214 MPa (cited) | ok: cylinder p R / t = 390.5 MPa, 2x and over 214 |
| 6 layout | ok: 53 records build; 12 buildings within 5 pct (0.00 pct, see 2 below); 239 building part pairs and 66 equipment pairs through KCad.overlap_volume, no overlap | ok: turbine hall 60 m into the reactor building, 19+ clashing pairs |
| 7 build | ok: 53 of 53 parts rest on built parts over 10 stages; video 10 frames in order, all differ, each stage colour grows; section frame 3964 red px, the closed building 0 | ok: dome before wall: "Shield wall is not built yet" |
| 8 hand | ok: 11 hand checks at 1e-9 | ok: exponent -0.25 is 29 pct off |
| 9 drawings (extra) | ok: three SVGs with title block and scale; 24 dimensions on the site plan; 15 buses with kV and 8 transformers with MVA on the one-line | ok: a transformer without MVA is caught |

Key numbers against Angra 2: thermal 3771 MWt (model 3728 by cp, 3766.5 by enthalpy); gross 1350 / net 1280 MWe (house 70 MW); ideal-cycle efficiency 36.7 pct vs 35.8 pct thermal yield; primary 4 x 4700 kg/s, steam 2055 kg/s cited; generator 1458 MVA nameplate, 1500 MVA needed at cos phi 0.9 (the nameplate runs 1350 MW at cos phi 0.926), 25 kV, 33.7 kA nameplate; 500 kV grid; main transformer 1560 MVA (ASSUMED); diesels 4 x 5.4 MW + 4 x 0.86 MW (SEEN).
Pictures: docs/ch15/ch15_build_sheet.png (10 stages), ch15_section.png (section frame), ch15_site.svg / ch15_section.svg / ch15_oneline.svg and their PNGs ch15_sheet_*.png.

## 2. Engineering level reached

| discipline | level | evidence | the next level needs |
|---|---|---|---|
| thermal-fluids | L3 | IF97 implemented and verified to 3e-9 against the release's tables; heat balance from FSAR flows and temperatures; condenser derived from the cited seawater flow and temperature; planted controls | L4: a full heat balance (HP/LP efficiencies, moisture separator reheater, 7 feed heaters, pump power) closing on 1350 MWe within 1 pct; the ideal cycle lands near the real number only because the losses and the regeneration roughly cancel |
| electrical | L3 | S, I, transformer and diesel sizing by hand from the SEEN nameplates; one-line drawn from the model and checked label by label | L4: IEC 60909 short-circuit levels at 500 / 25 / 10 kV, breaker duty, voltage drop and motor starting on a diesel, the diesel load sequence; MT / UAT / SST ratings are ASSUMED |
| structural (containment) | L3 | membrane stress against the SEEN KTA 3401.2 criterion (Pm <= 0.67 Rp); the Angra 3 cross-check is consistent with 5.3 bar gauge | L4: KTA 3401.2 load combinations, buckling under external pressure, penetrations and the equipment hatch, the 145 C yield of WStE 51 (ASSUMED by ratio) and Angra 2's real wall thickness (ASSUMED 30 mm) |
| nuclear (decay heat) | L3 | Way-Wigner closed form checked by hand, emergency feedwater boil-off | L4: ANS-5.1-2014 with its uncertainty and the 3-batch core history; the feed pump capacity per pump |
| mechanical (primary circuit, turbines) | L2 | block sizes (MEMORY / ASSUMED), real loop layout, exact-solid overlap checks | L3+: nozzle loads, pipe stress (ASME III NB-3600), RCP and SG supports, real component drawings |
| civil / layout | L2 | four footprints measured on Esri imagery at 1.1 m/px (reactor 71.5 m, turbine hall 93 x 50, switchyard 280 x 190, intake 70 x 35); heights ASSUMED; 8 of 12 buildings ASSUMED, so for them the 5 pct bar only checks the model against its own table | L3: measured heights (shadows or drawings), the real auxiliary/diesel/feedwater buildings, terrain (the site is cut into steep hills); L4: foundations (Angra 2 is on piles, reinforced in 1980 [E]) |

## 3. What Kine lacked

| # | needed | exists today | workaround | cost | proposed feature |
|---|---|---|---|---|---|
| 1 | meshing a Part at plant scale | Part._tess_cached tessellates every body at 0.3 mm absolute (part.gd line 942); Assembly.built uses it | ch15_site.built(): replay with defer_tess, KCad.tessellate at 1 cm | 576 s for four sphere records before; 16 s for the whole test after; 35 lines | a deflection relative to the body's size (or a record-level "tess" field) in Part.replay and Assembly.built |
| 2 | Split at building scale | Part._half is a 20 m box (part.gd line 2662): a Split of a 56 m sphere bites a 20 m hole and leaves the rest | the section is a cut prim with a 2 km box | 1 run lost; 3 lines | size the half-space from the bodies' bounds |
| 3 | hemispherical shells by prims | prim sphere + cut sphere + cut box replays to the wrong body in Part (the full half's volume, or the whole shell) while the same KCad calls alone give the right volumes; Part._combine keeps a body silently when KCad.cut returns 0 (part.gd line 2316) | hemi_shell(): a Sketch of the quarter annulus + Revolve | about 1.5 h of debugging, 20 lines | a cut that fails is an error on the step, and the concentric-sphere cut case is found and fixed |
| 4 | section drawing of an Assembly (cut plane -> 2D outlines with poche) | Blueprint draws Building records only (rooms, walls); PartUI has a view-only section (part_section_plane, section_look.gd), not a drawing | the reactor-building section was drawn by hand from Blueprint's entity helpers | about 90 lines; not derived from the solids, so it can drift from the model | Assembly "Section drawing": a plane through the assembly -> Blueprint sheet with the cut faces filled and the parts beyond in outline |
| 5 | site plan from an Assembly | nothing (Blueprint needs rooms) | footprints from the parts' boxes drawn as polygons + dims | about 50 lines | a plan view of an Assembly: footprints, labels, dimension chains, north arrow, scale |
| 6 | electrical one-line / schematic | nothing (searched one-line, schematic, single line) | one_line() model + a hand-placed drawing + a label checker | about 140 lines | a schematic layer: buses, transformers, breakers, generators with ratings, laid out automatically, exported as a Blueprint sheet |
| 7 | water / steam properties | nothing (searched IAPWS, IF97, steam table) | ch15_if97.gd from the IAPWS release | 130 lines, GDScript | a thermo library (IF97 regions 1-5, backward equations) available to scripts and to an engineering panel |
| 8 | construction sequence (4D): stages, support check, staged render | nothing in Assembly (same family as G7 / G11) | stages table, support_check(), show_stage() with flat stage colours | about 120 lines | Assembly stages on the timeline: each part's stage, a "rests on" check, a staged video export |
| 9 | Blueprint helpers as an API | _dim, _frame, _poly, _text are underscore functions; title_of() only knows Floor / Front / Side | called the private helpers and rewrote the title and scale text afterwards ("NTS" for the one-line) | DISCOVERABILITY + fragility; 15 lines | public sheet-building calls (frame with any title and scale text, dimension, poly, text) |
| 10 | contact sheet and video of an assembly | each lane writes its own (G11) | the CH14 grab loop again, plus a SubViewport painter for the sheets | about 80 lines | G11's shared render-sequence helper |
| 11 | Assembly.built memo | 64 entries, cleared when full (assembly.gd line 71) | own memo in ch15_site.built() | small | a memo sized by vertex count, not by entries |
| 12 | a fresh worktree runs a test | class_name scripts (Part, Assembly, Blueprint) are not declared until the editor has imported once | `godot --headless --path . --import` first | 1 failed run | wtest / the test runner imports a fresh worktree first, or the lane setup does |

## 4. What looks wrong (after looking at every picture)

- Contact sheet (docs/ch15/ch15_build_sheet.png): frame 1 is the 600 m ground slab all in yellow; the base mat in the pit cannot be seen. Stages 5 and 6 (polar crane, vessel and SGs) are small at this distance: the camera shows the whole site, so the inside of the reactor building is about 70 px wide. The switchyard is cut by the top of the frame. The ground is flat and the sea a blue slab: Angra sits on a narrow shelf between steep hills and Itaorna bay.
- Section frame (ch15_section.png): six buildings that stand between this camera and the cut (auxiliary, fuel, diesel 1 and 2, intake, outfall) are hidden for this view only. The vessel's cut face reads as a red triangle (the half cylinder seen past the cavity wall). Pipes are posed by rotation, so the z = 0 cut cannot be applied in their frame: those on the near side are hidden, not cut. The steel sphere's lower bowl stands in an empty pit: the real plant has a concrete cup under it.
- Site plan (ch15_sheet_site.png): the reactor building and the turbine hall nearly touch (0.55 m, straight from the satellite measurement, an oblique view good to about +-3 m). Small buildings' names now sit under them but still crowd the dimensions. The shoreline is ASSUMED and passes through the outfall. The diesel, fuel, feedwater and auxiliary positions are ASSUMED.
- Section drawing (ch15_sheet_section.png): "+0.00 grade" is struck through by the ground line, and the 2.00 wall dimension's text collides with the wall. Concrete is drawn as solid black (poche) with no hatch. The SGs and pumps behind the cut are drawn projected, the pumps dashed.
- One-line (ch15_sheet_oneline.png): no tie between the BA/BB and BC/BD halves (only through the generator bus); the main transformer is one two-winding symbol, not the three single-phase units it is said to be; ratings print a trailing ".0" (500.0 kV).

## 5. What was changed after seeing results

- Before the first run (commit 6695a0f9): the video frames are the section frames, and the closed-building control is the same camera on the uncut model.
- Test harness (no bar loosened): bar 6 builds meshes with ch15_site.built() because Assembly.built's 0.3 mm tessellation took 576 s for four sphere records. An end check was added that every bar ran to its end, because a script error inside bar 9 had printed "0 fail". The sheet PNGs were renamed after one of them overwrote the 3D section frame.
- ch15_site.clashes: the first run used a box pre-filter and checked 0 building pairs exactly (all the boxes were apart). The pre-filter was removed, so all 239 pairs now go through the kernel. This made the bar stricter.
- Model after the pictures: the section is a 2 km cut box, not Split (gap 2). The sphere halves and the dome are revolved profiles, not sphere booleans (gap 3). The video camera moved closer. The section camera moved past the auxiliary building's corner and hides the six buildings in front. The one-line feeds are drawn straight down (UAT2 to BC, standby to BD; before, they ran along bus BB and looked like a tie). Small buildings are labelled under their outlines.

## 6. L4 update (lane w4-eng2, 2026-11-05): three of the "next level needs" taken up
The three cheapest, picked because each is closed-form on numbers already in the reference: electrical short circuit, sphere buckling, decay heat with a core history. Bars 10-12 of tests/ch15_test.gd (committed in 23cff76c before they first ran; bars 1-9 untouched); sources and ASSUMED inputs in docs/CH15_REFERENCE.md section 9; models at the end of scripts/build/ch15_plant.gd. Result: `ch15 ok 61 fail 0` in wtest (was 44).

| bar | result | planted control |
|---|---|---|
| 10a GCB duty (IEC 60909: c 1.1, KT, KG) | system-fed 194.640074 kA, generator-fed 134.930691 kA, both under the 210 kA rating (92.7 pct); hand values to 1e-9 | caught below |
| 10b 10.5 kV house bus | network 29.522136 + motors 10.486445 = 40.008580 kA <= 50 kA | UAT uk 5 pct gives 65.89 kA, caught |
| 10c diesel start sequence | Sk''gen = 6.6 / 0.16 = 41.25 MVA; dips 16.5, 16.5, 12.9, 11.7, 7.6 pct <= 20 | all 4.6 MW in one step dips 43.2 pct, caught |
| 11 external-pressure buckling | Zoelly p_cl 0.270963 MPa, x 0.2 / 2 = 0.027096 MPa >= 0.02 MPa (margin 1.35) | a 10 mm wall allows 0.0030 MPa, caught |
| 12 3-batch core decay heat | 3.7506, 1.0354, 0.46661 pct at 10 s, 1 h, 1 d (one cycle 3.7309, 1.0156, 0.4469): +0.5, +1.9, +4.4 pct; under the infinite-irradiation bound; 1 h boil-off 14.74 kg/s <= 36 (one cycle 14.45) | four batches at one third each rejected |

| discipline | before | after | what is still open |
|---|---|---|---|
| electrical | L3 | **L4** | IEC 60909 at 25 kV and 10.5 kV with breaker duty and the diesel start sequence. ALL inputs (grid 25 GVA, uk, xd'', ratings) are ASSUMED, so it shows the method closes, not that Angra 2's breakers are right. Open: peak factor kappa and the DC component, the 500 kV level, cable voltage drop, relay coordination |
| structural (containment) | L3 | **L3, one L4 item done** | buckling under 0.02 MPa external (ASSUMED differential, knock-down 0.2 ASSUMED, the SP-8032 PDF was not opened). Open: KTA 3401.2 load combinations, the equipment hatch and penetrations, the real wall thickness |
| nuclear (decay heat) | L3 | **L3+** | the 3-batch history done (it raises the 1 day value by 4.4 pct). ANS-5.1 itself is NOT done (no fission-product group data), and the batch scheme is ASSUMED |
| thermal-fluids, mechanical, civil / layout | unchanged | | as in section 2 |
Honest limit: Way-Wigner superposition is a closed form, not a validated decay-heat code; do not read 1.035 pct as a better 1 h number than 1.016, only as the direction and size of the history effect.
