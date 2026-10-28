extends SceneTree
## godot --path . --position 4000,4000 -s tests/psweep_test.gd     (GAP 6 SWEEP: a closed profile swept along an open path; scripts/build/part.gd _sweep / sweep_path, part_ui.gd Sweep; needs a window and the CAD DLL)
## The profile: a 20 mm circle on the Front plane, centred on the origin. The path: a 100 mm straight line down the Top plane from the origin, then a quarter arc of radius 45 mm
## that leaves it tangent (the path is 100 + 45 pi/2 = 170.69 mm long). Bars:
##   1 RIBBON    Sweep by a real click on its ribbon button: the dialog picks the profile (f1) and the path (f2); OK by click: ONE undo step, one "sweep" feature
##   2 VOLUME    the body's volume = pi r^2 x path length within 1 percent (the dialog's preview says the same before OK)
##   3 STRAIGHT  (record) the same circle along a straight 100 mm path equals the extrude of the same circle 100 mm, within 0.1 percent
##   4 KINK      (record) a path with a 90 degree corner: one body, no failed step, volume within 2 percent of pi r^2 x (the length less the corner rounding)
##   5 CLOSED    the mesh of the swept body is closed (every triangle edge shared by two triangles, welded at 1 um)
##   6 FILE      save, new scene, load: the same record, the same volume within 1e-9 m3
##   7 SHOT      the Part view with the sweep: C:/Temp/claude/psweep/shot.png
## Only user:// is written (and the screenshots). With no DLL it says so and stops.
var fails := 0
var m: Node
const SHOT := "C:/Temp/claude/psweep"
const DIRT := "user://psweep_test"
const CIRC_AREA := PI * 1e-4   # m2: a 20 mm circle


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


## a Part tool as a user reaches it: its own button, else its group caption menu, else More (as ploft_test does)
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


func E(v: float) -> String:
	return String.num_scientific(v)


## triangle edges used other than twice (0 = closed), welded at 1 um; -1 = no mesh
func open_edges(mesh: ArrayMesh) -> int:
	if mesh == null or mesh.get_surface_count() == 0:
		return -1
	var arr := mesh.surface_get_arrays(0)
	var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var idx = arr[Mesh.ARRAY_INDEX]
	var n: int = idx.size() if idx != null else v.size()
	var cnt := {}
	for t in range(0, n, 3):
		var ids := []
		for k in 3:
			var p: Vector3 = v[idx[t + k]] if idx != null else v[t + k]
			ids.append(Vector3i(roundi(p.x * 1e6), roundi(p.y * 1e6), roundi(p.z * 1e6)))
		for k in 3:
			var sa := str(ids[k])
			var sb := str(ids[(k + 1) % 3])
			var key := "%s|%s" % [sa, sb] if sa < sb else "%s|%s" % [sb, sa]
			cnt[key] = int(cnt.get(key, 0)) + 1
	var bad := 0
	for key in cnt:
		if int(cnt[key]) != 2:
			bad += 1
	return bad


func circle_ents() -> Array:
	return [{"k": "circle", "c": [0, 0], "r": 10}]


## the straight and arc path (Top plane: +v is -Z, so the path runs down the world Z axis from the origin)
func arc_path() -> Array:
	return [{"k": "line", "a": [0, 0], "b": [0, -100]}, {"k": "arc", "a": [0, -100], "m": [13.18, -131.82], "b": [45, -145]}]


