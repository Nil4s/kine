extends SceneTree
## godot --path . --position 4000,4000 -s tests/s228_test.gd     (s228 PATTERNS ALONG PATHS AND GRIDS: Part pattern kinds "grid" and "route"; scripts/build/part_array.gd,
## part_array_ui.gd (Expert Pattern dialog), easy_part_repeat.gd (Grid and Round edge chips); needs a window and the CAD DLL)
## A 4 x 1 x 1 mm bar (the piece) and a path sketch: a 10 x 6 mm rectangle, an R 20 quarter arc. Every bar is measured on the REPLAYED solids (centres, long-axis heading).
##   A1 GRID    4 x 3 x 2 grid in ONE step: 23 copies, every centre exactly on the lattice (0.001 mm)
##   A2 CORNERS rectangle 10 x 6, 2 mm spacing, corners + follow: 16 copies at the exact perimeter places (0.001 mm), headings (0.1 deg), a copy at each of the 4 corners turned 45 deg
##   A3 CURVE   quarter arc R 20, 7 copies fit-to-length: the last on the end (0.01), every copy on the arc (0.01), tangent (0.5 deg), equal arc steps; fit on a line
##   A4 VARY    seeded jitter: same seed = same copies (exact), another seed differs, within the stated size; skip every 3rd leaves the right places empty
##   A5 GROUP   two bars as a group round the rectangle: every copy pair keeps its 4 mm and turns together
##   A6 FILE    the record through JSON text replays to the same copies
##   E* EXPERT  real clicks in the Pattern dialog: Along a path (rect, corners, follow): one undo step; Grid 4 x 3 x 2; undo / redo / save / reload
##   Z* EASY    Repeat it > Round edge (a bracket on a slab goes round the slab's edge, a copy at every corner), Repeat it > Grid
##   H* HALL    the hall's bracket band round its corners and a tile row along an eave (screenshots)
## Shots: C:/Users/Nick/tools/kine_workers/out/228/*.png
const KCad := preload("res://scripts/kcad.gd")
var fails := 0
var m: Node
const SHOT := "C:/Users/Nick/tools/kine_workers/out/228"
const DIRT := "user://s228_test"
const HALF_L := 2.0
const HALF_W := 0.5
const RECT := [{"k": "line", "a": [0, 0], "b": [10, 0]}, {"k": "line", "a": [10, 0], "b": [10, 6]}, {"k": "line", "a": [10, 6], "b": [0, 6]}, {"k": "line", "a": [0, 6], "b": [0, 0]}]


## a record: the bar (top plane, centre at (cx, cy) in the plane mm, 1 mm up) and the path sketch f3 (and a second bar 4 mm further when two is true)
func bar_rec(path_ents: Array, cx := 5.0, cy := 0.0, two := false) -> Dictionary:
	var r := Part.make("t")
	var fs := [
		{"t": "sketch", "id": "f1", "name": "S1", "plane": "top", "ents": [{"k": "rect", "a": [cx - HALF_L, cy - HALF_W], "b": [cx + HALF_L, cy + HALF_W]}], "dims": []},
		{"t": "extrude", "id": "f2", "name": "E1", "sketch": "f1", "dist": 1.0, "both": false, "op": "new"}]
	if two:
		fs.append({"t": "sketch", "id": "f4", "name": "S4", "plane": "top", "ents": [{"k": "rect", "a": [cx - HALF_L, cy + 4.0 - HALF_W], "b": [cx + HALF_L, cy + 4.0 + HALF_W]}], "dims": []})
		fs.append({"t": "extrude", "id": "f5", "name": "E2", "sketch": "f4", "dist": 1.0, "both": false, "op": "new"})
	fs.append({"t": "sketch", "id": "f3", "name": "S3", "plane": "top", "ents": path_ents, "dims": []})
	r["features"] = fs
	r["seq"] = 5
	return r


func with_pattern(r: Dictionary, fields: Dictionary) -> Dictionary:
	var rc: Dictionary = JSON.parse_string(JSON.stringify(r))
	var f := Part.new_feature(rc, "pattern", fields)
	rc["features"].append(f)
	return rc


## replay: the bodies' centres (mm), long-axis headings (deg mod 180) and volumes
func measure(r: Dictionary) -> Dictionary:
	var res := Part.replay(r, -1, {"keep": true, "props": true})
	var ids: Array = res.get("ids", [])
	var props: Array = res.get("props", [])
	var cs: Array = []
	var hs: Array = []
	var vs: Array = []
	for i in ids.size():
		var c: Vector3 = props[i]["center"]
		cs.append(c * 1000.0)
		vs.append(float(props[i]["volume"]))
		hs.append(heading(int(ids[i])))
	for b in ids:
		KCad.release(int(b))
	return {"c": cs, "h": hs, "v": vs, "errors": res["errors"], "bodies": int(res["bodies"]), "volume": float(res["volume"])}


## the long axis of a body in the floor plane, deg mod 180, in the path sketch's angle (x, -z)
func heading(id: int) -> float:
	var seen := {}
	var pts := PackedVector3Array()
	for q in Part._tris_of(id):
		var key := "%.5f,%.5f" % [q.x * 1000.0, q.z * 1000.0]   # each corner once (a box's triangles repeat corners unevenly)
		if not seen.has(key):
			seen[key] = true
			pts.append(q)
	var mean := Vector2.ZERO
	for q in pts:
		mean += Vector2(q.x, -q.z)
	mean /= maxf(float(pts.size()), 1.0)
	var sxx := 0.0
	var syy := 0.0
	var sxy := 0.0
	for q in pts:
		var d := Vector2(q.x, -q.z) - mean
		sxx += d.x * d.x
		syy += d.y * d.y
		sxy += d.x * d.y
	return fposmod(rad_to_deg(0.5 * atan2(2.0 * sxy, sxx - syy)), 180.0)


