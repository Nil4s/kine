extends SceneTree
## godot --position 4000,4000 -s tests/s079_test.gd   (Friday plan 79: Parts > Pipes: PVC pipe by real outside width, elbows 90 / 45, T-piece, sleeve with the Fit clearance; scripts/easy_pipes.gd, scripts/build/pipe_parts.gd; needs the CAD DLL)
## Real clicks at 1280 x 720 from the BUILDING card. Everything is measured on the BUILT mesh (triangles in mm): ray casts through the axis for outside / inside width,
## the planar ring faces (annulus area) for the openings and the angle between their axes, the kernel body count, the undo list. Expected numbers are written here by hand:
## PVC-U PN16 wall (SDR 13.6): outside 20 25 32 40 50 -> wall 1.5 1.9 2.4 3.0 3.7 mm.
##   1 PAGE    Parts > Pipes shows 5 kind chips, 5 size chips, Fit and Add, all inside the 1280 x 720 screen
##   2 PIPE    each size: outside and inside by ray cast within 0.05 mm of the table, ONE solid, ONE undo step, 300 mm long
##   3 SLIDER  the Length slider: 500 mm long (bounding box)
##   4 ELBOW   each size: ONE solid, ONE undo step, two openings, axes 90.0 deg (+-0.5), outside / inside of the stub by ray cast
##   5 ELBOW45 the same with 45.0 deg
##   6 TEE     each size: ONE solid, three openings, branch axis square to the run 90.0 (+-0.5), run ends in line, ray-cast widths
##   7 SLEEVE  each Fit: sleeve inside = pipe outside (ray cast of the pipe) + 2 x fit within 0.05; the Fit chip is one undo step; over a pipe (Add to the part) the gap measured between them = the fit
##   8 JOIN    an elbow added to a pipe (2 solids), Stick together: ONE solid, ONE undo step
##   9 WORDS   no key names in the page
var fails := 0
var m: Node
const SHOT := "C:/Temp/claude/s079"
const DIRT := "user://s079_test"
const BAD_WORDS := ["ctrl", "shift", "alt+", "esc", "enter", "tab ", "delete", "backspace", "f1", "f2", "f3", "f4", "f5", "f6", "f7", "f8", "f9", "f10", "f11", "f12", "spacebar", "return key"]
const WALL := {20: 1.5, 25: 1.9, 32: 2.4, 40: 3.0, 50: 3.7}
const SIZES := [20, 25, 32, 40, 50]
const KINDS := ["pipe", "elbow", "elbow45", "tee", "sleeve"]
var pu: PartUI
var ep


func ok(c: bool, w: String) -> void:
	print(("ok   " if c else "FAIL ") + w)
	fails += 0 if c else 1


func idle(n := 3) -> void:
	for i in n:
		await process_frame


func ev_mouse(p: Vector2, down: bool) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = down
	e.position = p
	e.global_position = p
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
	if c == null:
		return
	if ep != null:
		ep._scroll_into_view(c)   # the page is taller than the panel: the user scrolls to the chip
		await idle(2)
	var p := c.get_global_rect().get_center()
	await ev_move(p, false)
	await ev_mouse(p, true)
	await ev_mouse(p, false)
	await idle(3)


func click_at(p: Vector2) -> void:
	await ev_move(p, false)
	await ev_mouse(p, true)
	await ev_mouse(p, false)
	await idle(3)


func shot(nm: String) -> void:
	await idle(3)
	DirAccess.make_dir_recursive_absolute(SHOT)
	root.get_texture().get_image().save_png("%s/%s.png" % [SHOT, nm])


func kind_chip(k: String) -> Button:
	return root.find_child("easypart_pipe_kind_" + k, true, false) as Button


func size_chip(d: int) -> Button:
	return root.find_child("easypart_pipe_size_%d" % d, true, false) as Button


func named(n: String) -> Button:
	return root.find_child(n, true, false) as Button


