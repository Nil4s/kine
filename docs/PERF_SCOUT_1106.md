# PERF SCOUT 11-06 (lane L54): what the end user waits for

Measured, not guessed: `tests/perfscout_test.gd` (run `wtest.sh perfscout`; `tools/perf_scout.gd` is a thin alias), RTX 3070, window 1280x720 off-screen, vsync off, Godot 4.7.2, scene `combo3` plus N props. Median of 5 (3 or 1 run when an op took over 0.5 s / 3 s). Raw rows: `C:/Temp/claude/perfscout/rows.jsonl` and the section logs. A stall above 100 ms is a hitch, above 16 ms drops a frame.

## Ranked table (worst user-visible stall first)

| # | Operation | ms @256 | ms @1000 | Exponent (50 to 1000) | Stall | Now | Hot function | Fix | Expected gain |
|---|---|---|---|---|---|---|---|---|---|
| 1 | Save scene / export USD with a big set | save 2502, USD 2748, check alone 3629 | save 8778, USD 9612, check alone 8595 | save 0.84 (base 500 ms, then linear in props) | 2.5 to 9 s freeze | GDScript | `Scene.check(B)` scripts/scene.gd:2178, called from `Scene.to_dict` scripts/scene.gd:2277 (plays every frame through `apply` + `B.contacts()` with all props in `B.props`) | Save must not replay the scene: cache `bad_frames`, recompute on a worker thread or only when a card changed; then a C++ broadphase for the ground/contact pass | save 8.8 s to under 0.2 s (40x+) |
| 2 | Part CAD replay (every parameter edit) | 1203 (256 separate boxes), 16299 (edit last step of 256 joined) | not run | 1.83 (joined: 10 boxes 55 ms, 50: 782, 256: 15412) | 0.36 s on a 40-hole plate, 0.8 s at 50 features, 16 s at 256 | native kernel (kine_cad), GDScript driver | `Part.replay` scripts/build/part.gd:566 replays ALL steps from step 0 on each edit; each join fuses the growing body (O(n^2)) | Checkpoint the body list after every step and replay only from the edited step; fuse a pattern's tools in ONE native boolean call | edit of the last step 16 s to about one step (60 ms): 200x |
| 3 | Props.settle (runs on every prop change) | 63 | 924 to 933 | 1.99 (2.4 ms at 50) | 0.9 s hitch per edit at 1000 | GDScript | `Props.settle` scripts/props.gd:665 (for each prop, loops every earlier prop's supports) | Uniform grid over the supports (C++ in a new native file, GDScript twin, equality bar) | 924 to under 10 ms (90x) |
| 4 | Undo / redo with a big set | undo 195, redo 172 | undo 1169, redo 1178 | 0.78, but 112 ms already at 50 | hitch at 50 props, 1.2 s at 1000 | GDScript | `Main._undo` scripts/main.gd:7384 then `_restore` :7058, ends in `_props_show` (settle is about 80% of it at 1000) | Do not settle a restored state (it was settled when saved), diff the prop nodes; find the 100 ms base cost of the whole-app `_restore` | 1.2 s to about 50 ms (20x), base 112 to under 50 ms |
| 5 | Prop rebuild (`_props_show`) | 192 | 1597 | 1.86 | 0.2 s to 1.6 s on any prop add/move | GDScript | `Main._props_show` scripts/main.gd:22323 (settle 924 ms, the other ~650 ms is node free/add + `_props_pose`); `Props.mesh` for all 1000 is only 62 ms | Incremental node update (only the changed prop); MultiMesh for every repeated kind (1000 shared props still draw 1649 calls) | 1.6 s to under 50 ms |
| 6 | Nature scatter (app caps `n` at 4000: a request for 10000 places 4000) | points 56 ms @1000, scatter_node 319 ms @1000 | points 957 ms, scatter_node 1949 ms @4000 | about 1.4 | 1 to 2 s on every edit of a scatter | GDScript | `Nature.scatter` scripts/build/nature.gd:878 (dart throwing, `cap = n*600+2000` tries, spacing test against every placed point), `NatureView.scatter_node` scripts/build/nature_view.gd:261 | C++ dart throwing with a spatial hash, MultiMesh transforms from one PackedFloat32Array | 2.9 s to about 0.1 s (25x) |
| 7 | KMesh topology + validation on an open 20k-tri mesh; boolean; subdivide | n/a | from_array_mesh 67, rebuild 49, is_manifold 58 (175 total @20k); subdivide 69 @5k; boolean 203 @10k tris; voxel remesh 365 @20k (native) | about linear; subdivide and boolean super-linear | 175 ms to open and check a 20k mesh; boolean over 100 ms from 10k tris | GDScript (remesh, decimate, sculpt already native) | `KMesh.from_array_mesh` scripts/kmesh.gd:551, `KMesh.rebuild` :327, `KMesh.is_manifold` :507, `KMeshSubdiv.subdivide` scripts/kmesh_subdiv.gd:26, `KMeshBoolean.run` scripts/kmesh_boolean.gd:53 | C++ half-edge build (kine_meshops_native exists), subdivide and boolean ports; voxel remesh on a worker thread | topology 175 to about 20 ms (8x), boolean 200 to 30 ms |
| 8 | Playback frame (1 fighter) | n/a | `_process` 8.2 ms + draw 3.2 ms; soft flesh adds 1.3 ms; idle 2.1 ms | n/a | inside the 16.7 ms budget with 1 fighter, but 7.5 ms is one block | mixed (skinning native) | `Main._refresh` scripts/main.gd:5595 (`p_refresh` 7.5 ms; `r_hands` 3.4, `h_dock` 3.3 nested) | Skip the hands/dock rebuild when the hands did not change; partial refresh while playing. For 4 fighters see tests/perf4_test.gd | 8 to about 4 ms per frame |

## Everything measured (ms, median)

Scene with N props, shared kinds (4 kinds, MultiMesh path), N = 50 / 256 / 1000:

| op | 50 | 256 | 1000 |
|---|---|---|---|
| props_show | 6.1 | 191.8 | 1597 |
| _snapshot | 1.6 | 3.3 | 6.4 |
| _push_undo | 16.7 | 21.5 | 28.4 |
| undo | 111.7 | 194.8 | 1168.8 |
| redo | 89.7 | 171.6 | 1178.0 |
| Outliner.objects | 0.07 | 0.34 | 1.5 |
| pick prop (click ray) | 0.5 | 2.4 | 9.3 |
| Props.settle | 2.4 | 62.7 | 933 |
| save (to_dict + stringify) | 706 | 2502 | 8778 |
| load: JSON.parse (engine C++) | 3.2 | 3.1 | 4.5 |
| load: Scene.from_dict | 3.5 | 3.6 | 6.7 |
| frame `_process` | 2.7 | 2.3 | 3.8 |
| frame total incl draw | 3.5 | 5.3 | 4.0 |
| draw calls / nodes | 909 / 4988 | 1104 / 5868 | 1649 / 9030 |

Unique kind per prop (no batching; the synthetic kinds hit a few `Props.kind_of` errors during undo, so approximate): props_show 5.8 / 104.9 / 1647, redo 74 / 155 / 1242, save 497 / 1422 / 5755, frame `_process` 2.6 / 2.8 / 3.7, draw calls 813 / 878 / 1051. Per-frame cost does not grow with parts on this GPU: the stalls are edit-time (GDScript O(n^2)), not draw-time.

Profile split (256 / 1000): Scene.check 3629 / 8595; Props.settle 60 / 924; PropInstances.plan 0.5 / 2; Props.mesh for all props 16 / 62; Props.to_dict for all 0.6 / 2.7; S.props_at 0.1 / 0.4. Export: glb 181 ms (combo3), USD text 193 ms; USD with props 713 / 2748 / 9612 ms at 50 / 256 / 1000.

CAD (native kernel, GDScript replay): 10/50/256 separate boxes 27/160/1203 ms; joined into one body 55/782/15412; edit last step 55/901/16299; edit first step 55 (10) and 733 (50); plate with 40 drilled holes 357.

KMesh (tris 1280 / 5120 / 20480): rebuild 2.6/11.6/49; to_array_mesh 0.15/0.6/2.8; from_array_mesh 4.3/16/67; to_dict 1.2/4.8/20; is_manifold 3.2/12.6/58; symmetry_map 0.5/1.9/8.7; subdivide 17/69/not run; decimate (native) 5.6/23/104; voxel remesh (native) 111/134/365; bevel 30 edges 16/37/not run; sculpt begin 8/0.5/1.9 and sculpt dab 0.01/0.02/0.05 (native, never a problem); boolean union (2 spheres, 640/2560/10240 tris in) 21/63/203; autoweights (642/2562 verts) 13/55 (native CG; the file header says 9 s for the 7k-vert mannequin, not re-measured); retopo setup 2.8 (5k); uv_sphere 128x64 29.

Body: playback `_process` 8.2 ms, idle 2.1 ms, soft flesh (6 regions) 8.2 ms with soft = 1.3 ms of it, soft bake 0.77 s on a thread. Nothing here is a stall.

## Top 8 lanes, ready to brief

1. L-SAVE: stop Scene.check on save/export. Cache or thread `bad_frames`; `to_dict(B, false)` for autosave/export. Bar: save @1000 props under 300 ms and the file equal except `bad_frames`. Biggest stall (up to 9 s).
2. L-CADINC: incremental Part.replay. Checkpoint bodies per step, replay from the edited step; batch pattern fuses in one native call. Bar: 256-box joined, edit last, under 500 ms, volume equal to the full replay.
3. L-SETTLE: Props.settle to C++ with a grid (GDScript twin, equality bar over 20 random sets). Bar: 1000 props under 15 ms.
4. L-UNDO: undo/redo without re-settle and without a full prop rebuild; find the 100 ms base cost of `_restore` at 50 props. Bar: undo @1000 under 100 ms, @50 under 40 ms.
5. L-PROPNODES: incremental `_props_show` (diff nodes, MultiMesh everything repeated). Bar: moving one of 1000 props redraws in under 30 ms.
6. L-SCATTER: Nature.scatter + scatter_node in C++ with a spatial hash and a MultiMesh buffer; same points for the same seed. Bar: 4000 under 150 ms.
7. L-KMESH-TOPO: KMesh from_array_mesh / rebuild / is_manifold in C++ (extend kine_meshops_native), then subdivide and boolean ports; voxel remesh on a worker thread. Bar: 20k-tri mesh open under 40 ms; boolean 10k tris under 50 ms.
8. L-REFRESH: playback `_refresh` (hands and dock blocks, 7.5 of 8.2 ms): skip unchanged work. Bar: `_process` under 5 ms playing; check 4 fighters with perf4.

## Honest limits

- Browser/outliner tree refresh timed 0.00 ms: the tree is not built while its page is hidden, so inspector/outliner refresh with 1000 items is NOT measured (Outliner.objects is: 1.5 ms). look_facts / id render were not measured (the scene had 0 build units). Retopo was only timed at setup. A second fighter via `_actor_add` crashed the app in the scout's off-screen window (signal 11 in UI layout), so multi-fighter numbers are left to tests/perf4_test.gd.
- Synthetic props are boxes/crates/tables/chairs on a grid; a real heavy scene (houses, trees, imported glb) costs more in `Props.mesh`. "Parts" were props of a registered part mesh, and CAD parts were prim steps.
- GPU draw time is the dev box's RTX 3070 off-screen: weaker GPUs will see draw cost this scout cannot.
- Different sections come from different runs (the first full run died at the 2-fighter step; later runs used SCOUT_ONLY).
- One sanity check changed after seeing results: scatter 10000 placed 4000 (the app caps n), so "placed over half of n" became "placed over 500". No speed bar exists to move.
