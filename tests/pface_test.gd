extends SceneTree
## godot --path . --position 4000,4000 -s tests/pface_test.gd     (GAP 10: OFFSET FACE and DRAFT in the Part workspace; needs a window and the CAD DLL, KineCAD v3)
## Bars, written before measuring (every number in the record is mm; the kernel gets metres):
##   1 NO DLL    Part.force_off: the Part tools (Offset face, Draft) are greyed with the reason (Part.why_not)
##   2 OFFSET +2 (data): a 100 mm cube (100 x 100 x 100 extrude), its top face (picked by centre + normal) offset +2 mm: the top at 102 mm (within 1e-6),
##               volume 1.02e-3 m3 within 1e-8, no step failed
##   3 OFFSET -2 (data): the same face offset -2 mm: the top at 98 mm, volume 0.98e-3 m3 within 1e-8
##   4 RE-FIND (data): the same offset step after the sketch is made 120 mm wide: the face is found again, volume 1.2e-3 + 2.4e-5 within 1e-8
##   5 DRAFT 5 deg (data): a 100 x 60 x 40 extrude, its +X wall drafted 5 deg (pull Z): that wall leans 5 deg from the pull plane within 0.1 deg; no step failed
##   6 OFFSET (real clicks): Part on, Offset face from the MODIFY caption, click the top face (it turns sky blue; the dialog counts 1 picked), type 2:
##               ONE undo step, a feature 'offset_face', volume 1.02e-3 within 1e-8; undo back to the cube, redo to 1.02e-3
##   7 FILE: save + new scene + load: the same record, the same volume
##   8 DRAFT (real clicks): Draft from the caption, click the +X wall, type 5 (pull Z is the default): ONE undo step, the wall leans 5 deg within 0.1
##   9 SHOT: C:/Temp/claude/pface/shot.png is the Offset face dialog with its live preview (looked at by the author)
## Only user:// is written (and the screenshots).
const KCad := preload("res://scripts/kcad.gd")
var fails := 0
var m: Node
const SHOT := "C:/Temp/claude/pface"
const DIRT := "user://pface_test"
const MM := 0.001


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


func key(k: Key, ctrl := false, uni := 0) -> void:
	for down in [true, false]:
		var e := InputEventKey.new()
		e.keycode = k
		e.physical_keycode = k
		e.unicode = uni
		e.pressed = down
		e.ctrl_pressed = ctrl
		root.push_input(e, true)
		await process_frame


func click_ctl(c: Control) -> void:
	var p := c.get_global_rect().get_center()
	await ev_move(p, false)
	await ev_mouse(p, true)
	await ev_mouse(p, false)
	await idle(2)


func click_ctl_at(p: Vector2) -> void:
	await ev_move(p, false)
	await ev_mouse(p, true)
	await ev_mouse(p, false)
	await idle(2)


## a Part tool as a user reaches it: its own button when the row shows it; else its group's caption menu (RIBBON_REST)
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
	ok(false, "%s is not under a caption" % t)


func type_in(le: LineEdit, txt: String) -> void:
	await click_ctl(le)
	await key(KEY_A, true)
	for ch in txt:
		await key(KEY_0 + int(ch) if ch != "." else KEY_PERIOD, false, ch.unicode_at(0))
	await key(KEY_ENTER)
	await idle(2)


func shot(nm: String) -> void:
	await idle(3)
	DirAccess.make_dir_recursive_absolute(SHOT)
	root.get_texture().get_image().save_png("%s/%s.png" % [SHOT, nm])


func ps() -> String:
	return JSON.stringify(m.S.part) if not m.S.part.is_empty() else "{}"


func near(a: float, b: float, tol: float) -> bool:
	return absf(a - b) <= tol


## a record: one rectangle w x h (mm) on the Front plane, extruded d mm along +Z
static func base_rec(w: float, h: float, d: float) -> Dictionary:
	var rec := Part.make("Pface")
	rec["features"] = [
		{"t": "sketch", "id": "f1", "name": "Sketch1", "plane": "front", "ents": [{"k": "rect", "a": [0.0, 0.0], "b": [w, h]}], "dims": []},
		{"t": "extrude", "id": "f2", "name": "Extrude1", "sketch": "f1", "dist": d, "both": false, "op": "new", "taper": 0.0}]
	rec["seq"] = 2
	return rec