## every triangle corner of every body, in mm
func tris() -> Array:
	var out: Array = []
	for f in Part.body_faces(m.S.part):
		for v in (f as PackedVector3Array):
			out.append(v * 1000.0)
	return out


## the sorted distances along a ray at which it crosses the mesh's triangles
func ray_ts(tr: Array, o: Vector3, dir: Vector3) -> Array:
	var ts := []
	var i := 0
	while i + 2 < tr.size():
		var a: Vector3 = tr[i]
		var e1: Vector3 = tr[i + 1] - a
		var e2: Vector3 = tr[i + 2] - a
		i += 3
		var pv := dir.cross(e2)
		var det := e1.dot(pv)
		if absf(det) < 1e-12:
			continue
		var tv := o - a
		var u := tv.dot(pv) / det
		if u < 0.0 or u > 1.0:
			continue
		var qv := tv.cross(e1)
		var v := dir.dot(qv) / det
		if v < 0.0 or u + v > 1.0:
			continue
		var t := e2.dot(qv) / det
		if t > 0.0:
			ts.append(t)
	ts.sort()
	return ts


## [outside, inside] width at z by rays through the axis (x = 0, y = 0) in four directions, the larger of each (a ray through a polygon corner is the true width)
func widths_at(z: float) -> Array:
	var tr := tris()
	var best_od := 0.0
	var best_id := 0.0
	var a_od := 0.0
	var a_id := 0.0
	var angles: Array = []
	for k in 24:   # 24 directions 7.5 deg apart, then 0.5 deg steps round the widest outside and the widest inside: a ray through a polygon corner of the mesh is the true width
		angles.append(7.5 * float(k))
	var refined := false
	var ai := 0
	while ai < angles.size():
		var ang := float(angles[ai])
		ai += 1
		var a := deg_to_rad(ang)
		var dir := Vector3(cos(a), sin(a), 0.0)
		var perp := Vector3(-dir.y, dir.x, 0.0)
		var ts := ray_ts(tr, Vector3(0, 0, z) - dir * 300.0 + perp * 0.07, dir)   # 0.07 mm off the axis: a ray along a mesh edge would cross it twice
		if ts.size() == 4:
			if float(ts[3]) - float(ts[0]) > best_od:
				best_od = float(ts[3]) - float(ts[0])
				a_od = ang
			if float(ts[2]) - float(ts[1]) > best_id:
				best_id = float(ts[2]) - float(ts[1])
				a_id = ang
		if ai == angles.size() and not refined:
			refined = true
			for q in range(-8, 9):
				if q != 0:
					angles.append(a_od + 0.5 * float(q))
					angles.append(a_id + 0.5 * float(q))
	return [best_od, best_id]


func bbox() -> Array:
	var lo := Vector3(1e9, 1e9, 1e9)
	var hi := Vector3(-1e9, -1e9, -1e9)
	for v in tris():
		lo = lo.min(v)
		hi = hi.max(v)
	return [lo, hi]


## the planar ring faces (an annulus of the pipe's own area): [{n, area}] grouped by plane
func openings(d: int) -> Array:
	var tr := tris()
	var ro := float(d) * 0.5
	var ri := ro - float(WALL[d])
	var ann := PI * (ro * ro - ri * ri)
	var groups := {}
	var i := 0
	while i + 2 < tr.size():
		var a: Vector3 = tr[i]
		var b: Vector3 = tr[i + 1]
		var c: Vector3 = tr[i + 2]
		i += 3
		var cr := (b - a).cross(c - a)
		var ar := cr.length() * 0.5
		if ar < 1e-9:
			continue
		var n := cr.normalized()
		if n.x < -1e-6 or (absf(n.x) <= 1e-6 and n.y < -1e-6) or (absf(n.x) <= 1e-6 and absf(n.y) <= 1e-6 and n.z < 0.0):
			n = -n
		var off := n.dot((a + b + c) / 3.0)
		var key := "%d,%d,%d,%d" % [roundi(n.x * 200.0), roundi(n.y * 200.0), roundi(n.z * 200.0), roundi(off * 5.0)]
		if not groups.has(key):
			groups[key] = {"n": n, "area": 0.0}
		groups[key]["area"] = float(groups[key]["area"]) + ar
	var out := []
	for k in groups:
		var g: Dictionary = groups[k]
		if absf(float(g["area"]) - ann) <= 0.06 * ann:
			out.append(g)
	return out


