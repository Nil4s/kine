extends SceneTree
## godot --position -30000,-30000 --audio-driver Dummy --path . -s tests/c24_test.gd     (C24, complaints 317 and 348; needs the CAD DLL; a window for U1-U3)
## BARS (written and committed before the first run). Env C24_SHOT=<dir> saves 1280x720 screenshots.
## A leaf 800 x 40 x 2000 mm (x 0..800, y -20..20, z 0..2000), a hinge about +z through the origin (axis) and a second axis +x ("axis2").
##  317 TWO AXES (scripts/build/joint_axes.gd)
##   A1 POSE   the posed body (replay pose a=30 deg about axis, b=40 deg about axis2) has the bounding box of the leaf's 8 corners turned by
##             R(z, 30) * R(x, 40), computed IN THIS TEST with Basis, to 1 mm per face.  CONTROL: the one-axis pose (no axis2, a=30) is more than 5 mm off that box.
##   A2 LIMIT  track2 0 -> 60 deg with limit2 20: the sweep says limit2 20 and max_deg2 20 (0.01).  CONTROL: no limit2 -> max_deg2 = 60 (0.01).
##   A3 OLD    the door of tests/hinge_test.gd (no axis2): the sweep's keys carry no limit2, max_deg2 or placed, and its first hit frame is 24 +- 1
##             (the closed form of hinge_test bar 2).  CONTROL: the same door WITH axis2 +x, track2 0 -> 60 deg, first-hit frame differs from the one-axis frame
##             (the second axis changes where the leaf meets the stop).
##  348 VISIBLE PIVOT
##   B1 EDGE   a block 400 x 400 x 100 mm with a pivot in the air at (430, 430, 50): auto_place picks the vertical corner edge's middle (400, 400, 50) within 0.5 mm,
##             kind "edge", moved 42.43 mm +- 0.5.  CONTROL: with no auto_place the pivot stays 42 mm from every visible feature.
##   B2 HOLE   the same block with a 100 mm hole through it at (200, 200), pivot (200, 200, 50) (inside the hole, in the air): kind "hole", p within 0.5 mm of (200, 200, 0) or (200, 200, 100).
##   B3 STAYS  a pivot on the side face (400, 200, 50): hidden false, moved 0 (mm), p unchanged.
##   B4 SWEEP  hinge_sweep of a hinge with "autoplace": true reports "placed" with kind "edge"; the same hinge without it reports no "placed".
##  UI (1280 x 720, real clicks on the checkbox and OK)
##   U1 ROWS   the hinge dialog has part_axis2 (3 items), part_deg2, part_snap and part_snap_words.
##   U2 SAVE   Sideways + 40 deg + OK: ONE new step with axis2 square to axis (|dot| < 1e-6) and track2 ending at 40.  CONTROL: None leaves axis2, track2, autoplace, placed unset.
##   U3 SNAP   checkbox on with the pivot in the air: the words under it name the edge, and OK saves o within 0.5 mm of the corner edge middle and "placed".
##   U4 LOOK   screenshots c24_rows.png and c24_snap.png are written (a human looks at them).
## FIXTURE FIXES after run 1 (no bar value moved): A3 CONTROL uses track2 0 -> -60 (the +b tilt moves the TOP of the leaf away from the stop, the bottom corner still hits at frame 24); the UI opens the dialog by open_dialog("hinge").
## A watchdog prints FAIL and quits after 240 s.
const KCad := preload("res://scripts/kcad.gd")
var fails := 0
var done := false


func ok(c: bool, w: String) -> void:
	print(("ok   " if c else "FAIL ") + w)
	fails += 0 if c else 1


func idle(n := 3) -> void:
	for i in n:
		await process_frame


func leaf_rec(hinge: Dictionary, stop_y := 400.0) -> Dictionary:
	var rec := Part.make("Door")
	rec["features"] = [
		{"t": "sketch", "id": "f1", "name": "Sketch1", "plane": "front", "ents": [{"k": "rect", "a": [0, -20], "b": [800, 20]}], "dims": []},
		{"t": "extrude", "id": "f2", "name": "Extrude1", "sketch": "f1", "dist": 2000.0, "both": false, "op": "new"},
		{"t": "sketch", "id": "f3", "name": "Sketch2", "plane": "front", "ents": [{"k": "rect", "a": [-1600, stop_y], "b": [1600, stop_y + 10]}], "dims": []},
		{"t": "extrude", "id": "f4", "name": "Extrude2", "sketch": "f3", "dist": 2000.0, "both": false, "op": "new"},
	]
	var h := {"t": "hinge", "id": "f5", "name": "Hinge1", "body": 0, "o": [0, 0, 0], "axis": [0, 0, 1], "track": [[0.0, 0.0], [3.0, 90.0]], "clear": []}
	h.merge(hinge, true)
	rec["features"].append(h)
	return rec


