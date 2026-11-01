extends SceneTree
## godot --path . --position 4000,4000 -s tests/s214_test.gd     (s214 PATTERN A GROUP: Repeat it / Pattern on SEVERAL bodies in one step; scripts/build/part.gd _pattern_group, part_ui.gd _pgrp_*, easy_part_repeat.gd _rep_group; needs a window and the CAD DLL)
## Three cubes (10, 16, 22 mm) stand on the +X line at 60, 100 and 140 mm. A Ring of 3 round Y on all three, in ONE step, must give nine bodies.
## Bars (REAL clicks at 1280 x 720; numbers measured from the replayed result, not from the code's own variables):
##   E1 PICK    Expert Pattern dialog: Ctrl+click on a body adds it (and Ctrl+click again takes it off); a plain click makes it the only one
##   E2 BOX     Shift + a box dragged from empty space round ONE body adds just that body
##   E3 STEP    Circular 3, round Y, 360, New bodies: the preview says 9 bodies; OK = ONE undo step and ONE pattern step carrying bodies [0,1,2]
##   E4 NINE    9 bodies, no failed step; every original is exactly its cube volume (1e-12 m3) and each copy has the volume of its original
##   E5 ANGLES  copy k of each cube sits at 120 and 240 deg round Y (0.01 deg) and the same radius (0.01 mm) as its original
##   E6 UNDO    one Undo gives 3 bodies and the 3 cubes' volume back; Redo gives the nine back
##   E7 FILE    save, new scene, reload: the same record, nine bodies, the same volume
##   Z1 GROUP   Easy: Repeat it then Group: ONE undo step, the step carries bodies [0,1,2]
##   Z2 RING    Ring: nine bodies, copies at 120 / 240 deg, volumes exact, no failed step; the whole of Group + Ring is 2 undo steps
##   Z3 CLICK   a click on a piece takes it off (7 bodies, one undo step), Shift + click again puts it back (9 bodies)
##   Z4 ROW     Row on the group: the 3 pieces are moved by the same distance in X (9 bodies, the three copies of one cube are one spacing apart)
##   Z5 UNDO    one Undo takes the Row step back; Group off leaves the single-piece Repeat it
##   Z6 FILE    save, new scene, reload: the same record and nine bodies
## Shots: C:/Temp/claude/s214/expert_pick.png (the dialog with three bodies picked, frames round them), expert_ring.png, easy_group.png, easy_ring.png
var fails := 0
var m: Node
const SHOT := "C:/Temp/claude/s214"
const DIRT := "user://s214_test"
const SIZES := [10.0, 16.0, 22.0]
const XS := [60.0, 100.0, 140.0]


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


## three separate cubes (front plane, x centres XS, sizes SIZES, depth = the size), each a body of its own
func cubes_rec() -> Dictionary:
	var r := Part.make("Group test")
	var fs := []
	for i in 3:
		var s: float = SIZES[i]
		var cx: float = XS[i]
		fs.append({"t": "sketch", "id": "f%d" % (2 * i + 1), "name": "Sketch%d" % (i + 1), "plane": "front", "ents": [{"k": "rect", "a": [cx - s / 2.0, -s / 2.0], "b": [cx + s / 2.0, s / 2.0]}], "dims": []})
		fs.append({"t": "extrude", "id": "f%d" % (2 * i + 2), "name": "Extrude%d" % (i + 1), "sketch": "f%d" % (2 * i + 1), "dist": s, "both": true, "op": "new"})
	r["features"] = fs
	r["seq"] = 6
	return r


func cube_m3(i: int) -> float:
	return pow(float(SIZES[i]) * 0.001, 3.0)