## the difference of two headings as lines (deg, 0..90)
func hdiff(a: float, b: float) -> float:
	return absf(fposmod(a - b + 90.0, 180.0) - 90.0)


func plan(c: Vector3) -> Vector2:
	return Vector2(c.x, -c.z)


## the rectangle audit (bar at (5,0) on side 1; corners + follow; 2 mm): 1 + 16 bodies. The copies run along the perimeter: s = 2 k, corners at k = 0, 5, 8, 13.
## Returns "" or what is wrong
func corners_audit(me: Dictionary) -> String:
	var cs: Array = me["c"]
	var hs: Array = me["h"]
	if int(me["bodies"]) != 17 or cs.size() != 17 or not (me["errors"] as Dictionary).is_empty():
		return "%d bodies, errors %s" % [int(me["bodies"]), str(me["errors"])]
	var P := [Vector2(0, 0), Vector2(10, 0), Vector2(10, 6), Vector2(0, 6)]
	var Ls := [10.0, 6.0, 10.0, 6.0]
	var corner_in := {0: 3, 5: 0, 8: 1, 13: 2}   # k -> the side that ends at that corner
	var worst_p := 0.0
	var worst_h := 0.0
	var worst_c := 0.0
	var worst_step := 0.0
	var hits := 0
	for k in 16:
		var s := 2.0 * k
		var acc := 0.0
		var side := 3
		for i in 4:
			if s < acc + Ls[i] - 1e-9:
				side = i
				break
			acc += Ls[i]
		var d: Vector2 = (P[(side + 1) % 4] - P[side]).normalized()
		var want: Vector2 = P[side] + d * (s - acc)
		worst_p = maxf(worst_p, plan(cs[1 + k]).distance_to(want))
		var hd := rad_to_deg(d.angle())
		if corner_in.has(k):
			var sin_i: int = corner_in[k]
			var tin := rad_to_deg((P[(sin_i + 1) % 4] - P[sin_i]).normalized().angle())
			hd = tin + 45.0
			hits += 1
			worst_c = maxf(worst_c, absf(hdiff(float(hs[1 + k]), tin) - 45.0))
		worst_h = maxf(worst_h, hdiff(float(hs[1 + k]), hd))
		if k > 0 and not corner_in.has(k) and not corner_in.has(k - 1):
			worst_step = maxf(worst_step, absf(plan(cs[1 + k]).distance_to(plan(cs[k])) - 2.0))
	if worst_p > 0.001:
		return "a copy is %.4f mm off its place" % worst_p
	if worst_h > 0.1:
		return "a copy is turned %.3f deg off" % worst_h
	if hits != 4 or worst_c > 0.1:
		return "corner copies: %d, worst turn error %.3f deg" % [hits, worst_c]
	if worst_step > 0.001:
		return "a straight step is %.4f mm off 2" % worst_step
	return ""


## slab 100 x 60 x 10 (top plane, up from y = 0) with a bracket 8 x 6 x 4 standing on its top face at the right edge (centre 2 mm in from the edge, overhanging 2 mm)
func slab_rec() -> Dictionary:
	var r := Part.make("slab")
	r["features"] = [
		{"t": "sketch", "id": "f1", "name": "S1", "plane": "top", "ents": [{"k": "rect", "a": [-50, -30], "b": [50, 30]}], "dims": []},
		{"t": "extrude", "id": "f2", "name": "E1", "sketch": "f1", "dist": 10.0, "both": false, "op": "new"},
		{"t": "plane", "id": "f3", "name": "P1", "from": "top", "mm": 10.0},
		{"t": "sketch", "id": "f4", "name": "S2", "plane": "f3", "ents": [{"k": "rect", "a": [44, -3], "b": [52, 3]}], "dims": []},
		{"t": "extrude", "id": "f5", "name": "E2", "sketch": "f4", "dist": 4.0, "both": false, "op": "join"}]
	r["seq"] = 5
	return r


## the hall: a band slab 300 x 40 x 200 (mm) with a corbel bracket on its back edge, patterned round the band's outline (corners + follow, 40 mm),
## and a roof slab 400 x 12 x 260 with a row of tiles along its back eave (fit, 12 tiles)
func hall_rec(roof := true) -> Dictionary:
	var r := Part.make("hall")
	r["features"] = [
		{"t": "sketch", "id": "f1", "name": "Band", "plane": "top", "ents": [{"k": "rect", "a": [-150, -100], "b": [150, 100]}], "dims": []},
		{"t": "extrude", "id": "f2", "name": "Band", "sketch": "f1", "dist": 40.0, "both": false, "op": "new"},
		{"t": "plane", "id": "f3", "name": "P1", "from": "top", "mm": 40.0},
		{"t": "sketch", "id": "f4", "name": "Bracket", "plane": "f3", "ents": [{"k": "rect", "a": [-10, 94], "b": [10, 112]}], "dims": []},
		{"t": "extrude", "id": "f5", "name": "Bracket", "sketch": "f4", "dist": 22.0, "both": false, "op": "new"},
		{"t": "plane", "id": "f6", "name": "P2", "from": "top", "mm": 70.0},
		{"t": "sketch", "id": "f7", "name": "Roof", "plane": "f6", "ents": [{"k": "rect", "a": [-200, -130], "b": [200, 130]}], "dims": []},
		{"t": "extrude", "id": "f8", "name": "Roof", "sketch": "f7", "dist": 12.0, "both": false, "op": "new"},
		{"t": "plane", "id": "f9", "name": "P3", "from": "top", "mm": 82.0},
		{"t": "sketch", "id": "f10", "name": "Tile", "plane": "f9", "ents": [{"k": "rect", "a": [-190, 112], "b": [-176, 128]}], "dims": []},
		{"t": "extrude", "id": "f11", "name": "Tile", "sketch": "f10", "dist": 8.0, "both": false, "op": "new"},
		{"t": "sketch", "id": "f12", "name": "Eave line", "plane": "f9", "ents": [{"k": "line", "a": [-183, 120], "b": [183, 120]}], "dims": []}]
	r["seq"] = 12
	if not roof:   # the band and its brackets only: the roof stands over them in the full hall
		r["features"] = (r["features"] as Array).slice(0, 5)
	var fp: Array = Part.PartArray.footprint_pts(r, 0, 0.0)["pts"]
	r["features"].append(Part.new_feature(r, "pattern", {"kind": "route", "body": 1, "op": "new", "pts": fp, "closed": true, "mm": 40.0, "corners": true, "follow": true, "hold": true, "count": 0}))
	if not roof:
		return r
	r["features"].append(Part.new_feature(r, "pattern", {"kind": "route", "body": 3, "op": "new", "path": "f12", "mm": 0.0, "count": 12, "fit": true, "follow": true, "hold": true}))
	return r