## the face of a replay whose outward normal is (within 0.01) along axis, the furthest out along it; {} if none
static func outer_face(faces: Array, axis: Vector3) -> Dictionary:
	var best := {}
	for f in faces:
		if (f["n"] as Vector3).dot(axis) > 0.99 and (best.is_empty() or (f["c"] as Vector3).dot(axis) > (best["c"] as Vector3).dot(axis)):
			best = f
	return best


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
	ss.show_screen()
	await idle(3)
	await click_ctl(ss._cards["building"])
	if m.ui_save_ask != null and m.ui_save_ask.visible:
		m._save_ask_choose("discard")
	await idle(6)
	ok(m.cur_page == "BUILD" and m.S.kind == "building" and bld.on and pu.part_btn.visible, "0 a 3D BUILDING project on BUILD with the Part button (page %s)" % m.cur_page)

	# 1 NO DLL
	Part.force_off = true
	await click_ctl(pu.part_btn)
	await idle(3)
	var grey := true
	for t in ["Offset face", "Draft"]:
		var b: Button = pu.tool_btns[t]
		grey = grey and b.disabled and b.tooltip_text.contains("KineCAD")
	ok(grey, "1 no DLL: Offset face and Draft greyed with the KineCAD reason")
	Part.force_off = false
	if not Part.available():
		print("SKIP: no KineCAD DLL (Part.available() false); only the no-DLL bar runs")
		finish()
		return
	await click_ctl(pu.part_btn)   # off again
	await idle(2)
	await click_ctl(pu.part_btn)   # on
	await idle(2)

	# 2 / 3 OFFSET (data)
	var box := base_rec(100.0, 100.0, 100.0)
	var r0: Dictionary = Part.replay(box, -1, {"faces": true})
	ok(near(float(r0["volume"]), 1e-3, 1e-9), "2 the 100 mm cube: volume %s" % String.num_scientific(float(r0["volume"])))
	var top: Dictionary = outer_face(r0["faces"], Vector3(0, 0, 1))
	var up_rec := box.duplicate(true)
	up_rec["features"].append({"t": "offset_face", "id": "f3", "name": "Offset1", "body": 0, "face": Part.describe_face(top), "mm": 2.0})
	up_rec["seq"] = 3
	var r2: Dictionary = Part.replay(up_rec, -1, {"faces": true})
	var top2: Dictionary = outer_face(r2["faces"], Vector3(0, 0, 1))
	ok(r2["errors"].is_empty() and near(float(r2["volume"]), 1.02e-3, 1e-8) and not top2.is_empty() and near((top2["c"] as Vector3).z, 0.102, 1e-6),
		"2 OFFSET +2 mm: top %s mm (want 102), volume %s (want 1.02e-3), errors %s" % [snappedf((top2["c"] as Vector3).z / MM, 0.001) if not top2.is_empty() else -1, String.num_scientific(float(r2["volume"])), r2["errors"]])
	var dn_rec := box.duplicate(true)
	dn_rec["features"].append({"t": "offset_face", "id": "f3", "name": "Offset1", "body": 0, "face": Part.describe_face(top), "mm": -2.0})
	dn_rec["seq"] = 3
	var r3: Dictionary = Part.replay(dn_rec, -1, {"faces": true})
	var top3: Dictionary = outer_face(r3["faces"], Vector3(0, 0, 1))
	ok(r3["errors"].is_empty() and near(float(r3["volume"]), 0.98e-3, 1e-8) and not top3.is_empty() and near((top3["c"] as Vector3).z, 0.098, 1e-6),
		"3 OFFSET -2 mm: top %s mm (want 98), volume %s (want 0.98e-3), errors %s" % [snappedf((top3["c"] as Vector3).z / MM, 0.001) if not top3.is_empty() else -1, String.num_scientific(float(r3["volume"])), r3["errors"]])

	# 4 RE-FIND: the sketch made 120 mm wide, the same stored face
	var wide := base_rec(120.0, 100.0, 100.0)
	wide["features"].append(up_rec["features"][2].duplicate(true))
	wide["seq"] = 3
	var r4: Dictionary = Part.replay(wide, -1, {"faces": true})
	ok(r4["errors"].is_empty() and near(float(r4["volume"]), 1.224e-3, 1e-8), "4 RE-FIND: the face is found again on the 120 mm box: volume %s (want 1.224e-3), errors %s" % [String.num_scientific(float(r4["volume"])), r4["errors"]])

	# 5 DRAFT (data): 100 x 60 x 40, the +X wall at 5 deg from the pull plane
	var slab := base_rec(100.0, 60.0, 40.0)
	var rs: Dictionary = Part.replay(slab, -1, {"faces": true})
	var wall: Dictionary = outer_face(rs["faces"], Vector3(1, 0, 0))
	var dr_rec := slab.duplicate(true)
	dr_rec["features"].append({"t": "draft", "id": "f3", "name": "Draft1", "body": 0, "faces": [Part.describe_face(wall)], "deg": 5.0, "dir": "z"})
	dr_rec["seq"] = 3
	var rd: Dictionary = Part.replay(dr_rec, -1, {"faces": true})
	var lean := -1.0
	for f in rd["faces"]:
		if (f["n"] as Vector3).x > 0.9:
			lean = rad_to_deg(asin(absf((f["n"] as Vector3).z)))
	ok(rd["errors"].is_empty() and absf(lean - 5.0) <= 0.1, "5 DRAFT 5 deg: the +X wall leans %.4f deg (want 5 within 0.1), errors %s" % [lean, rd["errors"]])

	# 6 OFFSET by real clicks
	m.S.part = box.duplicate(true)
	bld.sync()
	await idle(3)
	pu._view_model()
	await idle(3)
	var n0: int = m.undo.size()
	await press_tool(pu, "Offset face")
	ok(pu.dlg.size() > 0 and String(pu.dlg["t"]) == "offset_face" and pu.face_cache.size() >= 6, "6 Offset face: its dialog, %d faces to pick" % pu.face_cache.size())
	var tf := {}
	for fc in pu.face_cache:
		if (fc["n"] as Vector3).z > 0.99 and (tf.is_empty() or (fc["c"] as Vector3).z > (tf["c"] as Vector3).z):
			tf = fc
	await click_ctl_at(m.cam.unproject_position(tf["c"]))
	ok(pu.picked.size() == 1 and (pu.picked[0]["c"] as Vector3).distance_to(tf["c"]) < 1e-6, "6 the top face picked by a click (%d picked)" % pu.picked.size())
	await type_in(pu.f_num, "2")
	await shot("shot")
	ok(m.undo.size() == n0 + 1 and m.S.part["features"].size() == 3 and String(m.S.part["features"][2]["t"]) == "offset_face"
		and near(float(pu.res["volume"]), 1.02e-3, 1e-8), "6 OFFSET +2 by clicks: ONE step (%d), feature offset_face, volume %s (want 1.02e-3)" % [m.undo.size() - n0, String.num_scientific(float(pu.res["volume"]))])
	m._undo()
	await idle(3)
	ok(m.S.part["features"].size() == 2 and near(float(pu.res["volume"]), 1e-3, 1e-8), "6 undo: back to the cube (volume %s)" % String.num_scientific(float(pu.res["volume"])))
	m._redo()
	await idle(3)
	ok(m.S.part["features"].size() == 3 and near(float(pu.res["volume"]), 1.02e-3, 1e-8), "6 redo: offset again, volume %s" % String.num_scientific(float(pu.res["volume"])))

	# 7 FILE
	var saved := JSON.stringify(JSON.parse_string(ps()))
	var path := DIRT + "/pface.json"
	var fh := FileAccess.open(path, FileAccess.WRITE)
	fh.store_string(JSON.stringify(m.S.to_dict(m.B, false)))
	fh.close()
	m._new_scene()
	await idle(3)
	if m.ui_save_ask != null and m.ui_save_ask.visible:
		m._save_ask_choose("discard")
	await idle(2)
	m._load_scene(path)
	await idle(4)
	bld.sync()
	await idle(2)
	ok(JSON.stringify(JSON.parse_string(ps())) == saved and near(float(pu.res["volume"]), 1.02e-3, 1e-8), "7 reopened: the same record, volume %s" % String.num_scientific(float(pu.res["volume"])))

	# 8 DRAFT by real clicks
	m.S.part = slab.duplicate(true)
	bld.sync()
	await idle(3)
	pu._view_model()
	await idle(3)
	var n1: int = m.undo.size()
	await press_tool(pu, "Draft")
	ok(pu.dlg.size() > 0 and String(pu.dlg["t"]) == "draft", "8 Draft: its dialog")
	var wf := {}
	for fc in pu.face_cache:
		if (fc["n"] as Vector3).x > 0.99 and (wf.is_empty() or (fc["c"] as Vector3).x > (wf["c"] as Vector3).x):
			wf = fc
	await click_ctl_at(m.cam.unproject_position(wf["c"]))
	ok(pu.picked.size() == 1, "8 the +X wall picked by a click (%d picked)" % pu.picked.size())
	await type_in(pu.f_num, "5")
	var lean2 := -1.0
	for f in pu.res.get("faces", []):
		if (f["n"] as Vector3).x > 0.9:
			lean2 = rad_to_deg(asin(absf((f["n"] as Vector3).z)))
	ok(m.undo.size() == n1 + 1 and String(m.S.part["features"][-1]["t"]) == "draft" and absf(lean2 - 5.0) <= 0.1 and pu.res["errors"].is_empty(),
		"8 DRAFT 5 deg by clicks: ONE step (%d), the wall leans %.4f deg (want 5 within 0.1), errors %s" % [m.undo.size() - n1, lean2, pu.res["errors"]])
	m._undo()
	await idle(3)
	ok(m.S.part["features"].size() == 2 and not pu.res.get("faces", []).is_empty(), "8 undo: the 100 x 60 x 40 slab without the draft")

	finish()


func finish() -> void:
	print("pface: %d fail" % fails)
	print("PASS" if fails == 0 else "FAIL")
	quit(1 if fails > 0 else 0)