func angle_between(a: Vector3, b: Vector3) -> float:
	return rad_to_deg(acos(clampf(absf(a.dot(b)), 0.0, 1.0)))


func bodies() -> int:
	return int(pu.res.get("bodies", 0))


## picks the kind, then the size, with real clicks. Returns the undo steps minus the steps this should take: the kind chip on another kind (or an empty floor)
## is one step (a new part), a size chip with another size on the floor is one step (the part is resized); a repeat is none. 0 = exactly right
func place(kind: String, d: int) -> int:
	var u0: int = m.undo.size()
	var want := 0
	var on_floor: bool = PipeParts.KINDS.has(ep._tpl()) and not (m.S.part.get("features", []) as Array).is_empty()
	var cur_d: int = int(ep.pipes_box.sel_d)
	if not (on_floor and ep._tpl() == kind):
		want += 1
	await click_ctl(kind_chip(kind))
	if d != cur_d:
		want += 1
	await click_ctl(size_chip(d))
	await idle(2)
	return (m.undo.size() - u0) - want


func body_box(faces: Array, i: int) -> Rect2:
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for w in faces[i]:
		var q: Vector2 = m.cam.unproject_position(w)
		lo = lo.min(q)
		hi = hi.max(q)
	return Rect2(lo, hi - lo)


func inside_pt(faces: Array, i: int) -> Vector2:
	var r := body_box(faces, i)
	for f in [Vector2(0.5, 0.5), Vector2(0.35, 0.5), Vector2(0.65, 0.5), Vector2(0.5, 0.35), Vector2(0.5, 0.65), Vector2(0.2, 0.5), Vector2(0.8, 0.5), Vector2(0.5, 0.2), Vector2(0.5, 0.8)]:
		var p: Vector2 = r.position + r.size * f
		var hit: Dictionary = pu._ray_hit(p, faces)
		if not hit.is_empty() and int(hit["body"]) == i and not ep._over_ui(p):
			return p
	return Vector2(-1, -1)