## the record k times bigger (every length), for the screenshots: the camera cannot come close enough to a 10 mm part
func scale_rec(r: Dictionary, k: float) -> Dictionary:
	var rc: Dictionary = JSON.parse_string(JSON.stringify(r))
	for f in rc["features"]:
		for key in ["dist", "mm", "mm2", "mm3", "fgrow", "jit"]:
			if f.has(key):
				f[key] = float(f[key]) * k
		for e in f.get("ents", []):
			for key in ["a", "b", "c", "m"]:
				if e.has(key):
					e[key] = [float(e[key][0]) * k, float(e[key][1]) * k]
			if e.has("r"):
				e["r"] = float(e["r"]) * k
		if f.has("pts"):
			var np := []
			for q in f["pts"]:
				np.append([float(q[0]) * k, float(q[1]) * k, float(q[2]) * k])
			f["pts"] = np
	return rc


## the camera at distance d with the world point c0 on screen at px (the clear part of the Easy screen is its right side)
func place_view(c0: Vector3, px: Vector2, d: float) -> void:
	m.dist = d
	m._cam()
	await idle(6)
	for it in 5:
		var p: Vector2 = m.cam.unproject_position(c0)
		var bx: Vector3 = m.cam.global_transform.basis.x
		var by: Vector3 = m.cam.global_transform.basis.y
		var q: Vector2 = m.cam.unproject_position(c0 + bx * 0.1)
		var sc := maxf(absf(q.x - p.x), 1.0) / 0.1
		m.target -= bx * ((px.x - p.x) / sc) + by * (-(px.y - p.y) / sc)
		m._cam()
		await idle(6)
	await idle(20)


## the browser bar: rows = the Button rows under the panel; bad = rows that stick out of the panel's rect and are not clipped away
## (a clipping ancestor, a ScrollContainer, hides what is outside it; a plain panel does not)
func browser_check(panel: Control, tl: Control) -> Dictionary:
	var pr := panel.get_global_rect()
	var rows := 0
	var bad := 0
	var hidden := 0
	var stack: Array = [panel]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for c in n.get_children():
			stack.append(c)
		if n is Button:
			rows += 1
			var r := (n as Control).get_global_rect()
			var clipped := panel is PanelContainer and (panel as Control).clip_contents and panel.get_node_or_null("part_browser_scroll") != null
			if pr.encloses(r):
				continue
			if clipped:
				if not pr.intersects(r):
					hidden += 1
				elif not pr.grow(0.5).encloses(r):
					# partly cut by the scroll box edge: drawn clipped, inside the panel
					pass
				continue
			bad += 1
	return {"rows": rows, "bad": bad, "hidden": hidden, "bottom": pr.end.y, "tl_top": tl.get_global_rect().position.y, "above": pr.end.y <= tl.get_global_rect().position.y}


