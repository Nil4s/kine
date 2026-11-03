extends SceneTree
## godot --headless --path . -s tests/c37_test.gd   (C37 SKETCH SHAPES: Rounded rectangle, Slot, typed Radius, Size first; needs the CAD DLL)
## Bars, written and committed BEFORE the first run (mm; volumes m3, tolerance 0.5 percent of the analytic answer):
##   1 RRECT   Rounded rect button, drag (0,0)-(60,40), Radius field 8: 8 entities (4 lines + 4 arcs), Extrude 10 = (60x40 - (4-pi) 8^2) x 10,
##             1 body, 0 open mesh edges, the whole sketch ONE undo step
##   2 SLOT    Slot button, drag (0,0)-(50,0), Radius 10: volume (50 x 20 + pi 10^2) x 10, one undo step
##   3 CIRCLE  Radius 12 typed, Circle tool, ONE click: a circle r 12 (volume pi 12^2 x 10); CONTROL (default unchanged): Radius blank, the same click
##             adds nothing (the old press starts a draft), and a drag (0,0)-(20,0) makes a circle r 20
##   4 TYPED   Rounded rect, first click, type 40x30 Enter, Radius blank: auto corner R = a fifth of 30 = 6: volume (1200 - (4-pi) 36) x 10
##   5 FIRST   Size first 80 x 50 x 20: Box = 80 x 50 x 20; Rounded box (Radius 10) = (4000 - (4-pi)100) x 20; Slot = (30 x 50 + pi 25^2) x 20;
##             each ONE undo step; Make with nothing typed makes nothing
##   6 CONTROL the plain-rectangle volume (60x40x10) is NOT within 0.5 percent of bar 1 (the bar can fail)
##   7 SHOTS   1280x720 screenshots in C:/Temp/claude/c37/ (looked at by eye)
##   8 WATCHDOG the test quits itself at 240 s
const SHOT := "C:/Temp/claude/c37"
const DIRT := "user://c37_test"
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


## a Part tool as a user reaches it: its own ribbon button when shown, else its group caption or More
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
	var sa := InputEventKey.new()   # select all, then type over it
	sa.keycode = KEY_A
	sa.physical_keycode = KEY_A
	sa.ctrl_pressed = true
	sa.pressed = true
	root.push_input(sa, true)
	await process_frame
	for ch in txt:
		var e := InputEventKey.new()
		e.keycode = KEY_0 + int(ch)
		e.physical_keycode = KEY_0 + int(ch)
		e.unicode = ch.unicode_at(0)
		e.pressed = true
		root.push_input(e, true)
		await process_frame
	var k := InputEventKey.new()
	k.keycode = KEY_ENTER
	k.physical_keycode = KEY_ENTER
	k.pressed = true
	root.push_input(k, true)
	await idle(2)


## the screen point of a sketch point (mm) on the Front plane
func sp2(x: float, y: float) -> Vector2:
	return m.cam.unproject_position(Part.to_world(Part.plane("front"), Vector2(x, y)))


func ps() -> String:
	return JSON.stringify(m.S.part) if not m.S.part.is_empty() else "{}"


func _key(p: Vector3) -> String:
	return "%d,%d,%d" % [roundi(p.x * 1e6), roundi(p.y * 1e6), roundi(p.z * 1e6)]


