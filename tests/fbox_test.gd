extends SceneTree
## FBOX (Nick 2026-10-28): a beginner makes a storage box with a lid from the BUILDING card (free Easy Part), real clicks at 1280x720.
## Walk: Draw shape + drag on the floor -> Pull it up (How far slider: a click at its fifth) -> Cut a hole, Hollow inside (open at the top)
##   -> Draw shape on the rim (a drag that hangs past the box by 1 cm) -> Pull it up (the lid) -> Cut a hole, Through (the finger hole).
## Bars (dead ends found on the old code are the FAILs; each is a bar, not a loosened one):
##   0 the BUILDING card, one click: page BUILD, Easy Part on
##   1 Pull it up on the floor drawing makes one body, at least 6 cm tall
##   2 Hollow inside keeps the outline, makes a shell open at the top (one body, no error)
##   3 a lid drawn on the rim and pulled up is a SEPARATE body (two bodies), not joined to the box
##   4 the lid is slightly larger than the box (its x and z span exceed the box's by at least 5 mm)
##   5 a finger hole cut through the lid: no error, the lid keeps its outline
## shots: C:/Temp/claude/fbox/NN_*.png
const SHOT := "C:/Temp/claude/fbox"
const DIRT := "user://fbox_test"

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


func click_at(p: Vector2) -> void:
	await ev_move(p, false)
	await ev_mouse(p, true)
	await ev_mouse(p, false)
	await idle(3)


func click_ctl(c: Control) -> void:
	await click_at(c.get_global_rect().get_center())


func drag_screen(a: Vector2, b: Vector2) -> void:
	await ev_move(a, false)
	await ev_mouse(a, true)
	for i in range(1, 13):
		await ev_move(a.lerp(b, i / 12.0))
	await ev_mouse(b, false)
	await idle(3)


func shot(nm: String) -> void:
	await idle(3)
	DirAccess.make_dir_recursive_absolute(SHOT)
	root.get_texture().get_image().save_png("%s/%s.png" % [SHOT, nm])


func pu():
	return m.bld.part


func scr(w: Vector3) -> Vector2:
	return m.cam.unproject_position(w)


func res() -> Dictionary:
	return pu().res


func box_aabb(bb: AABB) -> String:
	return "%.0f x %.0f x %.0f mm" % [bb.size.x / 0.001, bb.size.y / 0.001, bb.size.z / 0.001]


