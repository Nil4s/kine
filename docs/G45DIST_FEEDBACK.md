# G45DIST: the minimum distance between two solids (gap G45)

Branch `w4-g45dist` (from `origin/poser-ui-rounds`). Test: `tests/g45dist_test.gd`, registered in `tools/run_all.sh` as `g45dist:w`.

## What was built

- **KineCAD 6** (`native/cad/src/kine_cad.cpp`, built with `kine_workers/native_build.sh` from `native/cad`). Two new calls, both OCCT (LGPL 2.1 + exception, already linked; no new DLL):
  - `KCad.distance(a, b)` -> `{"ok", "d", "pa", "pb", "pa64", "pb64", "inner"}`.
    - `d` is in metres: 0 when the solids touch or overlap, and also when one is wholly inside the other.
    - `pa` / `pb` are the witness points as Vector3 (float32). `pa64` / `pb64` are the same points as PackedFloat64Array `[x, y, z]` in doubles: use those when precision matters.
    - It is `BRepExtrema_DistShapeShape`, run solid by solid so that its inside test applies.
    - On two faces, the witness points are then polished with a local Newton (`Extrema_GenLocateExtSS`). The extrema stops once the distance has converged, and on a sphere that left the points 3.7e-7 m off.
  - `KCad.bounds(id)`: the exact-geometry box `[xmin, ymin, zmin, xmax, ymax, zmax]` from `BRepBndLib::AddOptimal`, with no triangulation. `KCad.bounds_aabb(id)` gives it as a Godot AABB, grown by 1 um + 1e-6 of its size.
  - Each one is -1 / empty on an older DLL (`KCad.has_distance()`).
- **AssemblyStage.check** (`scripts/build/assembly_stage.gd`):
  - Touch is now one `distance` per solid pair: touching means d <= tol, in any direction. An overlap still counts as touching, and over Part.HIT_VOL it is still listed as a collision.
  - The collision pass skips the boolean of a pair farther apart than 1 um (GATE).
  - The box prefilter uses `KCad.bounds`.
  - `opts {"touch": "overlap"}` runs the whole old check (tessellated boxes + seven booleans) for the equality check.
  - The result gains `"touch"`, `"dist_calls"` and `"gated"`. `kernel_calls` counts booleans + distances.
- **Not changed:**
  - `assembly_motion.check_motion` needs the clash VOLUME. A distance gate there would also change g1motion / g2loop bars that count kernel calls exactly (g2loop g: 13 calls, 10 skipped).
  - `ch13` bar j reports overlap volumes.
  - `join_helper.contact` classifies the overlap.

## 1. Result

The bars were committed before the first run (25fa269e). The code was last changed in 1c558de3.

| bar | result | numbers |
|---|---|---|
| a cubes | ok | 1.000 mm apart: d = 0.000999999940 m. The error is 6.0e-11 m, all of it the float32 move (0.011 as float32). pa x = 0.005, pb x = 0.0059999999 |
| a spheres | ok | r 10 / 20 mm: d = 0.021419839466 m vs hand, error 0.0. Witness on sphere 1 at r = 0.010000000000, on the centre line to 0.0 m |
| a CONTROL | ok | cubes overlapping by 5 mm: d = 0. A 5 mm sphere inside a 15 mm cube (boundary gap 2.5 mm): d = 0, inner true |
| b fixtures | ok | 11 of 11 g33stage fixtures give the identical verdict on both paths: unsupported (id, stage), collisions (id, with, mm3 to the bit), support kind |
| b CH15 | ok | 53 of 53 supported, 33 collisions, identical to the old path. 3 parts name a different (equally touching) "on" part, because the box order changed |
| b dome first | ok | Shield dome unsupported at its stage, identical to the old path |
| b CONTROL | ok | tower vs roof-before-walls verdicts differ; every run took its own path |
| c speed | ok | CH15 check: old 180.3 s, new 7.6 s, **23.8x** (bound >= 5x). The new path ran first. Dome-first: 176.9 s -> 5.1 s |
| c CONTROL | **FAIL** | the new path asks 82 booleans vs the old 296 (3.6x, bound 5x) |
| d suite | ok | g33stage 28/0 in 86 s (was 436 s) |

Suites (one wtest call, final code): g45dist 8/1 (396 s; the old path's two CH15 runs take 357 s of it), g33stage 28/0 (86 s), ch15 44/0 (65 s), g1motion 22/0 (28 s), ch13 92/0 (19 s), scalefix 7/0 (43 s), easypart 73/0 (61 s), peasy3 23/0 (31 s), freestart 14/0 (25 s).

## 2. Engineering level reached

- **CAD kernel queries: L3.**
  - Distance and witness points match closed forms to 1e-11 m.
  - Containment is caught.
  - The verdict is identical to the old check on 13 assemblies, plant scale included.
- **Why not L4:** there is no signed distance (penetration depth), and no batch call (one call per solid pair from GDScript).

## 3. What Kine lacked (rows for the ledger)

| needed | exists today | workaround | cost | proposed feature |
|---|---|---|---|---|
| distance between two solids and an exact box | **this branch**: KCad.distance, KCad.bounds | none needed now | - | done |
| penetration depth (how far to move a part out of a clash) | overlap volume only | none | not attempted | a signed distance / minimum translation vector |
| an exact box for every Part (the Assembly's `built()` aabb, ch15's layout boxes) | tessellated meshes | the same as G33 used | each tessellation at plant scale takes 2-14 s | use KCad.bounds wherever a box only gates exact work |

## 4. What looks wrong

- Nothing is drawn by this lane. In the log, the 3 changed "on" parts on CH15 are valid supports, but the Stages panel would now name a different neighbour for them.

## 5. What was changed after seeing results (no bar or tolerance was changed)

- **First run: c failed at 1.0x (old 175 s, new 184 s).**
  - A probe (not committed) showed that 172 s of the check went on `_box_of` tessellations (2-14 s per big part).
  - The booleans took 0.6 s for 99 pairs, and the distances 1.6 s.
  - The premise from the G33 doc ("most of the time goes on booleans") was wrong.
  - **Fix:** `KCad.bounds` (exact box, no mesh) for the new path's prefilter. The old path keeps the tessellated box, so "old" is the PR #208 check.
- **Sphere witness bar failed:** the points were 3.7e-7 m off the centre line. **Fix:** the local Newton polish (see above). The bar message now prints the offset.
- **c CONTROL still fails.** I planted it on the same wrong premise (booleans 5x fewer). They went from 296 to 82: the 82 left are the touching / overlapping pairs, whose collision volume still needs the boolean. **The bar is left failing.** It is not reworded or loosened. The lead decides whether a control on boolean count is the right one.

## 6. What is left

- Report the gap of an unsupported part from `distance` ("the crane is 0.42 m short of the runway").
- check_motion could gate pairs with `distance` (it keeps the clash volume) once the call-count bars in g1motion / g2loop are re-cut.
- A batch `distance_many` in C++ if the GDScript loop over solid pairs ever matters.
