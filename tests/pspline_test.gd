extends SceneTree
## godot --headless --path . -s tests/pspline_test.gd     (GAP 1 SPLINE: a sketch Spline entity in the Part record, the Expert SKETCH ribbon "Spline"; needs the CAD DLL)
## A flat-panel outline: the closed spline ring (0,0), (50,-10), (100,0), (100,60), (0,60) mm, clicked on the Front plane through the real
## ribbon button and the canvas (a click on the first point closes it), dragged and put back, then Finish sketch, then Extrude 40 mm.
## Bars, written before measuring (every number in the record is mm; volumes in m3):
##   1 CLICKS    the Spline ribbon button, five clicks and a click on the first point: ONE closed bspline entity with the five points
##   2 UNDO      the whole sketch (start, spline, drag, finish) is ONE undo step
##   3 DRAG      a point dragged to (110, 70) moves to it (no undo step); dragged back to (100, 60) the record is exactly as before
##   4 REPLAY    Extrude 40 mm: errors = {}, bodies = 1, the solid is closed (0 open mesh edges), volume within 1 percent of the
##               CURVE THE SKETCH DRAWS x 40 mm (the solid is what the user saw). Redefined before merge: the first version compared
##               with the line polygon through the clicks (6500 mm2), which a smooth curve through sharp corners cannot meet, and
##               it hid that the kernel's curve was not the drawn one (+13 percent)
##   4b SMOOTH   (data) a closed spline through 8 points of an ellipse 100 x 60 mm, extruded 40 mm: volume within 1 percent of pi a b h
##   5 FILE      save -> new scene -> load: the same record, the same replay volume
## Only user:// is written (the test folder) and the screenshots in C:/Temp/claude/pspline/.
const SHOT := "C:/Temp/claude/pspline"
const DIRT := "user://pspline_test"
const RING := [[0, 0], [50, -10], [100, 0], [100, 60], [0, 60]]
var fails := 0
var m: Node


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
	var p := c.get_global_rect().get_center()
	await ev_move(p, false)
	await ev_mouse(p, true)
	await ev_mouse(p, false)
	await idle(2)


func click_at(p: Vector2) -> void:
	await ev_move(p, false)
	await ev_mouse(p, true)
	await ev_mouse(p, false)
	await idle(2)


## a Part tool as a user reaches it: its own ribbon button when shown, else its group caption or More
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


func type_in(le: LineEdit, txt: String) -> void:
	await click_ctl(le)
	var sa := InputEventKey.new()   # select all, then type over it
	sa.keycode = KEY_A
	sa.physical_keycode = KEY_A
	sa.ctrl_pressed = true
	sa.pressed = true
	root.push_input(sa, true)
	await process_frame
	for ch in txt:
		var e := InputEventKey.new()
		e.keycode = KEY_0 + int(ch)
		e.physical_keycode = KEY_0 + int(ch)
		e.unicode = ch.unicode_at(0)
		e.pressed = true
		root.push_input(e, true)
		await process_frame
	var k := InputEventKey.new()
	k.keycode = KEY_ENTER
	k.physical_keycode = KEY_ENTER
	k.pressed = true
	root.push_input(k, true)
	await idle(2)


## the screen point of a sketch point (mm) on the Front plane
func sp2(x: float, y: float) -> Vector2:
	return m.cam.unproject_position(Part.to_world(Part.plane("front"), Vector2(x, y)))


func ps() -> String:
	return JSON.stringify(m.S.part) if not m.S.part.is_empty() else "{}"


func _key(p: Vector3) -> String:
	return "%d,%d,%d" % [roundi(p.x * 1e6), roundi(p.y * 1e6), roundi(p.z * 1e6)]


