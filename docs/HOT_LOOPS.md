# Hot loops (C64, 11-03)

Fixed scene, 3 repeats, median ms, `tests/c64_prof_test.gd` run through wtest.sh (headless, off-screen, machine loaded).
Scene: UV sphere 3010 verts / 3072 faces (remesh, decimate, autoweights uses a 1874-vert sphere), 18240-tri sphere (STL), 20k skinned verts x 24 bones, "Bay house" building.

| Path | File:line of the loop | GDScript ms | Native ms | Status |
|---|---|---|---|---|
| Voxel remesh (voxel 0.02) | scripts/kmesh_voxel_remesh.gd:97 (surface_nets), any_grip.gd MeshField.build_banded | 862 | 107 | already C++ (KineMeshOpsNative / KineFieldNative) |
| Decimate to 25 % | scripts/kmesh_decimate.gd:297 collapse | 179 | 48 | already C++ |
| STL export (18k tris) | scripts/build/mesh_export.gd:182 stl_bytes | 11.9 | 0.37 | already C++ |
| Auto skin weights (1874 verts, 3 bones) | scripts/kmesh_autoweights.gd:113 compute: solve 115 ms (the CG, _cg), visibility 38, dist 6.5, laplacian 5.4 | 172 | 66 whole (solve 118 -> 5.6) | solve ported (this item) |
| DQS skin surface, 20k verts | scripts/dq_skin.gd:152 skin_surface / :98 skin_one | 43 (LBS 41) | none | GDScript only; ~2 us/vertex, next candidate |
| Blueprint sheets + SVG + DXF (4 tabs) | scripts/build/blueprint.gd:103 sheet, :636 to_svg, :680 to_dxf | 14 | none | fast enough |
| Cut list solids | scripts/build/cut_list.gd:71 solids | not timed | none | engine-bound: Part.replay (OCC) |
| Explode view, retarget/IK per frame, part replay, texture bake, video track, glb/fbx export | scripts/easy_explode.gd, limb_ik.gd, build/part_replay_calls.gd, bake.gd, video_*.gd, gltf_export.gd | not timed | none | engine calls inside (nodes, scene tree, OCC): not pure loops |

Picked by number: among the pure GDScript loops the worst is the auto-weights heat solve (172 ms for 1.9k verts, and the mannequin has far more; 67 % of it is the conjugate gradient `_cg`).
Ported: `KineSolveNative.cg` (native/src/kine_solve_native.cpp), GDScript fallback `_cg_gd`, switch in `_cg`. Bars: tests/c64_test.gd.