func _init() -> void:
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(8)
	m.tour_step = -1
	if m.ui_tour != null:
		m.ui_tour.visible = false
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	root.content_scale_size = Vector2i(1280, 720)
	await idle(4)
	var ss: StartScreen = m.start_screen
	var bld: BuildUI = m.bld
	var pu: PartUI = bld.part
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIRT))
	DirAccess.make_dir_recursive_absolute(SHOT)
	ss.dirs_override = [DIRT]
	if not Part.available():
		print("FAIL: no KineCAD DLL, s228 needs the kernel")
		print("s228: 1 fail")
		quit(1)
		return

	# ---------------- A1 GRID: 4 columns x 3 rows x 2 layers
	var g := with_pattern(bar_rec(RECT, 0.0, 0.0), {"kind": "grid", "body": 0, "op": "new", "count": 4, "mm": 7.0, "dir": "x", "rows": 3, "mm2": 5.0, "dir2": "z", "layers": 2, "mm3": 3.0, "dir3": "y"})
	var mg := measure(g)
	var worst := 0.0
	var seen := {}
	for i in range(1, mg["c"].size()):
		var d: Vector3 = (mg["c"][i] as Vector3) - (mg["c"][0] as Vector3)
		var dx := d.x / 7.0
		var dz := d.z / 5.0
		var dy := d.y / 3.0
		worst = maxf(worst, maxf(absf(dx - roundf(dx)) * 7.0, maxf(absf(dz - roundf(dz)) * 5.0, absf(dy - roundf(dy)) * 3.0)))
		seen["%d,%d,%d" % [int(roundf(dx)), int(roundf(dz)), int(roundf(dy))]] = true
	ok(int(mg["bodies"]) == 24 and (mg["errors"] as Dictionary).is_empty(), "A1 4 x 3 x 2 grid in ONE step: %d bodies (want 24), no failed step" % int(mg["bodies"]))
	ok(seen.size() == 23 and worst < 0.001, "A1 23 distinct lattice places, every centre within %.5f mm of the lattice (spacing 7 / 5 / 3 mm exact)" % worst)
	var gv := true
	for i in mg["v"].size():
		gv = gv and absf(float(mg["v"][i]) - 4e-9) < 1e-12
	ok(gv, "A1 every copy has the bar's volume (4 mm3)")

	# ---------------- A2 CORNERS: rectangle 10 x 6, 2 mm, corners + follow
	var rr := with_pattern(bar_rec(RECT, 5.0, 0.0), {"kind": "route", "body": 0, "op": "new", "path": "f3", "mm": 2.0, "corners": true, "follow": true, "count": 0})
	var mr := measure(rr)
	var why := corners_audit(mr)
	ok(why == "", "A2 rectangle 10 x 6, 2 mm: 16 copies at the exact places, a copy at each of the 4 corners turned 45 deg (+-0.1), straights 2.000 apart [%s]" % why)

	# ---------------- A3 CURVE: quarter arc R 20 centre (0, 20), fit 7
	var arc := [{"k": "arc", "a": [0, 0], "m": [20.0 * sin(deg_to_rad(45.0)), 20.0 - 20.0 * cos(deg_to_rad(45.0))], "b": [20, 20]}]
	var ma := measure(with_pattern(bar_rec(arc, 0.0, 0.0), {"kind": "route", "body": 0, "op": "new", "path": "f3", "count": 7, "fit": true, "follow": true, "mm": 0.0}))
	var on_worst := 0.0
	var tan_worst := 0.0
	var step_w := 0.0
	var prev_phi := -90.0
	for k in range(1, ma["c"].size()):
		var p := plan(ma["c"][k])
		on_worst = maxf(on_worst, absf(p.distance_to(Vector2(0, 20)) - 20.0))
		var phi := rad_to_deg(atan2(p.y - 20.0, p.x))
		tan_worst = maxf(tan_worst, hdiff(float(ma["h"][k]), phi + 90.0))
		step_w = maxf(step_w, absf((phi - prev_phi) - 15.0))
		prev_phi = phi
	var last := plan(ma["c"][ma["c"].size() - 1])
	ok(int(ma["bodies"]) == 7 and (ma["errors"] as Dictionary).is_empty(), "A3 fit 7 on the arc: %d bodies (the original is the first), no failed step" % int(ma["bodies"]))
	ok(last.distance_to(Vector2(20, 20)) < 0.01, "A3 fit-to-length: the last copy is on the arc's end (%.5f mm off)" % last.distance_to(Vector2(20, 20)))
	ok(on_worst < 0.01, "A3 every copy is on the curve (worst %.5f mm)" % on_worst)
	ok(tan_worst < 0.5, "A3 every copy's tangent matches the curve +-0.5 deg (worst %.4f deg)" % tan_worst)
	ok(step_w < 0.05, "A3 the 6 steps are equal along the arc, 15 deg each (worst error %.4f deg)" % step_w)
	var ml := measure(with_pattern(bar_rec([{"k": "line", "a": [0, 0], "b": [10, 0]}], 0.0, 0.0), {"kind": "route", "body": 0, "op": "new", "path": "f3", "count": 0, "fit": true, "mm": 1.5, "follow": true}))
	var lx: float = (ml["c"][ml["c"].size() - 1] as Vector3).x
	var stl := 0.0
	for k in range(2, ml["c"].size()):
		stl = maxf(stl, absf((ml["c"][k] as Vector3).x - (ml["c"][k - 1] as Vector3).x - 10.0 / 7.0))
	ok(ml["c"].size() == 8 and absf(lx - 10.0) < 0.01 and stl < 0.001, "A3 fit on a 10 mm line (1.5 asked): %d places, the last at x = %.5f (want 10 +-0.01), steps %.5f off 10/7" % [ml["c"].size(), lx, stl])

	# ---------------- A4 VARY
	var jf := {"kind": "route", "body": 0, "op": "new", "path": "f3", "mm": 2.0, "corners": true, "follow": true, "count": 0, "seed": 7, "jit": 0.5, "jit_turn": 10.0}
	var j1 := measure(with_pattern(bar_rec(RECT, 5.0, 0.0), jf))
	var j2 := measure(with_pattern(bar_rec(RECT, 5.0, 0.0), jf))
	var jf8: Dictionary = jf.duplicate()
	jf8["seed"] = 8
	var j3 := measure(with_pattern(bar_rec(RECT, 5.0, 0.0), jf8))
	var same: bool = j1["c"].size() == j2["c"].size() and j1["c"].size() == 17
	var diff_seed := 0.0
	var max_off := 0.0
	var max_turn := 0.0
	for i in mini(j1["c"].size(), mr["c"].size()):
		same = same and (j1["c"][i] as Vector3) == (j2["c"][i] as Vector3) and float(j1["h"][i]) == float(j2["h"][i])
		diff_seed = maxf(diff_seed, (j1["c"][i] as Vector3).distance_to(j3["c"][i]))
		if i > 0:
			max_off = maxf(max_off, plan(j1["c"][i]).distance_to(plan(mr["c"][i])))
			max_turn = maxf(max_turn, hdiff(float(j1["h"][i]), float(mr["h"][i])))
	ok(same, "A4 jitter is deterministic: the same seed gives the SAME 17 bodies (centres and headings equal bit for bit)")
	ok(diff_seed > 0.05, "A4 another seed gives other places (largest difference %.3f mm)" % diff_seed)
	ok(max_off <= 0.5 * sqrt(2.0) + 0.001 and max_off > 0.05 and max_turn <= 10.1, "A4 jitter stays inside its size: places %.3f mm (<= 0.707) and turns %.2f deg (<= 10) from the clean copies" % [max_off, max_turn])
	var sk := measure(with_pattern(bar_rec(RECT, 5.0, 0.0), {"kind": "grid", "body": 0, "op": "new", "count": 7, "mm": 6.0, "dir": "x", "skip": 3}))
	var xs := []
	for i in sk["c"].size():
		xs.append(snappedf(((sk["c"][i] as Vector3).x - (sk["c"][0] as Vector3).x) / 6.0, 0.001))
	ok(xs == [0.0, 1.0, 3.0, 4.0, 6.0], "A4 skip every 3rd of a row of 7: places %s (want 0 1 3 4 6: the 3rd and 6th are left empty, the original stays)" % str(xs))

	# ---------------- A5 GROUP: two bars 4 mm apart round the rectangle, as a group
	var mgp := measure(with_pattern(bar_rec(RECT, 0.0, 1.0, true), {"kind": "route", "body": 0, "bodies": [0, 1], "op": "new", "path": "f3", "mm": 2.0, "corners": true, "follow": true, "count": 0}))
	var ncp: int = (mgp["c"].size() - 2) / 2
	var pair_w := 0.0
	var turn_w := 0.0
	for k in ncp:
		pair_w = maxf(pair_w, absf(plan(mgp["c"][2 + k]).distance_to(plan(mgp["c"][2 + ncp + k])) - 4.0))
		turn_w = maxf(turn_w, hdiff(float(mgp["h"][2 + k]), float(mgp["h"][2 + ncp + k])))
	ok(ncp == 16 and (mgp["errors"] as Dictionary).is_empty(), "A5 a group of 2 round the rectangle in one step: %d bodies (2 + 2 x 16 copies), no failed step" % mgp["c"].size())
	ok(pair_w < 0.001 and turn_w < 0.01, "A5 the group moves as one: every pair of copies keeps its 4 mm (worst %.5f) and turns together (worst %.4f deg)" % [pair_w, turn_w])

	# ---------------- A6 FILE text + a missing path
	var back: Dictionary = JSON.parse_string(JSON.stringify(rr))
	ok(corners_audit(measure(back)) == "", "A6 the record as JSON text replays to the same 16 copies")
	var errs := Part.replay(with_pattern(bar_rec(RECT, 5.0, 0.0), {"kind": "route", "body": 0, "op": "new", "path": "nope", "mm": 2.0}), -1)["errors"] as Dictionary
	ok(not errs.is_empty(), "A6 a missing path is a plain failed step, not a crash: %s" % str(errs.values()))

	# ---------------- E EXPERT: the real dialog
	ss.show_screen()
	await idle(3)
	await click_ctl(ss._cards["building"])
	if m.ui_save_ask != null and m.ui_save_ask.visible:
		m._save_ask_choose("discard")
	await idle(6)
	pu.set_on(false)
	pu.m.S.part = {}
	await process_frame
	await click_ctl(pu.part_btn)
	await idle(3)
	if pu.easy:
		pu.easy = false
	m.S.part = bar_rec(RECT, 5.0, 0.0)
	bld.sync()
	m.target = Vector3(0.005, 0.0, -0.003)
	m.dist = 0.03
	m.pitch = -70.0
	m.yaw = 0.0
	m._cam()
	await idle(30)
	var path := DIRT + "/s228.json"
	var n0: int = m.undo.size()
	await press_tool(pu, "Pattern")
	ok(String(pu.dlg.get("t", "")) == "pattern", "E1 Pattern opens its dialog")
	var ko: OptionButton = pu.pat["kind"]
	ok(ko.item_count == 4, "E1 the kind list has %d entries (Linear, Circular, Grid, Along a path)" % ko.item_count)
	ko.select(3)
	ko.item_selected.emit(3)
	await idle(2)
	ok((pu.pat["r_path"] as Control).is_visible_in_tree() and not (pu.pat["mm"] as Control).is_visible_in_tree(), "E1 Along a path shows the path rows and hides the Linear rows")
	await typed(pu.pat["r_mm"], "2")
	var cbx: CheckBox = pu.pat["r_corners"]
	await click_ctl(cbx)
	var fbx: CheckBox = pu.pat["r_follow"]
	await click_ctl(fbx)
	(pu.pat["op"] as OptionButton).select(1)
	(pu.pat["op"] as OptionButton).item_selected.emit(1)
	await idle(3)
	ok(cbx.button_pressed and fbx.button_pressed and int(pu.prev.get("bodies", 0)) == 17, "E2 corners and follow ticked by clicks: the preview says %s bodies (want 17); dialog: %s" % [str(pu.prev.get("bodies", 0)), pu.dlg_info.text])
	await shot("expert_dialog")
	await click_ctl(pu.ok_btn)
	await idle(3)
	var pf := {}
	for f in m.S.part["features"]:
		if String(f["t"]) == "pattern":
			pf = f
	ok(m.undo.size() == n0 + 1 and String(pf.get("kind", "")) == "route" and String(pf.get("path", "")) == "f3", "E3 OK = ONE undo step (%d) and ONE route step on the path sketch" % (m.undo.size() - n0))
	var ewhy := corners_audit(measure(m.S.part))
	ok(ewhy == "", "E4 the dialog's result passes the rectangle audit: 16 copies exact, 4 corners at 45 deg [%s]" % ewhy)
	var rec_after := JSON.stringify(m.S.part)
	var keep: Dictionary = m.S.part
	m.S.part = scale_rec(keep, 10.0)   # the same part ten times bigger, to look at
	bld.sync()
	m.target = Vector3(0.05, 0.0, -0.03)
	m.dist = 0.6
	m.pitch = -62.0
	m.yaw = 10.0
	m._cam()
	await idle(30)
	await shot("expert_route")
	m.S.part = keep
	bld.sync()
	await idle(4)
	m._undo()
	await idle(4)
	ok(int(Part.replay(m.S.part)["bodies"]) == 1 and m.undo.size() == n0, "E5 one Undo: 1 body, no pattern step")
	m._redo()
	await idle(4)
	ok(JSON.stringify(m.S.part) == rec_after and corners_audit(measure(m.S.part)) == "", "E5 Redo gives the same record and the same 16 copies")
	await save_reload(path, rec_after, bld)
	ok(JSON.stringify(JSON.parse_string(JSON.stringify(m.S.part))) == JSON.stringify(JSON.parse_string(rec_after)) and corners_audit(measure(m.S.part)) == "", "E6 saved, new scene, reloaded: the same record, the same 16 copies")
	m.S.part = bar_rec(RECT, 5.0, 0.0)   # a reload has no undo history: start the Grid from the plain bar
	bld.sync()
	await idle(4)
	var n1: int = m.undo.size()
	await press_tool(pu, "Pattern")
	var ko2: OptionButton = pu.pat["kind"]
	ko2.select(2)
	ko2.item_selected.emit(2)
	await idle(2)
	await typed(pu.pat["g_cols"], "4")
	await typed(pu.pat["g_cols_mm"], "7")
	await typed(pu.pat["g_rows"], "3")
	await typed(pu.pat["g_rows_mm"], "5")
	await typed(pu.pat["g_layers"], "2")
	await typed(pu.pat["g_layers_mm"], "3")
	(pu.pat["op"] as OptionButton).select(1)
	(pu.pat["op"] as OptionButton).item_selected.emit(1)
	await idle(3)
	ok(int(pu.prev.get("bodies", 0)) == 24, "E7 Grid 4 x 3 x 2: the preview says %s bodies (want 24); dialog: %s" % [str(pu.prev.get("bodies", 0)), pu.dlg_info.text])
	await click_ctl(pu.ok_btn)
	await idle(3)
	var mg2 := measure(m.S.part)
	var gw := 0.0
	for i in range(1, mg2["c"].size()):
		var d2: Vector3 = (mg2["c"][i] as Vector3) - (mg2["c"][0] as Vector3)
		gw = maxf(gw, maxf(absf(d2.x / 7.0 - roundf(d2.x / 7.0)) * 7.0, maxf(absf(d2.z / 5.0 - roundf(d2.z / 5.0)) * 5.0, absf(d2.y / 3.0 - roundf(d2.y / 3.0)) * 3.0)))
	ok(m.undo.size() == n1 + 1 and int(mg2["bodies"]) == 24 and gw < 0.001, "E8 OK: ONE undo step, 24 bodies, every centre on the 7 x 5 x 3 mm lattice (worst %.5f mm)" % gw)
	var keep2: Dictionary = m.S.part
	m.S.part = scale_rec(keep2, 10.0)
	bld.sync()
	m.target = Vector3(0.12, 0.02, 0.0)
	m.dist = 0.9
	m.pitch = -35.0
	m.yaw = 25.0
	m._cam()
	await idle(30)
	await shot("expert_grid")
	m.S.part = keep2
	bld.sync()
	await idle(4)
	m._undo()
	await idle(4)

	# ---------------- Z EASY: a slab with a bracket on its right edge; Repeat it > Round edge / Grid
	pu.set_on(false)
	m.S.part = {}
	await process_frame
	await click_ctl(pu.part_btn)
	await click_ctl(pu.easy_open_btn)
	await idle(4)
	var ep = pu.ep
	m.S.part = slab_rec()
	pu.upto = -1
	pu.sync()
	m.target = Vector3(0.0, 0.01, 0.0)
	m.dist = 0.5
	m.pitch = -45.0
	m.yaw = 20.0
	m._cam()
	await idle(30)
	ok(pu.easy and int(Part.replay(m.S.part)["bodies"]) == 1, "Z0 Easy Part with the slab and its bracket (1 body)")
	var u1: int = m.undo.size()
	await click_ctl(ep.make_btns["repeat"])
	u1 = m.undo.size()
	ok(ep.rep_btns["grid"].is_visible_in_tree() and ep.rep_btns["route"].is_visible_in_tree(), "Z1 the Repeat it box shows the Grid and Round edge chips")
	await click_ctl(ep.rep_btns["route"])
	var u2: int = m.undo.size()
	var zf := {}
	for f in m.S.part["features"]:
		if String(f["t"]) == "pattern":
			zf = f
	ok(u2 == u1 + 1 and String(zf.get("kind", "")) == "route" and bool(zf.get("corners", false)), "Z2 Round edge is ONE undo step (%d -> %d) and the step is a route with corners (kind %s)" % [u1, u2, String(zf.get("kind", ""))])
	var piece_v := 8.0 * 6.0 * 4.0
	var slab_v := 100.0 * 60.0 * 10.0
	var zr := Part.replay(m.S.part)
	ok((zr["errors"] as Dictionary).is_empty() and absf(float(zr["volume"]) * 1e9 - (slab_v + 19.0 * piece_v)) < 0.5, "Z3 the volume is the slab plus 19 brackets (the first + 18 copies): %.2f mm3 (want %.2f)" % [float(zr["volume"]) * 1e9, slab_v + 19.0 * piece_v])
	var zrec: Dictionary = JSON.parse_string(JSON.stringify(m.S.part))   # the same step with each copy a body of its own, to measure the places
	for f in zrec["features"]:
		if String(f["t"]) == "pattern":
			f["op"] = "new"
	var zm := measure(zrec)
	var runs := [6, 3, 6, 3]
	var corner_err := 0.0
	var corner_turn := 0.0
	var in_err := 0.0
	var step_err := 0.0
	var k0 := 1
	var corners2d := [Vector2(-50, -30), Vector2(50, -30), Vector2(50, 30), Vector2(-50, 30)]
	for r in 4:
		var side_len: float = [100.0, 60.0, 100.0, 60.0][r]
		for j in int(runs[r]):
			var cc := plan(zm["c"][k0 + j])
			if j == 0:
				corner_err = maxf(corner_err, absf(cc.distance_to(corners2d[r]) - 2.0))
				corner_turn = maxf(corner_turn, absf(hdiff(float(zm["h"][k0]), [0.0, 90.0, 180.0, 270.0][(r + 3) % 4] - 90.0) - 45.0))
			elif j >= 2:   # the copy beside a corner copy is not a straight step (the corner copy sits turned, 2 mm in)
				var dd := cc - plan(zm["c"][k0 + j - 1])
				step_err = maxf(step_err, absf(dd.length() - side_len / float(runs[r])))
				var edge_d: float = [absf(cc.y + 30.0), absf(cc.x - 50.0), absf(cc.y - 30.0), absf(cc.x + 50.0)][r]
				in_err = maxf(in_err, absf(edge_d - 2.0))
		k0 += int(runs[r])
	ok(zm["c"].size() == 19 and corner_err < 0.01 and corner_turn < 0.1, "Z4 a copy at each of the 4 corners (2.000 mm in from the corner, worst error %.5f), turned 45 deg (+-0.1: worst %.4f deg); %d bodies" % [corner_err, corner_turn, zm["c"].size()])
	ok(step_err < 0.001 and in_err < 0.001, "Z5 spacing on the straights exact (worst error %.5f mm: 100 / 6, 60 / 3) and every copy keeps its 2 mm from the edge (worst error %.5f)" % [step_err, in_err])
	ep._view_press("3q")   # the view chips; then the part is moved into the clear part of the screen (right of the Repeat it box)
	await idle(40)
	await place_view(Vector3(0.0, 0.01, 0.0), Vector2(1150, 580), 0.8)
	await shot("easy_round_edge")
	ep._view_press("top")
	await idle(40)
	await place_view(Vector3(0.0, 0.01, 0.0), Vector2(1150, 580), 0.8)
	await shot("easy_round_edge_top")
	var u3: int = m.undo.size()
	await click_ctl(ep.rep_btns["grid"])
	var zg := {}
	for f in m.S.part["features"]:
		if String(f["t"]) == "pattern":
			zg = f
	ok(m.undo.size() == u3 + 1 and String(zg.get("kind", "")) == "grid" and (zg.get("rows", 0) as int) == 3, "Z6 Grid is ONE undo step and the step is a grid (cols %s, rows %s)" % [str(zg.get("count", "")), str(zg.get("rows", ""))])
	var zgrec: Dictionary = JSON.parse_string(JSON.stringify(m.S.part))
	for f in zgrec["features"]:
		if String(f["t"]) == "pattern":
			f["op"] = "new"
	var zgm := measure(zgrec)
	var cols := int(zg.get("count", 0))
	var rows := int(zg.get("rows", 0))
	var lat := 0.0
	var sx := float(zg.get("mm", 1.0))
	var sz := float(zg.get("mm2", 1.0))
	for i in range(2, zgm["c"].size()):
		var d3: Vector3 = (zgm["c"][i] as Vector3) - (zgm["c"][1] as Vector3)
		lat = maxf(lat, minf(absf(d3.x / sx - roundf(d3.x / sx)) * sx, 99.0))
		lat = maxf(lat, absf(d3.z / sz - roundf(d3.z / sz)) * sz)
	ok((zgm["errors"] as Dictionary).is_empty() and zgm["c"].size() == cols * rows and lat < 0.001, "Z7 the grid is %d x %d places (%d bodies), spacing %.1f x %.1f mm exact (worst lattice error %.5f)" % [cols, rows, zgm["c"].size(), sx, sz, lat])
	ep._view_press("3q")
	await idle(40)
	await place_view(Vector3(0.0, 0.01, 0.0), Vector2(1150, 580), 0.8)
	await shot("easy_grid")
	m._undo()
	await idle(3)
	m._undo()
	await idle(3)
	var zn := 0
	for f in m.S.part["features"]:
		if String(f["t"]) == "pattern":
			zn += 1
	var zk := ""
	for f in m.S.part["features"]:
		if String(f["t"]) == "pattern":
			zk = String(f.get("kind", ""))
	ok(zn == 1 and zk == "linear" and m.undo.size() == u1, "Z8 two Undos take Grid and Round edge back, one step each: the plain Repeat it row is left (pattern steps %d, kind %s, undo depth %d vs %d)" % [zn, zk, m.undo.size(), u1])

	# ---------------- H HALL: a bracket band round its corners, a tile row along an eave
	pu.set_on(false)
	m.S.part = {}
	await process_frame
	await click_ctl(pu.part_btn)
	await idle(3)
	if pu.easy:
		pu.easy = false
	m.S.part = hall_rec()
	bld.sync()
	m.target = Vector3(0.0, 0.05, 0.0)
	m.dist = 1.5
	m.pitch = -38.0
	m.yaw = 28.0
	m._cam()
	await idle(40)
	var hres := Part.replay(m.S.part)
	ok((hres["errors"] as Dictionary).is_empty() and int(hres["bodies"]) == 4 + 25 + 11, "H1 the hall bands replay: %d bodies (4 + 25 bracket copies + 11 tile copies), no failed step" % int(hres["bodies"]))
	await shot("hall_full")
	m.S.part = hall_rec(false)   # the band and its bracket sets alone, so the roof does not hide them
	bld.sync()
	m.target = Vector3(0.0, 0.02, 0.0)
	m.dist = 1.1
	m.pitch = -52.0
	m.yaw = 28.0
	m._cam()
	await idle(40)
	await shot("hall_brackets")
	# BROWSER with many bodies: every row is inside the panel or clipped away by it (scrolled), the panel ends above the timeline
	await idle(4)
	var bchk: Dictionary = browser_check(pu.browser, pu.tl)
	ok(int(m.S.part.get("seq", 0)) >= 0 and int(pu.res.get("bodies", 0)) >= 27 and bchk["rows"] >= 27 and bchk["bad"] == 0 and bchk["above"],
		"browser with %d bodies: %d rows, %d drawn outside the panel, panel bottom %.0f above timeline top %.0f, %d rows scrolled out of view" % [int(pu.res.get("bodies", 0)), bchk["rows"], bchk["bad"], bchk["bottom"], bchk["tl_top"], bchk["hidden"]])
	# a planted unclipped panel with the same rows must FAIL the same check
	var plant := Control.new()
	var pvb := VBoxContainer.new()
	plant.add_child(pvb)
	m.ui_root.add_child(plant)
	for i in 27:
		var pb := Button.new()
		pb.text = "    Body%d" % (i + 1)
		pb.flat = true
		pvb.add_child(pb)
	plant.position = pu.browser.position
	plant.size = pu.browser.size
	await idle(3)
	plant.size = pu.browser.size
	var pchk: Dictionary = browser_check(plant, pu.tl)
	ok(pchk["bad"] > 0, "a planted unclipped panel fails the browser bar (%d rows drawn outside it)" % pchk["bad"])
	plant.queue_free()
	m.S.part = hall_rec()   # the whole hall again: a row of 12 tiles along the roof's back eave
	bld.sync()
	m.target = Vector3(0.0, 0.085, -0.12)
	m.dist = 0.8
	m.pitch = -32.0
	m.yaw = 28.0
	m._cam()
	await idle(40)
	await shot("hall_eave")
	print("s228: %d fail" % fails)
	quit(1 if fails > 0 else 0)


