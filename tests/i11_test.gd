## godot --path . -s tests/i11_test.gd     (I11: stroke-guided retopology; scripts/kmesh_retopo_*.gd, native/src/kine_retopo_native.cpp)
## Method: Takayama, Panozzo, Sorkine-Hornung, Sorkine-Hornung, "Sketch-Based Generation and Editing of Quad Meshes",
## ACM Transactions on Graphics 32(4), SIGGRAPH 2013, art. 97.
## BARS, COMMITTED BEFORE THE FIRST RUN (numbers fixed here; a fixture may be changed after a run only if the run shows it was wrong
## as a fixture, and that is said in the report, never the bar):
##   1 VALID PATCHES. For every side count n in 2..6 and every count vector d_i in 1..8 whose plan() is feasible, the filled patch
##     (a regular n-gon, flat, ccw seen from +z): every face has 4 distinct verts; the ring has sum(d_i) verts; every ring edge lies
##     in exactly 1 face and every other edge in exactly 2 (a manifold disk); no face is flipped (normal.z > 0); Euler V-E+F = 1.
##     The infeasible count vectors are listed with their reason (not filled). NETWORK: on the sphere network the baked mesh has every
##     edge in exactly 2 faces, no vertex lying inside another edge (no T-junction), and the count on a shared side is the same
##     from both patches. PLANTED (each must be caught by the same checker): a pair of patches whose shared side has 3 vs 4 edges
##     is flagged; one quad with its winding reversed is flagged as flipped; a vertex put on the middle of an edge is flagged T-junction.
##   2 SINGULARITIES. Interior (non-ring) vertices of valence != 4, per filled patch, <= MIN_SING[n] = {2:2, 3:1, 4:0, 5:1, 6:1}
##     (the Gauss-Bonnet count of a quad disk whose n corners have valence 2; KMeshRetopoFill header). Counts printed per n.
##     PLANTED: a patch with an extra valence-3 interior vertex is counted above the bound.
##   3 SURFACE FIT. Max distance from the baked mesh (vertices, edge midpoints, quad centres, 3x3 points per quad) to the source,
##     relative to the source bounding-box diagonal: sphere <= 1.0 %, the real mesh (mannequin head and torso from assets/mannequin.glb,
##     the densest organic surface in the repo) <= 2.5 %. The distance is measured against the analytic sphere / a brute-force
##     GDScript closest point on 40 samples, not only with the solver's own projection. PLANTED: the sphere baked mesh scaled 1.05
##     about the centre must read above its bound.
##   4 QUALITY. Minimum scaled Jacobian (min over a quad's 4 corners of the sine of the corner angle) of every quad >= 0.3 after
##     relaxation (20 iterations) on the sphere network and on the real-mesh network. PLANTED: the same curved patch with 0 relaxation
##     iterations must read below 0.3.
##   5 EDITS. Deleting a stroke merges its patches (count drops by the merged amount, the surviving patches that did not touch it are
##     bit-identical, the new patch solved). Changing a count re-solves ONLY the patches touching that side (solve counter per patch;
##     others bit-identical; the touched ones changed). Hand-set counts stay while auto counts of other arcs do not move.
##   6 SPEED. A 24-patch network (8 sectors x 3 bands on a sphere): the whole solve_patches call <= 50 ms, timed inside C++ (median of
##     5), and the edit re-solve (one side's count changed: 2-3 patches) <= 50 ms too; both printed.
##   7 C++ = GDScript. KMeshRetopoFill.fill vs KineRetopoNative.fill: every feasible count vector (n = 2..6, d_i in 1..8), ring points
##     perturbed by a fixed pseudo-random 0.3 jitter: verts within 1e-9, quads identical, plan() identical. PLANTED: one input
##     coordinate changed by 1e-6 on the C++ side must read above 1e-9.
##   8 UI. Q opens Retopo mode in the model preview (registry line mesh_retopo, do op:retopo); a drawn stroke (mouse events) snaps to
##     the surface; wheel over a side changes its count; Delete removes the hovered stroke; Bake replaces the mesh by an all-quad
##     mesh in ONE undo step and Ctrl+Z gives the source back exactly. The pole of the keys: Q was free in the model preview.
##   LOOK: screenshots of the mannequin head and torso: strokes, patches, baked quads with the heat map, beside the source.
extends SceneTree
