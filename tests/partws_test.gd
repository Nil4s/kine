extends SceneTree
## godot --path . --position 4000,4000 -s tests/partws_test.gd     (EXPERT PART workspace, phase 1: scripts/build/part.gd + part_ui.gd on the BUILD page; needs a window and the CAD DLL)
## Bars, written before measuring (real clicks / drags / keys through root.push_input at 1280 x 720; a 3D BUILDING project; every number in the record is mm):
##   1 NO DLL    Part.force_off (= KCad.available() false): the Part tools are greyed, each tooltip and the note say KineCAD, nothing is made
##   2 SKETCH    Part button, Front plane in the browser, Rectangle dragged 95 x 25 mm, then Dimension: bottom edge typed 100, left edge typed 20 =
##               one rectangle (0,0)-(100,20) with two dimensions; Finish sketch = ONE undo step
##   3 EXTRUDE   Extrude, typed 5 mm: ONE step, volume 1e-5 m3 within 1e-9, one body, the mesh is 100 x 20 x 5 mm
##   4 FILLET    click one long top edge (it turns sky blue), Radius 2 typed: ONE step, volume = KCad's own box + fillet_edges on the same edge within 1e-9
##               (and the closed form 1e-5 - (1 - pi/4) r^2 L within 1e-6 relative)
##   5 TIMELINE  double-click the sketch step, the width number typed 120: ONE step; the extrude and the fillet replay: volume = 0.12 x 0.02 x 0.005 - the
##               fillet's closed form within 1e-6 relative, no step failed; undo / redo
##   6 REVOLVE   a second sketch (rectangle 150..180 x 30..40 mm), Revolve 360 deg round the horizontal axis as a NEW body: that body's volume
##               pi (40^2 - 30^2) 30 mm3 within 1e-6 relative, two bodies
##   7 UNDO      every step undone one by one back to no part, each state equal to the one recorded after it; redone to the end
##   8 FILE      save + new scene + reopen: the same record, the same volume
##   9 LAYOUT    at 1280 x 720 the browser, the right panel, the timeline and the note overlap nothing and stay inside the view, while sketching and while a fillet dialog is open
##  10 MIRROR    (data) a 10 mm cube at x 5..15 mirrored across the Right plane: volume 2 x 1e-6 within 1e-9
##  11 SWORD     blade outline (9 lines by clicks) -> Extrude both 8 mm -> Fillet one edge 2 mm; guard, grip and pommel revolved: every step ok, all joined into one
##               body, screenshots in C:/Temp/claude/partws/
## (the kernel takes float32 numbers, so a volume is good to about 1e-7 relative: the 1e-9 bars are absolute, in m3, on parts of 1e-5 m3)
## Only user:// is written (and the screenshots).
const KCad := preload("res://scripts/kcad.gd")
var fails := 0
var m: Node
const SHOT := "C:/Temp/claude/partws"
const DIRT := "user://partws_test"


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


## a Part tool as a user reaches it: its own button when the row shows it; else More, then the tool (1280 x 720: Fillet, Chamfer and
## Mirror sit in More, the row is full). Clicking a hidden button's last rect hit nothing (round 10-26: Fillet never opened)
func press_tool(pu: PartUI, t: String) -> void:
	var b: Button = pu.tool_btns[t]
	if b.is_visible_in_tree():
		await click_ctl(b)
		return
	await click_ctl(m.ui_more)
	m.ui_more.get_popup().hide()
	var i: int = m._more_tools.find(b)
	ok(i >= 0, "%s is in More at this size" % t)
	if i >= 0:
		m._more_pick(i)
	await idle(2)


func click_ctl_at(p: Vector2) -> void:
	await ev_move(p, false)
	await ev_mouse(p, true)
	await ev_mouse(p, false)
	await idle(2)


func E(v: float) -> String:
	return String.num_scientific(v)


func shot(nm: String) -> void:
	await idle(3)
	DirAccess.make_dir_recursive_absolute(SHOT)
	root.get_texture().get_image().save_png("%s/%s.png" % [SHOT, nm])


func ps() -> String:
	return JSON.stringify(m.S.part) if not m.S.part.is_empty() else "{}"


## the screen point of a sketch point (mm) on the Front plane
func sp2(x: float, y: float) -> Vector2:
	return m.cam.unproject_position(Part.to_world(Part.plane("front"), Vector2(x, y)))


func drag2(x0: float, y0: float, x1: float, y1: float) -> void:
	await ev_move(sp2(x0, y0), false)
	await ev_mouse(sp2(x0, y0), true)
	await ev_move(sp2((x0 + x1) * 0.5, (y0 + y1) * 0.5))
	await ev_move(sp2(x1, y1))
	await ev_mouse(sp2(x1, y1), false)
	await idle(2)


