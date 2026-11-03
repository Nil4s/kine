extends SceneTree
## godot --path . -s tests/c44_test.gd   (C44: complaints #238 extrude to an object in one step, #239 extrude / offset to an edge of another element)
## BARS, written before any number was seen. Scene: a 20 x 20 profile on the Front plane (z 0), a ceiling slab (-20..60 square, z 60..70) above it.
##   1 UPTO DATA  an extrude carrying "upto" = the ceiling's top-face centre makes a body of volume 20*20*70 mm3 within 0.5 pct (28000 mm3), and it equals a plain
##                extrude of dist 70 to 1e-3 mm3. Control: the same step WITHOUT upto is 4000 mm3 (10 mm), so the bar fails on the old behaviour.
##   2 OFFSET     "upto_off" -5 stops 5 short: 20*20*65 within 0.5 pct; +5 runs 5 past: 20*20*75.
##   3 EDGE       "upto" = the midpoint of the ceiling's top front edge (z 70) gives the same 28000 within 0.5 pct.
##   4 PLAIN      a step without "upto" is read exactly as before: resolve() returns the very same dictionary, and the plain record's volume is 4000 mm3 (+-0.5).
##   5 UI         real clicks: open Extrude, press "Up to a face or edge", click the ceiling's top face: the distance field reads 70 (+-0.05), the dialog feature carries
##                upto; OK = ONE undo step, one new feature, the new body is 28000 mm3 within 0.5 pct. Control: typing 30 in the distance field afterwards clears the pick
##                (dialog_feature has no "upto").
##   6 UI OFFSET  the offset field -10 in the dialog: the body is 20*20*60 within 0.5 pct.
##   7 LOOK       screenshots at 1280 x 720 of the armed state and the result; the new button, label and offset row are inside the window and overlap nothing.
const Part := preload("res://scripts/build/part.gd")
const OUT := "C:/Users/Nick/tools/kine_workers/out/c44"
var fails := 0
var m: Node


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


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


func click_at(p: Vector2) -> void:
	var mv := InputEventMouseMotion.new()
	mv.position = p
	mv.global_position = p
	root.push_input(mv, true)
	await process_frame
	await ev_mouse(p, true)
	await ev_mouse(p, false)
	await idle(3)


func click_ctl(c: Control) -> void:
	await click_at(c.get_global_rect().get_center())


func feats(upto: Variant, off: float, dist: float, with_last := true) -> Array:
	var fs := [
		{"t": "plane", "id": "p1", "name": "Ceiling plane", "from": "front", "mm": 60.0},
		{"t": "sketch", "id": "f2", "name": "S2", "plane": "p1", "ents": [{"k": "rect", "a": [-20.0, -20.0], "b": [60.0, 60.0]}], "dims": []},
		{"t": "extrude", "id": "f3", "name": "Ceiling", "sketch": "f2", "dist": 10.0, "both": false, "op": "new"},
		{"t": "sketch", "id": "f4", "name": "Profile", "plane": "front", "ents": [{"k": "rect", "a": [0.0, 0.0], "b": [20.0, 20.0]}], "dims": []},
	]
	if with_last:
		var e := {"t": "extrude", "id": "f5", "name": "Pull", "sketch": "f4", "dist": dist, "both": false, "op": "new"}
		if upto != null:
			e["upto"] = upto
			e["upto_off"] = off
		fs.append(e)
	return fs


func rec_of(fs: Array) -> Dictionary:
	var r := Part.make("c44")
	r["features"] = fs
	r["seq"] = 20
	return r


## the volume (mm3) of the newest body, -1 on any step error
func vol(r: Dictionary) -> float:
	var res := Part.replay(r)
	if not (res["errors"] as Dictionary).is_empty():
		print("   errors: ", res["errors"])
		return -1.0
	var vs: Array = res["volumes"]
	return float(vs[vs.size() - 1]) * 1e9 if not vs.is_empty() else -1.0