func find_slider() -> HSlider:
	for n in m.find_children("easypart_slider_*", "HSlider", true, false):
		if (n as Control).is_visible_in_tree() and (n as Control).size.x > 50.0:
			return n
	return null


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
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIRT))
	ss.dirs_override = [DIRT]
	if not Part.available():
		print("FAIL: no KineCAD DLL, the test cannot run")
		quit(1)
		return

	# 0 the BUILDING card, one click
	m.build_choose.auto = true
	ss.show_screen()
	await idle(3)
	await click_ctl(ss._easy_btn["building"])
	if m.ui_save_ask != null and m.ui_save_ask.visible:
		m._save_ask_choose("discard")
	await idle(30)
	ok(m.cur_page == "BUILD" and pu().on and pu().easy, "0 BUILDING card, one click -> Easy Part on (page %s)" % m.cur_page)

	m.target = Vector3.ZERO
	m.pitch = -30.0
	m.yaw = 30.0
	m._cam()
	await idle(60)

	# 1 the floor box: Draw shape + drag, Pull it up, then the How far slider at its fifth (8 cm)
	await click_ctl(pu().ep.make_btns["draw"])
	await drag_screen(scr(Vector3(-0.1, 0.0, -0.1)), scr(Vector3(0.1, 0.0, 0.1)))
	await click_ctl(pu().ep.make_btns["pull"])
	await idle(5)
	var sl := find_slider()
	if sl != null:
		var r := sl.get_global_rect()
		var yy := r.get_center().y
		await drag_screen(Vector2(r.position.x + r.size.x * 0.05, yy), Vector2(r.position.x + r.size.x * 0.2, yy))   # a real drag of the grabber to 8 cm
	await idle(10)
	var bb: AABB = res().get("aabb", AABB())
	ok(int(res().get("bodies", 0)) == 1 and bb.size.y >= 0.06, "1 Pull it up makes one body at least 6 cm tall (bodies %d, box %s)" % [int(res().get("bodies", 0)), box_aabb(bb)])
	await shot("01_pulled")
	var box_bb := bb

	# 2 Cut a hole -> Hollow inside (open at the top, 3 mm wall)
	await click_ctl(pu().ep.make_btns["hole"])
	await idle(5)
	await click_ctl(pu().ep.hole_btns["hollow"])
	await idle(10)
	var shell_ok := false
	for f in m.S.part.get("features", []):
		if String(f.get("t", "")) == "shell" and String(f.get("open", "")) == "+y":
			shell_ok = true
	var bb2: AABB = res().get("aabb", AABB())
	ok(shell_ok and int(res().get("bodies", 0)) == 1 and bb2.size.is_equal_approx(box_bb.size), "2 Hollow inside: an open-top shell, one body, same outline (shell %s, box %s)" % [shell_ok, box_aabb(bb2)])
	await shot("02_hollow")

	# 3 + 4 the lid: a drag on the rim (the top face) that hangs past the box by about 1 cm, then Pull it up
	var x0 := bb2.position.x
	var x1 := bb2.end.x
	var z0 := bb2.position.z
	var z1 := bb2.end.z
	var top := bb2.end.y
	var a := scr(Vector3(x0 + 0.001, top, z0 + 0.001))   # 1 mm inside the rim's outer edge: the top face (the wall's own face is 3 mm thick)
	var b := scr(Vector3(x1 + 0.01, top, z1 + 0.01))
	await click_ctl(pu().ep.make_btns["draw"])
	await drag_screen(a, b)
	await click_ctl(pu().ep.make_btns["pull"])
	await idle(10)
	var bodies := int(res().get("bodies", 0))
	ok(bodies == 2, "3 the lid is a separate body (bodies %d)" % bodies)
	var bb3: AABB = res().get("aabb", AABB())
	var span_x := bb3.size.x - bb2.size.x
	var span_z := bb3.size.z - bb2.size.z
	ok(span_x >= 0.005 or span_z >= 0.005, "4 the lid is slightly larger than the box (x +%.1f mm, z +%.1f mm)" % [span_x / 0.001, span_z / 0.001])
	await shot("03_lid")

	# 5 the finger hole: Cut a hole, Through, in the middle of the lid
	await click_ctl(pu().ep.make_btns["hole"])
	await idle(5)
	await click_ctl(pu().ep.hole_btns["through"])
	await idle(10)
	var bb4: AABB = res().get("aabb", AABB())
	ok(bb4.size.is_equal_approx(bb3.size), "5 a finger hole through the lid keeps the outline (box %s)" % box_aabb(bb4))
	await shot("04_hole")

	# 6 the finger NOTCH: a cut at the lid's edge (its centre within 15 mm of the lid's +Z edge). Easy's hole is a round hole in the middle: a DEAD END (fails)
	var hc := -1.0
	for f in m.S.part.get("features", []):
		if String(f.get("t", "")) == "sketch" and not (f.get("ents", []) as Array).is_empty():
			var e: Dictionary = f["ents"][0]
			if String(e.get("k", "")) == "circle":
				hc = float(e["c"][1])   # the top plane's v axis is -Z: v = -z (mm)
	var edge_mm := bb4.end.z / Part.MM
	ok(hc != -1.0 and absf(-hc - edge_mm) <= 15.0, "6 the finger notch sits at the lid's edge (hole centre z %.0f mm, lid edge %.0f mm)" % [-hc, edge_mm])

	print("fbox: %d fail" % fails)
	quit(1 if fails > 0 else 0)
