extends SceneTree
## godot --path . --position 4000,4000 -s tests/ppattern_test.gd     (GAP 30 PATTERN: copies of a body in a row or round an axis; scripts/build/part.gd _pattern, part_ui.gd _pattern_open; needs a window and the CAD DLL)
## Bars:
##   1 RIBBON    Pattern by real clicks (its caption menu, CREATE): the dialog opens; linear 3 copies, spacing 150 mm, X, New bodies; the preview says 3 bodies while typing; OK by click = ONE undo step and one "pattern" step
##   2 LINEAR    a 100 mm cube, 3 copies 150 mm apart as new bodies: 3 bodies, total volume 3e-3 m3 within 1e-8
##   3 CIRCULAR  a 20 mm cube 100 mm from the Y axis, 6 copies round Y (full turn), New bodies, by real clicks: 6 bodies, each centre 100 mm from the axis within 0.01 mm
##   4 JOIN      (record) the same row joined into the body (the default): one body, volume 3e-3 m3 within 1e-8
##   5 FILE      save, new scene, load: the same record, the same bodies and volume
##   6 SHOT      the Part view with the pattern: C:/Temp/claude/ppattern/shot.png (the dialog open: shot_dialog.png)
## Only user:// is written (and the screenshots). With no DLL it says so and stops.
var fails := 0
var m: Node
const SHOT := "C:/Temp/claude/ppattern"
const DIRT := "user://ppattern_test"
const CUBE_M3 := 1e-3   # m3: a 100 mm cube


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


## a Part tool as a user reaches it: its own button, else its group caption menu, else More (as psweep_test does)
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


## types a value into a dialog field as the user does: the text, then the change (the field previews on it)
func typed(le: LineEdit, t: String) -> void:
	le.text = t
	le.text_changed.emit(t)
	await idle(2)


func E(v: float) -> String:
	return String.num_scientific(v)


func cube_ents(cx: float, cy: float, s: float) -> Array:
	return [{"k": "rect", "a": [cx - s / 2.0, cy - s / 2.0], "b": [cx + s / 2.0, cy + s / 2.0]}]


