extends SceneTree
## godot --headless --path . -s tests/c45_test.gd     (C45, M #233 / F #203: pick the one you mean)
## Bars, written before measuring:
##  A MESH   face mode, test cube. First plain click = front face F (as origin). A quick 2nd click (<0.6 s, <3 px) = a hidden face G != F, a 3rd wraps to F; a slow click or one elsewhere is ordinary. Alt+click on an edge = the origin loop set (same as select_loop). Nothing deleted.
##           Alt+click at the same spot picks F; Alt+click again picks a DIFFERENT face G that is hidden (not visible from the camera);
##           a third wraps round to F (the cube has 2 faces on the ray). Face count and vert count never change (nothing deleted).
##           The status line names the pick ("N of M"). CONTROL: G != F and G is hidden (a plain click can never give it).
##  B SKETCH three lines meet at (100,60) plus a rect + a line across it. Alt+click on the shared corner lists >= 3 points before >= 2 edges;
##           the list is in rule order (point < edge < face, never out of order); the rule words "point > edge > face" are in the status.
##           Alt+click inside the rect on a line lists edge before face. Choosing list item 2 sets the pick to that entry (status names it).
##           A plain click (no Alt) at the corner opens no list, picks nothing, adds no entity (default unchanged).
##           CONTROL: a spot with nothing there lists nothing and says so.
## 240 s watchdog. Shots: C:/Users/Nick/tools/kine_workers/out/c45/.
const SHOT := "C:/Users/Nick/tools/kine_workers/out/c45"
const DIRT := "user://c45_test"
var fails := 0
var m: Node


func ok(c: bool, w: String) -> void:
	print(("ok   " if c else "FAIL ") + w)
	fails += 0 if c else 1


func idle(n := 3) -> void:
	for i in n:
		await process_frame


func ev_mouse(p: Vector2, down: bool, alt := false) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = down
	e.alt_pressed = alt
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


func key(k: Key) -> void:
	var e := InputEventKey.new()
	e.keycode = k
	e.physical_keycode = k
	e.pressed = true
	root.push_input(e, true)
	await idle(2)


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


func ev_alt(p: Vector2) -> void:
	await ev_move(p, false)
	await ev_mouse(p, true, true)
	await ev_mouse(p, false, true)
	await idle(2)


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


func sp2(x: float, y: float) -> Vector2:
	return m.cam.unproject_position(Part.to_world(Part.plane("front"), Vector2(x, y)))


func mk(p: Vector2, alt := false, pressed := true) -> InputEventMouseButton:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = pressed
	e.alt_pressed = alt
	e.position = p
	return e


func shot(nm: String) -> void:
	await idle(3)
	DirAccess.make_dir_recursive_absolute(SHOT)
	var img: Image = root.get_texture().get_image()
	if img != null:
		img.save_png("%s/%s.png" % [SHOT, nm])


func top_face_spot(ui) -> Array:
	var cam: Camera3D = ui.m.cam
	var best := -1
	for fi in ui.mesh.face_count():
		if absf(ui.mesh.face_center(fi).y - 0.3) > 1e-6:
			continue
		if ui.view.point_visible(cam, ui.view.global_transform * ui.mesh.face_center(fi)):
			best = fi
			break
	return [best, cam.unproject_position(ui.view.global_transform * ui.mesh.face_center(best))]


func click_mesh(ui, p: Vector2, alt := false) -> void:
	ui.input(mk(p, alt))
	ui.input(mk(p, alt, false))


