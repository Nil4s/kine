extends SceneTree
## godot --path . --position 4000,4000 -s tests/ploft_test.gd     (GAP item 2, LOFT BETWEEN PROFILES: scripts/build/part.gd _loft + part_ui.gd Loft / Offset plane; needs a window and the CAD DLL)
## A 100 x 60 mm rectangle on the Front plane (z = 0), and a 60 x 40 mm rectangle on an OFFSET plane 50 mm in front of it (Offset plane, typed 50 mm).
## Bars (closed forms from the geometry; a ruled frustum of two rectangles: V = h/3 (A1 + A2 + sqrt(A1 A2)) = 50/3 (6000 + 2400 + 3795) mm3 = 2.0325e-4 m3):
##   0 GREY      Loft is greyed with no profiles (its tip says two)
##   1 SKETCH    Front sketch by drags (100 x 60) and Offset plane (Front, 50 mm, typed, OK by click) = a plane row in the browser; a sketch on it by
##               that row (click), a 60 x 40 rectangle dragged on the offset plane; each Finish sketch is one step
##   2 RIBBON    Loft by real clicks (its button, or its caption menu): the dialog picks the profiles in order (the first sketch, then the second);
##               OK by click: ONE undo step, one feature with sketches [f1, f3] in that order, ruled
##   3 VOLUME    ruled: 1 body, volume 2.0325e-4 m3 within 2 percent (the preview of the dialog says the same before OK)
##   4 CLOSED    the mesh is closed: every triangle edge is shared by exactly two triangles (welded at 1 um)
##   5 SMOOTH    (record) a third 80 x 50 mm sketch on an offset plane 100 mm out, lofted smooth (ruled false) through f1, f3, f5: no failed step,
##               1 body, closed, volume above the ruled one (the bulge)
##   6 FILE      save, new scene, load: the same record, the same volume within 1e-9 m3 (the ruled loft)
##   7 SHOT      the Part view with the loft shown: C:/Temp/claude/ploft/shot.png
## Only user:// is written (and the screenshots). Needs a window (the clicks and the picture); with no DLL it says so and stops.
const KCad := preload("res://scripts/kcad.gd")
var fails := 0
var m: Node
const SHOT := "C:/Temp/claude/ploft"
const DIRT := "user://ploft_test"
const FRUSTUM := 2.0325e-4


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


## a Part tool as a user reaches it: its own button, else its group caption menu, else More (as partws_test does)
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
	await key(KEY_A, true)
	for ch in txt:
		await key(KEY_0 + int(ch) if ch != "." else KEY_PERIOD, false, ch.unicode_at(0))
	await key(KEY_ENTER)
	await idle(2)


func E(v: float) -> String:
	return String.num_scientific(v)


func ps() -> String:
	return JSON.stringify(m.S.part) if not m.S.part.is_empty() else "{}"


## the screen point of a point (mm) on a plane
func spp(pl: Dictionary, x: float, y: float) -> Vector2:
	return m.cam.unproject_position(Part.to_world(pl, Vector2(x, y)))


func drag_on(pl: Dictionary, x0: float, y0: float, x1: float, y1: float) -> void:
	await ev_move(spp(pl, x0, y0), false)
	await ev_mouse(spp(pl, x0, y0), true)
	await ev_move(spp(pl, (x0 + x1) * 0.5, (y0 + y1) * 0.5))
	await ev_move(spp(pl, x1, y1))
	await ev_mouse(spp(pl, x1, y1), false)
	await idle(2)


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


