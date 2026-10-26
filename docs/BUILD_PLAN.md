# BUILD mode: the plan (3D BUILDING projects)

Reference mockups (owner-approved, 2026-10-25): `C:/Temp/claude/buildmock/build_start.png`, `build_room.png`,
`build_openings.png`, `build_words.png`, `build_to_scene.png`. Research: `C:/Temp/claude/research/modeling/report.md`.
Strategy: **Easy** = SketchUp basics (Room, Wall, Pull, snap to a 0.5 m grid, type a number). **Expert** later = Fusion-like
depth on the CAD kernel (`scripts/kcad.gd`, KineCAD on OCCT, optional DLL) and blueprints (plan / elevation / section, PDF / SVG / DXF).

The goal of phase 1 is the 60-second product in the research report: a new user draws a room, puts a door in it, presses
**Use in a scene**, and the fighter walks through the door on STAGE.

## 1. How Kine is built (what BUILD plugs into)

| Piece | Where | What BUILD uses |
|---|---|---|
| Pages | `scripts/main.gd` `PAGES`, `PAGE_ROW`, `PAGE_LAYOUT`, `PAGE_TIPS`, `_page_set(p)`; page bar `_page_bar` (~l.14760), ribbon `_ribbon_row(row)` | a new `BUILD` page: one more entry in each table, its own ribbon row |
| Expert pages | `scripts/expert_pages.gd` (`ExpertPages.PAGES` = MODEL, SCULPT, SURFACE; hidden in Easy) | the pattern for a page with its own 3D preview, its own tools and an enter / leave hook (`_mesh_leave_apply`) |
| Start screen | `scripts/start_screen.gd`: the "3D BUILDING" card, kind `"building"` -> today `m._page_set("STAGE")` | becomes `m._page_set("BUILD")`; `Scene.kind = "building"` already saves |
| Scene file | `scripts/scene.gd` `to_dict` / `from_dict`: every optional feature is a key written "only when there is one" (props, part_keys, drivers...), plus `MIRROR_SCENE` (every key must say whether it has a side; `tests/mirror_list_test.gd`) | the `"building"` key (**done in this skeleton**) |
| Set / props | `scripts/props.gd`: a prop = `{"kind", "xf"}`; a kind is DATA (`solids` boxes, `wedges`, `supports`); `Props.register(kind, aabb, glb)` adds runtime kinds to `EXTRA`; the body's floor / collision queries (`depth`, `rests`, `surface_below`, `solid_cache`) read `Props.solids(p)` | the building on STAGE is a prop whose kind is registered from the record, its `solids` = `Building.collision_boxes` |
| Mesh core | `scripts/kmesh.gd` (half-edge n-gons, `boundary_edge_count`, `is_manifold`, `to_array_mesh`), `kmesh_validate.gd` (`_volume`), editor `kmed` = `kmesh_edit_ui.gd` | the generated solid is a KMesh; Expert "Edit as mesh" opens it in MODEL |
| Undo | `main._snapshot()` / `_push_undo()` (whole-state dictionaries: `"props"`, `"pk"`, `"layers"`...) | one more `"building"` field: `Building.to_file(S.building)` |
| Words | `scripts/mesh_words.gd` (phrases -> KMesh ops, `claims()` routing, numbers + units, "every edit is ONE undo step and the reply says what was done") and `text_blocking.gd` (a phrase -> a plan of cards, unknown words listed back, not guessed) | `scripts/build/build_words.gd` copies both: parse -> a visible PLAN list -> Build it |
| CAD kernel | `scripts/kcad.gd`: `box`, `cut`, `union`, `fillet_all`, `shell`, `volume`, `tessellate`, `export_step`; `available()` false without the DLL and everything still runs | phase 2 mesh generator |

## 2. Where the page lives: a BUILD page (recommended), not a mode of STAGE

