# CH8 feedback (liquids): what was found, what is red

State: RED. 6 of the bars in `tests/ch8_test.gd` fail on the last full run; one fix pass was used. Nothing below changed a bar's threshold or statistic.
Bars were committed before their first number (1347f6ca for a-g; c2 in 11ec7b5e).

## Final bar table (last full run, native C++ build, 8 threads, one Godot)

| Bar | Number | Verdict |
|---|---|---|
| native class registered | yes | ok |
| (a) hydrostatic max speed < 1e-3 m/s | 1.2149e-3 | FAIL |
| (a) bottom pressure within 2 % of rho g H | 982.9 vs 981.0 Pa, 0.20 % | ok |
| (b) volume V/V0 >= 0.98 over the dam break | 0.9266 | FAIL |
| (c) Ritter bound Z <= 1 + 2T | holds | ok |
| (c) Martin & Moyce within 10 % (UNVERIFIED remembered table) | worst 16.6 % | FAIL |
| (c2) average front speed in 1.48 .. 1.74 sqrt(gH), square column, tau 1..2 | 1.740058 | FAIL (6e-5 over the edge, not rounded in its favour) |
| (d) C++ == GDScript, 16^3, 20 steps, < 1e-6 | max diff 0 | ok |
| (e) 0 particles in wall voxels / inside the mesh by ray parity | 0 / 0 | ok |
| (e) no leak below the rim while < 0.9 of the cup poured | 0 | ok |
| (e) fills >= 85 % | 79 % (0.291 of 0.371 L) | FAIL |
| (e) spills >= 2 % | 36.8 % | ok |
| (f) largest count at >= 10 steps/s >= 200000 | 194672 (ladder rung; next rung 417600 runs 7.8 steps/s) | FAIL |
| (g) all controls (gravity 0, planted M&M x1.3, other seed, mesh without voxels, Ritter 2.0 vs c2) | all fail as they must | ok |

Regression suites (easypart, peasy3, freestart): see the report line at the end of this file.

## What the first run found (previous lane died before reporting)

1. `Fluid.native()` only asked ClassDB, so the extension (config `native/kine_native.gdext`, loaded by `NativeExt.ensure`) was never loaded: the suite ran the GDScript twin and timed out at 900 s. Fixed in `scripts/fluid.gd`.
2. PCG matrix-vector product (`pcg()` in `native/src/kine_fluid_native.cpp`) called `pfor(1, ...)` for systems under 20000 cells, so it multiplied only the first fluid cell. The solve diverged (pressure 1e30). One line. After it: hydrostatic pressure 0.20 % off.
3. The density-drift term in the pressure RHS scaled as (h/dt)^2, so every short step (the partial last step of each `advance()`) injected a huge velocity. The same free-slip dam break gave front Z = 3.99 at T = 2 or 3.08 depending on how it was sampled. Now a fixed rate with dt floored at dtmax.
4. `pfor` ran serial whenever n < 2*nt, so p2g (about 4 slabs), the dot product and advect never used threads. Now it spawns min(nt, n) threads.
5. Test message strings used `%.2e`, which Godot's format does not have (script error): replaced by `String.num_scientific`.

## The Martin & Moyce reference (bar c) and c2

* Bar (c) uses a table written from memory; it stays as committed and is reported as against an UNVERIFIED remembered table. Failing (worst 16.6 % after the fixes).
* Inference, marked as such in `docs/CH8_REFERENCE.md`: that table's late slope fits a square column (n^2 = 1), not the n^2 = 2 scene of bar (c). Nothing was changed because of it.
* c2 uses cited numbers (arXiv:1308.0115 Table 1: v / sqrt(gH) for tau = t sqrt(g/H) > 1; M&M 1.48/1.69, Dressler 1.54-1.74; cross-check arXiv:2108.08769 sec 3.3.2). Window tau 1..2 is my choice (the source gives none). Result 1.740058: the free-slip solver's front is right at the upper edge of the experimental span; frictionless theory is 2.0.
* Friction diagnostic (not a bar): opt-in wall friction 0.5 gives 1.233 and 1.0 gives 1.370, both BELOW the span. No friction value in the span comes from a cited tank-material coefficient, so none was added; friction stays 0 in every bar. c2 stays failing and I do not claim it can be closed by friction.

## Volume (bar b): measured, not fixed

Dam scene, 20 samples T = 0.25 .. 5: particle count constant at 51200, NaN 0, out-of-bounds 0, in-solid 0. Nothing is deleted. What changes is packing: 1900-2100 cells hold more than 8 particles (peak 14-19), excess 6.4 % at T = 0.25 rising to 7.3 %, and occupied cells x 8 / N grows 1.03 -> 1.22 (spray and surface cells). So the bar measures how far the particles drift from the initial one-per-octant lattice; random particle positions at 8 per cell score about 0.9 whatever the physics. Sign of the correction checked: positive pressure source expands over-full cells. The correction is too weak to hold the lattice, and the changes in this pass moved the number 0.952 -> 0.944 -> 0.927 (the rate-based drift is weaker on short steps; the void pull-in compresses neighbours). The standard remedy is particle shifting (Xu, Stansby, Laurence 2009; Lind et al. 2012), not a reseed: not done in this pass.

## Mug (bar e): where the poured water goes

Before the void fix (poured 0.556 L = 1.5 cap): inside the cup below the rim 34.6 %, table below 15 mm 28.0 %, heaped above 15 mm or on the cup outside 34.9 %, in the air above the rim 2.5 %, lost 0. The cup interior held every 10 mm layer at about half the packed density (6200 against about 12000 particles): voids from the thinning stream were never re-compressed, since the drift only pushed apart over-full cells. Fix: under-dense cells whose six neighbours are all fluid get a negative source (free surface untouched). Fill 52 % -> 79 %, leak 11178 -> 0. Still 6 points short of 85 %. Walls: 0 particles in wall voxels or inside the mesh; no gap thinner than a cell at the rim was found (the leak count is 0).

## Throughput (bar f), reported separately

Threaded: p2g (slabs), g2p, advect, dot, matvec; PCG warm-started from the previous step. Ladder, 8 threads, other lanes were running (noisy): 52k 82 steps/s, 96k 58, 195k 10.9 (12.7 on a quieter run), 418k 7.8, 810k 4.5, 1.24M 3.4 (about 3-4 M particles/s). The projection (serial MIC-preconditioned PCG sweeps) is about two thirds of a step at 418k. The bar needs a rung above 200000 at 10 steps/s; the next rung is 418k at 7.8, so it fails. Next: a threaded preconditioner (red-black / multigrid) in C++.

## Render (looked at)

`C:/Users/Nick/tools/kine_workers/out/ch8/` (f0000..f0179.png and ch8.mp4; contact sheets in `C:/Temp/claude/dam_sheet.png`, `mug_sheet.png`). Dam break: correct wave shape (front across the floor, splash up the far wall) but the water reads as thin shells and lines, not as a volume. Mug: fills to the rim and a pool forms on the table, but the pool is a lacy film with holes (one-cell-thin sheets fall under the iso threshold). A `look_at` warning is printed (camera aimed before it is in the tree). The look is not good enough to show.

## Build command

`cd native && bash /c/Users/Nick/tools/kine_workers/native_build.sh` (waited 24 min once for another lane's lock).

## Regression suites (after the final solver commit)

PASS peasy3 ok 23 fail 0; PASS freestart ok 14 fail 0; PASS easypart ok 73 fail 0 (WT_MAX=8, one call).