func type_in(le: LineEdit, txt: String) -> void:
	await click_ctl(le)
	await key(KEY_A, true)
	for ch in txt:
		await key(KEY_0 + int(ch) if ch != "." else KEY_PERIOD, false, ch.unicode_at(0))
	await key(KEY_ENTER)
	await idle(2)


func overlaps(names: Array) -> Array:
	var bad := []
	var cl: Rect2 = m.nav_clear_rect()
	var rs := []
	for c in names:
		var ctl: Control = c
		if ctl.visible:
			rs.append([ctl.name, Rect2(ctl.global_position, ctl.size)])
	for i in rs.size():
		var r: Rect2 = rs[i][1]
		if r.position.x < cl.position.x - 1.0 or r.end.x > cl.end.x + 1.0 or r.position.y < cl.position.y - 1.0 or r.end.y > cl.end.y + 1.0:
			bad.append("%s outside the clear view %s (clear %s)" % [rs[i][0], r, cl])
		for j in range(i + 1, rs.size()):
			if r.intersects(rs[j][1]):
				bad.append("%s overlaps %s" % [rs[i][0], rs[j][0]])
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
		print("SKIP: no KineCAD DLL (Part.available() false); only the no-DLL bar can run")
	ss.show_screen()
	await idle(3)
	await click_ctl(ss._cards["building"])
	if m.ui_save_ask != null and m.ui_save_ask.visible: m._save_ask_choose("discard")
	await idle(6)
	ok(m.cur_page == "BUILD" and m.S.kind == "building" and bld.on and pu.part_btn.visible, "0 a 3D BUILDING project on BUILD with the Part button (page %s, kind %s, build on %s, button visible %s, easy %s)" % [m.cur_page, m.S.kind, bld.on, pu.part_btn.visible, m.easy.on])

	# 1 NO DLL
	var had := Part.available()
	Part.force_off = true
	await click_ctl(pu.part_btn)
	await idle(3)
	var grey := true
	for t in pu.tool_btns:
		var b: Button = pu.tool_btns[t]
		grey = grey and b.disabled and b.tooltip_text.contains("KineCAD")
	ok(pu.on and grey and pu.note.visible and pu.note_l.text.contains("KineCAD"), "1 no DLL: Part tools greyed with the reason (note: %s)" % pu.note_l.text)
	await shot("nodll")
	pu._pick("Rectangle")   # (a greyed button cannot be clicked; the door itself also refuses)
	ok(m.S.part.is_empty() and pu.sk == "", "1 no DLL: asking for a tool makes nothing")
	Part.force_off = false
	await click_ctl(pu.part_btn)   # off
	await idle(2)
	ok(not pu.on and bld.house.visible, "1 the Part button again: back to the house tools")
	if not had:
		print("partws: %d fail (DLL missing: bars 2-11 skipped)" % fails)
		quit(1 if fails > 0 else 0)
		return
	await click_ctl(pu.part_btn)
	await idle(3)
	ok(pu.on and not bld.house.visible and (pu.tool_btns["Rectangle"] as Button).visible and not (pu.tool_btns["Rectangle"] as Button).disabled and (pu.tool_btns["Extrude"] as Button).disabled,
		"1 DLL: tools on, Extrude greyed until there is a sketch")

	if OS.get_environment("PARTWS_SWORD") != "":
		await sword(bld, pu)
		print("partws (sword only): %d fail" % fails)
		quit(1 if fails > 0 else 0)
		return

	# 2 SKETCH
	var n0: int = m.undo.size()
	var states := [ps()]
	await click_ctl(pu.browser.find_child("part_plane_front", true, false))
	ok(pu.sk != "" and String(pu._sk()["plane"]) == "front", "2 the Front plane in the browser starts a sketch")
	await click_ctl(pu.tool_btns["Rectangle"])
	await drag2(0, 0, 95, 25)
	var ents: Array = pu._sk()["ents"]
	ok(ents.size() == 1 and ents[0]["k"] == "rect" and Part.v2(ents[0]["b"]).is_equal_approx(Vector2(95, 25)), "2 a rectangle dragged 95 x 25: %s" % [ents])
	await shot("sketch_rect")
	await click_ctl(pu.tool_btns["Dimension"])
	await click_ctl_at(sp2(47.5, 0))
	ok(pu.dim_edit.visible, "2 Dimension on the bottom edge opens the type box")
	await type_in(pu.dim_edit, "100")
	await click_ctl_at(sp2(0, 12.5))
	await type_in(pu.dim_edit, "20")
	var sk0: Dictionary = pu._sk()
	ok(Part.v2(sk0["ents"][0]["b"]).is_equal_approx(Vector2(100, 20)) and sk0["dims"].size() == 2, "2 typed 100 and 20: rectangle %s, %d dimensions" % [sk0["ents"][0], sk0["dims"].size()])
	await shot("sketch_dims")
	var bad := overlaps([pu.browser, pu.side, pu.tl, pu.note])
	ok(bad.is_empty(), "9 layout while sketching: %s" % [bad])
	await click_ctl(pu.finish_btn)
	ok(pu.sk == "" and m.undo.size() == n0 + 1 and m.S.part["features"].size() == 1, "2 Finish sketch: one step (%d), %d feature" % [m.undo.size() - n0, m.S.part["features"].size()])
	states.append(ps())

	# 3 EXTRUDE
	await click_ctl(pu.tool_btns["Extrude"])
	ok(pu.dlg.size() > 0 and pu.side.visible, "3 Extrude opens its dialog on the right")
	n0 = m.undo.size()
	await type_in(pu.f_num, "5")
	var r3: Dictionary = Part.replay(m.S.part)
	print("   undo delta %d: %s" % [m.undo.size() - n0, m.undo.slice(n0).map(func(u): return u.get("hint", "?"))])
	ok(m.undo.size() == n0 + 1 and m.S.part["features"].size() == 2 and absf(float(pu.res["volume"]) - 1e-5) < 1e-9 and absf(float(r3["volume"]) - 1e-5) < 1e-9 and int(pu.res["bodies"]) == 1,
		"3 Extrude 5 mm: one step, volume %s (want 1e-5 within 1e-9), %d body" % [E(float(pu.res["volume"])), int(pu.res["bodies"])])
	var bb: AABB = pu.part_mesh.mesh.get_aabb() if pu.part_mesh.mesh != null else AABB()
	ok(absf(bb.size.x - 0.1) < 1e-4 and absf(bb.size.y - 0.02) < 1e-4 and absf(bb.size.z - 0.005) < 1e-4, "3 the mesh is %s" % [bb.size])
	await shot("model_extrude")
	states.append(ps())

	# 4 FILLET
	await press_tool(pu, "Fillet")
	ok(pu.dlg.size() > 0 and pu.edge_cache.size() == 12, "4 Fillet: its dialog, %d edges to pick" % pu.edge_cache.size())
	var target := Vector3(0.05, 0.02, 0.005)   # the long top edge on the +y side
	await click_ctl_at(m.cam.unproject_position(target))
	ok(pu.picked.size() == 1 and (pu.picked[0]["c"] as Vector3).distance_to(target) < 1e-4, "4 one edge picked at %s" % [pu.picked[0]["c"] if pu.picked.size() > 0 else "-"])
	n0 = m.undo.size()
	await shot("fillet_dialog")
	bad = overlaps([pu.browser, pu.side, pu.tl, pu.note])
	ok(bad.is_empty(), "9 layout with the fillet dialog: %s" % [bad])
	await type_in(pu.f_num, "2")
	var bx := KCad.box(0.1, 0.02, 0.005)
	var ids := PackedInt32Array()
	var es := KCad.edges(bx)
	var top := Vector3(-INF, -INF, -INF)
	for e in es:
		top = top.max(e["center"])
	for e in es:
		if absf((e["center"] as Vector3).y - top.y) < 1e-6 and absf((e["center"] as Vector3).z - top.z) < 1e-6 and absf((e["dir"] as Vector3).x) > 0.9:
			ids.append(e["id"])
	var fb := KCad.fillet_edges(bx, ids, 0.002)
	var v_direct := KCad.volume(fb)
	var v_closed := 1e-5 - (1.0 - PI / 4.0) * 4e-6 * 0.1
	var v4: float = pu.res["volume"]
	ok(m.undo.size() == n0 + 1 and m.S.part["features"].size() == 3 and absf(v4 - v_direct) < 1e-9 and absf(v4 / v_closed - 1.0) < 1e-6,
		"4 Fillet 2 mm on one edge: one step, volume %s, KCad direct %s (diff %s), closed form %s (rel %s)" % [E(v4), E(v_direct), E(absf(v4 - v_direct)), E(v_closed), E(absf(v4 / v_closed - 1.0))])
	KCad.release(bx)
	KCad.release(fb)
	states.append(ps())

	# 5 TIMELINE
	n0 = m.undo.size()
	await click_ctl(pu.tl_row.find_child("part_step_0", true, false))
	await click_ctl(pu.tl_row.find_child("part_step_0", true, false))   # the second click, inside the double-click time
	ok(pu.sk != "" and pu.tl_info.text.contains("Editing step 1 of 3"), "5 a double click on the sketch step opens it: \"%s\"" % pu.tl_info.text.replace("\n", " / "))
	var wf: LineEdit = pu.nums_vb.find_child("part_dim_0", true, false)
	await type_in(wf, "120")
	await shot("timeline_edit")
	await click_ctl(pu.finish_btn)
	var v5: float = pu.res["volume"]
	var v5w := 0.12 * 0.02 * 0.005 - (1.0 - PI / 4.0) * 4e-6 * 0.12
	ok(m.undo.size() == n0 + 1 and absf(v5 / v5w - 1.0) < 1e-6 and pu.res["errors"].is_empty(), "5 width 120: one step, volume %s (want %s, rel %s), failed steps %s" % [E(v5), E(v5w), E(absf(v5 / v5w - 1.0)), pu.res["errors"]])
	ok(absf(v5 / v4 - 1.2) < 0.01, "5 the volume scaled by %.4f (about 1.2: the fillet survived the rebuild)" % (v5 / v4))
	states.append(ps())
	m._undo()
	await idle(3)
	ok(ps() == states[3] and absf(float(pu.res["volume"]) - v4) < 1e-12, "5 undo: the 100 mm part is back")
	m._redo()
	await idle(3)
	ok(ps() == states[4] and absf(float(pu.res["volume"]) - v5) < 1e-12, "5 redo: 120 mm again")

	# 6 REVOLVE
	await click_ctl(pu.browser.find_child("part_plane_front", true, false))
	await click_ctl(pu.tool_btns["Rectangle"])
	await drag2(150, 30, 180, 40)
	await click_ctl(pu.finish_btn)
	states.append(ps())
	await click_ctl(pu.tool_btns["Revolve"])
	ok(pu.dlg.size() > 0 and String(pu.dlg["sketch"]) == String(m.S.part["features"][3]["id"]), "6 Revolve takes the newest sketch")
	pu.f_op.select(1)   # New body
	n0 = m.undo.size()
	await type_in(pu.f_ang, "360")
	var r6: Dictionary = pu.res
	var v6 := PI * (40.0 * 40.0 - 30.0 * 30.0) * 30.0 * 1e-9
	var vols: Array = r6["volumes"]
	var vnew: float = float(vols[1]) if vols.size() > 1 else -1.0
	ok(m.undo.size() == n0 + 1 and int(r6["bodies"]) == 2 and vols.size() == 2 and absf(vnew / v6 - 1.0) < 1e-6,
		"6 Revolve 360: one step, %d bodies, the new body %s (want %s, rel %s)" % [int(r6["bodies"]), E(vnew), E(v6), E(absf(vnew / v6 - 1.0))])
	await shot("model_revolve")
	states.append(ps())

	# 7 UNDO
	var ok7 := true
	for i in range(states.size() - 1, 0, -1):
		m._undo()
		await idle(2)
		if ps() != states[i - 1]:
			ok7 = false
			print("   undo of step %d did not give state %d" % [i, i - 1])
	ok(ok7 and m.S.part.is_empty(), "7 every step undone one by one back to no part (%d steps)" % (states.size() - 1))
	for i in range(1, states.size()):
		m._redo()
		await idle(2)
		if ps() != states[i]:
			ok7 = false
			print("   redo %d did not give state %d" % [i, i])
	ok(ok7 and absf(float(pu.res["volume"]) - (v5 + v6)) < 1e-9, "7 redone to the end: volume %s" % E(float(pu.res["volume"])))

	# 8 FILE
	var saved := JSON.stringify(JSON.parse_string(ps()))   # (a file holds every number as a float: 0 and 0.0 are the same record)
	var path := DIRT + "/part.json"
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify(m.S.to_dict(m.B, false)))
	f.close()
	m._new_scene()
	await idle(3)
	if m.ui_save_ask != null and m.ui_save_ask.visible: m._save_ask_choose("discard")
	await idle(2)
	ok(m.S.part.is_empty(), "8 a new scene has no part")
	m._load_scene(path)
	await idle(4)
	bld.sync()
	await idle(2)
	ok(JSON.stringify(JSON.parse_string(ps())) == saved and absf(float(pu.res["volume"]) - (v5 + v6)) < 1e-9, "8 reopened: the same record, volume %s" % E(float(pu.res["volume"])))

	# 10 MIRROR (data)
	var mr := Part.make("m")
	var mk := Part.new_feature(mr, "sketch", {"plane": "front", "ents": [{"k": "rect", "a": [5, 0], "b": [15, 10]}], "dims": []})
	mr["features"].append(mk)
	mr["features"].append(Part.new_feature(mr, "extrude", {"sketch": mk["id"], "dist": 10.0, "both": false, "op": "new"}))
	mr["features"].append(Part.new_feature(mr, "mirror", {"plane": "right", "op": "join"}))
	var rm := Part.replay(mr)
	ok(absf(float(rm["volume"]) - 2e-6) < 1e-9 and rm["errors"].is_empty(), "10 mirror across the Right plane: volume %s (want 2e-6)" % E(float(rm["volume"])))

	await sword(bld, pu)
	print("partws: %d fail" % fails)
	quit(1 if fails > 0 else 0)