**Recommendation: a separate `BUILD` page**, first in the page bar of a building project (`BUILD | STAGE | CHECK | DELIVER`,
exactly the mockups' bar), reachable in Expert from any project.

Why not a STAGE mode:
- STAGE is *placement*: props, cast, lights, camera, the fighter. BUILD is *authoring* with 9-12 tools of its own (mockup ribbon:
  DRAW / ADD / MEASURE & EDIT / SAY). Both on one ribbon = the crowding the MODEL keys already show (`kmesh_edit_ui.gd` header).
- The camera and the input differ: BUILD is a ground grid with a 1.8 m ghost person, rectangle drags and typed sizes;
  STAGE drags props and the fighter. A mode switch inside one page doubles every click handler's branches.
- The mockups' hand-off (**Use in a scene** -> STAGE with "Set in use: Bay house (from BUILD)", **Back to BUILD** / **Edit in
  BUILD**) is a page change, which Kine already does well (`_page_set`, per-page folds, page tour).
- Page plumbing exists: one entry in `PAGES`, `PAGE_ROW` (`"BUILD": "BUILD"`), `PAGE_LAYOUT` (`{"left": true, "right": false,
  "bottom": true}`: the inspector = the selected part's numbers, as the Door panel), `PAGE_TIPS`. Easy shows BUILD for building
  projects (it is not an expert page).

## 3. The data model (done: `scripts/build/building.gd`)

A Building is a **parametric record**, plain JSON-able data, never a stored mesh. The scene file, the undo snapshot and the
words plan hold the same dictionary; the mesh is **regenerated** from it.

```json
{"version": 1, "name": "Bay house",
 "params":   {"wall_height": 2.7, "wall_thickness": 0.2, "floor_thickness": 0.2, "door_width": 0.9, "door_height": 2.1,
              "window_width": 1.2, "window_height": 1.2, "window_sill": 0.9, "grid": 0.5},
 "rooms":    [{"id": "r1", "x": 0, "z": 0, "w": 4, "d": 3, "yaw": 0, "height": "wall_height", "thickness": "wall_thickness", "floor": true}],
 "openings": [{"id": "o1", "room": "r1", "wall": "front", "kind": "door", "at": 0, "w": "door_width", "h": "door_height", "sill": 0}]}
```

- **Named numbers.** A number field holds a number or a param's name. `"height": "wall_height"` follows the param (change it once
  and every room follows: the mockup's "Change one and the house follows"); typing a number into one room's field makes it
  that room's own. Phase 1 UI shows a param's name next to a field that follows it.
- **Rooms**: outer corner (x, z) + outer sizes w x d (what the user drags is the outside of the walls) + yaw about the corner.
- **Walls** are implicit (a room's 4 sides: front z=0, right x=w, back z=d, left x=0). Phase 1b adds free `"walls"`
  (polyline, thickness, height) for the Wall tool.
- **Openings**: on a room's wall, `at` = metres from the wall centre (+X / +Z), clamped between the corner walls and under the top.
  Kinds door / window / arch; the frame and the leaf (a hinged `door` prop already exists in `props.gd`) are dressing.
- **Floors / roof** (phase 1b): `"storeys": [{"height": "wall_height"}]` (rooms get a `"storey"` index), `"roof": {"kind":
  "gable"|"flat"|"shed", "pitch_deg", "overhang"}`. **Pieces**: `"pieces": [{"kind": <Props kind>, "pos", "yaw"}]`.
- **Versioned**: `"version"`. A file from a newer Kine is kept whole and read only (saved back untouched); older versions get an
  upgrade step in `from_file`.
- **Bad data**: params clamped to their ranges, a non-finite number -> the default, an opening on an unknown wall / room dropped.

**Geometry (phase 1 mesher).** Each room = boxes (4 wall slabs, a floor slab under y = 0) minus opening boxes. All box faces cut
space into a rectilinear grid; a cell is solid when its centre is in a solid box and in no cut; a face is written where a
solid cell meets an empty one. Result: **closed and manifold by construction**, exact volume, an opening removes exactly its own
volume, and rooms with the same yaw share one grid (two rooms drawn wall to wall = one wall, no z-fighting). Measured: a 4x3 m room
is 32 faces / 32 verts; with door and floor, 96 verts. Cost: grid cells grow as (planes)^3, fine for houses (tens of openings);
a 50-room level would want the KineCAD path or per-room grids (open question 3).

## 4. Phase 1 tools (Easy), exact interactions

All tools: **0.5 m grid snap** (the `grid` param; Alt = free; Shift = lock the current snap), a size label that follows the cursor,
**type a number** while dragging (`4` Tab `3` Enter), Esc cancels, the status line says the tool's one sentence (as in the mockups).
**One undo step per action**, pushed on release / Enter, never during a drag (the drag previews by regenerating the mesh only).

| Tool | Interaction | Record change |
|---|---|---|
| **Room** (R) | Press on the floor = corner A; drag = live box with the walls rising to `wall_height` and "4.0 m x 3.0 m / 12 m2 floor"; release = done. Typing sets w Tab d Enter. A drag under 0.5 m is a click: nothing. Starting on an existing wall's face snaps to it (rooms share walls) | `add_room` |
| **Wall** (W) | Click points on the grid; each click ends a straight wall (thickness / height from params); double-click or Enter ends; clicking the first point closes the loop (= a room) | phase 1b `"walls"` |
| **Pull** (P) | Hover a wall top / a room side face (it highlights); drag along its normal; the number is the move ("+0.5 m"). A wall top changes that room's height (writes a number, leaves the param); a side face moves that side (w / d and x / z); typing = exact. Never opens the solid: it edits the record | room fields |
| **Opening** (O) | A ghost door follows the cursor on the hovered wall, snapped to the grid along it; click = place. Drag an opening to slide it ("snaps to 0.5 m"); Delete removes it and the hole fills; the right panel = its numbers (width, height, sill) as in build_openings.png. A W key (or the panel) switches door / window | `add_opening`, `at`, sizes |
| **Floor** | **+ Floor** adds a storey on top (rooms copied up, openings not); the panel lists the storeys; Delete removes the top one | `"storeys"` (1b) |
| **Roof** | Click = gable over the outline (default); the panel: gable / flat / shed, pitch, overhang | `"roof"` (1b) |
| **Piece** | The prop library (`Props.catalogue()`); drop on a floor (it snaps to floors and wall faces); linked copies come later | `"pieces"` (1b) |
| **Words** | build_words.png: a box; Build it shows a numbered PLAN list (Room 8x6, Floors 2 x 2.8 m, Door front centre 0.9 m, Windows 4, Roof gable 0.45 m), defaults tagged "default: ...", grid rounding said ("8.3 became 8.5"); nothing is built until **Build it**; then "move the door to the left", "make the second floor taller" edit the record. One undo step per Build it / edit | many |
| **Use in a scene** | Big yellow button (enabled when there is a room). Switches to STAGE with the building as the set (section 5) | scene props |

Expert adds (same page, later): Stairs, Guide (tape), Cut (boolean box), Repeat (array), and "Edit as mesh" (opens the generated
KMesh in MODEL; then it is a mesh, not a record: said on the button).

## 5. Use in a scene: on STAGE, with collision for the fighter

1. The building lives in the scene as `S.building` (the record, done). One project file holds the house and the scenes that use it.
2. **Use in a scene** registers a prop kind from the record: `Props.register_building("building:<name>", Building.collision_boxes(b),
   mesh)` (a sibling of `Props.register`, putting the boxes into `EXTRA[kind]["solids"]` in the prop's local frame and the
   floor slab tops into `"supports"`), adds one prop `{"kind": "building:<name>", "xf": identity}` to `S.props`, and goes to STAGE.
   The body's existing queries (`Props.depth`, `rests`, `surface_below`, `solid_cache`, foot plants on props) then work
   unchanged: walls block, the floor holds the feet, **the doorway is open** (the collision is solid cells merged along X; bar 7
   of build_test proves the door gap is in no box).
3. **Linked to BUILD**: the prop stores only the kind; on load and after every BUILD edit the kind is re-registered from the
   record, so the set follows the house. A file with the prop but no record says so (like `props_skipped`).
4. **Anchors** (to_scene mockup): every door yields a named point `"front door"` (the opening's centre at floor level, its
   outward normal), plus a "stand here" spawn; STAGE draws them; ANIMATE's walk cards can target them ("walk through the front
   door"). CHECK adds head clearance at doors (door height minus the fighter's stature) and feet-on-floor.
5. **Export**: the glb export names nodes Godot-style (`walls-col`, `floor-col`; research report section 4) so the house arrives in
   Godot with collision.

## 6. Undo

`main._snapshot()` gains `"building": Building.to_file(S.building)` and `_restore` puts it back and regenerates the preview.
One `_push_undo()` per action: a Room drag's release, a Pull's release, an Opening placed / slid / deleted, a panel number
committed (Enter or focus out, not every spin tick), a words Build it, Use in a scene (with the prop it adds). Every BUILD tool
registers in the command search with its undo name, so `undo_audit_s0..s3` cover it; a param edit is named "Wall height 2.7 -> 3.0 m".

## 7. Phase 2: KineCAD swaps in when the DLL exists

`Building` keeps the record and the API (`to_kmesh`, `collision_boxes`); only the generator changes:

```
static func to_kmesh(b, roles):
    if KCad.available() and not b.get("force_grid", false):
        return _cad_kmesh(b, roles)      # per room: KCad.box walls -> KCad.union -> KCad.cut each opening box (+ fillets,
                                          # arches = cylinder cuts, sloped roofs) -> KCad.tessellate -> KMesh.from_array_mesh
    return _grid_kmesh(b, roles)          # today's exact rectilinear mesher (no DLL: Kine still builds houses)
```

- Same record, same tests: `build_test` runs both paths when the DLL is there and compares volumes (`KCad.volume` vs `_volume`)
  within 0.1%; without it the CAD half SKIPs (as `cad_test` does).
- KineCAD unlocks what the grid cannot: arches and round windows, angled walls joined cleanly (non-equal yaw rooms unioned),
  fillets, true roofs, STEP export (`KCad.export_step`) for real fabrication, and later Fusion-like sketches + constraints
  (Expert, carefully: the research says constraints are the main stumbling block).
- Collision stays boxes from the record (cheap and exact for walls), not from the CAD mesh.

## 8. Blueprints (later)

From the same record (no mesh needed): **plan** (a horizontal section at 1.0 m: walls as filled poly, door swings as arcs,
windows as triple lines, dimensions on the outer walls from the named numbers), **elevations** (front / back / left / right
outlines with openings), **section** (a vertical cut). Output SVG first (pure GDScript), PDF via the existing export path, DXF
(R12 ASCII: LINE / ARC / TEXT, simple to write). With KineCAD: OCCT HLR (hidden line removal) for true elevations of any shape.

## 9. Phases, sizes, suites and bars

| Phase | Size | Contents | Suites and bars |
|---|---|---|---|
| **1a skeleton (this commit)** | S (done) | `scripts/build/building.gd` record + grid mesher + collision boxes + mirror; `scene.gd` "building" key; no UI | `build` (h): 4x3x2.7 room 0.2 walls closed (0 boundary, manifold); wall volume within 1% of 7.128 m3 (measured 0.0000%); 0.9x2.1 door removes exactly 0.378 m3 (1e-6); walls+floor closed; scene round trip identical; named number follows; collision volume = mesh, doorway open; mirror twice = original; newer version kept. Also `mirror_list` (the new key is listed) |
| **1b the page** | M (1-2 wk) | BUILD page in `PAGES`; start card -> BUILD; ground grid, ghost person, grid chip; Room + Opening + Pull with typed numbers; the numbers panel; undo snapshot | `build_ui` (w): real clicks (no direct calls) drag a room 4x3 = record 4x3 and 1 undo step; Ctrl+Z empties it; typed `4 Tab 3 Enter` = the same; door placed on the hovered wall snapped to 0.5 m; slide = 1 step; Delete fills (volume back exactly); Pull +0.5 m on a wall top = height 3.2; 0 script errors; screenshot at 1280x720 vs build_room.png / build_openings.png. `undo_audit_s0..s3`, `pages`, `easyhome` unchanged |
| **1c storeys, roof, walls, pieces** | M | Floor, Roof (gable / flat / shed), Wall polyline, Piece | `build`: 2 storeys closed, volume = sum; gable roof closed, volume = analytic prism; a wall loop closes into a room; `build_ui`: + Floor / Roof clicks, 1 step each |
| **1c + 1d DONE (this branch, w4-build1d)** | M | Floor (`storey`, `floor_height` 2.8 m, a slab between), Roof (gable / flat / shed, `roof_overhang` 0.45 m, one closed convex solid), interior Wall (`walls`, axis + pos from the corner, openings allowed), Pull (room side faces, 0.5 m, live label), Use in a scene (`scripts/build/build_stage.gd`: `Props.register_building`, the named point "front door", the STAGE panel with "Walk through the front door", re-registered after every BUILD edit and on load) | `build` bars 9-13, `buildpage` bars 12-17 (real clicks: + Floor, Roof gable, Wall, Pull, Use in a scene, a walk through the front door: root passes the doorway plane, no foot in a wall box). Piece and Words stay greyed |
| **1d Use in a scene (the plan)** | M | register the building kind, STAGE prop, anchors, re-register on edit, glb `-col` names | `build_stage` (w): after Use in a scene the fighter's foot rests on the floor (`Props.rests`), a hand pushed into a wall has depth > 0, a capsule through the doorway has depth 0; "front door" anchor at the opening; editing the door in BUILD moves the gap on STAGE; `props`, `stage`, `set`, `glb_export` unchanged |
| **1e words** | M | `build_words.gd`: plan list, defaults, grid rounding, edit phrases | `build_words` (h): 20 phrases -> expected plan rows (sizes, counts, defaults tagged); "8.3 m" rounds to 8.5 and says so; unknown words listed back; Build it = 1 step; 5 edit phrases change exactly one field; `meshwords`, `command_search` routing unchanged |
| **2 KineCAD generator** | M-L | `_cad_kmesh`, arches, angled walls, STEP | `build` CAD half (SKIP without DLL): grid vs CAD volume within 0.1%, CAD mesh closed; `cad` unchanged |
| **3 blueprints** | M | plan / elevation / section, SVG / PDF / DXF | `blueprint` (h): the 4x3 room's plan SVG has 4 wall polys with the door gap 0.9 m at 1:50; DXF re-read gives the same lines; dimensions = the named numbers |
| **4 Expert depth** | L | Stairs (ramp collider), Guide, Cut, Repeat, sketches on KineCAD | per tool, the same pattern |

## 10. Open questions for the owner

1. **Grid**: the mockups say both "sizes snap to 0.5 m" (drags) and "numbers snap to 0.1 m" (the panel). Proposed: drags 0.5 m,
   typed numbers and panel steps 0.1 m. OK?
2. **Outer or inner sizes**: a dragged 4 x 3 m room is 4 x 3 m *outside* the walls here (floor inside 3.6 x 2.6). SketchUp users
   expect outer; game makers often think in inner floor size. Keep outer?
3. **Scope**: sets for fights (rooms, arenas, a house; tens of openings) or whole levels? This decides when the KineCAD /
   per-room path must replace the single grid.
