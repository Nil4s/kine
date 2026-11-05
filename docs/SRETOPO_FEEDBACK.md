# SRETOPO (lane I11 of the worktree): stroke-guided retopology, feedback

Method: Takayama, Panozzo, Sorkine-Hornung, Sorkine-Hornung, "Sketch-Based Generation and Editing of Quad Meshes", ACM TOG 32(4), SIGGRAPH 2013. Code: `scripts/kmesh_retopo_fill.gd` (patch dictionary, GDScript reference), `native/src/kine_retopo_native.cpp` (`KineRetopoNative`: plan, fill, BVH projection, solve with relaxation), `scripts/kmesh_retopo_net.gd` (strokes -> nodes, arcs, patches, counts, edits, bake), `scripts/kmesh_retopo_ui.gd` (Q in the model preview). Test: `tests/sretopo_test.gd` (bars in its header, committed before the first run; one AMENDED note for two fixtures).

## 1. Result

Suite: `WT_MAX=8 wtest.sh sretopo i11 easypart peasy3 freestart`: sretopo ok 29 / fail 0, i11 16/0, easypart 73/0, peasy3 23/0, freestart 14/0.

| bar | result | numbers |
|---|---|---|
| 1 valid patches | ok | 13918 feasible count vectors (n = 2..6, d_i 1..8) all fill a manifold disk; the infeasible ones listed by reason (parity, triangle inequality, opposite sides, digon < 3 edges) |
| 1 network (sphere, 3 great circles) | ok | 600 quads, 1200 edges: 0 edges not in 2 faces, 0 T-junctions, 0 unequal shared sides, 0 flipped |
| 1 planted | ok | 3 vs 4 shared side flagged, reversed quad flagged, mid-edge vertex flagged T-junction (same checker) |
| 2 singularities | ok | max interior singular verts per patch: n=2: 2, n=3: 1, n=4: 0, n=5: 1, n=6: 1 (= MIN_SING); planted diagonal collapse counts 3 > 0 |
| 3 fit sphere | ok | 0.231 % of the diagonal (analytic sphere, 8402 points; bound 1.0 %); planted x1.05 reads 1.443 % |
| 3 fit mannequin | ok | 0.705 % (5.3 mm of a 76 cm diagonal, 3405 points; bound 2.5 %); brute-force GDScript closest point on 40 samples agrees with the BVH to 6e-8 |
| 4 quality | ok | min scaled Jacobian 0.867 sphere, 0.837 mannequin (>= 0.3, 20 steps); planted skewed octant patch (4, 10, 12): 0.680 relaxed, -0.243 unrelaxed |
| 5 edits | ok | count change: arcs 24, 32 (3 -> 5), re-solved exactly the 3 touching patches, others bit-identical; delete north ring: 16 touched -> 8 merged, 24 -> 16 patches, the 8 untouched bit-identical; the pinned count and the 16 south arcs' auto counts kept |
| 6 speed | ok | 24 patches 1.07 ms, edit (3 patches) 0.17 ms, medians of 5 timed in C++ (bound 50 ms) |
| 7 C++ = GDScript | ok | every feasible vector, 0.3 jitter: plan and quads identical, verts max diff 0; planted 1e-6 reads 1.0e-6 |
| 8 UI | ok | registry line `mesh_retopo` `op:retopo` key Q (the only Q on MODEL); 4 mouse strokes snap (max 1.6e-8 off the surface); wheel over a side 2 -> 3; Delete over a hovered stroke removes it; Enter bakes 6 quads in one undo step; Ctrl+Z gives the 1106-vert source back exactly |
| LOOK | written | `docs/sretopo/mannequin_front.png`, `mannequin_back.png` (source, strokes + patches, baked quads with the heat map) |

## 2. Level reached: geometry processing

On the scale of `CHALLENGE_FEEDBACK.md` read for geometry processing: **L3** (student engineer). Every metric is checked against an independent reference: the analytic sphere, a brute-force closest point, an exhaustive enumeration of the patch dictionary, a second implementation (GDScript vs C++) and planted controls for each checker. The patch topologies follow the Gauss-Bonnet count of a quad disk, and the singularity bound is met exactly.

Why not L4: there is no comparison with the paper's results or a reference implementation on standard meshes, and no dense scan or sculpt. The densest organic piece in the repo is 451 verts, coarser than the quads laid on it. Counts come from a greedy +-1 search, not the paper's integer optimisation over the whole network. Relaxation is tangent-plane Laplacian, not the paper's parametrisation-based smoothing. There is no symmetry and no guide-curve field. L4 would need a dense test asset, the paper's ILP for the counts, and a quality comparison against QuadriFlow or Instant Meshes output, measured but with none of their code.

## 3. What Kine lacked