## the nine-body bars on a replay with props: volumes exact and every copy 120 / 240 deg round Y at its original's radius. Returns "" or what is wrong
func ring_audit(rec: Dictionary) -> String:
	var rc := Part.replay(rec, -1, {"props": true})
	var props: Array = rc["props"]
	if int(rc["bodies"]) != 9 or props.size() != 9:
		return "%d bodies" % int(rc["bodies"])
	if not (rc["errors"] as Dictionary).is_empty():
		return "errors %s" % str(rc["errors"])
	# bodies 0..2 are the originals; the copies follow body by body: 3,4 are cube 0's copies, 5,6 cube 1's, 7,8 cube 2's
	var worst_v := 0.0
	var worst_r := 0.0
	var worst_a := 0.0
	for i in 3:
		var c0: Vector3 = props[i]["center"]
		var a0 := atan2(c0.z, c0.x)
		worst_v = maxf(worst_v, absf(float(props[i]["volume"]) - cube_m3(i)))
		for k in [1, 2]:
			var j: int = 3 + 2 * i + (k - 1)
			var cj: Vector3 = props[j]["center"]
			worst_v = maxf(worst_v, absf(float(props[j]["volume"]) - cube_m3(i)))
			worst_r = maxf(worst_r, absf(Vector2(cj.x, cj.z).length() - Vector2(c0.x, c0.z).length()) * 1000.0)
			var da := rad_to_deg(wrapf(atan2(cj.z, cj.x) - a0, -PI, PI))   # the turn this copy made, -180..180
			var want: float = 120.0 * k if 120.0 * k <= 180.0 else 120.0 * k - 360.0
			# Kine rotates about Y with the right-hand rule: the sign of the angle in the (x, z) plane is the opposite of atan2(z, x)
			worst_a = maxf(worst_a, minf(absf(wrapf(da - want, -180.0, 180.0)), absf(wrapf(da + want, -180.0, 180.0))))
	if worst_v > 1e-11:   # the kernel volume is good to about 2e-7 of a cube
		return "volume off by %s m3" % E(worst_v)
	if worst_r > 0.01:
		return "radius off by %.4f mm" % worst_r
	if worst_a > 0.01:
		return "angle off by %.4f deg" % worst_a
	# the two copies of one cube must be at DIFFERENT turns (120 and 240), not the same place twice
	for i in 3:
		var ca: Vector3 = props[3 + 2 * i]["center"]
		var cb: Vector3 = props[4 + 2 * i]["center"]
		if (ca - cb).length() < 1e-4:
			return "two copies of cube %d sit in the same place" % i
	return ""


func total_cubes() -> float:
	return cube_m3(0) + cube_m3(1) + cube_m3(2)


func ps(rec: Dictionary) -> String:
	return JSON.stringify(rec) if not rec.is_empty() else "{}"


func last_of(rec: Dictionary, t: String) -> Dictionary:
	var out := {}
	for f in rec.get("features", []):
		if String(f["t"]) == t:
			out = f
	return out


func n_of(rec: Dictionary, t: String) -> int:
	var n := 0
	for f in rec.get("features", []):
		if String(f["t"]) == t:
			n += 1
	return n


## the screen point of the middle of cube i's front face (z = +half size)
func face_pt(i: int) -> Vector2:
	var s: float = SIZES[i]
	return m.cam.unproject_position(Vector3(float(XS[i]) * 0.001, 0.0, s * 0.5 * 0.001))


func world_pt(x_mm: float, y_mm: float) -> Vector2:
	return m.cam.unproject_position(Vector3(x_mm * 0.001, y_mm * 0.001, 0.0))