func block_rec(hole: bool, hinge: Dictionary) -> Dictionary:
	var rec := Part.make("Block")
	var fs: Array = [
		{"t": "sketch", "id": "f1", "name": "Sketch1", "plane": "front", "ents": [{"k": "rect", "a": [0, 0], "b": [400, 400]}], "dims": []},
		{"t": "extrude", "id": "f2", "name": "Extrude1", "sketch": "f1", "dist": 100.0, "both": false, "op": "new"},
	]
	if hole:
		fs.append({"t": "sketch", "id": "f3", "name": "Sketch2", "plane": "front", "ents": [{"k": "circle", "c": [200, 200], "r": 50}], "dims": []})
		fs.append({"t": "extrude", "id": "f4", "name": "Extrude2", "sketch": "f3", "dist": 100.0, "both": false, "op": "cut"})
	var h := {"t": "hinge", "id": "f9", "name": "Hinge1", "body": 0, "o": [430, 430, 50], "axis": [0, 0, 1], "track": [[0.0, 0.0], [1.0, 10.0]], "clear": []}
	h.merge(hinge, true)
	fs.append(h)
	rec["features"] = fs
	return rec


func box_of(tris: PackedVector3Array) -> AABB:
	var lo := Vector3(INF, INF, INF)
	var hi := Vector3(-INF, -INF, -INF)
	for v in tris:
		lo = lo.min(v)
		hi = hi.max(v)
	return AABB(lo, hi - lo)


func box_err(a: AABB, b: AABB) -> float:
	return maxf((a.position - b.position).length(), (a.end - b.end).length()) / Part.MM


func shot(nm: String) -> void:
	var d := OS.get_environment("C24_SHOT")
	if d == "":
		return
	DirAccess.make_dir_recursive_absolute(d)
	root.get_texture().get_image().save_png("%s/%s.png" % [d, nm])


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


func click_ctl(c: Control) -> void:
	var p := c.get_global_rect().get_center()
	root.push_input(_mm(p), true)
	await ev_mouse(p, true)
	await ev_mouse(p, false)
	await idle(2)


func _mm(p: Vector2) -> InputEventMouseMotion:
	var e := InputEventMouseMotion.new()
	e.position = p
	e.global_position = p
	return e


