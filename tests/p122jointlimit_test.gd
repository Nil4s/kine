extends SceneTree
## p122jointlimit (Friday plan item 122: Joint limits with sliders, 0 to 90 deg). A hinge (Part's Hinge tool) gets a Joint limit slider in its dialog:
## the part may not swing past it either way. Default 90 = no stop, so every older hinge plays as before.
## Bars (written before the code ran; closed forms from the geometry, never read back from the code's own variables):
## A door: a leaf 800 x 40 x 2000 mm hinged on its z edge at the origin, swing linear 0 -> 90 deg in 3 s, 25 fps (frame i = 1.2 i deg while unlimited).
## With limit 30 the swing is 30 deg per second (raw = 30 t), so the frames past the stop are those with t > 1 s: frames 26..75 = 50 frames.
## The leaf's far corner (800, 20) is at y = 800 sin(th) + 20 cos(th): 417.3 at 30 deg.
##   1 CLAMP     limit 30, a far stop: limited_frames = 50 (frames 26..75), limit reported as 30
##   2 CLEAR30   limit 30, a stop face at y = 430 (the corner never reaches it below 30 deg): no interference, first = -1
##   3 HIT30     limit 30, a stop face at y = 410: the first interfering frame is 25 (the corner is at 408.9 at 29.3 deg, so frame 24 at 28.8 deg is clear
##               and frame 25 at 30 deg is in), and deg_first = 30 within 0.01
##   4 DEFAULT   no limit key: limit 90, limited_frames 0, the same 430 stop IS hit (first >= 0)
##   5 NEWUNDO   the dialog: Hinge tool by real clicks (Part 1 picked, its edge clicked), the Joint limit slider dragged to 40: the row reads "40 deg",
##               OK makes ONE step whose limit is 40 within 0.5, and one Ctrl+Z takes the hinge away
##   6 PLAY40    the Play slider at 100 % shows the hinge at 40 deg within 0.5 (not 90): the view stops at the limit
## Shots: C:/Temp/claude/p122jointlimit/
const SHOT_UI := "C:/Temp/claude/p122jointlimit"
const DIR_UI := "user://p122jointlimit_test"
const FPS := 25.0
const DOOR_W := 800.0
const DOOR_T := 40.0
const DOOR_H := 2000.0

var fails := 0


func ok(c: bool, w: String) -> void:
	print(("ok   " if c else "FAIL ") + w)
	fails += 0 if c else 1


## the door record: the leaf (body 0), a stop wall at y = stop_y, the hinge f5 with the track and (optionally) its limit key
func door(stop_y: float, track: Array, limit = null) -> Dictionary:
	var rec := Part.make("Door")
	var hf := {"t": "hinge", "id": "f5", "name": "Hinge1", "body": 0, "o": [0, 0, 0], "axis": [0, 0, 1], "track": track, "clear": []}
	if limit != null:
		hf["limit"] = limit
	rec["features"] = [
		{"t": "sketch", "id": "f1", "name": "Sketch1", "plane": "front", "ents": [{"k": "rect", "a": [0, -DOOR_T / 2], "b": [DOOR_W, DOOR_T / 2]}], "dims": []},
		{"t": "extrude", "id": "f2", "name": "Extrude1", "sketch": "f1", "dist": DOOR_H, "both": false, "op": "new"},
		{"t": "sketch", "id": "f3", "name": "Sketch2", "plane": "front", "ents": [{"k": "rect", "a": [-1600, stop_y], "b": [1600, stop_y + 10]}], "dims": []},
		{"t": "extrude", "id": "f4", "name": "Extrude2", "sketch": "f3", "dist": DOOR_H, "both": false, "op": "new"},
		hf,
	]
	return rec


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


func ev_move(p: Vector2) -> void:
	var e := InputEventMouseMotion.new()
	e.position = p
	e.global_position = p
	root.push_input(e, true)
	await process_frame


func click_at(p: Vector2) -> void:
	await ev_move(p)
	await ev_mouse(p, true)
	await ev_mouse(p, false)
	await idle(2)


func click_ctl(c: Control) -> void:
	await click_at(c.get_global_rect().get_center())


func shot_ui(nm: String) -> void:
	await idle(3)
	DirAccess.make_dir_recursive_absolute(SHOT_UI)
	root.get_texture().get_image().save_png("%s/%s.png" % [SHOT_UI, nm])


