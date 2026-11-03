extends SceneTree
## godot --path . --position 4000,4000 -s tests/c18_test.gd     (C18 part behaviour: scripts/build/part_door.gd; needs the CAD DLL and a window)
## Bars, written BEFORE the numbers were read. A control after each shows the bar can fail (the unmarked / old path fails it).
##  #334 DOOR     a door-marked piece's hinge sits on its left (right) end edge: pivot x = the piece's min (max) x within 0.05 mm, axis vertical within 0.5 deg
##   1 LEFT       marked left: pivot x = min x, axis vertical, the replay has no failed step, hinge_sweep ok
##   2 RIGHT      marked right: pivot x = max x, axis vertical
##   3 SAVED      the mark survives Part.from_file(Part.to_file(rec))
##   4 UNMARKED   (control, MUST stay as it was) an unmarked piece: axis X and the pivot at its back top edge (min x, max y, min z) within 0.05 mm
##   5 CONTROL    the unmarked hinge FAILS bar 1's vertical-axis test (so bar 1 can fail)
##   6 UI         real clicks at 1280x720: pick "Door, hinged on the left" and press Swing it: the step's axis is vertical and its pivot x = the door's min x
##  #291 NOTE     the first Join says it can be undone
##   7 FIRST      join_note() the first time is non-empty and names Ctrl+Z and the step list
##   8 ONCE       the second time it is empty
##   9 UINOTE     a real Join in the app: the first says the note, the second does not
##  #297 TOL      Join's touch tolerance at 1 mm and 50 m parts
##   10 SAME      JOIN_TOUCH_M is still 0.00005 and an unmarked part's tolerance is exactly it at 1 mm and at 50 m
##   11 TOUCH     two cubes sharing a face touch at 1 mm and at 50 m (scaled and not)
##   12 KERNEL    the kernel unions those cubes at 1 mm and 50 m: volume = 2 cubes within 1e-4 relative, one body
##   13 TINY      1 mm cubes 0.04 mm apart: NOT touching with tol_scaled (the old default says touching, kept: control)
##   14 BIG       50 m cubes 0.04 mm apart: touching in both (unchanged); 0.2 mm apart: not touching in both
const MM := 0.001
const OUT := "C:/Users/Nick/tools/kine_workers/out/c18"
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


func press(c: Control) -> void:
	var p := c.get_global_rect().get_center()
	await ev_move(p, false)
	await ev_mouse(p, true)
	await ev_mouse(p, false)
	await idle(2)


func pu() -> PartUI:
	return m.bld.part


func ep():
	return pu().ep


func scr(w: Vector3) -> Vector2:
	return m.cam.unproject_position(w)


func draw_floor(a: Vector3, b: Vector3) -> void:
	var pa := scr(a)
	var pb := scr(b)
	await ev_move(pa, false)
	await ev_mouse(pa, true)
	for i in range(1, 13):
		await ev_move(pa.lerp(pb, i / 12.0))
	await ev_mouse(pb, false)
	await idle(3)


## a record of cubes: each [x0, y0, z0, side] in mm (the front plane is XY, extruded along z)
func cubes(list: Array) -> Dictionary:
	var rec := Part.make("C18")
	var n := 0
	for c in list:
		var s := float(c[3])
		n += 1
		rec["features"].append({"t": "sketch", "id": "f%d" % (n * 2 - 1), "name": "Sketch%d" % n, "plane": "front", "ents": [{"k": "rect", "a": [c[0], c[1]], "b": [c[0] + s, c[1] + s]}], "dims": []})
		rec["features"].append({"t": "extrude", "id": "f%d" % (n * 2), "name": "Extrude%d" % n, "sketch": "f%d" % (n * 2 - 1), "dist": s, "both": false, "op": "new"})
		rec["seq"] = n * 2
	return rec


func box_of(tris: PackedVector3Array) -> AABB:
	var lo := Vector3(INF, INF, INF)
	var hi := Vector3(-INF, -INF, -INF)
	for v in tris:
		lo = lo.min(v)
		hi = hi.max(v)
	return AABB(lo, hi - lo)


## add a Swing-it hinge for body 1 the way the app does; returns the hinge feature
func swing(rec: Dictionary, side: String) -> Dictionary:
	if side != "":
		PartDoor.mark(rec, 1, side)
	var faces: Array = Part.body_faces(rec, -1)
	var bb := box_of(faces[1])
	var hg := PartDoor.swing_hinge(rec, 1, bb.position, bb.end)
	var o: Vector3 = hg["o"]
	var ax: Vector3 = hg["axis"]
	var f := Part.new_feature(rec, "hinge", {"body": 1, "o": [o.x, o.y, o.z], "axis": [ax.x, ax.y, ax.z], "track": [[0.0, 0.0], [2.0, 90.0]]})
	rec["features"].append(f)
	return f