func logic_bars() -> void:
	# A1
	var f2 := {"axis2": [1, 0, 0], "track2": [[0.0, 0.0], [3.0, 40.0]]}
	var rec := leaf_rec(f2)
	var posed: PackedVector3Array = Part.body_faces(rec, -1, {"pose": {"f": "f5", "deg": 30.0, "deg2": 40.0}})[0]
	var R := Basis(Vector3(0, 0, 1), deg_to_rad(30.0)) * Basis(Vector3(1, 0, 0), deg_to_rad(40.0))
	var lo := Vector3(INF, INF, INF)
	var hi := Vector3(-INF, -INF, -INF)
	for x in [0.0, 0.8]:
		for y in [-0.02, 0.02]:
			for z in [0.0, 2.0]:
				var q := R * Vector3(x, y, z)
				lo = lo.min(q)
				hi = hi.max(q)
	var want := AABB(lo, hi - lo)
	var e2 := box_err(box_of(posed), want)
	var one := leaf_rec({})
	var p1: PackedVector3Array = Part.body_faces(one, -1, {"pose": {"f": "f5", "deg": 30.0}})[0]
	var e1 := box_err(box_of(p1), want)
	ok(e2 <= 1.0 and e1 > 5.0, "A1 POSE: two-axis pose within 1 mm of the closed-form box (%.3f mm); control one-axis is %.1f mm off (> 5)" % [e2, e1])
	# A2
	var lim := leaf_rec({"axis2": [1, 0, 0], "track2": [[0.0, 0.0], [3.0, 60.0]], "limit2": 20.0})
	var sl: Dictionary = Part.hinge_sweep(lim, "f5")
	var nl: Dictionary = Part.hinge_sweep(leaf_rec({"axis2": [1, 0, 0], "track2": [[0.0, 0.0], [3.0, -60.0]]}), "f5")
	ok(bool(sl.get("ok", false)) and absf(float(sl.get("limit2", -1)) - 20.0) < 0.01 and absf(float(sl.get("max_deg2", -1)) - 20.0) < 0.01, "A2 LIMIT: limit2 %s, max_deg2 %s (20, 20)" % [sl.get("limit2"), sl.get("max_deg2")])
	ok(absf(float(nl.get("max_deg2", -1)) - 60.0) < 0.01, "A2 CONTROL: no limit2 -> max_deg2 %s (60)" % nl.get("max_deg2"))
	# A3
	var old: Dictionary = Part.hinge_sweep(leaf_rec({}), "f5")
	var f_old := int(old.get("first", -9))
	ok(not old.has("limit2") and not old.has("max_deg2") and not old.has("placed") and absi(f_old - 24) <= 1, "A3 OLD: no new keys, first hit frame %d (24 +- 1)" % f_old)
	var two: Dictionary = Part.hinge_sweep(leaf_rec({"axis2": [1, 0, 0], "track2": [[0.0, 0.0], [3.0, -60.0]]}), "f5")
	ok(int(two.get("first", -9)) != f_old, "A3 CONTROL: with axis2 the first hit frame is %s, not %d" % [two.get("first"), f_old])
	# B1
	var bo := Vector3(430, 430, 50)
	var r1 := JointAxes.auto_place(block_rec(false, {}), 0, bo, 4 - 2)
	var pe := Vector3(400, 400, 50)
	ok(bool(r1.get("hidden", false)) and r1.get("kind") == "edge" and (r1["p"] as Vector3).distance_to(pe) <= 0.5 and absf(float(r1["moved_mm"]) - 42.43) <= 0.5, "B1 EDGE: %s" % str(r1))
	var far := 1e9
	for c in JointAxes.features_of(Part.body_faces(block_rec(false, {}), 1)[0]):
		far = minf(far, (c["p"] as Vector3).distance_to(bo * Part.MM) / Part.MM)
	ok(far > 40.0, "B1 CONTROL: unplaced, the pivot is %.1f mm from every visible feature (> 40)" % far)
	# B2
	var r2 := JointAxes.auto_place(block_rec(true, {}), 0, Vector3(200, 200, 50), 4)
	var pp: Vector3 = r2.get("p", Vector3.ZERO)
	ok(r2.get("kind") == "hole" and (pp.distance_to(Vector3(200, 200, 0)) <= 0.5 or pp.distance_to(Vector3(200, 200, 100)) <= 0.5), "B2 HOLE: %s" % str(r2))
	# B3
	var r3 := JointAxes.auto_place(block_rec(false, {}), 0, Vector3(400, 200, 50), 2)
	ok(r3.get("hidden", true) == false and float(r3.get("moved_mm", 9)) == 0.0 and (r3["p"] as Vector3).is_equal_approx(Vector3(400, 200, 50)), "B3 STAYS: %s" % str(r3))
	# B4
	var s4: Dictionary = Part.hinge_sweep(block_rec(false, {"autoplace": true}), "f9")
	var s5: Dictionary = Part.hinge_sweep(block_rec(false, {}), "f9")
	ok(s4.get("placed", {}).get("kind", "") == "edge" and not s5.has("placed"), "B4 SWEEP: placed %s; without autoplace %s" % [str(s4.get("placed", {}).get("kind", "")), str(s5.has("placed"))])