func near(v: float, want: float) -> bool:
	return absf(v - want) <= 0.005 * want


func data_bars() -> void:
	var v1 := vol(rec_of(feats([20.0, 20.0, 70.0], 0.0, 10.0)))
	var vp := vol(rec_of(feats(null, 0.0, 70.0)))
	ok(near(v1, 28000.0), "1 up to the ceiling's top face: %.1f mm3 (want 28000 +-0.5 pct)" % v1)
	ok(absf(v1 - vp) < 1e-3, "1b equals a plain extrude of 70: %.3f vs %.3f" % [v1, vp])
	var v0 := vol(rec_of(feats(null, 0.0, 10.0)))
	ok(not near(v0, 28000.0), "1 control: the same step without upto is %.1f mm3, the bar FAILS on the old behaviour" % v0)
	var vm := vol(rec_of(feats([20.0, 20.0, 70.0], -5.0, 10.0)))
	var vq := vol(rec_of(feats([20.0, 20.0, 70.0], 5.0, 10.0)))
	ok(near(vm, 26000.0) and near(vq, 30000.0), "2 offset -5 / +5: %.1f / %.1f mm3 (want 26000 / 30000)" % [vm, vq])
	var ve := vol(rec_of(feats([20.0, -20.0, 70.0], 0.0, 10.0)))
	ok(near(ve, 28000.0), "3 edge midpoint (20,-20,70): %.1f mm3" % ve)
	var PU := load("res://scripts/build/part_upto.gd")
	var pl := Part.plane("front")
	var plain := {"t": "extrude", "dist": 10.0}
	ok(is_same(PU.resolve(plain, pl), plain), "4 a step without upto comes back as the very same dictionary")
	ok(absf(v0 - 4000.0) < 0.5, "4b plain extrude of 10 is 4000 mm3 (%.3f)" % v0)


func shot(nm: String) -> void:
	await idle(3)
	root.get_texture().get_image().save_png("%s/%s.png" % [OUT, nm])


func set_part(fs: Array) -> void:
	var pu = m.bld.part
	m.S.part = rec_of(fs)
	pu.upto = -1
	pu.sync()
	await idle(16)


func top_face_screen(pu) -> Vector2:
	var base := Part.replay(pu._rec(), -1, {"faces": true, "body": pu._body_measures()})
	var best := Vector2(-1, -1)
	for fc in base["faces"]:
		var c: Vector3 = fc["c"]
		if (fc["n"] as Vector3).dot(Vector3.BACK) > 0.9 and absf(c.z - 0.07) < 1e-4:
			best = m.cam.unproject_position(c)
	return best