func ok(c: bool, w: String) -> void:
	print(("ok   " if c else "FAIL ") + w)
	fails += 0 if c else 1


func idle(n := 3) -> void:
	for i in n:
		await process_frame


func ev_mouse(p: Vector2, down: bool, mods := 0) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = down
	e.position = p
	e.global_position = p
	e.shift_pressed = mods == 1
	e.ctrl_pressed = mods == 2
	if down:
		e.button_mask = MOUSE_BUTTON_MASK_LEFT
	root.push_input(e, true)
	await process_frame


func ev_move(p: Vector2, held := true) -> void:
	var e := InputEventMouseMotion.new()
	e.position = p
	e.global_position = p
	if held:
		e.button_mask = MOUSE_BUTTON_MASK_LEFT
	root.push_input(e, true)
	await process_frame


func click_ctl(c: Control) -> void:
	var p := c.get_global_rect().get_center()
	await ev_move(p, false)
	await ev_mouse(p, true)
	await ev_mouse(p, false)
	await idle(2)


## a click in the view (mods: 0 none, 1 Shift, 2 Ctrl)
func click_at(p: Vector2, mods := 0) -> void:
	await ev_move(p, false)
	await ev_mouse(p, true, mods)
	await ev_mouse(p, false, mods)
	await idle(2)