## a body record: the sketch of a square on the Front plane and its extrude (both sides when both)
func body_rec(cx: float, s: float, dist: float, both: bool) -> Dictionary:
	var r := Part.make("Pattern test")
	r["features"] = [
		{"t": "sketch", "id": "f1", "name": "Sketch1", "plane": "front", "ents": cube_ents(cx, 0.0, s), "dims": []},
		{"t": "extrude", "id": "f2", "name": "Extrude1", "sketch": "f1", "dist": dist, "both": both, "op": "new"},
	]
	r["seq"] = 2
	return r


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
		print("SKIP: no KineCAD DLL; ppattern needs the kernel")
		quit(0)
		return
	ss.show_screen()
	await idle(3)
	await click_ctl(ss._cards["building"])
	if m.ui_save_ask != null and m.ui_save_ask.visible:
		m._save_ask_choose("discard")
	await idle(6)
	await click_ctl(pu.part_btn)
	await idle(3)
	ok(pu.on, "0 Part workspace on")
	m.S.part = body_rec(0.0, 100.0, 100.0, false)
	bld.sync()
	await idle(2)
	var path := DIRT + "/ppattern.json"
	# 1 RIBBON: Pattern by real clicks, linear 3 copies, 150 mm, X, New bodies
	var n0: int = m.undo.size()
	await press_tool(pu, "Pattern")
	ok(pu.dlg.size() > 0 and String(pu.dlg["t"]) == "pattern" and pu.side.visible, "1 Pattern opens its dialog on the right")
	await typed(pu.pat["count"], "3")
	await typed(pu.pat["mm"], "150")
	(pu.pat["op"] as OptionButton).select(1)
	(pu.pat["op"] as OptionButton).item_selected.emit(1)
	await idle(2)
	ok(int(pu.prev.get("bodies", 0)) == 3, "1 live preview while typing: %s bodies (want 3)" % [pu.prev.get("bodies", 0)])
	ok(pu.dlg_info.text.begins_with("3 bodies"), "1 the dialog says: %s" % pu.dlg_info.text)
	ok(not pu.ok_btn.disabled, "1 OK is on")
	await click_ctl(pu.ok_btn)
	await idle(3)
	var pf := Part.feature(m.S.part, "f3")
	ok(String(pf.get("t", "")) == "pattern" and String(pf.get("kind", "")) == "linear" and int(pf.get("count", 0)) == 3 and String(pf.get("op", "")) == "new", "1 the record: a linear pattern of 3, new bodies (%s)" % [pf])
	ok(m.undo.size() == n0 + 1, "1 OK = ONE undo step (%d)" % (m.undo.size() - n0))
	ok(pu.dlg.is_empty() and pu.tool == "", "1 the dialog closes after OK")
	# 2 LINEAR bars
	var rp := Part.replay(m.S.part)
	var vol := float(rp["volume"])
	ok(int(rp["bodies"]) == 3 and (rp["errors"] as Dictionary).is_empty(), "2 3 bodies, no failed step (%s, errors %s)" % [rp["bodies"], rp["errors"]])
	ok(absf(vol - 3.0 * CUBE_M3) < 1e-8, "2 total volume %s = 3 cubes 3e-3 m3 within 1e-8" % E(vol))
	# 3 CIRCULAR: a 20 mm cube 100 mm out from the Y axis, 6 copies round Y by real clicks, New bodies
	m.S.part = body_rec(100.0, 20.0, 20.0, true)
	bld.sync()
	await idle(2)
	n0 = m.undo.size()
	await press_tool(pu, "Pattern")
	(pu.pat["kind"] as OptionButton).select(1)
	(pu.pat["kind"] as OptionButton).item_selected.emit(1)
	await idle(2)
	await typed(pu.pat["count"], "6")
	await typed(pu.pat["deg"], "360")
	(pu.pat["axis"] as OptionButton).select(1)
	(pu.pat["op"] as OptionButton).select(1)
	(pu.pat["op"] as OptionButton).item_selected.emit(1)
	await idle(2)
	ok(int(pu.prev.get("bodies", 0)) == 6, "3 live preview: %s bodies (want 6)" % [pu.prev.get("bodies", 0)])
	await click_ctl(pu.ok_btn)
	await idle(3)
	var pc := Part.feature(m.S.part, "f3")
	ok(String(pc.get("kind", "")) == "circular" and String(pc.get("axis", "")) == "y", "3 the record: a circular pattern round Y (%s)" % [pc])
	ok(m.undo.size() == n0 + 1, "3 OK = ONE undo step (%d)" % (m.undo.size() - n0))
	var rc := Part.replay(m.S.part, -1, {"props": true})
	var props: Array = rc["props"]
	ok(int(rc["bodies"]) == 6 and (rc["errors"] as Dictionary).is_empty(), "3 6 bodies, no failed step (%s, errors %s)" % [rc["bodies"], rc["errors"]])
	var worst := 0.0
	for p in props:
		var c: Vector3 = p["center"]
		worst = maxf(worst, absf(Vector2(c.x, c.z).length() * 1000.0 - 100.0))
	ok(props.size() == 6 and worst < 0.01, "3 each centre 100 mm from the Y axis, worst %.5f mm off (want < 0.01)" % worst)
	# 4 JOIN (record): the row joined into the body (the default) is one body with the same volume
	var rj := Part.make("Join test")
	rj["features"] = [
		{"t": "sketch", "id": "f1", "name": "Sketch1", "plane": "front", "ents": cube_ents(0.0, 0.0, 100.0), "dims": []},
		{"t": "extrude", "id": "f2", "name": "Extrude1", "sketch": "f1", "dist": 100.0, "both": false, "op": "new"},
		{"t": "pattern", "id": "f3", "name": "Pattern1", "body": 0, "kind": "linear", "count": 3, "mm": 150.0, "dir": "x", "op": "join"},
	]
	var rjr := Part.replay(rj)
	ok(int(rjr["bodies"]) == 1 and (rjr["errors"] as Dictionary).is_empty() and absf(float(rjr["volume"]) - 3.0 * CUBE_M3) < 1e-8, "4 joined: 1 body, volume %s (want 3e-3 within 1e-8, errors %s)" % [E(float(rjr["volume"])), rjr["errors"]])
	# 5 FILE: save, new scene, load: the same record, the same bodies and volume
	var vol0 := float(rc["volume"])
	var saved := JSON.stringify(JSON.parse_string(JSON.stringify(m.S.part)))
	var fh := FileAccess.open(path, FileAccess.WRITE)
	fh.store_string(JSON.stringify(m.S.to_dict(m.B, false)))
	fh.close()
	m._new_scene()
	await idle(3)
	if m.ui_save_ask != null and m.ui_save_ask.visible:
		m._save_ask_choose("discard")
	await idle(2)
	ok(m.S.part.is_empty(), "5 a new scene has no part")
	m._load_scene(path)
	await idle(4)
	bld.sync()
	await idle(2)
	var rl := Part.replay(m.S.part)
	ok(JSON.stringify(JSON.parse_string(JSON.stringify(m.S.part))) == saved and int(rl["bodies"]) == 6 and absf(float(rl["volume"]) - vol0) < 1e-9, "5 reopened: the same record, %d bodies, volume %s (was %s)" % [int(rl["bodies"]), E(float(rl["volume"])), E(vol0)])
	# 6 SHOT: the dialog open on a fresh pattern, then the finished view
	await press_tool(pu, "Pattern")
	await idle(3)
	var img := root.get_texture().get_image()
	img.save_png("%s/shot_dialog.png" % SHOT)
	await click_ctl(pu.cancel_btn)
	await idle(2)
	pu._view_model()
	await idle(3)
	img = root.get_texture().get_image()
	img.save_png("%s/shot.png" % SHOT)
	print("ppattern: %d fail" % fails)
	quit(1 if fails > 0 else 0)