func _init() -> void:
	if not Part.available():
		print("SKIP 1-4: the CAD kernel is not available")
	else:
		var swing: Array = [[0.0, 0.0], [3.0, 90.0]]
		# 1 CLAMP: limit 30 on a far stop (y = 810): the curve asks past 30 on frames 26..75
		var far := Part.hinge_sweep(door(810.0, swing, 30.0), "f5", FPS)
		ok(bool(far["ok"]) and int(far["limited_frames"]) == 50 and absf(float(far["limit"]) - 30.0) < 1e-6,
				"1 CLAMP: limit 30: %s frames past the stop (50 by the closed form), limit reported %s" % [far.get("limited_frames", "?"), far.get("limit", "?")])
		# 2 CLEAR30: the corner stays under 417.3 mm, so a face at 430 is never reached
		var clear := Part.hinge_sweep(door(430.0, swing, 30.0), "f5", FPS)
		ok(bool(clear["ok"]) and int(clear["first"]) == -1 and int(clear["hit_frames"]) == 0,
				"2 CLEAR30: stop at 430 mm, limit 30: first %s (-1 by the closed form), %s frames hit" % [clear.get("first", "?"), clear.get("hit_frames", "?")])
		# 3 HIT30: the stop at 410 mm: frame 24 (28.8 deg) is clear, frame 25 (30 deg, the stop) is in
		var hit := Part.hinge_sweep(door(410.0, swing, 30.0), "f5", FPS)
		ok(bool(hit["ok"]) and int(hit["first"]) == 25 and absf(float(hit["deg_first"]) - 30.0) < 0.01,
				"3 HIT30: stop at 410 mm, limit 30: first frame %s (25 by the closed form), at %s deg (30)" % [hit.get("first", "?"), hit.get("deg_first", "?")])
		# 4 DEFAULT: no limit key: 90 deg, nothing clamped, the stop at 430 is reached
		var dflt := Part.hinge_sweep(door(430.0, swing), "f5", FPS)
		ok(bool(dflt["ok"]) and int(dflt["limited_frames"]) == 0 and absf(float(dflt["limit"]) - 90.0) < 1e-6 and int(dflt["first"]) >= 0,
				"4 DEFAULT: limit %s, limited frames %s, first hit frame %s (>= 0)" % [dflt.get("limit", "?"), dflt.get("limited_frames", "?"), dflt.get("first", "?")])
	await ui_bars()
	print("P122JOINTLIMIT ", "PASS" if fails == 0 else "FAIL %d" % fails)
	quit(1 if fails > 0 else 0)


func ui_bars() -> void:
	if not Part.available():
		print("SKIP 5-6: the CAD kernel is not available")
		return
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
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIR_UI))
	ss.dirs_override = [DIR_UI]
	ss.show_screen()
	await idle(3)
	await click_ctl(ss._cards["building"])
	if m.ui_save_ask != null and m.ui_save_ask.visible:
		m._save_ask_choose("discard")
	await idle(6)
	pu.set_on(false)
	pu.m.S.part = {}
	await process_frame
	m.S.part = Part.make("Lid")
	m.S.part["features"] = [
		{"t": "sketch", "id": "f1", "name": "Sketch1", "plane": "front", "ents": [{"k": "rect", "a": [0, -20], "b": [800, 20]}], "dims": []},
		{"t": "extrude", "id": "f2", "name": "Extrude1", "sketch": "f1", "dist": 2000.0, "both": false, "op": "new"},
	]
	m.S.part["seq"] = 2
	await click_ctl(pu.part_btn)
	await idle(3)
	pu._view_model()
	await idle(3)
	var rec_before: int = (m.S.part["features"] as Array).size()
	var n0: int = m.undo.size()
	var b: Button = pu.tool_btns["Hinge"]
	if b.is_visible_in_tree():
		await click_ctl(b)
	else:
		await click_ctl(m.ui_more)
		m.ui_more.get_popup().hide()
		m._more_pick(m._more_tools.find(b))
		await idle(2)
	# the lid: its centre, then its edge nearest the corner (0, -20, z 0..2000 mm)
	var lid_tris: PackedVector3Array = Part.body_faces(m.S.part, -1)[0]
	var lid_pt := Vector3.ZERO
	for v in lid_tris:
		lid_pt += v / float(lid_tris.size())
	await click_at(m.cam.unproject_position(lid_pt))
	var best := -1
	var best_d := INF
	for i in pu.edge_cache.size():
		var e: Dictionary = pu.edge_cache[i]
		if int(e["body"]) != 0 or (e["a"] as Vector3).distance_to(e["b"] as Vector3) < 1e-6:
			continue
		var dd := (e["c"] as Vector3).distance_to(Vector3(0.0, -0.02, 1.0))
		if dd < best_d:
			best_d = dd
			best = i
	if best >= 0:
		await click_at(m.cam.unproject_position((pu.edge_cache[best] as Dictionary)["c"]))
	# 5 NEWUNDO: the Joint limit slider dragged to 40 (the row reads it), OK = one step
	var sl: HSlider = pu.limit_slider
	var row_ok := sl != null and sl.is_visible_in_tree()
	if row_ok:
		sl.value = 40.0
	await idle(2)
	ok(row_ok and pu.limit_lbl.text == "40 deg", "5 NEWUNDO: the Joint limit row is shown and reads \"%s\"" % (pu.limit_lbl.text if pu.limit_lbl != null else "?"))
	await shot_ui("limit_dialog")
	await click_ctl(pu.ok_btn)
	await idle(3)
	var feats: Array = m.S.part["features"]
	var hf: Dictionary = feats[-1] if not feats.is_empty() else {}
	var made := feats.size() == rec_before + 1 and String(hf.get("t", "")) == "hinge"
	var lim := float(hf.get("limit", -1.0))
	ok(made and absf(lim - 40.0) <= 0.5 and m.undo.size() == n0 + 1,
			"5 NEWUNDO: one hinge step (%d -> %d features, %d undo step), limit %.1f (40 within 0.5)" % [rec_before, feats.size(), m.undo.size() - n0, lim])
	m._undo()
	await idle(2)
	var back: bool = (m.S.part["features"] as Array).size() == rec_before
	m._redo()
	await idle(2)
	ok(back and (m.S.part["features"] as Array).size() == rec_before + 1, "5 NEWUNDO: one undo takes the hinge away, redo gives it back")
	# 6 PLAY40: the Play slider at 100 % shows the hinge at its limit, not at 90
	pu.hinge_slider.value = 100.0
	await idle(3)
	var deg := float(pu.pose.get("deg", -999.0))
	ok(absf(deg - 40.0) <= 0.5, "6 PLAY40: at 100 %% the hinge shows %.2f deg (40 within 0.5, the stop; 90 without the limit)" % deg)
	m.queue_free()
	await idle(2)