func drag_box(a: Vector2, b: Vector2, mods: int) -> void:
	await ev_move(a, false)
	await ev_mouse(a, true, mods)
	for i in range(1, 9):
		await ev_move(a.lerp(b, i / 8.0))
	await ev_mouse(b, false, mods)
	await idle(2)


func shot(nm: String) -> void:
	await idle(3)
	DirAccess.make_dir_recursive_absolute(SHOT)
	root.get_texture().get_image().save_png("%s/%s.png" % [SHOT, nm])


func press_tool(pu: PartUI, t: String) -> void:
	var b: Button = pu.tool_btns[t]
	if b.is_visible_in_tree():
		await click_ctl(b)
		return
	for pair in m.ui_caps.get("BUILD", []):
		if (pair[1] as Array).has(b):
			await click_ctl(pair[0])
			(pair[0] as MenuButton).get_popup().hide()
			m._run_tool(b, pair[0])
			await idle(2)
			return
	await click_ctl(m.ui_more)
	m.ui_more.get_popup().hide()
	var i: int = m._more_tools.find(b)
	if i >= 0:
		m._more_pick(i)
	await idle(2)


func typed(le: LineEdit, t: String) -> void:
	le.text = t
	le.text_changed.emit(t)
	await idle(2)


func E(v: float) -> String:
	return String.num_scientific(v)


func save_reload(path: String, saved_json: String, bld: BuildUI) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify(m.S.to_dict(m.B, false)))
	f.close()
	m._new_scene()
	await idle(3)
	if m.ui_save_ask != null and m.ui_save_ask.visible:
		m._save_ask_choose("discard")
	await idle(2)
	m._load_scene(path)
	await idle(4)
	bld.sync()
	await idle(2)