func near(a: float, b: float, tol: float) -> bool:
	return absf(a - b) <= tol


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
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIRT))
	ss.dirs_override = [DIRT]
	ss.show_screen()
	await idle(3)
	await click_ctl(ss._cards["building"])
	if m.ui_save_ask != null and m.ui_save_ask.visible:
		m._save_ask_choose("discard")
	await idle(6)
	m.bld.part.set_on(false)
	m.S.part = {}
	await idle(8)
	if not Part.available():
		print("FAIL: no KineCAD DLL, the pipes cannot run")
		quit(1)
		return
	pu = m.bld.part
	await click_ctl(pu.part_btn)
	await click_ctl(pu.easy_open_btn)
	await idle(4)
	ep = pu.ep
	var vp := Rect2(Vector2.ZERO, Vector2(1280, 720))

	# 1 PAGE
	await click_ctl(root.find_child("easypart_chip_parts", true, false) as Button)
	var lb := root.find_child("easypart_lib_Pipes", true, false) as Button
	await click_ctl(lb)
	var seen := 0
	var off := []
	var ctl: Array = []
	await idle(3)
	for k in KINDS:
		ctl.append(kind_chip(k))
	for d in SIZES:
		ctl.append(size_chip(d))
	ctl.append(named("easypart_pipe_fit"))
	ctl.append(named("easypart_pipe_add"))
	for c in ctl:
		if c != null and c.is_visible_in_tree():
			seen += 1
			ep._scroll_into_view(c)
			await idle(2)
			if not vp.encloses(Rect2(c.global_position, c.size)):
				off.append(c.name)
	ok(lb != null and seen == 12 and off.is_empty(), "1 Parts > Pipes: 12 controls shown %d/12, off screen %s" % [seen, str(off)])
	await shot("page")

	# 2 PIPE: each size
	var bad := []
	for d in SIZES:
		var steps := await place("pipe", d)
		var w := widths_at(-150.0)
		var bb := bbox()
		var good: bool = near(float(w[0]), d, 0.05) and near(float(w[1]), float(d) - 2.0 * float(WALL[d]), 0.05) and bodies() == 1 and steps == 0 and near(float(bb[1].z) - float(bb[0].z), 300.0, 0.5)
		if not good:
			bad.append("%d: od %.3f id %.3f bodies %d steps %d len %.2f" % [d, w[0], w[1], bodies(), steps, float(bb[1].z) - float(bb[0].z)])
	ok(bad.is_empty(), "2 pipe 20 25 32 40 50 mm: outside and inside by ray cast within 0.05 of the PN16 table, 300 mm, one solid, one undo step each %s" % str(bad))
	await shot("pipe50")

	# 3 SLIDER
	var sl: HSlider = null
	for r in ep.rows:
		if String(r.get("key", "")) == "len":
			sl = r["slider"]
	if sl != null:
		sl.value = 500.0
	await idle(6)
	var bb2 := bbox()
	ok(sl != null and near(float(bb2[1].z) - float(bb2[0].z), 500.0, 0.5) and bodies() == 1, "3 Length slider to 500 mm: built %.2f mm long, %d solid" % [float(bb2[1].z) - float(bb2[0].z), bodies()])

	# 4 / 5 ELBOWS
	for kind in ["elbow", "elbow45"]:
		var want := 90.0 if kind == "elbow" else 45.0
		bad = []
		for d in SIZES:
			var steps := await place(kind, d)
			var ops := openings(d)
			var w := widths_at(-float(d) * 0.5)
			var ang := angle_between(ops[0]["n"], ops[1]["n"]) if ops.size() == 2 else -1.0
			var good: bool = ops.size() == 2 and near(ang, want, 0.5) and near(float(w[0]), d, 0.05) and near(float(w[1]), float(d) - 2.0 * float(WALL[d]), 0.05) and bodies() == 1 and steps == 0
			if not good:
				bad.append("%d: openings %d angle %.2f od %.3f id %.3f bodies %d steps %d" % [d, ops.size(), ang, w[0], w[1], bodies(), steps])
			if d == 32:
				await shot(kind)
		ok(bad.is_empty(), "%s: %.0f deg between the two opening axes (+-0.5), widths by ray cast within 0.05, one solid, one undo step, all 5 sizes %s" % [kind, want, str(bad)])

	# 6 TEE
	bad = []
	for d in SIZES:
		var steps := await place("tee", d)
		var ops := openings(d)
		var w := widths_at(-float(d) * 0.4)
		var zrings := 0
		var xrings := 0
		var nzv := Vector3.ZERO
		var nxv := Vector3.ZERO
		for g in ops:
			if absf((g["n"] as Vector3).z) > 0.9:
				zrings += 1
				nzv = g["n"]
			elif absf((g["n"] as Vector3).x) > 0.9:
				xrings += 1
				nxv = g["n"]
		var ang := angle_between(nzv, nxv)
		var good: bool = zrings == 2 and xrings == 1 and near(ang, 90.0, 0.5) and bodies() == 1 and steps == 0 and near(float(w[0]), d, 0.05) and near(float(w[1]), float(d) - 2.0 * float(WALL[d]), 0.05)
		if not good:
			bad.append("%d: run rings %d branch rings %d angle %.2f od %.3f id %.3f bodies %d steps %d" % [d, zrings, xrings, ang, w[0], w[1], bodies(), steps])
		if d == 32:
			await shot("tee")
	ok(bad.is_empty(), "6 T-piece: three openings (run ends in line, branch square to the run 90 +-0.5), widths within 0.05, one solid, one undo step, all 5 sizes %s" % str(bad))

	# 7 SLEEVE: the pipe's own outside width, then the sleeve at each Fit
	await place("pipe", 32)
	var pipe_od: float = float(widths_at(-150.0)[0])
	var fitb := named("easypart_pipe_fit")
	var fits_ok := true
	var fit_words := []
	var steps_ok := true
	var steps0 := await place("sleeve", 32)
	for i in 4:
		var u0: int = m.undo.size()
		await click_ctl(fitb)
		var fit_now := float(ep.pipes_box.fit)
		var w2 := widths_at(-20.0)
		var expected := pipe_od + 2.0 * fit_now
		fit_words.append("fit %.1f id %.3f want %.3f" % [fit_now, w2[1], expected])
		if not near(float(w2[1]), expected, 0.05) or bodies() != 1:
			fits_ok = false
		if m.undo.size() - u0 != 1:
			steps_ok = false
	ok(steps0 == 0 and fits_ok and steps_ok, "7 sleeve: inside width = pipe outside (%.3f) + 2 x fit within 0.05 at every Fit chip, one undo step each %s" % [pipe_od, str(fit_words)])
	# over a pipe
	await place("pipe", 32)
	await click_ctl(named("easypart_pipe_add"))
	var u1: int = m.undo.size()
	await click_ctl(kind_chip("sleeve"))
	var tr2 := tris()
	var ts := ray_ts(tr2, Vector3(-300, 0.07, -280.3), Vector3(1, 0, 0))
	var gap := -1.0
	var sid := -1.0
	var pod := -1.0
	if ts.size() == 8:
		gap = float(ts[2]) - float(ts[1])
		sid = float(ts[6]) - float(ts[1])
		pod = float(ts[5]) - float(ts[2])
	print("rays hit %d" % ts.size())
	ok(bodies() == 2 and m.undo.size() - u1 == 1 and ts.size() == 8 and near(gap, float(ep.pipes_box.fit), 0.05) and near(sid, pod + 2.0 * float(ep.pipes_box.fit), 0.06), "7 sleeve over the pipe (Add to the part): %d solids, one undo step, gap to the pipe %.3f vs fit %.1f, sleeve inside %.3f vs pipe %.3f + 2 fit" % [bodies(), gap, float(ep.pipes_box.fit), sid, pod])
	await shot("sleeve")

	# 8 JOIN: an elbow added to a pipe, Stick together
	await click_ctl(named("easypart_pipe_add"))   # off
	await place("tee", 25)
	await place("pipe", 25)
	await click_ctl(named("easypart_pipe_add"))   # on
	var u2: int = m.undo.size()
	await click_ctl(kind_chip("elbow"))
	var two := bodies()
	var added_steps: int = m.undo.size() - u2
	await shot("added")
	var faces: Array = Part.body_faces(m.S.part, -1)
	await click_ctl(ep.make_btns["stick"])
	await click_at(inside_pt(faces, 0))
	await click_at(inside_pt(faces, 1))
	var u3: int = m.undo.size()
	await click_ctl(ep.stick_btns["join"])
	await idle(4)
	ok(two == 2 and added_steps == 1 and bodies() == 1 and ep._lumps(pu.res) == 1 and m.undo.size() - u3 == 1, "8 elbow added to a pipe: %d solids, one undo step; Stick together > Join: %d solid, %d piece in the view, one undo step" % [two, bodies(), ep._lumps(pu.res)])
	await shot("joined")

	# 9 WORDS
	var hit := []
	var texts := [ep.hint_l.text, ep.status_l.text, ep.pipes_box.words.text]
	for c in ctl:
		if c != null:
			texts.append((c as Button).text)
			texts.append((c as Button).tooltip_text)
	for t in texts:
		for w3 in BAD_WORDS:
			if String(t).to_lower().contains(w3):
				hit.append("%s in [%s]" % [w3, t])
	ok(hit.is_empty(), "9 no key name in the Pipes page words %s" % str(hit))
	print("s079: %d fail" % fails)
	quit(1 if fails > 0 else 0)
