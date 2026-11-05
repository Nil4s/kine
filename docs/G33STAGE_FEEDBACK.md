# G33STAGE: build stages in an Assembly (gap G33)

Branch `w4-g33stage` (from `origin/poser-ui-rounds`). Test: `tests/g33stage_test.gd`, registered in `tools/run_all.sh` as `g33stage:w`.

## What was built

- **Stages in the Assembly record** (`scripts/build/assembly_stage.gd`, class `AssemblyStage`). Two more optional entries; a record without them loads, checks and saves exactly as before (bar g).
  - `"stages": [{"name", "parts": [ids], "dur": s}]` in build order. A part in no stage is there from the start (the site, the bench) and is never checked.
  - `"stage_opts": {"tol": mm (0.1), "ground": mm (0; null = no ground), "drop": mm (0 = parts just appear), "fps"}`.
  - A part may carry `"hang": [ids]`: an attachment the model does not draw (brackets, a crane hook). It counts only when the part touches nothing, and the result lists it as held "by hang", so it is never hidden.
- **The support check** `AssemblyStage.check(asm)`:
  - A part added at stage k must touch the ground or a part from stages <= k. Parts in the same stage hold each other only through a chain that reaches built parts or the ground (a fixed point inside the stage).
  - Touch is exact and uses the posed solids (Part.replay keep, AssemblyMotion.place). Two parts touch when they overlap, or when one moved by tol along any of the six axis directions overlaps the other more than before. A face within tol along an axis counts. A slanted face counts from tol / sqrt(3).
  - The ground is a solid slab under the plane.
  - A box prefilter skips far pairs: a coarse tessellation of each posed solid, grown by its chord error and by tol.
  - Each new part is also checked against everything built before it and the parts listed before it in its stage. An overlap over Part.HIT_VOL (1 mm3) is listed as a collision, in mm3.
  - The likeliest support (the part whose top is nearest this part's bottom) is tried first. The rest overlaps are shared between the collision pass and the touch test.
- **Time.** Stage k starts at the sum of the earlier durations. `pose_at(asm, t)` gives the visible parts and the moves: with `drop`, each part slides down into place over its stage (smooth ease). An AssemblyAnim animation (#205) is played first and the drop goes on top.
- **Video.**
  - `AssemblyStage.video(host, asm, opts)` films the build through AssemblyRender, with all of its options (camera, `cut`, `only`, sheet, mp4).
  - Frames are at (k + 1) / fps for k = 0 .. fps x total - 1, so the last frame is the finished build.
  - AssemblyRender gained `"steps"` (frames posed by the caller, each with its own visible set) and `"fps"`. Without them it is unchanged (g7time 27/0).
- **The Stages panel** (`scripts/build/assembly_stage_ui.gd`) opens from a **Stages** button in the Assembly panel's Parts row, next to Check motion and BOM. No row was added to Easy Part.
  - The list of stages; Name and seconds fields.
  - New stage (from the selected part), + Part, - Part, Up, Down, Delete: each is one undo step.
  - Check lists the problems and turns the flagged parts red.
  - A time slider and Play show the build.
  - Video (1280 x 720, the current view) with a Cut toggle that cuts away the half toward the camera.
  - Removing a part from the assembly also takes it out of its stage.

## 1. Result

Bars were committed before the first run (fa94889a). First run: 27 ok, 1 fail. The fail was bar d (section 5). Second run: 28 ok, 0 fail.

| bar | result | numbers |
|---|---|---|
| a tower | ok | base / walls / roof: 4 of 4 placed, no problem (12 kernel calls, 30 ms) |
| a same stage | ok | the roof listed first in the walls' stage is held up through the walls |
| a CONTROL roof before walls | ok | unsupported: Roof at stage index 1 "Roof", and nothing else |
| a CONTROL floating pair | ok | two stacked blocks 1 mm over the base: both unsupported |
| b float | ok | 1 mm above the base: unsupported (tol 0.1 mm). 0.05 mm above: supported |
| b side | ok | on wall B's side: 0.05 mm away supported, 1 mm away unsupported |
| c overlap | ok | cube sunk 2 mm: Block x Base 799.999565 mm3 vs hand 800 (rel 5.4e-7, float32 poses), still supported |
| c CONTROL | ok | resting (0 mm) and sunk 0.001 mm (0.4 mm3): no collision |
| d CH15 | ok | 53 of 53 supported, the same as ch15 bar 7 (53 of 53): 16 by the ground, 36 by contact, 1 by hang (the crane runway); 177 s |
| d CONTROL dome first | ok | unsupported: Shield dome at its stage |
| e frames | ok | 12 = 4 fps x 3 s; sheet + mp4 |
| e schedule | ok | blue in all 12 frames (4985-7022 px); green 0 in frames 0-2, then 5389-8123 px; red 0 in frames 0-6, then 3564-4777 px |
| e drop | ok | the roof at 2.5 s is 29.999999329 mm up (hand 30); at 3 s 0 |
| e section | ok | the cut at z = 50 mm shows 5419 cap px; the closed tower 0 |
| e CONTROL frozen | ok | 12 frames, 0 px differ; the real schedule's frames 2 / 3 differ in 11923 px |
| f UI | ok | 3 New stage + one + Part make 3 stages in 4 undo steps. Down moves the roof stage last (5 steps), rename (6), slider at 0.5 s shows only the base, Play ran 298 frames to 3.00 s with everything shown, delete (7). 7 x Ctrl+Z gives the identical record |
| f CONTROL | ok | Check with the roof before the walls: "Roof (stage 2, Stage 2): touches no part built by then nor the ground (tol 0.1 mm)", and only the roof is coloured. Before the undo the record differs |
| g old | ok | old_assembly, drive_199, joint_204, anim_205 and bom_206 (written by the #206 code, 92702e92) each open in the screen; with Stages opened, checked and closed, each saves back equal |
| g CONTROL | ok | the #206 record with one stage does not compare equal |

**CH15 reproduction (d):** the plant's own records go in unchanged:
- its stage names become ids;
- its "hang" supports become part "hang" ids;
- tol 20 mm (ch15 TOL).

The verdict is 53/53, and the dome-first order is caught. The check also lists **33 collisions** that ch15 never looked at. Its pipes are drawn centre to centre, so they run into what they join: hot leg 1 x the vessel 55.4 m3, x steam generator 1 1.2 m3, x internal concrete 1.7 m3, and so on. Bar 6 checked only the buildings and the equipment, not the pipes.

Suites (one wtest call, final code): g33stage 28/0, ch15 44/0, g7time 27/0, g8bom 19/0, g2loop 24/0, g1motion 22/0, easypart 73/0, peasy3 23/0, freestart 14/0.

## 2. Engineering level reached

- **Construction sequencing: L3.** Support is decided on the exact solids, with a stated tolerance, and checked against hand cases with planted controls:
  - gap vs touch, below and beside;
  - an overlap volume vs its hand value to 5e-7.
  - It reproduces CH15's verdict on 53 plant-scale parts and found a modelling error that ch15's box check let through.
- **Why not L4:** "touching" is not "supported":
  - There is no load path: a part touching a wall's side is held, with no check of friction, a fixing or a moment.
  - No centre-of-gravity or tip-over check per stage.
  - No temporary works (props, a crane's reach and capacity).
  - No real erection schedule (durations are typed in, not computed).
  - "hang" is a declaration that nothing checks.

## 3. What Kine lacked (rows for the ledger)

| needed | exists today | workaround | cost | proposed feature |
|---|---|---|---|---|
| stages, a support check and a staged video | **this branch**: AssemblyStage + Stages panel | none needed now | CH15's records convert in 17 lines (test `ch15_staged`) | done |
| distance between two solids (to give the gap of an unsupported part, and a touch test with one call) | nothing in KCad (overlap_volume only) | six shifted overlaps per pair | up to 7 booleans per pair; CH15's 53 parts take 177 s | KCad.distance(a, b) (OCCT BRepExtrema_DistShapeShape) |
| a stability check per stage (centre of gravity over the support, tip-over) | KCad.mass_properties gives the centre | none | not attempted | per stage: the built parts' centre of gravity vs the convex hull of their ground contacts |
| the parts that hold up a stage drawn in the view (what rests on what) | the check's "support" map (id -> on) | none | the user reads text | lines from each part to its support, drawn in the Stages panel's view |

## 4. What looks wrong (C:/Temp/claude/g33stage/stages_check.png, e_stages/sheet.png, e_cut/frame_0000.png, LOOKED at under new names)

- **stages_check.png:**
  - The Stages panel sits on the left at 1280 x 720 and ends well above the bottom bar. It shows the 3 rows ("3. Stage 3: Wall A, Wall B (1 s)" picked), the Name / 1 s fields, the New stage / + Part / - Part and Up / Down (greyed: last) / Delete rows, Play with the slider at 3.0 s, Check / Video / Cut / Close, and the problem line naming the roof.
  - The Parts row in the Assembly panel ("Parts, Check motion, BOM, Stages") fits.
  - **Wrong:**
    - The view is not reframed when the panel opens, so the tower sits half behind it (Check motion moves the view, Stages does not).
    - The red overlay on the roof cannot be told apart from the roof's own red in this test scene. The bar checks the overlay material instead.
    - The status line is repeated at the bottom left (the app's own line, as with BOM).
- **e_stages/sheet.png:**
  - The base, then the walls, then the roof come in at the right frames.
  - Each part drops in over its stage: the base too, which moves in frames 0-2.
  - The final frame is the closed tower.
  - The camera frames the whole drop path, so the finished tower fills only part of the tile.
- **e_cut/frame_0000.png:** the cut through z = 50 mm shows each part's cap in its own colour (base orange, walls purple / teal, roof pink), and the inside of the box is open to view. It looks right.

## 5. What was changed after seeing results (no bar or tolerance was changed)

- **d failed on the first run:** 52 of 53, with the **Polar crane** unsupported. I had seen this coming while reading the geometry before the run:
  - CH15's crane bridge was 50 m (x -25..25), and its ring runway's inner radius is 25.5 m, so the bridge stood 0.42 m clear of the runway at each end.
  - ch15 bar 7 passed it because its check compares boxes (bottom = runway top, footprints overlap).
  - CH15_REFERENCE section 6 gives the crane a 52 m span.
  - **Model change** (scripts/build/ch15_parts.gd, ch15_draw.gd): the bridge is 52 m, as the reference says, and 2 m deep instead of 2.5. The depth change keeps its top corners (r 26.08 m) inside the steel sphere (inner r 26.12 m at +32 m). The trolley moved down with it.
  - After the change: g33stage d 53/53, and ch15 44/0 with bar 7 still 53/53.
- **The bar c message** used `%e`, which GDScript does not format: the line printed unformatted (the check itself was right). It now prints with `str()`.
- **Speed:** the first run took 180 s for CH15. The check now shares rest overlaps between the collision pass and the touch test, and tries the likeliest support first: 177 s. Most of the time goes on booleans against the 28 m sphere shells, whose boxes hold every part inside them.

## 6. What is left

- **KCad.distance:** the check could then give the gap of an unsupported part ("the crane is 0.42 m short of the runway") and touch in one call, instead of seven booleans.
- **Stability per stage** (section 2) and load paths.
- **CH15's pipes** run into the vessel, the SGs and the pumps (33 collisions). They should end at the nozzles. That is ch15's model; I did not change it.
- **The Stages panel** should reframe the view like Check motion does. A part's flag colour should be one that the part's own colours never use.
- **Plant scale in the UI:** the check of a 53-part plant takes about 3 minutes and blocks the screen while it runs.
- **The staged video** could highlight each stage's new parts in a flat colour, as ch15_scene.show_stage does. Today they show their own looks.