func sword(bld: BuildUI, pu: PartUI) -> void:
	m.S.part = {}   # (a new part in the same building project)
	pu._rec_sig = ""
	bld.sync()
	await idle(3)
	ok(pu.on and m.S.part.is_empty(), "11 a new part for the sword")
	await click_ctl(pu.browser.find_child("part_plane_front", true, false))
	m._turn_to(0.0, 0.0, 1.5, Vector3(0.27, 0.0, 0.0), false)
	await idle(2)
	await click_ctl(pu.tool_btns["Line"])
	await shot("sword_dbg")
	var outline := [Vector2(-100, -10), Vector2(0, -10), Vector2(0, -30), Vector2(500, -30), Vector2(640, 0), Vector2(500, 30), Vector2(0, 30), Vector2(0, 10), Vector2(-100, 10), Vector2(-100, -10)]
	for p in outline:
		await click_ctl_at(sp2(p.x, p.y))
	ok(pu.sk != "" and (pu._sk()["ents"] as Array).size() == 9, "11 blade outline: 9 lines by clicks (%d)" % (pu._sk()["ents"] as Array).size())
	ok(pu.note_l.text.contains("closed profile"), "11 the sketch says: %s" % pu.note_l.text)
	await shot("sword_blade_sketch")
	await click_ctl(pu.finish_btn)
	await click_ctl(pu.tool_btns["Extrude"])
	pu.f_both.button_pressed = true
	pu.f_op.select(1)
	await type_in(pu.f_num, "8")
	var vb := float(pu.res["volume"])
	var area := (100.0 * 20.0 + 500.0 * 60.0 + 0.5 * 140.0 * 60.0) * 1e-6
	ok(absf(vb - area * 0.008) < 1e-9 and int(pu.res["bodies"]) == 1, "11 blade extruded 8 mm both sides: volume %s (want %s)" % [E(vb), E(area * 0.008)])
	m._turn_to(20.0, -25.0, 1.5, Vector3(0.27, 0.0, 0.0), false)
	await idle(2)
	await press_tool(pu, "Fillet")
	var edge_pt := Vector3(0.25, 0.03, 0.004)
	await click_ctl_at(m.cam.unproject_position(edge_pt))
	ok(pu.picked.size() == 1, "11 a blade edge picked")
	await shot("sword_fillet")
	await type_in(pu.f_num, "2")
	ok(pu.res["errors"].is_empty() and float(pu.res["volume"]) < vb, "11 blade edge filleted 2 mm: volume %s, no failed step" % E(float(pu.res["volume"])))
	var revs := [["guard", 0, 6, 0, 35], ["grip", -100, 0, 0, 10], ["pommel", -125, -100, 0, 14]]
	for rv in revs:
		m._turn_to(0.0, 0.0, 1.5, Vector3(0.27, 0.0, 0.0), false)
		await click_ctl(pu.browser.find_child("part_plane_front", true, false))
		await click_ctl(pu.tool_btns["Rectangle"])
		m._turn_to(0.0, 0.0, 1.5, Vector3(0.27, 0.0, 0.0), false)
		await idle(2)
		await drag2(rv[1], rv[3], rv[2], rv[4])
		await click_ctl(pu.finish_btn)
		await click_ctl(pu.tool_btns["Revolve"])
		await type_in(pu.f_ang, "360")
	ok(pu.res["errors"].is_empty() and m.S.part["features"].size() == 9, "11 sword: %d features, %d body, volume %s, failed %s" % [m.S.part["features"].size(), int(pu.res["bodies"]), E(float(pu.res["volume"])), pu.res["errors"]])
	m._turn_to(25.0, -25.0, 1.4, Vector3(0.25, 0.0, 0.0), false)
	await idle(2)
	await shot("sword_final")
	m._turn_to(0.0, 0.0, 1.5, Vector3(0.27, 0.0, 0.0), false)
	await idle(2)
	await shot("sword_front")