func rect_ents(w: float, h: float) -> Array:
	return [{"k": "rect", "a": [0, 0], "b": [w, h]}]


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
		print("SKIP: no KineCAD DLL; ploft needs the kernel")
		quit(0)
		return
	ss.show_screen()
	await idle(3)
	await click_ctl(ss._cards["building"])
	if m.ui_save_ask != null and m.ui_save_ask.visible: m._save_ask_choose("discard")
	await idle(6)
	# Nick 2026-10-28 (free 3D building, #100): the BUILDING card now opens a blank Easy Part itself. Start from the
	# state the card gave before (Part off, no part), so the clicks below drive the same opening they always did
	pu.set_on(false)
	pu.m.S.part = {}
	await process_frame
	await click_ctl(pu.part_btn)
	await idle(3)
	ok((pu.tool_btns["Loft"] as Button).disabled and String((pu.tool_btns["Loft"] as Button).tooltip_text).contains("two"), "0 Loft greyed with no profiles (tip: %s)" % String((pu.tool_btns["Loft"] as Button).tooltip_text).left(70))

	# 1 SKETCH: profile A on the Front plane, 100 x 60
	await click_ctl(pu.browser.find_child("part_plane_front", true, false))
	await press_tool(pu, "Rectangle")
	var front := Part.plane("front")
	await drag_on(front, 0, 0, 100, 60)
	var ea: Array = pu._sk().get("ents", [])
	ok(ea.size() == 1 and ea[0]["k"] == "rect" and Part.v2(ea[0]["b"]).is_equal_approx(Vector2(100, 60)), "1 profile A dragged 100 x 60 on Front: %s" % [ea])
	await click_ctl(pu.finish_btn)
	ok(pu.sk == "" and String(Part.feature(m.S.part, "f1").get("plane", "")) == "front", "1 Finish sketch: sketch f1 on Front")

	# 1 OFFSET PLANE by the ribbon: Offset plane, 50 mm from Front
	var n0: int = m.undo.size()
	await press_tool(pu, "Offset plane")
	ok(pu.dlg.size() > 0 and String(pu.dlg["t"]) == "plane" and pu.side.visible, "1 Offset plane opens its dialog on the right")
	await type_in(pu.f_num, "50")
	pu.f_plane.select(0)
	pu.f_plane.item_selected.emit(0)
	await idle(2)
	await click_ctl(pu.ok_btn)
	await idle(2)
	var pf := m.S.part["features"] as Array
	var plane_f: Dictionary = pf[-1] if not pf.is_empty() else {}
	ok(String(plane_f.get("t", "")) == "plane" and String(plane_f.get("from", "")) == "front" and absf(float(plane_f.get("mm", 0.0)) - 50.0) < 1e-6, "1 Offset plane: %s" % [plane_f])
	ok(m.undo.size() == n0 + 1, "1 Offset plane: one undo step (%d)" % (m.undo.size() - n0))

	# 1 SKETCH on the offset plane: its browser row, rectangle 60 x 40 dragged on it
	var pid := String(plane_f.get("id", ""))
	var prow := pu.browser.find_child("part_plane_" + pid, true, false) as Button
	ok(prow != null, "1 the offset plane is a browser row (part_plane_%s)" % pid)
	if prow == null:
		quit(1)
		return
	await click_ctl(prow)
	ok(pu.sk != "" and String(pu._sk()["plane"]) == pid, "1 the offset plane row starts a sketch on it")
	var offp := Part.resolve_plane(m.S.part, pid)
	await press_tool(pu, "Rectangle")
	await drag_on(offp, 0, 0, 60, 40)
	var eb: Array = pu._sk().get("ents", [])
	ok(eb.size() == 1 and Part.v2(eb[0]["b"]).is_equal_approx(Vector2(60, 40)), "1 profile B dragged 60 x 40 on the offset plane: %s" % [eb])
	await click_ctl(pu.finish_btn)
	ok(pu.sk == "" and String(Part.feature(m.S.part, "f3").get("plane", "")) == pid, "1 Finish sketch: f3 on %s" % pid)
	await shot("sketches")

	# 2 RIBBON LOFT by real clicks
	await press_tool(pu, "Loft")
	ok(pu.dlg.size() > 0 and String(pu.dlg["t"]) == "loft" and pu.side.visible, "2 Loft opens its dialog (two sketches now)")
	ok(not (pu.tool_btns["Loft"] as Button).disabled, "2 Loft is no longer greyed with two sketches")
	var pick: Array = pu.dlg.get("pick", [])
	ok(pick.size() == 2 and pick[0] == "f1" and pick[1] == "f3", "2 the picker lists the profiles in order (%s)" % [pick])
	ok(pu.dlg["sketches"].is_empty() and pu.ok_btn.disabled, "2 OK is off until two profiles are picked")
	pu.f_prof.item_selected.emit(1)   # the first profile (f1)
	await idle(1)
	pu.f_prof.item_selected.emit(2)   # the second profile (f3)
	await idle(2)
	ok(pu.dlg["sketches"] == ["f1", "f3"], "2 picked in order: %s" % [pu.dlg["sketches"]])
	var prev_v: float = float(pu.prev.get("volume", 0.0)) if not pu.prev.is_empty() else 0.0
	ok(absf(prev_v / FRUSTUM - 1.0) < 0.02, "3 the dialog preview: %s m3 (frustum %s)" % [E(prev_v), E(FRUSTUM)])
	await shot("loft_dialog")
	n0 = m.undo.size()
	await click_ctl(pu.ok_btn)
	await idle(3)
	var lf := Part.feature(m.S.part, "f4")
	ok(String(lf.get("t", "")) == "loft" and lf.get("sketches", []) == ["f1", "f3"] and bool(lf.get("ruled", false)), "2 the record: a ruled loft through f1, f3 (%s)" % [lf])
	ok(m.undo.size() == n0 + 1, "2 OK = ONE undo step (%d)" % (m.undo.size() - n0))
	ok(pu.dlg.is_empty() and pu.tool == "", "2 the dialog closes after OK")

	# 3 VOLUME, 4 CLOSED
	var vol: float = float(pu.res.get("volume", 0.0))
	ok(String(pu.res.get("errors", {}).get("f4", "")) == "" and int(pu.res.get("bodies", 0)) == 1, "3 the loft replays with no failed step, 1 body (errors %s)" % [pu.res.get("errors", {})])
	ok(absf(vol / FRUSTUM - 1.0) < 0.02, "3 volume %s m3 within 2 percent of the frustum %s (rel %s)" % [E(vol), E(FRUSTUM), E(absf(vol / FRUSTUM - 1.0))])
	var oe := open_edges(pu.res.get("mesh", null))
	ok(oe == 0, "4 the mesh is closed: %d edges not shared by two triangles" % oe)
	await shot("model")

	# 5 SMOOTH (record): a third profile 100 mm out, smooth through f1, f3, f5
	var rec: Dictionary = m.S.part.duplicate(true)
	var pl3 := Part.new_feature(rec, "plane", {"from": "front", "mm": 100.0})
	rec["features"].append(pl3)
	var s3 := Part.new_feature(rec, "sketch", {"plane": pl3["id"], "ents": rect_ents(80, 50), "dims": []})
	rec["features"].append(s3)
	rec["features"].append(Part.new_feature(rec, "loft", {"sketches": ["f1", "f3", s3["id"]], "ruled": false, "op": "join"}))
	var sm: Dictionary = Part.replay(rec)
	var sm_oe := open_edges(sm["mesh"])
	ok(sm["errors"].is_empty() and int(sm["bodies"]) == 1, "5 smooth 3-profile loft: no failed step, 1 body (errors %s)" % [sm["errors"]])
	ok(sm_oe == 0 and float(sm["volume"]) > vol, "5 smooth loft closed (%d open) and bigger than the ruled one (%s > %s)" % [sm_oe, E(float(sm["volume"])), E(vol)])

	# 6 FILE
	var saved := JSON.stringify(JSON.parse_string(ps()))
	var path := DIRT + "/ploft.json"
	var fh := FileAccess.open(path, FileAccess.WRITE)
	fh.store_string(JSON.stringify(m.S.to_dict(m.B, false)))
	fh.close()
	m._new_scene()
	await idle(3)
	if m.ui_save_ask != null and m.ui_save_ask.visible: m._save_ask_choose("discard")
	await idle(2)
	ok(m.S.part.is_empty(), "6 a new scene has no part")
	m._load_scene(path)
	await idle(4)
	bld.sync()
	await idle(2)
	var vol2 := float(pu.res.get("volume", 0.0))
	ok(JSON.stringify(JSON.parse_string(ps())) == saved and absf(vol2 - vol) < 1e-9, "6 reopened: the same record, volume %s (was %s)" % [E(vol2), E(vol)])

	# 7 SHOT
	pu._view_model()
	await shot("shot")
	print("ploft: %d fail" % fails)
	quit(1 if fails > 0 else 0)


func shot(nm: String) -> void:
	await idle(3)
	DirAccess.make_dir_recursive_absolute(SHOT)
	root.get_texture().get_image().save_png("%s/%s.png" % [SHOT, nm])