## the three cubes small and on the right of the screen, clear of the Repeat it box (a click there would hit the box, not a piece)
func frame_right() -> void:
	m.target = Vector3(0.1, 0.0, 0.0)
	m.dist = 1.6
	m.pitch = 0.0
	m.yaw = 0.0
	m._cam()
	await idle(10)
	var p0: Vector2 = m.cam.unproject_position(Vector3(0.1, 0.0, 0.0))
	var p1: Vector2 = m.cam.unproject_position(Vector3(0.2, 0.0, 0.0))
	var sc := (p1.x - p0.x) / 0.1
	m.target = Vector3(0.1 - (960.0 - p0.x) / sc, (470.0 - p0.y) / sc, 0.0)
	m._cam()
	await idle(40)


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
		print("FAIL: no KineCAD DLL, s214 needs the kernel")
		print("s214: 1 fail")
		quit(1)
		return
	ss.show_screen()
	await idle(3)
	await click_ctl(ss._cards["building"])
	if m.ui_save_ask != null and m.ui_save_ask.visible:
		m._save_ask_choose("discard")
	await idle(6)
	# the BUILDING card opens a blank Easy Part: start from Part off, no part, then the Expert workspace by its own button
	pu.set_on(false)
	pu.m.S.part = {}
	await process_frame
	await click_ctl(pu.part_btn)
	await idle(3)
	if pu.easy:
		pu.easy = false
	m.S.part = cubes_rec()
	bld.sync()
	m.target = Vector3(0.1, 0.0, 0.0)
	m.dist = 0.55
	m.pitch = 0.0
	m.yaw = 0.0
	m._cam()
	await idle(40)
	var r0 := Part.replay(m.S.part)
	ok(int(r0["bodies"]) == 3 and absf(float(r0["volume"]) - total_cubes()) < 1e-12, "0 three separate cubes: %d bodies, volume %s m3 (want %s)" % [int(r0["bodies"]), E(float(r0["volume"])), E(total_cubes())])
	var path := DIRT + "/s214.json"

	# E1 PICK: Ctrl + click adds a body
	var n0: int = m.undo.size()
	await press_tool(pu, "Pattern")
	ok(String(pu.dlg.get("t", "")) == "pattern", "E1 Pattern opens its dialog")
	ok(pu.pat_pick == [2], "E1 the dialog starts with the newest body only: %s" % str(pu.pat_pick))
	await click_at(face_pt(0), 2)
	await click_at(face_pt(1), 2)
	var sorted := pu.pat_pick.duplicate()
	sorted.sort()
	ok(sorted == [0, 1, 2], "E1 Ctrl+click on body 1 and 2 adds them: picked %s" % str(sorted))
	await click_at(face_pt(1), 2)
	var s2 := pu.pat_pick.duplicate()
	s2.sort()
	ok(s2 == [0, 2], "E1 Ctrl+click again takes body 2 off: picked %s" % str(s2))
	await click_at(face_pt(0), 0)
	ok(pu.pat_pick == [0], "E1 a plain click makes it the only one: picked %s" % str(pu.pat_pick))
	ok(m.undo.size() == n0, "E1 picking changes nothing in the record (undo %d -> %d)" % [n0, m.undo.size()])

	# E2 BOX: Shift + a box from empty space round body 2 only (x between the cubes at 60 and 100 up to 120), adds just that one
	var a := world_pt(80.0, 60.0)
	var b := world_pt(120.0, -20.0)
	var in_box_other := 0
	await drag_box(a, b, 1)
	var s3 := pu.pat_pick.duplicate()
	s3.sort()
	ok(s3 == [0, 1], "E2 Shift + a box round body 2 adds just that body: picked %s (box %s to %s)" % [str(s3), str(a), str(b)])
	# the box that holds body 3 and starts on empty space too
	await drag_box(world_pt(125.0, 60.0), world_pt(160.0, -30.0), 1)
	var s4 := pu.pat_pick.duplicate()
	s4.sort()
	ok(s4 == [0, 1, 2], "E2 a second box adds body 3: picked %s" % str(s4))

	# E3 STEP: Circular 3 round Y, 360, New bodies
	(pu.pat["kind"] as OptionButton).select(1)
	(pu.pat["kind"] as OptionButton).item_selected.emit(1)
	await idle(2)
	await typed(pu.pat["count"], "3")
	await typed(pu.pat["deg"], "360")
	(pu.pat["axis"] as OptionButton).select(1)
	(pu.pat["op"] as OptionButton).select(1)
	(pu.pat["op"] as OptionButton).item_selected.emit(1)
	await idle(3)
	ok(int(pu.prev.get("bodies", 0)) == 9, "E3 the preview says %s bodies (want 9)" % str(pu.prev.get("bodies", 0)))
	ok(pu.dlg_info.text.begins_with("9 bodies"), "E3 the dialog says: %s" % pu.dlg_info.text)
	var boxes: Array = pu.pat["picks"]
	var ticked := []
	for i in boxes.size():
		if (boxes[i] as CheckBox).button_pressed:
			ticked.append(i)
	ok(ticked == [0, 1, 2], "E3 the three Also copy ticks are on: %s" % str(ticked))
	await shot("expert_pick")
	await click_ctl(pu.ok_btn)
	await idle(3)
	var pf := last_of(m.S.part, "pattern")
	var bl: Array = pf.get("bodies", [])
	ok(m.undo.size() == n0 + 1 and n_of(m.S.part, "pattern") == 1 and bl.size() == 3 and int(bl[0]) == 0 and int(bl[1]) == 1 and int(bl[2]) == 2 and String(pf.get("kind", "")) == "circular",
		"E3 OK = ONE undo step (%d) and ONE pattern step carrying bodies %s" % [m.undo.size() - n0, str(bl)])
	var rec_after := ps(m.S.part)

	# E4 + E5
	var why := ring_audit(m.S.part)
	var r4 := Part.replay(m.S.part)
	var want_v := 3.0 * total_cubes()
	ok(why == "", "E4/E5 nine bodies, volumes exact, every copy at 120 / 240 deg and the same radius [%s]" % why)
	ok(absf(float(r4["volume"]) - want_v) < 1e-11, "E4 total volume %s m3 = 3 x the cubes %s" % [E(float(r4["volume"])), E(want_v)])
	pu._view_model()
	m.target = Vector3(0.0, 0.0, 0.0)
	m.dist = 0.62
	m.pitch = -55.0
	m.yaw = 15.0
	m._cam()
	await idle(40)
	await shot("expert_ring")

	# E6 UNDO
	m._undo()
	await idle(4)
	var ru := Part.replay(m.S.part)
	ok(int(ru["bodies"]) == 3 and absf(float(ru["volume"]) - total_cubes()) < 1e-12 and n_of(m.S.part, "pattern") == 0 and m.undo.size() == n0,
		"E6 one Undo: %d bodies, volume %s m3 (want 3, %s), no pattern step" % [int(ru["bodies"]), E(float(ru["volume"])), E(total_cubes())])
	m._redo()
	await idle(4)
	ok(int(Part.replay(m.S.part)["bodies"]) == 9 and ps(m.S.part) == rec_after, "E6 Redo gives the nine back (same record)")

	# E7 FILE
	var saved := JSON.stringify(JSON.parse_string(ps(m.S.part)))
	await save_reload(path, saved, bld)
	ok(JSON.stringify(JSON.parse_string(ps(m.S.part))) == saved and ring_audit(m.S.part) == "" and absf(float(Part.replay(m.S.part)["volume"]) - want_v) < 1e-11,
		"E7 reloaded: the same record, nine bodies, the same volume [%s]" % ring_audit(m.S.part))

	# ---- EASY
	pu.set_on(false)
	m.S.part = {}
	await process_frame
	await click_ctl(pu.part_btn)
	await click_ctl(pu.easy_open_btn)
	await idle(4)
	var ep = pu.ep
	m.S.part = cubes_rec()
	pu.upto = -1
	pu.sync()
	await frame_right()
	ok(pu.easy and int(Part.replay(m.S.part)["bodies"]) == 3, "Z0 Easy Part with three separate cubes (bodies %d)" % int(Part.replay(m.S.part)["bodies"]))
	var u0: int = m.undo.size()
	await click_ctl(ep.make_btns["repeat"])
	var u1: int = m.undo.size()
	await click_ctl(ep.rep_btns["group"])
	var u2: int = m.undo.size()
	var zf := last_of(m.S.part, "pattern")
	var zb: Array = zf.get("bodies", [])
	ok(u2 == u1 + 1 and zb.size() == 3 and int(zb[0]) == 0 and int(zb[2]) == 2, "Z1 Repeat it then Group: Group is ONE undo step (%d -> %d), the step carries bodies %s" % [u1, u2, str(zb)])
	ok(ep.rep_btns["group"].visible and ep.rep_btns["group"].button_pressed, "Z1 the Group button shows on the Repeat it box and is pressed")
	await shot("easy_group")
	await click_ctl(ep.rep_btns["ring"])
	var u3: int = m.undo.size()
	await idle(3)
	var zr := Part.replay(m.S.part)
	var zwhy := ring_audit(m.S.part)
	ok(zwhy == "" and n_of(m.S.part, "pattern") == 1, "Z2 Ring on the group: nine bodies, 120 / 240 deg, volumes exact, one pattern step [%s]" % zwhy)
	ok(u3 - u0 == 3, "Z2 Repeat it + Group + Ring are %d undo steps (3: one each)" % (u3 - u0))
	m.target = Vector3(0.0, 0.0, 0.0)
	m.dist = 0.62
	m.pitch = -55.0
	m.yaw = 15.0
	m._cam()
	await idle(40)
	await shot("easy_ring")
	await frame_right()

	# Z3 CLICK: Shift + click on cube 2 takes it off, again puts it back
	var u4: int = m.undo.size()
	await click_at(face_pt(1), 0)
	var zb2: Array = last_of(m.S.part, "pattern").get("bodies", [])
	ok(m.undo.size() == u4 + 1 and zb2.size() == 2 and not zb2.has(1) and int(Part.replay(m.S.part)["bodies"]) == 7,
		"Z3 a click on a piece takes it off: ONE undo step (%d), bodies %s, %d bodies in the part (want 7: 3 + 2 copies of each of 2)" % [m.undo.size() - u4, str(zb2), int(Part.replay(m.S.part)["bodies"])])
	await click_at(face_pt(1), 1)
	var zb3: Array = last_of(m.S.part, "pattern").get("bodies", [])
	ok(zb3.size() == 3 and int(Part.replay(m.S.part)["bodies"]) == 9 and ring_audit(m.S.part) == "", "Z3 Shift+click again puts it back (the modifier works too): %s, nine bodies, audit [%s]" % [str(zb3), ring_audit(m.S.part)])

	# Z4 ROW: the same step as a row: the copies of each cube are one spacing apart in X (the group's width + the gap)
	var u5: int = m.undo.size()
	await click_ctl(ep.rep_btns["row"])
	var zrow := Part.replay(m.S.part, -1, {"props": true})
	var props: Array = zrow["props"]
	var step_want := 0.0
	var step_got := []
	if props.size() == 9:
		for i in 3:
			var c0: Vector3 = props[i]["center"]
			var c1: Vector3 = props[3 + 2 * i]["center"]
			var c2: Vector3 = props[4 + 2 * i]["center"]
			step_got.append(snappedf((c1.x - c0.x) * 1000.0, 0.001))
			step_got.append(snappedf((c2.x - c1.x) * 1000.0, 0.001))
		step_want = float(step_got[0]) if not step_got.is_empty() else 0.0
	var same := props.size() == 9 and step_want > 1.0
	for v in step_got:
		same = same and absf(float(v) - step_want) < 0.001
	var group_w := (float(XS[2]) + float(SIZES[2]) * 0.5) - (float(XS[0]) - float(SIZES[0]) * 0.5)
	ok(same and absf(step_want - (group_w + 10.0)) < 0.01 and int(zrow["bodies"]) == 9 and (zrow["errors"] as Dictionary).is_empty(),
		"Z4 Row on the group: nine bodies, every copy one spacing %s mm along X (the group is %.1f mm wide + 10 mm gap), no failed step; steps %s" % [str(step_want), group_w, str(step_got)])
	ok(m.undo.size() == u5 + 1, "Z4 Row is ONE undo step (%d)" % (m.undo.size() - u5))

	# Z5 UNDO
	m._undo()
	await idle(4)
	ok(m.undo.size() == u5 and ring_audit(m.S.part) == "", "Z5 one Undo takes the Row back to the ring: the audit is clean [%s]" % ring_audit(m.S.part))
	var jz := JSON.stringify(JSON.parse_string(ps(m.S.part)))

	# Z6 FILE
	await save_reload(path, jz, bld)
	ok(JSON.stringify(JSON.parse_string(ps(m.S.part))) == jz and ring_audit(m.S.part) == "", "Z6 reloaded: the same record, nine bodies [%s]" % ring_audit(m.S.part))
	print("s214: %d fail" % fails)
	quit(1 if fails > 0 else 0)