| needed | exists today | workaround | cost | proposed feature |
|---|---|---|---|---|
| a plane section of a mesh as polylines (strokes along rings and meridians) | nothing as a query (the knife `Shift+K` and `kmesh_cut_tool.gd` cut faces; they return no curve) | `section()`, `ring_at()`, `runs_between()` in the test | ~150 lines | `KMesh.section(plane) -> Array[PackedVector3Array]` (closed loops marked), reused by knife, measure and retopo |
| closest point on a triangle mesh | three GDScript copies: `KMeshDecimate.closest_on_tri`, `KMeshSnap.closest_on_tri`, `KMeshShrinkwrap.closest_bary`; now a BVH in `KineRetopoNative.project` | wrote a fourth copy (Ericson) for the brute-force check | 40 lines; a DISCOVERABILITY and duplication gap | one `KMeshClosest` helper (GDScript + native door) that all four use |
| a dense organic mesh to retopologise | the mannequin: a segmented, open low-poly shell (head + chest piece 451 verts, cracks at the neck front, head open below 1.67 m) | strokes placed only where the piece is a closed loop; fixture amended after the first run | one fixture amendment; the result is no test of retopo on dense data | a CC0 dense bust or scan (50k+ verts) in `assets/test/` for retopo, decimate and shrinkwrap tests |
| the model preview naming a mesh opened through `kmed.source` | `main.gd` falls back to "Editing: Test cube" when there is no name | none (the screenshots say "Test cube" on the mannequin) | wrong label in every LOOK image | a `"name"` key in the source dictionary, shown in the bar |
| framing and composing model-preview screenshots | each lane writes its own (G11) | `look_at_mesh()` + crop/compose in the test | ~60 lines | a shared "frame mesh + shot + side-by-side sheet" helper |
| loading an optional native class from a script | `NativeExt.ensure` (found only after the first run, where `ClassDB.class_exists` said no) | the previous agent's net never got its native solver in the app | the GDScript fallback ran (nearest-vertex projection, 7.7 % fit) | `KineXNative.get()`-style doors, or a lint that flags `ClassDB.class_exists("Kine...")` without `NativeExt.ensure` |

## 4. What looks wrong (after looking at the PNGs)

- Only the head cap (4 three-sided + 4 four-sided patches) and one chest band (8 patches) are baked. The neck, the face below 1.69 m and the lower chest are left out, because those regions hold the open edge of the mesh. The status line only says "3 regions skipped". A real retopo of this piece needs many more strokes, and the UI does not show where the holes are.
- The chest band is one quad tall between rings 5 cm apart, with 9 edges round each sector. The heat map legend counts 4 "skewed quads". From the back, the open band reads as a broken mesh even though it is correct for those strokes.
- The 4 valence-3 poles of the head-top patches cluster near the crown: correct by the dictionary, but visible.
- The heat-map colours barely show: the baked mesh draws as white wire, and only the legend gives the counts.
- In the middle panel, the green patch wires are hard to see under the yellow strokes and the white source wireframe. The count labels overlap the lines.
- Framing: the crown is clipped in the front view, the fighter's arm and the UI panels get into the shot, and the bar says "Editing: Test cube".

## 5. What was changed after the results

No bar was loosened. Changes, with git as the record:

- **Implementation, found by reading before the first run** (commit 96bd689e). The bake used the wrong ring ids whenever a patch's first corner was not at ring position 0: the fill's ring starts at the first side. The end-snap appended a point to the stored stroke on every rebuild, so strokes grew and nodes drifted. A band between two stroke rings was filled as two disks: regions claimed by two cycles now become "not a disk". Folded fills (quads facing against the surface) are no longer baked. Each patch now carries a solve stamp. The relaxation was 12 steps; the header says 20.
- **Implementation, found by the runs** (ef09c908):
  - `KineRetopoNative` never loaded, because the net used `ClassDB.class_exists` without `NativeExt.ensure`. It now loads.
  - 4 of the 18 two-sided count vectors gave flipped quads: the parallelogram X/Y points cross when the corners are wide. The digon interior now gets 100 Laplacian steps in both GDScript and C++ (native rebuilt), and the two still agree to 0.
  - The region probe jumped across thin chest patches into the next region (5 good patches dropped). It now walks on the surface and stops at another stroke's wall.
- **Fixtures** (AMENDED note in the header):
  - Mannequin rings moved to heights where the piece is a closed loop (1.69 / 1.75 m and 1.34 / 1.39 / 1.44 m).
  - The bar 4 planted is now a skewed octant patch (4, 10, 12). Every network patch already read >= 0.5 before relaxation, so none of them could serve as the planted.
- **Test bugs:** a packed array copy in the bar 7 planted (the 1e-6 change was lost), a `%.3g` format, a type annotation.
