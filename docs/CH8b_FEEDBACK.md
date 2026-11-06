# CH8b feedback (liquids, second lane): PARKED, 28 ok / 3 fail after Nick's 11-04 volume amendment (was 28 / 5)

Branch `w4-ch8b`. Last full run was on commit 91681812, with native built by `native_build.sh`. Suites: ch8 28 ok / 5 fail; easypart 73/0, peasy3 23/0, freestart 14/0.
Merged origin/poser-ui-rounds (014dfbd4) with no conflicts. Every new bar was committed before its first run: bdfd9d99 holds h, h2, b2, a2, d2 and r, and 53101dd0 holds b4. No existing threshold was changed.

## 1. Result

| Bar | CH8 parked | CH8b now | Verdict |
|---|---|---|---|
| (a) still-water vmax < 1e-3 m/s | 1.21e-3 | 2.9e-9 | ok |
| (a2) the same, < 1e-4 (new) | - | 2.9e-9 | ok |
| (a) bottom pressure within 2 % | 0.20 % | 0.00 % | ok |
| (b) V/V0 = sum min(n,8)/N >= 0.98 | 0.927 | 0.9445 | retired 11-04 (info) |
| (b2) peak cell count <= 12 (new) | - | 15 | retired 11-04 (info) |
| (b4) VOLUME BAR: smoothed volume vs seeded count >= 0.98 | - | 0.9838 | ok (5 %-deleted control 0.9449 fails) |
| (c) M&M n^2=2 within 10 %, remembered table | 16.6 % | 24.3 % | FAIL |
| (h2) remembered table = paper Table 2 (new) | - | 7/7 rows | ok |
| (h) M&M n^2=2 within 10 %, VERIFIED table, 14 points (new) | - | 24.4 % | FAIL |
| (c2) square-column front speed in 1.48..1.74 sqrt(gH) | 1.740058 | 1.708065 | ok |
| (c) Ritter bound | ok | ok | ok |
| (d) C++ == GDScript; (d2) the same with the projection active | 0 | 0 / 0 | ok |
| (e) 0 in walls, 0 in mesh, no leak, spills >= 2 % | ok | ok (spill 34.6 %) | ok |
| (e) fills >= 85 % | 79 % | 78 % | FAIL |
| (f) >= 200k particles at >= 10 steps/s | 194,672 | 810,448 at 10.35 steps/s (417,600 at 21.6) | ok |
| (r) surface_aniso volume within 10 % (new) | - | 96.3 % | ok |
| every (g) control | ok | all 14 fail as they must | ok |

### What changed (code)
- **Inherited from 6498439e (previous CH8b agent):**
  - pooled threads with a block-MIC(0) PCG
  - implicit density projection on positions (Kugelstadt et al. 2019)
  - velocity extrapolation into the air (Bridson). This is what fixed (a): air faces held -g dt.
  - anisotropic surface (Yu & Turk 2013)
  - all of it ported to the twin
- **c884c98b: Taubin λ|μ smoothing of the kernel centres** (Taubin 1995, k_PB = 0.1). The λ step alone shrank the surface to 86.7 % of the particle volume; with μ it is 96.3 %. `tools/ch8_video.gd` now uses `surface_aniso`.
- **91681812: free-slip walls for the B-spline.** Faces with solid on both sides (inside a wall) were fixed at 0, so every particle next to a wall read zeros one cell into it. That acted as a numerical no-slip.
  - In the harness, about 1000 particles stayed stuck on the front and back walls, falling at 0.14 m/s at T = 4. The render showed this as a ghost of the column hanging in the air, plus drops stuck to the outside of the mug.
  - Those faces are now extrapolated. Only faces with solid on exactly one side stay fixed at 0.
  - After the fix: no particles hang, c2 went from 1.416 to 1.708 (inside the span), and the twin still matches exactly.

## 2. Engineering level: fluids/CFD L3

- **Evidence:**
  - closed-form checks pass: hydrostatic pressure (0.00 %), the Ritter bound, a still tank at 3e-9 m/s
  - two independent implementations agree to 0
  - planted controls on every bar
  - verified experimental data (Martin & Moyce Table 2, read from the paper scan), with a cited span for c2
  - a resolution study (below)
- **Not L4:**
  - no grid-convergence-based uncertainty
  - single-phase only (no air)
  - walls are staircase voxels
  - a first-order free-surface boundary
  - no validation against pressure-probe data (e.g. Lobovsky 2014)

## 3. What Kine lacked

