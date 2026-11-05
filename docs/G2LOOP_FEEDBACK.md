# G2LOOP: closed-loop kinematic joints in an Assembly (gap G2)

Branch `w4-g2loop` (from `origin/poser-ui-rounds`). Test: `tests/g2loop_test.gd`, registered in `tools/run_all.sh` as `g2loop:w`.

## What was built

- **Joints in the Assembly record** (`scripts/build/assembly_loop.gd`, class `AssemblyLoop`). This adds one optional list next to #199's `drives` and `links`. A record without it loads, runs and saves exactly as before (bar g).
  - Format: `"joints": [{"name", "kind": "revolute" | "slider" | "fixed", "a": part id, "b": part id | "ground", "axis" (a's frame), "origin" (mm, a's frame), "origin_b" (mm, b's frame or the world; optional)}]`.
  - If `origin_b` is left out, the joint sits where the record's poses put it.
- **The loop solver.** The loops are planar: every revolute axis must be parallel, and every slider axis square to them. Anything else is refused with a message.
  - **Known parts:** the driven part and its links. They move as #199 moves them.
  - **Free parts:** every other part named in a joint. Each has three unknowns (x, y, phi).
  - **Method:** Newton-Raphson on the constraint residuals (mm; angles scaled by a length), with an analytic Jacobian and full-pivot elimination. Each step starts from the last step's pose. A step is halved when Newton fails or the sign of det J (the assembly mode) flips.
  - **Locks:** a step that still fails below 1e-9 of a drive unit is reported as a **lock**. The report gives the Jacobian's rank there and the steps with no pose. The solver does not go through a lock.
  - **Re-entry:** after a lock, later values are solved fresh from the record along the shorter path. A lone turn wraps to -180..180. The start of the reachable range is found by stepping back from the first value that solves.
  - **Precision:** the solver works in doubles throughout. `AssemblyLoop.world_mm` gives a solved point in doubles.
