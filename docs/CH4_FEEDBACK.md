# CH4 feedback: the dovetailed oak box with solid grain

## What was built
- `scripts/build/wood_solid.gd` (the 3D grain field + material hook), `wood_solid.gdshader` (same field in GLSL), `native/src/kine_wood_native.cpp` (same field in C++, for baking many points), `scripts/build/oak_box.gd` (the box as ONE Part record: 5 prims, 2 offset planes, 6 sketches, 6 extrude cuts, a chamfer, 5 solid-wood looks).
- Two small additive hooks, `Part.paint` (part.gd) and `_look_surfaces` (part_ui.gd): a look whose `mat.kind` is `oak3d` gets the ShaderMaterial. MaterialMaker is untouched.
- Build command (from native/): `bash /c/Users/Nick/tools/kine_workers/native_build.sh` (rebuilds kine_native.dll with the new class; sources only are committed).
- The field is evaluated in the mesh's own space (mm), so the grain does not depend on UVs, on the face, or on how the mesh was cut: the tail ends show end grain (rings as arcs, round pores), the long faces show flat-sawn bands, the lid's chamfer shows the grain inside the board.

## Numbers (tests/ch4_test.gd, 0 fail)
- Dovetail: 24 flank triangles all at 7.125 deg (1:8); gap Front/Left 0.0496 mm (bars < 0.1, > 0.02). Controls: a 1:6 box measures 9.46 deg, a 0.3 mm build 0.298 mm: both fail.
- Continuity: worst ring-phase step across 712 samples at every crease (16 chamfer, 112 tail-end creases) 0.79 px (median 0.45; bar 1 px = 0.125 mm). The planted 2D UV texture: median 334 px.
- End vs side: 5 closed rings on the billet end (rms 3.2 % of radius, centre off 0.04 mm); all 30 faces classified right by pore shape (end 1.2, long 7-17); the 2D control misclassifies 14 of 30.
- Long face 79 % of the gradient across the grain; the lid shows cathedrals (75 % slanted, turning both ways); a trunk with no taper does not (12 %).
- C++ equals GDScript to 1.2e-7 on 20000 points; 85x faster (3.1 ms vs 271 ms). Shader vs field on pixels: 100 % within 3/255, mean error 0.385/255. Phase image across the chamfer edge: jump 0.006 ring mean.

## What I changed after seeing results (so you can judge it)
- The first E3 bar (dg/dx of both signs) was a wrong theory: the sign of dg/dx is fixed by the taper. I replaced the measure with slant along the grain + turning across it (the cathedral signature) before re-running, and replaced my own extra control (which the numbers disproved) with a no-taper trunk control. The registered bars A-D, F-H, R, L and the E1/E2/E4 bars are unchanged.
- E4 first misclassified one end face: with ellipsoid pores a face at an unlucky depth saw only the cap. Real vessels are tubes, so pores became tubes cut into segments; this is a better model, not a looser bar. The window for E4 grew from 10 to up to 60 mm (more pores to count), which is a measurement change, not a bar change.
- Ring profile: latewood now the last half of the ring (was 0.18-0.62 ramp), because the first render showed huge dark lenses on the side faces. The side lenses are still the weakest part.

## Looking at it (docs/ch4/sbs_*.png, corner/chamfer/endgrain/box.png)
- Good: the lid's cathedral arches next to the floor photo's arches; the tail ends with arcs and pore dots; the rings do run round the corners and into the chamfer.
- Not good enough: the side boards are too smooth, with a broad dark "lens" where the cut is nearly tangent to a ring. Real flat-sawn oak has finer stripes and more pores per area. Pores are too sparse next to the 1200 dpi scan (its earlywood band is a dense row of pores). Rays on the end face are sparse, long straight lines; the scan has ray lines every 3 mm. Colour is fresh-oak light, the floor photo is aged and grey-brown; there is no normal/bump so pores do not catch light.
- Reference limit: the Commons search had no clean quarter-sawn ray-fleck photo; large-ray size is from text, not measured.

## Left
- Finer ring profile for flat-sawn faces (a second, faster latewood line, per-ring width variation), denser pores and rays, a normal map from the pore mask.
- A UI picker for solid oak on any body (today it is a spec in the look: `{"mat": {"kind": "oak3d", "pith": [..], "dir": [..]}}`).
- The GDScript fallback bake is 85x slower than C++ (fine for tests, slow for big faces).