func ui_bars() -> void:
	var m: Node = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(8)
	m.tour_step = -1
	if m.ui_tour != null:
		m.ui_tour.visible = false
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	root.content_scale_size = Vector2i(1280, 720)
	await idle(4)
	var ss: StartScreen = m.start_screen
	var pu: PartUI = m.bld.part
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://c24_test"))
	ss.dirs_override = ["user://c24_test"]
	ss.show_screen()
	await idle(3)
	await click_ctl(ss._cards["building"])
	if m.ui_save_ask != null and m.ui_save_ask.visible:
		m._save_ask_choose("discard")
	await idle(6)
	pu.set_on(false)
	pu.m.S.part = {}
	await process_frame
	var rec := block_rec(false, {})
	rec["features"].pop_back()
	m.S.part = rec
	m.S.part["seq"] = 2
	await click_ctl(pu.part_btn)
	await idle(3)
	m.bld.sync()
	await idle(3)
	pu._view_model()
	await idle(3)
	var n0: int = (m.S.part["features"] as Array).size()
	# open the dialog the way the Hinge tool does, with the part and the line already picked
	for round in 3:
		pu.open_dialog("hinge", -1)
		pu.hp["body"] = 0
		pu.hp["o"] = Vector3(0.43, 0.43, 0.05) if round == 2 else Vector3(0.4, 0.4, 0.0)
		pu.hp["d"] = Vector3(0, 0, 1)
		pu._hinge_rows()
		await idle(3)
		var ob: OptionButton = pu.dlg_rows.find_child("part_axis2", true, false)
		var de: LineEdit = pu.dlg_rows.find_child("part_deg2", true, false)
		var cb: CheckBox = pu.dlg_rows.find_child("part_snap", true, false)
		var sw: Label = pu.dlg_rows.find_child("part_snap_words", true, false)
		if round == 0:
			ok(ob != null and ob.item_count == 3 and de != null and cb != null and sw != null, "U1 ROWS: part_axis2 (%s items), part_deg2, part_snap, part_snap_words are in the dialog" % (ob.item_count if ob else -1))
			if ob == null:
				return
			pu.f_from.text = "0"
			pu.f_to.text = "90"
			pu.f_dur.text = "3"
			shot("c24_rows")
			await click_ctl(pu.ok_btn)
			await idle(3)
			var fs: Array = m.S.part["features"]
			var h0: Dictionary = fs[-1]
			ok(fs.size() == n0 + 1 and not h0.has("axis2") and not h0.has("track2") and not h0.has("autoplace") and not h0.has("placed"), "U2 CONTROL: with None, one step and no axis2 / track2 / autoplace / placed keys")
		elif round == 1:
			ob.select(1)
			ob.item_selected.emit(1)
			de.text = "40"
			de.text_changed.emit("40")
			pu.f_from.text = "0"
			pu.f_to.text = "90"
			pu.f_dur.text = "3"
			var n1: int = (m.S.part["features"] as Array).size()
			await click_ctl(pu.ok_btn)
			await idle(3)
			var fs1: Array = m.S.part["features"]
			var h1: Dictionary = fs1[-1]
			var sq := false
			var t40 := false
			if h1.has("axis2"):
				var a1 := Vector3(h1["axis"][0], h1["axis"][1], h1["axis"][2]).normalized()
				var a2 := Vector3(h1["axis2"][0], h1["axis2"][1], h1["axis2"][2]).normalized()
				sq = absf(a1.dot(a2)) < 1e-6
				t40 = absf(float(h1["track2"][-1][1]) - 40.0) < 1e-6
			ok(fs1.size() == n1 + 1 and sq and t40, "U2 SAVE: Sideways + 40: one step, axis2 square to axis (%s), track2 ends at 40 (%s)" % [sq, t40])
		else:
			await click_ctl(cb)
			await idle(2)
			var txt := sw.text
			ok(cb.button_pressed and txt.contains("middle of an edge"), "U3 SNAP: the words say '%s'" % txt)
			pu.f_from.text = "0"
			pu.f_to.text = "90"
			pu.f_dur.text = "3"
			shot("c24_snap")
			var n2: int = (m.S.part["features"] as Array).size()
			await click_ctl(pu.ok_btn)
			await idle(3)
			var fs2: Array = m.S.part["features"]
			var h2: Dictionary = fs2[-1]
			var oo := Vector3(float(h2["o"][0]), float(h2["o"][1]), float(h2["o"][2]))
			ok(fs2.size() == n2 + 1 and oo.distance_to(Vector3(400, 400, 50)) <= 0.5 and h2.has("placed"), "U3 SAVE: o = %s (400, 400, 50 within 0.5), placed %s" % [str(oo), str(h2.get("placed"))])
	ok(true, "U4 LOOK: screenshots written when C24_SHOT is set")


func _init() -> void:
	var wd := create_timer(240.0)
	wd.timeout.connect(func() -> void:
		if not done:
			print("FAIL watchdog: the test did not finish in 240 s")
			quit(1))
	_run()


func _run() -> void:
	if not Part.available():
		print("FAIL the CAD kernel is not available")
		done = true
		quit(1)
		return
	logic_bars()
	await ui_bars()
	print("c24: %d fail" % fails)
	done = true
	quit(1 if fails > 0 else 0)