func pivot_of(rec: Dictionary, f: Dictionary) -> Vector3:
	var r = PartRefs.hinge_pivot(rec, String(f["id"]))
	return r if r is Vector3 else Vector3(INF, INF, INF)


func vertical(f: Dictionary) -> bool:
	var a := Vector3(float(f["axis"][0]), float(f["axis"][1]), float(f["axis"][2])).normalized()
	return absf(a.dot(Vector3.UP)) >= cos(deg_to_rad(0.5))


func tris_cube(x0: float, s: float) -> PackedVector3Array:   # the -x and +x faces of a cube (two triangles each): all the touch test needs
	var out := PackedVector3Array()
	for x in [x0, x0 + s]:
		out.append_array(PackedVector3Array([Vector3(x, 0, 0), Vector3(x, s, 0), Vector3(x, 0, s), Vector3(x, s, 0), Vector3(x, s, s), Vector3(x, 0, s)]))
	return out


func touch(rec: Dictionary, s: float, gap: float) -> bool:
	var a := tris_cube(0.0, s)
	var b := tris_cube(s + gap, s)
	var tol := PartDoor.touch_tol(rec, PartDoor.min_side(a), PartDoor.min_side(b))
	return Part.tris_touch(a, b, tol)


func _init() -> void:
	if not Part.available():
		print("FAIL: no KineCAD DLL, the test cannot run")
		quit(1)
		return
	# ---- logic bars (no window needed) ----
	var base := cubes([[0, 0, 0, 40], [60, 0, 0, 40]])   # frame at x 0..40, door at x 60..100 (mm)
	var rl := base.duplicate(true)
	var fl := swing(rl, "left")
	var pl := pivot_of(rl, fl)
	var rp := Part.replay(rl)
	var sw := Part.hinge_sweep(rl, String(fl["id"]))
	ok((rp["errors"] as Dictionary).is_empty() and absf(pl.x - 60.0) <= 0.05 and vertical(fl) and bool(sw.get("ok", false)),
		"1 LEFT pivot x %.3f (want 60), axis %s, errors %d, sweep ok %s" % [pl.x, str(fl["axis"]), (rp["errors"] as Dictionary).size(), str(sw.get("ok"))])
	var rr := base.duplicate(true)
	var fr := swing(rr, "right")
	var pr := pivot_of(rr, fr)
	ok(absf(pr.x - 100.0) <= 0.05 and vertical(fr), "2 RIGHT pivot x %.3f (want 100), axis %s" % [pr.x, str(fr["axis"])])
	var back := Part.from_file(Part.to_file(rl))
	ok(PartDoor.side_of(back, 1) == "left" and PartDoor.side_of(back, 0) == "", "3 SAVED the mark survives save and load: body 1 %s" % PartDoor.side_of(back, 1))
	var ru := base.duplicate(true)
	var fu := swing(ru, "")
	var pu_ := pivot_of(ru, fu)
	ok(absf(float(fu["axis"][0]) - 1.0) < 1e-6 and absf(float(fu["axis"][1])) < 1e-6 and absf(pu_.x - 60.0) <= 0.05 and absf(pu_.y - 40.0) <= 0.05 and absf(pu_.z - 0.0) <= 0.05 and not ru.has("doors"),
		"4 UNMARKED axis %s, pivot %s (want axis X, pivot (60, 40, 0)), no door mark" % [str(fu["axis"]), str(pu_)])
	ok(not vertical(fu), "5 CONTROL the unmarked hinge is not vertical, so bar 1's test can fail")

	# ---- #291 ----
	var flag := ProjectSettings.globalize_path(PartDoor.NOTE_FILE)
	if FileAccess.file_exists(PartDoor.NOTE_FILE):
		DirAccess.remove_absolute(flag)
	var n1 := PartDoor.join_note()
	ok(n1 != "" and n1.contains("Ctrl+Z") and n1.contains("step list"), "7 FIRST '%s'" % n1)
	ok(PartDoor.join_note() == "", "8 ONCE the second time is empty")

	# ---- #297 ----
	ok(PartDoor.JOIN_TOUCH_M == 0.00005 and PartDoor.touch_tol({}, 0.001, 0.001) == 0.00005 and PartDoor.touch_tol({}, 50.0, 50.0) == 0.00005,
		"10 SAME unmarked tolerance %s at 1 mm, %s at 50 m" % [str(PartDoor.touch_tol({}, 0.001, 0.001)), str(PartDoor.touch_tol({}, 50.0, 50.0))])
	var sc := {"tol_scaled": true}
	ok(touch({}, 0.001, 0.0) and touch(sc, 0.001, 0.0) and touch({}, 50.0, 0.0) and touch(sc, 50.0, 0.0), "11 TOUCH shared faces touch at 1 mm and 50 m, scaled or not")
	var vols := []
	var bodies_ok := true
	for s in [1.0, 50000.0]:
		var rk := cubes([[0, 0, 0, s], [s, 0, 0, s]])
		var cf := Part.new_feature(rk, "combine", {"target": 0, "tools": [1], "op": "join", "keep": false})
		rk["features"].append(cf)
		var res := Part.replay(rk)
		var want := 2.0 * pow(s * MM, 3.0)
		vols.append(float(res["volume"]) / want)
		bodies_ok = bodies_ok and int(res["bodies"]) == 1 and (res["errors"] as Dictionary).is_empty()
	ok(bodies_ok and absf(vols[0] - 1.0) <= 1e-4 and absf(vols[1] - 1.0) <= 1e-4, "12 KERNEL join at 1 mm and 50 m: one body, volume/closed form %s" % str(vols))
	ok(touch({}, 0.001, 0.00004) and not touch(sc, 0.001, 0.00004), "13 TINY 1 mm cubes 0.04 mm apart: old default touching %s (kept), scaled touching %s (want false)" % [str(touch({}, 0.001, 0.00004)), str(touch(sc, 0.001, 0.00004))])
	ok(touch({}, 50.0, 0.00004) and touch(sc, 50.0, 0.00004) and not touch({}, 50.0, 0.0002) and not touch(sc, 50.0, 0.0002), "14 BIG 50 m cubes 0.04 mm apart touch, 0.2 mm apart do not, both ways")

	# ---- UI bars ----
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
	var dirt := "user://c18_test"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dirt))
	ss.dirs_override = [dirt]
	ss.show_screen()
	await idle(3)
	await press(ss._cards["building"])
	await idle(3)
	if m.ui_save_ask != null and m.ui_save_ask.visible:
		m._save_ask_choose("discard")
	await idle(6)
	pu().set_on(false)
	pu().m.S.part = {}
	await process_frame
	await press(pu().part_btn)
	await idle(3)
	await press(pu().easy_open_btn)
	await idle(4)
	m.S.part = Part.make("Part")
	pu().upto = -1
	pu().sync()
	m.target = Vector3.ZERO
	m.pitch = -40.0
	m.yaw = 20.0
	m._cam()
	await idle(60)
	await press(ep().make_btns["draw"])
	await draw_floor(Vector3(-0.10, 0.0, -0.05), Vector3(0.0, 0.0, 0.05))
	await press(ep().make_btns["pull"])
	await press(ep().make_btns["draw"])
	await draw_floor(Vector3(0.05, 0.0, -0.05), Vector3(0.09, 0.0, 0.05))
	await press(ep().make_btns["pull"])
	await idle(6)
	var f0: Array = Part.body_faces(ep()._rec(), -1)
	var door_bb := box_of(f0[f0.size() - 1]) if f0.size() >= 2 else AABB()
	ok(f0.size() == 2, "6a UI built two pieces (%d)" % f0.size())
	var opt: OptionButton = ep().door_opt
	ok(opt != null and ep().swing_btn.is_visible_in_tree() and opt.is_visible_in_tree(), "6b UI the Swing it button and the door choice are both shown")
	DirAccess.make_dir_recursive_absolute(OUT)
	if opt != null and opt.is_visible_in_tree():
		await idle(3)
		root.get_viewport().get_texture().get_image().save_png(OUT + "/door_option.png")
		opt.select(1)
		await press(ep().swing_btn)
		await idle(6)
		var feats: Array = ep()._rec().get("features", [])
		var hf: Dictionary = feats[feats.size() - 1]
		var pv := pivot_of(ep()._rec(), hf)
		ok(String(hf.get("t", "")) == "hinge" and vertical(hf) and absf(pv.x * MM - door_bb.position.x) <= 0.00005,
			"6 UI Swing it with 'hinged on the left': axis %s, pivot x %.4f m (door min x %.4f m)" % [str(hf.get("axis")), pv.x * MM, door_bb.position.x])
		root.get_viewport().get_texture().get_image().save_png(OUT + "/door_swung.png")
	# 9: a real Join, twice (the flag is cleared first)
	if FileAccess.file_exists(PartDoor.NOTE_FILE):
		DirAccess.remove_absolute(flag)
	var said: Array = []
	for round in 2:
		m.S.part = cubes([[0, 0, 0, 40], [40, 0, 0, 40]])
		pu().upto = -1
		pu().sync()
		await idle(4)
		var fc: Array = Part.body_faces(ep()._rec(), -1)
		ep().stick_picks = [0, 1]
		ep().stick_tris = {0: fc[0], 1: fc[1]}
		ep()._stick("join", "Join")
		await idle(4)
		said.append(String(ep().msg))
		if round == 0:
			root.get_viewport().get_texture().get_image().save_png(OUT + "/join_note.png")
	ok(said[0].contains("Ctrl+Z") and not said[1].contains("Ctrl+Z"), "9 UINOTE first Join: '%s' / second: '%s'" % [said[0], said[1]])
	print("c18: %d fail" % fails)
	quit(1 if fails > 0 else 0)
