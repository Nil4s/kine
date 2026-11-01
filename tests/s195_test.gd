extends SceneTree
## godot --path . --position 4000,4000 -s tests/s195_test.gd     (EASY PART: Cut a hole > Make it lighter; scripts/build/lighter.gd; needs the CAD DLL)
## MAKE IT LIGHTER is a RULE OF THUMB, not a stress simulation (the app says so in its status line and tooltip; this test checks that sentence too).
## Bars (real clicks at 1280 x 720; a 120 x 40 x 10 mm bracket; everything measured from the BUILT mesh and the kernel volume):
##   1 CHIP     Cut a hole shows a "Make it lighter" chip, no key names in the row; Held / Pushed chips appear after it
##   2 ONE STEP the press is ONE undo step; ONE solid; Held / Pushed picked with clicks (left end held, right end pushed)
##   3 DROP     bracket held on the left end, pushed at the right end: the volume drops by 20 to 50 pct (printed)
##   4 SOLID    ray probes (along the thin way) on a 0.75 mm grid over every point within 3 mm of the held face, the pushed face and the outer
##              edges: 0 holes found there; and the same probes DO find holes in the middle (the probe can fail)
##   5 SLIDER   the How much lighter slider at 3 settings (40, 70, 100 pct): the volume drop grows strictly, each still ONE solid
##   6 UNDO     one Undo after the Make it lighter press takes the holes away (volume back to the Cut a hole step's)
##   7 WORDS    the status line says it is a rule of thumb, not a stress test
## Shots: C:/Temp/claude/s195/lighter.png
var fails := 0
var m: Node
const SHOT := "C:/Temp/claude/s195"
const DIRT := "user://s195_test"
const BAD_WORDS := ["ctrl", "shift", "alt+", "esc", "enter", "tab ", "delete", "backspace", "f1", "f2", "f3", "f4", "f5", "f6", "f7", "f8", "f9", "f10", "f11", "f12"]
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


func ev_move(p: Vector2, held := false) -> void:
	var e := InputEventMouseMotion.new()
	e.position = p
	e.global_position = p
	if held:
		e.button_mask = MOUSE_BUTTON_MASK_LEFT
	root.push_input(e, true)
	await process_frame


func click_ctl(c: Control) -> void:
	var p := c.get_global_rect().get_center()
	await ev_move(p)
	await ev_mouse(p, true)
	await ev_mouse(p, false)
	await idle(4)


func shot(nm: String) -> void:
	await idle(3)
	DirAccess.make_dir_recursive_absolute(SHOT)
	root.get_texture().get_image().save_png("%s/%s.png" % [SHOT, nm])


func texts(n: Node, out: Array) -> void:
	if n is Control and not (n as Control).visible:
		return
	if n is Button:
		out.append((n as Button).text)
	if n is Control:
		out.append((n as Control).tooltip_text)
	for c in n.get_children():
		texts(c, out)


func vol_mm3() -> float:
	return float(Part.replay(m.S.part)["volume"]) * 1e9


func bodies() -> int:
	return int(Part.replay(m.S.part)["bodies"])


## the thin-way ray probe: the triangles of the built mesh that face front or back, as [a, b, c] points in mm (x, y)
func top_tris() -> Array:
	var msh: ArrayMesh = Part.replay(m.S.part)["mesh"]
	var a := msh.surface_get_arrays(0)
	var v: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
	var ix: PackedInt32Array = a[Mesh.ARRAY_INDEX]
	var out := []
	for t in ix.size() / 3:
		var p0: Vector3 = v[ix[t * 3]] / Part.MM
		var p1: Vector3 = v[ix[t * 3 + 1]] / Part.MM
		var p2: Vector3 = v[ix[t * 3 + 2]] / Part.MM
		var nrm := (p1 - p0).cross(p2 - p0)
		if nrm.length() < 1e-9 or absf(nrm.normalized().z) < 0.5:
			continue
		var lo := Vector2(minf(p0.x, minf(p1.x, p2.x)), minf(p0.y, minf(p1.y, p2.y)))
		var hi := Vector2(maxf(p0.x, maxf(p1.x, p2.x)), maxf(p0.y, maxf(p1.y, p2.y)))
		out.append([Vector2(p0.x, p0.y), Vector2(p1.x, p1.y), Vector2(p2.x, p2.y), lo, hi])
	return out