func rec_with(path_ents: Array) -> Dictionary:
	var r := Part.make("Sweep test")
	r["features"] = [
		{"t": "sketch", "id": "f1", "name": "Sketch1", "plane": "front", "ents": circle_ents(), "dims": []},
		{"t": "sketch", "id": "f2", "name": "Sketch2", "plane": "top", "ents": path_ents, "dims": []},
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
		print("SKIP: no KineCAD DLL; psweep needs the kernel")
		quit(0)
		return
	# set up: the Part workspace as a user opens it (the building card, then PART), the two sketches as the record
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
	m.S.part = rec_with(arc_path())
	bld.sync()
	await idle(2)
	var path := DIRT + "/psweep.json"
	var fh: FileAccess
	# 1 RIBBON: Sweep by real clicks
	var n0: int = m.undo.size()
	await press_tool(pu, "Sweep")
	ok(pu.dlg.size() > 0 and String(pu.dlg["t"]) == "sweep" and pu.side.visible, "1 Sweep opens its dialog on the right")
	var pick: Array = pu.dlg.get("pick", [])
	ok(pick.size() == 2 and pick[0] == "f1" and pick[1] == "f2", "1 the pickers list the two sketches (%s)" % [pick])
	ok(pu.f_sw_prof.selected == 0 and pu.f_sw_path.selected == 1, "1 the profile is f1 and the path f2 by default")
	var prev_v: float = float(pu.prev.get("volume", 0.0)) if not pu.prev.is_empty() else 0.0
	var L := 170.69e-3
	ok(absf(prev_v / (CIRC_AREA * L) - 1.0) < 0.01, "2 the dialog preview: %s m3 (pi r^2 L = %s)" % [E(prev_v), E(CIRC_AREA * L)])
	await click_ctl(pu.ok_btn)
	await idle(3)
	var sf := Part.feature(m.S.part, "f3")
	ok(String(sf.get("t", "")) == "sweep" and String(sf.get("profile", "")) == "f1" and String(sf.get("path", "")) == "f2", "1 the record: a sweep of f1 along f2 (%s)" % [sf])
	ok(m.undo.size() == n0 + 1, "1 OK = ONE undo step (%d)" % (m.undo.size() - n0))
	ok(pu.dlg.is_empty() and pu.tool == "", "1 the dialog closes after OK")
	# 2 VOLUME of the swept body
	var rp := Part.replay(m.S.part)
	var vol := float(rp["volume"])
	ok(int(rp["bodies"]) == 1 and (rp["errors"] as Dictionary).is_empty(), "2 one body, no failed step (errors %s)" % [rp["errors"]])
	ok(absf(vol / (CIRC_AREA * L) - 1.0) < 0.01, "2 volume %s = pi r^2 x 170.69 mm within 1 percent (%s)" % [E(vol), E(CIRC_AREA * L)])
	# 3 STRAIGHT equals the extrude
	var rs := Part.make("S")
	rs["features"] = [
		{"t": "sketch", "id": "f1", "name": "Sketch1", "plane": "front", "ents": circle_ents(), "dims": []},
		{"t": "sketch", "id": "f2", "name": "Sketch2", "plane": "top", "ents": [{"k": "line", "a": [0, 0], "b": [0, -100]}], "dims": []},
		{"t": "sweep", "id": "f3", "name": "Sweep1", "profile": "f1", "path": "f2", "op": "new"},
	]
	var re := Part.make("E")
	re["features"] = [
		{"t": "sketch", "id": "f1", "name": "Sketch1", "plane": "front", "ents": circle_ents(), "dims": []},
		{"t": "extrude", "id": "f2", "name": "Extrude1", "sketch": "f1", "dist": 100.0, "both": false, "op": "new"},
	]
	var v_sw := float(Part.replay(rs)["volume"])
	var v_ex := float(Part.replay(re)["volume"])
	ok(v_ex > 0.0 and absf(v_sw / v_ex - 1.0) < 0.001, "3 straight sweep %s = extrude %s within 0.1 percent" % [E(v_sw), E(v_ex)])
	# 4 KINK: a 90 degree corner: one body, no failed step, volume within 2 percent of the rounded length
	var rk := rec_with([{"k": "line", "a": [0, 0], "b": [0, -100]}, {"k": "line", "a": [0, -100], "b": [60, -100]}])
	(rk["features"] as Array).append({"t": "sweep", "id": "f3", "name": "Sweep1", "profile": "f1", "path": "f2", "op": "new"})
	var rkr := Part.replay(rk)
	var vk := float(rkr["volume"])
	var kink_len := 0.1 + 0.06 - (2.0 - PI / 2.0) * 0.015   # the fillet (radius 15 mm = 1.5 x the 10 mm profile) cuts the corner
	ok(int(rkr["bodies"]) == 1 and (rkr["errors"] as Dictionary).is_empty() and absf(vk / (CIRC_AREA * kink_len) - 1.0) < 0.02, "4 kinked path: one body, no failed step, volume %s vs %s" % [E(vk), E(CIRC_AREA * kink_len)])
	# 5 CLOSED
	var mesh: ArrayMesh = rp["mesh"]
	var oe := open_edges(mesh)
	ok(oe == 0, "5 the swept mesh is closed (%d open edges)" % oe)
	# 6 FILE
	var saved := JSON.stringify(JSON.parse_string(JSON.stringify(m.S.part)))
	fh = FileAccess.open(path, FileAccess.WRITE)
	fh.store_string(JSON.stringify(m.S.to_dict(m.B, false)))
	fh.close()
	m._new_scene()
	await idle(3)
	if m.ui_save_ask != null and m.ui_save_ask.visible:
		m._save_ask_choose("discard")
	await idle(2)
	ok(m.S.part.is_empty(), "6 a new scene has no part")
	m._load_scene(path)
	await idle(4)
	bld.sync()
	await idle(2)
	var vol2 := float(Part.replay(m.S.part)["volume"])
	ok(JSON.stringify(JSON.parse_string(JSON.stringify(m.S.part))) == saved and absf(vol2 - vol) < 1e-9, "6 reopened: the same record, volume %s (was %s)" % [E(vol2), E(vol)])
	# 7 SHOT
	pu._view_model()
	await idle(3)
	var img := root.get_texture().get_image()
	img.save_png("%s/shot.png" % SHOT)
	print("psweep: %d fail" % fails)
	quit(1 if fails > 0 else 0)
