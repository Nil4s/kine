# Kine API digest for agents (read this BEFORE reading source)

Purpose: cut the token cost of challenge lanes (CH16 measured 64% of tool-result cost in file reads). This is the 10% of the API that covers 90% of lanes. Signatures are abbreviated; read the named file only when you need more.
Units: Part records use **mm**; the kernel (KCad) uses **metres** (`MM = 0.001`). Assembly part poses are `pos` (mm) and `rot` (deg). Godot format strings have **no `%g` or `%e`**; use `String.num_scientific`. Vector3/Transform3D are float32; records keep doubles in Arrays/PackedFloat64Array.

## 1. Parts and the CAD kernel
- `Part.make(name) -> Dictionary` (a record); `rec["features"] = [...]`; `rec["seq"] = features.size()`.
- `Part.replay(rec, upto := -1, want := {}) -> Dictionary` — keys include `volume`, `errors`, `mesh`, `ids` (when `want.keep`), `bodies`. Use `{"defer_tess": true}` when you only need solids.
- `Part.release_kept(ids)` frees kept solids. `Part.fine_defl(id)` is the size-scaled mesh deflection (#195). `Part.HIT_VOL` = 1e-9 m³: below it is contact, not interference.
- Primitive feature: `{"t":"prim","id":"f1","kind":"box"|"cylinder"|"tube"|"sphere"|"cone","op":"new"|"cut"|"union","x","y","z","w","h","d" | "r","r_in","len","axis"}`; optional `"into": body_index`.
- `KCad.overlap_volume(a, b) -> float` (m³, -1 if unsupported), `KCad.distance(a, b) -> {"ok","d","pa","pb","pa64","pb64","inner"}` (0 when touching/overlapping), `KCad.bounds(id) -> PackedFloat64Array` (exact box, no tessellation), `KCad.volume(id)`, `KCad.mass_properties(id)`, `KCad.tessellate(id, defl, angle)`.
- Posed-part clash checks: build exact solids once, then transform per pose; prefilter with `KCad.bounds` boxes. See `scripts/build/ch13_parts.gd` `solid()`/`place()` and `tests/ch13_test.gd` bar j.

## 2. Assembly records
`Assembly.make(name)`, `Assembly.built(rec) -> {"mesh","volume",...}`, `Assembly.xf_of(part) -> Transform3D`.
Optional record fields (all backward compatible; old records must save back unchanged):
- `"drives"`: `AssemblyMotion.make_drive(name, part, kind, axis, origin_mm, lo, hi)`; kind `"rotate"` (deg) or `"slide"` (mm). `AssemblyMotion.make_link(drive, part, kind, axis, origin_mm, gain)` makes a follower (gear/rack ratio).
- `"joints"` (#204): `AssemblyLoop.make_joint("revolute"|"slider"|"fixed", a, b, axis, origin, origin_b?, name?)`; `b` may be `"ground"`. Planar only (parallel revolute axes, sliders square to them). The Newton solver reports assembly mode and locks.
- `"anim"` (#205): `{"fps", "length", "tracks":[{"drive", "keys":[[t, value, "linear"|"smooth"|"hold"]]}]}`.
- `"stages"` (#208): `[{"name","parts":[ids],"dur": seconds}]`; parts in no stage are there from the start.
- `"buy"` on a part marks a purchased item for the BOM. `"bom.body_materials"` = `{"1": "pla"}` prices bodies individually (#216).
- `"wires"` (#214): `[{"a","b","kind":"power"|"signal","label"}]`, endpoints are Assembly part ids. Ratings on a part's `rec`: `v`/`kv`, `mva`, `w`, `rail`, `kind` (`bus|grid|transformer|breaker|generator|battery|regulator|ic`), optional `unit`, `powered`. All optional.

## 3. Motion, staging, filming, cost (USE THESE; do not write your own)
- `AssemblyMotion.check_motion(asm, drive_name, steps) -> {"clashes","pairs","kernel_calls","skipped","ms","values","moving"}`; with joints it follows the loop.
- `AssemblyStage.check(asm, opts) ` — support and overlap verdicts; `AssemblyStage.stages/starts/total/fps/frame_count`; `opts {"touch":"overlap"}` is the old slow path.
- `await AssemblyRender.render(host: Node, asm, opts) -> Dictionary` — PNG frames + `sheet.png` + mp4. Opts: `dir`, `width`, `height`, `times`, `camera` (`{"pos","look","fov"}` or `{"xf","fov"}`), `cut` (`{"n": Vector3, "w": metres}`), part subset. Nothing in the record changes.
- `AssemblyBom.bom(asm, prices?) -> {"lines","mass","cost","currency"}`; `AssemblyBom.cheaper(asm)` is the cheapest combination that still passes the record's named check; `AssemblyBom.prices()` reads `data/prices.json` (every entry needs source+date or ASSUMED).
- UI entry points (Assembly panel): **Check motion**, **BOM**, **Stages**, **Export → Video**.

## 4. Drawing and documents
- `scripts/build/blueprint.gd` + `blueprint_view.gd`: Building-record drawings. `scripts/build/ch15_draw.gd`: SVG sheet + title block pattern used by CH15/CH16 (site plan, section, one-line).
- `SectionLook` (`scripts/build/section_look.gd`): section/cutaway rendering; `AssemblyRender` opts `cut` wraps it.
- `AssemblyDraw.sheet(asm, opts)` (`scripts/build/assembly_draw.gd`): exact posed B-rep edge projection -> plan/front/section Blueprint sheet; overall mm from `KCad.bounds`, part labels, BOM mass when present. `opts.cut = {"n":Vector3,"w":metres}` uses SectionLook semantics (`n.p > w` removed); `opts.denom` overrides scale.
- `AssemblyDraw.schematic_sheet(asm)` / `validate_schematic(asm)`: rated IEC-ish blocks + power/signal wires, source-BFS layered layout; missing bus/transformer ratings, unknown endpoints and unpowered blocks are returned and printed on the sheet.
- `await AssemblyDraw.write(host, asm, "drawing"|"schematic", opts) -> {"ok","svg","png","sheet","warnings"}`; opts `dir`, `stem`, `ppm`. UI: Assembly **Export → Sheets → Drawing / Schematic**. No hidden-line removal; not a pin-level editor.

## 5. Characters, hands, mesh
- `Balance.com(body)` (`scripts/balance.gd`): whole-body centre of mass (do not approximate with the pelvis).
- `HandShape.caps(B, hand, fingers := true)`, `HandShape.palm_flat(B, h, contact, normal, opts)`, `HandShape.close_on(B, h, obstacles)`, `HandShape.legacy` for the old capsule.
- Retopo: `KMeshRetopoNet` / `KMeshRetopoFill` / `KineRetopoNative` (Q in the model preview). `net.skipped_regions()` names each skipped region and why.
- Render vs reference: `CompareShot.stats/compare/side_by_side/write` (scripts/build/compare_shot.gd).
- Involute gears: `scripts/build/part_gear.gd`, `clock_ch2.gd involute_outline()`. STL: `scripts/build/mesh_export.gd write_stl`.

## 6. Lane rules that cost money when forgotten
- Test: `WT_MAX=8 bash /c/Users/Nick/tools/kine_workers/wtest.sh <suites>` — ONE blocking command, no polling. Direct: `Godot_v4.7.2-stable_win64_console.exe --headless --path . -s tests/X.gd` (pictures need a window).
- Bars and planted controls are committed BEFORE their first run; never loosen one. `git add` by name only (never `.uid`, `native/bin`).
- Before writing a helper, grep this digest's module; rebuilding an existing tool is a discoverability gap and the most expensive mistake we measure.
- Cache external facts in `docs/CHxx_REFERENCE.md` on first use; prefer search snippets over webfetch.
- When reading a re-rendered screenshot, copy it to a NEW filename first (the image reader caches by path).