func _init() -> void:
	var dog := create_timer(240.0)
	dog.timeout.connect(func():
		print("FAIL watchdog: c45 ran 240 s")
		quit(2))
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(8)
	m.tour_step = -1
	if m.ui_tour != null:
		m.ui_tour.visible = false
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	root.content_scale_size = Vector2i(1280, 720)
	await idle(4)

	# ---------------- A MESH
	m._kmesh_edit_start()
	await idle(3)
	var ui = m.kmed
	var k3 := InputEventKey.new()
	k3.pressed = true
	k3.keycode = KEY_3
	k3.physical_keycode = KEY_3
	ui.input(k3)
	ui.sel.set_mode(KMeshSelect.FACE)
	var ts := top_face_spot(ui)
	var f_front: int = ts[0]
	var spot: Vector2 = ts[1]
	var nv0: int = ui.mesh.vert_count()
	var nf0: int = ui.mesh.face_count()
	click_mesh(ui, spot)
	var p1: Array = ui.sel.faces.keys()
	ok(p1 == [f_front], "A1 a first plain click picks the front face %d (as before): %s" % [f_front, str(p1)])
	click_mesh(ui, spot + Vector2(40, 0))   # elsewhere: an ordinary click (a different face or a miss, never the one behind)
	await get_root().get_tree().create_timer(0.7).timeout
	click_mesh(ui, spot)
	ok(ui.sel.faces.keys() == [f_front], "A1b a slow second click (0.7 s) is an ordinary click: front face again %s" % str(ui.sel.faces.keys()))
	var picks := []
	await get_root().get_tree().create_timer(0.7).timeout
	for i in 4:
		click_mesh(ui, spot)
		picks.append((ui.sel.faces.keys() as Array)[0] if ui.sel.faces.size() == 1 else -1)
	var g: int = picks[1]
	ok(picks[0] == f_front and g >= 0 and g != f_front, "A2 quick repeated clicks: front %d, then a different face %d (picks %s)" % [f_front, g, str(picks)])
	ok(g >= 0 and not ui.view.point_visible(ui.m.cam, ui.view.global_transform * ui.mesh.face_center(g)), "A3 the second pick (face %d) is hidden from the camera" % g)
	ok(picks[2] == f_front and picks[3] == g, "A4 it wraps round (%s)" % str(picks))
	ok(ui.mesh.vert_count() == nv0 and ui.mesh.face_count() == nf0, "A5 nothing deleted: %d verts %d faces unchanged" % [nv0, nf0])
	var st := String(m.ui_status.text)
	ok(st.contains("of 2"), "A6 status names the pick: '%s'" % st.left(100))
	# A7: Alt+click on an edge in face mode is the origin's edge loop, same set as select_loop on a fresh selection
	await get_root().get_tree().create_timer(0.7).timeout
	ui.sel.clear()
	var fp: PackedInt32Array = ui.mesh.faces[f_front]
	var wa: Vector2 = ui.m.cam.unproject_position(ui.view.global_transform * ui.mesh.verts[fp[0]])
	var wb: Vector2 = ui.m.cam.unproject_position(ui.view.global_transform * ui.mesh.verts[fp[1]])
	var emid := (wa + wb) * 0.5 + (spot - (wa + wb) * 0.5).normalized() * 3.0
	var h: Dictionary = ui.view.pick(ui.m.cam, emid)
	var exp := KMeshSelect.new(ui.mesh, KMeshSelect.FACE)
	if not h.is_empty() and (h["edge"] as Vector2i).x >= 0:
		exp.select_loop((h["edge"] as Vector2i).x, (h["edge"] as Vector2i).y, false)
	click_mesh(ui, emid, true)
	var got: Array = ui.sel.edges.keys()
	got.sort()
	var want: Array = exp.edges.keys()
	want.sort()
	ok(not want.is_empty() and got == want and ui.sel.mode == exp.mode, "A7 Alt+click on an edge in face mode: the origin's loop selection (%d edges, same set, mode as select_loop leaves it)" % got.size())
	ui.sel.clear()
	var cp: Vector3 = ui.view.global_position
	ui.m.cam.look_at_from_position(cp + Vector3(0.5, 0.9, 1.1), cp + Vector3(0, 0.1, 0))
	await idle(4)
	ui.sel.set_mode(KMeshSelect.FACE)
	var best := Vector2(640, 330)
	var bd := 1.0e9
	for fi in ui.mesh.face_count():
		var c: Vector3 = ui.view.global_transform * ui.mesh.face_center(fi)
		if not ui.view.point_visible(ui.m.cam, c):
			continue
		var q: Vector2 = ui.m.cam.unproject_position(c)
		if q.x < 330 or q.x > 1000 or q.y < 170 or q.y > 560:
			continue
		if q.distance_to(Vector2(640, 330)) < bd:
			bd = q.distance_to(Vector2(640, 330))
			best = q
	await get_root().get_tree().create_timer(0.7).timeout
	click_mesh(ui, best)
	await idle(4)
	await shot("mesh_front")
	click_mesh(ui, best)
	await idle(4)
	await shot("mesh_behind")
	ui.stop()
	await idle(2)

	# ---------------- B SKETCH
	var ss: StartScreen = m.start_screen
	var bld: BuildUI = m.bld
	var pu: PartUI = bld.part
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIRT))
	ss.dirs_override = [DIRT]
	if not Part.available():
		print("SKIP B: no KineCAD DLL")
		print("c45: %d fail" % fails)
		quit(1 if fails > 0 else 0)
		return
	ss.show_screen()
	await idle(3)
	await click_ctl(ss._cards["building"])
	if m.ui_save_ask != null and m.ui_save_ask.visible:
		m._save_ask_choose("discard")
	await idle(6)
	pu.set_on(false)
	pu.m.S.part = {}
	await process_frame
	await click_ctl(pu.part_btn)
	await idle(3)
	await click_ctl(pu.browser.find_child("part_plane_front", true, false))
	ok(pu.sk != "", "B0 a sketch is open")
	await press_tool(pu, "Line")
	for q in [[0, 0], [100, 0], [100, 60], [0, 60], [0, 0]]:
		await click_at(sp2(q[0], q[1]))
	await key(KEY_ESCAPE)
	await press_tool(pu, "Line")
	await click_at(sp2(100, 60))
	await click_at(sp2(150, 100))
	await key(KEY_ESCAPE)
	pu.tool = ""
	pu.draft = {}
	pu._add_ent({"k": "rect", "a": [-90.0, 10.0], "b": [-10.0, 80.0]})
	pu._add_ent({"k": "line", "a": [-100.0, 45.0], "b": [0.0, 45.0]})
	await idle(2)
	var n_ents: int = pu._sk()["ents"].size()
	ok(pu.tool == "" and pu.draft.is_empty(), "B0 no tool, nothing being drawn (%d entities)" % n_ents)
	await ev_alt(sp2(100, 60))
	var ps_: PartPickStack = pu.pick_stack
	var it: Array = ps_.items if ps_ != null else []
	var np := it.filter(func(x): return x["kind"] == "point").size()
	var ne := it.filter(func(x): return x["kind"] == "edge").size()
	ok(np >= 3 and ne >= 2, "B1 the corner (100,60): %d points then %d edges listed" % [np, ne])
	var ordered := true
	for i in range(1, it.size()):
		if PartPickStack.PRI[it[i]["kind"]] < PartPickStack.PRI[it[i - 1]["kind"]]:
			ordered = false
	ok(ordered and not it.is_empty() and it[0]["kind"] == "point", "B2 listed in rule order (%s), first is a point" % str(it.map(func(x): return x["kind"])))
	ok(String(m.ui_status.text).contains("point > edge > face"), "B3 the rule is stated in the status: '%s'" % String(m.ui_status.text).left(110))
	ok(ps_ != null and ps_.popup != null and ps_.popup.visible and ps_.popup.item_count >= it.size(), "B4 the stack picker list is showing with %d rows" % (ps_.popup.item_count if ps_ != null and ps_.popup != null else -1))
	await shot("sketch_stack_list")
	ps_._choose(1)
	await idle(2)
	ok(not ps_.chosen.is_empty() and ps_.chosen == it[1] and String(m.ui_status.text).contains("Picked"), "B5 choosing row 2 picks that item: %s" % str(ps_.chosen.get("label", "")))
	ps_.popup.hide()
	await idle(5)
	await shot("sketch_stack_picked")
	await ev_alt(sp2(-50, 45) + Vector2(0, 4))
	it = ps_.items
	var kinds := it.map(func(x): return x["kind"])
	var ie := kinds.find("edge")
	var iff := kinds.find("face")
	ok(ie >= 0 and iff > ie, "B6 inside the rect on a line: edge (row %d) before face (row %d)" % [ie, iff])
	ps_.popup.hide()
	ps_.chosen = {}
	await click_at(sp2(100, 60))
	ok(pu._sk()["ents"].size() == n_ents and ps_.chosen.is_empty() and not ps_.popup.visible, "B7 plain click at the corner: no list, no pick, no new entity (default unchanged)")
	await ev_alt(sp2(400, 300))
	ok(ps_.items.is_empty() and String(m.ui_status.text).contains("Nothing under"), "B8 control: an empty spot lists nothing and says so ('%s')" % String(m.ui_status.text).left(60))
	print("c45: %d fail" % fails)
	quit(1 if fails > 0 else 0)