## mesh edges used other than twice (0 = closed), welded at 1e-6 m
func open_edges(mesh: Mesh) -> int:
	if mesh == null:
		return -1
	var uses := {}
	for s in mesh.get_surface_count():
		var arr: Array = mesh.surface_get_arrays(s)
		var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX] if arr[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
		var n := idx.size() if idx.size() > 0 else v.size()
		for t in range(0, n - 2, 3):
			var tri := [idx[t], idx[t + 1], idx[t + 2]] if idx.size() > 0 else [t, t + 1, t + 2]
			for j in 3:
				var a := _key(v[tri[j]])
				var b := _key(v[tri[(j + 1) % 3]])
				var k: String = a + "|" + b if a < b else b + "|" + a
				uses[k] = int(uses.get(k, 0)) + 1
	var bad := 0
	for k in uses:
		if uses[k] != 2:
			bad += 1
	return bad


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
	ss.dirs_override = [DIRT]
	if not Part.available():
		print("SKIP: no KineCAD DLL (Part.available() false)")
		quit(0)
		return
	ss.show_screen()
	await idle(3)
	await click_ctl(ss._cards["building"])
	if m.ui_save_ask != null and m.ui_save_ask.visible:
		m._save_ask_choose("discard")
	await idle(6)
	# Nick 2026-10-28 (free 3D building, #100): the BUILDING card now opens a blank Easy Part itself. Start from the
	# state the card gave before (Part off, no part), so the clicks below drive the same opening they always did
	pu.set_on(false)
	pu.m.S.part = {}
	await process_frame
	await click_ctl(pu.part_btn)
	await idle(3)
	ok(pu.on, "0 Part workspace on")

	# 1 CLICKS: Front plane, the Spline button, five corners, then the first corner again
	var n0: int = m.undo.size()
	await click_ctl(pu.browser.find_child("part_plane_front", true, false))
	ok(pu.sk != "", "1 the Front plane starts a sketch")
	await press_tool(pu, "Spline")
	ok(pu.tool == "Spline", "1 the Spline button selects the Spline tool (tool %s)" % pu.tool)
	for q in RING:
		await click_at(sp2(q[0], q[1]))
	await click_at(sp2(0, 0))
	var ents: Array = pu._sk().get("ents", [])
	ok(ents.size() == 1 and String(ents[0]["k"]) == "bspline" and bool(ents[0]["closed"]) and (ents[0]["pts"] as Array).size() == 5,
		"1 five clicks and the first point: one closed spline, %s" % [ents])
	await shot("spline_closed")

	# 3 DRAG: the point (100, 60) to (110, 70) and back
	await ev_move(sp2(100, 60), false)
	await ev_mouse(sp2(100, 60), true)
	await ev_move(sp2(105, 65))
	await ev_move(sp2(110, 70))
	await ev_mouse(sp2(110, 70), false)
	await idle(2)
	var moved := Part.v2(pu._sk()["ents"][0]["pts"][3])
	ok(moved.is_equal_approx(Vector2(110, 70)), "3 dragged point is at (110, 70): %s" % [moved])
	await ev_move(sp2(110, 70), false)
	await ev_mouse(sp2(110, 70), true)
	await ev_move(sp2(100, 60))
	await ev_mouse(sp2(100, 60), false)
	await idle(2)
	var back := Part.v2(pu._sk()["ents"][0]["pts"][3])
	ok(back.is_equal_approx(Vector2(100, 60)) and (pu._sk()["ents"][0]["pts"] as Array).size() == 5, "3 dragged back to (100, 60): %s" % [back])

	# 2 UNDO: finish the sketch = one step
	await click_ctl(pu.finish_btn)
	ok(pu.sk == "" and m.undo.size() == n0 + 1, "2 Finish sketch: one undo step for the spline sketch (%d)" % (m.undo.size() - n0))

	# 4 REPLAY: Extrude 40 mm
	await press_tool(pu, "Extrude")
	await type_in(pu.f_num, "40")
	var r: Dictionary = Part.replay(m.S.part)
	var drawn := Part.spline_curve(RING, true, 64)   # the curve on screen, finely sampled
	var area := 0.0
	for i in drawn.size() - 1:
		area += drawn[i].x * drawn[i + 1].y - drawn[i + 1].x * drawn[i].y
	var want := absf(area) * 0.5 * 40.0 * 1e-9
	var vol := float(r["volume"])
	var eo := open_edges(pu.part_mesh.mesh)
	ok((r["errors"] as Dictionary).is_empty() and int(r["bodies"]) == 1 and absf(vol - want) < 0.01 * want,
		"4 replay: errors %s, bodies %d, volume %s (the drawn curve x 40 mm: %s, within 1 percent)" % [r["errors"], int(r["bodies"]), vol, want])
	ok(eo == 0, "4 the solid is closed: %d open mesh edges" % eo)
	await shot("spline_extruded")
	await shot("shot")

	# 4b SMOOTH (data): a closed spline through 8 points of an ellipse 100 x 60 mm, extruded 40 mm: volume within 1 percent of pi a b h
	var er := Part.make("ell")
	var epts := []
	for j in 8:
		var t := TAU * j / 8.0
		epts.append([50.0 * cos(t), 30.0 * sin(t)])
	var ek := Part.new_feature(er, "sketch", {"plane": "front", "ents": [{"k": "bspline", "pts": epts, "closed": true}], "dims": []})
	er["features"].append(ek)
	er["features"].append(Part.new_feature(er, "extrude", {"sketch": ek["id"], "dist": 40.0, "both": false, "op": "new"}))
	var re: Dictionary = Part.replay(er)
	var want_e := PI * 50.0 * 30.0 * 40.0 * 1e-9
	ok((re["errors"] as Dictionary).is_empty() and int(re["bodies"]) == 1 and absf(float(re["volume"]) - want_e) < 0.01 * want_e,
		"4b smooth ring (ellipse 100 x 60, 8 points) extruded 40: volume %s (ellipse %s, within 1 percent)" % [re["volume"], want_e])

	# 5 FILE
	var saved := JSON.stringify(JSON.parse_string(ps()))
	var path := DIRT + "/pspline.json"
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
	var r2: Dictionary = Part.replay(m.S.part)
	ok(JSON.stringify(JSON.parse_string(ps())) == saved and absf(float(r2["volume"]) - vol) < 1e-9,
		"5 reopened: the same record, volume %s (was %s)" % [float(r2["volume"]), vol])

	print("pspline: %d fail" % fails)
	quit(1 if fails > 0 else 0)


func shot(nm: String) -> void:
	await idle(3)
	DirAccess.make_dir_recursive_absolute(SHOT)
	var img: Image = root.get_texture().get_image() if root.get_texture() != null else null
	if img != null:   # (no picture without a window: the headless run skips the shots)
		img.save_png("%s/%s.png" % [SHOT, nm])