| Needed | Exists today | Workaround | Cost | Proposed feature |
|---|---|---|---|---|
| sub-cell solid walls (cut cells / fractional face areas, Batty et al. 2007) and SDF push-out | `add_solid_mesh` marks every cell a triangle touches (conservative) | none | could not do it: (e) is capped by geometry (below) | variational cut-cell pressure solve with mesh SDF |
| second-order free-surface boundary (ghost fluid, Enright/Gibou) | Dirichlet p = 0 at air cell centres | none | could not do it in budget | GFM diagonal terms from a particle level set |
| air phase / two-phase flow | nothing | none | unknown share of the (c)/(h) gap | optional air drag or two-phase level set |
| a fluid tool in the app (emitters, solid from any Part, bake, playback) | only `scripts/fluid.gd`, `fluid_scenes.gd` and tests; no UI | the test scripts | the whole user path is missing | a Fluid panel: domain box, emitter, Part-as-collider, bake to cache |
| water render material (refraction, thickness, foam/spray) | `shaders/water_refract.gdshader` | used as is | surface reads opaque and pitted | screen-space fluid or a level-set mesh with thickness-based absorption |
| GPU compute for p2g/PCG | nothing in the fluid code (RenderingDevice is only used in `scripts/quality.gd`) | CPU threads | fine at 800k; 1M+ needs GPU | RenderingDevice compute for p2g/g2p |
| a lone-runtime harness for native classes | none in the repo (the lane used `C:/Temp/ch8b_h` with a godot shim) | about 150 lines of shim plus a harness | minutes per experiment instead of a Godot run | check in `native/tests/` with a shim so solver studies run without Godot |

## 4. What looks wrong (stills in `C:/Users/Nick/tools/kine_workers/out/ch8b/final/`: dam f0020, f0032; mug f0069)

- The water now reads as one connected body; the thin shells and lace are gone. But the surface is pitted and crumpled, like crushed ice or wet gravel, not a glassy liquid. The material renders mostly opaque.
- The dam break shape is right: a collapse, a surge, then run-up on the far wall with a plunging lip at the top (f0032). The ghost column that used to hang in the air (before 91681812) is gone.
- **Mug:**
  - the water in the cup has a rough top
  - a few drops are left on the outside of the cup
  - spilled water spreads to the edge of the invisible simulation box and stops, so the puddle is a square
  - no splash sheet or spray can be seen

## 5. What was amended after seeing results

- **(b), (b2) retired, AMENDED per Nick 11-04** (commit 05e45122, committed before its run): "the per-cell count reads 0.926 on a rigidly moved block, it measures particle spacing not volume".
  - Both are now printed as information only. Last run: (b) 0.9445, (b2) peak 15.
  - The volume bars are now (b4), the smoothed-density volume, at >= 0.98, and (r), the render-surface volume, within 10 %.
  - (b4) is now measured against the particle count seeded at t = 0, so a lost particle counts as lost volume.
  - New planted control: deleting 5 % of the dam-break particles makes (b4) read 0.9449, which fails as it must.
  - Last run: (b4) worst 0.9838 ok, (r) 96.3 % ok.
  - With the amendment, ch8 is at 28 ok / 3 fail: (c), (h) and (e).
- **(e): one pass offered on sub-cell walls; not attempted, because it does not fit one pass.**
  - Batty-style face weights only help if the cut cells also become fluid. That needs four things, each in both C++ and the GDScript twin:
    - a mesh signed-distance field
    - per-face open fractions
    - weighted off-diagonals in the block-MIC preconditioner, the matvec, the pressure gradient and the density projection
    - pushing particles out by the signed-distance field, to keep the "0 particles inside the mesh" bar
  - (e) stays red at 78 %; the geometric cap of 86-89 % is shown below.
- **(h2):** compared in whole hundredths instead of floats. 2.00 - 1.98 = 0.020000000000000018 > 0.02 had failed a row the bar's own text accepts. Same tolerance, reason in the test. No other bar was touched.

## Why the 5 reds stay red (precise park note)

- **(b), (b2): the statistic counts particles per cell, not volume.**
  - The (b4) control shows a block moved rigidly with no gravity (nothing compressed) reads 0.926 on (b), against 0.992 on the smooth measure.
  - Repeating the density projection does not get past it. In the harness, 8 passes on one state reach 0.968, and 2-3 passes per step or linear displacement interpolation change (b) by less than 0.001.
  - (b) also drops as the grid gets finer: 0.941 at res 40.
  - Peaks of 13-15 are the tail of the random per-cell counts. They appear at T = 0.25 as well as at the wall hit.
  - Passing would need particles kept in step with the cell lattice (sorted into the cells), which is not a fluid property. The lead decides; the bars are untouched.
- **(c), (h): the simulation leads M&M n^2=2 by a nearly constant ΔZ ≈ 0.3, set up between T = 0.41 and 0.84.**
  - After that the slopes are similar.
  - Refining the grid makes it worse (res 20 → 40: 19.5 % → 23.6 % before the wall fix). The converged single-phase free-slip answer is further from the data, so this is not a discretisation bug.
  - A half-density front (cell count >= 4) instead of the furthest particle gives the same numbers, so the gap does not come from the front metric.
  - Possible causes, not tested: gate opening time (a time shift of about 0.2-0.3 in T would line them up, but a fitted shift is not allowed), air drag, and bed friction with no cited coefficient.
  - c2 (n^2=1, cited span) passes with the same solver.
- **(e): the voxelised cup can hold at most about 86-89 % of the true interior.**
  - That figure comes from a geometric count of free cells for R_in 36 mm, a 4 mm floor and h = 3 mm, over three grid phases: 0.859, 0.879 and 0.890.
  - 85 % would need the cup brim-full and still after 0.8 s of sloshing.
  - The fix is the cut-cell wall from gap row 1. The voxels must stay conservative, or the "0 particles inside the mesh" bar breaks.