func hit(tris: Array, p: Vector2) -> bool:
	for t in tris:
		var lo: Vector2 = t[3]
		var hi: Vector2 = t[4]
		if p.x < lo.x - 1e-6 or p.x > hi.x + 1e-6 or p.y < lo.y - 1e-6 or p.y > hi.y + 1e-6:
			continue
		var a: Vector2 = t[0]
		var b: Vector2 = t[1]
		var c: Vector2 = t[2]
		var d := (b.y - c.y) * (a.x - c.x) + (c.x - b.x) * (a.y - c.y)
		if absf(d) < 1e-12:
			continue
		var u := ((b.y - c.y) * (p.x - c.x) + (c.x - b.x) * (p.y - c.y)) / d
		var w := ((c.y - a.y) * (p.x - c.x) + (a.x - c.x) * (p.y - c.y)) / d
		if u >= -1e-6 and w >= -1e-6 and u + w <= 1.0 + 1e-6:
			return true
	return false


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
		print("FAIL: no KineCAD DLL")
		quit(1)
		return
	pu = m.bld.part
	await click_ctl(pu.part_btn)
	await click_ctl(pu.easy_open_btn)
	await idle(4)
	ep = pu.ep
	# the bracket: 120 x 40 x 10 mm, flat to the front (the record, as an Easy plate would be)
	var br := Part.make("Bracket")
	br["features"] = [
		{"t": "sketch", "id": "f1", "name": "Sketch1", "plane": "front", "ents": [{"k": "rect", "a": [0.0, 0.0], "b": [120.0, 40.0]}], "dims": []},
		{"t": "extrude", "id": "f2", "name": "Extrude1", "sketch": "f1", "dist": 10.0, "both": false, "op": "new"}]
	br["seq"] = 2
	m.S.part = br
	pu.upto = -1
	pu.sync()
	await idle(4)
	var v_box := vol_mm3()
	ok(absf(v_box - 48000.0) < 1.0, "0 the bracket is 120 x 40 x 10 = %.1f mm3" % v_box)

	await click_ctl(ep.make_btns["hole"])
	await idle(3)
	var words := []
	texts(ep.hole_box, words)
	var bad := []
	for w in words:
		for bw in BAD_WORDS:
			if String(w).to_lower().contains(bw):
				bad.append(String(w))
	var lb := root.find_child("easypart_hole_lighter", true, false) as Button
	ok(lb != null and lb.visible and lb.text == "Make it lighter" and bad.is_empty(), "1 CHIP: Cut a hole shows a Make it lighter chip, no key names %s" % str(bad))
	ok(not ep.lighter_held_btn.visible, "1 CHIP: Held / Pushed chips wait until Make it lighter is pressed")
	var v_hole := vol_mm3()
	var u0: int = m.undo.size()
	await click_ctl(lb)
	await idle(4)
	var u1: int = m.undo.size()
	var v_def := vol_mm3()
	ok(u1 == u0 + 1 and bodies() == 1 and v_def < v_hole, "2 ONE STEP: the press is %d undo step, %d solid, volume %.0f -> %.0f mm3" % [u1 - u0, bodies(), v_hole, v_def])
	ok(ep.lighter_held_btn.visible and ep.lighter_push_btn.visible and ep.lighter_held_btn.text == "Held: bottom" and ep.lighter_push_btn.text == "Pushed: top", "2 the Held / Pushed chips show their defaults [%s | %s]" % [ep.lighter_held_btn.text, ep.lighter_push_btn.text])
	await click_ctl(ep.lighter_held_btn)
	await click_ctl(ep.lighter_push_btn)
	ok(ep.lighter_held_btn.text == "Held: left end" and ep.lighter_push_btn.text == "Pushed: right end", "2 clicks pick left end held, right end pushed [%s | %s]" % [ep.lighter_held_btn.text, ep.lighter_push_btn.text])
	await shot("lighter")

	# 3 DROP
	var v_lr := vol_mm3()
	var drop := (v_box - v_lr) / v_box * 100.0
	ok(drop >= 20.0 and drop <= 50.0 and bodies() == 1, "3 DROP: held left, pushed right: volume %.0f -> %.0f mm3, down %.1f pct, %d solid (want 20 to 50)" % [v_box, v_lr, drop, bodies()])
	var holes: Array = (Part.feature(m.S.part, String(ep.hole_id))["ents"] as Array)
	print("     (%d holes in the sketch)" % holes.size())

	# 4 SOLID: ray probes
	var tris := top_tris()
	var found := 0
	var n_probe := 0
	var step := 0.75
	var yy := 0.0
	while yy <= 40.0 + 1e-6:
		var xx := 0.0
		while xx <= 120.0 + 1e-6:
			var near := xx <= 3.0 or xx >= 117.0 or yy <= 3.0 or yy >= 37.0
			if near:
				n_probe += 1
				# nudge the outermost probes 0.01 mm in: a probe exactly on the outside edge is on the boundary of the triangles
				var pr := Vector2(clampf(xx, 0.01, 119.99), clampf(yy, 0.01, 39.99))
				if not hit(tris, pr):
					found += 1
			xx += step
		yy += step
	var mid_holes := 0
	var xx2 := 5.0
	while xx2 <= 115.0:
		var yy2 := 5.0
		while yy2 <= 35.0:
			if not hit(tris, Vector2(xx2, yy2)):
				mid_holes += 1
			yy2 += 1.0
		xx2 += 1.0
	ok(found == 0 and n_probe > 800, "4 SOLID: %d probes within 3 mm of the held face, the pushed face and the outer edges: %d holes found" % [n_probe, found])
	ok(mid_holes > 100, "4 SOLID: the same probe finds holes in the middle (%d of the 3 x 3-grid points are open): it can fail" % mid_holes)

	# 5 SLIDER at 3 settings
	var sl := root.find_child("easypart_slider_last", true, false) as HSlider
	var drops := []
	var solids := true
	if sl != null:
		for lvl in [40.0, 70.0, 100.0]:
			sl.value = lvl
			await idle(4)
			drops.append((v_box - vol_mm3()) / v_box * 100.0)
			if bodies() != 1:
				solids = false
	ok(sl != null and drops.size() == 3 and drops[0] < drops[1] and drops[1] < drops[2] and solids, "5 SLIDER: How much lighter 40 / 70 / 100 pct drops the volume by %s pct, each ONE solid" % str(drops.map(func(x): return snappedf(float(x), 0.1))))
	var pill := root.find_child("easypart_pill_last", true, false) as Label
	ok(pill != null and pill.text == "100 %", "5 the slider reads a plain percent [%s]" % (pill.text if pill != null else "none"))
	await shot("lighter_max")

	# 7 WORDS: the status line right after a fresh press
	await click_ctl(ep.hole_btns["through"])
	var v_h2 := vol_mm3()
	var ua: int = m.undo.size()
	lb = root.find_child("easypart_hole_lighter", true, false) as Button
	await click_ctl(lb)
	var st: String = ep.hint_l.text
	ok(st.to_lower().contains("rule of thumb") and st.to_lower().contains("not a stress"), "7 WORDS: the hint line says [%s]" % st)
	ok(String(lb.tooltip_text).to_lower().contains("not a stress test"), "7 WORDS: the chip's tooltip says it is not a stress test")
	# 6 UNDO: from that fresh Make it lighter press
	var ub: int = m.undo.size()
	var v_l2 := vol_mm3()
	await click_ctl(ep.undo_btn)
	await idle(4)
	var v_back := vol_mm3()
	ok(ub == ua + 1 and v_l2 < v_h2 and absf(v_back - v_h2) < 0.5 and m.undo.size() == ub - 1, "6 UNDO: the press is %d step; one Undo takes the holes away (%.1f -> %.1f -> %.1f mm3)" % [ub - ua, v_h2, v_l2, v_back])

	print("s195: %d fail" % fails)
	quit(1 if fails > 0 else 0)