## mesh edges used other than twice (0 = closed), welded at 1e-6 m
func open_edges(mesh: Mesh) -> int:
	if mesh == null:
		return -1
	var uses := {}
	for s in mesh.get_surface_count():
		var arr: Array = mesh.surface_get_arrays(s)
		var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX] if arr[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
		var n := idx.size() if idx.size() > 0 else v.size()
		for t in range(0, n - 2, 3):
			var tri := [idx[t], idx[t + 1], idx[t + 2]] if idx.size() > 0 else [t, t + 1, t + 2]
			for j in 3:
				var a := _key(v[tri[j]])
				var b := _key(v[tri[(j + 1) % 3]])
				var k: String = a + "|" + b if a < b else b + "|" + a
				uses[k] = int(uses.get(k, 0)) + 1
	var bad := 0
	for k in uses:
		if uses[k] != 2:
			bad += 1
	return bad



func sp(x: float, y: float) -> Vector2:
	return m.cam.unproject_position(Part.to_world(Part.plane("front"), Vector2(x, y)))


func vol_of(ents: Array, h: float) -> Dictionary:
	var rec := Part.make("t")
	var s := Part.new_feature(rec, "sketch", {"plane": "front", "ents": ents.duplicate(true), "dims": []})
	rec["features"].append(s)
	rec["features"].append(Part.new_feature(rec, "extrude", {"sketch": s["id"], "dist": h, "both": false, "op": "new"}))
	return Part.replay(rec)


func near(v: float, want_mm3: float) -> bool:
	return absf(v - want_mm3 * 1e-9) < 0.005 * want_mm3 * 1e-9


func set_radius(pu: PartUI, t: String) -> void:
	pu.shp.radius_edit.text = t


func begin(pu: PartUI) -> void:
	await click_ctl(pu.browser.find_child("part_plane_front", true, false))


func drag(a: Vector2, b: Vector2) -> void:
	await ev_move(a, false)
	await ev_mouse(a, true)
	await ev_move((a + b) * 0.5)
	await ev_move(b)
	await ev_mouse(b, false)
	await idle(2)


func key(code: int, uni := 0) -> void:
	var e := InputEventKey.new()
	e.keycode = code
	e.physical_keycode = code
	e.unicode = uni
	e.pressed = true
	root.push_input(e, true)
	await process_frame


func typed(s: String) -> void:
	for ch in s:
		await key(KEY_X if ch == "x" else KEY_0 + int(ch), ch.unicode_at(0))


func shot(nm: String) -> void:
	await idle(3)
	DirAccess.make_dir_recursive_absolute(SHOT)
	var img: Image = root.get_texture().get_image() if root.get_texture() != null else null
	if img != null:
		img.save_png("%s/%s.png" % [SHOT, nm])


func _init() -> void:
	var wd := create_timer(240.0)
	wd.timeout.connect(func():
		print("FAIL watchdog: 240 s")
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
	var ss: StartScreen = m.start_screen
	var bld: BuildUI = m.bld
	var pu: PartUI = bld.part
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIRT))
	ss.dirs_override = [DIRT]
	if not Part.available():
		print("SKIP: no KineCAD DLL")
		quit(0)
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
	ok(pu.on and pu.shp != null, "0 Part workspace on, shapes helper built")

	# 1 RRECT
	var n0: int = m.undo.size()
	await begin(pu)
	ok(pu.shp.btns["Rounded rectangle"].is_visible_in_tree(), "1 the Rounded rect button shows in the sketch palette")
	set_radius(pu, "8")
	await click_ctl(pu.shp.btns["Rounded rectangle"])
	ok(pu.tool == "Rounded rectangle", "1 the button picks the tool (%s)" % pu.tool)
	await drag(sp(0, 0), sp(60, 40))
	await shot("rrect_sketch")
	var ents: Array = pu._sk()["ents"]
	ok(ents.size() == 8, "1 8 entities (4 lines + 4 arcs), got %d" % ents.size())
	await click_ctl(pu.finish_btn)
	ok(m.undo.size() == n0 + 1, "1 ONE undo step (%d)" % (m.undo.size() - n0))
	await press_tool(pu, "Extrude")
	await type_in(pu.f_num, "10")
	var r: Dictionary = Part.replay(m.S.part)
	var want1 := (60.0 * 40.0 - (4.0 - PI) * 64.0) * 10.0
	ok((r["errors"] as Dictionary).is_empty() and int(r["bodies"]) == 1 and near(float(r["volume"]), want1), "1 rounded rect extrudes: errors %s bodies %d volume %s want %s" % [r["errors"], int(r["bodies"]), r["volume"], want1 * 1e-9])
	var eo := open_edges(pu.part_mesh.mesh)
	ok(eo == 0, "1 solid closed: %d open edges" % eo)
	await shot("rrect_solid")
	ok(not near(float(r["volume"]), 60.0 * 40.0 * 10.0), "6 control: plain 60x40x10 box volume fails bar 1")

	# 2 SLOT
	set_radius(pu, "10")
	n0 = m.undo.size()
	await begin(pu)
	await click_ctl(pu.shp.btns["Slot"])
	await drag(sp(0, 0), sp(50, 0))
	ents = pu._sk()["ents"]
	ok(ents.size() == 4, "2 slot = 4 entities, got %d" % ents.size())
	await shot("slot_sketch")
	var e2 := ents.duplicate(true)
	await click_ctl(pu.finish_btn)
	ok(m.undo.size() == n0 + 1, "2 ONE undo step (%d)" % (m.undo.size() - n0))
	var r2 := vol_of(e2, 10.0)
	ok((r2["errors"] as Dictionary).is_empty() and int(r2["bodies"]) == 1 and near(float(r2["volume"]), (50.0 * 20.0 + PI * 100.0) * 10.0), "2 slot volume %s want %s" % [r2["volume"], (50.0 * 20.0 + PI * 100.0) * 10.0e-9])

	# 3 CIRCLE typed radius
	set_radius(pu, "12")
	await begin(pu)
	await press_tool(pu, "Circle")
	await click_at(sp(0, 0))
	ents = pu._sk()["ents"]
	ok(ents.size() == 1 and String(ents[0]["k"]) == "circle" and absf(float(ents[0]["r"]) - 12.0) < 1e-6, "3 one click with Radius 12: a circle r 12 (%s)" % [ents])
	var r3 := vol_of(ents, 10.0)
	ok(near(float(r3["volume"]), PI * 144.0 * 10.0), "3 circle volume %s" % r3["volume"])
	await shot("circle_typed")
	set_radius(pu, "")
	await click_at(sp(30, 30))
	ents = pu._sk()["ents"]
	ok(ents.size() == 1, "3 control: Radius blank, a click adds no circle (the old click-without-drag cancels)")
	pu.draft = {}
	await drag(sp(0, 0), sp(20, 0))
	ents = pu._sk()["ents"]
	ok(ents.size() == 2 and absf(float(ents[1]["r"]) - 20.0) < 0.01, "3 control: blank field, a drag makes the old circle r 20 (%s)" % [ents.back()])
	await click_ctl(pu.finish_btn)

	# 4 TYPED corner
	set_radius(pu, "")
	await begin(pu)
	await click_ctl(pu.shp.btns["Rounded rectangle"])
	await click_at(sp(0, 0))
	await ev_move(sp(40, 30), false)
	await typed("40x30")
	await key(KEY_ENTER)
	ents = pu._sk()["ents"]
	var r4 := vol_of(ents, 10.0)
	ok(ents.size() == 8 and near(float(r4["volume"]), (1200.0 - (4.0 - PI) * 36.0) * 10.0), "4 typed 40x30, auto R 6: %d ents volume %s" % [ents.size(), r4["volume"]])
	await click_ctl(pu.finish_btn)

	# 5 SIZE FIRST
	await click_ctl(pu.finish_btn)
	await begin(pu)
	await click_ctl(pu.shp.first_btn)
	ok(pu.shp.first_panel.visible, "5 Size first opens its panel")
	var nf0: int = (m.S.part.get("features", []) as Array).size()
	await click_ctl(pu.shp.first_panel.find_child("part_first_make", true, false))
	ok((m.S.part.get("features", []) as Array).size() == nf0, "5 Make with nothing typed adds nothing")
	await shot("size_first_panel")
	await click_ctl(pu.finish_btn)
	var cases := [["Box", "", 80.0 * 50.0 * 20.0], ["Rounded box", "10", (4000.0 - (4.0 - PI) * 100.0) * 20.0], ["Slot", "", (30.0 * 50.0 + PI * 625.0) * 20.0]]
	for cs in cases:
		set_radius(pu, String(cs[1]))
		if not pu.shp.first_panel.visible:
			pu.shp.open_first()
		for pair in [["W", "80"], ["D", "50"], ["H", "20"]]:
			(pu.shp.first_edits[pair[0]] as LineEdit).text = pair[1]
		await click_ctl(pu.shp.first_shape_btns[cs[0]])
		var before: int = m.undo.size()
		await click_ctl(pu.shp.first_panel.find_child("part_first_make", true, false))
		ok(m.undo.size() == before + 1, "5 %s: ONE undo step (%d)" % [cs[0], m.undo.size() - before])
		var feats: Array = m.S.part["features"]
		var rec := Part.make("x")
		rec["features"] = [feats[feats.size() - 2].duplicate(true), feats[feats.size() - 1].duplicate(true)]
		var rr: Dictionary = Part.replay(rec)
		ok((rr["errors"] as Dictionary).is_empty() and near(float(rr["volume"]), float(cs[2])), "5 %s: volume %s want %s errors %s" % [cs[0], rr["volume"], float(cs[2]) * 1e-9, rr["errors"]])
		if cs[0] == "Rounded box":
			await shot("size_first_solid")
	await shot("final")
	print("c37: %d fail%s" % [fails, "" if fails == 1 else "s"])
	quit(1 if fails > 0 else 0)