func ui_bars(pu) -> void:
	await set_part(feats(null, 0.0, 0.0, false))
	var n_f: int = (m.S.part["features"] as Array).size()
	var n_u: int = m.undo.size()
	pu.open_dialog("Extrude", -1)
	await idle(3)
	var b: Button = pu.dlg_rows.find_child("part_upto", true, false)
	ok(b != null, "5 the Extrude dialog has the button 'Up to a face or edge'")
	if b == null:
		return
	await click_ctl(b)
	ok(bool(pu.dlg.get("upto_arm", false)), "5 the button arms the picker")
	var sp := top_face_screen(pu)
	ok(sp.x >= 0.0 and sp.x < 1280.0 and sp.y >= 0.0 and sp.y < 720.0, "5 the ceiling's top face centre is on screen at %s" % str(sp))
	var mv := InputEventMouseMotion.new()
	mv.position = sp
	mv.global_position = sp
	root.push_input(mv, true)
	await idle(3)
	await shot("armed_1280")
	await click_at(sp)
	await shot("picked_1280")
	var d := float(pu.f_num.text)
	ok(absf(d - 70.0) <= 0.05, "5 the distance field reads %s (want 70)" % pu.f_num.text)
	var f: Dictionary = pu.dialog_feature()
	ok(f.has("upto"), "5 the dialog's feature carries the pick")
	await click_ctl(pu.ok_btn)
	await idle(4)
	ok(m.undo.size() == n_u + 1 and (m.S.part["features"] as Array).size() == n_f + 1, "5 OK = ONE undo step, one new feature (%d, %d)" % [m.undo.size() - n_u, (m.S.part["features"] as Array).size() - n_f])
	var v := vol(m.S.part)
	ok(near(v, 28000.0), "5 the new body is %.1f mm3 (want 28000)" % v)
	await shot("result_1280")
	# control: typing a distance afterwards clears the pick
	await set_part(feats(null, 0.0, 0.0, false))
	pu.open_dialog("Extrude", -1)
	await idle(3)
	b = pu.dlg_rows.find_child("part_upto", true, false)
	await click_ctl(b)
	await click_at(top_face_screen(pu))
	ok(pu.dialog_feature().has("upto"), "5 control setup: picked again")
	pu.f_num.text = "30"
	pu.f_num.text_changed.emit("30")
	await idle(2)
	ok(not pu.dialog_feature().has("upto"), "5 control: typing 30 clears the pick (the bar can fail)")
	# 6 offset typed in the dialog
	await click_ctl(b)
	await click_at(top_face_screen(pu))
	var le: LineEdit = pu.dlg_rows.find_child("part_upto_off", true, false)
	ok(le != null, "6 the offset row exists")
	if le != null:
		le.text = "-10"
		le.text_changed.emit("-10")
		await idle(2)
		var f2: Dictionary = pu.dialog_feature()
		var r := rec_of(feats(null, 0.0, 0.0, false))
		f2["id"] = "f5"
		f2["name"] = "Pull"
		r["features"].append(f2)
		var v6 := vol(r)
		ok(near(v6, 24000.0), "6 offset -10 typed in the dialog: %.1f mm3 (want 24000)" % v6)
		await shot("offset_1280")
		var rows: Array = []
		for nm in ["part_upto", "part_upto_lab", "part_upto_off"]:
			var c: Control = pu.dlg_rows.find_child(nm, true, false)
			if c != null:
				rows.append(c)
		var win := Rect2(Vector2.ZERO, Vector2(root.get_visible_rect().size))
		var inside := rows.size() == 3
		for c in rows:
			inside = inside and win.encloses((c as Control).get_global_rect()) and (c as Control).is_visible_in_tree()
		ok(inside, "7 the new controls are visible and inside the window")
		var clash := false
		for i in rows.size():
			for j in range(i + 1, rows.size()):
				clash = clash or (rows[i] as Control).get_global_rect().intersects((rows[j] as Control).get_global_rect())
		ok(not clash, "7 the new controls overlap each other nowhere")


func _init() -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	if not Part.available():
		print("SKIP: no KineCAD DLL")
		quit(0)
		return
	var wd := create_timer(300.0)   # watchdog
	wd.timeout.connect(func():
		print("FAIL watchdog: c44 took over 300 s")
		quit(2))
	data_bars()
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(8)
	m.tour_step = -1
	if m.ui_tour != null:
		m.ui_tour.visible = false
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	root.content_scale_size = Vector2i(1280, 720)
	root.size = Vector2i(1280, 720)
	var ss: StartScreen = m.start_screen
	var pu: PartUI = m.bld.part
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://c44_test"))
	ss.dirs_override = ["user://c44_test"]
	ss.show_screen()
	await idle(3)
	if ss._easy_btn["building"].button_pressed:
		await click_ctl(ss._easy_btn["building"])
	await click_ctl(ss._cards["building"])
	if m.ui_save_ask != null and m.ui_save_ask.visible:
		m._save_ask_choose("discard")
	await idle(6)
	pu.set_on(false)
	pu.m.S.part = {}
	await process_frame
	await click_ctl(pu.part_btn)
	await idle(4)
	await ui_bars(pu)
	print("c44: %d fail" % fails)
	quit(1 if fails > 0 else 0)
