# G1MOTION: clash detection while a mechanism moves (gap G1, the minimum of G2)

Branch `w4-g1motion` (from `origin/poser-ui-rounds`). Test: `tests/g1motion_test.gd` (registered in `tools/run_all.sh` as `g1motion:w`).

## 1. What was built

- **Drives and links in the Assembly record** (`scripts/build/assembly_motion.gd`, class `AssemblyMotion`). Both lists are optional. A record without them loads, runs and saves exactly as before (bar g).
  - `"drives": [{"name", "part", "kind": "rotate" | "slide", "axis": [x,y,z], "origin": [mm], "range": [lo, hi]}]`. Rotate is in degrees about the axis through the origin (right-hand rule). Slide is in mm along the axis.
  - `"links": [{"drive", "part", "kind", "axis", "origin", "gain"}]`. The follower moves by gain x the drive's value. A gear pair uses gain = -z1/z2. A rack on a pinion uses gain = r_pitch x pi/180 mm per degree.
  - A moved part's place is `motion(value) * Assembly.xf_of(part)`. The record's `pos`/`rot` are never written.
- **`check_motion(asm, drive, steps, opts)`** takes steps + 1 samples (both ends included) and returns `{clashes: [{a, b, ida, idb, at, mm3, static}], by_pair, pairs, kernel_calls, skipped, values, moving, ms}`. How it works:
  - It poses the parts' exact solids: `Part.replay` with keep, then one `KCad.rotate` (axis-angle from the transform's quaternion) and one `KCad.translate`.
  - A pair whose boxes don't meet (each box grown 1 mm) is skipped. Every other pair goes to `KCad.overlap_volume`.
  - An overlap of `Part.HIT_VOL` (1 mm3) or less counts as contact, not a clash.
  - Two parts that both stay still are checked once.
  - Parts with several bodies sum the overlaps of each body pair.
- **The screen** (`scripts/build/assembly_motion_ui.gd`, class `AssemblyMotionUI`). It opens from the **Check motion** button next to the Assembly panel's parts list, or from the S box: **"Assembly: check motion"** (no key, so nothing is taken). The panel has:
  - a drive picker
  - **Add drive** for the selected part: Turn/Slide, axis, range, and the point the axis passes through
  - Steps, then **Run the sweep**
  - one red line per clashing pair: "Lid and Ceiling: from 70 deg, worst 184.0 mm3 at 70 deg"
  - red on every part that clashes
  - a slider that scrubs the drive on screen only, with a line such as "Lid at 70 deg: CLASH Lid x Ceiling" or "...: clear". The move gizmo hides while you scrub.
  - Close, which puts the parts back
- **Undo.** The Assembly screen had no undo, because the assembly isn't in the scene snapshot. It now has its own stack (`AssemblyUI.push_undo` / `undo_redo`). `main._mesh_undo` asks it first while the screen is on, and an empty stack falls through to the scene's undo as before. Adding a drive is one step. Running, scrubbing and closing change nothing.

## 2. Bars (every one has a planted control; committed in 6799465e before the first run; nothing was amended)

| bar | result | numbers |
|---|---|---|
| a hinge clears | ok | 80 mm lid, 0..70 deg, 11 samples: 0 clashes, 3 pairs, 11 kernel calls, 12 skipped, 35 ms |
| a CONTROL 5 mm longer | ok | clashes with the Ceiling only; first clash at 70 deg. By hand the onset is 64.73 deg, so this is within one 7-degree step. Worst overlap 184 mm3 |
| b link arithmetic | ok | rack 18.849555921539 mm = 12 pi/2 (1e-9); gear -45.000000000000 deg (1e-9). Posed (float32): rack (18.84956, 0, 0) mm, gear -45.000001 deg about its own axis |
| b CONTROL | ok | the frame (no link) stays put |
| c contact | ok | face to face, 5 steps: 0 clashes; 5 kernel calls, so every step went to the kernel |
| c CONTROL 0.5 mm in | ok | 200.0000 mm3 at 0 (hand 200), 100.0000 at -10 (hand 100), clash at all 5 steps |
| d static once | ok | 50 kernel calls with no prefilter (hand 6 + 44); with the prefilter, 0 calls + 50 skipped |
| d CONTROL | ok | a gain-0 link makes one more part moving: 80 calls (hand 3 + 7 x 11) |
| e speed | ok | 7 parts x 36 steps: 106 ms (< 5000), 21 pairs, 66 kernel calls, 171 skipped |
| e CONTROL | ok | without the prefilter: 237 calls, 167 ms, the same 10 clashes |
| f UI | ok (6 bars) | the S box finds the command first and Enter opens the panel; Add drive is 1 undo step; Run lists 1 pair; lid and ceiling are red, base is not; slider at 35.000 deg shows "clear", at 70.000 deg shows "CLASH", and the record's rot stays [0,0,0]; Ctrl+Z gives back the identical record with no red and the lid at 0 deg |
| g old record | ok | `tests/assets/g1motion/old_assembly.json` was written by the pre-drive code (tests/assets had no assembly, so one was made). It loads, opens Check motion, and saves back equal with keys sorted (4229 -> 4245 bytes: only int -> float formatting) |
| g CONTROL | ok | the same record saved with a drive does not compare equal |

Suites (wtest.sh, one call): g1motion 22/0, easypart 73/0, peasy3 23/0, freestart 14/0, and every assembly suite: c15 28/0, ch13 92/0, ch14 60/0, ch15 44/0, s213 27/0, s250 192/0, scalefix 7/0.

## 3. What is left

- **G2, the rest:** closed loops. A slider-crank or four-bar needs a loop solver. A link here is open: one value in, one pose out. The CH13 engine can't be driven from this record yet; it still needs `ch13_parts.pose_of()`. Also missing: joints declared between two parts (revolute or prismatic mates that infer the axis from geometry), and limits that stop a drag. A follower that rides on another follower (a chain of links) isn't composed either. Each link is relative to its drive only.
- **G7:** drives aren't keyframed on the Assembly timeline, and no build sequence is recorded. The slider is a scrub, not an animation.
- **Sampling:** a clash that starts and ends between two samples is missed. The first clash is reported at the first sample past the onset (70 deg against 64.73). A continuous check (bisection on the first clashing interval, as ch13's crown_gap does) would close this.
- **Add drive:** the axis can only be X, Y or Z. Links have no screen yet: they are written in the record or from a script.

## 4. What looks wrong in the screenshots (C:/Temp/claude/g1motion/swept.png, undone.png, LOOKED at)

- swept.png: the lid visibly passes into the ceiling at 70 deg. Both are red and the base is grey. The panel text matches.
- The red overlay is a light pink over the lit parts, not a strong red. The clash volume itself isn't shown (no intersection solid is drawn).
- The bottom status strip draws over the Assembly panel's Export row while a long message is shown. That's the panel layout from before this branch, but this branch's message is long enough to show it.
- undone.png: the part labels "Base" and "Lid" overlap at the hinge (the overlay puts names at each box's corner).