- **`check_motion` follows the loop when a record has joints.**
  - It runs one `AssemblyLoop.sweep` and checks each step's poses. A step with no pose is skipped and listed in `res.loop.unsolved` / `locks`.
  - The solids are placed from the doubles (`AssemblyMotion.place_state`: the record's Euler turns, then phi, then one move computed in doubles). The volumes match bar j's own placement to 6e-10 mm3.
  - New option `hit_mm3` sets the clash threshold.
- **The Check motion panel** has a joint row: Pin (turns) / Slide / Weld, from the selected part to another part or Ground, at the axis and point typed above. Adding a joint is one undo step.
  - With joints, the scrub poses every part through the solver (cached per value).
  - The line under the slider says "NOT SOLVED: the joints leave 2 degrees of freedom free..." when the joints don't settle the pose.
  - Run lists locks and steps with no pose in orange.
- **The CH13 engine drives itself:** `ch13_parts.loop_assembly()` = `assembly(0)` plus a "Crank" drive (about -z, so the value is pose_of's theta) plus 5 joints: crank in the case, big end, small end, pin welded in the piston, piston sliding in the bore. That gives 9 unknowns and 9 equations. `with_loop(asm)` adds the same drive and joints to any engine assembly built from the same constants. Bar d uses it on the old geometry.

## 1. Result

Bars were committed before the first run (c8d93895). First run: 19 ok, 5 fail (section 5).

| bar | result | numbers |
|---|---|---|
| a slider-crank r 25, l 90 | ok | piston vs r cos t + sqrt(l^2 - (r sin t)^2) at 36 angles: worst 1.4e-12 mm (bar 1e-6). Doubles, so the G4 float32 limit doesn't apply. The posed Transform3D is within 5.1e-6 mm (G4 bar 1e-4). 206 iterations, 9 ms |
| a CONTROL r and l swapped | ok | crank 90, rod 25: locks at 16.128 and 343.872 deg (hand asin(25/90) = 16.128), 33 of 36 steps with no pose |
| b four-bar 100/40/120/80 (Grashof crank-rocker) | ok | rocker vs Freudenstein, branch +1 at every angle: worst 1.5e-12 rad (bar 1e-6). 0 locks, 221 iterations, 9 ms |
| b CONTROL non-Grashof 100/70/120/80 | ok | locks at 161.8051 and 198.1949 deg. Hand: 180 -+ acos((70^2 + 100^2 - 40^2)/(2 x 70 x 100)) = 161.8051 / 198.1949. Jacobian rank 5 of 6 at both. No pose at 170, 180, 190. 2206 iterations, 149 ms |
| c CH13 engine from its record | ok | vs pose_of() for 7 parts x 36 angles x 4 points: worst 6.3e-11 mm (piston at 100 deg; bar 1e-6). 202 iterations, 13 ms |
| c CONTROL | ok | pose_of with the rod unturned is 26.1 mm from the solved poses |
| d clashes, current geometry | ok | 36 angles through the joints: 0 clashes, the same as bar j's second run. 21 pairs, 364 kernel calls, 287 skipped, 1.9 s |
| d old geometry (9a9522ca) | ok | at 0.001 mm3: 48 (pair, angle) overlaps, the same 48 that bar j's own pose_of loop finds. Worst volume difference 5.7e-10 mm3 |
| d the faults | ok | rod x piston at 36/36 angles, worst 3752.8 mm3 (CH13 doc: 3.7 cm3). Rod x cylinder at 50-80 and 280-310 deg, worst 9.686 mm3 (doc: 9.7, "50-80"). Rod x crankcase at 60-70 and 290-300 deg, worst 0.046 mm3 (doc: 0.05). At the default 1 mm3 the graze is contact, so only 2 pairs are listed. Bar j's 4th fault (crown gap 5.10 mm, not 0.50) is a gap, not an overlap, so no sweep can list it. Count: 3 overlaps, not 4. The doc said "50-80"; the sweep also finds the mirror angles |
| d CONTROL rod +2 mm | ok | piston x head at 0 deg: 579.774 mm3 (bar j: 580) |
| e convergence, 360 steps of 1 deg | ok | 720 iterations: mean 1.99, max 2 (bound mean 4, max 5). 57 ms (bound 1000). Smallest pivot ratio 0.0043 (rank tolerance 0.001) |
| e CONTROL cold | ok | each step from the zero guess: mean 2.93, max 3, 68 ms |
| f UI (4 bars + control) | ok | S box opens Check motion on "Crank". With 4 joints the scrub says "NOT SOLVED: ... 2 degrees of freedom free" and the piston stays at 66.7 mm (control). Add joint (Piston, Slide, Y, Ground) is 1 undo step. Scrub at 90 / 180 deg: piston at 43.2755 / 25.3 mm (closed form x - 34; worst 7.6e-6 mm), rod turn worst 4.8e-7 deg. Run: no clash, no lock. Ctrl+Z gives the identical record, 4 joints, piston back at 66.7 |
| g old records | ok | old_assembly.json saves back equal. drive_199.json was written by the #199 code before this branch: the same line "Lid and Ceiling: from 70 deg, worst 184.0 mm3 at 70 deg", 13 kernel calls, 10 skipped, no loop path, and it saves back equal |
| g CONTROL | ok | the #199 record with a joint doesn't compare equal |

Suites (one wtest call, after the fixes): g2loop 24/0, g1motion 22/0, ch13 92/0, ch14 60/0, ch15 44/0, scalefix 7/0, easypart 73/0, peasy3 23/0, freestart 14/0.

**Timing:** GDScript only, no C++ (so no twin is needed). The engine takes 0.16 ms per 1-degree step, and a 36-step sweep takes 13 ms. Most of check_motion's time is the 364 kernel booleans (1.9 s), not the solver.

## 2. Engineering level reached

- **Mechanical kinematics: L3.** The position analysis of a slider-crank and a four-bar is checked against two closed forms to 1e-12. Grashof's condition shows up as the lock positions, matching the hand formula to 1e-4 deg. A planted control fails in each case.
- **Why not L4:** there is no velocity or acceleration analysis yet. That would be the same Jacobian, J qdot = -dPhi/dv, and is about 20 lines away. There are no joint clearances or tolerances in the joints (G3), no transmission-angle check against a design rule (40-140 deg), no spatial loops, and no force analysis.

## 3. What Kine lacked (rows for the ledger)

| needed | exists today | workaround | cost | proposed feature |
|---|---|---|---|---|
| a joint UI that infers the axis from geometry (pick a cylindrical face) | typed point + X/Y/Z axis only | typed the piston's place by hand | under a minute per joint for a user who knows the numbers; hard otherwise | pick a face or edge: a revolute takes its axis, a slider its direction (mates) |
| velocities and accelerations of a loop (piston speed, rod angular velocity) | positions only | none | could not do it in the Assembly | J qdot = -dPhi/dv on the solved pose; a speed readout and a plot along the sweep |
| gears, racks, cams and pin-in-slot as JOINTS in a loop | #199 gear/rack LINKS (open: one value in, one pose out) | none | could not do it | gear (a phi_a + b phi_b = 0) and pin-slot residuals in the same solver |
| spatial loops (non-parallel axes: a universal joint, a Bennett linkage) | refused with a message | none | could not do it | 6-unknown parts, spherical / cylindrical joints, a rank-revealing least-squares step |
| continuous clash onset (between samples) | sampled sweep only (G1) | none | the first clash is reported up to one step late | bisection on the first clashing interval (as ch13's crown_gap) |
| the drive on the timeline (G7) | scrub only | none | no animation | keyframe the drive value; the loop solver poses each frame |

## 4. What looks wrong (C:/Temp/claude/g2loop/scrub90.png, undone.png, LOOKED at)

- **scrub90.png (crank at 90 deg):** the rod leans and the piston has dropped about 23 mm from TDC. Its crown is visibly below the head, and its frame box moved down with it. The crank web is turned and the rod's big end sits on it. The panel reads "Crank at 90 deg: clear" and "No clash over the whole range". This looks right.
- **undone.png:** after Ctrl+Z the piston is back at TDC and the panel says "4 joints" and "Crank at 0 deg: NOT SOLVED: the joints leave 2 degrees of freedom free". That is correct: the slide joint is gone.
- **The labels "Piston", "Rod" and "Pin" overlap** at the top of the piston. The overlay puts names at box corners, the same issue as in G1. The crankcase is transparent, so the rod is hard to read inside it.
- **The axis picker is shared:** the drive's "Turn (deg) / about Y" row also sets the joint's axis, so a Slide joint reads "about Y". The joint row should show its own "along Y" label.
- **The engine's assembly mode isn't shown on screen.** The result has `mode` (+1/-1), but the panel doesn't say "open / crossed".

## 5. What was changed after seeing results (no bar or tolerance was changed)

- **"String formatting error" flood:** GDScript has no `%g`. Three solver messages and the e bar's message were moved to `String.num_scientific`. This was text only.
- **d's volume difference 0.092 mm3 on the first run (bar 1e-3 + 1e-6 rel):** the cause was G4. check_motion placed the loop's solids through the float32 Transform3D (Basis to quaternion to axis-angle). They are now placed from the solver's doubles (`place_state`), the same way bar j does. The difference fell to 5.7e-10 mm3. This was a code change; the bar is unchanged.
- **f's first run clicked `asm_row_3` while it was scrolled out of the 7-part list,** so the click missed and the joint went on the Crankcase. The test now scrolls the row into view (`ensure_control_visible`) before clicking. This was a procedure fix.
- **g's first run saved the old record with a name.** `Assembly.save(asm, nm)` renames the record, so the comparison was against a different record. It now saves without a name, as g1motion does. This was a procedure fix.
- **The UI's joint point is now parsed into doubles,** not a Vector3, so a typed 66.7 stays 66.7 in the joint (it was 66.69999695). This is behaviour the bars don't measure.

## 6. What is left

- **Gears, racks and cams as loop joints:** #199 links are still open chains. **Velocities and accelerations.** **Spatial loops.** **Joint limits** that stop a drag in the Move gizmo: the joints only act in Check motion, not while dragging a part.
- **G7:** keyframe the drive on the Assembly timeline and render the loop's motion. The solver is ready: `AssemblyLoop.solve(asm, drive, v)` is stateless.
- **G3:** fits on the joints, so clearance is part of the kinematic chain.
- **A drive on a joint** (for example, drive the piston and let the crank follow). Today a drive moves a part. A piston-driven slider-crank should show the TDC and BDC dead points as locks, which the solver already detects.
